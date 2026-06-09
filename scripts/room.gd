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
const ShuttleCrateScript: Script = preload("res://scripts/shuttle_crate.gd")
const ShuttleDoorPanelScript: Script = preload("res://scripts/shuttle_door_panel.gd")
const NpcScript: Script = preload("res://scripts/npc.gd")
const ScrubberRushScript: Script = preload("res://scripts/scrubber_rush.gd")
const GreerScript: Script = preload("res://scripts/greer.gd")
const InfirmaryJamesScript: Script = preload("res://scripts/infirmary_james.gd")
const KinoDispenserScript: Script = preload("res://scripts/kino_dispenser.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
const Co2ScrubberScript: Script = preload("res://scripts/co2_scrubber.gd")
const PowerConsoleScript: Script = preload("res://scripts/power_console.gd")
const QuestWaypointScript: Script = preload("res://scripts/quest_waypoint.gd")
# Preload (not class_name lookup) — class_name registration can lag in
# headless `-s` runs so the bare identifier sometimes resolves at parse-time
# and sometimes doesn't. preload always works.
const ShipAlertScript: Script = preload("res://scripts/ship_alert.gd")
const ElevatorPanelScript: Script = preload("res://scripts/elevator_panel.gd")
const FloorCodeTerminalScript: Script = preload("res://scripts/floor_code_terminal.gd")
const AssignmentConsoleScript: Script = preload("res://scripts/assignment_console.gd")
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
	"ShuttleDoorPanel": 0.7,   # wall panel beside the jammed door
	"PowerConsole": 0.7,       # wall console
	"CO2Scrubber": 1.4,        # scrubber housing top
	"ControlConsoleNearest": 1.4, # nearest-console sentinel (see _find_nearest_in_group)
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
# Multiple diamonds for the Shuttle Dock crate-search phase: one per un-looted
# crate. Separate from the single _quest_waypoint used by every other beat.
var _crate_waypoints: Array[Node3D] = []
# True once the red-alert tint has been applied to this scene, so the objective
# handler knows whether it needs to clear the tint when the breach is sealed.
var _alert_applied: bool = false


func _ready() -> void:
	# Resolve which room we are. Door-set baton wins over @export.
	if GameState.next_room_id != "":
		room_id = GameState.next_room_id
		GameState.next_room_id = ""
	if room_id == "":
		push_error("room.gd: no room_id provided (GameState.next_room_id and @export both empty)")
		return

	_room_data = ProceduralShip.room(room_id)
	if _room_data.is_empty():
		push_error("room.gd: ProceduralShip has no row for '%s'" % room_id)
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
	# Red-alert tint applies to lights + WorldEnvironment if the air crisis
	# is active. Runs after RoomBuilder.build so it catches every light the
	# accent functions just spawned. Idempotent on re-entry.
	if ShipAlertScript.is_alert_active():
		ShipAlertScript.apply_to_scene(self)
		_alert_applied = true
	GameState.discover_room(room_id, String(_room_data.get("name", room_id)))
	GameState.set_current_room(room_id)
	# Leaving the infirmary after a recovery beat clears the knockout flag so the
	# next infirmary visit shows the normal post-crisis ward (issue #92).
	if room_id != "infirmary" and GameState.recovering_in_infirmary:
		GameState.clear_infirmary_recovery()
	if room_id == "quarters_room_1":
		GameState.mark_quarters_found()
	elif room_id == "eli_quarters":
		GameState.mark_eli_quarters_found()

	# Post-crisis return to the control room: Rush is gone, Eli radios Scott,
	# Scott hands the problem to Eli, and the quest advances to "access a
	# control terminal".
	if (room_id == "control_interface_room"
			and GameState.air_crisis_started
			and GameState.quest_step == GameState.QUEST_RETURN_TO_CONTROL):
		_trigger_rush_absent_beat()

	# Persist for save/load — F5 reloads this scene with the same room_id.
	GameState.current_scene_path = "res://scenes/room.tscn"

	# Piloted-Kino arrival: the player flew a Kino through a transition door into
	# this room (issue #49). discover_room/set_current_room above already lit the
	# room up on the map for free. Hand the scene to a fresh recon drone instead
	# of the static player rig and bail before the player-facing waypoint setup.
	if GameState.kino_pilot_mode:
		_start_kino_arrival()
		return

	# Quest diamond waypoint — refreshes on objective_changed so quest
	# advances mid-room (e.g. picking up the Kino) reposition the diamond
	# without needing a room reload.
	_refresh_quest_waypoint()
	if not GameState.objective_changed.is_connected(_on_quest_objective_changed):
		GameState.objective_changed.connect(_on_quest_objective_changed)


# Stamp door + matching spawn Marker3D for each connection that originates at
# this room (and the reverse-edge stamp from any other room that points here).
# Delegates edge resolution to ProceduralShip.door_edges() which handles both
# base (authored) rooms and procedurally generated rooms uniformly.
func _setup_doors() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	for edge: Dictionary in ProceduralShip.door_edges(room_id):
		_stamp_door(edge, half_x, half_z)


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
	var target: Dictionary = ProceduralShip.room(target_id)
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


# Piloted-Kino arrival into this procedural room (issue #49). Mirrors
# planet.gd::_start_kino_recon: tear down the static third-person rig (player +
# view), hide the on-foot HUD, and spawn a fresh recon drone at the door's
# arrival marker so the DRONE (never the body) lands at the spawn point — no
# SceneRouter clobber because the crossing used an empty spawn key. kino_pilot_mode
# stays set so the next hop keeps piloting.
func _start_kino_arrival() -> void:
	var spawn_key: String = GameState.kino_pilot_arrival_spawn
	GameState.kino_pilot_arrival_spawn = ""
	# Drone hovers at eye height above the floor-anchored arrival marker, facing
	# the way the marker faces (into the room — away from the door it came through).
	var spawn_pos: Vector3 = Vector3(0.0, 1.4, 0.0)
	var spawn_yaw: float = 0.0
	if spawn_key != "":
		var marker: Node = markers.get_node_or_null(spawn_key)
		if marker is Marker3D:
			var m: Marker3D = marker
			spawn_pos = m.global_position + Vector3.UP * 1.4
			spawn_yaw = m.rotation.y
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(view):
		view.queue_free()
	var hud_layer: Node = get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	# Headless / instant_mode tests assert on state, not the live drone — the
	# drone's own _ready early-returns under instant_mode, so spawning it is safe
	# but unnecessary. Spawn it anyway so the node graph matches real play.
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	# NOT in group "player": the recon drone is a camera, not the player body.
	drone.set("launch_in_ship", false)
	# Set yaw BEFORE add_child so the drone caches its initial heading in _ready.
	drone.rotation.y = spawn_yaw
	add_child(drone)
	drone.global_position = spawn_pos
	# Ship auto-explore (issue #50, Phase 4b): if the previous room's drone was
	# auto-exploring when it hopped here, re-arm this fresh drone so it keeps
	# crawling undiscovered doors. start_ship_autopilot bails under instant_mode
	# (the drone's _ready also early-returns headless, leaving no camera), so a
	# headless run never triggers further Kino scene churn. Deferred so the
	# drone's own _ready (camera/HUD build) finishes first.
	if GameState.kino_autopilot and not SceneRouter.instant_mode:
		drone.call_deferred("start_ship_autopilot")


func _spawn_interactables() -> void:
	match room_id:
		"quarters_room_1":
			_spawn_quarters_bed()
		"eli_quarters":
			# Eli's room — Eli IS the player. Houses the Kino Remote pickup on
			# the desk and his bed for the FIND_REST → SLEEP quest beat.
			_spawn_eli_kino_pickup()
			_spawn_quarters_bed("My bed. Time to crash.")
			# Kino dispenser appears once Phase E begins (Brody's "no MALP" beat
			# sends Eli back here for a Kino to scout the planet).
			if GameState.reported_to_gate:
				_spawn_kino_dispenser()
		"east_corridor":
			# Sgt Greer holds the east corridor; the actual breach lives in the
			# far-south Damaged Section now.
			_spawn_sgt_greer()
		"breached_section_south":
			# Shuttle Dock: jammed door venting atmo from the damaged shuttle to
			# the west, a dead door panel beside it, and 3 lootable crates (one
			# holds the actuator). The Phase C seal mini-quest lives here.
			_spawn_shuttle_dock()
		"control_interface_room":
			# Pre-crisis: Rush is at his console. Once the air crisis starts he
			# has left to chase the fault elsewhere — the player arrives to an
			# empty control room, radios Scott, and works the terminal alone
			# (see _trigger_rush_absent_beat). Young, James, Park are in the
			# gate room with the unconscious-Young tableau.
			if not GameState.air_crisis_started:
				_spawn_dr_rush()
			# Floor 2 access-code terminal: always present in the control room
			# (a data terminal the player can examine). Disabled once collected.
			_spawn_floor_code_terminal(2)
		"engineering_bay":
			_spawn_power_console()
		"south_corridor":
			# The CO2 scrubber wall panel always exists (it's a fixture), but the
			# corridor stays EMPTY of people until the player seals the Shuttle
			# Dock breach below — nobody's down here while it's still venting.
			# After the seal: Chloe is about, and during the Phase D window
			# (breach sealed, scrubber not yet diagnosed) Rush + Park work the
			# panel. Once diagnosed they don't respawn (they've moved on).
			var scrubber: StaticBody3D = _spawn_co2_scrubber()
			if not GameState.breaches_sealed.is_empty():
				_spawn_chloe()
				if GameState.air_crisis_started and not GameState.scrubber_diagnosed:
					_spawn_scrubber_crew(scrubber.position)
		"north_corridor":
			_spawn_soldier()
			# Optional maintenance scrubber (issue: ship-wide scrubbers). West end
			# of the long corridor, clear of the mid-wall spur/approach doors.
			_spawn_co2_scrubber("north_corridor", -350.0)
		"east_corridor_far":
			# New maintenance spur off the east corridor — houses a scrubber.
			_spawn_co2_scrubber("east_far", 0.0)
		"hydroponics":
			# The upper-deck hydroponics bay (its door plaque already reads
			# "Hydroponics — CO2 Scrubber").
			_spawn_co2_scrubber("hydroponics", 0.0)
		"infirmary":
			# A downed player wakes here for the no-death recovery beat (issue
			# #92): TJ at the bedside with a cause-tagged line. Otherwise, post-
			# crisis James has moved Young here to recover; pre-crisis the pair
			# are still in the gate-room arrival tableau (empty ward).
			if GameState.recovering_in_infirmary:
				_spawn_recovery_ward()
			elif GameState.air_crisis_started:
				_spawn_infirmary_ward()
		"elevator_north", "elevator_room_floor_1":
			# Elevator rooms: wall-mounted floor-selection panel (Phase B).
			_spawn_elevator_panel()
			# Floor-2 access code lives in control_interface_room (base room)
			# but the terminal marker for floor 2 belongs here so the player can
			# find the panel before they know where the code is. The actual
			# terminal is spawned in control_interface_room via the generated
			# floor dispatch below.
			pass
		_:
			# Generated room dispatch. Runs AFTER all authored room ids have
			# been matched (the _ branch only fires when no authored id matched).
			if ProceduralShip.is_generated(room_id):
				_spawn_generated_room_interactables()


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
# Kino dispenser barrel on the +X (right) wall, +Z side — clear of the desk
# (centre) and bed. Spawned only once Phase E has begun (see dispatch).
func _spawn_kino_dispenser() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var disp: StaticBody3D = StaticBody3D.new()
	disp.set_script(KinoDispenserScript)
	disp.name = "KinoDispenser"
	disp.position = Vector3(w_m * 0.5 - 0.9, 0.0, d_m * 0.5 - 2.5)
	add_child(disp)


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

	# Pickup hitbox — DELIBERATELY large. The kino prop on the desk is tiny
	# (~0.05 m at scale 0.2) so a tight box requires pixel-precise aim with
	# the camera. Box is sized to cover the whole desktop surface above the
	# kino so the player can E from any approach angle as long as their
	# camera points at the desk. Tall (0.9 m) so the chest-height interact
	# ray catches it from a step back, too.
	var pickup: StaticBody3D = StaticBody3D.new()
	pickup.set_script(KinoPickupScript)
	pickup.name = "KinoPickup"
	pickup.position = holder.position
	pickup.set("prop_to_hide", NodePath("../KinoProp"))
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 0.9, 1.4)
	cs.shape = box
	pickup.add_child(cs)
	add_child(pickup)


# Shuttle Dock (breached_section_south). The west wall holds a jammed bulkhead
# door ajar — venting atmosphere from the damaged shuttle beyond — with a dead
# control panel just south of it. Three lootable crates line the east wall;
# the middle one holds the Small Fuse the panel needs. Fitting it grinds
# the door shut and seals the breach. If already sealed (loaded save) the door
# spawns closed and the panel screen reads green.
func _spawn_shuttle_dock() -> void:
	const BREACH_ID: String = "breach_a"
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	var sealed: bool = GameState.breaches_sealed.has(BREACH_ID)
	var door_z: float = 0.0

	# --- Jammed bulkhead door on the -X (west) wall ---
	var leaf: Node3D = _spawn_jammed_door(Vector3(-half_x + 0.06, 1.3, door_z), sealed)

	# --- Door control panel to the LEFT of the door (south/+Z side — the
	# player's left when they enter from the north and face the west wall) ---
	var panel_pos: Vector3 = Vector3(-half_x + 0.22, 1.3, door_z + 1.7)
	var panel: StaticBody3D = StaticBody3D.new()
	panel.set_script(ShuttleDoorPanelScript)
	panel.name = "ShuttleDoorPanel"
	panel.position = panel_pos
	var p_cs: CollisionShape3D = CollisionShape3D.new()
	var p_box: BoxShape3D = BoxShape3D.new()
	p_box.size = Vector3(0.5, 0.7, 0.6)
	p_cs.shape = p_box
	panel.add_child(p_cs)
	add_child(panel)
	# Grind the jammed door shut when the panel reports a successful seal.
	if leaf != null:
		panel.connect("door_sealed", _close_jammed_door.bind(leaf))
	# Rush radios in the moment the breach is sealed, pointing the player at the
	# CO2 scrubber (Phase D). The handler early-returns in instant_mode so tests
	# don't hang on the coroutine.
	panel.connect("door_sealed", _play_breach_sealed_radio)
	_add_mesh_box(self, panel_pos, Vector3(0.06, 0.6, 0.5), _flat_mat(Color(0.20, 0.20, 0.22), 0.5, 0.45))
	var screen_col: Color = Color(0.30, 0.9, 0.5) if sealed else Color(1.0, 0.3, 0.1)
	_add_mesh_box(self, panel_pos + Vector3(0.02, 0.0, 0.0), Vector3(0.04, 0.34, 0.34), _emis_mat(screen_col, 3.0))
	var plabel: Label3D = Label3D.new()
	plabel.text = "DOOR CONTROL"
	plabel.pixel_size = 0.004
	plabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plabel.outline_size = 6
	plabel.shaded = false
	plabel.modulate = Color(0.95, 0.92, 0.78, 1.0)
	plabel.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	plabel.position = panel_pos + Vector3(0.05, 0.55, 0.0)
	add_child(plabel)

	# --- Three supply crates along the +X wall. Contents: a Large Fuse (wrong
	# size), the Small Fuse the door needs (crate 2), and ration packs — the
	# player searches all three, none is a dead end. The crate owns its own
	# collider + body/lid meshes (see shuttle_crate.gd) so it can pop its lid
	# off when looted. ---
	var crate_contents: Array[String] = ["large", "small", "rations"]
	for i in 3:
		var crate: StaticBody3D = StaticBody3D.new()
		crate.set_script(ShuttleCrateScript)
		crate.name = "ShuttleCrate%d" % (i + 1)
		crate.position = Vector3(half_x - 1.3, 0.0, -2.6 + float(i) * 2.6)
		crate.set("fuse_type", crate_contents[i])
		add_child(crate)
		# Refresh the per-crate diamonds after a loot. interacted fires BEFORE
		# the crate's _on_interact sets _looted, so defer until the loot has
		# actually applied.
		crate.connect("interacted", _on_crate_interacted)


# A bulkhead door on the west wall: slightly ajar when unsealed (a dark vent
# gap behind it reads as the venting shuttle bay), flush-closed when sealed.
# Returns the door leaf MeshInstance so the panel can grind it shut on repair.
func _spawn_jammed_door(pos: Vector3, sealed: bool) -> Node3D:
	var wrap: Node3D = Node3D.new()
	wrap.name = "JammedDoor"
	wrap.position = pos
	add_child(wrap)
	# Dark vent gap behind the door — the damaged shuttle / open space beyond.
	_add_mesh_box(wrap, Vector3(-0.05, 0.0, 0.0), Vector3(0.06, 2.2, 1.9), _flat_mat(Color(0.02, 0.03, 0.05), 0.0, 1.0))
	var leaf: MeshInstance3D = MeshInstance3D.new()
	leaf.name = "Leaf"
	var leaf_box: BoxMesh = BoxMesh.new()
	leaf_box.size = Vector3(0.12, 2.2, 1.8)
	leaf.mesh = leaf_box
	leaf.material_override = _flat_mat(Color(0.42, 0.44, 0.48), 0.7, 0.4)
	# Ajar (slid +Z) when unsealed; centred (shut) when sealed.
	leaf.position = Vector3(0.0, 0.0, 0.0 if sealed else 1.0)
	wrap.add_child(leaf)
	if not sealed:
		_add_mesh_box(wrap, Vector3(0.05, 0.0, -0.95), Vector3(0.04, 2.2, 0.08), _emis_mat(Color(1.0, 0.55, 0.1), 3.0))
	return leaf


func _close_jammed_door(leaf: Node3D) -> void:
	if leaf == null or not is_instance_valid(leaf):
		return
	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.tween_property(leaf, "position:z", 0.0, 0.8)


# Inline StandardMaterial3D helpers for the procedural shuttle-dock props.
func _flat_mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m


func _emis_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


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


# Spawn a CO2 scrubber wall panel on the -Z wall at world-x `x`. `unit_id` ""
# builds the E1 story scrubber (south corridor); a non-empty id builds an
# optional maintenance unit backed by GameState's scrubber_units registry
# (discover/open/recharge at leisure). Set scrubber_id BEFORE add_child so the
# panel's _ready reads it.
func _spawn_co2_scrubber(unit_id: String = "", x: float = -10.0) -> StaticBody3D:
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_z: float = d_m * 0.5
	var scrubber: StaticBody3D = StaticBody3D.new()
	scrubber.set_script(Co2ScrubberScript)
	scrubber.name = "CO2Scrubber"
	if unit_id != "":
		scrubber.set("scrubber_id", unit_id)
	scrubber.position = Vector3(x, 0.0, -half_z + 0.15)
	add_child(scrubber)
	return scrubber


# Rush + Park stand shoulder-to-shoulder right in front of the open scrubber
# panel for the Phase D reveal — both within ~1 m of the panel and ~1.1 m apart,
# centred on it, so they read as a pair working the exposed bank. The scene's
# dialogue is driven by scrubber_rush.gd; these are the on-screen figures.
func _spawn_scrubber_crew(panel_pos: Vector3) -> void:
	# Rush carries the whole multi-speaker scene (scrubber_rush.gd sets its own
	# dialogue_tree + drives the FTL beat), so pass an empty tree + its script.
	# Node name MUST differ from the control-room "DrRush" — NPCState keys saved
	# position by node name, so a shared name cross-restores this Rush to the
	# control-room Rush's spot. Display name stays "Dr Rush".
	_spawn_npc(
		"ScrubberRush",
		"Dr Rush",
		panel_pos + Vector3(-0.55, 0.0, 1.0),
		0.0,  # face -Z, toward the panel
		"res://models/characters/rush.glb",
		[],
		"",
		ScrubberRushScript,
	)
	_spawn_npc(
		"DrPark",
		"Dr Park",
		panel_pos + Vector3(0.6, 0.0, 1.0),
		0.0,
		"res://models/characters/park.glb",
		[
			{
				"speaker": "Dr Park",
				"text": "Rush thinks it's the scrubber. I'm hoping he's wrong, for once.",
				"choices": [{"text": "Same.", "next": "exit"}],
			},
		],
	)


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


# Post-crisis "Rush isn't here" beat. Eli radios Scott, Scott hands the
# problem off, and the quest advances RETURN_TO_CONTROL → access-terminal.
# Skipped (state flipped synchronously) under SceneRouter.instant_mode so
# the headless playthrough doesn't have to wait out the radio timers.
func _trigger_rush_absent_beat() -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		GameState.mark_control_room_returned()
		return
	_play_rush_absent_radio()


func _play_rush_absent_radio() -> void:
	# Advance the quest up front so it sticks even if the player closes the
	# comm early. Short beat after arrival so the HUD is settled before the
	# dialog opens; is_inside_tree() guards the freed-mid-await case.
	GameState.mark_control_room_returned()
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	var line_eli: String = "Uhh… Scott? Rush isn't here."
	var line_scott: String = "Well then, Eli — it's up to you. Find out what's going on."
	GameState.add_log("Eli: " + line_eli)
	GameState.add_log("Lt Scott (radio): " + line_scott)
	_play_radio_dialog([
		{"speaker": "Eli", "text": line_eli, "choices": [{"text": "(key the radio)", "next": 1}]},
		{"speaker": "Lt Scott", "text": line_scott, "choices": [{"text": "Understood.", "next": "exit"}]},
	])


# Rush radios the player the instant the jammed shuttle door is sealed: praise
# + the next objective (the CO2 scrubber in the south corridor).
func _play_breach_sealed_radio() -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	var line: String = "Good work, Eli. Now get over to the south corridor — I think I found what's causing the CO2 buildup."
	GameState.add_log("Dr Rush (radio): " + line)
	_play_radio_dialog([
		{"speaker": "Dr Rush", "text": line, "choices": [{"text": "On my way.", "next": "exit"}]},
	])


# Play a radio comm as a WoW-style dialog (single-choice continues) instead of
# timed captions, bookended by the radio click/off SFX. Quest/state changes
# happen at the call site (up front) so they stick if the player closes early.
func _play_radio_dialog(tree: Array) -> void:
	Audio.play("res://sounds/radio_click.ogg")
	if not GameState.dialog_closed.is_connected(_on_radio_dialog_closed):
		GameState.dialog_closed.connect(_on_radio_dialog_closed, CONNECT_ONE_SHOT)
	var player: Node = get_tree().get_first_node_in_group("player")
	GameState.dialog_started.emit(player, tree)


func _on_radio_dialog_closed() -> void:
	Audio.play("res://sounds/radio_off.ogg")


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
		met_flag: String = "",
		script: Script = NpcScript,
		ambient: Array[String] = [],
		alert: Array[String] = []
	) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.set_script(script)
	body.name = npc_name
	body.position = pos
	body.rotation.y = yaw
	body.set("character_name", character_name)
	body.set("prompt", "Talk to %s" % character_name)
	body.set("dialogue_tree", dialog_tree)
	if not ambient.is_empty():
		body.set("ambient_lines", ambient)
	if not alert.is_empty():
		body.set("alert_lines", alert)
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
		NpcScript,
		# Command-school cadence — calm, dry, watchful.
		[
			"Wallace.",
			"Keep your eyes open, son.",
			"Rush thinks he's got the consoles. We'll see.",
			"How're we doing on air?",
		],
		[
			"That's a hull alarm. Wallace — with me.",
			"Everybody stay calm and move with purpose.",
		],
	)


# Civilian scientist in the control room — tracking power systems on a side console.
func _spawn_dr_james() -> void:
	_spawn_npc(
		"DrJames",
		"Dr James",
		Vector3(-4.5, 0.0, 3.8),
		PI * 0.25,
		"res://models/characters/james.glb",
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
		"res://models/characters/park.glb",
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
	# greer.gd builds his line dynamically from the quest step (a single "go
	# here next" hint), so the passed tree is unused.
	_spawn_npc(
		"SgtGreer",
		"Sgt Greer",
		Vector3(0.0, 0.0, 8.0),
		PI,  # face north (-z) so he's watching back toward the gate room
		"res://models/characters/scott.glb",
		[],
		"met_greer",
		GreerScript,
	)


# Infirmary ward (simple first pass): Colonel Young recovering on a bed against
# the -Z wall, a desk against the +X wall, and Lt James pacing between the two.
func _spawn_infirmary_ward() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5

	# Bed (frame + mattress), long axis along Z, west of centre on the -Z wall.
	var bed_pos: Vector3 = Vector3(-2.5, 0.0, -half_z + 1.8)
	_add_mesh_box(self, bed_pos + Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.5, 2.2), _flat_mat(Color(0.20, 0.22, 0.26), 0.4, 0.6))
	_add_mesh_box(self, bed_pos + Vector3(0.0, 0.55, 0.0), Vector3(0.9, 0.16, 2.0), _flat_mat(Color(0.78, 0.80, 0.84), 0.1, 0.7))

	# Young laid on his back on the mattress (model tipped 90° onto its back,
	# lifted to the mattress top). Unique node name so NPCState doesn't cross-
	# restore him to the gate-room "ColonelYoung" tableau spot.
	var young: StaticBody3D = _spawn_npc(
		"InfirmaryYoung",
		"Colonel Young",
		bed_pos + Vector3(0.0, 0.55, -0.4),
		0.0,
		"res://models/characters/scott.glb",
		[
			{
				"speaker": "Colonel Young",
				"text": "I'm fine, Wallace — just banged up. Rush and Scott have it. Do what they tell you and we'll get through this.",
				"choices": [{"text": "Rest up, Colonel.", "next": "exit"}],
			},
		],
	)
	var ym: Node3D = young.get_node_or_null("Model") as Node3D
	if ym != null:
		ym.rotation = Vector3(-PI * 0.5, PI, 0.0)
		ym.position = Vector3(0.0, 0.18, 0.7)

	# Desk against the +X wall.
	var desk_pos: Vector3 = Vector3(half_x - 1.2, 0.0, -half_z + 2.4)
	_add_mesh_box(self, desk_pos + Vector3(0.0, 0.75, 0.0), Vector3(1.6, 0.1, 0.8), _flat_mat(Color(0.22, 0.24, 0.28), 0.5, 0.5))
	_add_mesh_box(self, desk_pos + Vector3(0.0, 0.35, 0.0), Vector3(1.4, 0.7, 0.6), _flat_mat(Color(0.14, 0.15, 0.18), 0.4, 0.6))

	# James paces between the bedside and her desk.
	var bedside: Vector3 = bed_pos + Vector3(1.5, 0.0, 0.4)
	var deskside: Vector3 = desk_pos + Vector3(-1.4, 0.0, 0.0)
	var james: StaticBody3D = _spawn_npc(
		"InfirmaryJames",
		"Lt James",
		bedside,
		0.0,
		"res://models/characters/james.glb",
		[
			{
				"speaker": "Lt James",
				"text": "He's stable — concussion, a couple of cracked ribs. I've got him. You just keep the air on, all right?",
				"choices": [{"text": "Will do.", "next": "exit"}],
			},
		],
		"",
		InfirmaryJamesScript,
	)
	james.set("pace_a", bedside)
	james.set("pace_b", deskside)


# No-death recovery beat (issue #92): the player wakes on the infirmary bed and
# TJ is at the bedside with a cause-tagged, semi-random wake-up line. The line is
# resolved at spawn time from GameState (data-driven pool per cause) and seeded
# into TJ's one-node dialog tree so it plays on the auto-greet. Leaving the
# infirmary clears the recovery flag (back to the normal ward next visit).
func _spawn_recovery_ward() -> void:
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_z: float = d_m * 0.5

	# Bed (frame + mattress) on the -Z wall — Eli's bed for the recovery beat.
	var bed_pos: Vector3 = Vector3(-2.5, 0.0, -half_z + 1.8)
	_add_mesh_box(self, bed_pos + Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.5, 2.2), _flat_mat(Color(0.20, 0.22, 0.26), 0.4, 0.6))
	_add_mesh_box(self, bed_pos + Vector3(0.0, 0.55, 0.0), Vector3(0.9, 0.16, 2.0), _flat_mat(Color(0.78, 0.80, 0.84), 0.1, 0.7))

	var picked: Dictionary = GameState.knockout_line()
	var speaker: String = String(picked.get("speaker", "TJ"))
	var line: String = String(picked.get("line", "You're awake. You'll be fine."))

	# TJ at the bedside, reusing the medic model. Unique node name so NPCState
	# doesn't cross-restore her to any other scene's tableau.
	var bedside: Vector3 = bed_pos + Vector3(1.6, 0.0, 0.2)
	var tj: StaticBody3D = _spawn_npc(
		"InfirmaryTJ",
		speaker,
		bedside,
		PI,  # face -X toward the bed/player
		"res://models/characters/james.glb",
		[
			{
				"speaker": speaker,
				"text": line,
				"choices": [{"text": "…where am I?", "next": "exit"}],
			},
		],
	)
	tj.set("auto_greet", true)
	tj.set("auto_greet_distance", 2.6)


# Civilian along the south corridor — Chloe, the IOA daughter. She's already
# been through the gate-room briefing and is wandering, trying to be useful.
func _spawn_chloe() -> void:
	_spawn_npc(
		"Chloe",
		"Chloe Armstrong",
		Vector3(12.0, 0.0, 0.0),
		-PI * 0.5,  # face -x, back toward gate room
		"res://models/characters/chloe.glb",
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
		NpcScript,
		# Anxious, searching — a civilian out of her depth.
		[
			"Oh — hi again.",
			"Do you think we're going to be okay?",
			"It's so quiet up here. I can't stand it.",
			"Have you seen my dad?",
		],
		# Frightened during the alarm.
		[
			"What is that?! Is the ship breaking apart?",
			"Eli — where are we supposed to go?!",
		],
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
				"text": "Mr Wallace — sir. Heading anywhere in particular, or just walking the deck?",
				"choices": [
					{"text": "What's down this corridor?", "next": 1},
					{"text": "Everything okay up here?", "next": 2},
					{"text": "Just passing through. Carry on.", "next": "exit"},
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
		NpcScript,
		# Clipped, professional — a soldier walking a beat.
		[
			"Hey, Eli.",
			"Corridor's clear, sir.",
			"Watch your step — ship's still mapping this section.",
			"Stay in the lit hallways.",
		],
		# Red-alert chatter — reacts to the hull alarm.
		[
			"Eli — that alarm! What's going on?!",
			"Hull breach somewhere. Move!",
			"Get to a sealed compartment!",
		],
	)


# -------- quest waypoint ---------------------------------------------------

func _on_quest_objective_changed(_text: String) -> void:
	_refresh_quest_waypoint()
	_refresh_alert_state()


# Re-evaluate the red-alert tint when the quest advances mid-room. Sealing the
# Shuttle Dock breach flips is_alert_active() to false, so the room reverts from
# red to its normal lighting without a reload (other rooms come up untinted on
# their next build).
func _refresh_alert_state() -> void:
	var should_alert: bool = ShipAlertScript.is_alert_active()
	if should_alert and not _alert_applied:
		ShipAlertScript.apply_to_scene(self)
		_alert_applied = true
	elif _alert_applied and not should_alert:
		ShipAlertScript.clear_scene(self)
		_alert_applied = false


# Position the floating diamond either above the in-room anchor for the
# current quest target, or — when the target is in another room — above the
# door leading toward that room (per ShipLayout's BFS). Spawns the marker on
# first use and reuses it thereafter.
func _refresh_quest_waypoint() -> void:
	var target: Dictionary = GameState.quest_target()
	var target_room: String = String(target.get("room", ""))
	var anchor_name: String = String(target.get("anchor", ""))

	# Multi-marker case: the Shuttle Dock crate-search phase puts a diamond over
	# every UN-looted crate. Each clears as its crate is emptied; all clear once
	# the Small Fuse turns up (handing back to the single panel marker below).
	if (target_room == room_id and anchor_name == "ShuttleObjective"
			and GameState.door_panel_examined and not Inventory.has("small_fuse")):
		_destroy_quest_waypoint()
		_refresh_crate_waypoints()
		return
	_clear_crate_waypoints()

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
		elif anchor_name == "ControlConsoleNearest":
			# All four control consoles are identical, so point the diamond at
			# whichever one is closest to the player — wherever they're
			# standing in the room, the objective marker is on a console they
			# can see, not a fixed cardinal one that may be behind them.
			var console: Node3D = _find_nearest_in_group("control_console")
			if console != null:
				pos = console.global_position + Vector3(0.0, WAYPOINT_OFFSET_BY_ANCHOR.get("ControlConsoleNearest", 1.4), 0.0)
				placed = true
		elif anchor_name == "ShuttleObjective":
			# Panel marker. The crate-search phase (door examined, no fuse yet)
			# is handled by the multi-marker case above; here the single diamond
			# sits on the panel both before the player examines it and once the
			# Small Fuse is in hand to fit it.
			var panel: Node3D = get_node_or_null("ShuttleDoorPanel") as Node3D
			if panel != null:
				pos = panel.global_position + Vector3(0.0, WAYPOINT_OFFSET_BY_ANCHOR.get("ShuttleDoorPanel", 0.7), 0.0)
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
		var next_hop: String = ProceduralShip.next_room_toward(room_id, target_room)
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


# Rebuild one diamond per un-looted Shuttle Dock crate. Cheap to rebuild from
# scratch (three crates) so we don't track per-crate marker identity.
func _refresh_crate_waypoints() -> void:
	_clear_crate_waypoints()
	for c in get_tree().get_nodes_in_group("shuttle_crate"):
		var crate: Node3D = c as Node3D
		if crate == null or crate.get("_looted") == true:
			continue
		var wp: Node3D = Node3D.new()
		wp.set_script(QuestWaypointScript)
		wp.name = "CrateWaypoint"
		world.add_child(wp)
		var pos: Vector3 = crate.global_position + Vector3(0.0, 1.3, 0.0)
		wp.global_position = pos
		if wp.has_method("set_target_position"):
			wp.call("set_target_position", pos)
		_crate_waypoints.append(wp)


func _clear_crate_waypoints() -> void:
	for wp in _crate_waypoints:
		if wp != null and is_instance_valid(wp):
			wp.queue_free()
	_crate_waypoints.clear()


# Crate loot fires interacted BEFORE _on_interact sets _looted, so defer the
# diamond refresh until the loot has applied (the emptied crate's diamond then
# drops; finding the Small Fuse clears them all and hands off to the panel).
func _on_crate_interacted(_by: Node) -> void:
	_refresh_quest_waypoint.call_deferred()


# Nearest Node3D in the given group to the player. Drives the
# DIAGNOSE_LIFE_SUPPORT (control_console) and SEAL_BREACH (shuttle_crate)
# waypoints so the diamond tracks whichever interchangeable target is closest.
func _find_nearest_in_group(group: String) -> Node3D:
	var nearest: Node3D = null
	var best_dist: float = INF
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
	for node in get_tree().get_nodes_in_group(group):
		if not (node is Node3D):
			continue
		var n3: Node3D = node
		var d: float = origin.distance_to(n3.global_position)
		if d < best_dist:
			best_dist = d
			nearest = n3
	return nearest


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


# ── Phase B interactable spawners ─────────────────────────────────────────────

# Elevator floor-selection panel on the -Z wall (facing into the room).
func _spawn_elevator_panel() -> void:
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_z: float = d_m * 0.5
	var panel: StaticBody3D = StaticBody3D.new()
	panel.set_script(ElevatorPanelScript)
	panel.name = "ElevatorPanel"
	# Position on the -Z wall at chest height. The script builds its own visual.
	panel.position = Vector3(0.0, 0.0, -half_z + 0.08)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.3)
	cs.shape = box
	cs.position = Vector3(0.0, 0.9, 0.0)
	panel.add_child(cs)
	add_child(panel)


# Floor-code terminal on the +X wall (right side when facing -Z into the room).
# Spawning is one-shot per floor: if the code is already known, we still spawn
# (so the player can see it was here) but it starts disabled.
func _spawn_floor_code_terminal(target_floor: int) -> void:
	if target_floor <= 1:
		return  # Floor 1 has no code gating.
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var terminal: StaticBody3D = StaticBody3D.new()
	terminal.set_script(FloorCodeTerminalScript)
	terminal.name = "FloorCodeTerminal_F%d" % target_floor
	terminal.set("target_floor", target_floor)
	terminal.position = Vector3(half_x - 0.08, 0.0, 0.0)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 1.8, 0.6)
	cs.shape = box
	cs.position = Vector3(0.0, 0.9, 0.0)
	terminal.add_child(cs)
	add_child(terminal)


# Dispatch for generated rooms: assignment console for unassigned storage,
# or assigned-function props for already-assigned rooms. Also places a
# floor-code terminal in rooms designated as the code-carrier for floor n+1.
func _spawn_generated_room_interactables() -> void:
	var type_id: String = String(_room_data.get("type", ""))
	var assigned_fn: String = ProceduralShip.assigned_function(room_id)
	var floor_n: int = int(_room_data.get("floor", 0))

	# Check if this room is the designated code-carrier for the next floor.
	# ProceduralShip.floor_code_terminal_room(n) returns the room where floor
	# n's code terminal should be placed. We iterate the next few floors to see
	# if this room qualifies for any of them.
	for check_floor in range(2, 10):
		var code_room: String = ProceduralShip.floor_code_terminal_room(check_floor)
		if code_room == room_id:
			_spawn_floor_code_terminal(check_floor)
			break  # One code terminal per room max.

	# Elevator landing rooms on generated floors get a panel.
	# The landing room is always "f{n}_r00" (entry corridor, first room placed).
	if room_id == ("f%d_r00" % floor_n) and floor_n >= 2:
		_spawn_elevator_panel()

	# Already assigned: dispatch on the function type.
	if assigned_fn != "":
		match assigned_fn:
			"hydroponics_bay":
				_spawn_co2_scrubber("gen_%s" % room_id, 0.0)
			# armory, machine_shop, recreation, medical_annex — set-dressing
			# deferred to Phase C; for now they're empty but labeled.
			_:
				pass
		return

	# Unassigned storage rooms get the assignment console.
	if type_id == "storage":
		_spawn_assignment_console()


# Assignment console on the -X wall (left side when facing into the room).
func _spawn_assignment_console() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var console: StaticBody3D = StaticBody3D.new()
	console.set_script(AssignmentConsoleScript)
	console.name = "AssignmentConsole"
	console.set("console_room_id", room_id)
	console.position = Vector3(-half_x + 0.08, 0.0, 0.0)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 1.8, 0.6)
	cs.shape = box
	cs.position = Vector3(0.0, 0.9, 0.0)
	console.add_child(cs)
	add_child(console)
