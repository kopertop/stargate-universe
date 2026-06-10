extends SceneTree

# Rifle grip orientation tuner for the Quaternius rig: same aim pose, one
# actor per candidate rotation, camera on the aim axis so "forward" is
# unambiguous. Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/rifle_grip_tune.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")
const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const CANDIDATES: Array = [
	["current (upside down)", Vector3(-1.57, 1.57, 0.0)],
	["+ Z roll 180", Vector3(-1.57, 1.57, 3.14)],
	["Rx+90 Ry-90", Vector3(1.57, -1.57, 0.0)],
	["Rx+90 Ry+90", Vector3(1.57, 1.57, 0.0)],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1500, 700)
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
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(i * 1.6 - 2.4, 0.0, 0.0)
		c.rotation.y = 0.9   # angled so the aim direction reads in depth
		world.add_child(c)
		c.call("play_clip", "rifle_aim", 0.0)
		var ap: AnimationPlayer = _find_anim(c)
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * 0.4, true)
			ap.pause()
		var skel: Skeleton3D = c.call("skeleton")
		var mount: BoneAttachment3D = BoneAttachment3D.new()
		skel.add_child(mount)
		mount.bone_name = "RightHand"
		var rifle: Node3D = FactoryRef.build_rifle()
		rifle.position = Vector3(0.0, 0.08, -0.02)
		rifle.rotation = CANDIDATES[i][1]
		mount.add_child(rifle)
		var tag: Label3D = Label3D.new()
		tag.text = CANDIDATES[i][0]
		tag.position = Vector3(c.position.x, 2.05, 0.0)
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.4, 4.8)
	cam.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
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
