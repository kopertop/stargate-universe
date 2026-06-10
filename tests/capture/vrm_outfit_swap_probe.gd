extends SceneTree

# VRoid-family outfit swap experiment: both crew VRMs come from VRoid Studio's
# standard base body. If Scott's clothed Body mesh (black tactical suit) binds
# onto ELI's skeleton without ballooning, the VRoid family itself is a modular
# gear ecosystem: author outfits in VRoid Studio, swap Body meshes in code.
# Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/vrm_outfit_swap_probe.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.1
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.5, 0.0)
	world.add_child(sun)

	# Bind diagnostics for Scott's Body mesh.
	var scott_scene: Node = (load("res://models/vrm/scott.vrm") as PackedScene).instantiate()
	var scott_body: MeshInstance3D = _find_mesh(scott_scene, "Body")
	if scott_body != null and scott_body.skin != null:
		var named: int = 0
		for i in range(scott_body.skin.get_bind_count()):
			if String(scott_body.skin.get_bind_name(i)) != "":
				named += 1
		print("[binds] scott Body: %d binds, %d name-based" % [scott_body.skin.get_bind_count(), named])

	# Col 1: Eli as authored.
	_spawn(world, "eli", Vector3(-1.2, 0.0, 0.0), [])
	# Col 2: Eli with HIS body hidden, wearing SCOTT's Body mesh (suit + skin).
	var eli_b: Node3D = _spawn(world, "eli", Vector3(0.0, 0.0, 0.0), [])
	var skel: Skeleton3D = eli_b.call("skeleton")
	var own_body: MeshInstance3D = _find_mesh(eli_b, "Body")
	if own_body != null:
		own_body.visible = false
	if scott_body != null and skel != null:
		var worn: MeshInstance3D = scott_body.duplicate() as MeshInstance3D
		worn.name = "Equip_Body"
		skel.add_child(worn)
		print("[swap] Scott Body -> Eli skeleton (Eli body hidden, head/hair kept)")
	# Col 3: Scott as authored for reference.
	_spawn(world, "scott", Vector3(1.2, 0.0, 0.0), [])

	for col in [["eli base", -1.2], ["eli head + scott suit", 0.0], ["scott base", 1.2]]:
		var tag: Label3D = Label3D.new()
		tag.text = col[0]
		tag.position = Vector3(col[1], 2.0, 0.0)
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.15, 3.8)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_outfit_swap.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_outfit_swap.png"))
	quit()


func _spawn(world: Node3D, stem: String, pos: Vector3, _gear: Array) -> Node3D:
	var c: Node3D = VrmCharacterScript.create("res://models/vrm/%s.vrm" % stem, stem)
	c.set("auto_blink", false)
	c.position = pos
	world.add_child(c)
	c.call("play_clip", "walk", 0.0)
	var ap: AnimationPlayer = c.get_node_or_null("%s/AnimationPlayer" % stem)
	if ap != null and ap.current_animation != "":
		ap.seek(ap.current_animation_length * 0.3, true)
		ap.pause()
	return c


func _find_mesh(node: Node, mesh_name: String) -> MeshInstance3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.name == mesh_name:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
