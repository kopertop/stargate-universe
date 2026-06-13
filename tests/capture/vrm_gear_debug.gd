extends SceneTree

# VRM gear-snap tuning: one character, front/back/side columns, chosen state,
# pose frozen mid-clip so mounts read against real anatomy. Prints gear world
# positions. Run NON-headless:
#   VRMC=scott CLIP=walk AIM=0 GEAR="rifle,sidearm,helmet" godot --quit-after 900 \
#     -s res://tests/capture/vrm_gear_debug.gd

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stem: String = OS.get_environment("VRMC")
	if stem == "":
		stem = "scott"
	var clip: String = OS.get_environment("CLIP")
	if clip == "":
		clip = "walk"
	var aimed: bool = OS.get_environment("AIM") == "1"
	var gear: PackedStringArray = OS.get_environment("GEAR").split(",", false)
	if gear.is_empty():
		gear = PackedStringArray(["rifle", "sidearm"])

	root.size = Vector2i(1280, 800)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.32, 0.36)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.2
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, -0.5, 0.0)
	world.add_child(sun)

	var angles: Array = [["front", 0.0], ["back", PI], ["side", PI * 0.5]]
	var first: Node3D = null
	for i in range(angles.size()):
		var c: Node3D = VrmCharacterScript.create("res://models/vrm/%s.vrm" % stem, stem)
		c.set("auto_blink", false)
		c.position = Vector3(i * 1.5 - 1.5, 0.0, 0.0)
		c.rotation.y = angles[i][1]
		world.add_child(c)
		c.call("play_clip", clip, 0.0)
		var ap: AnimationPlayer = c.get_node_or_null("%s/AnimationPlayer" % stem)
		if ap != null and ap.current_animation != "":
			ap.seek(ap.current_animation_length * 0.3, true)
			ap.pause()
		var primary: String = "rifle" if gear.has("rifle") else ("sidearm" if gear.has("sidearm") else "")
		for g in gear:
			c.call("attach_gear", g, aimed and String(g) == primary)
		if first == null:
			first = c
		var tag: Label3D = Label3D.new()
		tag.text = angles[i][0]
		tag.position = Vector3(c.position.x, 1.95, 0.0)
		tag.pixel_size = 0.0035
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.15, 3.8)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(24):
		await process_frame
	await RenderingServer.frame_post_draw

	print("[snap] %s clip=%s aim=%s" % [stem, clip, aimed])
	var skel: Skeleton3D = first.call("skeleton")
	if skel != null:
		for ba in skel.get_children():
			if ba is BoneAttachment3D:
				for g in ba.get_children():
					if g is Node3D:
						print("  %-8s on '%s' world=%s" % [g.name, (ba as BoneAttachment3D).bone_name, (g as Node3D).global_position])

	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_gear.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_gear.png"))
	quit()
