extends SceneTree

# THE modular-equipment experiment: can a skinned clothing mesh from one
# humanoid-retargeted export be snapped onto a DIFFERENT character's skeleton
# at runtime (WoW-style gear swap)?
#
# Dumps Skin bind info (name-based vs index-based binds decide everything),
# then attempts the swap: Mixamo avatar 'Tops' shirt -> Eli VRM skeleton,
# and renders the result mid-walk. Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/equip_probe.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	# ---------- diagnostics: skin binds ----------
	var src: Node = (load("res://models/vrm/anim_src/walking.fbx") as PackedScene).instantiate()
	var src_skel: Skeleton3D = src.get_node_or_null("GeneralSkeleton")
	for mesh_name in ["Tops", "Bottoms", "Shoes", "Body"]:
		var mi: MeshInstance3D = _find_mesh(src, mesh_name)
		if mi == null:
			print("[binds] %s: MISSING" % mesh_name)
			continue
		var skin: Skin = mi.skin
		if skin == null:
			print("[binds] %s: NO SKIN (rigid)" % mesh_name)
			continue
		var named: int = 0
		for i in range(skin.get_bind_count()):
			if String(skin.get_bind_name(i)) != "":
				named += 1
		print("[binds] %s: %d binds, %d name-based; sample names: %s, %s" % [
			mesh_name, skin.get_bind_count(), named,
			skin.get_bind_name(0), skin.get_bind_name(mini(1, skin.get_bind_count() - 1))])

	# ---------- the swap ----------
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

	# Column 1: Eli as authored.
	var eli_a: Node3D = _spawn_eli(world, Vector3(-1.0, 0.0, 0.0))
	# Column 2: Eli wearing the Mixamo avatar's shirt (cross-pack equip!).
	var eli_b: Node3D = _spawn_eli(world, Vector3(0.2, 0.0, 0.0))
	var eli_b_skel: Skeleton3D = eli_b.call("skeleton")
	var tops: MeshInstance3D = _find_mesh(src, "Tops")
	if tops != null and eli_b_skel != null:
		var worn: MeshInstance3D = tops.duplicate() as MeshInstance3D
		worn.name = "Equip_Tops"
		eli_b_skel.add_child(worn)
		# A MeshInstance3D child of a Skeleton3D binds to it via its Skin;
		# binds resolve by name against the new skeleton.
		print("[swap] Tops added to Eli skeleton; skin=%s" % (worn.skin != null))
	# Column 3: the Mixamo source avatar in its own clothes for reference.
	src.position = Vector3(1.6, 0.0, 0.0)
	src.rotation.y = 0.0
	world.add_child(src)
	var src_ap: AnimationPlayer = src.get_node_or_null("AnimationPlayer")
	if src_ap != null and src_ap.has_animation("mixamo_com"):
		src_ap.play("mixamo_com")
		src_ap.seek(0.3, true)
		src_ap.pause()

	for col in [["eli base", -1.0], ["eli + mixamo shirt", 0.2], ["mixamo avatar", 1.6]]:
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
	cam.position = Vector3(0.3, 1.15, 3.8)
	cam.look_at(Vector3(0.3, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://equip_probe.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://equip_probe.png"))
	quit()


func _spawn_eli(world: Node3D, pos: Vector3) -> Node3D:
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
