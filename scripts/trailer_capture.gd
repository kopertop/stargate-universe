extends Node

# @no-save: dev-only trailer capture/replay. Records NOTHING and changes nothing
# during normal play — it only activates when launched with a flag. Mirrors the
# TestCapture autoload's "inert unless flagged" pattern.
#
# TWO modes:
#
# • RECORD  (env SGU_TRAILER_RECORD=<path>, or --trailer-record=<path>)
#     Captured by tools/trailer/record.sh. Logs EVERY keyboard/mouse InputEvent
#     keyed by PHYSICS FRAME (Godot's physics is a fixed 60 Hz tick regardless of
#     render fps), plus per-scene GameState/Inventory/NPCState snapshots and the
#     camera/character transform per render frame. Writes a capture JSON on quit.
#
# • REPLAY  (env SGU_TRAILER_REPLAY=<path>)
#     Launches the REAL game (title.tscn) and RE-INJECTS the recorded inputs on
#     the matching physics frame under --fixed-fps, so the game plays ITSELF:
#     movement, the "E" interactions (talk to Rush, consoles, doors, Kino), the
#     Kino remote, dialogs — everything the player did, mirrored. Same fixed tick
#     rate + same per-frame inputs ⇒ a deterministic reproduction. Renders a title
#     and end card around it. Used by tools/make_trailer.sh.

# --- shared ----------------------------------------------------------------
var _mode: String = ""          # "" | "record" | "replay"
var _path: String = ""
var _t: float = 0.0
var _start_pf: int = -1         # physics frame index at start (0-based mapping)
# Scene-sequence re-sync: every scene spawns the player at a fixed marker, so it's
# a deterministic anchor. We index inputs by (scene sequence #, frames-since-that-
# scene-loaded) and re-sync at each scene change — absorbing the variable per-load
# frame cost that would otherwise desync absolute-frame input replay.
var _seq: int = -1
var _seq_pf: int = 0
var _seq_scene: Node = null

# --- record state ----------------------------------------------------------
var _frames: Array[Dictionary] = []
var _events: Array[Dictionary] = []          # scene-change snapshots
var _inputs: Array[Dictionary] = []          # [{ "f": physics_frame, "e": [encoded,…] }]
var _pending: Array = []                     # encoded events since last physics frame
var _last_scene: String = ""
var _written: bool = false

# --- replay state -----------------------------------------------------------
var _replay_inputs: Array = []
var _replay_idx: int = 0
var _fps: float = 60.0
var _done: bool = false
var _ended_logged: bool = false
var _end_frame: int = 0
# title/end card overlay
var _overlay: CanvasLayer = null
var _card: ColorRect = null
var _card_title: Label = null
var _card_sub: Label = null
const END_FRAMES: int = 180                  # hold the end card ~3s after inputs end


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rec_path: String = _record_path()
	var rep_path: String = OS.get_environment("SGU_TRAILER_REPLAY")
	if rec_path != "":
		_mode = "record"
		_path = rec_path
		get_tree().auto_accept_quit = true
		print("[trailer_capture] RECORDING this run → ", _path)
	elif rep_path != "":
		_mode = "replay"
		_path = rep_path
		_begin_replay()
	else:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)


func _record_path() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trailer-record="):
			return a.substr("--trailer-record=".length())
	return OS.get_environment("SGU_TRAILER_RECORD")


# ===========================================================================
# INPUT — buffered in _input, committed per physics frame (deterministic key).
# ===========================================================================

func _input(event: InputEvent) -> void:
	if _mode != "record":
		return
	var enc: Variant = _encode_event(event)
	if enc != null:
		_pending.append(enc)


func _encode_event(event: InputEvent) -> Variant:
	if event is InputEventKey:
		var k: InputEventKey = event
		# Ignore pure echoes (held-key repeats) — is_action_pressed stays true anyway.
		if k.echo:
			return null
		return ["k", int(k.physical_keycode), int(k.keycode), 1 if k.pressed else 0]
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		return ["b", int(mb.button_index), 1 if mb.pressed else 0, mb.position.x, mb.position.y]
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		return ["m", mm.screen_relative.x, mm.screen_relative.y, mm.relative.x, mm.relative.y, mm.position.x, mm.position.y]
	return null


func _decode_event(enc: Array) -> InputEvent:
	match String(enc[0]):
		"k":
			var k: InputEventKey = InputEventKey.new()
			k.physical_keycode = int(enc[1])
			k.keycode = int(enc[2])
			k.pressed = int(enc[3]) == 1
			return k
		"b":
			var mb: InputEventMouseButton = InputEventMouseButton.new()
			mb.button_index = int(enc[1])
			mb.pressed = int(enc[2]) == 1
			mb.position = Vector2(enc[3], enc[4])
			return mb
		"m":
			var mm: InputEventMouseMotion = InputEventMouseMotion.new()
			mm.screen_relative = Vector2(enc[1], enc[2])
			mm.relative = Vector2(enc[3], enc[4])
			mm.position = Vector2(enc[5], enc[6])
			return mm
	return null


func _physics_process(_delta: float) -> void:
	if _mode == "":
		return
	var pf: int = Engine.get_physics_frames()
	if _start_pf < 0:
		_start_pf = pf
	var frame: int = pf - _start_pf
	# Re-anchor the per-scene clock whenever the active scene instance changes.
	var cs: Node = get_tree().current_scene
	if cs != _seq_scene:
		_seq += 1
		_seq_pf = frame
		_seq_scene = cs
	if _mode == "record":
		if not _pending.is_empty():
			_inputs.append({"s": _seq, "sf": frame - _seq_pf, "e": _pending})
			_pending = []
	elif _mode == "replay":
		_replay_tick(frame)


# ===========================================================================
# RECORD — per-render-frame transform/scene capture (for the transform-replay
# fallback) lives here; inputs are committed in _physics_process above.
# ===========================================================================

func _process(delta: float) -> void:
	if _mode != "record":
		return
	_t += delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var scene: Node = get_tree().current_scene
	var scene_path: String = scene.scene_file_path if scene != null else ""
	var room_id: String = String(GameState.current_room_id)
	var key: String = scene_path + "#" + room_id
	if key != _last_scene:
		var ev: Dictionary = {"t": _t, "type": "scene", "scene": scene_path, "room": room_id}
		if GameState.has_method("serialize"):
			ev["state"] = GameState.serialize()
		var inv: Node = get_node_or_null("/root/Inventory")
		if inv != null and inv.has_method("serialize"):
			ev["inv"] = inv.call("serialize")
		var npc: Node = get_node_or_null("/root/NPCState")
		if npc != null and npc.has_method("serialize"):
			ev["npc"] = npc.call("serialize")
		_events.append(ev)
		_last_scene = key

	var rec: Dictionary = {"t": _t, "scene": scene_path, "cam": _xf(cam.global_transform), "fov": cam.fov}
	var subj: Node = get_tree().get_first_node_in_group("player")
	if subj is Node3D:
		rec["subj"] = _xf((subj as Node3D).global_transform)
		var anim: String = _subject_anim(subj)
		if anim != "":
			rec["anim"] = anim
	_frames.append(rec)


func _subject_anim(subj: Node) -> String:
	var ap: Variant = subj.get("_animation")
	if ap is AnimationPlayer:
		return (ap as AnimationPlayer).current_animation
	return ""


func _xf(t: Transform3D) -> Dictionary:
	var e: Vector3 = t.basis.get_euler()
	return {"px": t.origin.x, "py": t.origin.y, "pz": t.origin.z, "rx": e.x, "ry": e.y, "rz": e.z}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush()


func _flush() -> void:
	if _mode != "record" or _written:
		return
	_written = true
	if not _pending.is_empty():
		_inputs.append({"s": _seq, "sf": 0, "e": _pending})
	var doc: Dictionary = {
		"version": 2,
		"duration": _t,
		"phys_frames": (Engine.get_physics_frames() - _start_pf) if _start_pf >= 0 else 0,
		"frame_count": _frames.size(),
		"events": _events,
		"frames": _frames,
		"inputs": _inputs,
	}
	var f: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("[trailer_capture] could not open %s for write" % _path)
		return
	f.store_string(JSON.stringify(doc))
	f.close()
	print("[trailer_capture] wrote %d frames, %d input batches (%.1fs) → %s" % [
		_frames.size(), _inputs.size(), _t, _path])


# ===========================================================================
# REPLAY — inject recorded inputs on the matching physics frame.
# ===========================================================================

func _begin_replay() -> void:
	var fps_env: String = OS.get_environment("TRAILER_FPS")
	if fps_env != "" and fps_env.is_valid_float():
		_fps = maxf(fps_env.to_float(), 1.0)
	var f: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if f == null:
		push_error("[trailer_capture] replay: cannot open " + _path)
		get_tree().quit(2)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("[trailer_capture] replay: bad capture JSON")
		get_tree().quit(2)
		return
	var doc: Dictionary = parsed
	var inp: Variant = doc.get("inputs", [])
	_replay_inputs = inp if inp is Array else []
	print("[trailer_capture] REPLAY (input) — %d input batches @ %.0ffps" % [_replay_inputs.size(), _fps])
	_build_overlay()
	_show_title()


func _replay_tick(frame: int) -> void:
	if _done:
		return
	# Lift the title card once the menu has been navigated and gameplay starts
	# (the first scene off the title screen → _seq >= 1).
	if _card != null and _card.visible and not _ended_logged and _seq >= 1:
		_card.visible = false
	# Inject input batches, anchored per scene. A batch for an EARLIER scene than
	# the one we're in (shouldn't happen, but be safe) fires immediately; a batch
	# for the CURRENT scene fires once its frames-since-scene-load is reached; a
	# batch for a FUTURE scene waits until we've loaded into it.
	while _replay_idx < _replay_inputs.size():
		var b: Dictionary = _replay_inputs[_replay_idx]
		var bs: int = int(b.get("s", 0))
		if bs > _seq:
			break
		if bs == _seq and int(b.get("sf", 0)) > frame - _seq_pf:
			break
		for enc in b.get("e", []):
			var ev: InputEvent = _decode_event(enc)
			if ev != null:
				Input.parse_input_event(ev)
		_replay_idx += 1
	# All inputs replayed → end card, hold, quit.
	if _replay_idx >= _replay_inputs.size():
		if not _ended_logged:
			_ended_logged = true
			_end_frame = frame
			_show_end_card()
		elif frame >= _end_frame + END_FRAMES:
			_done = true
			print("=== trailer input-replay complete — quitting ===")
			get_tree().quit(0)


# --- overlay ----------------------------------------------------------------

func _cta_text() -> String:
	var c: String = OS.get_environment("TRAILER_CTA")
	return c if c != "" else "Wishlist now"


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "TrailerOverlay"
	_overlay.layer = 90
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_overlay)
	_card = ColorRect.new()
	_card.color = Color(0.02, 0.027, 0.051, 1.0)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_overlay.add_child(_card)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	_card.add_child(vb)
	_card_title = _make_label(64, Color(0.95, 0.97, 1.0))
	vb.add_child(_card_title)
	_card_sub = _make_label(28, Color(0.62, 0.88, 0.63))
	vb.add_child(_card_sub)


func _make_label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _show_title() -> void:
	var nm: String = OS.get_environment("TRAILER_GAME_NAME")
	_card_title.text = nm if nm != "" else "STARGATE UNIVERSE"
	_card_sub.text = OS.get_environment("TRAILER_TITLE_SUB")
	_card.visible = true


func _show_end_card() -> void:
	var nm: String = OS.get_environment("TRAILER_GAME_NAME")
	_card_title.text = nm if nm != "" else "STARGATE UNIVERSE"
	_card_sub.text = _cta_text()
	_card.visible = true
