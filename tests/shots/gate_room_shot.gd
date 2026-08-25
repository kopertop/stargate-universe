extends SceneTree

# Architectural shot of the REAL gate_room scene (geometry + lighting + props),
# but with the arrival cinematic / Scott auto-greet suppressed and a free camera
# placed head-on to the gate (concept "Central Approach"). Lets us judge the new
# floor-pinned ring, brightness, and prop framing without the dialog cinema.
#
#   godot --quit-after 240 -s res://tests/shots/gate_room_shot.gd ++ \
#       out=user://gate_room_front.png active=0 cam=front wait=70

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var out_path := String(args.get("out", "user://gate_room_front.png"))
	var active := String(args.get("active", "0")) == "1"
	var cam_mode := String(args.get("cam", "front"))
	var wait_frames := int(args.get("wait", "70"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "gate_room_shot")

	var gs: Node = root.get_node_or_null("GameState")
	# Suppress the first-visit cinematic + Scott auto-greet: pre-mark the room as
	# discovered and Scott as met, and force instant_mode so dialogs don't fire.
	if gs != null:
		if gs.has_method("discover_room"):
			gs.call("discover_room", "gate_room", "Gate Room")
		gs.set("met_scott", true)
		# is_gate_open() == lime_planet_dialed and not scrubber_repaired. Set it so
		# the scene's _refresh_gate_state keeps the event horizon lit for active shots.
		if active:
			gs.set("lime_planet_dialed", true)
			gs.set("scrubber_repaired", false)
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	await process_frame

	# Optionally light the gate.
	var sg: Node = inst.get_node_or_null("World/Stargate")
	if sg != null and "active" in sg:
		sg.set("active", active)

	# Hide the player rig + HUD so we get a clean architectural frame.
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	for i in wait_frames:
		await process_frame

	# Disable the player's follow camera so our free camera reliably wins (make_current
	# alone is flaky in headless — the SpringArm cam sometimes re-asserts).
	var pcam: Camera3D = inst.get_node_or_null("View/SpringArm/Camera")
	if pcam != null:
		pcam.current = false
	# Free camera: drop a Camera3D and make it current so it overrides the player cam.
	var cam := Camera3D.new()
	cam.fov = 58.0
	inst.add_child(cam)
	if cam_mode == "medic":
		# Close-up on the medic tableau (Young prone + James kneeling) at (-3,0,-15).
		cam.fov = 45.0
		cam.global_position = Vector3(0.5, 2.2, -10.5)
		cam.look_at(Vector3(-3.0, 0.4, -15.0), Vector3.UP)
	elif cam_mode == "left":
		cam.global_position = Vector3(-11.0, 3.4, -2.0)
		cam.look_at(Vector3(0, 3.0, 12.0), Vector3.UP)
	elif cam_mode == "high":
		cam.global_position = Vector3(0.0, 7.5, -12.0)
		cam.look_at(Vector3(0, 2.0, 12.0), Vector3.UP)
	else: # front — concept "Central Approach"
		cam.global_position = Vector3(0.0, 2.6, -3.0)
		cam.look_at(Vector3(0, 2.6, 12.0), Vector3.UP)
	cam.make_current()
	await process_frame
	await process_frame

	var c2: Camera3D = root.get_viewport().get_camera_3d()
	if c2 != null:
		print("CAM pos=", c2.global_position, " fwd=", -c2.global_transform.basis.z)

	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("SHOT ", out_path, " err=", err)
	quit(0)
