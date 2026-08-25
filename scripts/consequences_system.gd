extends Node

# Food/water consumption consequences (issue #134 consequences task).
#
# Connects ConsumptionManager to InjurySystem. When water hits zero the crew
# dehydrates: stamina drains, vision blurs below a stamina threshold, and
# sustained dehydration knocks the player out (recoverable injury). When food
# hits zero the crew starves: health drains, movement slows, and sustained
# starvation knocks the player out (recoverable injury). Emergency rationing
# kicks in when BOTH food and water are critically low: consumption rates are
# reduced and stamina regen is throttled so the ship can limp a bit longer.
#
# Data-driven: all rates and thresholds live in data/consequences.json so
# designers can tune without touching code.
#
# _process is gated on _phase_active() AND NOT SceneRouter.instant_mode so
# headless smoke tests never tick the consequences clock. Tests drive via
# simulate_seconds(s) / tick(delta) directly.
#
# The player reads state via public accessors (stamina, movement_multiplier,
# sprint_allowed, vision_blur_intensity) — player.gd polls these each
# physics frame. No hard node refs; signals keep HUD decoupled.
#
# Save registration: register_system("consequences", self) — stamina and the
# dehydration/starvation accumulators are the only state that must survive a
# save (resource counts persist in Inventory, rates/thresholds reload from
# JSON each _ready).

const CONSEQUENCES_PATH: String = "res://data/consequences.json"
const _INJURY_SCRIPT: GDScript = preload("res://scripts/injury_system.gd")

signal stamina_changed(value: float)
signal vision_blur_changed(intensity: float)
signal dehydration_warning(active: bool)
signal starvation_warning(active: bool)
signal emergency_rationing_changed(active: bool)
signal consequence_knockout(cause: int)

# --- Config (loaded from JSON) -----------------------------------------------
var _player_character_id: String = "eli"
var _stamina_max: float = 100.0
var _stamina_regen_per_sec: float = 4.0
var _stamina_sprint_drain_per_sec: float = 8.0
var _stamina_min_to_sprint: float = 15.0
var _dehydration_water_threshold: int = 0
var _dehydration_stamina_drain_per_sec: float = 2.5
var _dehydration_vision_blur_at_stamina_pct: float = 25.0
var _dehydration_knockout_severity: float = 0.5
var _starvation_food_threshold: int = 0
var _starvation_health_drain_per_sec: float = 0.8
var _starvation_slow_movement_multiplier: float = 0.6
var _starvation_knockout_severity: float = 0.5
var _emergency_water_critical: int = 3
var _emergency_food_critical: int = 3
var _emergency_consumption_multiplier: float = 0.5
var _emergency_stamina_regen_multiplier: float = 0.3

# --- Live state ---------------------------------------------------------------
# Player stamina (0–_stamina_max). Drains on sprint, regenerates at rest,
# drains faster when dehydrated.
var _stamina: float = 100.0
# Dehydration accumulation timer (seconds spent at zero water). When this
# exceeds DEHYDRATION_KNOCKOUT_SECONDS the player is knocked out.
var _dehydration_timer: float = 0.0
# Starvation accumulation timer (seconds spent at zero food). When this
# exceeds STARVATION_KNOCKOUT_SECONDS the player is knocked out.
var _starvation_timer: float = 0.0
# Cached flags to avoid re-emitting warning signals every tick.
var _dehydrated: bool = false
var _starved: bool = false
var _emergency_rationing: bool = false
# True while the player is sprinting this frame (set by tick_sprint).
var _sprinting: bool = false
# Knockout cooldown so we don't double-register after a knock-out fires.
var _knocked_out: bool = false

const DEHYDRATION_KNOCKOUT_SECONDS: float = 120.0
const STARVATION_KNOCKOUT_SECONDS: float = 300.0

var _initialized: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	_load_config()
	call_deferred("_install_hooks")


# --- config loading -----------------------------------------------------------

func _load_config() -> void:
	var f: FileAccess = FileAccess.open(CONSEQUENCES_PATH, FileAccess.READ)
	if f == null:
		push_error("ConsequencesSystem: cannot open %s" % CONSEQUENCES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ConsequencesSystem: %s did not parse to a Dictionary" % CONSEQUENCES_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_player_character_id = String(d.get("player_character_id", "eli"))
	var stamina: Dictionary = d.get("stamina", {}) as Dictionary
	_stamina_max = float(stamina.get("max", 100.0))
	_stamina_regen_per_sec = float(stamina.get("regen_per_sec", 4.0))
	_stamina_sprint_drain_per_sec = float(stamina.get("sprint_drain_per_sec", 8.0))
	_stamina_min_to_sprint = float(stamina.get("min_to_sprint", 15.0))
	var dehyd: Dictionary = d.get("dehydration", {}) as Dictionary
	_dehydration_water_threshold = int(dehyd.get("water_threshold", 0))
	_dehydration_stamina_drain_per_sec = float(dehyd.get("stamina_drain_per_sec", 2.5))
	_dehydration_vision_blur_at_stamina_pct = float(dehyd.get("vision_blur_at_stamina_pct", 25.0))
	_dehydration_knockout_severity = float(dehyd.get("knockout_severity", 0.5))
	var starv: Dictionary = d.get("starvation", {}) as Dictionary
	_starvation_food_threshold = int(starv.get("food_threshold", 0))
	_starvation_health_drain_per_sec = float(starv.get("health_drain_per_sec", 0.8))
	_starvation_slow_movement_multiplier = float(starv.get("slow_movement_multiplier", 0.6))
	_starvation_knockout_severity = float(starv.get("knockout_severity", 0.5))
	var emer: Dictionary = d.get("emergency_rationing", {}) as Dictionary
	_emergency_water_critical = int(emer.get("water_critical", 3))
	_emergency_food_critical = int(emer.get("food_critical", 3))
	_emergency_consumption_multiplier = float(emer.get("consumption_multiplier", 0.5))
	_emergency_stamina_regen_multiplier = float(emer.get("stamina_regen_multiplier", 0.3))
	_stamina = _stamina_max


# --- phase gate (mirrors ConsumptionManager) ---------------------------------

func _phase_active() -> bool:
	var loop: Node = _autoload("FtlLoop")
	if loop != null:
		if int(loop.get("phase")) == 1:
			return true
		if int(loop.get("phase")) != 0:
			return false
	var gs: Node = _autoload("GameState")
	if gs == null:
		return false
	return gs.get("episode_complete") == true


func _install_hooks() -> void:
	var loop: Node = _autoload("FtlLoop")
	if loop != null and loop.has_signal("phase_changed"):
		if not loop.is_connected("phase_changed", _reevaluate_process):
			loop.connect("phase_changed", _reevaluate_process)
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_signal("episode_completed"):
		if not gs.is_connected("episode_completed", _reevaluate_process):
			gs.connect("episode_completed", _reevaluate_process)
	_reevaluate_process()


func _reevaluate_process(_arg: Variant = null) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		set_process(false)
		return
	set_process(_phase_active())


# --- _process -----------------------------------------------------------------

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	if not _phase_active():
		return
	tick(delta)


# --- tick API (also used by tests) --------------------------------------------

# Advance consequences by `delta` seconds. Drives stamina, dehydration,
# starvation, emergency rationing, and knockout routing. Does NOT check
# instant_mode / phase (callers are responsible — _process checks both).
func tick(delta: float) -> void:
	_ensure_initialized()
	if _knocked_out:
		return
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	var water: int = int(gs.call("resource_count", "water"))
	var food: int = int(gs.call("resource_count", "food"))
	# --- Emergency rationing: both food AND water critically low ---
	var new_emergency: bool = water <= _emergency_water_critical and food <= _emergency_food_critical
	if new_emergency != _emergency_rationing:
		_emergency_rationing = new_emergency
		emergency_rationing_changed.emit(_emergency_rationing)
	# --- Dehydration: water at or below threshold (zero by default) ---
	var new_dehydrated: bool = water <= _dehydration_water_threshold
	if new_dehydrated != _dehydrated:
		_dehydrated = new_dehydrated
		dehydration_warning.emit(_dehydrated)
	# --- Starvation: food at or below threshold (zero by default) ---
	var new_starved: bool = food <= _starvation_food_threshold
	if new_starved != _starved:
		_starved = new_starved
		starvation_warning.emit(_starved)
	# --- Stamina regen / drain ---
	var regen: float = _stamina_regen_per_sec
	if _emergency_rationing:
		regen *= _emergency_stamina_regen_multiplier
	if _dehydrated:
		# Dehydration drains stamina on top of any sprint drain.
		_stamina = clampf(_stamina - _dehydration_stamina_drain_per_sec * delta, 0.0, _stamina_max)
	else:
		# No sprint drain here when dehydrated — sprint is gated by stamina.
		if _sprinting:
			_stamina = clampf(_stamina - _stamina_sprint_drain_per_sec * delta, 0.0, _stamina_max)
		else:
			_stamina = clampf(_stamina + regen * delta, 0.0, _stamina_max)
	stamina_changed.emit(_stamina)
	# --- Vision blur from dehydration (intensity 0..1 based on stamina) ---
	if _dehydrated:
		var blur_threshold: float = _dehydration_vision_blur_at_stamina_pct
		var blur_value: float = clampf(1.0 - (_stamina / maxf(blur_threshold, 1.0)), 0.0, 1.0)
		vision_blur_changed.emit(blur_value)
	else:
		vision_blur_changed.emit(0.0)
	# --- Starvation health drain ---
	if _starved:
		if gs.has_method("damage"):
			gs.call("damage", _starvation_health_drain_per_sec * delta)
	# --- Accumulate timers toward knockout ---
	if _dehydrated:
		_dehydration_timer += delta
		if _dehydration_timer >= DEHYDRATION_KNOCKOUT_SECONDS:
			_trigger_knockout(_INJURY_SCRIPT.InjuryCause.DEHYDRATION, _dehydration_knockout_severity)
			return
	else:
		_dehydration_timer = maxf(0.0, _dehydration_timer - delta * 0.5)
	if _starved:
		_starvation_timer += delta
		if _starvation_timer >= STARVATION_KNOCKOUT_SECONDS:
			_trigger_knockout(_INJURY_SCRIPT.InjuryCause.STARVATION, _starvation_knockout_severity)
			return
	else:
		_starvation_timer = maxf(0.0, _starvation_timer - delta * 0.5)


# --- sprint input (player.gd calls this each physics frame) -------------------

# Set whether the player is actively sprinting this frame. The tick loop uses
# this to drain stamina. Passing false at rest lets stamina regenerate.
func tick_sprint(is_sprinting: bool) -> void:
	_sprinting = is_sprinting


# --- public accessors (player.gd + HUD read these) ---------------------------

func stamina() -> float:
	return _stamina

func stamina_pct() -> float:
	return clampf(_stamina / maxf(_stamina_max, 1.0) * 100.0, 0.0, 100.0)

func stamina_max() -> float:
	return _stamina_max

# True if the player has enough stamina to start / continue sprinting.
func sprint_allowed() -> bool:
	return _stamina >= _stamina_min_to_sprint

func is_dehydrated() -> bool:
	return _dehydrated

func is_starved() -> bool:
	return _starved

func is_emergency_rationing() -> bool:
	return _emergency_rationing

# Movement speed multiplier. Starvation slows movement; dehydration alone does
# not (it hits stamina instead). Emergency rationing does not slow movement.
func movement_multiplier() -> float:
	if _starved:
		return _starvation_slow_movement_multiplier
	return 1.0

# Vision blur intensity 0..1 for the HUD/post-process. Only non-zero when
# dehydrated and stamina has dropped below the blur threshold.
func vision_blur_intensity() -> float:
	if not _dehydrated:
		return 0.0
	var blur_threshold: float = _dehydration_vision_blur_at_stamina_pct
	return clampf(1.0 - (_stamina / maxf(blur_threshold, 1.0)), 0.0, 1.0)

# Emergency-rationing consumption multiplier for ConsumptionManager to apply
# to its per-cycle rates. Returns 1.0 when rationing is inactive.
func consumption_multiplier() -> float:
	if _emergency_rationing:
		return _emergency_consumption_multiplier
	return 1.0


# --- knockout routing ---------------------------------------------------------

func _trigger_knockout(cause: int, severity: float) -> void:
	if _knocked_out:
		return
	_knocked_out = true
	consequence_knockout.emit(cause)
	var isys: Node = _autoload("InjurySystem")
	if isys != null and isys.has_method("register_injury"):
		isys.call("register_injury", _player_character_id, cause, severity)
	# Reset the timer that fired so a post-recovery run starts clean.
	if cause == _INJURY_SCRIPT.InjuryCause.DEHYDRATION:
		_dehydration_timer = 0.0
	elif cause == _INJURY_SCRIPT.InjuryCause.STARVATION:
		_starvation_timer = 0.0
	set_process(false)


# --- recovery (called by MedBay / InjurySystem on recovery_complete) ---------

# Clear the knockout flag and re-arm process ticking. Called when the player
# recovers from a dehydration/starvation injury so consequences resume.
func on_recovery(character_id: String) -> void:
	if character_id != _player_character_id:
		return
	_knocked_out = false
	_dehydration_timer = 0.0
	_starvation_timer = 0.0
	_stamina = _stamina_max
	stamina_changed.emit(_stamina)
	_reevaluate_process()


# --- helpers ------------------------------------------------------------------

func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "consequences", self)
	# Wire recovery_complete so the knockout flag clears after MedBay recovery.
	var isys: Node = _autoload("InjurySystem")
	if isys != null and isys.has_signal("recovery_complete"):
		if not isys.is_connected("recovery_complete", on_recovery):
			isys.connect("recovery_complete", on_recovery)


func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)


# --- deterministic test helpers -----------------------------------------------

func simulate_seconds(seconds: float) -> void:
	tick(seconds)

# Set stamina directly (tests / debug). Clamps to [0, max].
func set_stamina(v: float) -> void:
	_stamina = clampf(v, 0.0, _stamina_max)
	stamina_changed.emit(_stamina)


# --- reset / save / load ------------------------------------------------------

func reset() -> void:
	_stamina = _stamina_max
	_dehydration_timer = 0.0
	_starvation_timer = 0.0
	_dehydrated = false
	_starved = false
	_emergency_rationing = false
	_sprinting = false
	_knocked_out = false
	set_process(false)


func serialize() -> Dictionary:
	return {
		"stamina": _stamina,
		"dehydration_timer": _dehydration_timer,
		"starvation_timer": _starvation_timer,
		"dehydrated": _dehydrated,
		"starved": _starved,
		"emergency_rationing": _emergency_rationing,
		"knocked_out": _knocked_out,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_stamina = clampf(float(data.get("stamina", _stamina_max)), 0.0, _stamina_max)
	_dehydration_timer = float(data.get("dehydration_timer", 0.0))
	_starvation_timer = float(data.get("starvation_timer", 0.0))
	_dehydrated = bool(data.get("dehydrated", false))
	_starved = bool(data.get("starved", false))
	_emergency_rationing = bool(data.get("emergency_rationing", false))
	_knocked_out = bool(data.get("knocked_out", false))