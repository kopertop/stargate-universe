extends SceneTree

# VRM lineup: render the imported VRM characters side by side (MToon materials,
# spring bones live) with an expression applied to one — foundation proof for
# the VRM character pipeline. Run NON-headless:
#   godot --quit-after 600 -s res://tests/capture/vrm_lineup.gd

const MODELS: Array = [
	["eli", "res://models/vrm/eli.vrm", "happy"],
	["scott", "res://models/vrm/scott.vrm", "neutral"],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1100, 900)
	var world: Node3D = Node3D.new()
	root.add_child(world)

	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.5, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	for i in range(MODELS.size()):
		var label: String = MODELS[i][0]
		var packed: PackedScene = load(MODELS[i][1])
		if packed == null:
			print("[vrm] FAILED to load %s" % [MODELS[i][1]])
			continue
		var inst: Node3D = packed.instantiate()
		inst.position = Vector3(i * 1.4 - 0.7, 0.0, 0.0)
		inst.rotation.y = PI   # VRM 1.0 faces +Z; turn to face the camera at -Z... or not
		world.add_child(inst)
		# Apply an expression via the imported AnimationPlayer.
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		var expr: String = MODELS[i][2]
		if ap != null and ap.has_animation(expr):
			ap.play(expr)
			ap.seek(0.99, true)
			ap.pause()
		var tag: Label3D = Label3D.new()
		tag.text = label
		tag.position = Vector3(inst.position.x, 1.95, 0.0)
		tag.pixel_size = 0.0035
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.25, 3.4)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_lineup.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_lineup.png"))
	quit()
