extends Node

# MutinySystem — crew mutiny progression, phase management, moral choices, and
# Rush's secret agenda for E12 Divided.
#
# The mutiny unfolds across 5 phases, each triggered by escalating tensions
# between factions. Each phase presents a moral choice with lasting
# consequences — relationship changes, section control shifts, morale
# impacts, and decision flags that gate future events.
#
# Rush's secret agenda runs in parallel: a 4-stage subplot where Rush
# attempts to unlock the bridge and reveal Destiny's true mission. The
# agenda's outcome depends on which faction the player sides with in the
# final standoff.
#
# Integration:
#   - FactionSystem: apply_event_effects() handles all state changes
#   - RelationshipSystem: choices affect trust/respect with crew members
#   - GameState: narrate() and say() for in-fiction dialogue
#   - QuestLog: mutiny phase advancement gates quest steps
#   - SaveManager: serialize/deserialize for save/load round-trip
#
# Data: res://data/faction_warfare.json (mutiny_events + rush_agenda sections)

signal mutiny_phase_changed(old_phase: int, new_phase: int)
signal mutiny_event_triggered(event_id: String, phase: int)
signal mutiny_choice_made(event_id: String, choice_id: String)
signal rush_agenda_stage_changed(old_stage: String, new_stage: String)
signal rush_agenda_revealed(outcome: String)
signal mutiny_resolved(outcome: String)

const DATA_PATH: String = "res://data/faction_warfare.json"

# ── Mutiny phases ────────────────────────────────────────────────────────────

const PHASE_CALM: int = 0
const PHASE_TENSION: int = 1
const PHASE_DIVISION: int = 2
const PHASE_CRISIS: int = 3
const PHASE_STANDOFF: int = 4
const PHASE_RESOLVED: int = 5

const PHASE_NAMES: Dictionary = {
	0: "Calm",
	1: "Tension",
	2: "Division",
	3: "Crisis",
	4: "Standoff",
	5: "Resolved",
}

# ── Internal state ───────────────────────────────────────────────────────────

var _current_phase: int = PHASE_CALM
var _events: Dictionary = {}          # event_id → _MutinyEvent
var _completed_events: Dictionary = {} # event_id → choice_id
var _rush_stage: int = 0               # 0=not started, 1-4 = stages
var _rush_agenda_outcome: String = ""
var _mutiny_outcome: String = ""
var _loaded: bool = false

# ── Internal classes ─────────────────────────────────────────────────────────

class _MutinyEvent:
	var id: String
	var phase: int
	var title: String
	var description: String
	var trigger: String
	var faction_affected: String
	var morale_impact: Dictionary
	var choices: Array  # Array of Dictionaries

	func _init(eid: String) -> void:
		id = eid

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	_loaded = true

func _load_config() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("MutinySystem: could not open %s" % DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_warning("MutinySystem: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data as Dictionary

	# Load mutiny events
	var events: Dictionary = data.get("mutiny_events", {})
	for eid in events.keys():
		var ed: Dictionary = events[eid]
		var ev: _MutinyEvent = _MutinyEvent.new(eid)
		ev.phase = int(ed.get("phase", 1))
		ev.title = String(ed.get("title", eid))
		ev.description = String(ed.get("description", ""))
		ev.trigger = String(ed.get("trigger", "auto"))
		ev.faction_affected = String(ed.get("faction_affected", ""))
		var mi: Variant = ed.get("morale_impact", {})
		if mi is Dictionary:
			ev.morale_impact = mi
		else:
			ev.morale_impact = {}
		var ch: Variant = ed.get("choices", [])
		if ch is Array:
			ev.choices = ch
		_events[eid] = ev

# ── Public API: phase management ─────────────────────────────────────────────

## Returns the current mutiny phase (0-5).
func get_current_phase() -> int:
	return _current_phase

## Returns the current phase name.
func get_current_phase_name() -> String:
	return String(PHASE_NAMES.get(_current_phase, "Unknown"))

## Advance to the next phase. Emits mutiny_phase_changed.
func advance_phase() -> void:
	if _current_phase >= PHASE_RESOLVED:
		return
	var old: int = _current_phase
	_current_phase += 1
	mutiny_phase_changed.emit(old, _current_phase)
	# Auto-trigger events for the new phase
	_trigger_phase_events(_current_phase)

## Set the phase directly (for save/load and testing).
func set_phase(phase: int) -> void:
	if phase < 0 or phase > PHASE_RESOLVED:
		return
	var old: int = _current_phase
	_current_phase = phase
	if old != phase:
		mutiny_phase_changed.emit(old, phase)

## Trigger all auto-trigger events for a given phase.
func _trigger_phase_events(phase: int) -> void:
	for eid in _events.keys():
		var ev: _MutinyEvent = _events[eid]
		if ev.phase == phase and ev.trigger == "auto" and not _completed_events.has(eid):
			mutiny_event_triggered.emit(eid, phase)

## Start the mutiny (called by the E12 quest or by a story trigger).
func start_mutiny() -> void:
	if _current_phase != PHASE_CALM:
		return
	_current_phase = PHASE_TENSION
	mutiny_phase_changed.emit(PHASE_CALM, PHASE_TENSION)
	_trigger_phase_events(PHASE_TENSION)

# ── Public API: event access ──────────────────────────────────────────────────

## Returns all mutiny event ids.
func get_event_ids() -> Array:
	return _events.keys()

## Returns event info as a Dictionary.
func get_event_info(event_id: String) -> Dictionary:
	var ev: _MutinyEvent = _events.get(event_id, null)
	if ev == null:
		return {}
	return {
		"id": ev.id,
		"phase": ev.phase,
		"title": ev.title,
		"description": ev.description,
		"faction_affected": ev.faction_affected,
		"choices": ev.choices,
	}

## Returns the choices for a given event.
func get_event_choices(event_id: String) -> Array:
	var ev: _MutinyEvent = _events.get(event_id, null)
	if ev == null:
		return []
	return ev.choices.duplicate()

## Returns the choice_id that was made for an event, or "" if not yet decided.
func get_event_choice(event_id: String) -> String:
	return String(_completed_events.get(event_id, ""))

## Check if an event has been completed.
func is_event_completed(event_id: String) -> bool:
	return _completed_events.has(event_id)

## Returns an Array of completed event ids.
func get_completed_events() -> Array:
	return _completed_events.keys()

## Returns events for a given phase that haven't been completed yet.
func get_pending_events(phase: int) -> Array:
	var result: Array = []
	for eid in _events.keys():
		var ev: _MutinyEvent = _events[eid]
		if ev.phase == phase and not _completed_events.has(eid):
			result.append(eid)
	return result

# ── Public API: making choices ────────────────────────────────────────────────

## Make a choice for a mutiny event. Applies all effects via FactionSystem,
## records the choice, and emits signals. Returns true on success.
func make_choice(event_id: String, choice_id: String) -> bool:
	var ev: _MutinyEvent = _events.get(event_id, null)
	if ev == null:
		push_warning("MutinySystem: unknown event '%s'" % event_id)
		return false
	if _completed_events.has(event_id):
		push_warning("MutinySystem: event '%s' already completed" % event_id)
		return false
	# Find the choice
	var choice: Dictionary = {}
	for c in ev.choices:
		if c is Dictionary and String(c.get("id", "")) == choice_id:
			choice = c
			break
	if choice.is_empty():
		push_warning("MutinySystem: unknown choice '%s' for event '%s'" % [choice_id, event_id])
		return false
	# Record the choice
	_completed_events[event_id] = choice_id
	# Apply initial morale impact from the event
	for fid in ev.morale_impact.keys():
		_apply_morale(fid, int(ev.morale_impact[fid]))
	# Apply choice effects via FactionSystem
	var effects: Variant = choice.get("effects", {})
	if effects is Dictionary:
		_apply_effects(effects)
	# Emit signal
	mutiny_choice_made.emit(event_id, choice_id)
	# Check if this event advances Rush's agenda
	_check_rush_agenda_progress(event_id, choice_id)
	# Check if this was the final standoff
	if event_id == "final_standoff":
		_resolve_mutiny(choice_id)
	return true

## Apply morale change through FactionSystem.
func _apply_morale(faction_id: String, delta: int) -> void:
	var fs: Node = get_node_or_null("/root/FactionSystem")
	if fs != null and fs.has_method("adjust_morale"):
		fs.adjust_morale(faction_id, delta)

## Apply event effects through FactionSystem.
func _apply_effects(effects: Dictionary) -> void:
	var fs: Node = get_node_or_null("/root/FactionSystem")
	if fs != null and fs.has_method("apply_event_effects"):
		fs.apply_event_effects(effects)

# ── Public API: Rush's secret agenda ─────────────────────────────────────────

## Returns the current Rush agenda stage (0-4).
func get_rush_stage() -> int:
	return _rush_stage

## Returns the Rush agenda stage info as a Dictionary.
func get_rush_stage_info() -> Dictionary:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Dictionary = json.data as Dictionary
	var agenda: Dictionary = data.get("rush_agenda", {})
	var stages: Array = agenda.get("stages", [])
	if _rush_stage < 1 or _rush_stage > stages.size():
		return {}
	return stages[_rush_stage - 1]

## Returns the Rush agenda outcome string, or "" if not yet revealed.
func get_rush_agenda_outcome() -> String:
	return _rush_agenda_outcome

## Check if a choice advances Rush's agenda and update the stage.
func _check_rush_agenda_progress(event_id: String, choice_id: String) -> void:
	# Stage 1 → 2: rush_secret_project resolved
	if event_id == "rush_secret_project":
		if _rush_stage < 1:
			_rush_stage = 1
			rush_agenda_stage_changed.emit("", "rush_stage_1_gathering")
		# Advance to stage 2 regardless of choice — the event is resolved
		if _rush_stage < 2:
			_rush_stage = 2
			rush_agenda_stage_changed.emit("rush_stage_1_gathering", "rush_stage_2_leverage")
	# Stage 2 → 3: Rush controls engineering or control_interface_room
	if _rush_stage == 2:
		var fs: Node = get_node_or_null("/root/FactionSystem")
		if fs != null:
			var eng: String = fs.get_controller("engineering")
			var ctrl: String = fs.get_controller("control_interface_room")
			if eng == "science" or ctrl == "science":
				_rush_stage = 3
				rush_agenda_stage_changed.emit("rush_stage_2_leverage", "rush_stage_3_bridge")
	# Stage 3 → 4: bridge access (triggered by final_standoff choice)
	if event_id == "final_standoff":
		if choice_id == "side_science_end":
			if _rush_stage < 3:
				_rush_stage = 3
			if _rush_stage < 4:
				_rush_stage = 4
				rush_agenda_stage_changed.emit("rush_stage_3_bridge", "rush_stage_4_reveal")
				_rush_agenda_outcome = "rush_agenda_revealed_science"
				rush_agenda_revealed.emit(_rush_agenda_outcome)
		elif choice_id == "side_military_end":
			if _rush_stage < 4:
				_rush_stage = 4
				rush_agenda_stage_changed.emit("rush_stage_3_bridge", "rush_stage_4_reveal")
				_rush_agenda_outcome = "rush_agenda_revealed_military"
				rush_agenda_revealed.emit(_rush_agenda_outcome)
		elif choice_id == "side_civilian_end":
			if _rush_stage < 4:
				_rush_stage = 4
				rush_agenda_stage_changed.emit("rush_stage_3_bridge", "rush_stage_4_reveal")
				_rush_agenda_outcome = "rush_agenda_revealed_coalition"
				rush_agenda_revealed.emit(_rush_agenda_outcome)

## Force-set the Rush agenda stage (for testing or scripted events).
func set_rush_stage(stage: int) -> void:
	if stage < 0 or stage > 4:
		return
	var old: String = ""
	if _rush_stage > 0:
		old = "rush_stage_%d" % _rush_stage
	_rush_stage = stage
	var new_s: String = ""
	if stage > 0:
		new_s = "rush_stage_%d" % stage
	rush_agenda_stage_changed.emit(old, new_s)

## Check if Rush's agenda has been revealed.
func is_rush_agenda_revealed() -> bool:
	return _rush_agenda_outcome != ""

# ── Public API: mutiny resolution ─────────────────────────────────────────────

## Returns the mutiny outcome string, or "" if not yet resolved.
func get_mutiny_outcome() -> String:
	return _mutiny_outcome

## Check if the mutiny has been resolved.
func is_mutiny_resolved() -> bool:
	return _current_phase == PHASE_RESOLVED

## Resolve the mutiny based on the final standoff choice.
func _resolve_mutiny(choice_id: String) -> void:
	var outcome: String = ""
	match choice_id:
		"side_military_end":
			outcome = "military_victory"
		"side_science_end":
			outcome = "science_victory"
		"side_civilian_end":
			outcome = "coalition_government"
		_:
			outcome = "unresolved"
	_mutiny_outcome = outcome
	set_phase(PHASE_RESOLVED)
	mutiny_resolved.emit(outcome)

## Returns a summary of the mutiny state for HUD display.
func get_mutiny_summary() -> Dictionary:
	return {
		"phase": _current_phase,
		"phase_name": get_current_phase_name(),
		"completed_events": _completed_events.keys(),
		"rush_stage": _rush_stage,
		"rush_agenda_outcome": _rush_agenda_outcome,
		"mutiny_outcome": _mutiny_outcome,
		"resolved": is_mutiny_resolved(),
	}

# ── Public API: negotiation ───────────────────────────────────────────────────

## Attempt a negotiation between two factions. Returns true if the negotiation
## succeeds based on the player's relationship strength and faction power.
func attempt_negotiation(faction_a: String, faction_b: String) -> bool:
	var fs: Node = get_node_or_null("/root/FactionSystem")
	if fs == null:
		return false
	var strength_a: int = fs.get_negotiation_strength(faction_a) if fs.has_method("get_negotiation_strength") else 50
	var strength_b: int = fs.get_negotiation_strength(faction_b) if fs.has_method("get_negotiation_strength") else 50
	# Negotiation succeeds if the difference in strength is not too large
	# (i.e., neither side can simply dominate the other)
	var diff: int = absi(strength_a - strength_b)
	return diff <= 40

## Returns the negotiation strength of a faction (delegates to FactionSystem).
func get_negotiation_strength(faction_id: String) -> int:
	var fs: Node = get_node_or_null("/root/FactionSystem")
	if fs != null and fs.has_method("get_negotiation_strength"):
		return fs.get_negotiation_strength(faction_id)
	return 50

# ── Save / Load ───────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "mutiny_system", self)

func serialize() -> Dictionary:
	return {
		"current_phase": _current_phase,
		"completed_events": _completed_events.duplicate(),
		"rush_stage": _rush_stage,
		"rush_agenda_outcome": _rush_agenda_outcome,
		"mutiny_outcome": _mutiny_outcome,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_current_phase = int(data.get("current_phase", PHASE_CALM))
	var ce: Variant = data.get("completed_events", {})
	if ce is Dictionary:
		_completed_events = (ce as Dictionary).duplicate()
	_rush_stage = int(data.get("rush_stage", 0))
	_rush_agenda_outcome = String(data.get("rush_agenda_outcome", ""))
	_mutiny_outcome = String(data.get("mutiny_outcome", ""))

func reset() -> void:
	_current_phase = PHASE_CALM
	_completed_events.clear()
	_rush_stage = 0
	_rush_agenda_outcome = ""
	_mutiny_outcome = ""

# ── Convenience ───────────────────────────────────────────────────────────────

func is_loaded() -> bool:
	return _loaded

## Returns the total number of mutiny events.
func event_count() -> int:
	return _events.size()

## Returns the number of completed events.
func completed_event_count() -> int:
	return _completed_events.size()