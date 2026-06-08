extends Node3D

# Hero gate-room — a CINEMATIC beauty-shot scene, NOT a gameplay scene. Built
# procedurally toward design/concept-art/gate-room/target/gateroom-hero-target.png:
# a dark ribbed cathedral, a symmetric hall converging on an active Stargate whose
# blue vortex is the only real light source, console banks flanking the foreground,
# concentric ceiling rings with volumetric spot shafts, and a wet reflective floor.
#
# This scene is the iteration surface for the Karpathy-style self-improvement loop
# (tools/gate_hero_render.sh + the gate-room-hero workflow). Everything the loop
# tunes lives in the typed CONFIG consts below or in the small build_* helpers —
# keep it parametric (one value per line so edits stay surgical).
#
# No HUD, no NPCs, no autoload coupling: a fixed hero Camera3D frames the gate
# head-on so renders are directly comparable to the concept frame.

const HERO_PORTAL_SHADER: Shader = preload("res://shaders/hero_portal.gdshader")

# --- CONFIG (the loop edits these) -----------------------------------------
# Hall — long box, camera at -Z looking toward the gate at +Z.
const HALL_HALF_WIDTH: float = 11.0
const HALL_LENGTH: float = 38.0
const CEILING_HEIGHT: float = 15.0
# Gate
const GATE_RADIUS: float = 4.2
const GATE_TUBE: float = 0.9
const GATE_CENTER_Y: float = 5.6
const GATE_Z: float = 13.5
const CHEVRON_COUNT: int = 9
# Camera (concept: low, centred, gate ~45% up the frame)
const CAM_POS: Vector3 = Vector3(0.0, 2.4, -17.5)
const CAM_LOOK_Y: float = 5.2
const CAM_FOV: float = 52.0
# Lighting
const PORTAL_LIGHT_ENERGY: float = 14.0
const PORTAL_LIGHT_COLOR: Color = Color(0.45, 0.68, 1.0)
const SPOT_ENERGY: float = 22.0
const SPOT_COLOR: Color = Color(0.7, 0.82, 1.0)
const AMBIENT_ENERGY: float = 0.015
# Materials
const METAL_COLOR: Color = Color(0.05, 0.06, 0.08)
const METAL_ROUGHNESS: float = 0.42
const METAL_METALLIC: float = 0.85
const FLOOR_ROUGHNESS: float = 0.18
const SCREEN_COLOR: Color = Color(0.25, 0.55, 1.0)
const SCREEN_ENERGY: float = 2.2
# Fog
const FOG_DENSITY: float = 0.004

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_console_banks()
	_build_dais()
	_build_gate()
	_build_lights()
	_build_camera()

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
func _metal(rough: float = -1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = METAL_COLOR
	m.metallic = METAL_METALLIC
	m.roughness = METAL_ROUGHNESS if rough < 0.0 else rough
	m.metallic_specular = 0.5
	return m

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
	mi.rotation.y = rot_y
	return mi

# ---------------------------------------------------------------------------
# Environment — dark, glow, SSR floor reflections, volumetric fog.
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.42)
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 8.0
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.glow_strength = 1.0
	env.set("glow_levels/3", 0.6)
	env.set("glow_levels/4", 0.8)
	env.set("glow_levels/5", 0.5)
	env.glow_hdr_threshold = 0.85
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = FOG_DENSITY
	env.volumetric_fog_albedo = Color(0.32, 0.4, 0.58)
	env.volumetric_fog_emission = Color(0.004, 0.01, 0.03)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.42
	env.adjustment_saturation = 0.78
	env.adjustment_brightness = 0.92
	we.environment = env
	add_child(we)

# ---------------------------------------------------------------------------
# Floor — wet reflective grid plates.
# ---------------------------------------------------------------------------
func _build_floor() -> void:
	var mat := _metal(FLOOR_ROUGHNESS)
	mat.metallic = 0.7
	var floor := _box(
		Vector3(HALL_HALF_WIDTH * 2.0 + 6.0, 0.4, HALL_LENGTH + 8.0),
		Vector3(0.0, -0.2, (GATE_Z - CAM_POS.z) * 0.2),
		mat)
	floor.name = "Floor"
	# Grid plate seams — thin recessed lines for the converging-plate look.
	var seam_mat := _metal(0.6)
	seam_mat.albedo_color = Color(0.02, 0.025, 0.035)
	var span_z: int = int(HALL_LENGTH / 3.0)
	for i in span_z:
		var z: float = -HALL_LENGTH * 0.5 + float(i) * 3.0
		_box(Vector3(HALL_HALF_WIDTH * 2.0, 0.02, 0.12), Vector3(0.0, 0.01, z), seam_mat)
	var span_x: int = int(HALL_HALF_WIDTH * 2.0 / 3.0)
	for j in span_x + 1:
		var x: float = -HALL_HALF_WIDTH + float(j) * 3.0
		_box(Vector3(0.12, 0.02, HALL_LENGTH), Vector3(x, 0.01, 0.0), seam_mat)

# ---------------------------------------------------------------------------
# Walls — tall ribbed dark panels both sides + back wall.
# ---------------------------------------------------------------------------
func _build_walls() -> void:
	var mat := _metal()
	var h: float = CEILING_HEIGHT
	var hw: float = HALL_HALF_WIDTH
	var L: float = HALL_LENGTH
	for sgn: float in [-1.0, 1.0]:
		_box(Vector3(0.6, h, L), Vector3(sgn * hw, h * 0.5, 0.0), mat)
		var ribs: int = int(L / 4.0)
		for i in ribs:
			var z: float = -L * 0.5 + 2.0 + float(i) * 4.0
			_box(Vector3(0.9, h, 0.7), Vector3(sgn * (hw - 0.4), h * 0.5, z), _metal(0.35))
			_box(Vector3(0.3, h * 0.5, 0.12), Vector3(sgn * (hw - 0.85), h * 0.55, z),
				_emissive(Color(0.15, 0.35, 0.7), 0.9))
	# Back wall behind the gate
	_box(Vector3(hw * 2.0, h, 0.6), Vector3(0.0, h * 0.5, GATE_Z + 3.5), mat)

# ---------------------------------------------------------------------------
# Ceiling — flat slab + concentric rings (dome) over the gate.
# ---------------------------------------------------------------------------
func _build_ceiling() -> void:
	var h: float = CEILING_HEIGHT
	_box(Vector3(HALL_HALF_WIDTH * 2.0 + 4.0, 0.6, HALL_LENGTH + 4.0),
		Vector3(0.0, h + 0.3, 0.0), _metal(0.5))
	var ring_mat := _metal(0.4)
	for i in range(4):
		var rad: float = 3.0 + float(i) * 2.2
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rad
		tm.outer_radius = rad + 0.5
		mi.mesh = tm
		mi.material_override = ring_mat
		add_child(mi)
		mi.position = Vector3(0.0, h - 0.1 - float(i) * 0.15, GATE_Z * 0.2)
		var em := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		tm2.inner_radius = rad + 0.15
		tm2.outer_radius = rad + 0.35
		em.mesh = tm2
		em.material_override = _emissive(Color(0.2, 0.4, 0.8), 0.6)
		add_child(em)
		em.position = Vector3(0.0, h - 0.2 - float(i) * 0.15, GATE_Z * 0.2)

# ---------------------------------------------------------------------------
# Console banks — angled desks with glowing screens, foreground both sides.
# ---------------------------------------------------------------------------
func _build_console_banks() -> void:
	var desk_mat := _metal(0.45)
	var screen_mat := _emissive(SCREEN_COLOR, SCREEN_ENERGY)
	for sgn: float in [-1.0, 1.0]:
		for i in range(4):
			var z: float = -HALL_LENGTH * 0.4 + float(i) * 3.2
			var x: float = sgn * (HALL_HALF_WIDTH - 2.2)
			var yaw: float = -sgn * 0.35
			_box(Vector3(2.4, 1.1, 1.4), Vector3(x, 0.55, z), desk_mat, yaw)
			var scr := _box(Vector3(2.0, 0.9, 0.08), Vector3(x, 1.5, z), screen_mat, yaw)
			scr.rotation.x = -0.5

# ---------------------------------------------------------------------------
# Dais — railed platform + short staircase leading up to the gate.
# ---------------------------------------------------------------------------
func _build_dais() -> void:
	var mat := _metal(0.45)
	var dz: float = GATE_Z - 2.5
	_box(Vector3(12.0, 0.8, 6.0), Vector3(0.0, 0.4, dz), mat)
	for i in range(4):
		var w: float = 6.0 - float(i) * 0.4
		var step := _box(Vector3(w, 0.25, 0.8),
			Vector3(0.0, 0.7 - float(i) * 0.18, dz - 3.0 - float(i) * 0.8), mat)
		step.name = "Step%d" % i
	var rail_mat := _metal(0.3)
	for j in range(9):
		var rx: float = -5.0 + float(j) * 1.25
		_box(Vector3(0.1, 1.0, 0.1), Vector3(rx, 1.3, dz - 3.2), rail_mat)
	_box(Vector3(10.0, 0.1, 0.1), Vector3(0.0, 1.75, dz - 3.2), rail_mat)

# ---------------------------------------------------------------------------
# Gate — dark metal ring, emissive chevron triangles, blue vortex puddle.
# ---------------------------------------------------------------------------
func _build_gate() -> void:
	var center := Vector3(0.0, GATE_CENTER_Y, GATE_Z)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = GATE_RADIUS - GATE_TUBE
	tm.outer_radius = GATE_RADIUS + GATE_TUBE
	tm.rings = 48
	ring.mesh = tm
	ring.material_override = _metal(0.3)
	add_child(ring)
	ring.position = center
	ring.rotation.x = PI * 0.5
	ring.name = "GateRing"

	var chev_mat := _emissive(Color(0.7, 0.85, 1.0), 3.0)
	var n: int = CHEVRON_COUNT
	for i in n:
		var ang: float = TAU * float(i) / float(n) + PI * 0.5
		var px: float = cos(ang) * (GATE_RADIUS - GATE_TUBE - 0.3)
		var py: float = sin(ang) * (GATE_RADIUS - GATE_TUBE - 0.3)
		var chev := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.9, 0.7, 0.25)
		chev.mesh = pm
		chev.material_override = chev_mat
		add_child(chev)
		chev.position = center + Vector3(px, py, 0.0)
		chev.rotation.z = ang - PI * 0.5

	var puddle := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var d: float = (GATE_RADIUS - GATE_TUBE) * 2.0
	qm.size = Vector2(d, d)
	puddle.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = HERO_PORTAL_SHADER
	puddle.material_override = sm
	add_child(puddle)
	puddle.position = center + Vector3(0.0, 0.0, -0.05)
	puddle.name = "PortalPuddle"

# ---------------------------------------------------------------------------
# Lights — portal omni, ceiling spot shafts.
# ---------------------------------------------------------------------------
func _build_lights() -> void:
	var center := Vector3(0.0, GATE_CENTER_Y, GATE_Z)
	var portal_light := OmniLight3D.new()
	portal_light.light_color = PORTAL_LIGHT_COLOR
	portal_light.light_energy = PORTAL_LIGHT_ENERGY
	portal_light.omni_range = 30.0
	portal_light.light_volumetric_fog_energy = 2.0
	add_child(portal_light)
	portal_light.position = center + Vector3(0.0, 0.0, -1.0)

	for i in range(5):
		var sx: float = -8.0 + float(i) * 4.0
		var spot := SpotLight3D.new()
		spot.light_color = SPOT_COLOR
		spot.light_energy = SPOT_ENERGY
		spot.spot_range = 20.0
		spot.spot_angle = 22.0
		spot.light_volumetric_fog_energy = 3.0
		add_child(spot)
		spot.position = Vector3(sx, CEILING_HEIGHT - 1.0, -2.0 + float(i % 2) * 4.0)
		spot.rotation.x = -PI * 0.5

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	add_child(cam)
	cam.position = CAM_POS
	cam.look_at(Vector3(0.0, CAM_LOOK_Y, GATE_Z), Vector3.UP)
	cam.current = true
	cam.name = "HeroCamera"
