extends SceneTree

# Capture the dial/spin/kawoosh activation as a 4-frame strip so we can verify
# each beat of the gate turning on:
#   dial_0_dormant -> dial_1_spin -> dial_2_kawoosh -> dial_3_open
#
#   godot --quit-after 360 -s res://tests/shots/gate_dial_shot.gd ++ out=user://dial

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var prefix := String(args.get("out", "user://dial"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "gate_dial_shot")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		if gs.has_method("discover_room"):
			gs.call("discover_room", "gate_room", "Gate Room")
		gs.set("met_scott", true)
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	await process_frame

	# Hide HUD + player rig for a clean architectural frame.
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer: (hud as CanvasLayer).visible = false

	# Head-on camera (concept "Central Approach").
	var cam := Camera3D.new()
	cam.fov = 58.0
	inst.add_child(cam)
	cam.global_position = Vector3(0.0, 2.8, -3.0)
	cam.look_at(Vector3(0, 2.8, 12.0), Vector3.UP)
	cam.make_current()

	for i in 20:
		await process_frame
	_save(prefix + "_0_dormant.png")

	# Kick the dial (no SFX in headless). Spin runs in _process.
	inst.call("dial_and_open", false)

	# Mid-spin (~1.4s in).
	for i in 84:
		await process_frame
	_save(prefix + "_1_spin.png")

	# Right after the lock + kawoosh burst (DIAL_TIME 3.2s -> ~frame 192, +12 for burst).
	for i in 120:
		await process_frame
	_save(prefix + "_2_kawoosh.png")

	# Settled open.
	for i in 60:
		await process_frame
	_save(prefix + "_3_open.png")
	quit(0)

func _save(path: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
