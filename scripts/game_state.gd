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
signal lime_discovered_changed()
# Fires whenever an inventoried resource count changes (mining, top-up,
# scrubber repair, etc.). Drives the planet-side lime objective counter
# and any future resource HUD.
signal resource_changed(type: String, count: int)
# Fires whenever scrubber_level changes (decay tick or top-up). Drives the
# in-world bar gauge + the Kino System Status readout.
signal scrubber_level_changed(level: float)
# Fired when the player enters a new room. Drives the Kino Remote player
# marker and the in-world quest-waypoint diamond's re-targeting.
signal current_room_changed(room_id: String)
signal kino_changed(acquired: bool)
signal episode_completed()
signal log_added(line: String)
# Fired by npc.gd each time a dialogue line is shown. The HUD listens and
# renders the line inside the sci-fi dialog panel; log_added still captures
# the same text for the journal.
signal dialogue_shown(character_name: String, line: String)
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
const AIR_LIME_REQUIRED: int = 3
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

var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var current_episode: String = EPISODE_AIR
var quest_step: String = QUEST_TALK_SCOTT
var kino_acquired: bool = false  # @collection-ok: pre-#41 item fork — migrates into the Inventory registry
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
# Stable keys ("min_room_id|max_room_id") of doors the player has walked
# through. Both directions resolve to the same key via door_key(). Drives the
# Kino map's bright-vs-dim pip styling and survives save/load.
var doors_traversed: Array[String] = []
# Stable keys (the deterministic node name, e.g. "LimeNode3") of lime deposits
# the team has spotted — on foot or via a passing Kino. Only discovered deposits
# show on the planet compass (F3). The planet seed is fixed, so a given key
# always maps to the same world position, and discovery survives save/load.
var lime_discovered: Array[String] = []
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
# Fuses looted from the Shuttle Dock crates. The jammed door panel needs a
# SMALL fuse; a large fuse also turns up (wrong size for the door — kept for
# flavor / future use). One crate holds the small fuse the player needs.
var small_fuse_found: bool = false  # @collection-ok: pre-#41 item fork — migrates into the Inventory registry
var large_fuse_found: bool = false  # @collection-ok: pre-#41 item fork — migrates into the Inventory registry
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
var ftl_drop_triggered: bool = false
var lime_planet_dialed: bool = false
# True once the player reaches the Gate Room after Dr Brody's "the gate
# dialed itself" call (the GO_TO_GATE beat that ends the CO2 scrubber scene).
var reported_to_gate: bool = false
# Kino orbs the player is carrying. The quarters dispenser is unlimited but the
# player can hold at most KINO_ORB_MAX; launching one (Kino Control) spends it.
var kino_orbs: int = 0
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
var resources: Dictionary = {AIR_LIME_RESOURCE: 0}
# E1 story milestones — set by NPC interacts (npc.gd via met_flag).
# met_scott: Lt Scott briefs the player on arrival; gates objective priority
# to "Find a Map" once true.
# met_rush: Player reaches Dr Rush in the control interface room; combined
# with kino + quarters + breach, this is the E1 completion gate.
var met_scott: bool = false
var met_rush: bool = false

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
	if not scrubber_repaired:
		return
	var router: Node = _autoload_node("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	_tick_scrubber(delta)


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
	kino_acquired = false
	quarters_found = false
	eli_quarters_visited = false
	elevator_repaired = false
	rooms_discovered.clear()
	doors_traversed.clear()
	lime_discovered.clear()
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
	small_fuse_found = false
	large_fuse_found = false
	life_support_diagnosed = false
	scrubber_diagnosed = false
	scrubber_repaired = false
	scrubber_level = 0.0
	_scrubber_warned = false
	_scrubber_critical = false
	ftl_drop_triggered = false
	lime_planet_dialed = false
	reported_to_gate = false
	kino_orbs = 0
	deployed_kinos.clear()
	kino_scout_done = false
	kino_plan_approved = false
	away_party_briefed = false
	returned_from_lime_planet = false
	resources.clear()
	resources[AIR_LIME_RESOURCE] = 0
	met_scott = false
	met_rush = false
	ftl_drop_game_time = -1.0
	kino_pan_x = 0.0
	kino_pan_y = 0.0
	kino_zoom = 1.0
	kino_active_floor = -1
	kino_marker = {}
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
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	kino_changed.emit(kino_acquired)
	# Wipe QuestLog progress so the e1_air quest restarts at step 1 with no
	# completed_steps carried over. autoload-tolerant: tests without QuestLog
	# in the tree skip this and rely on quest_step's `= QUEST_TALK_SCOTT`
	# default.
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("reset"):
		ql.call("reset")
	advance_air_quest()

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

# Mark a lime deposit as spotted (by the player or a passing Kino). Idempotent;
# emits lime_discovered_changed so an open compass refreshes live.
func discover_lime(key: String) -> void:
	if key == "" or lime_discovered.has(key):
		return
	lime_discovered.append(key)
	lime_discovered_changed.emit()

func is_lime_discovered(key: String) -> bool:
	return lime_discovered.has(key)


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
	if kino_acquired:
		return
	kino_acquired = true
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

func add_log(line: String) -> void:
	log_entries.append(line)
	log_added.emit(line)

func resource_count(type: String) -> int:
	return int(resources.get(type, 0))

func add_resource(type: String, amount: int, source: String = "") -> bool:
	if amount <= 0:
		return false
	var next_amount: int = resource_count(type) + amount
	resources[type] = next_amount
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
	resources[type] = current - amount
	var reason_suffix: String = "" if reason == "" else " for " + reason
	add_log("Spent %d %s%s. Remaining: %d." % [amount, type, reason_suffix, resource_count(type)])
	resource_changed.emit(type, resource_count(type))
	advance_air_quest()
	return true

func can_start_air_crisis() -> bool:
	return met_rush and eli_quarters_visited and kino_acquired and not air_crisis_started

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
	if small_fuse_found:
		return
	small_fuse_found = true
	add_log("Found a Small Fuse — this should fit the door panel.")
	advance_air_quest()


func find_large_fuse() -> void:
	if large_fuse_found:
		return
	large_fuse_found = true
	add_log("Found a Large Fuse. Too big for the door panel — pocket it anyway.")


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
	if kino_orbs >= KINO_ORB_MAX:
		add_log("Can't carry more than %d Kinos at once." % KINO_ORB_MAX)
		return
	kino_orbs += 1
	add_log("Took a Kino from the dispenser. Carrying %d/%d." % [kino_orbs, KINO_ORB_MAX])
	advance_air_quest()


# Spend a carried Kino orb (launching one through the gate). Returns false if
# none are in hand.
func consume_kino_orb() -> bool:
	if kino_orbs <= 0:
		return false
	kino_orbs -= 1
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
	add_log("Gate Control locks a viable address: lime deposits detected near the landing zone.")
	advance_air_quest()

func is_lime_gate_open() -> bool:
	return lime_planet_dialed and not returned_from_lime_planet and not scrubber_repaired

func can_travel_to_lime_planet() -> bool:
	return is_lime_gate_open() and (quest_step == QUEST_MINE_LIME or quest_step == QUEST_RETURN_DESTINY)

func return_from_lime_planet() -> void:
	if returned_from_lime_planet:
		return
	returned_from_lime_planet = true
	add_log("Returned to Destiny with lime from the planet.")
	advance_air_quest()

func repair_scrubber_with_lime() -> bool:
	if scrubber_repaired:
		add_log("CO2 scrubber is already repaired.")
		return true
	if not scrubber_diagnosed:
		diagnose_scrubber()
		return false
	if not spend_resource(AIR_LIME_RESOURCE, AIR_LIME_REQUIRED, "CO2 scrubber repair"):
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
		"kino_acquired": kino_acquired,
		"quarters_found": quarters_found,
		"eli_quarters_visited": eli_quarters_visited,
		"elevator_repaired": elevator_repaired,
		# Duplicate every collection so a downstream reset() can't mutate
		# the snapshot through a shared reference (caught by the e1_flow
		# round-trip test before it became a save-corruption bug).
		"rooms_discovered": rooms_discovered.duplicate(),
		"doors_traversed": doors_traversed.duplicate(),
		"lime_discovered": lime_discovered.duplicate(),
		"breaches_sealed": breaches_sealed.duplicate(),
		"current_room_id": current_room_id,
		"objective": current_objective,
		"episode_complete": episode_complete,
		"log_entries": log_entries.duplicate(),
		"met_scott": met_scott,
		"met_rush": met_rush,
		"prologue_complete": prologue_complete,
		"air_crisis_started": air_crisis_started,
		"control_room_returned": control_room_returned,
		"blocked_door_beat_done": blocked_door_beat_done,
		"door_panel_examined": door_panel_examined,
		"small_fuse_found": small_fuse_found,
		"large_fuse_found": large_fuse_found,
		"life_support_diagnosed": life_support_diagnosed,
		"scrubber_diagnosed": scrubber_diagnosed,
		"scrubber_repaired": scrubber_repaired,
		"scrubber_level": scrubber_level,
		"ftl_drop_triggered": ftl_drop_triggered,
		"ftl_drop_game_time": ftl_drop_game_time,
		"lime_planet_dialed": lime_planet_dialed,
		"reported_to_gate": reported_to_gate,
		"kino_orbs": kino_orbs,
		"deployed_kinos": deployed_kinos.duplicate(true),
		"kino_scout_done": kino_scout_done,
		"kino_plan_approved": kino_plan_approved,
		"away_party_briefed": away_party_briefed,
		"returned_from_lime_planet": returned_from_lime_planet,
		"resources": resources.duplicate(true),
		"kino_pan_x": kino_pan_x,
		"kino_pan_y": kino_pan_y,
		"kino_zoom": kino_zoom,
		"kino_active_floor": kino_active_floor,
		"kino_marker": kino_marker.duplicate(true),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	health = float(data.get("health", MAX_HEALTH))
	oxygen = float(data.get("oxygen", MAX_OXYGEN))
	current_episode = String(data.get("current_episode", EPISODE_AIR))
	quest_step = String(data.get("quest_step", QUEST_TALK_SCOTT))
	kino_acquired = data.get("kino_acquired", false) == true
	quarters_found = data.get("quarters_found", false) == true
	eli_quarters_visited = data.get("eli_quarters_visited", false) == true
	elevator_repaired = data.get("elevator_repaired", false) == true
	episode_complete = data.get("episode_complete", false) == true
	current_room_id = String(data.get("current_room_id", ""))
	current_objective = String(data.get("objective", current_objective))
	met_scott = data.get("met_scott", false) == true
	met_rush = data.get("met_rush", false) == true
	prologue_complete = data.get("prologue_complete", false) == true
	air_crisis_started = data.get("air_crisis_started", false) == true
	control_room_returned = data.get("control_room_returned", false) == true
	blocked_door_beat_done = data.get("blocked_door_beat_done", false) == true
	door_panel_examined = data.get("door_panel_examined", false) == true
	small_fuse_found = data.get("small_fuse_found", false) == true
	large_fuse_found = data.get("large_fuse_found", false) == true
	life_support_diagnosed = data.get("life_support_diagnosed", false) == true
	scrubber_diagnosed = data.get("scrubber_diagnosed", false) == true
	scrubber_repaired = data.get("scrubber_repaired", false) == true
	scrubber_level = float(data.get("scrubber_level", 0.0))
	ftl_drop_triggered = data.get("ftl_drop_triggered", false) == true
	ftl_drop_game_time = float(data.get("ftl_drop_game_time", -1.0))
	lime_planet_dialed = data.get("lime_planet_dialed", false) == true
	reported_to_gate = data.get("reported_to_gate", false) == true
	kino_orbs = int(data.get("kino_orbs", 0))
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
	resources.clear()
	var loaded_resources: Variant = data.get("resources", {})
	if loaded_resources is Dictionary:
		for key in (loaded_resources as Dictionary).keys():
			resources[String(key)] = int((loaded_resources as Dictionary)[key])
	if not resources.has(AIR_LIME_RESOURCE):
		resources[AIR_LIME_RESOURCE] = 0
	rooms_discovered.clear()
	for r in data.get("rooms_discovered", []):
		rooms_discovered.append(String(r))
	doors_traversed.clear()
	for d in data.get("doors_traversed", []):
		doors_traversed.append(String(d))
	lime_discovered.clear()
	for lk in data.get("lime_discovered", []):
		lime_discovered.append(String(lk))
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
	advance_air_quest()
	# Republish so the HUD, Kino, and quest waypoint pick up loaded values.
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(kino_acquired)
