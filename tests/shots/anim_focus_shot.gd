extends SceneTree

# Render the suggested crew_body clips one-at-a-time, large and centered, on the
# Quaternius modular rig — its own camera/light so the pose reads clearly (the
# Animation Lab's interactive focus cam doesn't drive cleanly headless).
#   godot --quit-after 600 -s res://tests/shots/anim_focus_shot.gd ++ clips=repair,crouch_idle,hit,knockback
# Writes user://anim_<clip>.png per clip.

const CF: Script = preload("res://scripts/character_factory.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var clips: PackedStringArray = String(args.get("clips", "repair,crouch_idle,hit,knockback")).split(",")
	var prefix := String(args.get("out", "user://anim_"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "anim_focus_shot")

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.13, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.82)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.5
	world.add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.20)
	floor_mi.material_override = fmat
	world.add_child(floor_mi)

	# Modular actor at origin, turned to a 3/4 FRONT view toward the camera so the
	# pose reads (models export +Z forward; the camera sits at +Z).
	var holder := Node3D.new()
	holder.rotation.y = 0.5
	world.add_child(holder)
	var body: Node3D = CF.build_modular("Crewman")
	holder.add_child(body)
	# CRITICAL: an UNDRESSED modular body renders as just floating eyes — dressing
	# attaches the body/skin/clothing meshes. (Same call the gate-room crew use.)
	CF.dress_modular(body, "Crewman", CF.CTX_SHIP)

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.global_position = Vector3(0.6, 1.0, 3.0)
	cam.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	cam.make_current()

	# Let the body's _ready build its skeleton + load the clip library.
	for i in 25:
		await process_frame

	for clip in clips:
		var c := String(clip).strip_edges()
		if body.has_method("play_clip_looped"):
			body.call("play_clip_looped", c)
		elif body.has_method("play_clip"):
			body.call("play_clip", c)
		for i in 40:
			await process_frame
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(prefix + c + ".png")
		print("SHOT ", prefix, c, ".png")
	quit(0)
