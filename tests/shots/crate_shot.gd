extends SceneTree

# One-off visual sign-off harness for the Ancient-tech crate (issue #37).
# Spawns one closed and one looted-open crate on a neutral floor under a
# fixed 3/4 camera, renders a few frames with the project's real renderer,
# then dumps a PNG. NOT committed as a baseline — eyeball only.
#
# Run with:
#   godot --quit-after 200 -s res://tests/shots/crate_shot.gd ++ out=user://crate_shot.png

const CRATE_SCRIPT: String = "res://scripts/shuttle_crate.gd"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out_path: String = "user://crate_shot.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)

	var router: Node = root.get_node_or_null("/root/SceneRouter")
	if router != null:
		router.set("instant_mode", true)

	var world: Node3D = Node3D.new()
	root.add_child(world)

	# Neutral dark floor.
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.06, 0.07, 0.09)
	fmat.roughness = 0.9
	floor_mi.material_override = fmat
	world.add_child(floor_mi)

	# Lighting.
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(40), 0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.05)
	e.ambient_light_color = Color(0.2, 0.24, 0.3)
	e.ambient_light_energy = 0.5
	env.environment = e
	world.add_child(env)

	var script: Script = load(CRATE_SCRIPT)
	var closed: StaticBody3D = StaticBody3D.new()
	closed.set_script(script)
	closed.set("fuse_type", "rations")
	closed.position = Vector3(-0.85, 0, 0)
	world.add_child(closed)

	var opened: StaticBody3D = StaticBody3D.new()
	opened.set_script(script)
	opened.set("fuse_type", "small")
	opened.position = Vector3(0.85, 0, 0)
	world.add_child(opened)
	opened.call("interact", null)  # loot → lid swings open

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(1.6, 1.9, 2.6)
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)

	for i in 80:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path)
	quit(0)
