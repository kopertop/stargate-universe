extends Node

# @no-save: dev-only trailer capture. Holds no persistent gameplay state and
# records NOTHING during normal play — it only activates when the game is
# launched with the record flag (env SGU_TRAILER_RECORD=<path> or the user arg
# `--trailer-record=<path>`). Mirrors the TestCapture autoload's "inert unless
# flagged" pattern.
#
# When active, it logs the live camera + player transform (+ current animation)
# and the current scene every frame, plus scene-change markers, and writes a
# capture JSON on quit. tools/trailer/replay_runner.gd renders a trailer from
# that REAL human playthrough — deterministic transform playback, so nothing can
# snag on steps or bounce off doors the way a scripted walk-solver does.
#
# Capture a run with:  tools/trailer/record.sh

var _active: bool = false
var _path: String = ""
var _t: float = 0.0
var _frames: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _last_scene: String = ""
var _written: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_path = _resolve_path()
	if _path == "":
		set_process(false)
		return
	_active = true
	# Write on a clean quit too (in case the player exits via the menu).
	get_tree().auto_accept_quit = true
	print("[trailer_capture] RECORDING this run → ", _path)


func _resolve_path() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trailer-record="):
			return a.substr("--trailer-record=".length())
	return OS.get_environment("SGU_TRAILER_RECORD")


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var scene: Node = get_tree().current_scene
	var scene_path: String = scene.scene_file_path if scene != null else ""
	# Mark transitions so replay can re-build the right level at the right time.
	# Key on scene + room_id, NOT scene alone: every ship corridor is the SAME
	# procedural res://scenes/room.tscn with a different room_id, so a scene-only
	# key would miss corridor→corridor moves. Capture the GameState snapshot +
	# room id too: room.tscn reads next_room_id to pick which room to build,
	# planet.tscn needs the dialed spec, alert tint follows the crisis flags —
	# replay restores this before loading each scene so it builds identically.
	var room_id: String = String(GameState.current_room_id)
	var key: String = scene_path + "#" + room_id
	if key != _last_scene:
		var ev: Dictionary = {"t": _t, "type": "scene", "scene": scene_path, "room": room_id}
		if GameState.has_method("serialize"):
			ev["state"] = GameState.serialize()
		# Items (kino_remote, lime, fuses…) live in the Inventory autoload, NPC
		# positions/dialogue in NPCState — both drive how a scene builds (the Kino
		# pickup, dispenser, kino-gated doors, NPC placement). Snapshot them too so
		# replay rebuilds each scene exactly, not just GameState.
		var inv: Node = get_node_or_null("/root/Inventory")
		if inv != null and inv.has_method("serialize"):
			ev["inv"] = inv.call("serialize")
		var npc: Node = get_node_or_null("/root/NPCState")
		if npc != null and npc.has_method("serialize"):
			ev["npc"] = npc.call("serialize")
		_events.append(ev)
		_last_scene = key

	var rec: Dictionary = {
		"t": _t,
		"scene": scene_path,
		"cam": _xf(cam.global_transform),
		"fov": cam.fov,
	}
	# The filmed subject is whatever is in group "player" (the on-foot character).
	# A piloted Kino is NOT in that group by design, so also record the camera —
	# during Kino flight the camera IS the drone's view and replay follows it.
	var subj: Node = get_tree().get_first_node_in_group("player")
	if subj is Node3D:
		rec["subj"] = _xf((subj as Node3D).global_transform)
		var anim: String = _subject_anim(subj)
		if anim != "":
			rec["anim"] = anim
	_frames.append(rec)


# Current animation clip name of the character, read from its AnimationPlayer so
# replay can reproduce the exact walk/idle/sprint pose without running physics.
func _subject_anim(subj: Node) -> String:
	var ap: Variant = subj.get("_animation")
	if ap is AnimationPlayer:
		return (ap as AnimationPlayer).current_animation
	return ""


func _xf(t: Transform3D) -> Dictionary:
	var e: Vector3 = t.basis.get_euler()
	return {
		"px": t.origin.x, "py": t.origin.y, "pz": t.origin.z,
		"rx": e.x, "ry": e.y, "rz": e.z,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush()


func _flush() -> void:
	if not _active or _written:
		return
	_written = true
	var doc: Dictionary = {
		"version": 1,
		"duration": _t,
		"frame_count": _frames.size(),
		"events": _events,
		"frames": _frames,
	}
	var f: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("[trailer_capture] could not open %s for write" % _path)
		return
	f.store_string(JSON.stringify(doc))
	f.close()
	print("[trailer_capture] wrote %d frames (%.1fs) → %s" % [_frames.size(), _t, _path])
