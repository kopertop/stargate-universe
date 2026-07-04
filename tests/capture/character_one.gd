extends SceneTree

# Single-character snap-point check: one crew member in three states —
# ship (stowed sidearm), mission (rifle slung + sidearm holstered), and
# mission-aimed (rifle to hand + holding pose). Idle/holding animations run so
# the BoneAttachment3D mounts resolve to live bone poses (gear must ride the
# rig, not float in body-space). Rotated ~35° so back-slung gear is visible.
#   CHAR_ONE="Sgt Greer" godot --quit-after 600 -s res://tests/capture/character_one.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const MODEL_SCALE: float = 2.6


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

	# label, context, aimed
	var variants: Array = [
		["ship", FactoryRef.CTX_SHIP, false],
		["mission", FactoryRef.CTX_MISSION, false],
		["aimed", FactoryRef.CTX_MISSION, true],
	]
	for i in range(variants.size()):
		var label: String = variants[i][0]
		var ctx: String = variants[i][1]
		var aimed: bool = variants[i][2]
		var body: Node3D = Node3D.new()
		body.position = Vector3(i * 2.2, 0.0, 0.0)
		body.rotation.y = -0.6   # turn so the back-slung rifle reads
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
		# Run an animation so the bone mounts move with the rig.
		if anim != null:
			var clip: String = "holding-right" if aimed and anim.has_animation("holding-right") else "idle"
			if anim.has_animation(clip):
				anim.play(clip)
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

	# Let the animations advance a few frames so BoneAttachment3D resolves.
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var out: String = "user://character_one.png"
	img.save_png(out)
	print("[capture] %s saved abs=%s" % [character_name, ProjectSettings.globalize_path(out)])
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
