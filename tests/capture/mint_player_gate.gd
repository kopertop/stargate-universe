extends SceneTree

# Visual: Mint-player Eli in the control/gate opening room with sidearm.
# Needs a GPU window (not --headless).
#
#   mkdir -p screenshots/result/mint_player
#   /Applications/Godot.app/Contents/MacOS/Godot --path . --quit-after 12000 \
#     -s res://tests/capture/mint_player_gate.gd

const OUT: String = "user://mint_player/gate_eli.png"
const OUT_AIM: String = "user://mint_player/gate_eli_aim.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mint_player_gate ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mint_player"))

	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.set("next_room_id", "control_interface_room")
		if gs.has_method("discover_room"):
			gs.call("discover_room", "control_interface_room", "Control Interface Room")

	var packed: PackedScene = load("res://scenes/room.tscn") as PackedScene
	if packed == null:
		push_error("room.tscn missing")
		quit(1)
		return
	var room: Node = packed.instantiate()
	if "room_id" in room:
		room.set("room_id", "control_interface_room")
	root.add_child(room)
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var player: Node = room.get_node_or_null("Player")
	if player == null:
		push_error("Player missing")
		quit(1)
		return
	player.set("use_mint_avatar", true)
	# Re-setup if already modular from scene _ready race — force mint if absent.
	var mint: Node = _find_mint(player)
	if mint == null and player.has_method("_setup_mint_avatar"):
		player.call("_setup_mint_avatar")
		await process_frame
		await process_frame
		mint = _find_mint(player)
	print("mint body: ", mint)

	var cam: Camera3D = room.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		cam = Camera3D.new()
		room.add_child(cam)
	cam.current = true
	if player is Node3D:
		var p3: Node3D = player as Node3D
		cam.global_position = p3.global_position + Vector3(1.4, 1.55, 2.4)
		cam.look_at(p3.global_position + Vector3(0.0, 1.05, 0.0), Vector3.UP)

	await _settle(12)
	await _shot(OUT)

	if mint != null and mint.has_method("equip_weapon"):
		mint.call("equip_weapon", "sidearm")
		var held: Node = mint.get_node_or_null("HeldWeapon")
		if held != null and held.has_method("notify_draw_finished"):
			held.call("notify_draw_finished")
		if mint.has_method("set_aim_blend"):
			mint.call("set_aim_blend", 0.85)
		await _settle(16)
		await _shot(OUT_AIM)

	_copy_to_repo()
	print("=== mint_player_gate done ===")
	quit(0)


func _find_mint(actor: Node) -> Node:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("set_move_blend") and n.has_method("equip_weapon"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(user_path: String) -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(user_path)
	print("[shot] %s err=%s" % [ProjectSettings.globalize_path(user_path), error_string(err)])


func _copy_to_repo() -> void:
	var src: String = ProjectSettings.globalize_path("user://mint_player")
	var dst: String = ProjectSettings.globalize_path("res://screenshots/result/mint_player")
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".png"):
			DirAccess.copy_absolute(src.path_join(name), dst.path_join(name))
			print("[copy] %s" % dst.path_join(name))
		name = d.get_next()
	d.list_dir_end()
