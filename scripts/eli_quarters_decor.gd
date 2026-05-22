extends Node3D

# Hero-prop layer for Eli's quarters. Sells "this person actually lives here
# and recently moved in" — laptop on the desk, posters on the wall, a
# personal effects shelf, scattered cables, and warm bedside lighting. Eli
# is the youngest character on Destiny and the most "civilian"; his quarters
# should feel cluttered and student-dorm, not military.
#
# Room assumptions: 6 wide x 6 long, walls at x=±3 and z=±3, south door
# cutout at x=0.5 z=-3, desk at (1.6, 0, 0), bed at (-1.5, 0, 1.5).

func _ready() -> void:
	_build_desk_clutter()
	_build_wall_posters()
	_build_personal_shelf()
	_build_bedside_lamp()
	_build_floor_clutter()

# ----- desk clutter: mug, papers, a power cable -----------------------------

func _build_desk_clutter() -> void:
	var mug_mat: StandardMaterial3D = StandardMaterial3D.new()
	mug_mat.albedo_color = Color(0.65, 0.20, 0.18, 1.0)
	mug_mat.roughness = 0.55
	var paper_mat: StandardMaterial3D = StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.86, 0.84, 0.78, 1.0)
	paper_mat.roughness = 0.85
	var cable_mat: StandardMaterial3D = StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	cable_mat.roughness = 0.70
	# Mug.
	var mug: MeshInstance3D = MeshInstance3D.new()
	var mug_mesh: CylinderMesh = CylinderMesh.new()
	mug_mesh.top_radius = 0.05
	mug_mesh.bottom_radius = 0.045
	mug_mesh.height = 0.10
	mug.mesh = mug_mesh
	mug.material_override = mug_mat
	mug.position = Vector3(1.95, 0.95, 0.18)
	add_child(mug)
	# Stack of papers.
	_add_box(Vector3(1.25, 0.93, 0.10), Vector3(0.22, 0.02, 0.28), paper_mat)
	# A loose page slightly offset.
	_add_box(Vector3(1.28, 0.94, 0.14), Vector3(0.22, 0.005, 0.28), paper_mat)
	# Snaking cable across the back of the desk.
	for i in range(5):
		var cz: float = -0.22 + i * 0.005
		var cx: float = 1.3 + i * 0.10
		var cable: MeshInstance3D = MeshInstance3D.new()
		var cable_mesh: CylinderMesh = CylinderMesh.new()
		cable_mesh.top_radius = 0.012
		cable_mesh.bottom_radius = 0.012
		cable_mesh.height = 0.10
		cable.mesh = cable_mesh
		cable.material_override = cable_mat
		cable.position = Vector3(cx, 0.918, cz)
		cable.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		add_child(cable)

# ----- wall posters above the bed ------------------------------------------

func _build_wall_posters() -> void:
	# West wall (x=-3) above the bed at (-1.5, _, 1.5). Three small posters.
	var poster_a: StandardMaterial3D = StandardMaterial3D.new()
	poster_a.albedo_color = Color(0.10, 0.55, 0.85, 1.0)
	poster_a.emission_enabled = true
	poster_a.emission = Color(0.20, 0.70, 1.0, 1.0)
	poster_a.emission_energy_multiplier = 0.4
	poster_a.roughness = 0.75
	var poster_b: StandardMaterial3D = StandardMaterial3D.new()
	poster_b.albedo_color = Color(0.85, 0.55, 0.20, 1.0)
	poster_b.emission_enabled = true
	poster_b.emission = Color(1.0, 0.60, 0.20, 1.0)
	poster_b.emission_energy_multiplier = 0.4
	poster_b.roughness = 0.80
	var poster_c: StandardMaterial3D = StandardMaterial3D.new()
	poster_c.albedo_color = Color(0.20, 0.20, 0.22, 1.0)
	poster_c.roughness = 0.85
	var wall_x: float = -2.97
	_add_box(Vector3(wall_x, 2.4, 0.5), Vector3(0.02, 0.55, 0.40), poster_a)
	_add_box(Vector3(wall_x, 2.4, 1.5), Vector3(0.02, 0.55, 0.40), poster_b)
	_add_box(Vector3(wall_x, 2.4, 2.5), Vector3(0.02, 0.55, 0.40), poster_c)

# ----- personal effects shelf on the north wall -----------------------------

func _build_personal_shelf() -> void:
	var shelf_mat: StandardMaterial3D = StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.32, 0.30, 0.34, 1.0)
	shelf_mat.metallic = 0.45
	shelf_mat.roughness = 0.45
	var book_a: StandardMaterial3D = StandardMaterial3D.new()
	book_a.albedo_color = Color(0.55, 0.18, 0.22, 1.0)
	book_a.roughness = 0.75
	var book_b: StandardMaterial3D = StandardMaterial3D.new()
	book_b.albedo_color = Color(0.18, 0.40, 0.55, 1.0)
	book_b.roughness = 0.75
	var book_c: StandardMaterial3D = StandardMaterial3D.new()
	book_c.albedo_color = Color(0.18, 0.55, 0.30, 1.0)
	book_c.roughness = 0.75
	var trinket_mat: StandardMaterial3D = StandardMaterial3D.new()
	trinket_mat.albedo_color = Color(0.70, 0.55, 0.20, 1.0)
	trinket_mat.metallic = 0.7
	trinket_mat.roughness = 0.35
	# North wall is at z=3, shelf at y=1.6, runs along x.
	var shelf_z: float = 2.95
	_add_box(Vector3(0.5, 1.6, shelf_z), Vector3(1.6, 0.04, 0.20), shelf_mat)
	# Books standing up on the shelf.
	_add_box(Vector3(0.0, 1.78, shelf_z + 0.02), Vector3(0.05, 0.30, 0.16), book_a)
	_add_box(Vector3(0.08, 1.77, shelf_z + 0.02), Vector3(0.05, 0.28, 0.16), book_b)
	_add_box(Vector3(0.16, 1.79, shelf_z + 0.02), Vector3(0.05, 0.32, 0.16), book_c)
	# A small trophy/figurine.
	var trinket: MeshInstance3D = MeshInstance3D.new()
	var trinket_mesh: SphereMesh = SphereMesh.new()
	trinket_mesh.radius = 0.05
	trinket_mesh.height = 0.10
	trinket.mesh = trinket_mesh
	trinket.material_override = trinket_mat
	trinket.position = Vector3(0.9, 1.69, shelf_z + 0.04)
	add_child(trinket)

# ----- bedside lamp ---------------------------------------------------------

func _build_bedside_lamp() -> void:
	# Bed center at (-1.5, _, 1.5) — lamp on the inside corner.
	var lamp_base: StandardMaterial3D = StandardMaterial3D.new()
	lamp_base.albedo_color = Color(0.18, 0.18, 0.22, 1.0)
	lamp_base.metallic = 0.55
	lamp_base.roughness = 0.35
	var shade: StandardMaterial3D = StandardMaterial3D.new()
	shade.albedo_color = Color(0.95, 0.85, 0.55, 1.0)
	shade.emission_enabled = true
	shade.emission = Color(1.0, 0.85, 0.55, 1.0)
	shade.emission_energy_multiplier = 3.0
	shade.roughness = 0.50
	var lx: float = -0.55
	var lz: float = 0.55
	# Base.
	_add_box(Vector3(lx, 0.78, lz), Vector3(0.10, 0.04, 0.10), lamp_base)
	# Stem.
	var stem: MeshInstance3D = MeshInstance3D.new()
	var stem_mesh: CylinderMesh = CylinderMesh.new()
	stem_mesh.top_radius = 0.012
	stem_mesh.bottom_radius = 0.012
	stem_mesh.height = 0.28
	stem.mesh = stem_mesh
	stem.material_override = lamp_base
	stem.position = Vector3(lx, 0.94, lz)
	add_child(stem)
	# Shade.
	var sh: MeshInstance3D = MeshInstance3D.new()
	var sh_mesh: CylinderMesh = CylinderMesh.new()
	sh_mesh.top_radius = 0.07
	sh_mesh.bottom_radius = 0.10
	sh_mesh.height = 0.15
	sh.mesh = sh_mesh
	sh.material_override = shade
	sh.position = Vector3(lx, 1.16, lz)
	add_child(sh)

# ----- floor clutter: a discarded hoodie + an empty soda can ----------------

func _build_floor_clutter() -> void:
	var fabric_mat: StandardMaterial3D = StandardMaterial3D.new()
	fabric_mat.albedo_color = Color(0.35, 0.32, 0.30, 1.0)
	fabric_mat.roughness = 0.90
	var can_mat: StandardMaterial3D = StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.78, 0.20, 0.18, 1.0)
	can_mat.metallic = 0.50
	can_mat.roughness = 0.35
	# Crumpled hoodie at the foot of the bed.
	_add_box(Vector3(-1.6, 0.08, -0.2), Vector3(0.55, 0.15, 0.45), fabric_mat)
	_add_box(Vector3(-1.45, 0.12, -0.05), Vector3(0.35, 0.12, 0.30), fabric_mat)
	# Soda can on the floor near the desk.
	var can: MeshInstance3D = MeshInstance3D.new()
	var can_mesh: CylinderMesh = CylinderMesh.new()
	can_mesh.top_radius = 0.033
	can_mesh.bottom_radius = 0.033
	can_mesh.height = 0.12
	can.mesh = can_mesh
	can.material_override = can_mat
	can.position = Vector3(1.2, 0.06, -0.8)
	can.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(can)

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
