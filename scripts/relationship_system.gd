extends Node

# RelationshipSystem — tracks trust and respect between Eli and each crew member.
#
# Factions: military, science, civilian, lucian_alliance.
# Each crew member has trust and respect values (clamped to min/max from JSON).
# Dialogue choices affect relationships via apply_dialogue_action(action_id).
# Relationship thresholds gate dialogue and quests via meets_threshold() and
# quest_step_available().
#
# Integration:
#   - GameState.dialog_action signal → apply_dialogue_action() for data-driven
#     relationship changes from dialog trees.
#   - QuestLog → quest_step_available() to gate quest steps behind relationship
#     levels.
#   - NPC dialogue → meets_threshold() to unlock/lock dialogue options.
#   - SaveManager → serialize()/deserialize() for save/load round-trip.
#
# Data: res://data/relationships.json

signal trust_changed(crew_name: String, old_value: int, new_value: int)
signal respect_changed(crew_name: String, old_value: int, new_value: int)
signal relationship_level_changed(crew_name: String, old_level: String, new_level: String)
signal faction_standing_changed(faction_id: String, standing: float)

const DATA_PATH: String = "res://data/relationships.json"

# ── Threshold levels (ordered lowest → highest) ─────────────────────────────

const LEVEL_ORDER: Array[String] = [
	"hostile", "wary", "neutral", "friendly", "loyal"
]

# ── Internal state ───────────────────────────────────────────────────────────

# crew_name → _CrewRelationship
var _crew: Dictionary = {}

# faction_id → _Faction
var _factions: Dictionary = {}

# action_id → Dictionary (from JSON)
var _dialogue_actions: Dictionary = {}

# quest_step_id → { "crew": String, "level": String }
var _quest_gates: Dictionary = {}

var _loaded: bool = false

# ── Internal classes ─────────────────────────────────────────────────────────

class _CrewRelationship:
	var name: String
	var faction: String
	var trust: int
	var respect: int
	var trust_max: int = 100
	var trust_min: int = -50
	var respect_max: int = 100
	var respect_min: int = -50
	var description: String = ""
	# Thresholds: level_name → { "trust": int, "respect": int }
	var thresholds: Dictionary = {}

	func _init(n: String) -> void:
		name = n

	## Returns the highest threshold level the crew member currently meets.
	## A level is "met" if trust >= level.trust AND respect >= level.respect.
	func current_level() -> String:
		var best: String = "hostile"
		for level in RelationshipSystem.LEVEL_ORDER:
			var req: Dictionary = thresholds.get(level, {})
			if req.is_empty():
				continue
			var req_trust: int = int(req.get("trust", -9999))
			var req_respect: int = int(req.get("respect", -9999))
			if trust >= req_trust and respect >= req_respect:
				best = level
			else:
				break
		return best


class _Faction:
	var id: String
	var display_name: String
	var description: String = ""
	var members: Array[String] = []

	func _init(fid: String) -> void:
		id = fid

	## Average trust across all members.
	func avg_trust(rs: Node) -> float:
		if members.is_empty():
			return 0.0
		var total: int = 0
		for m in members:
			var cr: Variant = rs.call("_get_crew_entry", m)
			if cr is Object and cr != null:
				total += cr.trust
		return float(total) / float(members.size())

	## Average respect across all members.
	func avg_respect(rs: Node) -> float:
		if members.is_empty():
			return 0.0
		var total: int = 0
		for m in members:
			var cr: Variant = rs.call("_get_crew_entry", m)
			if cr is Object and cr != null:
				total += cr.respect
		return float(total) / float(members.size())

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	# Wire to GameState.dialog_action for data-driven relationship changes.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("dialog_action"):
		if not gs.dialog_action.is_connected(_on_dialog_action):
			gs.dialog_action.connect(_on_dialog_action)

# ── Config loading ───────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("RelationshipSystem: cannot open %s" % DATA_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("RelationshipSystem: %s did not parse to a Dictionary" % DATA_PATH)
		return
	var d: Dictionary = parsed as Dictionary

	# Load factions.
	var raw_factions: Variant = d.get("factions", {})
	if raw_factions is Dictionary:
		for fid in (raw_factions as Dictionary).keys():
			var fd: Dictionary = (raw_factions as Dictionary)[fid]
			var faction: _Faction = _Faction.new(String(fid))
			faction.display_name = String(fd.get("display_name", fid))
			faction.description = String(fd.get("description", ""))
			var raw_members: Variant = fd.get("members", [])
			if raw_members is Array:
				for m in (raw_members as Array):
					faction.members.append(String(m))
			_factions[fid] = faction

	# Load crew relationships.
	var raw_crew: Variant = d.get("crew", {})
	if raw_crew is Dictionary:
		for cname in (raw_crew as Dictionary).keys():
			var cd: Dictionary = (raw_crew as Dictionary)[cname]
			var cr: _CrewRelationship = _CrewRelationship.new(String(cname))
			cr.faction = String(cd.get("faction", ""))
			cr.trust = int(cd.get("trust", 0))
			cr.respect = int(cd.get("respect", 0))
			cr.trust_max = int(cd.get("trust_max", 100))
			cr.trust_min = int(cd.get("trust_min", -50))
			cr.respect_max = int(cd.get("respect_max", 100))
			cr.respect_min = int(cd.get("respect_min", -50))
			cr.description = String(cd.get("description", ""))
			var raw_thresholds: Variant = cd.get("thresholds", {})
			if raw_thresholds is Dictionary:
				for level in (raw_thresholds as Dictionary).keys():
					var td: Dictionary = (raw_thresholds as Dictionary)[level]
					cr.thresholds[String(level)] = {
						"trust": int(td.get("trust", -9999)),
						"respect": int(td.get("respect", -9999)),
					}
			_crew[cname] = cr

	# Load dialogue actions.
	var raw_actions: Variant = d.get("dialogue_actions", {})
	if raw_actions is Dictionary:
		for aid in (raw_actions as Dictionary).keys():
			if aid == "_comment":
				continue
			_dialogue_actions[String(aid)] = (raw_actions as Dictionary)[aid]

	# Load quest gates.
	var raw_gates: Variant = d.get("quest_gates", {})
	if raw_gates is Dictionary:
		for step_id in (raw_gates as Dictionary).keys():
			if step_id == "_comment":
				continue
			var gd: Dictionary = (raw_gates as Dictionary)[step_id]
			_quest_gates[String(step_id)] = {
				"crew": String(gd.get("crew", "")),
				"level": String(gd.get("level", "neutral")),
			}

# ── Public API: queries ──────────────────────────────────────────────────────

## Returns the number of tracked crew members.
func crew_count() -> int:
	return _crew.size()

## Returns an Array of all crew member names.
func crew_names() -> Array:
	return _crew.keys()

## Returns the faction id for a crew member (or "" if unknown).
func get_faction(crew_name: String) -> String:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return ""
	return cr.faction

## Returns the current trust value for a crew member.
func get_trust(crew_name: String) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return 0
	return cr.trust

## Returns the current respect value for a crew member.
func get_respect(crew_name: String) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return 0
	return cr.respect

## Returns the description string for a crew member.
func get_description(crew_name: String) -> String:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return ""
	return cr.description

## Returns the current relationship level string (hostile/wary/neutral/friendly/loyal).
func get_level(crew_name: String) -> String:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return "hostile"
	return cr.current_level()

## Returns true if the crew member meets or exceeds the given threshold level.
func meets_threshold(crew_name: String, level: String) -> bool:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return false
	var current: String = cr.current_level()
	var current_idx: int = LEVEL_ORDER.find(current)
	var required_idx: int = LEVEL_ORDER.find(level)
	if current_idx < 0 or required_idx < 0:
		return false
	return current_idx >= required_idx

## Returns the trust min/max bounds for a crew member as { min, max }.
func get_trust_bounds(crew_name: String) -> Dictionary:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return {"min": -50, "max": 100}
	return {"min": cr.trust_min, "max": cr.trust_max}

## Returns the respect min/max bounds for a crew member as { min, max }.
func get_respect_bounds(crew_name: String) -> Dictionary:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return {"min": -50, "max": 100}
	return {"min": cr.respect_min, "max": cr.respect_max}

## Returns the threshold requirements for a specific level on a crew member.
func get_threshold(crew_name: String, level: String) -> Dictionary:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return {}
	return cr.thresholds.get(level, {}).duplicate()

# ── Public API: factions ──────────────────────────────────────────────────────

## Returns an Array of all faction ids.
func faction_ids() -> Array:
	return _factions.keys()

## Returns the display name for a faction.
func get_faction_display_name(faction_id: String) -> String:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return faction_id
	return f.display_name

## Returns the description for a faction.
func get_faction_description(faction_id: String) -> String:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return ""
	return f.description

## Returns the member list for a faction.
func get_faction_members(faction_id: String) -> Array:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return []
	return Array(f.members)

## Returns the average trust across all members of a faction.
func get_faction_avg_trust(faction_id: String) -> float:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return 0.0
	return f.avg_trust(self)

## Returns the average respect across all members of a faction.
func get_faction_avg_respect(faction_id: String) -> float:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return 0.0
	return f.avg_respect(self)

## Returns a 0..1 standing score for a faction, computed from average trust
## normalized across the trust range of all members.
func get_faction_standing(faction_id: String) -> float:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return 0.5
	if f.members.is_empty():
		return 0.5
	var total_norm: float = 0.0
	var count: int = 0
	for m in f.members:
		var cr: _CrewRelationship = _crew.get(m, null) as _CrewRelationship
		if cr == null:
			continue
		var range: int = cr.trust_max - cr.trust_min
		if range <= 0:
			total_norm += 0.5
		else:
			total_norm += float(cr.trust - cr.trust_min) / float(range)
		count += 1
	if count == 0:
		return 0.5
	return total_norm / float(count)

# ── Public API: modifications ─────────────────────────────────────────────────

## Adjust trust for a crew member by delta (clamped to min/max). Returns the
## new value. Emits trust_changed and potentially relationship_level_changed.
func adjust_trust(crew_name: String, delta: int) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		push_warning("RelationshipSystem: unknown crew '%s'" % crew_name)
		return 0
	var old_val: int = cr.trust
	var old_level: String = cr.current_level()
	cr.trust = clampi(cr.trust + delta, cr.trust_min, cr.trust_max)
	if cr.trust != old_val:
		trust_changed.emit(crew_name, old_val, cr.trust)
	var new_level: String = cr.current_level()
	if new_level != old_level:
		relationship_level_changed.emit(crew_name, old_level, new_level)
	# Check if this crew is in a faction and fire standing change.
	if cr.faction != "":
		faction_standing_changed.emit(cr.faction, get_faction_standing(cr.faction))
	return cr.trust

## Adjust respect for a crew member by delta (clamped to min/max). Returns the
## new value. Emits respect_changed and potentially relationship_level_changed.
func adjust_respect(crew_name: String, delta: int) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		push_warning("RelationshipSystem: unknown crew '%s'" % crew_name)
		return 0
	var old_val: int = cr.respect
	var old_level: String = cr.current_level()
	cr.respect = clampi(cr.respect + delta, cr.respect_min, cr.respect_max)
	if cr.respect != old_val:
		respect_changed.emit(crew_name, old_val, cr.respect)
	var new_level: String = cr.current_level()
	if new_level != old_level:
		relationship_level_changed.emit(crew_name, old_level, new_level)
	if cr.faction != "":
		faction_standing_changed.emit(cr.faction, get_faction_standing(cr.faction))
	return cr.respect

## Set trust directly (clamped). Emits signals as needed.
func set_trust(crew_name: String, value: int) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return 0
	var old_val: int = cr.trust
	var old_level: String = cr.current_level()
	cr.trust = clampi(value, cr.trust_min, cr.trust_max)
	if cr.trust != old_val:
		trust_changed.emit(crew_name, old_val, cr.trust)
	var new_level: String = cr.current_level()
	if new_level != old_level:
		relationship_level_changed.emit(crew_name, old_level, new_level)
	if cr.faction != "":
		faction_standing_changed.emit(cr.faction, get_faction_standing(cr.faction))
	return cr.trust

## Set respect directly (clamped). Emits signals as needed.
func set_respect(crew_name: String, value: int) -> int:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		return 0
	var old_val: int = cr.respect
	var old_level: String = cr.current_level()
	cr.respect = clampi(value, cr.respect_min, cr.respect_max)
	if cr.respect != old_val:
		respect_changed.emit(crew_name, old_val, cr.respect)
	var new_level: String = cr.current_level()
	if new_level != old_level:
		relationship_level_changed.emit(crew_name, old_level, new_level)
	if cr.faction != "":
		faction_standing_changed.emit(cr.faction, get_faction_standing(cr.faction))
	return cr.respect

## Apply both trust and respect deltas at once. More efficient than calling
## adjust_trust + adjust_respect separately since it computes the level change
## only once.
func adjust_relationship(crew_name: String, trust_delta: int, respect_delta: int) -> void:
	var cr: _CrewRelationship = _crew.get(crew_name, null) as _CrewRelationship
	if cr == null:
		push_warning("RelationshipSystem: unknown crew '%s'" % crew_name)
		return
	var old_trust: int = cr.trust
	var old_respect: int = cr.respect
	var old_level: String = cr.current_level()
	cr.trust = clampi(cr.trust + trust_delta, cr.trust_min, cr.trust_max)
	cr.respect = clampi(cr.respect + respect_delta, cr.respect_min, cr.respect_max)
	if cr.trust != old_trust:
		trust_changed.emit(crew_name, old_trust, cr.trust)
	if cr.respect != old_respect:
		respect_changed.emit(crew_name, old_respect, cr.respect)
	var new_level: String = cr.current_level()
	if new_level != old_level:
		relationship_level_changed.emit(crew_name, old_level, new_level)
	if cr.faction != "":
		faction_standing_changed.emit(cr.faction, get_faction_standing(cr.faction))

# ── Public API: dialogue actions ──────────────────────────────────────────────

## Apply a dialogue action by its action_id. Looks up the action in
## _dialogue_actions and applies trust/respect deltas to the specified crew
## members and/or factions. This is the primary integration point for
## data-driven relationship changes from dialog trees.
func apply_dialogue_action(action_id: String) -> void:
	var action: Variant = _dialogue_actions.get(action_id, null)
	if action == null:
		return
	if not (action is Dictionary):
		return
	var ad: Dictionary = action as Dictionary
	for key in ad.keys():
		if key == "_comment":
			continue
		var deltas: Variant = ad[key]
		if not (deltas is Dictionary):
			continue
		var dd: Dictionary = deltas as Dictionary
		var trust_delta: int = int(dd.get("trust", 0))
		var respect_delta: int = int(dd.get("respect", 0))
		if key.begins_with("_faction:"):
			var faction_id: String = key.substr(9)
			_apply_faction_delta(faction_id, trust_delta, respect_delta)
		else:
			adjust_relationship(String(key), trust_delta, respect_delta)

## Apply trust/respect deltas to all members of a faction.
func _apply_faction_delta(faction_id: String, trust_delta: int, respect_delta: int) -> void:
	var f: _Faction = _factions.get(faction_id, null) as _Faction
	if f == null:
		return
	for m in f.members:
		adjust_relationship(m, trust_delta, respect_delta)

## Returns true if the given action_id is a known dialogue action.
func has_dialogue_action(action_id: String) -> bool:
	return _dialogue_actions.has(action_id)

## Returns the list of all dialogue action ids.
func dialogue_action_ids() -> Array:
	return _dialogue_actions.keys()

# ── Public API: quest gating ───────────────────────────────────────────────────

## Returns true if the quest step is available (i.e., the player meets the
## required relationship level with the required crew member). Returns true
## for steps with no gate.
func quest_step_available(step_id: String) -> bool:
	var gate: Variant = _quest_gates.get(step_id, null)
	if gate == null:
		return true
	if not (gate is Dictionary):
		return true
	var gd: Dictionary = gate as Dictionary
	var crew_name: String = String(gd.get("crew", ""))
	var level: String = String(gd.get("level", "neutral"))
	if crew_name.is_empty():
		return true
	return meets_threshold(crew_name, level)

## Returns the gate requirement for a quest step as { crew, level } or {}.
func get_quest_gate(step_id: String) -> Dictionary:
	var gate: Variant = _quest_gates.get(step_id, null)
	if gate == null or not (gate is Dictionary):
		return {}
	return (gate as Dictionary).duplicate()

## Returns an Array of all quest step ids that have gates.
func gated_quest_steps() -> Array:
	return _quest_gates.keys()

# ── Public API: summary ───────────────────────────────────────────────────────

## Returns an Array of Dictionaries, one per crew member, with their current
## relationship state. Useful for HUD / crew viewer integration.
func get_all_crew_summary() -> Array:
	var result: Array = []
	for cname in _crew.keys():
		var cr: _CrewRelationship = _crew[cname] as _CrewRelationship
		result.append({
			"name": cname,
			"faction": cr.faction,
			"trust": cr.trust,
			"respect": cr.respect,
			"level": cr.current_level(),
			"description": cr.description,
		})
	return result

## Returns a Dictionary of faction_id → { display_name, avg_trust, avg_respect,
## standing, member_count } for HUD / faction overview screens.
func get_faction_summary() -> Dictionary:
	var result: Dictionary = {}
	for fid in _factions.keys():
		var f: _Faction = _factions[fid] as _Faction
		result[fid] = {
			"display_name": f.display_name,
			"description": f.description,
			"avg_trust": f.avg_trust(self),
			"avg_respect": f.avg_respect(self),
			"standing": get_faction_standing(fid),
			"member_count": f.members.size(),
		}
	return result

# ── Signal handler ────────────────────────────────────────────────────────────

func _on_dialog_action(action_id: String) -> void:
	apply_dialogue_action(action_id)

# ── Internal access for _Faction.avg_* ────────────────────────────────────────

func _get_crew_entry(crew_name: String) -> Variant:
	return _crew.get(crew_name, null)

# ── Save / Load ───────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "relationship_system", self)

func serialize() -> Dictionary:
	var data: Dictionary = {}
	for cname in _crew.keys():
		var cr: _CrewRelationship = _crew[cname] as _CrewRelationship
		data[cname] = {
			"trust": cr.trust,
			"respect": cr.respect,
		}
	return {"crew": data}

func deserialize(data: Dictionary, _version: int) -> void:
	var raw_crew: Variant = data.get("crew", {})
	if not (raw_crew is Dictionary):
		return
	for cname in (raw_crew as Dictionary).keys():
		var cr: _CrewRelationship = _crew.get(String(cname), null) as _CrewRelationship
		if cr == null:
			continue
		var cd: Dictionary = (raw_crew as Dictionary)[cname]
		cr.trust = int(cd.get("trust", cr.trust))
		cr.respect = int(cd.get("respect", cr.respect))

func reset() -> void:
	# Reload from JSON to restore initial values.
	_crew.clear()
	_factions.clear()
	_dialogue_actions.clear()
	_quest_gates.clear()
	_loaded = false
	_load_config()