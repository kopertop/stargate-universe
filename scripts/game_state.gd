extends Node

# Global persistent game state. Cross-scene singleton.
# Survives scene_router transitions; reset() returns to clean E1 start.

signal health_changed(value: float)
signal oxygen_changed(value: float)
signal objective_changed(text: String)
signal room_discovered(room_id: String)
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

const MAX_HEALTH: float = 100.0
const MAX_OXYGEN: float = 100.0

const EPISODE_AIR: String = "air"
const QUEST_TALK_SCOTT: String = "talk_scott"
const QUEST_FIND_RUSH: String = "find_rush"
const QUEST_FIND_REST: String = "find_rest"
const QUEST_FIND_KINO: String = "find_kino"
const QUEST_RESTORE_POWER: String = "restore_power"
const QUEST_FIND_QUARTERS: String = "find_quarters"
const QUEST_SLEEP: String = "sleep"
const QUEST_RETURN_TO_CONTROL: String = "return_to_control"
const QUEST_DIAGNOSE_LIFE_SUPPORT: String = "diagnose_life_support"
const QUEST_SEAL_BREACH: String = "seal_breach"
const QUEST_FIND_SCRUBBER: String = "find_scrubber"
const QUEST_WAIT_FTL: String = "wait_ftl"
const QUEST_DIAL_LIME_PLANET: String = "dial_lime_planet"
const QUEST_MINE_LIME: String = "mine_lime"
const QUEST_RETURN_DESTINY: String = "return_destiny"
const QUEST_REPAIR_SCRUBBER: String = "repair_scrubber"
const QUEST_COMPLETE: String = "complete"
const AIR_LIME_RESOURCE: String = "lime"
const AIR_LIME_REQUIRED: int = 3

const QUEST_LABELS: Dictionary = {
	QUEST_TALK_SCOTT: "Talk to Scott",
	QUEST_FIND_RUSH: "Find Rush",
	QUEST_FIND_REST: "Find a place to rest",
	QUEST_FIND_KINO: "Inspect the strange device",
	QUEST_RESTORE_POWER: "Restore main power",
	QUEST_FIND_QUARTERS: "Find quarters",
	QUEST_SLEEP: "Sleep",
	QUEST_RETURN_TO_CONTROL: "Return to the Control Room",
	QUEST_DIAGNOSE_LIFE_SUPPORT: "Access a control terminal",
	QUEST_SEAL_BREACH: "Seal the jammed door",
	QUEST_FIND_SCRUBBER: "Find CO2 scrubber",
	QUEST_WAIT_FTL: "Trigger FTL drop",
	QUEST_DIAL_LIME_PLANET: "Dial lime planet",
	QUEST_MINE_LIME: "Mine lime",
	QUEST_RETURN_DESTINY: "Return to Destiny",
	QUEST_REPAIR_SCRUBBER: "Repair CO2 scrubber",
	QUEST_COMPLETE: "Episode complete",
}

# Where each quest step's diamond should anchor. The room field names a row in
# data/ship_layout.json; the anchor field names a Node already spawned by
# room.gd / gate_room.gd (matched by Node.name). When `anchor` is empty the
# waypoint pins to the room itself (door of entry); when both fields are empty
# the waypoint is hidden (off-ship or completion states).
const QUEST_TARGETS: Dictionary = {
	QUEST_TALK_SCOTT: {"room": "gate_room", "anchor": "LtScott"},
	QUEST_FIND_RUSH: {"room": "control_interface_room", "anchor": "DrRush"},
	QUEST_FIND_REST: {"room": "eli_quarters", "anchor": ""},
	QUEST_FIND_KINO: {"room": "eli_quarters", "anchor": "KinoPickup"},
	QUEST_RESTORE_POWER: {"room": "engineering_bay", "anchor": "PowerConsole"},
	QUEST_FIND_QUARTERS: {"room": "quarters_room_1", "anchor": ""},
	QUEST_SLEEP: {"room": "eli_quarters", "anchor": "Bed"},
	QUEST_RETURN_TO_CONTROL: {"room": "control_interface_room", "anchor": ""},
	QUEST_DIAGNOSE_LIFE_SUPPORT: {"room": "control_interface_room", "anchor": "ControlConsoleNearest"},
	QUEST_SEAL_BREACH: {"room": "breached_section_south", "anchor": "HullSealSwitch"},
	QUEST_FIND_SCRUBBER: {"room": "hydroponics", "anchor": "CO2Scrubber"},
	QUEST_WAIT_FTL: {"room": "gate_room", "anchor": "FTLConsole"},
	QUEST_DIAL_LIME_PLANET: {"room": "gate_room", "anchor": "GateControlConsole"},
	QUEST_MINE_LIME: {"room": "", "anchor": ""},  # offworld — hide waypoint
	QUEST_RETURN_DESTINY: {"room": "", "anchor": ""},  # offworld — hide waypoint
	QUEST_REPAIR_SCRUBBER: {"room": "hydroponics", "anchor": "CO2Scrubber"},
	QUEST_COMPLETE: {"room": "", "anchor": ""},
}

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

var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var current_episode: String = EPISODE_AIR
var quest_step: String = QUEST_TALK_SCOTT
var kino_acquired: bool = false
var quarters_found: bool = false
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
var scrubber_diagnosed: bool = false
var scrubber_repaired: bool = false
var ftl_drop_triggered: bool = false
var lime_planet_dialed: bool = false
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


func _ready() -> void:
	# Autoload-tolerant: e1_flow.gd and other -s SceneTree script tests
	# instantiate GameState directly with no SaveManager in the tree.
	# `/root/SaveManager` resolves to the live autoload in real runs and
	# returns null in script tests, which we accept silently.
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "game_state", self)


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
	life_support_diagnosed = false
	scrubber_diagnosed = false
	scrubber_repaired = false
	ftl_drop_triggered = false
	lime_planet_dialed = false
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
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	kino_changed.emit(kino_acquired)
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

func advance_air_quest() -> void:
	_set_quest_step(_next_air_quest_step())

func _next_air_quest_step() -> String:
	if episode_complete or scrubber_repaired:
		return QUEST_COMPLETE
	if not met_scott:
		return QUEST_TALK_SCOTT
	if not met_rush:
		return QUEST_FIND_RUSH
	if not eli_quarters_visited:
		return QUEST_FIND_REST
	if not kino_acquired:
		return QUEST_FIND_KINO
	prologue_complete = true
	if not air_crisis_started:
		return QUEST_SLEEP
	if not control_room_returned:
		return QUEST_RETURN_TO_CONTROL
	if not life_support_diagnosed:
		return QUEST_DIAGNOSE_LIFE_SUPPORT
	if breaches_sealed.is_empty():
		return QUEST_SEAL_BREACH
	if not scrubber_diagnosed:
		return QUEST_FIND_SCRUBBER
	if not ftl_drop_triggered:
		return QUEST_WAIT_FTL
	if not lime_planet_dialed:
		return QUEST_DIAL_LIME_PLANET
	if not has_resource(AIR_LIME_RESOURCE, AIR_LIME_REQUIRED):
		return QUEST_MINE_LIME
	if not returned_from_lime_planet:
		return QUEST_RETURN_DESTINY
	if not scrubber_repaired:
		return QUEST_REPAIR_SCRUBBER
	return QUEST_COMPLETE

func _set_quest_step(step: String) -> void:
	quest_step = step
	set_objective(_objective_for_step(step))

func _objective_for_step(step: String) -> String:
	match step:
		QUEST_TALK_SCOTT:
			return "Talk to Lt Scott in the Gate Room."
		QUEST_FIND_RUSH:
			return "Find Dr Rush in the Control Interface Room."
		QUEST_FIND_REST:
			return "Find a place to rest. Try your quarters."
		QUEST_FIND_KINO:
			return "There's a strange device on your desk. Take a look."
		QUEST_RESTORE_POWER:
			return "Restore main power at the Engineering Bay (south of cr corridor)."
		QUEST_FIND_QUARTERS:
			return "Take the elevator to the upper deck: find Crew Quarters Alpha."
		QUEST_SLEEP:
			return "Get some rest. Lay down on the bed in your quarters."
		QUEST_RETURN_TO_CONTROL:
			return "Scott's orders: get to the Control Interface Room and find Rush."
		QUEST_DIAGNOSE_LIFE_SUPPORT:
			return "Access a control terminal in the Control Interface Room."
		QUEST_SEAL_BREACH:
			return "Head south to the Damaged Section and force the jammed bulkhead door shut."
		QUEST_FIND_SCRUBBER:
			return "Find the broken CO2 scrubber in Hydroponics."
		QUEST_WAIT_FTL:
			return "Return to the Gate Room and trigger the FTL drop."
		QUEST_DIAL_LIME_PLANET:
			return "Use Gate Control in the Gate Room to dial the lime planet."
		QUEST_MINE_LIME:
			return "Step through the Stargate and mine lime on the planet."
		QUEST_RETURN_DESTINY:
			return "Return through the planet gate to Destiny."
		QUEST_REPAIR_SCRUBBER:
			return "Bring lime to the CO2 scrubber in Hydroponics."
		QUEST_COMPLETE:
			return "Episode 1: Air — Complete"
		_:
			return "Explore the Destiny."

func quest_step_label(step: String = "") -> String:
	var key: String = quest_step if step == "" else step
	return String(QUEST_LABELS.get(key, key))


# Anchor data for the in-world quest diamond and the Kino Remote target
# marker. Returns {} when the active step has no on-ship target (offworld
# planet steps + completion).
func quest_target(step: String = "") -> Dictionary:
	var key: String = quest_step if step == "" else step
	var entry: Variant = QUEST_TARGETS.get(key, null)
	if entry is Dictionary:
		return entry
	return {}


func set_current_room(room_id: String) -> void:
	if room_id == "" or room_id == current_room_id:
		return
	current_room_id = room_id
	current_room_changed.emit(room_id)

func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)

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
	var gc: Node = get_node_or_null("/root/GameClock")
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
	restore_oxygen(MAX_OXYGEN)
	add_log("CO2 scrubber repaired. Life support is stabilising across this section.")
	complete_episode_air()
	return true

# Episode 1 completion now happens after the Air crisis loop resolves, not at
# the old Rush + Kino + quarters + breach milestone.
func check_episode_complete() -> void:
	if scrubber_repaired:
		complete_episode_air()

func complete_episode_air() -> void:
	if episode_complete:
		return
	quest_step = QUEST_COMPLETE
	episode_complete = true
	set_objective(_objective_for_step(QUEST_COMPLETE))
	add_log("Episode 1 complete: Destiny can breathe again.")
	episode_completed.emit()

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
	var sm: Node = get_node_or_null("/root/SaveManager")
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
		"life_support_diagnosed": life_support_diagnosed,
		"scrubber_diagnosed": scrubber_diagnosed,
		"scrubber_repaired": scrubber_repaired,
		"ftl_drop_triggered": ftl_drop_triggered,
		"ftl_drop_game_time": ftl_drop_game_time,
		"lime_planet_dialed": lime_planet_dialed,
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
	life_support_diagnosed = data.get("life_support_diagnosed", false) == true
	scrubber_diagnosed = data.get("scrubber_diagnosed", false) == true
	scrubber_repaired = data.get("scrubber_repaired", false) == true
	ftl_drop_triggered = data.get("ftl_drop_triggered", false) == true
	ftl_drop_game_time = float(data.get("ftl_drop_game_time", -1.0))
	lime_planet_dialed = data.get("lime_planet_dialed", false) == true
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
