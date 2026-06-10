extends SceneTree

# THE WoW-gear proof sheet: the SAME character (Eli) in three outfits swapped
# entirely in code — own clothes; Scott's tactical top over his own jeans;
# full tactical + helmet + aimed rifle. Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/vrm_wardrobe.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")

# label, clip, phase, equips[], rigid[[id, aimed]]
const LOOKS: Array = [
	["own clothes", "idle", 0.2, [], []],
	["+ tactical top", "walk", 0.3, ["tactical_top"], []],
	["full tactical kit", "rifle_run_aim", 0.4,
		["tactical_top", "tactical_boots"], [["helmet", false], ["rifle", true]]],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1380, 800)
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
		var c: Node3D = VrmCharacterScript.create("res://models/vrm/eli.vrm", "eli")
		c.set("auto_blink", false)
		c.position = Vector3(i * 1.25 - 1.25, 0.0, 0.0)
		c.rotation.y = 0.25
		world.add_child(c)
		c.call("play_clip", look[1], 0.0)
		var ap: AnimationPlayer = c.get_node_or_null("eli/AnimationPlayer")
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * float(look[2]), true)
			ap.pause()
		for item_id in look[3]:
			c.call("equip", item_id)
		for rig in look[4]:
			c.call("attach_gear", rig[0], rig[1])
		var tag: Label3D = Label3D.new()
		tag.text = "eli — %s" % look[0]
		tag.position = Vector3(c.position.x, 1.95, 0.0)
		tag.pixel_size = 0.0030
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 44.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.15, 4.4)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_wardrobe.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_wardrobe.png"))
	quit()
