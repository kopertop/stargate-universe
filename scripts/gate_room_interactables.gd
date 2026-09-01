extends Node

# Interactables module for the gate room. Extracted from gate_room.gd
# to decompose the god object. Added as a child Node "Interactables" by the
# main script and called via the host reference.
#
# Owns: chevron glows + lock SFX, dial choreography, gate portal Area3D,
# spawn markers, upper-deck stairs door, pending-save spawn restore,
# ship-gate portal, Kino arrival, gate-state refresh, ambient SFX,
# console wake/offline state management, quest waypoint.

const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")
const QuestWaypointScript: Script = preload("res://scripts/quest_waypoint.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")

const QUEST_WAYPOINT_ANCHOR_HEIGHT: float = 2.4
const QUEST_WAYPOINT_DOOR_HEIGHT: float = 1.8

const DIAL_TIME: float = 3.2          # seconds the ring spins before lock + kawoosh
const CHEVRON_COUNT: int = 9
const CHEVRON_ENERGY: float = 4.0

# Stair landing geometry — referenced by build_upper_deck_stairs_door.
const STAIR_Z_CENTER: float = -10.0

# Host reference (the gate_room.gd Node3D). Set by the host before build calls.
var host: Node3D = null

# State vars moved from gate_room.gd (public, no underscore prefix).
var from_gate_marker: Marker3D
var from_corridor_marker: Marker3D
var from_east_connector_marker: Marker3D
var gate_portal: Area3D
var quest_waypoint: Node3D = null
var gate_forced_open: bool = false
var dialing: bool = false
var dial_elapsed: float = 0.0
var chevrons_lit_prev: int = 0
var chevron_lock_players: Array[AudioStreamPlayer] = []
var chevron_lock_idx: int = 0
var dial_with_sfx: bool = true
var chevron_glows: Array[MeshInstance3D] = []
var chevron_rig: Node3D = null


# ── Setup ───────────────────────────────────────────────────────────────────

func setup(room: Node3D) -> void:
	host = room


# ── Chevron glows + lock SFX ─────────────────────────────────────────────────

# Build the 9 chevron-glow prisms on an unscaled pivot ("ChevronRig") at the gate
# face centre. The rig lives as a child of _world (NOT _gate_ring) so the ring's
# (0.33/8.5/8.5) scale does NOT distort the prism meshes — they stay round/correct.
# During the dial spin, the orchestrator's _process copies _gate_ring.rotation.z to
# chevron_rig.rotation.z each frame, keeping the amber glows locked on the molded
# chevron wedges.
func build_chevron_glows() -> void:
	var cy: float = gate_center_y()
	var outer_r: float = host.GATE_RING_OUTER_NATIVE * host.GATE_DIAM_SCALE
	# ~3.69 m radius puts the centre of each glow on the moulded chevron bracket.
	# (outer_native 0.505 * diam_scale 8.5 * 0.86 ≈ 3.69 m)
	var r: float = outer_r * 0.86
	# Unscaled pivot at the gate face centre. Children inherit NO scale from the ring.
	chevron_rig = Node3D.new()
	chevron_rig.name = "ChevronRig"
	chevron_rig.position = Vector3(0.0, cy, host.GATE_Z)
	host._world.add_child(chevron_rig)
	for i in CHEVRON_COUNT:
		var ang: float = float(i) * TAU / float(CHEVRON_COUNT)   # i=0 at top → +Y
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.26, 0.5, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.7, 1.0, 1.0)   # tech blue (was amber)
		mat.emission_energy_multiplier = 0.0   # dark until locked
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "ChevronGlow%d" % i
		var prism: PrismMesh = PrismMesh.new()
		prism.size = Vector3(0.55, 0.5, 0.14)
		mi.mesh = prism
		mi.material_override = mat
		# Position is relative to the rig centre (which is already at (0, cy, GATE_Z)).
		# ang=0 → top chevron at (0, r, -0.14). -0.14 on Z = 14 cm in front of ring face.
		mi.position = Vector3(r * sin(ang), r * cos(ang), -0.14)
		mi.rotation.z = PI - ang   # point the prism apex inward toward the gate centre
		chevron_rig.add_child(mi)
		chevron_glows.append(mi)


# Fire one chevron-lock one-shot (round-robin pool, built lazily) — called once per
# chevron as it lights during the dial.
func play_chevron_lock() -> void:
	if chevron_lock_players.is_empty():
		var stream: AudioStream = load("res://sounds/stargate_chevron_incom.mp3") as AudioStream
		if stream == null:
			return
		for _i in 3:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.stream = stream
			host.add_child(pl)
			chevron_lock_players.append(pl)
	var p: AudioStreamPlayer = chevron_lock_players[chevron_lock_idx % chevron_lock_players.size()]
	chevron_lock_idx += 1
	p.play()


# Light the first `count` chevrons (0..CHEVRON_COUNT); the rest stay dark.
func light_chevrons(count: int) -> void:
	for i in chevron_glows.size():
		var mi: MeshInstance3D = chevron_glows[i]
		if mi == null or not is_instance_valid(mi):
			continue
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = CHEVRON_ENERGY if i < count else 0.0


# ── Dial choreography ────────────────────────────────────────────────────────

# Reusable dial choreography, in the exact beats the design calls for:
#   1) the ring SPINS up (stargate-style),
#   2) the CHEVRONS light up one-by-one as it locks them (driven in _process),
#   3) the centre portal FLUSHES open (kawoosh) and the ring STOPS spinning,
#   4) the portal STABILISES (shimmering) and is then walkable.
# `with_sfx` plays the dial rumble + whoosh (skipped for silent/headless captures).
# Awaitable so cinematics can sequence around it.
func dial_and_open(with_sfx: bool = true) -> void:
	if dialing:
		return
	dialing = true
	dial_elapsed = 0.0
	chevrons_lit_prev = 0
	light_chevrons(0)
	# Reset the ring + chevron rig to a known, in-sync pose so a repeat dial can't
	# accumulate drift (ring base orientation = yaw +90°; the rig is unrotated).
	if host._gate_ring != null and is_instance_valid(host._gate_ring):
		host._gate_ring.rotation = Vector3(0.0, PI * 0.5, 0.0)
	if chevron_rig != null and is_instance_valid(chevron_rig):
		chevron_rig.rotation = Vector3.ZERO
	# (1)+(2) The chevron-lock sound now fires per-chevron in _process as each locks
	# (gated on dial_with_sfx); no single dial-start rumble.
	dial_with_sfx = with_sfx
	await get_tree().create_timer(DIAL_TIME).timeout
	# Ring STOPS spinning; all chevrons locked.
	dialing = false
	# If the cold open was SKIPPED mid-dial, bail before forcing the gate open — else
	# this completes after _finalize_cold_open() and re-opens the portal it just shut.
	if host.cinematic.co_skip:
		return
	light_chevrons(CHEVRON_COUNT)
	# Keep the gate lit after lock so refresh_gate_state doesn't snap it back off.
	gate_forced_open = true
	# (3) The centre portal FLUSHES open — kawoosh burst on the gate itself.
	if host._stargate != null and host._stargate.has_method("kawoosh"):
		host._stargate.call("kawoosh")
	elif host._stargate != null and "active" in host._stargate:
		host._stargate.active = true
	# WHOOSH on open (the kawoosh), then settle into the steady energy hum.
	if with_sfx:
		if host._gate_loop_sfx != null and host._gate_loop_sfx.playing:
			host._gate_loop_sfx.stop()
		if host._gate_kawoosh_sfx != null and host._gate_kawoosh_sfx.stream != null:
			host._gate_kawoosh_sfx.play()
		if host._gate_hum_sfx != null and host._gate_hum_sfx.stream != null:
			host._gate_hum_sfx.play()
	# (4) Let the puddle stabilise (the shader's shimmer settles) before callers
	# treat it as walkable.
	await get_tree().create_timer(0.6).timeout


# ── Gate geometry helper ─────────────────────────────────────────────────────

# Floor-pinned gate centre: one inner-radius up, minus a margin so the hole's
# bottom dips just below the deck and the opening is player-width at floor level
# (walk straight through — no step, no jump). The lower ring arc tucks under.
func gate_center_y() -> float:
	return host.GATE_RING_INNER_NATIVE * host.GATE_DIAM_SCALE - host.GATE_FLOOR_MARGIN


# ── Spawn markers ─────────────────────────────────────────────────────────────

func create_spawn_markers() -> void:
	# "FromGate" — player just stepped through the (floor-pinned) gate, on the deck
	# just in front of the ring, facing -Z into the room. No dais now → floor height.
	from_gate_marker = host.get_node_or_null("FromGate")
	from_gate_marker.position = Vector3(0.0, 0.05, host.room_size.y * 0.5 - 5.5)
	from_gate_marker.rotation = Vector3.ZERO  # -Z forward = facing the room
	# "FromCorridor" — re-enters from the exit archway, facing +Z toward the gate.
	# y=0.05 keeps the capsule bottom (player.y + 0.05) just above the main floor.
	from_corridor_marker = host.get_node_or_null("FromCorridor")
	from_corridor_marker.position = Vector3(0.0, 0.05, -host.room_size.y * 0.5 + 2.5)
	from_corridor_marker.rotation = Vector3(0.0, PI, 0.0)  # face +Z (toward gate)
	# Factory-routed reverse edge from `stargate_corridor_east_connector` —
	# room.gd::_stamp_door auto-derives the spawn key as
	# "From" + _to_camel(room_id). Same landing as FromCorridor.
	from_east_connector_marker = host.get_node_or_null("FromStargateCorridorEastConnector")
	from_east_connector_marker.position = from_corridor_marker.position
	from_east_connector_marker.rotation = from_corridor_marker.rotation
	# "FromPlanet" — returning through the gate from the lime planet. Unlike the
	# prologue's FromGate (on the dais), the player steps off the platform and
	# ends up on the main floor SOUTH of it, facing into the room (-Z, toward
	# the exit). Created in code (no .tscn node) — must be a Marker3D so
	# SceneRouter._find_marker resolves it.
	var from_planet: Marker3D = Marker3D.new()
	from_planet.name = "FromPlanet"
	from_planet.position = Vector3(0.0, 0.05, host.room_size.y * 0.5 - 12.0)
	from_planet.rotation = Vector3.ZERO  # -Z forward = into the room / toward the exit
	host.add_child(from_planet)


# ── Upper deck stairs door ──────────────────────────────────────────────────

# D1: Stamp a transition door at the right stair-top landing (x=+12, y=5, z=-10)
# pointing to the Floor-2 Observation Deck entry room. Generates Floor 2 on demand
# so the target room exists before any transition fires. Also creates the
# "FromObservationDeck" arrival Marker3D so the return trip (obs-deck → gate room)
# lands the player at this stair-top landing facing into the room (+Z toward gate).
func build_upper_deck_stairs_door() -> void:
	# Ensure Floor 2 is generated so floor2_obs_entry_id() returns a valid id.
	ProceduralShip.ensure_floor_generated(2)
	var obs_id: String = ProceduralShip.floor2_obs_entry_id()
	if obs_id == "":
		push_warning("gate_room: floor 2 not generated — upper deck door skipped")
		return

	# Stair-top position: right stair (side_sign=+1) top lands at
	#   x = +(half_x - mezzanine_depth) = +12, y = mezzanine_height = 5, z = STAIR_Z_CENTER = -10
	var half_x: float = host.room_size.x * 0.5
	var stair_top: Vector3 = Vector3(half_x - host.mezzanine_depth, host.mezzanine_height, STAIR_Z_CENTER)

	# The door faces -X from the right mezzanine wall (face_yaw = +PI*0.5 = face left/inward).
	# Place it flush with the inner edge of the right mezzanine strip.
	var door: Node = host.DOOR_SCENE.instantiate()
	door.name = "UpperDeckDoor"
	door.position = stair_top + Vector3(0.0, 0.0, 0.0)
	door.rotation.y = PI * 0.5   # Face -X (door is on the right wall, opens inward)
	door.set("target_room_id", obs_id)
	door.set("source_room_id", "gate_room")
	door.set("target_spawn", ProceduralShip.STAIRS_OBS_SPAWN)
	door.set("plaque_label", "Upper Deck — Observation")
	door.set("open_prompt", "Step up to Upper Deck")
	door.set("transition_prompt", "Step up to Upper Deck")
	door.add_to_group("interactable")
	host._world.add_child(door)

	# Return-trip arrival marker: player landing back from the Observation Deck
	# appears 1.2 m inward (toward -X) from the door, facing +X into the room.
	var marker: Marker3D = Marker3D.new()
	marker.name = ProceduralShip.STAIRS_GATE_SPAWN   # "FromObservationDeck"
	# 1.2 m inward from the stair-top door, still on the mezzanine level (y=5).
	marker.position = stair_top + Vector3(-1.2, 0.0, 0.0)
	marker.rotation.y = -PI * 0.5  # face +X into room (away from wall)
	host.add_child(marker)


# ── Pending save spawn ───────────────────────────────────────────────────────

func apply_pending_save_spawn() -> void:
	if host._player == null:
		return
	host._player.global_position = GameState.pending_spawn_position
	host._player.rotation.y = GameState.pending_spawn_yaw
	# Align the camera rig to the restored heading. Without this the View keeps the
	# yaw it snapped to in its own _ready (before this restore ran), and player.gd's
	# idle-facing (_facing_yaw = view.rotation.y) would swing the body back to that
	# default — losing the heading the player had when they left. Mirrors
	# room.gd::_place_player / planet.gd's restore.
	if host._view != null and host._view.has_method("snap_to_target"):
		host._view.snap_to_target()


# ── Ship gate portal ──────────────────────────────────────────────────────────

func build_ship_gate_portal() -> void:
	gate_portal = Area3D.new()
	gate_portal.set_script(PLANET_GATE_SCRIPT)
	gate_portal.name = "ShipGatePortal"
	# Center the interaction volume inside the floor-pinned ring's opening so the
	# player steps "into" the puddle naturally while walking through at floor level.
	gate_portal.position = Vector3(0.0, gate_center_y(), host.GATE_Z)
	gate_portal.set("mode", "to_planet")
	gate_portal.set("target_scene", "res://scenes/planet.tscn")
	gate_portal.set("target_spawn", "FromShipGate")
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.4, 3.2, 1.2)
	cs.shape = shape
	gate_portal.add_child(cs)
	host._world.add_child(gate_portal)
	gate_portal.monitoring = false


# ── Kino arrival ──────────────────────────────────────────────────────────────

# Piloted-Kino arrival into the gate room (a Kino flew home through the planet's
# to_ship gate). Mirrors room.gd::_start_kino_arrival / planet.gd::_start_kino_recon:
# tear down the static player rig, hide the on-foot HUD, and spawn a fresh recon
# drone at the arrival marker so the DRONE (never the body) lands there. The Kino
# can then fly back through the (still-open) gate — two-way travel.
func start_kino_arrival() -> void:
	var spawn_key: String = GameState.kino_pilot_arrival_spawn
	GameState.kino_pilot_arrival_spawn = ""
	# Default: hover near the gate at eye height. The planet's to_ship gate stores
	# target_spawn "FromPlanet", but that marker is only built in the player-arrival
	# branch (which this kino path returns before), so we fall through to this
	# default — fine, since it already sits just in front of the gate.
	var spawn_pos: Vector3 = Vector3(0.0, 1.4, host.room_size.y * 0.5 - 5.5)
	var spawn_yaw: float = 0.0
	if spawn_key != "":
		var marker: Node = host.get_node_or_null(spawn_key)
		if marker is Node3D:
			spawn_pos = (marker as Node3D).global_position + Vector3.UP * 1.4
			spawn_yaw = (marker as Node3D).rotation.y
	if is_instance_valid(host._player):
		host._player.queue_free()
	if is_instance_valid(host._view):
		host._view.queue_free()
	var hud_layer: Node = host.get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	drone.set("launch_in_ship", false)
	drone.rotation.y = spawn_yaw
	host.add_child(drone)
	drone.global_position = spawn_pos
	if GameState.kino_autopilot and not SceneRouter.instant_mode:
		drone.call_deferred("start_ship_autopilot")


# ── Gate state refresh ───────────────────────────────────────────────────────

func refresh_gate_state() -> void:
	if host.cinematic.arrival_running:
		return
	# A cinematic/dial may force the gate open (e.g. the prologue wormhole the crew
	# tumble through) independent of the story's is_gate_open() flags.
	var gate_open: bool = GameState.is_gate_open() or gate_forced_open
	if host._stargate != null and "active" in host._stargate:
		host._stargate.active = gate_open
	if gate_portal != null:
		# Player gate stays disabled until the away team walks through first.
		gate_portal.monitoring = gate_open and not host.npcs.gate_player_locked


# ── Ambient SFX ──────────────────────────────────────────────────────────────

func start_ambient() -> void:
	# The procedural AmbientHum stays as a quiet sub-bass rumble; the MusicDirector
	# now owns the actual bed/mood on top of it (ship_calm normally, crisis during the
	# air-crisis quest steps — refresh() derives which from live world state).
	if host._ambient_sfx != null and not host._ambient_sfx.playing:
		host._ambient_sfx.play()
	Audio.refresh()


# ── Console state management ─────────────────────────────────────────────────

# Boot both gate consoles from OFFLINE to their Ancient-glyph readout (called when
# control returns to the player). Each console holder has a gate_console.gd
# Interactable child with offline()/wake() methods.
func wake_consoles() -> void:
	consoles_call("wake")


# Force both consoles to a dark/offline screen (called at the cold-open start).
func set_consoles_offline() -> void:
	consoles_call("offline")


func consoles_call(method: String) -> void:
	for holder_name: String in ["GateControlConsole", "FTLConsole"]:
		var holder: Node = host._world.get_node_or_null(holder_name)
		if holder == null:
			continue
		var inter: Node = holder.get_node_or_null("Interactable")
		if inter != null and inter.has_method(method):
			inter.call(method)


# ── Quest waypoint ────────────────────────────────────────────────────────────

func on_quest_objective_changed(_text: String) -> void:
	refresh_quest_waypoint()


# Same pattern as room.gd::_refresh_quest_waypoint, adapted for the hand-
# authored gate room: anchors are direct children of self (LtScott, the two
# console holders), the cross-room target uses the ExitDoor instance defined
# in gate_room.tscn (target_room_id = "stargate_corridor_east_connector").
func refresh_quest_waypoint() -> void:
	# Cold open: no quest marker until Lt Scott has come over and talked to us
	# (that conversation is a guaranteed trigger — he walks up on his own). The
	# first quest + its diamond only appear AFTER that beat (met_scott).
	if not GameState.met_scott:
		destroy_quest_waypoint()
		return

	# Scout beat: the objective is "open the Kino Remote", which has no spatial
	# target — the HUD shows a [Tab] guide instead. Suppress the diamond + the
	# HUD edge-arrow (which follows the quest_waypoint group) entirely.
	if GameState.quest_step == GameState.QUEST_SCOUT_KINO:
		destroy_quest_waypoint()
		return

	var target: Dictionary = GameState.quest_target()
	var target_room: String = String(target.get("room", ""))
	var anchor_name: String = String(target.get("anchor", ""))

	if target_room == "":
		destroy_quest_waypoint()
		return

	var pos: Vector3 = Vector3.ZERO
	var placed: bool = false

	if target_room == "gate_room":
		if anchor_name == "":
			pos = Vector3(0.0, QUEST_WAYPOINT_ANCHOR_HEIGHT, 0.0)
			placed = true
		else:
			var anchor: Node = host.get_node_or_null(anchor_name)
			# The two console holders (GateControlConsole, FTLConsole) are
			# children of $World, not self. Look there as a fallback.
			if anchor == null and host._world != null:
				anchor = host._world.get_node_or_null(anchor_name)
			if anchor is Node3D:
				var n3: Node3D = anchor
				pos = n3.global_position + Vector3(0.0, QUEST_WAYPOINT_ANCHOR_HEIGHT, 0.0)
				placed = true
	else:
		var next_hop: String = ShipLayout.next_room_toward("gate_room", target_room)
		if next_hop != "":
			var door: Node3D = find_door_to(next_hop)
			if door != null:
				pos = door.global_position + Vector3(0.0, QUEST_WAYPOINT_DOOR_HEIGHT, 0.0)
				placed = true

	if not placed:
		destroy_quest_waypoint()
		return

	if quest_waypoint == null or not is_instance_valid(quest_waypoint):
		quest_waypoint = Node3D.new()
		quest_waypoint.set_script(QuestWaypointScript)
		quest_waypoint.name = "QuestWaypoint"
		host._world.add_child(quest_waypoint)
	quest_waypoint.global_position = pos
	if quest_waypoint.has_method("set_target_position"):
		quest_waypoint.call("set_target_position", pos)


func destroy_quest_waypoint() -> void:
	if quest_waypoint != null and is_instance_valid(quest_waypoint):
		quest_waypoint.queue_free()
	quest_waypoint = null


func find_door_to(target_id: String) -> Node3D:
	for c in host.get_children():
		if not (c is Node3D):
			continue
		var n: Node3D = c
		var prop: Variant = n.get("target_room_id")
		if prop != null and String(prop) == target_id:
			return n
	return null