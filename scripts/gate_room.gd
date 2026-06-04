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
const GREER_SCRIPT: Script = preload("res://scripts/greer.gd")
const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")
const QuestWaypointScript: Script = preload("res://scripts/quest_waypoint.gd")
const CompanionScript: Script = preload("res://scripts/companion.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
# Preload bypasses class_name registration timing — same reason as room.gd.
const ShipAlertScript: Script = preload("res://scripts/ship_alert.gd")
const QUEST_WAYPOINT_ANCHOR_HEIGHT: float = 2.4
const QUEST_WAYPOINT_DOOR_HEIGHT: float = 1.8
# Z of the gate-control / FTL consoles (and the Phase E crew clustered around
# them). The Stargate sits at +Z (room_size.y*0.5 - 3.8 ≈ +12.2); putting the
# consoles well into the -Z half keeps the operators back by the staircases
# (STAIR_Z_CENTER ≈ -10) instead of crowding the event horizon.
const GATE_CONSOLE_Z: float = -4.0

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
# Phase F gate-walk-through choreography: when the player arrives at MINE_LIME
# (post-briefing) the away team is already lined up in front of the gate. The
# player's gate portal stays disabled until the team has walked through first.
var _gate_team: Array[Node3D] = []
var _gate_player_locked: bool = false
var _team_walkthrough_running: bool = false

func _ready() -> void:
	# Tell the save system this is a real gameplay scene.
	GameState.current_scene_path = "res://scenes/gate_room.tscn"

	# Build the room and gate furniture before anything else looks for nodes.
	_build_floor()
	_build_walls_and_ceiling()
	_build_ceiling_dome()
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

	# Returning through the gate from the lime planet: the away team came back
	# WITH the player — spawn them standing just behind the FromPlanet landing.
	if GameState.pending_planet_return:
		GameState.pending_planet_return = false
		_spawn_returned_away_team()

	# Discover + run arrival branch. If resuming from save, skip the cinematic.
	var first_visit: bool = not GameState.rooms_discovered.has("gate_room")
	GameState.discover_room("gate_room", "Gate Room")
	GameState.set_current_room("gate_room")

	# Piloted-Kino arrival: a Kino flew back through the planet's to_ship gate
	# (open Stargates are two-way). Hand the scene to a fresh recon drone instead
	# of the player rig and bail before the player-facing dialog/spawn branches.
	if GameState.kino_pilot_mode:
		_start_kino_arrival()
		return

	# Phase D → E bridge: Brody's "the gate dialed itself" call (end of the CO2
	# scrubber scene) routes the player back here. Arriving satisfies the
	# GO_TO_GATE objective and plays the "no MALP → I have an idea" beat that
	# sends Eli to fetch a Kino. Returning later with a Kino plays Rush's
	# approval and unlocks Kino Control.
	if GameState.quest_step == GameState.QUEST_GO_TO_GATE:
		GameState.report_to_gate()
		_play_gate_arrival_scene()
	elif GameState.quest_step == GameState.QUEST_SCOUT_KINO and not GameState.kino_plan_approved:
		_play_rush_kino_approval()
	elif GameState.quest_step == GameState.QUEST_MINE_LIME and not GameState.away_party_briefed:
		_play_post_scout_briefing()
	# After Scott's briefing (this run, or a prior session that already saw it),
	# the away team should be waiting at the active gate ready to step through.
	if (GameState.quest_step == GameState.QUEST_MINE_LIME
			and GameState.away_party_briefed
			and not GameState.returned_from_lime_planet):
		_assemble_away_team_at_gate()

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
	_refresh_gate_state()

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
	# "FromPlanet" — returning through the gate from the lime planet. Unlike the
	# prologue's FromGate (on the dais), the player steps off the platform and
	# ends up on the main floor SOUTH of it, facing into the room (-Z, toward
	# the exit). Created in code (no .tscn node) — must be a Marker3D so
	# SceneRouter._find_marker resolves it.
	var from_planet: Marker3D = Marker3D.new()
	from_planet.name = "FromPlanet"
	from_planet.position = Vector3(0.0, 0.05, room_size.y * 0.5 - 12.0)
	from_planet.rotation = Vector3.ZERO  # -Z forward = into the room / toward the exit
	add_child(from_planet)

func _apply_pending_save_spawn() -> void:
	if _player == null:
		return
	_player.global_position = GameState.pending_spawn_position
	_player.rotation.y = GameState.pending_spawn_yaw
	# Align the camera rig to the restored heading. Without this the View keeps the
	# yaw it snapped to in its own _ready (before this restore ran), and player.gd's
	# idle-facing (_facing_yaw = view.rotation.y) would swing the body back to that
	# default — losing the heading the player had when they left. Mirrors
	# room.gd::_place_player / planet.gd's restore.
	if _view != null and _view.has_method("snap_to_target"):
		_view.snap_to_target()

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


# Piloted-Kino arrival into the gate room (a Kino flew home through the planet's
# to_ship gate). Mirrors room.gd::_start_kino_arrival / planet.gd::_start_kino_recon:
# tear down the static player rig, hide the on-foot HUD, and spawn a fresh recon
# drone at the arrival marker so the DRONE (never the body) lands there. The Kino
# can then fly back through the (still-open) gate — two-way travel.
func _start_kino_arrival() -> void:
	var spawn_key: String = GameState.kino_pilot_arrival_spawn
	GameState.kino_pilot_arrival_spawn = ""
	# Default: hover near the gate at eye height. The planet's to_ship gate stores
	# target_spawn "FromPlanet", but that marker is only built in the player-arrival
	# branch (which this kino path returns before), so we fall through to this
	# default — fine, since it already sits just in front of the gate.
	var spawn_pos: Vector3 = Vector3(0.0, 1.4, room_size.y * 0.5 - 5.5)
	var spawn_yaw: float = 0.0
	if spawn_key != "":
		var marker: Node = get_node_or_null(spawn_key)
		if marker is Node3D:
			spawn_pos = (marker as Node3D).global_position + Vector3.UP * 1.4
			spawn_yaw = (marker as Node3D).rotation.y
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_view):
		_view.queue_free()
	var hud_layer: Node = get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	drone.set("launch_in_ship", false)
	drone.rotation.y = spawn_yaw
	add_child(drone)
	drone.global_position = spawn_pos
	if GameState.kino_autopilot and not SceneRouter.instant_mode:
		drone.call_deferred("start_ship_autopilot")

func _refresh_gate_state() -> void:
	if _arrival_running:
		return
	var gate_open: bool = GameState.is_gate_open()
	if _stargate != null and "active" in _stargate:
		_stargate.active = gate_open
	if _gate_portal != null:
		# Player gate stays disabled until the away team walks through first.
		_gate_portal.monitoring = gate_open and not _gate_player_locked

func _start_ambient() -> void:
	if _ambient_sfx != null and not _ambient_sfx.playing:
		_ambient_sfx.play()

# ----- Phase E gate beats ----------------------------------------------------

# Brody flags the no-MALP problem; Eli has an idea. Quest is already at
# FETCH_KINO (report_to_gate advanced it); this is the in-person dialog.
func _play_gate_arrival_scene() -> void:
	GameState.add_log("Dr Brody: We didn't bring a MALP — we've no idea what's on the other side.")
	_play_gate_dialog([
		{"speaker": "Dr Brody", "text": "We didn't bring a MALP. We have no idea what's on the other side of that gate.", "choices": [{"text": "...", "next": 1}]},
		{"speaker": "Eli", "text": "Wait — I have an idea!", "choices": [{"text": "(head to my quarters)", "next": "exit"}]},
	])


# Player returned with a Kino — Rush approves, which (with kino_orbs > 0) leaves
# the objective at SCOUT_KINO and unlocks Kino Control in the Kino Remote.
func _play_rush_kino_approval() -> void:
	GameState.kino_plan_approved = true
	GameState.add_log("Dr Rush: Oh, that's bloody brilliant, Eli.")
	_play_gate_dialog([
		{"speaker": "Dr Rush", "text": "Oh, that's bloody brilliant, Eli. I suspect that's exactly what these devices are for.", "choices": [{"text": "Let's send one through.", "next": "exit"}]},
	])


# Returned from the Kino scout (quest MINE_LIME). The crew's still here: Eli
# reports the good news, Rush orders an away party, Eli volunteers. One-shot.
func _play_post_scout_briefing() -> void:
	GameState.away_party_briefed = true
	GameState.add_log("Kino recon: breathable atmosphere and lime deposits near the gate.")
	_play_gate_dialog([
		{"speaker": "Eli", "text": "Hey — it's breathable! AND there's lime deposits right near the gate.", "choices": [{"text": "(show Rush the readings)", "next": 1}]},
		{"speaker": "Dr Rush", "text": "Well then, Sergeant — I think you should put together a little away party to go mine some lime.", "choices": [{"text": "...", "next": 2}]},
		{"speaker": "Lt Scott", "text": "You heard him. Greer, Park — gear up. We're taking a walk.", "choices": [{"text": "I'll come too!", "next": "exit"}]},
	])


# Phase F: post-briefing, the away team is already lined up in front of the
# active gate (Greer / Park / Scott, same roster as the planet side). The
# player's gate portal is locked off until they walk up behind the team — a
# trigger Area3D fires the walkthrough coroutine, which sends each companion
# through the event horizon one-by-one and then re-opens the gate for the
# player. Skipped in instant_mode so headless tests still walk the gate
# straight through.
func _assemble_away_team_at_gate() -> void:
	if not _gate_team.is_empty():
		return
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	# Stand them on the dais facing the gate. Gate is at z = room_size.y*0.5-3.8
	# (≈+12.2); the FromGate marker sits at y=1.05 z≈+10.5, so y=1.05 is the
	# right floor height. Spread the trio along X.
	var gate_z: float = room_size.y * 0.5 - 3.8
	var line_z: float = gate_z - 2.4         # ≈ +9.8 — a couple metres south of the event horizon
	var line_y: float = 1.05
	const SCOTT_GLB: String = "res://models/characters/scott.glb"
	const GREER_TINT: Color = Color(0.66, 0.50, 0.38)
	# Roster order matches the planet-side spawn (Greer left, Park centre,
	# Scott right) and the cutscene's group "away_team" muster.
	var roster: Array = [
		{"name": "Greer", "glb": SCOTT_GLB, "tint": GREER_TINT, "x": -1.6},
		{"name": "Park", "glb": "res://models/characters/park.glb", "tint": Color.WHITE, "x": 0.0},
		{"name": "Lt Scott", "glb": SCOTT_GLB, "tint": Color.WHITE, "x": 1.6},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var c: Node3D = CompanionScript.new()
		c.name = "GateTeam_" + String(entry["name"]).replace(" ", "")
		c.set("stationary", true)
		_world.add_child(c)
		c.position = Vector3(float(entry["x"]), line_y, line_z)
		c.rotation.y = 0.0    # model holder is internally flipped 180° → visible front faces +Z (the gate)
		c.call("setup", String(entry["name"]), String(entry["glb"]), i, entry["tint"])
		_gate_team.append(c)
	# Lock the player out of the gate until the team has walked through.
	_gate_player_locked = true
	_refresh_gate_state()
	# Every character who joined the away team has a standing gate-room NPC
	# (Scott at the briefing spot, Park at the gate console) — hide them so the
	# same person isn't on screen twice. Rush/Brody are NOT on the team, so they
	# stay. (Greer has no standing NPC.) Keyed by the known node names from
	# _build_npcs / _build_gate_phase_e_crew.
	for npc_node_name in ["LtScott", "GatePark"]:
		var dup: Node = _world.get_node_or_null(npc_node_name)
		if dup is Node3D:
			(dup as Node3D).visible = false
			if "enabled" in dup:
				dup.set("enabled", false)
	# Drop a trigger volume a few metres south of the team. Walking up behind
	# them fires the choreographed walkthrough exactly once.
	var trigger: Area3D = Area3D.new()
	trigger.name = "TeamWalkthroughTrigger"
	trigger.position = Vector3(0.0, line_y, line_z - 2.4)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(6.0, 2.4, 1.5)
	cs.shape = box
	trigger.add_child(cs)
	# The player capsule sits on layer 1; only react to it (not crew bodies).
	trigger.collision_mask = 1
	trigger.body_entered.connect(_on_team_walkthrough_trigger)
	_world.add_child(trigger)
	GameState.add_log("Lt Scott: We'll head through first — keep tight, Eli.")


# The away team that mined with the player on the planet steps back through the
# gate too. They land on the dais just south of the event horizon, then walk
# (staggered) down to their home posts on the main floor and idle there — fully
# talkable NPCs, not the static Companion props they used to be (issue #43).
# Lt Scott reuses his quest-aware repeat line; Greer uses the Greer hint script;
# Park gets a short authored wrap-up. Skipped in instant_mode (headless tests
# drive state directly), so the e1_playthrough path is unaffected.
func _spawn_returned_away_team() -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	if _world == null:
		return
	# Idempotent: the returned away team comes home exactly once. Bail if any
	# member is already present so a double pending_planet_return (or a re-entry)
	# can't put two of each crewmember on screen. Members are named ReturnTeam_*.
	for child in _world.get_children():
		if String(child.name).begins_with("ReturnTeam_"):
			return
	const SCOTT_GLB: String = "res://models/characters/scott.glb"
	const GREER_TINT: Color = Color(0.66, 0.50, 0.38)
	# Spawn line: on the dais top (y=1.05) a couple metres south of the event
	# horizon, mirroring the departure muster. Home line: down on the main floor
	# (y=0.05), gate-side of the FromPlanet landing so the player lands behind
	# them and watches them spread out. Slight per-member X spread at each end.
	var gate_z: float = room_size.y * 0.5 - 3.8
	var spawn_z: float = gate_z - 2.4               # ≈ +9.8 on the dais
	var home_z: float = room_size.y * 0.5 - 10.5    # ≈ +5.5 on the main floor
	var roster: Array = [
		{"name": "Greer", "glb": SCOTT_GLB, "tint": GREER_TINT, "x": -2.4, "kind": "greer"},
		{"name": "Park", "glb": "res://models/characters/park.glb", "tint": Color.WHITE, "x": 0.0, "kind": "park"},
		{"name": "Lt Scott", "glb": SCOTT_GLB, "tint": Color.WHITE, "x": 2.4, "kind": "scott"},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var npc: StaticBody3D = _build_returned_crew_npc(
			String(entry["name"]), String(entry["kind"]),
			String(entry["glb"]), entry["tint"])
		# Stand on the dais facing the room (-Z forward), then stroll to the home
		# post. rotation.y=0 → -Z forward (toward the player landing south).
		npc.position = Vector3(float(entry["x"]), 1.05, spawn_z)
		npc.rotation.y = 0.0
		_world.add_child(npc)
		# Fan out: each member targets its home post with a small stagger so they
		# don't march in lockstep. ~2.5 m/s reads as an unhurried "we made it".
		npc.call("walk_to", Vector3(float(entry["x"]), 0.05, home_z), 2.5, float(i) * 0.4)
	# Scott is part of the returned team — hide the briefing-spot LtScott NPC so
	# there aren't two Scotts on screen (same fix as _assemble_away_team_at_gate).
	var briefing_scott: Node = _world.get_node_or_null("LtScott")
	if briefing_scott is Node3D:
		(briefing_scott as Node3D).visible = false
		if "enabled" in briefing_scott:
			briefing_scott.set("enabled", false)
	GameState.add_log("The away team steps back through the gate onto Destiny.")


# Build one returned-crew NPC body: StaticBody3D + the right dialogue script,
# CapsuleShape3D, GLB model holder (scaled 2.6×, internally flipped 180° to face
# the body's -Z), colormap/tint, idle anim, and a billboard nametag. Mirrors the
# _build_npcs Lt-Scott pattern so the returned trio share that one code path.
# `kind` picks the dialogue wiring: "scott" (quest-aware repeat line), "greer"
# (Greer hint script), or "park" (short authored wrap-up).
func _build_returned_crew_npc(display_name: String, kind: String, glb_path: String,
		tint: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ReturnTeam_" + display_name.replace(" ", "")
	match kind:
		"greer":
			body.set_script(GREER_SCRIPT)
		_:
			body.set_script(NPC_SCRIPT)
	body.set("character_name", display_name)
	body.set("prompt", "Talk to %s" % display_name)
	if kind == "scott":
		# Reuse Scott's quest-aware repeat line so the returned Scott reflects the
		# post-mission step ("Get that lime to the scrubber…").
		body.set("dialogue_tree", _returned_scott_dialog())
		body.set("repeat_dialogue_tree", _returned_scott_dialog())
	elif kind == "park":
		body.set("dialogue_tree", _returned_park_dialog())
		body.set("repeat_dialogue_tree", _returned_park_dialog())
	# Greer rebuilds its tree from quest_step on every interact (greer.gd), so it
	# needs no authored tree here.

	# Collision capsule — blocks the player and acts as the interactable hitbox.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(cs)

	# Visual body — Kenney mini-char GLB, flipped 180° (export +Z forward).
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	model_holder.rotation.y = PI
	var glb: PackedScene = load(glb_path)
	if glb != null:
		var inst: Node = glb.instantiate()
		model_holder.add_child(inst)
		var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
		Npc.apply_kenney_colormap(inst, colormap)
		if tint != Color.WHITE:
			_tint_kenney_model(inst, tint)
		Npc.play_idle_animation(inst)
	body.add_child(model_holder)

	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = display_name
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.05, 0.0)
	body.add_child(tag)
	return body


# Re-tint the just-applied colormap material per-instance so Greer can share
# Scott's body GLB and still read as a different character (same trick as
# Companion._apply_tint — duplicate the shared material before mutating albedo).
func _tint_kenney_model(root: Node, tint: Color) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = tint
				mi.material_override = mat
		for c in n.get_children():
			stack.append(c)


# Returned Lt Scott — quest-aware wrap-up. The repeat line method already maps
# the post-mission steps (REPAIR_SCRUBBER → "Get that lime to the scrubber…").
func _returned_scott_dialog() -> Array:
	return [
		{
			"speaker": "Lt Scott",
			"text": _scott_repeat_line(),
			"choices": [{"text": "On it.", "next": "exit"}],
		},
	]


# Returned Dr Park — short authored wrap-up beat (she had no dialogue before).
func _returned_park_dialog() -> Array:
	return [
		{
			"speaker": "Dr Park",
			"text": "We actually pulled it off. Get that lime to the scrubber and we might just keep breathing.",
			"choices": [
				{"text": "How are you holding up?", "next": 1},
				{"text": "On my way.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Park",
			"text": "Rattled, but in one piece. First alien world I've ever set foot on — I'll process that later. Go on, the scrubber won't wait.",
			"choices": [{"text": "Hang in there.", "next": "exit"}],
		},
	]


func _on_team_walkthrough_trigger(body: Node) -> void:
	if _team_walkthrough_running:
		return
	if not (body is Node3D) or not body.is_in_group("player"):
		return
	_team_walkthrough_running = true
	_run_team_walkthrough()


func _run_team_walkthrough() -> void:
	var gate_z: float = room_size.y * 0.5 - 3.8
	# Walk each companion forward to the event horizon, staggered so they file
	# through one at a time. rush_to() flips the companion into its cinematic
	# sprint mode and ARRIVE handles the visible=false.
	for i in _gate_team.size():
		var c: Node3D = _gate_team[i]
		if not is_instance_valid(c):
			continue
		var target: Vector3 = Vector3(c.global_position.x, c.global_position.y, gate_z + 0.6)
		c.call("rush_to", target)
		await get_tree().create_timer(0.45).timeout
		# Wait until this one's through, then flash + hide before launching the next.
		while is_instance_valid(c) and c.get("_rushing") == true:
			await get_tree().process_frame
		if is_instance_valid(c):
			c.visible = false
	# Whole team through — open the gate for the player and free the trigger.
	_gate_player_locked = false
	_refresh_gate_state()
	var trigger: Node = _world.get_node_or_null("TeamWalkthroughTrigger")
	if trigger != null:
		trigger.queue_free()
	GameState.add_log("Away team's through. Your turn.")


# Play an in-person WoW dialog in the gate room. Skipped in instant_mode (tests
# drive state directly); short beat so the HUD settles before it opens.
func _play_gate_dialog(tree: Array) -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	GameState.dialog_started.emit(player, tree)


# ----- quest waypoint --------------------------------------------------------

func _on_quest_objective_changed(_text: String) -> void:
	_refresh_quest_waypoint()


# Same pattern as room.gd::_refresh_quest_waypoint, adapted for the hand-
# authored gate room: anchors are direct children of self (LtScott, the two
# console holders), the cross-room target uses the ExitDoor instance defined
# in gate_room.tscn (target_room_id = "stargate_corridor_east_connector").
func _refresh_quest_waypoint() -> void:
	# Scout beat: the objective is "open the Kino Remote", which has no spatial
	# target — the HUD shows a [Tab] guide instead. Suppress the diamond + the
	# HUD edge-arrow (which follows the quest_waypoint group) entirely.
	if GameState.quest_step == GameState.QUEST_SCOUT_KINO:
		_destroy_quest_waypoint()
		return

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
	var mat: StandardMaterial3D = RoomBuilder.make_floor_mat(Color(0.10, 0.11, 0.14, 1.0), room_size.x, room_size.y)
	# Wet/reflective dark-metal deck (reference): dark, metallic, low roughness so
	# SSR (enabled in the env) bounces the gate glow + downlight shafts off it.
	mat.metallic = 0.85
	mat.roughness = 0.22
	mat.metallic_specular = 0.6
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
	glow_mat.albedo_color = Color(0.30, 0.62, 1.0, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.34, 0.66, 1.0, 1.0)
	glow_mat.emission_energy_multiplier = 5.0
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

	# Vertical cyan light strips marching down the side walls — the reference's
	# signature "tall glowing window slots" that give the chamber height + depth.
	var vstrip_mat: StandardMaterial3D = StandardMaterial3D.new()
	vstrip_mat.albedo_color = Color(0.26, 0.55, 1.0, 1.0)
	vstrip_mat.emission_enabled = true
	vstrip_mat.emission = Color(0.32, 0.62, 1.0, 1.0)
	vstrip_mat.emission_energy_multiplier = 3.2
	vstrip_mat.metallic = 0.0
	vstrip_mat.roughness = 0.4
	var vstrip_h: float = ceiling_height * 0.5
	var vstrip_y: float = ceiling_height * 0.52
	var vcount: int = 6
	for i in vcount:
		var tz: float = -half_z + 3.0 + (room_size.y - 6.0) * float(i) / float(vcount - 1)
		# Pair the strips with darker recessed pilasters so they read as inset
		# window slots, not floating bars.
		for sx in [-1.0, 1.0]:
			_add_decorative_box(Vector3(sx * (half_x - 0.12), vstrip_y, tz),
				Vector3(0.12, vstrip_h, 0.34), vstrip_mat)


# Stepped concentric-ring ceiling dome over the room centre — the reference's
# signature overhead. Ancient-metal rings recessing upward, with thin cyan accent
# rings between them, so the central downlight shaft reads as coming through a dome.
func _build_ceiling_dome() -> void:
	var panel: Material = load("res://shaders/ancient_metal_panel.tres")
	var accent: StandardMaterial3D = StandardMaterial3D.new()
	accent.albedo_color = Color(0.28, 0.56, 1.0, 1.0)
	accent.emission_enabled = true
	accent.emission = Color(0.32, 0.62, 1.0, 1.0)
	accent.emission_energy_multiplier = 2.4
	var rings: int = 4
	for i in rings:
		var rad: float = 7.6 - float(i) * 1.7
		var y: float = ceiling_height - 0.1 - float(i) * 0.4
		var ring: MeshInstance3D = MeshInstance3D.new()
		var tm: TorusMesh = TorusMesh.new()
		tm.inner_radius = rad - 0.55
		tm.outer_radius = rad
		tm.ring_segments = 64
		tm.rings = 6
		ring.mesh = tm
		if panel != null:
			ring.material_override = panel
		ring.position = Vector3(0.0, y, 0.0)
		_world.add_child(ring)
		var acc: MeshInstance3D = MeshInstance3D.new()
		var atm: TorusMesh = TorusMesh.new()
		atm.inner_radius = rad - 0.68
		atm.outer_radius = rad - 0.58
		atm.ring_segments = 64
		atm.rings = 4
		acc.mesh = atm
		acc.material_override = accent
		acc.position = Vector3(0.0, y - 0.05, 0.0)
		_world.add_child(acc)

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
			"text": _scott_repeat_line(),
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
	# beside him. Only present BEFORE the air crisis — once it starts, James has
	# moved Young to the Infirmary (off the south corridor) to recover, so the
	# gate-room floor is clear.
	if not GameState.air_crisis_started:
		_build_medic_tableau()

	# Phase E: Brody (at the gate console) plus Rush + Park, who "followed" Eli
	# in to look at the dialed gate. Present from arrival through the lime run.
	_build_gate_phase_e_crew()


# Lt Scott's repeat line is quest-aware: a nudge toward Rush early on, but once
# the Kino scout confirms the lime world he's supportive about the away mission
# (he leads it). Default preserves the early "find Rush" nudge.
func _scott_repeat_line() -> String:
	match GameState.quest_step:
		GameState.QUEST_MINE_LIME:
			return "Breathable air and lime on the far side — good work, Eli. I guess we'd better go mine some."
		GameState.QUEST_RETURN_DESTINY:
			return "Grab what lime you can and get back to the gate."
		GameState.QUEST_REPAIR_SCRUBBER:
			return "Get that lime to the scrubber — we're counting on you."
		_:
			return "Hurry up Eli, find Rush!"


# Spawn Brody + Rush + Park clustered by the gate-control console during the
# Phase E gate window (arrival → Kino scout). Unique node names so NPCState
# doesn't cross-restore them to the control-room / infirmary versions.
func _build_gate_phase_e_crew() -> void:
	# Present from the gate report through the lime run: Brody/Rush/Park stay to
	# brief the away party once the Kino scout confirms the planet (MINE_LIME).
	var q: String = GameState.quest_step
	var in_window: bool = (q == GameState.QUEST_GO_TO_GATE
		or q == GameState.QUEST_FETCH_KINO
		or q == GameState.QUEST_SCOUT_KINO
		or q == GameState.QUEST_DIAL_LIME_PLANET
		or q == GameState.QUEST_MINE_LIME)
	if not in_window:
		return
	var z_console: float = GATE_CONSOLE_Z
	# Brody at the gate-control console (x -3.5), facing the player's arrival.
	_build_tableau_npc(
		"GateBrody", "Dr Brody",
		Vector3(-5.2, 0.0, z_console - 1.0), 0.0,
		"res://models/characters/scott.glb",
		[{"speaker": "Dr Brody", "text": "Still no telemetry from the other side. We're flying blind here.", "choices": [{"text": "Working on it.", "next": "exit"}]}],
		"", "stand", true,
	)
	_build_tableau_npc(
		"GateRush", "Dr Rush",
		Vector3(-1.4, 0.0, z_console - 1.6), 0.0,
		"res://models/characters/rush.glb",
		[{"speaker": "Dr Rush", "text": "Whenever you're ready, Mr Wallace. The gate won't stay open forever.", "choices": [{"text": "Right.", "next": "exit"}]}],
		"", "stand", true,
	)
	_build_tableau_npc(
		"GatePark", "Dr Park",
		Vector3(0.8, 0.0, z_console - 1.6), 0.0,
		"res://models/characters/park.glb",
		[{"speaker": "Dr Park", "text": "A camera drone through a wormhole. Honestly? Worth a shot.", "choices": [{"text": "Let's find out.", "next": "exit"}]}],
		"", "stand", true,
	)


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
		"res://models/characters/james.glb",
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
	var z_console: float = GATE_CONSOLE_Z
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

	# COOL + DARK lighting to match the cinematic reference: the event horizon is
	# the key light; everything else is low, blue, and dramatic. Ceiling downlight
	# SPOTS cast volumetric shafts through the fog (volumetric_fog in the env).

	# Faint cool wall-wash uplights — just enough to read panel detail at the room
	# edges without flattening the dark.
	var uplight_positions: Array = [
		Vector3(-half_x + 1.5, 0.4,  half_z - 2.0),
		Vector3( half_x - 1.5, 0.4,  half_z - 2.0),
		Vector3(-half_x + 1.5, 0.4, -half_z + 2.0),
		Vector3( half_x - 1.5, 0.4, -half_z + 2.0),
		Vector3(-half_x + 1.5, 0.4, 0.0),
		Vector3( half_x - 1.5, 0.4, 0.0),
	]
	for p in uplight_positions:
		var l: OmniLight3D = OmniLight3D.new()
		l.light_color = Color(0.34, 0.52, 0.85, 1.0)
		l.light_energy = 0.7
		l.omni_range = 7.0
		l.omni_attenuation = 2.0
		l.position = p
		_world.add_child(l)

	# Ceiling downlights — cool-white SPOTS straight down the central aisle from
	# door to gate. With volumetric fog on, these are the shafts in the reference.
	for bz in [-half_z + 4.0, -half_z + 9.0, 0.0, half_z - 9.0]:
		var beam: SpotLight3D = SpotLight3D.new()
		beam.light_color = Color(0.72, 0.82, 1.0, 1.0)
		beam.light_energy = 10.0
		beam.spot_range = ceiling_height + 2.0
		beam.spot_angle = 24.0
		beam.spot_attenuation = 1.2
		beam.shadow_enabled = true
		beam.position = Vector3(0.0, ceiling_height - 0.4, bz)
		# Point straight down. look_at(directly-below) is degenerate (forward ∥ up),
		# so set the rotation directly: -90° about X aims a SpotLight's -Z down -Y.
		beam.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		_world.add_child(beam)

	# Gate rim fill: subtle COOL side spots so the ring metal catches a cold
	# highlight — the horizon does most of the work. look_at() needs the node in
	# the tree first, else it silently errors and points along its default axis.
	var gate_center: Vector3 = Vector3(0.0, 4.0, half_z - 3.8)
	for sx in [-1.0, 1.0]:
		var side: SpotLight3D = SpotLight3D.new()
		side.light_color = Color(0.62, 0.78, 1.0, 1.0)
		side.light_energy = 2.2
		side.spot_range = 12.0
		side.spot_angle = 30.0
		side.position = Vector3(sx * 5.5, 1.4, gate_center.z - 1.5)
		_world.add_child(side)
		side.look_at(gate_center, Vector3.UP)

	# Very soft cool top key — establishes form without lifting the blacks.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(0.66, 0.76, 1.0, 1.0)
	key.light_energy = 0.28
	key.shadow_enabled = true
	key.shadow_opacity = 0.7
	key.rotation = Vector3(deg_to_rad(-68.0), deg_to_rad(12.0), 0.0)
	_world.add_child(key)

	# Door-archway pool — cool, dim, just enough to read the exit.
	var door_spot: SpotLight3D = SpotLight3D.new()
	door_spot.name = "DoorArchSpot"
	door_spot.light_color = Color(0.6, 0.74, 1.0, 1.0)
	door_spot.light_energy = 3.0
	door_spot.spot_range = 8.0
	door_spot.spot_angle = 34.0
	door_spot.position = Vector3(0.0, ceiling_height - 0.6, -half_z + 1.2)
	_world.add_child(door_spot)
	door_spot.look_at(Vector3(0.0, 0.0, -half_z + 0.2), Vector3.UP)
