extends Node

# LifeMissions — manages the E6 "Life" personal story missions for crew members.
#
# Three personal quests, each gated by a relationship threshold with the
# relevant crew member:
#   1. TJ — Medical Supplies (requires "friendly")
#   2. Camille — Political Mediation (requires "neutral")
#   3. Greer — Emotional Guard (requires "wary")
#
# Each mission has a multi-node dialogue tree loaded from
# data/e6_life_dialogues.json. The player can start a mission only if their
# relationship level with the crew member meets the required threshold.
#
# Mission states: locked → available → active → completed
#   locked    — relationship too low; mission not visible
#   available — relationship met; player can start the mission
#   active    — player has started the mission; dialogue tree in progress
#   completed — mission finished; rewards applied
#
# Integration:
#   - RelationshipSystem → meets_threshold() to check availability
#   - GameState.dialog_action signal → apply_dialogue_action() for
#     relationship changes from dialogue choices
#   - QuestLog → quest_step_available() gates E6 quest steps behind
#     mission completion
#   - SaveManager → serialize()/deserialize() for save/load round-trip
#
# Data: res://data/e6_life_dialogues.json

signal mission_started(mission_id: String)
signal mission_completed(mission_id: String)
signal mission_state_changed(mission_id: String, old_state: String, new_state: String)
signal all_missions_completed()

const DATA_PATH: String = "res://data/e6_life_dialogues.json"

# Mission IDs.
const MISSION_TJ: String = "tj_medical_supplies"
const MISSION_CAMILLE: String = "camille_political_mediation"
const MISSION_GREER: String = "greer_emotional_guard"

# Mission states.
const STATE_LOCKED: String = "locked"
const STATE_AVAILABLE: String = "available"
const STATE_ACTIVE: String = "active"
const STATE_COMPLETED: String = "completed"

# Loaded data: mission_id → Dictionary.
var _missions: Dictionary = {}

# Runtime state: mission_id → String (state).
var _mission_states: Dictionary = {}

# Which dialogue node the player is currently on per mission.
var _dialogue_positions: Dictionary = {}

var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()
	_register_with_save_manager()
	# Listen to GameState.dialog_action for E6-specific dialogue actions.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_signal("dialog_action"):
		if not gs.dialog_action.is_connected(_on_dialog_action):
			gs.dialog_action.connect(_on_dialog_action)


# ── Public API: data access ───────────────────────────────────────────────────

## Returns the list of all mission IDs.
func mission_ids() -> Array:
	_ensure_loaded()
	return _missions.keys()


## Returns the mission data Dictionary for a mission, or {}.
func get_mission(mission_id: String) -> Dictionary:
	_ensure_loaded()
	return _missions.get(mission_id, {})


## Returns the display name for a mission.
func get_mission_display_name(mission_id: String) -> String:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	return String(m.get("display_name", ""))


## Returns the crew member name for a mission.
func get_mission_crew(mission_id: String) -> String:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	return String(m.get("crew", ""))


## Returns the required relationship level for a mission.
func get_mission_required_level(mission_id: String) -> String:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	return String(m.get("required_level", "neutral"))


## Returns the location string for a mission.
func get_mission_location(mission_id: String) -> String:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	return String(m.get("location", ""))


## Returns the summary text for a mission.
func get_mission_summary(mission_id: String) -> String:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	return String(m.get("summary", ""))


## Returns the dialogue tree (Array of node Dictionaries) for a mission.
func get_mission_dialogue_tree(mission_id: String) -> Array:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	var tree: Variant = m.get("dialogue_tree", [])
	if tree is Array:
		return tree as Array
	return []


## Returns the ambient lines (Array of strings) for a mission.
func get_mission_ambient_lines(mission_id: String) -> Array:
	_ensure_loaded()
	var m: Dictionary = _missions.get(mission_id, {})
	var lines: Variant = m.get("ambient_lines", [])
	if lines is Array:
		return lines as Array
	return []


# ── Public API: mission state ─────────────────────────────────────────────────

## Returns the current state of a mission (locked/available/active/completed).
func get_mission_state(mission_id: String) -> String:
	_ensure_loaded()
	return String(_mission_states.get(mission_id, STATE_LOCKED))


## Returns true if the mission is completed.
func is_mission_completed(mission_id: String) -> bool:
	return get_mission_state(mission_id) == STATE_COMPLETED


## Returns true if all three missions are completed.
func all_missions_done() -> bool:
	for mid in _missions.keys():
		if not is_mission_completed(mid):
			return false
	return _missions.size() > 0


## Returns the number of completed missions.
func completed_count() -> int:
	var count: int = 0
	for mid in _mission_states.keys():
		if _mission_states[mid] == STATE_COMPLETED:
			count += 1
	return count


## Returns the total number of missions.
func total_missions() -> int:
	return _missions.size()


## Returns an Array of mission IDs that are currently available (relationship
## met but not yet started).
func available_missions() -> Array:
	_ensure_loaded()
	var result: Array = []
	for mid in _missions.keys():
		if get_mission_state(mid) == STATE_AVAILABLE:
			result.append(mid)
	return result


## Returns an Array of mission IDs that are currently active.
func active_missions() -> Array:
	_ensure_loaded()
	var result: Array = []
	for mid in _missions.keys():
		if get_mission_state(mid) == STATE_ACTIVE:
			result.append(mid)
	return result


## Returns an Array of mission IDs that are completed.
func completed_missions() -> Array:
	_ensure_loaded()
	var result: Array = []
	for mid in _missions.keys():
		if is_mission_completed(mid):
			result.append(mid)
	return result


## Refreshes the state of all missions based on current relationship levels.
## A locked mission becomes available when the relationship threshold is met.
## This is called on _ready and can be called manually after relationship
## changes.
func refresh_mission_states() -> void:
	_ensure_loaded()
	var rs: Node = _autoload_node("RelationshipSystem")
	if rs == null:
		return
	for mid in _missions.keys():
		var current_state: String = get_mission_state(mid)
		# Don't downgrade completed or active missions.
		if current_state == STATE_COMPLETED or current_state == STATE_ACTIVE:
			continue
		var m: Dictionary = _missions[mid]
		var crew: String = String(m.get("crew", ""))
		var level: String = String(m.get("required_level", "neutral"))
		if rs.has_method("meets_threshold"):
			if rs.call("meets_threshold", crew, level):
				_set_state(mid, STATE_AVAILABLE)
			else:
				_set_state(mid, STATE_LOCKED)


## Starts a mission if it's available. Returns true on success.
func start_mission(mission_id: String) -> bool:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return false
	var state: String = get_mission_state(mission_id)
	if state != STATE_AVAILABLE and state != STATE_LOCKED:
		# Already active or completed.
		return state == STATE_ACTIVE
	# Check relationship threshold.
	var rs: Node = _autoload_node("RelationshipSystem")
	if rs == null:
		return false
	var m: Dictionary = _missions[mission_id]
	var crew: String = String(m.get("crew", ""))
	var level: String = String(m.get("required_level", "neutral"))
	if rs.has_method("meets_threshold"):
		if not rs.call("meets_threshold", crew, level):
			return false
	_set_state(mission_id, STATE_ACTIVE)
	_dialogue_positions[mission_id] = 0
	mission_started.emit(mission_id)
	return true


## Completes a mission. Called when the dialogue tree reaches the "exit" node
## with a completion action, or can be called directly for testing.
func complete_mission(mission_id: String) -> bool:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return false
	var state: String = get_mission_state(mission_id)
	if state == STATE_COMPLETED:
		return true
	if state != STATE_ACTIVE:
		return false
	_set_state(mission_id, STATE_COMPLETED)
	_dialogue_positions.erase(mission_id)
	mission_completed.emit(mission_id)
	if all_missions_done():
		all_missions_completed.emit()
	return true


## Forces a mission into the completed state (for testing/debug).
func force_complete(mission_id: String) -> void:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return
	_set_state(mission_id, STATE_COMPLETED)
	_dialogue_positions.erase(mission_id)
	mission_completed.emit(mission_id)
	if all_missions_done():
		all_missions_completed.emit()


# ── Public API: dialogue progression ─────────────────────────────────────────

## Returns the current dialogue node for a mission, or null.
func get_current_dialogue_node(mission_id: String) -> Dictionary:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return {}
	var state: String = get_mission_state(mission_id)
	if state != STATE_ACTIVE:
		return {}
	var pos: int = int(_dialogue_positions.get(mission_id, 0))
	var tree: Array = get_mission_dialogue_tree(mission_id)
	if pos < 0 or pos >= tree.size():
		return {}
	return tree[pos] as Dictionary


## Returns the current dialogue position index for a mission.
func get_dialogue_position(mission_id: String) -> int:
	return int(_dialogue_positions.get(mission_id, 0))


## Advances the dialogue for a mission to the node at the given index.
## If the target is "exit", completes the mission.
func advance_dialogue(mission_id: String, target: Variant) -> void:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return
	if get_mission_state(mission_id) != STATE_ACTIVE:
		return
	if target is String:
		if target == "exit":
			# Check if there's a completion action in the current node's
			# selected choice. The caller should have fired the action via
			# GameState.dialog_action before calling advance_dialogue.
			complete_mission(mission_id)
			return
		# Numeric string → convert.
		var idx: int = int(target)
		_dialogue_positions[mission_id] = idx
	elif target is int:
		_dialogue_positions[mission_id] = target


## Processes a dialogue choice: fires the action (if any) and advances.
## choice_index is the index into the current node's choices array.
func process_choice(mission_id: String, choice_index: int) -> void:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return
	if get_mission_state(mission_id) != STATE_ACTIVE:
		return
	var node: Dictionary = get_current_dialogue_node(mission_id)
	if node.is_empty():
		return
	var choices: Variant = node.get("choices", [])
	if not (choices is Array):
		return
	var choices_arr: Array = choices as Array
	if choice_index < 0 or choice_index >= choices_arr.size():
		return
	var choice: Dictionary = choices_arr[choice_index] as Dictionary
	# Fire the dialogue action if present.
	var action: String = String(choice.get("action", ""))
	if action != "":
		var gs: Node = _autoload_node("GameState")
		if gs != null and gs.has_signal("dialog_action"):
			gs.emit_signal("dialog_action", action)
	# Advance to the target node.
	var target: Variant = choice.get("next", "exit")
	advance_dialogue(mission_id, target)


# ── Public API: mission availability check ───────────────────────────────────

## Returns true if the player's relationship with the crew member meets the
## threshold for this mission.
func is_mission_unlocked(mission_id: String) -> bool:
	_ensure_loaded()
	if not _missions.has(mission_id):
		return false
	var rs: Node = _autoload_node("RelationshipSystem")
	if rs == null:
		return false
	var m: Dictionary = _missions[mission_id]
	var crew: String = String(m.get("crew", ""))
	var level: String = String(m.get("required_level", "neutral"))
	if rs.has_method("meets_threshold"):
		return rs.call("meets_threshold", crew, level)
	return false


## Returns a summary Array of Dictionaries for all missions, for HUD use.
func get_all_missions_summary() -> Array:
	_ensure_loaded()
	var result: Array = []
	for mid in _missions.keys():
		var m: Dictionary = _missions[mid]
		result.append({
			"id": mid,
			"display_name": String(m.get("display_name", "")),
			"crew": String(m.get("crew", "")),
			"location": String(m.get("location", "")),
			"required_level": String(m.get("required_level", "neutral")),
			"state": get_mission_state(mid),
			"summary": String(m.get("summary", "")),
		})
	return result


# ── Internal ─────────────────────────────────────────────────────────────────

func _set_state(mission_id: String, new_state: String) -> void:
	var old_state: String = get_mission_state(mission_id)
	if old_state == new_state:
		return
	_mission_states[mission_id] = new_state
	mission_state_changed.emit(mission_id, old_state, new_state)


func _on_dialog_action(action_id: String) -> void:
	# Check if this is a mission-completion action.
	# The dialogue tree's "exit" nodes with completion actions are handled
	# by process_choice → advance_dialogue. But we also listen here for
	# any E6-specific actions that should trigger relationship changes
	# (those are handled by RelationshipSystem which also listens to
	# dialog_action). We don't need to do anything extra here — the
	# RelationshipSystem handles the relationship deltas.
	pass


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_data()
	# Initialize all missions to locked state.
	for mid in _missions.keys():
		_mission_states[mid] = STATE_LOCKED
	# Refresh states based on current relationships.
	refresh_mission_states()


func _load_data() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("LifeMissions: cannot open %s" % DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("LifeMissions: %s did not parse to a Dictionary" % DATA_PATH)
		return
	var data: Dictionary = parsed as Dictionary
	var missions: Variant = data.get("missions", [])
	if not (missions is Array):
		push_error("LifeMissions: 'missions' is not an array in %s" % DATA_PATH)
		return
	for m in missions as Array:
		if not (m is Dictionary):
			continue
		var md: Dictionary = m as Dictionary
		var mid: String = String(md.get("id", ""))
		if mid == "":
			continue
		_missions[mid] = md


func _register_with_save_manager() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "life_missions", self)


func _autoload_node(name: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(name)


# ── Save round-trip (ISaveableSystem) ─────────────────────────────────────────

func serialize() -> Dictionary:
	var states: Dictionary = {}
	for mid in _mission_states.keys():
		states[mid] = _mission_states[mid]
	var positions: Dictionary = {}
	for mid in _dialogue_positions.keys():
		positions[mid] = _dialogue_positions[mid]
	return {
		"mission_states": states,
		"dialogue_positions": positions,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_mission_states.clear()
	_dialogue_positions.clear()
	var states: Variant = data.get("mission_states", {})
	if states is Dictionary:
		for mid in (states as Dictionary).keys():
			_mission_states[String(mid)] = String((states as Dictionary)[mid])
	var positions: Variant = data.get("dialogue_positions", {})
	if positions is Dictionary:
		for mid in (positions as Dictionary).keys():
			_dialogue_positions[String(mid)] = int((positions as Dictionary)[mid])


func reset() -> void:
	_mission_states.clear()
	_dialogue_positions.clear()
	_ensure_loaded()
	for mid in _missions.keys():
		_mission_states[mid] = STATE_LOCKED
	refresh_mission_states()