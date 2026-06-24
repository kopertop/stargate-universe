extends Node3D

# Phase A: cavernous two-deck gateroom — Destiny's "altar". Procedurally builds
# the hero space so the .tscn stays small and re-runs cheap. Layout:
#
#   • Origin at room centre. +Z = "altar end" (the Stargate); -Z = exit wall
#     with twin staircases and the corridor archway.
#   • 32 m × 32 m footprint, 9 m ceiling, mezzanine deck at y = 5 m on three
#     sides (back, left, right) — open on the +Z side so you can look down on
#     the gate from the back balcony.
#   • Gate platform: raised circular platform prop (from the Stargate hero
#     asset pack) with real metal staircase steps on the room side so the
#     player can walk up the base of the gate without jumping. Stargate ring
#     (detailed prop) mounted at the back, horizon centered inside it.
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
# Shared crew-appearance source of truth (base models, outfits per context, gear).
const CharacterFactoryRef: Script = preload("res://scripts/character_factory.gd")
# Preload bypasses class_name registration timing — same reason as room.gd.
const ShipAlertScript: Script = preload("res://scripts/ship_alert.gd")
const DOOR_SCENE: PackedScene = preload("res://objects/door.tscn")
const QUEST_WAYPOINT_ANCHOR_HEIGHT: float = 2.4
const QUEST_WAYPOINT_DOOR_HEIGHT: float = 1.8

# New cinematic Stargate hero props (Asset Pack) for matching the reference
# gate-room look-and-feel. These replace the old simple stepped dais and provide
# real, walkable metal stairs so the player can climb the gate platform base
# without jumping.
#
# Props are referenced by PATH and loaded at runtime through `_prop_scene()`
# (NOT const preload): a fresh checkout whose `.glb`s have no `.import` sidecar
# yet would HARD parse-error on preload and take the whole scene down with it.
# Runtime load + a null guard degrades a missing asset to "prop absent" instead.
# Run `godot --headless --import` once after copying the glbs so Godot generates
# the sidecars and the props actually appear.
const PROP_DIR: String = "res://models/sci-fi/stargate-props/"
const GATE_RING_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-stargate-portal-ring.glb"
# NEW hero gate: a clean gunmetal ring with NO baked-in portal and NO base/platform
# (decompressed from Draco). It is floor-pinned and walkable straight through — no
# dais, no stairs. Native (scale 1) AABB: thin on X (depth 0.291), circle in the YZ
# plane (Ø 0.998); measured inner radius 0.353, outer radius 0.505 (ratio 0.70).
const GATE_RING_NEW_PATH: String = PROP_DIR + "gunmetal-gate-no-glyphs.glb"
const GATE_DEPTH_SCALE: float = 0.33   # X (ring thickness/depth) — user spec
const GATE_DIAM_SCALE: float = 8.5     # Y/Z (diameter) — user spec ">= 2.0", hero-sized
const GATE_RING_INNER_NATIVE: float = 0.353
const GATE_RING_OUTER_NATIVE: float = 0.505
# Z of the gate plane (a few metres in front of the +Z back wall).
const GATE_Z: float = 12.2
# Sink the ring so the bottom of its INNER hole sits just below the floor: the
# centre is one inner-radius up, minus a small margin so the walk-through opening
# is already player-width at floor level (no step, no jump). The lower ring arc
# tucks under the deck.
const GATE_FLOOR_MARGIN: float = 0.2
const GATE_PLATFORM_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-raised-circular-platform.glb"
const GATE_STAIRS_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-metal-staircase-steps.glb"
const GATE_CONSOLE_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-operator-control-console.glb"
const OVERHEAD_RING_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-overhead-ceiling-ring-structure.glb"
const SPOTLIGHT_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-spotlight-ceiling-light.glb"
const INDUSTRIAL_COLUMN_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-industrial-wall-column.glb"
const CATWALK_RAILING_PROP_PATH: String = PROP_DIR + "sci-fi-stargate-props-catwalk-railing-segment.glb"
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

# --- Gate-throw projectile tuning -------------------------------------------
# Crew (and crates) are FIRED out of the wormhole on a ballistic arc — NOT
# ragdolled. The PhysicalBone joint solver bleeds the launch so badly the body
# never travels (it flops at the gate), so we drive a kinematic projectile that
# always reaches its spot. One value per line so the overnight Karpathy tuner
# can sed-replace them; see tools/throw_tune_loop.sh + tests/shots/ragdoll_tune.gd.
const THROW_FLIGHT_TIME: float = 1.603    # seconds gate→landing (higher = floatier, taller arc)
const THROW_TUMBLE_BASE: float = 5.246     # head-over-heels tumble rate (rad/s) — limbs swing
const THROW_TUMBLE_DIST: float = 0.403    # extra tumble per metre of downrange throw
const THROW_CRATE_FLIGHT: float = 1.15   # crates fly flatter/faster than bodies
const THROW_CRATE_SPIN: float = 6.0      # crate tumble rate (rad/s)

@export_group("Room")
@export var room_size: Vector2 = Vector2(32.0, 32.0)
@export var tile_size: float = 2.0
@export var deck1_height: float = 0.0
@export var mezzanine_height: float = 5.0
@export var ceiling_height: float = 13.0   # tall + cavernous — the vast empty-ship read
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
@onready var _gate_kawoosh_sfx: AudioStreamPlayer = $GateKawoosh
@onready var _gate_hum_sfx: AudioStreamPlayer = $GateHum
# Round-robin pool of body-impact players for the panic arrival (built lazily).
var _thud_players: Array[AudioStreamPlayer] = []
var _thud_streams: Array[AudioStream] = []
var _thud_i: int = 0
# Crates hurled through the gate this cold-open, so crew can shove them to the
# walls afterward (out of the way so nobody trips over them).
var _arrival_crates: Array[Node3D] = []

var _stargate: Node3D
# The visible gunmetal ring GLB (separate from the procedural _stargate, which now
# only owns the event horizon). Cached so the dial sequence can spin it.
var _gate_ring: Node3D = null
# Dial/spin state. While _dialing, _process spins the ring about its facing axis
# (world Z) with an accelerating ramp — the "stargate dialing" read.
var _dialing: bool = false
var _dial_elapsed: float = 0.0
# Per-chevron lock SFX: fire stargate_chevron_incom.mp3 once each time a chevron locks
# (round-robin pool so consecutive locks don't cut each other off).
var _chevrons_lit_prev: int = 0
var _chevron_lock_players: Array[AudioStreamPlayer] = []
var _chevron_lock_idx: int = 0
var _dial_with_sfx: bool = true
# Latch: keep the gate open after a dial/cinematic regardless of story flags.
var _gate_forced_open: bool = false
const DIAL_TIME: float = 3.2          # seconds the ring spins before lock + kawoosh
const SCOTT_GETUP_DELAY: float = 1.5  # seconds after Scott's ragdoll settles before he stands
# Fixed chevron-glow markers ringing the gate. They light up one-by-one while the
# ring spins (the dialing read), then all lock just before the portal flushes open.
var _chevron_glows: Array[MeshInstance3D] = []
# Unscaled pivot at the gate face centre that carries all 9 glow prisms as children.
# Parented to _world (NOT to _gate_ring) so the ring's (0.33/8.5/8.5) scale does NOT
# distort the prism meshes. Rotation is copied from the ring each frame so the glows
# stay locked on the chevron wedges during the dial spin.
var _chevron_rig: Node3D = null
const CHEVRON_COUNT: int = 9
const CHEVRON_ENERGY: float = 4.0
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
# One-time cache for runtime-loaded hero props (see PROP_DIR consts above).
var _prop_cache: Dictionary = {}

func _ready() -> void:
	# Tell the save system this is a real gameplay scene.
	GameState.current_scene_path = "res://scenes/gate_room.tscn"

	# Build the room and gate furniture before anything else looks for nodes.
	_build_floor()
	_build_walls_and_ceiling()
	_build_mezzanine()
	_build_staircases()
	_build_gate_platform()
	_build_structural_columns()
	_build_consoles()
	_build_npcs()
	_build_lighting_props()

	# Red-alert tint catches every light spawned by the build helpers above.
	# Tints the WorldEnvironment ambient too so the gate room reads as the
	# same emergency state as the procedural rooms.
	if ShipAlertScript.is_alert_active():
		ShipAlertScript.apply_to_scene(self)

	# Spawn the procedural Stargate node — we keep ONLY its animated event horizon
	# (+ ripples + light + activation logic); the visible ring is the new gunmetal
	# GLB. Floor-pinned: centre one inner-radius up so the hole reaches the deck.
	var gate_center_y: float = _gate_center_y()
	_stargate = STARGATE_SCENE.instantiate()
	_stargate.name = "Stargate"
	_stargate.position = Vector3(0.0, gate_center_y, GATE_Z)
	_world.add_child(_stargate)
	_build_ship_gate_portal()

	# === NEW gunmetal hero ring — floor-pinned, walkable, NO platform ===
	# Native ring lies in the YZ plane (thin X). Rotate 90° about Y so the thin
	# (facing) axis points along Z toward the room. Scale: X = depth, Y/Z = Ø.
	var ring: Node3D = _instance_prop(GATE_RING_NEW_PATH)
	if ring != null:
		ring.name = "GateRing"
		ring.position = Vector3(0.0, gate_center_y, GATE_Z)
		ring.scale = Vector3(GATE_DEPTH_SCALE, GATE_DIAM_SCALE, GATE_DIAM_SCALE)
		ring.rotation.y = PI * 0.5
		_world.add_child(ring)
		_gate_ring = ring
		_build_chevron_glows()
		# Trimesh collider follows the ring (incl. the hole), so you can't clip the
		# metal but the central opening — and the sunk lower arc — stay walkable.
		_add_prop_collider(ring)
		# Hide the procedural Stargate's own ring/chevrons; the GLB is the ring now.
		for n in ["OuterRing", "GlyphBand"]:
			var old := _stargate.get_node_or_null(n)
			if old != null:
				old.visible = false
		for i in 9:
			var ch := _stargate.get_node_or_null("Chevron%d" % i)
			if ch != null:
				ch.visible = false
		# Match the horizon disc (native radius ~2.32) to the new ring's inner
		# radius so the puddle fills the hole flush with the rim.
		var inner_r: float = GATE_RING_INNER_NATIVE * GATE_DIAM_SCALE
		var horizon_scale: float = inner_r / 2.32
		_stargate.scale = Vector3(horizon_scale, horizon_scale, 1.0)

	# Place the spawn markers now that the room geometry is in place.
	_create_spawn_markers()

	# D1: stamp the always-open Upper Deck door at the right stair-top landing,
	# and create the matching return-trip arrival marker. Floor 2 is generated on
	# demand so the room.gd target always exists before the transition fires.
	_build_upper_deck_stairs_door()

	# Returning through the gate from the lime planet: the away team came back
	# WITH the player — spawn them standing just behind the FromPlanet landing.
	if GameState.pending_planet_return:
		GameState.pending_planet_return = false
		_spawn_returned_away_team()

	# Discover + run arrival branch. If resuming from save, skip the cinematic.
	var first_visit: bool = not GameState.rooms_discovered.has("gate_room")
	GameState.discover_room("gate_room", "Gate Room")
	# Home base — the player is here on foot, so decipher it (readable name /
	# plaques, no glyphs). The hand-authored gate room doesn't route through
	# room.gd, so decipher explicitly here.
	GameState.decipher_room("gate_room")
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

func _process(delta: float) -> void:
	# While dialing: spin the ring (accelerating, about its facing axis = world Z)
	# and light the fixed chevrons one-by-one as it locks them in. Runs before
	# _refresh_gate_state so the dial sequence owns the gate state while active.
	if _dialing and _gate_ring != null and is_instance_valid(_gate_ring):
		_dial_elapsed += delta
		var ramp: float = clampf(_dial_elapsed / DIAL_TIME, 0.0, 1.0)
		var spin_speed: float = TAU * (0.12 + 0.5 * ramp)   # rev/s, slower: was (0.35 + 1.6*ramp)
		_gate_ring.rotate(Vector3(0.0, 0.0, 1.0), spin_speed * delta)
		# Spin the ChevronRig by the SAME world-Z delta so the glows stay locked to the
		# moulded chevrons. Do NOT read _gate_ring.rotation.z — the ring sits at
		# rotation.y = PI/2, the Euler-XYZ gimbal-lock singularity, so its .z channel is
		# degenerate and would drift the rig. Identical incremental rotate() = perfect sync.
		if _chevron_rig != null and is_instance_valid(_chevron_rig):
			_chevron_rig.rotate(Vector3(0.0, 0.0, 1.0), spin_speed * delta)
		# Chevrons light progressively across the dial (the "locking" read), and the
		# chevron-lock sound fires once for each chevron at the moment it lights.
		var lit: int = int(ramp * float(CHEVRON_COUNT))
		_light_chevrons(lit)
		if lit > _chevrons_lit_prev:
			if _dial_with_sfx:
				for _i in range(_chevrons_lit_prev, lit):
					_play_chevron_lock()
			_chevrons_lit_prev = lit
		return
	_refresh_gate_state()


# Build the 9 chevron-glow prisms on an unscaled pivot ("ChevronRig") at the gate
# face centre. The rig lives as a child of _world (NOT _gate_ring) so the ring's
# (0.33/8.5/8.5) scale does NOT distort the prism meshes — they stay round/correct.
# During the dial spin, _process copies _gate_ring.rotation.z to _chevron_rig.rotation.z
# each frame, keeping the amber glows locked on the molded chevron wedges.
func _build_chevron_glows() -> void:
	var cy: float = _gate_center_y()
	var outer_r: float = GATE_RING_OUTER_NATIVE * GATE_DIAM_SCALE
	# ~3.69 m radius puts the centre of each glow on the moulded chevron bracket.
	# (outer_native 0.505 * diam_scale 8.5 * 0.86 ≈ 3.69 m)
	var r: float = outer_r * 0.86
	# Unscaled pivot at the gate face centre. Children inherit NO scale from the ring.
	_chevron_rig = Node3D.new()
	_chevron_rig.name = "ChevronRig"
	_chevron_rig.position = Vector3(0.0, cy, GATE_Z)
	_world.add_child(_chevron_rig)
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
		_chevron_rig.add_child(mi)
		_chevron_glows.append(mi)


# Fire one chevron-lock one-shot (round-robin pool, built lazily) — called once per
# chevron as it lights during the dial.
func _play_chevron_lock() -> void:
	if _chevron_lock_players.is_empty():
		var stream: AudioStream = load("res://sounds/stargate_chevron_incom.mp3") as AudioStream
		if stream == null:
			return
		for _i in 3:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.stream = stream
			add_child(pl)
			_chevron_lock_players.append(pl)
	var p: AudioStreamPlayer = _chevron_lock_players[_chevron_lock_idx % _chevron_lock_players.size()]
	_chevron_lock_idx += 1
	p.play()


# Light the first `count` chevrons (0..CHEVRON_COUNT); the rest stay dark.
func _light_chevrons(count: int) -> void:
	for i in _chevron_glows.size():
		var mi: MeshInstance3D = _chevron_glows[i]
		if mi == null or not is_instance_valid(mi):
			continue
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = CHEVRON_ENERGY if i < count else 0.0


# Reusable dial choreography, in the exact beats the design calls for:
#   1) the ring SPINS up (stargate-style),
#   2) the CHEVRONS light up one-by-one as it locks them (driven in _process),
#   3) the centre portal FLUSHES open (kawoosh) and the ring STOPS spinning,
#   4) the portal STABILISES (shimmering) and is then walkable.
# `with_sfx` plays the dial rumble + whoosh (skipped for silent/headless captures).
# Awaitable so cinematics can sequence around it.
func dial_and_open(with_sfx: bool = true) -> void:
	if _dialing:
		return
	_dialing = true
	_dial_elapsed = 0.0
	_chevrons_lit_prev = 0
	_light_chevrons(0)
	# Reset the ring + chevron rig to a known, in-sync pose so a repeat dial can't
	# accumulate drift (ring base orientation = yaw +90°; the rig is unrotated).
	if _gate_ring != null and is_instance_valid(_gate_ring):
		_gate_ring.rotation = Vector3(0.0, PI * 0.5, 0.0)
	if _chevron_rig != null and is_instance_valid(_chevron_rig):
		_chevron_rig.rotation = Vector3.ZERO
	# (1)+(2) The chevron-lock sound now fires per-chevron in _process as each locks
	# (gated on _dial_with_sfx); no single dial-start rumble.
	_dial_with_sfx = with_sfx
	await get_tree().create_timer(DIAL_TIME).timeout
	# Ring STOPS spinning; all chevrons locked.
	_dialing = false
	_light_chevrons(CHEVRON_COUNT)
	# Keep the gate lit after lock so _refresh_gate_state doesn't snap it back off.
	_gate_forced_open = true
	# (3) The centre portal FLUSHES open — kawoosh burst on the gate itself.
	if _stargate != null and _stargate.has_method("kawoosh"):
		_stargate.call("kawoosh")
	elif _stargate != null and "active" in _stargate:
		_stargate.active = true
	# WHOOSH on open (the kawoosh), then settle into the steady energy hum.
	if with_sfx:
		if _gate_loop_sfx != null and _gate_loop_sfx.playing:
			_gate_loop_sfx.stop()
		if _gate_kawoosh_sfx != null and _gate_kawoosh_sfx.stream != null:
			_gate_kawoosh_sfx.play()
		if _gate_hum_sfx != null and _gate_hum_sfx.stream != null:
			_gate_hum_sfx.play()
	# (4) Let the puddle stabilise (the shader's shimmer settles) before callers
	# treat it as walkable.
	await get_tree().create_timer(0.6).timeout

# Floor-pinned gate centre: one inner-radius up, minus a margin so the hole's
# bottom dips just below the deck and the opening is player-width at floor level
# (walk straight through — no step, no jump). The lower ring arc tucks under.
func _gate_center_y() -> float:
	return GATE_RING_INNER_NATIVE * GATE_DIAM_SCALE - GATE_FLOOR_MARGIN

# ----- spawn -----------------------------------------------------------------

func _create_spawn_markers() -> void:
	# "FromGate" — player just stepped through the (floor-pinned) gate, on the deck
	# just in front of the ring, facing -Z into the room. No dais now → floor height.
	_from_gate_marker = $FromGate
	_from_gate_marker.position = Vector3(0.0, 0.05, room_size.y * 0.5 - 5.5)
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

# D1: Stamp a transition door at the right stair-top landing (x=+12, y=5, z=-10)
# pointing to the Floor-2 Observation Deck entry room. Generates Floor 2 on demand
# so the target room exists before any transition fires. Also creates the
# "FromObservationDeck" arrival Marker3D so the return trip (obs-deck → gate room)
# lands the player at this stair-top landing facing into the room (+Z toward gate).
func _build_upper_deck_stairs_door() -> void:
	# Ensure Floor 2 is generated so floor2_obs_entry_id() returns a valid id.
	ProceduralShip.ensure_floor_generated(2)
	var obs_id: String = ProceduralShip.floor2_obs_entry_id()
	if obs_id == "":
		push_warning("gate_room: floor 2 not generated — upper deck door skipped")
		return

	# Stair-top position: right stair (side_sign=+1) top lands at
	#   x = +(half_x - mezzanine_depth) = +12, y = mezzanine_height = 5, z = STAIR_Z_CENTER = -10
	var half_x: float = room_size.x * 0.5
	var stair_top: Vector3 = Vector3(half_x - mezzanine_depth, mezzanine_height, STAIR_Z_CENTER)

	# The door faces -X from the right mezzanine wall (face_yaw = +PI*0.5 = face left/inward).
	# Place it flush with the inner edge of the right mezzanine strip.
	var door: Node = DOOR_SCENE.instantiate()
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
	_world.add_child(door)

	# Return-trip arrival marker: player landing back from the Observation Deck
	# appears 1.2 m inward (toward -X) from the door, facing +X into the room.
	var marker: Marker3D = Marker3D.new()
	marker.name = ProceduralShip.STAIRS_GATE_SPAWN   # "FromObservationDeck"
	# 1.2 m inward from the stair-top door, still on the mezzanine level (y=5).
	marker.position = stair_top + Vector3(-1.2, 0.0, 0.0)
	marker.rotation.y = -PI * 0.5  # face +X into room (away from wall)
	add_child(marker)


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
	GameState.set_objective("Talk to Lt Scott.")
	GameState.add_log("Eli: Okay… where am I?")
	GameState.add_log("Lt Scott: Hey — over here. We need to figure out where we are.")
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(true)

	# Headless / scripted runs (e1_playthrough) skip the cinematic spectacle and
	# settle straight to the gameplay state — the cinematic uses tweens/timers and
	# a temp camera that those tests neither tick nor want.
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		if _stargate != null and "active" in _stargate:
			_stargate.active = false
		_gate_forced_open = false
		_start_ambient()
		if _player != null and _player.has_method("set_input_locked"):
			_player.set_input_locked(false)
		_arrival_running = false
		return

	await _play_prologue_cinematic()

	_start_ambient()
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(false)
	_arrival_running = false


# The cold open — now driven by the REAL "Air" recording (sounds/dialog/prologue/
# cold_open_master.mp3) played as ONE master track. Every visual beat is timed
# against that clip's playhead (_await_audio) and the captions subtitle its own
# dialogue, so the scene stays locked to the audio across its full ~4:15 runtime.
# Beats:
#   • The gate DIALS (spin → chevrons lock → portal flushes open → stabilises).
#   • WAVE 1: Lt Scott flung through first, kneels, rises, waves the rest through.
#   • WAVES 2–8: the flood — Young thrown hardest (injured, face-down), James the
#     medic, Park/Volker to consoles, soldiers + civilians in pairs, crates raining.
#   • Eli (the player) last through, closest to the gate; he groggily stands.
#   • The hush → wonder → Scott can't find Rush → "Eli! NOW!". The recording carries
#     the voices; we subtitle them and stage Scott's looks.
# The old per-line baked TTS clips (open-*.wav) are retired by this single track.
func _play_prologue_cinematic() -> void:
	_set_arrival_crew_visible(false)
	# Hold Scott's auto-greet for the WHOLE cold open — and, per the synced-audio
	# design, we DON'T turn it back on at the end: by the time the recording finishes
	# the player already holds the Find-Rush objective (set below), so Scott never
	# walks over to brief them (the "first stop is the quest, not a Scott chat" beat).
	_set_scott_autogreet(false)
	# The player body stays hidden until his wave delivers him.
	_show_player_model(false)
	# Consoles are dead/offline on the derelict during the cold open.
	_set_consoles_offline()

	# A cinematic carries NO floating UI labels — the captions name the speaker.
	# Hide any nametag already in the room (pre-built Scott/James/Young) and arm
	# the flag so every crew body built mid-flood spawns its tag hidden too.
	_cold_open_active = true
	_set_crew_nametags_visible(false)

	# Camera cuts (cut-to-speaker) own the framing for the whole verbatim cold open.
	_begin_cuts()
	_cut_wide(0.5)

	# THE soundtrack: the ~165s ambience BED, played ONCE. _cold_open_start_ms anchors
	# the wall-clock fallback if the stream fails (real play has it; headless skips this
	# whole path via instant_mode). Our designed per-character VO plays on top via _cap.
	_cold_open_start_ms = Time.get_ticks_msec()
	var audio: AudioStreamPlayer = AudioStreamPlayer.new()
	audio.name = "ColdOpenMaster"
	add_child(audio)
	var bed: AudioStream = load(COLD_OPEN_BED) as AudioStream
	if bed != null:
		if "loop" in bed:
			bed.set("loop", false)
		audio.stream = bed
		audio.play()

	await Cinematic.letterbox_in()

	# DIAL (≈0.5–3.5s): ring spins → chevrons lock one-by-one (sound per chevron) → kawoosh.
	await get_tree().create_timer(0.5).timeout
	await dial_and_open(true)

	# §1.2 FIRST THROUGH — Scott dives through, rolls up, marshals the early arrivals.
	var scott: StaticBody3D = _co_arrival("Lt Scott", "", Vector3(1.6, 0.05, GATE_Z - 4.5),
			Vector3(2.2, 0.05, GATE_Z - 5.5), "scott", _world.get_node_or_null("LtScott") as StaticBody3D)
	GameState.add_log("Lt Scott comes barrelling through the gate!")
	GameState.narrate("Lt Scott comes barrelling through the gate!")
	_cut_follow(scott, Vector3(2.0, 1.6, 3.2))
	_cap("LT. SCOTT", "All right, get out of here. Get out of the way!", 6.0, "open-scott-clearway")

	# §1.3 PANDEMONIUM — people pour through FIRST, then the crates start raining.
	_co_crowd_flood(audio, 7.0, 60.0, 0.7)
	_cap("LT. SCOTT", "This is Scott! Slow down the evac — we are comin' in too hot!", 10.0, "open-scott-evac")
	await _await_audio(audio, 12.0)
	var wray: StaticBody3D = _co_arrival("Camile Wray", "", Vector3(-1.4, 0.05, GATE_Z - 3.4),
			Vector3(-3.2, 0.05, GATE_Z - 4.5), "civ")
	_cut_to(wray, 3.0, 1.5, 1.4, 0.6)
	_cap("CAMILE WRAY", "Where are we? Why didn't we come through to Earth?", 13.5, "open-wray-whereare")
	_cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	_cap("LT. SCOTT", "There's no time to explain. Off to the side!", 15.5, "open-scott-side")
	await _await_audio(audio, 16.0)
	_launch_crate_wave()                       # gear now raining in (after the first people)
	_cap("LT. SCOTT", "This is Scott — come in!", 18.5, "open-scott-comein")

	# §1.4 "I NEED A MEDIC" — TJ working the broken-arm man; a crate hits him.
	# Reveal TJ at the medic pocket and place the wounded man beside her.
	var tj: StaticBody3D = _world.get_node_or_null("LtJames") as StaticBody3D
	var medic_spot: Vector3 = Vector3(3.4, 0.05, GATE_Z - 8.0)
	if tj != null:
		tj.visible = true
		if "enabled" in tj: tj.set("enabled", true)
		tj.global_position = medic_spot
		_rise_npc(tj, "crouch_idle")
	var man: StaticBody3D = _co_arrival("Wounded Marine", "", medic_spot + Vector3(1.0, 0.0, 0.4),
			medic_spot + Vector3(1.0, 0.0, 0.4), "hard")
	_cap("MARINE", "I need a medic!", 20.0, "open-marine-medic")
	await _await_audio(audio, 23.0)
	_cut_to(tj, 2.8, 1.4, -1.2, 0.6)           # cut to TJ + the wounded man
	_cap("TJ", "Over here! Can you move your fingers?", 24.0, "open-tj-fingers")
	await _await_audio(audio, 27.0)
	_launch_impact_crate(man, "arm")           # a crate skids in and clips his arm
	_cap("MARINE", "No. I think my arm is broken.", 29.0, "open-man-broken")
	_cap("TJ", "Okay, just hold your arm there and we'll put it in a sling, okay?", 32.0, "open-tj-sling")

	# §1.5 RUSH/ELI + the staircase; Scott marshals; Senator + Chloe arrive.
	await _await_audio(audio, 36.0)
	_cut_wide(0.8)
	_cap("LT. SCOTT", "Clear this area! There could still be more incoming!", 38.0, "open-scott-cleararea")
	await _await_audio(audio, 42.0)
	var senator: StaticBody3D = _co_arrival("Senator Armstrong", "", Vector3(-5.0, 0.05, GATE_Z - 6.5),
			Vector3(-6.5, 0.05, GATE_Z - 7.5), "civ")
	var chloe: StaticBody3D = _co_arrival("Chloe Armstrong", "", Vector3(-4.0, 0.05, GATE_Z - 5.8),
			Vector3(-6.0, 0.05, GATE_Z - 8.2), "civ")
	_cut_to(chloe, 2.8, 1.4, 1.3, 0.6)
	_cap("CHLOE", "Are you okay?", 44.0, "open-chloe-areyouok")
	_cut_to(senator, 3.0, 1.5, 1.4, 0.5)
	_cap("SENATOR", "Yeah.", 47.0, "open-senator-yeah")
	_cap("SENATOR", "Where the hell are we?", 49.0, "open-senator-whereare")

	# §1.6 "Where's Colonel Young?" — Scott to Greer.
	await _await_audio(audio, 51.0)
	var greer: StaticBody3D = _co_arrival("Sgt Greer", "greer", Vector3(4.4, 0.05, GATE_Z - 5.0),
			Vector3(5.6, 0.05, GATE_Z - 6.5), "mil")
	# Eli (the player) is delivered last-ish, closest to the gate.
	await _await_audio(audio, 53.0)
	var eli_spot: Vector3 = Vector3(-0.6, 0.05, GATE_Z - 6.2)
	var r_eli: Node3D = _launch_ragdoll("Eli", eli_spot)
	GameState.add_log("Eli is hurled through and slams into the deck!")
	_cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	_cap("LT. SCOTT", "Greer? Where's Colonel Young?", 55.0, "open-scott-greerwhere")
	await _await_audio(audio, 54.5)
	if _player != null:
		_player.global_position = eli_spot
		_lay_player_prone(true)
		_show_player_model(true)
	if is_instance_valid(r_eli): r_eli.queue_free()
	_thud()
	_cut_to(greer, 3.0, 1.5, 1.5, 0.5)
	_cap("SGT. GREER", "He was right behind me.", 58.0, "open-greer-behindme")

	# §1.7 YOUNG arrives HARDEST → a crate clips his head → the gate shuts.
	await _await_audio(audio, 60.5)
	var young_spot: Vector3 = Vector3(-3.2, 0.05, GATE_Z - 11.0)
	var young: StaticBody3D = _co_arrival("Colonel Young", "", young_spot, young_spot, "hard",
			_world.get_node_or_null("ColonelYoung") as StaticBody3D)
	_cut_to(young, 3.2, 1.4, 1.6, 0.6)
	await _await_audio(audio, 63.0)
	_launch_impact_crate(young, "head")        # head wound
	await _await_audio(audio, 64.0)
	_collapse_gate()
	Cinematic.flash(Color(1.0, 0.6, 0.25, 1.0), 0.6)   # flame/steam vent
	_cut_follow(greer, Vector3(2.0, 1.6, 3.0))
	_cap("SGT. GREER", "Move, move, move. Stay calm! Keep it down! Move, move, move, move, move.", 66.0, "open-greer-move")

	# Eli groggily climbs to his feet.
	await _await_audio(audio, 68.0)
	_lay_player_prone(false)

	# §1.8 COMMAND HAND-OFF — Scott crosses to Young; Young passes command; blood; TJ called.
	_co_command_handoff(scott, young)
	_cut_follow(scott, Vector3(1.8, 1.5, 3.0))
	_cap("LT. SCOTT", "Colonel? Colonel?", 72.0, "open-scott-colonel")
	_cap("SGT. GREER", "Don't move!", 74.0, "open-greer-dontmove")
	await _await_audio(audio, 76.0)
	_cut_to(young, 2.4, 1.1, 1.3, 0.6)         # close on Young, barely conscious
	_cap("COL. YOUNG", "Where are we? Where are we?", 76.0, "open-young-whereare")
	_cap("LT. SCOTT", "I don't know, sir.", 78.0, "open-scott-idontknow")
	_cap("COL. YOUNG", "You're in charge, okay? You're...", 80.0, "open-young-incharge")
	_cut_to(scott, 2.6, 1.4, 1.4, 0.6)
	_cap("LT. SCOTT", "Yes, sir.", 83.5, "open-scott-yessir")   # blood-on-the-hand beat
	_cap("LT. SCOTT", "TJ!", 86.0, "open-scott-tj")
	_cut_follow(tj, Vector3(1.8, 1.5, 2.8))
	_cap("TJ", "I'm coming!", 88.0, "open-tj-coming")
	_cap("SGT. GREER", "Is he okay?", 91.0, "open-greer-isheok")
	_cap("TJ", "Uh, I dunno.", 93.0, "open-tj-dunno")

	# §1.8b Scott rounds on Eli (Wallace) to find Rush.
	await _await_audio(audio, 96.0)
	_cut_to(scott, 3.0, 1.5, 1.5, 0.5)
	_cap("LT. SCOTT", "Wallace!", 96.0, "open-scott-wallace")
	_cut_to(_player, 3.0, 1.5, 1.5, 0.5)
	_cap("LT. SCOTT", "What is this place?", 99.0, "open-scott-whatisplace")
	_cap("ELI", "Look, I just did what Rush told me.", 101.0, "open-eli-didwhat")
	_cut_to(scott, 3.0, 1.5, 1.5, 0.5)
	_cap("LT. SCOTT", "Where is he?", 104.0, "open-scott-whereishe")
	_cut_to(_player, 3.0, 1.5, 1.5, 0.5)
	_cap("ELI", "I don't know if he went ahead of me.", 106.0, "open-eli-wentahead")
	await _await_audio(audio, 108.5)
	_face_gate(scott)
	_cut_to(scott, 3.4, 1.6, 1.6, 0.5)
	_cap("LT. SCOTT", "Rush!", 109.0, "open-scott-rush")
	_cap("LT. SCOTT", "Rush! Eli, help me find him.", 112.0, "open-scott-findhim")
	_cap("ELI", "Well, I...", 114.5, "open-eli-welli")

	# §1.9 THE SHIMMER — the ship jumps to FTL (left-right shake + blur), then the button.
	await _await_audio(audio, 118.0)
	_ftl_jump()
	_cut_wide(0.8)
	_cap("SGT. GREER", "What in the hell was that?!", 120.0, "open-greer-whatwasthat")
	_cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	_cap("LT. SCOTT", "I don't know. Sergeant, I need you to get these people settled here. I need you to find out who and what we've got. Nobody leaves this room.", 123.0, "open-scott-settle")
	_cut_to(greer, 3.0, 1.5, 1.5, 0.5)
	_cap("SGT. GREER", "Yes, sir.", 133.0, "open-greer-yessir")
	await _await_audio(audio, 137.0)
	_face_player(scott)
	_cut_to(_player, 2.8, 1.5, 1.4, 0.5)
	_cap("LT. SCOTT", "Eli! Now!", 139.0, "open-scott-elinow")

	# End: drop the bars, release the cut camera, hand control back.
	await _await_audio(audio, 142.0)
	Cinematic.set_caption("")
	await Cinematic.letterbox_out()
	if is_instance_valid(audio):
		audio.queue_free()
	_end_cuts()

	# Hand control back. The player ALREADY holds the Find-Rush quest — Scott does NOT
	# walk over to brief them. Mark him met and advance e1_air talk_scott → find_rush.
	_restore_player_camera(null)
	_wake_consoles()
	# Cinematic over: restore crew nametags so the player can ID who's who in the
	# room (anonymous flood extras carry no tag, so only named crew light up).
	_cold_open_active = false
	_set_crew_nametags_visible(true)
	GameState.met_scott = true
	GameState.advance_air_quest()
	_set_scott_autogreet(false)


# Throw a pair of crew (and optionally a crate) head-first through the gate, ≤2 in
# the air. Each crew member is a REAL persistent interactable NPC whose own body is
# the ragdoll that flies through — the SAME body lands, settles, and stays as the
# character (no throwaway-then-spawn swap). Names are real SGU cast.
func _extra_pair(a_name: String, a_kind: String, a_spot: Vector3,
		b_name: String, b_kind: String, b_spot: Vector3,
		crate_spot: Vector3 = Vector3.ZERO) -> void:
	var na: StaticBody3D = _throw_persistent_crew(a_name, a_kind, a_spot)
	await get_tree().create_timer(0.35).timeout
	var nb: StaticBody3D = _throw_persistent_crew(b_name, b_kind, b_spot)
	if crate_spot != Vector3.ZERO:
		_launch_crate(crate_spot)
	await get_tree().create_timer(2.3).timeout   # full flight + settle
	# Stop the ragdoll on each body and leave THE SAME body, where it landed, in a
	# beaten-up kneel/sit (nobody pops straight up after a hit like that).
	_settle_persistent_crew(na)
	_settle_persistent_crew(nb)
	await get_tree().create_timer(0.6).timeout


# Build a REAL interactable crew NPC, dive it HEAD-FIRST through the gate as a
# ragdoll (its own skeleton is the physics body), and return it. After it lands,
# call _settle_persistent_crew() to stop the sim and leave the same body in place.
func _throw_persistent_crew(display_name: String, kind: String, spot: Vector3,
		existing: StaticBody3D = null) -> StaticBody3D:
	# Spawn clear of the ring collider so the body flies cleanly into the room.
	var origin: Vector3 = Vector3(0.0, _gate_center_y(), GATE_Z - 2.0)
	var npc: StaticBody3D = existing
	if npc == null:
		# Generic returned-crew body (extras who have no authored scene node).
		npc = _build_returned_crew_npc(
			display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
		var tree: Variant = npc.get("dialogue_tree")
		if tree == null or (tree is Array and (tree as Array).is_empty()):
			var generic: Array = [{"speaker": display_name,
				"text": "Still shaking that off. Give me a second.",
				"choices": [{"text": "(nod)", "next": "exit"}]}]
			npc.set("dialogue_tree", generic)
			npc.set("repeat_dialogue_tree", generic)
		npc.position = origin
		npc.set_meta("arrival_spot", spot)
		_world.add_child(npc)
	else:
		# Re-use a PRE-BUILT scene NPC (Scott, Young) so the SAME body that flies is
		# the one that stays — keeping its authored dialogue / auto_greet / met-flag
		# identity. No throwaway-then-reveal swap (the old "different body appears
		# somewhere else" artifact). It was hidden at cold-open start; reveal it now.
		npc.visible = true
		if "enabled" in npc:
			npc.set("enabled", true)
		npc.global_position = origin
		npc.set_meta("arrival_spot", spot)
	# Fire head-first across the room as a PROJECTILE (clean ballistic arc), NOT a
	# ragdoll. The PhysicalBone joint solver bleeds the launch so hard the body never
	# travels — it flops at the gate, and the old code hid that by TELEPORTING it to
	# the spot at settle (the "lands here / spawns over there" jump). A projectile
	# flies far like it was hurled out of the wormhole and lands EXACTLY on the spot.
	_fly_projectile(npc, spot, THROW_FLIGHT_TIME)
	return npc


# Drive `npc` along a ballistic arc from its current position to `spot` over
# `flight` seconds — fired out of the gate STRAIGHT to its landing spot, NO flip.
# The body holds one fixed face-down dive orientation the whole flight (so it can't
# rotate through the floor) and lands FACE DOWN exactly on the spot. Kinematic (we
# integrate the position ourselves), so it always arrives on `spot` (no teleport/
# jump) and the floor-clamp guarantees it never sinks through the deck mid-air.
# Fire-and-forget coroutine; _settle_persistent_crew then poses the landed body.
func _fly_projectile(npc: StaticBody3D, spot: Vector3, flight: float) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var origin: Vector3 = npc.global_position
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var disp: Vector3 = spot - origin
	# Ballistic solve: horizontal at constant speed; vertical launched so the body
	# returns to spot.y at t=flight (apex height grows with flight → taller arc).
	var vel: Vector3 = Vector3(disp.x / flight, (disp.y + 0.5 * g * flight * flight) / flight, disp.z / flight)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	# Face-DOWN dive, HEAD pointing along the horizontal travel — held FIXED (no
	# tumble) so the crew don't flip head-over-heels and so the mesh can't rotate
	# below the deck. rotation.x = +PI/2 is face-down (same as the player prone); the
	# yaw is set so the HEAD leads (not feet-first).
	var yaw: float = atan2(disp.x, disp.z)
	if model != null and is_instance_valid(model):
		model.rotation = Vector3(PI * 0.5, yaw, 0.0)
		model.position.y = 0.1
	var t: float = 0.0
	while t < flight and is_instance_valid(npc):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		vel.y -= g * dt
		npc.global_position += vel * dt
		# Collision floor: never let the body sink through the deck while airborne.
		if npc.global_position.y < 0.05:
			npc.global_position.y = 0.05
		t += dt
		await get_tree().process_frame
	# Arrive exactly on the aimed spot, FACE DOWN. _settle_persistent_crew then either
	# leaves them sprawled face-down or rises them to a kneel/crouch.
	if is_instance_valid(npc):
		npc.global_position = Vector3(spot.x, 0.05, spot.z)
		var mc0: Node3D = _first_mc(npc)
		if mc0 != null and mc0.has_method("play_clip"):
			mc0.call("play_clip", "idle")
		_thud()


# Stop a thrown crew member's ragdoll and leave THE SAME body where it landed, in
# a beaten-up kneel/crouch/recoil. No swap, no free — this is the persistent
# character. `pose`: "auto" picks a varied injured clip per character; pass an
# explicit clip (e.g. "repair") to force one.
func _settle_persistent_crew(npc: StaticBody3D, pose: String = "auto") -> void:
	if npc == null or not is_instance_valid(npc):
		return
	# The projectile already flew the body to its aimed spot (no teleport jump), so
	# this just confirms the position and drops it into the injured pose. (sim is
	# null on the projectile path; the guard keeps it safe if a ragdoll body is ever
	# passed in.)
	var rest: Vector3 = npc.get_meta("arrival_spot", npc.global_position)
	npc.global_position = rest
	var sim: PhysicalBoneSimulator3D = _ragdoll_sim(npc)
	if sim != null:
		sim.physical_bones_stop_simulation()
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	var mc: Node3D = _first_mc(npc)
	# Pose pool: kneel (repair), low crouch (crouch_idle), or stay sprawled FACE-DOWN
	# (facedown). All land face-down off the throw; the kneel/crouch ones have pushed
	# themselves up to a knee. Deterministic per character so the crowd isn't uniform.
	var clip: String = pose
	if pose == "auto":
		var pool: Array[String] = ["repair", "crouch_idle", "facedown"]
		clip = pool[absi(npc.name.hash()) % pool.size()]
	if clip == "facedown":
		# Knocked flat on their front (NOT on their back) — rotation.x = +PI/2 is the
		# same face-down lay the player prone uses.
		if model != null:
			model.rotation = Vector3(PI * 0.5, PI, 0.0)
			model.position.y = 0.1
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "idle")
	else:
		# Recovered to a knee/crouch — upright again.
		if model != null:
			model.rotation = Vector3(0.0, PI, 0.0)
			model.position.y = 0.0
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", clip)
	_thud()   # body hits the deck


# The ModularCharacter under a crew NPC's "Model" holder (or null).
func _first_mc(npc: Node) -> Node3D:
	if npc == null:
		return null
	var model: Node = npc.get_node_or_null("Model")
	if model == null:
		return null
	for c: Node in model.get_children():
		return c as Node3D
	return null


# The real "Air" cold-open recording, played once as the master soundtrack and
# anchor for every beat below. The old per-line open-*.wav TTS clips are retired in
# favour of this single track (left on disk only as a fallback reference).
const COLD_OPEN_MASTER: String = "res://sounds/dialog/prologue/cold_open_master.mp3"
# The cold open now plays the Demucs-isolated AMBIENCE bed (music/kawoosh/crowd, the
# original voices stripped) and layers OUR designed per-character VO clips on top via
# _cap(...) — so the dialog is our voices, not the recording's. The bed is still the
# master clock (same 255.3 s timeline as cold_open_master.mp3).
const COLD_OPEN_BED: String = "res://sounds/dialog/prologue/cold_open_bed.mp3"
const PROLOGUE_VO_DIR: String = "res://sounds/dialog/prologue/"

# Wall-clock anchor (ms) for the cold open, used only when the master stream fails
# to load so the beats still pace out. Real play reads the audio playhead instead.
var _cold_open_start_ms: int = 0
# True for the whole cold-open cinematic. While set, newly-built crew nametags
# spawn hidden — a cutscene carries NO floating UI labels (captions name the
# speaker instead). Flipped false at the hand-off, then crew tags are revealed.
var _cold_open_active: bool = false


# Block until the master cold-open track's PLAYHEAD reaches `t` seconds — this is how
# every visual wave + caption stays locked to the recording instead of free-running
# on tuned timers. Falls back to a wall-clock measured from _cold_open_start_ms when
# the stream is missing (so it never hangs and never over-waits cumulatively).
func _await_audio(player: AudioStreamPlayer, t: float) -> void:
	if player != null and is_instance_valid(player) and player.stream != null:
		while is_instance_valid(player) and player.playing and player.get_playback_position() < t:
			await get_tree().process_frame
		return
	var target_ms: int = int(t * 1000.0)
	while (Time.get_ticks_msec() - _cold_open_start_ms) < target_ms:
		await get_tree().process_frame


# Fire-and-forget caption cue: await the playhead to `at_t`, then subtitle the
# recording's own line (empty `line` clears the caption). Scheduling these without
# `await` lets the main flow keep pacing the visual waves while captions land on time.
func _cap(speaker: String, line: String, at_t: float, vo_id: String = "") -> void:
	var player: AudioStreamPlayer = get_node_or_null("ColdOpenMaster") as AudioStreamPlayer
	await _await_audio(player, at_t)
	if line == "":
		Cinematic.set_caption("")
		return
	GameState.add_log("%s: %s" % [speaker, line])
	Cinematic.set_caption("%s — \"%s\"" % [speaker, line])
	# Voiced line (our designed VO) on top of the ambience bed. Fire-and-forget; frees
	# itself when finished. Lines with no baked clip stay caption-only.
	if vo_id == "":
		return
	var path: String = PROLOGUE_VO_DIR + vo_id + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var vo: AudioStreamPlayer = AudioStreamPlayer.new()
	vo.name = "ColdOpenVO"
	add_child(vo)
	vo.stream = stream
	vo.finished.connect(vo.queue_free)
	vo.play()


# Turn Scott to face the (dead) gate — he's calling back through the wormhole / for Rush.
func _face_gate(scott: Node3D) -> void:
	if scott == null or not is_instance_valid(scott) or not scott.has_method("look_at"):
		return
	var pt: Vector3 = Vector3(scott.global_position.x, scott.global_position.y, GATE_Z)
	if scott.global_position.distance_to(pt) > 0.1:
		scott.look_at(pt, Vector3.UP)


# Turn Scott to face the player (Eli) — for the "Eli! NOW!" button.
func _face_player(scott: Node3D) -> void:
	if scott == null or not is_instance_valid(scott) or not scott.has_method("look_at") or _player == null:
		return
	var pt: Vector3 = Vector3(_player.global_position.x, scott.global_position.y, _player.global_position.z)
	if scott.global_position.distance_to(pt) > 0.1:
		scott.look_at(pt, Vector3.UP)


# Turn `node` to face `target` on the horizontal plane (generic version of the two above).
func _face_node(node: Node3D, target: Node3D) -> void:
	if node == null or not is_instance_valid(node) or target == null \
			or not is_instance_valid(target) or not node.has_method("look_at"):
		return
	var pt: Vector3 = Vector3(target.global_position.x, node.global_position.y, target.global_position.z)
	if node.global_position.distance_to(pt) > 0.1:
		node.look_at(pt, Vector3.UP)


# WAVE 1 (fire-and-forget): the pre-built LtScott body flies through, lands kneeling,
# rises, and turns back to the gate to wave the rest through.
func _co_wave1_scott(scott: StaticBody3D) -> void:
	scott = _throw_persistent_crew("Lt Scott", "", Vector3(2.0, 0.05, 2.0), scott)
	await get_tree().create_timer(1.6).timeout
	_settle_persistent_crew(scott, "repair")
	await get_tree().create_timer(1.1).timeout
	_rise_npc(scott, "idle")
	await get_tree().create_timer(0.5).timeout
	_face_gate(scott)
	# Scott moves toward the crew crashing onto the deck in front of the gate — the
	# "Get out of the way!" beat (the line plays at ~6 s in _play_prologue_cinematic).
	if is_instance_valid(scott) and scott.has_method("walk_to"):
		scott.call("walk_to", Vector3(1.0, 0.05, GATE_Z - 4.5), 2.6, 0.0)
		await get_tree().create_timer(2.2).timeout
		if is_instance_valid(scott) and scott.has_method("stop_walk"):
			scott.call("stop_walk")
		_face_gate(scott)


# WAVE 2 (fire-and-forget): Young thrown hardest (off-screen, stays face-down injured)
# + Lt James landing in view as the kneeling medic.
func _co_wave2(young: StaticBody3D) -> void:
	young = _throw_persistent_crew("Colonel Young", "", Vector3(-3.0, 0.05, -15.0), young)
	await get_tree().create_timer(0.35).timeout
	var james: StaticBody3D = _throw_persistent_crew("Lt James", "", Vector3(1.5, 0.05, -2.0))
	await get_tree().create_timer(2.0).timeout
	_settle_persistent_crew(young, "facedown")
	_settle_persistent_crew(james, "repair")


# COMMAND HAND-OFF (fire-and-forget): during the post-collapse hush Scott breaks for
# the downed Young, kneels to check him over, takes his "you're in charge", finds
# blood on his hand, and calls the medic — who crosses from the medic pocket. Young
# stays face-down (out cold). Subtitled against the master bed in
# _play_prologue_cinematic; this only stages the bodies. Every wait is on the audio
# playhead so it stays locked to the recording (and no-ops via the wall-clock fallback
# in headless, where the cinematic is skipped entirely).
func _co_command_handoff(scott: StaticBody3D, young: StaticBody3D) -> void:
	if not is_instance_valid(scott) or not is_instance_valid(young):
		return
	var audio: AudioStreamPlayer = get_node_or_null("ColdOpenMaster") as AudioStreamPlayer
	# Scott crosses to Young (room-left/gate-side of him) the moment the gate snuffs out.
	var beside: Vector3 = Vector3(young.global_position.x + 1.6, 0.05, young.global_position.z)
	await _await_audio(audio, 70.0)
	if is_instance_valid(scott) and scott.has_method("walk_to"):
		scott.call("walk_to", beside, 3.2, 0.0)
	# Arrive, stop, kneel beside him and check him over.
	await _await_audio(audio, 73.5)
	if is_instance_valid(scott):
		if scott.has_method("stop_walk"):
			scott.call("stop_walk")
		_face_node(scott, young)
		_rise_npc(scott, "crouch_idle")
	# Scott rocks back — blood on his hand — and stands to take charge.
	await _await_audio(audio, 84.0)
	if is_instance_valid(scott):
		_rise_npc(scott, "idle")
	# The medic breaks from the pocket to Young.
	await _await_audio(audio, 87.5)
	var james: StaticBody3D = _world.get_node_or_null("LtJames") as StaticBody3D
	if is_instance_valid(james):
		_rise_npc(james, "idle")
		if james.has_method("walk_to"):
			james.call("walk_to",
					Vector3(young.global_position.x - 1.4, 0.05, young.global_position.z), 3.4, 0.0)
		await get_tree().create_timer(2.2).timeout
		if is_instance_valid(james):
			if james.has_method("stop_walk"):
				james.call("stop_walk")
			_face_node(james, young)
			_rise_npc(james, "crouch_idle")


# A console scientist (fire-and-forget): flies through, settles low, then steps onto
# the station and faces the console at x=`console_x`, z=GATE_CONSOLE_Z.
func _co_console_crew(disp_name: String, kind: String, spot: Vector3, console_x: float) -> void:
	var n: StaticBody3D = _throw_persistent_crew(disp_name, kind, spot)
	await get_tree().create_timer(2.2).timeout
	_settle_persistent_crew(n, "crouch_idle")
	_man_console_after(n, Vector3(console_x, 0.05, GATE_CONSOLE_Z - 1.1), 1.0)


# Play a standing/working clip so a downed crew member rises to their feet. Resets
# the model upright first, so a body that was lying FACE-DOWN stands properly
# instead of playing the clip while still pitched into the deck.
func _rise_npc(npc: Node3D, clip: String = "idle") -> void:
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation = Vector3(0.0, PI, 0.0)
		model.position.y = 0.0
	var mc: Node3D = _first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)


# A body hits the metal deck — play one of the impact one-shots (round-robin,
# varied pitch) to build the panic arrival soundscape. Pool is built on first use.
func _thud() -> void:
	if _thud_streams.is_empty():
		for p: String in ["res://sounds/land.ogg", "res://sounds/fall.ogg", "res://sounds/break.ogg"]:
			var s: AudioStream = load(p) as AudioStream
			if s != null:
				_thud_streams.append(s)
		for i in 4:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.volume_db = -7.0
			add_child(pl)
			_thud_players.append(pl)
	if _thud_streams.is_empty() or _thud_players.is_empty():
		return
	var pl2: AudioStreamPlayer = _thud_players[_thud_i % _thud_players.size()]
	pl2.stream = _thud_streams[_thud_i % _thud_streams.size()]
	pl2.pitch_scale = 0.85 + 0.12 * float(_thud_i % 3)   # vary so it's not a metronome
	pl2.play()
	_thud_i += 1


# Stand a spawned NPC up after `delay` seconds (fire-and-forget coroutine).
func _stand_after(npc: Node3D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_stand_npc(npc)


# Rise a settled crew member to their feet after `delay` (plays a standing clip).
func _rise_after(npc: Node3D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_rise_npc(npc)


# Rise a settled operator, walk them onto their console `stand_pos`, then turn them
# to FACE the console (+Z, at z=GATE_CONSOLE_Z) so Park/Volker end up working their
# stations rather than standing idle. Fire-and-forget coroutine.
func _man_console_after(npc: Node3D, stand_pos: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(npc):
		return
	_rise_npc(npc, "idle")
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(npc):
		return
	if npc.has_method("walk_to"):
		npc.call("walk_to", stand_pos, 2.0, 0.0)
	# Let the short walk finish, then stop it and face the console.
	await get_tree().create_timer(2.4).timeout
	if not is_instance_valid(npc):
		return
	if npc.has_method("stop_walk"):
		npc.call("stop_walk")
	var face: Vector3 = Vector3(stand_pos.x, npc.global_position.y, GATE_CONSOLE_Z)
	if npc.global_position.distance_to(face) > 0.05:
		npc.look_at(face, Vector3.UP)
	# Drop into the two-handed "working the console" pose (the frozen typing pose
	# authored for Rush) rather than standing idle — Park/Volker man their stations.
	var mc: Node3D = _first_mc(npc)
	if mc != null and mc.has_method("pose_console_work"):
		mc.call("pose_console_work")
	else:
		_rise_npc(npc, "idle")


# Reveal a PRE-BUILT crew NPC at `pos` (where its thrown body came to rest), play
# an injured `clip`, and thud. Used for Scott, whose walk-up/talk auto-greet is
# wired on the pre-built LtScott node — so we reveal that body rather than keep
# the thrown ragdoll.
func _reveal_crew_at(node_name: String, pos: Vector3, clip: String) -> void:
	var npc: Node3D = _world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	npc.global_position = pos
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation = Vector3(0.0, PI, 0.0)
	npc.visible = true
	if "enabled" in npc:
		npc.set("enabled", true)
	var mc: Node3D = _first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)
	_thud()


# Boot both gate consoles from OFFLINE to their Ancient-glyph readout (called when
# control returns to the player). Each console holder has a gate_console.gd
# Interactable child with offline()/wake() methods.
func _wake_consoles() -> void:
	_consoles_call("wake")


# Force both consoles to a dark/offline screen (called at the cold-open start).
func _set_consoles_offline() -> void:
	_consoles_call("offline")


func _consoles_call(method: String) -> void:
	for holder_name: String in ["GateControlConsole", "FTLConsole"]:
		var holder: Node = _world.get_node_or_null(holder_name)
		if holder == null:
			continue
		var inter: Node = holder.get_node_or_null("Interactable")
		if inter != null and inter.has_method(method):
			inter.call(method)


const CRATE_SIZE: Vector3 = Vector3(1.4, 0.55, 0.85)   # footlocker: longer than wide/tall

# Ten supply crates hurled through the gate, in pairs with a short stagger, to
# open spots scattered across the room (clear of the consoles, the gate mouth, and
# the player's landing). One skids in next to Sgt Riley. Fire-and-forget.
func _launch_crate_wave() -> void:
	var spots: Array[Vector3] = [
		Vector3(2.2, 0.05, 2.4), Vector3(-2.6, 0.05, 2.0),
		Vector3(3.6, 0.05, -1.2), Vector3(-3.8, 0.05, -1.0),
		Vector3(4.0, 0.05, -6.3), Vector3(-4.4, 0.05, -5.6),   # first one lands by Sgt Riley
		Vector3(1.6, 0.05, -3.4), Vector3(-1.8, 0.05, -3.0),
		Vector3(5.2, 0.05, -3.6), Vector3(-5.4, 0.05, -3.9),
	]
	for i in range(spots.size()):
		_launch_crate(spots[i])
		await get_tree().create_timer(0.45).timeout

# Fire a supply crate out of the gate as a PROJECTILE (same reliable kinematic arc
# the crew use — a RigidBody's launch velocity gets bled/reset the same way, so we
# drive it ourselves). It tumbles through the air and lands FLAT on the deck at
# `target` (which may be on or beside a downed crewman). Returns the crate body.
func _launch_crate(target: Vector3) -> Node3D:
	var crate: StaticBody3D = StaticBody3D.new()
	crate.name = "ArrivalCrate"
	crate.collision_layer = 1           # solid once landed (player/crew can't walk through)
	crate.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = CRATE_SIZE
	cs.shape = box
	crate.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = CRATE_SIZE
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.26, 1.0)   # placeholder crate grey-brown
	mat.metallic = 0.2
	mat.roughness = 0.7
	mi.material_override = mat
	crate.add_child(mi)
	_world.add_child(crate)
	crate.global_position = Vector3(0.0, _gate_center_y(), GATE_Z - 0.4)
	_arrival_crates.append(crate)
	_fly_crate(crate, target, THROW_CRATE_FLIGHT)
	return crate


# Kinematic ballistic arc for a crate: hurls it out of the gate, tumbling in 3D,
# and lands it FLAT (rotation zeroed, resting on its base) exactly at `target`.
func _fly_crate(crate: Node3D, target: Vector3, flight: float) -> void:
	if crate == null or not is_instance_valid(crate):
		return
	var origin: Vector3 = crate.global_position
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var rest_y: float = CRATE_SIZE.y * 0.5
	var land: Vector3 = Vector3(target.x, rest_y, target.z)
	var disp: Vector3 = land - origin
	var vel: Vector3 = Vector3(disp.x / flight, (disp.y + 0.5 * g * flight * flight) / flight, disp.z / flight)
	var spin: Vector3 = Vector3(THROW_CRATE_SPIN, THROW_CRATE_SPIN * 0.35, THROW_CRATE_SPIN * 0.6)
	var rot: Vector3 = Vector3.ZERO
	var t: float = 0.0
	while t < flight and is_instance_valid(crate):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		vel.y -= g * dt
		crate.global_position += vel * dt
		rot += spin * dt
		crate.rotation = rot
		t += dt
		await get_tree().process_frame
	# Land flat on the deck at the target (settles on its base, not an edge).
	if is_instance_valid(crate):
		crate.global_position = land
		crate.rotation = Vector3.ZERO
		_thud()


# ----- cold-open arrival: roll in → get up → scramble clear -------------------

# Per-character arrival roll clips (imported Mixamo). Scott dives; mil/civ get a
# varied roll; "hard" crashes (Young, crate victims).
const ARRIVAL_ROLLS: Array[String] = ["sprint_roll", "roll_to_run", "run_roll", "falling_roll"]

func _arrival_roll_for(role: String, name_hash: int) -> String:
	match role:
		"scott": return "dive_roll"
		"hard":  return "crash"
		_:       return ARRIVAL_ROLLS[absi(name_hash) % ARRIVAL_ROLLS.size()]

# Build (or reuse `existing`) a crew body, fire it through the gate (kinematic arc),
# land it, play its assigned ROLL upright, push up with get_up, then scramble to
# `clear_spot` to dodge incoming crates. Returns the body. `role`: "scott" | "mil" |
# "civ" | "hard". A "hard" arrival stays down where it lands (crash → prone) — Young.
# `freeze` drops the body out of _process once settled (cheap nameless extras).
func _co_arrival(disp_name: String, kind: String, land_spot: Vector3, clear_spot: Vector3,
		role: String = "mil", existing: StaticBody3D = null, freeze: bool = false) -> StaticBody3D:
	# _throw_persistent_crew builds/reveals the NPC and fires the ballistic arc.
	var npc: StaticBody3D = _throw_persistent_crew(disp_name, kind, land_spot, existing)
	_co_roll_settle(npc, clear_spot, role, freeze)
	return npc


# Post-throw behaviour for an already-launched body: wait out the arc, play the ROLL
# upright, get up, and scramble to `clear_spot`. Split out so principals can grab the
# node ref from _throw_persistent_crew synchronously, then fire this and keep going.
func _co_roll_settle(npc: StaticBody3D, clear_spot: Vector3, role: String = "mil", freeze: bool = false) -> void:
	await get_tree().create_timer(THROW_FLIGHT_TIME).timeout   # let the arc land
	if npc == null or not is_instance_valid(npc):
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	var mc: Node3D = _first_mc(npc)
	var roll: String = _arrival_roll_for(role, npc.name.hash())
	# Upright the model so the roll clip drives the pose (the arc left it face-down).
	if model != null:
		model.rotation = Vector3(0.0, model.rotation.y, 0.0)
		model.position.y = 0.0
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", roll)
	_thud()
	if role == "hard":
		return   # crashed hard — stays down where it landed
	await get_tree().create_timer(0.95).timeout
	if not is_instance_valid(npc):
		return
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", "get_up")
	await get_tree().create_timer(1.0).timeout
	# Scramble to the side, out of the landing zone (dodging crates).
	if is_instance_valid(npc) and npc.has_method("walk_to"):
		npc.call("walk_to", clear_spot, 3.2, 0.0)
		await get_tree().create_timer(1.6).timeout
		if is_instance_valid(npc) and npc.has_method("stop_walk"):
			npc.call("stop_walk")
		if is_instance_valid(npc) and mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "idle")
	if freeze and is_instance_valid(npc):
		npc.set_process(false)   # settled extra — cap cost


# Continuous nameless flood: spawn civ_#/mil_# every ~`gap`s from `from_t` to `to_t`
# (playhead), each rolling in to a scattered spot then scrambling to the perimeter.
# Keeps the gate "always flowing" with ~1-2 bodies/sec. Cheap (frozen once settled).
func _co_crowd_flood(audio: AudioStreamPlayer, from_t: float, to_t: float, gap: float = 0.7) -> void:
	await _await_audio(audio, from_t)
	var i: int = 0
	var t: float = from_t
	while t < to_t and is_instance_valid(audio):
		var mil: bool = (i % 2) == 0
		var nm: String = ("mil_%d" % i) if mil else ("civ_%d" % i)
		# Scatter landings across the front half of the room; scramble to a wall.
		var sx: float = (-1.0 if (i % 2) else 1.0) * (2.0 + float(i % 5) * 0.9)
		var lz: float = GATE_Z - (3.0 + float(i % 6) * 1.4)
		var land: Vector3 = Vector3(sx * 0.5, 0.05, lz)
		var clear: Vector3 = Vector3(clampf(sx * 1.7, -8.0, 8.0), 0.05, lz - 1.5)
		_co_arrival(nm, ("greer" if mil else ""), land, clear, ("mil" if mil else "civ"), null, true)
		i += 1
		t += gap
		await _await_audio(audio, t)


# ----- cold-open crate impact: REAL RigidBody3D that HITS a victim ------------

const IMPACT_CRATE_TIME: float = 0.55     # ~flight to the victim; sets launch speed

# Hurl a REAL RigidBody crate at `victim` so it physically collides (contact-monitored).
# On first contact with the victim it fires the scripted wound reaction (`wound`:
# "arm" = clutch/limp, "head" = down + blood). The crate then tumbles/settles via
# physics. Returns the crate. Deterministic enough for a headless physics test.
func _launch_impact_crate(victim: StaticBody3D, wound: String) -> RigidBody3D:
	var crate: RigidBody3D = RigidBody3D.new()
	crate.name = "ImpactCrate"
	crate.mass = 16.0
	crate.contact_monitor = true
	crate.max_contacts_reported = 6
	crate.collision_layer = 1
	crate.collision_mask = 1 | 2          # floor, walls, and crew static bodies (layer 1)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = CRATE_SIZE
	cs.shape = box
	crate.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = CRATE_SIZE
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.24, 1.0)
	mat.metallic = 0.2
	mat.roughness = 0.7
	mi.material_override = mat
	crate.add_child(mi)
	_world.add_child(crate)
	crate.global_position = Vector3(0.0, _gate_center_y(), GATE_Z - 0.4)
	_arrival_crates.append(crate)
	if victim != null and is_instance_valid(victim):
		var aim: Vector3 = victim.global_position + Vector3(0.0, 0.95, 0.0)
		var disp: Vector3 = aim - crate.global_position
		crate.linear_velocity = disp / IMPACT_CRATE_TIME + Vector3.UP * 2.0
		crate.angular_velocity = Vector3(7.0, 2.0, 4.0)
		crate.body_entered.connect(_on_impact_crate_hit.bind(crate, victim, wound))
	return crate


func _on_impact_crate_hit(body: Node, crate: RigidBody3D, victim: StaticBody3D, wound: String) -> void:
	if body != victim or not is_instance_valid(victim):
		return
	if crate.get_meta("hit", false):
		return
	crate.set_meta("hit", true)
	_wound_crew(victim, wound)
	_thud()


# Scripted wound reaction (the crew bodies are static — physics doesn't shove them).
# "arm": clutch and go to a knee (the broken-arm marine). "head": crash flat and stay
# down with a head-wound mark (Col. Young).
func _wound_crew(victim: StaticBody3D, wound: String) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	victim.set_meta("wounded", true)
	var model: Node3D = victim.get_node_or_null("Model") as Node3D
	var mc: Node3D = _first_mc(victim)
	if wound == "head":
		if model != null:
			model.rotation = Vector3(PI * 0.5, PI, 0.0)   # face-down
			model.position.y = 0.1
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "idle")
		_add_head_blood(victim)
	else:   # "arm"
		if model != null:
			model.rotation = Vector3(0.0, model.rotation.y, 0.0)
			model.position.y = 0.0
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "crouch_idle")   # hunched, favouring the arm


# Small dark-red marker at head height to read as a head wound (placeholder VFX).
func _add_head_blood(victim: Node3D) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.get_node_or_null("HeadWound") != null:
		return
	var blood: MeshInstance3D = MeshInstance3D.new()
	blood.name = "HeadWound"
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	blood.mesh = sm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.albedo_color = Color(0.35, 0.02, 0.02, 1.0)
	bmat.roughness = 0.3
	blood.material_override = bmat
	blood.position = Vector3(0.15, 0.25, 0.0)   # near the head when face-down
	victim.add_child(blood)


const CRATE_CARRY_HEIGHT: float = 1.0     # crate ride height when two crew lift it
const CRATE_FLANK: float = 0.85           # half-gap between the two carriers

# After the crew are up, TWO-PERSON teams lift the loose crates and carry them to
# the side walls (out of the way). Crates are split round-robin across the teams;
# each team works through its share one crate at a time. Fire-and-forget.
func _carry_crates_to_edges(teams: Array) -> void:
	if teams.is_empty():
		return
	# Round-robin the crates into a per-team queue.
	var queues: Array = []
	for _t in teams:
		queues.append([])
	var i: int = 0
	for crate in _arrival_crates:
		if is_instance_valid(crate):
			queues[i % teams.size()].append(crate)
			i += 1
	for ti in range(teams.size()):
		_team_carry_loop(teams[ti], queues[ti], float(ti) * 0.8)


# One two-person team carries its whole list of crates to the walls, one at a time.
func _team_carry_loop(team: Array, crates: Array, start_delay: float) -> void:
	if team.size() < 2:
		return
	await get_tree().create_timer(start_delay).timeout
	var a: Node3D = team[0]
	var b: Node3D = team[1]
	var half_x: float = room_size.x * 0.5 - 1.6
	var idx: int = 0
	for crate in crates:
		if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
			continue
		# Stack along the wall on the crate's own side, spaced by z so they don't pile up.
		var cp: Vector3 = (crate as Node3D).global_position
		var dest: Vector3 = Vector3(signf(cp.x) * half_x, CRATE_SIZE.y * 0.5,
			clampf(cp.z + float(idx) * 0.2, -room_size.y * 0.5 + 2.0, room_size.y * 0.5 - 2.0))
		await _two_person_carry(crate as Node3D, a, b, dest)
		idx += 1


# Two crew flank `crate` (one on each side), LIFT it to carry height, walk it to
# `dest` with the crate riding the midpoint BETWEEN them the whole way, then set it
# down. Awaitable so a team carries its crates sequentially.
func _two_person_carry(crate: Node3D, a: Node3D, b: Node3D, dest: Vector3) -> void:
	if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
		return
	var cp: Vector3 = crate.global_position
	# Phase 1 — get up and walk to opposite sides of the crate (obstacle-aware walk).
	_rise_npc(a, "idle")
	_rise_npc(b, "idle")
	if a.has_method("walk_to"):
		a.call("walk_to", Vector3(cp.x - CRATE_FLANK, 0.05, cp.z), 2.3, 0.0)
	if b.has_method("walk_to"):
		b.call("walk_to", Vector3(cp.x + CRATE_FLANK, 0.05, cp.z), 2.3, 0.0)
	await get_tree().create_timer(2.0).timeout
	if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
		return
	# Phase 2 — both stop walking and hold a carry pose; lift the crate between them.
	if a.has_method("stop_walk"): a.call("stop_walk")
	if b.has_method("stop_walk"): b.call("stop_walk")
	_face(a, crate.global_position); _face(b, crate.global_position)
	_play_clip_on(a, "walk_carry"); _play_clip_on(b, "walk_carry")
	var lift: Tween = create_tween()
	lift.tween_property(crate, "global_position:y", CRATE_CARRY_HEIGHT, 0.5).set_trans(Tween.TRANS_SINE)
	await lift.finished
	# Phase 3 — manually walk both carriers to the dest flanks (manual move keeps the
	# walk_carry pose, which the NPC walker would otherwise overwrite with "walk"),
	# crate tracking their midpoint at carry height.
	var da: Vector3 = Vector3(dest.x - CRATE_FLANK, 0.05, dest.z)
	var db: Vector3 = Vector3(dest.x + CRATE_FLANK, 0.05, dest.z)
	var speed: float = 1.5
	var t: float = 0.0
	while t < 6.0 and is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		var travel: Vector3 = (da - a.global_position); travel.y = 0.0
		a.global_position = a.global_position.move_toward(Vector3(da.x, 0.05, da.z), speed * dt)
		b.global_position = b.global_position.move_toward(Vector3(db.x, 0.05, db.z), speed * dt)
		if travel.length() > 0.05:
			_face(a, da); _face(b, db)
		var mid: Vector3 = (a.global_position + b.global_position) * 0.5
		crate.global_position = Vector3(mid.x, CRATE_CARRY_HEIGHT, mid.z)
		t += dt
		if a.global_position.distance_to(Vector3(da.x, 0.05, da.z)) < 0.25 \
				and b.global_position.distance_to(Vector3(db.x, 0.05, db.z)) < 0.25:
			break
		await get_tree().process_frame
	# Phase 4 — set the crate down at the wall; carriers stand off.
	if is_instance_valid(crate):
		var down: Tween = create_tween()
		down.tween_property(crate, "global_position", Vector3(dest.x, CRATE_SIZE.y * 0.5, dest.z), 0.5).set_trans(Tween.TRANS_SINE)
		await down.finished
	if is_instance_valid(a): _play_clip_on(a, "idle")
	if is_instance_valid(b): _play_clip_on(b, "idle")


# Face a crew body toward a world point (model holder convention handled by look_at).
func _face(npc: Node3D, target: Vector3) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var flat: Vector3 = Vector3(target.x, npc.global_position.y, target.z)
	if npc.global_position.distance_to(flat) > 0.05:
		npc.look_at(flat, Vector3.UP)


# Play a body clip on an NPC's ModularCharacter (no orientation reset, unlike _rise_npc).
func _play_clip_on(npc: Node3D, clip: String) -> void:
	var mc: Node3D = _first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)


# Hand a flying-through ragdoll off to a PRE-BUILT, PRE-POSED tableau NPC (Young
# prone): reposition the NPC to its expected landing spot, reveal it, then free
# the ragdoll the SAME frame so the body appears to settle into the character (no
# vanish). Keeps the NPC's authored pose.
func _handoff_tableau(rag: Node3D, node_name: String, pos: Vector3) -> void:
	var npc: Node3D = _world.get_node_or_null(node_name) as Node3D
	if npc != null:
		npc.global_position = pos
		npc.visible = true
		if "enabled" in npc:
			npc.set("enabled", true)
	if is_instance_valid(rag):
		rag.queue_free()


# Spawn a recovered crew NPC face-down at `pos` (where their ragdoll landed),
# visible immediately. Returns the node so the caller can stand it up later.
func _spawn_crew_prone(display_name: String, kind: String, pos: Vector3) -> StaticBody3D:
	var npc: StaticBody3D = _build_returned_crew_npc(
		display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
	var tree: Variant = npc.get("dialogue_tree")
	if tree == null or (tree is Array and (tree as Array).is_empty()):
		var generic: Array = [{"speaker": display_name,
			"text": "Still shaking that off. Give me a second.",
			"choices": [{"text": "(nod)", "next": "exit"}]}]
		npc.set("dialogue_tree", generic)
		npc.set("repeat_dialogue_tree", generic)
	npc.position = pos
	npc.rotation.y = 0.0
	_world.add_child(npc)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-down
		model.position.y = 0.1
	return npc


# Stand a spawned NPC up (groggy, unsteady) — push up from face-down.
func _stand_npc(npc: Node3D) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(model, "rotation:x", 0.0, 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 1.8)


# Move the player rig to its WAVE-2 landing spot, lay it prone, and hide the body
# until the ragdoll toss "delivers" Eli there.
func _place_player_for_toss(spot: Vector3) -> void:
	if _player == null:
		return
	_player.global_position = spot
	_lay_player_prone(true)
	_show_player_model(false)


func _show_player_model(vis: bool) -> void:
	if _player == null:
		return
	var model: Node = _player.get_node_or_null("Character")
	if model is Node3D:
		(model as Node3D).visible = vis


func _reveal_crew_member(node_name: String) -> void:
	var n: Node = _world.get_node_or_null(node_name)
	if n is Node3D:
		(n as Node3D).visible = true


# Move a persistent NPC to `pos` and tip its Model node prone (rotation.x = -PI*0.5),
# then make it visible. Used by Wave 1 so Scott crumples at his ragdoll rest spot
# before standing up a moment later via _stand_crew_member.
func _place_crew_prone(node_name: String, pos: Vector3) -> void:
	var npc: Node3D = _world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	npc.global_position = pos
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1
	npc.visible = true


# Tween a persistent NPC's Model node from prone back to upright (same tween
# as _lay_player_prone(false)). Used after _place_crew_prone to animate standing.
func _stand_crew_member(node_name: String) -> void:
	var npc: Node3D = _world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(model, "rotation:x", 0.0, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 1.1)


# After the crew have landed and lain there, they recover: Dr Park and Dr Volker
# pick themselves up (staggered) and walk over to man the two operator consoles;
# Rush and Brody also get up (later) and file out the exit corridor.
# Young stays permanently prone (injured); James stays kneeling (no walker for them).
# `rest_positions` maps character name → ragdoll rest position on the floor.
func _recover_crew(rest_positions: Dictionary) -> void:
	var half_z: float = room_size.y * 0.5
	# Stand the operators just in front of the ROOM's real consoles (GateControlConsole
	# at x=-3.5, FTLConsole at x=+3.5, both at z=GATE_CONSOLE_Z), on the arrival (-Z)
	# side where the controls face, looking back at the console.
	var console_l: Vector3 = Vector3(-3.5, 0.05, GATE_CONSOLE_Z - 1.1)   # GateControlConsole
	var console_r: Vector3 = Vector3(3.5, 0.05, GATE_CONSOLE_Z - 1.1)    # FTLConsole
	var exit_pos: Vector3 = Vector3(0.0, 0.05, -half_z + 3.2)    # toward the corridor door
	# All four walkers are called without await so they run as concurrent coroutines.
	# get_up_delay staggers when each one starts standing up — long, uneven gaps so
	# the crew read as dazed and disoriented, picking themselves up one at a time.
	_recover_walker("Dr Park",  "park",  rest_positions.get("Dr Park",  console_l), console_l, false, 1.6)
	_recover_walker("Dr Volker","volker",rest_positions.get("Dr Volker",console_r), console_r, false, 3.0)
	_recover_walker("Dr Rush",  "rush",  rest_positions.get("Dr Rush",  exit_pos),  exit_pos,  true,  4.4)
	_recover_walker("Dr Brody", "brody", rest_positions.get("Dr Brody", exit_pos),  exit_pos,  true,  5.6)


# Spawn one recovered crew member at where they landed, crumpled on the floor.
# After `get_up_delay` seconds they groggily stand, then walk to their post.
# `leave` = true means they're heading out (despawn once they reach the corridor);
# false means they stay (e.g. manning a console). Multiple callers fire this
# concurrently (no await in _recover_crew), so each walker is its own coroutine.
func _recover_walker(display_name: String, kind: String, from: Vector3, to: Vector3,
		leave: bool, get_up_delay: float = 0.0) -> void:
	var npc: StaticBody3D = _build_returned_crew_npc(
		display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
	# Anyone the returned-crew builder didn't author a line for gets a placeholder
	# so interacting can't error.
	var tree: Variant = npc.get("dialogue_tree")
	if tree == null or (tree is Array and (tree as Array).is_empty()):
		var generic: Array = [{"speaker": display_name,
			"text": "Still shaking that off. Give me a second.",
			"choices": [{"text": "(nod)", "next": "exit"}]}]
		npc.set("dialogue_tree", generic)
		npc.set("repeat_dialogue_tree", generic)
	npc.position = from
	npc.rotation.y = 0.0
	# Lay prone before adding to tree so the first visible frame is crumpled.
	_world.add_child(npc)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1

	# Stagger: wait for this character's personal get-up timer.
	await get_tree().create_timer(get_up_delay).timeout
	if not is_instance_valid(npc):
		return

	# Stand up groggily — a slow, unsteady push to the feet (disoriented).
	model = npc.get_node_or_null("Model") as Node3D
	if model != null and is_instance_valid(model):
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(model, "rotation:x", 0.0, 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(model, "position:y", 0.0, 1.8)
	await get_tree().create_timer(1.8).timeout   # wait for stand tween to complete
	if not is_instance_valid(npc):
		return

	# Now walk to post.
	if npc.has_method("walk_to"):
		npc.call("walk_to", to, 2.4, 0.0)
	if leave:
		# Walked off down the corridor — remove once they've had time to reach it.
		await get_tree().create_timer(6.0).timeout
		if is_instance_valid(npc):
			npc.queue_free()


# Launch one throwaway ragdoll on a ballistic arc from the event horizon toward a
# landing spot (so Young can be thrown demonstrably farther than Eli). The body's
# PhysicalBone3D bones ARE the physics — they fall under their own gravity and
# carry the launch velocity, tumbling limb-by-limb. The root Node3D stays at the
# gate (the bones move in world space), so read the landed spot from the hips bone
# via _ragdoll_rest_pos(). Returns the root so the caller can free it once settled.
func _launch_ragdoll(character: String, target: Vector3) -> Node3D:
	var root: Node3D = _make_ragdoll(character)
	_world.add_child(root)
	# Position the body at the event-horizon mouth BEFORE building the bones so they
	# start simulating from the correct world position.
	var origin: Vector3 = Vector3(0.0, _gate_center_y(), GATE_Z - 0.4)
	root.global_position = origin
	# Ballistic solve: reach target.y at t=flight under gravity.
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var flight: float = 1.8
	var disp: Vector3 = target - origin
	var vy: float = (disp.y + 0.5 * g * flight * flight) / flight
	var launch_vel: Vector3 = Vector3(disp.x / flight, vy, disp.z / flight)
	# Hard tumble — magnitude scales with throw distance (deterministic, no RNG).
	var spin: float = 4.0 + absf(disp.z) * 0.6
	var launch_ang: Vector3 = Vector3(spin, spin * 0.5, spin * 0.7)
	# Build the physical skeleton and start it WITH the launch velocity in the same
	# frame, so every bone leaves the gate on one arc (no 1-frame free-fall gap).
	_setup_ragdoll_physics(root, launch_vel, launch_ang)
	return root


# The RagdollSim simulator under a ragdoll root (or null).
func _ragdoll_sim(root: Node3D) -> PhysicalBoneSimulator3D:
	var model: Node3D = root.get_node_or_null("Model")
	if model == null:
		return null
	var mc: Node3D = null
	for c: Node in model.get_children():
		mc = c as Node3D
		break
	if mc == null:
		return null
	var skel: Skeleton3D = _find_skel_in_mc(mc)
	if skel == null:
		return null
	return skel.get_node_or_null("RagdollSim") as PhysicalBoneSimulator3D


# Where the ragdoll actually came to rest — the hips bone's world position (the
# root never moves; only the bones do). Falls back to the root position.
func _ragdoll_rest_pos(root: Node3D) -> Vector3:
	var sim: PhysicalBoneSimulator3D = _ragdoll_sim(root)
	if sim != null:
		var hips: Node = sim.get_node_or_null("PB_Hips")
		if hips is Node3D:
			var p: Vector3 = (hips as Node3D).global_position
			return Vector3(p.x, 0.05, p.z)
	return Vector3(root.global_position.x, 0.05, root.global_position.z)


# Toggle Lt Scott's walk-up auto-greet (held off during the cold open so the
# dialog camera can't hijack the cinematic; released once Eli is on his feet).
func _set_scott_autogreet(on: bool) -> void:
	var scott: Node = _world.get_node_or_null("LtScott")
	if scott == null:
		return
	if on:
		if not GameState.met_scott:
			# CRITICAL: disabling auto_greet earlier made npc._process turn ITSELF off
			# (`not auto_greet` → set_process(false)). Just flipping the flag back on
			# won't restart the walk — reset the greet state AND re-enable _process, or
			# Scott stands frozen and never comes over to brief the player.
			scott.set("auto_greet", true)
			scott.set("_auto_greet_done", false)
			scott.set("_auto_greet_t", 0.0)
			scott.set_process(true)
	else:
		scott.set("auto_greet", false)


# Temp head-on Camera3D under the room, made current for the cold open. The
# player's SpringArm camera is restored by _restore_player_camera(). The camera
# starts closer on the gate and DOLLIES BACK (pulls out) across the cinematic,
# revealing the whole cavernous room as the crew scatter across it — no shake.
func _make_cinematic_camera() -> Camera3D:
	var cam: Camera3D = Camera3D.new()
	cam.name = "PrologueCam"
	cam.fov = 62.0
	add_child(cam)
	# Start closer on the gate; pull BACK (z more negative = away from the gate =
	# zoom OUT) over the cinematic, ending shy of the rear mezzanine (z≈-11.8) so the
	# camera stays in the open and doesn't clip the back balcony deck.
	var start_z: float = GATE_Z - 19.0
	var end_z: float = GATE_Z - 24.0
	cam.global_position = Vector3(0.0, 5.5, start_z)
	cam.look_at(Vector3(0.0, 1.4, GATE_Z - 9.0), Vector3.UP)
	cam.make_current()
	var t: Tween = create_tween()
	t.tween_property(cam, "global_position:z", end_z, 88.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return cam


func _restore_player_camera(cam: Camera3D) -> void:
	var pcam: Camera3D = get_node_or_null("View/SpringArm/Camera")
	if pcam != null:
		pcam.make_current()
		if _view != null and _view.has_method("snap_to_target"):
			_view.snap_to_target()
	if cam != null and is_instance_valid(cam):
		cam.queue_free()


# ----- cold-open camera cuts (cut-to-speaker) + FTL jump ----------------------

const StandoffCameraScript: Script = preload("res://scripts/standoff_camera.gd")
var _cut_cam: Node = null   # active StandoffCamera during the verbatim cold open

# Spin up the cut camera (captures whatever camera is current for restore).
func _begin_cuts() -> void:
	if _cut_cam != null and is_instance_valid(_cut_cam):
		return
	_cut_cam = StandoffCameraScript.new()
	_cut_cam.name = "ColdOpenCutCam"
	add_child(_cut_cam)
	if _cut_cam.has_method("configure"):
		_cut_cam.call("configure", 50.0, 0.0)   # centred framing (no dialog window to dodge)
	if _cut_cam.has_method("activate"):
		_cut_cam.call("activate")

# Hard-cut/glide to frame `node` (the speaker). side/height/dist compose the shot.
func _cut_to(node: Node3D, dist: float = 3.4, height: float = 1.5, side: float = 1.6, dur: float = 0.6) -> void:
	if _cut_cam == null or not is_instance_valid(_cut_cam) or node == null or not is_instance_valid(node):
		return
	var look: Vector3 = node.global_position + Vector3.UP * 1.4
	var pos: Vector3 = node.global_position + Vector3(side, height, dist)
	if _cut_cam.has_method("frame"):
		_cut_cam.call("frame", pos, look, dur, 0.05)

# Track a moving subject (Scott crossing, TJ crossing in).
func _cut_follow(node: Node3D, offset: Vector3 = Vector3(1.6, 1.5, 3.0), dur: float = 0.6) -> void:
	if _cut_cam == null or not is_instance_valid(_cut_cam) or node == null or not is_instance_valid(node):
		return
	if _cut_cam.has_method("follow"):
		_cut_cam.call("follow", node, offset, dur, 1.4)

# Wide establishing shot of the gate/landing zone.
func _cut_wide(dur: float = 1.0) -> void:
	if _cut_cam == null or not is_instance_valid(_cut_cam):
		return
	var pos: Vector3 = Vector3(0.0, 5.5, GATE_Z - 20.0)
	var look: Vector3 = Vector3(0.0, 1.4, GATE_Z - 8.0)
	if _cut_cam.has_method("frame"):
		_cut_cam.call("frame", pos, look, dur, 0.02)

func _end_cuts() -> void:
	if _cut_cam != null and is_instance_valid(_cut_cam):
		if _cut_cam.has_method("release"):
			_cut_cam.call("release")
		_cut_cam.queue_free()
	_cut_cam = null

# The FTL jump: the ship lurches into faster-than-light. Repeated LEFT-RIGHT shake
# (shake_y_scale low) + box-blur over the whole world, with the jump whoosh. Spawns
# the FtlDrop overlay directly (NOT GameState.trigger_ftl_drop, which is gated on the
# later air-crisis state) so it's purely a cold-open visual.
const FTL_JUMP_SOUND_COLDOPEN: String = "res://sounds/ftl_jump_destiny.ogg"

func _ftl_jump() -> void:
	var fx: FtlDrop = FtlDrop.new()
	fx.sound_path = FTL_JUMP_SOUND_COLDOPEN   # enhanced Destiny FTL-jump whoosh
	fx.shake_y_scale = 0.2   # bias to a repeated left-right jolt
	get_tree().root.add_child(fx)


# Tip the player's visual body onto its back (prone) or stand it upright. Only
# the Character model is rotated — the physics capsule stays vertical so nothing
# downstream (camera target, idle facing) is disturbed.
func _lay_player_prone(prone: bool) -> void:
	if _player == null:
		return
	var model: Node3D = _player.get_node_or_null("Character")
	if model == null:
		return
	if prone:
		# Snap flat instantly (Eli is already down when the scene opens).
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1
	else:
		# Groggily push up to standing — slow and unsteady (disoriented).
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(model, "rotation:x", 0.0, 1.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(model, "position:y", 0.0, 1.9)


# One throwaway ragdoll: RigidBody3D root wrapper + Quaternius skeletal body.
# NOTE: the skeleton + PhysicalBone3D setup is deferred to _setup_ragdoll_physics,
# which _launch_ragdoll calls after _world.add_child(rb) so that mc._ready() has
# fired (ModularCharacter._ready builds _skel and the base gltf). If called before
# the node is in the scene tree, mc._ready() does not fire, _skel stays null,
# and _find_skel_in_mc returns null — hence the two-phase design.
func _make_ragdoll(character: String) -> Node3D:
	# Static root — the bones (PhysicalBone3D) own all motion in world space, so the
	# root just anchors the initial pose at the gate mouth and never moves itself.
	var root: Node3D = Node3D.new()
	root.name = "Ragdoll_" + character.replace(" ", "")
	root.set_meta("ragdoll_character", character)

	# Visual + skeleton holder. The crew were RUNNING when the gate flung them
	# through, so they enter DIVING HEAD-FIRST: pitch the body forward to near-
	# horizontal (head leading toward the room, -Z) — the limbs then flail behind
	# under the launch (torso gets the speed, limbs trail; see _setup_ragdoll_physics).
	var holder: Node3D = Node3D.new()
	holder.name = "Model"
	holder.rotation = Vector3(-PI * 0.5, PI, 0.0)
	root.add_child(holder)

	# Build the Quaternius modular body and attach it. mc._ready() fires once root
	# is added to _world (in _launch_ragdoll), populating its Skeleton3D.
	var mc: Node3D = CharacterFactoryRef.build_modular(character)
	if mc != null:
		holder.add_child(mc)
		CharacterFactoryRef.dress_modular(mc, character, CharacterFactoryRef.CTX_SHIP)
	return root


# Build the PhysicalBoneSimulator3D + 13 PhysicalBone3D limbs under the body's
# Skeleton3D, start the simulation, and impart the launch velocity to every bone
# in the SAME frame so the whole skeleton leaves the gate on one ballistic arc and
# tumbles limb-by-limb. Called after _world.add_child(root) so mc._ready() has fired.
func _setup_ragdoll_physics(root: Node3D, vel: Vector3, ang: Vector3) -> void:
	var model: Node3D = root.get_node_or_null("Model")
	if model == null:
		return
	var mc: Node3D = null
	for c: Node in model.get_children():
		mc = c as Node3D
		break
	if mc == null:
		return

	# mc._ready() has fired (root is in the tree) → _skel is populated. Stop the
	# autoplay so bones start from the rest pose, not mid-walk.
	_stop_anim(mc)

	var skel: Skeleton3D = _find_skel_in_mc(mc)
	if skel == null:
		var char_name: String = String(root.get_meta("ragdoll_character", "?"))
		push_warning("_setup_ragdoll_physics: Skeleton3D not found for '%s'" % char_name)
		return

	# Create the PhysicalBoneSimulator3D as a direct child of the Skeleton3D.
	# Godot resolves bone IDs via Skeleton3D → PhysicalBoneSimulator3D → PhysicalBone3D.
	var sim: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSim"
	skel.add_child(sim)

	# --- Major bones with capsule sizes for Quaternius humanoid proportions ---
	# Base model is ~1.85 m at default scale; sizes are in world-space metres.
	# collision_layer=0 → bones are not hittable by raycasts.
	# collision_mask=1 → bones collide with floor/walls (layer 1), not player (layer 2).
	# Torso chain.
	# Torso chain — TIGHT swing/twist so the spine can't fold backwards at the waist.
	_make_physical_bone(sim, "Hips",       0.15, 0.30, PhysicalBone3D.JOINT_TYPE_CONE, 18.0, 12.0)
	_make_physical_bone(sim, "Spine",      0.13, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 18.0, 12.0)
	_make_physical_bone(sim, "Chest",      0.14, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 16.0, 12.0)
	_make_physical_bone(sim, "UpperChest", 0.13, 0.22, PhysicalBone3D.JOINT_TYPE_CONE, 16.0, 12.0)
	_make_physical_bone(sim, "Head",       0.12, 0.24, PhysicalBone3D.JOINT_TYPE_CONE, 30.0, 20.0)
	# Arms — shoulders swing wide, elbows are one-way hinges.
	_make_physical_bone(sim, "LeftUpperArm",  0.07, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 70.0, 30.0)
	_make_physical_bone(sim, "RightUpperArm", 0.07, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 70.0, 30.0)
	_make_physical_bone(sim, "LeftLowerArm",  0.06, 0.26, PhysicalBone3D.JOINT_TYPE_HINGE)
	_make_physical_bone(sim, "RightLowerArm", 0.06, 0.26, PhysicalBone3D.JOINT_TYPE_HINGE)
	# Legs — hips swing moderately, knees are one-way hinges.
	_make_physical_bone(sim, "LeftUpperLeg",  0.10, 0.38, PhysicalBone3D.JOINT_TYPE_CONE, 50.0, 20.0)
	_make_physical_bone(sim, "RightUpperLeg", 0.10, 0.38, PhysicalBone3D.JOINT_TYPE_CONE, 50.0, 20.0)
	_make_physical_bone(sim, "LeftLowerLeg",  0.08, 0.36, PhysicalBone3D.JOINT_TYPE_HINGE)
	_make_physical_bone(sim, "RightLowerLeg", 0.08, 0.36, PhysicalBone3D.JOINT_TYPE_HINGE)

	# Log any bones that failed to resolve — silent failure = no per-bone tumble.
	var char_name2: String = String(root.get_meta("ragdoll_character", "?"))
	for pb_child: Node in sim.get_children():
		if pb_child is PhysicalBone3D:
			var pb: PhysicalBone3D = pb_child as PhysicalBone3D
			if pb.get_bone_id() < 0:
				push_warning("_setup_ragdoll_physics: bone '%s' unresolved for '%s'" % [pb.bone_name, char_name2])

	# Start the per-bone physics simulation, then impart the throw. EVERY bone gets
	# the full launch velocity so the body's centre of mass reaches the aimed spot
	# (no undershoot/clustering). The head-first DIVE orientation (set in _make_
	# ragdoll) makes it enter head-first; the limbs get extra spin so the arms and
	# legs FLAIL behind during the flight (running-through-the-gate look).
	var lead_bones := {"Hips": true, "Spine": true, "Chest": true, "UpperChest": true, "Head": true}
	sim.physical_bones_start_simulation()
	for pb_child2: Node in sim.get_children():
		if pb_child2 is PhysicalBone3D:
			var pb2: PhysicalBone3D = pb_child2 as PhysicalBone3D
			pb2.linear_velocity = vel
			if lead_bones.has(pb2.bone_name):
				pb2.angular_velocity = ang
			else:
				pb2.angular_velocity = ang * 1.3   # limbs flail (modest — too much bleeds travel)


# Recursive depth-first search for the Skeleton3D inside a ModularCharacter node.
# ModularCharacter.skeleton() returns _skel if mc has already entered the tree
# (its _ready has fired). Falling back to a recursive walk handles edge cases where
# the method is unavailable or returns null.
func _find_skel_in_mc(mc: Node3D) -> Skeleton3D:
	if mc.has_method("skeleton"):
		var s: Variant = mc.call("skeleton")
		if s is Skeleton3D:
			return s as Skeleton3D
	var stack: Array = [mc as Node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n as Skeleton3D
		for c: Node in n.get_children():
			stack.append(c)
	return null


# Create one PhysicalBone3D child of `sim`, assigned to `p_bone_name` on the
# parent Skeleton3D, with a CapsuleShape3D collider. collision_layer=0 so the
# bone is not a hittable target; collision_mask=1 so it reacts to floor/walls.
func _make_physical_bone(
		sim: PhysicalBoneSimulator3D,
		p_bone_name: String,
		cap_radius: float,
		cap_height: float,
		j_type: int,
		swing_deg: float = 40.0,
		twist_deg: float = 25.0) -> PhysicalBone3D:
	var pb: PhysicalBone3D = PhysicalBone3D.new()
	pb.name = "PB_" + p_bone_name
	pb.bone_name = p_bone_name
	pb.joint_type = j_type
	pb.collision_layer = 0
	pb.collision_mask = 1
	pb.mass = 4.0
	# Heavier damping so the body settles into a believable heap instead of
	# flailing/jittering into broken-looking poses.
	pb.linear_damp = 1.2
	pb.angular_damp = 2.0
	# Joint limits keep the body in a HUMAN range of motion — no folding backwards
	# at the waist or hyperextending elbows/knees (joint_constraints spans are in
	# degrees on PhysicalBone3D).
	if j_type == PhysicalBone3D.JOINT_TYPE_CONE:
		pb.set("joint_constraints/swing_span", swing_deg)
		pb.set("joint_constraints/twist_span", twist_deg)
		pb.set("joint_constraints/relaxation", 1.0)
	elif j_type == PhysicalBone3D.JOINT_TYPE_HINGE:
		# Elbows/knees bend ONE way only (toward the body), never backwards.
		pb.set("joint_constraints/angular_limit_enabled", true)
		pb.set("joint_constraints/angular_limit_lower", -120.0)
		pb.set("joint_constraints/angular_limit_upper", 2.0)
	var bone_cs: CollisionShape3D = CollisionShape3D.new()
	var bone_cap: CapsuleShape3D = CapsuleShape3D.new()
	bone_cap.radius = cap_radius
	bone_cap.height = cap_height
	bone_cs.shape = bone_cap
	pb.add_child(bone_cs)
	sim.add_child(pb)
	return pb


# Halt the first AnimationPlayer under `root` so a tumbling ragdoll body stays
# limp (no walking/idle motion fighting the physics tumble).
func _stop_anim(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			(n as AnimationPlayer).stop()
			return
		for c in n.get_children():
			stack.append(c)


# Shut the wormhole: drop the forced-open latch, kill the horizon, play the
# collapse whoosh + fade the dial loop. Returns the room to its dormant, empty,
# walk-through state for normal gameplay.
func _collapse_gate() -> void:
	_gate_forced_open = false
	_light_chevrons(0)
	if _stargate != null and "active" in _stargate:
		_stargate.active = false
	if _gate_hum_sfx != null and _gate_hum_sfx.playing:
		_gate_hum_sfx.stop()
	if _gate_loop_sfx != null and _gate_loop_sfx.playing:
		var t: Tween = create_tween()
		t.tween_property(_gate_loop_sfx, "volume_db", -60.0, arrival_fade)
		t.tween_callback(Callable(_gate_loop_sfx, "stop"))
	if _gate_shutdown_sfx != null and _gate_shutdown_sfx.stream != null:
		_gate_shutdown_sfx.play()


# Show/hide the crew that arrive through the gate during the cold open, so the
# ragdoll burst isn't pre-empted by them standing at their posts.
# When showing (vis=true) LtScott is excluded — he was already revealed and
# stood up in Wave 1 via _place_crew_prone / _stand_crew_member, so re-showing
# him here would reset his position to the authored spawn spot.
func _set_arrival_crew_visible(vis: bool) -> void:
	var names: Array = ["LtScott", "ColonelYoung", "LtJames", "GateBrody", "GateRush", "GatePark"]
	for node_name in names:
		if vis and node_name == "LtScott":
			continue   # Scott is already positioned by Wave 1 — skip
		var n: Node = _world.get_node_or_null(node_name)
		if n is Node3D:
			(n as Node3D).visible = vis

func _build_ship_gate_portal() -> void:
	_gate_portal = Area3D.new()
	_gate_portal.set_script(PLANET_GATE_SCRIPT)
	_gate_portal.name = "ShipGatePortal"
	# Center the interaction volume inside the floor-pinned ring's opening so the
	# player steps "into" the puddle naturally while walking through at floor level.
	_gate_portal.position = Vector3(0.0, _gate_center_y(), GATE_Z)
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
	# A cinematic/dial may force the gate open (e.g. the prologue wormhole the crew
	# tumble through) independent of the story's is_gate_open() flags.
	var gate_open: bool = GameState.is_gate_open() or _gate_forced_open
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
	# Line them up on the deck just in front of the floor-pinned gate.
	var gate_z: float = room_size.y * 0.5 - 3.8
	var line_z: float = gate_z - 2.4         # a couple metres south of the event horizon
	var line_y: float = 0.05                 # main floor (no dais now)
	# Roster order matches the planet-side spawn (Greer left, Park centre,
	# Scott right) and the cutscene's group "away_team" muster. Appearance
	# (models, fatigues, Greer's skin tone) comes from CharacterFactory.
	var roster: Array = [
		{"name": "Greer", "glb": "res://models/characters/greer.glb", "x": -1.6},
		{"name": "Park", "glb": "res://models/characters/park.glb", "x": 0.0},
		{"name": "Lt Scott", "glb": "res://models/characters/scott.glb", "x": 1.6},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var c: Node3D = CompanionScript.new()
		c.name = "GateTeam_" + String(entry["name"]).replace(" ", "")
		c.set("stationary", true)
		_world.add_child(c)
		c.position = Vector3(float(entry["x"]), line_y, line_z)
		c.rotation.y = 0.0    # model holder is internally flipped 180° → visible front faces +Z (the gate)
		c.call("setup", String(entry["name"]), String(entry["glb"]), i)
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
	# Spawn line: on the deck a couple metres in front of the gate. Home line: down
	# on the main floor, gate-side of the FromPlanet landing. Appearance from CF.
	var gate_z: float = room_size.y * 0.5 - 3.8
	var spawn_z: float = gate_z - 2.4               # just in front of the ring
	var home_z: float = room_size.y * 0.5 - 10.5    # main floor (y≈0.05)
	var roster: Array = [
		{"name": "Greer", "glb": "res://models/characters/greer.glb", "tint": Color.WHITE, "x": -2.4, "kind": "greer"},
		{"name": "Park", "glb": "res://models/characters/park.glb", "tint": Color.WHITE, "x": 0.0, "kind": "park"},
		{"name": "Lt Scott", "glb": "res://models/characters/scott.glb", "tint": Color.WHITE, "x": 2.4, "kind": "scott"},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var npc: StaticBody3D = _build_returned_crew_npc(
			String(entry["name"]), String(entry["kind"]),
			String(entry["glb"]), entry["tint"])
		# Stand in front of the gate facing the room (-Z forward), then stroll to the
		# home post. rotation.y=0 → -Z forward (toward the player landing south).
		npc.position = Vector3(float(entry["x"]), 0.05, spawn_z)
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
# Nameless crowd built by _co_crowd_flood: internal ids, not characters to label.
func _is_anonymous_extra(display_name: String) -> bool:
	return display_name.begins_with("mil_") or display_name.begins_with("civ_")


# Show/hide every crew nametag in the room at once. Used to strip floating UI
# labels for the duration of the cold-open cinematic and restore them at the
# hand-off (so gameplay can still ID Scott/Greer across the room).
func _set_crew_nametags_visible(vis: bool) -> void:
	if _world == null:
		return
	for tag in _world.find_children("Nametag", "Label3D", true, false):
		if tag is Label3D:
			(tag as Label3D).visible = vis


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

	# Visual body — flipped 180° (models export +Z forward).
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.rotation.y = PI
	body.add_child(model_holder)
	if CharacterFactoryRef.profile_for(display_name).has("mod"):
		var mc: Node3D = CharacterFactoryRef.build_modular(display_name)
		model_holder.add_child(mc)
		# Back aboard: ship dress code (duty tint + sidearm for military).
		CharacterFactoryRef.dress_modular(mc, display_name, CharacterFactoryRef.CTX_SHIP)
	else:
		model_holder.scale = Vector3(2.6, 2.6, 2.6)
		var glb: PackedScene = load(CharacterFactoryRef.model_for(display_name, glb_path))
		if glb != null:
			var inst: Node = glb.instantiate()
			model_holder.add_child(inst)
			Npc.play_idle_animation(inst)
		CharacterFactoryRef.dress(body, model_holder, display_name, CharacterFactoryRef.CTX_SHIP)
		if tint != Color.WHITE:
			# Legacy per-instance tint for unregistered characters.
			_tint_kenney_model(model_holder, tint)

	# Anonymous flood extras (mil_#/civ_#) are nameless crowd — never stamp their
	# internal id over their head (the "mil_22 floating over an extra" cinematic
	# tell). Named crew get a tag, but it spawns hidden during the cold open.
	if not _is_anonymous_extra(display_name):
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
		tag.visible = not _cold_open_active
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
	# Cold open: no quest marker until Lt Scott has come over and talked to us
	# (that conversation is a guaranteed trigger — he walks up on his own). The
	# first quest + its diamond only appear AFTER that beat (met_scott).
	if not GameState.met_scott:
		_destroy_quest_waypoint()
		return

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
	# (Removed the glowing blue floor inlay ring around the gate — it read as a
	# stray hexagon on the deck. The floor is clean grating now.)


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

	# Edge glow strips — emissive boxes hugging the top of every wall. Cool blue
	# to match the reference's icy industrial lighting (was warm amber).
	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.30, 0.55, 0.95, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.32, 0.58, 1.0, 1.0)
	glow_mat.emission_energy_multiplier = 2.6
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
	_world.add_child(mi)

# Runtime-load a prop scene with a null guard + one-time cache. Returns null if
# the asset is missing or not yet imported, so a single bad prop can never take
# the whole gate-room scene down with a parse/preload error.
func _prop_scene(path: String) -> PackedScene:
	if _prop_cache.has(path):
		return _prop_cache[path]
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		push_warning("gate_room: prop failed to load (run `godot --headless --import`?): " + path)
	_prop_cache[path] = ps
	return ps


# Instantiate a hero prop by path, or null if it couldn't load. The caller is
# responsible for positioning/scaling and adding it to the tree.
func _instance_prop(path: String) -> Node3D:
	var ps: PackedScene = _prop_scene(path)
	if ps == null:
		return null
	return ps.instantiate() as Node3D


# Helper for the new hero props: attach a trimesh StaticBody collider so the
# player can walk on the raised platform and (critically) the real metal
# staircase steps without having to jump the base of the gate.
func _add_prop_collider(parent: Node3D) -> void:
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
	# The gate is now a floor-pinned, walk-through ring (NO dais, NO stairs) — the
	# user can walk straight through it without jumping. We keep only the framing
	# furniture from the hero prop pack: flanking operator consoles, the overhead
	# ceiling ring, and the cinematic spotlights, all matching the concept art.
	var half_z: float = room_size.y * 0.5
	var platform_z: float = half_z - 3.8

	# (Removed the extra prop operator-consoles that flanked the gate — the room's
	# real consoles are GateControlConsole + FTLConsole, built by _build_consoles().
	# Park & Volker man those.)

	# === Overhead ceiling ring structure (dramatic circular architecture above gate) ===
	# Native disc normal points along X (AABB thin on X); rotate 90° about Z so the
	# face points up and the ring lies flat against the ceiling above the gate.
	var overhead: Node3D = _instance_prop(OVERHEAD_RING_PROP_PATH)
	if overhead != null:
		overhead.scale = Vector3(14.0, 14.0, 14.0)
		overhead.rotation = Vector3(0.0, 0.0, PI * 0.5)
		overhead.position = Vector3(0.0, ceiling_height - 0.4, platform_z)
		_world.add_child(overhead)

	# === Spotlights for the cinematic god-ray / volumetric beams in the reference ===
	var spot_l: Node3D = _instance_prop(SPOTLIGHT_PROP_PATH)
	if spot_l != null:
		spot_l.scale = Vector3(2.2, 2.2, 2.2)
		spot_l.position = Vector3(-4.5, ceiling_height - 1.0, platform_z + 1.5)
		_world.add_child(spot_l)
	var spot_r: Node3D = _instance_prop(SPOTLIGHT_PROP_PATH)
	if spot_r != null:
		spot_r.scale = Vector3(2.2, 2.2, 2.2)
		spot_r.position = Vector3(4.5, ceiling_height - 1.0, platform_z + 1.5)
		_world.add_child(spot_r)

	# (The old inlay ring and simple slab are superseded by the new props.
	# Any ancient_metal materials on the new GLBs will be used as authored.)


# Industrial wall columns: tall vertical structures that frame the gate (the
# angular "wings" either side of it in the reference) and march along the side
# walls for the cathedral-of-machinery read. Prop is normalized to a 1-unit box
# (tall axis = Y), so scale.y ≈ height in metres.
func _build_structural_columns() -> void:
	var half_x: float = room_size.x * 0.5
	var gate_z: float = room_size.y * 0.5 - 3.8
	var col_scale: Vector3 = Vector3(4.0, ceiling_height, 4.0)
	# Two columns flanking the gate (the reference's framing wings).
	for sx in [-1.0, 1.0]:
		var flank: Node3D = _instance_prop(INDUSTRIAL_COLUMN_PROP_PATH)
		if flank != null:
			flank.scale = col_scale
			flank.position = Vector3(sx * 7.0, 0.0, gate_z - 0.5)
			_world.add_child(flank)
	# A row marching down each side wall.
	for sx in [-1.0, 1.0]:
		for cz in [-8.0, 0.0, 8.0]:
			var col: Node3D = _instance_prop(INDUSTRIAL_COLUMN_PROP_PATH)
			if col != null:
				col.scale = col_scale
				col.position = Vector3(sx * (half_x - 0.8), 0.0, cz)
				_world.add_child(col)

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
		_world.add_child(beam)


# Attach a crew member's visual body under `model_holder` (already 180°-flipped
# so the model faces the body's -Z). PRIMARY path is the Quaternius
# ModularCharacter dressed via CharacterFactory — each crew member is uniquely
# styled (gender / hair / skin tone + duty blacks + sidearm for military, civvies
# for science staff). Falls back to the legacy Kenney mini GLB (2.6× + shared
# colormap + outfit recolor) only when the profile has no modular spec or the
# modular base fails to load. Returns the visual node that was added.
func _attach_crew_body(model_holder: Node3D, character: String, fallback_glb: String,
		context: String = "") -> Node:
	var ctx: String = context if context != "" else CharacterFactoryRef.CTX_SHIP
	if CharacterFactoryRef.profile_for(character).has("mod"):
		var mc: Node3D = CharacterFactoryRef.build_modular(character)
		if mc != null:
			model_holder.add_child(mc)
			CharacterFactoryRef.dress_modular(mc, character, ctx)
			return mc
	# Legacy fallback: Kenney mini at 2.6× with the shared colormap + dressing.
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	var glb: PackedScene = load(CharacterFactoryRef.model_for(character, fallback_glb))
	if glb == null:
		return null
	var inst: Node = glb.instantiate()
	model_holder.add_child(inst)
	var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
	if colormap != null:
		Npc.apply_kenney_colormap(inst, colormap)
	Npc.play_idle_animation(inst)
	if model_holder.get_parent() is Node3D:
		CharacterFactoryRef.dress(model_holder.get_parent(), model_holder, character, ctx)
	return inst


# Lt Scott waits down the dais ramp from the arrival platform and walks up to
# the player to brief them. His body is the Quaternius ModularCharacter (ship
# duty dress) so he reads as a distinct crew member. Collision capsule + Label3D
# nametag are still procedural — the model is purely visual.
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
	# He heads over the MOMENT control returns (short delay, brisk pace) so the
	# first thing the player does is talk to Scott, which kicks off the main quest
	# (met_scott → objective recompute → "find Rush").
	scott.set("auto_greet", not GameState.met_scott)
	scott.set("auto_greet_distance", 2.6)
	scott.set("auto_greet_delay", 0.3)
	scott.set("auto_greet_speed", 2.8)

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
	# Models export with +Z forward; rotate 180° to Godot's -Z forward —
	# otherwise Scott walks/auto-greets facing the wrong way.
	model_holder.rotation.y = PI
	scott.add_child(model_holder)
	# PRIMARY: Quaternius ModularCharacter, uniquely dressed for ship duty (duty
	# blacks + sidearm for military). Mirrors _build_returned_crew_npc so the
	# whole gate-room crew shares one styling code path. Falls back to the legacy
	# mini GLB only if the profile has no modular spec or the base fails to load.
	_attach_crew_body(model_holder, "Lt Scott", "res://models/characters/scott.glb")

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
	tag.visible = not _cold_open_active
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


# Medic vignette down-range from the gate where Colonel Young was thrown:
#   • Young lying face-up on the floor, unconscious and not interactable.
#   • Lt James kneeling on the gate-side of him, facing Young.
# James is the only talkable NPC in this cluster. The spot is also where the
# prologue's "Young thrown farthest" ragdoll lands, so the reveal is seamless.
func _build_medic_tableau() -> void:
	var tableau_center: Vector3 = Vector3(-1.5, 0.0, -6.5)   # = Young's arrival landing spot

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
	# PRIMARY for EVERY pose now: the Quaternius ModularCharacter, uniquely dressed
	# by CharacterFactory (goal: all crew are Quaternius, incl. the prone Young and
	# kneeling James). The "Invalid array format for surface" push_error is benign
	# garment-surface stripping noise that the standing modular crew already emit.
	var modular: bool = CharacterFactoryRef.profile_for(character).has("mod")
	if pose == "down":
		# Lay character on their back: tip the holder forward 90° so what was up
		# (head along +Y) now extends along +Z away from the feet anchor.
		# Lift slightly so the back doesn't z-fight with the floor.
		model_holder.rotation = Vector3(PI * 0.5, PI, 0.0)   # face-DOWN (injured, prone)
		model_holder.position = Vector3(0.0, 0.15, 0.0) if modular else Vector3(0.0, 0.18, 0.7)
		if not modular:
			model_holder.scale = Vector3(2.6, 2.6, 2.6)
	elif pose == "kneel":
		if modular:
			# Real rig: the kneeling-repair clip replaces the legacy Y-squash.
			model_holder.rotation = Vector3(0.0, PI, 0.0)
		else:
			# Compress the standing model vertically — reads as crouched/kneeling
			# without needing a separate rig. Slight forward tilt sells the lean.
			model_holder.rotation = Vector3(deg_to_rad(-20.0), PI, 0.0)
			model_holder.scale = Vector3(2.6, 1.5, 2.6)
	else:
		model_holder.rotation.y = PI
		if not modular:
			model_holder.scale = Vector3(2.6, 2.6, 2.6)

	body.add_child(model_holder)
	if modular:
		var mc: Node3D = CharacterFactoryRef.build_modular(character)
		model_holder.add_child(mc)
		CharacterFactoryRef.dress_modular(mc, character, CharacterFactoryRef.CTX_SHIP)
		if pose == "kneel":
			mc.call("play_clip", "repair")   # kneeling, hands working — medic triage
		elif pose == "down":
			# Freeze the idle pose: an unconscious body shouldn't breathe-sway.
			mc.call("freeze_pose")
	else:
		var glb: PackedScene = load(glb_path)
		if glb != null:
			var inst: Node = glb.instantiate()
			model_holder.add_child(inst)
			var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
			if colormap != null:
				Npc.apply_kenney_colormap(inst, colormap)
			# Down characters DON'T idle-loop — the breathe-anim makes "unconscious"
			# read as "stretching." Kneelers do, so they feel busy with their hands.
			if pose != "down":
				Npc.play_idle_animation(inst)
	# The face-override plane is positioned for the mini head; modular bodies
	# have a real face, so the X-eyed sticker would float mid-air — skip it.
	if face_override != "" and not modular:
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
	tag.visible = not _cold_open_active
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
		l.light_color = Color(0.42, 0.58, 0.95, 1.0)   # cool blue wash (was amber)
		l.light_energy = 1.6
		l.omni_range = 12.0
		l.omni_attenuation = 1.6
		l.position = p
		_world.add_child(l)

	# Gate uplighting: 1 spot from directly in front, 2 from the sides.
	# look_at() requires the node to already be inside the tree, so add_child
	# before re-orienting; otherwise the call quietly errors and the spotlight
	# points along its default axis.
	var gate_center: Vector3 = Vector3(0.0, _gate_center_y(), GATE_Z)
	# Front spot — cool, to pick the gate ring out of the dark (was warm).
	var front_spot: SpotLight3D = SpotLight3D.new()
	front_spot.light_color = Color(0.55, 0.7, 1.0, 1.0)
	front_spot.light_energy = 3.5
	front_spot.spot_range = 14.0
	front_spot.spot_angle = 35.0
	front_spot.position = Vector3(0.0, 1.2, gate_center.z - 5.5)
	_world.add_child(front_spot)
	front_spot.look_at(gate_center, Vector3.UP)
	# Side spots
	for sx in [-1.0, 1.0]:
		var side: SpotLight3D = SpotLight3D.new()
		side.light_color = Color(0.5, 0.66, 1.0, 1.0)
		side.light_energy = 2.4
		side.spot_range = 12.0
		side.spot_angle = 32.0
		side.position = Vector3(sx * 5.5, 1.2, gate_center.z - 1.5)
		_world.add_child(side)
		side.look_at(gate_center, Vector3.UP)

	# Soft top key light — directional, slightly cool. Establishes the "shafts
	# from above" feel even without a volumetric pass.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(0.78, 0.85, 1.0, 1.0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
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
		fill.light_color = Color(0.62, 0.72, 0.95, 1.0)
		fill.light_energy = 1.5
		fill.omni_range = 15.0
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
