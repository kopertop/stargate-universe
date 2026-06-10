extends SceneTree

# Single-character close-up: one crew member in base colors vs ship vs mission
# dress, front-facing. Iteration harness for outfit/swatch debugging.
#   CHAR_ONE="Sgt Greer" godot --quit-after 600 -s res://tests/capture/character_one.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var character_name: String = OS.get_environment("CHAR_ONE")
	if character_name == "":
		character_name = "Sgt Greer"
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

	var variants: Array = [
		["base", ""],
		["ship", FactoryRef.CTX_SHIP],
		["mission", FactoryRef.CTX_MISSION],
	]
	for i in range(variants.size()):
		var label: String = variants[i][0]
		var ctx: String = variants[i][1]
		var body: Node3D = Node3D.new()
		body.position = Vector3(i * 2.2, 0.0, 0.0)
		body.rotation.y = -0.45   # quarter-turn so chest-carried gear profiles show
		world.add_child(body)
		var holder: Node3D = Node3D.new()
		holder.name = "Model"
		holder.scale = Vector3(2.6, 2.6, 2.6)
		body.add_child(holder)
		var glb: PackedScene = load(FactoryRef.model_for(character_name, "res://models/characters/scott.glb"))
		if glb != null:
			holder.add_child((glb as PackedScene).instantiate())
		if ctx == "":
			FactoryRef.apply_texture(holder, load(FactoryRef.COLORMAP_PATH))
		else:
			FactoryRef.dress(body, holder, character_name, ctx)
			var stem: String = String(FactoryRef.profile_for(character_name)["model"])
			var oid: String = FactoryRef.outfit_id_for(character_name, ctx)
			var tex: Texture2D = FactoryRef.outfit_texture(stem, oid)
			var is_base: bool = tex == load(FactoryRef.COLORMAP_PATH)
			print("[debug] %s ctx=%s stem=%s outfit=%s baked_is_base=%s groups=%s" % [
				character_name, ctx, stem, oid, is_base,
				FactoryRef.SWATCH_GROUPS.get(stem, {}).keys()])
		var tag: Label3D = Label3D.new()
		tag.text = label
		tag.position = Vector3(0.0, 2.3, 0.0)
		tag.pixel_size = 0.009
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.global_position = Vector3(2.2, 2.0, 5.6)
	cam.look_at(Vector3(2.2, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var out: String = "user://character_one.png"
	img.save_png(out)
	print("[capture] %s saved abs=%s" % [character_name, ProjectSettings.globalize_path(out)])
	quit()
