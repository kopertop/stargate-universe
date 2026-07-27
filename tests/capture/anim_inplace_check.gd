extends SceneTree

# In-place verification: actors frozen at four phases of a locomotion clip,
# each standing on a marker disc at its own origin. With root drift removed
# they stay centered on their discs at every phase; with Mixamo root motion
# they'd slide off (the "walks out of frame" bug). Side view so the travel
# axis (Z) reads horizontally. Run NON-headless:
#   CLIP=walk godot --quit-after 900 -s res://tests/capture/anim_inplace_check.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
const PHASES: Array = [0.05, 0.35, 0.65, 0.95]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var clip: String = OS.get_environment("CLIP")
	if clip == "":
		clip = "walk"
	root.size = Vector2i(1380, 760)
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

	for i in range(PHASES.size()):
		var x: float = i * 1.4 - 2.1
		# Origin marker disc — the actor must stay centered on it.
		var disc: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.35
		cyl.height = 0.02
		disc.mesh = cyl
		disc.position = Vector3(x, 0.01, 0.0)
		var dmat: StandardMaterial3D = StandardMaterial3D.new()
		dmat.albedo_color = Color(0.85, 0.55, 0.15)
		disc.material_override = dmat
		world.add_child(disc)

		var c: Node3D = VrmCharacterScript.create("res://models/vrm/scott.vrm", "scott")
		c.set("auto_blink", false)
		c.position = Vector3(x, 0.0, 0.0)
		c.rotation.y = PI * 0.5   # travel axis across the screen
		world.add_child(c)
		c.call("play_clip", clip, 0.0)
		c.call("attach_gear", "rifle", clip.begins_with("rifle_aim"))
		var ap: AnimationPlayer = c.get_node_or_null("scott/AnimationPlayer")
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * float(PHASES[i]), true)
			ap.pause()
		var tag: Label3D = Label3D.new()
		tag.text = "%s @ %d%%" % [clip, int(PHASES[i] * 100)]
		tag.position = Vector3(x, 2.0, 0.0)
		tag.pixel_size = 0.0030
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 44.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.3, 4.6)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var out: String = "user://anim_inplace_%s.png" % clip
	img.save_png(out)
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path(out))
	quit()
