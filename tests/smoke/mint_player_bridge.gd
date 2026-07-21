extends SceneTree

# Player ↔ Mint Eli bridge: avatar loads, loco blend, jump, sidearm equip.
# Run: tests/run.sh mint-character  (wired) or:
#   godot --headless -s res://tests/smoke/mint_player_bridge.gd

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mint_player_bridge smoke ===")
	var packed: PackedScene = load("res://objects/player.tscn") as PackedScene
	_check(packed != null, "load player.tscn")
	if packed == null:
		_finish()
		return
	var player: Node = packed.instantiate()
	# Force Mint path even if the scene export was toggled off locally.
	player.set("use_mint_avatar", true)
	root.add_child(player)
	await process_frame
	await process_frame
	await process_frame

	var mint: Node = _find_mint(player)
	_check(mint != null, "player hosts MintCharacter Eli")
	if mint == null:
		player.queue_free()
		_finish()
		return

	_check(mint.has_method("set_move_blend"), "mint set_move_blend")
	mint.call("set_move_blend", 1.0, 0.4)
	await process_frame
	_check(true, "set_move_blend walk")

	if mint.has_method("request_jump"):
		_check(mint.call("request_jump") == true, "request_jump")

	_check(mint.call("equip_weapon", "sidearm") == true, "equip sidearm on player mint")
	_check(mint.call("request_draw") == true, "draw sidearm")
	await create_timer(0.55).timeout
	var held: Node = mint.get_node_or_null("HeldWeapon")
	if str(mint.call("weapon_state_name")) != "AIMED" and held != null and held.has_method("notify_draw_finished"):
		held.call("notify_draw_finished")
	mint.call("set_aim_blend", 0.8)
	for _i in 6:
		await process_frame
	_check(str(mint.call("weapon_state_name")) == "AIMED", "player mint weapon AIMED")

	var skel: Skeleton3D = mint.call("find_skeleton") as Skeleton3D
	_check(skel != null and skel.get_bone_count() == 24, "player mint skeleton 24-bone host")

	player.queue_free()
	_finish()


func _find_mint(n: Node) -> Node:
	if n.has_method("set_move_blend") and n.has_method("equip_weapon"):
		return n
	for c in n.get_children():
		var f: Node = _find_mint(c)
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
