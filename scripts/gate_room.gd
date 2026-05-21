extends Node3D

# Phase A: cavernous two-deck gateroom — Destiny's "altar". Procedurally builds
# the hero space so the .tscn stays small and re-runs cheap. Layout:
#
#   • Origin at room centre. +Z = "altar end" (the Stargate); -Z = exit wall
#     with twin staircases and the corridor archway.
#   • 32 m × 32 m footprint, 9 m ceiling, mezzanine deck at y = 5 m on three
#     sides (back, left, right) — open on the +Z side so you can look down on
#     the gate from the back balcony.
#   • Gate platform: stepped bronze dais 8 m × 6 m × 1 m at +Z end. Stargate
#     mounted at y ≈ 4 m on top of it.
#   • Lighting: amber floor uplights washing the upper walls, cyan accents
#     along the mezzanine rail, and an emissive strip ringing the ceiling.

const STARGATE_SCENE: PackedScene = preload("res://objects/stargate.tscn")
const FLOOR_SCENE: PackedScene = preload("res://models/sci-fi/space-station/floor.glb")
const CONSOLE_SCENE: PackedScene = preload("res://models/sci-fi/space-station/computer.glb")
const GATE_CONSOLE_SCRIPT: Script = preload("res://scripts/gate_console.gd")

@export_group("Room")
@export var room_size: Vector2 = Vector2(32.0, 32.0)
@export var tile_size: float = 2.0
@export var deck1_height: float = 0.0
@export var mezzanine_height: float = 5.0
@export var ceiling_height: float = 9.0
@export var mezzanine_depth: float = 4.0     # how far the mezzanine extends inward from walls
@export var exit_width: float = 3.2

@export_group("Arrival")
# Total time the portal stays cyan after spawn (player input locked the whole hold).
@export var arrival_hold: float = 1.5
@export var arrival_fade: float = 1.0

@onready var _world: Node3D = $World
@onready var _player: CharacterBody3D = $Player
@onready var _view: Node3D = $View
@onready var _ambient_sfx: AudioStreamPlayer = $AmbientHum
@onready var _gate_loop_sfx: AudioStreamPlayer = $GateActiveLoop
@onready var _gate_shutdown_sfx: AudioStreamPlayer = $GateShutdown

var _stargate: Node3D
var _from_gate_marker: Marker3D
var _from_corridor_marker: Marker3D

func _ready() -> void:
	# Tell the save system this is a real gameplay scene.
	GameState.current_scene_path = "res://scenes/gate_room.tscn"

	# Build the room and gate furniture before anything else looks for nodes.
	_build_floor()
	_build_walls_and_ceiling()
	_build_mezzanine()
	_build_staircases()
	_build_gate_platform()
	_build_consoles()
	_build_lighting_props()

	# Spawn the gate model on the dais.
	_stargate = STARGATE_SCENE.instantiate()
	_stargate.name = "Stargate"
	# Gate diameter 6 m → centre at y = 4 means bottom rim at y = 1 (on the dais).
	_stargate.position = Vector3(0.0, 4.0, room_size.y * 0.5 - 3.8)
	_world.add_child(_stargate)

	# Place the spawn markers now that the room geometry is in place.
	_create_spawn_markers()

	# Discover + run arrival branch. If resuming from save, skip the cinematic.
	var first_visit: bool = not GameState.rooms_discovered.has("gate_room")
	GameState.discover_room("gate_room", "Gate Room")

	if GameState.skip_arrival_cinematic and GameState.pending_spawn_position != null:
		# Continue-from-save: place player at saved position with their facing.
		_apply_pending_save_spawn()
		GameState.skip_arrival_cinematic = false
		GameState.pending_spawn_position = null
		# Gate already dormant.
		if _stargate != null and "active" in _stargate:
			_stargate.active = false
		_start_ambient()
	elif first_visit:
		_run_arrival()
	else:
		# Re-entry from corridor — no cinematic, gate dormant.
		if _stargate != null and "active" in _stargate:
			_stargate.active = false
		_start_ambient()

# ----- spawn -----------------------------------------------------------------

func _create_spawn_markers() -> void:
	# "FromGate" — player just stepped through the portal, on the dais, facing -Z.
	_from_gate_marker = $FromGate
	_from_gate_marker.position = Vector3(0.0, 1.05, room_size.y * 0.5 - 5.5)
	_from_gate_marker.rotation = Vector3.ZERO  # -Z forward = facing the room
	# "FromCorridor" — re-enters from the exit archway, facing +Z toward the gate.
	_from_corridor_marker = $FromCorridor
	_from_corridor_marker.position = Vector3(0.0, 0.5, -room_size.y * 0.5 + 2.5)
	_from_corridor_marker.rotation = Vector3(0.0, PI, 0.0)  # face +Z (toward gate)

func _apply_pending_save_spawn() -> void:
	if _player == null:
		return
	_player.global_position = GameState.pending_spawn_position
	_player.rotation.y = GameState.pending_spawn_yaw

# ----- arrival ---------------------------------------------------------------

func _run_arrival() -> void:
	# Player spawns on the dais facing outward; gate active behind them.
	GameState.set_objective("Find a way off this ship")
	GameState.add_log("Eli: Okay… where am I?")
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(true)
	if _stargate != null and "active" in _stargate:
		_stargate.active = true
	if _gate_loop_sfx != null and _gate_loop_sfx.stream != null:
		_gate_loop_sfx.play()

	# Hold on the active portal so the player registers the cyan glow behind them.
	await get_tree().create_timer(arrival_hold).timeout

	# Collapse: shut the portal, play the whoosh, hand control back.
	if _stargate != null and "active" in _stargate:
		_stargate.active = false
	if _gate_loop_sfx != null and _gate_loop_sfx.playing:
		var t: Tween = create_tween()
		t.tween_property(_gate_loop_sfx, "volume_db", -60.0, arrival_fade)
		t.tween_callback(Callable(_gate_loop_sfx, "stop"))
	if _gate_shutdown_sfx != null and _gate_shutdown_sfx.stream != null:
		_gate_shutdown_sfx.play()

	_start_ambient()
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(false)

func _start_ambient() -> void:
	if _ambient_sfx != null and not _ambient_sfx.playing:
		_ambient_sfx.play()

# ----- procedural geometry ---------------------------------------------------

func _build_floor() -> void:
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	# Single mesh-based floor — Kenney tiles would cost 256 instances at 2 m
	# pitch. A BoxMesh + offset gives the same look at one draw call.
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Floor"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(room_size.x, 0.2, room_size.y)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.155, 0.17, 1.0)
	mat.metallic = 0.32
	mat.roughness = 0.62
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.1, 0.0)
	_world.add_child(mi)

	# Floor collider.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "FloorCollider"
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	_world.add_child(body)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(room_size.x, 0.2, room_size.y)
	cs.shape = shape
	cs.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(cs)

	# Inlay: bronze ring of light tiles around the gate dais (visual interest).
	var inlay_mat: StandardMaterial3D = StandardMaterial3D.new()
	inlay_mat.albedo_color = Color(0.18, 0.13, 0.06, 1.0)
	inlay_mat.metallic = 0.7
	inlay_mat.roughness = 0.35
	inlay_mat.emission_enabled = true
	inlay_mat.emission = Color(1.0, 0.45, 0.12, 1.0)
	inlay_mat.emission_energy_multiplier = 0.6
	var inlay: MeshInstance3D = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 5.0
	ring.outer_radius = 5.4
	ring.ring_segments = 64
	ring.rings = 8
	inlay.mesh = ring
	inlay.material_override = inlay_mat
	inlay.position = Vector3(0.0, 0.02, half_z - 4.0)
	_world.add_child(inlay)


func _build_walls_and_ceiling() -> void:
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	var wall_thickness: float = 0.5

	var wall_mat: StandardMaterial3D = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.21, 0.20, 0.23, 1.0)
	wall_mat.metallic = 0.30
	wall_mat.roughness = 0.65

	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.13, 0.13, 0.16, 1.0)
	dark_mat.metallic = 0.25
	dark_mat.roughness = 0.7

	var walls: StaticBody3D = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	_world.add_child(walls)

	# +X wall (right, solid).
	_add_wall_segment(walls, wall_mat, Vector3(half_x + wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size.y))
	# -X wall (left, solid).
	_add_wall_segment(walls, wall_mat, Vector3(-half_x - wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size.y))
	# +Z wall (back, behind the gate — solid).
	_add_wall_segment(walls, wall_mat, Vector3(0.0, ceiling_height * 0.5, half_z + wall_thickness * 0.5),
		Vector3(room_size.x, ceiling_height, wall_thickness))

	# -Z wall (front, the EXIT wall) — split around the archway opening.
	var arch_h: float = 3.2
	var top_h: float = ceiling_height - arch_h
	var side_w: float = (room_size.x - exit_width) * 0.5
	# Left of arch
	_add_wall_segment(walls, wall_mat, Vector3(-half_x + side_w * 0.5, ceiling_height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(side_w, ceiling_height, wall_thickness))
	# Right of arch
	_add_wall_segment(walls, wall_mat, Vector3(half_x - side_w * 0.5, ceiling_height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(side_w, ceiling_height, wall_thickness))
	# Lintel above the arch
	_add_wall_segment(walls, wall_mat, Vector3(0.0, arch_h + top_h * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(exit_width, top_h, wall_thickness))

	# Ceiling (dark; not a collider for player, only for SpringArm).
	var ceil_body: StaticBody3D = StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 2
	ceil_body.collision_mask = 0
	_world.add_child(ceil_body)
	_add_wall_segment(ceil_body, dark_mat, Vector3(0.0, ceiling_height + wall_thickness * 0.5, 0.0),
		Vector3(room_size.x, wall_thickness, room_size.y))

	# Edge glow strips — emissive amber boxes hugging the top of every wall.
	# Creates the "ring of light at the top of the wall" the reference image shows.
	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.55, 0.18, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	glow_mat.emission_energy_multiplier = 4.0
	glow_mat.metallic = 0.0
	glow_mat.roughness = 0.4
	var strip_thickness: float = 0.18
	var strip_y: float = ceiling_height - 0.35
	# +X strip
	_add_decorative_box(Vector3(half_x - 0.1, strip_y, 0.0), Vector3(strip_thickness, strip_thickness, room_size.y - 1.0), glow_mat)
	# -X strip
	_add_decorative_box(Vector3(-half_x + 0.1, strip_y, 0.0), Vector3(strip_thickness, strip_thickness, room_size.y - 1.0), glow_mat)
	# +Z strip
	_add_decorative_box(Vector3(0.0, strip_y, half_z - 0.1), Vector3(room_size.x - 1.0, strip_thickness, strip_thickness), glow_mat)
	# -Z strip (split around lintel for visual coherence)
	_add_decorative_box(Vector3(0.0, strip_y, -half_z + 0.1), Vector3(room_size.x - 1.0, strip_thickness, strip_thickness), glow_mat)


func _add_wall_segment(parent: StaticBody3D, mat: StandardMaterial3D, pos: Vector3, size: Vector3) -> void:
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

func _add_decorative_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	_world.add_child(mi)


func _build_mezzanine() -> void:
	# 3-sided U mezzanine at y = mezzanine_height. Open on the +Z (gate) side.
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	var deck_thickness: float = 0.3
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.18, 0.21, 1.0)
	mat.metallic = 0.35
	mat.roughness = 0.55

	var deck: StaticBody3D = StaticBody3D.new()
	deck.name = "Mezzanine"
	deck.collision_layer = 1 | 2
	deck.collision_mask = 0
	_world.add_child(deck)

	# Back deck strip (-Z runs along -Z wall, the "back" facing the gate)
	_add_wall_segment(deck, mat,
		Vector3(0.0, mezzanine_height, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size.x, deck_thickness, mezzanine_depth))
	# Left deck strip (-X)
	_add_wall_segment(deck, mat,
		Vector3(-half_x + mezzanine_depth * 0.5, mezzanine_height, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size.y - mezzanine_depth * 2.0))
	# Right deck strip (+X)
	_add_wall_segment(deck, mat,
		Vector3(half_x - mezzanine_depth * 0.5, mezzanine_height, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size.y - mezzanine_depth * 2.0))

	# Underside trim — a darker thinner mesh on the bottom of each deck strip,
	# reads as architectural soffit and hides the raw box bottom.
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.10, 0.09, 0.11, 1.0)
	trim_mat.metallic = 0.45
	trim_mat.roughness = 0.42
	_add_decorative_box(Vector3(0.0, mezzanine_height - deck_thickness * 0.5 - 0.05, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size.x, 0.06, mezzanine_depth + 0.1), trim_mat)
	_add_decorative_box(Vector3(-half_x + mezzanine_depth * 0.5, mezzanine_height - deck_thickness * 0.5 - 0.05, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size.y - mezzanine_depth * 2.0), trim_mat)
	_add_decorative_box(Vector3(half_x - mezzanine_depth * 0.5, mezzanine_height - deck_thickness * 0.5 - 0.05, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size.y - mezzanine_depth * 2.0), trim_mat)

	# Railing along the open (inward-facing) edge of each strip.
	_build_railing()


func _build_railing() -> void:
	# Modular railing: short emissive cyan posts at intervals connected by a
	# darker top rail. Posts double as "rail accent" lights — they have a
	# strong emissive cyan top that reads at distance.
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	var inner_x: float = half_x - mezzanine_depth          # right rail x
	var inner_z_back: float = -half_z + mezzanine_depth    # back rail z (front edge of back deck)
	var post_spacing: float = 2.0
	var top_rail_y: float = mezzanine_height + 1.0

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

	# Back rail (runs along x at z = inner_z_back).
	var back_count: int = int(room_size.x / post_spacing)
	for i in back_count + 1:
		var x: float = -half_x + i * post_spacing
		_add_rail_post(Vector3(x, mezzanine_height, inner_z_back), post_mat, accent_mat)
	_add_decorative_box(Vector3(0.0, top_rail_y, inner_z_back), Vector3(room_size.x, 0.08, 0.08), rail_mat)

	# Side rails (-X and +X) — span z range minus mezzanine_depth on each end.
	var side_z_min: float = -half_z + mezzanine_depth
	var side_z_max: float = half_z - mezzanine_depth
	var side_count: int = int((side_z_max - side_z_min) / post_spacing)
	for side_x in [-(half_x - mezzanine_depth), half_x - mezzanine_depth]:
		for i in side_count + 1:
			var z: float = side_z_min + i * post_spacing
			_add_rail_post(Vector3(side_x, mezzanine_height, z), post_mat, accent_mat)
		_add_decorative_box(Vector3(side_x, top_rail_y, (side_z_min + side_z_max) * 0.5),
			Vector3(0.08, 0.08, side_z_max - side_z_min), rail_mat)

	# Open-end rails on the side mezzanines (+Z end faces the gate — would
	# otherwise be a fall-off-the-edge hazard when walking past the inside rail
	# and out onto the gate-facing tip of the side deck).
	var end_count: int = int(mezzanine_depth / post_spacing)
	for side_x in [-half_x + mezzanine_depth * 0.5, half_x - mezzanine_depth * 0.5]:
		var x_min: float = side_x - mezzanine_depth * 0.5
		for i in end_count + 1:
			var x: float = x_min + i * (mezzanine_depth / float(end_count))
			_add_rail_post(Vector3(x, mezzanine_height, side_z_max), post_mat, accent_mat)
		_add_decorative_box(Vector3(side_x, top_rail_y, side_z_max),
			Vector3(mezzanine_depth, 0.08, 0.08), rail_mat)


func _add_rail_post(base: Vector3, post_mat: StandardMaterial3D, accent_mat: StandardMaterial3D) -> void:
	# Stem (0.06 × 1.0 × 0.06) topped by a small emissive cyan cap (0.16 × 0.06 × 0.16).
	var stem: MeshInstance3D = MeshInstance3D.new()
	var stem_box: BoxMesh = BoxMesh.new()
	stem_box.size = Vector3(0.06, 1.0, 0.06)
	stem.mesh = stem_box
	stem.material_override = post_mat
	stem.position = base + Vector3(0.0, 0.5, 0.0)
	_world.add_child(stem)

	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(0.16, 0.06, 0.16)
	cap.mesh = cap_box
	cap.material_override = accent_mat
	cap.position = base + Vector3(0.0, 0.96, 0.0)
	_world.add_child(cap)


func _build_staircases() -> void:
	# Two straight diagonal flights flanking the exit archway: bottom near the
	# -Z wall, climbing toward +Z up to the side mezzanines.
	#
	# Collision is a single inclined ramp per stair, NOT per-step boxes.
	# CharacterBody3D has no built-in step-up; a stack of 0.5 m collision boxes
	# walks like a wall. The visual step meshes remain on top for the staircase
	# read; the invisible ramp underneath does the walking.
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	var step_count: int = 10
	var step_h: float = mezzanine_height / float(step_count)   # 0.5 m
	var step_run: float = 0.8
	var stair_width: float = 2.4
	var stair_mat: StandardMaterial3D = StandardMaterial3D.new()
	stair_mat.albedo_color = Color(0.22, 0.18, 0.13, 1.0)
	stair_mat.metallic = 0.45
	stair_mat.roughness = 0.45
	stair_mat.emission_enabled = true
	stair_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	stair_mat.emission_energy_multiplier = 0.18

	var z_start: float = -half_z + 1.0
	var rise: float = mezzanine_height
	var run: float = step_count * step_run
	var ramp_len: float = sqrt(rise * rise + run * run)
	var slope_angle: float = atan2(rise, run)

	for side_sign in [-1.0, 1.0]:
		var x_center: float = side_sign * (half_x - mezzanine_depth * 0.5)

		# Visual steps — mesh only, no collider.
		for i in step_count:
			var step_y: float = (i + 0.5) * step_h
			var step_z: float = z_start + i * step_run + step_run * 0.5
			_add_decorative_box(Vector3(x_center, step_y, step_z),
				Vector3(stair_width, step_h, step_run), stair_mat)

		# Single inclined ramp collider — the actual walking surface.
		# Positive X rotation in Godot's right-handed system tilts +Z toward -Y,
		# so to put the +Z end up (matching the stair climbing from -Z to +Z)
		# we rotate by NEGATIVE slope_angle.
		var ramp_body: StaticBody3D = StaticBody3D.new()
		ramp_body.name = "Stairs_%s" % ("L" if side_sign < 0 else "R")
		ramp_body.collision_layer = 1 | 2
		ramp_body.collision_mask = 0
		_world.add_child(ramp_body)
		var ramp_cs: CollisionShape3D = CollisionShape3D.new()
		var ramp_shape: BoxShape3D = BoxShape3D.new()
		ramp_shape.size = Vector3(stair_width, 0.2, ramp_len)
		ramp_cs.shape = ramp_shape
		ramp_cs.position = Vector3(x_center, rise * 0.5, z_start + run * 0.5)
		ramp_cs.rotation = Vector3(-slope_angle, 0.0, 0.0)
		ramp_body.add_child(ramp_cs)

		# Railings — one on each side of the stair so the player can't fall off.
		for rail_sign in [-1.0, 1.0]:
			var rail_x: float = x_center + rail_sign * (stair_width * 0.5)
			_build_stair_railing(rail_x, z_start, step_count, step_h, step_run,
				slope_angle, ramp_len)


func _build_stair_railing(rail_x: float, z_start: float, step_count: int, step_h: float,
		step_run: float, slope_angle: float, ramp_len: float) -> void:
	# Matches the mezzanine railing palette: dark posts, cyan emissive caps,
	# darker top bar. One post every two steps. Top bar is a single sloped box.
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

	for i in range(0, step_count + 1, 2):
		var post_base_y: float = float(i) * step_h
		var post_z: float = z_start + float(i) * step_run
		_add_rail_post(Vector3(rail_x, post_base_y, post_z), post_mat, accent_mat)

	# Top rail spans from post-top at bottom of stair to post-top at top of
	# stair: (z_start, 1.0) → (z_start + run, mezzanine_height + 1.0).
	var run: float = float(step_count) * step_run
	var top_rail: MeshInstance3D = MeshInstance3D.new()
	var top_box: BoxMesh = BoxMesh.new()
	top_box.size = Vector3(0.08, 0.08, ramp_len)
	top_rail.mesh = top_box
	top_rail.material_override = rail_mat
	top_rail.position = Vector3(rail_x, mezzanine_height * 0.5 + 1.0, z_start + run * 0.5)
	top_rail.rotation = Vector3(-slope_angle, 0.0, 0.0)
	_world.add_child(top_rail)


func _build_gate_platform() -> void:
	# Stepped pedestal on the +Z side: 8 × 6 × 1 main slab + two 0.3 m steps
	# in front so the player visibly climbs onto the dais.
	var half_z: float = room_size.y * 0.5
	var platform_z: float = half_z - 3.8
	var dais_mat: StandardMaterial3D = StandardMaterial3D.new()
	dais_mat.albedo_color = Color(0.24, 0.18, 0.10, 1.0)
	dais_mat.metallic = 0.65
	dais_mat.roughness = 0.40
	dais_mat.emission_enabled = true
	dais_mat.emission = Color(0.6, 0.34, 0.12, 1.0)
	dais_mat.emission_energy_multiplier = 0.22

	# Main slab — kept as a collider so the player stands on the dais top.
	var slab: StaticBody3D = StaticBody3D.new()
	slab.name = "GatePlatform"
	slab.collision_layer = 1 | 2
	slab.collision_mask = 0
	_world.add_child(slab)
	_add_wall_segment(slab, dais_mat, Vector3(0.0, 0.5, platform_z), Vector3(10.0, 1.0, 6.0))

	# Front ceremonial steps — visual only. Their tops (0.33 m, 0.66 m) are
	# too tall for CharacterBody3D to step up; the ramp collider below handles
	# the actual climb so the visible steps stay decorative.
	_add_decorative_box(Vector3(0.0, 0.33, platform_z - 3.6), Vector3(8.0, 0.66, 1.2), dais_mat)
	_add_decorative_box(Vector3(0.0, 0.165, platform_z - 4.8), Vector3(6.0, 0.33, 1.2), dais_mat)

	# Hidden ramp collider: from (y=0, z=front-of-step-2) up to (y=1, z=front-of-slab).
	# Step #2 front: platform_z - 4.8 - 0.6 = platform_z - 5.4
	# Slab front:    platform_z - 3.0
	# Run = 2.4 m, rise = 1.0 m → slope ≈ 22.6° (well under floor_max_angle).
	var ramp_run: float = 2.4
	var ramp_rise: float = 1.0
	var ramp_len: float = sqrt(ramp_run * ramp_run + ramp_rise * ramp_rise)
	var ramp_angle: float = atan2(ramp_rise, ramp_run)
	var dais_ramp: StaticBody3D = StaticBody3D.new()
	dais_ramp.name = "DaisRamp"
	dais_ramp.collision_layer = 1 | 2
	dais_ramp.collision_mask = 0
	_world.add_child(dais_ramp)
	var ramp_cs: CollisionShape3D = CollisionShape3D.new()
	var ramp_shape: BoxShape3D = BoxShape3D.new()
	ramp_shape.size = Vector3(8.0, 0.2, ramp_len)
	ramp_cs.shape = ramp_shape
	ramp_cs.position = Vector3(0.0, ramp_rise * 0.5, platform_z - 3.0 - ramp_run * 0.5)
	ramp_cs.rotation = Vector3(-ramp_angle, 0.0, 0.0)
	dais_ramp.add_child(ramp_cs)


func _build_consoles() -> void:
	# Two consoles on the deck-1 floor, facing the gate (i.e. looking +Z).
	# Player walks down the front steps and reaches them between the dais and
	# the centre of the room.
	var half_z: float = room_size.y * 0.5
	var z_console: float = half_z - 10.5
	for spec in [
		{"name": "GateControlConsole", "x": -3.5, "kind": "gate_control"},
		{"name": "FTLConsole",         "x":  3.5, "kind": "ftl_countdown"},
	]:
		var holder: Node3D = Node3D.new()
		holder.name = spec["name"]
		holder.position = Vector3(spec["x"], 0.0, z_console)
		# Make the console face +Z (toward the gate) so the player reads it
		# from the gate-room side. Default console model points -Z.
		holder.rotation = Vector3(0.0, PI, 0.0)
		_world.add_child(holder)

		var mesh: Node3D = CONSOLE_SCENE.instantiate()
		mesh.scale = Vector3(1.4, 1.4, 1.4)
		holder.add_child(mesh)

		# Wrap with a StaticBody3D on the interactable layer.
		var inter: StaticBody3D = StaticBody3D.new()
		inter.set_script(GATE_CONSOLE_SCRIPT)
		inter.name = "Interactable"
		inter.set("kind", spec["kind"])
		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(1.8, 1.8, 1.4)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.9, 0.0)
		inter.add_child(cs)
		holder.add_child(inter)


func _build_lighting_props() -> void:
	# Atmospheric uplights — amber OmniLights at floor level pointed up by
	# placement, washing the upper walls warm. Plus dedicated SpotLights aimed
	# at the gate from below.
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5

	# Floor uplights around the perimeter (4 corners + 2 mid-walls).
	var uplight_positions: Array = [
		Vector3(-half_x + 2.0, 0.5,  half_z - 2.0),
		Vector3( half_x - 2.0, 0.5,  half_z - 2.0),
		Vector3(-half_x + 2.0, 0.5, -half_z + 2.0),
		Vector3( half_x - 2.0, 0.5, -half_z + 2.0),
		Vector3(-half_x + 2.0, 0.5, 0.0),
		Vector3( half_x - 2.0, 0.5, 0.0),
	]
	for p in uplight_positions:
		var l: OmniLight3D = OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.20, 1.0)
		l.light_energy = 2.4
		l.omni_range = 11.0
		l.omni_attenuation = 1.6
		l.position = p
		_world.add_child(l)

	# Gate uplighting: 1 spot from directly in front, 2 from the sides.
	# look_at() requires the node to already be inside the tree, so add_child
	# before re-orienting; otherwise the call quietly errors and the spotlight
	# points along its default axis.
	var gate_center: Vector3 = Vector3(0.0, 4.0, half_z - 3.8)
	# Front spot
	var front_spot: SpotLight3D = SpotLight3D.new()
	front_spot.light_color = Color(1.0, 0.65, 0.25, 1.0)
	front_spot.light_energy = 6.0
	front_spot.spot_range = 14.0
	front_spot.spot_angle = 35.0
	front_spot.position = Vector3(0.0, 1.2, gate_center.z - 5.5)
	_world.add_child(front_spot)
	front_spot.look_at(gate_center, Vector3.UP)
	# Side spots
	for sx in [-1.0, 1.0]:
		var side: SpotLight3D = SpotLight3D.new()
		side.light_color = Color(1.0, 0.55, 0.18, 1.0)
		side.light_energy = 4.0
		side.spot_range = 12.0
		side.spot_angle = 32.0
		side.position = Vector3(sx * 5.5, 1.2, gate_center.z - 1.5)
		_world.add_child(side)
		side.look_at(gate_center, Vector3.UP)

	# Soft top key light — directional, slightly cool. Establishes the "shafts
	# from above" feel even without a volumetric pass.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(0.78, 0.86, 1.0, 1.0)
	key.light_energy = 0.45
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	# Tilt to come "from above and front" (-Y mostly, slight +Z).
	key.rotation = Vector3(deg_to_rad(-72.0), deg_to_rad(15.0), 0.0)
	_world.add_child(key)
