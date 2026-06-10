extends SceneTree

# ModularCharacter verification: bone-weight body splitting + slot equipment +
# rifle mounts on the Quaternius packs. Columns:
#   1. bare base (all body regions visible)
#   2. FULL Ranger (covered regions hidden — no clip-through "holes")
#   3. mixed Ranger/Peasant + rifle AIMED in hand (fixed direction)
#   4. Peasant + hair + rifle slung on back
# Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/quaternius_assembly.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")

# label, clip, phase, slots{}, rifle[carried, aimed]
const LOOKS: Array = [
	["bare base", "walk", 0.35, {}, [false, false]],
	["full ranger", "walk", 0.35, {
		"Body": "Male_Ranger_Body", "Arms": "Male_Ranger_Arms",
		"Legs": "Male_Ranger_Legs", "Feet": "Male_Ranger_Feet_Boots",
		"Head": "Male_Ranger_Head_Hood", "Acc": "Male_Ranger_Acc_Pauldron"}, [false, false]],
	["mixed + rifle aimed", "rifle_aim", 0.40, {
		"Body": "Male_Ranger_Body", "Arms": "Male_Ranger_Arms",
		"Legs": "Male_Peasant_Legs", "Feet": "Male_Ranger_Feet_Boots"}, [true, true]],
	["peasant + hair + slung", "idle", 0.20, {
		"Body": "Male_Peasant_Body", "Arms": "Male_Peasant_Arms",
		"Legs": "Male_Peasant_Legs", "Feet": "Male_Peasant_Feet",
		"Hair": "Hair_Buzzed"}, [true, false]],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1500, 800)
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
	sun.light_energy = 1.1
	world.add_child(sun)

	for i in range(LOOKS.size()):
		var look: Array = LOOKS[i]
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(i * 1.45 - 2.2, 0.0, 0.0)
		c.rotation.y = 0.35
		world.add_child(c)
		for slot in look[3]:
			c.call("set_slot", slot, look[3][slot])
		c.call("set_rifle", look[4][0], look[4][1])
		c.call("play_clip", look[1], 0.0)
		var ap: AnimationPlayer = c.get_node_or_null("Superhero_Male_FullBody/AnimationPlayer")
		if ap == null:
			ap = _find_anim(c)
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * float(look[2]), true)
			ap.pause()
		var tag: Label3D = Label3D.new()
		tag.text = look[0]
		tag.position = Vector3(c.position.x, 2.05, 0.0)
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.2, 5.2)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://quaternius_assembly.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://quaternius_assembly.png"))
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
