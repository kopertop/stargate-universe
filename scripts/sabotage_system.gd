extends Node

# SabotageSystem — cascading ship failures, sabotage investigation, and moral
# choice for Episode 10: Sabotage.
#
# Systems across Destiny fail one by one — not random breakdowns, but
# deliberate sabotage. Eli must investigate the pattern, identify the
# saboteur, and race against cascading failures. Repair systems while
# gathering evidence. Then face a moral choice: expose the saboteur
# publicly or give a second chance privately.
#
# The system has two parallel tracks:
#   1. Failure Cascade — systems fail in sequence, each with a cascade timer.
#      The player must repair each system before the next failure cascades.
#      Failure timers accelerate over time (acceleration_factor).
#   2. Investigation — each failure site yields a clue. Clues point toward
#      suspects. Once enough evidence is gathered, the player can make an
#      accusation. The moral choice follows the accusation.
#
# Integration:
#   - ShipDamage → apply_damage on each failure event
#   - PowerGrid → set_section_damaged when power systems fail
#   - RelationshipSystem → apply_dialogue_action for moral choice effects
#   - GameState → narrate() for story beats, dialog_action for data-driven
#     clue discovery
#   - QuestLog → quest_step_available checks investigation state
#   - SaveManager → serialize/deserialize for save/load round-trip
#
# Data: res://data/sabotage.json

signal phase_changed(old_phase: int, new_phase: int)
signal failure_triggered(event_id: String, order: int)
signal system_repaired(system: String)
signal clue_discovered(clue_id: String)
signal suspect_interrogated(suspect_id: String)
signal accusation_made(suspect_id: String, is_correct: bool)
signal moral_choice_made(choice_id: String)
signal sabotage_resolved(outcome: String)
signal cascade_timer_changed(time_remaining: float)
signal all_systems_repaired()

const DATA_PATH: String = "res://data/sabotage.json"

# ── Phase enum ────────────────────────────────────────────────────────────────

enum Phase {
	INACTIVE,           # No sabotage event active.
	FIRST_FAILURE,      # First system has failed — investigation begins.
	CASCADE,            # Systems failing in sequence — race against time.
	INVESTIGATION,      # Player is gathering clues and interrogating suspects.
	ACCUSATION,         # Player has enough evidence to accuse.
	MORAL_CHOICE,       # Saboteur identified — player faces the moral choice.
	RESOLVED            # Episode resolved (exposed or second_chance).
}

# ── Config ────────────────────────────────────────────────────────────────────

var _scenario: Dictionary = {}
var _failure_events: Dictionary = {}       # event_id → Dictionary
var _ordered_events: Array[String] = []     # event_ids sorted by order
var _clues: Dictionary = {}                 # clue_id → Dictionary
var _suspects: Dictionary = {}             # suspect_id → Dictionary
var _moral_choices: Dictionary = {}        # choice_id → Dictionary
var _repair_requirements: Dictionary = {}
var _cascade_timing: Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────

var _current_phase: int = Phase.INACTIVE
var _active_failures: Dictionary = {}       # system → event_id
var _repaired_systems: Dictionary = {}      # system → true
var _discovered_clues: Dictionary = {}      # clue_id → true
var _interrogated_suspects: Dictionary = {}  # suspect_id → true
var _cascade_timer: float = 0.0
var _next_failure_order: int = 1
var _accused_suspect: String = ""
var _accusation_correct: bool = false
var _moral_choice_id: String = ""
var _resolution_outcome: String = ""
var _loaded: bool = false
var _initialized: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_initialized()
	_register_with_save_manager()

func _ensure_initialized() -> void:
	if _initialized:
		return
	_load_config()
	_initialized = true

func _load_config() -> void:
	if _loaded:
		return
	if not FileAccess.file_exists(DATA_PATH):
		push_error("SabotageSystem: data file not found: " + DATA_PATH)
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("SabotageSystem: cannot open " + DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("SabotageSystem: JSON parse error: " + json.get_error_message())
		return
	var data: Dictionary = json.data as Dictionary
	_scenario = data.get("scenario", {})
	_failure_events = data.get("failure_events", {})
	_clues = data.get("clues", {})
	_suspects = data.get("suspects", {})
	_moral_choices = data.get("moral_choices", {})
	_repair_requirements = data.get("repair_requirements", {})
	_cascade_timing = data.get("cascade_timing", {})
	# Build ordered event list.
	_ordered_events.clear()
	var events_arr: Array = []
	for eid in _failure_events.keys():
		events_arr.append(_failure_events[eid])
	events_arr.sort_custom(_compare_event_order)
	for evt in events_arr:
		_ordered_events.append(String(evt.get("id", "")))
	_loaded = true

static func _compare_event_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))

# ── Phase management ──────────────────────────────────────────────────────────

func get_phase() -> int:
	return _current_phase

func get_phase_name() -> String:
	match _current_phase:
		Phase.INACTIVE: return "Inactive"
		Phase.FIRST_FAILURE: return "First Failure"
		Phase.CASCADE: return "Cascade"
		Phase.INVESTIGATION: return "Investigation"
		Phase.ACCUSATION: return "Accusation"
		Phase.MORAL_CHOICE: return "Moral Choice"
		Phase.RESOLVED: return "Resolved"
		_: return "Unknown"

func _set_phase(new_phase: int) -> void:
	if _current_phase == new_phase:
		return
	var old: int = _current_phase
	_current_phase = new_phase
	phase_changed.emit(old, new_phase)

## Start the sabotage episode. Sets phase to FIRST_FAILURE and triggers
## the first failure event.
func start_sabotage() -> void:
	_ensure_initialized()
	_next_failure_order = 1
	_active_failures.clear()
	_repaired_systems.clear()
	_discovered_clues.clear()
	_interrogated_suspects.clear()
	_cascade_timer = float(_cascade_timing.get("initial_delay", 300.0))
	_trigger_next_failure()
	_set_phase(Phase.FIRST_FAILURE)

## Advance the cascade timer. Called by _process or test_advance.
func tick_cascade(delta: float) -> void:
	if _current_phase == Phase.INACTIVE or _current_phase == Phase.RESOLVED:
		return
	if _current_phase == Phase.MORAL_CHOICE:
		return
	if _current_phase == Phase.ACCUSATION:
		return
	# While in INVESTIGATION, the cascade timer still ticks — the player
	# is racing against time.
	_cascade_timer = maxf(0.0, _cascade_timer - delta)
	cascade_timer_changed.emit(_cascade_timer)
	if _cascade_timer <= 0.0:
		_trigger_next_failure()

## Trigger the next failure event in the cascade sequence.
func _trigger_next_failure() -> void:
	if _next_failure_order > _ordered_events.size():
		# All failures triggered. If not resolved, ship goes critical.
		return
	var event_id: String = _ordered_events[_next_failure_order - 1]
	var evt: Dictionary = _failure_events.get(event_id, {})
	if evt.is_empty():
		return
	var system: String = String(evt.get("system", ""))
	var room_id: String = String(evt.get("room_id", ""))
	var hull_dmg: float = float(evt.get("hull_damage", 0.0))
	var room_dmg: float = float(evt.get("room_damage", 0.0))
	# Apply damage via ShipDamage.
	_apply_ship_damage(room_id, hull_dmg, room_dmg)
	# Mark system as failed.
	_active_failures[system] = event_id
	# Emit signal.
	failure_triggered.emit(event_id, _next_failure_order)
	# Advance order.
	_next_failure_order += 1
	# Set cascade timer for next failure.
	var delay: float = float(evt.get("cascade_delay", 120.0))
	var accel: float = float(_cascade_timing.get("acceleration_factor", 0.85))
	var min_delay: float = float(_cascade_timing.get("min_delay", 30.0))
	delay = maxf(min_delay, delay * accel)
	_cascade_timer = delay
	# Auto-discover the clue at the failure site.
	var clue_id: String = String(evt.get("clue_id", ""))
	if not clue_id.is_empty() and _clues.has(clue_id):
		discover_clue(clue_id)
	# Transition phase.
	if _current_phase == Phase.FIRST_FAILURE:
		_set_phase(Phase.CASCADE)
	elif _current_phase == Phase.CASCADE:
		pass  # Stay in CASCADE.
	# If this was the first failure and it triggers investigation.
	if bool(evt.get("triggers_investigation", false)) and _current_phase < Phase.INVESTIGATION:
		_set_phase(Phase.INVESTIGATION)

## Apply ship damage via the ShipDamage autoload.
func _apply_ship_damage(room_id: String, hull_dmg: float, room_dmg: float) -> void:
	var sd: Node = _autoload("ShipDamage")
	if sd == null or not sd.has_method("apply_damage"):
		return
	if hull_dmg > 0.0 or room_dmg > 0.0:
		sd.call("apply_damage", room_id, hull_dmg, room_dmg, 1)  # COMBAT source

## Repair a sabotaged system. Returns true if the repair succeeded.
func repair_system(system: String) -> bool:
	if not _active_failures.has(system):
		return false
	if _repaired_systems.has(system):
		return false  # Already repaired.
	# Check repair requirements.
	var req: Dictionary = _repair_requirements.get(system, {})
	var action: String = String(req.get("action", "patch"))
	var parts_cost: int = int(req.get("parts_cost", 0))
	# Check parts via Inventory.
	if parts_cost > 0:
		var inv: Node = _autoload("Inventory")
		if inv != null and inv.has_method("get_item_count"):
			var count: int = int(inv.call("get_item_count", "ship_parts"))
			if count < parts_cost:
				return false  # Not enough parts.
			inv.call("remove_item", "ship_parts", parts_cost)
	# Start repair via ShipDamage.
	var event_id: String = String(_active_failures[system])
	var evt: Dictionary = _failure_events.get(event_id, {})
	var room_id: String = String(evt.get("room_id", ""))
	var sd: Node = _autoload("ShipDamage")
	if sd != null and sd.has_method("start_repair"):
		sd.call("start_repair", room_id, action)
	# Mark as repaired.
	_repaired_systems[system] = true
	system_repaired.emit(system)
	# Check if all sabotaged systems are repaired.
	if _repaired_systems.size() >= _active_failures.size():
		all_systems_repaired.emit()
	# Advance phase if appropriate.
	if _current_phase == Phase.CASCADE:
		_set_phase(Phase.INVESTIGATION)
	return true

## Check if a system has been repaired.
func is_system_repaired(system: String) -> bool:
	return _repaired_systems.has(system)

## Check if a system is currently sabotaged (failed and not yet repaired).
func is_system_failed(system: String) -> bool:
	return _active_failures.has(system) and not _repaired_systems.has(system)

## Get all failed systems (not yet repaired).
func get_failed_systems() -> Array[String]:
	var out: Array[String] = []
	for system in _active_failures.keys():
		if not _repaired_systems.has(system):
			out.append(String(system))
	return out

## Get all repaired systems.
func get_repaired_systems_list() -> Array[String]:
	var out: Array[String] = []
	for system in _repaired_systems.keys():
		out.append(String(system))
	return out

## Get the cascade timer (seconds until next failure).
func get_cascade_timer() -> float:
	return _cascade_timer

## Get the next failure order number.
func get_next_failure_order() -> int:
	return _next_failure_order

## Get the total number of failure events.
func get_total_failures() -> int:
	return _ordered_events.size()

# ── Clue management ───────────────────────────────────────────────────────────

## Discover a clue. Returns true if the clue was newly discovered.
func discover_clue(clue_id: String) -> bool:
	if not _clues.has(clue_id):
		return false
	if _discovered_clues.has(clue_id):
		return false
	_discovered_clues[clue_id] = true
	# Set the world-state flag via GameState.
	var clue: Dictionary = _clues[clue_id] as Dictionary
	var flag: String = String(clue.get("found_flag", ""))
	if not flag.is_empty():
		var gs: Node = _autoload("GameState")
		if gs != null and gs.has_method("set_flag"):
			gs.call("set_flag", flag, true)
	clue_discovered.emit(clue_id)
	# Check if we have enough evidence for accusation.
	_check_accusation_ready()
	return true

## Check if a clue has been discovered.
func is_clue_discovered(clue_id: String) -> bool:
	return _discovered_clues.has(clue_id)

## Get all discovered clue IDs.
func get_discovered_clues() -> Array[String]:
	var out: Array[String] = []
	for cid in _discovered_clues.keys():
		out.append(String(cid))
	return out

## Get clue data.
func get_clue(clue_id: String) -> Dictionary:
	return _clues.get(clue_id, {})

## Get the total evidence strength of discovered clues pointing to a suspect.
func get_evidence_for_suspect(suspect_id: String) -> int:
	var total: int = 0
	for cid in _discovered_clues.keys():
		var clue: Dictionary = _clues.get(String(cid), {})
		var points_to: Array = clue.get("points_to", [])
		if suspect_id in points_to:
			total += int(clue.get("evidence_strength", 0))
	return total

## Get the total evidence strength of all discovered clues.
func get_total_evidence() -> int:
	var total: int = 0
	for cid in _discovered_clues.keys():
		var clue: Dictionary = _clues.get(String(cid), {})
		total += int(clue.get("evidence_strength", 0))
	return total

## Get the number of discovered clues.
func get_discovered_clue_count() -> int:
	return _discovered_clues.size()

## Get the total number of clues.
func get_total_clues() -> int:
	return _clues.size()

# ── Suspect management ────────────────────────────────────────────────────────

## Interrogate a suspect. Returns true if the interrogation succeeded.
func interrogate_suspect(suspect_id: String) -> bool:
	if not _suspects.has(suspect_id):
		return false
	if _interrogated_suspects.has(suspect_id):
		return false
	_interrogated_suspects[suspect_id] = true
	suspect_interrogated.emit(suspect_id)
	_check_accusation_ready()
	return true

## Check if a suspect has been interrogated.
func is_suspect_interrogated(suspect_id: String) -> bool:
	return _interrogated_suspects.has(suspect_id)

## Get suspect data.
func get_suspect(suspect_id: String) -> Dictionary:
	return _suspects.get(suspect_id, {})

## Get all suspect IDs.
func get_suspects() -> Array[String]:
	var out: Array[String] = []
	for sid in _suspects.keys():
		out.append(String(sid))
	return out

## Get the true culprit ID.
func get_true_culprit() -> String:
	return String(_scenario.get("true_culprit", ""))

# ── Accusation ────────────────────────────────────────────────────────────────

## Check if the player has enough evidence to make an accusation.
## Requires at least 3 clues discovered and at least 1 suspect interrogated.
func can_accuse() -> bool:
	return _discovered_clues.size() >= 3 and _interrogated_suspects.size() >= 1

## Check internal state and transition to ACCUSATION if ready.
func _check_accusation_ready() -> void:
	if _current_phase == Phase.INVESTIGATION and can_accuse():
		_set_phase(Phase.ACCUSATION)

## Make an accusation against a suspect. Returns true if the accusation
## was accepted (suspect exists).
func make_accusation(suspect_id: String) -> bool:
	if not _suspects.has(suspect_id):
		return false
	if _current_phase != Phase.ACCUSATION and _current_phase != Phase.INVESTIGATION:
		return false
	_accused_suspect = suspect_id
	var suspect: Dictionary = _suspects[suspect_id] as Dictionary
	_accusation_correct = bool(suspect.get("is_culprit", false))
	accusation_made.emit(suspect_id, _accusation_correct)
	# Transition to MORAL_CHOICE regardless of correctness.
	_set_phase(Phase.MORAL_CHOICE)
	return true

## Get the accused suspect ID.
func get_accused_suspect() -> String:
	return _accused_suspect

## Check if the accusation was correct.
func is_accusation_correct() -> bool:
	return _accusation_correct

# ── Moral choice ──────────────────────────────────────────────────────────────

## Make the moral choice. Returns true if the choice was valid.
func make_moral_choice(choice_id: String) -> bool:
	if not _moral_choices.has(choice_id):
		return false
	if _current_phase != Phase.MORAL_CHOICE:
		return false
	_moral_choice_id = choice_id
	var choice: Dictionary = _moral_choices[choice_id] as Dictionary
	var outcome: String = String(choice.get("outcome", ""))
	_resolution_outcome = outcome
	# Apply relationship effects.
	_apply_relationship_effects(choice)
	# Apply faction tension.
	var tension_delta: int = int(choice.get("faction_tension_delta", 0))
	_apply_faction_tension(tension_delta)
	# Narrate the outcome.
	var narrative: String = String(choice.get("narrative", ""))
	if not narrative.is_empty():
		var gs: Node = _autoload("GameState")
		if gs != null and gs.has_method("narrate"):
			gs.call("narrate", narrative)
	moral_choice_made.emit(choice_id)
	sabotage_resolved.emit(outcome)
	_set_phase(Phase.RESOLVED)
	return true

## Get the moral choice that was made.
func get_moral_choice() -> String:
	return _moral_choice_id

## Get the resolution outcome.
func get_resolution_outcome() -> String:
	return _resolution_outcome

## Get all moral choice IDs.
func get_moral_choices() -> Array[String]:
	var out: Array[String] = []
	for cid in _moral_choices.keys():
		out.append(String(cid))
	return out

## Get moral choice data.
func get_moral_choice_data(choice_id: String) -> Dictionary:
	return _moral_choices.get(choice_id, {})

## Apply relationship effects from a moral choice.
func _apply_relationship_effects(choice: Dictionary) -> void:
	var effects: Dictionary = choice.get("relationship_effects", {})
	var rs: Node = _autoload("RelationshipSystem")
	if rs == null or not rs.has_method("adjust_trust"):
		return
	for crew_name in effects.keys():
		var cn: String = String(crew_name)
		var vals: Dictionary = effects[cn] as Dictionary
		var trust_delta: int = int(vals.get("trust", 0))
		var respect_delta: int = int(vals.get("respect", 0))
		if trust_delta != 0 and rs.has_method("adjust_trust"):
			rs.call("adjust_trust", cn, trust_delta)
		if respect_delta != 0 and rs.has_method("adjust_respect"):
			rs.call("adjust_respect", cn, respect_delta)

## Apply faction tension change via the FactionSystem.
func _apply_faction_tension(delta: int) -> void:
	if delta == 0:
		return
	var fs: Node = _autoload("FactionSystem")
	if fs != null and fs.has_method("adjust_tension"):
		fs.call("adjust_tension", delta)

# ── Scenario info ─────────────────────────────────────────────────────────────

func get_scenario() -> Dictionary:
	return _scenario

func get_scenario_id() -> String:
	return String(_scenario.get("id", ""))

func get_scenario_title() -> String:
	return String(_scenario.get("title", ""))

func get_scenario_description() -> String:
	return String(_scenario.get("description", ""))

func get_true_motive() -> String:
	return String(_scenario.get("true_motive", ""))

func get_first_failure_room() -> String:
	return String(_scenario.get("first_failure_room", ""))

# ── _process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	tick_cascade(delta)

# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	var clues_arr: Array[String] = []
	for cid in _discovered_clues.keys():
		clues_arr.append(String(cid))
	var suspects_arr: Array[String] = []
	for sid in _interrogated_suspects.keys():
		suspects_arr.append(String(sid))
	var failed_arr: Array[String] = []
	for sys in _active_failures.keys():
		failed_arr.append(String(sys))
	var repaired_arr: Array[String] = []
	for sys in _repaired_systems.keys():
		repaired_arr.append(String(sys))
	return {
		"current_phase": _current_phase,
		"discovered_clues": clues_arr,
		"interrogated_suspects": suspects_arr,
		"active_failures": failed_arr,
		"repaired_systems": repaired_arr,
		"cascade_timer": _cascade_timer,
		"next_failure_order": _next_failure_order,
		"accused_suspect": _accused_suspect,
		"accusation_correct": _accusation_correct,
		"moral_choice_id": _moral_choice_id,
		"resolution_outcome": _resolution_outcome,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_initialized()
	_current_phase = int(data.get("current_phase", Phase.INACTIVE))
	_discovered_clues.clear()
	var clues_arr: Variant = data.get("discovered_clues", [])
	if clues_arr is Array:
		for cid in clues_arr:
			_discovered_clues[String(cid)] = true
	_interrogated_suspects.clear()
	var suspects_arr: Variant = data.get("interrogated_suspects", [])
	if suspects_arr is Array:
		for sid in suspects_arr:
			_interrogated_suspects[String(sid)] = true
	_active_failures.clear()
	var failed_arr: Variant = data.get("active_failures", [])
	if failed_arr is Array:
		for sys in failed_arr:
			# Reconstruct event_id from system name.
			var system: String = String(sys)
			for eid in _failure_events.keys():
				var evt: Dictionary = _failure_events[eid] as Dictionary
				if String(evt.get("system", "")) == system:
					_active_failures[system] = String(eid)
					break
	_repaired_systems.clear()
	var repaired_arr: Variant = data.get("repaired_systems", [])
	if repaired_arr is Array:
		for sys in repaired_arr:
			_repaired_systems[String(sys)] = true
	_cascade_timer = float(data.get("cascade_timer", 0.0))
	_next_failure_order = int(data.get("next_failure_order", 1))
	_accused_suspect = String(data.get("accused_suspect", ""))
	_accusation_correct = bool(data.get("accusation_correct", false))
	_moral_choice_id = String(data.get("moral_choice_id", ""))
	_resolution_outcome = String(data.get("resolution_outcome", ""))

func reset() -> void:
	_current_phase = Phase.INACTIVE
	_active_failures.clear()
	_repaired_systems.clear()
	_discovered_clues.clear()
	_interrogated_suspects.clear()
	_cascade_timer = 0.0
	_next_failure_order = 1
	_accused_suspect = ""
	_accusation_correct = false
	_moral_choice_id = ""
	_resolution_outcome = ""

# ── Test hooks ────────────────────────────────────────────────────────────────

## Advance the cascade timer by a fixed delta (bypasses _process, for tests).
func test_advance(delta: float) -> void:
	tick_cascade(delta)

## Force-trigger the next failure (for tests, bypasses timer).
func test_trigger_failure() -> void:
	_trigger_next_failure()

## Force-set the cascade timer (for tests).
func test_set_cascade_timer(t: float) -> void:
	_cascade_timer = t

## Force-set the phase (for tests).
func test_set_phase(p: int) -> void:
	_set_phase(p)

# ── Helpers ──────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "sabotage_system", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)