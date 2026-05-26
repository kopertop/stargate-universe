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
const GATE_CONSOLE_SCRIPT: Script = preload("res://scripts/gate_console.gd")
const NPC_SCRIPT: Script = preload("res://scripts/npc.gd")
const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")
const QuestWaypointScript: Script = preload("res://scripts/quest_waypoint.gd")
# Preload bypasses class_name registration timing — same reason as room.gd.
const ShipAlertScript: Script = preload("res://scripts/ship_alert.gd")
const QUEST_WAYPOINT_ANCHOR_HEIGHT: float = 2.4
const QUEST_WAYPOINT_DOOR_HEIGHT: float = 1.8

# Railings are tall enough that the player's 0.6 m jump (jump² / 2·g ≈ 0.6 m
# given the player's tunables) can't clear them. Combined with the per-rail
# collider below, the rail is unjumpable AND impassable.
const RAIL_HEIGHT: float = 1.4
const RAIL_THICKNESS: float = 0.1
# Stair landing geometry — also referenced by the railing code so the side
# mezzanine rail can leave a doorway for the stair.
const STAIR_WIDTH: float = 2.4
const STAIR_Z_CENTER: float = -10.0

@export_group("Room")
@export var room_size: Vector2 = Vector2(32.0, 32.0)
@export var tile_size: float = 2.0
@export var deck1_height: float = 0.0
@export var mezzanine_height: float = 5.0
@export var ceiling_height: float = 9.0
@export var mezzanine_depth: float = 4.0     # how far the mezzanine extends inward from walls

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
var _from_east_connector_marker: Marker3D
var _gate_portal: Area3D
var _arrival_running: bool = false
var _quest_waypoint: Node3D = null

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
	_build_npcs()
	_build_lighting_props()

	# Red-alert tint catches every light spawned by the build helpers above.
	# Tints the WorldEnvironment ambient too so the gate room reads as the
	# same emergency state as the procedural rooms.
	if ShipAlertScript.is_alert_active():
		ShipAlertScript.apply_to_scene(self)

	# Spawn the gate model on the dais.
	_stargate = STARGATE_SCENE.instantiate()
	_stargate.name = "Stargate"
	# Gate diameter 6 m → centre at y = 4 means bottom rim at y = 1 (on the dais).
	_stargate.position = Vector3(0.0, 4.0, room_size.y * 0.5 - 3.8)
	_world.add_child(_stargate)
	_build_ship_gate_portal()

	# Place the spawn markers now that the room geometry is in place.
	_create_spawn_markers()

	# Discover + run arrival branch. If resuming from save, skip the cinematic.
	var first_visit: bool = not GameState.rooms_discovered.has("gate_room")
	GameState.discover_room("gate_room", "Gate Room")
	GameState.set_current_room("gate_room")

	# Quest diamond — same pattern as room.gd. Refresh on objective_changed.
	_refresh_quest_waypoint()
	if not GameState.objective_changed.is_connected(_on_quest_objective_changed):
		GameState.objective_changed.connect(_on_quest_objective_changed)

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

func _process(_delta: float) -> void:
	_refresh_lime_gate_state()

# ----- spawn -----------------------------------------------------------------

func _create_spawn_markers() -> void:
	# "FromGate" — player just stepped through the portal, on the dais, facing -Z.
	_from_gate_marker = $FromGate
	_from_gate_marker.position = Vector3(0.0, 1.05, room_size.y * 0.5 - 5.5)
	_from_gate_marker.rotation = Vector3.ZERO  # -Z forward = facing the room
	# "FromCorridor" — re-enters from the exit archway, facing +Z toward the gate.
	# y=0.05 keeps the capsule bottom (player.y + 0.05) just above the main floor.
	_from_corridor_marker = $FromCorridor
	_from_corridor_marker.position = Vector3(0.0, 0.05, -room_size.y * 0.5 + 2.5)
	_from_corridor_marker.rotation = Vector3(0.0, PI, 0.0)  # face +Z (toward gate)
	# Factory-routed reverse edge from `stargate_corridor_east_connector` —
	# room.gd::_stamp_door auto-derives the spawn key as
	# "From" + _to_camel(room_id). Same landing as FromCorridor.
	_from_east_connector_marker = $FromStargateCorridorEastConnector
	_from_east_connector_marker.position = _from_corridor_marker.position
	_from_east_connector_marker.rotation = _from_corridor_marker.rotation

func _apply_pending_save_spawn() -> void:
	if _player == null:
		return
	_player.global_position = GameState.pending_spawn_position
	_player.rotation.y = GameState.pending_spawn_yaw

# ----- arrival ---------------------------------------------------------------

func _run_arrival() -> void:
	_arrival_running = true
	# Player spawns on the dais facing outward; gate active behind them.
	GameState.set_objective("Talk to Lt Scott.")
	GameState.add_log("Eli: Okay… where am I?")
	GameState.add_log("Lt Scott: Hey — over here. We need to figure out where we are.")
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
	_arrival_running = false

func _build_ship_gate_portal() -> void:
	_gate_portal = Area3D.new()
	_gate_portal.set_script(PLANET_GATE_SCRIPT)
	_gate_portal.name = "ShipGatePortal"
	_gate_portal.position = Vector3(0.0, 2.35, room_size.y * 0.5 - 3.8)
	_gate_portal.set("mode", "to_planet")
	_gate_portal.set("target_scene", "res://scenes/planet.tscn")
	_gate_portal.set("target_spawn", "FromShipGate")
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.4, 3.2, 1.2)
	cs.shape = shape
	_gate_portal.add_child(cs)
	_world.add_child(_gate_portal)
	_gate_portal.monitoring = false

func _refresh_lime_gate_state() -> void:
	if _arrival_running:
		return
	var gate_open: bool = GameState.is_lime_gate_open()
	if _stargate != null and "active" in _stargate:
		_stargate.active = gate_open
	if _gate_portal != null:
		_gate_portal.monitoring = gate_open

func _start_ambient() -> void:
	if _ambient_sfx != null and not _ambient_sfx.playing:
		_ambient_sfx.play()

# ----- quest waypoint --------------------------------------------------------

func _on_quest_objective_changed(_text: String) -> void:
	_refresh_quest_waypoint()


# Same pattern as room.gd::_refresh_quest_waypoint, adapted for the hand-
# authored gate room: anchors are direct children of self (LtScott, the two
# console holders), the cross-room target uses the ExitDoor instance defined
# in gate_room.tscn (target_room_id = "stargate_corridor_east_connector").
func _refresh_quest_waypoint() -> void:
	var target: Dictionary = GameState.quest_target()
	var target_room: String = String(target.get("room", ""))
	var anchor_name: String = String(target.get("anchor", ""))

	if target_room == "":
		_destroy_quest_waypoint()
		return

	var pos: Vector3 = Vector3.ZERO
	var placed: bool = false

	if target_room == "gate_room":
		if anchor_name == "":
			pos = Vector3(0.0, QUEST_WAYPOINT_ANCHOR_HEIGHT, 0.0)
			placed = true
		else:
			var anchor: Node = get_node_or_null(anchor_name)
			# The two console holders (GateControlConsole, FTLConsole) are
			# children of $World, not self. Look there as a fallback.
			if anchor == null and _world != null:
				anchor = _world.get_node_or_null(anchor_name)
			if anchor is Node3D:
				var n3: Node3D = anchor
				pos = n3.global_position + Vector3(0.0, QUEST_WAYPOINT_ANCHOR_HEIGHT, 0.0)
				placed = true
	else:
		var next_hop: String = ShipLayout.next_room_toward("gate_room", target_room)
		if next_hop != "":
			var door: Node3D = _find_door_to(next_hop)
			if door != null:
				pos = door.global_position + Vector3(0.0, QUEST_WAYPOINT_DOOR_HEIGHT, 0.0)
				placed = true

	if not placed:
		_destroy_quest_waypoint()
		return

	if _quest_waypoint == null or not is_instance_valid(_quest_waypoint):
		_quest_waypoint = Node3D.new()
		_quest_waypoint.set_script(QuestWaypointScript)
		_quest_waypoint.name = "QuestWaypoint"
		_world.add_child(_quest_waypoint)
	_quest_waypoint.global_position = pos
	if _quest_waypoint.has_method("set_target_position"):
		_quest_waypoint.call("set_target_position", pos)


func _destroy_quest_waypoint() -> void:
	if _quest_waypoint != null and is_instance_valid(_quest_waypoint):
		_quest_waypoint.queue_free()
	_quest_waypoint = null


func _find_door_to(target_id: String) -> Node3D:
	for c in get_children():
		if not (c is Node3D):
			continue
		var n: Node3D = c
		var prop: Variant = n.get("target_room_id")
		if prop != null and String(prop) == target_id:
			return n
	return null

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
	# Shared metal-grate floor via RoomBuilder.make_floor_mat — same texture,
	# tile size, brightness, and PNG-buffer fallback as every procedural room.
	# Palette kept near the original (0.30, 0.29, 0.32) tint.
	var mat: StandardMaterial3D = RoomBuilder.make_floor_mat(Color(0.30, 0.29, 0.32, 1.0), room_size.x, room_size.y)
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

	# Shared Ancient-tech wall-panel texture via RoomBuilder.make_wall_mat —
	# same loader/cache/tile-size as every procedural room. Two material
	# clones because BoxMesh uv1_scale is per-face uniform: ±X walls show
	# room_size.y × ceiling_height; ±Z walls show room_size.x × ceiling_height.
	# Palette tint kept close to the original (0.36, 0.34, 0.38) so the gate
	# room's slightly warmer wall reading survives the texture overlay.
	var wall_palette: Color = Color(0.36, 0.34, 0.38, 1.0)
	var wall_mat_x: StandardMaterial3D = RoomBuilder.make_wall_mat(wall_palette, room_size.y, ceiling_height)
	var wall_mat_z: StandardMaterial3D = RoomBuilder.make_wall_mat(wall_palette, room_size.x, ceiling_height)

	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	dark_mat.metallic = 0.25
	dark_mat.roughness = 0.7

	var walls: StaticBody3D = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	_world.add_child(walls)

	# Walls are solid — doors are decorative panels recessed INTO the wall, and the
	# scene transition is driven entirely by their E-interact. No archway cutouts.
	# +X wall (right, Crew Quarters side).
	_add_wall_segment(walls, wall_mat_x,
		Vector3(half_x + wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size.y))
	# -X wall (left, Mess Hall side).
	_add_wall_segment(walls, wall_mat_x,
		Vector3(-half_x - wall_thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(wall_thickness, ceiling_height, room_size.y))
	# +Z wall (back, behind the gate).
	_add_wall_segment(walls, wall_mat_z,
		Vector3(0.0, ceiling_height * 0.5, half_z + wall_thickness * 0.5),
		Vector3(room_size.x, ceiling_height, wall_thickness))
	# -Z wall (front, the EXIT wall) — also solid; ExitDoor sits recessed in it.
	_add_wall_segment(walls, wall_mat_z,
		Vector3(0.0, ceiling_height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(room_size.x, ceiling_height, wall_thickness))

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
	mat.albedo_color = Color(0.32, 0.30, 0.34, 1.0)
	mat.metallic = 0.35
	mat.roughness = 0.55

	var deck: StaticBody3D = StaticBody3D.new()
	deck.name = "Mezzanine"
	deck.collision_layer = 1 | 2
	deck.collision_mask = 0
	_world.add_child(deck)

	# `mezzanine_height` is the WALKING SURFACE (top of deck). The box centre
	# sits half a deck-thickness below it so the deck top aligns with the
	# stair-top tread top — otherwise the player walks up to a 0.15 m wall at
	# the deck's inside face and gets stuck.
	var deck_center_y: float = mezzanine_height - deck_thickness * 0.5
	# Back deck strip (-Z runs along -Z wall, the "back" facing the gate)
	_add_wall_segment(deck, mat,
		Vector3(0.0, deck_center_y, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size.x, deck_thickness, mezzanine_depth))
	# Left deck strip (-X)
	_add_wall_segment(deck, mat,
		Vector3(-half_x + mezzanine_depth * 0.5, deck_center_y, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size.y - mezzanine_depth * 2.0))
	# Right deck strip (+X)
	_add_wall_segment(deck, mat,
		Vector3(half_x - mezzanine_depth * 0.5, deck_center_y, 0.0),
		Vector3(mezzanine_depth, deck_thickness, room_size.y - mezzanine_depth * 2.0))

	# Underside trim — a darker thinner mesh on the bottom of each deck strip,
	# reads as architectural soffit and hides the raw box bottom.
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.10, 0.09, 0.11, 1.0)
	trim_mat.metallic = 0.45
	trim_mat.roughness = 0.42
	var trim_y: float = mezzanine_height - deck_thickness - 0.05
	_add_decorative_box(Vector3(0.0, trim_y, -half_z + mezzanine_depth * 0.5),
		Vector3(room_size.x, 0.06, mezzanine_depth + 0.1), trim_mat)
	_add_decorative_box(Vector3(-half_x + mezzanine_depth * 0.5, trim_y, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size.y - mezzanine_depth * 2.0), trim_mat)
	_add_decorative_box(Vector3(half_x - mezzanine_depth * 0.5, trim_y, 0.0),
		Vector3(mezzanine_depth + 0.1, 0.06, room_size.y - mezzanine_depth * 2.0), trim_mat)

	# Railing along the open (inward-facing) edge of each strip.
	_build_railing()


func _build_railing() -> void:
	# Modular railing: emissive cyan posts at intervals connected by a darker
	# top rail. A thin invisible collision wall runs the length of each rail so
	# the player can't walk through or jump over it. Side rails leave a doorway
	# at the top of each staircase.
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
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
	_world.add_child(rail_body)

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
	_world.add_child(stem)

	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(0.16, 0.06, 0.16)
	cap.mesh = cap_box
	cap.material_override = accent_mat
	cap.position = base + Vector3(0.0, RAIL_HEIGHT - 0.04, 0.0)
	_world.add_child(cap)


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


func _build_staircases() -> void:
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
	var half_x: float = room_size.x * 0.5
	var step_count: int = 10
	var step_h: float = mezzanine_height / float(step_count)   # 0.5 m
	var step_run: float = 0.8                                   # 0.8 m
	var stair_mat: StandardMaterial3D = StandardMaterial3D.new()
	stair_mat.albedo_color = Color(0.22, 0.18, 0.13, 1.0)
	stair_mat.metallic = 0.45
	stair_mat.roughness = 0.45
	stair_mat.emission_enabled = true
	stair_mat.emission = Color(1.0, 0.55, 0.18, 1.0)
	stair_mat.emission_energy_multiplier = 0.18

	var rise: float = mezzanine_height                          # 5
	var run: float = float(step_count) * step_run               # 8
	var ramp_len: float = sqrt(rise * rise + run * run)         # ~9.43
	var slope_angle: float = atan2(rise, run)                   # ~32°
	var x_top_abs: float = half_x - mezzanine_depth             # 12 — deck inside edge
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
		_world.add_child(ramp_body)
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
	_world.add_child(top_rail)

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
	_world.add_child(rail_body)
	var rail_cs: CollisionShape3D = CollisionShape3D.new()
	var rail_shape: BoxShape3D = BoxShape3D.new()
	rail_shape.size = Vector3(ramp_len, RAIL_HEIGHT, RAIL_THICKNESS)
	rail_cs.shape = rail_shape
	rail_cs.position = Vector3(x_center, mezzanine_height * 0.5 + RAIL_HEIGHT * 0.5, rail_z)
	rail_cs.rotation = Vector3(0.0, 0.0, side_sign * slope_angle)
	rail_body.add_child(rail_cs)


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


# Lt Scott waits down the dais ramp from the arrival platform and walks up to
# the player to brief them. The body uses Kenney "Mini Characters 1" so Scott
# reads as a different humanoid than the platformer-mascot player. Collision
# capsule + Label3D nametag are still procedural — the GLB is purely visual.
func _build_npcs() -> void:
	var half_z: float = room_size.y * 0.5
	var spawn: Vector3 = Vector3(1.5, 0.0, half_z - 9.0)
	var scott: StaticBody3D = StaticBody3D.new()
	scott.set_script(NPC_SCRIPT)
	scott.name = "LtScott"
	scott.position = spawn
	# Face -Z (toward the dais) so the player arriving on the dais sees his face.
	scott.rotation.y = 0.0
	scott.set("character_name", "Lt Scott")
	scott.set("prompt", "Talk to Lt Scott")
	# Choice-tree dialog (renders via objects/dialog_screen.tscn — full-screen
	# Fable-style portrait + branching choices). Indexes refer to positions in
	# this same array; "exit" closes the conversation.
	# New quest opening (sprint-005, 2026-05-23): Scott has no answers — he kicks
	# the player toward Rush, who's the one who'll actually know what's going on.
	# All other E1 objectives (quarters, map, hull breach) are gated in
	# GameState._recompute_objective behind met_rush so Scott's opening doesn't
	# promise tasks the player hasn't been told about yet.
	scott.set("dialogue_tree", [
		{
			"speaker": "Lt Scott",
			"text": "Eli! Hey — you alright? What the hell just happened?",
			"choices": [
				{"text": "Where are we?", "next": 1},
				{"text": "What happened?", "next": 2},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "Hell if I know. We just came through the gate, and... this isn't earth. This isn't anywhere I've ever heard of.",
			"choices": [
				{"text": "Where's Rush?", "next": 3},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "Gate dialed an unknown address. Rush yelled GO, and we went — next thing we know, we're here. Wherever 'here' is.",
			"choices": [
				{"text": "Where's Rush?", "next": 3},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "I think he went through that door. Catch up to him — he'll know what's happening. He always does, even when he won't say.",
			"choices": [
				{"text": "On it.", "next": "exit"},
			],
		},
	])
	scott.set("repeat_dialogue_tree", [
		{
			"speaker": "Lt Scott",
			"text": "Hurry up Eli, find Rush!",
			"choices": [
				{"text": "On it.", "next": "exit"},
			],
		},
	])
	scott.set("met_flag", "met_scott")
	scott.set("first_meet_recompute_objective", true)
	# Walk up to the player and trigger the briefing automatically — no E-press.
	scott.set("auto_greet", not GameState.met_scott)
	scott.set("auto_greet_distance", 2.6)
	scott.set("auto_greet_delay", 1.5)
	scott.set("auto_greet_speed", 1.9)

	# Collision capsule — blocks the player and acts as interactable hitbox.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	scott.add_child(cs)

	# Visual body — Kenney "Mini Characters 1" GLB. Wrapped in a Node3D so we
	# can tune scale/yaw without touching the imported scene's transform.
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.position = Vector3(0.0, 0.0, 0.0)
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	# Kenney mini characters export with +Z forward (look at the spine in the
	# import preview), so rotate 180° to align with Godot's -Z forward
	# convention — otherwise Scott walks/auto-greets facing the wrong way.
	model_holder.rotation.y = PI
	var scott_glb: PackedScene = load("res://models/characters/scott.glb")
	if scott_glb != null:
		var scott_model: Node = scott_glb.instantiate()
		model_holder.add_child(scott_model)
		# Kenney GLBs reference an external colormap.png that the Godot importer
		# doesn't bind to the material — without this override Scott renders as
		# a solid white silhouette. (See feedback-kenney-mini-chars-colormap.)
		var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
		Npc.apply_kenney_colormap(scott_model, colormap)
		# Start the GLB's idle animation so Scott isn't a statue.
		Npc.play_idle_animation(scott_model)
	scott.add_child(model_holder)

	# Floating nametag billboard so the player can ID him from across the room.
	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = "Lt Scott"
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.05, 0.0)
	scott.add_child(tag)

	_world.add_child(scott)

	# Medic tableau: Colonel Young laid out unconscious with Lt James kneeling
	# beside him trying to stabilise him. Clustered well away from the
	# gate at the -X / -Z corner so the player walks past on their way to the
	# south corridor exit and can't miss it.
	_build_medic_tableau()


# Medic vignette near the -X wall, behind the staircases:
#   • Young lying face-up on the floor, unconscious and not interactable.
#   • Lt James kneeling on the gate-side of him, facing Young.
# James is the only talkable NPC in this cluster.
func _build_medic_tableau() -> void:
	var tableau_center: Vector3 = Vector3(-9.0, 0.0, -6.0)

	# --- Colonel Young — laid out on his back ----
	_build_tableau_npc(
		"ColonelYoung",
		"Colonel Young",
		tableau_center + Vector3(0.0, 0.0, 0.0),
		0.0,
		"res://models/characters/scott.glb",
		[],
		"met_young",
		"down",
		false,
		"X_X",
	)

	# --- Lt James — kneeling BESIDE Young by his head (gate-side of him),
	# facing him so she reads as a medic mid-triage. Offset on +X to clear
	# his body; her yaw turns her -90° so she looks toward -X (at Young).
	_build_tableau_npc(
		"LtJames",
		"Lt James",
		tableau_center + Vector3(0.85, 0.0, 0.4),
		PI * 0.5,
		"res://models/characters/lt_james.glb",
		_james_tableau_dialog(),
		"",
		"kneel",
	)


# Tableau NPC builder — supports two poses beyond standing:
#   • "down"  — rotated 90° around X so the model lies face-up on the floor.
#   • "kneel" — Y-axis squashed so the model reads as crouched / kneeling.
# The collision capsule + nametag are repositioned to suit each pose.
func _build_tableau_npc(
		npc_name: String,
		character: String,
		pos: Vector3,
		yaw: float,
		glb_path: String,
		dialog_tree: Array,
		met_flag: String,
		pose: String,
		talkable: bool = true,
		face_override: String = "",
	) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	if talkable:
		body.set_script(NPC_SCRIPT)
	body.name = npc_name
	body.position = pos
	body.rotation.y = yaw
	if talkable:
		body.set("character_name", character)
		body.set("prompt", "Talk to %s" % character)
		body.set("dialogue_tree", dialog_tree)
		body.set("met_flag", met_flag)
		body.set("first_meet_recompute_objective", true)
	else:
		body.collision_layer = 1
		body.collision_mask = 0

	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	if pose == "down":
		# Wide flat hitbox at floor height — capsule oriented horizontally.
		cap.radius = 0.4
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0.0, 0.25, 0.0)
		# Capsule's long axis is Y; rotate so it lies along the body's local Z.
		cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	elif pose == "kneel":
		cap.radius = 0.36
		cap.height = 1.2
		cs.shape = cap
		cs.position = Vector3(0.0, 0.6, 0.0)
	else:
		cap.radius = 0.32
		cap.height = 1.75
		cs.shape = cap
		cs.position = Vector3(0.0, 0.88, 0.0)
	body.add_child(cs)

	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	if pose == "down":
		# Lay character on their back: tip the holder forward 90° so what was up
		# (head along +Y) now extends along +Z away from the feet anchor.
		# Lift slightly so the back doesn't z-fight with the floor.
		model_holder.rotation = Vector3(-PI * 0.5, PI, 0.0)
		model_holder.position = Vector3(0.0, 0.18, 0.7)
		model_holder.scale = Vector3(2.6, 2.6, 2.6)
	elif pose == "kneel":
		# Compress the standing model vertically — reads as crouched/kneeling
		# without needing a separate rig. Slight forward tilt sells the lean.
		model_holder.rotation = Vector3(deg_to_rad(-20.0), PI, 0.0)
		model_holder.position = Vector3(0.0, 0.0, 0.0)
		model_holder.scale = Vector3(2.6, 1.5, 2.6)
	else:
		model_holder.rotation.y = PI
		model_holder.scale = Vector3(2.6, 2.6, 2.6)

	var glb: PackedScene = load(glb_path)
	if glb != null:
		var inst: Node = glb.instantiate()
		model_holder.add_child(inst)
		var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
		Npc.apply_kenney_colormap(inst, colormap)
		# Down characters DON'T idle-loop — the breathe-anim makes "unconscious"
		# read as "stretching." Kneelers do, so they feel busy with their hands.
		if pose != "down":
			Npc.play_idle_animation(inst)
	body.add_child(model_holder)
	if face_override != "":
		_add_face_override(body, face_override, pose)

	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = character
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Pull the nametag closer to the floor for the prone character so it floats
	# above his chest rather than way up where his head used to be.
	if pose == "down":
		tag.position = Vector3(0.0, 0.9, 0.3)
	elif pose == "kneel":
		tag.position = Vector3(0.0, 1.5, 0.0)
	else:
		tag.position = Vector3(0.0, 2.05, 0.0)
	body.add_child(tag)

	_world.add_child(body)


func _add_face_override(body: Node3D, text: String, pose: String) -> void:
	var face: Label3D = Label3D.new()
	face.name = "FaceOverride"
	face.text = text
	face.pixel_size = 0.0068
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.outline_size = 2
	face.shaded = false
	face.modulate = Color(0.03, 0.035, 0.04, 1.0)
	face.outline_modulate = Color(0.85, 0.62, 0.46, 0.85)
	face.position = Vector3(0.0, 0.78, 1.35) if pose == "down" else Vector3(0.0, 1.7, 0.0)
	body.add_child(face)


func _james_tableau_dialog() -> Array:
	return [
		{
			"speaker": "Lt James",
			"text": "Hold on — give me space, please. Colonel Young took a hard fall when we landed. He's unconscious, but his pulse is steady.",
			"choices": [
				{"text": "Will he be okay?", "next": 1},
				{"text": "Can I help?", "next": 2},
				{"text": "I'll keep moving.", "next": "exit"},
			],
		},
		{
			"speaker": "Lt James",
			"text": "I need him still until I can finish checking him. He's breathing, and that's the part that matters right now.",
			"choices": [
				{"text": "Can I help?", "next": 2},
				{"text": "Glad to hear it.", "next": "exit"},
			],
		},
		{
			"speaker": "Lt James",
			"text": "Yes — find Dr Rush. He's the one who needs to know what state the Colonel is in, and he's the only one of us who might be able to read these consoles. He went through to the control room.",
			"choices": [
				{"text": "Heading there now.", "next": "exit"},
			],
		},
	]


func _build_consoles() -> void:
	# Two consoles on the deck-1 floor, facing the gate. Both use the SHARED
	# Ancient-tech console mesh (RoomBuilder.attach_console_mesh) — same
	# silhouette, same tweak surface as the control-room consoles. Per-console
	# screen color is the optional differentiator if we ever want Gate Control
	# vs FTL Countdown to read differently; for now both use the default blue.
	var half_z: float = room_size.y * 0.5
	var z_console: float = half_z - 10.5
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
		_world.add_child(holder)
		RoomBuilder.attach_console_mesh(holder)

		var inter: StaticBody3D = StaticBody3D.new()
		inter.set_script(GATE_CONSOLE_SCRIPT)
		inter.name = "Interactable"
		inter.set("kind", spec["kind"])
		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(1.8, 1.6, 1.2)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.8, 0.0)
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
	key.light_color = Color(0.82, 0.88, 1.0, 1.0)
	key.light_energy = 0.85
	key.shadow_enabled = true
	key.shadow_opacity = 0.5
	# Tilt to come "from above and front" (-Y mostly, slight +Z).
	key.rotation = Vector3(deg_to_rad(-72.0), deg_to_rad(15.0), 0.0)
	_world.add_child(key)

	# Ceiling fill — 6 downward Omnis in a 2×3 grid below the ceiling. Wide range
	# so each one washes a quadrant. Cool tint so warm uplights still pop on the
	# walls without the whole room going flat-grey.
	var ceiling_fill_y: float = ceiling_height - 0.8
	var fill_positions: Array = [
		Vector3(-half_x * 0.55, ceiling_fill_y,  half_z * 0.55),
		Vector3( half_x * 0.55, ceiling_fill_y,  half_z * 0.55),
		Vector3(-half_x * 0.55, ceiling_fill_y, 0.0),
		Vector3( half_x * 0.55, ceiling_fill_y, 0.0),
		Vector3(-half_x * 0.55, ceiling_fill_y, -half_z * 0.55),
		Vector3( half_x * 0.55, ceiling_fill_y, -half_z * 0.55),
	]
	for p in fill_positions:
		var fill: OmniLight3D = OmniLight3D.new()
		fill.light_color = Color(0.86, 0.90, 1.0, 1.0)
		fill.light_energy = 2.2
		fill.omni_range = 14.0
		fill.omni_attenuation = 1.4
		fill.position = p
		_world.add_child(fill)

	# Door-archway pool — spotlight aimed straight down through the -Z arch so
	# the exit reads as "lit doorway" instead of black hole. Player sees it from
	# across the room and walks toward it.
	var door_spot: SpotLight3D = SpotLight3D.new()
	door_spot.name = "DoorArchSpot"
	door_spot.light_color = Color(1.0, 0.78, 0.45, 1.0)
	door_spot.light_energy = 5.5
	door_spot.spot_range = 8.0
	door_spot.spot_angle = 38.0
	door_spot.position = Vector3(0.0, ceiling_height - 0.6, -half_z + 1.2)
	_world.add_child(door_spot)
	door_spot.look_at(Vector3(0.0, 0.0, -half_z + 0.2), Vector3.UP)
