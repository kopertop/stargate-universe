extends Node3D

# Hero-prop layer for the hull breach compartment. Sells the dramatic beat:
# a damaged shuttlecraft has impacted the north wall, ripped a jagged hole in
# Destiny's hull, and is venting atmosphere into vacuum. The player must
# see the broken shuttlecraft (the cause) and the rupture (the effect)
# clearly enough that "seal the breach" reads instantly.
#
# Visual layers, north to south:
#   1. Vacuum void backdrop beyond the wall (deep black + tiny distant stars)
#   2. Jagged rupture in the north wall — twisted metal teeth ringing a hole
#   3. The broken shuttlecraft, half-wedged through the rupture, leaking
#      sparks from torn fuselage panels
#   4. Debris field on the floor — scorched plating, snapped hull panels
#   5. Warning floor stripes leading the eye to the seal switch
#   6. An emergency blast shutter (hidden) ready to slam down when sealed
#
# The script also exposes the shutter via a group so hull_breach.gd can show
# it when the breach is sealed — providing visual feedback for the action.
#
# Room assumptions: 6 wide x 6 long, walls at x=±3 and z=±3, breach on the
# north wall (z=+3), seal switch at (-2.6, 1.4, 0), south door at z=-3.

const RUPTURE_CENTER: Vector3 = Vector3(0.0, 1.8, 2.95)
const RUPTURE_WIDTH: float = 2.6
const RUPTURE_HEIGHT: float = 2.2

func _ready() -> void:
	_build_void_backdrop()
	_build_distant_stars()
	_build_rupture_teeth()
	_build_broken_shuttlecraft()
	_build_debris_field()
	_build_warning_stripes()
	_build_emergency_shutter()
	_build_sparks_emitter()

# ----- vacuum void backdrop behind the rupture ----------------------------

func _build_void_backdrop() -> void:
	var void_mat: StandardMaterial3D = StandardMaterial3D.new()
	void_mat.albedo_color = Color(0.0, 0.0, 0.02, 1.0)
	void_mat.metallic = 0.0
	void_mat.roughness = 1.0
	# The void plane sits a bit beyond the wall, larger than the rupture so
	# the player sees pure black through the hole no matter where they stand.
	_add_box(Vector3(0.0, 1.8, 3.6), Vector3(4.0, 3.6, 0.1), void_mat)

func _build_distant_stars() -> void:
	var star_mat: StandardMaterial3D = StandardMaterial3D.new()
	star_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 0.95, 0.85, 1.0)
	star_mat.emission_energy_multiplier = 6.5
	var blue_star: StandardMaterial3D = StandardMaterial3D.new()
	blue_star.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	blue_star.emission_enabled = true
	blue_star.emission = Color(0.55, 0.78, 1.0, 1.0)
	blue_star.emission_energy_multiplier = 5.5
	var entries: Array = [
		[Vector3(-0.8, 2.6, 3.45), 0.025, star_mat],
		[Vector3(0.5, 2.2, 3.45), 0.030, blue_star],
		[Vector3(1.0, 2.9, 3.45), 0.022, star_mat],
		[Vector3(-0.4, 1.4, 3.45), 0.028, star_mat],
		[Vector3(0.9, 1.6, 3.45), 0.020, blue_star],
		[Vector3(-1.1, 2.0, 3.45), 0.024, star_mat],
	]
	for entry in entries:
		var pos: Vector3 = entry[0]
		var r: float = entry[1]
		var mat: StandardMaterial3D = entry[2]
		var star: MeshInstance3D = MeshInstance3D.new()
		var s_mesh: SphereMesh = SphereMesh.new()
		s_mesh.radius = r
		s_mesh.height = r * 2.0
		s_mesh.radial_segments = 6
		s_mesh.rings = 3
		star.mesh = s_mesh
		star.material_override = mat
		star.position = pos
		add_child(star)

# ----- jagged rupture teeth ringing the breach hole ------------------------

func _build_rupture_teeth() -> void:
	var torn_mat: StandardMaterial3D = StandardMaterial3D.new()
	torn_mat.albedo_color = Color(0.20, 0.18, 0.18, 1.0)
	torn_mat.metallic = 0.85
	torn_mat.roughness = 0.55
	var hot_mat: StandardMaterial3D = StandardMaterial3D.new()
	hot_mat.albedo_color = Color(0.45, 0.18, 0.08, 1.0)
	hot_mat.metallic = 0.40
	hot_mat.roughness = 0.45
	hot_mat.emission_enabled = true
	hot_mat.emission = Color(1.0, 0.40, 0.10, 1.0)
	hot_mat.emission_energy_multiplier = 4.0
	# The rupture is centered at z=+3 on the north wall, roughly 2.6m wide and
	# 2.2m tall. Build a ring of irregular jagged "teeth" boxes around the
	# perimeter; alternate hot/cool to suggest superheated edges.
	var wall_z: float = 2.95
	# Top rim — descending teeth.
	for i in range(6):
		var tx: float = -1.2 + i * 0.5 + randf_range(-0.05, 0.05)
		var th: float = randf_range(0.20, 0.45)
		var ty: float = 2.85 + th * 0.5 - 0.05
		var mat: StandardMaterial3D = hot_mat if i % 3 == 0 else torn_mat
		var tooth: MeshInstance3D = MeshInstance3D.new()
		var tmesh: BoxMesh = BoxMesh.new()
		tmesh.size = Vector3(0.18, th, 0.20)
		tooth.mesh = tmesh
		tooth.material_override = mat
		tooth.position = Vector3(tx, ty, wall_z)
		tooth.rotation_degrees = Vector3(randf_range(-15.0, 15.0), randf_range(-25.0, 25.0), randf_range(-20.0, 20.0))
		add_child(tooth)
	# Bottom rim — upward teeth.
	for i in range(6):
		var tx: float = -1.2 + i * 0.5 + randf_range(-0.05, 0.05)
		var th: float = randf_range(0.25, 0.50)
		var ty: float = 0.75 - th * 0.5 + 0.05
		var mat: StandardMaterial3D = hot_mat if i % 4 == 0 else torn_mat
		var tooth: MeshInstance3D = MeshInstance3D.new()
		var tmesh: BoxMesh = BoxMesh.new()
		tmesh.size = Vector3(0.18, th, 0.20)
		tooth.mesh = tmesh
		tooth.material_override = mat
		tooth.position = Vector3(tx, ty, wall_z)
		tooth.rotation_degrees = Vector3(randf_range(-15.0, 15.0), randf_range(-25.0, 25.0), randf_range(-20.0, 20.0))
		add_child(tooth)
	# Left rim.
	for i in range(5):
		var ty: float = 0.95 + i * 0.40 + randf_range(-0.05, 0.05)
		var tw: float = randf_range(0.22, 0.42)
		var tx: float = -1.45 - tw * 0.5 + 0.05
		var mat: StandardMaterial3D = hot_mat if i % 3 == 1 else torn_mat
		var tooth: MeshInstance3D = MeshInstance3D.new()
		var tmesh: BoxMesh = BoxMesh.new()
		tmesh.size = Vector3(tw, 0.20, 0.20)
		tooth.mesh = tmesh
		tooth.material_override = mat
		tooth.position = Vector3(tx, ty, wall_z)
		tooth.rotation_degrees = Vector3(randf_range(-15.0, 15.0), randf_range(-25.0, 25.0), randf_range(-20.0, 20.0))
		add_child(tooth)
	# Right rim.
	for i in range(5):
		var ty: float = 0.95 + i * 0.40 + randf_range(-0.05, 0.05)
		var tw: float = randf_range(0.22, 0.42)
		var tx: float = 1.45 + tw * 0.5 - 0.05
		var mat: StandardMaterial3D = hot_mat if i % 3 == 2 else torn_mat
		var tooth: MeshInstance3D = MeshInstance3D.new()
		var tmesh: BoxMesh = BoxMesh.new()
		tmesh.size = Vector3(tw, 0.20, 0.20)
		tooth.mesh = tmesh
		tooth.material_override = mat
		tooth.position = Vector3(tx, ty, wall_z)
		tooth.rotation_degrees = Vector3(randf_range(-15.0, 15.0), randf_range(-25.0, 25.0), randf_range(-20.0, 20.0))
		add_child(tooth)

# ----- the broken shuttlecraft itself, wedged into the breach --------------

func _build_broken_shuttlecraft() -> void:
	var hull_mat: StandardMaterial3D = StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.65, 0.62, 0.58, 1.0)
	hull_mat.metallic = 0.80
	hull_mat.roughness = 0.45
	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
	dark_mat.metallic = 0.70
	dark_mat.roughness = 0.40
	var window_mat: StandardMaterial3D = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.04, 0.08, 0.14, 1.0)
	window_mat.metallic = 0.0
	window_mat.roughness = 0.15
	window_mat.emission_enabled = true
	window_mat.emission = Color(0.20, 0.55, 0.85, 1.0)
	window_mat.emission_energy_multiplier = 0.8
	var damage_mat: StandardMaterial3D = StandardMaterial3D.new()
	damage_mat.albedo_color = Color(0.15, 0.10, 0.08, 1.0)
	damage_mat.metallic = 0.30
	damage_mat.roughness = 0.85
	# Shuttle body group — tilted to look "crashed through" the wall.
	var shuttle: Node3D = Node3D.new()
	shuttle.position = Vector3(0.5, 1.6, 2.4)
	shuttle.rotation_degrees = Vector3(8.0, -18.0, -12.0)
	add_child(shuttle)
	# Main fuselage — wide flattened box (a wedge-shaped shuttle).
	_add_box_to(shuttle, Vector3(0.0, 0.0, 0.0), Vector3(1.6, 0.75, 1.8), hull_mat)
	# Nose taper — front (the bit poking back into the room).
	_add_box_to(shuttle, Vector3(0.0, 0.0, -1.05), Vector3(1.0, 0.55, 0.55), hull_mat)
	# Cockpit window strip on top-front of the nose.
	_add_box_to(shuttle, Vector3(0.0, 0.30, -1.05), Vector3(0.85, 0.18, 0.50), window_mat)
	# Aft (the rear sticking through the wall void).
	_add_box_to(shuttle, Vector3(0.0, 0.0, 1.10), Vector3(1.3, 0.65, 0.5), dark_mat)
	# A broken-off wing dangling on the south (room-side) — torn jagged shape.
	_add_box_to(shuttle, Vector3(-0.95, -0.10, 0.20), Vector3(0.50, 0.18, 1.20), hull_mat)
	_add_box_to(shuttle, Vector3(-1.25, -0.25, 0.30), Vector3(0.30, 0.10, 0.40), damage_mat)
	# Right wing torn off entirely — show stub only.
	_add_box_to(shuttle, Vector3(0.85, -0.05, 0.10), Vector3(0.18, 0.18, 0.30), damage_mat)
	# Engine pod under the aft (singular, the other ripped off).
	_add_box_to(shuttle, Vector3(-0.55, -0.45, 0.85), Vector3(0.35, 0.30, 0.55), dark_mat)
	# Engine nozzle — dark cylinder.
	var nozzle: MeshInstance3D = MeshInstance3D.new()
	var nozzle_mesh: CylinderMesh = CylinderMesh.new()
	nozzle_mesh.top_radius = 0.16
	nozzle_mesh.bottom_radius = 0.14
	nozzle_mesh.height = 0.30
	nozzle.mesh = nozzle_mesh
	nozzle.material_override = dark_mat
	nozzle.position = Vector3(-0.55, -0.45, 1.20)
	nozzle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	shuttle.add_child(nozzle)
	# Visible scorch / blast damage panels on the underside.
	_add_box_to(shuttle, Vector3(0.20, -0.40, -0.40), Vector3(0.55, 0.05, 0.45), damage_mat)
	_add_box_to(shuttle, Vector3(-0.25, -0.40, 0.30), Vector3(0.45, 0.05, 0.55), damage_mat)
	# An angry red emergency strobe still active on the nose.
	var beacon_mat: StandardMaterial3D = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.55, 0.10, 0.08, 1.0)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.20, 0.10, 1.0)
	beacon_mat.emission_energy_multiplier = 5.0
	_add_box_to(shuttle, Vector3(0.0, 0.42, -1.10), Vector3(0.10, 0.10, 0.10), beacon_mat)

# ----- debris field of scorched plating on the floor -----------------------

func _build_debris_field() -> void:
	var debris_mat: StandardMaterial3D = StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
	debris_mat.metallic = 0.65
	debris_mat.roughness = 0.55
	var scorch_mat: StandardMaterial3D = StandardMaterial3D.new()
	scorch_mat.albedo_color = Color(0.10, 0.08, 0.06, 1.0)
	scorch_mat.metallic = 0.30
	scorch_mat.roughness = 0.90
	var hot_mat: StandardMaterial3D = StandardMaterial3D.new()
	hot_mat.albedo_color = Color(0.45, 0.20, 0.10, 1.0)
	hot_mat.emission_enabled = true
	hot_mat.emission = Color(1.0, 0.35, 0.10, 1.0)
	hot_mat.emission_energy_multiplier = 3.0
	# A long scorch-mark down the center of the floor.
	_add_box(Vector3(0.0, 0.025, 1.5), Vector3(1.6, 0.02, 2.8), scorch_mat)
	# Torn hull plates scattered around.
	var plates: Array = [
		[Vector3(-1.2, 0.1, 1.0), Vector3(0.6, 0.10, 0.4), Vector3(-5.0, 30.0, 15.0), debris_mat],
		[Vector3(1.0, 0.08, 0.5), Vector3(0.5, 0.08, 0.5), Vector3(8.0, -40.0, 0.0), debris_mat],
		[Vector3(-0.6, 0.15, 1.8), Vector3(0.7, 0.15, 0.3), Vector3(15.0, 10.0, -20.0), debris_mat],
		[Vector3(1.4, 0.05, 1.4), Vector3(0.4, 0.05, 0.6), Vector3(0.0, 60.0, 5.0), scorch_mat],
		[Vector3(-1.4, 0.12, 2.0), Vector3(0.5, 0.10, 0.35), Vector3(-10.0, -20.0, 25.0), debris_mat],
		[Vector3(0.7, 0.18, 1.9), Vector3(0.3, 0.18, 0.3), Vector3(20.0, 45.0, -15.0), debris_mat],
		[Vector3(-0.2, 0.04, 2.4), Vector3(0.7, 0.04, 0.4), Vector3(0.0, 0.0, 0.0), scorch_mat],
		# A glowing-hot fragment near the rupture.
		[Vector3(0.4, 0.10, 2.7), Vector3(0.25, 0.10, 0.20), Vector3(15.0, 30.0, 0.0), hot_mat],
		[Vector3(-0.9, 0.08, 2.6), Vector3(0.20, 0.08, 0.18), Vector3(-5.0, 0.0, 10.0), hot_mat],
	]
	for entry in plates:
		var pos: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var rot: Vector3 = entry[2]
		var mat: StandardMaterial3D = entry[3]
		var plate: MeshInstance3D = MeshInstance3D.new()
		var pmesh: BoxMesh = BoxMesh.new()
		pmesh.size = size
		plate.mesh = pmesh
		plate.material_override = mat
		plate.position = pos
		plate.rotation_degrees = rot
		add_child(plate)

# ----- yellow/black warning stripes leading to the seal switch -------------

func _build_warning_stripes() -> void:
	var yellow: StandardMaterial3D = StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.78, 0.15, 1.0)
	yellow.emission_enabled = true
	yellow.emission = Color(1.0, 0.80, 0.15, 1.0)
	yellow.emission_energy_multiplier = 2.0
	yellow.roughness = 0.60
	var black: StandardMaterial3D = StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.05, 1.0)
	black.roughness = 0.85
	# A box drawn around the seal switch on the west wall, x=-2.6.
	# Floor stripes guiding the eye from spawn to the switch.
	for i in range(5):
		var alt: bool = i % 2 == 0
		var mat: StandardMaterial3D = yellow if alt else black
		_add_box(Vector3(-1.8 + i * -0.20, 0.025, -0.5 + i * 0.2), Vector3(0.20, 0.025, 0.3), mat)
	# Hazard frame around the switch (highlights the actionable element).
	# Switch is at (-2.6, 1.4, 0.0).
	_add_box(Vector3(-2.94, 1.85, 0.0), Vector3(0.04, 0.05, 1.0), yellow)
	_add_box(Vector3(-2.94, 0.95, 0.0), Vector3(0.04, 0.05, 1.0), yellow)
	_add_box(Vector3(-2.94, 1.40, 0.48), Vector3(0.04, 0.95, 0.05), yellow)
	_add_box(Vector3(-2.94, 1.40, -0.48), Vector3(0.04, 0.95, 0.05), yellow)

# ----- emergency blast shutter (hidden until sealed) -----------------------

func _build_emergency_shutter() -> void:
	var shutter_body: StandardMaterial3D = StandardMaterial3D.new()
	shutter_body.albedo_color = Color(0.36, 0.30, 0.18, 1.0)
	shutter_body.metallic = 0.80
	shutter_body.roughness = 0.30
	shutter_body.emission_enabled = true
	shutter_body.emission = Color(1.0, 0.55, 0.18, 1.0)
	shutter_body.emission_energy_multiplier = 0.4
	var ridges: StandardMaterial3D = StandardMaterial3D.new()
	ridges.albedo_color = Color(0.18, 0.16, 0.14, 1.0)
	ridges.metallic = 0.85
	ridges.roughness = 0.30
	# Build the shutter as a Node3D child of self with name "EmergencyShutter"
	# and join the "emergency_shutter" group so hull_breach.gd can find it.
	var shutter: Node3D = Node3D.new()
	shutter.name = "EmergencyShutter"
	shutter.add_to_group("emergency_shutter")
	shutter.position = Vector3(0.0, 1.8, 2.85)
	shutter.visible = false # hidden until seal engaged
	add_child(shutter)
	# Main shutter plate covering the rupture.
	_add_box_to(shutter, Vector3(0.0, 0.0, 0.0), Vector3(RUPTURE_WIDTH + 0.6, RUPTURE_HEIGHT + 0.4, 0.10), shutter_body)
	# Horizontal ridges across the shutter (4 stripes).
	for ry in [-0.7, -0.2, 0.3, 0.8]:
		_add_box_to(shutter, Vector3(0.0, ry, 0.06), Vector3(RUPTURE_WIDTH + 0.4, 0.06, 0.02), ridges)
	# Center latch bolt (emissive amber, signals "locked").
	var latch_mat: StandardMaterial3D = StandardMaterial3D.new()
	latch_mat.albedo_color = Color(0.10, 0.85, 0.40, 1.0)
	latch_mat.emission_enabled = true
	latch_mat.emission = Color(0.30, 1.0, 0.50, 1.0)
	latch_mat.emission_energy_multiplier = 5.0
	_add_box_to(shutter, Vector3(0.0, 0.0, 0.08), Vector3(0.25, 0.25, 0.04), latch_mat)

# ----- intermittent sparks emitter from the rupture ------------------------

func _build_sparks_emitter() -> void:
	var sparks: GPUParticles3D = GPUParticles3D.new()
	sparks.name = "RuptureSparks"
	sparks.add_to_group("rupture_sparks")
	sparks.position = Vector3(0.4, 2.2, 2.85)
	sparks.amount = 60
	sparks.lifetime = 1.5
	sparks.preprocess = 0.3
	sparks.speed_scale = 1.0
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0.0, 1.0, -0.5)
	pm.spread = 35.0
	pm.gravity = Vector3(0.0, -2.5, 0.0)
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.scale_min = 0.02
	pm.scale_max = 0.06
	pm.color = Color(1.0, 0.55, 0.18, 1.0)
	sparks.process_material = pm
	var spark_mesh: SphereMesh = SphereMesh.new()
	spark_mesh.radius = 0.03
	spark_mesh.height = 0.06
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.65, 0.20, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	spark_mat.emission_energy_multiplier = 6.0
	spark_mesh.material = spark_mat
	sparks.draw_pass_1 = spark_mesh
	add_child(sparks)

# ----- helpers --------------------------------------------------------------

func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	_add_box_to(self, pos, size, mat)

func _add_box_to(parent: Node, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
