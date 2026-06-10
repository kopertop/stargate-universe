extends SceneTree

# Rifle mount tuner for the Quaternius rig: candidate grid for the aimed
# grip POSITION (top-down camera, like the user's screenshot) and the slung
# back-mount ROTATION (those actors face away). Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/rifle_grip_tune.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")
const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const AIM_ROT: Vector3 = Vector3(-1.57, 1.57, 3.14)
# label, position, rotation, slung(bool)
const CANDIDATES: Array = [
	["z+0.03", Vector3(0.0, 0.08, 0.03), AIM_ROT, false],
	["z+0.07", Vector3(0.0, 0.08, 0.07), AIM_ROT, false],
	["z+0.11", Vector3(0.0, 0.08, 0.11), AIM_ROT, false],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1700, 760)
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
	world.add_child(sun)

	for i in range(CANDIDATES.size()):
		var cand: Array = CANDIDATES[i]
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(i * 1.1 - 1.1, 0.0, 0.0)
		# Slung candidates face away so the back mount reads.
		c.rotation.y = PI if cand[3] else 0.25
		world.add_child(c)
		c.call("play_clip", "idle" if cand[3] else "rifle_aim", 0.0)
		var ap: AnimationPlayer = _find_anim(c)
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * 0.4, true)
			ap.pause()
		var skel: Skeleton3D = c.call("skeleton")
		var mount: BoneAttachment3D = BoneAttachment3D.new()
		skel.add_child(mount)
		mount.bone_name = "Chest" if cand[3] else "RightHand"
		var rifle: Node3D = FactoryRef.build_rifle()
		rifle.position = cand[1]
		rifle.rotation = cand[2]
		mount.add_child(rifle)
		var tag: Label3D = Label3D.new()
		tag.text = cand[0]
		tag.position = Vector3(c.position.x, 2.05, 0.0)
		tag.pixel_size = 0.0034
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	# High camera looking down, like the user's screenshot.
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	# Tight, high 3/4 view matching the user's screenshot angle.
	cam.position = Vector3(0.0, 2.6, 2.2)
	cam.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://rifle_grip.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://rifle_grip.png"))
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
