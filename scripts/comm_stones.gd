extends Node

# CommStones — Ancient communication stones body-swap system.
#
# Manages the consciousness-swap mechanic from SGU: when the player activates
# a communication stone pedestal on Destiny, their consciousness is
# transferred to a body on Earth. They explore an Earth location (SGC or
# Pentagon), report to SGC personnel, then return to Destiny.
#
# State machine:
#   IDLE        → no stone link active, player is on Destiny
#   SWAPPING    → cutscene in progress (fade + cinematic framing)
#   ON_EARTH    → player consciousness is in an Earth body
#   RETURNING   → return cutscene in progress
#
# Data-driven: stone definitions, Earth bodies, and SGC report objectives
# are loaded from data/comm_stones.json at runtime.
#
# Save contract: registers as the "comm_stones" ISaveableSystem in SaveManager.
# Serializes: current_phase, active_stone_id, active_earth_body_id,
# completed_sgc_objectives, stones_used, earth_visits, current_body_index.
#
# Signals:
#   stone_activated(stone_id)         — player placed hand on stone
#   body_swap_started(earth_body_id)  — consciousness transfer begins
#   body_swap_complete(earth_body_id) — player now controls Earth body
#   sgc_objective_completed(id)       — one of the SGC report objectives done
#   return_started()                  — return-to-Destiny sequence begins
#   return_complete()                 — player back on Destiny
#   phase_changed(new_phase)          — any phase transition

signal stone_activated(stone_id: String)
signal body_swap_started(earth_body_id: String)
signal body_swap_complete(earth_body_id: String)
signal sgc_objective_completed(id: String)
signal return_started()
signal return_complete()
signal phase_changed(new_phase: String)

const DATA_PATH: String = "res://data/comm_stones.json"

# Phase enum — the state machine.
const PHASE_IDLE: String = "idle"
const PHASE_SWAPPING: String = "swapping"
const PHASE_ON_EARTH: String = "on_earth"
const PHASE_RETURNING: String = "returning"

# Loaded data.
var _stones: Array = []
var _earth_bodies: Array = []
var _sgc_objectives: Array = []

# Runtime state.
var _phase: String = PHASE_IDLE
var _active_stone_id: String = ""
var _active_earth_body_id: String = ""
var _completed_sgc_objectives: Array[String] = []
var _stones_used: int = 0
var _earth_visits: int = 0
# Cycles through Earth bodies so each visit gives a different perspective.
var _body_index: int = 0

var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()
	# Register with SaveManager (autoload-tolerant for -s SceneTree tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "comm_stones", self)


# Check instant mode at call time (not _ready time) so tests that set
# SceneRouter.instant_mode after autoloads are loaded still work.
func _check_instant_mode() -> bool:
	var sr: Node = _autoload_node("SceneRouter")
	if sr == null:
		return false
	return bool(sr.get("instant_mode"))


# --- Public API ---------------------------------------------------------------

# Called by the stone pedestal Interactable when the player uses it.
# Triggers the body-swap cinematic, then emits body_swap_complete.
func activate_stone(stone_id: String = "stone_01") -> void:
	_ensure_loaded()
	if _phase != PHASE_IDLE:
		push_warning("CommStones: activate_stone called while not idle (phase=%s)" % _phase)
		return
	_active_stone_id = stone_id
	_stones_used += 1
	stone_activated.emit(stone_id)
	# In instant mode, skip the cinematic and jump straight to on_earth.
	if _check_instant_mode():
		_begin_earth_segment()
	else:
		_set_phase(PHASE_SWAPPING)
		await _play_swap_cinematic()
		_begin_earth_segment()


# Complete a specific SGC report objective. Called by dialogue trees or
# interactables on the Earth side.
func complete_sgc_objective(objective_id: String) -> void:
	_ensure_loaded()
	if _completed_sgc_objectives.has(objective_id):
		return
	_completed_sgc_objectives.append(objective_id)
	sgc_objective_completed.emit(objective_id)
	var def: Dictionary = _find_sgc_objective(objective_id)
	if not def.is_empty():
		var label: String = String(def.get("label", objective_id))
		var gs: Node = _autoload_node("GameState")
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "SGC report: %s — delivered." % label)
	# Check if all objectives are done → can return.
	if _all_sgc_objectives_done():
		var gs2: Node = _autoload_node("GameState")
		if gs2 != null and gs2.has_method("add_log"):
			gs2.call("add_log", "All SGC objectives complete. Return to the stone to go back to Destiny.")


# Return to Destiny. Called when the player uses the stone on the Earth side
# or when all objectives are complete and the player triggers the return.
func return_to_destiny() -> void:
	if _phase != PHASE_ON_EARTH:
		push_warning("CommStones: return_to_destiny called while not on Earth (phase=%s)" % _phase)
		return
	if _check_instant_mode():
		_end_earth_segment()
	else:
		_set_phase(PHASE_RETURNING)
		return_started.emit()
		await _play_return_cinematic()
		_end_earth_segment()


# True if the player is currently in an Earth body.
func is_on_earth() -> bool:
	return _phase == PHASE_ON_EARTH or _phase == PHASE_SWAPPING


# True if a specific SGC objective has been completed.
func is_sgc_objective_done(objective_id: String) -> bool:
	return _completed_sgc_objectives.has(objective_id)


# True if all SGC objectives are complete.
func all_sgc_objectives_done() -> bool:
	return _all_sgc_objectives_done()


# Get the active Earth body definition, or empty dict if not on Earth.
func get_active_earth_body() -> Dictionary:
	if _active_earth_body_id == "":
		return {}
	return _find_earth_body(_active_earth_body_id)


# Get the active stone definition, or empty dict if none active.
func get_active_stone() -> Dictionary:
	if _active_stone_id == "":
		return {}
	return _find_stone(_active_stone_id)


# Get all SGC objective definitions.
func get_sgc_objectives() -> Array:
	_ensure_loaded()
	return _sgc_objectives.duplicate(true)


# Get the list of completed SGC objective ids.
func get_completed_objectives() -> Array[String]:
	return _completed_sgc_objectives.duplicate()


# Get the current phase.
func get_phase() -> String:
	return _phase


# Get total number of Earth visits (how many times the player has used the stones).
func get_earth_visits() -> int:
	return _earth_visits


# Get the number of stones used.
func get_stones_used() -> int:
	return _stones_used


# Get all loaded stone definitions.
func get_stones() -> Array:
	_ensure_loaded()
	return _stones.duplicate(true)


# Get all loaded Earth body definitions.
func get_earth_bodies() -> Array:
	_ensure_loaded()
	return _earth_bodies.duplicate(true)


# --- Save / Load contract -----------------------------------------------------

func serialize() -> Dictionary:
	return {
		"phase": _phase,
		"active_stone_id": _active_stone_id,
		"active_earth_body_id": _active_earth_body_id,
		"completed_sgc_objectives": _completed_sgc_objectives.duplicate(),
		"stones_used": _stones_used,
		"earth_visits": _earth_visits,
		"body_index": _body_index,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_phase = String(data.get("phase", PHASE_IDLE))
	_active_stone_id = String(data.get("active_stone_id", ""))
	_active_earth_body_id = String(data.get("active_earth_body_id", ""))
	_completed_sgc_objectives.clear()
	var saved_objs: Variant = data.get("completed_sgc_objectives", [])
	if saved_objs is Array:
		for o in saved_objs:
			_completed_sgc_objectives.append(String(o))
	_stones_used = int(data.get("stones_used", 0))
	_earth_visits = int(data.get("earth_visits", 0))
	_body_index = int(data.get("body_index", 0))
	# If we were mid-swap when saved, snap back to idle (don't restore a
	# half-finished cinematic — the player reloads into a stable state).
	if _phase == PHASE_SWAPPING or _phase == PHASE_RETURNING:
		_phase = PHASE_IDLE
		_active_stone_id = ""
		_active_earth_body_id = ""
	phase_changed.emit(_phase)


# --- Reset --------------------------------------------------------------------

func reset() -> void:
	_phase = PHASE_IDLE
	_active_stone_id = ""
	_active_earth_body_id = ""
	_completed_sgc_objectives.clear()
	_stones_used = 0
	_earth_visits = 0
	_body_index = 0
	phase_changed.emit(_phase)


# --- Internal -----------------------------------------------------------------

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_data()


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("CommStones: data file not found: %s" % DATA_PATH)
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("CommStones: cannot open %s (err %d)" % [DATA_PATH, FileAccess.get_open_error()])
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("CommStones: failed to parse JSON from %s" % DATA_PATH)
		return
	var data: Dictionary = parsed
	_stones = data.get("stones", []) if data.get("stones") is Array else []
	_earth_bodies = data.get("earth_bodies", []) if data.get("earth_bodies") is Array else []
	_sgc_objectives = data.get("sgc_objectives", []) if data.get("sgc_objectives") is Array else []


func _set_phase(new_phase: String) -> void:
	if _phase == new_phase:
		return
	_phase = new_phase
	phase_changed.emit(new_phase)


func _begin_earth_segment() -> void:
	_earth_visits += 1
	# Cycle through Earth bodies so each visit gives a different perspective.
	if _earth_bodies.is_empty():
		push_error("CommStones: no Earth bodies defined")
		_set_phase(PHASE_IDLE)
		return
	_active_earth_body_id = String(_earth_bodies[_body_index % _earth_bodies.size()].get("id", ""))
	_body_index += 1
	_set_phase(PHASE_ON_EARTH)
	body_swap_started.emit(_active_earth_body_id)
	body_swap_complete.emit(_active_earth_body_id)
	# Log the transition via GameState.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_method("narrate"):
		var body: Dictionary = get_active_earth_body()
		var body_name: String = String(body.get("display_name", "Unknown"))
		var location: String = String(body.get("location", "Earth"))
		gs.call("narrate", "The stone hums. Light fills your vision. When it fades...")
		gs.call("narrate", "You open your eyes. You're on Earth — in the body of %s." % body_name)
		gs.call("narrate", "Location: %s" % location)
		gs.call("add_log", "Communication stones activated. Consciousness transferred to %s on Earth." % body_name)


func _end_earth_segment() -> void:
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_method("narrate"):
		gs.call("narrate", "The stone pulses. Your vision blurs...")
		gs.call("narrate", "You're back on Destiny. The stone is dark again.")
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Returned to Destiny from Earth visit #%d." % _earth_visits)
	return_complete.emit()
	_active_stone_id = ""
	_active_earth_body_id = ""
	_set_phase(PHASE_IDLE)


func _play_swap_cinematic() -> void:
	var cine: Node = _autoload_node("Cinematic")
	if cine == null or not cine.has_method("letterbox_in"):
		# No Cinematic autoload — skip.
		return
	await cine.call("letterbox_in")
	# Flash to white (the stone activation glow).
	if cine.has_method("flash"):
		await cine.call("flash", Color(0.8, 0.9, 1.0))
	# Brief hold for the "crossing" beat.
	await get_tree().create_timer(1.0).timeout
	await cine.call("letterbox_out")


func _play_return_cinematic() -> void:
	var cine: Node = _autoload_node("Cinematic")
	if cine == null or not cine.has_method("letterbox_in"):
		return
	await cine.call("letterbox_in")
	if cine.has_method("flash"):
		await cine.call("flash", Color(0.4, 0.5, 0.7))
	await get_tree().create_timer(0.8).timeout
	await cine.call("letterbox_out")


func _all_sgc_objectives_done() -> bool:
	_ensure_loaded()
	if _sgc_objectives.is_empty():
		return true
	for obj in _sgc_objectives:
		var oid: String = String(obj.get("id", ""))
		if not _completed_sgc_objectives.has(oid):
			return false
	return true


func _find_stone(stone_id: String) -> Dictionary:
	_ensure_loaded()
	for s in _stones:
		if String(s.get("id", "")) == stone_id:
			return s
	return {}


func _find_earth_body(body_id: String) -> Dictionary:
	_ensure_loaded()
	for b in _earth_bodies:
		if String(b.get("id", "")) == body_id:
			return b
	return {}


func _find_sgc_objective(obj_id: String) -> Dictionary:
	_ensure_loaded()
	for o in _sgc_objectives:
		if String(o.get("id", "")) == obj_id:
			return o
	return {}


# Same autoload-tolerant pattern as GameState._autoload_node.
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)