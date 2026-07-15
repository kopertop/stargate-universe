extends Node

# EarthVisit — manages the Earth-side segment of the communication stones visit.
#
# When CommStones puts the player in the PHASE_ON_EARTH state, EarthVisit
# provides the gameplay layer: SGC report objectives, NPC dialogue trees,
# and the personal moment (Eli visits his mom). It is the glue between
# the CommStones state machine and the actual Earth content.
#
# Data-driven: NPC dialogue trees, briefing narration, and personal moment
# lines are loaded from data/earth_dialogues.json at runtime.
#
# Save contract: registers as "earth_visit" in SaveManager.
# Serializes: personal_moment_done, sgc_briefing_shown, visited_npcs.
#
# Signals:
#   sgc_objective_reported(objective_id) — a report objective was delivered
#   personal_moment_started()            — Eli's mom scene started
#   personal_moment_complete()           — Eli's mom scene finished
#   all_reports_delivered()              — all 4 SGC objectives done
#   earth_segment_ready()                — EarthVisit data loaded and ready

signal sgc_objective_reported(objective_id: String)
signal personal_moment_started()
signal personal_moment_complete()
signal all_reports_done()
signal earth_segment_ready()

const DATA_PATH: String = "res://data/earth_dialogues.json"

# Objective IDs (must match comm_stones.json sgc_objectives).
const OBJ_AIR_CRISIS: String = "report_air_crisis"
const OBJ_SHIP_STATUS: String = "report_ship_status"
const OBJ_ALIEN_ENCOUNTER: String = "report_alien_encounter"
const OBJ_REQUEST_SUPPLIES: String = "request_supplies"

# NPC IDs from earth_dialogues.json.
const NPC_ONEILL: String = "general_oneill"
const NPC_BRIGHTMAN: String = "dr_brightman"
const NPC_ELIS_MOM: String = "elis_mom"

# Maps SGC objective IDs to the NPC who can receive that report.
const OBJECTIVE_NPC_MAP: Dictionary = {
	OBJ_AIR_CRISIS: NPC_ONEILL,
	OBJ_SHIP_STATUS: NPC_ONEILL,
	OBJ_ALIEN_ENCOUNTER: NPC_ONEILL,
	OBJ_REQUEST_SUPPLIES: NPC_ONEILL,
}

# Loaded data.
var _npcs: Dictionary = {}  # id → Dictionary (display_name, location, role, dialogue_tree, ambient_lines)
var _sgc_briefing_lines: Array = []
var _personal_moment_lines: Array = []

# Runtime state.
var _personal_moment_done: bool = false
var _sgc_briefing_shown: bool = false
var _visited_npcs: Array[String] = []

var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()
	# Register with SaveManager (autoload-tolerant for -s SceneTree tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "earth_visit", self)
	# Listen to CommStones body_swap_complete to auto-show briefing.
	var cs: Node = _autoload_node("CommStones")
	if cs != null and cs.has_signal("body_swap_complete"):
		if not cs.body_swap_complete.is_connected(_on_body_swap_complete):
			cs.body_swap_complete.connect(_on_body_swap_complete)


# --- Public API ---------------------------------------------------------------

# Called when the player arrives on Earth (body_swap_complete signal).
# Shows the SGC briefing narration the first time per visit.
func _on_body_swap_complete(_earth_body_id: String) -> void:
	if not _sgc_briefing_shown:
		_show_sgc_briefing()


# Show the SGC briefing room narration.
func show_sgc_briefing() -> void:
	_show_sgc_briefing()


func _show_sgc_briefing() -> void:
	_sgc_briefing_shown = true
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return
	for line in _sgc_briefing_lines:
		if gs.has_method("narrate"):
			gs.call("narrate", String(line))
	if gs.has_method("add_log"):
		gs.call("add_log", "Arrived at Stargate Command. Briefing room.")


# Deliver an SGC report objective. Called by SGCReportConsole or NPC dialogue
# action handlers. Delegates to CommStones for the actual objective tracking.
func deliver_report(objective_id: String) -> void:
	var cs: Node = _autoload_node("CommStones")
	if cs == null:
		push_warning("EarthVisit: CommStones not found when delivering report %s" % objective_id)
		return
	if not cs.has_method("complete_sgc_objective"):
		return
	# Check if already done to avoid double-reporting.
	if cs.call("is_sgc_objective_done", objective_id):
		return
	cs.call("complete_sgc_objective", objective_id)
	sgc_objective_reported.emit(objective_id)
	# Log via GameState.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_method("add_log"):
		var label: String = _objective_label(objective_id)
		gs.call("add_log", "SGC report delivered: %s" % label)
	# Check if all objectives are now done.
	if cs.has_method("all_sgc_objectives_done") and cs.call("all_sgc_objectives_done"):
		_on_all_reports_delivered()


# Start the personal moment (Eli visits his mom).
func start_personal_moment() -> void:
	if _personal_moment_done:
		return
	_personal_moment_done = true
	personal_moment_started.emit()
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return
	for line in _personal_moment_lines:
		if gs.has_method("narrate"):
			gs.call("narrate", String(line))
	if gs.has_method("add_log"):
		gs.call("add_log", "Visited Maryann Wallace — Eli's mother.")
	# Get the mom NPC dialogue tree and narrate the opening.
	var mom: Dictionary = _npcs.get(NPC_ELIS_MOM, {})
	if not mom.is_empty():
		var tree: Array = mom.get("dialogue_tree", [])
		if not tree.is_empty():
			var first: Dictionary = tree[0]
			var speaker: String = String(first.get("speaker", ""))
			var text: String = String(first.get("text", ""))
			if gs.has_method("say") and speaker != "" and text != "":
				gs.call("say", speaker, text)
	personal_moment_complete.emit()


# Mark an NPC as visited (for tracking/completion).
func visit_npc(npc_id: String) -> void:
	if not _visited_npcs.has(npc_id):
		_visited_npcs.append(npc_id)


# True if an NPC has been visited during this Earth visit.
func has_visited_npc(npc_id: String) -> bool:
	return _visited_npcs.has(npc_id)


# Get the dialogue tree for an Earth NPC. Returns empty array if not found.
func get_npc_dialogue_tree(npc_id: String) -> Array:
	_ensure_loaded()
	var npc: Dictionary = _npcs.get(npc_id, {})
	if npc.is_empty():
		return []
	return npc.get("dialogue_tree", [])


# Get NPC display name.
func get_npc_display_name(npc_id: String) -> String:
	_ensure_loaded()
	var npc: Dictionary = _npcs.get(npc_id, {})
	return String(npc.get("display_name", npc_id))


# Get NPC location string.
func get_npc_location(npc_id: String) -> String:
	_ensure_loaded()
	var npc: Dictionary = _npcs.get(npc_id, {})
	return String(npc.get("location", ""))


# Get NPC ambient lines.
func get_npc_ambient_lines(npc_id: String) -> Array:
	_ensure_loaded()
	var npc: Dictionary = _npcs.get(npc_id, {})
	return npc.get("ambient_lines", [])


# Get all NPC IDs.
func get_npc_ids() -> Array:
	_ensure_loaded()
	return _npcs.keys()


# Get the list of all available SGC objective IDs.
func get_sgc_objective_ids() -> Array:
	return [OBJ_AIR_CRISIS, OBJ_SHIP_STATUS, OBJ_ALIEN_ENCOUNTER, OBJ_REQUEST_SUPPLIES]


# True if the personal moment has been completed.
func is_personal_moment_done() -> bool:
	return _personal_moment_done


# True if the SGC briefing has been shown.
func is_sgc_briefing_shown() -> bool:
	return _sgc_briefing_shown


# True if all SGC report objectives have been delivered.
func all_reports_delivered() -> bool:
	var cs: Node = _autoload_node("CommStones")
	if cs == null:
		return false
	if cs.has_method("all_sgc_objectives_done"):
		return cs.call("all_sgc_objectives_done")
	return false


# Reset for a new Earth visit (called by CommStones or tests).
func reset_visit() -> void:
	_sgc_briefing_shown = false
	_visited_npcs.clear()


# Full reset (including personal moment state).
func reset() -> void:
	_personal_moment_done = false
	_sgc_briefing_shown = false
	_visited_npcs.clear()


# --- Save / Load contract -----------------------------------------------------

func serialize() -> Dictionary:
	return {
		"personal_moment_done": _personal_moment_done,
		"sgc_briefing_shown": _sgc_briefing_shown,
		"visited_npcs": _visited_npcs.duplicate(),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_personal_moment_done = data.get("personal_moment_done", false) == true
	_sgc_briefing_shown = data.get("sgc_briefing_shown", false) == true
	_visited_npcs.clear()
	var saved: Variant = data.get("visited_npcs", [])
	if saved is Array:
		for v in saved:
			_visited_npcs.append(String(v))


# --- Internal -----------------------------------------------------------------

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_data()
	earth_segment_ready.emit()


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("EarthVisit: data file not found: %s" % DATA_PATH)
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("EarthVisit: cannot open %s (err %d)" % [DATA_PATH, FileAccess.get_open_error()])
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("EarthVisit: failed to parse JSON from %s" % DATA_PATH)
		return
	var data: Dictionary = parsed
	# Load NPCs into a dict keyed by id.
	_npcs.clear()
	var npcs_arr: Variant = data.get("npcs", [])
	if npcs_arr is Array:
		for npc in npcs_arr:
			var nid: String = String(npc.get("id", ""))
			if nid != "":
				_npcs[nid] = npc
	_sgc_briefing_lines = data.get("sgc_briefing_lines", []) if data.get("sgc_briefing_lines") is Array else []
	_personal_moment_lines = data.get("personal_moment_lines", []) if data.get("personal_moment_lines") is Array else []


func _objective_label(objective_id: String) -> String:
	match objective_id:
		OBJ_AIR_CRISIS:
			return "Air crisis"
		OBJ_SHIP_STATUS:
			return "Ship status"
		OBJ_ALIEN_ENCOUNTER:
			return "Alien encounters"
		OBJ_REQUEST_SUPPLIES:
			return "Supply request"
		_:
			return objective_id


func _on_all_reports_delivered() -> void:
	all_reports_done.emit()
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "All SGC reports delivered. Return to the stone to go back to Destiny.")
	# Sync GameState mirror var.
	if gs != null:
		gs.set("all_sgc_objectives_done", true)


# Same autoload-tolerant pattern as CommStones._autoload_node.
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)