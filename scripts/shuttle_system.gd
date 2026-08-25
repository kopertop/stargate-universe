extends Node

# ShuttleSystem — pilotable shuttle craft for planetary approach.
#
# Manages shuttle flight in two environments (atmospheric + space),
# landing sequences, cargo capacity, and shuttle damage. Used in
# specific episodes where the crew pilots a shuttle to a planet surface
# or asteroid base.
#
# Flight modes:
#   DOCKED    — shuttle is parked, no flight controls active.
#   FLYING    — shuttle is in flight (atmospheric or space).
#   LANDING   — shuttle is executing a landing descent sequence.
#   CRASHED   — shuttle hull hit zero or landing impact exceeded threshold.
#
# Shuttle types: destiny_shuttle (balanced), cargo_shuttle (heavy transport),
# recon_shuttle (fast scout). Each has different hull, fuel, cargo, speed,
# acceleration, drag, and fuel-burn characteristics.
#
# Cargo: items are stored as a Dictionary of item_id → count. Max cargo
# slots depend on shuttle type. load_cargo / unload_cargo manage inventory.
#
# Damage integration:
#   - ShipDamage.apply_damage when shuttle takes hull damage from
#     atmospheric entry or hard landing (uses shuttle_damage source).
#   - GameState.shuttle_hull_percent + shuttle_fuel_percent published
#     on every change for HUD display.
#   - ConsumptionManager reads shuttle fuel for efficiency calculations.
#
# Save contract: active shuttle type, hull, fuel, cargo, flight mode,
# environment, current landing zone, landing progress.

# ── Flight mode enum ──────────────────────────────────────────────────────────

enum FlightMode { DOCKED, FLYING, LANDING, CRASHED }

# ── Flight environment enum ────────────────────────────────────────────────────

enum FlightEnv { ATMOSPHERIC, SPACE }

# ── Landing phase enum ─────────────────────────────────────────────────────────

enum LandingPhase { IDLE, DESCENT, TOUCHDOWN, COMPLETE }

# ── Signals ────────────────────────────────────────────────────────────────────

signal shuttle_selected(shuttle_key: String)
signal flight_mode_changed(mode: int)
signal flight_env_changed(env: int)
signal hull_changed(value: float)
signal fuel_changed(value: float)
signal cargo_changed(cargo: Dictionary)
signal cargo_loaded(item_id: String, count: int)
signal cargo_unloaded(item_id: String, count: int)
signal landing_started(zone_id: String)
signal landing_progress_updated(phase: int, progress: float)
signal landing_completed(zone_id: String, success: bool)
signal shuttle_destroyed()
signal shuttle_crashed()

const SHUTTLE_CONFIG_PATH: String = "res://data/shuttle_config.json"

# ── Config ─────────────────────────────────────────────────────────────────────

var _max_hull: float = 100.0
var _max_fuel: float = 100.0
var _max_cargo: int = 10
var _fuel_warning: float = 25.0
var _fuel_critical: float = 10.0
var _hull_warning: float = 50.0
var _hull_critical: float = 25.0
var _atmo_entry_damage: float = 5.0
var _landing_impact_threshold: float = 8.0
var _shuttles: Dictionary = {}
var _flight_envs: Dictionary = {}
var _landing_zones: Dictionary = {}

# ── State ──────────────────────────────────────────────────────────────────────

var _current_shuttle: String = ""
var _shuttle_config: Dictionary = {}
var _hull: float = 100.0
var _fuel: float = 100.0
var _cargo: Dictionary = {}
var _flight_mode: int = FlightMode.DOCKED
var _flight_env: int = FlightEnv.ATMOSPHERIC
var _velocity: Vector3 = Vector3.ZERO
var _position: Vector3 = Vector3.ZERO
var _landing_zone: String = ""
var _landing_phase: int = LandingPhase.IDLE
var _landing_progress: float = 0.0
var _landing_timer: float = 0.0
var _landing_duration: float = 5.0
var _landing_duration_overridden: bool = false
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
	_tick_flight(delta)
	_tick_landing(delta)

# ── Config loading ──────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(SHUTTLE_CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("ShuttleSystem: cannot open %s" % SHUTTLE_CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ShuttleSystem: %s did not parse to a Dictionary" % SHUTTLE_CONFIG_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_max_hull = float(d.get("max_hull", 100.0))
	_max_fuel = float(d.get("max_fuel", 100.0))
	_max_cargo = int(d.get("max_cargo", 10))
	_fuel_warning = float(d.get("fuel_warning_threshold", 25.0))
	_fuel_critical = float(d.get("fuel_critical_threshold", 10.0))
	_hull_warning = float(d.get("hull_warning_threshold", 50.0))
	_hull_critical = float(d.get("hull_critical_threshold", 25.0))
	_atmo_entry_damage = float(d.get("atmospheric_entry_damage", 5.0))
	_landing_impact_threshold = float(d.get("landing_impact_damage_threshold", 8.0))
	var raw_shuttles: Variant = d.get("shuttles", {})
	if raw_shuttles is Dictionary:
		_shuttles = (raw_shuttles as Dictionary).duplicate(true)
	var raw_envs: Variant = d.get("flight_environments", {})
	if raw_envs is Dictionary:
		_flight_envs = (raw_envs as Dictionary).duplicate(true)
	var raw_zones: Variant = d.get("landing_zones", {})
	if raw_zones is Dictionary:
		_landing_zones = (raw_zones as Dictionary).duplicate(true)

# ── Shuttle selection ──────────────────────────────────────────────────────────

## Select a shuttle type by key. Resets hull, fuel, cargo to that shuttle's
## max values. Returns false if the shuttle key is unknown.
func select_shuttle(shuttle_key: String) -> bool:
	if not _shuttles.has(shuttle_key):
		push_warning("ShuttleSystem: unknown shuttle '%s'" % shuttle_key)
		return false
	_current_shuttle = shuttle_key
	_shuttle_config = (_shuttles[shuttle_key] as Dictionary).duplicate(true)
	_hull = float(_shuttle_config.get("max_hull", _max_hull))
	_fuel = float(_shuttle_config.get("max_fuel", _max_fuel))
	_max_cargo = int(_shuttle_config.get("max_cargo", _max_cargo))
	_cargo.clear()
	_flight_mode = FlightMode.DOCKED
	_velocity = Vector3.ZERO
	_position = Vector3.ZERO
	_landing_zone = ""
	_landing_phase = LandingPhase.IDLE
	_landing_progress = 0.0
	shuttle_selected.emit(shuttle_key)
	hull_changed.emit(_hull)
	fuel_changed.emit(_fuel)
	cargo_changed.emit(_cargo.duplicate())
	_publish_to_game_state()
	return true

func get_current_shuttle() -> String:
	return _current_shuttle

func get_shuttle_config() -> Dictionary:
	return _shuttle_config.duplicate(true)

func get_all_shuttle_keys() -> Array[String]:
	var out: Array[String] = []
	for k in _shuttles.keys():
		out.append(String(k))
	return out

# ── Flight mode ─────────────────────────────────────────────────────────────────

## Start flight in the given environment. Returns false if no shuttle is
## selected, fuel is empty, or the shuttle is destroyed.
func start_flight(env: int) -> bool:
	if _current_shuttle.is_empty():
		push_warning("ShuttleSystem: no shuttle selected")
		return false
	if _flight_mode == FlightMode.FLYING or _flight_mode == FlightMode.LANDING or _flight_mode == FlightMode.CRASHED:
		return false
	if _fuel <= 0.0:
		push_warning("ShuttleSystem: cannot start flight with no fuel")
		return false
	_flight_mode = FlightMode.FLYING
	_flight_env = env
	_velocity = Vector3.ZERO
	flight_mode_changed.emit(_flight_mode)
	flight_env_changed.emit(_flight_env)
	_publish_to_game_state()
	return true

## End flight and dock the shuttle. Returns false if not flying.
func end_flight() -> bool:
	if _flight_mode != FlightMode.FLYING and _flight_mode != FlightMode.LANDING:
		return false
	_flight_mode = FlightMode.DOCKED
	_velocity = Vector3.ZERO
	_landing_phase = LandingPhase.IDLE
	_landing_progress = 0.0
	flight_mode_changed.emit(_flight_mode)
	_publish_to_game_state()
	return true

func get_flight_mode() -> int:
	return _flight_mode

func get_flight_mode_int() -> int:
	return int(_flight_mode)

func set_flight_mode(mode: int) -> void:
	_flight_mode = mode
	flight_mode_changed.emit(_flight_mode)

func get_flight_env() -> int:
	return _flight_env

func set_flight_env(env: int) -> void:
	_flight_env = env
	flight_env_changed.emit(_flight_env)

## Switch flight environment (atmospheric to space or vice versa).
## Atmospheric entry applies hull damage to the shuttle.
func switch_environment(env: int) -> bool:
	if _flight_mode != FlightMode.FLYING:
		return false
	if _flight_env == env:
		return true
	_flight_env = env
	flight_env_changed.emit(_flight_env)
	if env == FlightEnv.ATMOSPHERIC:
		_apply_hull_damage(_atmo_entry_damage, "atmospheric_entry")
	return true

# ── Velocity and movement ──────────────────────────────────────────────────────

func get_velocity() -> Vector3:
	return _velocity

func set_velocity(vel: Vector3) -> void:
	_velocity = vel

func get_position() -> Vector3:
	return _position

func set_position(pos: Vector3) -> void:
	_position = pos

## Apply a thrust input direction to the shuttle. Accelerates the shuttle
## up to the max speed for the current environment. Burns fuel.
## input_dir should be a normalized Vector3.
func apply_thrust(input_dir: Vector3, delta: float) -> void:
	if _flight_mode != FlightMode.FLYING:
		return
	if input_dir.length_squared() < 0.01:
		return
	var env_key: String = _env_enum_to_key(_flight_env)
	var env_cfg: Dictionary = _flight_envs.get(env_key, {})
	var shuttle_accel: float = float(_shuttle_config.get(
		"accel_" + env_key, 15.0))
	var shuttle_max_speed: float = float(_shuttle_config.get(
		"max_speed_" + env_key, 60.0))
	var drag: float = float(_shuttle_config.get("drag_" + env_key,
		float(env_cfg.get("drag", 0.88))))
	var fuel_rate: float = float(_shuttle_config.get(
		"fuel_burn_rate_" + env_key, 0.3))
	var accel_vec: Vector3 = input_dir.normalized() * shuttle_accel
	_velocity = (_velocity + accel_vec * delta) * drag
	var speed: float = _velocity.length()
	if speed > shuttle_max_speed:
		_velocity = _velocity.normalized() * shuttle_max_speed
	_burn_fuel(fuel_rate * delta)
	_position += _velocity * delta

func _tick_flight(delta: float) -> void:
	if _flight_mode != FlightMode.FLYING:
		return
	# Apply passive drag even without thrust.
	var env_key: String = _env_enum_to_key(_flight_env)
	var drag: float = float(_shuttle_config.get("drag_" + env_key, 0.88))
	_velocity = _velocity * pow(drag, delta)
	_position += _velocity * delta

# ── Fuel ────────────────────────────────────────────────────────────────────────

func get_fuel() -> float:
	return _fuel

func get_fuel_percent() -> float:
	var max_f: float = float(_shuttle_config.get("max_fuel", _max_fuel))
	if max_f <= 0.0:
		return 0.0
	return clampf(_fuel / max_f * 100.0, 0.0, 100.0)

func set_fuel(value: float) -> void:
	_fuel = clampf(value, 0.0, float(_shuttle_config.get("max_fuel", _max_fuel)))
	fuel_changed.emit(_fuel)
	_publish_to_game_state()

func is_fuel_warning() -> bool:
	return _fuel <= _fuel_warning

func is_fuel_critical() -> bool:
	return _fuel <= _fuel_critical

func is_fuel_empty() -> bool:
	return _fuel <= 0.0

## Refuel the shuttle to max fuel.
func refuel() -> void:
	_fuel = float(_shuttle_config.get("max_fuel", _max_fuel))
	fuel_changed.emit(_fuel)
	_publish_to_game_state()

func _burn_fuel(amount: float) -> void:
	_fuel = maxf(0.0, _fuel - amount)
	fuel_changed.emit(_fuel)
	_publish_to_game_state()

# ── Hull / damage ──────────────────────────────────────────────────────────────

func get_hull() -> float:
	return _hull

func get_hull_percent() -> float:
	var max_h: float = float(_shuttle_config.get("max_hull", _max_hull))
	if max_h <= 0.0:
		return 0.0
	return clampf(_hull / max_h * 100.0, 0.0, 100.0)

func set_hull(value: float) -> void:
	_hull = clampf(value, 0.0, float(_shuttle_config.get("max_hull", _max_hull)))
	hull_changed.emit(_hull)
	_publish_to_game_state()

func is_hull_warning() -> bool:
	return _hull <= _hull_warning

func is_hull_critical() -> bool:
	return _hull <= _hull_critical

func is_hull_destroyed() -> bool:
	return _hull <= 0.0

## Apply hull damage to the shuttle. If hull reaches zero, the shuttle
## is destroyed (CRASHED mode). source_key is for logging/debugging.
func _apply_hull_damage(amount: float, source_key: String) -> void:
	_hull = maxf(0.0, _hull - amount)
	hull_changed.emit(_hull)
	if _hull <= 0.0:
		_flight_mode = FlightMode.CRASHED
		flight_mode_changed.emit(_flight_mode)
		shuttle_destroyed.emit()
		shuttle_crashed.emit()
	_publish_to_game_state()

## Apply damage from an external source (meteoroid, combat, etc.).
## Propagates to ShipDamage if the shuttle is docked.
func apply_damage(amount: float, source_key: String = "combat") -> float:
	var prev_hull: float = _hull
	_apply_hull_damage(amount, source_key)
	return prev_hull - _hull

## Repair the shuttle hull by a fixed amount.
func repair_hull(amount: float) -> void:
	var max_h: float = float(_shuttle_config.get("max_hull", _max_hull))
	_hull = minf(max_h, _hull + amount)
	hull_changed.emit(_hull)
	_publish_to_game_state()

# ── Cargo ──────────────────────────────────────────────────────────────────────

func get_cargo() -> Dictionary:
	return _cargo.duplicate()

func get_cargo_count() -> int:
	var total: int = 0
	for k in _cargo.keys():
		total += int(_cargo[k])
	return total

func get_cargo_capacity() -> int:
	return _max_cargo

func get_cargo_free_slots() -> int:
	return _max_cargo - get_cargo_count()

## Load cargo into the shuttle. Returns the number actually loaded
## (may be less if cargo hold is full).
func load_cargo(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var free: int = get_cargo_free_slots()
	var to_load: int = minf(count, free)
	if to_load <= 0:
		return 0
	_cargo[item_id] = int(_cargo.get(item_id, 0)) + to_load
	cargo_changed.emit(_cargo.duplicate())
	cargo_loaded.emit(item_id, to_load)
	_publish_to_game_state()
	return to_load

## Unload cargo from the shuttle. Returns the number actually unloaded
## (may be less if not enough in hold).
func unload_cargo(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	if not _cargo.has(item_id):
		return 0
	var have: int = int(_cargo[item_id])
	var to_unload: int = minf(count, have)
	_cargo[item_id] = have - to_unload
	if int(_cargo[item_id]) <= 0:
		_cargo.erase(item_id)
	cargo_changed.emit(_cargo.duplicate())
	cargo_unloaded.emit(item_id, to_unload)
	_publish_to_game_state()
	return to_unload

## Clear all cargo from the shuttle.
func clear_cargo() -> void:
	_cargo.clear()
	cargo_changed.emit(_cargo.duplicate())
	_publish_to_game_state()

## Check if the shuttle has at least count of item_id.
func has_cargo(item_id: String, count: int = 1) -> bool:
	return int(_cargo.get(item_id, 0)) >= count

# ── Landing sequence ────────────────────────────────────────────────────────────
#
# Landing is a multi-phase descent: DESCENT → TOUCHDOWN → COMPLETE.
# The shuttle descends over a fixed duration, consuming fuel. On touchdown,
# landing speed is checked — if velocity exceeds the landing speed threshold
# for the shuttle type, the shuttle takes hull damage (hard landing).
# A safe landing zone (safe_landing=true) negates the hard landing damage.

## Begin a landing sequence at the given zone. Returns false if no shuttle
## is selected, fuel is insufficient, or the shuttle is not flying.
func start_landing(zone_id: String) -> bool:
	if _current_shuttle.is_empty():
		push_warning("ShuttleSystem: no shuttle selected")
		return false
	if _flight_mode != FlightMode.FLYING:
		push_warning("ShuttleSystem: must be flying to start landing")
		return false
	if not _landing_zones.has(zone_id):
		push_warning("ShuttleSystem: unknown landing zone '%s'" % zone_id)
		return false
	var zone: Dictionary = _landing_zones[zone_id] as Dictionary
	if bool(zone.get("requires_fuel", true)) and _fuel <= 0.0:
		push_warning("ShuttleSystem: insufficient fuel to land at %s" % zone_id)
		return false
	_flight_mode = FlightMode.LANDING
	_landing_zone = zone_id
	_landing_phase = LandingPhase.DESCENT
	_landing_progress = 0.0
	_landing_timer = 0.0
	if not _landing_duration_overridden:
		_landing_duration = 5.0
	flight_mode_changed.emit(_flight_mode)
	landing_started.emit(zone_id)
	landing_progress_updated.emit(_landing_phase, 0.0)
	_publish_to_game_state()
	return true

func get_landing_zone() -> String:
	return _landing_zone

func get_landing_phase() -> int:
	return _landing_phase

func get_landing_phase_int() -> int:
	return int(_landing_phase)

func get_landing_progress() -> float:
	return _landing_progress

func _tick_landing(delta: float) -> void:
	if _flight_mode != FlightMode.LANDING:
		return
	if _landing_phase == LandingPhase.IDLE or _landing_phase == LandingPhase.COMPLETE:
		return
	_landing_timer += delta
	_landing_progress = clampf(_landing_timer / _landing_duration, 0.0, 1.0)
	# Burn fuel during descent.
	var fuel_rate: float = float(_shuttle_config.get("fuel_burn_rate_landing", 0.5))
	_burn_fuel(fuel_rate * delta)
	# Apply descent velocity.
	var descent_rate: float = float(_shuttle_config.get("landing_descent_rate", 2.0))
	_position.y -= descent_rate * delta
	# Check fuel depletion during descent — before touchdown.
	if _fuel <= 0.0 and _landing_phase == LandingPhase.DESCENT:
		# Out of fuel during descent — hard crash.
		_landing_phase = LandingPhase.TOUCHDOWN
		landing_progress_updated.emit(_landing_phase, 1.0)
		_complete_touchdown(true)
		return
	if _landing_phase == LandingPhase.DESCENT:
		landing_progress_updated.emit(_landing_phase, _landing_progress)
		if _landing_progress >= 1.0:
			_landing_phase = LandingPhase.TOUCHDOWN
			landing_progress_updated.emit(_landing_phase, 1.0)
			_complete_touchdown()

## Handle the touchdown moment. Checks landing speed and applies damage
## if the landing is too hard. force_crash = true means fuel ran out.
func _complete_touchdown(force_crash: bool = false) -> void:
	var zone: Dictionary = _landing_zones.get(_landing_zone, {})
	var safe: bool = bool(zone.get("safe_landing", false))
	var speed_threshold: float = float(_shuttle_config.get("landing_speed_threshold", 5.0))
	var landing_speed: float = _velocity.length()
	var success: bool = true
	if force_crash:
		# Fuel ran out — forced crash landing.
		_apply_hull_damage(_hull, "fuel_depletion_crash")
		success = false
	elif not safe and landing_speed > speed_threshold * 2.0:
		# Very hard landing — crash.
		_apply_hull_damage(_hull, "crash_landing")
		success = false
	elif not safe and landing_speed > speed_threshold:
		# Hard landing — apply damage proportional to excess speed.
		var excess: float = landing_speed - speed_threshold
		_apply_hull_damage(excess, "hard_landing")
		if _hull <= 0.0:
			success = false
	_landing_phase = LandingPhase.COMPLETE
	landing_progress_updated.emit(_landing_phase, 1.0)
	landing_completed.emit(_landing_zone, success)
	if success:
		_flight_mode = FlightMode.DOCKED
		flight_mode_changed.emit(_flight_mode)
	else:
		_flight_mode = FlightMode.CRASHED
		flight_mode_changed.emit(_flight_mode)
		shuttle_crashed.emit()
	_publish_to_game_state()

## Abort the landing sequence. Returns to flying mode.
## Returns false if not in a landing sequence.
func abort_landing() -> bool:
	if _flight_mode != FlightMode.LANDING:
		return false
	_flight_mode = FlightMode.FLYING
	_landing_phase = LandingPhase.IDLE
	_landing_progress = 0.0
	_landing_zone = ""
	flight_mode_changed.emit(_flight_mode)
	_publish_to_game_state()
	return true

# ── Landing zones ──────────────────────────────────────────────────────────────

func get_landing_zone_config(zone_id: String) -> Dictionary:
	if not _landing_zones.has(zone_id):
		return {}
	return _landing_zones[zone_id] as Dictionary

func get_all_landing_zone_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _landing_zones.keys():
		out.append(String(k))
	return out

func is_safe_landing_zone(zone_id: String) -> bool:
	var zone: Dictionary = get_landing_zone_config(zone_id)
	return bool(zone.get("safe_landing", false))

# ── GameState integration ──────────────────────────────────────────────────────

func _publish_to_game_state() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	if gs.has_method("set_shuttle_hull_percent"):
		gs.call("set_shuttle_hull_percent", get_hull_percent())
	if gs.has_method("set_shuttle_fuel_percent"):
		gs.call("set_shuttle_fuel_percent", get_fuel_percent())
	if gs.has_method("set_shuttle_active"):
		gs.call("set_shuttle_active", _flight_mode != FlightMode.DOCKED)

# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"current_shuttle": _current_shuttle,
		"hull": _hull,
		"fuel": _fuel,
		"cargo": _cargo.duplicate(true),
		"flight_mode": _flight_mode,
		"flight_env": _flight_env,
		"velocity": {
			"x": _velocity.x, "y": _velocity.y, "z": _velocity.z,
		},
		"position": {
			"x": _position.x, "y": _position.y, "z": _position.z,
		},
		"landing_zone": _landing_zone,
		"landing_phase": _landing_phase,
		"landing_progress": _landing_progress,
		"landing_timer": _landing_timer,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_current_shuttle = String(data.get("current_shuttle", ""))
	if not _current_shuttle.is_empty() and _shuttles.has(_current_shuttle):
		_shuttle_config = (_shuttles[_current_shuttle] as Dictionary).duplicate(true)
		_max_cargo = int(_shuttle_config.get("max_cargo", _max_cargo))
	_hull = float(data.get("hull", _max_hull))
	_fuel = float(data.get("fuel", _max_fuel))
	_cargo.clear()
	var saved_cargo: Variant = data.get("cargo", {})
	if saved_cargo is Dictionary:
		for k in (saved_cargo as Dictionary).keys():
			_cargo[String(k)] = int((saved_cargo as Dictionary)[k])
	_flight_mode = int(data.get("flight_mode", FlightMode.DOCKED))
	_flight_env = int(data.get("flight_env", FlightEnv.ATMOSPHERIC))
	var saved_vel: Variant = data.get("velocity", {})
	if saved_vel is Dictionary:
		_velocity = Vector3(
			float((saved_vel as Dictionary).get("x", 0.0)),
			float((saved_vel as Dictionary).get("y", 0.0)),
			float((saved_vel as Dictionary).get("z", 0.0)),
		)
	var saved_pos: Variant = data.get("position", {})
	if saved_pos is Dictionary:
		_position = Vector3(
			float((saved_pos as Dictionary).get("x", 0.0)),
			float((saved_pos as Dictionary).get("y", 0.0)),
			float((saved_pos as Dictionary).get("z", 0.0)),
		)
	_landing_zone = String(data.get("landing_zone", ""))
	_landing_phase = int(data.get("landing_phase", LandingPhase.IDLE))
	_landing_progress = float(data.get("landing_progress", 0.0))
	_landing_timer = float(data.get("landing_timer", 0.0))
	_publish_to_game_state()

func reset() -> void:
	if not _current_shuttle.is_empty() and _shuttles.has(_current_shuttle):
		_shuttle_config = (_shuttles[_current_shuttle] as Dictionary).duplicate(true)
		_hull = float(_shuttle_config.get("max_hull", _max_hull))
		_fuel = float(_shuttle_config.get("max_fuel", _max_fuel))
		_max_cargo = int(_shuttle_config.get("max_cargo", _max_cargo))
	else:
		_hull = _max_hull
		_fuel = _max_fuel
	_cargo.clear()
	_flight_mode = FlightMode.DOCKED
	_velocity = Vector3.ZERO
	_position = Vector3.ZERO
	_landing_zone = ""
	_landing_phase = LandingPhase.IDLE
	_landing_progress = 0.0
	_landing_timer = 0.0
	_landing_duration_overridden = false
	_publish_to_game_state()

# ── Enum conversion helpers ────────────────────────────────────────────────────

func _env_enum_to_key(env: int) -> String:
	match env:
		FlightEnv.ATMOSPHERIC:
			return "atmospheric"
		FlightEnv.SPACE:
			return "space"
		_:
			return "atmospheric"

func _env_key_to_enum(key: String) -> int:
	match key:
		"atmospheric":
			return FlightEnv.ATMOSPHERIC
		"space":
			return FlightEnv.SPACE
		_:
			return FlightEnv.ATMOSPHERIC

# ── Test hooks ──────────────────────────────────────────────────────────────────

## Advance flight + landing ticks by a fixed delta (bypasses _process).
func test_advance(delta: float) -> void:
	_tick_flight(delta)
	_tick_landing(delta)

## Advance only landing ticks (no flight drag, for tests).
func test_advance_landing(delta: float) -> void:
	_tick_landing(delta)

## Force-set the landing duration (for test speed-up).
func set_landing_duration(duration: float) -> void:
	_landing_duration = duration
	_landing_duration_overridden = true

# ── Helpers ──────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "shuttle_system", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)