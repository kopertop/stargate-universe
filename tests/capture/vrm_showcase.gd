extends SceneTree

# VRM showcase grid: expressions, visemes, gear snap points, and retargeted
# animation — the "everything VRoid supports" proof sheet. Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/vrm_showcase.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")

# [vrm, label, clip, phase, emotion, viseme, gear, aimed]
const SHOTS: Array = [
	["eli", "happy + wave", "wave", 0.55, "happy", "", [], false],
	["eli", "surprised + 'aa'", "idle", 0.10, "surprised", "aa", [], false],
	["eli", "sad idle", "idle_sad", 0.30, "sad", "", [], false],
	["scott", "rifle slung (back)", "walk", 0.30, "neutral", "", ["rifle", "sidearm"], false],
	["scott", "rifle aimed (hand)", "rifle_run_aim", 0.40, "angry", "", ["rifle", "sidearm"], true],
	["scott", "helmet + draw", "rifle_draw", 0.90, "neutral", "", ["helmet", "rifle"], true],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1500, 760)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.21)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.45, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	for i in range(SHOTS.size()):
		var s: Array = SHOTS[i]
		var c: Node3D = VrmCharacterScript.create("res://models/vrm/%s.vrm" % s[0], s[0])
		c.set("auto_blink", false)
		c.position = Vector3(i * 1.15 - 2.85, 0.0, 0.0)
		c.rotation.y = 0.30
		world.add_child(c)
		c.call("play_clip", s[2], 0.0)
		var ap: AnimationPlayer = c.get_node_or_null("%s/AnimationPlayer" % s[0])
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * float(s[3]), true)
			ap.pause()
		if String(s[4]) != "":
			c.call("set_emotion", s[4], 1.0)
		if String(s[5]) != "":
			c.call("set_viseme", s[5], 1.0)
		for g in s[6]:
			c.call("attach_gear", g, s[7])
		c.call("_mix_face")
		var tag: Label3D = Label3D.new()
		tag.text = "%s\n%s" % [s[0], s[1]]
		tag.position = Vector3(c.position.x, 1.92, 0.0)
		tag.pixel_size = 0.0028
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.2, 5.8)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_showcase.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_showcase.png"))
	quit()
