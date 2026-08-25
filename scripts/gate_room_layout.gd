extends Node

# Procedural geometry builder for the gate room. Extracted from gate_room.gd
# to decompose the god object. Added as a child Node by the main script and
# called via the host reference.
#
# Builds: floor, walls, ceiling, mezzanine, railings, staircases, gate platform,
# structural columns, and operator consoles.

# Preload bypasses class_name registration timing in headless -s mode.
const RoomBuilderScript: Script = preload("res://scripts/room_builder.gd")

# Prop paths (shared with the main script via the host).
const PROP_DIR: String = "res://models/sci-fi/stargate-props/"
const GATE_PLATFORM_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-raised-circular-platform.glb"
const GATE_STAIRS_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-metal-staircase-steps.glb"
const GATE_CONSOLE_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-operator-control-console.glb"
const OVERHEAD_RING_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-overhead-ceiling-ring-structure.glb"
const SPOTLIGHT_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-spotlight-ceiling-light.glb"
const INDUSTRIAL_COLUMN_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-industrial-wall-column.glb"
const CATWALK_RAILING_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-catwalk-railing-segment.glb"

# Railings are tall enough that the player's 0.6 m jump can't clear them.
const RAIL_HEIGHT: float = 1.4
const RAIL_THICKNESS: float = 0.1
# Stair landing geometry — also referenced by the railing code so the side
# mezzanine rail can leave a doorway for the stair.
const STAIR_WIDTH: float = 2.4
const STAIR_Z_CENTER: float = -10.0

# Host reference (the gate_room.gd Node3D). Set by the host before build calls.
var host: Node3D = null

# One-time cache for runtime-loaded hero props (shared with host).
var _prop_cache: Dictionary = {}


# Build the floor mesh + collider + amber floor light strips.
func build_floor() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var gate_z: float = host.GATE_Z
	var half_x: float = room_size_v.x * 0.5
	var half_z: float = room_size_v.y * 0.5
	# Single mesh-based floor — Kenney tiles would cost 256 instances at 2 m
	# pitch. A BoxMesh + offset gives the same look at one draw call.
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Floor"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(room_size_v.x, 0.2, room_size_v.y)
	mi.mesh = box
	# Shared metal-grate floor via RoomBuilder.make_floor_mat — same texture,
	# tile size, brightness, and PNG-buffer fallback as every procedural room.
	# Palette kept near the original (0.30, 0.29, 0.32) tint.
	var mat: StandardMaterial3D = RoomBuilderScript.make_floor_mat(Color(0.30, 0.29, 0.32, 1.0), room_size_v.x, room_size_v.y)
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.1, 0.0)
	world.add_child(mi)

	# Floor collider.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "FloorCollider"
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	world.add_child(body)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(room_size_v.x, 0.2, room_size_v.y)
	cs.shape = shape
	cs.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(cs)
	# (Removed the glowing blue floor inlay ring around the gate — it read as a
	# stray hexagon on the deck. The floor is clean grating now.)

	# Twin rows of AMBER floor lights running down the walkway toward the gate — the
	# iconic Destiny gate-room look from the SGU "Air" opening establishing shot.
	_build_floor_light_strips(half_x, half_z, gate_z)


# Two receding rows of amber floor lights flanking the central walkway, marching
# toward the gate. Emissive (unshaded) segments carry the glow; a few low amber
# OmniLights per side wash the deck without lifting the room out of its gloom.
func _build_floor_light_strips(_half_x: float, half_z: float, gate_z: float) -> void:
	var world: Node3D = host._world
	var strip_x: float = 3.8                 # walkway half-width
	var z0: float = -half_z + 2.0            # near the front (exit) wall
	var z1: float = gate_z - 2.6             # stop short of the gate dais
	var spacing: float = 1.7
	var amber: Color = Color(1.0, 0.52, 0.14)
	var seg_mat: StandardMaterial3D = StandardMaterial3D.new()
	seg_mat.albedo_color = amber
	seg_mat.emission_enabled = true
	seg_mat.emission = amber
	seg_mat.emission_energy_multiplier = 3.4
	seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var count: int = int((z1 - z0) / spacing)
	for side: float in [-1.0, 1.0]:
		for i in range(count + 1):
			var z: float = z0 + float(i) * spacing
			var seg: MeshInstance3D = MeshInstance3D.new()
			seg.name = "FloorStrip"
			var bm: BoxMesh = BoxMesh.new()
			bm.size = Vector3(0.5, 0.05, 1.05)
			seg.mesh = bm
			seg.material_override = seg_mat
			seg.position = Vector3(side * strip_x, 0.03, z)   # flush on the floor top (y≈0)
			world.add_child(seg)
		for i in range(4):
			var lz: float = lerpf(z0, z1, float(i) / 3.0)
			var l: OmniLight3D = OmniLight3D.new()
			l.name = "FloorStripGlow"
			l.light_color = amber
			l.light_energy = 1.1
			l.omni_range = 6.5
			l.shadow_enabled = false
			l.position = Vector3(side * strip_x, 0.5, lz)
			world.add_child(l)


# Build the four walls + ceiling + edge glow strips.
func build_walls_and_ceiling() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var ceiling_height: float = host.ceiling_height
	var half_x: float = room_size_v.x * 0.5
	var half_z: float = room_size_v.y * 0.5
	var wall_thickness: float = 0.5

	# Shared Ancient-tech wall-panel texture via RoomBuilder.make_wall_mat —
	# same loader/cache/tile-size as every procedural room. Two material
	# clones because BoxMesh uv1_scale is per-face uniform: ±X walls show
	# room_size.y × ceiling_height; ±Z walls show room_size.x × ceiling_height.
	# Palette tint kept close to the original (0.36, 0.34, 0.38) so the gate
	# room's slightly warmer wall reading survives the texture overlay.
	var wall_palette: Color = Color(0.36, 0.34, 0.38, 1.0)
	var wall_mat_x: StandardMaterial3D = RoomBuilderScript.make_wall_mat(wall_palette, room_size_v.y, ceiling_height)
	var wall_mat_z: StandardMaterial3D = RoomBuilderScript.make_wall_mat(wall_palette, room_size_v.x, ceiling_height)

	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	dark_mat.metallic = 0.25
	dark_mat.roughness = 0.7

	var walls: StaticBody3D = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	world.add_child(walls)

	# Walls are solid — doors are decorative panels recessed INTO the wall, and the
	# scene transition is driven entirely by their E-interact. No archway cutouts.
	# +X wall (right, Crew Quarters side).
	_add_wall_segment(walls, wall_mat_x,
		Vector3(half_x + wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size_v.y))
	# -X wall (left, Mess Hall side).
	_add_wall_segment(walls, wall_mat_x,
		Vector3(-half_x - wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size_v.y))
	# +Z wall (back, behind the gate).
	_add_wall_segment(walls, wall_mat_z,
		Vector3(0.0, ceiling_height * 0.5, half_z + wall_thickness * 0.5),
		Vector3(room_size_v.x, ceiling_height, wall_thickness))
	# -Z wall (front, the EXIT wall) — also solid; ExitDoor sits recessed in it.
	_add_wall_segment(walls, wall_mat_z,
		Vector3(0.0, ceiling_height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(room_size_v.x, ceiling_height, wall_thickness))

	# Ceiling (dark; not a collider for player, only for SpringArm).
	var ceil_body: StaticBody3D = StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 2
	ceil_body.collision_mask = 0
	world.add_child(ceil_body)
	_add_wall_segment(ceil_body, dark_mat, Vector3(0.0, ceiling_height + wall_thickness * 0.5, 0.0),
		Vector3(room_size_v.x, wall_thickness, room_size_v.y))

	# Edge glow strips — emissive boxes hugging the top of every wall. Cool blue
	# to match the reference's icy industrial lighting (was warm amber).
	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.30, 0.55, 0.95, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.32, 0.58, 1.0, 1.0)
	glow_mat.emission_energy_multiplier = 2.6
	glow_mat.metallic = 0.0
	glow_mat.roughness = 0.4
	host._glow_mat = glow_mat                 # so _open_dark can crush these emissive strips
	host._glow_energy0 = glow_mat.emission_energy_multiplier
	var strip_thickness: float = 0.18
	var strip_y: float = ceiling_height - 0.35
	# +X strip
	_add_decorative_box(Vector3(half_x - 0.1, strip_y, 0.0), Vector3(strip_thickness, strip_thickness, room_size_v.y - 1.0), glow_mat)
	# -X strip
	_add_decorative_box(Vector3(-half_x + 0.1, strip_y, 0.0), Vector3(strip_thickness, strip_thickness, room_size_v.y - 1.0), glow_mat)
	# +Z strip
	_add_decorative_box(Vector3(0.0, strip_y, half_z - 0.1), Vector3(room_size_v.x - 1.0, strip_thickness, strip_thickness), glow_mat)
	# -Z strip (split around lintel for visual coherence)
	_add_decorative_box(Vector3(0.0, strip_y, -half_z + 0.1), Vector3(room_size_v.x - 1.0, strip_thickness, strip_thickness), glow_mat)


func _add_wall_segment(parent: StaticBody3D, mat: Material, pos: Vector3, size: Vector3) -> void:
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

func _add_decorative_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	host._world.add_child(mi)

# Runtime-load a prop scene with a null guard + one-time cache. Returns null if
# the asset is missing or not yet imported, so a single bad prop can never take
# the whole gate-room scene down with a parse/preload error.
func prop_scene(path: String) -> PackedScene:
	if _prop_cache.has(path):
		return _prop_cache[path]
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		push_warning("gate_room: prop failed to load (run `godot --headless --import`?): " + path)
	_prop_cache[path] = ps
	return ps


# Instantiate a hero prop by path, or null if it couldn't load. The caller is
# responsible for positioning/scaling and adding it to the tree.
func instance_prop(path: String) -> Node3D:
	var ps: PackedScene = prop_scene(path)
	if ps == null:
		return null
	return ps.instantiate() as Node3D


# Helper for the new hero props: attach a trimesh StaticBody collider so the
# player can walk on the raised platform and (critically) the real metal
# staircase steps without having to jump the base of the gate.
func add_prop_collider(parent: Node3D) -> void:
	if parent == null:
		return
	# Find the main visual mesh (props are usually a single MeshInstance3D or
	# have one prominent child with the geometry).
	var mi: MeshInstance3D = null
	if parent is MeshInstance3D and parent.mesh != null:
		mi = parent
	else:
		for c in parent.get_children():
			if c is MeshInstance3D and c.mesh != null:
				mi = c
				break
			for gc in c.get_children():
				if gc is MeshInstance3D and gc.mesh != null:
					mi = gc
					break
	if mi == null or mi.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	# Accurate trimesh collision for steps and platform top (hero room, one-time cost is fine).
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)


# Build the 3-sided U mezzanine at y = mezzanine_height. Open on the +Z (gate) side.
func build_mezzanine() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var mezzanine_height: float = host.mezzanine_height
	var mezzanine_depth: float = host.mezzanine_depth
	var half_x: float = room_size_v.x * 0.5
	var half_z: float = room_size_v.y * 0.5
	var deck_thickness: float = 0.3
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.34, 1.0)
	mat.metallic = 0.35
	mat.roughness = 0.55

	var deck: StaticBody3D = StaticBody3D.new()
	deck.name = "Mezzanine"
	deck.collision_layer = 1 | 2
	deck.collision_mask = 0
	world.add_child(deck)

	# `mezzanine_height` is the WALKING SURFACE (top of deck). The box centre
	# sits half a deck-thickness below it so the deck top aligns with the
	# stair-top tread top — otherwise the player walks up to a 0.15 m wall at
	# the deck's inside face and gets stuck.
	var deck_center_y: float = mezzanine_height - deck_thickness * 0.5
	# Back deck strip (-Z runs along -Z wall, the "back" facing the gate)
	_add_wall_segment(deck, mat,
		Vector3(0.0, deck_center_y, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size_v.x, deck_thickness, mezzanine_depth))
	# Left deck strip (-X)
	_add_wall_segment(deck, mat,
		Vector3(-half_x + mezzanine_depth * 0.5, deck_center_y, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size_v.y - mezzanine_depth * 2.0))
	# Right deck strip (+X)
	_add_wall_segment(deck, mat,
		Vector3(half_x - mezzanine_depth * 0.5, deck_center_y, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size_v.y - mezzanine_depth * 2.0))

	# Underside trim — a darker thinner mesh on the bottom of each deck strip,
	# reads as architectural soffit and hides the raw box bottom.
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.10, 0.09, 0.11, 1.0)
	trim_mat.metallic = 0.45
	trim_mat.roughness = 0.42
	var trim_y: float = mezzanine_height - deck_thickness - 0.05
	_add_decorative_box(Vector3(0.0, trim_y, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size_v.x, 0.06, mezzanine_depth + 0.1), trim_mat)
	_add_decorative_box(Vector3(-half_x + mezzanine_depth * 0.5, trim_y, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size_v.y - mezzanine_depth * 2.0), trim_mat)
	_add_decorative_box(Vector3(half_x - mezzanine_depth * 0.5, trim_y, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size_v.y - mezzanine_depth * 2.0), trim_mat)

	# Railing along the open (inward-facing) edge of each strip.
	_build_railing()


func _build_railing() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var mezzanine_height: float = host.mezzanine_height
	var mezzanine_depth: float = host.mezzanine_depth
	var half_x: float = room_size_v.x * 0.5
	var half_z: float = room_size_v.y * 0.5
	var inner_x: float = half_x - mezzanine_depth          # right rail x (+12)
	var inner_z_back: float = -half_z + mezzanine_depth    # back rail z (-12)
	var post_spacing: float = 2.0
	var top_rail_y: float = mezzanine_height + RAIL_HEIGHT
	var rail_collider_y: float = mezzanine_height + RAIL_HEIGHT * 0.5

	var post_mat: StandardMaterial3D = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.5
	var accent_mat: StandardMaterial3D = StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.0, 0.6, 0.85, 1.0)
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(0.0, 0.75, 1.0, 1.0)
	accent_mat.emission_energy_multiplier = 5.0
	accent_mat.metallic = 0.0
	accent_mat.roughness = 0.3
	var rail_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.20, 0.20, 0.24, 1.0)
	rail_mat.metallic = 0.6
	rail_mat.roughness = 0.45

	var rail_body: StaticBody3D = StaticBody3D.new()
	rail_body.name = "Railings"
	rail_body.collision_layer = 1 | 2
	rail_body.collision_mask = 0
	world.add_child(rail_body)

	# Stair-landing doorway in the side rails.
	var stair_gap_min: float = STAIR_Z_CENTER - STAIR_WIDTH * 0.5    # -11.2
	var stair_gap_max: float = STAIR_Z_CENTER + STAIR_WIDTH * 0.5    # -8.8

	# ===== Back rail =====
	# Only the *open* inner span needs a rail — outside the inner_x corners the
	# back deck continues onto the side decks at the same y level, so no edge.
	var back_x_min: float = -inner_x   # -12
	var back_x_max: float =  inner_x   # +12
	var back_len: float = back_x_max - back_x_min
	var back_count: int = int(back_len / post_spacing)
	for i in back_count + 1:
		var x: float = back_x_min + i * (back_len / float(back_count))
		_add_rail_post(Vector3(x, mezzanine_height, inner_z_back), post_mat, accent_mat)
	_add_decorative_box(Vector3((back_x_min + back_x_max) * 0.5, top_rail_y, inner_z_back),
		Vector3(back_len, 0.08, 0.08), rail_mat)
	_add_rail_collider(rail_body,
		Vector3((back_x_min + back_x_max) * 0.5, rail_collider_y, inner_z_back),
		Vector3(back_len, RAIL_HEIGHT, RAIL_THICKNESS))

	# ===== Side rails =====
	var side_z_min: float = -half_z + mezzanine_depth    # -12
	var side_z_max: float =  half_z - mezzanine_depth    # +12
	for side_sign in [-1.0, 1.0]:
		var side_x: float = side_sign * inner_x          # ±12
		# Two segments: from side_z_min to the stair gap, and from the stair
		# gap up to side_z_max.
		var seg_a_len: float = stair_gap_min - side_z_min   # 0.8
		var seg_b_len: float = side_z_max - stair_gap_max   # 20.8

		if seg_a_len > 0.05:
			var seg_a_center_z: float = (side_z_min + stair_gap_min) * 0.5
			var seg_a_posts: int = max(1, int(seg_a_len / post_spacing))
			for i in seg_a_posts + 1:
				var z: float = side_z_min + i * (seg_a_len / float(seg_a_posts))
				_add_rail_post(Vector3(side_x, mezzanine_height, z), post_mat, accent_mat)
			_add_decorative_box(Vector3(side_x, top_rail_y, seg_a_center_z),
				Vector3(0.08, 0.08, seg_a_len), rail_mat)
			_add_rail_collider(rail_body,
				Vector3(side_x, rail_collider_y, seg_a_center_z),
				Vector3(RAIL_THICKNESS, RAIL_HEIGHT, seg_a_len))

		if seg_b_len > 0.05:
			var seg_b_center_z: float = (stair_gap_max + side_z_max) * 0.5
			var seg_b_posts: int = max(1, int(seg_b_len / post_spacing))
			for i in seg_b_posts + 1:
				var z: float = stair_gap_max + i * (seg_b_len / float(seg_b_posts))
				_add_rail_post(Vector3(side_x, mezzanine_height, z), post_mat, accent_mat)
			_add_decorative_box(Vector3(side_x, top_rail_y, seg_b_center_z),
				Vector3(0.08, 0.08, seg_b_len), rail_mat)
			_add_rail_collider(rail_body,
				Vector3(side_x, rail_collider_y, seg_b_center_z),
				Vector3(RAIL_THICKNESS, RAIL_HEIGHT, seg_b_len))

	# ===== Open-end rails on the +Z tips of the side mezzanines =====
	var end_count: int = int(mezzanine_depth / post_spacing)
	for side_x_center in [-half_x + mezzanine_depth * 0.5, half_x - mezzanine_depth * 0.5]:
		var x_min: float = side_x_center - mezzanine_depth * 0.5
		for i in end_count + 1:
			var x: float = x_min + i * (mezzanine_depth / float(end_count))
			_add_rail_post(Vector3(x, mezzanine_height, side_z_max), post_mat, accent_mat)
		_add_decorative_box(Vector3(side_x_center, top_rail_y, side_z_max),
			Vector3(mezzanine_depth, 0.08, 0.08), rail_mat)
		_add_rail_collider(rail_body,
			Vector3(side_x_center, rail_collider_y, side_z_max),
			Vector3(mezzanine_depth, RAIL_HEIGHT, RAIL_THICKNESS))


func _add_rail_post(base: Vector3, post_mat: StandardMaterial3D, accent_mat: StandardMaterial3D) -> void:
	# Stem (0.06 × RAIL_HEIGHT × 0.06) topped by a small emissive cyan cap.
	var stem: MeshInstance3D = MeshInstance3D.new()
	var stem_box: BoxMesh = BoxMesh.new()
	stem_box.size = Vector3(0.06, RAIL_HEIGHT, 0.06)
	stem.mesh = stem_box
	stem.material_override = post_mat
	stem.position = base + Vector3(0.0, RAIL_HEIGHT * 0.5, 0.0)
	host._world.add_child(stem)

	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(0.16, 0.06, 0.16)
	cap.mesh = cap_box
	cap.material_override = accent_mat
	cap.position = base + Vector3(0.0, RAIL_HEIGHT - 0.04, 0.0)
	host._world.add_child(cap)


func _add_rail_collider(parent: StaticBody3D, center: Vector3, size: Vector3,
		rotation: Vector3 = Vector3.ZERO) -> void:
	# Thin static-box collider used to give rails actual physics. Without this
	# the decorative rail boxes are mesh-only and the player walks straight
	# through them.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	cs.rotation = rotation
	parent.add_child(cs)


# Two flights, one per side mezzanine. They climb in the X direction
# (perpendicular to the deck's inside edge) so the *top* lands ON the deck
# rather than into its underside, and the *bottom* sits well clear of the
# front wall.
#
#   Right stair: floor at (x=4,  z=-10) → deck at (x=+12, y=5, z=-10)
#   Left stair:  floor at (x=-4, z=-10) → deck at (x=-12, y=5, z=-10)
#
# Collision is a single inclined ramp per stair, NOT per-step boxes.
# CharacterBody3D has no built-in step-up; a stack of 0.5 m collision boxes
# walks like a wall. The visual step meshes sit on top for the staircase
# read; the invisible ramp underneath does the walking.
func build_staircases() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var mezzanine_height: float = host.mezzanine_height
	var half_x: float = room_size_v.x * 0.5
	var step_count: int = 10
	var step_h: float = mezzanine_height / float(step_count)   # 0.5 m
	var step_run: float = 0.8                                   # 0.8 m
	# Shared Ancient-metal panel material on the step treads (was warm emissive).
	var stair_mat: Material = load("res://shaders/ancient_metal_panel.tres")
	if stair_mat == null:
		var fb: StandardMaterial3D = StandardMaterial3D.new()
		fb.albedo_color = Color(0.22, 0.20, 0.24, 1.0)
		fb.metallic = 0.45
		fb.roughness = 0.45
		stair_mat = fb

	var rise: float = mezzanine_height                          # 5
	var run: float = float(step_count) * step_run               # 8
	var ramp_len: float = sqrt(rise * rise + run * run)         # ~9.43
	var slope_angle: float = atan2(rise, run)                   # ~32°
	var x_top_abs: float = half_x - host.mezzanine_depth             # 12 — deck inside edge
	var x_bot_abs: float = x_top_abs - run                      # 4

	for side_sign in [-1.0, 1.0]:
		var x_top: float = side_sign * x_top_abs
		var x_bot: float = side_sign * x_bot_abs
		var x_center: float = (x_top + x_bot) * 0.5             # ±8

		# Visual steps — mesh only.
		for i in step_count:
			var step_y: float = (i + 0.5) * step_h
			var step_x: float = x_bot + side_sign * (float(i) + 0.5) * step_run
			_add_decorative_box(Vector3(step_x, step_y, STAIR_Z_CENTER),
				Vector3(step_run, step_h, STAIR_WIDTH), stair_mat)

		# Single inclined ramp collider — the actual walking surface.
		# Long axis is X; rotating around Z by +slope_angle tilts +X up.
		# For the left stair we want -X up, so rotation.z = side_sign * slope.
		var ramp_body: StaticBody3D = StaticBody3D.new()
		ramp_body.name = "Stairs_%s" % ("L" if side_sign < 0 else "R")
		ramp_body.collision_layer = 1 | 2
		ramp_body.collision_mask = 0
		world.add_child(ramp_body)
		var ramp_cs: CollisionShape3D = CollisionShape3D.new()
		var ramp_shape: BoxShape3D = BoxShape3D.new()
		ramp_shape.size = Vector3(ramp_len, 0.2, STAIR_WIDTH)
		ramp_cs.shape = ramp_shape
		ramp_cs.position = Vector3(x_center, rise * 0.5, STAIR_Z_CENTER)
		ramp_cs.rotation = Vector3(0.0, 0.0, side_sign * slope_angle)
		ramp_body.add_child(ramp_cs)

		# Railings — one on each Z side of the stair so the player can't fall off.
		for rail_sign in [-1.0, 1.0]:
			var rail_z: float = STAIR_Z_CENTER + rail_sign * (STAIR_WIDTH * 0.5)
			_build_stair_railing(x_bot, x_top, rail_z, slope_angle, ramp_len,
				side_sign, step_count, step_h, step_run)


func _build_stair_railing(x_bot: float, x_top: float, rail_z: float, slope_angle: float,
		ramp_len: float, side_sign: float, step_count: int, step_h: float,
		step_run: float) -> void:
	var world: Node3D = host._world
	var mezzanine_height: float = host.mezzanine_height
	# Matches the mezzanine railing palette: dark posts, cyan emissive caps,
	# darker top bar. One post every two steps. Top bar is a single sloped box
	# paired with an invisible inclined collision wall so the rail is solid.
	var post_mat: StandardMaterial3D = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.5
	var accent_mat: StandardMaterial3D = StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.0, 0.6, 0.85, 1.0)
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(0.0, 0.75, 1.0, 1.0)
	accent_mat.emission_energy_multiplier = 5.0
	accent_mat.metallic = 0.0
	accent_mat.roughness = 0.3
	var rail_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.20, 0.20, 0.24, 1.0)
	rail_mat.metallic = 0.6
	rail_mat.roughness = 0.45

	# Vertical posts every two steps. By construction (step_h/step_run == slope)
	# the post tops line up exactly with the sloped top rail.
	for i in range(0, step_count + 1, 2):
		var post_base_y: float = float(i) * step_h
		var post_x: float = x_bot + side_sign * float(i) * step_run
		_add_rail_post(Vector3(post_x, post_base_y, rail_z), post_mat, accent_mat)

	# Top decorative bar — a single rotated box following the slope.
	var x_center: float = (x_bot + x_top) * 0.5
	var top_rail: MeshInstance3D = MeshInstance3D.new()
	var top_box: BoxMesh = BoxMesh.new()
	top_box.size = Vector3(ramp_len, 0.08, 0.08)
	top_rail.mesh = top_box
	top_rail.material_override = rail_mat
	top_rail.position = Vector3(x_center, mezzanine_height * 0.5 + RAIL_HEIGHT, rail_z)
	top_rail.rotation = Vector3(0.0, 0.0, side_sign * slope_angle)
	world.add_child(top_rail)

	# Invisible inclined wall — the actual physics. Same long axis and rotation
	# as the ramp, but RAIL_HEIGHT tall and centred half a rail-height above the
	# tread midline. Aligned closely enough with the steps that the player can't
	# slip under or jump over.
	var rail_body: StaticBody3D = StaticBody3D.new()
	rail_body.name = "StairRail_%s_%s" % [
		"L" if side_sign < 0 else "R",
		"front" if rail_z > STAIR_Z_CENTER else "back",
	]
	rail_body.collision_layer = 1 | 2
	rail_body.collision_mask = 0
	world.add_child(rail_body)
	var rail_cs: CollisionShape3D = CollisionShape3D.new()
	var rail_shape: BoxShape3D = BoxShape3D.new()
	rail_shape.size = Vector3(ramp_len, RAIL_HEIGHT, RAIL_THICKNESS)
	rail_cs.shape = rail_shape
	rail_cs.position = Vector3(x_center, mezzanine_height * 0.5 + RAIL_HEIGHT * 0.5, rail_z)
	rail_cs.rotation = Vector3(0.0, 0.0, side_sign * slope_angle)
	rail_body.add_child(rail_cs)


# The gate is now a floor-pinned, walk-through ring (NO dais, NO stairs) — the
# user can walk straight through it without jumping. We keep only the framing
# furniture from the hero prop pack: flanking operator consoles, the overhead
# ceiling ring, and the cinematic spotlights, all matching the concept art.
func build_gate_platform() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var ceiling_height: float = host.ceiling_height
	var half_z: float = room_size_v.y * 0.5
	var platform_z: float = half_z - 3.8

	# (Removed the extra prop operator-consoles that flanked the gate — the room's
	# real consoles are GateControlConsole + FTLConsole, built by _build_consoles().
	# Park & Volker man those.)

	# === Overhead ceiling ring structure (dramatic circular architecture above gate) ===
	# Native disc normal points along X (AABB thin on X); rotate 90° about Z so the
	# face points up and the ring lies flat against the ceiling above the gate.
	var overhead: Node3D = instance_prop(OVERHEAD_RING_PROP_PATH)
	if overhead != null:
		overhead.scale = Vector3(14.0, 14.0, 14.0)
		overhead.rotation = Vector3(0.0, 0.0, PI * 0.5)
		overhead.position = Vector3(0.0, ceiling_height - 0.4, platform_z)
		world.add_child(overhead)

	# === Spotlights for the cinematic god-ray / volumetric beams in the reference ===
	var spot_l: Node3D = instance_prop(SPOTLIGHT_PROP_PATH)
	if spot_l != null:
		spot_l.scale = Vector3(2.2, 2.2, 2.2)
		spot_l.position = Vector3(-4.5, ceiling_height - 1.0, platform_z + 1.5)
		world.add_child(spot_l)
	var spot_r: Node3D = instance_prop(SPOTLIGHT_PROP_PATH)
	if spot_r != null:
		spot_r.scale = Vector3(2.2, 2.2, 2.2)
		spot_r.position = Vector3(4.5, ceiling_height - 1.0, platform_z + 1.5)
		world.add_child(spot_r)

	# (The old inlay ring and simple slab are superseded by the new props.
	# Any ancient_metal materials on the new GLBs will be used as authored.)


# Industrial wall columns: tall vertical structures that frame the gate (the
# angular "wings" either side of it in the reference) and march along the side
# walls for the cathedral-of-machinery read. Prop is normalized to a 1-unit box
# (tall axis = Y), so scale.y ≈ height in metres.
func build_structural_columns() -> void:
	var world: Node3D = host._world
	var room_size_v: Vector2 = host.room_size
	var ceiling_height: float = host.ceiling_height
	var half_x: float = room_size_v.x * 0.5
	var gate_z: float = room_size_v.y * 0.5 - 3.8
	var col_scale: Vector3 = Vector3(4.0, ceiling_height, 4.0)
	# Two columns flanking the gate (the reference's framing wings).
	for sx in [-1.0, 1.0]:
		var flank: Node3D = instance_prop(INDUSTRIAL_COLUMN_PROP_PATH)
		if flank != null:
			flank.scale = col_scale
			flank.position = Vector3(sx * 7.0, 0.0, gate_z - 0.5)
			world.add_child(flank)
	# A row marching down each side wall.
	for sx in [-1.0, 1.0]:
		for cz in [-8.0, 0.0, 8.0]:
			var col: Node3D = instance_prop(INDUSTRIAL_COLUMN_PROP_PATH)
			if col != null:
				col.scale = col_scale
				col.position = Vector3(sx * (half_x - 0.8), 0.0, cz)
				world.add_child(col)

	# Angular truss "wings": diagonal beams from each flanking column up toward the
	# centre over the gate, framing it in an A-frame like the concept art.
	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.13, 0.14, 0.17, 1.0)
	beam_mat.metallic = 0.55
	beam_mat.roughness = 0.45
	var base_xy: Vector2 = Vector2(7.0, 2.5)      # foot at the flank column
	var apex_xy: Vector2 = Vector2(0.0, 11.2)     # both beams meet at a clean apex (A-frame)
	var span: Vector2 = apex_xy - base_xy
	var beam_len: float = span.length()
	var beam_tilt: float = atan2(absf(span.x), span.y)   # lean from vertical
	for sx in [-1.0, 1.0]:
		var mid: Vector2 = (base_xy + apex_xy) * 0.5
		var beam: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.5, beam_len, 0.5)
		beam.mesh = bm
		beam.material_override = beam_mat
		beam.position = Vector3(sx * mid.x, mid.y, gate_z - 0.4)
		beam.rotation.z = sx * beam_tilt    # top leans inward toward the centre
		world.add_child(beam)


# Build the two operator consoles (GateControlConsole + FTLConsole) on the
# deck-1 floor, facing the gate. Both use the SHARED Ancient-tech console mesh
# (RoomBuilder.attach_console_mesh) — same silhouette, same tweak surface as
# the control-room consoles.
func build_consoles() -> void:
	var world: Node3D = host._world
	var gate_console_script: Script = preload("res://scripts/gate_console.gd")
	var z_console: float = -4.0   # GATE_CONSOLE_Z
	for spec in [
		{"name": "GateControlConsole", "x": -3.5, "kind": "gate_control"},
		{"name": "FTLConsole",         "x":  3.5, "kind": "ftl_countdown"},
	]:
		var holder: Node3D = Node3D.new()
		holder.name = spec["name"]
		holder.position = Vector3(spec["x"], 0.0, z_console)
		# Yaw 180° flips the shared mesh so its operator-controls face the
		# player who's approaching from -Z (gate-room arrival side). Without
		# this the chunky back of the console points at the player and the
		# controls are reachable only by walking around the unit.
		holder.rotation = Vector3(0.0, PI, 0.0)
		world.add_child(holder)
		RoomBuilderScript.attach_console_mesh(holder)

		var inter: StaticBody3D = StaticBody3D.new()
		inter.set_script(gate_console_script)
		inter.name = "Interactable"
		inter.set("kind", spec["kind"])
		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(1.8, 1.6, 1.2)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.8, 0.0)
		inter.add_child(cs)
		holder.add_child(inter)