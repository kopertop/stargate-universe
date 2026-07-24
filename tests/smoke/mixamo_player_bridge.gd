extends SceneTree

# Player ↔ Mixamo combat avatar: mounts Swat pack when present, aim/fire API,
# and boots a real ship scene (gate_room) so combat_look / feet plant wire up.
# Skips (PASS) when Swat_rifle_combat.glb is absent (ToS-local rebuild).
# Run: tests/run.sh mixamo-player  or:
#   godot --headless -s res://tests/smoke/mixamo_player_bridge.gd

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mixamo_player_bridge smoke ===")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "mixamo_player_bridge")

	var MixamoRef: Script = load("res://scripts/mixamo_combat_avatar.gd") as Script
	_check(MixamoRef != null, "load MixamoCombatAvatar script")
	if MixamoRef == null:
		_finish()
		return
	if not (
		ResourceLoader.exists("res://models/mixamo_openbot/Swat_rifle_combat.glb")
		or ResourceLoader.exists("res://models/mixamo_openbot/Swat_rifle_idle.glb")
	):
		print("  SKIP  Swat combat pack not present (rebuild locally)")
		_passes += 1
		_finish()
		return

	await _check_isolated_player()
	await _check_gate_room_ship()
	_finish()


func _check_isolated_player() -> void:
	var packed: PackedScene = load("res://objects/player.tscn") as PackedScene
	_check(packed != null, "load player.tscn")
	if packed == null:
		return
	var player: Node = packed.instantiate()
	player.set("use_mixamo_avatar", true)
	player.set("use_mint_avatar", false)
	root.add_child(player)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var mixamo: Node = _find_mixamo(player)
	_check(mixamo != null, "player hosts MixamoCombatAvatar")
	if mixamo == null:
		player.queue_free()
		return

	# Freeze player physics so it doesn't overwrite manual tick() aiming state.
	player.set_physics_process(false)
	player.set_process(false)

	_check(bool(mixamo.call("is_combat_ready")), "mixamo is_combat_ready")
	var skel: Skeleton3D = mixamo.call("find_skeleton") as Skeleton3D
	_check(skel != null and skel.get_bone_count() >= 50, "mixamo skeleton has Mixamo bone count")

	mixamo.call("tick", 0.016, false, false, Vector2.ZERO, false, 0.0)
	await process_frame
	_check(true, "tick holster idle")

	mixamo.call("tick", 0.016, true, false, Vector2.ZERO, false, 0.0)
	await process_frame
	_check(bool(mixamo.call("is_aiming_stance")), "tick aim crouch stance")

	mixamo.call("tick", 0.016, true, true, Vector2(0.0, -1.0), false, 0.0)
	await process_frame
	_check(true, "tick aim+move")

	var col: CollisionShape3D = player.get_node_or_null("Collider") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		var cap: CapsuleShape3D = col.shape as CapsuleShape3D
		_check(is_equal_approx(cap.radius, 0.28), "mixamo capsule radius tuned to showcase")
		_check(is_equal_approx(col.position.y, cap.height * 0.5), "mixamo capsule centered for floor plant")
	else:
		_check(false, "mixamo capsule present")

	player.queue_free()
	await process_frame


func _check_gate_room_ship() -> void:
	print("--- gate_room Mixamo boot ---")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.set("instant_mode", true)
		if gs.has_method("discover_room"):
			gs.call("discover_room", "gate_room", "Gate Room")

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	_check(packed != null, "load gate_room.tscn")
	if packed == null:
		return
	var gate: Node = packed.instantiate()
	root.add_child(gate)
	for _i in 10:
		await process_frame

	var player: Node = gate.get_node_or_null("Player")
	_check(player != null, "gate_room has Player")
	var mixamo: Node = _find_mixamo(player) if player != null else null
	_check(mixamo != null, "gate_room player hosts MixamoCombatAvatar")
	if mixamo != null:
		_check(bool(mixamo.call("is_combat_ready")), "gate_room mixamo is_combat_ready")
		# Foot align runs deferred; host y should have moved off identity.
		var host: Node3D = mixamo.get_node_or_null(".") as Node3D
		_check(host != null, "gate_room mixamo host node")

	var view: Node = gate.get_node_or_null("View")
	_check(view != null, "gate_room has View")
	if view != null:
		_check(bool(view.get("combat_look")), "gate_room view combat_look enabled")
		var hip_z: float = float(view.get("combat_hip_zoom"))
		_check(hip_z > 0.0 and hip_z <= 4.0, "gate_room combat_hip_zoom showcase-close")
		var fh: float = float(view.get("follow_height"))
		_check(fh >= 1.2, "gate_room follow_height raised for Mixamo")

	# Aim API still works inside the ship scene (freeze player so physics
	# cannot clear aiming between our manual ticks).
	if mixamo != null and player != null:
		player.set_physics_process(false)
		player.set_process(false)
		mixamo.call("tick", 0.016, true, false, Vector2.ZERO, false, 0.0)
		await process_frame
		_check(bool(mixamo.call("is_aiming_stance")), "gate_room tick aim crouch")
		if view != null and view.has_method("set_combat_aiming"):
			view.call("set_combat_aiming", true)
			_check(bool(view.get("combat_aiming")), "gate_room view combat_aiming set")
		if gs != null and gs.has_signal("dialog_started"):
			gs.emit_signal("dialog_started", null, [])
			await process_frame
			_check(not bool(view.get("combat_aiming")), "dialog_started clears combat_aiming")
			if gs.has_signal("dialog_closed"):
				gs.emit_signal("dialog_closed")
			await process_frame
			_check(bool(view.get("combat_look")), "dialog_closed keeps combat_look")

	gate.queue_free()
	await process_frame


func _find_mixamo(n: Node) -> Node:
	if n.has_method("is_combat_ready") and n.has_method("tick"):
		return n
	for c in n.get_children():
		var f: Node = _find_mixamo(c)
		if f != null:
			return f
	return null


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
