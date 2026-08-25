extends Node

# NebulaSystem — E4 "Darkness" nebula trap + power conservation crisis.
#
# Destiny is trapped inside a nebula that drains power. The crew must decide
# which systems to keep online (conservation puzzle) while a planet mission
# runs in low-power mode (limited Kino, no sprint).
#
# Multi-stage crisis:
#   1. NEBULA_TRAP — Destiny drops out of FTL inside a nebula. Power drains
#      over time. The player must reach the Control Interface Room.
#   2. CONSERVATION — the player chooses which ship systems to power down to
#      stretch remaining reserves. Each system has a drain rate and a
#      consequence if shut off. The puzzle: keep enough systems to survive
#      while power lasts long enough to find the exit.
#   3. PLANET_MISSION — a planet with resources is detected. The away team
#      deploys in low-power mode: limited Kino count (1 instead of 3), no
#      sprint. They must collect enough resources to jump-start the engines.
#   4. ESCAPE — with resources secured, the player reroutes power to engines
#      and escapes the nebula. The crisis ends.
#
# Integration:
#   - PowerGrid: set_generator_output drains over time; conservation choices
#     shed load by powering down specific rooms.
#   - ShipDamage: nebula radiation causes slow hull damage during the trap.
#   - TimerSystem: per-stage countdown timers for power drain.
#   - KinoSystem: limited Kino deployment during planet mission.
#   - GameState: publishes nebula stage + stats for HUD.
#   - SaveManager: serialize/deserialize nebula state.
#
# Save contract: current stage, stages completed, conservation choices,
# power reserve, planet mission progress, escape status.

signal stage_started(stage_id: String)
signal stage_completed(stage_id: String)
signal all_stages_completed()
signal power_drained(remaining: float)
signal system_toggled(system_id: String, online: bool)
signal planet_mission_progress(resources: int, required: int)
signal escape_triggered()
signal nebula_failed(reason: String)

enum Stage { NONE, NEBULA_TRAP, CONSERVATION, PLANET_MISSION, ESCAPE, COMPLETE }
enum Outcome { IN_PROGRESS, ESCAPED, FAILED }

# Ship systems that can be toggled during conservation.
# Each has: id, label, drain_per_sec, critical (cannot be shut off).
const SYSTEMS: Dictionary = {
	"life_support": {"label": "Life Support", "drain": 0.8, "critical": true},
	"shields": {"label": "Shields", "drain": 1.2, "critical": false},
	"engines": {"label": "Engines", "drain": 1.0, "critical": false},
	"weapons": {"label": "Weapons", "drain": 0.6, "critical": false},
	"sensors": {"label": "Sensors", "drain": 0.4, "critical": false},
	"lights": {"label": "Lights", "drain": 0.3, "critical": false},
}

const INITIAL_POWER: float = 60.0
const POWER_FAIL_THRESHOLD: float = 5.0
const NEBULA_HULL_DAMAGE_PER_TICK: float = 0.5
const NEBULA_TICK_INTERVAL: float = 5.0
const PLANET_RESOURCE_REQUIRED: int = 3
const LOW_POWER_KINO_MAX: int = 1

# ── State ────────────────────────────────────────────────────────────────────

var _current_stage: int = Stage.NONE
var _completed_stages: Array[int] = []
var _outcome: int = Outcome.IN_PROGRESS
var _power_reserve: float = INITIAL_POWER
var _system_states: Dictionary = {}  # system_id → bool (online)
var _nebula_tick_accumulator: float = 0.0
var _planet_resources_collected: int = 0
var _kino_limit_override: int = -1
var _sprint_disabled: bool = false
var _escape_ready: bool = false
var _instant_mode: bool = false
var _loaded: bool = false


# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_init_system_states()
	_register_with_save_manager()


func _init_system_states() -> void:
	_system_states.clear()
	for sid in SYSTEMS.keys():
		_system_states[String(sid)] = true


func _process(delta: float) -> void:
	if _instant_mode:
		return
	if _current_stage == Stage.NONE or _current_stage == Stage.COMPLETE:
		return
	# Nebula power drain happens during NEBULA_TRAP and CONSERVATION.
	if _current_stage == Stage.NEBULA_TRAP or _current_stage == Stage.CONSERVATION:
		_nebula_tick_accumulator += delta
		if _nebula_tick_accumulator >= NEBULA_TICK_INTERVAL:
			_nebula_tick_accumulator = 0.0
			_tick_power_drain()
	# Planet mission: no drain but hull radiation continues.
	if _current_stage == Stage.PLANET_MISSION:
		_nebula_tick_accumulator += delta
		if _nebula_tick_accumulator >= NEBULA_TICK_INTERVAL:
			_nebula_tick_accumulator = 0.0
			_tick_hull_radiation()


# ── Public API ───────────────────────────────────────────────────────────────

func set_instant_mode(enabled: bool) -> void:
	_instant_mode = enabled


func get_current_stage() -> int:
	return _current_stage


func get_stage_name(stage: int = _current_stage) -> String:
	match stage:
		Stage.NONE:
			return "none"
		Stage.NEBULA_TRAP:
			return "nebula_trap"
		Stage.CONSERVATION:
			return "conservation"
		Stage.PLANET_MISSION:
			return "planet_mission"
		Stage.ESCAPE:
			return "escape"
		Stage.COMPLETE:
			return "complete"
		_:
			return "unknown"


func get_outcome() -> int:
	return _outcome


func get_power_reserve() -> float:
	return _power_reserve


func get_power_reserve_percent() -> float:
	return (_power_reserve / INITIAL_POWER) * 100.0 if INITIAL_POWER > 0.0 else 0.0


func is_system_online(system_id: String) -> bool:
	if not _system_states.has(system_id):
		return false
	return bool(_system_states[system_id])


func is_system_critical(system_id: String) -> bool:
	if not SYSTEMS.has(system_id):
		return false
	return bool(SYSTEMS[system_id].get("critical", false))


func get_system_label(system_id: String) -> String:
	if not SYSTEMS.has(system_id):
		return system_id
	return String(SYSTEMS[system_id].get("label", system_id))


func get_system_drain(system_id: String) -> float:
	if not SYSTEMS.has(system_id):
		return 0.0
	return float(SYSTEMS[system_id].get("drain", 0.0))


func get_all_system_ids() -> Array[String]:
	var out: Array[String] = []
	for sid in SYSTEMS.keys():
		out.append(String(sid))
	return out


func get_online_systems() -> Array[String]:
	var out: Array[String] = []
	for sid in _system_states.keys():
		if bool(_system_states[sid]):
			out.append(String(sid))
	return out


func get_total_drain_per_sec() -> float:
	var total: float = 0.0
	for sid in _system_states.keys():
		if bool(_system_states[sid]):
			total += get_system_drain(String(sid))
	return total


# Start the E4 Darkness crisis. Sets stage to NEBULA_TRAP.
func start_crisis() -> void:
	if _current_stage != Stage.NONE:
		return
	_current_stage = Stage.NEBULA_TRAP
	_power_reserve = INITIAL_POWER
	_outcome = Outcome.IN_PROGRESS
	_escape_ready = false
	_planet_resources_collected = 0
	_init_system_states()
	# Apply low-power Kino limit for the planet mission phase.
	_kino_limit_override = LOW_POWER_KINO_MAX
	_sprint_disabled = false
	stage_started.emit("nebula_trap")
	_publish_to_game_state()


# Toggle a ship system on/off during conservation. Returns true if the
# toggle succeeded. Critical systems cannot be shut off.
func toggle_system(system_id: String) -> bool:
	if not _system_states.has(system_id):
		return false
	if _current_stage != Stage.CONSERVATION and _current_stage != Stage.NEBULA_TRAP:
		return false
	var currently_online: bool = bool(_system_states[system_id])
	if currently_online and is_system_critical(system_id):
		return false  # cannot shut off critical systems
	_system_states[system_id] = not currently_online
	var online: bool = bool(_system_states[system_id])
	system_toggled.emit(system_id, online)
	# Update PowerGrid to reflect load changes.
	_apply_to_power_grid()
	_publish_to_game_state()
	return true


# Force a system state (for scripted events or tests).
func set_system_online(system_id: String, online: bool) -> void:
	if not _system_states.has(system_id):
		return
	if not online and is_system_critical(system_id):
		return
	_system_states[system_id] = online
	system_toggled.emit(system_id, online)
	_apply_to_power_grid()
	_publish_to_game_state()


# Advance from NEBULA_TRAP to CONSERVATION.
func begin_conservation() -> void:
	if _current_stage != Stage.NEBULA_TRAP:
		return
	_completed_stages.append(Stage.NEBULA_TRAP)
	stage_completed.emit("nebula_trap")
	_current_stage = Stage.CONSERVATION
	stage_started.emit("conservation")
	_publish_to_game_state()


# Advance from CONSERVATION to PLANET_MISSION.
func begin_planet_mission() -> void:
	if _current_stage != Stage.CONSERVATION:
		return
	_completed_stages.append(Stage.CONSERVATION)
	stage_completed.emit("conservation")
	_current_stage = Stage.PLANET_MISSION
	# Disable sprint for low-power planet mission.
	_sprint_disabled = true
	_planet_resources_collected = 0
	stage_started.emit("planet_mission")
	planet_mission_progress.emit(0, PLANET_RESOURCE_REQUIRED)
	_publish_to_game_state()


# Collect resources during the planet mission. Returns true when enough
# resources have been gathered to attempt escape.
func collect_resource(amount: int = 1) -> bool:
	if _current_stage != Stage.PLANET_MISSION:
		return false
	_planet_resources_collected += amount
	planet_mission_progress.emit(_planet_resources_collected, PLANET_RESOURCE_REQUIRED)
	if _planet_resources_collected >= PLANET_RESOURCE_REQUIRED:
		_escape_ready = true
	_publish_to_game_state()
	return _escape_ready


func get_planet_resources() -> int:
	return _planet_resources_collected


func get_planet_resources_required() -> int:
	return PLANET_RESOURCE_REQUIRED


func is_escape_ready() -> bool:
	return _escape_ready


func get_kino_limit() -> int:
	return _kino_limit_override if _kino_limit_override > 0 else 3


func is_sprint_disabled() -> bool:
	return _sprint_disabled


# Begin the escape sequence. Requires enough planet resources.
func begin_escape() -> void:
	if _current_stage != Stage.PLANET_MISSION:
		return
	if not _escape_ready:
		nebula_failed.emit("not_enough_resources")
		return
	_completed_stages.append(Stage.PLANET_MISSION)
	stage_completed.emit("planet_mission")
	_current_stage = Stage.ESCAPE
	# Restore full system power for the escape.
	_power_reserve = INITIAL_POWER
	_init_system_states()
	_sprint_disabled = false
	stage_started.emit("escape")
	escape_triggered.emit()
	_publish_to_game_state()


# Complete the escape — ends the crisis.
func complete_escape() -> void:
	if _current_stage != Stage.ESCAPE:
		return
	_completed_stages.append(Stage.ESCAPE)
	stage_completed.emit("escape")
	_current_stage = Stage.COMPLETE
	_outcome = Outcome.ESCAPED
	_kino_limit_override = -1
	_sprint_disabled = false
	stage_started.emit("complete")
	all_stages_completed.emit()
	_publish_to_game_state()
	# Restore PowerGrid to full.
	var pg: Node = _autoload_node("PowerGrid")
	if pg != null and pg.has_method("repair_generator"):
		pg.call("repair_generator")


func is_complete() -> bool:
	return _current_stage == Stage.COMPLETE


func get_outcome_name() -> String:
	match _outcome:
		Outcome.IN_PROGRESS:
			return "in_progress"
		Outcome.ESCAPED:
			return "escaped"
		Outcome.FAILED:
			return "failed"
		_:
			return "unknown"


# Fail the crisis (e.g. power ran out completely).
func fail_crisis(reason: String = "power_depleted") -> void:
	_outcome = Outcome.FAILED
	nebula_failed.emit(reason)
	_publish_to_game_state()


# ── Internal ───────────────────────────────────────────────────────────────

func _tick_power_drain() -> void:
	var drain: float = get_total_drain_per_sec() * NEBULA_TICK_INTERVAL
	_power_reserve = maxf(_power_reserve - drain, 0.0)
	power_drained.emit(_power_reserve)
	# Apply to PowerGrid so room states degrade.
	_apply_to_power_grid()
	# Hull radiation damage.
	_tick_hull_radiation()
	if _power_reserve <= POWER_FAIL_THRESHOLD:
		fail_crisis("power_depleted")
	_publish_to_game_state()


func _tick_hull_radiation() -> void:
	var sd: Node = _autoload_node("ShipDamage")
	if sd != null and sd.has_method("apply_damage"):
		sd.call("apply_damage", "nebula_radiation", NEBULA_HULL_DAMAGE_PER_TICK)


func _apply_to_power_grid() -> void:
	var pg: Node = _autoload_node("PowerGrid")
	if pg == null:
		return
	# Map nebula power reserve to PowerGrid generator output.
	var output: float = (_power_reserve / INITIAL_POWER) * float(pg.call("get_total_capacity"))
	if pg.has_method("set_generator_output"):
		pg.call("set_generator_output", output)


func _publish_to_game_state() -> void:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return
	# Publish nebula stats to GameState for HUD consumption.
	if gs.has_method("set_power_percent"):
		gs.call("set_power_percent", get_power_reserve_percent())


# ── Save / Load (ISaveableSystem) ─────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "nebula_system", self)


func serialize() -> Dictionary:
	return {
		"current_stage": _current_stage,
		"completed_stages": _completed_stages.duplicate(),
		"outcome": _outcome,
		"power_reserve": _power_reserve,
		"system_states": _system_states.duplicate(),
		"nebula_planet_resources": _planet_resources_collected,
		"kino_limit_override": _kino_limit_override,
		"sprint_disabled": _sprint_disabled,
		"escape_ready": _escape_ready,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_current_stage = int(data.get("current_stage", Stage.NONE))
	_completed_stages.clear()
	var saved_stages: Variant = data.get("completed_stages", [])
	if saved_stages is Array:
		for s in saved_stages:
			_completed_stages.append(int(s))
	_outcome = int(data.get("outcome", Outcome.IN_PROGRESS))
	_power_reserve = float(data.get("power_reserve", INITIAL_POWER))
	_system_states.clear()
	var saved_systems: Variant = data.get("system_states", {})
	if saved_systems is Dictionary:
		for k in (saved_systems as Dictionary).keys():
			_system_states[String(k)] = (saved_systems as Dictionary)[k] == true
	else:
		_init_system_states()
	_planet_resources_collected = int(data.get("nebula_planet_resources", 0))
	_kino_limit_override = int(data.get("kino_limit_override", -1))
	_sprint_disabled = data.get("sprint_disabled", false) == true
	_escape_ready = data.get("escape_ready", false) == true
	_publish_to_game_state()


func reset() -> void:
	_current_stage = Stage.NONE
	_completed_stages.clear()
	_outcome = Outcome.IN_PROGRESS
	_power_reserve = INITIAL_POWER
	_init_system_states()
	_nebula_tick_accumulator = 0.0
	_planet_resources_collected = 0
	_kino_limit_override = -1
	_sprint_disabled = false
	_escape_ready = false
	_publish_to_game_state()


# ── Helpers ────────────────────────────────────────────────────────────────────

func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)