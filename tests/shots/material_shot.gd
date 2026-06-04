extends SceneTree

# Material preview bench for the Ancient-metal shader (#30). Builds a neutral
# studio scene (3-point light, grey env, SSR/SSAO/glow) and shows the material on
# a sphere + a wall slab + a console-ish cylinder — the same surfaces the concept
# sheet (design/concept-art/materials/ancient-metal-pbr-sheet.png) previews it on.
# Run WITHOUT --headless so a real frame renders:
#   godot --quit-after 200 -s res://tests/shots/material_shot.gd ++ out=user://mat.png
#
# Builds the material IN CODE from ancient_metal.gdshader so we preview the BASE
# look (neutral steel, no seam emission), independent of the gate's tinted .tres.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Dictionary = _parse_args()
	var out_path: String = String(args.get("out", "user://mat.png"))

	# --- studio environment -------------------------------------------------
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	# A studio SKY so the metal has something to REFLECT (a metallic surface in a
	# black void renders black). Soft blue-grey gradient = neutral product-shot.
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.48, 0.60)
	sky_mat.sky_horizon_color = Color(0.62, 0.66, 0.72)
	sky_mat.ground_bottom_color = Color(0.20, 0.21, 0.24)
	sky_mat.ground_horizon_color = Color(0.40, 0.43, 0.48)
	sky_mat.sky_energy_multiplier = 1.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ssr_enabled = true
	env.ssao_enabled = true
	env.ssao_intensity = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	we.environment = env
	root.add_child(we)

	# --- 3-point lighting ---------------------------------------------------
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -125.0, 0.0)
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	root.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, 55.0, 0.0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(fill)

	# --- material (built in code = the neutral BASE look) -------------------
	var mat: ShaderMaterial = _make_material(args)

	# --- preview meshes -----------------------------------------------------
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	_add_mesh(sphere, mat, Vector3(-2.4, 0.0, 0.0))

	var wall: BoxMesh = BoxMesh.new()
	wall.size = Vector3(2.0, 2.0, 0.4)
	_add_mesh(wall, mat, Vector3(0.5, 0.0, 0.0))

	var col: CylinderMesh = CylinderMesh.new()
	col.top_radius = 0.85
	col.bottom_radius = 0.95
	col.height = 2.0
	col.radial_segments = 64
	_add_mesh(col, mat, Vector3(3.3, 0.0, 0.0))

	# --- camera -------------------------------------------------------------
	var cam: Camera3D = Camera3D.new()
	cam.fov = float(args.get("fov", "46"))
	root.add_child(cam)
	cam.global_position = _v3(String(args.get("cam_pos", "0.4,0.9,6.2")))
	cam.look_at(_v3(String(args.get("cam_look", "0.4,0.0,0.0"))), Vector3.UP)
	cam.current = true

	for i in int(args.get("wait", "30")):
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	print("SHOT ", out_path, " (save err=", img.save_png(out_path), ")")
	quit(0)

func _make_material(args: Dictionary) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://shaders/ancient_metal.gdshader")
	m.set_shader_parameter("detail_normal", load("res://textures/ancient-metal/detail_normal.tres"))
	m.set_shader_parameter("detail_rough", load("res://textures/ancient-metal/detail_rough.tres"))
	# Neutral steel base (Ancient-metal): cool dark blue-grey, no seam emission.
	m.set_shader_parameter("albedo_tint", Color(0.24, 0.26, 0.30, 1.0))
	m.set_shader_parameter("metallic", 0.82)
	m.set_shader_parameter("roughness_base", 0.44)
	m.set_shader_parameter("panel_scale", 0.6)
	return m

func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)

func _v3(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.ZERO

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		var eq: int = s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
