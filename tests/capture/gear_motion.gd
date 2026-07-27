extends SceneTree

# Proof that gear rides the rig: ONE character sampled at several frames of the
# WALK cycle. If the snap points work, the helmet stays glued to the head and
# the rifle to the back as the body bobs/strides — no drift. Mission loadout.
#   CHAR_ONE="Sgt Greer" godot --quit-after 600 -s res://tests/capture/gear_motion.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const MODEL_SCALE: float = 2.6
const SAMPLES: int = 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var character_name: String = OS.get_environment("CHAR_ONE")
	if character_name == "":
		character_name = "Sgt Greer"
	root.size = Vector2i(1200, 560)
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

	# One actor per sampled walk-frame, all turned 3/4 so head + back read.
	var anims: Array = []
	var clip: String = "walk"
	for i in range(SAMPLES):
		var body: Node3D = Node3D.new()
		body.position = Vector3(i * 2.2, 0.0, 0.0)
		body.rotation.y = -0.7
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
		FactoryRef.dress(body, holder, character_name, FactoryRef.CTX_MISSION, MODEL_SCALE, false)
		anims.append(anim)

	# Settle a frame so skeletons exist, then sample each actor at a different
	# phase of the walk and freeze it.
	await process_frame
	for i in range(SAMPLES):
		var anim: AnimationPlayer = anims[i]
		if anim != null and anim.has_animation(clip):
			var len: float = anim.get_animation(clip).length
			anim.play(clip)
			anim.seek(len * float(i) / float(SAMPLES), true)
			anim.pause()

	var cam: Camera3D = Camera3D.new()
	cam.fov = 42.0
	world.add_child(cam)
	cam.global_position = Vector3((SAMPLES - 1) * 1.1, 1.5, 6.2)
	cam.look_at(Vector3((SAMPLES - 1) * 1.1, 0.85, 0.0), Vector3.UP)
	cam.current = true

	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://gear_motion.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://gear_motion.png"))
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
