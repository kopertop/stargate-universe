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
	"corridor-template": 6.4,
	"control-room-template": 9.0,
	"kino-room-template": 6.0,
	"quarters-template": 5.4,
	"hydroponics-template": 10.0,
	"elevator-template": 5.6,
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
	_add_fill_light(world, width_m, depth_m, ceiling_m, palette)


# ----- shell (floor + walls + ceiling, identical structure across templates) --

static func _build_shell(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var wall_thickness: float = 0.4

	# Slightly more metallic + crisper roughness than the first pass — empty
	# walls were reading flat next to the gate-room artisan walls. These values
	# put the procedural rooms in the same finish range as gate_room.gd.
	var floor_mat: StandardMaterial3D = _make_mat(palette["floor"], 0.35, 0.55)
	var wall_mat: StandardMaterial3D = _make_mat(palette["wall"], 0.30, 0.58)
	var ceil_mat: StandardMaterial3D = _make_mat(palette["ceiling"], 0.25, 0.65)

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
				var perp_s: float = side_s * (half_short - 0.025)
				_corridor_place(world, sconce_mat, axis_z, perp_s,
					1.65, ts, 0.05, 0.32, 0.18)
				# Sconces only GLOW without a real light; the wall stayed flat.
				# A small OmniLight3D per sconce pool of warm bounce makes the
				# rib geometry pop and gives the corridor genuine depth.
				var lamp: OmniLight3D = OmniLight3D.new()
				lamp.light_color = palette["accent"]
				lamp.light_energy = 1.6
				lamp.omni_range = 5.5
				lamp.omni_attenuation = 1.8
				lamp.shadow_enabled = false
				if axis_z:
					lamp.position = Vector3(perp_s - side_s * 0.25, 1.7, ts)
				else:
					lamp.position = Vector3(ts, 1.7, perp_s - side_s * 0.25)
				world.add_child(lamp)

	_corridor_place(world, conduit_mat, axis_z, 0.0, height - 0.18, 0.0, 0.22, 0.22, strip_len)

	# --- Floor walkway stripe -----------------------------------------------
	# Pair of dim emissive strips inset from the floor edges, framing a
	# pedestrian lane down the corridor's center. Only worth adding when the
	# corridor is wide enough that the lane reads as intentional.
	if short_len >= 2.5:
		var lane_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 0.9)
		var lane_inset: float = 0.50
		for lane_side in [1.0, -1.0]:
			_corridor_place(world, lane_mat, axis_z,
				lane_side * (half_short - lane_inset),
				0.025, 0.0,
				0.06, 0.02, strip_len)

	# --- Wall service panels -------------------------------------------------
	# Small dark recessed rectangles set into the wall between sconces — a
	# silent storytelling beat: "this corridor has working systems behind it."
	# Each panel gets a tiny accent indicator dot. Only emit when the rib
	# spacing is wide enough to fit them between ribs without crowding.
	if rib_count >= 1 and short_len > 2.0:
		var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.55), 0.5, 0.55)
		var indicator_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 3.0)
		var spacing_p: float = strip_len / float(rib_count + 1)
		for j in range(rib_count + 1):
			var ts_p: float = -strip_len * 0.5 + spacing_p * (float(j) + 0.5)
			# Panel sits ~0.85 m off the floor — hip height. Slim recess look.
			for side_p in [1.0, -1.0]:
				_corridor_place(world, panel_mat, axis_z,
					side_p * (half_short - 0.02),
					0.85, ts_p, 0.03, 0.45, 0.30)
				_corridor_place(world, indicator_mat, axis_z,
					side_p * (half_short - 0.04),
					1.02, ts_p + 0.10, 0.02, 0.04, 0.04)


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


# Control room: industrial metal-grate floor overlay, a continuous amber band
# at chest height around all four walls, a massive floor-to-ceiling central
# pillar (Ancient power column with pipe and conduit cladding), and 4 Kenney
# `desk_computer.glb` consoles arranged 2-east / 2-west, all facing the pillar.
# Rush (placed by room.gd::_spawn_dr_rush) stands at the NW console.
static func _accent_control_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	var band_mat: StandardMaterial3D = _emissive_mat(accent, 1.6)
	var ring_mat: StandardMaterial3D = _emissive_mat(accent, 2.2)

	# --- Grate floor overlay -------------------------------------------------
	# A second floor slab sitting 1 cm above the base floor, textured with a
	# procedurally-generated grate pattern. Keeps the base floor collider
	# untouched while giving the room a hard industrial read.
	var grate_tex: Texture2D = _make_grate_texture()
	var grate_mat: StandardMaterial3D = StandardMaterial3D.new()
	grate_mat.albedo_texture = grate_tex
	grate_mat.albedo_color = Color(0.92, 0.92, 0.95)
	grate_mat.metallic = 0.75
	grate_mat.roughness = 0.4
	grate_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# 0.5 m tile size — each 32-px grate square reads as one floor panel.
	grate_mat.uv1_scale = Vector3(width / 0.5, depth / 0.5, 1.0)
	var grate_mi: MeshInstance3D = MeshInstance3D.new()
	var grate_box: BoxMesh = BoxMesh.new()
	grate_box.size = Vector3(width - 0.5, 0.04, depth - 0.5)
	grate_mi.mesh = grate_box
	grate_mi.material_override = grate_mat
	grate_mi.position = Vector3(0.0, 0.022, 0.0)
	world.add_child(grate_mi)

	# --- Wall band -----------------------------------------------------------
	# Continuous emissive band at chest height around all four walls — the
	# room's primary colour anchor.
	var hx: float = width * 0.5 - 0.05
	var hz: float = depth * 0.5 - 0.05
	var band_t: float = 0.06
	_add_decor(world, band_mat, Vector3(hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(-hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, hz), Vector3(width - 0.6, band_t, band_t))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, -hz), Vector3(width - 0.6, band_t, band_t))

	# --- Central power pillar -----------------------------------------------
	# SGU control-room signature: a circular column running floor-to-ceiling
	# with cladding pipes + emissive conduit bands. Doubles as a navigation
	# anchor (player can't walk through it — see PillarCollider).
	_accent_control_pillar(world, height, accent)

	# --- Four consoles flanking the pillar (NW / NE / SW / SE) ---------------
	# Each console faces the pillar so operators (Rush at NW) work with their
	# backs to the wall. Z = ±4 m straddles the +X door at z=0 so neither
	# console blocks the entrance from cr_corridor_2.
	# Kenney Space Station Kit's `computer-wide.glb` is a wide chest-height
	# control panel with an angled screen — much better silhouette than the
	# Space Kit desk_computer (which was reading as just a floating screen
	# against the dark grate). Scale 1.8 puts it at ~1.4 m tall.
	var console_glb: PackedScene = load("res://models/props/space_station_kit/computer-wide.glb")
	if console_glb != null:
		var east_x: float = width * 0.5 - 1.4
		var west_x: float = -width * 0.5 + 1.4
		var console_z_offsets: Array = [-4.0, 4.0]
		for cz in console_z_offsets:
			# West (-X wall) consoles face +X — front faces the pillar.
			_spawn_station_console(world, console_glb,
				Vector3(west_x, 0.0, cz), PI * 0.5)
			# East (+X wall) consoles face -X.
			_spawn_station_console(world, console_glb,
				Vector3(east_x, 0.0, cz), -PI * 0.5)

	# --- Console downlights ---------------------------------------------------
	# One soft warm pool over each of the four workstations so the consoles
	# pop against the cooler walls; emissive ceiling plate above each.
	for cz in [-4.0, 4.0]:
		for cx in [width * 0.5 - 2.4, -width * 0.5 + 2.4]:
			_add_decor(world, ring_mat,
				Vector3(cx, height - 0.08, cz),
				Vector3(0.7, 0.04, 0.7))
			var work_light: OmniLight3D = OmniLight3D.new()
			work_light.light_color = accent.lerp(Color(1.0, 0.92, 0.78), 0.4)
			work_light.light_energy = 1.9
			work_light.omni_range = 8.0
			work_light.omni_attenuation = 1.6
			work_light.shadow_enabled = false
			work_light.position = Vector3(cx, 2.6, cz)
			world.add_child(work_light)


# Floor-to-ceiling power column at the room's centre. Built from a dark metal
# shaft, 6 amber-tinted vertical pipes ringing the outside, three emissive
# conduit bands at quarter/half/three-quarter height, a wider floor collar,
# and a tapered top cap that visually merges into the ceiling. A CylinderShape
# collider on layer 1|2 blocks player+camera from passing through.
static func _accent_control_pillar(world: Node3D, height: float, accent: Color) -> void:
	var shaft_mat: StandardMaterial3D = _make_mat(Color(0.22, 0.24, 0.28), 0.75, 0.40)
	var pipe_mat: StandardMaterial3D = _make_mat(Color(0.62, 0.55, 0.40), 0.70, 0.38)
	var conduit_mat: StandardMaterial3D = _emissive_mat(accent, 2.2)
	var collar_mat: StandardMaterial3D = _make_mat(Color(0.30, 0.32, 0.36), 0.70, 0.50)
	var cap_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.20, 0.22), 0.70, 0.45)

	# --- Main shaft (dark cylinder, slightly conical for visual weight) ----
	var shaft_mi: MeshInstance3D = MeshInstance3D.new()
	shaft_mi.name = "PillarShaft"
	var shaft_mesh: CylinderMesh = CylinderMesh.new()
	shaft_mesh.top_radius = 1.40
	shaft_mesh.bottom_radius = 1.55
	shaft_mesh.height = height
	shaft_mesh.radial_segments = 32
	shaft_mi.mesh = shaft_mesh
	shaft_mi.material_override = shaft_mat
	shaft_mi.position = Vector3(0.0, height * 0.5, 0.0)
	world.add_child(shaft_mi)

	# --- Cladding pipes (6 around the shaft) -------------------------------
	var pipe_count: int = 6
	var pipe_radius: float = 0.10
	var pipe_offset: float = 1.70
	for i in pipe_count:
		var theta: float = (TAU / float(pipe_count)) * float(i)
		var pipe_mi: MeshInstance3D = MeshInstance3D.new()
		var pipe_mesh: CylinderMesh = CylinderMesh.new()
		pipe_mesh.top_radius = pipe_radius
		pipe_mesh.bottom_radius = pipe_radius
		pipe_mesh.height = height - 0.4
		pipe_mesh.radial_segments = 8
		pipe_mi.mesh = pipe_mesh
		pipe_mi.material_override = pipe_mat
		pipe_mi.position = Vector3(cos(theta) * pipe_offset, height * 0.5, sin(theta) * pipe_offset)
		world.add_child(pipe_mi)

	# --- Emissive conduit bands wrapping the shaft -------------------------
	# Three bands at quarter heights — read as "power flowing up the column."
	for y_frac in [0.20, 0.50, 0.80]:
		var band_mi: MeshInstance3D = MeshInstance3D.new()
		var band_mesh: CylinderMesh = CylinderMesh.new()
		band_mesh.top_radius = 1.78
		band_mesh.bottom_radius = 1.78
		band_mesh.height = 0.18
		band_mesh.radial_segments = 32
		band_mi.mesh = band_mesh
		band_mi.material_override = conduit_mat
		band_mi.position = Vector3(0.0, height * y_frac, 0.0)
		world.add_child(band_mi)

	# --- Floor collar (wider base disc) ------------------------------------
	var collar_mi: MeshInstance3D = MeshInstance3D.new()
	var collar_mesh: CylinderMesh = CylinderMesh.new()
	collar_mesh.top_radius = 1.90
	collar_mesh.bottom_radius = 2.10
	collar_mesh.height = 0.30
	collar_mesh.radial_segments = 32
	collar_mi.mesh = collar_mesh
	collar_mi.material_override = collar_mat
	collar_mi.position = Vector3(0.0, 0.15, 0.0)
	world.add_child(collar_mi)

	# --- Top cap (tapered up into ceiling) ---------------------------------
	var cap_mi: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius = 1.95
	cap_mesh.bottom_radius = 1.50
	cap_mesh.height = 0.50
	cap_mesh.radial_segments = 32
	cap_mi.mesh = cap_mesh
	cap_mi.material_override = cap_mat
	cap_mi.position = Vector3(0.0, height - 0.25, 0.0)
	world.add_child(cap_mi)

	# --- Player+camera collider --------------------------------------------
	# Radius covers the shaft plus pipes so the SpringArm can't clip through
	# either. Player capsule stops at the same radius. Matches kenney_room
	# floor/walls convention: layer 1|2.
	var pillar_body: StaticBody3D = StaticBody3D.new()
	pillar_body.name = "PillarCollider"
	pillar_body.collision_layer = 1 | 2
	pillar_body.collision_mask = 0
	var p_cs: CollisionShape3D = CollisionShape3D.new()
	var p_shape: CylinderShape3D = CylinderShape3D.new()
	p_shape.radius = 1.85
	p_shape.height = height
	p_cs.shape = p_shape
	p_cs.position = Vector3(0.0, height * 0.5, 0.0)
	pillar_body.add_child(p_cs)
	world.add_child(pillar_body)


# Space Station Kit `computer-wide.glb` console. GLB is authored at ~1u = 1m
# with a wide flat top, angled screen, and a chunky housing — much more
# "Ancient ship control panel" than the basic Space Kit desk_computer. Kenney
# textures are stripped on import, so we apply a two-tone override: dark
# brushed-metal body + a bright amber emissive screen plate aligned to the
# model's screen face.
#
# Model is authored facing +Z (operator stands on -Z side); `yaw` rotates
# the whole console so the operator standing direction is controlled by the
# caller.
static func _spawn_station_console(world: Node3D, glb: PackedScene, pos: Vector3, yaw: float) -> void:
	# Verified GLB AABB (raw): 0.8 × 0.497 × 0.533 m, single mesh / surface
	# (z-range -0.237 to +0.297). The model is authored with the OPERATOR side
	# on +Z and the back wall on -Z; the housing rises from a low operator-side
	# lip up to a tall back-of-console, with the slanted screen face descending
	# from the high back (-Z) down toward the operator's hands (+Z).
	# Scale 2.2 → 1.76 × 1.09 × 1.17 m.
	#
	# To match that slope on the floating plate: rotation.x = -38° tilts the
	# plate's +Z edge DOWN toward the operator (positive X rotation by right-
	# hand rule lifts +Z; negative lowers it). Plate y is set so the plate
	# embeds slightly into the slanted face rather than floating above it.
	const SCREEN_PLATE_Y: float = 0.36
	const SCREEN_TILT_DEG: float = -38.0
	var holder: Node3D = Node3D.new()
	holder.name = "StationConsole"
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = Vector3(2.2, 2.2, 2.2)
	world.add_child(holder)

	var inst: Node = glb.instantiate()
	holder.add_child(inst)

	# GLB is a single-surface mesh — the embedded base-color texture was
	# stripped by Godot's glTF importer (see feedback_gltf_embedded_texture_lost),
	# so we override with a brushed-metal body. Pop the screen separately via
	# an emissive plate child since we can't address the screen sub-region.
	var body_mat: StandardMaterial3D = _make_mat(Color(0.46, 0.48, 0.52), 0.65, 0.45)
	_apply_material_recursive(inst, body_mat)

	# Tech-blue screen plate aligned to the slanted top surface. Ancient ship
	# consoles in SGU read as cool-blue holographic UI, not warm amber. Plate
	# anchor sits a hair toward -Z and rotates around +X to match the GLB's
	# native slope (see SCREEN_TILT_DEG comment above).
	var screen_mat: StandardMaterial3D = _emissive_mat(Color(0.32, 0.72, 1.0), 3.2)
	var screen_mi: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.68, 0.015, 0.36)
	screen_mi.mesh = screen_box
	screen_mi.material_override = screen_mat
	# Shift slightly toward +Z (operator side) so the plate centers on the
	# visible slanted face rather than the upper-back peak.
	screen_mi.position = Vector3(0.0, SCREEN_PLATE_Y, 0.06)
	screen_mi.rotation = Vector3(deg_to_rad(SCREEN_TILT_DEG), 0.0, 0.0)
	holder.add_child(screen_mi)


# Generic Space Kit desk_computer.glb spawner — used by kino-room's
# corner-desk + chair decor. Control room now uses _spawn_station_console
# instead (computer-wide.glb has a stronger silhouette).
static func _spawn_kenney_console(world: Node3D, glb: PackedScene, pos: Vector3, yaw: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Console"
	holder.position = pos
	holder.rotation.y = yaw
	# Space Kit assets are authored ~1u = 1m. A 2× upscale puts a desk at
	# realistic console height (~1.6 m) without distorting proportions.
	holder.scale = Vector3(2.0, 2.0, 2.0)
	world.add_child(holder)

	var inst: Node = glb.instantiate()
	holder.add_child(inst)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.36, 0.38, 0.42)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.45
	_apply_material_recursive(inst, body_mat)

	# Emissive screen plate floating just above the desk surface — gives every
	# console a glowing readout that catches the eye from across the room.
	var screen_mat: StandardMaterial3D = _emissive_mat(Color(1.0, 0.55, 0.18), 2.6)
	var screen_mi: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.45, 0.02, 0.30)
	screen_mi.mesh = screen_box
	screen_mi.material_override = screen_mat
	# Top of the GLB desk surface, in the model's local space (before scale).
	screen_mi.position = Vector3(0.0, 0.55, 0.0)
	holder.add_child(screen_mi)


# Walk a GLB instance and stamp `mat` onto every surface of every MeshInstance3D.
# Used to recover Kenney GLBs whose embedded textures were dropped by the
# Godot glTF importer.
static func _apply_material_recursive(root: Node, mat: StandardMaterial3D) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		var surf_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i in surf_count:
			mi.set_surface_override_material(i, mat)
	for child in root.get_children():
		_apply_material_recursive(child, mat)


# 32×32 procedural grate pattern — bright cross-lattice with dark holes in the
# middle of each cell. Crisp pixel edges with TEXTURE_FILTER_NEAREST give a
# hard industrial read; UV scale is set by the caller to tile per-metre.
static func _make_grate_texture() -> Texture2D:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var bright: Color = Color(0.72, 0.74, 0.78, 1.0)
	var mid: Color = Color(0.40, 0.42, 0.46, 1.0)
	var hole: Color = Color(0.06, 0.07, 0.08, 1.0)
	for y in 32:
		for x in 32:
			# Outer 2-pixel rim = bright frame; one mid-cross at the midline.
			var on_rim: bool = (x < 2 or x > 29 or y < 2 or y > 29)
			var on_mid: bool = (x >= 15 and x <= 16) or (y >= 15 and y <= 16)
			if on_rim:
				img.set_pixel(x, y, bright)
			elif on_mid:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, hole)
	return ImageTexture.create_from_image(img)


# Kino room: a working drone bay. Two wall shelves of dormant kino spheres on
# the -Z wall, a centre pedestal where the player's active kino rests, an
# operator workbench (Kenney desk_computer + desk_chair) on the -X wall for the
# kino remote pilot, and a row of storage barrels along the +X wall. A warm
# pedestal light + a ceiling lamp panel keep the scene readable.
static func _accent_kino_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var shelf_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.4, 0.55)
	var body_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.20, 0.24), 0.55, 0.35)
	var eye_mat: StandardMaterial3D = _emissive_mat(Color(0.95, 0.85, 0.55), 3.5)
	var pedestal_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.2), 0.3, 0.6)
	var pedestal_top_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 1.8)
	var lamp_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.5)

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5

	# --- Kino display shelves (signature: this is THE kino room) -----------
	for shelf_y in [1.2, 1.9]:
		_add_decor(world, shelf_mat,
			Vector3(0.0, shelf_y, -half_z + 0.35),
			Vector3(width - 0.8, 0.08, 0.6))
		var span: float = width - 1.6
		for k in 4:
			var x: float = -span * 0.5 + span * (float(k) / 3.0)
			_add_kino_ball(world, body_mat, eye_mat,
				Vector3(x, shelf_y + 0.20, -half_z + 0.35))

	# --- Centre pedestal — DO NOT MOVE. room.gd::_spawn_kino_pickup places
	# the working kino + interactable hitbox at exactly (0, 1.05, 0).
	_add_decor(world, pedestal_mat, Vector3(0.0, 0.5, 0.0), Vector3(0.9, 1.0, 0.9))
	_add_decor(world, pedestal_top_mat, Vector3(0.0, 1.025, 0.0), Vector3(0.7, 0.05, 0.7))

	# Soft warm pool around the pedestal so the working kino reads as the
	# centerpiece — without this the eye drifts to the brighter shelf kinos.
	var pedestal_light: OmniLight3D = OmniLight3D.new()
	pedestal_light.name = "PedestalLight"
	pedestal_light.light_color = (palette["accent"] as Color).lerp(Color(1.0, 0.92, 0.78), 0.4)
	pedestal_light.light_energy = 1.8
	pedestal_light.omni_range = 4.5
	pedestal_light.omni_attenuation = 1.6
	pedestal_light.shadow_enabled = false
	pedestal_light.position = Vector3(0.0, 1.8, 0.0)
	world.add_child(pedestal_light)

	# --- Operator workbench against -X wall --------------------------------
	# A Kenney `desk_computerCorner.glb` (L-shaped desk with screen) faces +X
	# into the room, with a `desk_chair.glb` slid under it. This is where Eli
	# (or whoever inherits kino-pilot duty) sits to fly a kino remotely.
	var corner_glb: PackedScene = load("res://models/props/space_kit/desk_computerCorner.glb")
	var chair_glb: PackedScene = load("res://models/props/space_kit/desk_chair.glb")
	if corner_glb != null:
		# Tucked into -X wall, facing +X. Yaw of PI/2 rotates the desk so its
		# back-edge meets the wall.
		_spawn_kenney_console(world, corner_glb,
			Vector3(-half_x + 0.8, 0.0, 0.0), PI * 0.5)
	if chair_glb != null:
		var chair: Node3D = Node3D.new()
		chair.name = "OperatorChair"
		chair.position = Vector3(-half_x + 2.0, 0.0, 0.0)
		chair.rotation.y = -PI * 0.5
		chair.scale = Vector3(1.6, 1.6, 1.6)
		world.add_child(chair)
		var chair_inst: Node = chair_glb.instantiate()
		chair.add_child(chair_inst)
		var chair_mat: StandardMaterial3D = _make_mat(Color(0.22, 0.24, 0.28), 0.45, 0.55)
		_apply_material_recursive(chair_inst, chair_mat)

	# --- Storage barrels along +X wall -------------------------------------
	# Sample crates / spare-parts barrels lined up. A `machine_wireless.glb`
	# in the middle reads as a kino comms relay; the row of barrels around it
	# fills the wall without crowding the path.
	var barrels_glb: PackedScene = load("res://models/props/space_kit/barrels.glb")
	var wireless_glb: PackedScene = load("res://models/props/space_kit/machine_wireless.glb")
	if barrels_glb != null:
		for off_z in [-half_z + 2.5, half_z - 2.5]:
			_spawn_kenney_prop(world, barrels_glb,
				Vector3(half_x - 0.7, 0.0, off_z), -PI * 0.5, 1.6,
				Color(0.55, 0.45, 0.20))
	if wireless_glb != null:
		_spawn_kenney_prop(world, wireless_glb,
			Vector3(half_x - 0.7, 0.0, 0.0), -PI * 0.5, 1.6,
			Color(0.32, 0.36, 0.42))

	# --- Ceiling lamp -------------------------------------------------------
	_add_decor(world, lamp_mat, Vector3(0.0, height - 0.15, 0.0), Vector3(0.6, 0.05, 0.6))


# Spawn a Kenney prop GLB with a flat material override (textures stripped on
# import — see feedback_gltf_embedded_texture_lost). `tint` controls the body
# colour; `scale` is a uniform multiplier (Kenney space-kit is ~1u = 1m).
static func _spawn_kenney_prop(world: Node3D, glb: PackedScene, pos: Vector3, yaw: float, scale: float, tint: Color) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "KenneyProp"
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = Vector3(scale, scale, scale)
	world.add_child(holder)
	var inst: Node = glb.instantiate()
	holder.add_child(inst)
	var mat: StandardMaterial3D = _make_mat(tint, 0.55, 0.55)
	_apply_material_recursive(inst, mat)


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


# Quarters: a lived-in crew bunk. Kenney Furniture Kit `bedSingle.glb` against
# the -Z wall (positioned to match the Bed interactable in room.gd::_spawn_quarters_bed),
# a `lampSquareTable.glb` nightstand with a warm lamp glow, a tall
# `bathroomCabinet.glb` locker on the opposite wall, and (in wider rooms) a
# `desk.glb` + `chairDesk.glb` side workstation.
static func _accent_quarters(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var bunk_w: float = min(width - 1.0, 2.0)
	var bunk_x: float = -half_x * 0.3

	# --- Bed (must line up with the interactable hitbox in room.gd) --------
	# room.gd::_spawn_quarters_bed places a 2.0 m × 1.0 m × 2.0 m hitbox at
	# (bunk_x, 0.5, -half_z + 1.1). The Kenney bedSingle.glb is authored ~2 m
	# long and ~1 m wide; we sit it on the floor (y=0) and yaw to face +Z so
	# the headboard is against the -Z wall.
	var bed_glb: PackedScene = load("res://models/props/furniture_kit/bedSingle.glb")
	if bed_glb != null:
		_spawn_kenney_prop(world, bed_glb,
			Vector3(bunk_x, 0.0, -half_z + 1.1), 0.0, 1.5,
			Color(0.62, 0.58, 0.52))

	# --- Nightstand + lamp -------------------------------------------------
	var stand_x: float = bunk_x + bunk_w * 0.5 + 0.55
	if stand_x < half_x - 0.4:
		var stand_glb: PackedScene = load("res://models/props/furniture_kit/cabinetBedDrawerTable.glb")
		var lamp_glb: PackedScene = load("res://models/props/furniture_kit/lampSquareTable.glb")
		if stand_glb != null:
			_spawn_kenney_prop(world, stand_glb,
				Vector3(stand_x, 0.0, -half_z + 0.55), 0.0, 1.2,
				Color(0.42, 0.36, 0.30))
		if lamp_glb != null:
			_spawn_kenney_prop(world, lamp_glb,
				Vector3(stand_x, 0.55, -half_z + 0.55), 0.0, 1.2,
				Color(0.85, 0.78, 0.65))
		# A warm bedside pool — sells the lamp as a real lit object and gives
		# the bunk corner the cosy read it needs.
		var bed_light: OmniLight3D = OmniLight3D.new()
		bed_light.name = "BedsideLamp"
		bed_light.light_color = Color(1.0, 0.78, 0.50)
		bed_light.light_energy = 1.8
		bed_light.omni_range = 3.5
		bed_light.omni_attenuation = 1.8
		bed_light.shadow_enabled = false
		bed_light.position = Vector3(stand_x, 1.2, -half_z + 0.55)
		world.add_child(bed_light)

	# --- Wall locker on +Z wall --------------------------------------------
	var locker_glb: PackedScene = load("res://models/props/furniture_kit/bathroomCabinet.glb")
	if locker_glb != null:
		_spawn_kenney_prop(world, locker_glb,
			Vector3(bunk_x, 0.0, half_z - 0.3), PI, 1.4,
			Color(0.38, 0.40, 0.44))

	# --- Side desk (wider rooms only) --------------------------------------
	if width > 6.0:
		var desk_glb: PackedScene = load("res://models/props/furniture_kit/desk.glb")
		var chair_glb: PackedScene = load("res://models/props/furniture_kit/chairDesk.glb")
		if desk_glb != null:
			_spawn_kenney_prop(world, desk_glb,
				Vector3(half_x - 0.7, 0.0, 0.0), -PI * 0.5, 1.4,
				Color(0.45, 0.40, 0.35))
		if chair_glb != null:
			_spawn_kenney_prop(world, chair_glb,
				Vector3(half_x - 1.6, 0.0, 0.0), -PI * 0.5, 1.3,
				Color(0.30, 0.32, 0.36))


# Hydroponics: working crop bay. Ceiling-spanning grow-light array (emissive
# green slab), four raised planter beds in a 2×2 grid stocked with Kenney
# Nature-Kit crops (corn, wheat, leafy, bushes), a central nutrient column,
# and a row of nutrient barrels along one wall.
static func _accent_hydroponics(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var grow_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 4.0)
	var planter_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.3), 0.4, 0.55)
	var soil_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.13, 0.09), 0.0, 0.9)
	var column_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.2, 0.4)

	# --- Ceiling grow-light array (signature green wash) -------------------
	_add_decor(world, grow_mat,
		Vector3(0.0, height - 0.15, 0.0),
		Vector3(width - 1.0, 0.05, depth - 1.0))

	# Soft green fill light cast downward — the emissive ceiling slab alone
	# doesn't actually illuminate the crops, so add one OmniLight per quadrant.
	for sx_l in [1.0, -1.0]:
		for sz_l in [1.0, -1.0]:
			var grow_light: OmniLight3D = OmniLight3D.new()
			grow_light.light_color = Color(0.55, 1.0, 0.65)
			grow_light.light_energy = 2.2
			grow_light.omni_range = max(width, depth) * 0.35
			grow_light.omni_attenuation = 1.6
			grow_light.shadow_enabled = false
			grow_light.position = Vector3(sx_l * width * 0.22, height - 0.5, sz_l * depth * 0.22)
			world.add_child(grow_light)

	# --- Planter beds (2×2 grid) -------------------------------------------
	var corn_glb: PackedScene = load("res://models/props/nature_kit/crops_cornStageD.glb")
	var wheat_glb: PackedScene = load("res://models/props/nature_kit/crops_wheatStageB.glb")
	var leaf_glb: PackedScene = load("res://models/props/nature_kit/crops_leafsStageB.glb")
	var bush_glb: PackedScene = load("res://models/props/nature_kit/plant_bushDetailed.glb")
	var pumpkin_glb: PackedScene = load("res://models/props/nature_kit/crop_pumpkin.glb")
	var crop_palette: Array = [corn_glb, wheat_glb, leaf_glb, bush_glb]
	var crop_tints: Array = [
		Color(0.40, 0.75, 0.25),
		Color(0.85, 0.78, 0.40),
		Color(0.30, 0.70, 0.30),
		Color(0.20, 0.55, 0.25),
	]

	var bed_w: float = min(width * 0.30, 8.0)
	var bed_d: float = min(depth * 0.30, 6.0)
	var off_x: float = width * 0.24
	var off_z: float = depth * 0.24
	var quad: int = 0
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			var bx: float = sx * off_x
			var bz: float = sz * off_z
			# Planter box (collider-less decor — RoomBuilder is decor-only).
			_add_decor(world, planter_mat,
				Vector3(bx, 0.35, bz),
				Vector3(bed_w, 0.7, bed_d))
			# Dark soil cap sits 1 cm proud of the rim so crops appear rooted.
			_add_decor(world, soil_mat,
				Vector3(bx, 0.71, bz),
				Vector3(bed_w - 0.25, 0.04, bed_d - 0.25))
			# Crop fill: 3 rows × 4 cols of one crop type per bed, jittered for
			# an organic look. Uniform crop per bed reads as a deliberate row.
			var crop_glb: PackedScene = crop_palette[quad % 4]
			var crop_tint: Color = crop_tints[quad % 4]
			if crop_glb != null:
				var rows: int = 3
				var cols: int = 4
				var inner_w: float = bed_w - 0.6
				var inner_d: float = bed_d - 0.6
				for r in rows:
					for c in cols:
						var rx: float = bx - inner_w * 0.5 + inner_w * (float(c) / float(cols - 1))
						var rz: float = bz - inner_d * 0.5 + inner_d * (float(r) / float(rows - 1))
						# A tiny deterministic jitter — different per cell but
						# stable across runs (no RNG seeding needed).
						var jitter_x: float = sin(float(quad * 17 + r * 3 + c)) * 0.08
						var jitter_z: float = cos(float(quad * 13 + r * 5 + c * 2)) * 0.08
						_spawn_kenney_prop(world, crop_glb,
							Vector3(rx + jitter_x, 0.73, rz + jitter_z),
							sin(float(quad + r + c)) * PI, 0.9, crop_tint)
			# A single pumpkin accent at the bed's near edge gives each bed a
			# focal point — like a "today's harvest" demonstration crop.
			if pumpkin_glb != null and (quad % 2 == 0):
				_spawn_kenney_prop(world, pumpkin_glb,
					Vector3(bx, 0.78, bz - bed_d * 0.40),
					sin(float(quad)) * PI, 1.1, Color(0.95, 0.55, 0.20))
			quad += 1

	# --- Central nutrient column -------------------------------------------
	_add_decor(world, column_mat,
		Vector3(0.0, height * 0.45, 0.0),
		Vector3(0.6, height * 0.9, 0.6))

	# --- Nutrient tanks along -X wall --------------------------------------
	# Space-kit barrels lined up — reads as the chemical supply for the beds.
	var barrels_glb: PackedScene = load("res://models/props/space_kit/barrels.glb")
	if barrels_glb != null:
		var half_x: float = width * 0.5
		var slots: int = 3
		for i in slots:
			var t: float = 0.0 if slots == 1 else float(i) / float(slots - 1)
			var bz_b: float = lerp(-depth * 0.3, depth * 0.3, t)
			_spawn_kenney_prop(world, barrels_glb,
				Vector3(-half_x + 0.8, 0.0, bz_b), PI * 0.5, 1.5,
				Color(0.45, 0.55, 0.40))


# Elevator: cyan-rimmed floor disc + ceiling cap, plus four corner light
# columns running floor-to-ceiling and a wall-mounted control panel on +X.
# Elevator / transport bay: central glowing transport pad with a Kenney
# `machine_generator.glb` lift mechanism against the -X wall and a
# `machine_wireless.glb` call console on the +X wall. Cyan strip-lights climb
# the four corner pillars so the geometry reads as an active lift shaft, and
# warm cyan Omni lights pool on the pad and ceiling cap.
static func _accent_elevator(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	var disc_mat: StandardMaterial3D = _emissive_mat(accent, 2.4)
	var ring_mat: StandardMaterial3D = _emissive_mat(accent, 3.4)
	var cap_mat: StandardMaterial3D = _emissive_mat(accent, 2.0)
	var strip_mat: StandardMaterial3D = _emissive_mat(accent, 2.8)
	var pillar_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.45), 0.55, 0.5)
	var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.25), 0.55, 0.4)
	var panel_screen_mat: StandardMaterial3D = _emissive_mat(accent, 3.2)

	# --- Transport pad ------------------------------------------------------
	# Inner glowing disc + bright outer ring frame. Ring frame is 4 thin slabs
	# inset around the disc to read as a beveled platform edge.
	var pad_w: float = width - 1.4
	var pad_d: float = depth - 1.4
	_add_decor(world, disc_mat, Vector3(0.0, 0.025, 0.0), Vector3(pad_w, 0.05, pad_d))
	var rim_t: float = 0.10
	var rim_y: float = 0.07
	_add_decor(world, ring_mat,
		Vector3(0.0, rim_y, pad_d * 0.5 + rim_t * 0.5),
		Vector3(pad_w + rim_t * 2.0, 0.04, rim_t))
	_add_decor(world, ring_mat,
		Vector3(0.0, rim_y, -pad_d * 0.5 - rim_t * 0.5),
		Vector3(pad_w + rim_t * 2.0, 0.04, rim_t))
	_add_decor(world, ring_mat,
		Vector3(pad_w * 0.5 + rim_t * 0.5, rim_y, 0.0),
		Vector3(rim_t, 0.04, pad_d))
	_add_decor(world, ring_mat,
		Vector3(-pad_w * 0.5 - rim_t * 0.5, rim_y, 0.0),
		Vector3(rim_t, 0.04, pad_d))

	# --- Ceiling cap --------------------------------------------------------
	_add_decor(world, cap_mat,
		Vector3(0.0, height - 0.10, 0.0),
		Vector3(width - 1.2, 0.06, depth - 1.2))

	# --- Corner pillars with vertical light strips --------------------------
	# Dark metal pillars frame the bay; a thin cyan strip up the inner face of
	# each pillar reads as a lift-shaft "rails-lit" effect from any angle.
	var hx: float = width * 0.5 - 0.14
	var hz: float = depth * 0.5 - 0.14
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			_add_decor(world, pillar_mat,
				Vector3(sx * hx, height * 0.5, sz * hz),
				Vector3(0.18, height - 0.12, 0.18))
			# Cyan strip on the inner faces (-X and -Z direction from the pillar).
			_add_decor(world, strip_mat,
				Vector3(sx * (hx - 0.10), height * 0.5, sz * hz),
				Vector3(0.04, height - 0.5, 0.04))
			_add_decor(world, strip_mat,
				Vector3(sx * hx, height * 0.5, sz * (hz - 0.10)),
				Vector3(0.04, height - 0.5, 0.04))

	# --- Lift machinery against -X wall -------------------------------------
	# `machine_generator.glb` is a chunky pipe-and-housing unit that sells the
	# room as a real elevator shaft rather than an empty cube.
	var gen_glb: PackedScene = load("res://models/props/space_kit/machine_generator.glb")
	if gen_glb != null:
		_spawn_kenney_prop(world, gen_glb,
			Vector3(-width * 0.5 + 0.5, 0.0, -depth * 0.5 + 0.6),
			PI * 0.5, 1.4,
			Color(0.55, 0.58, 0.62))
		_spawn_kenney_prop(world, gen_glb,
			Vector3(-width * 0.5 + 0.5, 0.0, depth * 0.5 - 0.6),
			PI * 0.5, 1.4,
			Color(0.55, 0.58, 0.62))

	# --- Call console on +X wall --------------------------------------------
	# Wall-mounted `machine_wireless.glb` as the floor-selector console plus a
	# small emissive readout plate above it.
	var wireless_glb: PackedScene = load("res://models/props/space_kit/machine_wireless.glb")
	if wireless_glb != null:
		_spawn_kenney_prop(world, wireless_glb,
			Vector3(width * 0.5 - 0.5, 0.0, 0.0),
			-PI * 0.5, 1.0,
			Color(0.50, 0.55, 0.60))
	_add_decor(world, panel_mat,
		Vector3(width * 0.5 - 0.06, 1.55, 0.0),
		Vector3(0.06, 0.45, 0.55))
	_add_decor(world, panel_screen_mat,
		Vector3(width * 0.5 - 0.09, 1.60, 0.0),
		Vector3(0.04, 0.22, 0.40))

	# --- Lights --------------------------------------------------------------
	# Floor pool — the transport-pad glow.
	var pad_light: OmniLight3D = OmniLight3D.new()
	pad_light.name = "PadLight"
	pad_light.light_color = accent
	pad_light.light_energy = 1.8
	pad_light.omni_range = 4.5
	pad_light.omni_attenuation = 1.6
	pad_light.shadow_enabled = false
	pad_light.position = Vector3(0.0, 0.4, 0.0)
	world.add_child(pad_light)
	# Ceiling pool — picks out the cap and machinery housing.
	var cap_light: OmniLight3D = OmniLight3D.new()
	cap_light.name = "CapLight"
	cap_light.light_color = accent
	cap_light.light_energy = 2.0
	cap_light.omni_range = 6.0
	cap_light.omni_attenuation = 1.4
	cap_light.shadow_enabled = false
	cap_light.position = Vector3(0.0, height - 0.5, 0.0)
	world.add_child(cap_light)


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
				# Brighter brushed-steel walls + cool dark floor so the orange
				# accents (amber band, console screens) really pop. The grate
				# overlay built in _accent_control_room sits on top of `floor`.
				"floor": Color(0.16, 0.18, 0.20, 1.0),
				"wall": Color(0.62, 0.66, 0.72, 1.0),
				"ceiling": Color(0.22, 0.24, 0.27, 1.0),
				"accent": Color(1.0, 0.55, 0.18, 1.0),
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


# Every procedural room gets a single soft OmniLight pulled toward the ceiling
# so wall normals catch real shading instead of relying on the world environment
# alone. Without this the rooms read "flat" next to the artisan gate room.
static func _add_fill_light(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "FillLight"
	light.light_color = (palette["accent"] as Color).lerp(Color(1.0, 0.92, 0.85), 0.55)
	light.light_energy = 1.1
	light.omni_range = max(width, depth) * 0.9 + 4.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0.0, height - 0.6, 0.0)
	world.add_child(light)


static func _emissive_mat(tint: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = 0.0
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	return m
