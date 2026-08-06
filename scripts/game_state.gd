extends Node

# Global persistent game state. Cross-scene singleton.
# State delegated to subsystem autoloads; this file keeps core ship state,
# proxy properties for back-compat, and thin facade methods.

signal health_changed(value: float)
signal oxygen_changed(value: float)
signal objective_changed(text: String)
signal quest_step_changed(step: String)
signal room_discovered(room_id: String)
signal room_deciphered(room_id: String)
signal pois_discovered_changed()
signal resource_changed(type: String, count: int)
signal scrubber_level_changed(level: float)
signal scrubber_unit_changed(id: String)
signal gate_window_expired()
signal current_room_changed(room_id: String)
signal kino_changed(acquired: bool)
signal episode_completed()
signal log_added(line: String)
signal planet_run_ended()
signal dialogue_shown(character_name: String, line: String)
signal narrative_added(speaker: String, text: String)
signal chat_cleared()
signal kino_closed()
signal door_traversed(key: String)
signal deployed_kinos_changed()
signal power_changed(value: float)
signal hull_changed(value: float)
signal dialog_started(npc: Node3D, tree: Array)
signal dialog_closed()
signal dialog_action(action_id: String)
signal dialog_release()

# --- Constants (back-compat: 29 files reference these) ---
const MAX_HEALTH: float = 100.0
const MAX_OXYGEN: float = 100.0
const EPISODE_AIR: String = "air"
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
const SCRUBBER_REPAIR_LIME_COST: int = 1
const PLANETS_PATH: String = "res://data/planets.json"
const AIR_LIME_WORLD_ID: String = "air_lime_world"
const TRACKED_RESOURCES: Array[Dictionary] = [
	{"id": "water", "label": "Water", "low_threshold": 10, "default_amount": 4},
	{"id": "food", "label": "Food", "low_threshold": 10, "default_amount": 6},
	{"id": "parts", "label": "Ship Parts", "low_threshold": 6, "default_amount": 2},
	{"id": "lime", "label": "Lime", "low_threshold": 3, "default_amount": 0},
]
const SCRUBBER_LIME_RECHARGE: float = 100.0 / float(AIR_LIME_REQUIRED)
const SCRUBBER_DECAY_PER_SEC: float = SCRUBBER_LIME_RECHARGE / 3600.0
const SCRUBBER_WARN_PERCENT: float = 33.0
const SCRUBBER_O2_BLEED_PER_SEC: float = 1.0 / 60.0
const KINO_ORB_MAX: int = 3
const KINO_DEPLOYED_MAX: int = 3
const SHIP_PHASE_BASE: float = 1800.0
const PLANET_WINDOW_BASE: float = 600.0
const PLANET_SEED_SALT: int = 2654435761
const STATUS_OFFLINE: float = -1.0
const KNOCKOUT_TARGET_BANK: int = 1
const _KNOCKOUT_LINES_PATH: String = "res://data/knockout_lines.json"
const _POI_TOAST_INTERVAL: float = 1.0
const AUX_SCRUBBERS: Array = [
	{"id": "north_corridor", "room": "north_corridor", "name": "North Section Scrubber"},
	{"id": "east_far", "room": "east_corridor_far", "name": "East Maintenance Scrubber"},
	{"id": "hydroponics", "room": "hydroponics", "name": "Hydroponics Scrubber"},
]

# --- FTL loop tuning + crew scalars ---
var ship_phase_override: float = -1.0
var planet_window_override: float = -1.0
var crew_count: int = 6
var active_sections: int = 3

func ship_phase_base_seconds() -> float:
	return ship_phase_override if ship_phase_override >= 0.0 else SHIP_PHASE_BASE
func planet_window_base_seconds() -> float:
	return planet_window_override if planet_window_override >= 0.0 else PLANET_WINDOW_BASE
func crew_size() -> int:
	return crew_count
func active_section_count() -> int:
	return active_sections

# --- Core ship state (lives HERE) ---
var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var current_scene_path: String = ""
var pending_spawn_position: Variant = null
var pending_spawn_yaw: float = 0.0
var next_room_id: String = ""
var skip_arrival_cinematic: bool = false
var kino_pilot_mode: bool = false
var kino_return_position: Variant = null
var kino_return_yaw: float = 0.0
var kino_return_scene: String = ""
var kino_return_room_id: String = ""
var kino_pilot_target_scene: String = ""
var kino_pilot_target_pos: Variant = null
var kino_pilot_arrival_spawn: String = ""
var kino_autopilot: bool = false
var quarters_found: bool = false  # @collection-ok: E1 story flag — room-state discovery, not an inventory item
var eli_quarters_visited: bool = false
var elevator_repaired: bool = false
var rooms_discovered: Array[String] = []
var rooms_deciphered: Array[String] = []
var doors_traversed: Array[String] = []
var discovered_pois: Dictionary = {}
var breaches_sealed: Array[String] = []
var power_percent: float = STATUS_OFFLINE
var hull_percent: float = STATUS_OFFLINE
var current_room_id: String = ""
var current_objective: String = "Explore the Destiny"
var log_entries: Array[String] = []
var _poi_toast_queue: Array[String] = []
var _poi_toast_timer: SceneTreeTimer = null

# --- Proxy properties (delegate to subsystem autoloads via _gp/_sp) ---
var current_episode: String:
	get: return String(_gp("QuestFlowSystem","current_episode",EPISODE_AIR))
	set(v): _sp("QuestFlowSystem","current_episode",v)
var quest_step: String:
	get: return String(_gp("QuestFlowSystem","quest_step",QUEST_TALK_SCOTT))
	set(v): _sp("QuestFlowSystem","quest_step",v)
var episode_complete: bool:
	get: return bool(_gp("QuestFlowSystem","episode_complete",false))
	set(v): _sp("QuestFlowSystem","episode_complete",v)
var prologue_complete: bool:
	get: return bool(_gp("QuestFlowSystem","prologue_complete",false))
	set(v): _sp("QuestFlowSystem","prologue_complete",v)
var air_crisis_started: bool:
	get: return bool(_gp("QuestFlowSystem","air_crisis_started",false))
	set(v): _sp("QuestFlowSystem","air_crisis_started",v)
var control_room_returned: bool:
	get: return bool(_gp("QuestFlowSystem","control_room_returned",false))
	set(v): _sp("QuestFlowSystem","control_room_returned",v)
var blocked_door_beat_done: bool:
	get: return bool(_gp("QuestFlowSystem","blocked_door_beat_done",false))
	set(v): _sp("QuestFlowSystem","blocked_door_beat_done",v)
var door_panel_examined: bool:
	get: return bool(_gp("QuestFlowSystem","door_panel_examined",false))
	set(v): _sp("QuestFlowSystem","door_panel_examined",v)
var life_support_diagnosed: bool:
	get: return bool(_gp("QuestFlowSystem","life_support_diagnosed",false))
	set(v): _sp("QuestFlowSystem","life_support_diagnosed",v)
var ftl_drop_triggered: bool:
	get: return bool(_gp("QuestFlowSystem","ftl_drop_triggered",false))
	set(v): _sp("QuestFlowSystem","ftl_drop_triggered",v)
var lime_planet_dialed: bool:
	get: return bool(_gp("QuestFlowSystem","lime_planet_dialed",false))
	set(v): _sp("QuestFlowSystem","lime_planet_dialed",v)
var reported_to_gate: bool:
	get: return bool(_gp("QuestFlowSystem","reported_to_gate",false))
	set(v): _sp("QuestFlowSystem","reported_to_gate",v)
var returned_from_lime_planet: bool:
	get: return bool(_gp("QuestFlowSystem","returned_from_lime_planet",false))
	set(v): _sp("QuestFlowSystem","returned_from_lime_planet",v)
var recovering_in_infirmary: bool:
	get: return bool(_gp("QuestFlowSystem","recovering_in_infirmary",false))
	set(v): _sp("QuestFlowSystem","recovering_in_infirmary",v)
var knockout_cause: String:
	get: return String(_gp("QuestFlowSystem","knockout_cause",""))
	set(v): _sp("QuestFlowSystem","knockout_cause",v)
var pending_planet_return: bool:
	get: return bool(_gp("QuestFlowSystem","pending_planet_return",false))
	set(v): _sp("QuestFlowSystem","pending_planet_return",v)
var met_scott: bool:
	get: return bool(_gp("QuestFlowSystem","met_scott",false))
	set(v): _sp("QuestFlowSystem","met_scott",v)
var met_rush: bool:
	get: return bool(_gp("QuestFlowSystem","met_rush",false))
	set(v): _sp("QuestFlowSystem","met_rush",v)
var pressure_suits_found: bool:
	get: return bool(_gp("QuestFlowSystem","pressure_suits_found",false))
	set(v): _sp("QuestFlowSystem","pressure_suits_found",v)
var scrubber_diagnosed: bool:
	get: return bool(_gp("ScrubberSystem","scrubber_diagnosed",false))
	set(v): _sp("ScrubberSystem","scrubber_diagnosed",v)
var scrubber_repaired: bool:
	get: return bool(_gp("ScrubberSystem","scrubber_repaired",false))
	set(v): _sp("ScrubberSystem","scrubber_repaired",v)
var scrubber_level: float:
	get: return float(_gp("ScrubberSystem","scrubber_level",0.0))
	set(v): _sp("ScrubberSystem","scrubber_level",v)
var _scrubber_warned: bool:
	get: return bool(_gp("ScrubberSystem","_scrubber_warned",false))
	set(v): _sp("ScrubberSystem","_scrubber_warned",v)
var _scrubber_critical: bool:
	get: return bool(_gp("ScrubberSystem","_scrubber_critical",false))
	set(v): _sp("ScrubberSystem","_scrubber_critical",v)
var scrubber_units: Dictionary:
	get: return _gpd("ScrubberSystem","scrubber_units",{})
	set(v): _sp("ScrubberSystem","scrubber_units",v)
var active_planet_spec: Dictionary:
	get: return _gpd("PlanetSystem","active_planet_spec",{})
	set(v): _sp("PlanetSystem","active_planet_spec",v)
var planets_dialed: int:
	get: return int(_gp("PlanetSystem","planets_dialed",0))
	set(v): _sp("PlanetSystem","planets_dialed",v)
var gate_window_active: bool:
	get: return bool(_gp("PlanetSystem","gate_window_active",false))
	set(v): _sp("PlanetSystem","gate_window_active",v)
var gate_window_remaining: float:
	get: return float(_gp("PlanetSystem","gate_window_remaining",0.0))
	set(v): _sp("PlanetSystem","gate_window_remaining",v)
var gate_window_water_drain: float:
	get: return float(_gp("PlanetSystem","gate_window_water_drain",0.0))
	set(v): _sp("PlanetSystem","gate_window_water_drain",v)
var _water_drain_accum: float:
	get: return float(_gp("PlanetSystem","_water_drain_accum",0.0))
	set(v): _sp("PlanetSystem","_water_drain_accum",v)
var run_start_resources: Dictionary:
	get: return _gpd("PlanetSystem","run_start_resources",{})
	set(v): _sp("PlanetSystem","run_start_resources",v)
var ftl_drop_game_time: float:
	get: return float(_gp("PlanetSystem","_ftl_drop_game_time",-1.0))
	set(v): _sp("PlanetSystem","_ftl_drop_game_time",v)
var deployed_kinos: Array:
	get: return _gpa("KinoSystem","deployed_kinos",[])
	set(v): _sp("KinoSystem","deployed_kinos",v)
var kino_scout_done: bool:
	get: return bool(_gp("KinoSystem","kino_scout_done",false))
	set(v): _sp("KinoSystem","kino_scout_done",v)
var kino_plan_approved: bool:
	get: return bool(_gp("KinoSystem","kino_plan_approved",false))
	set(v): _sp("KinoSystem","kino_plan_approved",v)
var away_party_briefed: bool:
	get: return bool(_gp("KinoSystem","away_party_briefed",false))
	set(v): _sp("KinoSystem","away_party_briefed",v)
var kino_pan_x: float:
	get: return float(_gp("KinoSystem","kino_pan_x",0.0))
	set(v): _sp("KinoSystem","kino_pan_x",v)
var kino_pan_y: float:
	get: return float(_gp("KinoSystem","kino_pan_y",0.0))
	set(v): _sp("KinoSystem","kino_pan_y",v)
var kino_zoom: float:
	get: return float(_gp("KinoSystem","kino_zoom",1.0))
	set(v): _sp("KinoSystem","kino_zoom",v)
var kino_active_floor: int:
	get: return int(_gp("KinoSystem","kino_active_floor",-1))
	set(v): _sp("KinoSystem","kino_active_floor",v)
var kino_marker: Dictionary:
	get: return _gpd("KinoSystem","kino_marker",{})
	set(v): _sp("KinoSystem","kino_marker",v)
var compass_show_lime: bool:
	get: return bool(_gp("Settings","compass_show_lime",true))
	set(v): _sp("Settings","compass_show_lime",v)
var compass_show_kinos: bool:
	get: return bool(_gp("Settings","compass_show_kinos",true))
	set(v): _sp("Settings","compass_show_kinos",v)
var compass_show_companions: bool:
	get: return bool(_gp("Settings","compass_show_companions",true))
	set(v): _sp("Settings","compass_show_companions",v)
var compass_show_gate: bool:
	get: return bool(_gp("Settings","compass_show_gate",true))
	set(v): _sp("Settings","compass_show_gate",v)
var compass_show_pois: bool:
	get: return bool(_gp("Settings","compass_show_pois",true))
	set(v): _sp("Settings","compass_show_pois",v)

# --- Proxy helpers ---
func _autoload_node(n: String) -> Node:
	var t: SceneTree = Engine.get_main_loop() as SceneTree
	return t.root.get_node_or_null(n) if t != null and t.root != null else null
func _inv() -> Node:
	return _autoload_node("Inventory")
func _gp(s: String, p: String, d: Variant) -> Variant:
	var n: Node = _autoload_node(s)
	return n.get(p) if n != null and n.get(p) != null else d
func _sp(s: String, p: String, v: Variant) -> void:
	var n: Node = _autoload_node(s)
	if n != null:
		n.set(p, v)
func _gpd(s: String, p: String, d: Dictionary) -> Dictionary:
	var v: Variant = _gp(s, p, d)
	return v if v is Dictionary else d
func _gpa(s: String, p: String, d: Array) -> Array:
	var v: Variant = _gp(s, p, d)
	return v if v is Array else d
func _callv(s: String, m: String, a: Array = []) -> Variant:
	var n: Node = _autoload_node(s)
	return n.callv(m, a) if n != null and n.has_method(m) else null

# --- Lifecycle ---
func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "game_state", self)
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_signal("quest_step_changed"):
		if not ql.is_connected("quest_step_changed", _on_quest_log_step_changed):
			ql.connect("quest_step_changed", _on_quest_log_step_changed)
	_ensure_signal_bridges()

func _on_quest_log_step_changed(qid: String, _sid: String) -> void:
	if qid == E1_QUEST_ID:
		_pull_quest_step_from_log(_autoload_node("QuestLog"))

# Bridge subsystem signals to GameState's matching declarations so consumers
# that connect to GameState still see the events.  Must be idempotent because
# it is called from both _ready() and reset() (in -s test mode _ready is
# deferred, so reset() runs first).
func _ensure_signal_bridges() -> void:
	# PlanetSystem → gate_window_expired
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null and ps.has_signal("gate_window_expired"):
		if not ps.is_connected("gate_window_expired", _on_gate_window_expired):
			ps.connect("gate_window_expired", _on_gate_window_expired)
	# ScrubberSystem → scrubber_level_changed / scrubber_unit_changed
	var ss: Node = _autoload_node("ScrubberSystem")
	if ss != null:
		if ss.has_signal("scrubber_level_changed") and not ss.is_connected("scrubber_level_changed", _on_scrubber_level_changed):
			ss.connect("scrubber_level_changed", _on_scrubber_level_changed)
		if ss.has_signal("scrubber_unit_changed") and not ss.is_connected("scrubber_unit_changed", _on_scrubber_unit_changed):
			ss.connect("scrubber_unit_changed", _on_scrubber_unit_changed)
	# KinoSystem → deployed_kinos_changed
	var ks: Node = _autoload_node("KinoSystem")
	if ks != null and ks.has_signal("deployed_kinos_changed"):
		if not ks.is_connected("deployed_kinos_changed", _on_deployed_kinos_changed):
			ks.connect("deployed_kinos_changed", _on_deployed_kinos_changed)

func _on_gate_window_expired() -> void: gate_window_expired.emit()
func _on_scrubber_level_changed(lvl: float) -> void: scrubber_level_changed.emit(lvl)
func _on_scrubber_unit_changed(id: String) -> void: scrubber_unit_changed.emit(id)
func _on_deployed_kinos_changed() -> void: deployed_kinos_changed.emit()

func _process(delta: float) -> void:
	var r: Node = _autoload_node("SceneRouter")
	var h: bool = r != null and r.get("instant_mode") == true
	if gate_window_active and not h:
		_callv("PlanetSystem", "tick_gate_window", [delta])
	if scrubber_repaired and not h:
		_callv("ScrubberSystem", "tick_scrubber", [delta])

# --- Signal emit helpers (called by subsystems via has_method) ---
func objective_changed_emit(t: String) -> void: objective_changed.emit(t)
func quest_step_changed_emit(s: String) -> void: quest_step_changed.emit(s)
func health_changed_emit(v: float) -> void: health_changed.emit(v)
func oxygen_changed_emit(v: float) -> void: oxygen_changed.emit(v)
func episode_completed_emit() -> void: episode_completed.emit()
func planet_run_ended_emit() -> void: planet_run_ended.emit()
func dialogue_shown_emit(s: String, l: String) -> void: dialogue_shown.emit(s, l)
func _emit_resource_changed(t: String, c: int) -> void: resource_changed.emit(t, c)

# --- Health / Oxygen ---
func damage(a: float) -> void:
	health = clampf(health - a, 0.0, MAX_HEALTH)
	health_changed.emit(health)
func heal_full() -> void:
	health = MAX_HEALTH
	health_changed.emit(health)
func consume_oxygen(a: float) -> void:
	oxygen = clampf(oxygen - a, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)
	if oxygen < 25.0:
		damage(a * 0.5)
func restore_oxygen(a: float) -> void:
	oxygen = clampf(oxygen + a, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)

# --- Room / POI / Door ---
func discover_room(rid: String, dn: String = "") -> void:
	if not rooms_discovered.has(rid):
		rooms_discovered.append(rid)
		room_discovered.emit(rid)
		if dn != "":
			add_log("Discovered: " + dn)
func decipher_room(rid: String) -> void:
	if not rooms_deciphered.has(rid):
		rooms_deciphered.append(rid)
		room_deciphered.emit(rid)
func is_deciphered(rid: String) -> bool:
	return rooms_deciphered.has(rid)
func discover_poi(k: String, c: String, l: String, a: bool = false) -> void:
	if k != "" and not discovered_pois.has(k):
		discovered_pois[k] = {"category": c, "label": l}
		pois_discovered_changed.emit()
		if a:
			_announce_poi(l)
func is_poi_discovered(k: String) -> bool:
	return discovered_pois.has(k)
func discover_lime(k: String) -> void:
	discover_poi(k, AIR_LIME_RESOURCE, "Lime deposit")
func is_lime_discovered(k: String) -> bool:
	return is_poi_discovered(k)
func _announce_poi(l: String) -> void:
	var r: Node = _autoload_node("SceneRouter")
	if (r != null and r.get("instant_mode") == true) or Engine.get_main_loop() == null:
		return
	_poi_toast_queue.append(l)
	if _poi_toast_timer == null:
		_emit_next_poi_toast()
func _emit_next_poi_toast() -> void:
	if _poi_toast_queue.is_empty():
		_poi_toast_timer = null
		return
	add_log("Kino found: " + _poi_toast_queue.pop_front())
	var t: SceneTree = Engine.get_main_loop() as SceneTree
	if t == null:
		_poi_toast_timer = null
		return
	_poi_toast_timer = t.create_timer(_POI_TOAST_INTERVAL)
	_poi_toast_timer.timeout.connect(_emit_next_poi_toast)
static func door_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a <= b else "%s|%s" % [b, a]
func mark_door_traversed(a: String, b: String) -> void:
	if a == "" or b == "":
		return
	var k: String = door_key(a, b)
	if not doors_traversed.has(k):
		doors_traversed.append(k)
		door_traversed.emit(k)
func door_was_traversed(a: String, b: String) -> bool:
	return doors_traversed.has(door_key(a, b))
func set_power_percent(v: float) -> void:
	power_percent = v
	power_changed.emit(v)
func set_hull_percent(v: float) -> void:
	hull_percent = v
	hull_changed.emit(v)

# --- Kino facades ---
func acquire_kino() -> void:
	var inv: Node = _inv()
	if inv != null and not inv.call("has", "kino_remote"):
		inv.call("add_item", "kino_remote", 1)
	prologue_complete = true
	kino_changed.emit(true)
	add_log("Acquired the Kino Remote.")
	advance_air_quest()
func acquire_kino_orb() -> void: _callv("KinoSystem", "acquire_kino_orb")
func consume_kino_orb() -> bool: return bool(_callv("KinoSystem", "consume_kino_orb"))
func deploy_kino(s: String, p: Vector3) -> void: _callv("KinoSystem", "deploy_kino", [s, p])
func deployed_kinos_in_scene(s: String) -> Array: return _callv("KinoSystem", "deployed_kinos_in_scene", [s]) as Array
func complete_kino_scout() -> void: _callv("KinoSystem", "complete_kino_scout")

# --- Quest flow facades ---
func advance_air_quest() -> void:
	_callv("QuestFlowSystem", "advance_air_quest")
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("advance"):
		ql.call("advance", E1_QUEST_ID)
	_pull_quest_step_from_log(ql)
func _pull_quest_step_from_log(ql: Node) -> void:
	if ql == null:
		return
	var ns: String = ""
	if ql.has_method("active_step_id"):
		ns = String(ql.call("active_step_id", E1_QUEST_ID))
	if ns == "":
		return
	var nt: String = ""
	if ql.has_method("objective"):
		nt = String(ql.call("objective", E1_QUEST_ID))
	var sc: bool = ns != quest_step
	var tc: bool = nt != "" and nt != current_objective
	quest_step = ns
	if nt != "":
		current_objective = nt
	if tc:
		objective_changed.emit(current_objective)
	if sc:
		quest_step_changed.emit(ns)
func quest_step_label(s: String = "") -> String:
	var k: String = quest_step if s == "" else s
	var ql: Node = _autoload_node("QuestLog")
	return String(ql.call("label", k)) if ql != null and ql.has_method("label") else k
func quest_target(s: String = "") -> Dictionary:
	var ql: Node = _autoload_node("QuestLog")
	if ql == null:
		return {}
	if s == "":
		return ql.call("target", E1_QUEST_ID) if ql.has_method("target") else {}
	return ql.call("target_for_step", s) if ql.has_method("target_for_step") else {}
func set_current_room(rid: String) -> void:
	if rid != "" and rid != current_room_id:
		current_room_id = rid
		current_room_changed.emit(rid)
func set_objective(t: String) -> void:
	current_objective = t
	objective_changed.emit(t)
static func lime_objective_text(h: int, n: int) -> String:
	return ("Lime collected — %d/%d  ✓  head back to the gate" % [h, n]) if h >= n else ("Collect at least %d lime deposits — %d/%d" % [n, h, n])
func room_atmosphere(rid: String) -> Dictionary:
	var ps: Node = _autoload_node("PlanetSystem")
	return ps.call("room_atmosphere", rid) if ps != null and ps.has_method("room_atmosphere") else {"status": "NOMINAL", "composition": "N2/O2 NOMINAL", "breathable": true, "oxygen": int(round(oxygen)), "radiation": "LOW", "toxins": "NONE"}
func add_log(l: String) -> void:
	log_entries.append(l)
	log_added.emit(l)
func narrate(t: String) -> void: narrative_added.emit("", t)
func say(s: String, t: String) -> void: narrative_added.emit(s, t)
func clear_chat() -> void: chat_cleared.emit()

# --- Resource facades ---
func resource_count(t: String) -> int: return int(_callv("ResourceSystem", "resource_count", [t]))
func add_resource(t: String, a: int, s: String = "") -> bool: return bool(_callv("ResourceSystem", "add_resource", [t, a, s]))
func has_resource(t: String, a: int) -> bool: return bool(_callv("ResourceSystem", "has_resource", [t, a]))
func spend_resource(t: String, a: int, r: String = "") -> bool: return bool(_callv("ResourceSystem", "spend_resource", [t, a, r]))
func seed_default_resources() -> void: _callv("ResourceSystem", "seed_default_resources")
func tracked_resource_ids() -> Array: return _callv("ResourceSystem", "tracked_resource_ids") as Array
func resource_deficit(i: String) -> int: return int(_callv("ResourceSystem", "resource_deficit", [i]))
func resource_scarcity() -> Array: return _callv("ResourceSystem", "resource_scarcity") as Array
func build_resource_table(s: int) -> Dictionary: return _callv("ResourceSystem", "build_resource_table", [s]) as Dictionary
func resource_label(i: String) -> String: return String(_callv("ResourceSystem", "resource_label", [i]))

# --- Planet facades ---
func build_next_planet_spec(n: String = "", fb: String = "", fs: int = -1) -> Dictionary: return _callv("PlanetSystem", "build_next_planet_spec", [n, fb, fs]) as Dictionary
func build_air_lime_spec() -> Dictionary: return _callv("PlanetSystem", "build_air_lime_spec") as Dictionary
func planet_scan_profile(s: Dictionary = {}) -> Dictionary: return _callv("PlanetSystem", "planet_scan_profile", [s]) as Dictionary
func start_gate_window(d: float) -> bool: return bool(_callv("PlanetSystem", "start_gate_window", [d]))
func _tick_gate_window(d: float) -> void: _callv("PlanetSystem", "tick_gate_window", [d])
func _tick_atmosphere_oxygen_drain(d: float) -> bool:
	var r: float = PlanetGenerator.oxygen_drain_for(active_planet_spec, pressure_suits_found)
	if r <= 0.0:
		return false
	consume_oxygen(r * d)
	if oxygen <= 0.0:
		knock_out("asphyxiation")
		return true
	return false

# --- Scrubber facades ---
func _tick_scrubber(d: float) -> void: _callv("ScrubberSystem", "tick_scrubber", [d])
func repair_scrubber_with_lime() -> bool: return bool(_callv("ScrubberSystem", "repair_scrubber_with_lime"))
func top_up_scrubber() -> bool: return bool(_callv("ScrubberSystem", "top_up_scrubber"))
func scrubber_unit_state(i: String) -> Dictionary: return _callv("ScrubberSystem", "scrubber_unit_state", [i]) as Dictionary
func is_scrubber_unit_discovered(i: String) -> bool: return bool(_callv("ScrubberSystem", "is_scrubber_unit_discovered", [i]))
func is_scrubber_unit_open(i: String) -> bool: return bool(_callv("ScrubberSystem", "is_scrubber_unit_open", [i]))
func is_scrubber_unit_repaired(i: String) -> bool: return bool(_callv("ScrubberSystem", "is_scrubber_unit_repaired", [i]))
func discover_scrubber_unit(i: String, l: String = "CO2 Scrubber") -> bool: return bool(_callv("ScrubberSystem", "discover_scrubber_unit", [i, l]))
func set_scrubber_unit_open(i: String, w: bool) -> void: _callv("ScrubberSystem", "set_scrubber_unit_open", [i, w])
func repair_scrubber_unit(i: String) -> bool: return bool(_callv("ScrubberSystem", "repair_scrubber_unit", [i]))
func aux_scrubbers_repaired_count() -> int: return int(_callv("ScrubberSystem", "aux_scrubbers_repaired_count"))
func scrubber_green_bars() -> int: return int(_callv("ScrubberSystem", "scrubber_green_bars"))

# --- Quest flow story facades ---
func can_start_air_crisis() -> bool: return bool(_callv("QuestFlowSystem", "can_start_air_crisis"))
func start_air_crisis() -> void: _callv("QuestFlowSystem", "start_air_crisis")
func announce_air_crisis() -> void: _callv("QuestFlowSystem", "announce_air_crisis")
func mark_control_room_returned() -> void: _callv("QuestFlowSystem", "mark_control_room_returned")
func examine_door_panel() -> void: _callv("QuestFlowSystem", "examine_door_panel")
func find_small_fuse() -> void: _callv("QuestFlowSystem", "find_small_fuse")
func find_large_fuse() -> void: _callv("QuestFlowSystem", "find_large_fuse")
func find_bus_fuse() -> void: _callv("QuestFlowSystem", "find_bus_fuse")
func find_rations() -> void: _callv("QuestFlowSystem", "find_rations")
func diagnose_life_support() -> void: _callv("QuestFlowSystem", "diagnose_life_support")
func diagnose_scrubber() -> void: _callv("QuestFlowSystem", "diagnose_scrubber")
func complete_scrubber_scene() -> void: _callv("QuestFlowSystem", "complete_scrubber_scene")
func report_to_gate() -> void: _callv("QuestFlowSystem", "report_to_gate")
func trigger_ftl_drop() -> void: _callv("QuestFlowSystem", "trigger_ftl_drop")
func dial_lime_planet() -> void: _callv("QuestFlowSystem", "dial_lime_planet")
func is_gate_open() -> bool: return bool(_callv("QuestFlowSystem", "is_gate_open"))
func can_travel_to_lime_planet() -> bool: return bool(_callv("QuestFlowSystem", "can_travel_to_lime_planet"))
func return_from_lime_planet() -> void: _callv("QuestFlowSystem", "return_from_lime_planet")
func recall_after_window_close() -> void: _callv("QuestFlowSystem", "recall_after_window_close")
func knock_out(c: String = "generic") -> void: _callv("QuestFlowSystem", "knock_out", [c])
func _reconcile_run_resources_on_knockout() -> void: _callv("PlanetSystem", "reconcile_run_resources_on_knockout")
func run_target_resource() -> String: return String(_callv("PlanetSystem", "run_target_resource"))
func knockout_line(c: String = "") -> Dictionary: return _callv("QuestFlowSystem", "knockout_line", [c]) as Dictionary
func _load_knockout_data() -> Dictionary: return _callv("QuestFlowSystem", "_load_knockout_data") as Dictionary
func clear_infirmary_recovery() -> void: _callv("QuestFlowSystem", "clear_infirmary_recovery")
func check_episode_complete() -> void: _callv("QuestFlowSystem", "check_episode_complete")
func complete_episode_air() -> void: _callv("QuestFlowSystem", "complete_episode_air")
func mark_pressure_suits_found() -> void: _callv("QuestFlowSystem", "mark_pressure_suits_found")
func biome_flags() -> Dictionary:
	return {"pressure_suits_found": pressure_suits_found}

# --- Ship story facades (live HERE) ---
func mark_quarters_found(l: String = "Found Crew Quarters Alpha.") -> void:
	if not quarters_found:
		quarters_found = true
		add_log(l)
		advance_air_quest()
func mark_eli_quarters_found() -> void:
	if not eli_quarters_visited:
		eli_quarters_visited = true
		add_log("My quarters. Something's sitting on the desk — better take a look.")
		advance_air_quest()
func unlock_elevator() -> void:
	if not elevator_repaired:
		elevator_repaired = true
		add_log("Main power restored. The elevator north of the corridor is online.")
		advance_air_quest()
func seal_breach(b: String) -> void:
	if breaches_sealed.has(b):
		return
	breaches_sealed.append(b)
	if air_crisis_started and not scrubber_repaired:
		restore_oxygen(8.0)
		add_log("Exposed section locked down. Pressure is steadier, but CO2 is still climbing.")
	else:
		restore_oxygen(MAX_OXYGEN)
	add_log("Hull breach sealed: " + b)
	advance_air_quest()

# --- Save / Load ---
func has_save() -> bool:
	var sm: Node = _autoload_node("SaveManager")
	return sm != null and sm.has_method("has_save") and sm.call("has_save") == true

func _save_scalar_fields() -> Array[Array]:
	return [
		["health","f",MAX_HEALTH],["oxygen","f",MAX_OXYGEN],["quarters_found","b",false],["eli_quarters_visited","b",false],
		["elevator_repaired","b",false],["current_room_id","s",""],["objective","s",current_objective],
		["current_episode","s",EPISODE_AIR],["quest_step","s",QUEST_TALK_SCOTT],["episode_complete","b",false],["met_scott","b",false],
		["met_rush","b",false],["pressure_suits_found","b",false],["prologue_complete","b",false],["air_crisis_started","b",false],
		["control_room_returned","b",false],["blocked_door_beat_done","b",false],["door_panel_examined","b",false],["life_support_diagnosed","b",false],
		["ftl_drop_triggered","b",false],["ftl_drop_game_time","f",-1.0],["lime_planet_dialed","b",false],["reported_to_gate","b",false],
		["returned_from_lime_planet","b",false],["recovering_in_infirmary","b",false],["knockout_cause","s",""],["scrubber_diagnosed","b",false],
		["scrubber_repaired","b",false],["scrubber_level","f",0.0],["planets_dialed","i",0],["gate_window_active","b",false],
		["gate_window_remaining","f",0.0],["gate_window_water_drain","f",0.0],["kino_scout_done","b",false],["kino_plan_approved","b",false],
		["away_party_briefed","b",false],["kino_pan_x","f",0.0],["kino_pan_y","f",0.0],["kino_zoom","f",1.0],
		["kino_active_floor","i",-1],["compass_show_lime","b",true],["compass_show_kinos","b",true],["compass_show_companions","b",true],
		["compass_show_gate","b",true],["compass_show_pois","b",true],["ship_phase_override","f",-1.0],["planet_window_override","f",-1.0],
		["crew_count","i",6],["active_sections","i",3],
	]

func serialize() -> Dictionary:
	var d: Dictionary = {}
	for row in _save_scalar_fields():
		d[row[0]] = get(row[0])
	for k in ["rooms_discovered","rooms_deciphered","doors_traversed","breaches_sealed","log_entries"]:
		d[k] = (get(k) as Array).duplicate()
	for k in ["discovered_pois","scrubber_units","active_planet_spec","run_start_resources","kino_marker"]:
		d[k] = (get(k) as Dictionary).duplicate(true)
	var ka: Array = []
	for k in deployed_kinos:
		if k is Dictionary:
			ka.append((k as Dictionary).duplicate(true))
	d["deployed_kinos"] = ka
	for sys in ["QuestFlowSystem","ScrubberSystem","PlanetSystem","KinoSystem"]:
		var n: Node = _autoload_node(sys)
		if n != null and n.has_method("serialize"):
			d.merge(n.call("serialize"), true)
	return d

func _db(d: Dictionary, k: String, def: bool) -> bool:
	return d.get(k, def) == true
func _ds(d: Dictionary, k: String, def: String) -> String:
	var v: Variant = d.get(k, def)
	return v if v is String else def
func _df(d: Dictionary, k: String, def: float) -> float:
	return float(d.get(k, def))
func _di(d: Dictionary, k: String, def: int) -> int:
	return int(d.get(k, def))
func _dsa(d: Dictionary, k: String) -> Array[String]:
	var a: Array[String] = []
	for v in d.get(k, []):
		a.append(String(v))
	return a

func deserialize(data: Dictionary, _v: int) -> void:
	# Scalar fields via table-driven approach
	for row in _save_scalar_fields():
		var key: String = row[0]
		var typ: String = row[1]
		var def: Variant = row[2]
		match typ:
			"b": set(key, _db(data, key, def))
			"s": set(key, _ds(data, key, def))
			"f": set(key, _df(data, key, def))
			"i": set(key, _di(data, key, def))
	# Special handling for non-scalar fields
	var su: Variant = data.get("scrubber_units", {})
	scrubber_units = (su as Dictionary).duplicate(true) if su is Dictionary else {}
	var sp: Variant = data.get("active_planet_spec", {})
	active_planet_spec = (sp as Dictionary).duplicate(true) if sp is Dictionary else {}
	_water_drain_accum = 0.0
	run_start_resources = {}
	var srr: Variant = data.get("run_start_resources", {})
	if srr is Dictionary:
		for k in (srr as Dictionary).keys():
			run_start_resources[String(k)] = int((srr as Dictionary)[k])
	deployed_kinos.clear()
	var lk: Variant = data.get("deployed_kinos", [])
	if lk is Array:
		for k in lk:
			if k is Dictionary:
				deployed_kinos.append({"scene": _ds(k as Dictionary, "scene", ""), "x": _df(k as Dictionary, "x", 0.0), "y": _df(k as Dictionary, "y", 0.0), "z": _df(k as Dictionary, "z", 0.0)})
	var mr: Variant = data.get("kino_marker", {})
	kino_marker = mr if mr is Dictionary else {}
	# Legacy item migration
	var inv: Node = _inv()
	if inv != null:
		if data.get("kino_acquired", false) == true: inv.call("set_count", "kino_remote", 1)
		if data.get("small_fuse_found", false) == true: inv.call("set_count", "small_fuse", 1)
		if data.get("large_fuse_found", false) == true: inv.call("set_count", "large_fuse", 1)
		if data.has("kino_orbs"): inv.call("set_count", "kino_orb", int(data.get("kino_orbs", 0)))
		var lr: Variant = data.get("resources", {})
		if lr is Dictionary:
			for k in (lr as Dictionary).keys():
				inv.call("set_count", String(k), int((lr as Dictionary)[k]))
	# Core collections
	rooms_discovered = _dsa(data, "rooms_discovered")
	rooms_deciphered = _dsa(data, "rooms_deciphered")
	doors_traversed = _dsa(data, "doors_traversed")
	breaches_sealed = _dsa(data, "breaches_sealed")
	log_entries = _dsa(data, "log_entries")
	discovered_pois.clear()
	var sp2: Variant = data.get("discovered_pois", null)
	if sp2 is Dictionary:
		for k in (sp2 as Dictionary).keys():
			var rc: Variant = (sp2 as Dictionary)[k]
			if rc is Dictionary:
				discovered_pois[String(k)] = {"category": _ds(rc as Dictionary, "category", AIR_LIME_RESOURCE), "label": _ds(rc as Dictionary, "label", "Point of interest")}
	else:
		for lk2 in data.get("lime_discovered", []):
			discovered_pois[String(lk2)] = {"category": AIR_LIME_RESOURCE, "label": "Lime deposit"}
	advance_air_quest()
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(inv != null and inv.call("has", "kino_remote"))

# --- Reset ---
func reset() -> void:
	_ensure_signal_bridges()
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	quarters_found = false
	eli_quarters_visited = false
	elevator_repaired = false
	for c in [rooms_discovered, rooms_deciphered, doors_traversed, discovered_pois, breaches_sealed, log_entries, _poi_toast_queue]:
		c.clear()
	power_percent = STATUS_OFFLINE
	hull_percent = STATUS_OFFLINE
	current_room_id = ""
	_poi_toast_timer = null
	for sys in ["QuestFlowSystem","ScrubberSystem","PlanetSystem","KinoSystem"]:
		var n: Node = _autoload_node(sys)
		if n != null and n.has_method("reset"):
			n.call("reset")
	for k in ["compass_show_lime","compass_show_kinos","compass_show_companions","compass_show_gate","compass_show_pois"]:
		set(k, true)
	# Scene-staging batons
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
	kino_pilot_arrival_spawn = ""
	kino_autopilot = false
	ship_phase_override = -1.0
	planet_window_override = -1.0
	crew_count = 6
	active_sections = 3
	var inv: Node = _inv()
	if inv != null and inv.has_method("reset"):
		inv.call("reset")
	seed_default_resources()
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	kino_changed.emit(false)
	for sys2 in ["QuestLog","Achievements"]:
		var n2: Node = _autoload_node(sys2)
		if n2 != null and n2.has_method("reset"):
			n2.call("reset")
	advance_air_quest()