extends Node3D

# Hero-prop layer for the mess hall. The existing .tscn has two long tables
# with benches; this script adds the "people eat here" props that turn the
# tables into a working mess: a food-service counter along the north wall, a
# menu board above the counter, food trays / mugs / cutlery on the tables, a
# half-dead potted plant in a corner (Destiny's been gone a while), warm
# pendant lights over the tables, and a recycler bin near the door.
#
# Room assumptions: 12 wide x 10 long, walls at x=±6 and z=±5, south door
# cutout at z=-5, tables at (±2.5, _, 1.5) running 4m along z.

const ROOM_HALF_X: float = 6.0
const ROOM_HALF_Z: float = 5.0

func _ready() -> void:
	_build_service_counter()
	_build_menu_board()
	_build_table_props()
	_build_potted_plant()
	_build_pendant_lights()
	_build_recycler_bin()

# ----- service counter along the north wall --------------------------------

func _build_service_counter() -> void:
	var counter_mat: StandardMaterial3D = StandardMaterial3D.new()
	counter_mat.albedo_color = Color(0.36, 0.34, 0.30, 1.0)
	counter_mat.metallic = 0.55
	counter_mat.roughness = 0.35
	var top_mat: StandardMaterial3D = StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.62, 0.60, 0.56, 1.0)
	top_mat.metallic = 0.75
	top_mat.roughness = 0.20
	var warmer_mat: StandardMaterial3D = StandardMaterial3D.new()
	warmer_mat.albedo_color = Color(0.90, 0.55, 0.18, 1.0)
	warmer_mat.emission_enabled = true
	warmer_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	warmer_mat.emission_energy_multiplier = 3.0
	warmer_mat.roughness = 0.40
	var pan_mat: StandardMaterial3D = StandardMaterial3D.new()
	pan_mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
	pan_mat.metallic = 0.80
	pan_mat.roughness = 0.30
	# Main counter body along z=+4.5, runs ±3 in x.
	var counter_z: float = 4.5
	_add_box(Vector3(0.0, 0.45, counter_z), Vector3(6.0, 0.90, 0.7), counter_mat)
	# Stainless top.
	_add_box(Vector3(0.0, 0.92, counter_z), Vector3(6.0, 0.04, 0.78), top_mat)
	# Three warming-tray bays inset into the top.
	for ox in [-2.0, 0.0, 2.0]:
		_add_box(Vector3(ox, 0.96, counter_z), Vector3(0.9, 0.04, 0.55), pan_mat)
		# Warm orange glow inside the bay — sells "hot food" without showing
		# actual food, which is good because there isn't any left.
		_add_box(Vector3(ox, 0.99, counter_z), Vector3(0.84, 0.01, 0.50), warmer_mat)
	# Sneeze guard — vertical glass-ish panel above the trays.
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.50, 0.60, 0.70, 0.35)
	glass.metallic = 0.0
	glass.roughness = 0.10
	glass.transparency = 1
	_add_box(Vector3(0.0, 1.35, counter_z - 0.32), Vector3(5.8, 0.6, 0.02), glass)
	# Vertical glass support brackets at counter ends + center.
	var bracket_mat: StandardMaterial3D = StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.50, 0.50, 0.54, 1.0)
	bracket_mat.metallic = 0.80
	bracket_mat.roughness = 0.30
	for bx in [-2.9, 0.0, 2.9]:
		_add_box(Vector3(bx, 1.20, counter_z - 0.32), Vector3(0.04, 0.30, 0.04), bracket_mat)

# ----- menu board above the counter ----------------------------------------

func _build_menu_board() -> void:
	var board_mat: StandardMaterial3D = StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.08, 0.12, 0.18, 1.0)
	board_mat.metallic = 0.0
	board_mat.roughness = 0.25
	board_mat.emission_enabled = true
	board_mat.emission = Color(0.20, 0.65, 1.0, 1.0)
	board_mat.emission_energy_multiplier = 2.5
	var amber_mat: StandardMaterial3D = StandardMaterial3D.new()
	amber_mat.albedo_color = Color(0.85, 0.55, 0.20, 1.0)
	amber_mat.emission_enabled = true
	amber_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	amber_mat.emission_energy_multiplier = 4.0
	var ration_mat: StandardMaterial3D = StandardMaterial3D.new()
	ration_mat.albedo_color = Color(0.85, 0.20, 0.18, 1.0)
	ration_mat.emission_enabled = true
	ration_mat.emission = Color(1.0, 0.22, 0.20, 1.0)
	ration_mat.emission_energy_multiplier = 4.0
	var board_z: float = 4.95
	# Two side-by-side panels (left blue "menu", right amber "out of stock").
	_add_box(Vector3(-1.0, 3.0, board_z), Vector3(1.8, 1.0, 0.04), board_mat)
	_add_box(Vector3(1.0, 3.0, board_z), Vector3(1.8, 1.0, 0.04), board_mat)
	# Fake text rows: thin bright bars suggesting items.
	for i in range(3):
		var row_y: float = 3.30 - i * 0.20
		_add_box(Vector3(-1.4, row_y, board_z - 0.025), Vector3(0.8, 0.06, 0.01), amber_mat)
		# Right board — alternate rations crossed out (just shorter bars).
		_add_box(Vector3(0.6, row_y, board_z - 0.025), Vector3(0.4, 0.06, 0.01), ration_mat)

# ----- food trays + mugs on the tables --------------------------------------

func _build_table_props() -> void:
	var tray_mat: StandardMaterial3D = StandardMaterial3D.new()
	tray_mat.albedo_color = Color(0.20, 0.30, 0.45, 1.0)
	tray_mat.metallic = 0.10
	tray_mat.roughness = 0.65
	var ration_mat: StandardMaterial3D = StandardMaterial3D.new()
	ration_mat.albedo_color = Color(0.55, 0.40, 0.22, 1.0)
	ration_mat.metallic = 0.0
	ration_mat.roughness = 0.75
	var mug_mat: StandardMaterial3D = StandardMaterial3D.new()
	mug_mat.albedo_color = Color(0.78, 0.74, 0.66, 1.0)
	mug_mat.roughness = 0.65
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.08, 0.18, 0.28, 1.0)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.30, 0.85, 1.0, 1.0)
	pad_mat.emission_energy_multiplier = 2.0
	# Table A at (-2.5, 0.85, 1.5), top runs ±2 in z, ±0.7 in x.
	# Table B at (2.5, 0.85, 1.5).
	var table_top_y: float = 0.92
	var positions: Array = [
		Vector3(-2.5, table_top_y, 0.4),
		Vector3(-2.5, table_top_y, 2.3),
		Vector3(2.5, table_top_y, 0.8),
		Vector3(2.5, table_top_y, 2.6),
	]
	for p in positions:
		# Tray.
		_add_box(p, Vector3(0.45, 0.025, 0.32), tray_mat)
		# Ration block sitting on the tray.
		_add_box(p + Vector3(0.0, 0.04, 0.0), Vector3(0.20, 0.05, 0.16), ration_mat)
		# Mug next to it.
		var mug: MeshInstance3D = MeshInstance3D.new()
		var mug_mesh: CylinderMesh = CylinderMesh.new()
		mug_mesh.top_radius = 0.045
		mug_mesh.bottom_radius = 0.04
		mug_mesh.height = 0.10
		mug.mesh = mug_mesh
		mug.material_override = mug_mat
		mug.position = p + Vector3(0.18, 0.055, -0.10)
		add_child(mug)
	# A glowing datapad left on table B (someone got called away mid-meal).
	_add_box(Vector3(2.5, table_top_y + 0.04, -0.4), Vector3(0.22, 0.02, 0.16), pad_mat)

# ----- potted plant in the southwest corner --------------------------------

func _build_potted_plant() -> void:
	var pot_mat: StandardMaterial3D = StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.40, 0.32, 0.22, 1.0)
	pot_mat.roughness = 0.70
	var dirt_mat: StandardMaterial3D = StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.18, 0.12, 0.08, 1.0)
	dirt_mat.roughness = 0.95
	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	# Slightly yellowed — Destiny's plants are thirsty.
	leaf_mat.albedo_color = Color(0.30, 0.45, 0.18, 1.0)
	leaf_mat.roughness = 0.65
	var px: float = -5.2
	var pz: float = -3.8
	# Pot.
	var pot: MeshInstance3D = MeshInstance3D.new()
	var pot_mesh: CylinderMesh = CylinderMesh.new()
	pot_mesh.top_radius = 0.28
	pot_mesh.bottom_radius = 0.22
	pot_mesh.height = 0.45
	pot.mesh = pot_mesh
	pot.material_override = pot_mat
	pot.position = Vector3(px, 0.22, pz)
	add_child(pot)
	# Dirt cap.
	var dirt: MeshInstance3D = MeshInstance3D.new()
	var dirt_mesh: CylinderMesh = CylinderMesh.new()
	dirt_mesh.top_radius = 0.27
	dirt_mesh.bottom_radius = 0.27
	dirt_mesh.height = 0.04
	dirt.mesh = dirt_mesh
	dirt.material_override = dirt_mat
	dirt.position = Vector3(px, 0.47, pz)
	add_child(dirt)
	# A few drooping leaf-boxes.
	var leaf_positions: Array = [
		[Vector3(px - 0.10, 0.65, pz), Vector3(0.0, 0.0, -25.0)],
		[Vector3(px + 0.12, 0.62, pz - 0.08), Vector3(15.0, 30.0, 18.0)],
		[Vector3(px - 0.05, 0.75, pz + 0.08), Vector3(-10.0, -10.0, -5.0)],
		[Vector3(px + 0.06, 0.80, pz + 0.02), Vector3(8.0, 60.0, -30.0)],
	]
	for entry in leaf_positions:
		var p: Vector3 = entry[0]
		var rot: Vector3 = entry[1]
		var leaf: MeshInstance3D = MeshInstance3D.new()
		var leaf_mesh: BoxMesh = BoxMesh.new()
		leaf_mesh.size = Vector3(0.06, 0.04, 0.30)
		leaf.mesh = leaf_mesh
		leaf.material_override = leaf_mat
		leaf.position = p
		leaf.rotation_degrees = rot
		add_child(leaf)

# ----- pendant lights over each table --------------------------------------

func _build_pendant_lights() -> void:
	var rod_mat: StandardMaterial3D = StandardMaterial3D.new()
	rod_mat.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
	rod_mat.metallic = 0.6
	rod_mat.roughness = 0.30
	var shade_mat: StandardMaterial3D = StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.55, 0.42, 0.24, 1.0)
	shade_mat.metallic = 0.55
	shade_mat.roughness = 0.30
	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.88, 0.65, 1.0)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.88, 0.65, 1.0)
	bulb_mat.emission_energy_multiplier = 3.5
	var ceil_y: float = 4.5
	# Two pendants per table — at z=0.5 and z=2.5, over each table x.
	for tx in [-2.5, 2.5]:
		for tz in [0.5, 2.5]:
			# Rod.
			var rod: MeshInstance3D = MeshInstance3D.new()
			var rod_mesh: CylinderMesh = CylinderMesh.new()
			rod_mesh.top_radius = 0.015
			rod_mesh.bottom_radius = 0.015
			rod_mesh.height = 1.5
			rod.mesh = rod_mesh
			rod.material_override = rod_mat
			rod.position = Vector3(tx, ceil_y - 0.75, tz)
			add_child(rod)
			# Shade.
			var shade: MeshInstance3D = MeshInstance3D.new()
			var shade_mesh: CylinderMesh = CylinderMesh.new()
			shade_mesh.top_radius = 0.20
			shade_mesh.bottom_radius = 0.10
			shade_mesh.height = 0.24
			shade.mesh = shade_mesh
			shade.material_override = shade_mat
			shade.position = Vector3(tx, ceil_y - 1.62, tz)
			add_child(shade)
			# Bulb.
			var bulb: MeshInstance3D = MeshInstance3D.new()
			var bulb_mesh: SphereMesh = SphereMesh.new()
			bulb_mesh.radius = 0.07
			bulb_mesh.height = 0.14
			bulb.mesh = bulb_mesh
			bulb.material_override = bulb_mat
			bulb.position = Vector3(tx, ceil_y - 1.76, tz)
			add_child(bulb)

# ----- recycler bin near the door ------------------------------------------

func _build_recycler_bin() -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.40
	var lid_mat: StandardMaterial3D = StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.32, 0.32, 0.36, 1.0)
	lid_mat.metallic = 0.55
	lid_mat.roughness = 0.35
	var indicator: StandardMaterial3D = StandardMaterial3D.new()
	indicator.albedo_color = Color(0.10, 0.85, 0.40, 1.0)
	indicator.emission_enabled = true
	indicator.emission = Color(0.20, 1.0, 0.45, 1.0)
	indicator.emission_energy_multiplier = 4.0
	# Two bins flanking the south door (door at z=-4.7, x=0.5).
	for bx in [-1.6, 2.6]:
		_add_box(Vector3(bx, 0.5, -4.55), Vector3(0.45, 1.0, 0.45), body_mat)
		_add_box(Vector3(bx, 1.04, -4.55), Vector3(0.50, 0.06, 0.50), lid_mat)
		_add_box(Vector3(bx, 0.95, -4.31), Vector3(0.08, 0.06, 0.01), indicator)

# ----- helpers --------------------------------------------------------------

func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
