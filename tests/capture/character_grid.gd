extends SceneTree

# Visual validation grid for the character generation system: the full crew
# roster dressed for SHIP (front row) and MISSION (back row), captured to PNG.
# Run NON-headless (capture needs a real viewport):
#   godot --quit-after 600 -s res://tests/capture/character_grid.gd

# npc.gd's dependency chain doesn't compile under bare `-s` runs, so the idle
# helper is inlined below instead of preloading NpcScript.
const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const SPACING: float = 1.7
const ROW_GAP: float = 4.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)

	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.2
	env.environment = e
	world.add_child(env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	world.add_child(sun)

	var names: Array = FactoryRef.PROFILES.keys()
	var contexts: Array[String] = [FactoryRef.CTX_SHIP, FactoryRef.CTX_MISSION]
	for row in range(contexts.size()):
		for i in range(names.size()):
			var character_name: String = names[i]
			var body: Node3D = Node3D.new()
			# Back row offset half a slot so both rows read from one camera.
			body.position = Vector3(i * SPACING + row * SPACING * 0.5, 0.0, -row * ROW_GAP)
			body.rotation.y = -0.35   # quarter turn so chest gear profiles show
			world.add_child(body)

			var holder: Node3D = Node3D.new()
			holder.name = "Model"
			holder.scale = Vector3(2.6, 2.6, 2.6)
			body.add_child(holder)
			var glb: PackedScene = load(FactoryRef.model_for(character_name))
			if glb != null:
				var inst: Node = glb.instantiate()
				holder.add_child(inst)
				_play_idle(inst)
			FactoryRef.dress(body, holder, character_name, contexts[row])

			var tag: Label3D = Label3D.new()
			tag.text = character_name + "\n(%s)" % contexts[row]
			tag.position = Vector3(0.0, 2.25, 0.0)
			tag.pixel_size = 0.0075
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.outline_size = 8
			body.add_child(tag)

	var mid: float = (names.size() - 1) * SPACING * 0.5
	var cam: Camera3D = Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_position = Vector3(mid, 5.2, 10.5)
	cam.look_at(Vector3(mid, 0.6, -ROW_GAP * 0.55), Vector3.UP)
	cam.current = true

	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://character_grid.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://character_grid.png"))
	quit()


func _play_idle(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			var ap: AnimationPlayer = n
			for nm in ap.get_animation_list():
				if String(nm).to_lower().contains("idle"):
					ap.play(String(nm))
					return
			return
		for c in n.get_children():
			stack.append(c)
