extends Node3D

# Generic data-driven room scene. Reads room_id from GameState (set by the
# door that ferried us here), looks up the row via ShipLayout, and dispatches
# to RoomBuilder for floor/walls/ceiling + per-template accents.
#
# gate_room is the artisan exception: its template_id is a RoomBuilder no-op
# and gate_room.tscn is hand-authored.

const DOOR_SCENE: PackedScene = preload("res://objects/door.tscn")
const CONNECTIONS_PATH: String = "res://data/room_connections.json"
# Preload to sidestep `class_name RoomBuilder` not always being registered in
# `-s` headless runs.
const RoomBuilderRef: Script = preload("res://scripts/room_builder.gd")
const BedScript: Script = preload("res://scripts/bed.gd")
const KinoPickupScript: Script = preload("res://scripts/kino_pickup.gd")
const HullSealSwitchScript: Script = preload("res://scripts/hull_seal_switch.gd")
const NpcScript: Script = preload("res://scripts/npc.gd")
const Co2ScrubberScript: Script = preload("res://scripts/co2_scrubber.gd")
const PowerConsoleScript: Script = preload("res://scripts/power_console.gd")
const QuestWaypointScript: Script = preload("res://scripts/quest_waypoint.gd")
# Vertical offset above an in-room anchor (NPC head, console top, pickup body)
# where the diamond sits. Tuned so it clears nametag Label3Ds.
const QUEST_WAYPOINT_ANCHOR_HEIGHT: float = 2.4
# Vertical offset above a door's local origin when the target is in another
# room. Door origin sits on the floor; this lifts the diamond into eye-line.
const QUEST_WAYPOINT_DOOR_HEIGHT: float = 1.8
# Per-anchor vertical offset OVERRIDES — for objects that aren't NPCs and
# would have the diamond floating embarrassingly high above them. Anchor
# names not listed fall back to QUEST_WAYPOINT_ANCHOR_HEIGHT (NPC-default).
const WAYPOINT_OFFSET_BY_ANCHOR: Dictionary = {
	"KinoPickup": 0.35,        # tiny remote on a desk — diamond sits just above
	"Bed": 1.1,                # bunk-height
	"HullSealSwitch": 0.7,     # wall switch at chest height
	"PowerConsole": 0.7,       # wall console
	"CO2Scrubber": 1.4,        # scrubber housing top
}

# Set this in the editor to preview a specific room when running the scene
# standalone (F6). At runtime, GameState.next_room_id takes precedence.
@export var room_id: String = ""

@onready var world: Node3D = $World
@onready var markers: Node3D = $Markers
@onready var player: Node3D = $Player
@onready var view: Node3D = $View

var _room_data: Dictionary = {}
var _quest_waypoint: Node3D = null


func _ready() -> void:
	# Resolve which room we are. Door-set baton wins over @export.
	if GameState.next_room_id != "":
		room_id = GameState.next_room_id
		GameState.next_room_id = ""
	if room_id == "":
		push_error("room.gd: no room_id provided (GameState.next_room_id and @export both empty)")
		return

	_room_data = ShipLayout.room(room_id)
	if _room_data.is_empty():
		push_error("room.gd: ShipLayout has no row for '%s'" % room_id)
		return

	# Some JSON corridors are 3.5 m short-axis (cr_north, room_1751649578881)
	# which reads as a closet, not a Destiny corridor. Widen the short axis to
	# a 6 m minimum for corridor-template rooms; the JSON adjacency math still
	# uses the original rectangle so door alignment between rooms is preserved
	# (overlap midpoints fall inside the widened walls).
	_apply_corridor_min_short_axis(6.0)

	# Geometry first so doors can sit against real walls.
	RoomBuilderRef.build(world, _room_data)
	_setup_doors()
	_spawn_interactables()
	_place_player()
	GameState.discover_room(room_id, String(_room_data.get("name", room_id)))
	GameState.set_current_room(room_id)
	if room_id == "quarters_room_1":
		GameState.mark_quarters_found()
	elif room_id == "eli_quarters":
		GameState.mark_eli_quarters_found()

	# Persist for save/load — F5 reloads this scene with the same room_id.
	GameState.current_scene_path = "res://scenes/room.tscn"

	# Quest diamond waypoint — refreshes on objective_changed so quest
	# advances mid-room (e.g. picking up the Kino) reposition the diamond
	# without needing a room reload.
	_refresh_quest_waypoint()
	if not GameState.objective_changed.is_connected(_on_quest_objective_changed):
		GameState.objective_changed.connect(_on_quest_objective_changed)


# Stamp door + matching spawn Marker3D for each connection that originates at
# this room (and the reverse-edge stamp from any other room that points here).
# Reads data/room_connections.json on demand — no preload cost when running
# the gate-room scene.
func _setup_doors() -> void:
	var connections: Dictionary = _load_connections()
	if connections.is_empty():
		return
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5

	# Edges originating at THIS room — stamp doors that exit here.
	for edge: Dictionary in connections.get(room_id, []) as Array:
		_stamp_door(edge, half_x, half_z)
	# Edges where ANOTHER room points at us — flip the direction and stamp
	# matching doors on this side so the trip is two-way without requiring
	# the connection table to list every edge twice.
	for from_id: String in connections.keys():
		for edge: Dictionary in connections[from_id] as Array:
			if String(edge.get("to", "")) == room_id:
				var reverse: Dictionary = edge.duplicate()
				reverse["to"] = from_id
				reverse["dir"] = _flip_direction(String(edge.get("dir", "")))
				# Plaque on the return-side door should name the destination
				# (i.e. the room we came from), not whatever the outgoing
				# plaque said. _stamp_door auto-derives that from `to`.
				reverse.erase("plaque")
				_stamp_door(reverse, half_x, half_z)


# Stamps one door + matching arrival marker on the wall indicated by `edge.dir`.
# Spawn-key convention: target_spawn = "From" + camel(THIS room) so the
# receiving side knows which marker to use; local marker name = "From" +
# camel(OTHER room) so when the player comes BACK, they arrive at our wall.
func _stamp_door(edge: Dictionary, half_x: float, half_z: float) -> void:
	var dir: String = String(edge.get("dir", ""))
	var target_id: String = String(edge.get("to", ""))
	if target_id == "":
		return
	# Elevator pairs aren't physically adjacent — present them as a lift door on
	# the -Z wall (deterministic so the reverse edge lands on the matching wall
	# in the other elevator). Everything else follows wall-axis literally.
	var is_elevator: bool = (dir == "elevator")
	if is_elevator:
		dir = "-z"

	var along: float = _door_along_offset(target_id, dir)
	var pos: Vector3 = Vector3.ZERO
	var face_yaw: float = 0.0
	match dir:
		"+x":
			pos = Vector3(half_x, 0.0, along)
			face_yaw = -PI * 0.5
		"-x":
			pos = Vector3(-half_x, 0.0, along)
			face_yaw = PI * 0.5
		"+z":
			pos = Vector3(along, 0.0, half_z)
			face_yaw = PI
		"-z":
			pos = Vector3(along, 0.0, -half_z)
			face_yaw = 0.0
		_:
			return

	# Spawn keys identify "who I came from" — symmetric across both ends.
	var outgoing_spawn: String = "From" + _to_camel(room_id)
	var local_marker_name: String = "From" + _to_camel(target_id)
	var plaque: String = String(edge.get("plaque", _humanize(target_id)))

	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = face_yaw
	door.set("target_room_id", target_id)
	door.set("source_room_id", room_id)
	door.set("target_spawn", outgoing_spawn)
	door.set("plaque_label", plaque)
	door.set("open_prompt", "Step through to %s" % plaque)
	door.set("transition_prompt", "Step through to %s" % plaque)
	# Elevator doors stay locked until Engineering Bay power is restored.
	# Sets the legacy `locked` + `lock_message` exports on door.gd — its
	# _on_interact() short-circuits when locked.
	if is_elevator and not GameState.elevator_repaired:
		door.set("locked", true)
		door.set("lock_message", "LOCKED — power offline. Restore power at the Engineering Bay (south of cr corridor).")
	door.add_to_group("interactable")
	add_child(door)

	# Arrival marker: place 1.2 m into the room from the door so SceneRouter
	# can land the player clear of the doorway when they return.
	var marker: Marker3D = Marker3D.new()
	marker.name = local_marker_name
	var inset: float = 1.2
	var inset_pos: Vector3 = pos
	match dir:
		"+x": inset_pos.x -= inset
		"-x": inset_pos.x += inset
		"+z": inset_pos.z -= inset
		"-z": inset_pos.z += inset
	inset_pos.y = 0.0
	marker.position = inset_pos
	marker.rotation.y = face_yaw + PI
	markers.add_child(marker)


# Where along the wall (perpendicular to `dir`) the door should sit. Returns
# the overlap midpoint between this room and the target room's JSON rect,
# converted to metres relative to this room's local origin. Falls back to 0
# (wall centre) when there's no overlap (elevator pairs across floors).
func _door_along_offset(target_id: String, dir: String) -> float:
	var target: Dictionary = ShipLayout.room(target_id)
	if target.is_empty() or _room_data.is_empty():
		return 0.0
	var my_sx: float = float(_room_data.get("startX", 0))
	var my_ex: float = float(_room_data.get("endX", 0))
	var my_sy: float = float(_room_data.get("startY", 0))
	var my_ey: float = float(_room_data.get("endY", 0))
	var t_sx: float = float(target.get("startX", 0))
	var t_ex: float = float(target.get("endX", 0))
	var t_sy: float = float(target.get("startY", 0))
	var t_ey: float = float(target.get("endY", 0))
	var lo: float = 0.0
	var hi: float = 0.0
	var my_center: float = 0.0
	if dir == "+x" or dir == "-x":
		# Wall faces along JSON-Y (world Z). Find overlap on Y.
		lo = max(my_sy, t_sy)
		hi = min(my_ey, t_ey)
		my_center = (my_sy + my_ey) * 0.5
	else:
		# +z/-z wall — find overlap on X.
		lo = max(my_sx, t_sx)
		hi = min(my_ex, t_ex)
		my_center = (my_sx + my_ex) * 0.5
	if hi <= lo:
		return 0.0
	var mid: float = (lo + hi) * 0.5
	return (mid - my_center) * ShipLayout.SCALE


func _place_player() -> void:
	# Save-restored spawn wins. SceneRouter handles marker-by-name placement
	# AFTER _ready() returns (it walks the tree looking for the spawn key it
	# was passed), so we only set a sensible default here.
	if GameState.pending_spawn_position != null:
		player.global_position = GameState.pending_spawn_position
		player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
		if view.has_method("snap_to_target"):
			view.snap_to_target()
		return

	# Default: drop the player at the first arrival marker (any door's
	# "From<src>" Marker3D). This avoids spawning inside center geometry like
	# the control-room pillar or kino-room pedestal when the scene is loaded
	# standalone without a `pending_spawn_position`. SceneRouter still
	# overwrites this when a named spawn key was passed in.
	if markers != null and markers.get_child_count() > 0:
		var first: Node = markers.get_child(0)
		if first is Marker3D:
			var m: Marker3D = first
			player.global_position = m.global_position
			player.rotation.y = m.rotation.y
			if view.has_method("snap_to_target"):
				view.snap_to_target()
			return

	# Fallback: room centre, looking +Z (used for rooms with no connections,
	# i.e. an isolated test scene).
	player.global_position = Vector3.ZERO
	player.rotation.y = 0.0
	if view.has_method("snap_to_target"):
		view.snap_to_target()


func _spawn_interactables() -> void:
	match room_id:
		"quarters_room_1":
			_spawn_quarters_bed()
		"eli_quarters":
			# Eli's room — Eli IS the player. Houses the Kino Remote pickup on
			# the desk and his bed for the FIND_REST → SLEEP quest beat.
			_spawn_eli_kino_pickup()
			_spawn_quarters_bed("My bed. Time to crash.")
		"east_corridor":
			_spawn_hull_breach()
			_spawn_sgt_greer()
		"control_interface_room":
			# Only Rush — Young, James, Park have moved to the gate room with the
			# unconscious-tableau (Young laid out, James + Park treating him).
			_spawn_dr_rush()
		"engineering_bay":
			_spawn_power_console()
		"hydroponics":
			_spawn_co2_scrubber()
		"south_corridor":
			_spawn_chloe()
		"north_corridor":
			_spawn_soldier()


# Bed against the -Z wall, matching the position used by RoomBuilder._accent_quarters.
# `first_time_log` overrides bed.gd's default flavor message for the FIRST
# interact (e.g. so resting in Eli's quarters reads differently than resting
# in the player's own Crew Quarters Alpha).
func _spawn_quarters_bed(first_time_log: String = "") -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	var bunk_x: float = -half_x * 0.3
	var bunk_pos: Vector3 = Vector3(bunk_x, 0.5, -half_z + 2.0)

	# Interact body — Interactable._ready() hard-sets collision_layer = 4, so
	# this one ONLY handles the E-prompt. Player interact ray casts at
	# y=interact_origin_height (1.1 m, chest) so the box has to reach UP to
	# that height — a thin mattress-only box would let the ray fly over it.
	# Generous footprint so the prompt fires from a step back too.
	const BED_INTERACT_SIZE: Vector3 = Vector3(2.4, 1.6, 4.0)
	var bed: StaticBody3D = StaticBody3D.new()
	bed.set_script(BedScript)
	bed.name = "Bed"
	bed.position = bunk_pos + Vector3(0.0, 0.25, 0.0)  # raise to box centre y≈0.75
	if first_time_log != "":
		bed.set("first_time_log", first_time_log)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = BED_INTERACT_SIZE
	cs.shape = box
	bed.add_child(cs)
	add_child(bed)

	# Walk-blocker — sibling StaticBody on world layer 1 so the player can't
	# stroll through the mattress. Tighter footprint (matches the visual mesh)
	# so the player can stand right alongside the bed without being shoved.
	const BED_BLOCKER_SIZE: Vector3 = Vector3(1.8, 0.7, 3.4)
	var bed_block: StaticBody3D = StaticBody3D.new()
	bed_block.name = "BedBlocker"
	bed_block.position = bunk_pos + Vector3(0.0, -0.05, 0.0)
	bed_block.collision_layer = 1
	bed_block.collision_mask = 0
	var block_cs: CollisionShape3D = CollisionShape3D.new()
	var block_box: BoxShape3D = BoxShape3D.new()
	block_box.size = BED_BLOCKER_SIZE
	block_cs.shape = block_box
	bed_block.add_child(block_cs)
	add_child(bed_block)


# Eli left his Kino Remote on the desk in his quarters — RoomBuilder's
# quarters-template builds a Kenney desk at (half_x - 0.7, 0.0, 0.0) when the
# room is wider than 6 m. eli_quarters is 10 m × 12 m so the desk always spawns.
# Kino prop sits on the desktop, pickup hitbox alongside.
func _spawn_eli_kino_pickup() -> void:
	# Position + scale baked from scenes/quarters_test.tscn workbench. RoomBuilder
	# spawns the desk at (half_x - 1.4, 0, 0); the remote sits centred on that desktop.
	const KINO_GLB_PATH: String = "res://models/props/kino_remote.glb"
	const KINO_SCALE: float = 0.2

	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var kino_pos: Vector3 = Vector3(half_x - 1.4, 1.02, 0.0)
	var holder: Node3D = Node3D.new()
	holder.name = "KinoProp"
	holder.position = kino_pos
	holder.scale = Vector3.ONE * KINO_SCALE
	add_child(holder)

	var glb: PackedScene = load(KINO_GLB_PATH)
	if glb != null:
		var inst: Node = glb.instantiate()
		holder.add_child(inst)

	# Pickup hitbox — generous interact zone since the remote itself is small.
	# Sized in world space (NOT scaled by the holder), so set as a SIBLING of
	# the visual prop rather than a child.
	var pickup: StaticBody3D = StaticBody3D.new()
	pickup.set_script(KinoPickupScript)
	pickup.name = "KinoPickup"
	pickup.position = holder.position
	pickup.set("prop_to_hide", NodePath("../KinoProp"))
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.45, 0.40, 0.30)
	cs.shape = box
	pickup.add_child(cs)
	add_child(pickup)


# Hull breach in the east_corridor: jagged dark hole on the +X wall with red
# warning trim, plus an emergency seal switch on the opposite wall. If the
# breach is already sealed (loaded save), swap the hole for a clean patch panel
# and the switch's _ready() will leave itself disabled.
func _spawn_hull_breach() -> void:
	const BREACH_ID: String = "breach_a"
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	# 14 m in from the -Z end — well past the south door's arrival marker so
	# the player has to walk a stretch of corridor before stumbling on it.
	var breach_z: float = -half_z + 14.0
	var sealed: bool = GameState.breaches_sealed.has(BREACH_ID)

	var wrap: Node3D = Node3D.new()
	wrap.name = "HullBreach"
	wrap.position = Vector3(half_x - 0.02, 1.6, breach_z)
	add_child(wrap)

	if sealed:
		var patch_mat: StandardMaterial3D = StandardMaterial3D.new()
		patch_mat.albedo_color = Color(0.55, 0.50, 0.42)
		patch_mat.metallic = 0.7
		patch_mat.roughness = 0.4
		var patch_mi: MeshInstance3D = MeshInstance3D.new()
		var patch_box: BoxMesh = BoxMesh.new()
		patch_box.size = Vector3(0.06, 1.6, 1.8)
		patch_mi.mesh = patch_box
		patch_mi.material_override = patch_mat
		wrap.add_child(patch_mi)
		# Rivet dots — small bright cylinders along the patch edges read as
		# "this was welded shut" without needing a separate model.
		var rivet_mat: StandardMaterial3D = StandardMaterial3D.new()
		rivet_mat.albedo_color = Color(0.8, 0.75, 0.6)
		rivet_mat.metallic = 0.9
		rivet_mat.roughness = 0.25
		for ry in [-0.6, 0.0, 0.6]:
			for rz in [-0.75, 0.75]:
				var rivet_mesh: SphereMesh = SphereMesh.new()
				rivet_mesh.radius = 0.04
				rivet_mesh.height = 0.08
				var rivet: MeshInstance3D = MeshInstance3D.new()
				rivet.mesh = rivet_mesh
				rivet.material_override = rivet_mat
				rivet.position = Vector3(-0.04, ry, rz)
				wrap.add_child(rivet)
	else:
		var hole_mat: StandardMaterial3D = StandardMaterial3D.new()
		hole_mat.albedo_color = Color(0.02, 0.02, 0.03)
		hole_mat.metallic = 0.0
		hole_mat.roughness = 1.0
		var hole_mi: MeshInstance3D = MeshInstance3D.new()
		var hole_box: BoxMesh = BoxMesh.new()
		hole_box.size = Vector3(0.10, 1.4, 1.6)
		hole_mi.mesh = hole_box
		hole_mi.material_override = hole_mat
		wrap.add_child(hole_mi)

		var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
		trim_mat.albedo_color = Color(1.0, 0.18, 0.10)
		trim_mat.emission_enabled = true
		trim_mat.emission = Color(1.0, 0.20, 0.10)
		trim_mat.emission_energy_multiplier = 3.5
		# Four warning bars framing the hole (top/bottom/left/right).
		for trim in [
			{"pos": Vector3(-0.03, 0.75, 0.0), "size": Vector3(0.04, 0.08, 1.7)},
			{"pos": Vector3(-0.03, -0.75, 0.0), "size": Vector3(0.04, 0.08, 1.7)},
			{"pos": Vector3(-0.03, 0.0, 0.85), "size": Vector3(0.04, 1.5, 0.08)},
			{"pos": Vector3(-0.03, 0.0, -0.85), "size": Vector3(0.04, 1.5, 0.08)},
		]:
			var bar_mi: MeshInstance3D = MeshInstance3D.new()
			var bar_box: BoxMesh = BoxMesh.new()
			bar_box.size = trim["size"]
			bar_mi.mesh = bar_box
			bar_mi.material_override = trim_mat
			bar_mi.position = trim["pos"]
			wrap.add_child(bar_mi)

		# Debris on the floor beneath the hole.
		var debris_mat: StandardMaterial3D = StandardMaterial3D.new()
		debris_mat.albedo_color = Color(0.18, 0.16, 0.14)
		debris_mat.metallic = 0.4
		debris_mat.roughness = 0.7
		for i in 5:
			var d_mi: MeshInstance3D = MeshInstance3D.new()
			var d_box: BoxMesh = BoxMesh.new()
			var s: float = 0.18 + float(i) * 0.05
			d_box.size = Vector3(s * 0.6, 0.10, s)
			d_mi.mesh = d_box
			d_mi.material_override = debris_mat
			d_mi.position = Vector3(-0.4 - float(i) * 0.05, -1.5, -0.4 + float(i) * 0.2)
			d_mi.rotation = Vector3(0.0, deg_to_rad(15.0 * float(i)), deg_to_rad(8.0 * float(i)))
			wrap.add_child(d_mi)

	# Switch on the -X wall, opposite the breach, at chest height. Even when
	# already sealed we still spawn it so the prompt reads "Hull integrity
	# holding." instead of leaving the panel missing entirely.
	var switch: StaticBody3D = StaticBody3D.new()
	switch.set_script(HullSealSwitchScript)
	switch.name = "HullSealSwitch"
	switch.position = Vector3(-half_x + 0.25, 1.4, breach_z)
	switch.set("breach_id", BREACH_ID)
	var s_cs: CollisionShape3D = CollisionShape3D.new()
	var s_box: BoxShape3D = BoxShape3D.new()
	s_box.size = Vector3(0.5, 0.6, 0.5)
	s_cs.shape = s_box
	switch.add_child(s_cs)
	add_child(switch)

	# Switch visual: dark housing + bright emissive button. Parent to the room
	# (not the switch body) so the visible mesh doesn't double-count as a
	# collision shape on layer 4.
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.20, 0.20, 0.22)
	housing_mat.metallic = 0.5
	housing_mat.roughness = 0.45
	var housing_mi: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.55, 0.45)
	housing_mi.mesh = housing_box
	housing_mi.material_override = housing_mat
	housing_mi.position = switch.position
	add_child(housing_mi)

	var btn_mat: StandardMaterial3D = StandardMaterial3D.new()
	var btn_color: Color = Color(0.30, 0.85, 1.0) if sealed else Color(1.0, 0.30, 0.10)
	btn_mat.albedo_color = btn_color
	btn_mat.emission_enabled = true
	btn_mat.emission = btn_color
	btn_mat.emission_energy_multiplier = 3.0
	var btn_mi: MeshInstance3D = MeshInstance3D.new()
	var btn_box: BoxMesh = BoxMesh.new()
	btn_box.size = Vector3(0.04, 0.22, 0.22)
	btn_mi.mesh = btn_box
	btn_mi.material_override = btn_mat
	btn_mi.position = switch.position + Vector3(0.02, 0.0, 0.0)
	add_child(btn_mi)


# Engineering Bay power console — wall-mounted breaker switch on the -X wall.
# Modeled visually after the hull-seal switch: dark housing + bright emissive
# button that flips from red (offline) to green (restored). One-shot.
func _spawn_power_console() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var restored: bool = GameState.elevator_repaired

	var console: StaticBody3D = StaticBody3D.new()
	console.set_script(PowerConsoleScript)
	console.name = "PowerConsole"
	console.position = Vector3(-half_x + 0.25, 1.4, 0.0)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var s_box: BoxShape3D = BoxShape3D.new()
	s_box.size = Vector3(0.5, 0.8, 0.7)
	cs.shape = s_box
	console.add_child(cs)
	add_child(console)

	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.20, 0.20, 0.22)
	housing_mat.metallic = 0.55
	housing_mat.roughness = 0.42
	var housing_mi: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.75, 0.65)
	housing_mi.mesh = housing_box
	housing_mi.material_override = housing_mat
	housing_mi.position = console.position
	add_child(housing_mi)

	var btn_mat: StandardMaterial3D = StandardMaterial3D.new()
	var btn_color: Color = Color(0.35, 1.0, 0.55) if restored else Color(1.0, 0.30, 0.10)
	btn_mat.albedo_color = btn_color
	btn_mat.emission_enabled = true
	btn_mat.emission = btn_color
	btn_mat.emission_energy_multiplier = 3.2
	var btn_mi: MeshInstance3D = MeshInstance3D.new()
	var btn_box: BoxMesh = BoxMesh.new()
	btn_box.size = Vector3(0.04, 0.32, 0.32)
	btn_mi.mesh = btn_box
	btn_mi.material_override = btn_mat
	btn_mi.position = console.position + Vector3(0.02, 0.0, 0.0)
	add_child(btn_mi)

	var label: Label3D = Label3D.new()
	label.name = "PowerLabel"
	label.text = "MAIN POWER\n(Elevator)"
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.95, 0.92, 0.78, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = console.position + Vector3(0.05, 0.6, 0.0)
	add_child(label)


func _spawn_co2_scrubber() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_z: float = d_m * 0.5
	var scrubber: StaticBody3D = StaticBody3D.new()
	scrubber.set_script(Co2ScrubberScript)
	scrubber.name = "CO2Scrubber"
	scrubber.position = Vector3(-w_m * 0.22, 0.0, half_z - 3.0)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.6, 1.8, 1.1)
	cs.shape = box
	cs.position = Vector3(0.0, 0.9, 0.0)
	scrubber.add_child(cs)

	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.18, 0.20, 0.22)
	housing_mat.metallic = 0.65
	housing_mat.roughness = 0.38
	var warning_mat: StandardMaterial3D = StandardMaterial3D.new()
	warning_mat.albedo_color = Color(1.0, 0.42, 0.12)
	warning_mat.emission_enabled = true
	warning_mat.emission = Color(1.0, 0.35, 0.10)
	warning_mat.emission_energy_multiplier = 2.6
	var lime_mat: StandardMaterial3D = StandardMaterial3D.new()
	lime_mat.albedo_color = Color(0.72, 0.92, 0.38)
	lime_mat.emission_enabled = true
	lime_mat.emission = Color(0.42, 0.78, 0.18)
	lime_mat.emission_energy_multiplier = 0.9

	_add_mesh_box(scrubber, Vector3(0.0, 0.85, 0.0), Vector3(1.4, 1.5, 0.8), housing_mat)
	_add_mesh_box(scrubber, Vector3(0.0, 1.52, -0.43), Vector3(1.1, 0.14, 0.08), warning_mat)
	_add_mesh_box(scrubber, Vector3(-0.42, 0.72, -0.46), Vector3(0.24, 0.56, 0.08), lime_mat)
	_add_mesh_box(scrubber, Vector3(0.0, 0.72, -0.46), Vector3(0.24, 0.56, 0.08), lime_mat)
	_add_mesh_box(scrubber, Vector3(0.42, 0.72, -0.46), Vector3(0.24, 0.56, 0.08), lime_mat)

	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = "CO2 SCRUBBER"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.75, 0.95, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, 2.0, 0.0)
	scrubber.add_child(label)

	add_child(scrubber)


func _add_mesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# Dr Rush in the control interface room. Stands at the NW console (one of four
# arranged around the central power pillar by RoomBuilder._accent_control_pillar),
# body facing -X toward the console so he reads as "focused on his work" when
# the player walks in — he ignores Eli until interacted with (Interactable
# already gates on E + proximity, auto_greet stays off by default).
# First interact flips `met_rush` and re-checks episode completion.
func _spawn_dr_rush() -> void:
	# Mirrors RoomBuilder._accent_control_room — the east console sits 4 m
	# east of origin with its screen facing +X (outward toward operator).
	# Rush stands on the OUTER side of the east console (between console
	# and east wall) facing -X so his look direction passes through the
	# console screen and onward to the central pillar.
	const CONSOLE_OFFSET: float = 4.0
	var pos: Vector3 = Vector3(CONSOLE_OFFSET + 1.0, 0.0, 0.0)
	var rush: StaticBody3D = StaticBody3D.new()
	rush.set_script(NpcScript)
	rush.name = "DrRush"
	rush.position = pos
	rush.rotation.y = PI * 0.5  # Forward = -X (toward console + pillar at room centre).
	rush.set("character_name", "Dr Rush")
	rush.set("prompt", "Talk to Dr Rush")
	# Choice-tree dialog — Rush brushes Eli off. The only useful instruction is
	# the closer: "nothing for now, get some rest." That advances the player's
	# quest to FIND_REST (eli_quarters).
	rush.set("dialogue_tree", [
		{
			"speaker": "Dr Rush",
			"text": "Eli. I'm in the middle of something. What do you need?",
			"choices": [
				{"text": "Scott sent me. What should I do?", "next": 1},
				{"text": "Where are we?", "next": 2},
				{"text": "What is this ship?", "next": 3},
				{"text": "I'll leave you to it.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Rush",
			"text": "Nothing for now. Honestly. You look exhausted — go get some rest. I'll send for you when I have something.",
			"choices": [
				{"text": "Where would I even go?", "next": 4},
				{"text": "Understood.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Rush",
			"text": "Several billion light years from Earth, if my early readings are right. The ship doesn't know we're aboard — that's the only reason we're still breathing. Now: rest. Go.",
			"choices": [
				{"text": "Where would I even go?", "next": 4},
				{"text": "Right. Carrying on.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Rush",
			"text": "An Ancient seed ship. Launched long before Atlantis, on a fixed FTL sequence. We're along for the ride. There — that's your briefing. Nothing for you to do right now except sleep.",
			"choices": [
				{"text": "Where would I even go?", "next": 4},
				{"text": "Back to the start.", "next": 0},
				{"text": "Got it.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Rush",
			"text": "Your quarters, Eli. Down the corridor, past Control. Find them. Lay down. Stop hovering over my shoulder.",
			"choices": [
				{"text": "On my way.", "next": "exit"},
			],
		},
	])
	rush.set("met_flag", "met_rush")
	rush.set("first_meet_recompute_objective", true)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0.0, 0.88, 0.0)
	rush.add_child(cs)

	# Visual body — Kenney "Mini Characters 1" GLB (character-male-f), distinct
	# from Scott's character-male-d so the two NPCs read differently at a glance.
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.position = Vector3(0.0, 0.0, 0.0)
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	# Kenney mini characters export with +Z forward; rotate 180° so the model
	# faces the same direction as its parent StaticBody3D's -Z forward.
	model_holder.rotation.y = PI
	var rush_glb: PackedScene = load("res://models/characters/rush.glb")
	if rush_glb != null:
		var rush_model: Node = rush_glb.instantiate()
		model_holder.add_child(rush_model)
		var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
		Npc.apply_kenney_colormap(rush_model, colormap)
		Npc.play_idle_animation(rush_model)
	rush.add_child(model_holder)

	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = "Dr Rush"
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.00, 0.0)
	rush.add_child(tag)

	add_child(rush)


# Generic NPC spawn — mirrors the manual _spawn_dr_rush construction so the
# six secondary crew members can share a single code path. Returns the
# StaticBody3D so callers can tweak post-hoc if needed.
func _spawn_npc(
		npc_name: String,
		character_name: String,
		pos: Vector3,
		yaw: float,
		glb_path: String,
		dialog_tree: Array,
		met_flag: String = ""
	) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.set_script(NpcScript)
	body.name = npc_name
	body.position = pos
	body.rotation.y = yaw
	body.set("character_name", character_name)
	body.set("prompt", "Talk to %s" % character_name)
	body.set("dialogue_tree", dialog_tree)
	if met_flag != "":
		body.set("met_flag", met_flag)
		body.set("first_meet_recompute_objective", true)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0.0, 0.88, 0.0)
	body.add_child(cs)

	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	# Kenney mini chars export +Z forward; rotate so model faces -Z (parent forward).
	model_holder.rotation.y = PI
	var glb: PackedScene = load(glb_path)
	if glb != null:
		var inst: Node = glb.instantiate()
		model_holder.add_child(inst)
		var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
		Npc.apply_kenney_colormap(inst, colormap)
		Npc.play_idle_animation(inst)
	body.add_child(model_holder)

	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = character_name
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.00, 0.0)
	body.add_child(tag)

	add_child(body)
	return body


# Senior officer in the control interface room — pacing near a console east of the
# central hologram spine, watching readouts. Stoic, command-school cadence.
func _spawn_colonel_young() -> void:
	_spawn_npc(
		"ColonelYoung",
		"Colonel Young",
		Vector3(5.5, 0.0, -1.5),
		-PI * 0.75,  # face back toward spine / Rush
		"res://models/characters/scott.glb",
		[
			{
				"speaker": "Colonel Young",
				"text": "Stay sharp, son. We don't know what we're standing on yet. Have a question, or are you just walking the deck?",
				"choices": [
					{"text": "What's our situation?", "next": 1},
					{"text": "What can I do, sir?", "next": 2},
					{"text": "Just passing through.", "next": "exit"},
				],
			},
			{
				"speaker": "Colonel Young",
				"text": "Best estimate: we're on an Ancient ship a very long way from home. Atmosphere holds for now. Power's marginal. Rush is reading the consoles. The rest of us are buying him time.",
				"choices": [
					{"text": "What can I do, sir?", "next": 2},
					{"text": "Acknowledged.", "next": "exit"},
				],
			},
			{
				"speaker": "Colonel Young",
				"text": "Listen for the radio. If a hull alarm goes off, you move. Otherwise, get rested — I need everyone able to think when this ship decides to surprise us.",
				"choices": [
					{"text": "Yes, sir.", "next": "exit"},
				],
			},
		],
		"met_young",
	)


# Civilian scientist in the control room — tracking power systems on a side console.
func _spawn_dr_james() -> void:
	_spawn_npc(
		"DrJames",
		"Dr James",
		Vector3(-4.5, 0.0, 3.8),
		PI * 0.25,
		"res://models/characters/eli.glb",
		[
			{
				"speaker": "Dr James",
				"text": "Reactor's pulling more than it's giving — I can see the curve, I just can't read what's draining it. Did you need something?",
				"choices": [
					{"text": "What are you working on?", "next": 1},
					{"text": "Should I be worried?", "next": 2},
					{"text": "Sorry to interrupt.", "next": "exit"},
				],
			},
			{
				"speaker": "Dr James",
				"text": "Power balance. The Ancients ran this ship on something like a stellar tap — and we're stuck on whatever's left in the cells. If we can't refuel, we drift.",
				"choices": [
					{"text": "Should I be worried?", "next": 2},
					{"text": "Hope you crack it.", "next": "exit"},
				],
			},
			{
				"speaker": "Dr James",
				"text": "Worried, yes. Panicked, no. Rush is on the master code, Colonel Young's keeping people calm. Your job is to keep yourself alive — patch leaks, eat, sleep.",
				"choices": [
					{"text": "Will do.", "next": "exit"},
				],
			},
		],
		"met_james",
	)


# Civilian scientist on the opposite side of the control room. Quieter than James;
# focused on environmental systems.
func _spawn_dr_park() -> void:
	_spawn_npc(
		"DrPark",
		"Dr Park",
		Vector3(3.2, 0.0, 5.0),
		-PI * 0.25,
		"res://models/characters/eli.glb",
		[
			{
				"speaker": "Dr Park",
				"text": "Hey. I'm trying to figure out which vents actually scrub and which ones are decorative. So far it's about half and half. Need anything?",
				"choices": [
					{"text": "Is the air safe?", "next": 1},
					{"text": "Need help?", "next": 2},
					{"text": "I'll let you work.", "next": "exit"},
				],
			},
			{
				"speaker": "Dr Park",
				"text": "Safe-ish. The CO₂ readings are climbing slowly. Not dangerous yet, but if we lose a scrubber we'll feel it within a day. Hence the half-and-half audit.",
				"choices": [
					{"text": "Need help?", "next": 2},
					{"text": "Good to know.", "next": "exit"},
				],
			},
			{
				"speaker": "Dr Park",
				"text": "Not from you, not yet — I need a multimeter that hasn't shown up on this ship. If you find one in a storage locker, bring it back. Otherwise: stay healthy, breathe shallow.",
				"choices": [
					{"text": "I'll keep an eye out.", "next": "exit"},
				],
			},
		],
		"met_park",
	)


# Sergeant pulling corridor watch in the east corridor — alongside the hull
# breach that the player is meant to seal. Direct, blunt, useful.
func _spawn_sgt_greer() -> void:
	_spawn_npc(
		"SgtGreer",
		"Sgt Greer",
		Vector3(0.0, 0.0, 8.0),
		PI,  # face north (-z) so he's watching back toward the gate room
		"res://models/characters/scott.glb",
		[
			{
				"speaker": "Sgt Greer",
				"text": "You see that breach down the hall? Don't walk past it. Seal it, then come back through this way. Got me?",
				"choices": [
					{"text": "Where's the switch?", "next": 1},
					{"text": "What if it gets worse?", "next": 2},
					{"text": "Copy that.", "next": "exit"},
				],
			},
			{
				"speaker": "Sgt Greer",
				"text": "Opposite wall from the breach. Big yellow handle. You can't miss it unless you're trying. Hit it, panel slams down, problem stops.",
				"choices": [
					{"text": "What if it gets worse?", "next": 2},
					{"text": "On it.", "next": "exit"},
				],
			},
			{
				"speaker": "Sgt Greer",
				"text": "Then we lose the corridor and probably anyone in it. So don't make me come do it for you. Move.",
				"choices": [
					{"text": "Moving.", "next": "exit"},
				],
			},
		],
		"met_greer",
	)


# Civilian along the south corridor — Chloe, the IOA daughter. She's already
# been through the gate-room briefing and is wandering, trying to be useful.
func _spawn_chloe() -> void:
	_spawn_npc(
		"Chloe",
		"Chloe Armstrong",
		Vector3(12.0, 0.0, 0.0),
		-PI * 0.5,  # face -x, back toward gate room
		"res://models/characters/eli.glb",
		[
			{
				"speaker": "Chloe Armstrong",
				"text": "Hi. I — sorry, I don't actually know what I'm supposed to be doing. Are you with the military, or…?",
				"choices": [
					{"text": "Civilian, same as you.", "next": 1},
					{"text": "Did you know your father…?", "next": 2},
					{"text": "I should keep moving.", "next": "exit"},
				],
			},
			{
				"speaker": "Chloe Armstrong",
				"text": "Oh. Good. I keep apologising to people in uniform. I came through the gate with my dad — Senator Armstrong. He's resting. They said it was bad.",
				"choices": [
					{"text": "I'm sorry.", "next": 2},
					{"text": "Hang in there.", "next": "exit"},
				],
			},
			{
				"speaker": "Chloe Armstrong",
				"text": "He's stable. That's what they say. I want to believe it. If you see Colonel Young, tell him I'm not in the way — I just don't want to sit in a room and wait.",
				"choices": [
					{"text": "I'll tell him.", "next": "exit"},
				],
			},
		],
		"met_chloe",
	)


# Anonymous soldier on north-corridor patrol. Short, professional exchange —
# reinforces that there's a chain of command beyond the named officers.
func _spawn_soldier() -> void:
	_spawn_npc(
		"Soldier",
		"Soldier",
		Vector3(-15.0, 0.0, 0.0),
		PI * 0.5,  # face +x, walking east
		"res://models/characters/scott.glb",
		[
			{
				"speaker": "Soldier",
				"text": "Ma'am. Sir. Sorry — half of us don't know who's who yet. Need directions?",
				"choices": [
					{"text": "What's down this corridor?", "next": 1},
					{"text": "Everything okay up here?", "next": 2},
					{"text": "I'm good. Carry on.", "next": "exit"},
				],
			},
			{
				"speaker": "Soldier",
				"text": "Control room east of us, an elevator further along, and the crew quarters around the corner. Stick to lit hallways — the ship's still showing us new sections.",
				"choices": [
					{"text": "Everything okay up here?", "next": 2},
					{"text": "Thanks.", "next": "exit"},
				],
			},
			{
				"speaker": "Soldier",
				"text": "Quiet so far. Couple of hull alarms south of here earlier. Sergeant Greer's down there if you need to report something.",
				"choices": [
					{"text": "Good to know.", "next": "exit"},
				],
			},
		],
		"met_soldier",
	)


# -------- quest waypoint ---------------------------------------------------

func _on_quest_objective_changed(_text: String) -> void:
	_refresh_quest_waypoint()


# Position the floating diamond either above the in-room anchor for the
# current quest target, or — when the target is in another room — above the
# door leading toward that room (per ShipLayout's BFS). Spawns the marker on
# first use and reuses it thereafter.
func _refresh_quest_waypoint() -> void:
	var target: Dictionary = GameState.quest_target()
	var target_room: String = String(target.get("room", ""))
	var anchor_name: String = String(target.get("anchor", ""))

	if target_room == "":
		_destroy_quest_waypoint()
		return

	var pos: Vector3 = Vector3.ZERO
	var placed: bool = false

	if target_room == room_id:
		# In-room anchor (NPC, pickup, console, bed). Empty anchor name falls
		# back to the room centre at standing-eye height.
		if anchor_name == "":
			pos = Vector3(0.0, QUEST_WAYPOINT_ANCHOR_HEIGHT, 0.0)
			placed = true
		else:
			var anchor: Node = get_node_or_null(anchor_name)
			if anchor is Node3D:
				var n3: Node3D = anchor
				var offset_y: float = WAYPOINT_OFFSET_BY_ANCHOR.get(anchor_name, QUEST_WAYPOINT_ANCHOR_HEIGHT)
				pos = n3.global_position + Vector3(0.0, offset_y, 0.0)
				placed = true
	else:
		# Cross-room — point at the door leading to the next hop on the path.
		var next_hop: String = ShipLayout.next_room_toward(room_id, target_room)
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
		world.add_child(_quest_waypoint)
	_quest_waypoint.global_position = pos
	if _quest_waypoint.has_method("set_target_position"):
		_quest_waypoint.call("set_target_position", pos)


func _destroy_quest_waypoint() -> void:
	if _quest_waypoint != null and is_instance_valid(_quest_waypoint):
		_quest_waypoint.queue_free()
	_quest_waypoint = null


# Door iteration: doors are direct children of self (added in _stamp_door) and
# expose `target_room_id` via set/get. We use the property rather than the
# script type so the lookup tolerates duck-typed swap-ins.
func _find_door_to(target_id: String) -> Node3D:
	for c in get_children():
		if not (c is Node3D):
			continue
		var n: Node3D = c
		var prop: Variant = n.get("target_room_id")
		if prop != null and String(prop) == target_id:
			return n
	return null


# -------- helpers ----------------------------------------------------------

func _apply_corridor_min_short_axis(min_metres: float) -> void:
	if String(_room_data.get("template_id", "")) != "corridor-template":
		return
	var min_units: float = min_metres / ShipLayout.SCALE
	var w: float = float(_room_data.get("width", 0))
	var h: float = float(_room_data.get("height", 0))
	# Widen whichever axis is the short axis (preserving "long" vs "short" identity).
	if w <= h:
		_room_data["width"] = maxf(w, min_units)
	else:
		_room_data["height"] = maxf(h, min_units)


func _load_connections() -> Dictionary:
	var f: FileAccess = FileAccess.open(CONNECTIONS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


func _flip_direction(dir: String) -> String:
	match dir:
		"+x": return "-x"
		"-x": return "+x"
		"+z": return "-z"
		"-z": return "+z"
		_: return dir


func _to_camel(snake: String) -> String:
	var out: String = ""
	for part in snake.split("_"):
		if part.length() == 0:
			continue
		out += part[0].to_upper() + part.substr(1)
	return out


func _humanize(id: String) -> String:
	# control_interface_room → "Control Interface Room"
	var parts: PackedStringArray = id.split("_")
	var out: PackedStringArray = []
	for p in parts:
		if p.length() == 0:
			continue
		out.append(p[0].to_upper() + p.substr(1))
	return " ".join(out)
