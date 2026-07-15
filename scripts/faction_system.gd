extends Node

# FactionSystem — ship section control, faction power tracking, and door
# lock/unlock as a faction warfare tool for E12 Divided.
#
# Ship sections (rooms) are controlled by factions. When a faction controls
# a section, they can lock/unlock its doors to restrict movement by rival
# factions. Section control changes through mutiny events, negotiations, and
# player choices.
#
# The system integrates with:
#   - RelationshipSystem: faction standing affects negotiation strength
#   - Door (scripts/door.gd): faction-controlled doors can be locked/unlocked
#     by the controlling faction
#   - GameState: fires faction_section_changed signal for HUD updates
#   - SaveManager: serialize/deserialize for save/load round-trip
#   - MutinySystem: mutiny events call apply_event_choice() which updates
#     section control and morale
#
# Data: res://data/faction_warfare.json

signal section_control_changed(section_id: String, old_faction: String, new_faction: String)
signal faction_power_changed(faction_id: String, power: int)
signal faction_morale_changed(faction_id: String, morale: int)
signal door_lock_state_changed(section_id: String, locked: bool, faction_id: String)

const DATA_PATH: String = "res://data/faction_warfare.json"

# ── Internal state ───────────────────────────────────────────────────────────

# section_id → _Section
var _sections: Dictionary = {}

# faction_id → _FactionState
var _factions: Dictionary = {}

# faction_id → Array[String] of section_ids they control
var _controlled_sections: Dictionary = {}

# section_id → bool (locked by faction warfare)
var _faction_locked_doors: Dictionary = {}

# Set of decision flags set by mutiny event choices (e.g. "rush_reported")
var _decision_flags: Dictionary = {}

var _loaded: bool = false

# ── Internal classes ─────────────────────────────────────────────────────────

class _Section:
	var id: String
	var display_name: String
	var description: String
	var critical: bool
	var controller: String  # faction_id

	func _init(sid: String) -> void:
		id = sid


class _FactionState:
	var id: String
	var power: int = 100       # overall faction strength (0-200)
	var morale: int = 50       # faction morale (-50 to 100)
	var goals: Dictionary = {}

	func _init(fid: String) -> void:
		id = fid


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	# Listen for dialog actions so mutiny event choices can trigger faction
	# changes via the existing dialog_action signal pipeline.
	if GameState != null and GameState.has_signal("dialog_action"):
		GameState.dialog_action.connect(_on_dialog_action)
	_loaded = true

func _load_config() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("FactionSystem: could not open %s" % DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_warning("FactionSystem: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data as Dictionary

	# Load sections
	var sections: Dictionary = data.get("sections", {})
	for sid in sections.keys():
		var sd: Dictionary = sections[sid]
		var sec: _Section = _Section.new(sid)
		sec.display_name = String(sd.get("display_name", sid))
		sec.description = String(sd.get("description", ""))
		sec.critical = bool(sd.get("critical", false))
		sec.controller = String(sd.get("default_controller", ""))
		_sections[sid] = sec

	# Load faction states
	var goals: Dictionary = data.get("faction_goals", {})
	# Use faction ids from RelationshipSystem's data if available, otherwise
	# derive from the goals section.
	var faction_ids: Array = goals.keys()
	for fid in faction_ids:
		var fs: _FactionState = _FactionState.new(fid)
		fs.goals = goals[fid]
		_factions[fid] = fs
		_controlled_sections[fid] = []

	# Build controlled_sections from section controllers
	for sid in _sections.keys():
		var sec: _Section = _sections[sid]
		if sec.controller != "" and _controlled_sections.has(sec.controller):
			(_controlled_sections[sec.controller] as Array).append(sid)

	# Load negotiation config (used by MutinySystem)
	# (stored in the JSON but accessed here for faction power calculations)

	# Calculate initial power for all factions based on default section control.
	recalculate_all_power()

# ── Public API: sections ─────────────────────────────────────────────────────

## Returns the faction controlling a section, or "" if uncontrolled.
func get_controller(section_id: String) -> String:
	var sec: _Section = _sections.get(section_id, null)
	if sec == null:
		return ""
	return sec.controller

## Set the controller of a section. Emits section_control_changed and
## faction_power_changed. Updates _controlled_sections mappings.
func set_controller(section_id: String, faction_id: String) -> void:
	var sec: _Section = _sections.get(section_id, null)
	if sec == null:
		push_warning("FactionSystem: unknown section '%s'" % section_id)
		return
	var old: String = sec.controller
	if old == faction_id:
		return
	sec.controller = faction_id
	# Update controlled_sections mappings
	if old != "" and _controlled_sections.has(old):
		(_controlled_sections[old] as Array).erase(section_id)
	if faction_id != "" and _controlled_sections.has(faction_id):
		if not (_controlled_sections[faction_id] as Array).has(section_id):
			(_controlled_sections[faction_id] as Array).append(section_id)
	section_control_changed.emit(section_id, old, faction_id)
	# Recalculate faction power
	_recalculate_power(old)
	_recalculate_power(faction_id)

## Returns an Array of section_ids controlled by the given faction.
func get_faction_sections(faction_id: String) -> Array:
	return (_controlled_sections.get(faction_id, []) as Array).duplicate()

## Returns the number of sections controlled by a faction.
func get_section_count(faction_id: String) -> int:
	return (_controlled_sections.get(faction_id, []) as Array).size()

## Returns the number of critical sections controlled by a faction.
func get_critical_section_count(faction_id: String) -> int:
	var count: int = 0
	for sid in (_controlled_sections.get(faction_id, []) as Array):
		var sec: _Section = _sections.get(sid, null)
		if sec != null and sec.critical:
			count += 1
	return count

## Returns all section ids.
func get_all_sections() -> Array:
	return _sections.keys()

## Returns section info as a Dictionary for HUD display.
func get_section_info(section_id: String) -> Dictionary:
	var sec: _Section = _sections.get(section_id, null)
	if sec == null:
		return {}
	return {
		"id": sec.id,
		"display_name": sec.display_name,
		"description": sec.description,
		"critical": sec.critical,
		"controller": sec.controller,
	}

## Returns an Array of Dictionaries for all sections (for HUD/overview).
func get_all_section_info() -> Array:
	var result: Array = []
	for sid in _sections.keys():
		result.append(get_section_info(sid))
	return result

# ── Public API: faction power and morale ─────────────────────────────────────

## Returns the faction's current power (0-200). Power is derived from the
## number of sections controlled, with critical sections worth more.
func get_faction_power(faction_id: String) -> int:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return 0
	return fs.power

## Returns the faction's current morale (-50 to 100).
func get_faction_morale(faction_id: String) -> int:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return 0
	return fs.morale

## Adjust faction morale by a delta, clamped to [-50, 100]. Emits signal.
func adjust_morale(faction_id: String, delta: int) -> void:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return
	var old: int = fs.morale
	fs.morale = clampi(fs.morale + delta, -50, 100)
	if fs.morale != old:
		faction_morale_changed.emit(faction_id, fs.morale)

## Set faction morale directly (clamped). Emits signal.
func set_morale(faction_id: String, value: int) -> void:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return
	var old: int = fs.morale
	fs.morale = clampi(value, -50, 100)
	if fs.morale != old:
		faction_morale_changed.emit(faction_id, fs.morale)

## Recalculate a faction's power based on controlled sections.
## Each normal section = 10 power, each critical section = 25 power.
func _recalculate_power(faction_id: String) -> void:
	if faction_id == "":
		return
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return
	var power: int = 0
	for sid in (_controlled_sections.get(faction_id, []) as Array):
		var sec: _Section = _sections.get(sid, null)
		if sec == null:
			continue
		if sec.critical:
			power += 25
		else:
			power += 10
	# Add morale contribution: morale/2 gives -25 to +50 bonus
	power += int(fs.morale * 0.5)
	power = clampi(power, 0, 200)
	var old_power: int = fs.power
	fs.power = power
	if power != old_power:
		faction_power_changed.emit(faction_id, power)

## Recalculate all factions' power (e.g. after a major event).
func recalculate_all_power() -> void:
	for fid in _factions.keys():
		_recalculate_power(fid)

# ── Public API: door lock/unlock as faction tool ─────────────────────────────

## Lock a section's doors for faction warfare purposes. Only the controlling
## faction can lock/unlock a section's doors.
func lock_section_doors(section_id: String, faction_id: String) -> bool:
	var sec: _Section = _sections.get(section_id, null)
	if sec == null:
		return false
	if sec.controller != faction_id:
		return false
	_faction_locked_doors[section_id] = true
	door_lock_state_changed.emit(section_id, true, faction_id)
	return true

## Unlock a section's doors.
func unlock_section_doors(section_id: String, faction_id: String) -> bool:
	var sec: _Section = _sections.get(section_id, null)
	if sec == null:
		return false
	if sec.controller != faction_id:
		return false
	_faction_locked_doors[section_id] = false
	door_lock_state_changed.emit(section_id, false, faction_id)
	return true

## Check if a section's doors are faction-locked.
func is_section_locked(section_id: String) -> bool:
	return _faction_locked_doors.get(section_id, false)

## Returns the faction that locked the section (the controller), or "".
func get_locking_faction(section_id: String) -> String:
	if not is_section_locked(section_id):
		return ""
	return get_controller(section_id)

## Check if a crew member can pass through a section's doors. A crew member
## is blocked if the section is faction-locked and they belong to a different
## faction.
func can_crew_pass(crew_name: String, section_id: String) -> bool:
	if not is_section_locked(section_id):
		return true
	var controller: String = get_controller(section_id)
	if controller == "":
		return true
	# Check the crew member's faction via RelationshipSystem
	var rs: Node = get_node_or_null("/root/RelationshipSystem")
	if rs == null:
		return true
	var crew_faction: String = ""
	if rs.has_method("get_faction"):
		crew_faction = rs.get_faction(crew_name)
	if crew_faction == "":
		return true  # unknown crew can pass
	return crew_faction == controller

# ── Public API: decision flags ───────────────────────────────────────────────

## Set a decision flag (e.g. "rush_reported", "council_formed").
func set_flag(flag_name: String) -> void:
	_decision_flags[flag_name] = true

## Check if a decision flag is set.
func has_flag(flag_name: String) -> bool:
	return _decision_flags.get(flag_name, false)

## Get all set decision flags.
func get_flags() -> Dictionary:
	return _decision_flags.duplicate()

# ── Public API: faction goals ────────────────────────────────────────────────

## Returns the faction's goal info Dictionary.
func get_faction_goals(faction_id: String) -> Dictionary:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return {}
	return fs.goals

## Check if a faction has met its success condition.
func check_faction_success(faction_id: String) -> bool:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return false
	var success: String = String(fs.goals.get("success_condition", ""))
	if success.is_empty():
		return false
	# Parse and check success conditions
	# "Controls gate_room, control_interface_room, and med_bay."
	# We check if the faction controls all named sections.
	var sections_to_check: Array = _extract_section_ids(success)
	for sid in sections_to_check:
		if get_controller(sid) != faction_id:
			return false
	# Check Rush trust for science faction
	if faction_id == "science":
		var rs: Node = get_node_or_null("/root/RelationshipSystem")
		if rs != null and rs.has_method("get_trust"):
			if rs.get_trust("Dr Rush") < 50:
				return false
	return true

## Check if a faction has met its failure condition.
func check_faction_failure(faction_id: String) -> bool:
	var fs: _FactionState = _factions.get(faction_id, null)
	if fs == null:
		return false
	var failure: String = String(fs.goals.get("failure_condition", ""))
	if failure.is_empty():
		return false
	# "Loses control of gate_room for more than 2 phases."
	# We check basic section loss
	var sections_to_check: Array = _extract_section_ids(failure)
	for sid in sections_to_check:
		if get_controller(sid) == faction_id:
			return false  # still controls it, not a failure
	# Check relationship-based failures
	if faction_id == "lucian_alliance":
		var rs: Node = get_node_or_null("/root/RelationshipSystem")
		if rs != null and rs.has_method("meets_threshold"):
			if rs.meets_threshold("Varro", "hostile") and rs.meets_threshold("Simeon", "hostile"):
				return true
	return false

## Extract section ids from a condition string by matching known section names.
func _extract_section_ids(condition: String) -> Array:
	var result: Array = []
	for sid in _sections.keys():
		if condition.find(sid) != -1:
			result.append(sid)
	return result

# ── Public API: faction summary ──────────────────────────────────────────────

## Returns a Dictionary of faction_id → { power, morale, sections, critical_sections }
func get_faction_summary() -> Dictionary:
	var result: Dictionary = {}
	for fid in _factions.keys():
		var fs: _FactionState = _factions[fid]
		result[fid] = {
			"power": fs.power,
			"morale": fs.morale,
			"sections": get_section_count(fid),
			"critical_sections": get_critical_section_count(fid),
			"controlled_section_ids": get_faction_sections(fid),
		}
	return result

# ── Public API: negotiation strength ─────────────────────────────────────────

## Calculate negotiation strength for a faction based on controlled sections,
## relationship with Eli, and faction-specific modifiers.
func get_negotiation_strength(faction_id: String) -> int:
	var base: int = 50
	# Section control bonus
	var section_count: int = get_section_count(faction_id)
	base += section_count * 3
	# Critical section bonus
	base += get_critical_section_count(faction_id) * 5
	# Relationship bonus: average trust of faction members with Eli
	var rs: Node = get_node_or_null("/root/RelationshipSystem")
	if rs != null and rs.has_method("get_faction_standing"):
		var standing: float = rs.get_faction_standing(faction_id)
		# standing is 0..1; convert to -25..+25 bonus
		base += int((standing - 0.5) * 50)
	# Morale bonus
	var morale: int = get_faction_morale(faction_id)
	base += int(morale * 0.2)
	return clampi(base, 0, 200)

# ── Apply event effects ──────────────────────────────────────────────────────

## Apply the effects of a mutiny event choice. Called by MutinySystem.
## Effects Dictionary can contain:
##   "relationships": { crew_name: { trust: int, respect: int }, ... }
##   "morale": { faction_id: int, ... }
##   "sections": { section_id: faction_id, ... }
##   "flag": String (decision flag to set)
func apply_event_effects(effects: Dictionary) -> void:
	# Apply relationship changes via RelationshipSystem
	var relationships: Variant = effects.get("relationships", {})
	if relationships is Dictionary:
		var rs: Node = get_node_or_null("/root/RelationshipSystem")
		if rs != null and rs.has_method("adjust_relationship"):
			for crew_name in (relationships as Dictionary).keys():
				var deltas: Dictionary = (relationships as Dictionary)[crew_name]
				var trust_d: int = int(deltas.get("trust", 0))
				var respect_d: int = int(deltas.get("respect", 0))
				rs.adjust_relationship(crew_name, trust_d, respect_d)
	# Apply morale changes
	var morale: Variant = effects.get("morale", {})
	if morale is Dictionary:
		for fid in (morale as Dictionary).keys():
			adjust_morale(fid, int((morale as Dictionary)[fid]))
	# Apply section control changes
	var sections: Variant = effects.get("sections", {})
	if sections is Dictionary:
		for sid in (sections as Dictionary).keys():
			set_controller(sid, (sections as Dictionary)[sid])
	# Set decision flag
	var flag: String = String(effects.get("flag", ""))
	if flag != "":
		set_flag(flag)
	# Recalculate all power after changes
	recalculate_all_power()

# ── Signal handler ────────────────────────────────────────────────────────────

func _on_dialog_action(action_id: String) -> void:
	# Dialog actions that start with "faction_" are handled here.
	# Currently a no-op passthrough — the MutinySystem handles event choices
	# directly via apply_event_effects().
	pass

# ── Save / Load ───────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "faction_system", self)

func serialize() -> Dictionary:
	var sections_data: Dictionary = {}
	for sid in _sections.keys():
		var sec: _Section = _sections[sid]
		sections_data[sid] = sec.controller
	var morale_data: Dictionary = {}
	var power_data: Dictionary = {}
	for fid in _factions.keys():
		var fs: _FactionState = _factions[fid]
		morale_data[fid] = fs.morale
		power_data[fid] = fs.power
	return {
		"section_controllers": sections_data,
		"faction_morale": morale_data,
		"faction_power": power_data,
		"faction_locked_doors": _faction_locked_doors.duplicate(),
		"decision_flags": _decision_flags.duplicate(),
	}

func deserialize(data: Dictionary, _version: int) -> void:
	var sc: Variant = data.get("section_controllers", {})
	if sc is Dictionary:
		for sid in (sc as Dictionary).keys():
			var sec: _Section = _sections.get(sid, null)
			if sec != null:
				sec.controller = (sc as Dictionary)[sid]
	# Rebuild controlled_sections
	for fid in _controlled_sections.keys():
		(_controlled_sections[fid] as Array).clear()
	for sid in _sections.keys():
		var sec: _Section = _sections[sid]
		if sec.controller != "" and _controlled_sections.has(sec.controller):
			(_controlled_sections[sec.controller] as Array).append(sid)
	var fm: Variant = data.get("faction_morale", {})
	if fm is Dictionary:
		for fid in (fm as Dictionary).keys():
			var fs: _FactionState = _factions.get(fid, null)
			if fs != null:
				fs.morale = int((fm as Dictionary)[fid])
	var fp: Variant = data.get("faction_power", {})
	if fp is Dictionary:
		for fid in (fp as Dictionary).keys():
			var fs: _FactionState = _factions.get(fid, null)
			if fs != null:
				fs.power = int((fp as Dictionary)[fid])
	var fld: Variant = data.get("faction_locked_doors", {})
	if fld is Dictionary:
		_faction_locked_doors = (fld as Dictionary).duplicate()
	var df: Variant = data.get("decision_flags", {})
	if df is Dictionary:
		_decision_flags = (df as Dictionary).duplicate()

func reset() -> void:
	_faction_locked_doors.clear()
	_decision_flags.clear()
	_sections.clear()
	_factions.clear()
	_controlled_sections.clear()
	_loaded = false
	_load_config()
	_loaded = true

# ── Convenience accessors ────────────────────────────────────────────────────

func get_faction_ids() -> Array:
	return _factions.keys()

func is_loaded() -> bool:
	return _loaded