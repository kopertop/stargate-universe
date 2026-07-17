extends SceneTree

# Headless smoke: MintCharacter loads Eli + merges basic_locomotion clips.
# Run: tests/run.sh mint-character
#   or: Godot --path . -s tests/smoke/mint_character.gd

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mint_character smoke ===")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "mint_character_smoke")

	var MintRef: Script = load("res://scripts/mint_character.gd") as Script
	_check(MintRef != null, "load MintCharacter script")

	var slugs: Array = MintRef.profile_slugs()
	_check(slugs.has("eli"), "registry lists eli")

	var eli: Node = MintRef.load_profile("eli")
	_check(eli != null, "load_profile('eli')")
	if eli == null:
		_finish()
		return

	root.add_child(eli)
	# Wait for _ready merge.
	await process_frame
	await process_frame
	await process_frame

	var clips: PackedStringArray = eli.call("clip_names")
	_check(clips.size() >= 10, "merged >= 10 clips (got %d loco+combat)" % clips.size())
	_check(Array(clips).has("Idle"), "has Idle clip")
	_check(eli.call("play", "Idle") == true, "play Idle")
	_check(str(eli.call("current_clip")) == "Idle", "current_clip is Idle")
	if Array(clips).has("Casual_Walk_inplace"):
		_check(eli.call("play", "Casual_Walk_inplace") == true, "play Casual_Walk_inplace")
	if Array(clips).has("Cowboy_Quick_Draw_Shooting"):
		_check(eli.call("play", "Cowboy_Quick_Draw_Shooting") == true, "play fire clip")
	if Array(clips).has("Gesture_with_Hand_on_Gun"):
		_check(eli.call("play", "Gesture_with_Hand_on_Gun") == true, "play aim clip")

	# Layering API (AnimationTree): aim blend + oneshots over loco.
	_check(eli.call("play", "Casual_Walk_inplace") == true or eli.call("play", "Idle") == true, "loco under layers")
	if eli.has_method("set_move_blend"):
		eli.call("set_move_blend", 1.0, 1.0)
		_check(true, "set_move_blend run")
	if eli.has_method("set_aim_blend"):
		eli.call("set_aim_blend", 0.6)
		_check(true, "set_aim_blend")
	if eli.has_method("request_jump") and Array(clips).has("Regular_Jump"):
		_check(eli.call("request_jump") == true, "request_jump oneshot")
	if eli.has_method("request_fire"):
		_check(eli.call("request_fire") == true, "request_fire oneshot")
	if eli.has_method("set_held_sidearm"):
		eli.call("set_held_sidearm", true, true)
		_check(bool(eli.call("is_held_aimed")), "sidearm aimed in RightHand")
		eli.call("set_held_sidearm", true, false)
		_check(not bool(eli.call("is_held_aimed")), "sidearm holstered")
		eli.call("set_held_sidearm", false, false)

	eli.queue_free()
	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	print("=== summary ===")
	print("passes: %d  fails: %d" % [_passes, _fails])
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
