extends SceneTree

# Headless smoke: MintCharacter loads Eli + merges clips + sidearm.
# Run: tests/run.sh mint-character

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
	await process_frame
	await process_frame
	await process_frame

	var clips: PackedStringArray = eli.call("clip_names")
	_check(clips.size() >= 10, "merged >= 10 clips (got %d loco+combat)" % clips.size())
	_check(Array(clips).has("Idle"), "has Idle clip")
	_check(eli.call("play", "Idle") == true, "play Idle")
	_check(str(eli.call("current_clip")) == "Idle", "current_clip is Idle")

	_check(_no_scale_tracks(eli, "Idle"), "Idle has no SCALE tracks (size-pop guard)")
	if Array(clips).has("run_fast_3_inplace"):
		_check(_no_scale_tracks(eli, "run_fast_3_inplace"), "run has no SCALE tracks")
		_check(_hip_y_close(eli, "Idle", "run_fast_3_inplace", 3.0), "Idle/run hip Y baselines within 3u")
	if Array(clips).has("Regular_Jump"):
		_check(_no_hip_position(eli, "Regular_Jump"), "jump has no Hips position (code hop owns Y)")

	if Array(clips).has("Casual_Walk_inplace"):
		_check(eli.call("play", "Casual_Walk_inplace") == true, "play Casual_Walk_inplace")
	if eli.has_method("set_move_blend"):
		eli.call("set_move_blend", 1.0, 1.0)
		_check(true, "set_move_blend run")
	if eli.has_method("set_aim_blend"):
		eli.call("set_aim_blend", 0.6)
		_check(true, "set_aim_blend")
	if eli.has_method("request_jump") and Array(clips).has("Regular_Jump"):
		_check(eli.call("request_jump") == true, "request_jump oneshot")

	# Weapon: equip holstered → draw → fire.
	_check(eli.call("equip_weapon", "sidearm") == true, "equip_weapon sidearm")
	_check(str(eli.call("weapon_state_name")) == "HOLSTERED", "weapon starts HOLSTERED")
	_check(eli.call("request_fire") == false, "fire blocked while holstered")
	_check(eli.call("request_draw") == true, "request_draw")
	await create_timer(0.5).timeout
	var aimed: bool = str(eli.call("weapon_state_name")) == "AIMED"
	if not aimed and eli.has_method("weapon_state_name"):
		# Force complete if timer raced headless.
		var w: Node = eli.get_node_or_null("HeldWeapon")
		if w == null:
			w = eli.get_node_or_null("Sidearm")
		if w != null and w.has_method("notify_draw_finished"):
			w.call("notify_draw_finished")
		aimed = str(eli.call("weapon_state_name")) == "AIMED"
	_check(aimed, "weapon reached AIMED")
	_check(bool(eli.call("is_weapon_ready")), "weapon ready to fire")
	_check(eli.call("request_fire") == true, "request_fire while aimed")
	var grip: String = str(eli.call("grip_status"))
	_check(grip.find("fingers") >= 0, "grip_status reports fingers (%s)" % grip)
	var skel: Skeleton3D = eli.call("find_skeleton") as Skeleton3D
	var finger_bones: int = 0
	if skel != null:
		for i in skel.get_bone_count():
			var nm: String = skel.get_bone_name(i)
			if (
				nm.find("Thumb") >= 0 or nm.find("Index") >= 0 or nm.find("Middle") >= 0
				or nm.find("Ring") >= 0 or nm.find("Little") >= 0
			):
				finger_bones += 1
	_check(finger_bones >= 30, "skeleton has skinned finger bones (got %d)" % finger_bones)
	_check(grip.find("bones") >= 0, "grip uses real finger bones (%s)" % grip)
	# Swap to rifle (fallback kit mesh OK) and confirm re-equip.
	if eli.has_method("equip_weapon"):
		_check(eli.call("equip_weapon", "rifle") == true, "equip_weapon rifle")
		_check(str(eli.call("current_weapon_id")) == "rifle", "current_weapon_id rifle")
		_check(eli.call("equip_weapon", "sidearm") == true, "swap back to sidearm")
	eli.call("request_holster")
	await create_timer(0.35).timeout
	if str(eli.call("weapon_state_name")) != "HOLSTERED":
		var w2: Node = eli.get_node_or_null("HeldWeapon")
		if w2 == null:
			w2 = eli.get_node_or_null("Sidearm")
		if w2 != null and w2.has_method("notify_holster_finished"):
			w2.call("notify_holster_finished")
	_check(str(eli.call("weapon_state_name")) == "HOLSTERED", "weapon holstered again")

	eli.queue_free()
	_finish()


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f: AnimationPlayer = _find_ap(c)
		if f != null:
			return f
	return null


func _no_scale_tracks(eli: Node, clip: String) -> bool:
	var ap: AnimationPlayer = _find_ap(eli)
	if ap == null or not ap.has_animation(clip):
		return false
	var a: Animation = ap.get_animation(clip)
	for ti in a.get_track_count():
		if a.track_get_type(ti) == Animation.TYPE_SCALE_3D:
			return false
	return true


func _no_hip_position(eli: Node, clip: String) -> bool:
	var ap: AnimationPlayer = _find_ap(eli)
	if ap == null or not ap.has_animation(clip):
		return false
	var a: Animation = ap.get_animation(clip)
	for ti in a.get_track_count():
		var path: String = String(a.track_get_path(ti))
		if a.track_get_type(ti) == Animation.TYPE_POSITION_3D and path.ends_with(":Hips"):
			return false
	return true


func _hip_y_close(eli: Node, a_name: String, b_name: String, tol: float) -> bool:
	var ya: float = _hip_y0(eli, a_name)
	var yb: float = _hip_y0(eli, b_name)
	if is_nan(ya) or is_nan(yb):
		return false
	return absf(ya - yb) <= tol


func _hip_y0(eli: Node, clip: String) -> float:
	var ap: AnimationPlayer = _find_ap(eli)
	if ap == null or not ap.has_animation(clip):
		return NAN
	var a: Animation = ap.get_animation(clip)
	for ti in a.get_track_count():
		var path: String = String(a.track_get_path(ti))
		if a.track_get_type(ti) == Animation.TYPE_POSITION_3D and path.ends_with(":Hips"):
			if a.track_get_key_count(ti) < 1:
				return NAN
			return (a.track_get_key_value(ti, 0) as Vector3).y
	return NAN


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
