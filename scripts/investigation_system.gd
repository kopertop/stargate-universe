extends Node

# InvestigationSystem — murder mystery mechanic for Episode 7: Justice.
#
# Manages a full investigation loop:
#   1. Clue Gathering — discover clues at the crime scene and via Kino recordings.
#   2. Interrogation — talk to suspects via dialogue trees with lie detection.
#   3. Accusation — present evidence against a suspect; correct vs. wrong outcomes.
#   4. Faction Tension — escalates with each action; wrong accusations raise it,
#      correct ones lower it. At high tension, crew relationships degrade.
#
# Data-driven: all clue/suspect/accusation definitions live in
# data/investigation.json. The system loads them at init and exposes a
# query/modification API for the quest system, HUD, and dialog screen.
#
# Integration points:
#   - GameState.dialog_action signal → apply_dialog_action() for data-driven
#     investigation events from dialog trees (e.g. clue discovery, accusation).
#   - RelationshipSystem → apply_relationship_outcome() after accusation to
#     adjust trust/respect based on the outcome.
#   - QuestLog → quest_step_available() can check investigation state.
#   - SaveManager → serialize()/deserialize() for save/load round-trip.
#   - DialogScreen → get_suspect_dialogue() returns the dialogue tree with
#     lie detection metadata injected.
#
# Data: res://data/investigation.json

signal clue_discovered(clue_id: String)
signal clue_examined(clue_id: String, description: String)
signal suspect_interrogated(suspect_id: String)
signal lie_detected(suspect_id: String, dialogue_index: int, indicator: String)
signal truth_confirmed(suspect_id: String, dialogue_index: int)
signal accusation_made(suspect_id: String, is_correct: bool)
signal investigation_completed(outcome: String)
signal faction_tension_changed(old_value: int, new_value: int)
signal faction_tension_level_changed(old_level: String, new_level: String)

const DATA_PATH: String = "res://data/investigation.json"

# ── Investigation state ───────────────────────────────────────────────────────

# Phase of the investigation.
enum Phase {
	INACTIVE,       # No active investigation.
	CRIME_SCENE,    # Gathering clues at the crime scene.
	INTERROGATION,  # Interrogating suspects.
	ACCUSATION,     # Ready to make an accusation.
	COMPLETED       # Investigation resolved (correct or wrong).
}

var _phase: Phase = Phase.INACTIVE

# Loaded definitions from JSON.
var _scenario: Dictionary = {}
var _clues: Dictionary = {}          # clue_id → Dictionary
var _suspects: Dictionary = {}        # suspect_id → Dictionary
var _accusations: Dictionary = {}    # suspect_id → Dictionary
var _faction_tension_cfg: Dictionary = {}
var _lie_detection_cfg: Dictionary = {}

# Live state.
var _discovered_clues: Dictionary = {}   # clue_id → true
var _interrogated_suspects: Dictionary = {}  # suspect_id → true
var _interrogation_count: int = 0
var _faction_tension: int = 30
var _accused_suspect: String = ""
var _investigation_outcome: String = ""   # "correct", "wrong", "insufficient_evidence", ""
var _kino_deployed: bool = false

var _loaded: bool = false
var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()
	# Register with SaveManager (autoload-tolerant for -s SceneTree tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "investigation_system", self)
	# Listen for dialog_action so data-driven dialog trees can trigger
	# investigation events (clue discovery, accusation, etc.).
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_signal("dialog_action"):
		if not gs.dialog_action.is_connected(_on_dialog_action):
			gs.dialog_action.connect(_on_dialog_action)


# ── Initialization ───────────────────────────────────────────────────────────

# Idempotent lazy init. Run from _ready AND from every public entry point
# so headless `-s` SceneTree tests work without awaiting a frame.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_data()


func _load_data() -> void:
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("InvestigationSystem: cannot open %s" % DATA_PATH)
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("InvestigationSystem: failed to parse %s" % DATA_PATH)
		return
	var data: Dictionary = parsed

	_scenario = data.get("scenario", {})
	_clues = data.get("clues", {})
	_suspects = data.get("suspects", {})
	_accusations = data.get("accusations", {})
	_faction_tension_cfg = data.get("faction_tension", {})
	_lie_detection_cfg = data.get("lie_detection", {})

	# Initialize faction tension from config.
	_faction_tension = int(_faction_tension_cfg.get("initial", 30))

	_loaded = true


# ── Public API: Phase & State ─────────────────────────────────────────────────

## Returns the current investigation phase.
func get_phase() -> Phase:
	return _phase

## Returns the phase as a human-readable string.
func get_phase_string() -> String:
	match _phase:
		Phase.INACTIVE: return "inactive"
		Phase.CRIME_SCENE: return "crime_scene"
		Phase.INTERROGATION: return "interrogation"
		Phase.ACCUSATION: return "accusation"
		Phase.COMPLETED: return "completed"
		_: return "unknown"

## Starts the investigation. Called when E7 begins.
func start_investigation() -> void:
	_ensure_initialized()
	_phase = Phase.CRIME_SCENE
	_discovered_clues.clear()
	_interrogated_suspects.clear()
	_interrogation_count = 0
	_accused_suspect = ""
	_investigation_outcome = ""
	_faction_tension = int(_faction_tension_cfg.get("initial", 30))

## Returns true if the investigation is active (not inactive or completed).
func is_active() -> bool:
	return _phase != Phase.INACTIVE and _phase != Phase.COMPLETED

## Returns true if the investigation has been completed.
func is_completed() -> bool:
	return _phase == Phase.COMPLETED

## Returns the investigation outcome: "correct", "wrong",
## "insufficient_evidence", or "" if not yet completed.
func get_outcome() -> String:
	return _investigation_outcome

## Returns the scenario metadata dictionary.
func get_scenario() -> Dictionary:
	_ensure_initialized()
	return _scenario

## Sets whether a Kino is deployed (enables lie detection and Kino clues).
func set_kino_deployed(deployed: bool) -> void:
	_kino_deployed = deployed

## Returns true if a Kino is currently deployed.
func is_kino_deployed() -> bool:
	return _kino_deployed


# ── Public API: Clues ─────────────────────────────────────────────────────────

## Returns all clue definitions.
func get_all_clues() -> Dictionary:
	_ensure_initialized()
	return _clues

## Returns a specific clue definition by ID.
func get_clue(clue_id: String) -> Dictionary:
	_ensure_initialized()
	return _clues.get(clue_id, {})

## Returns true if a clue has been discovered.
func is_clue_discovered(clue_id: String) -> bool:
	return _discovered_clues.has(clue_id) and _discovered_clues[clue_id] == true

## Discovers a clue. Returns true if this is a new discovery.
func discover_clue(clue_id: String) -> bool:
	_ensure_initialized()
	if not _clues.has(clue_id):
		push_warning("InvestigationSystem: unknown clue '%s'" % clue_id)
		return false
	if is_clue_discovered(clue_id):
		return false

	var clue: Dictionary = _clues[clue_id]

	# Check Kino requirement.
	if clue.get("requires_kino", false) and not _kino_deployed:
		push_warning("InvestigationSystem: clue '%s' requires Kino deployment" % clue_id)
		return false

	_discovered_clues[clue_id] = true
	clue_discovered.emit(clue_id)

	# Escalate faction tension per clue discovered.
	_adjust_tension(int(_faction_tension_cfg.get("per_clue_discovered", 2)))

	# Check if we should advance to interrogation phase.
	_check_phase_advancement()

	return true

## Returns the number of clues discovered so far.
func get_discovered_clue_count() -> int:
	return _discovered_clues.size()

## Returns an array of all discovered clue IDs.
func get_discovered_clue_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _discovered_clues.keys():
		if _discovered_clues[key] == true:
			ids.append(key)
	return ids

## Returns the total evidence strength of all discovered clues.
func get_total_evidence_strength() -> int:
	var total: int = 0
	for clue_id in _discovered_clues.keys():
		if _discovered_clues[clue_id] == true:
			var clue: Dictionary = _clues.get(clue_id, {})
			total += int(clue.get("evidence_strength", 0))
	return total

## Returns clues that point toward a specific suspect.
func get_clues_pointing_to(suspect_id: String) -> Array[String]:
	var result: Array[String] = []
	for clue_id in _discovered_clues.keys():
		if _discovered_clues[clue_id] == true:
			var clue: Dictionary = _clues.get(clue_id, {})
			var points_to: Array = clue.get("points_to", [])
			if suspect_id in points_to:
				result.append(clue_id)
	return result

## Returns the evidence strength of clues pointing toward a specific suspect.
func get_evidence_strength_against(suspect_id: String) -> int:
	var total: int = 0
	for clue_id in _discovered_clues.keys():
		if _discovered_clues[clue_id] == true:
			var clue: Dictionary = _clues.get(clue_id, {})
			var points_to: Array = clue.get("points_to", [])
			if suspect_id in points_to:
				total += int(clue.get("evidence_strength", 0))
	return total


# ── Public API: Suspects & Interrogation ──────────────────────────────────────

## Returns all suspect definitions.
func get_all_suspects() -> Dictionary:
	_ensure_initialized()
	return _suspects

## Returns a specific suspect definition by ID.
func get_suspect(suspect_id: String) -> Dictionary:
	_ensure_initialized()
	return _suspects.get(suspect_id, {})

## Returns true if a suspect has been interrogated.
func is_suspect_interrogated(suspect_id: String) -> bool:
	return _interrogated_suspects.has(suspect_id) and _interrogated_suspects[suspect_id] == true

## Marks a suspect as interrogated. Returns true if this is new.
func mark_interrogated(suspect_id: String) -> bool:
	_ensure_initialized()
	if not _suspects.has(suspect_id):
		push_warning("InvestigationSystem: unknown suspect '%s'" % suspect_id)
		return false
	if is_suspect_interrogated(suspect_id):
		return false

	_interrogated_suspects[suspect_id] = true
	_interrogation_count += 1
	suspect_interrogated.emit(suspect_id)

	# Escalate faction tension per interrogation.
	_adjust_tension(int(_faction_tension_cfg.get("per_interrogation", 3)))

	# Check if we should advance to accusation phase.
	_check_phase_advancement()

	return true

## Returns the number of suspects interrogated.
func get_interrogated_count() -> int:
	return _interrogation_count

## Returns the dialogue tree for a suspect, with lie detection metadata.
## If kino is deployed, lie indicators are included; otherwise they are
## stripped and a no-kino notice is appended.
func get_suspect_dialogue(suspect_id: String) -> Array:
	_ensure_initialized()
	var suspect: Dictionary = _suspects.get(suspect_id, {})
	var tree: Array = suspect.get("dialogue_tree", [])
	var result: Array = []

	var lie_enabled: bool = _kino_deployed and bool(_lie_detection_cfg.get("enabled", true))

	for node in tree:
		var node_copy: Dictionary = node.duplicate(true)
		if not lie_enabled:
			# Strip lie detection data when Kino is not deployed.
			node_copy.erase("is_lie")
			node_copy.erase("lie_indicator")
		result.append(node_copy)

	return result

## Returns true if a dialogue node contains a lie (for UI lie detection display).
func is_dialogue_node_a_lie(suspect_id: String, dialogue_index: int) -> bool:
	_ensure_initialized()
	var suspect: Dictionary = _suspects.get(suspect_id, {})
	var tree: Array = suspect.get("dialogue_tree", [])
	if dialogue_index < 0 or dialogue_index >= tree.size():
		return false
	var node: Dictionary = tree[dialogue_index]
	return bool(node.get("is_lie", false))

## Returns the lie indicator text for a dialogue node, or "" if truthful.
func get_lie_indicator(suspect_id: String, dialogue_index: int) -> String:
	_ensure_initialized()
	var suspect: Dictionary = _suspects.get(suspect_id, {})
	var tree: Array = suspect.get("dialogue_tree", [])
	if dialogue_index < 0 or dialogue_index >= tree.size():
		return ""
	var node: Dictionary = tree[dialogue_index]
	if not bool(node.get("is_lie", false)):
		return ""
	return String(node.get("lie_indicator", ""))

## Processes a dialogue node for lie detection. Emits lie_detected or
## truth_confirmed signals. Returns the display text for the lie/truth indicator.
func process_dialogue_node(suspect_id: String, dialogue_index: int) -> String:
	_ensure_initialized()
	if not _kino_deployed or not bool(_lie_detection_cfg.get("enabled", true)):
		return String(_lie_detection_cfg.get("no_kino_text", ""))

	var is_lie: bool = is_dialogue_node_a_lie(suspect_id, dialogue_index)
	if is_lie:
		var indicator: String = get_lie_indicator(suspect_id, dialogue_index)
		lie_detected.emit(suspect_id, dialogue_index, indicator)
		return String(_lie_detection_cfg.get("hint_text", "[Lie Detected]")) + " " + indicator
	else:
		truth_confirmed.emit(suspect_id, dialogue_index)
		return String(_lie_detection_cfg.get("truth_text", "[Truthful]"))


# ── Public API: Accusation ───────────────────────────────────────────────────

## Returns true if the player can make an accusation against a suspect.
## Requires minimum evidence strength and all required clues.
func can_accuse(suspect_id: String) -> bool:
	_ensure_initialized()
	if not _accusations.has(suspect_id):
		return false
	if _phase == Phase.COMPLETED:
		return false

	var accusation: Dictionary = _accusations[suspect_id]
	var min_strength: int = int(accusation.get("min_evidence_strength", 0))
	var required: Array = accusation.get("required_clues", [])

	# Check evidence strength.
	if get_evidence_strength_against(suspect_id) < min_strength:
		return false

	# Check required clues.
	for clue_id in required:
		if not is_clue_discovered(clue_id):
			return false

	return true

## Returns a list of suspects that can be accused with current evidence.
func get_accusable_suspects() -> Array[String]:
	var result: Array[String] = []
	for suspect_id in _accusations.keys():
		if can_accuse(suspect_id):
			result.append(suspect_id)
	return result

## Makes an accusation against a suspect. Returns the outcome string:
## "correct", "wrong", or "insufficient_evidence".
func make_accusation(suspect_id: String) -> String:
	_ensure_initialized()
	if not _accusations.has(suspect_id):
		push_warning("InvestigationSystem: unknown accusation target '%s'" % suspect_id)
		return ""

	if _phase == Phase.COMPLETED:
		push_warning("InvestigationSystem: investigation already completed")
		return _investigation_outcome

	_accused_suspect = suspect_id
	var accusation: Dictionary = _accusations[suspect_id]
	var is_correct_target: bool = bool(accusation.get("is_correct", false))

	# Check if we have enough evidence.
	var can: bool = can_accuse(suspect_id)
	var outcome: String = ""

	if is_correct_target and can:
		outcome = "correct"
		_apply_outcome(accusation, "outcome_correct")
		_adjust_tension(int(_faction_tension_cfg.get("per_correct_accusation", -15)))
	elif not is_correct_target and can:
		outcome = "wrong"
		_apply_outcome(accusation, "outcome_wrong")
		_adjust_tension(int(_faction_tension_cfg.get("per_false_accusation", 25)))
	else:
		outcome = "insufficient_evidence"
		_apply_outcome(accusation, "outcome_insufficient_evidence")
		_adjust_tension(int(_faction_tension_cfg.get("per_false_accusation", 25)))

	_investigation_outcome = outcome
	_phase = Phase.COMPLETED
	accusation_made.emit(suspect_id, is_correct_target and can)
	investigation_completed.emit(outcome)

	return outcome

## Returns the ID of the accused suspect ("" if no accusation made).
func get_accused_suspect() -> String:
	return _accused_suspect

## Returns the true culprit's ID from the scenario data.
func get_true_culprit() -> String:
	_ensure_initialized()
	return String(_scenario.get("true_culprit", ""))


# ── Public API: Faction Tension ───────────────────────────────────────────────

## Returns the current faction tension level (0-100).
func get_faction_tension() -> int:
	return _faction_tension

## Returns the tension level as a string: "calm", "uneasy", "tense", "critical".
func get_faction_tension_level() -> String:
	return _tension_to_level(_faction_tension)

## Returns the tension level string for a given numeric value.
func _tension_to_level(value: int) -> String:
	var thresholds: Dictionary = _faction_tension_cfg.get("thresholds", {})
	# Thresholds are ordered calm → critical by max value.
	if value <= int(thresholds.get("calm", {}).get("max", 25)):
		return "calm"
	elif value <= int(thresholds.get("uneasy", {}).get("max", 50)):
		return "uneasy"
	elif value <= int(thresholds.get("tense", {}).get("max", 75)):
		return "tense"
	else:
		return "critical"

## Adjusts faction tension by a delta, clamped to [min, max].
func _adjust_tension(delta: int) -> void:
	var old_val: int = _faction_tension
	var old_level: String = _tension_to_level(old_val)
	var min_val: int = int(_faction_tension_cfg.get("min", 0))
	var max_val: int = int(_faction_tension_cfg.get("max", 100))
	_faction_tension = clampi(_faction_tension + delta, min_val, max_val)
	if _faction_tension != old_val:
		faction_tension_changed.emit(old_val, _faction_tension)
		var new_level: String = _tension_to_level(_faction_tension)
		if new_level != old_level:
			faction_tension_level_changed.emit(old_level, new_level)

## Directly set faction tension (for testing or scripted events).
func set_faction_tension(value: int) -> void:
	var min_val: int = int(_faction_tension_cfg.get("min", 0))
	var max_val: int = int(_faction_tension_cfg.get("max", 100))
	_faction_tension = clampi(value, min_val, max_val)


# ── Public API: Summary & HUD ─────────────────────────────────────────────────

## Returns a summary dictionary for HUD display.
func get_summary() -> Dictionary:
	return {
		"phase": get_phase_string(),
		"clues_discovered": get_discovered_clue_count(),
		"total_clues": _clues.size(),
		"suspects_interrogated": _interrogation_count,
		"total_suspects": _suspects.size(),
		"faction_tension": _faction_tension,
		"faction_tension_level": get_faction_tension_level(),
		"evidence_strength": get_total_evidence_strength(),
		"accused_suspect": _accused_suspect,
		"outcome": _investigation_outcome,
		"kino_deployed": _kino_deployed,
		"victim": String(_scenario.get("victim_display", "")),
		"crime_scene": String(_scenario.get("crime_scene_display", ""))
	}

## Returns a per-suspect evidence summary for the accusation UI.
func get_suspect_evidence_summary(suspect_id: String) -> Dictionary:
	return {
		"suspect_id": suspect_id,
		"suspect_name": String(_suspects.get(suspect_id, {}).get("display_name", suspect_id)),
		"evidence_strength": get_evidence_strength_against(suspect_id),
		"min_required": int(_accusations.get(suspect_id, {}).get("min_evidence_strength", 0)),
		"can_accuse": can_accuse(suspect_id),
		"supporting_clues": get_clues_pointing_to(suspect_id),
		"interrogated": is_suspect_interrogated(suspect_id)
	}


# ── Phase Advancement ─────────────────────────────────────────────────────────

## Checks whether the investigation should advance to the next phase.
func _check_phase_advancement() -> void:
	if _phase == Phase.CRIME_SCENE:
		# Advance to interrogation after discovering at least 2 clues.
		if get_discovered_clue_count() >= 2:
			_phase = Phase.INTERROGATION
	elif _phase == Phase.INTERROGATION:
		# Advance to accusation after interrogating at least 1 suspect
		# and having enough evidence to accuse someone.
		if _interrogation_count >= 1 and get_accusable_suspects().size() > 0:
			_phase = Phase.ACCUSATION


# ── Outcome Application ───────────────────────────────────────────────────────

## Applies an outcome's faction tension and relationship changes.
func _apply_outcome(accusation: Dictionary, outcome_key: String) -> void:
	var outcome: Dictionary = accusation.get(outcome_key, {})
	if outcome.is_empty():
		return

	# Apply faction tension changes.
	var tension_changes: Dictionary = outcome.get("faction_tension_changes", {})
	# These are informational — the main tension adjustment is done via
	# _adjust_tension() in make_accusation(). But we also apply per-faction
	# changes via RelationshipSystem if available.
	var rs: Node = _autoload_node("RelationshipSystem")
	if rs == null:
		return

	# Apply relationship changes.
	var rel_changes: Dictionary = outcome.get("relationship_changes", {})
	for crew_name in rel_changes.keys():
		var changes: Dictionary = rel_changes[crew_name]
		var trust_delta: int = int(changes.get("trust", 0))
		var respect_delta: int = int(changes.get("respect", 0))
		if trust_delta != 0:
			rs.call("adjust_trust", crew_name, trust_delta)
		if respect_delta != 0:
			rs.call("adjust_respect", crew_name, respect_delta)


# ── Dialog Action Handler ─────────────────────────────────────────────────────

## Handles dialog_action signals from GameState. Supports investigation-specific
## action IDs:
##   "investigation:discover_clue:<clue_id>"  — discover a clue
##   "investigation:interrogate:<suspect_id>" — mark suspect interrogated
##   "investigation:accuse:<suspect_id>"      — make an accusation
##   "investigation:deploy_kino"              — set kino deployed
##   "investigation:accuse_simeon_confession" — trigger confession accusation
func _on_dialog_action(action_id: String) -> void:
	if not action_id.begins_with("investigation:"):
		return

	var parts: PackedStringArray = action_id.split(":")
	if parts.size() < 2:
		return

	var sub: String = parts[1]
	match sub:
		"discover_clue":
			if parts.size() >= 3:
				discover_clue(parts[2])
		"interrogate":
			if parts.size() >= 3:
				mark_interrogated(parts[2])
		"accuse":
			if parts.size() >= 3:
				make_accusation(parts[2])
		"deploy_kino":
			set_kino_deployed(true)
		"accuse_simeon_confession":
			make_accusation("Simeon")


# ── Save / Load ───────────────────────────────────────────────────────────────

## Serialize state for SaveManager.
func serialize() -> Dictionary:
	return {
		"phase": int(_phase),
		"discovered_clues": _discovered_clues.duplicate(true),
		"interrogated_suspects": _interrogated_suspects.duplicate(true),
		"interrogation_count": _interrogation_count,
		"faction_tension": _faction_tension,
		"accused_suspect": _accused_suspect,
		"investigation_outcome": _investigation_outcome,
		"kino_deployed": _kino_deployed
	}

## Deserialize state from SaveManager.
func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_initialized()
	_phase = data.get("phase", Phase.INACTIVE) as Phase
	_discovered_clues = data.get("discovered_clues", {}).duplicate(true)
	_interrogated_suspects = data.get("interrogated_suspects", {}).duplicate(true)
	_interrogation_count = int(data.get("interrogation_count", 0))
	_faction_tension = int(data.get("faction_tension", 30))
	_accused_suspect = String(data.get("accused_suspect", ""))
	_investigation_outcome = String(data.get("investigation_outcome", ""))
	_kino_deployed = bool(data.get("kino_deployed", false))

## Reset to initial state (for new game or reset).
func reset() -> void:
	_phase = Phase.INACTIVE
	_discovered_clues.clear()
	_interrogated_suspects.clear()
	_interrogation_count = 0
	_faction_tension = int(_faction_tension_cfg.get("initial", 30))
	_accused_suspect = ""
	_investigation_outcome = ""
	_kino_deployed = false


# ── Utility ───────────────────────────────────────────────────────────────────

# Same pattern as GameState/QuestLog/RelationshipSystem.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)