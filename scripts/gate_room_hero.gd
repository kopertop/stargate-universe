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
# Gate — large THICK ring that nearly fills the frame in the concept.
const GATE_RADIUS: float = 6.4
const GATE_TUBE: float = 1.25
const GATE_CENTER_Y: float = 6.6
const GATE_Z: float = 13.5
const CHEVRON_COUNT: int = 9
# Camera (concept: low, centred, gate large and ~45-50% up the frame). Pulled
# in closer so the ring + vortex dominate the shot rather than floating small.
const CAM_POS: Vector3 = Vector3(0.0, 3.0, -11.5)
const CAM_LOOK_Y: float = 6.2
const CAM_FOV: float = 54.0
# Lighting
const PORTAL_LIGHT_ENERGY: float = 14.0
const PORTAL_LIGHT_COLOR: Color = Color(0.45, 0.68, 1.0)
const SPOT_ENERGY: float = 30.0
const SPOT_COLOR: Color = Color(0.7, 0.82, 1.0)
const AMBIENT_ENERGY: float = 0.05
# Cold rim/fill so the dark-metal architecture (walls, dome, buttresses) reads as
# textured detail instead of crushing to a flat black void. Low energy, steep angle.
const RIM_ENERGY: float = 0.55
const RIM_COLOR: Color = Color(0.4, 0.55, 0.85)
const FILL_ENERGY: float = 0.22
const FILL_COLOR: Color = Color(0.32, 0.42, 0.62)
# Materials
const METAL_COLOR: Color = Color(0.05, 0.06, 0.08)
const METAL_ROUGHNESS: float = 0.42
const METAL_METALLIC: float = 0.85
const FLOOR_ROUGHNESS: float = 0.28
const SCREEN_COLOR: Color = Color(0.22, 0.45, 0.85)
const SCREEN_ENERGY: float = 0.85
# Fog
const FOG_DENSITY: float = 0.0018

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_console_banks()
	_build_buttresses()
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
	env.ambient_light_color = Color(0.28, 0.31, 0.38)
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
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
	env.volumetric_fog_albedo = Color(0.42, 0.46, 0.55)
	env.volumetric_fog_emission = Color(0.004, 0.01, 0.03)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.32
	env.adjustment_saturation = 0.6
	env.adjustment_brightness = 0.94
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
			# Thin recessed window-slit, faint cold glow — NOT a bright blue strip.
			_box(Vector3(0.12, h * 0.32, 0.1), Vector3(sgn * (hw - 0.85), h * 0.6, z),
				_emissive(Color(0.22, 0.4, 0.72), 0.32))
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
	var desk_mat := _metal(0.4)
	var screen_mat := _emissive(SCREEN_COLOR, SCREEN_ENERGY)
	# Two angled banks per side, marching from the foreground (near camera) toward
	# the gate. Pulled close to the camera and toward the room centre so they read
	# as the target's flanking console rows rather than vanishing into the dark.
	for sgn: float in [-1.0, 1.0]:
		for i in range(5):
			var z: float = CAM_POS.z + 4.0 + float(i) * 3.4
			var x: float = sgn * (HALL_HALF_WIDTH - 3.6)
			var yaw: float = -sgn * 0.5
			# Desk body
			_box(Vector3(2.8, 1.0, 1.5), Vector3(x, 0.5, z), desk_mat, yaw)
			# Raked screen panel facing the room centre, lifted to chest height
			var scr := _box(Vector3(2.4, 1.0, 0.1), Vector3(x, 1.45, z), screen_mat, yaw)
			scr.rotation.x = -0.45
			# Side-by-side mini screens to break the panel into many small displays
			var mini_mat := _emissive(Color(0.3, 0.6, 1.0), SCREEN_ENERGY * 0.7)
			for k in range(3):
				var mz: float = z - 0.5 + float(k) * 0.5
				var ms := _box(Vector3(0.55, 0.45, 0.06), Vector3(x, 1.5, mz), mini_mat, yaw)
				ms.rotation.x = -0.45

func _build_buttresses() -> void:
	# Large diagonal buttress beams flanking the gate — the dominant foreground
	# architecture in the concept frame. Two angled beams per side rise from the
	# dais floor outward toward the ceiling, framing the ring in a chevron of steel.
	var mat := _metal(0.38)
	var trim := _emissive(Color(0.18, 0.4, 0.85), 1.1)
	var bz: float = GATE_Z - 1.0
	for sgn: float in [-1.0, 1.0]:
		# Primary heavy buttress: leans inward over the gate shoulders, hugging the
		# larger ring so it reads as solid masonry framing the portal.
		var beam := _box(Vector3(2.8, 18.0, 3.0), Vector3(sgn * 9.0, 8.5, bz), mat)
		beam.rotation.z = sgn * 0.46
		beam.name = "Buttress%d" % int(sgn)
		# Glowing seam running up the inner face of the beam.
		var seam := _box(Vector3(0.28, 15.0, 0.28), Vector3(sgn * 7.4, 8.0, bz - 1.3), trim)
		seam.rotation.z = sgn * 0.46
		# Secondary outboard buttress, steeper, taller — adds depth layering.
		var beam2 := _box(Vector3(2.0, 17.0, 2.2), Vector3(sgn * 11.6, 9.0, bz + 0.4), mat)
		beam2.rotation.z = sgn * 0.24
		# Base block anchoring the beams to the platform.
		_box(Vector3(3.8, 2.4, 3.8), Vector3(sgn * 8.2, 1.2, bz), mat)

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
	# THICK segmented metal ring built from many short trapezoid blocks around the
	# circle so it reads as a heavy industrial gate, not a thin glowing torus.
	var ring_mat := _metal(0.34)
	ring_mat.albedo_color = Color(0.07, 0.08, 0.10)
	var seg_mat := _metal(0.28)
	seg_mat.albedo_color = Color(0.045, 0.05, 0.065)
	var segs: int = 36
	var ring_mid: float = GATE_RADIUS
	for i in segs:
		var ang: float = TAU * float(i) / float(segs)
		var px: float = cos(ang) * ring_mid
		var py: float = sin(ang) * ring_mid
		# Block spanning the tube depth; alternate slightly darker for plate banding.
		var blk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var seg_w: float = (TAU * ring_mid / float(segs)) * 1.08
		bm.size = Vector3(seg_w, GATE_TUBE * 2.0, GATE_TUBE * 1.6)
		blk.mesh = bm
		blk.material_override = seg_mat if i % 2 == 0 else ring_mat
		add_child(blk)
		blk.position = center + Vector3(px, py, 0.0)
		blk.rotation.z = ang + PI * 0.5
	# Outer + inner trim rings frame the segments.
	for rr: float in [GATE_RADIUS - GATE_TUBE, GATE_RADIUS + GATE_TUBE]:
		var trim := MeshInstance3D.new()
		var ttm := TorusMesh.new()
		ttm.inner_radius = rr - 0.12
		ttm.outer_radius = rr + 0.12
		ttm.rings = 48
		trim.mesh = ttm
		trim.material_override = _metal(0.25)
		add_child(trim)
		trim.position = center
		trim.rotation.x = PI * 0.5
	var ring_holder := Node3D.new()
	ring_holder.name = "GateRing"
	add_child(ring_holder)
	ring_holder.position = center

	# Inward-pointing TRIANGULAR chevrons: dark metal wedges with a faint inner glow
	# strip, recessed into the inner edge — NOT bright light studs.
	var n: int = CHEVRON_COUNT
	for i in n:
		var ang: float = TAU * float(i) / float(n) + PI * 0.5
		var px: float = cos(ang) * (GATE_RADIUS - GATE_TUBE - 0.15)
		var py: float = sin(ang) * (GATE_RADIUS - GATE_TUBE - 0.15)
		var chev := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(1.1, 0.85, 0.4)
		chev.mesh = pm
		chev.material_override = _metal(0.3)
		add_child(chev)
		chev.position = center + Vector3(px, py, 0.05)
		chev.rotation.z = ang - PI * 0.5
		# Thin faint glow strip up the chevron centre (subtle accent only).
		var glow := MeshInstance3D.new()
		var gpm := PrismMesh.new()
		gpm.size = Vector3(0.32, 0.55, 0.12)
		glow.mesh = gpm
		glow.material_override = _emissive(Color(0.45, 0.65, 1.0), 1.4)
		add_child(glow)
		glow.position = center + Vector3(px, py, -0.12)
		glow.rotation.z = ang - PI * 0.5

	# Vortex puddle — sized to nearly FILL the inner aperture of the ring.
	var puddle := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var d: float = (GATE_RADIUS - GATE_TUBE) * 2.05
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
	portal_light.omni_range = 18.0
	portal_light.light_volumetric_fog_energy = 1.0
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

	# Cool RIM light raking down the hall from behind/above the gate — picks out the
	# top edges of the ribbed walls, the ceiling-dome rings and the buttress beams so
	# the architecture reads as dark textured metal instead of a black void.
	var rim := DirectionalLight3D.new()
	rim.light_color = RIM_COLOR
	rim.light_energy = RIM_ENERGY
	rim.shadow_enabled = false
	add_child(rim)
	rim.position = Vector3(0.0, CEILING_HEIGHT, GATE_Z)
	rim.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(180.0), 0.0)
	# Soft frontal FILL from the camera side — lifts the near walls / console banks and
	# the dais out of pure black without washing the scene into a flat blue field.
	var fill := DirectionalLight3D.new()
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	add_child(fill)
	fill.position = Vector3(0.0, 6.0, CAM_POS.z)
	fill.rotation = Vector3(deg_to_rad(-18.0), 0.0, 0.0)

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	add_child(cam)
	cam.position = CAM_POS
	cam.look_at(Vector3(0.0, CAM_LOOK_Y, GATE_Z), Vector3.UP)
	cam.current = true
	cam.name = "HeroCamera"
