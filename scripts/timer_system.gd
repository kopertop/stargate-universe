extends Node

# Centralized timer service for Destiny (issue: P1 timer & pressure system).
#
# Capabilities:
#   • Multiple concurrent named countdown timers.
#   • Time acceleration (global speed multiplier on all timers).
#   • Drama-time dilation (slow-mo via Engine.time_scale during crises).
#   • Crisis auto-dilation (auto-engages dilation when a crisis timer
#     crosses below the threshold percentage).
#   • FTL countdown display query (doorway consoles read remaining time).
#
# Design:
#   - Timers are identified by a string key. Each stores remaining seconds,
#     total seconds, a category tag, and optional metadata.
#   - The system ticks all active timers in _process, scaled by the global
#     acceleration multiplier. Engine.time_scale handles drama dilation.
#   - Headless tests bypass ticking via SceneRouter.instant_mode (same pattern
#     as FtlLoop / GameState._process).
#   - Registers as "timer_system" via SaveManager.register_system.
#
# Signals:
#   timer_started(id)       — a new countdown began.
#   timer_tick(id, remaining) — fired every tick while a timer is active.
#   timer_expired(id)       — a countdown reached zero.
#   timer_cancelled(id)     — a countdown was cancelled before expiry.
#   dilation_changed(active, scale) — drama dilation engaged or released.
#   acceleration_changed(multiplier) — global acceleration changed.

signal timer_started(id: String)
signal timer_tick(id: String, remaining: float)
signal timer_expired(id: String)
signal timer_cancelled(id: String)
signal dilation_changed(active: bool, scale: float)
signal acceleration_changed(multiplier: float)

# --- Categories ---
enum Category { GENERIC, CRISIS, FTL, GATE_WINDOW, RECOVERY, STORY }

# --- Tunables ---
const DEFAULT_DIATION_SCALE: float = 0.35
const DEFAULT_ACCELERATION: float = 1.0
const CRISIS_AUTO_DILATION_THRESHOLD: float = 0.25  # 25% remaining

# --- Global acceleration multiplier ---
var _acceleration: float = DEFAULT_ACCELERATION

# --- Drama dilation state ---
var _dilation_active: bool = false
var _dilation_scale: float = DEFAULT_DIATION_SCALE
var _dilation_locks: Dictionary = {}  # key -> bool (named lock holders)

# --- Crisis auto-dilation ---
var _crisis_auto_dilation: bool = true

# --- Timer registry: id -> Dictionary ---
#   { "remaining": float, "total": float, "category": int,
#     "auto_dilate": bool, "expired": bool }
var _timers: Dictionary = {}

# --- Previous Engine.time_scale (to restore after dilation) ---
var _saved_time_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "timer_system", self)


func _process(delta: float) -> void:
	var router: Node = _autoload_node("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	var scaled_delta: float = delta * _acceleration
	var expired_ids: Array[String] = []
	for id: String in _timers.keys():
		var t: Dictionary = _timers[id]
		if t.get("expired", false) == true:
			continue
		var prev_remaining: float = float(t["remaining"])
		t["remaining"] = maxf(0.0, prev_remaining - scaled_delta)
		var remaining: float = float(t["remaining"])
		timer_tick.emit(id, remaining)
		# Crisis auto-dilation: engage when a crisis timer crosses the threshold.
		if _crisis_auto_dilation and bool(t.get("auto_dilate", false)):
			var total: float = float(t["total"])
			if total > 0.0 and remaining / total <= CRISIS_AUTO_DILATION_THRESHOLD:
				if not _dilation_active:
					_engage_dilation("crisis_" + id)
		if remaining <= 0.0:
			t["expired"] = true
			expired_ids.append(id)
	for id: String in expired_ids:
		timer_expired.emit(id)
		# Release crisis dilation lock if held.
		_release_dilation("crisis_" + id)


# --- Timer management --------------------------------------------------------

## Start a named countdown timer. Returns false if a timer with this id
## already exists and is not expired (use restart() to force).
func start_timer(id: String, duration: float, category: int = Category.GENERIC, auto_dilate: bool = false) -> bool:
	if _timers.has(id):
		var existing: Dictionary = _timers[id]
		if existing.get("expired", false) != true:
			return false
	_timers[id] = {
		"remaining": duration,
		"total": duration,
		"category": category,
		"auto_dilate": auto_dilate,
		"expired": false,
	}
	timer_started.emit(id)
	return true


## Restart or overwrite a timer with a new duration.
func restart_timer(id: String, duration: float, category: int = Category.GENERIC, auto_dilate: bool = false) -> void:
	_timers[id] = {
		"remaining": duration,
		"total": duration,
		"category": category,
		"auto_dilate": auto_dilate,
		"expired": false,
	}
	timer_started.emit(id)


## Cancel a timer before it expires. Returns true if the timer was active.
func cancel_timer(id: String) -> bool:
	if not _timers.has(id):
		return false
	var t: Dictionary = _timers[id]
	if t.get("expired", false) == true:
		return false
	_timers.erase(id)
	timer_cancelled.emit(id)
	_release_dilation("crisis_" + id)
	return true


## Remove a timer silently (no cancel signal). Used for cleanup.
func remove_timer(id: String) -> void:
	_timers.erase(id)
	_release_dilation("crisis_" + id)


## Get remaining seconds on a timer. Returns -1.0 if not found.
func remaining(id: String) -> float:
	if not _timers.has(id):
		return -1.0
	return float(_timers[id].get("remaining", 0.0))


## Get total duration of a timer. Returns -1.0 if not found.
func total(id: String) -> float:
	if not _timers.has(id):
		return -1.0
	return float(_timers[id].get("total", 0.0))


## Get the fraction remaining (0.0 to 1.0). Returns 0.0 if not found.
func fraction_remaining(id: String) -> float:
	if not _timers.has(id):
		return 0.0
	var t: Dictionary = _timers[id]
	var tot: float = float(t.get("total", 0.0))
	if tot <= 0.0:
		return 0.0
	return clampf(float(t.get("remaining", 0.0)) / tot, 0.0, 1.0)


## Check if a timer exists and is active (not expired).
func has_timer(id: String) -> bool:
	if not _timers.has(id):
		return false
	return _timers[id].get("expired", false) != true


## Check if a timer has expired (exists but reached zero).
func is_expired(id: String) -> bool:
	if not _timers.has(id):
		return false
	return _timers[id].get("expired", false) == true


## Get the category of a timer. Returns -1 if not found.
func get_category(id: String) -> int:
	if not _timers.has(id):
		return -1
	return int(_timers[id].get("category", Category.GENERIC))


## List all active timer ids.
func active_timer_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in _timers.keys():
		if _timers[id].get("expired", false) != true:
			result.append(id)
	return result


## List all timer ids (including expired).
func all_timer_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in _timers.keys():
		result.append(id)
	return result


## Force-expire a timer immediately (emits timer_expired). For tests and
## story skips.
func force_expire(id: String) -> bool:
	if not _timers.has(id):
		return false
	var t: Dictionary = _timers[id]
	if t.get("expired", false) == true:
		return false
	t["remaining"] = 0.0
	t["expired"] = true
	timer_expired.emit(id)
	_release_dilation("crisis_" + id)
	return true


# --- Time acceleration -------------------------------------------------------

## Set the global acceleration multiplier (1.0 = normal, 2.0 = double speed).
func set_acceleration(multiplier: float) -> void:
	_acceleration = maxf(0.01, multiplier)
	acceleration_changed.emit(_acceleration)


## Get the current acceleration multiplier.
func get_acceleration() -> float:
	return _acceleration


## Reset acceleration to normal.
func reset_acceleration() -> void:
	set_acceleration(DEFAULT_ACCELERATION)


# --- Drama-time dilation -----------------------------------------------------

## Engage drama dilation with a named lock. Multiple systems can hold locks;
## dilation releases only when ALL locks are released. The lowest requested
## scale among active locks is used.
func _engage_dilation(key: String, scale: float = _dilation_scale) -> void:
	_dilation_locks[key] = scale
	_apply_dilation()


## Release a named dilation lock.
func _release_dilation(key: String) -> void:
	_dilation_locks.erase(key)
	_apply_dilation()


## Recompute Engine.time_scale from active locks.
func _apply_dilation() -> void:
	var was_active: bool = _dilation_active
	if _dilation_locks.is_empty():
		_dilation_active = false
		Engine.time_scale = _saved_time_scale
		if was_active:
			dilation_changed.emit(false, 1.0)
	else:
		# Use the minimum scale among all active locks (most dramatic).
		var min_scale: float = 1.0
		for key: String in _dilation_locks.keys():
			var s: float = float(_dilation_locks[key])
			if s < min_scale:
				min_scale = s
		if not was_active:
			_saved_time_scale = Engine.time_scale
		_dilation_active = true
		_dilation_scale = min_scale
		Engine.time_scale = min_scale
		if not was_active:
			dilation_changed.emit(true, min_scale)
		else:
			dilation_changed.emit(true, min_scale)


## Manually engage drama dilation with a named lock and custom scale.
func engage_dilation(key: String, scale: float = DEFAULT_DIATION_SCALE) -> void:
	_engage_dilation(key, scale)


## Release a named dilation lock. Dilation ends when all locks are released.
func release_dilation(key: String) -> void:
	_release_dilation(key)


## Check if drama dilation is currently active.
func is_dilation_active() -> bool:
	return _dilation_active


## Get the current effective dilation scale (1.0 if not active).
func get_dilation_scale() -> float:
	if not _dilation_active:
		return 1.0
	return _dilation_scale


## Enable or disable crisis auto-dilation.
func set_crisis_auto_dilation(enabled: bool) -> void:
	_crisis_auto_dilation = enabled


## Check if crisis auto-dilation is enabled.
func is_crisis_auto_dilation_enabled() -> bool:
	return _crisis_auto_dilation


# --- FTL countdown display support -------------------------------------------

## Get the FTL countdown remaining seconds for doorway displays.
## Reads from the "ftl_countdown" timer if active, otherwise falls back
## to the GameClock-based calculation used by gate_console.gd.
func ftl_countdown_remaining() -> float:
	if has_timer("ftl_countdown"):
		return remaining("ftl_countdown")
	# Fall back to GameClock-based calculation (existing gate_console pattern).
	var gc: Node = _autoload_node("GameClock")
	if gc != null:
		var elapsed: float = float(gc.get("elapsed_seconds"))
		var gs: Node = _autoload_node("GameState")
		var total_secs: float = 3600.0  # Default FTL_COUNTDOWN_TOTAL_SECONDS
		if gs != null and gs.has_method("get") and gs.get("ftl_drop_game_time") != null:
			var drop_time: float = float(gs.get("ftl_drop_game_time"))
			if drop_time > 0.0:
				total_secs = drop_time
		return maxf(0.0, total_secs - elapsed)
	return 0.0


## Format a countdown for display (e.g. "1h 05m 30s").
func format_countdown(total_seconds: float) -> String:
	var t: int = int(maxf(0.0, total_seconds))
	var h: int = t / 3600
	var m: int = (t % 3600) / 60
	var s: int = t % 60
	return "%dh %02dm %02ds" % [h, m, s]


# --- Test hooks --------------------------------------------------------------

## Advance all timers by a fixed delta (bypasses _process, for tests).
func test_advance(delta: float) -> void:
	var scaled_delta: float = delta * _acceleration
	var expired_ids: Array[String] = []
	for id: String in _timers.keys():
		var t: Dictionary = _timers[id]
		if t.get("expired", false) == true:
			continue
		t["remaining"] = maxf(0.0, float(t["remaining"]) - scaled_delta)
		var rem: float = float(t["remaining"])
		timer_tick.emit(id, rem)
		if _crisis_auto_dilation and bool(t.get("auto_dilate", false)):
			var tot: float = float(t["total"])
			if tot > 0.0 and rem / tot <= CRISIS_AUTO_DILATION_THRESHOLD:
				if not _dilation_active:
					_engage_dilation("crisis_" + id)
		if rem <= 0.0:
			t["expired"] = true
			expired_ids.append(id)
	for id: String in expired_ids:
		timer_expired.emit(id)
		_release_dilation("crisis_" + id)


# --- Reset / Save / Load -----------------------------------------------------

func reset() -> void:
	_timers.clear()
	_acceleration = DEFAULT_ACCELERATION
	_dilation_active = false
	_dilation_scale = DEFAULT_DIATION_SCALE
	_dilation_locks.clear()
	_crisis_auto_dilation = true
	Engine.time_scale = 1.0
	_saved_time_scale = 1.0


func serialize() -> Dictionary:
	var timer_data: Dictionary = {}
	for id: String in _timers.keys():
		var t: Dictionary = _timers[id]
		timer_data[id] = {
			"remaining": float(t.get("remaining", 0.0)),
			"total": float(t.get("total", 0.0)),
			"category": int(t.get("category", Category.GENERIC)),
			"auto_dilate": bool(t.get("auto_dilate", false)),
			"expired": bool(t.get("expired", false)),
		}
	return {
		"timers": timer_data,
		"acceleration": _acceleration,
		"crisis_auto_dilation": _crisis_auto_dilation,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	reset()
	var td: Variant = data.get("timers", {})
	if td is Dictionary:
		for id: String in (td as Dictionary).keys():
			var t: Dictionary = (td as Dictionary)[id] as Dictionary
			if t == null or t.is_empty():
				continue
			_timers[id] = {
				"remaining": float(t.get("remaining", 0.0)),
				"total": float(t.get("total", 0.0)),
				"category": int(t.get("category", Category.GENERIC)),
				"auto_dilate": bool(t.get("auto_dilate", false)),
				"expired": bool(t.get("expired", false)),
			}
	_acceleration = float(data.get("acceleration", DEFAULT_ACCELERATION))
	_crisis_auto_dilation = bool(data.get("crisis_auto_dilation", true))


# --- Helpers -----------------------------------------------------------------

func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)