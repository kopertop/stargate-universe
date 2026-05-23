class_name RoomBuilder
extends Object

# Procedural geometry builder for Destiny rooms generated from ship_layout.json.
# All 7 template types build as basic boxes (floor + 4 walls + ceiling), sized
# from JSON × ShipLayout.SCALE, with template-specific ceiling heights and
# material palettes so each room TYPE reads as visually distinct even before
# hero detail is added.
#
# Convention matches scripts/gate_room.gd: floor + walls on layer 1|2 (player +
# camera SpringArm), ceiling on layer 2 (camera only) — lets the spring arm
# clamp to the ceiling without the player capsule getting trapped against it.
#
# Usage from a generic room scene script:
#     var data: Dictionary = ShipLayout.room(room_id)
#     RoomBuilder.build(world, data)


# Default ceiling height per template (metres). Picked to make small rooms
# feel intimate and large rooms feel monumental without per-room tuning.
const CEILING_BY_TEMPLATE: Dictionary = {
	"gate-room-template": 9.0,
	"corridor-template": 3.2,
	"control-room-template": 4.5,
	"kino-room-template": 3.0,
	"quarters-template": 2.7,
	"hydroponics-template": 5.0,
	"elevator-template": 2.8,
}


static func build(world: Node3D, room_data: Dictionary) -> void:
	if room_data.is_empty() or world == null:
		return
	var template_id: String = String(room_data.get("template_id", ""))
	var width_m: float = float(room_data.get("width", 200)) * ShipLayout.SCALE
	var depth_m: float = float(room_data.get("height", 200)) * ShipLayout.SCALE
	var ceiling_m: float = CEILING_BY_TEMPLATE.get(template_id, 3.5)

	# Apply a per-template visual palette and any template-specific accents
	# AFTER the base shell is built so accents render on top.
	var palette: Dictionary = _palette_for(template_id)
	_build_shell(world, width_m, depth_m, ceiling_m, palette)
	_add_template_accents(world, template_id, width_m, depth_m, ceiling_m, palette)


# ----- shell (floor + walls + ceiling, identical structure across templates) --

static func _build_shell(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var wall_thickness: float = 0.4

	var floor_mat: StandardMaterial3D = _make_mat(palette["floor"], 0.3, 0.65)
	var wall_mat: StandardMaterial3D = _make_mat(palette["wall"], 0.25, 0.7)
	var ceil_mat: StandardMaterial3D = _make_mat(palette["ceiling"], 0.2, 0.75)

	# Floor — single box + collider.
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1 | 2
	floor_body.collision_mask = 0
	world.add_child(floor_body)
	_add_box(floor_body, floor_mat, Vector3(0.0, -0.1, 0.0), Vector3(width, 0.2, depth))

	# Walls — one StaticBody3D containing four wall colliders + meshes.
	var walls: StaticBody3D = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	world.add_child(walls)
	# +X / -X
	_add_box(walls, wall_mat,
		Vector3(half_x + wall_thickness * 0.5, height * 0.5, 0.0),
		Vector3(wall_thickness, height, depth))
	_add_box(walls, wall_mat,
		Vector3(-half_x - wall_thickness * 0.5, height * 0.5, 0.0),
		Vector3(wall_thickness, height, depth))
	# +Z / -Z
	_add_box(walls, wall_mat,
		Vector3(0.0, height * 0.5, half_z + wall_thickness * 0.5),
		Vector3(width, height, wall_thickness))
	_add_box(walls, wall_mat,
		Vector3(0.0, height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(width, height, wall_thickness))

	# Ceiling — camera-only collision so the SpringArm can clamp to it without
	# trapping the player capsule against it (matches gate_room convention).
	var ceil_body: StaticBody3D = StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 2
	ceil_body.collision_mask = 0
	world.add_child(ceil_body)
	_add_box(ceil_body, ceil_mat,
		Vector3(0.0, height + wall_thickness * 0.5, 0.0),
		Vector3(width, wall_thickness, depth))


# ----- template-specific accents --------------------------------------------

static func _add_template_accents(world: Node3D, template_id: String, width: float, depth: float, height: float, palette: Dictionary) -> void:
	match template_id:
		"corridor-template":
			_accent_corridor(world, width, depth, height, palette)
		"control-room-template":
			_accent_control_room(world, width, depth, height, palette)
		"kino-room-template":
			_accent_kino_room(world, width, depth, height, palette)
		"quarters-template":
			_accent_quarters(world, width, depth, height, palette)
		"hydroponics-template":
			_accent_hydroponics(world, width, depth, height, palette)
		"elevator-template":
			_accent_elevator(world, width, depth, height, palette)
		"gate-room-template":
			# Reference-only — the artisan gate_room.tscn handles its own geometry.
			pass


# Corridor: layered industrial detail — emissive runners at the top + base of
# both long walls, periodic bulkhead ribs with chest-height sconces between
# them, and a dark conduit down the centreline of the ceiling. Reads as an
# Ancient ship corridor at both 5 m vestibule and 100 m hall scales.
static func _accent_corridor(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var strip_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.4)
	var sconce_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 4.5)
	var rib_color: Color = (palette["wall"] as Color).darkened(0.4)
	var rib_mat: StandardMaterial3D = _make_mat(rib_color, 0.45, 0.55)
	var conduit_mat: StandardMaterial3D = _make_mat(Color(0.09, 0.09, 0.11), 0.7, 0.45)

	var axis_z: bool = depth > width
	var long_len: float = depth if axis_z else width
	var short_len: float = width if axis_z else depth
	var half_short: float = short_len * 0.5
	var strip_len: float = long_len - 0.6
	var inset: float = 0.06

	for side in [1.0, -1.0]:
		var perp: float = side * (half_short - inset)
		_corridor_place(world, strip_mat, axis_z, perp, height - 0.45, 0.0, 0.10, 0.10, strip_len)
		_corridor_place(world, strip_mat, axis_z, perp, 0.20, 0.0, 0.10, 0.10, strip_len)

	# Ribs every ~6 m, with a wall sconce between each rib pair. Skip in tiny
	# rooms (<2 m short axis) where ribs would crowd the path.
	var rib_count: int = int(floor(strip_len / 6.0))
	if rib_count >= 1 and short_len > 2.0:
		var rib_depth: float = 0.22
		var rib_w: float = 0.45
		var rib_h: float = height - 0.4
		var spacing: float = strip_len / float(rib_count + 1)
		for i in range(1, rib_count + 1):
			var t: float = -strip_len * 0.5 + spacing * float(i)
			for side_r in [1.0, -1.0]:
				_corridor_place(world, rib_mat, axis_z, side_r * (half_short - rib_depth * 0.5),
					rib_h * 0.5, t, rib_w, rib_h, rib_depth)
		for j in range(rib_count + 1):
			var ts: float = -strip_len * 0.5 + spacing * (float(j) + 0.5)
			for side_s in [1.0, -1.0]:
				_corridor_place(world, sconce_mat, axis_z, side_s * (half_short - 0.025),
					1.65, ts, 0.05, 0.32, 0.18)

	_corridor_place(world, conduit_mat, axis_z, 0.0, height - 0.18, 0.0, 0.22, 0.22, strip_len)


# Place a decor box inside a corridor whose long axis is +Z (axis_z=true) or
# +X (axis_z=false). perp_off/along_off are positions in the corridor's short
# and long axes; perp_size/along_size are box extents along those same axes.
static func _corridor_place(world: Node3D, mat: StandardMaterial3D, axis_z: bool,
		perp_off: float, y: float, along_off: float,
		perp_size: float, h: float, along_size: float) -> void:
	if axis_z:
		_add_decor(world, mat, Vector3(perp_off, y, along_off), Vector3(perp_size, h, along_size))
	else:
		_add_decor(world, mat, Vector3(along_off, y, perp_off), Vector3(along_size, h, perp_size))


# Control room: tiered hologram spine at the centre, ringed by an amber floor
# inlay + a matching ceiling pendant, four cardinal console stations facing
# the spine, and a chest-height emissive band around all four walls.
static func _accent_control_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	var spine_mat: StandardMaterial3D = _make_mat(accent, 0.7, 0.4)
	spine_mat.emission_enabled = true
	spine_mat.emission = accent
	spine_mat.emission_energy_multiplier = 0.5
	var ring_mat: StandardMaterial3D = _emissive_mat(accent, 1.4)
	var holo_mat: StandardMaterial3D = _emissive_mat(accent, 2.6)
	var console_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.3), 0.5, 0.5)
	var screen_mat: StandardMaterial3D = _emissive_mat(accent, 2.5)
	var band_mat: StandardMaterial3D = _emissive_mat(accent, 1.6)

	# Tiered hologram spine: wide base, narrower mid, glowing tip.
	_add_decor(world, spine_mat, Vector3(0.0, 0.5, 0.0), Vector3(1.6, 1.0, 1.6))
	_add_decor(world, spine_mat, Vector3(0.0, 1.5, 0.0), Vector3(0.9, 1.0, 0.9))
	_add_decor(world, holo_mat, Vector3(0.0, 2.2, 0.0), Vector3(0.55, 0.45, 0.55))

	for ring_def in [
		{"y": 0.03, "ir": 2.6, "or": 2.9},
		{"y": height - 0.20, "ir": 2.8, "or": 3.2},
	]:
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = ring_def["ir"]
		ring.outer_radius = ring_def["or"]
		ring.ring_segments = 48
		ring.rings = 6
		var ring_mi: MeshInstance3D = MeshInstance3D.new()
		ring_mi.mesh = ring
		ring_mi.material_override = ring_mat
		ring_mi.position = Vector3(0.0, ring_def["y"], 0.0)
		world.add_child(ring_mi)

	# Cardinal console stations — bodies axis-aligned, screen plates inset
	# toward the room centre so the lit face reads from the spine.
	var radius: float = min(width, depth) * 0.30
	for cfg in [
		{"pos": Vector3(radius, 0.5, 0.0), "wide_axis": "z", "inset": Vector3(-0.1, 0.55, 0.0)},
		{"pos": Vector3(-radius, 0.5, 0.0), "wide_axis": "z", "inset": Vector3(0.1, 0.55, 0.0)},
		{"pos": Vector3(0.0, 0.5, radius), "wide_axis": "x", "inset": Vector3(0.0, 0.55, -0.1)},
		{"pos": Vector3(0.0, 0.5, -radius), "wide_axis": "x", "inset": Vector3(0.0, 0.55, 0.1)},
	]:
		var body_size: Vector3
		var screen_size: Vector3
		if cfg["wide_axis"] == "x":
			body_size = Vector3(2.0, 1.0, 1.2)
			screen_size = Vector3(1.8, 0.05, 1.0)
		else:
			body_size = Vector3(1.2, 1.0, 2.0)
			screen_size = Vector3(1.0, 0.05, 1.8)
		_add_decor(world, console_mat, cfg["pos"], body_size)
		_add_decor(world, screen_mat, cfg["pos"] + cfg["inset"], screen_size)

	# Continuous emissive band at chest height around all four walls.
	var hx: float = width * 0.5 - 0.05
	var hz: float = depth * 0.5 - 0.05
	var band_t: float = 0.06
	_add_decor(world, band_mat, Vector3(hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(-hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, hz), Vector3(width - 0.6, band_t, band_t))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, -hz), Vector3(width - 0.6, band_t, band_t))


# Kino room: two wall shelves stocked with dormant kino spheres, a centre
# pedestal for the player's working kino, and a ceiling spotlight overhead.
static func _accent_kino_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var shelf_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.4, 0.55)
	var body_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.20, 0.24), 0.55, 0.35)
	var eye_mat: StandardMaterial3D = _emissive_mat(Color(0.95, 0.85, 0.55), 3.5)
	var pedestal_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.2), 0.3, 0.6)
	var pedestal_top_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 1.8)
	var lamp_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.5)

	var half_z: float = depth * 0.5
	for shelf_y in [1.2, 1.9]:
		_add_decor(world, shelf_mat,
			Vector3(0.0, shelf_y, -half_z + 0.35),
			Vector3(width - 0.8, 0.08, 0.6))
		var span: float = width - 1.6
		for k in 4:
			var x: float = -span * 0.5 + span * (float(k) / 3.0)
			_add_kino_ball(world, body_mat, eye_mat,
				Vector3(x, shelf_y + 0.20, -half_z + 0.35))

	_add_decor(world, pedestal_mat, Vector3(0.0, 0.5, 0.0), Vector3(0.9, 1.0, 0.9))
	_add_decor(world, pedestal_top_mat, Vector3(0.0, 1.025, 0.0), Vector3(0.7, 0.05, 0.7))
	_add_decor(world, lamp_mat, Vector3(0.0, height - 0.15, 0.0), Vector3(0.6, 0.05, 0.6))


# Small Kino sphere: dark body with an emissive iris sphere protruding from
# its front. Used by the kino-room shelf display.
static func _add_kino_ball(world: Node3D, body: StandardMaterial3D, eye: StandardMaterial3D, pos: Vector3) -> void:
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: SphereMesh = SphereMesh.new()
	body_mesh.radius = 0.13
	body_mesh.height = 0.26
	body_mesh.radial_segments = 16
	body_mesh.rings = 8
	body_mi.mesh = body_mesh
	body_mi.material_override = body
	body_mi.position = pos
	world.add_child(body_mi)
	var eye_mi: MeshInstance3D = MeshInstance3D.new()
	var iris: SphereMesh = SphereMesh.new()
	iris.radius = 0.05
	iris.height = 0.10
	iris.radial_segments = 12
	iris.rings = 6
	eye_mi.mesh = iris
	eye_mi.material_override = eye
	eye_mi.position = pos + Vector3(0.0, 0.0, 0.10)
	world.add_child(eye_mi)


# Quarters: bunk + bedding against the -Z wall, a nightstand with a warm lamp,
# a wall locker on the opposite wall, and (in wider rooms) a side desk.
static func _accent_quarters(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var bunk_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.1, 0.85)
	var bedding_mat: StandardMaterial3D = _make_mat(Color(0.20, 0.30, 0.45), 0.0, 0.8)
	var locker_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.25), 0.55, 0.45)
	var desk_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.2, 0.7)
	var stand_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.2, 0.7)
	var lamp_mat: StandardMaterial3D = _emissive_mat(Color(1.0, 0.85, 0.55), 2.2)

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var bunk_w: float = min(width - 1.0, 2.0)
	var bunk_x: float = -half_x * 0.3

	_add_decor(world, bunk_mat,
		Vector3(bunk_x, 0.4, -half_z + 1.1),
		Vector3(bunk_w, 0.5, 1.8))
	_add_decor(world, bedding_mat,
		Vector3(bunk_x, 0.68, -half_z + 1.1),
		Vector3(bunk_w - 0.15, 0.08, 1.7))

	var stand_x: float = bunk_x + bunk_w * 0.5 + 0.35
	if stand_x < half_x - 0.3:
		_add_decor(world, stand_mat,
			Vector3(stand_x, 0.3, -half_z + 0.55),
			Vector3(0.5, 0.6, 0.5))
		_add_decor(world, lamp_mat,
			Vector3(stand_x, 0.75, -half_z + 0.55),
			Vector3(0.25, 0.30, 0.25))

	_add_decor(world, locker_mat,
		Vector3(bunk_x, 1.0, half_z - 0.3),
		Vector3(min(width - 1.0, 1.6), 2.0, 0.5))

	if width > 6.0:
		_add_decor(world, desk_mat,
			Vector3(half_x - 0.45, 0.4, 0.0),
			Vector3(0.9, 0.8, min(1.8, depth - 1.0)))


# Hydroponics: ceiling-spanning grow-light array, four raised planter beds in
# a 2×2 grid (each with a green crop layer), and a central nutrient column.
static func _accent_hydroponics(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var grow_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 4.0)
	var planter_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.3), 0.4, 0.55)
	var crop_mat: StandardMaterial3D = _make_mat(Color(0.20, 0.65, 0.25), 0.0, 0.85)
	var column_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.2, 0.4)

	_add_decor(world, grow_mat,
		Vector3(0.0, height - 0.15, 0.0),
		Vector3(width - 1.0, 0.05, depth - 1.0))

	var bed_w: float = min(width * 0.30, 8.0)
	var bed_d: float = min(depth * 0.30, 6.0)
	var off_x: float = width * 0.24
	var off_z: float = depth * 0.24
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			var bx: float = sx * off_x
			var bz: float = sz * off_z
			_add_decor(world, planter_mat,
				Vector3(bx, 0.35, bz),
				Vector3(bed_w, 0.7, bed_d))
			_add_decor(world, crop_mat,
				Vector3(bx, 0.75, bz),
				Vector3(bed_w - 0.20, 0.15, bed_d - 0.20))

	_add_decor(world, column_mat,
		Vector3(0.0, height * 0.45, 0.0),
		Vector3(0.6, height * 0.9, 0.6))


# Elevator: cyan-rimmed floor disc + ceiling cap, plus four corner light
# columns running floor-to-ceiling and a wall-mounted control panel on +X.
static func _accent_elevator(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var disc_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.0)
	var cap_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 1.8)
	var col_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.6)
	var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.25), 0.55, 0.4)
	var panel_screen_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 3.0)

	_add_decor(world, disc_mat, Vector3(0.0, 0.02, 0.0), Vector3(width - 0.8, 0.04, depth - 0.8))
	_add_decor(world, cap_mat,
		Vector3(0.0, height - 0.10, 0.0),
		Vector3(width - 1.2, 0.06, depth - 1.2))

	var hx: float = width * 0.5 - 0.12
	var hz: float = depth * 0.5 - 0.12
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			_add_decor(world, col_mat,
				Vector3(sx * hx, height * 0.5, sz * hz),
				Vector3(0.08, height - 0.1, 0.08))

	_add_decor(world, panel_mat,
		Vector3(width * 0.5 - 0.05, 1.3, 0.0),
		Vector3(0.08, 0.6, 0.45))
	_add_decor(world, panel_screen_mat,
		Vector3(width * 0.5 - 0.08, 1.4, 0.0),
		Vector3(0.04, 0.3, 0.35))


# ----- palette ---------------------------------------------------------------

static func _palette_for(template_id: String) -> Dictionary:
	match template_id:
		"corridor-template":
			return {
				"floor": Color(0.25, 0.25, 0.29, 1.0),
				"wall": Color(0.32, 0.33, 0.38, 1.0),
				"ceiling": Color(0.16, 0.17, 0.19, 1.0),
				"accent": Color(1.0, 0.55, 0.18, 1.0),
			}
		"control-room-template":
			return {
				"floor": Color(0.22, 0.20, 0.18, 1.0),
				"wall": Color(0.36, 0.32, 0.26, 1.0),
				"ceiling": Color(0.14, 0.13, 0.12, 1.0),
				"accent": Color(1.0, 0.45, 0.10, 1.0),
			}
		"kino-room-template":
			return {
				"floor": Color(0.26, 0.24, 0.22, 1.0),
				"wall": Color(0.34, 0.32, 0.30, 1.0),
				"ceiling": Color(0.18, 0.17, 0.16, 1.0),
				"accent": Color(0.85, 0.70, 0.45, 1.0),
			}
		"quarters-template":
			return {
				"floor": Color(0.24, 0.23, 0.25, 1.0),
				"wall": Color(0.40, 0.35, 0.34, 1.0),
				"ceiling": Color(0.18, 0.17, 0.18, 1.0),
				"accent": Color(0.75, 0.62, 0.50, 1.0),
			}
		"hydroponics-template":
			return {
				"floor": Color(0.20, 0.24, 0.21, 1.0),
				"wall": Color(0.28, 0.34, 0.30, 1.0),
				"ceiling": Color(0.10, 0.13, 0.11, 1.0),
				"accent": Color(0.30, 1.0, 0.45, 1.0),
			}
		"elevator-template":
			return {
				"floor": Color(0.18, 0.20, 0.24, 1.0),
				"wall": Color(0.26, 0.30, 0.36, 1.0),
				"ceiling": Color(0.10, 0.12, 0.14, 1.0),
				"accent": Color(0.20, 0.85, 1.0, 1.0),
			}
		_:
			return {
				"floor": Color(0.28, 0.28, 0.30, 1.0),
				"wall": Color(0.36, 0.36, 0.40, 1.0),
				"ceiling": Color(0.18, 0.18, 0.20, 1.0),
				"accent": Color(0.80, 0.80, 0.85, 1.0),
			}


# ----- low-level helpers -----------------------------------------------------

static func _add_box(parent: StaticBody3D, mat: StandardMaterial3D, pos: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _add_decor(world: Node3D, mat: StandardMaterial3D, pos: Vector3, size: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	world.add_child(mi)


static func _make_mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _emissive_mat(tint: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = 0.0
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	return m
