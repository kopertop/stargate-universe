extends Node

# Renders a trailer by REPLAYING a captured human playthrough (written by
# scripts/trailer_capture.gd via tools/trailer/record.sh). Deterministic transform
# playback: each output frame we set the character + camera to the recorded pose,
# reproduce the recorded animation clip, and re-load scenes at their captured
# times. Nothing runs the physics walk-solver, so the character can't snag on
# steps or bounce off doors — it follows exactly the path the human walked
# (including piloting the Kino, which replays as the recorded camera path).
#
# Bootstrapped from tools/trailer/replay.tscn. Lives under /root so it survives
# scene changes. Env knobs match the scripted runner (TRAILER_FPS, TRAILER_BEATS,
# TRAILER_CAPTIONS, TRAILER_GAME_NAME, TRAILER_TAGLINE, TRAILER_TITLE_SUB,
# TRAILER_CTA) plus:
#   TRAILER_CAPTURE   path to the capture JSON (required)
#   TRAILER_CAPTIONS_FILE  optional JSON [{ "t": s, "text": "..." }] to burn captions

const TITLE_SEC: float = 2.0
const END_SEC: float = 3.0

var _fps: float = 60.0
var _capture_path: String = ""
var _frames: Array = []
var _events: Array = []     # [{t, type:"scene", scene, room, state}] sorted
var _captions: Array = []   # [{t, text}] sorted
var _caption_idx: int = 0

var _game_name: String = "STARGATE UNIVERSE"
var _title_sub: String = ""
var _cta: String = "Wishlist now"
var _captions_on: bool = true

var _video_time: float = 0.0
var _frame_no: int = 0
var _started: bool = false
var _done: bool = false
# Optional clip window into the capture (seconds). Renders only [start, end] so a
# long playthrough can be cut to a social-length highlight without re-capturing.
var _clip_start: float = 0.0
var _clip_end: float = -1.0   # <0 = to end

var _cur_scene: String = ""
var _cam: Camera3D = null
var _subj: Node3D = null

# overlay
var _overlay: CanvasLayer = null
var _card: ColorRect = null
var _card_title: Label = null
var _card_sub: Label = null
var _caption: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_begin")


func _process(_delta: float) -> void:
	if _started and not _done:
		_frame_no += 1
		_video_time = float(_frame_no) / _fps


func _begin() -> void:
	if _started:
		return
	_started = true
	_read_env()
	if not _load_capture():
		push_error("trailer replay: no usable capture at '%s'" % _capture_path)
		get_tree().quit(2)
		return
	print("=== trailer REPLAY — %d frames, %.1fs capture @ %.0ffps ===" % [_frames.size(), _frames[-1].get("t", 0.0), _fps])
	_build_overlay()
	# Resolve in-engine cinematics instantly (no lingering letterbox bars; HUD
	# stays up) and isolate saves — same safety as the scripted runner.
	SceneRouter.instant_mode = true
	SaveManager.configure_test_paths("trailer_replay")
	# The project ships physics interpolation ON, which only commits visual poses
	# on PHYSICS frames. Replay drives transforms + the AnimationPlayer from IDLE
	# frames with physics_process disabled, so interpolated nodes (notably the
	# character Skeleton3D) freeze on their last physics snapshot — the body slides
	# but never animates. Disable interpolation for this render-only session so the
	# idle-driven poses render directly.
	get_tree().physics_interpolation = false
	_hide_cinematic_bars()

	await _title_card(TITLE_SEC)
	await _replay()
	await _end_card(END_SEC)
	_done = true
	print("=== replay complete — quitting ===")
	get_tree().quit(0)


func _read_env() -> void:
	var fps_env: String = OS.get_environment("TRAILER_FPS")
	if fps_env != "" and fps_env.is_valid_float():
		_fps = maxf(fps_env.to_float(), 1.0)
	_capture_path = OS.get_environment("TRAILER_CAPTURE")
	_captions_on = OS.get_environment("TRAILER_CAPTIONS") != "0"
	var nm: String = OS.get_environment("TRAILER_GAME_NAME")
	if nm != "":
		_game_name = nm
	_title_sub = OS.get_environment("TRAILER_TITLE_SUB")
	if _title_sub == "":
		_title_sub = OS.get_environment("TRAILER_TAGLINE")
	var cta: String = OS.get_environment("TRAILER_CTA")
	if cta != "":
		_cta = cta
	var cs: String = OS.get_environment("TRAILER_CLIP_START")
	if cs != "" and cs.is_valid_float():
		_clip_start = maxf(cs.to_float(), 0.0)
	var ce: String = OS.get_environment("TRAILER_CLIP_END")
	if ce != "" and ce.is_valid_float():
		_clip_end = ce.to_float()


func _load_capture() -> bool:
	if _capture_path == "":
		return false
	var f: FileAccess = FileAccess.open(_capture_path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var doc: Dictionary = parsed
	var fr: Variant = doc.get("frames", [])
	if not (fr is Array) or (fr as Array).is_empty():
		return false
	_frames = fr
	var ev: Variant = doc.get("events", [])
	if ev is Array:
		_events = ev
	_load_captions()
	return true


func _load_captions() -> void:
	var cp: String = OS.get_environment("TRAILER_CAPTIONS_FILE")
	if cp == "":
		return
	var f: FileAccess = FileAccess.open(cp, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_captions = parsed


# --- replay --------------------------------------------------------------

func _replay() -> void:
	var n: int = _frames.size()
	var cap_end: float = float(_frames[n - 1].get("t", 0.0))
	# Clip window: default to the whole capture; the video clock maps to capture
	# time as t = start + _video_time.
	var start: float = clampf(_clip_start, 0.0, cap_end)
	if start <= 0.0:
		start = float(_frames[0].get("t", 0.0))
	var end_t: float = cap_end if _clip_end < 0.0 else clampf(_clip_end, start, cap_end)

	# Seed the scene/state that was active AT the clip start (the last scene event
	# at or before it), so a mid-playthrough clip opens in the right level.
	var ev_idx: int = 0
	var seed_ev: int = -1
	for i in _events.size():
		if float((_events[i] as Dictionary).get("t", 0.0)) <= start:
			seed_ev = i
		else:
			break
	if seed_ev >= 0:
		await _apply_scene_event(_events[seed_ev])
		ev_idx = seed_ev + 1
	elif not _events.is_empty():
		await _apply_scene_event(_events[0])
		ev_idx = 1
	else:
		await _load_scene(String(_frames[0].get("scene", "")), "", {})

	var idx: int = 0
	while idx < n - 1 and float(_frames[idx + 1].get("t", 0.0)) <= start:
		idx += 1

	while true:
		var t: float = start + _video_time   # align capture clock to video clock
		if t >= end_t:
			break
		# Fire any scene-change events whose time we've reached.
		while ev_idx < _events.size() and float((_events[ev_idx] as Dictionary).get("t", 0.0)) <= t:
			await _apply_scene_event(_events[ev_idx])
			ev_idx += 1
		while idx < n - 1 and float(_frames[idx + 1].get("t", 0.0)) <= t:
			idx += 1
		var a: Dictionary = _frames[idx]
		var b: Dictionary = _frames[min(idx + 1, n - 1)]
		var same_scene: bool = String(b.get("scene", "")) == String(a.get("scene", ""))
		var seg: float = float(b.get("t", 0.0)) - float(a.get("t", 0.0))
		var u: float = clampf((t - float(a.get("t", 0.0))) / seg, 0.0, 1.0) if (same_scene and seg > 0.0001) else 0.0
		_apply_pose(a, (b if same_scene else a), u)
		_update_caption(t)
		await get_tree().process_frame


# Restore the captured GameState + room id, then load the scene so it builds
# exactly as it did during the live playthrough.
func _apply_scene_event(ev: Dictionary) -> void:
	var scene_path: String = String(ev.get("scene", ""))
	var room: String = String(ev.get("room", ""))
	var state: Variant = ev.get("state", null)
	if state is Dictionary and GameState.has_method("deserialize"):
		GameState.deserialize(state, int((state as Dictionary).get("version", 1)))
	# Items + NPC state drive how scenes build (Kino pickup/dispenser, kino-gated
	# doors, NPC placement) — restore them too or the back half renders wrong
	# (e.g. the Kino never "picked up" because Inventory wasn't restored).
	var inv_data: Variant = ev.get("inv", null)
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv_data is Dictionary and inv != null and inv.has_method("deserialize"):
		inv.call("deserialize", inv_data, 2)
	var npc_data: Variant = ev.get("npc", null)
	var npc: Node = get_node_or_null("/root/NPCState")
	if npc_data is Dictionary and npc != null and npc.has_method("deserialize"):
		npc.call("deserialize", npc_data, 2)
	# room.tscn is procedural — it reads next_room_id to pick which room to build.
	if room != "":
		GameState.next_room_id = room
	await _load_scene(scene_path, room, state if state is Dictionary else {})


func _load_scene(scene_path: String, _room: String = "", _state: Dictionary = {}) -> void:
	if scene_path == "":
		return
	# Track the OLD instance: corridors reload the SAME room.tscn file, so we must
	# wait for a NEW scene node, not just one whose path matches (the old one
	# matches too until it's freed).
	var prev: Node = get_tree().current_scene
	get_tree().change_scene_to_file(scene_path)
	var tries: int = 0
	while tries < 600:
		await get_tree().process_frame
		var cs: Node = get_tree().current_scene
		if cs != null and cs != prev and cs.scene_file_path == scene_path:
			break
		tries += 1
	_cur_scene = scene_path
	_subj = null
	_install_camera()
	_hide_cinematic_bars()


# Our own camera owns the view during replay so the scene's follow-cam can't
# fight the recorded framing.
func _install_camera() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_cam = Camera3D.new()
	_cam.name = "ReplayCamera"
	scene.add_child(_cam)
	_cam.current = true


func _apply_pose(a: Dictionary, b: Dictionary, u: float) -> void:
	# Camera (always present).
	if a.has("cam"):
		if _cam != null and is_instance_valid(_cam):
			_cam.global_transform = _lerp_xf(a["cam"], b.get("cam", a["cam"]), u)
			_cam.fov = lerpf(float(a.get("fov", 60.0)), float(b.get("fov", a.get("fov", 60.0))), u)
			if not _cam.current:
				_cam.current = true
	# Subject character (absent during Kino flight — camera-only then).
	if a.has("subj"):
		var s: Node3D = _subject()
		if s != null:
			s.global_transform = _lerp_xf(a["subj"], b.get("subj", a["subj"]), u)
			_play_subject_anim(s, String(a.get("anim", "")))


func _subject() -> Node3D:
	if _subj != null and is_instance_valid(_subj):
		return _subj
	var n: Node = get_tree().get_first_node_in_group("player")
	if n is Node3D:
		_subj = n as Node3D
		# Freeze its own logic so only our transform/anim drives it.
		if _subj.has_method("set_input_locked"):
			_subj.call("set_input_locked", true)
		_subj.set_physics_process(false)
		_subj.set_process(false)
		# CRITICAL: the project runs with physics interpolation on, which samples
		# the RENDER pose between PHYSICS frames. With physics_process disabled
		# there are no new physics frames, so the skeleton would freeze on its last
		# physics snapshot — the body slides but the walk/sprint animation never
		# shows. Turn interpolation OFF for the replayed character (inherited by its
		# skeleton/mesh) so the AnimationPlayer-driven pose we set each idle frame
		# renders directly.
		_subj.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return _subj


func _play_subject_anim(subj: Node3D, anim: String) -> void:
	if anim == "":
		return
	var ap: Variant = subj.get("_animation")
	if ap is AnimationPlayer:
		var player: AnimationPlayer = ap
		if player.current_animation != anim and player.has_animation(anim):
			player.play(anim)


func _lerp_xf(a: Dictionary, b: Dictionary, u: float) -> Transform3D:
	var pa: Vector3 = Vector3(a.get("px", 0.0), a.get("py", 0.0), a.get("pz", 0.0))
	var pb: Vector3 = Vector3(b.get("px", 0.0), b.get("py", 0.0), b.get("pz", 0.0))
	var ea: Vector3 = Vector3(a.get("rx", 0.0), a.get("ry", 0.0), a.get("rz", 0.0))
	var eb: Vector3 = Vector3(b.get("rx", 0.0), b.get("ry", 0.0), b.get("rz", 0.0))
	var pos: Vector3 = pa.lerp(pb, u)
	var rot: Vector3 = Vector3(
		lerp_angle(ea.x, eb.x, u),
		lerp_angle(ea.y, eb.y, u),
		lerp_angle(ea.z, eb.z, u))
	return Transform3D(Basis.from_euler(rot), pos)


# --- captions + cards ----------------------------------------------------

func _update_caption(t: float) -> void:
	if not _captions_on or _captions.is_empty() or _caption == null:
		return
	while _caption_idx < _captions.size() and float((_captions[_caption_idx] as Dictionary).get("t", 0.0)) <= t:
		_caption.text = String((_captions[_caption_idx] as Dictionary).get("text", ""))
		_caption.visible = _caption.text != ""
		_caption_idx += 1


func _hide_cinematic_bars() -> void:
	# Drop the letterbox bars (and flash) — keep the gameplay HUD up.
	var layer: Variant = Cinematic.get("_layer")
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = false


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "TrailerOverlay"
	_overlay.layer = 80
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

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

	_caption = _make_label(38, Color(0.95, 0.97, 1.0))
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 80.0
	_caption.offset_right = -80.0
	_caption.offset_top = -150.0
	_caption.offset_bottom = -64.0
	_caption.visible = false
	_overlay.add_child(_caption)


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


func _title_card(seconds: float) -> void:
	_card_title.text = _game_name
	_card_sub.text = _title_sub
	_card.visible = true
	await _hold(seconds)
	_card.visible = false


func _end_card(seconds: float) -> void:
	if _caption != null:
		_caption.visible = false
	_card_title.text = _game_name
	_card_sub.text = _cta
	_card.visible = true
	await _hold(seconds)


func _hold(seconds: float) -> void:
	var frames: int = int(round(seconds * _fps))
	for i in frames:
		await get_tree().process_frame
