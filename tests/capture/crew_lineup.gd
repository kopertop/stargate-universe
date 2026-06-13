extends SceneTree

# The in-game crew as the factory dresses them: ship row (duty/civvies) and
# mission row (field gear). Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/crew_lineup.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const CREW: Array = ["Eli", "Dr Rush", "Lt Scott", "Sgt Greer", "Dr Park", "Chloe Armstrong"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1700, 900)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.21)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.05
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.45, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	for row in range(2):
		var ctx: String = FactoryRef.CTX_SHIP if row == 0 else FactoryRef.CTX_MISSION
		for i in range(CREW.size()):
			var c: Node3D = FactoryRef.build_modular(CREW[i])
			c.position = Vector3(i * 1.35 - 3.4 + row * 0.5, 0.0, -row * 3.0)
			c.rotation.y = 0.2
			world.add_child(c)
			FactoryRef.dress_modular(c, CREW[i], ctx)
			c.call("play_clip", "idle" if row == 0 else "rifle_walk" if FactoryRef.is_military(CREW[i]) else "walk", 0.0)
			var ap: AnimationPlayer = _find_anim(c)
			if ap != null and ap.current_animation != "":
				ap.seek(ap.current_animation_length * (0.1 + 0.13 * i), true)
				ap.pause()
			var tag: Label3D = Label3D.new()
			tag.text = "%s\n(%s)" % [CREW[i], ctx]
			tag.position = Vector3(c.position.x, 2.1, c.position.z)
			tag.pixel_size = 0.0030
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.outline_size = 8
			world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 2.4, 6.4)
	cam.look_at(Vector3(0.0, 0.9, -1.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://crew_lineup.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://crew_lineup.png"))
	quit()


func _find_anim(node: Node) -> AnimationPlayer:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
