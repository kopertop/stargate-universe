extends Node3D

# Hero-prop layer for the shared crew quarters. Adds storage lockers along
# the south wall (where the camera looks at spawn), a common area with table
# and chairs in the south-central floor, bunk nameplates over each bed, and
# warm pendant lights so the room reads as a lived-in barracks. The bunks
# themselves are still authored in the .tscn — this script only adds the
# "people live here" props that turn an empty room into a billet.
#
# Room assumptions: 10 wide x 14 long, walls at x=±5 and z=±7, south door
# cutout at x=0.5 z=-7.

const ROOM_HALF_X: float = 5.0
const ROOM_HALF_Z: float = 7.0
const CENTER_X: float = 0.5

func _ready() -> void:
	_build_lockers()
	_build_common_area()
	_build_bunk_nameplates()
	_build_pendant_lights()
	_build_floor_safety_stripes()

# ----- crew lockers along the south wall, flanking the door ----------------

func _build_lockers() -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.35
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.95, 0.55, 0.18, 1.0)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	trim_mat.emission_energy_multiplier = 2.0
	trim_mat.roughness = 0.45
	var handle_mat: StandardMaterial3D = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.50, 0.50, 0.55, 1.0)
	handle_mat.metallic = 0.7
	handle_mat.roughness = 0.30
	var locker_w: float = 0.6
	var locker_d: float = 0.45
	var locker_h: float = 2.2
	var locker_y: float = locker_h * 0.5
	var wall_z: float = -ROOM_HALF_Z + locker_d * 0.5 + 0.05
	# West side of south door: 3 lockers from x=-4 to x=-2
	var west_xs: Array[float] = [-3.6, -3.0, -2.4]
	# East side of south door: 3 lockers from x=3 to x=5
	var east_xs: Array[float] = [2.4, 3.0, 3.6]
	for x in west_xs + east_xs:
		_add_box(Vector3(x, locker_y, wall_z), Vector3(locker_w, locker_h, locker_d), body_mat)
		# Door seam — vertical amber strip down the center.
		_add_box(Vector3(x, locker_y, wall_z + locker_d * 0.51), Vector3(0.03, locker_h - 0.2, 0.01), trim_mat)
		# Handle.
		_add_box(Vector3(x + 0.18, locker_y - 0.1, wall_z + locker_d * 0.51), Vector3(0.04, 0.04, 0.04), handle_mat)

# ----- common area: table + chairs in the south-central floor --------------

func _build_common_area() -> void:
	var table_mat: StandardMaterial3D = StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.40, 0.36, 0.32, 1.0)
	table_mat.metallic = 0.40
	table_mat.roughness = 0.50
	var leg_mat: StandardMaterial3D = StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.22, 0.22, 0.25, 1.0)
	leg_mat.metallic = 0.65
	leg_mat.roughness = 0.35
	var chair_mat: StandardMaterial3D = StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.32, 0.30, 0.34, 1.0)
	chair_mat.metallic = 0.30
	chair_mat.roughness = 0.55
	var table_x: float = CENTER_X
	var table_z: float = -2.5
	var top_y: float = 0.78
	# Tabletop.
	_add_box(Vector3(table_x, top_y, table_z), Vector3(1.7, 0.06, 0.9), table_mat)
	# Four legs.
	for ox in [-0.75, 0.75]:
		for oz in [-0.4, 0.4]:
			_add_box(Vector3(table_x + ox, top_y * 0.5, table_z + oz), Vector3(0.06, top_y - 0.03, 0.06), leg_mat)
	# Four chairs around the table.
	_build_chair(Vector3(table_x - 1.1, 0.0, table_z), 90.0, chair_mat, leg_mat)
	_build_chair(Vector3(table_x + 1.1, 0.0, table_z), -90.0, chair_mat, leg_mat)
	_build_chair(Vector3(table_x, 0.0, table_z - 0.85), 180.0, chair_mat, leg_mat)
	_build_chair(Vector3(table_x, 0.0, table_z + 0.85), 0.0, chair_mat, leg_mat)
	# A datapad on the table (small emissive screen) — sells "people sit here".
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.08, 0.18, 0.28, 1.0)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.20, 0.75, 1.0, 1.0)
	screen_mat.emission_energy_multiplier = 2.5
	_add_box(Vector3(table_x - 0.4, top_y + 0.04, table_z + 0.1), Vector3(0.22, 0.02, 0.16), screen_mat)

func _build_chair(base: Vector3, yaw_deg: float, seat_mat: StandardMaterial3D, leg_mat: StandardMaterial3D) -> void:
	var chair: Node3D = Node3D.new()
	chair.position = base
	chair.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	add_child(chair)
	# Seat.
	_add_box_to(chair, Vector3(0.0, 0.45, 0.0), Vector3(0.44, 0.05, 0.44), seat_mat)
	# Back.
	_add_box_to(chair, Vector3(0.0, 0.74, -0.22), Vector3(0.44, 0.55, 0.04), seat_mat)
	# Legs.
	for ox in [-0.18, 0.18]:
		for oz in [-0.18, 0.18]:
			_add_box_to(chair, Vector3(ox, 0.22, oz), Vector3(0.04, 0.43, 0.04), leg_mat)

# ----- bunk nameplates ------------------------------------------------------

func _build_bunk_nameplates() -> void:
	var plate_mat: StandardMaterial3D = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.10, 0.40, 0.60, 1.0)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.30, 0.85, 1.0, 1.0)
	plate_mat.emission_energy_multiplier = 3.0
	plate_mat.roughness = 0.30
	# Bunks at (±3.5, _, 2) and (±3.5, _, 5). Plates go above the lower-bunk
	# headrest (z is roughly the long axis of the bunk; the head of each bunk
	# is at the inner end facing the room interior).
	# Just place them above each bunk position at y=1.45 (between lower and
	# upper bunk) hugging the wall.
	var positions: Array = [
		Vector3(-4.65, 1.45, 2.0),
		Vector3(4.65, 1.45, 2.0),
		Vector3(-4.65, 1.45, 5.0),
		Vector3(4.65, 1.45, 5.0),
	]
	for p in positions:
		var inset: float = -0.02 if p.x > 0.0 else 0.02
		_add_box(Vector3(p.x + inset, p.y, p.z), Vector3(0.04, 0.12, 0.40), plate_mat)

# ----- pendant lights over the common table --------------------------------

func _build_pendant_lights() -> void:
	var rod_mat: StandardMaterial3D = StandardMaterial3D.new()
	rod_mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
	rod_mat.metallic = 0.6
	rod_mat.roughness = 0.30
	var shade_mat: StandardMaterial3D = StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.42, 0.34, 0.22, 1.0)
	shade_mat.metallic = 0.55
	shade_mat.roughness = 0.30
	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.88, 0.65, 1.0)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.88, 0.65, 1.0)
	bulb_mat.emission_energy_multiplier = 3.5
	var ceil_y: float = 4.5
	var pendant_xs: Array[float] = [CENTER_X - 0.7, CENTER_X + 0.7]
	var pendant_z: float = -2.5
	for px in pendant_xs:
		# Rod.
		var rod: MeshInstance3D = MeshInstance3D.new()
		var rod_mesh: CylinderMesh = CylinderMesh.new()
		rod_mesh.top_radius = 0.015
		rod_mesh.bottom_radius = 0.015
		rod_mesh.height = 1.6
		rod.mesh = rod_mesh
		rod.material_override = rod_mat
		rod.position = Vector3(px, ceil_y - 0.8, pendant_z)
		add_child(rod)
		# Shade (downward-facing cone-ish via inverted cylinder).
		var shade: MeshInstance3D = MeshInstance3D.new()
		var shade_mesh: CylinderMesh = CylinderMesh.new()
		shade_mesh.top_radius = 0.18
		shade_mesh.bottom_radius = 0.10
		shade_mesh.height = 0.22
		shade.mesh = shade_mesh
		shade.material_override = shade_mat
		shade.position = Vector3(px, ceil_y - 1.7, pendant_z)
		add_child(shade)
		# Emissive bulb visible under the shade.
		var bulb: MeshInstance3D = MeshInstance3D.new()
		var bulb_mesh: SphereMesh = SphereMesh.new()
		bulb_mesh.radius = 0.07
		bulb_mesh.height = 0.14
		bulb.mesh = bulb_mesh
		bulb.material_override = bulb_mat
		bulb.position = Vector3(px, ceil_y - 1.82, pendant_z)
		add_child(bulb)

# ----- safety stripes on floor near the south door -------------------------

func _build_floor_safety_stripes() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.15, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.80, 0.15, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.roughness = 0.60
	# Two parallel stripes flanking the doorway.
	for x_off in [-0.7, 0.7]:
		_add_box(Vector3(CENTER_X + x_off, 0.02, -6.2), Vector3(0.10, 0.03, 0.8), mat)

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
