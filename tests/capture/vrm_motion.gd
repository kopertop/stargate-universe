extends SceneTree

# THE retarget proof: VRM characters playing shared Mixamo clips. Eli walks +
# waves with a happy expression; Scott does rifle_walk. Each column samples a
# different phase of the clip. Spring bones live. Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/vrm_motion.gd

const BODY_LIB: String = "res://models/vrm/anim/crew_body.res"
# [vrm path, clip, expression, x]
const SHOTS: Array = [
	["res://models/vrm/eli.vrm", "body/walk", "happy", 0.30],
	["res://models/vrm/eli.vrm", "body/walk", "happy", 0.80],
	["res://models/vrm/scott.vrm", "body/rifle_walk", "", 0.30],
	["res://models/vrm/scott.vrm", "body/rifle_draw", "", 0.95],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.5, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	var lib: AnimationLibrary = load(BODY_LIB)
	for i in range(SHOTS.size()):
		var packed: PackedScene = load(SHOTS[i][0])
		if packed == null:
			continue
		var inst: Node3D = packed.instantiate()
		inst.position = Vector3(i * 1.3 - 2.0, 0.0, 0.0)
		inst.rotation.y = 0.55   # 3/4 turn so stride + rifle pose read
		world.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap == null:
			continue
		if not ap.has_animation_library("body"):
			ap.add_animation_library("body", lib)
		var clip: String = SHOTS[i][1]
		var phase: float = SHOTS[i][3]
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(ap.get_animation(clip).length * phase, true)
			ap.pause()
		else:
			print("[vrm_motion] clip %s missing" % clip)
		# Expression on a SECOND player would fight the body player; for the
		# still capture, bake the face by sampling the expression clip once.
		var expr: String = SHOTS[i][2]
		if expr != "":
			var expr_anim: Animation = ap.get_animation(expr)
			if expr_anim != null:
				_apply_blendshape_anim(inst, expr_anim, 0.95)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.15, 3.6)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://vrm_motion.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://vrm_motion.png"))
	quit()


# Manually apply an expression clip's blend-shape tracks at weight w (the
# clips are 1s ramps from 0 to full).
func _apply_blendshape_anim(inst: Node3D, anim: Animation, w: float) -> void:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_BLEND_SHAPE:
			continue
		var path: NodePath = anim.track_get_path(t)
		var node: Node = inst.get_node_or_null(NodePath(String(path).split(":")[0]))
		if node is MeshInstance3D:
			var mesh: MeshInstance3D = node
			var bs_name: String = String(path).split(":")[1]
			var idx: int = mesh.find_blend_shape_by_name(bs_name)
			if idx >= 0:
				mesh.set_blend_shape_value(idx, anim.blend_shape_track_interpolate(t, w))
