extends SceneTree

# Movie Maker / frame-dump driver: real gate_room + Mixamo player.
# Script: walk → RMB aim → LMB fire → holster.
#
# Video (headed GPU window — NOT --headless):
#   tools/record_mixamo_combat_demo.sh
#   # or:
#   godot --path . --rendering-driver metal --fixed-fps 30 --resolution 1280x720 \
#     --write-movie screenshots/result/mixamo_combat_demo_raw.avi \
#     -s res://tests/shots/mixamo_combat_demo_movie.gd
#
# Still frames (works headed or with a display; also under --write-movie):
#   dumps screenshots/result/mixamo_combat_demo/frame_NNN.png at scripted beats.

const OUT_DIR: String = "res://screenshots/result/mixamo_combat_demo"
const FPS: float = 30.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mixamo_combat_demo_movie ===")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "mixamo_combat_demo_movie")

	if not (
		ResourceLoader.exists("res://models/mixamo_openbot/YBot_rifle_combat.glb")
		or ResourceLoader.exists("res://models/mixamo_openbot/Swat_rifle_combat.glb")
		or ResourceLoader.exists("res://models/mixamo_openbot/Swat_rifle_idle.glb")
	):
		push_error("mixamo_combat_demo_movie: Mixamo combat pack missing — rebuild locally")
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		if gs.has_method("discover_room"):
			gs.call("discover_room", "gate_room", "Gate Room")
		gs.set("met_scott", true)
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	current_scene = inst
	await _settle(45)

	var player: Node = _find_player(inst)
	if player == null:
		push_error("mixamo_combat_demo_movie: no Player")
		quit(1)
		return
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", false)

	var mixamo: Node = _find_mixamo(player)
	if mixamo == null or not bool(mixamo.call("is_combat_ready")):
		push_error("mixamo_combat_demo_movie: Mixamo combat avatar not ready")
		quit(1)
		return

	DisplayServer.window_set_size(Vector2i(1280, 720))
	set_meta("demo_capture", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[demo] Mixamo ready — scripting walk / aim / fire")

	# Beat 1: holster idle
	await _settle(_frames(0.6))
	await _shot("01_holster_idle")

	# Beat 1b: holster + tool-use stub (Idle + HUD when Digging/Working absent)
	if player.has_method("begin_tool_use"):
		player.call("begin_tool_use", "repair", 1.2)
	await _settle(_frames(1.2))
	await _shot("01b_tool_use")
	if player.has_method("end_tool_use"):
		player.call("end_tool_use")
	await _settle(_frames(0.35))

	# Beat 2: walk corridor (forward)
	Input.action_press("move_forward")
	await _settle(_frames(2.2))
	await _shot("02_walk")
	Input.action_release("move_forward")
	await _settle(_frames(0.35))

	# Beat 3: RMB aim (stand)
	if player.has_method("set_demo_combat"):
		player.call("set_demo_combat", true, false)
	await _settle(_frames(1.0))
	await _shot("03_aim")

	# Beat 4: aim + strafe walk
	Input.action_press("move_right")
	await _settle(_frames(1.4))
	await _shot("04_aim_strafe")
	Input.action_release("move_right")
	await _settle(_frames(0.25))

	# Beat 5: LMB fire while aiming
	if player.has_method("set_demo_combat"):
		player.call("set_demo_combat", true, true)
	await _settle(_frames(1.8))
	await _shot("05_fire")

	# Beat 6: holster
	if player.has_method("clear_demo_combat"):
		player.call("clear_demo_combat")
	elif player.has_method("set_demo_combat"):
		player.call("set_demo_combat", false, false)
	await _settle(_frames(1.0))
	await _shot("06_holster")

	# Beat 7: short jog then settle (end card beat)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _settle(_frames(1.5))
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _settle(_frames(0.8))
	await _shot("07_end")

	print("=== mixamo_combat_demo_movie done ===")
	print("[demo] frames → ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _frames(seconds: float) -> int:
	return maxi(1, int(round(seconds * FPS)))


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_warning("[demo] no viewport image for ", label)
		return
	var path: String = "%s/%s.png" % [OUT_DIR, label]
	var abs_path: String = ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("[shot] ", path, " size=", img.get_size())


func _find_player(n: Node) -> Node:
	if n.is_in_group("player"):
		return n
	for c in n.get_children():
		var f: Node = _find_player(c)
		if f != null:
			return f
	return n.find_child("Player", true, false)


func _find_mixamo(n: Node) -> Node:
	if n == null:
		return null
	if String(n.name) == "MixamoCombatAvatar":
		return n
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("mixamo_combat_avatar.gd"):
		return n
	for c in n.get_children():
		var f: Node = _find_mixamo(c)
		if f != null:
			return f
	return null
