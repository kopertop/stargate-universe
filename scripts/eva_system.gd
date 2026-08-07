extends Node

# EVASystem — spacewalk EVA mechanic and exterior ship exploration.
#
# Manages EVA suit oxygen, suit integrity, tether status, and zero-G
# movement state. Exterior zones define hazard levels (radiation,
# meteoroid strikes). Repair tasks restore hull integrity from outside
# via ShipDamage integration.
#
# Exterior zones: hull_exterior, engine_nacelle_port/starboard,
# observation_deck_ext, shield_generator. Each has radiation level,
# meteoroid chance, repair points, and tether anchor count.
#
# Hazards: radiation (passive suit + oxygen drain), meteoroid (sudden
# suit + hull damage with warning time), tether_snap (drift + suit
# damage if tether exceeds max length).
#
# Integration:
#   - ShipDamage.apply_damage for hull damage from meteoroid strikes
#   - ShipDamage.start_repair / repair completion for exterior plate_weld
#   - GameState for oxygen + suit_integrity publication (HUD reads these)
#   - ConsumptionManager for oxygen supply drain while on EVA
#
# Save contract: current suit, oxygen, suit_integrity, active zone,
# tether status, active repair tasks.

# ── Suit type enum ────────────────────────────────────────────────────────────

enum SuitType { STANDARD, REINFORCED, LIGHT }

# ── EVA state enum ─────────────────────────────────────────────────────────────

enum EVAState { INSIDE, EVA_ACTIVE, TETHER_SNAP, RETURNING }

# ── Repair task enum ────────────────────────────────────────────────────────────

enum RepairTask { PLATE_WELD, SEAL_BREACH, REALIGN_PANEL }

# ── Signals ────────────────────────────────────────────────────────────────────

signal eva_started(zone_id: String)
signal eva_ended()
signal oxygen_changed(value: float)
signal suit_integrity_changed(value: float)
signal suit_changed(suit_type: int)
signal zone_changed(zone_id: String)
signal hazard_triggered(hazard_key: String, zone_id: String)
signal tether_status_changed(is_attached: bool)
signal eva_state_changed(state: int)
signal exterior_repair_started(zone_id: String, task: int)
signal exterior_repair_completed(zone_id: String, task: int)
signal meteoroid_warning(zone_id: String, time_remaining: float)

const EVA_CONFIG_PATH: String = "res://data/eva_config.json"

# ── Config ─────────────────────────────────────────────────────────────────────

var _max_oxygen: float = 100.0
var _oxygen_drain_rate: float = 1.5
var _oxygen_drain_hazard_multiplier: float = 2.5
var _tether_max_length: float = 30.0
var _zero_g_drag: float = 0.92
var _zero_g_accel: float = 8.0
var _suit_integrity_max: float = 100.0
var _suit_damage_warning: float = 50.0
var _suit_damage_critical: float = 25.0
var _suits: Dictionary = {}
var _exterior_zones: Dictionary = {}
var _hazards: Dictionary = {}
var _repair_tasks: Dictionary = {}

# ── State ──────────────────────────────────────────────────────────────────────

var _current_suit: int = SuitType.STANDARD
var _oxygen: float = 100.0
var _suit_integrity: float = 100.0
var _eva_state: int = EVAState.INSIDE
var _current_zone: String = ""
var _tether_attached: bool = true
var _tether_length: float = 0.0
var _active_exterior_repairs: Dictionary = {}  # zone_id → {task, remaining, total}
var _meteoroid_warn_timer: float = 0.0
var _meteoroid_pending_zone: String = ""
var _loaded: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	_publish_to_game_state()

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	_tick_oxygen(delta)
	_tick_hazards(delta)
	_tick_exterior_repairs(delta)

# ── Config loading ──────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(EVA_CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("EVASystem: cannot open %s" % EVA_CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("EVASystem: %s did not parse to a Dictionary" % EVA_CONFIG_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_max_oxygen = float(d.get("max_oxygen", 100.0))
	_oxygen_drain_rate = float(d.get("oxygen_drain_rate", 1.5))
	_oxygen_drain_hazard_multiplier = float(d.get("oxygen_drain_hazard_multiplier", 2.5))
	_tether_max_length = float(d.get("tether_max_length", 30.0))
	_zero_g_drag = float(d.get("zero_g_drag", 0.92))
	_zero_g_accel = float(d.get("zero_g_accel", 8.0))
	_suit_integrity_max = float(d.get("suit_integrity_max", 100.0))
	_suit_damage_warning = float(d.get("suit_damage_warning", 50.0))
	_suit_damage_critical = float(d.get("suit_damage_critical", 25.0))
	var raw_suits: Variant = d.get("suits", {})
	if raw_suits is Dictionary:
		_suits = (raw_suits as Dictionary).duplicate(true)
	var raw_zones: Variant = d.get("exterior_zones", {})
	if raw_zones is Dictionary:
		_exterior_zones = (raw_zones as Dictionary).duplicate(true)
	var raw_hazards: Variant = d.get("hazards", {})
	if raw_hazards is Dictionary:
		_hazards = (raw_hazards as Dictionary).duplicate(true)
	var raw_repairs: Variant = d.get("repair_tasks", {})
	if raw_repairs is Dictionary:
		_repair_tasks = (raw_repairs as Dictionary).duplicate(true)
	_oxygen = _max_oxygen
	_suit_integrity = _suit_integrity_max

# ── EVA start / end ────────────────────────────────────────────────────────────

## Start an EVA spacewalk in the given exterior zone. Returns false if
## the zone is unknown or an EVA is already active.
func start_eva(zone_id: String) -> bool:
	if not _exterior_zones.has(zone_id):
		push_warning("EVASystem: unknown exterior zone '%s'" % zone_id)
		return false
	if _eva_state == EVAState.EVA_ACTIVE or _eva_state == EVAState.TETHER_SNAP:
		return false
	_current_zone = zone_id
	_eva_state = EVAState.EVA_ACTIVE
	_tether_attached = true
	_tether_length = 0.0
	eva_started.emit(zone_id)
	zone_changed.emit(zone_id)
	eva_state_changed.emit(_eva_state)
	tether_status_changed.emit(true)
	_publish_to_game_state()
	return true

## End the EVA and return inside the ship. Returns false if no EVA active.
func end_eva() -> bool:
	if _eva_state == EVAState.INSIDE:
		return false
	_current_zone = ""
	_eva_state = EVAState.INSIDE
	_active_exterior_repairs.clear()
	_meteoroid_warn_timer = 0.0
	_meteoroid_pending_zone = ""
	eva_ended.emit()
	eva_state_changed.emit(_eva_state)
	_publish_to_game_state()
	return true

## Force the EVA state (used by tests to bypass start_eva checks).
func set_eva_state(state: int) -> void:
	_eva_state = state
	eva_state_changed.emit(_eva_state)

# ── Zone queries ───────────────────────────────────────────────────────────────

func get_current_zone() -> String:
	return _current_zone

func get_zone_config(zone_id: String) -> Dictionary:
	if not _exterior_zones.has(zone_id):
		return {}
	return _exterior_zones[zone_id] as Dictionary

func get_all_zone_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _exterior_zones.keys():
		out.append(String(k))
	return out

func is_zone_dangerous(zone_id: String) -> bool:
	var zone: Dictionary = get_zone_config(zone_id)
	if zone.is_empty():
		return false
	var rad: float = float(zone.get("radiation_level", 0.0))
	var met: float = float(zone.get("meteoroid_chance", 0.0))
	return rad > 0.5 or met > 0.1

# ── Oxygen ─────────────────────────────────────────────────────────────────────

func get_oxygen() -> float:
	return _oxygen

func get_oxygen_percent() -> float:
	if _max_oxygen <= 0.0:
		return 0.0
	return clampf(_oxygen / _max_oxygen * 100.0, 0.0, 100.0)

func set_oxygen(value: float) -> void:
	_oxygen = clampf(value, 0.0, _max_oxygen)
	oxygen_changed.emit(_oxygen)
	_publish_to_game_state()

func is_oxygen_critical() -> bool:
	return _oxygen <= 20.0

func is_oxygen_empty() -> bool:
	return _oxygen <= 0.0

## Refill oxygen to max (from a recharge station).
func refill_oxygen() -> void:
	_oxygen = _max_oxygen
	oxygen_changed.emit(_oxygen)
	_publish_to_game_state()

func _tick_oxygen(delta: float) -> void:
	if _eva_state != EVAState.EVA_ACTIVE and _eva_state != EVAState.TETHER_SNAP:
		return
	var drain: float = _oxygen_drain_rate
	# Hazard zones increase oxygen drain.
	if _exterior_zones.has(_current_zone):
		var zone: Dictionary = _exterior_zones[_current_zone] as Dictionary
		var rad: float = float(zone.get("radiation_level", 0.0))
		if rad > 0.0:
			drain += rad * _oxygen_drain_hazard_multiplier
	_oxygen = maxf(0.0, _oxygen - drain * delta)
	oxygen_changed.emit(_oxygen)
	_publish_to_game_state()

# ── Suit integrity ─────────────────────────────────────────────────────────────

func get_suit_integrity() -> float:
	return _suit_integrity

func get_suit_integrity_percent() -> float:
	if _suit_integrity_max <= 0.0:
		return 0.0
	return clampf(_suit_integrity / _suit_integrity_max * 100.0, 0.0, 100.0)

func set_suit_integrity(value: float) -> void:
	_suit_integrity = clampf(value, 0.0, _suit_integrity_max)
	suit_integrity_changed.emit(_suit_integrity)
	_publish_to_game_state()

func is_suit_damaged() -> bool:
	return _suit_integrity < _suit_damage_warning

func is_suit_critical() -> bool:
	return _suit_integrity <= _suit_damage_critical

func repair_suit(amount: float) -> void:
	_suit_integrity = minf(_suit_integrity_max, _suit_integrity + amount)
	suit_integrity_changed.emit(_suit_integrity)
	_publish_to_game_state()

func _damage_suit(amount: float) -> void:
	# Apply armor rating reduction.
	var suit_cfg: Dictionary = _get_current_suit_config()
	var armor: float = float(suit_cfg.get("armor_rating", 0.0))
	var reduced: float = maxf(0.0, amount - armor * 0.5)
	_suit_integrity = maxf(0.0, _suit_integrity - reduced)
	suit_integrity_changed.emit(_suit_integrity)
	_publish_to_game_state()

# ── Suit type ──────────────────────────────────────────────────────────────────

func get_current_suit() -> int:
	return _current_suit

func set_suit(suit_type: int) -> void:
	_current_suit = suit_type
	var cfg: Dictionary = _get_current_suit_config()
	var suit_max_o2: float = float(cfg.get("max_oxygen", _max_oxygen))
	_max_oxygen = suit_max_o2
	_oxygen = minf(_oxygen, _max_oxygen)
	_tether_max_length = float(cfg.get("tether_length", 30.0))
	suit_changed.emit(suit_type)
	_publish_to_game_state()

func _get_current_suit_config() -> Dictionary:
	var key: String = _suit_enum_to_key(_current_suit)
	if _suits.has(key):
		return _suits[key] as Dictionary
	return {}

# ── Tether ──────────────────────────────────────────────────────────────────────

func is_tether_attached() -> bool:
	return _tether_attached

func get_tether_length() -> float:
	return _tether_length

func get_tether_max_length() -> float:
	return _tether_max_length

## Set the current tether length (from player position relative to anchor).
## If tether exceeds max and is attached, triggers tether snap.
func update_tether_length(length: float) -> void:
	_tether_length = length
	if _tether_attached and length > _tether_max_length:
		_snap_tether()

func detach_tether() -> void:
	_tether_attached = false
	tether_status_changed.emit(false)

func attach_tether() -> void:
	_tether_attached = true
	_tether_length = 0.0
	tether_status_changed.emit(true)

func _snap_tether() -> void:
	_tether_attached = false
	_eva_state = EVAState.TETHER_SNAP
	tether_status_changed.emit(false)
	eva_state_changed.emit(_eva_state)
	# Tether snap causes suit damage.
	var snap_cfg: Dictionary = _hazards.get("tether_snap", {})
	var dmg: float = float(snap_cfg.get("suit_damage", 10.0))
	_damage_suit(dmg)
	hazard_triggered.emit("tether_snap", _current_zone)
	_publish_to_game_state()

## Recover from tether snap (grab a new anchor). Returns to EVA_ACTIVE.
func recover_tether() -> bool:
	if _eva_state != EVAState.TETHER_SNAP:
		return false
	_eva_state = EVAState.EVA_ACTIVE
	_tether_attached = true
	_tether_length = 0.0
	tether_status_changed.emit(true)
	eva_state_changed.emit(_eva_state)
	_publish_to_game_state()
	return true

# ── Zero-G movement ─────────────────────────────────────────────────────────────

func get_zero_g_drag() -> float:
	return _zero_g_drag

func get_zero_g_accel() -> float:
	return _zero_g_accel

## Compute velocity for zero-G movement. Applies drag each tick.
## Input_dir is a normalized Vector3 from input. Returns new velocity.
func compute_zero_g_velocity(current_vel: Vector3, input_dir: Vector3, delta: float) -> Vector3:
	var accel: Vector3 = input_dir * _zero_g_accel
	var new_vel: Vector3 = (current_vel + accel * delta) * _zero_g_drag
	return new_vel

# ── Hazards ─────────────────────────────────────────────────────────────────────

func _tick_hazards(delta: float) -> void:
	if _eva_state != EVAState.EVA_ACTIVE and _eva_state != EVAState.TETHER_SNAP:
		return
	if not _exterior_zones.has(_current_zone):
		return
	var zone: Dictionary = _exterior_zones[_current_zone] as Dictionary
	# Radiation: passive suit + oxygen drain.
	var rad: float = float(zone.get("radiation_level", 0.0))
	if rad > 0.0:
		var rad_cfg: Dictionary = _hazards.get("radiation", {})
		var suit_dmg_rate: float = float(rad_cfg.get("suit_damage_rate", 0.5))
		_damage_suit(suit_dmg_rate * rad * delta)
	# Meteoroid: random strike with warning.
	var met_chance: float = float(zone.get("meteoroid_chance", 0.0))
	if met_chance > 0.0:
		# Scale chance by delta (per-second chance → per-tick).
		var tick_chance: float = met_chance * delta
		if _meteoroid_warn_timer > 0.0:
			_meteoroid_warn_timer -= delta
			meteoroid_warning.emit(_current_zone, _meteoroid_warn_timer)
			if _meteoroid_warn_timer <= 0.0:
				_meteoroid_impact(_meteoroid_pending_zone)
				_meteoroid_pending_zone = ""
		elif randf() < tick_chance:
			# Start warning timer.
			var met_cfg: Dictionary = _hazards.get("meteoroid", {})
			_meteoroid_warn_timer = float(met_cfg.get("warn_time_seconds", 2.0))
			_meteoroid_pending_zone = _current_zone

func _meteoroid_impact(zone_id: String) -> void:
	var zone: Dictionary = _exterior_zones.get(zone_id, {})
	var met_dmg: float = float(zone.get("meteoroid_damage", 8.0))
	var met_cfg: Dictionary = _hazards.get("meteoroid", {})
	var suit_dmg: float = float(met_cfg.get("suit_damage", 15.0))
	var hull_dmg: float = float(met_cfg.get("hull_damage_on_hit", 5.0))
	_damage_suit(suit_dmg)
	# Propagate hull damage to ShipDamage.
	var sd: Node = _autoload("ShipDamage")
	if sd != null and sd.has_method("apply_damage"):
		# Use meteor_impact source for hull damage.
		sd.call("apply_damage", "meteor_impact", "gate_room")
	hazard_triggered.emit("meteoroid", zone_id)

## Trigger a meteoroid impact directly (for tests / scripted events).
func trigger_meteoroid(zone_id: String) -> void:
	_meteoroid_impact(zone_id)

# ── Exterior repair tasks ───────────────────────────────────────────────────────
#
# Three repair tasks: plate_weld, seal_breach, realign_panel. Each
# restores hull integrity via ShipDamage integration and costs oxygen.
# The exterior repair console interactable calls these methods.

## Start an exterior repair task in the current zone. Returns false if
## no EVA active, the task is unknown, or a repair is already active
## in the zone.
func start_exterior_repair(zone_id: String, task_key: String) -> bool:
	if _eva_state != EVAState.EVA_ACTIVE:
		return false
	if not _exterior_zones.has(zone_id):
		return false
	if _active_exterior_repairs.has(zone_id):
		return false
	if not _repair_tasks.has(task_key):
		return false
	var task: Dictionary = _repair_tasks[task_key] as Dictionary
	var duration: float = float(task.get("duration", 3.0))
	_active_exterior_repairs[zone_id] = {
		"task": task_key,
		"remaining": duration,
		"total": duration,
	}
	exterior_repair_started.emit(zone_id, _task_key_to_enum(task_key))
	return true

## Start an exterior repair using the RepairTask enum.
func start_exterior_repair_enum(zone_id: String, task: int) -> bool:
	var key: String = _task_enum_to_key(task)
	return start_exterior_repair(zone_id, key)

## Process exterior repair ticks. Returns zones whose repairs completed.
func _tick_exterior_repairs(delta: float) -> Array[String]:
	if _active_exterior_repairs.is_empty():
		return []
	var completed: Array[String] = []
	for zone_id in _active_exterior_repairs.keys():
		var zid: String = String(zone_id)
		var job: Dictionary = _active_exterior_repairs[zid]
		job["remaining"] = maxf(0.0, float(job["remaining"]) - delta)
		if float(job["remaining"]) <= 0.0:
			completed.append(zid)
	for zid in completed:
		var job: Dictionary = _active_exterior_repairs[zid]
		var task_key: String = String(job.get("task", "plate_weld"))
		_apply_exterior_repair_result(zid, task_key)
		_active_exterior_repairs.erase(zid)
		exterior_repair_completed.emit(zid, _task_key_to_enum(task_key))
	return completed

## Apply the repair result: restore hull via ShipDamage, drain oxygen.
func _apply_exterior_repair_result(zone_id: String, task_key: String) -> void:
	if not _repair_tasks.has(task_key):
		return
	var task: Dictionary = _repair_tasks[task_key] as Dictionary
	var hull_restore: float = float(task.get("hull_restore", 0.0))
	var o2_cost: float = float(task.get("suit_oxygen_cost", 0.0))
	# Drain oxygen.
	_oxygen = maxf(0.0, _oxygen - o2_cost)
	oxygen_changed.emit(_oxygen)
	# Restore hull via ShipDamage.set_hull_integrity.
	var sd: Node = _autoload("ShipDamage")
	if sd != null and sd.has_method("set_hull_integrity"):
		var current_hull: float = float(sd.call("get_hull_integrity"))
		sd.call("set_hull_integrity", current_hull + hull_restore)
	_publish_to_game_state()

## Check if a zone has an active exterior repair.
func is_exterior_repair_active(zone_id: String) -> bool:
	return _active_exterior_repairs.has(zone_id)

## Get the repair progress fraction (0.0 to 1.0) for a zone.
func get_exterior_repair_progress(zone_id: String) -> float:
	if not _active_exterior_repairs.has(zone_id):
		return 0.0
	var job: Dictionary = _active_exterior_repairs[zone_id]
	var total: float = float(job.get("total", 0.0))
	if total <= 0.0:
		return 1.0
	return 1.0 - clampf(float(job.get("remaining", 0.0)) / total, 0.0, 1.0)

## Get the parts cost for an exterior repair task.
func get_exterior_repair_cost(task_key: String) -> int:
	if not _repair_tasks.has(task_key):
		return 0
	var task: Dictionary = _repair_tasks[task_key] as Dictionary
	return int(task.get("parts_cost", 0))

## Get all zones with active exterior repairs.
func get_active_exterior_repair_zones() -> Array[String]:
	var out: Array[String] = []
	for k in _active_exterior_repairs.keys():
		out.append(String(k))
	return out

# ── GameState integration ───────────────────────────────────────────────────────

func _publish_to_game_state() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	if gs.has_method("set_eva_oxygen"):
		gs.call("set_eva_oxygen", get_oxygen_percent())
	if gs.has_method("set_eva_suit_integrity"):
		gs.call("set_eva_suit_integrity", get_suit_integrity_percent())
	if gs.has_method("set_eva_active"):
		gs.call("set_eva_active", _eva_state != EVAState.INSIDE)

# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	var repair_data: Dictionary = {}
	for zone_id in _active_exterior_repairs.keys():
		var zid: String = String(zone_id)
		repair_data[zid] = {
			"task": String(_active_exterior_repairs[zid].get("task", "plate_weld")),
			"remaining": float(_active_exterior_repairs[zid].get("remaining", 0.0)),
			"total": float(_active_exterior_repairs[zid].get("total", 0.0)),
		}
	return {
		"current_suit": _current_suit,
		"oxygen": _oxygen,
		"suit_integrity": _suit_integrity,
		"eva_state": _eva_state,
		"current_zone": _current_zone,
		"tether_attached": _tether_attached,
		"tether_length": _tether_length,
		"active_exterior_repairs": repair_data,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_current_suit = int(data.get("current_suit", SuitType.STANDARD))
	_oxygen = float(data.get("oxygen", _max_oxygen))
	_suit_integrity = float(data.get("suit_integrity", _suit_integrity_max))
	_eva_state = int(data.get("eva_state", EVAState.INSIDE))
	_current_zone = String(data.get("current_zone", ""))
	_tether_attached = bool(data.get("tether_attached", true))
	_tether_length = float(data.get("tether_length", 0.0))
	_active_exterior_repairs.clear()
	var saved_repairs: Variant = data.get("active_exterior_repairs", {})
	if saved_repairs is Dictionary:
		for k in (saved_repairs as Dictionary).keys():
			var zid: String = String(k)
			var job: Dictionary = (saved_repairs as Dictionary)[k] as Dictionary
			if job == null or job.is_empty():
				continue
			_active_exterior_repairs[zid] = {
				"task": String(job.get("task", "plate_weld")),
				"remaining": float(job.get("remaining", 0.0)),
				"total": float(job.get("total", 0.0)),
			}
	_publish_to_game_state()

func reset() -> void:
	_current_suit = SuitType.STANDARD
	# Restore max_oxygen and tether to standard suit defaults.
	var std_cfg: Dictionary = _suits.get("standard", {})
	_max_oxygen = float(std_cfg.get("max_oxygen", 100.0))
	_tether_max_length = float(std_cfg.get("tether_length", 30.0))
	_oxygen = _max_oxygen
	_suit_integrity = _suit_integrity_max
	_eva_state = EVAState.INSIDE
	_current_zone = ""
	_tether_attached = true
	_tether_length = 0.0
	_active_exterior_repairs.clear()
	_meteoroid_warn_timer = 0.0
	_meteoroid_pending_zone = ""
	_publish_to_game_state()

# ── Enum conversion helpers ────────────────────────────────────────────────────

func _suit_enum_to_key(suit: int) -> String:
	match suit:
		SuitType.STANDARD:
			return "standard"
		SuitType.REINFORCED:
			return "reinforced"
		SuitType.LIGHT:
			return "light"
		_:
			return "standard"

func _suit_key_to_enum(key: String) -> int:
	match key:
		"standard":
			return SuitType.STANDARD
		"reinforced":
			return SuitType.REINFORCED
		"light":
			return SuitType.LIGHT
		_:
			return SuitType.STANDARD

func _task_enum_to_key(task: int) -> String:
	match task:
		RepairTask.PLATE_WELD:
			return "plate_weld"
		RepairTask.SEAL_BREACH:
			return "seal_breach"
		RepairTask.REALIGN_PANEL:
			return "realign_panel"
		_:
			return "plate_weld"

func _task_key_to_enum(key: String) -> int:
	match key:
		"plate_weld":
			return RepairTask.PLATE_WELD
		"seal_breach":
			return RepairTask.SEAL_BREACH
		"realign_panel":
			return RepairTask.REALIGN_PANEL
		_:
			return RepairTask.PLATE_WELD

# ── Test hooks ──────────────────────────────────────────────────────────────────

## Advance oxygen + hazard + repair ticks by a fixed delta (bypasses _process).
func test_advance(delta: float) -> Array[String]:
	_tick_oxygen(delta)
	_tick_hazards(delta)
	return _tick_exterior_repairs(delta)

## Advance only exterior repairs (no oxygen/hazard drain, for tests).
func test_advance_repairs(delta: float) -> Array[String]:
	return _tick_exterior_repairs(delta)

# ── Helpers ──────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "eva_system", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)