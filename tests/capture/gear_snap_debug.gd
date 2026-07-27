extends SceneTree

# Gear-snap tuning harness: ONE character, large, front + back + side columns,
# in a chosen state, with idle running so BoneAttachment3D resolves. Prints each
# gear node's global position and its mount bone so offsets can be tuned.
#   CHAR_ONE="Sgt Greer" STATE=mission AIM=0 godot --quit-after 600 \
#     -s res://tests/capture/gear_snap_debug.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const MODEL_SCALE: float = 2.6

var _models: Array = []   # [holder, ...] for each angle column


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var character_name: String = OS.get_environment("CHAR_ONE")
	if character_name == "":
		character_name = "Sgt Greer"
	var ctx: String = OS.get_environment("STATE")
	if ctx == "":
		ctx = "mission"
	var aimed: bool = OS.get_environment("AIM") == "1"

	root.size = Vector2i(1100, 760)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.20, 0.24)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.25
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	world.add_child(sun)

	# Three columns: front (face cam), back (turned 180), side (turned 90).
	var angles: Array = [["front", 0.0], ["back", PI], ["side", PI * 0.5]]
	for i in range(angles.size()):
		var body: Node3D = Node3D.new()
		body.position = Vector3(i * 2.4, 0.0, 0.0)
		body.rotation.y = angles[i][1]
		world.add_child(body)
		var holder: Node3D = Node3D.new()
		holder.name = "Model"
		holder.scale = Vector3.ONE * MODEL_SCALE
		holder.rotation.y = PI
		body.add_child(holder)
		var glb: PackedScene = load(FactoryRef.model_for(character_name, "res://models/characters/scott.glb"))
		var anim: AnimationPlayer = null
		if glb != null:
			var inst: Node = glb.instantiate()
			holder.add_child(inst)
			anim = _find_anim(inst)
		FactoryRef.dress(body, holder, character_name, ctx, MODEL_SCALE, aimed)
		if anim != null:
			var clip: String = "holding-right" if aimed and anim.has_animation("holding-right") else "idle"
			if anim.has_animation(clip):
				# Freeze a representative frame so gear placement reads the same
				# every run; seek(update=true) refreshes bone poses. Holding poses
				# settle ~0.4s in; idle reads best near its start.
				anim.play(clip)
				anim.seek(0.4 if aimed else 0.05, true)
				anim.pause()
		_models.append(holder)
		var tag: Label3D = Label3D.new()
		tag.text = angles[i][0]
		tag.position = Vector3(0.0, 2.4, 0.0)
		tag.pixel_size = 0.011
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 34.0   # zoomed in for readable gear
	world.add_child(cam)
	cam.global_position = Vector3(2.4, 1.5, 6.6)
	cam.look_at(Vector3(2.4, 0.85, 0.0), Vector3.UP)
	cam.current = true

	for i in range(24):
		await process_frame
	await RenderingServer.frame_post_draw

	# Dump where the gear actually landed (front column).
	print("[snap] %s state=%s aim=%s" % [character_name, ctx, aimed])
	var skel: Skeleton3D = FactoryRef._find_skeleton(_models[0])
	if skel != null:
		for ba in skel.get_children():
			if ba is BoneAttachment3D:
				for g in ba.get_children():
					if g is Node3D:
						var box: AABB = FactoryRef._merged_aabb(g)
						print("  %-8s on bone '%s'  world=%s  world_size=%s" % [
							g.name, (ba as BoneAttachment3D).bone_name,
							(g as Node3D).global_position,
							box.size * (g as Node3D).global_transform.basis.get_scale()])

	var img: Image = root.get_viewport().get_texture().get_image()
	var out: String = "user://gear_snap.png"
	img.save_png(out)
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path(out))
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
