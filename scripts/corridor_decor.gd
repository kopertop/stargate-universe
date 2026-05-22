extends Node3D

# Procedural hero-detail layer for Destiny corridor scenes. Attach this script
# to a child Node3D of any corridor scene to add: emissive floor strip, amber
# wall-top glow, ceiling conduits, wall access panels with backlit screens,
# door-frame trim, and hanging cable bundles. Read corridor dimensions from
# the parent's kenney_room.gd Room node.

@export var corridor_width: float = 6.0
@export var corridor_length: float = 12.0
@export var ceiling_height: float = 5.0
# Z-offset of the corridor's "centerline" — the kenney_room layout is centered
# on origin, but the wall_door_index cutout can be off-center along the long
# axis. The player walks down the centerline strip; keep this 0.0 unless the
# scene's room has been authored off-center.
@export var center_x: float = 0.5
# Z position of the south door (where the south wall hosts the wall-door
# cutout). Used by door-frame trim. Set per-scene.
@export var south_door_z: float = -6.5
# Z position of the north door (if present). Set to a large negative number
# to disable (single-door rooms wired through south only).
@export var north_door_z: float = 6.5
# Accent color for door frames and floor strip — tune per corridor to give
# each transit space its own identity. Defaults to Destiny blue.
@export var accent_color: Color = Color(0.20, 0.75, 1.00, 1.0)

func _ready() -> void:
	_build_floor_strip()
	_build_floor_chevrons()
	_build_edge_glow()
	_build_ceiling_conduits()
	_build_access_panels()
	_build_door_trim()
	_build_cable_bundles()

func _build_floor_strip() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = accent_color * 0.6
	mat.emission_enabled = true
	mat.emission = accent_color
	mat.emission_energy_multiplier = 3.5
	mat.metallic = 0.0
	mat.roughness = 0.5
	_add_box(Vector3(center_x, 0.02, 0.0), Vector3(0.25, 0.04, corridor_length - 2.5), mat)

func _build_floor_chevrons() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.55, 0.15, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.metallic = 0.0
	mat.roughness = 0.55
	var z: float = -corridor_length * 0.5 + 2.0
	while z <= corridor_length * 0.5 - 2.0:
		_add_box(Vector3(center_x - 0.9, 0.02, z), Vector3(0.6, 0.03, 0.18), mat)
		_add_box(Vector3(center_x + 0.9, 0.02, z), Vector3(0.6, 0.03, 0.18), mat)
		z += 2.0

func _build_edge_glow() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.18, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.metallic = 0.0
	mat.roughness = 0.4
	var y: float = ceiling_height - 0.35
	var thick: float = 0.14
	var half_w: float = corridor_width * 0.5
	_add_box(Vector3(center_x + half_w - 0.15, y, 0.0), Vector3(thick, thick, corridor_length - 1.0), mat)
	_add_box(Vector3(center_x - half_w + 0.15, y, 0.0), Vector3(thick, thick, corridor_length - 1.0), mat)

func _build_ceiling_conduits() -> void:
	var pipe_mat: StandardMaterial3D = StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.45, 0.42, 0.40, 1.0)
	pipe_mat.metallic = 0.55
	pipe_mat.roughness = 0.45
	var pipe_radius: float = 0.10
	for offset_x in [center_x - 1.2, center_x + 1.2]:
		var pipe: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = pipe_radius
		cyl.bottom_radius = pipe_radius
		cyl.height = corridor_length - 1.0
		pipe.mesh = cyl
		pipe.material_override = pipe_mat
		pipe.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		pipe.position = Vector3(offset_x, ceiling_height - 0.18, 0.0)
		add_child(pipe)
	# Brackets every 3 m.
	var bracket_mat: StandardMaterial3D = StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.20, 0.20, 0.22, 1.0)
	bracket_mat.metallic = 0.6
	bracket_mat.roughness = 0.35
	var z: float = -corridor_length * 0.5 + 1.5
	while z <= corridor_length * 0.5 - 1.5:
		_add_box(Vector3(center_x - 1.2, ceiling_height - 0.05, z), Vector3(0.16, 0.10, 0.20), bracket_mat)
		_add_box(Vector3(center_x + 1.2, ceiling_height - 0.05, z), Vector3(0.16, 0.10, 0.20), bracket_mat)
		z += 3.0

func _build_access_panels() -> void:
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.28, 0.27, 0.30, 1.0)
	panel_mat.metallic = 0.55
	panel_mat.roughness = 0.42
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = accent_color * 0.25
	screen_mat.emission_enabled = true
	screen_mat.emission = accent_color
	screen_mat.emission_energy_multiplier = 2.5
	var positions_z: Array = []
	var half_l: float = corridor_length * 0.5
	# Four-panel rhythm scaled to length. Clip to leave room at the door ends.
	var first: float = -half_l + 2.5
	var last: float = half_l - 2.5
	var span: float = last - first
	var n: int = 4
	for i in range(n):
		positions_z.append(first + span * float(i) / float(n - 1))
	var half_w: float = corridor_width * 0.5
	var x_east: float = center_x + half_w - 0.08
	var x_west: float = center_x - half_w + 0.08
	for z_pos in positions_z:
		_add_box(Vector3(x_east, 1.6, z_pos), Vector3(0.06, 1.2, 0.8), panel_mat)
		_add_box(Vector3(x_east - 0.02, 1.8, z_pos), Vector3(0.04, 0.25, 0.55), screen_mat)
		_add_box(Vector3(x_west, 1.6, z_pos), Vector3(0.06, 1.2, 0.8), panel_mat)
		_add_box(Vector3(x_west + 0.02, 1.8, z_pos), Vector3(0.04, 0.25, 0.55), screen_mat)

func _build_door_trim() -> void:
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = accent_color * 0.5
	trim_mat.emission_enabled = true
	trim_mat.emission = accent_color
	trim_mat.emission_energy_multiplier = 4.0
	trim_mat.metallic = 0.0
	trim_mat.roughness = 0.5
	_add_door_frame(Vector3(center_x, 0.0, south_door_z + 0.1), trim_mat)
	if north_door_z < 100.0 and north_door_z > -100.0:
		_add_door_frame(Vector3(center_x, 0.0, north_door_z - 0.1), trim_mat)

func _add_door_frame(base: Vector3, mat: StandardMaterial3D) -> void:
	# Three-sided frame (left jamb, right jamb, lintel).
	_add_box(base + Vector3(-1.1, 1.0, 0.0), Vector3(0.06, 2.0, 0.06), mat)
	_add_box(base + Vector3(1.1, 1.0, 0.0), Vector3(0.06, 2.0, 0.06), mat)
	_add_box(base + Vector3(0.0, 2.05, 0.0), Vector3(2.16, 0.06, 0.06), mat)

func _build_cable_bundles() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.10, 0.12, 1.0)
	mat.metallic = 0.1
	mat.roughness = 0.75
	var bundles: Array = [
		Vector3(center_x + 1.4, 0.0, -corridor_length * 0.5 + 3.5),
		Vector3(center_x - 0.4, 0.0, 0.5),
		Vector3(center_x + 1.6, 0.0, corridor_length * 0.5 - 3.5),
	]
	for b in bundles:
		var c: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.06
		cyl.height = 1.2
		c.mesh = cyl
		c.material_override = mat
		c.position = Vector3(b.x, ceiling_height - 0.6, b.z)
		add_child(c)

func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
