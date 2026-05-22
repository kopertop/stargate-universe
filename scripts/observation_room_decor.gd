extends Node3D

# Hero-prop layer for the observation deck. The .tscn already has the big
# window with 8 stars and a single viewing bench; this script adds the
# atmosphere props that make it feel like a contemplative crew space: an
# inscribed memorial plaque to the lost expedition members, a planter with a
# resilient sapling (counterpart to the dying plant in the mess), a
# stargazer's brass telescope on a tripod, a second short bench for couples,
# floor accent lights guiding the eye toward the window, and a few extra
# distant stars in the void.
#
# Room assumptions: 14 wide x 10 long, walls at x=±7 and z=±5, window at
# x≈+6.85 (east), door at x=-7 (west), bench at x=+4.5 facing east.

const ROOM_HALF_X: float = 7.0
const ROOM_HALF_Z: float = 5.0

func _ready() -> void:
	_build_memorial_plaque()
	_build_planter()
	_build_telescope()
	_build_second_bench()
	_build_floor_runway()
	_build_extra_stars()

# ----- memorial plaque on the north wall -----------------------------------

func _build_memorial_plaque() -> void:
	var bronze: StandardMaterial3D = StandardMaterial3D.new()
	bronze.albedo_color = Color(0.45, 0.30, 0.14, 1.0)
	bronze.metallic = 0.80
	bronze.roughness = 0.30
	bronze.emission_enabled = true
	bronze.emission = Color(1.0, 0.55, 0.20, 1.0)
	bronze.emission_energy_multiplier = 0.5
	var inset: StandardMaterial3D = StandardMaterial3D.new()
	inset.albedo_color = Color(0.10, 0.08, 0.06, 1.0)
	inset.metallic = 0.50
	inset.roughness = 0.40
	var name_mat: StandardMaterial3D = StandardMaterial3D.new()
	name_mat.albedo_color = Color(0.55, 0.42, 0.20, 1.0)
	name_mat.emission_enabled = true
	name_mat.emission = Color(1.0, 0.65, 0.22, 1.0)
	name_mat.emission_energy_multiplier = 2.5
	# North wall is at z=-5. Plaque centered at x=0.
	var wz: float = -4.95
	# Outer frame.
	_add_box(Vector3(0.0, 2.4, wz), Vector3(2.4, 1.2, 0.08), bronze)
	# Inner dark panel.
	_add_box(Vector3(0.0, 2.4, wz + 0.03), Vector3(2.2, 1.05, 0.04), inset)
	# A row of "name" bars suggesting an inscription.
	for i in range(5):
		var ny: float = 2.78 - i * 0.16
		_add_box(Vector3(-0.05, ny, wz + 0.06), Vector3(1.7, 0.06, 0.005), name_mat)
	# Small candle / votive flame in front of the plaque, on a pedestal.
	var ped_mat: StandardMaterial3D = StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.20, 0.18, 0.20, 1.0)
	ped_mat.metallic = 0.45
	ped_mat.roughness = 0.50
	_add_box(Vector3(0.0, 0.45, wz + 0.55), Vector3(0.30, 0.90, 0.30), ped_mat)
	var flame_mat: StandardMaterial3D = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.65, 0.22, 1.0)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	flame_mat.emission_energy_multiplier = 6.0
	var flame: MeshInstance3D = MeshInstance3D.new()
	var flame_mesh: SphereMesh = SphereMesh.new()
	flame_mesh.radius = 0.07
	flame_mesh.height = 0.20
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position = Vector3(0.0, 1.05, wz + 0.55)
	add_child(flame)
	# Light source for the candle.
	var candle_light: OmniLight3D = OmniLight3D.new()
	candle_light.light_color = Color(1.0, 0.55, 0.22, 1.0)
	candle_light.light_energy = 1.2
	candle_light.omni_range = 3.0
	candle_light.position = Vector3(0.0, 1.10, wz + 0.55)
	add_child(candle_light)

# ----- planter with a healthy sapling --------------------------------------

func _build_planter() -> void:
	var pot_mat: StandardMaterial3D = StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.40, 0.32, 0.22, 1.0)
	pot_mat.roughness = 0.65
	var dirt_mat: StandardMaterial3D = StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.20, 0.12, 0.08, 1.0)
	dirt_mat.roughness = 0.95
	var trunk_mat: StandardMaterial3D = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.14, 1.0)
	trunk_mat.roughness = 0.85
	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.20, 0.55, 0.18, 1.0)
	leaf_mat.emission_enabled = true
	leaf_mat.emission = Color(0.30, 0.65, 0.25, 1.0)
	leaf_mat.emission_energy_multiplier = 0.4
	leaf_mat.roughness = 0.65
	var px: float = -5.5
	var pz: float = 3.5
	# Planter box (rectangular, larger than mess hall pot — this one is cared for).
	_add_box(Vector3(px, 0.25, pz), Vector3(0.8, 0.5, 0.8), pot_mat)
	_add_box(Vector3(px, 0.52, pz), Vector3(0.74, 0.04, 0.74), dirt_mat)
	# Trunk.
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.05
	trunk_mesh.bottom_radius = 0.07
	trunk_mesh.height = 1.0
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	trunk.position = Vector3(px, 1.05, pz)
	add_child(trunk)
	# Canopy — three offset spheres for a small lush bush.
	for entry in [
		Vector3(0.0, 1.70, 0.0),
		Vector3(-0.18, 1.60, 0.10),
		Vector3(0.16, 1.55, -0.08),
		Vector3(0.05, 1.78, -0.12),
	]:
		var leaf: MeshInstance3D = MeshInstance3D.new()
		var leaf_mesh: SphereMesh = SphereMesh.new()
		leaf_mesh.radius = 0.30
		leaf_mesh.height = 0.60
		leaf.mesh = leaf_mesh
		leaf.material_override = leaf_mat
		leaf.position = Vector3(px + entry.x, entry.y, pz + entry.z)
		add_child(leaf)

# ----- telescope on a tripod, aimed at the window --------------------------

func _build_telescope() -> void:
	var brass: StandardMaterial3D = StandardMaterial3D.new()
	brass.albedo_color = Color(0.55, 0.36, 0.16, 1.0)
	brass.metallic = 0.85
	brass.roughness = 0.30
	brass.emission_enabled = true
	brass.emission = Color(1.0, 0.55, 0.20, 1.0)
	brass.emission_energy_multiplier = 0.5
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.18, 1.0)
	dark.metallic = 0.70
	dark.roughness = 0.35
	var lens: StandardMaterial3D = StandardMaterial3D.new()
	lens.albedo_color = Color(0.10, 0.30, 0.50, 1.0)
	lens.emission_enabled = true
	lens.emission = Color(0.30, 0.85, 1.0, 1.0)
	lens.emission_energy_multiplier = 4.0
	# Telescope mount at (2.0, _, -3.0), tube pointing east toward the window.
	var tx: float = 2.0
	var tz: float = -3.0
	# Three tripod legs.
	for i in range(3):
		var ang: float = float(i) * TAU / 3.0
		var lx: float = tx + cos(ang) * 0.35
		var lz: float = tz + sin(ang) * 0.35
		var leg: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.03
		leg_mesh.bottom_radius = 0.025
		leg_mesh.height = 1.1
		leg.mesh = leg_mesh
		leg.material_override = dark
		leg.position = Vector3((tx + lx) * 0.5, 0.55, (tz + lz) * 0.5)
		leg.look_at(Vector3(lx, 0.0, lz), Vector3.UP)
		leg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		add_child(leg)
	# Yoke (small base on top of tripod).
	_add_box(Vector3(tx, 1.10, tz), Vector3(0.20, 0.10, 0.20), dark)
	# Telescope tube — long cylinder rotated to point east (+X) with slight tilt up.
	var tube: MeshInstance3D = MeshInstance3D.new()
	var tube_mesh: CylinderMesh = CylinderMesh.new()
	tube_mesh.top_radius = 0.10
	tube_mesh.bottom_radius = 0.10
	tube_mesh.height = 1.2
	tube.mesh = tube_mesh
	tube.material_override = brass
	tube.position = Vector3(tx + 0.30, 1.30, tz)
	tube.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(tube)
	# Front lens flare (east-facing end).
	var lens_mi: MeshInstance3D = MeshInstance3D.new()
	var lens_mesh: CylinderMesh = CylinderMesh.new()
	lens_mesh.top_radius = 0.11
	lens_mesh.bottom_radius = 0.11
	lens_mesh.height = 0.04
	lens_mi.mesh = lens_mesh
	lens_mi.material_override = lens
	lens_mi.position = Vector3(tx + 0.92, 1.30, tz)
	lens_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(lens_mi)
	# Eyepiece (west end).
	_add_box(Vector3(tx - 0.34, 1.30, tz), Vector3(0.10, 0.08, 0.08), dark)

# ----- second viewing bench (shorter, perpendicular to the main one) --------

func _build_second_bench() -> void:
	var bench_mat: StandardMaterial3D = StandardMaterial3D.new()
	bench_mat.albedo_color = Color(0.30, 0.28, 0.32, 1.0)
	bench_mat.metallic = 0.30
	bench_mat.roughness = 0.55
	# Bench at z=-3.5 facing east toward the window, x runs 1.8 wide.
	_add_box(Vector3(3.0, 0.45, -3.5), Vector3(1.8, 0.45, 0.50), bench_mat)
	_add_box(Vector3(3.0, 1.05, -3.78), Vector3(1.8, 0.85, 0.10), bench_mat)
	# Mirror it for the south side too — symmetry reads "couples viewing".
	_add_box(Vector3(3.0, 0.45, 3.5), Vector3(1.8, 0.45, 0.50), bench_mat)
	_add_box(Vector3(3.0, 1.05, 3.78), Vector3(1.8, 0.85, 0.10), bench_mat)

# ----- floor runway of accent lights leading toward the window -------------

func _build_floor_runway() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.55, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.85, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.5
	# Two runway lines of pill-shaped lights from -5 to +5 in x at z=±1.5,
	# guiding the player's eye east toward the window.
	for sz in [-1.4, 1.4]:
		for x_off in range(-4, 5, 2):
			var fx: float = float(x_off) * 0.6
			_add_box(Vector3(fx, 0.02, sz), Vector3(0.30, 0.03, 0.10), mat)

# ----- a few extra distant stars in the void -------------------------------

func _build_extra_stars() -> void:
	# Sit them just inside the void backdrop (z range ±3.5, y range 0.3-4.2).
	var star_warm: StandardMaterial3D = StandardMaterial3D.new()
	star_warm.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	star_warm.emission_enabled = true
	star_warm.emission = Color(1.0, 0.85, 0.70, 1.0)
	star_warm.emission_energy_multiplier = 7.0
	var star_cool: StandardMaterial3D = StandardMaterial3D.new()
	star_cool.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	star_cool.emission_enabled = true
	star_cool.emission = Color(0.60, 0.80, 1.0, 1.0)
	star_cool.emission_energy_multiplier = 5.5
	# 6 small extra stars at random-feeling positions.
	var entries: Array = [
		[Vector3(6.78, 2.45, -2.3), 0.035, star_warm],
		[Vector3(6.78, 3.10, 0.2), 0.045, star_cool],
		[Vector3(6.78, 1.10, -1.4), 0.040, star_warm],
		[Vector3(6.78, 2.10, 3.1), 0.030, star_warm],
		[Vector3(6.78, 0.50, 1.8), 0.038, star_cool],
		[Vector3(6.78, 3.75, -0.9), 0.045, star_warm],
	]
	for entry in entries:
		var pos: Vector3 = entry[0]
		var r: float = entry[1]
		var mat: StandardMaterial3D = entry[2]
		var star: MeshInstance3D = MeshInstance3D.new()
		var s_mesh: SphereMesh = SphereMesh.new()
		s_mesh.radius = r
		s_mesh.height = r * 2.0
		s_mesh.radial_segments = 8
		s_mesh.rings = 4
		star.mesh = s_mesh
		star.material_override = mat
		star.position = pos
		add_child(star)

# ----- helpers --------------------------------------------------------------

func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
