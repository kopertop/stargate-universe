extends Node

# E1 "Air" quest flow system. Owns the story flags and quest-advance methods
# that were previously inlined in GameState. GameState keeps thin proxy
# properties + facade methods so existing callers (tests, scenes, playthrough)
# keep working without changes.
#
# Save contract: registers as "quest_flow_system" via SaveManager.register_system.
# Serialize/deserialize own the story-flag fields only.

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
const KNOCKOUT_TARGET_BANK: int = 1
const _KNOCKOUT_LINES_PATH: String = "res://data/knockout_lines.json"

# Story flags.
var prologue_complete: bool = false
var air_crisis_started: bool = false
var control_room_returned: bool = false
var life_support_diagnosed: bool = false
var blocked_door_beat_done: bool = false
var door_panel_examined: bool = false
var ftl_drop_triggered: bool = false
var lime_planet_dialed: bool = false
var reported_to_gate: bool = false
var returned_from_lime_planet: bool = false
var recovering_in_infirmary: bool = false
var knockout_cause: String = ""
var pending_planet_return: bool = false
var met_scott: bool = false
var met_rush: bool = false
# @collection-ok: global suit availability flag, not a set of homogeneous items
var pressure_suits_found: bool = false
var current_episode: String = EPISODE_AIR
var quest_step: String = QUEST_TALK_SCOTT
var episode_complete: bool = false

# --- E2 "Light" power-restoration flags ---
var engineering_found: bool = false  # @collection-ok: E2 story flag — engineering discovery beat
var junction_located: bool = false  # @collection-ok: E2 story flag — junction located beat
var junction_repaired: bool = false  # @collection-ok: E2 story flag — junction repaired beat
var power_routed: bool = false  # @collection-ok: E2 story flag — power distribution beat

# --- E4 "Darkness" nebula crisis flags ---
var nebula_trap_detected: bool = false  # @collection-ok: E4 story flag — nebula trap beat
var power_conservation_started: bool = false  # @collection-ok: E4 story flag — conservation puzzle beat
var planet_resources_collected: bool = false  # @collection-ok: E4 story flag — planet mission beat
var nebula_escape_complete: bool = false  # @collection-ok: E4 story flag — escape beat


func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "quest_flow_system", self)


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _gs() -> Node:
	return _autoload_node("GameState")


# --- Quest advance -----------------------------------------------------------

func advance_air_quest() -> void:
	var ql: Node = _autoload_node("QuestLog")
	if ql == null:
		return
	if ql.has_method("advance"):
		ql.call("advance", E1_QUEST_ID)
	_pull_quest_step_from_log(ql)


func _pull_quest_step_from_log(ql: Node) -> void:
	if ql == null:
		return
	var new_step: String = ""
	if ql.has_method("active_step_id"):
		new_step = String(ql.call("active_step_id", E1_QUEST_ID))
	if new_step == "":
		return
	var new_text: String = ""
	if ql.has_method("objective"):
		new_text = String(ql.call("objective", E1_QUEST_ID))
	var step_changed: bool = new_step != quest_step
	var gs: Node = _gs()
	var current_objective: String = ""
	if gs != null:
		current_objective = String(gs.get("current_objective"))
	var text_changed: bool = new_text != "" and new_text != current_objective
	quest_step = new_step
	if new_text != "" and gs != null:
		gs.set("current_objective", new_text)
	if text_changed and gs != null and gs.has_signal("objective_changed"):
		gs.call("objective_changed_emit", new_text)
	if step_changed and gs != null and gs.has_signal("quest_step_changed"):
		gs.call("quest_step_changed_emit", new_step)


# --- Story flow methods ------------------------------------------------------

func can_start_air_crisis() -> bool:
	var gs: Node = _gs()
	if gs == null:
		return false
	var has_kino: bool = false
	var inv: Node = _autoload_node("Inventory")
	if inv != null:
		has_kino = inv.call("has", "kino_remote")
	return met_rush and bool(gs.get("eli_quarters_visited")) and has_kino and not air_crisis_started


func start_air_crisis() -> void:
	if air_crisis_started or episode_complete:
		return
	if not can_start_air_crisis():
		_add_log("Inspect the strange device on your desk first.")
		advance_air_quest()
		return
	prologue_complete = true
	air_crisis_started = true
	var gs: Node = _gs()
	if gs != null:
		gs.set("oxygen", minf(float(gs.get("oxygen")), 62.0))
		if gs.has_method("oxygen_changed_emit"):
			gs.call("oxygen_changed_emit", float(gs.get("oxygen")))
	_add_log("Destiny drops out of FTL. Alarms report rising CO2 in life support.")
	if not bool(gs.get("elevator_repaired")):
		_unlock_elevator()
	advance_air_quest()


func announce_air_crisis() -> void:
	if not air_crisis_started:
		return
	var gs: Node = _gs()
	if gs != null and gs.has_signal("dialogue_shown"):
		gs.call("dialogue_shown_emit", "Eli", "That's not a normal alarm. The air just got worse.")


func mark_control_room_returned() -> void:
	if control_room_returned:
		return
	control_room_returned = true
	advance_air_quest()


func examine_door_panel() -> void:
	if door_panel_examined:
		return
	door_panel_examined = true
	advance_air_quest()


func find_small_fuse() -> void:
	var inv: Node = _autoload_node("Inventory")
	if inv != null:
		inv.call("add_item", "small_fuse", 1, "a dock crate")
	_add_log("Found a Small Fuse — this should fit the door panel.")
	advance_air_quest()


func find_large_fuse() -> void:
	var inv: Node = _autoload_node("Inventory")
	if inv != null:
		inv.call("add_item", "large_fuse", 1, "a dock crate")
	_add_log("Found a Large Fuse. Too big for the door panel — pocket it anyway.")


func find_bus_fuse() -> void:
	var inv: Node = _autoload_node("Inventory")
	if inv != null:
		inv.call("add_item", "bus_fuse", 1, "a storage crate")
	_add_log("Found a Bus Fuse. One of the main-bus fuses Destiny's elevator circuit needs.")


func find_rations() -> void:
	var gs: Node = _gs()
	if gs != null and gs.has_method("add_resource"):
		gs.call("add_resource", "rations", 1, "a supply crate")


func diagnose_life_support() -> void:
	if not air_crisis_started:
		_add_log("Life support is nominal enough for now. Rush still wants priorities handled.")
		advance_air_quest()
		return
	if life_support_diagnosed:
		_add_log("Life support diagnostic already flagged the exposed section and scrubber failure.")
		return
	life_support_diagnosed = true
	_add_log("Life support diagnostic: exposed section must be locked off before repairs can hold.")
	advance_air_quest()


func diagnose_scrubber() -> void:
	if not air_crisis_started:
		_add_log("The scrubber bank is idle. No emergency repair queued yet.")
		advance_air_quest()
		return
	var ss: Node = _autoload_node("ScrubberSystem")
	if ss != null and bool(ss.get("scrubber_diagnosed")):
		_add_log("CO2 scrubber diagnosis confirmed: lime is required for the cartridge mix.")
		return
	if ss != null:
		ss.set("scrubber_diagnosed", true)
	_add_log("CO2 scrubber is cracked. It needs lime before the cartridge bed can reset.")
	advance_air_quest()


func complete_scrubber_scene() -> void:
	var ss: Node = _autoload_node("ScrubberSystem")
	if ss != null and bool(ss.get("scrubber_diagnosed")):
		return
	if ss != null:
		ss.set("scrubber_diagnosed", true)
	ftl_drop_triggered = true
	var gc: Node = _autoload_node("GameClock")
	var ftl_time: float = float(gc.get("elapsed_seconds")) if gc != null else 0.0
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		ps.set("_ftl_drop_game_time", ftl_time)
	lime_planet_dialed = true
	_add_log("Rush: the scrubber's beyond salvage — it needs lime. Destiny lurches out of FTL; the gate dials a lime-bearing world on its own.")
	advance_air_quest()


func report_to_gate() -> void:
	if reported_to_gate:
		return
	reported_to_gate = true
	advance_air_quest()


func trigger_ftl_drop() -> void:
	if not ftl_drop_triggered_check():
		_add_log("FTL controls stay locked until the scrubber fault is identified.")
		advance_air_quest()
		return
	if ftl_drop_triggered:
		_add_log("Destiny is already out of FTL. Gate systems are available.")
		return
	_do_ftl_drop()
	_add_log("FTL drop triggered. Destiny falls into normal space near a viable gate address.")
	advance_air_quest()


func ftl_drop_triggered_check() -> bool:
	var ss: Node = _autoload_node("ScrubberSystem")
	return ss != null and bool(ss.get("scrubber_diagnosed"))


func _do_ftl_drop() -> void:
	ftl_drop_triggered = true
	var gc: Node = _autoload_node("GameClock")
	var ftl_time: float = float(gc.get("elapsed_seconds")) if gc != null else 0.0
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		ps.set("_ftl_drop_game_time", ftl_time)


func dial_lime_planet() -> void:
	if not ftl_drop_triggered:
		_add_log("The gate will not dial until Destiny drops from FTL.")
		advance_air_quest()
		return
	if lime_planet_dialed:
		_add_log("Lime planet address is already active.")
		return
	lime_planet_dialed = true
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null and ps.has_method("build_air_lime_spec"):
		if (ps.get("active_planet_spec") as Dictionary).is_empty():
			ps.call("build_air_lime_spec")
	_add_log("Gate Control locks a viable address: lime deposits detected near the landing zone.")
	advance_air_quest()


func is_gate_open() -> bool:
	if episode_complete:
		var ps: Node = _autoload_node("PlanetSystem")
		return ps != null and bool(ps.get("gate_window_active"))
	var ss: Node = _autoload_node("ScrubberSystem")
	return lime_planet_dialed and not (ss != null and bool(ss.get("scrubber_repaired")))


func can_travel_to_lime_planet() -> bool:
	if episode_complete:
		return is_gate_open()
	return is_gate_open() and (quest_step == QUEST_MINE_LIME \
			or quest_step == QUEST_RETURN_DESTINY \
			or quest_step == QUEST_REPAIR_SCRUBBER)


func return_from_lime_planet() -> void:
	if returned_from_lime_planet:
		return
	returned_from_lime_planet = true
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		ps.set("gate_window_active", false)
		ps.set("run_start_resources", {})
	_add_log("Returned to Destiny with lime from the planet.")
	advance_air_quest()


func recall_after_window_close() -> void:
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		ps.set("gate_window_active", false)
		ps.set("gate_window_remaining", 0.0)
		ps.set("gate_window_water_drain", 0.0)
		ps.set("_water_drain_accum", 0.0)
	lime_planet_dialed = false
	pending_planet_return = true
	if not returned_from_lime_planet:
		returned_from_lime_planet = true
		if ps != null:
			ps.set("run_start_resources", {})
		_add_log("Destiny jumped to FTL — the away team scrambled back through the gate just in time.")
		advance_air_quest()
	var gs: Node = _gs()
	if gs != null and gs.has_signal("planet_run_ended"):
		gs.call("planet_run_ended_emit")
	var router: Node = _autoload_node("SceneRouter")
	var headless: bool = router == null or router.get("instant_mode") == true
	if headless:
		return
	router.call("change_to", "res://scenes/gate_room.tscn", "FromPlanet")


func knock_out(cause: String = "generic") -> void:
	var tag: String = cause if cause != "" else "generic"
	var gs: Node = _gs()
	# Reconcile run resources before clearing.
	if gs != null and gs.has_method("_reconcile_run_resources_on_knockout"):
		gs.call("_reconcile_run_resources_on_knockout")
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		ps.set("gate_window_active", false)
		ps.set("gate_window_remaining", 0.0)
		ps.set("run_start_resources", {})
	if gs != null:
		gs.set("health", float(gs.get("MAX_HEALTH")))
		gs.set("oxygen", float(gs.get("MAX_OXYGEN")))
		if gs.has_method("health_changed_emit"):
			gs.call("health_changed_emit", float(gs.get("health")))
		if gs.has_method("oxygen_changed_emit"):
			gs.call("oxygen_changed_emit", float(gs.get("oxygen")))
	recovering_in_infirmary = true
	knockout_cause = tag
	_add_log("Eli goes down. Everything fades to black…")
	_route_to_infirmary()


func _route_to_infirmary() -> void:
	var gs: Node = _gs()
	if gs == null:
		return
	var router: Node = _autoload_node("SceneRouter")
	var headless: bool = router == null or router.get("instant_mode") == true
	gs.set("next_room_id", "infirmary")
	if headless:
		if gs.has_method("set_current_room"):
			gs.call("set_current_room", "infirmary")
		return
	router.call("change_to", "res://scenes/room.tscn", "")


func knockout_line(cause: String = "") -> Dictionary:
	var tag: String = cause if cause != "" else knockout_cause
	if tag == "":
		tag = "generic"
	var data: Dictionary = _load_knockout_data()
	var speaker: String = String(data.get("speaker", "TJ"))
	var pools: Variant = data.get("pools", {})
	var pool: Array = []
	if pools is Dictionary:
		var picked: Variant = (pools as Dictionary).get(tag, null)
		if picked is Array and not (picked as Array).is_empty():
			pool = picked as Array
		else:
			var fallback: Variant = (pools as Dictionary).get("generic", null)
			if fallback is Array:
				pool = fallback as Array
	var line: String = "You're awake. You took a knock out there — you'll be fine."
	if not pool.is_empty():
		line = String(pool[randi() % pool.size()])
	return {"speaker": speaker, "line": line}


func _load_knockout_data() -> Dictionary:
	if not FileAccess.file_exists(_KNOCKOUT_LINES_PATH):
		return {}
	var f: FileAccess = FileAccess.open(_KNOCKOUT_LINES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func clear_infirmary_recovery() -> void:
	recovering_in_infirmary = false
	knockout_cause = ""


func check_episode_complete() -> void:
	var ss: Node = _autoload_node("ScrubberSystem")
	if ss != null and bool(ss.get("scrubber_repaired")):
		complete_episode_air()


func complete_episode_air() -> void:
	if episode_complete:
		return
	episode_complete = true
	_add_log("Episode 1 complete: Destiny can breathe again.")
	var gs: Node = _gs()
	if gs != null and gs.has_signal("episode_completed"):
		gs.call("episode_completed_emit")
	advance_air_quest()
	if _autoload_node("QuestLog") == null:
		var changed: bool = quest_step != QUEST_COMPLETE
		quest_step = QUEST_COMPLETE
		if gs != null:
			gs.set("current_objective", "Episode 1: Air — Complete")
			if gs.has_signal("objective_changed"):
				gs.call("objective_changed_emit", "Episode 1: Air — Complete")
			if changed and gs.has_signal("quest_step_changed"):
				gs.call("quest_step_changed_emit", QUEST_COMPLETE)


func mark_pressure_suits_found() -> void:
	if pressure_suits_found:
		return
	pressure_suits_found = true
	_add_log("Recovered a cache of pressure suits — no-atmosphere worlds are survivable now.")

# --- E2 "Light" power-restoration story methods ---

func find_engineering() -> void:
	if engineering_found:
		return
	engineering_found = true
	_add_log("Engineering Bay located. The main conduit junction is here.")
	_advance_e2_quest()

func mark_engineering_found() -> void:
	find_engineering()

func locate_junction() -> void:
	if junction_located:
		return
	junction_located = true
	_add_log("Power conduit junction identified. It's damaged but repairable.")
	_advance_e2_quest()

func mark_junction_located() -> void:
	locate_junction()

func repair_junction() -> void:
	if junction_repaired:
		return
	junction_repaired = true
	# Restore the generator to full output via PowerGrid.
	var pg: Node = _autoload_node("PowerGrid")
	if pg != null and pg.has_method("repair_generator"):
		pg.call("repair_generator")
	_add_log("Conduit junction repaired. Generator output restored.")
	_advance_e2_quest()

func mark_junction_repaired() -> void:
	repair_junction()

func route_power() -> void:
	if power_routed:
		return
	power_routed = true
	# Clear damaged sections on critical rooms so power flows.
	var pg: Node = _autoload_node("PowerGrid")
	if pg != null:
		if pg.has_method("repair_generator"):
			pg.call("repair_generator")
		for room_id in ["gate_room", "control_interface_room"]:
			if pg.has_method("set_room_override"):
				pg.call("set_room_override", room_id, -1)
			if pg.has_method("set_section_repaired"):
				pg.call("set_section_repaired", room_id)
	_add_log("Power routed to critical systems. Gate Room and Control Interface Room are online.")
	_advance_e2_quest()

func mark_power_routed() -> void:
	route_power()

# --- E4 "Darkness" nebula crisis story methods ---

func detect_nebula_trap() -> void:
	if nebula_trap_detected:
		return
	nebula_trap_detected = true
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null and ns.has_method("start_crisis"):
		ns.call("start_crisis")
	_add_log("Destiny is trapped in a nebula. Power is draining — get to the Control Interface Room.")
	_advance_e4_quest()

func mark_nebula_trap_detected() -> void:
	detect_nebula_trap()

func begin_conservation() -> void:
	if power_conservation_started:
		return
	power_conservation_started = true
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null and ns.has_method("begin_conservation"):
		ns.call("begin_conservation")
	_add_log("Conservation protocols active. Choose which systems to shut down.")
	_advance_e4_quest()

func mark_power_conservation_started() -> void:
	begin_conservation()

func start_low_power_mission() -> void:
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null and ns.has_method("begin_planet_mission"):
		ns.call("begin_planet_mission")
	_add_log("Away team deployed in low-power mode. Limited Kino. No sprint. Find resources.")
	_advance_e4_quest()

func collect_planet_resources(amount: int = 1) -> void:
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null and ns.has_method("collect_resource"):
		var ready: bool = ns.call("collect_resource", amount)
		if ready and not planet_resources_collected:
			planet_resources_collected = true
			_add_log("Enough resources gathered. Return to Destiny and escape the nebula.")
			_advance_e4_quest()

func mark_planet_resources_collected() -> void:
	if planet_resources_collected:
		return
	planet_resources_collected = true
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null and ns.has_method("begin_planet_mission"):
		ns.call("begin_planet_mission")
		if ns.has_method("collect_resource"):
			ns.call("collect_resource", 99)  # ensure escape ready
	_add_log("Enough resources gathered. Return to Destiny and escape the nebula.")
	_advance_e4_quest()

func escape_nebula() -> void:
	if nebula_escape_complete:
		return
	nebula_escape_complete = true
	var ns: Node = _autoload_node("NebulaSystem")
	if ns != null:
		if ns.has_method("begin_escape"):
			ns.call("begin_escape")
		if ns.has_method("complete_escape"):
			ns.call("complete_escape")
	_add_log("Engines jump-started. Destiny breaks free of the nebula.")
	_advance_e4_quest()

func mark_nebula_escape_complete() -> void:
	escape_nebula()

func _advance_e4_quest() -> void:
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("advance"):
		ql.call("advance", "e4_darkness")

func _advance_e2_quest() -> void:
	var ql: Node = _autoload_node("QuestLog")
	if ql != null and ql.has_method("advance"):
		ql.call("advance", "e2_explore")


func _unlock_elevator() -> void:
	var gs: Node = _gs()
	if gs == null:
		return
	if bool(gs.get("elevator_repaired")):
		return
	gs.set("elevator_repaired", true)
	_add_log("Main power restored. The elevator north of the corridor is online.")
	advance_air_quest()


func _add_log(line: String) -> void:
	var gs: Node = _gs()
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", line)


# --- Save / Load --------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"current_episode": current_episode,
		"quest_step": quest_step,
		"prologue_complete": prologue_complete,
		"air_crisis_started": air_crisis_started,
		"control_room_returned": control_room_returned,
		"blocked_door_beat_done": blocked_door_beat_done,
		"door_panel_examined": door_panel_examined,
		"life_support_diagnosed": life_support_diagnosed,
		"ftl_drop_triggered": ftl_drop_triggered,
		"lime_planet_dialed": lime_planet_dialed,
		"reported_to_gate": reported_to_gate,
		"returned_from_lime_planet": returned_from_lime_planet,
		"recovering_in_infirmary": recovering_in_infirmary,
		"knockout_cause": knockout_cause,
		"pending_planet_return": pending_planet_return,
		"met_scott": met_scott,
		"met_rush": met_rush,
		"pressure_suits_found": pressure_suits_found,
		"episode_complete": episode_complete,
		"engineering_found": engineering_found,
		"junction_located": junction_located,
		"junction_repaired": junction_repaired,
		"power_routed": power_routed,
		"nebula_trap_detected": nebula_trap_detected,
		"power_conservation_started": power_conservation_started,
		"planet_resources_collected": planet_resources_collected,
		"nebula_escape_complete": nebula_escape_complete,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	current_episode = String(data.get("current_episode", EPISODE_AIR))
	quest_step = String(data.get("quest_step", QUEST_TALK_SCOTT))
	prologue_complete = data.get("prologue_complete", false) == true
	air_crisis_started = data.get("air_crisis_started", false) == true
	control_room_returned = data.get("control_room_returned", false) == true
	blocked_door_beat_done = data.get("blocked_door_beat_done", false) == true
	door_panel_examined = data.get("door_panel_examined", false) == true
	life_support_diagnosed = data.get("life_support_diagnosed", false) == true
	ftl_drop_triggered = data.get("ftl_drop_triggered", false) == true
	lime_planet_dialed = data.get("lime_planet_dialed", false) == true
	reported_to_gate = data.get("reported_to_gate", false) == true
	returned_from_lime_planet = data.get("returned_from_lime_planet", false) == true
	recovering_in_infirmary = data.get("recovering_in_infirmary", false) == true
	knockout_cause = String(data.get("knockout_cause", ""))
	pending_planet_return = data.get("pending_planet_return", false) == true
	met_scott = data.get("met_scott", false) == true
	met_rush = data.get("met_rush", false) == true
	pressure_suits_found = data.get("pressure_suits_found", false) == true
	episode_complete = data.get("episode_complete", false) == true
	engineering_found = data.get("engineering_found", false) == true
	junction_located = data.get("junction_located", false) == true
	junction_repaired = data.get("junction_repaired", false) == true
	power_routed = data.get("power_routed", false) == true
	nebula_trap_detected = data.get("nebula_trap_detected", false) == true
	power_conservation_started = data.get("power_conservation_started", false) == true
	planet_resources_collected = data.get("planet_resources_collected", false) == true
	nebula_escape_complete = data.get("nebula_escape_complete", false) == true


func reset() -> void:
	current_episode = EPISODE_AIR
	quest_step = QUEST_TALK_SCOTT
	prologue_complete = false
	air_crisis_started = false
	control_room_returned = false
	blocked_door_beat_done = false
	door_panel_examined = false
	life_support_diagnosed = false
	ftl_drop_triggered = false
	lime_planet_dialed = false
	reported_to_gate = false
	returned_from_lime_planet = false
	recovering_in_infirmary = false
	knockout_cause = ""
	pending_planet_return = false
	met_scott = false
	met_rush = false
	pressure_suits_found = false
	episode_complete = false
	engineering_found = false
	junction_located = false
	junction_repaired = false
	power_routed = false
	nebula_trap_detected = false
	power_conservation_started = false
	planet_resources_collected = false
	nebula_escape_complete = false