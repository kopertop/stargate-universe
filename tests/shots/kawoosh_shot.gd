extends SceneTree

# Deterministically capture the kawoosh PLUME erupting toward the camera. Boots the
# gate room, head-on camera, calls Stargate.kawoosh() directly, and snaps frames at
# sim-time marks across the plume's erupt→retract so we can see it come AT the viewer.
#   godot --quit-after 400 -s res://tests/shots/kawoosh_shot.gd ++ out=user://kawoosh

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var prefix := String(args.get("out", "user://kawoosh"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "kawoosh_shot")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null and gs.has_method("discover_room"):
		gs.call("discover_room", "gate_room", "Gate Room")
	if gs != null:
		gs.set("met_scott", true)
		gs.set("lime_planet_dialed", true)
		gs.set("scrubber_repaired", false)
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer: (hud as CanvasLayer).visible = false
	var pcam: Camera3D = inst.get_node_or_null("View/SpringArm/Camera")
	if pcam != null: pcam.current = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	inst.add_child(cam)
	cam.global_position = Vector3(0.0, 2.7, -4.0)
	cam.look_at(Vector3(0, 2.7, 12.2), Vector3.UP)
	cam.make_current()
	for i in 40:
		await process_frame

	var sg: Node = inst.get_node_or_null("World/Stargate")
	if sg != null and sg.has_method("kawoosh"):
		sg.call("kawoosh")
	var marks := [0.12, 0.24, 0.40, 0.62]
	var elapsed := 0.0
	for i in marks.size():
		await create_timer(marks[i] - elapsed).timeout
		elapsed = marks[i]
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(prefix + "_%d.png" % i)
		print("SHOT ", prefix, "_", i, ".png  t=", marks[i])
	quit(0)
