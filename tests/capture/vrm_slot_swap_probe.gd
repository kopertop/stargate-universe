extends SceneTree

# Per-SLOT gear swap experiment (the WoW system): extract only the Tops
# surfaces from Scott's Body mesh (by VRoid material naming) and equip them on
# Eli over his own jeans + shoes + skin, with his own red tee removed.
# Surfaces keep the donor's Skin -> name-based binds onto Eli's skeleton.
# Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/vrm_slot_swap_probe.gd

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

	# Donor: Scott's Tops (his tactical top spans two Tops materials + Onepiece).
	var scott: Node = (load("res://models/vrm/scott.vrm") as PackedScene).instantiate()
	var donor_body: MeshInstance3D = _find_mesh(scott, "Body")

	# Col 1: Eli base.
	_spawn(world, Vector3(-1.2, 0.0, 0.0))
	# Col 2: Eli, own tee removed, Scott's top equipped.
	var eli: Node3D = _spawn(world, Vector3(0.0, 0.0, 0.0))
	var skel: Skeleton3D = eli.call("skeleton")
	var own_body: MeshInstance3D = _find_mesh(eli, "Body")
	if own_body != null and skel != null and donor_body != null:
		# Strip Eli's own Tops surfaces.
		own_body.mesh = _filtered_mesh(own_body.mesh, ["Tops"], true)
		# Equip Scott's Tops(+Onepiece) surfaces as a new skinned piece.
		var worn: MeshInstance3D = MeshInstance3D.new()
		worn.name = "Equip_Tops"
		worn.mesh = _filtered_mesh(donor_body.mesh, ["Tops", "Onepiece"], false)
		worn.skin = donor_body.skin
		skel.add_child(worn)
		print("[swap] Eli tee removed; Scott Tops equipped (%d surfaces)" % worn.mesh.get_surface_count())
	# Col 3: Scott base for reference.
	var scott_ref: Node3D = VrmCharacterScript.create("res://models/vrm/scott.vrm", "scott")
	scott_ref.set("auto_blink", false)
	scott_ref.position = Vector3(1.2, 0.0, 0.0)
	world.add_child(scott_ref)
	scott_ref.call("play_clip", "walk", 0.0)
	var sap: AnimationPlayer = scott_ref.get_node_or_null("scott/AnimationPlayer")
	if sap != null and sap.current_animation != "":
		sap.seek(sap.current_animation_length * 0.3, true)
		sap.pause()

	for col in [["eli base", -1.2], ["eli + scott TOP only\n(own jeans/shoes)", 0.0], ["scott base", 1.2]]:
		var tag: Label3D = Label3D.new()
		tag.text = col[0]
		tag.position = Vector3(col[1], 2.05, 0.0)
		tag.pixel_size = 0.0030
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
	img.save_png("user://vrm_slot_swap.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_slot_swap.png"))
	quit()


# New ArrayMesh with only surfaces whose material name matches (or doesn't
# match, if exclude=true) any of the garment keywords.
func _filtered_mesh(src: Mesh, keywords: Array, exclude: bool) -> ArrayMesh:
	var out: ArrayMesh = ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var mat: Material = src.surface_get_material(s)
		var mat_name: String = mat.resource_name if mat != null else ""
		var hit: bool = false
		for k in keywords:
			if mat_name.contains(k):
				hit = true
		if hit == exclude:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (src as ArrayMesh).surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


func _spawn(world: Node3D, pos: Vector3) -> Node3D:
	var c: Node3D = VrmCharacterScript.create("res://models/vrm/eli.vrm", "eli")
	c.set("auto_blink", false)
	c.position = pos
	world.add_child(c)
	c.call("play_clip", "walk", 0.0)
	var ap: AnimationPlayer = c.get_node_or_null("eli/AnimationPlayer")
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
