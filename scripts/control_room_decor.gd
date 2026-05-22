extends Node3D

# Hero-prop layer for the control room. The .tscn already has the central
# bronze pillar with four screens; this script wraps it in a ring of crew
# workstations, a captain's chair facing the pillar, a holographic Destiny
# display rising from the floor between the chair and the pillar, status
# screens on the walls, and reinforces the bridge as the command space of
# the ship.
#
# Room assumptions: 14 wide x 12 long, walls at x=±7 and z=±6, pillar at
# (0, _, 0), west door at x=-7 (z=0), east door at x=+7 (z=0).

const ROOM_HALF_X: float = 7.0
const ROOM_HALF_Z: float = 6.0

func _ready() -> void:
	_build_workstation_ring()
	_build_captains_chair()
	_build_hologram_table()
	_build_wall_status_screens()
	_build_floor_safety_stripes()

# ----- 4 crew workstations around the central pillar -----------------------

func _build_workstation_ring() -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.24, 0.22, 0.26, 1.0)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.40
	var top_mat: StandardMaterial3D = StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.36, 0.30, 0.22, 1.0)
	top_mat.metallic = 0.65
	top_mat.roughness = 0.35
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.06, 0.14, 0.22, 1.0)
	screen_mat.metallic = 0.0
	screen_mat.roughness = 0.20
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.30, 0.85, 1.0, 1.0)
	screen_mat.emission_energy_multiplier = 2.8
	var key_mat: StandardMaterial3D = StandardMaterial3D.new()
	key_mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
	key_mat.metallic = 0.35
	key_mat.roughness = 0.55
	# Stations sit at the four diagonals of the pillar, ~3m out.
	var entries: Array = [
		[Vector3(2.6, 0.0, 2.6), -135.0], # SE faces NW into pillar
		[Vector3(-2.6, 0.0, 2.6), 135.0], # SW
		[Vector3(2.6, 0.0, -2.6), -45.0], # NE
		[Vector3(-2.6, 0.0, -2.6), 45.0], # NW
	]
	for entry in entries:
		var base_pos: Vector3 = entry[0]
		var yaw: float = entry[1]
		var ws: Node3D = Node3D.new()
		ws.position = base_pos
		ws.rotation_degrees = Vector3(0.0, yaw, 0.0)
		add_child(ws)
		# Desk body.
		_add_box_to(ws, Vector3(0.0, 0.45, 0.0), Vector3(1.6, 0.90, 0.7), body_mat)
		# Desk top.
		_add_box_to(ws, Vector3(0.0, 0.92, 0.0), Vector3(1.6, 0.04, 0.78), top_mat)
		# Two monitors angled toward operator.
		_add_box_to(ws, Vector3(-0.40, 1.30, -0.10), Vector3(0.50, 0.40, 0.04), screen_mat)
		_add_box_to(ws, Vector3(0.40, 1.30, -0.10), Vector3(0.50, 0.40, 0.04), screen_mat)
		# Monitor stands.
		_add_box_to(ws, Vector3(-0.40, 1.04, -0.05), Vector3(0.06, 0.18, 0.04), body_mat)
		_add_box_to(ws, Vector3(0.40, 1.04, -0.05), Vector3(0.06, 0.18, 0.04), body_mat)
		# Keyboard.
		_add_box_to(ws, Vector3(0.0, 0.95, 0.18), Vector3(0.55, 0.02, 0.18), key_mat)

# ----- captain's chair on the west side of the room -----------------------

func _build_captains_chair() -> void:
	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.18, 0.16, 0.20, 1.0)
	frame_mat.metallic = 0.70
	frame_mat.roughness = 0.30
	var cushion: StandardMaterial3D = StandardMaterial3D.new()
	cushion.albedo_color = Color(0.32, 0.16, 0.10, 1.0)
	cushion.metallic = 0.15
	cushion.roughness = 0.65
	var armrest: StandardMaterial3D = StandardMaterial3D.new()
	armrest.albedo_color = Color(0.40, 0.30, 0.18, 1.0)
	armrest.metallic = 0.55
	armrest.roughness = 0.40
	armrest.emission_enabled = true
	armrest.emission = Color(1.0, 0.55, 0.20, 1.0)
	armrest.emission_energy_multiplier = 0.6
	var chair: Node3D = Node3D.new()
	# Sits between the player spawn and pillar, facing east (toward pillar).
	chair.position = Vector3(-4.3, 0.0, 0.0)
	chair.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(chair)
	# Base pedestal.
	var ped: MeshInstance3D = MeshInstance3D.new()
	var ped_mesh: CylinderMesh = CylinderMesh.new()
	ped_mesh.top_radius = 0.18
	ped_mesh.bottom_radius = 0.35
	ped_mesh.height = 0.30
	ped.mesh = ped_mesh
	ped.material_override = frame_mat
	ped.position = Vector3(0.0, 0.15, 0.0)
	chair.add_child(ped)
	# Seat.
	_add_box_to(chair, Vector3(0.0, 0.50, 0.0), Vector3(0.70, 0.12, 0.65), cushion)
	# Back rest (tall, leaning slightly back).
	var back: MeshInstance3D = MeshInstance3D.new()
	var back_mesh: BoxMesh = BoxMesh.new()
	back_mesh.size = Vector3(0.70, 1.20, 0.12)
	back.mesh = back_mesh
	back.material_override = cushion
	back.position = Vector3(0.0, 1.10, -0.32)
	back.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	chair.add_child(back)
	# Headrest pad.
	_add_box_to(chair, Vector3(0.0, 1.62, -0.30), Vector3(0.50, 0.18, 0.10), cushion)
	# Armrests with emissive control surface on top.
	for sx in [-0.40, 0.40]:
		_add_box_to(chair, Vector3(sx, 0.74, 0.10), Vector3(0.10, 0.10, 0.40), armrest)
		_add_box_to(chair, Vector3(sx, 0.80, 0.10), Vector3(0.08, 0.01, 0.30), armrest)

# ----- hologram table between captain's chair and pillar -------------------

func _build_hologram_table() -> void:
	var base_mat: StandardMaterial3D = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.18, 0.18, 0.22, 1.0)
	base_mat.metallic = 0.70
	base_mat.roughness = 0.35
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.36, 0.24, 0.10, 1.0)
	ring_mat.metallic = 0.80
	ring_mat.roughness = 0.30
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	var holo_mat: StandardMaterial3D = StandardMaterial3D.new()
	holo_mat.albedo_color = Color(0.05, 0.30, 0.55, 1.0)
	holo_mat.metallic = 0.0
	holo_mat.roughness = 0.10
	holo_mat.emission_enabled = true
	holo_mat.emission = Color(0.30, 0.75, 1.0, 1.0)
	holo_mat.emission_energy_multiplier = 5.0
	holo_mat.transparency = 1
	holo_mat.albedo_color.a = 0.60
	var hx: float = -2.8
	var hz: float = 0.0
	# Pedestal.
	var ped: MeshInstance3D = MeshInstance3D.new()
	var ped_mesh: CylinderMesh = CylinderMesh.new()
	ped_mesh.top_radius = 0.55
	ped_mesh.bottom_radius = 0.65
	ped_mesh.height = 0.90
	ped.mesh = ped_mesh
	ped.material_override = base_mat
	ped.position = Vector3(hx, 0.45, hz)
	add_child(ped)
	# Emissive ring on the rim.
	var ring: MeshInstance3D = MeshInstance3D.new()
	var ring_mesh: CylinderMesh = CylinderMesh.new()
	ring_mesh.top_radius = 0.56
	ring_mesh.bottom_radius = 0.56
	ring_mesh.height = 0.06
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	ring.position = Vector3(hx, 0.92, hz)
	add_child(ring)
	# Holographic Destiny — stack of progressively smaller cylinders to suggest
	# a tapered ship silhouette floating above the pad.
	var holo_heights: Array = [
		[0.40, 0.06, 1.10],
		[0.32, 0.05, 1.32],
		[0.22, 0.04, 1.50],
		[0.14, 0.03, 1.62],
	]
	for entry in holo_heights:
		var r: float = entry[0]
		var h: float = entry[1]
		var y: float = entry[2]
		var seg: MeshInstance3D = MeshInstance3D.new()
		var seg_mesh: CylinderMesh = CylinderMesh.new()
		seg_mesh.top_radius = r
		seg_mesh.bottom_radius = r
		seg_mesh.height = h
		seg.mesh = seg_mesh
		seg.material_override = holo_mat
		seg.position = Vector3(hx, y, hz)
		add_child(seg)
	# Light source pretending to be the hologram emission.
	var holo_light: OmniLight3D = OmniLight3D.new()
	holo_light.light_color = Color(0.30, 0.75, 1.0, 1.0)
	holo_light.light_energy = 1.8
	holo_light.omni_range = 2.5
	holo_light.position = Vector3(hx, 1.4, hz)
	add_child(holo_light)

# ----- wall status screens flanking the doors ------------------------------

func _build_wall_status_screens() -> void:
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.06, 0.14, 0.22, 1.0)
	screen_mat.metallic = 0.0
	screen_mat.roughness = 0.20
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.30, 0.85, 1.0, 1.0)
	screen_mat.emission_energy_multiplier = 2.5
	var amber: StandardMaterial3D = StandardMaterial3D.new()
	amber.albedo_color = Color(0.08, 0.06, 0.04, 1.0)
	amber.metallic = 0.0
	amber.roughness = 0.25
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.55, 0.18, 1.0)
	amber.emission_energy_multiplier = 3.5
	var bezel: StandardMaterial3D = StandardMaterial3D.new()
	bezel.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	bezel.metallic = 0.55
	bezel.roughness = 0.40
	# West wall (x=-7): two large screens flanking the west door (at z=0).
	for sz in [-3.0, 3.0]:
		_add_box(Vector3(-6.96, 2.5, sz), Vector3(0.06, 1.4, 1.8), bezel)
		_add_box(Vector3(-6.92, 2.5, sz), Vector3(0.02, 1.20, 1.60), screen_mat)
	# East wall (x=+7).
	for sz in [-3.0, 3.0]:
		_add_box(Vector3(6.96, 2.5, sz), Vector3(0.06, 1.4, 1.8), bezel)
		_add_box(Vector3(6.92, 2.5, sz), Vector3(0.02, 1.20, 1.60), screen_mat)
	# North wall (z=-6): one wide screen.
	_add_box(Vector3(0.0, 2.8, -5.96), Vector3(3.6, 1.4, 0.06), bezel)
	_add_box(Vector3(0.0, 2.8, -5.92), Vector3(3.4, 1.20, 0.02), amber)
	# South wall (z=+6): one wide screen.
	_add_box(Vector3(0.0, 2.8, 5.96), Vector3(3.6, 1.4, 0.06), bezel)
	_add_box(Vector3(0.0, 2.8, 5.92), Vector3(3.4, 1.20, 0.02), screen_mat)

# ----- safety stripes around the pillar ------------------------------------

func _build_floor_safety_stripes() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.15, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.80, 0.15, 1.0)
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.60
	# Four straight stripes forming a 2.0m square around the 2.6x2.6 base.
	_add_box(Vector3(0.0, 0.02, 1.55), Vector3(3.1, 0.03, 0.10), mat)
	_add_box(Vector3(0.0, 0.02, -1.55), Vector3(3.1, 0.03, 0.10), mat)
	_add_box(Vector3(1.55, 0.02, 0.0), Vector3(0.10, 0.03, 3.1), mat)
	_add_box(Vector3(-1.55, 0.02, 0.0), Vector3(0.10, 0.03, 3.1), mat)

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
