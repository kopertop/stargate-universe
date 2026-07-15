extends SceneTree

# Candidate grid for frozen-clip poses: renders one ModularCharacter per
# (clip, fraction) candidate side by side so a working pose (Rush hunched
# over his console, hands forward) is PICKED from a render, not reasoned
# about. Run NON-headless:
#   godot --quit-after 600 -s res://tests/capture/pose_grid.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")

# Candidates: [clip, fraction]
const CANDIDATES: Array = [
	["console_work", 0.0],
	["pickup", 0.30], ["pickup", 0.40], ["pickup", 0.50],
	["interact", 0.4], ["argue", 0.2],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	world.add_child(env)
	env.environment = e

	for i in range(CANDIDATES.size()):
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(float(i) * 1.5 - float(CANDIDATES.size() - 1) * 0.75, 0.0, 0.0)
		c.rotation.y = PI * 0.7   # three-quarter toward the camera
		world.add_child(c)
		c.call("set_slot", "Body", "Male_Peasant_Body")
		c.call("set_slot", "Legs", "Male_Peasant_Legs")
		if String(CANDIDATES[i][0]) == "console_work":
			c.call("pose_console_work")
		else:
			c.call("freeze_clip_at", String(CANDIDATES[i][0]), float(CANDIDATES[i][1]))
		var tag: Label3D = Label3D.new()
		tag.text = "%s\n%.2f" % [CANDIDATES[i][0], CANDIDATES[i][1]]
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.1, 0)
		c.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.5, 5.6)
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	cam.current = true
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://pose_grid.png")
	print("[grid] %s" % ProjectSettings.globalize_path("user://pose_grid.png"))
	quit()
