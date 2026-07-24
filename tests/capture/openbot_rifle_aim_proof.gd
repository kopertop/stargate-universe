extends SceneTree

# Proof: Mixamo Swat + Rifle Idle (finger-bone host) from the documented pipeline.
# Built by tools/blender_mixamo_rifle_idle.py → Swat_rifle_idle.glb
#
#   Godot --path . --quit-after 12000 -s res://tests/capture/openbot_rifle_aim_proof.gd

const OUT: String = "user://mint_rifle_aim/swat_rifle_idle_godot.png"
const SWAT_AIM: String = "res://models/mixamo_openbot/Swat_rifle_idle.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== openbot_rifle_aim_proof (Swat Rifle Idle) ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mint_rifle_aim"))
	var world := Node3D.new()
	root.add_child(world)
	_lights(world)

	if not ResourceLoader.exists(SWAT_AIM):
		push_error("Missing %s — run tools/blender_mixamo_rifle_idle.py first" % SWAT_AIM)
		quit(1)
		return

	var packed: PackedScene = load(SWAT_AIM) as PackedScene
	var bot: Node3D = packed.instantiate() as Node3D
	bot.rotation.y = PI
	world.add_child(bot)
	await process_frame
	await process_frame

	var anim: AnimationPlayer = _find_anim(bot)
	var skel: Skeleton3D = _find_skel(bot)
	print("skel bones=", skel.get_bone_count() if skel else -1)
	if anim:
		var names: PackedStringArray = anim.get_animation_list()
		print("anims=", names)
		if names.size() > 0:
			anim.play(names[0])
			anim.seek(0.5, true)
	else:
		print("WARN: no AnimationPlayer — static pose only")

	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.position = Vector3(1.2, 1.15, 2.1)
	cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	cam.current = true

	await _settle(16)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT)
	var dst := ProjectSettings.globalize_path("res://screenshots/result/mint_rifle_aim/swat_rifle_idle_godot.png")
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(OUT), dst)
	print("[copy] ", dst)
	print("=== openbot_rifle_aim_proof done ===")
	quit(0)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f: AnimationPlayer = _find_anim(c)
		if f != null:
			return f
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f: Skeleton3D = _find_skel(c)
		if f != null:
			return f
	return null


func _lights(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var env_n := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.55
	env_n.environment = env
	world.add_child(env_n)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mi.mesh = plane
	world.add_child(floor_mi)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
