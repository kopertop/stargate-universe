extends Node

# Global persistent game state. Cross-scene singleton.
# Survives scene_router transitions; reset() returns to clean E1 start.

signal health_changed(value: float)
signal oxygen_changed(value: float)
signal objective_changed(text: String)
# Fired only when quest_step actually advances to a different step (not on
# every objective-text update). SaveManager listens to this to autosave at
# each quest-progression beat — distinct from objective_changed, which can
# fire for custom NPC objectives that don't move the quest forward.
signal quest_step_changed(step: String)
signal room_discovered(room_id: String)
# Fired when the ON-FOOT player physically enters a room for the first time
# (NOT when the Kino finds it remotely). Drives the Ancient-glyph "decipher"
# decode on the discovery toast, door plaques, Kino map, and consoles.
signal room_deciphered(room_id: String)
# Fires whenever a discoverable point-of-interest (lime deposit, ruin, ore vein,
# water source, debris, …) is found — drives a live compass refresh.
signal pois_discovered_changed()
# Fires whenever an inventoried resource count changes (mining, top-up,
# scrubber repair, etc.). Drives the planet-side lime objective counter
# and any future resource HUD.
signal resource_changed(type: String, count: int)
# Fires whenever scrubber_level changes (decay tick or top-up). Drives the
# in-world bar gauge + the Kino System Status readout.
signal scrubber_level_changed(level: float)
# An optional maintenance scrubber's state changed (discovered / open / repaired).
signal scrubber_unit_changed(id: String)
# The gate-window departure countdown hit 0:00 — planet_timer.gd plays the
# scramble-back-through-the-gate cutscene.
signal gate_window_expired()
# Fired when the player enters a new room. Drives the Kino Remote player
# marker and the in-world quest-waypoint diamond's re-targeting.
signal current_room_changed(room_id: String)
signal kino_changed(acquired: bool)
signal episode_completed()
signal log_added(line: String)
# Fired by recall_after_window_close() and planet_gate.gd to_ship success (loop
# path only). FtlLoop listens to this to re-arm the ship phase after each gate
# run — E1 path ignores it entirely (E1 uses quest-step gates, not FtlLoop).
signal planet_run_ended()
# Fired by npc.gd each time a dialogue line is shown. The HUD listens and
# renders the line inside the sci-fi dialog panel; log_added still captures
# the same text for the journal.
signal dialogue_shown(character_name: String, line: String)
# Narrative transcript channel (#141). Drives the HUD Chat panel ONLY — a clean
# in-fiction transcript of stage directions + scripted speech, deliberately
# separate from add_log/log_added (which is the noisy system journal: discovery,
# resources, saves, …). speaker == "" → a white narration / stage-direction line;
# speaker set → a "Speaker: line" dialogue line. Emit via narrate()/say().
signal narrative_added(speaker: String, text: String)
# Fired by npc.gd when a choice-tree dialog should open. The HUD listens
# and shows the full-screen DialogScreen targeting `npc`.
signal kino_closed()
# Fired when the player walks through a door for the first time. Drives the
# Kino map's door-pip dim-on-traverse and survives save/load via
# doors_traversed.
signal door_traversed(key: String)
# Fired when a Kino is deployed/dropped from the tracked list — lets the Kino
# map (or any future retrieval UI) refresh its deployed-Kino markers.
signal deployed_kinos_changed()
# Placeholder status readouts shown on the Kino map HUD chrome. Future power
# / hull systems will fire these — defaults render as "OFFLINE" until any
# value is published.
signal power_changed(value: float)
signal hull_changed(value: float)
signal dialog_started(npc: Node3D, tree: Array)
# Fired by dialog_screen.gd::close() — lets one-shot triggers (e.g.
# kino_pickup) await a dialog's natural end without having to track the
# DialogScreen instance directly.
signal dialog_closed()
# Fired by dialog_screen.gd when it renders a dialog node carrying an "action"
# key. Lets a data-driven dialog tree trigger a side effect mid-conversation
# (e.g. the Phase D scrubber scene firing the FTL-drop blur on Brody's line).
signal dialog_action(action_id: String)
# Fired by gameplay code to RELEASE a dialog node that was rendered with
# "hold": true (choices disabled until this fires). Lets a beat block the player
# from advancing until staged choreography lands — e.g. Greer charging into the
# standoff before the player can continue. dialog_screen.gd listens one-shot.
signal dialog_release()

const MAX_HEALTH: float = 100.0
const MAX_OXYGEN: float = 100.0

const EPISODE_AIR: String = "air"
# Step IDs aliased as consts so existing readers (`GameState.QUEST_X`, test
# assertions, scene scripts) keep compiling unchanged. The data lives in
# data/quests.json; these constants exist only as a stable handle to the
# same strings. The QuestLog autoload is the source of truth for ordering,
# objectives, targets, and labels.
const QUEST_TALK_SCOTT: String = "talk_scott"
const QUEST_FIND_RUSH: String = "find_rush"
const QUEST_FIND_REST: String = "find_rest"
const QUEST_FIND_KINO: String = "find_kino"
const QUEST_SLEEP: String = "sleep"
const QUEST_RETURN_TO_CONTROL: String = "return_to_control"
const QUEST_DIAGNOSE_LIFE_SUPPORT: String = "diagnose_life_support"
const QUEST_SEAL_BREACH: String = "seal_breach"
const QUEST_FIND_SCRUBBER: String = "find_scrubber"
const QUEST_WAIT_FTL: String = "wait_ftl"
const QUEST_GO_TO_GATE: String = "go_to_gate"
const QUEST_FETCH_KINO: String = "fetch_kino"
const QUEST_SCOUT_KINO: String = "scout_kino"
const QUEST_DIAL_LIME_PLANET: String = "dial_lime_planet"
const QUEST_MINE_LIME: String = "mine_lime"
const QUEST_RETURN_DESTINY: String = "return_destiny"
const QUEST_REPAIR_SCRUBBER: String = "repair_scrubber"
const QUEST_COMPLETE: String = "complete"
const E1_QUEST_ID: String = "e1_air"
const AIR_LIME_RESOURCE: String = "lime"
# How much lime the away-mission objective asks the crew to bring back — enough
# to service ALL the scrubbers across the ship, not just the one blocking E1.
const AIR_LIME_REQUIRED: int = 3
# A single CO2 scrubber only needs ONE lime to refill to full. The extra lime in
# AIR_LIME_REQUIRED is banked for the other scrubbers, so even a run that grabbed
# just one unit (e.g. a timed-out recall) can still complete the E1 repair.
const SCRUBBER_REPAIR_LIME_COST: int = 1
# The authored E1 lime planet row (rich, hand-tuned layout) lives in this data
# file; build_air_lime_spec() loads it so the first dialed run is byte-identical
# to the authored world while still flowing through the dial -> spec pipeline.
const PLANETS_PATH: String = "res://data/planets.json"
const AIR_LIME_WORLD_ID: String = "air_lime_world"

# Tracked crew resources (issue #86) — the SINGLE registry of resources whose
# scarcity the crew cares about and that procedural-planet generation targets.
# ONE ordered collection (no per-resource `*_low` / `has_*` bools — honors the
# collection-fork lint). Each row: { id, label, low_threshold, default_amount }.
#   * id            — the Inventory item id holding the live count (counts persist
#                     in the Inventory pool, NOT here).
#   * low_threshold — at/under this the crew is "low" on it; deficit = threshold
#                     - amount drives resource_scarcity() ranking + targeting.
#   * default_amount— the starting stock seeded on a new game / reset().
# Lime stays the air-crisis resource AND a tracked resource so generation can
# target it when the scrubber is starved.
const TRACKED_RESOURCES: Array[Dictionary] = [
	{"id": "water", "label": "Water", "low_threshold": 10, "default_amount": 4},
	{"id": "food", "label": "Food", "low_threshold": 10, "default_amount": 6},
	{"id": "parts", "label": "Ship Parts", "low_threshold": 6, "default_amount": 2},
	{"id": "lime", "label": "Lime", "low_threshold": 3, "default_amount": 0},
]
# Phase G ongoing scrubber loop.
# One lime = one cartridge bar = a third of full charge.
const SCRUBBER_LIME_RECHARGE: float = 100.0 / float(AIR_LIME_REQUIRED)
# Decay rate: each bar of charge lasts 1 hour of real wall-clock time, so a
# full 100% charge buys 3 hours of life before a top-up is needed. _process
# runs on real frame delta (not in-game time), so this IS wall-clock seconds.
const SCRUBBER_DECAY_PER_SEC: float = SCRUBBER_LIME_RECHARGE / 3600.0
# Below this percentage the bar gauge shows red and a one-shot warning logs.
const SCRUBBER_WARN_PERCENT: float = 33.0
# At 0% the scrubber bleeds oxygen slowly until the player tops it up; the
# E1-forgiving rate is one oxygen point per minute, so even a stranded player
# has a long window to react.
const SCRUBBER_O2_BLEED_PER_SEC: float = 1.0 / 60.0
const KINO_ORB_MAX: int = 3
# How many DEPLOYED Kinos (left out in the world) we keep track of at once.
# Deploying another past this drops the oldest tracked location (FIFO).
const KINO_DEPLOYED_MAX: int = 3

# --- FTL loop duration tuning (issue #130) ------------------------------------
# Baseline ship phase: ~30 min real-time between gate drops.
const SHIP_PHASE_BASE: float = 1800.0
# Baseline planet window: ~10 min gate run. PlanetDepartureTimer reads this
# via planet_window_base_seconds() so all callers share one tunable source.
const PLANET_WINDOW_BASE: float = 600.0
# Override fields (default -1 = use base const). Set by the Bridge (#133) once
# the player finds and configures it. Persisted so the Bridge's tuning survives
# save/load. The ±20% randomization lives in FtlLoop, applied atop whatever
# base resolves here, so the Bridge tunes the CENTER of the distribution.
var ship_phase_override: float = -1.0  # @collection-ok: one tunable scalar, not an enumerated set
var planet_window_override: float = -1.0  # @collection-ok: one tunable scalar, not an enumerated set

# Crew / section scalars for consumption scaling (issue #134). Backed by
# simple integers; a future crew-roster system can forward its count here
# without touching ConsumptionManager. Annotated so the collection-fork
# lint knows these are SCALARS, not forked per-member bools.
# @collection-ok: scalar, not an enumerated set
var crew_count: int = 6
# @collection-ok: scalar, not an enumerated set
var active_sections: int = 3

# Return the effective ship-phase base (seconds). #133 writes ship_phase_override
# when the Bridge is found; until then returns the authored constant.
func ship_phase_base_seconds() -> float:
	return ship_phase_override if ship_phase_override >= 0.0 else SHIP_PHASE_BASE

# Return the effective planet-window base (seconds). PlanetDepartureTimer uses
# this when a loop planet phase is active, falling back to its own biome-scaled
# DURATION for the E1 run.
func planet_window_base_seconds() -> float:
	return planet_window_override if planet_window_override >= 0.0 else PLANET_WINDOW_BASE

# Consumption scaling accessors (issue #134).
func crew_size() -> int:
	return crew_count

# TODO: derive from a real powered-sections registry when that system ships.
func active_section_count() -> int:
	return active_sections

# QUEST_LABELS and QUEST_TARGETS used to live here as Dictionary lookups.
# Both moved into data/quests.json and are now served by QuestLog. Code that
# used `QUEST_LABELS[step]` or `QUEST_TARGETS[step]` should call
# `QuestLog.label(step)` / `QuestLog.target(step)` (or the GameState shims
# `quest_step_label(step)` / `quest_target(step)`) instead.

# Set by scene scripts (currently only gate_room.gd) when the player is
# in a scene that should be considered "in-world" for save purposes. Title
# screen / cutscenes leave this empty so F5 doesn't write garbage.
var current_scene_path: String = ""
# Player spawn override: when a scene loads after a "Continue from save",
# the room script reads this to know where to put the player, then clears it.
var pending_spawn_position: Variant = null   # Vector3 or null
var pending_spawn_yaw: float = 0.0
# Cross-scene baton: door.gd sets this before SceneRouter.change_to(room.tscn);
# room.gd::_ready() reads it to pick the right ShipLayout row, then clears it.
var next_room_id: String = ""
# True for the next room load only — tells the gate-room arrival cinematic
# to skip itself because we're resuming, not arriving.
var skip_arrival_cinematic: bool = false
# Launch baton: set true right before SceneRouter.change_to(planet) from Kino
# Control, so planet.gd spawns + possesses the Kino drone instead of the player.
# Transient (cleared by planet.gd on read); not part of the save snapshot.
var kino_pilot_mode: bool = false
# Where Eli's body was standing when the Kino launched. While piloting, Eli STAYS
# put (he doesn't "become" the Kino), so exiting kino control returns the player
# to this exact spot rather than a door spawn marker. Transient (set at launch,
# consumed on return; a kino flight is never saved mid-way).
var kino_return_position: Variant = null   # Vector3 or null
var kino_return_yaw: float = 0.0
# Scene the body is waiting in, so closing the Kino remote returns there even if
# the kino was being flown in a DIFFERENT scene (e.g. body on the ship, kino on
# the planet). Empty = current scene. kino_return_room_id restores the procedural
# room id when the body scene is room.tscn.
var kino_return_scene: String = ""
var kino_return_room_id: String = ""
# Where to spawn the CONTROLLED kino on the next scene load when taking control
# of a deployed kino in another scene. null pos = the scene's own default spawn
# (e.g. facing the planet gate).
var kino_pilot_target_scene: String = ""
var kino_pilot_target_pos: Variant = null   # Vector3 or null
# When a piloted Kino flies through a transition door, the destination room
# reads this to place the DRONE (not the player body) at the matching arrival
# marker. Holds the door's target_spawn key (e.g. "FromControlInterfaceRoom").
# Transient: set by kino_drone.gd right before the scene change, consumed by
# room.gd on arrival, never serialized (a piloted hop is never saved mid-way).
var kino_pilot_arrival_spawn: String = ""
# Ship auto-explore baton (issue #50, Phase 4b): a piloted Kino in ship
# auto-explore mode flies through undiscovered doors on its own. When it hops
# to the next room it sets this so the destination room.gd re-enters ship
# autopilot on the freshly-spawned drone. Transient (set right before the hop,
# consumed by room.gd on arrival; an auto-explore run is never saved mid-way).
var kino_autopilot: bool = false  # @collection-ok: one transient pilot-mode flag, not an enumerated set

# Active procedural-planet spec (issue #85). The dial / selection flow produces
# ONE spec per planet run; PlanetGenerator.build(world, spec) consumes it. Shape:
#   { "seed": int, "biome": String, "resource_table": Dictionary,
#     "hazard_params": Dictionary }
# Empty until a planet is dialed. Persisted (serialize/deserialize) so reloading
# mid-run rebuilds the IDENTICAL world. Discovery (discovered_pois) is keyed by
# deterministic node name, so chunk content + discovery survive save/load.
var active_planet_spec: Dictionary = {}

# Monotonic count of planets the gate has dialed this game (issue #93). The
# dial / selection flow derives each run's seed deterministically from this
# counter (PLANET_SEED_SALT-mixed) so build_next_planet_spec() is reproducible:
# the Nth dial always rolls the same biome + layout. Persisted so a reload that
# precedes the next dial still rolls the same upcoming planet.
# @collection-ok: a single monotonic run counter, not an enumerated collection
var planets_dialed: int = 0
# Seed salt mixed with planets_dialed so consecutive runs don't share low-bit
# biome rolls. Chosen as a large odd prime for good spread under FastNoiseLite.
const PLANET_SEED_SALT: int = 2654435761

var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var current_episode: String = EPISODE_AIR
var quest_step: String = QUEST_TALK_SCOTT
# Kino remote, kino orbs, fuses, lime + rations are NO LONGER stored here —
# they live in the Inventory autoload as counts. `kino_acquired` is now
# `Inventory.has("kino_remote")`; `kino_orbs` is `Inventory.count("kino_orb")`;
# the fuses are `Inventory.count("small_fuse"/"large_fuse")`.
var quarters_found: bool = false  # @collection-ok: one-shot story gate (first sleep), not an enumerated collection
# True once the player first steps into Eli's Quarters (eli_quarters). Drives
# the FIND_REST → SLEEP transition: Rush dismisses Eli with "go get some rest",
# the waypoint points at his quarters, and arriving there advances the quest.
var eli_quarters_visited: bool = false
# Main power is offline at E1 start: the elevator door north of cr_corridor_2 is
# locked until the player flips the Engineering Bay power console. Crew Quarters
# Alpha (floor 1) is gated by this — Eli's Quarters (floor 0) is reachable
# without power so the Kino Remote is still findable first.
var elevator_repaired: bool = false
var rooms_discovered: Array[String] = []
# Rooms the on-foot player has physically ENTERED (a strict subset of
# rooms_discovered: the Kino can discover a room remotely without the player
# ever setting foot in it). Until a room is deciphered its name/plaque/console
# text renders in the Ancient glyph font; walking in decodes it to English.
# One collection behind decipher_room()/is_deciphered() — NOT per-room bools
# (that would trip check_collection_forks.sh, the bug-#36/#41 guard).
var rooms_deciphered: Array[String] = []
# Stable keys ("min_room_id|max_room_id") of doors the player has walked
# through. Both directions resolve to the same key via door_key(). Drives the
# Kino map's bright-vs-dim pip styling and survives save/load.
var doors_traversed: Array[String] = []
# The ONE discovery registry (no per-type forks — see the collection-fork lint).
# Keyed by the discoverable's stable node name (e.g. "LimeNode3", "Poi_ruin_1")
# → { "category": String, "label": String }. A node is "discovered" once it's in
# here; only discovered POIs show on the planet compass. The planet seed is fixed,
# so a given key always maps to the same world position, and discovery survives
# save/load. Lime is just the "lime" category.
var discovered_pois: Dictionary = {}
var breaches_sealed: Array[String] = []
# Placeholder status readouts for the Kino map HUD chrome. The underlying
# systems (power grid, hull integrity) haven't been built yet — these stay at
# their default sentinels until something publishes a real value, in which
# case the HUD switches from "OFFLINE" to a percentage. Wire up later by
# setting `power_percent` (and emitting power_changed) from the power system.
const STATUS_OFFLINE: float = -1.0
var power_percent: float = STATUS_OFFLINE
var hull_percent: float = STATUS_OFFLINE
# Last room the player physically entered. Set by room.gd / gate_room.gd in
# _ready() and emitted via current_room_changed. Drives the Kino Remote map
# player-marker and the quest waypoint's "which door points toward the
# target" computation.
var current_room_id: String = ""
var current_objective: String = "Explore the Destiny"
var episode_complete: bool = false
var log_entries: Array[String] = []
var prologue_complete: bool = false
var air_crisis_started: bool = false
# True once the player has returned to the Control Interface Room after the
# air crisis, found Rush absent, and radioed Scott. Gates the
# RETURN_TO_CONTROL → DIAGNOSE_LIFE_SUPPORT (access terminal) transition.
var control_room_returned: bool = false
var life_support_diagnosed: bool = false
# True once the player has played out the "blocked door" beat at the control
# terminal — opened the sealed section (ship strobes red), panicked, and shut
# it again. One-shot: gates the beat so it doesn't replay on console re-access.
var blocked_door_beat_done: bool = false
# True once the player examines the jammed-door panel and learns its fuse
# slot is blown — only THEN does the objective send them to the crates for a
# fuse (don't hand the player the answer before they've looked at the door).
var door_panel_examined: bool = false
# Fuses looted from the Shuttle Dock crates are Inventory items now
# (counted, stackable): Inventory.count("small_fuse") / "large_fuse". The
# jammed door panel needs a small fuse and consumes one when seated.
var scrubber_diagnosed: bool = false
var scrubber_repaired: bool = false
# CO2 scrubber lime charge, 0–100%. Drives the 3-bar panel gauge (each bar =
# one third: 0%=3 red, 33%=1 green, 66%=2 green, 100%=3 green). Loading lime on
# repair sets it to 100; in Phase G it decays over time and the player tops it
# up with more lime (1 lime = 1 bar of charge) — the ongoing E1 → E2 loop.
var scrubber_level: float = 0.0
# Threshold latches so a warning fires exactly once per crossing (re-armed when
# the level rises back above the threshold via a top-up).
var _scrubber_warned: bool = false
var _scrubber_critical: bool = false
# --- Optional maintenance scrubbers (beyond the E1 south unit) --------------
# A SET of like things → ONE registry (collection-fork policy: never per-unit
# bools). Keyed by id → { "discovered": bool, "open": bool, "repaired": bool }.
# The E1 story scrubber keeps its dedicated state above (it has a unique
# diagnosis/Rush lifecycle); these are the discover/open/repair-at-leisure units
# the player services with banked lime. See [[project_air_crisis_rules]].
const AUX_SCRUBBERS: Array = [
	{"id": "north_corridor", "room": "north_corridor", "name": "North Section Scrubber"},
	{"id": "east_far", "room": "east_corridor_far", "name": "East Maintenance Scrubber"},
	{"id": "hydroponics", "room": "hydroponics", "name": "Hydroponics Scrubber"},
]
var scrubber_units: Dictionary = {}
var ftl_drop_triggered: bool = false
var lime_planet_dialed: bool = false
# True once the player reaches the Gate Room after Dr Brody's "the gate
# dialed itself" call (the GO_TO_GATE beat that ends the CO2 scrubber scene).
var reported_to_gate: bool = false
# Kino orbs the player is carrying live in Inventory as count("kino_orb")
# (dispenser is unlimited; held count caps at KINO_ORB_MAX; launching spends 1).
# Kinos left DEPLOYED out in the world (not in inventory). FIFO, newest last,
# capped at KINO_DEPLOYED_MAX — deploying another past the cap drops the oldest
# tracked location. Each entry: {"scene": String, "x"/"y"/"z": float}. World-
# state (read by future quest steps / map markers / retrieval — see issue #36).
var deployed_kinos: Array = []
# True once a Kino has been flown through the gate and confirmed what's on the
# far side (the SCOUT_KINO beat).
var kino_scout_done: bool = false
# One-shot: Rush's "that's bloody brilliant" approval has played (gate room,
# after the player returns with a Kino orb).
var kino_plan_approved: bool = false
# One-shot: the post-scout away-party briefing has played (gate room, MINE_LIME
# step, after the Kino recon returns). Gates the "let's mine some lime" dialog.
var away_party_briefed: bool = false
var returned_from_lime_planet: bool = false
# Gate-window departure countdown. Authoritative HERE (not in the planet scene's
# timer node) so it keeps ticking regardless of which controller is active — body
# OR a piloted/auto-searching Kino — and survives scene hops (a Kino crossing the
# two-way gate no longer resets it). planet_timer.gd is just the on-screen view +
# alarms + auto-return cinematic. Ticked in _process while active (skipped in
# instant_mode). Persisted so a resumed save keeps the same remaining time.
var gate_window_active: bool = false
var gate_window_remaining: float = 0.0
# Per-run heat/hazard water drain (issue #87). While a planet gate window is open
# the away team burns Water at the biome's rate (heat biomes drain faster). Water
# is an integer resource, so we accumulate fractional drain here and spend whole
# units as they cross 1.0. Rate is stamped at run start from the active biome.
# Both persisted so a resumed mid-run save keeps draining at the right rate.
var gate_window_water_drain: float = 0.0
var _water_drain_accum: float = 0.0
# Snapshot of tracked-resource counts captured the moment a planet run's gate
# window opens (run start). knock_out() reconciles against this: a downed run
# forfeits everything gathered this run EXCEPT the minimum-necessary bank of the
# run's scarce target resource. Empty = no run snapshot taken. Persisted so a
# save mid-run still reconciles correctly. Keyed by resource id → count.
var run_start_resources: Dictionary = {}
# Recovery beat (issue #92): set by knock_out() so the infirmary spawns TJ at the
# player's bedside with a cause-tagged wake-up line instead of the post-crisis
# James ward. recovering_in_infirmary stays true until the player leaves the
# infirmary; knockout_cause is consumed by the ward spawn to pick the line pool.
var recovering_in_infirmary: bool = false
var knockout_cause: String = ""
# Transient (NOT persisted): set just before a planet→gate-room return so the
# gate room spawns the away team that came back WITH the player and lands them
# past the platform. Consumed (cleared) by gate_room on arrival.
var pending_planet_return: bool = false
# E1 story milestones — set by NPC interacts (npc.gd via met_flag).
# met_scott: Lt Scott briefs the player on arrival; gates objective priority
# to "Find a Map" once true.
# met_rush: Player reaches Dr Rush in the control interface room; combined
# with kino + quarters + breach, this is the E1 completion gate.
var met_scott: bool = false
var met_rush: bool = false
# Standalone story flag (issue #89) — set by a story beat (E2+) when the crew
# finds pressure suits. Decoupled from the Equipment epic: this single flag both
# (a) gates the Toxic / no-atmosphere biome (the dial/selection flow may only roll
# it once this is true — see PlanetGenerator.eligible_biomes / select_biome), and
# (b) slows the on-surface oxygen drain on such a biome (suits don't make a toxic
# world free, just survivable). Persists via save.
# @collection-ok: one standalone story gate, not an enumerated collection
var pressure_suits_found: bool = false

# Stamped by trigger_ftl_drop() with GameClock.elapsed_seconds at the
# moment the FTL window opens. The gate console computes the live
# countdown as FTL_COUNTDOWN_START_SECONDS - (GameClock.elapsed_seconds -
# ftl_drop_game_time), so the displayed value is preserved across saves
# without depending on wall-clock time. -1 means the FTL drop hasn't
# happened yet.
var ftl_drop_game_time: float = -1.0

# Kino Remote map UI state — persisted so the player's preferred pan/zoom
# and any placed marker survives close + reopen and save + resume.
# `kino_marker` is empty when no marker is placed; otherwise:
#   { "floor": int, "world_x": float, "world_y": float }
var kino_pan_x: float = 0.0
var kino_pan_y: float = 0.0
var kino_zoom: float = 1.0
var kino_active_floor: int = -1
var kino_marker: Dictionary = {}

# Compass marker filters — configured on the Kino Remote's COMPASS settings page,
# read live by planet_compass.gd each _draw (so toggles apply instantly), and
# persisted so the player's preference survives save/resume. Default: show all.
var compass_show_lime: bool = true
var compass_show_kinos: bool = true
var compass_show_companions: bool = true
var compass_show_gate: bool = true
var compass_show_pois: bool = true

# Per-find discovery toast queue. When the Kino's auto-search finds things it
# announces each by NAME ("Kino found: Ancient Ruin"), but drains at ~1/sec so a
# simultaneous cluster doesn't stack on one frame. Transient (not serialized).
const _POI_TOAST_INTERVAL: float = 1.0
var _poi_toast_queue: Array[String] = []
var _poi_toast_timer: SceneTreeTimer = null


# Resolve an autoload by name, tolerating the headless -s SceneTree test
# context where GameState is instantiated as a bare node. Uses
# Engine.get_main_loop() rather than self.get_tree() because in -s mode
# `is_inside_tree()` returns false right after add_child until the next
# process_frame tick — see feedback_godot_scenetree_script_gotchas — and
# the previous get_tree() path would refuse the lookup during that
# window. Engine.get_main_loop() is unconditional and the root + child
# nodes ARE addressable by name as soon as add_child returns, even when
# the just-added child's is_inside_tree() hasn't flipped yet.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# The canonical item store. Autoload-tolerant so -s SceneTree tests that wire a
# sibling Inventory under their root still resolve it.
func _inv() -> Node:
	return _autoload_node("Inventory")


func _ready() -> void:
	# Autoload-tolerant: e1_flow.gd and other -s SceneTree script tests
	# instantiate GameState directly with no SaveManager in the tree.
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "game_state", self)
	# Re-emit QuestLog's signals through GameState's legacy names so the HUD,
	# Kino map, gate-room arrival branches, and every other reader of
	# `quest_step_changed(step)` / `objective_changed(text)` keep working
	# without churning their connection sites. We also cache the active step
	# id in `quest_step` and the active objective in `current_objective` so
	# direct property reads (the fast path everyone takes today) stay
	# correct. Autoload order in project.godot puts QuestLog after GameState,
	# so the signal connection is live by the time QuestLog._ready fires its
	# first quest_step_changed during auto_start.
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_signal("quest_step_changed"):
		if not ql.is_connected("quest_step_changed", _on_quest_log_step_changed):
			ql.connect("quest_step_changed", _on_quest_log_step_changed)


# Bridge: QuestLog tells us a quest advanced; route through the same pull
# helper that advance_air_quest uses so the back-compat mirrors + legacy
# signals stay consistent regardless of which path triggered the change.
func _on_quest_log_step_changed(quest_id: String, _step_id: String) -> void:
	if quest_id != E1_QUEST_ID:
		return
	_pull_quest_step_from_log(_autoload_node("QuestLog"))


# Phase G: tick the scrubber's lime charge down over time and bleed oxygen
# slowly once it bottoms out. Gated on SceneRouter.instant_mode so headless
# tests (which can run for many simulated frames) don't drift scrubber_level
# out from under their assertions.
func _process(delta: float) -> void:
	var router: Node = _autoload_node("SceneRouter")
	var headless: bool = router != null and router.get("instant_mode") == true
	# Gate window ticks here (not in the planet scene) so it keeps running while a
	# Kino is being piloted / auto-searching and across scene hops. Skipped in
	# instant_mode (start_gate_window is never called there anyway).
	if gate_window_active and not headless:
		_tick_gate_window(delta)
	if not scrubber_repaired:
		return
	if headless:
		return
	_tick_scrubber(delta)


# Begin the departure countdown. Idempotent: if a window is already running
# (e.g. the planet scene reloaded while it was active), this RESUMES it rather
# than restarting, so hopping in/out of a Kino or across the gate never resets
# the clock. Returns true only when it actually started a fresh window.
func start_gate_window(duration: float) -> bool:
	if gate_window_active:
		return false
	gate_window_active = true
	gate_window_remaining = duration
	# Heat/hazard water drain rate for THIS run, sourced from the active biome
	# (issue #87). A heat biome drains Water faster than the temperate baseline.
	gate_window_water_drain = PlanetGenerator.water_drain_for(active_planet_spec)
	_water_drain_accum = 0.0
	# Snapshot the crew's tracked-resource stock at run start so a knock-out can
	# forfeit everything gathered this run while banking the minimum of the
	# scarce target (issue #92).
	run_start_resources = {}
	for id in tracked_resource_ids():
		run_start_resources[id] = resource_count(id)
	return true

func _tick_gate_window(delta: float) -> void:
	_tick_heat_water_drain(delta)
	# Toxic / no-atmosphere biome (issue #89): oxygen drains while on-surface, slowed
	# by pressure suits. Run BEFORE the countdown decrement so a knock_out() it
	# triggers (oxygen hits 0) ends the window itself. _tick_atmosphere_oxygen_drain
	# returns true when it routed a knockout, in which case the window is already over.
	if _tick_atmosphere_oxygen_drain(delta):
		return
	gate_window_remaining = maxf(0.0, gate_window_remaining - delta)
	if gate_window_remaining <= 0.0:
		gate_window_active = false
		gate_window_expired.emit()


# On a toxin/no-atmosphere biome the away team's air drains while on the surface
# (issue #89). Reuses the existing `oxygen` pool + the sub-25% health bleed in
# consume_oxygen. Pressure suits (pressure_suits_found) slow the drain. When
# oxygen hits 0 the run ends via the no-death knockout, cause "asphyxiation".
# Returns true when it fired a knockout (the caller stops ticking the window).
func _tick_atmosphere_oxygen_drain(delta: float) -> bool:
	var rate: float = PlanetGenerator.oxygen_drain_for(active_planet_spec, pressure_suits_found)
	if rate <= 0.0:
		return false
	consume_oxygen(rate * delta)
	if oxygen <= 0.0:
		knock_out("asphyxiation")
		return true
	return false


# Burn Water on the surface at the biome's drain rate (issue #87). Water is an
# integer resource, so we accumulate fractional drain and spend whole units as
# they cross 1.0 — a hot biome reaches each whole unit sooner. Never drops below
# zero; if the crew is out of water the accumulator just idles.
func _tick_heat_water_drain(delta: float) -> void:
	if gate_window_water_drain <= 0.0:
		return
	_water_drain_accum += gate_window_water_drain * delta
	while _water_drain_accum >= 1.0:
		_water_drain_accum -= 1.0
		if resource_count("water") <= 0:
			_water_drain_accum = 0.0
			return
		spend_resource("water", 1, "the heat")


func _tick_scrubber(delta: float) -> void:
	var prev: float = scrubber_level
	if scrubber_level > 0.0:
		scrubber_level = maxf(0.0, scrubber_level - SCRUBBER_DECAY_PER_SEC * delta)
		scrubber_level_changed.emit(scrubber_level)
	else:
		# Out of lime: oxygen drains slowly so the player feels the pressure
		# without being instantly punished (E1 is forgiving — no stranding).
		consume_oxygen(SCRUBBER_O2_BLEED_PER_SEC * delta)
	# Threshold latches run regardless of which branch we took, so a tick that
	# only bleeds oxygen still fires the empty-alarm on its first frame.
	if not _scrubber_warned and prev > SCRUBBER_WARN_PERCENT and scrubber_level <= SCRUBBER_WARN_PERCENT:
		_scrubber_warned = true
		add_log("CO2 scrubber charge below %d%% — lime needed soon." % int(SCRUBBER_WARN_PERCENT))
	if not _scrubber_critical and scrubber_level <= 0.0:
		_scrubber_critical = true
		add_log("CO2 scrubber EMPTY — oxygen bleeding off, top up with lime immediately.")


func reset() -> void:
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	current_episode = EPISODE_AIR
	quest_step = QUEST_TALK_SCOTT
	quarters_found = false
	eli_quarters_visited = false
	elevator_repaired = false
	rooms_discovered.clear()
	rooms_deciphered.clear()
	doors_traversed.clear()
	discovered_pois.clear()
	breaches_sealed.clear()
	power_percent = STATUS_OFFLINE
	hull_percent = STATUS_OFFLINE
	current_room_id = ""
	episode_complete = false
	log_entries.clear()
	prologue_complete = false
	air_crisis_started = false
	control_room_returned = false
	blocked_door_beat_done = false
	door_panel_examined = false
	life_support_diagnosed = false
	scrubber_diagnosed = false
	scrubber_repaired = false
	scrubber_level = 0.0
	scrubber_units.clear()
	_scrubber_warned = false
	_scrubber_critical = false
	ftl_drop_triggered = false
	lime_planet_dialed = false
	reported_to_gate = false
	deployed_kinos.clear()
	kino_scout_done = false
	kino_plan_approved = false
	away_party_briefed = false
	returned_from_lime_planet = false
	pending_planet_return = false
	active_planet_spec = {}
	planets_dialed = 0
	gate_window_active = false
	gate_window_remaining = 0.0
	gate_window_water_drain = 0.0
	_water_drain_accum = 0.0
	run_start_resources = {}
	recovering_in_infirmary = false
	knockout_cause = ""
	# Items live in the Inventory store now — wipe it too (autoload-tolerant).
	var inv: Node = _inv()
	if inv != null and inv.has_method("reset"):
		inv.call("reset")
	# Seed the tracked-resource opening stock (water/food/parts/lime) so a fresh
	# run starts with the authored amounts and scarcity targeting is meaningful.
	seed_default_resources()
	met_scott = false
	met_rush = false
	pressure_suits_found = false
	ftl_drop_game_time = -1.0
	kino_pan_x = 0.0
	kino_pan_y = 0.0
	kino_zoom = 1.0
	kino_active_floor = -1
	kino_marker = {}
	compass_show_lime = true
	compass_show_kinos = true
	compass_show_companions = true
	compass_show_gate = true
	compass_show_pois = true
	_poi_toast_queue.clear()
	_poi_toast_timer = null
	# Clear scene-staging batons BEFORE advance_air_quest() emits
	# objective_changed. Otherwise the autosave hook sees a stale
	# current_scene_path (the room we were in when Restart was pressed) plus
	# a freshly-cleared current_room_id, and writes a roomless save that
	# void-falls on Continue. The next scene's _ready repopulates these.
	current_scene_path = ""
	next_room_id = ""
	pending_spawn_position = null
	pending_spawn_yaw = 0.0
	skip_arrival_cinematic = false
	kino_pilot_mode = false
	kino_return_position = null
	kino_return_yaw = 0.0
	kino_return_scene = ""
	kino_return_room_id = ""
	kino_pilot_target_scene = ""
	kino_pilot_target_pos = null
	kino_pilot_arrival_spawn = ""
	kino_autopilot = false
	# FTL loop tuning overrides back to "use base const" on a fresh game.
	ship_phase_override = -1.0
	planet_window_override = -1.0
	# Consumption scaling scalars — default crew of 6, 3 active sections.
	crew_count = 6
	active_sections = 3
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	kino_changed.emit(false)   # Inventory was just reset → no kino remote held
	# Wipe QuestLog progress so the e1_air quest restarts at step 1 with no
	# completed_steps carried over. autoload-tolerant: tests without QuestLog
	# in the tree skip this and rely on quest_step's `= QUEST_TALK_SCOTT`
	# default.
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("reset"):
		ql.call("reset")
	advance_air_quest()

# Set by a story beat (E2+) when the crew recovers pressure suits. Idempotent.
# Unlocks the Toxic biome in the selection pool and arms suit-slowed oxygen drain.
func mark_pressure_suits_found() -> void:
	if pressure_suits_found:
		return
	pressure_suits_found = true
	add_log("Recovered a cache of pressure suits — no-atmosphere worlds are survivable now.")


# Snapshot of the satisfied story flags the biome-selection pool consults. ONE
# place that maps story state → the {flag: bool} the generator reads, so adding a
# future biome gate doesn't fork selection logic.
func biome_flags() -> Dictionary:
	return {"pressure_suits_found": pressure_suits_found}


func damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	health_changed.emit(health)

func heal_full() -> void:
	health = MAX_HEALTH
	health_changed.emit(health)

func consume_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen - amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)
	# Below 25% oxygen, health starts ticking down too.
	if oxygen < 25.0:
		damage(amount * 0.5)

func restore_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen + amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)

func discover_room(room_id: String, display_name: String = "") -> void:
	if rooms_discovered.has(room_id):
		return
	rooms_discovered.append(room_id)
	room_discovered.emit(room_id)
	if display_name != "":
		add_log("Discovered: " + display_name)


# Mark a room as DECIPHERED — the on-foot player has physically entered it, so
# its Ancient-glyph name resolves to readable English. Idempotent. Called only
# from room.gd's on-foot _ready path (after the Kino-pilot early-return), so a
# remote Kino flyby discovers but never deciphers.
func decipher_room(room_id: String) -> void:
	if rooms_deciphered.has(room_id):
		return
	rooms_deciphered.append(room_id)
	room_deciphered.emit(room_id)


func is_deciphered(room_id: String) -> bool:
	return rooms_deciphered.has(room_id)

# Mark a discoverable point-of-interest as found. Idempotent; emits
# pois_discovered_changed so an open compass refreshes live. `announce` is set
# ONLY by the Kino's auto-search sweep, so a per-find toast names what the Kino
# turned up — mining/foot discovery still records the POI (so it shows on the
# compass) but stays quiet.
func discover_poi(key: String, category: String, label: String, announce: bool = false) -> void:
	if key == "" or discovered_pois.has(key):
		return
	discovered_pois[key] = {"category": category, "label": label}
	pois_discovered_changed.emit()
	if announce:
		_announce_poi(label)

func is_poi_discovered(key: String) -> bool:
	return discovered_pois.has(key)

# Backwards-compatible lime helpers — lime is just the "lime" category in the one
# discovery registry (no parallel store; see the collection-fork lint).
func discover_lime(key: String) -> void:
	discover_poi(key, AIR_LIME_RESOURCE, "Lime deposit")

func is_lime_discovered(key: String) -> bool:
	return is_poi_discovered(key)

# Per-find toast routed through the HUD log feed (the project's toast). Queues
# the find and drains one line per _POI_TOAST_INTERVAL so a simultaneous cluster
# doesn't stack on one frame, but each find keeps its own name. Skipped in
# instant_mode/headless (no log feed, and it'd add a stray timer to every test).
func _announce_poi(label: String) -> void:
	var router: Node = _autoload_node("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	if Engine.get_main_loop() == null:
		return
	_poi_toast_queue.append(label)
	if _poi_toast_timer == null:
		_emit_next_poi_toast()                  # show the first find immediately

func _emit_next_poi_toast() -> void:
	if _poi_toast_queue.is_empty():
		_poi_toast_timer = null
		return
	var label: String = _poi_toast_queue.pop_front()
	add_log("Kino found: " + label)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		_poi_toast_timer = null
		return
	_poi_toast_timer = tree.create_timer(_POI_TOAST_INTERVAL)
	_poi_toast_timer.timeout.connect(_emit_next_poi_toast)


# Stable, direction-agnostic key for a door connecting two rooms. Sorted so
# the same door has the same id regardless of which side you walk through.
static func door_key(a: String, b: String) -> String:
	if a <= b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]


# Record that the player has walked through the door between rooms a and b.
# Idempotent — re-traversing the same door is a no-op. Emits door_traversed
# so the open Kino map can dim the pip in real time.
func mark_door_traversed(a: String, b: String) -> void:
	if a == "" or b == "":
		return
	var key: String = door_key(a, b)
	if doors_traversed.has(key):
		return
	doors_traversed.append(key)
	door_traversed.emit(key)


func door_was_traversed(a: String, b: String) -> bool:
	return doors_traversed.has(door_key(a, b))


# Publish a power-reading. Future power system calls this; the Kino map HUD
# listens and switches from "OFFLINE" to "POWER xx%". -1 reverts to OFFLINE.
func set_power_percent(value: float) -> void:
	power_percent = value
	power_changed.emit(value)


func set_hull_percent(value: float) -> void:
	hull_percent = value
	hull_changed.emit(value)

func acquire_kino() -> void:
	var inv: Node = _inv()
	if inv != null and inv.call("has", "kino_remote"):
		return
	if inv != null:
		inv.call("add_item", "kino_remote", 1)
	# Used to be buried mid-ladder in _next_air_quest_step() — surfaced here
	# alongside its trigger so the side-effect is co-located with the world-
	# state change. start_air_crisis() also sets it, so either path (picking
	# the Kino up first, or skipping straight into the crisis) seals the
	# prologue.
	prologue_complete = true
	kino_changed.emit(true)
	add_log("Acquired the Kino Remote.")
	advance_air_quest()

func mark_quarters_found(log_msg: String = "Found Crew Quarters Alpha.") -> void:
	if quarters_found:
		return
	quarters_found = true
	add_log(log_msg)
	advance_air_quest()

func mark_eli_quarters_found() -> void:
	# Eli IS the player; this is HIS room. First entry flips eli_quarters_visited,
	# logs the moment, and advances the quest (FIND_REST → SLEEP).
	if eli_quarters_visited:
		return
	eli_quarters_visited = true
	add_log("My quarters. Something's sitting on the desk — better take a look.")
	advance_air_quest()

func unlock_elevator() -> void:
	if elevator_repaired:
		return
	elevator_repaired = true
	add_log("Main power restored. The elevator north of the corridor is online.")
	advance_air_quest()

func seal_breach(breach_id: String) -> void:
	if breaches_sealed.has(breach_id):
		return
	breaches_sealed.append(breach_id)
	if air_crisis_started and not scrubber_repaired:
		restore_oxygen(8.0)
		add_log("Exposed section locked down. Pressure is steadier, but CO2 is still climbing.")
	else:
		restore_oxygen(MAX_OXYGEN)
	add_log("Hull breach sealed: " + breach_id)
	advance_air_quest()

# Quest-gated objective. Each story beat unlocks a single concrete destination
# so the HUD never asks the player to solve a vague checklist.
func _recompute_objective() -> void:
	advance_air_quest()

# Re-derive the active step from current world-state. This is now a thin
# shim over QuestLog.advance("e1_air") — every call site that used to be
# `advance_air_quest()` keeps the same signature, but the predicate ladder
# lives in QuestLog/data instead of inline `if` chains.
#
# Pull-based sync (not signal-only): after telling QuestLog to advance, we
# also read back the new active step + objective and refresh GameState's
# back-compat mirrors. Going through pull (rather than only the
# quest_step_changed signal) keeps tests working even when QuestLog is
# added to the tree after GameState — the signal connection in _ready
# would race the test setup order otherwise.
#
# Autoload-tolerant: tests can spin up GameState without QuestLog in the
# tree, in which case advance is a no-op and the cached `quest_step`
# stays at whatever the test seeded.
func advance_air_quest() -> void:
	var ql: Node = _autoload_node("QuestLog")
	if ql == null:
		return
	if ql.has_method("advance"):
		ql.call("advance", E1_QUEST_ID)
	_pull_quest_step_from_log(ql)


# Sync GameState's mirror fields (quest_step + current_objective) from
# QuestLog's view of the e1_air quest and re-emit the legacy signals when
# anything changed. Idempotent — readable signals only fire on transitions.
func _pull_quest_step_from_log(ql: Node) -> void:
	if ql == null:
		return
	var new_step: String = ""
	if ql.has_method("active_step_id"):
		new_step = String(ql.call("active_step_id", E1_QUEST_ID))
	if new_step == "":
		return
	var new_text: String = ""
	if ql.has_method("objective"):
		new_text = String(ql.call("objective", E1_QUEST_ID))
	var step_changed: bool = new_step != quest_step
	var text_changed: bool = new_text != "" and new_text != current_objective
	quest_step = new_step
	if new_text != "":
		current_objective = new_text
	if text_changed:
		objective_changed.emit(current_objective)
	if step_changed:
		quest_step_changed.emit(new_step)


# HUD-facing short label for a step id (or the active step when key=="").
func quest_step_label(step: String = "") -> String:
	var key: String = quest_step if step == "" else step
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("label"):
		return String(ql.call("label", key))
	return key


# Anchor data for the in-world quest diamond and the Kino Remote target
# marker. Returns {} when the active step has no on-ship target (offworld
# planet steps + completion).
func quest_target(step: String = "") -> Dictionary:
	var ql: Node = _autoload_node("QuestLog")
	if ql == null:
		return {}
	if step == "":
		if ql.has_method("target"):
			return ql.call("target", E1_QUEST_ID)
		return {}
	if ql.has_method("target_for_step"):
		return ql.call("target_for_step", step)
	return {}


func set_current_room(room_id: String) -> void:
	if room_id == "" or room_id == current_room_id:
		return
	current_room_id = room_id
	current_room_changed.emit(room_id)

func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)


# Live counter shown by the top-left objective label while the player is on
# the lime planet. Until the threshold is met it reads "Collect at least N
# lime deposits — X/N"; once X >= N it flips to a "head back to the gate"
# completion line. Pulled into GameState (not planet_timer.gd) so the same
# string can be regenerated on save/load and asserted from headless tests
# without spinning up the planet scene.
static func lime_objective_text(have: int, need: int) -> String:
	if have >= need:
		return "Lime collected — %d/%d  ✓  head back to the gate" % [have, need]
	return "Collect at least %d lime deposits — %d/%d" % [need, have, need]

# Read-only, fully DERIVED atmosphere readout for a given room — no new stored
# state. Drives the always-on top-right ship readout (hud.gd) and could feed any
# future per-room display. E1 rules, in priority order:
#   • Base = nominal (N2/O2, breathable, current O2), merged over an optional
#     authored `atmosphere` field on the ShipLayout row (so a room can declare a
#     custom composition / temperature in data without code changes).
#   • The unsealed south breach reads as hard vacuum (VENTING) until sealed.
#   • During the air crisis, before the scrubber is repaired, every other room
#     reads DEGRADED with elevated CO2.
#   • Otherwise NOMINAL.
func room_atmosphere(room_id: String) -> Dictionary:
	var atmo: Dictionary = {
		"status": "NOMINAL",
		"composition": "N2/O2 NOMINAL",
		"breathable": true,
		"oxygen": int(round(oxygen)),
		"radiation": "LOW",
		"toxins": "NONE",
	}
	# Authored per-room overrides from the ship layout (default {}).
	var sl: Node = _autoload_node("ShipLayout")
	if sl != null and sl.has_method("room"):
		var row: Dictionary = sl.call("room", room_id)
		var authored: Variant = row.get("atmosphere", {})
		if authored is Dictionary:
			for k in (authored as Dictionary).keys():
				atmo[k] = (authored as Dictionary)[k]
	# Unsealed south breach → hard vacuum until sealed.
	if room_id == "breached_section_south" and not breaches_sealed.has("breach_a"):
		atmo["status"] = "VENTING"
		atmo["composition"] = "VACUUM"
		atmo["breathable"] = false
		atmo["oxygen"] = 0
		atmo["temperature_note"] = "FREEZING"
	# Air crisis pre-repair → CO2 climbing everywhere that isn't venting.
	elif air_crisis_started and not scrubber_repaired:
		atmo["status"] = "DEGRADED"
		atmo["toxins"] = "CO2 ELEVATED"
	return atmo

func add_log(line: String) -> void:
	log_entries.append(line)
	log_added.emit(line)


# Narrative-transcript helpers (feed the HUD Chat panel; see narrative_added).
# Kept separate from add_log so the chat stays a clean dialogue/stage-direction
# transcript and never fills with system-journal noise.
func narrate(text: String) -> void:
	narrative_added.emit("", text)


func say(speaker: String, text: String) -> void:
	narrative_added.emit(speaker, text)

# Resource shims over the Inventory pool. These keep the game-logic side
# effects (log line, resource_changed signal, quest advance) here while the
# counts themselves live in Inventory — there is no `resources` dict any more.
func resource_count(type: String) -> int:
	var inv: Node = _inv()
	return 0 if inv == null else int(inv.call("count", type))

func add_resource(type: String, amount: int, source: String = "") -> bool:
	if amount <= 0:
		return false
	var inv: Node = _inv()
	if inv == null:
		return false
	var next_amount: int = int(inv.call("add_item", type, amount, source))
	var source_suffix: String = "" if source == "" else " from " + source
	add_log("Collected %d %s%s. Total: %d." % [amount, type, source_suffix, next_amount])
	resource_changed.emit(type, next_amount)
	advance_air_quest()
	return true

func has_resource(type: String, amount: int) -> bool:
	return resource_count(type) >= amount

func spend_resource(type: String, amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return true
	var current: int = resource_count(type)
	if current < amount:
		add_log("Need %d %s for %s. Current: %d." % [amount, type, reason, current])
		return false
	var inv: Node = _inv()
	if inv != null:
		inv.call("remove_item", type, amount, reason)
	var reason_suffix: String = "" if reason == "" else " for " + reason
	add_log("Spent %d %s%s. Remaining: %d." % [amount, type, reason_suffix, resource_count(type)])
	resource_changed.emit(type, resource_count(type))
	advance_air_quest()
	return true


# --- Tracked resources + scarcity targeting (issue #86) ----------------------

# Seed the starting stock for every tracked resource. Called from reset() so a
# fresh run begins with the authored default amounts (the Inventory pool is the
# store; these are just the opening counts). Idempotent-ish: it SETS the counts,
# so calling it twice yields the same opening stock.
func seed_default_resources() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	for row in TRACKED_RESOURCES:
		inv.call("set_count", String(row["id"]), int(row.get("default_amount", 0)))


# The ids of every tracked resource, in registry order. The ONE enumerable
# surface — callers iterate this instead of naming water/food/parts/lime.
func tracked_resource_ids() -> Array:
	var ids: Array = []
	for row in TRACKED_RESOURCES:
		ids.append(String(row["id"]))
	return ids


# How far below its threshold a tracked resource currently sits (clamped at 0 —
# a resource at/over threshold has deficit 0, never negative). Drives ranking.
func resource_deficit(id: String) -> int:
	for row in TRACKED_RESOURCES:
		if String(row["id"]) == id:
			return maxi(0, int(row.get("low_threshold", 0)) - resource_count(id))
	return 0


# Rank tracked resources by how badly the crew needs them: deficit (threshold -
# amount) DESCENDING, ties broken by registry order (stable) so the result is
# deterministic. Returns a fresh array of
#   { "id": String, "label": String, "amount": int, "threshold": int, "deficit": int }
# The first entry is the SCARCEST resource — generation guarantees it (see
# build_resource_table).
func resource_scarcity() -> Array:
	var rows: Array = []
	var order: int = 0
	for row in TRACKED_RESOURCES:
		var id: String = String(row["id"])
		var amount: int = resource_count(id)
		var threshold: int = int(row.get("low_threshold", 0))
		rows.append({
			"id": id,
			"label": String(row.get("label", id.capitalize())),
			"amount": amount,
			"threshold": threshold,
			"deficit": maxi(0, threshold - amount),
			"_order": order,
		})
		order += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["deficit"]) != int(b["deficit"]):
			return int(a["deficit"]) > int(b["deficit"])
		return int(a["_order"]) < int(b["_order"]))
	for r in rows:
		(r as Dictionary).erase("_order")
	return rows


# Build a `resource_table` for a procedural planet, targeting crew scarcity
# (issue #86). DECIDED rule:
#   * the single SCARCEST tracked resource is GUARANTEED present in good quantity
#     (its own deposit cluster), AND
#   * 1-2 ADDITIONAL tracked resource types are chosen semi-randomly (seeded off
#     the spec seed, deterministic) as secondaries.
# The chosen clusters are emitted under `clusters` as an ordered list of
#   { "type": String, "nodes": int, "per_node": int, "min_radius": float,
#     "max_radius": float }
# which PlanetGenerator places (generalized resource_node per type). The legacy
# top-level lime_* keys are still emitted ONLY when lime is among the clusters,
# so existing lime-only consumers / saves keep working.
func build_resource_table(seed: int) -> Dictionary:
	var ranked: Array = resource_scarcity()
	if ranked.is_empty():
		return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	# Primary: the scarcest. Guaranteed, richer cluster.
	var primary_id: String = String((ranked[0] as Dictionary)["id"])
	var chosen: Array = [primary_id]
	# Secondaries: 1-2 of the remaining tracked resources, seeded.
	var pool: Array = []
	for r in ranked.slice(1):
		pool.append(String((r as Dictionary)["id"]))
	var want_extra: int = (1 if pool.size() <= 1 else rng.randi_range(1, 2))
	want_extra = mini(want_extra, pool.size())
	# Shuffle the pool deterministically (Fisher-Yates with the seeded rng), then
	# take the first want_extra. This keeps selection stable for a given seed.
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for k in want_extra:
		chosen.append(String(pool[k]))

	var clusters: Array = []
	var first: bool = true
	for type in chosen:
		# Primary gets more nodes + a tighter band (easy to find); secondaries are
		# leaner and ring further out. All radii deterministic per seed.
		var nodes: int = (5 if first else 3)
		var per_node: int = (2 if first else 1)
		var min_r: float = (50.0 if first else 90.0)
		var max_r: float = (120.0 if first else 200.0)
		clusters.append({
			"type": type,
			"nodes": nodes,
			"per_node": per_node,
			"min_radius": min_r,
			"max_radius": max_r,
		})
		first = false

	var table: Dictionary = {"clusters": clusters}
	# Back-compat: surface the lime cluster's params under the legacy keys so a
	# lime-only reader (or the legacy generator path) still finds lime placement.
	for c in clusters:
		if String((c as Dictionary)["type"]) == AIR_LIME_RESOURCE:
			table["lime_nodes"] = int((c as Dictionary)["nodes"])
			table["lime_per_node"] = int((c as Dictionary)["per_node"])
			table["lime_min_radius"] = float((c as Dictionary)["min_radius"])
			table["lime_max_radius"] = float((c as Dictionary)["max_radius"])
			break
	return table


# --- Dial / selection flow (issue #93) --------------------------------------
#
# THE single entry point that turns a gate dial / FTL drop into a complete,
# persisted PlanetSpec. Ties together the three planet-epic pieces:
#   * biome: PlanetGenerator.select_biome(seed, biome_flags()) — respects the
#     pressure_suits_found gate so Toxic only rolls once suits are found (#89),
#   * resource_table: build_resource_table(seed) — guarantees the scarcest
#     tracked resource + 1-2 extras (#86),
#   * hazard_params: the biome's own hazard block from biomes.json, so on-surface
#     window / water / oxygen / trap / sensor behaviour resolves for the run.
# The run seed is derived deterministically from planets_dialed (incremented per
# dial), so the Nth planet always rolls IDENTICALLY — and because the assembled
# spec is persisted whole into active_planet_spec, a reload rebuilds the same
# world without re-rolling. Returns the spec it stored.
#
# Pass force_biome to override selection (the E1 first lime run pins "desert" so
# the authored lime planet is unchanged); pass force_seed to pin the seed (the
# first run reuses the authored air_lime_world seed for an identical layout).
func build_next_planet_spec(name_hint: String = "", force_biome: String = "",
		force_seed: int = -1) -> Dictionary:
	planets_dialed += 1
	var run_seed: int = force_seed if force_seed >= 0 else _planet_run_seed(planets_dialed)
	var biome: String = force_biome
	if biome == "":
		biome = PlanetGenerator.select_biome(run_seed, biome_flags())
	var bp: Dictionary = PlanetGenerator.biome_params(biome)
	var hz: Variant = bp.get("hazard", {})
	var hazard_params: Dictionary = (hz as Dictionary).duplicate(true) if hz is Dictionary else {}
	var label: String = String(bp.get("label", biome.capitalize()))
	var planet_name: String = name_hint if name_hint != "" else "%s World" % label
	var spec: Dictionary = {
		"seed": run_seed,
		"biome": biome,
		"resource_table": build_resource_table(run_seed),
		"hazard_params": hazard_params,
		"name": planet_name,
	}
	active_planet_spec = spec
	return spec


# Deterministic per-run planet seed from the dial counter. Mixed with a large
# odd salt so consecutive runs don't share low-bit biome rolls. Masked to 31
# bits so it stays a positive int (FastNoiseLite / RandomNumberGenerator seed).
func _planet_run_seed(dial_index: int) -> int:
	return (dial_index * PLANET_SEED_SALT) & 0x7fffffff


# Build (and persist) the authored E1 lime-planet spec from the planets.json
# AIR_LIME_WORLD_ID row. This is the SINGLE source of the hand-tuned lime layout
# (node counts, radii, POI bands) — both the dial flow (dial_lime_planet) and the
# planet scene's direct-boot fallback (planet.gd::_active_spec) route through it,
# so the authored world is byte-identical no matter how it is entered. Counts the
# dial so planets_dialed advances like any other run. Returns the stored spec.
func build_air_lime_spec() -> Dictionary:
	planets_dialed += 1
	var row: Dictionary = _load_planet_row(AIR_LIME_WORLD_ID)
	var atmo: Variant = row.get("atmosphere", {})
	# The authored first planet is a DRY lime world: ONLY lime + sand. Force every
	# non-lime POI category to 0 so the generator scatters no water/ruin/ore/debris
	# here (water on a dry planet made no sense). Other planets keep their defaults.
	var poi: Dictionary = {"water": 0, "ruin": 0, "ore": 0, "debris": 0}
	var spec: Dictionary = {
		"seed": int(row.get("seed", 104729)),
		"biome": "desert",
		"resource_table": {
			"lime_nodes": int(row.get("lime_nodes", 5)),
			"lime_per_node": int(row.get("lime_per_node", 1)),
			"lime_min_radius": float(row.get("lime_min_radius", 70.0)),
			"lime_max_radius": float(row.get("lime_max_radius", 200.0)),
			"lime_far_count": int(row.get("lime_far_count", 0)),
			"lime_far_min_radius": float(row.get("lime_far_min_radius", 380.0)),
			"lime_far_max_radius": float(row.get("lime_far_max_radius", 440.0)),
			"lime_far_arc": float(row.get("lime_far_arc", 0.7)),
			"poi_counts": poi if poi is Dictionary else {},
		},
		"hazard_params": atmo if atmo is Dictionary else {},
		"name": String(row.get("name", "Lime World")),
	}
	active_planet_spec = spec
	return spec


# Load a single planets.json row by id. Returns {} if the file/row is missing so
# callers fall back to inlined defaults.
func _load_planet_row(id: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(PLANETS_PATH, FileAccess.READ)
	if f == null:
		push_error("game_state.gd: cannot open %s" % PLANETS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("game_state.gd: %s did not parse to an array" % PLANETS_PATH)
		return {}
	for entry in parsed:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
			return entry as Dictionary
	return {}


# Kino scan profile (issue #93). A compact, render-ready summary of the UPCOMING
# planet a spec describes, surfaced by the Kino recon HUD / compass BEFORE/while
# the player chooses to cross. Pure read — derives everything from the spec +
# the biome's data block, no side effects. Shape:
#   { "biome": String, "label": String, "breathable": bool,
#     "composition": String, "temperature_c": int, "temperature_note": String,
#     "radiation": String, "toxins": String, "hazard": String,
#     "gate_window": float, "resources": [String,...] }
# `resources` lists the human labels of the resource clusters the run will yield
# (scarcest first), so the player can read "what's down there" before crossing.
func planet_scan_profile(spec: Dictionary = {}) -> Dictionary:
	var s: Dictionary = spec if (spec is Dictionary and not spec.is_empty()) else active_planet_spec
	var biome: String = String(s.get("biome", "desert"))
	var bp: Dictionary = PlanetGenerator.biome_params(biome)
	var hz: Dictionary = bp.get("hazard", {}) if bp.get("hazard", {}) is Dictionary else {}
	var breathable: bool = PlanetGenerator.breathable_for(s)
	var hazard_type: String = String(hz.get("type", "none"))
	# Resource labels (scarcest first) from the spec's clusters; fall back to lime.
	var resources: Array = []
	var rt: Variant = s.get("resource_table", {})
	if rt is Dictionary and (rt as Dictionary).get("clusters", null) is Array:
		for c in (rt as Dictionary)["clusters"]:
			if c is Dictionary:
				resources.append(resource_label(String((c as Dictionary).get("type", ""))))
	if resources.is_empty():
		resources.append(resource_label(AIR_LIME_RESOURCE))
	return {
		"biome": biome,
		"label": String(bp.get("label", biome.capitalize())),
		"breathable": breathable,
		"composition": "BREATHABLE" if breathable else String(hz.get("toxins", "TOXIC")),
		"temperature_c": int(hz.get("temperature_c", 20)),
		"temperature_note": _temp_note(int(hz.get("temperature_c", 20))),
		"radiation": String(hz.get("radiation", "LOW")),
		"toxins": String(hz.get("toxins", "NONE")) if not breathable else "NONE",
		"hazard": hazard_type.to_upper() if hazard_type != "none" else "NONE",
		"gate_window": PlanetGenerator.gate_window_for(s),
		"resources": resources,
	}


# Human label for a tracked resource id (Water/Food/Parts/Lime), falling back to
# a capitalized id so an unknown type still reads cleanly on the scan profile.
func resource_label(id: String) -> String:
	for row in TRACKED_RESOURCES:
		if String(row["id"]) == id:
			return String(row.get("label", id.capitalize()))
	if id == AIR_LIME_RESOURCE:
		return "Lime"
	return id.capitalize()


# Coarse HOT/WARM/TEMPERATE/COLD note for a temperature, matching the atmosphere
# readout's `temperature_note` so the scan profile reads consistently with the
# in-room readout.
func _temp_note(temp_c: int) -> String:
	if temp_c >= 40:
		return "HOT"
	if temp_c >= 28:
		return "WARM"
	if temp_c <= 0:
		return "COLD"
	return ""


func can_start_air_crisis() -> bool:
	var inv: Node = _inv()
	var has_kino: bool = inv != null and inv.call("has", "kino_remote")
	return met_rush and eli_quarters_visited and has_kino and not air_crisis_started

func start_air_crisis() -> void:
	if air_crisis_started or episode_complete:
		return
	if not can_start_air_crisis():
		add_log("Inspect the strange device on your desk first.")
		advance_air_quest()
		return
	prologue_complete = true
	air_crisis_started = true
	oxygen = minf(oxygen, 62.0)
	oxygen_changed.emit(oxygen)
	add_log("Destiny drops out of FTL. Alarms report rising CO2 in life support.")
	# Dialog announcement is intentionally NOT fired here — callers play their
	# own cinematic (bed.gd fades to black on sleep, then wakes the player up
	# and calls announce_air_crisis()). Direct state-only callers (smoke tests)
	# skip the dialog entirely.
	# Emergency override flips the inter-deck elevator online so the player can
	# reach Hydroponics on the upper floor without first solving the power
	# console. (That console used to gate the prologue; now it's free flavor.)
	if not elevator_repaired:
		unlock_elevator()
	advance_air_quest()


# Wake-up dialog beat — fired after bed.gd's sleep cinematic finishes its
# fade-in so the line reads as the player coming to and noticing the alarm,
# not as a popup the moment they pressed E on the bed.
func announce_air_crisis() -> void:
	if not air_crisis_started:
		return
	dialogue_shown.emit("Eli", "That's not a normal alarm. The air just got worse.")


# Marks the post-crisis return to the control room (Rush absent, Eli radios
# Scott). Advances RETURN_TO_CONTROL → DIAGNOSE_LIFE_SUPPORT so the next
# objective is "access a control terminal". The radio exchange itself is
# played by room.gd on entry; this just flips the state.
func mark_control_room_returned() -> void:
	if control_room_returned:
		return
	control_room_returned = true
	advance_air_quest()


# First time the player works the dead door panel: they learn the fuse slot
# is blown. Flips the objective + waypoint from the panel to the crates.
func examine_door_panel() -> void:
	if door_panel_examined:
		return
	door_panel_examined = true
	advance_air_quest()


# Looting a fuse from a Shuttle Dock crate. The small fuse is the one the
# door panel needs (flips the objective + waypoint to the panel); the large
# fuse is the wrong size for the door.
func find_small_fuse() -> void:
	var inv: Node = _inv()
	if inv != null:
		inv.call("add_item", "small_fuse", 1, "a dock crate")
	add_log("Found a Small Fuse — this should fit the door panel.")
	advance_air_quest()


func find_large_fuse() -> void:
	var inv: Node = _inv()
	if inv != null:
		inv.call("add_item", "large_fuse", 1, "a dock crate")
	add_log("Found a Large Fuse. Too big for the door panel — pocket it anyway.")


# Adds a Bus Fuse to inventory (issue #132). Bus fuses are needed together with
# the large fuse to restore elevator power via the fuse-based restore mechanic.
func find_bus_fuse() -> void:
	var inv: Node = _inv()
	if inv != null:
		inv.call("add_item", "bus_fuse", 1, "a storage crate")
	add_log("Found a Bus Fuse. One of the main-bus fuses Destiny's elevator circuit needs.")


# Generic crate loot for the non-fuse crate: a ration pack the player pockets.
# Stocks the shared resource pool so the dock crate isn't a dead end.
func find_rations() -> void:
	add_resource("rations", 1, "a supply crate")

func diagnose_life_support() -> void:
	if not air_crisis_started:
		add_log("Life support is nominal enough for now. Rush still wants priorities handled.")
		advance_air_quest()
		return
	if life_support_diagnosed:
		add_log("Life support diagnostic already flagged the exposed section and scrubber failure.")
		return
	life_support_diagnosed = true
	add_log("Life support diagnostic: exposed section must be locked off before repairs can hold.")
	advance_air_quest()

func diagnose_scrubber() -> void:
	if not air_crisis_started:
		add_log("The scrubber bank is idle. No emergency repair queued yet.")
		advance_air_quest()
		return
	if scrubber_diagnosed:
		add_log("CO2 scrubber diagnosis confirmed: lime is required for the cartridge mix.")
		return
	scrubber_diagnosed = true
	add_log("CO2 scrubber is cracked. It needs lime before the cartridge bed can reset.")
	advance_air_quest()


# End of the Phase D scrubber scene (Rush opens the wall panel, the crew agree
# lime is the only fix). One call collapses the old player-driven beats: the
# scrubber is diagnosed, Destiny drops from FTL, and the gate dials a known
# lime-bearing world on its own. The objective then becomes "get to the Gate
# Room" (Dr Brody's call) — the Phase E entry point.
func complete_scrubber_scene() -> void:
	if scrubber_diagnosed:
		return
	scrubber_diagnosed = true
	ftl_drop_triggered = true
	var gc: Node = _autoload_node("GameClock")
	ftl_drop_game_time = float(gc.get("elapsed_seconds")) if gc != null else 0.0
	lime_planet_dialed = true
	add_log("Rush: the scrubber's beyond salvage — it needs lime. Destiny lurches out of FTL; the gate dials a lime-bearing world on its own.")
	advance_air_quest()


# Player reaches the Gate Room after Brody's "the gate dialed itself" call.
func report_to_gate() -> void:
	if reported_to_gate:
		return
	reported_to_gate = true
	advance_air_quest()


# Pull a Kino orb from the quarters dispenser. Unlimited supply, but the player
# can carry at most KINO_ORB_MAX at once.
func acquire_kino_orb() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var held: int = int(inv.call("count", "kino_orb"))
	if held >= KINO_ORB_MAX:
		add_log("Can't carry more than %d Kinos at once." % KINO_ORB_MAX)
		return
	held = int(inv.call("add_item", "kino_orb", 1, "the dispenser"))
	add_log("Took a Kino from the dispenser. Carrying %d/%d." % [held, KINO_ORB_MAX])
	advance_air_quest()


# Spend a carried Kino orb (launching one through the gate). Returns false if
# none are in hand.
func consume_kino_orb() -> bool:
	var inv: Node = _inv()
	if inv == null or int(inv.call("count", "kino_orb")) <= 0:
		return false
	inv.call("remove_item", "kino_orb", 1, "launched")
	return true


# Record a Kino left out in the world at `pos` in `scene_path`. FIFO-capped at
# KINO_DEPLOYED_MAX: deploying another past the cap drops the OLDEST tracked
# location.
func deploy_kino(scene_path: String, pos: Vector3) -> void:
	deployed_kinos.append({"scene": scene_path, "x": pos.x, "y": pos.y, "z": pos.z})
	while deployed_kinos.size() > KINO_DEPLOYED_MAX:
		deployed_kinos.pop_front()
	add_log("Kino deployed (%d/%d tracked)." % [deployed_kinos.size(), KINO_DEPLOYED_MAX])
	deployed_kinos_changed.emit()


# World-space positions of Kinos deployed in a given scene (for re-spawn /
# map markers / retrieval). Order is oldest→newest.
func deployed_kinos_in_scene(scene_path: String) -> Array:
	var out: Array = []
	for k in deployed_kinos:
		if String((k as Dictionary).get("scene", "")) == scene_path:
			out.append(Vector3(
				float((k as Dictionary).get("x", 0.0)),
				float((k as Dictionary).get("y", 0.0)),
				float((k as Dictionary).get("z", 0.0))))
	return out


# A launched Kino confirmed what's on the far side of the gate (the SCOUT_KINO
# beat) — clears the way to physically step through and mine.
func complete_kino_scout() -> void:
	if kino_scout_done:
		return
	kino_scout_done = true
	add_log("Kino recon confirmed: breathable atmosphere, lime deposits near the gate.")
	advance_air_quest()

func trigger_ftl_drop() -> void:
	if not scrubber_diagnosed:
		add_log("FTL controls stay locked until the scrubber fault is identified.")
		advance_air_quest()
		return
	if ftl_drop_triggered:
		add_log("Destiny is already out of FTL. Gate systems are available.")
		return
	ftl_drop_triggered = true
	# Stamp the moment so gate_console can compute a stable countdown
	# anchored to GameClock — survives save / resume without depending on
	# wall-clock time. Tolerates GameClock absence so the headless
	# e1_flow.gd test (no autoloads) can still exercise this path.
	var gc: Node = _autoload_node("GameClock")
	ftl_drop_game_time = float(gc.get("elapsed_seconds")) if gc != null else 0.0
	add_log("FTL drop triggered. Destiny falls into normal space near a viable gate address.")
	advance_air_quest()

func dial_lime_planet() -> void:
	if not ftl_drop_triggered:
		add_log("The gate will not dial until Destiny drops from FTL.")
		advance_air_quest()
		return
	if lime_planet_dialed:
		add_log("Lime planet address is already active.")
		return
	lime_planet_dialed = true
	# Dialing a viable address is the moment the destination world is determined:
	# build + persist the PlanetSpec NOW so the surface (biome, resource clusters,
	# hazards) is fixed for this run and survives save/load. The E1 lime run uses
	# the authored air-lime layout; future selectable destinations roll procedurally
	# via build_next_planet_spec(). Skip if a spec was already assembled for this
	# dial (e.g. a resumed save restored active_planet_spec).
	if active_planet_spec.is_empty():
		build_air_lime_spec()
	add_log("Gate Control locks a viable address: lime deposits detected near the landing zone.")
	advance_air_quest()

# Planet-agnostic: "is the Stargate currently dialed/open to a destination?"
# An OPEN gate is a free two-way portal both directions, unlimited crossings,
# UNTIL it closes (KEY RULE — design/gdd/stargate-planetary-runs.md). The window
# opens when a destination is dialed and closes on the terminal world/story
# condition (scrubber_repaired). It deliberately does NOT depend on whether the
# player has crossed back once — that is the separate lime-return story latch
# (returned_from_lime_planet) and must not slam the portal shut.
# Today the only destination is the lime planet, so this reads the lime-dial
# flag; when multiple/selectable destinations land, the dial state generalizes
# behind this same query and callers don't change.
func is_gate_open() -> bool:
	# Post-episode (loop) path: FtlLoop arms gate_window_active when a planet
	# phase starts (via start_gate_window). The loop gate is open whenever a
	# window is active, regardless of E1 story flags. Strictly additive — the
	# E1 branch below is byte-identical to the original.
	if episode_complete and gate_window_active:
		return true
	# E1 path (byte-identical): lime dialed + scrubber not yet repaired.
	return lime_planet_dialed and not scrubber_repaired

# Whether the player on foot may step through to the lime planet right now. The
# open gate alone permits the crossing (two-way, unlimited) for the whole window;
# we keep a quest-span guard so a crossing can't fire before the away-team beat
# (MINE_LIME) or after the gate has been retired by the story (post-REPAIR_SCRUBBER
# → is_gate_open() is already false). The MINE_LIME outbound-success objective
# (carry enough lime back) is enforced separately in planet_gate.gd's to_ship path.
func can_travel_to_lime_planet() -> bool:
	# Post-episode loop: gate_window_active is the open-window condition;
	# is_gate_open() already returns true when that is set + episode_complete.
	if episode_complete:
		return is_gate_open()
	# E1 path (byte-identical).
	return is_gate_open() and (quest_step == QUEST_MINE_LIME \
			or quest_step == QUEST_RETURN_DESTINY \
			or quest_step == QUEST_REPAIR_SCRUBBER)

func return_from_lime_planet() -> void:
	if returned_from_lime_planet:
		return
	returned_from_lime_planet = true
	# The departure window is over once the team is back aboard — stop the clock
	# so it can't keep ticking invisibly (and fire a phantom expiry) in the ship.
	gate_window_active = false
	run_start_resources = {}
	add_log("Returned to Destiny with lime from the planet.")
	advance_air_quest()


# Out of TIME (not health): the departure window closed while the team was still
# on the surface. They scramble back through the still-open gate and make it
# aboard, KEEPING whatever lime they gathered — then Destiny jumps to FTL and the
# gate closes behind them, so this planet can't be re-dialed. This is deliberately
# NOT knock_out(): running out of time is a near-miss, not a downed outcome — the
# infirmary/"goes down" beat is reserved for running out of HEALTH. instant_mode /
# headless flips state without the scene change (so smoke tests don't hang).
func recall_after_window_close() -> void:
	gate_window_active = false
	gate_window_remaining = 0.0
	gate_window_water_drain = 0.0
	_water_drain_accum = 0.0
	# Destiny jumped — the gate is gone. Closing the dial keeps the player from
	# re-entering a planet they can no longer reach.
	lime_planet_dialed = false
	pending_planet_return = true
	if not returned_from_lime_planet:
		returned_from_lime_planet = true
		run_start_resources = {}   # forgiving: keep all gathered lime
		add_log("Destiny jumped to FTL — the away team scrambled back through the gate just in time.")
		advance_air_quest()
	# Notify FtlLoop (and any other listener) that this planet run ended — the
	# loop re-arms the ship phase from this signal. Emitted regardless of
	# headless/instant_mode so the smoke-test hook fires synchronously.
	planet_run_ended.emit()
	var router: Node = _autoload_node("SceneRouter")
	var headless: bool = router == null or router.get("instant_mode") == true
	if headless:
		return
	router.call("change_to", "res://scenes/gate_room.tscn", "FromPlanet")


# --- No-death knockout → med-bay recovery loop (issue #92) -------------------
#
# THE single "downed" entry point. Ship-wide rule: NO DEATH, NO STRANDING — the
# worst outcome on a planet is waking in the infirmary. Every hazard biome calls
# this instead of any death/game-over path. `cause` is a tag
# ("trap", "asphyxiation", "heat", "alarm"/"alien_defense", "window_closed",
# "generic"); it selects a semi-random TJ wake-up line pool and is consumed by
# the infirmary ward spawn.
#
# Consequence (decided): the downed run banks ONLY the minimum-necessary bank of
# the run's scarce target resource (so a run is never a total loss) and forfeits
# every other resource gathered this run plus the remaining window (the run
# ends). Reconciliation is against the run-start snapshot.
#
# Respects SceneRouter.instant_mode: headless flips all state + routes the
# infirmary baton but skips the fade/cutscene so the playthrough doesn't hang.
const KNOCKOUT_TARGET_BANK: int = 1
const _KNOCKOUT_LINES_PATH: String = "res://data/knockout_lines.json"

func knock_out(cause: String = "generic") -> void:
	var tag: String = cause if cause != "" else "generic"
	# Reconcile this run's gathered resources down to the guaranteed minimum of
	# the scarce target; forfeit the rest. Then end the window (run over).
	_reconcile_run_resources_on_knockout()
	gate_window_active = false
	gate_window_remaining = 0.0
	run_start_resources = {}
	# Heal the player fully on wake — health AND oxygen, since asphyxiation is one
	# of the causes.
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	# Arm the infirmary recovery beat: the ward spawns TJ with the cause-tagged
	# line instead of the post-crisis James tableau.
	recovering_in_infirmary = true
	knockout_cause = tag
	add_log("Eli goes down. Everything fades to black…")
	_route_to_infirmary()


# The resource the run was after — the scarcest tracked target, derived from the
# active planet spec's first resource cluster, defaulting to lime (the air-crisis
# resource). This is what a downed run is allowed to bank a minimum of.
func run_target_resource() -> String:
	var spec: Dictionary = active_planet_spec
	var rt: Variant = spec.get("resource_table", {})
	if rt is Dictionary:
		var clusters: Variant = (rt as Dictionary).get("clusters", [])
		if clusters is Array and not (clusters as Array).is_empty():
			var first: Variant = (clusters as Array)[0]
			if first is Dictionary:
				var t: String = String((first as Dictionary).get("type", ""))
				if t != "":
					return t
	return AIR_LIME_RESOURCE


# Forfeit everything gathered this run except the minimum-necessary bank of the
# run's target. Reconciles each tracked resource back to its run-start count;
# the target gets run-start + min(gathered, KNOCKOUT_TARGET_BANK). With no run
# snapshot (e.g. a hazard with no open window) this is a no-op so we never strip
# resources the player legitimately holds.
func _reconcile_run_resources_on_knockout() -> void:
	if run_start_resources.is_empty():
		return
	var inv: Node = _inv()
	if inv == null:
		return
	var target: String = run_target_resource()
	for id in tracked_resource_ids():
		if not run_start_resources.has(id):
			continue
		var start_count: int = int(run_start_resources[id])
		var current: int = resource_count(id)
		var gathered: int = maxi(0, current - start_count)
		var keep: int = start_count
		if id == target:
			keep = start_count + mini(gathered, KNOCKOUT_TARGET_BANK)
		if keep != current:
			inv.call("set_count", id, keep)
			resource_changed.emit(id, keep)


# Route the downed player to the infirmary. Headless / instant_mode flips the
# scene baton + room state directly (no fade, no cutscene) so the playthrough
# doesn't hang. Live play fades to black, then loads the infirmary room.
func _route_to_infirmary() -> void:
	var router: Node = _autoload_node("SceneRouter")
	var headless: bool = router == null or router.get("instant_mode") == true
	next_room_id = "infirmary"
	if headless:
		# Flip state without the cinematic. current_room_id mirrors the load so
		# anything keying off the active room sees the infirmary immediately.
		set_current_room("infirmary")
		return
	router.call("change_to", "res://scenes/room.tscn", "")


# Pick a semi-random TJ wake-up line for the active knockout cause. Reads the
# per-cause pool from data (editable), falling back to "generic" for an unknown
# cause and to a hardcoded safety line only if the data file is missing/empty.
# Returns { "speaker": String, "line": String }.
func knockout_line(cause: String = "") -> Dictionary:
	var tag: String = cause if cause != "" else knockout_cause
	if tag == "":
		tag = "generic"
	var data: Dictionary = _load_knockout_data()
	var speaker: String = String(data.get("speaker", "TJ"))
	var pools: Variant = data.get("pools", {})
	var pool: Array = []
	if pools is Dictionary:
		var picked: Variant = (pools as Dictionary).get(tag, null)
		if picked is Array and not (picked as Array).is_empty():
			pool = picked as Array
		else:
			var fallback: Variant = (pools as Dictionary).get("generic", null)
			if fallback is Array:
				pool = fallback as Array
	var line: String = "You're awake. You took a knock out there — you'll be fine."
	if not pool.is_empty():
		line = String(pool[randi() % pool.size()])
	return {"speaker": speaker, "line": line}


func _load_knockout_data() -> Dictionary:
	if not FileAccess.file_exists(_KNOCKOUT_LINES_PATH):
		return {}
	var f: FileAccess = FileAccess.open(_KNOCKOUT_LINES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


# Called by room.gd when the player leaves the infirmary after a recovery beat,
# so a later (non-knockout) infirmary visit shows the normal James ward.
func clear_infirmary_recovery() -> void:
	recovering_in_infirmary = false
	knockout_cause = ""

func repair_scrubber_with_lime() -> bool:
	if scrubber_repaired:
		add_log("CO2 scrubber is already repaired.")
		return true
	if not scrubber_diagnosed:
		diagnose_scrubber()
		return false
	# One lime fully refills this scrubber; the rest of the haul is for the other
	# scrubbers (see SCRUBBER_REPAIR_LIME_COST / AIR_LIME_REQUIRED).
	if not spend_resource(AIR_LIME_RESOURCE, SCRUBBER_REPAIR_LIME_COST, "CO2 scrubber repair"):
		return false
	scrubber_repaired = true
	scrubber_level = 100.0
	_scrubber_warned = false
	_scrubber_critical = false
	scrubber_level_changed.emit(scrubber_level)
	restore_oxygen(MAX_OXYGEN)
	add_log("CO2 scrubber repaired. Life support is stabilising across this section.")
	complete_episode_air()
	return true

# Phase G: spend one lime to add one bar of charge (33%) back to the scrubber.
# Caps at 100%. No-op when the scrubber isn't repaired yet, already at full,
# or the player has no lime. Returns true if a top-up actually happened.
func top_up_scrubber() -> bool:
	if not scrubber_repaired or scrubber_level >= 100.0:
		return false
	if not spend_resource(AIR_LIME_RESOURCE, 1, "CO2 scrubber top-up"):
		return false
	scrubber_level = minf(100.0, scrubber_level + SCRUBBER_LIME_RECHARGE)
	# Coming back above thresholds re-arms the one-shot warnings.
	if scrubber_level > SCRUBBER_WARN_PERCENT:
		_scrubber_warned = false
	if scrubber_level > 0.0:
		_scrubber_critical = false
	add_log("Topped up the CO2 scrubber. Charge at %d%%." % int(round(scrubber_level)))
	scrubber_level_changed.emit(scrubber_level)
	return true


# --- Optional maintenance scrubber registry ---------------------------------
# One collection, one add/query API (collection-fork policy). State for an unknown
# id lazily defaults to undiscovered/closed/unrepaired so callers never branch on
# "does this key exist yet".

func scrubber_unit_state(id: String) -> Dictionary:
	if not scrubber_units.has(id):
		scrubber_units[id] = {"discovered": false, "open": false, "repaired": false}
	return scrubber_units[id]

func is_scrubber_unit_discovered(id: String) -> bool:
	return scrubber_unit_state(id).get("discovered", false) == true

func is_scrubber_unit_open(id: String) -> bool:
	return scrubber_unit_state(id).get("open", false) == true

func is_scrubber_unit_repaired(id: String) -> bool:
	return scrubber_unit_state(id).get("repaired", false) == true

# First sighting: register the panel as a known POI and slide it open. Returns
# true the first time (so the interactable can play the "found it" beat once).
func discover_scrubber_unit(id: String, label: String = "CO2 Scrubber") -> bool:
	var st: Dictionary = scrubber_unit_state(id)
	if st.get("discovered", false) == true:
		return false
	st["discovered"] = true
	st["open"] = true
	discover_poi("scrubber_" + id, "life_support", label, true)
	add_log("Found a CO2 scrubber access panel — it needs lime to recharge.")
	scrubber_unit_changed.emit(id)
	return true

# Player toggles the access panel open/closed at will (no repair side effect).
func set_scrubber_unit_open(id: String, want_open: bool) -> void:
	var st: Dictionary = scrubber_unit_state(id)
	if (st.get("open", false) == true) == want_open:
		return
	st["open"] = want_open
	scrubber_unit_changed.emit(id)

# Drop one lime into an aux scrubber. Succeeds only if discovered, not already
# repaired, and the player has lime. On success the panel auto-slides SHUT.
func repair_scrubber_unit(id: String) -> bool:
	var st: Dictionary = scrubber_unit_state(id)
	if st.get("repaired", false) == true:
		return false
	if not spend_resource(AIR_LIME_RESOURCE, SCRUBBER_REPAIR_LIME_COST, "scrubber recharge"):
		return false
	st["repaired"] = true
	st["open"] = false          # the panel slides shut once the cartridge is seated
	st["discovered"] = true
	add_log("Recharged a CO2 scrubber. The access panel slides shut.")
	scrubber_unit_changed.emit(id)
	return true

# How many of the optional units are repaired (for UI / completion flavor).
func aux_scrubbers_repaired_count() -> int:
	var n: int = 0
	for row in AUX_SCRUBBERS:
		if is_scrubber_unit_repaired(String((row as Dictionary).get("id", ""))):
			n += 1
	return n


# Green-bar count (0–3) for the scrubber panel gauge, derived from
# scrubber_level. 0%→0, 33%→1, 66%→2, 100%→3. Phase G decay of scrubber_level
# will make this drop back through 2 and 1 over time.
func scrubber_green_bars() -> int:
	return clampi(roundi(scrubber_level / (100.0 / 3.0)), 0, 3)

# Episode 1 completion now happens after the Air crisis loop resolves, not at
# the old Rush + Kino + quarters + breach milestone.
func check_episode_complete() -> void:
	if scrubber_repaired:
		complete_episode_air()

func complete_episode_air() -> void:
	if episode_complete:
		return
	episode_complete = true
	add_log("Episode 1 complete: Destiny can breathe again.")
	episode_completed.emit()
	# Drive the active-step transition through QuestLog so the legacy
	# quest_step_changed + objective_changed signals fire via the normal
	# bridge (_on_quest_log_step_changed). The terminal "complete" step's
	# objective text comes from data/quests.json.
	advance_air_quest()
	# Autoload-tolerant fallback: tests without QuestLog still want to
	# observe quest_step == QUEST_COMPLETE + the legacy signals fire so
	# the e1_flow assertions keep passing under the manual GameState
	# construction pattern.
	if _autoload_node("QuestLog") == null:
		var changed: bool = quest_step != QUEST_COMPLETE
		quest_step = QUEST_COMPLETE
		current_objective = "Episode 1: Air — Complete"
		objective_changed.emit(current_objective)
		if changed:
			quest_step_changed.emit(QUEST_COMPLETE)

# --- save / wipe -------------------------------------------------------------
#
# File I/O lives on SaveManager — this autoload only owns its serialize /
# deserialize contract per the ISaveableSystem pattern in
# design/gdd/save-load-interface.md. SaveManager auto-saves on every
# objective_changed + current_room_changed emit and rotates 3 backups for
# corruption recovery.

func has_save() -> bool:
	# Forward to SaveManager when autoloads are active; gracefully report
	# "no save" in script tests where the SaveManager autoload is absent.
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("has_save"):
		return sm.call("has_save") == true
	return false


func serialize() -> Dictionary:
	return {
		"health": health,
		"oxygen": oxygen,
		"current_episode": current_episode,
		"quest_step": quest_step,
		# Items (kino remote, kino orbs, fuses, lime, rations) are persisted by
		# the Inventory system's own block, not here.
		"quarters_found": quarters_found,
		"eli_quarters_visited": eli_quarters_visited,
		"elevator_repaired": elevator_repaired,
		# Duplicate every collection so a downstream reset() can't mutate
		# the snapshot through a shared reference (caught by the e1_flow
		# round-trip test before it became a save-corruption bug).
		"rooms_discovered": rooms_discovered.duplicate(),
		"rooms_deciphered": rooms_deciphered.duplicate(),
		"doors_traversed": doors_traversed.duplicate(),
		"discovered_pois": discovered_pois.duplicate(true),
		"breaches_sealed": breaches_sealed.duplicate(),
		"current_room_id": current_room_id,
		"objective": current_objective,
		"episode_complete": episode_complete,
		"log_entries": log_entries.duplicate(),
		"met_scott": met_scott,
		"met_rush": met_rush,
		"pressure_suits_found": pressure_suits_found,
		"prologue_complete": prologue_complete,
		"air_crisis_started": air_crisis_started,
		"control_room_returned": control_room_returned,
		"blocked_door_beat_done": blocked_door_beat_done,
		"door_panel_examined": door_panel_examined,
		"life_support_diagnosed": life_support_diagnosed,
		"scrubber_diagnosed": scrubber_diagnosed,
		"scrubber_repaired": scrubber_repaired,
		"scrubber_level": scrubber_level,
		"scrubber_units": scrubber_units.duplicate(true),
		"ftl_drop_triggered": ftl_drop_triggered,
		"ftl_drop_game_time": ftl_drop_game_time,
		"lime_planet_dialed": lime_planet_dialed,
		"reported_to_gate": reported_to_gate,
		"deployed_kinos": deployed_kinos.duplicate(true),
		"kino_scout_done": kino_scout_done,
		"kino_plan_approved": kino_plan_approved,
		"away_party_briefed": away_party_briefed,
		"returned_from_lime_planet": returned_from_lime_planet,
		# Active procedural-planet spec — deep-duplicated so a later reset() can't
		# mutate the snapshot through the shared resource_table / hazard_params dicts.
		"active_planet_spec": active_planet_spec.duplicate(true),
		"planets_dialed": planets_dialed,
		"gate_window_active": gate_window_active,
		"gate_window_remaining": gate_window_remaining,
		"gate_window_water_drain": gate_window_water_drain,
		"run_start_resources": run_start_resources.duplicate(true),
		"recovering_in_infirmary": recovering_in_infirmary,
		"knockout_cause": knockout_cause,
		"kino_pan_x": kino_pan_x,
		"kino_pan_y": kino_pan_y,
		"kino_zoom": kino_zoom,
		"kino_active_floor": kino_active_floor,
		"kino_marker": kino_marker.duplicate(true),
		"compass_show_lime": compass_show_lime,
		"compass_show_kinos": compass_show_kinos,
		"compass_show_companions": compass_show_companions,
		"compass_show_gate": compass_show_gate,
		"compass_show_pois": compass_show_pois,
		# FTL loop duration overrides (#130 / #133). -1 means "use base const".
		"ship_phase_override": ship_phase_override,
		"planet_window_override": planet_window_override,
		# Consumption scaling scalars (issue #134).
		"crew_count": crew_count,
		"active_sections": active_sections,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	health = float(data.get("health", MAX_HEALTH))
	oxygen = float(data.get("oxygen", MAX_OXYGEN))
	current_episode = String(data.get("current_episode", EPISODE_AIR))
	quest_step = String(data.get("quest_step", QUEST_TALK_SCOTT))
	quarters_found = data.get("quarters_found", false) == true
	eli_quarters_visited = data.get("eli_quarters_visited", false) == true
	elevator_repaired = data.get("elevator_repaired", false) == true
	episode_complete = data.get("episode_complete", false) == true
	current_room_id = String(data.get("current_room_id", ""))
	current_objective = String(data.get("objective", current_objective))
	met_scott = data.get("met_scott", false) == true
	met_rush = data.get("met_rush", false) == true
	pressure_suits_found = data.get("pressure_suits_found", false) == true
	prologue_complete = data.get("prologue_complete", false) == true
	air_crisis_started = data.get("air_crisis_started", false) == true
	control_room_returned = data.get("control_room_returned", false) == true
	blocked_door_beat_done = data.get("blocked_door_beat_done", false) == true
	door_panel_examined = data.get("door_panel_examined", false) == true
	life_support_diagnosed = data.get("life_support_diagnosed", false) == true
	scrubber_diagnosed = data.get("scrubber_diagnosed", false) == true
	scrubber_repaired = data.get("scrubber_repaired", false) == true
	scrubber_level = float(data.get("scrubber_level", 0.0))
	var su: Variant = data.get("scrubber_units", {})
	scrubber_units = (su as Dictionary).duplicate(true) if su is Dictionary else {}
	ftl_drop_triggered = data.get("ftl_drop_triggered", false) == true
	ftl_drop_game_time = float(data.get("ftl_drop_game_time", -1.0))
	lime_planet_dialed = data.get("lime_planet_dialed", false) == true
	reported_to_gate = data.get("reported_to_gate", false) == true
	deployed_kinos.clear()
	var loaded_kinos: Variant = data.get("deployed_kinos", [])
	if loaded_kinos is Array:
		for k in loaded_kinos:
			if k is Dictionary:
				deployed_kinos.append({
					"scene": String((k as Dictionary).get("scene", "")),
					"x": float((k as Dictionary).get("x", 0.0)),
					"y": float((k as Dictionary).get("y", 0.0)),
					"z": float((k as Dictionary).get("z", 0.0)),
				})
	kino_scout_done = data.get("kino_scout_done", false) == true
	kino_plan_approved = data.get("kino_plan_approved", false) == true
	away_party_briefed = data.get("away_party_briefed", false) == true
	returned_from_lime_planet = data.get("returned_from_lime_planet", false) == true
	var saved_spec: Variant = data.get("active_planet_spec", {})
	active_planet_spec = (saved_spec as Dictionary).duplicate(true) if saved_spec is Dictionary else {}
	planets_dialed = int(data.get("planets_dialed", 0))
	gate_window_active = data.get("gate_window_active", false) == true
	gate_window_remaining = float(data.get("gate_window_remaining", 0.0))
	gate_window_water_drain = float(data.get("gate_window_water_drain", 0.0))
	_water_drain_accum = 0.0
	run_start_resources = {}
	var saved_run_res: Variant = data.get("run_start_resources", {})
	if saved_run_res is Dictionary:
		for k in (saved_run_res as Dictionary).keys():
			run_start_resources[String(k)] = int((saved_run_res as Dictionary)[k])
	recovering_in_infirmary = data.get("recovering_in_infirmary", false) == true
	knockout_cause = String(data.get("knockout_cause", ""))
	# --- legacy item migration ---------------------------------------------
	# Pre-store saves kept items here (kino_acquired / *_fuse_found / kino_orbs
	# / a `resources` dict). Seed the Inventory pool from them. Runs BEFORE the
	# Inventory system's own deserialize (registration order = game_state then
	# inventory), and Inventory.deserialize leaves the seed intact when the save
	# has no "inventory" block (old saves). New saves carry no legacy keys here,
	# so this is a no-op for them.
	var inv: Node = _inv()
	if inv != null:
		if data.has("kino_acquired") and data.get("kino_acquired") == true:
			inv.call("set_count", "kino_remote", 1)
		if data.has("small_fuse_found") and data.get("small_fuse_found") == true:
			inv.call("set_count", "small_fuse", 1)
		if data.has("large_fuse_found") and data.get("large_fuse_found") == true:
			inv.call("set_count", "large_fuse", 1)
		if data.has("kino_orbs"):
			inv.call("set_count", "kino_orb", int(data.get("kino_orbs", 0)))
		var loaded_resources: Variant = data.get("resources", {})
		if loaded_resources is Dictionary:
			for key in (loaded_resources as Dictionary).keys():
				inv.call("set_count", String(key), int((loaded_resources as Dictionary)[key]))
	rooms_discovered.clear()
	for r in data.get("rooms_discovered", []):
		rooms_discovered.append(String(r))
	rooms_deciphered.clear()
	for r in data.get("rooms_deciphered", []):
		rooms_deciphered.append(String(r))
	doors_traversed.clear()
	for d in data.get("doors_traversed", []):
		doors_traversed.append(String(d))
	discovered_pois.clear()
	var saved_pois: Variant = data.get("discovered_pois", null)
	if saved_pois is Dictionary:
		for k in (saved_pois as Dictionary).keys():
			var rec: Variant = (saved_pois as Dictionary)[k]
			if rec is Dictionary:
				discovered_pois[String(k)] = {
					"category": String((rec as Dictionary).get("category", AIR_LIME_RESOURCE)),
					"label": String((rec as Dictionary).get("label", "Point of interest")),
				}
	else:
		# Back-compat: pre-POI saves stored a flat "lime_discovered" name array.
		for lk in data.get("lime_discovered", []):
			discovered_pois[String(lk)] = {"category": AIR_LIME_RESOURCE, "label": "Lime deposit"}
	breaches_sealed.clear()
	for b in data.get("breaches_sealed", []):
		breaches_sealed.append(String(b))
	log_entries.clear()
	for l in data.get("log_entries", []):
		log_entries.append(String(l))
	kino_pan_x = float(data.get("kino_pan_x", 0.0))
	kino_pan_y = float(data.get("kino_pan_y", 0.0))
	kino_zoom = float(data.get("kino_zoom", 1.0))
	kino_active_floor = int(data.get("kino_active_floor", -1))
	var marker_raw: Variant = data.get("kino_marker", {})
	kino_marker = marker_raw if marker_raw is Dictionary else {}
	compass_show_lime = data.get("compass_show_lime", true) == true
	compass_show_kinos = data.get("compass_show_kinos", true) == true
	compass_show_companions = data.get("compass_show_companions", true) == true
	compass_show_gate = data.get("compass_show_gate", true) == true
	compass_show_pois = data.get("compass_show_pois", true) == true
	# FTL loop duration overrides (#130 / #133).
	ship_phase_override = float(data.get("ship_phase_override", -1.0))
	planet_window_override = float(data.get("planet_window_override", -1.0))
	# Consumption scaling scalars (issue #134).
	crew_count = int(data.get("crew_count", 6))
	active_sections = int(data.get("active_sections", 3))
	advance_air_quest()
	# Republish so the HUD, Kino, and quest waypoint pick up loaded values.
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(inv != null and inv.call("has", "kino_remote"))
