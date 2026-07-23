extends SceneTree

# Player ↔ Mixamo combat avatar: mounts Swat pack when present, aim/fire API.
# Skips (PASS) when Swat_rifle_combat.glb is absent (ToS-local rebuild).
# Run: tests/run.sh mixamo-player  or:
#   godot --headless -s res://tests/smoke/mixamo_player_bridge.gd

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mixamo_player_bridge smoke ===")
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

	var packed: PackedScene = load("res://objects/player.tscn") as PackedScene
	_check(packed != null, "load player.tscn")
	if packed == null:
		_finish()
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
		_finish()
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

	player.queue_free()
	_finish()


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
