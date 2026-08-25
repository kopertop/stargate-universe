extends Node

# FTL core-game loop coordinator (issue #130).
#
# After Episode 1 completes (GameState.episode_completed), Destiny enters a
# repeating cycle:
#   SHIP   ~30 min ±20% real-time aboard the ship
#   JUMPING  transient — rolls the next planet spec + arms the gate window
#   PLANET   up to ~10 min gate run, managed by GameState.gate_window_active
#
# Timing is tunable: durations read from GameState.ship_phase_base_seconds() /
# GameState.planet_window_base_seconds() so #133 (Bridge) can override them
# later without touching this file.  ±20% randomization is applied HERE, atop
# whatever base resolves.
#
# State persisted via SaveManager: phase, phase_remaining, jump_count, armed.
# Planet countdown NOT duplicated — GameState.gate_window_remaining owns it.
#
# _process is gated on phase == SHIP AND NOT SceneRouter.instant_mode so
# headless smoke tests never tick the 30-min clock.

enum Phase { IDLE, SHIP, JUMPING, PLANET }

# Emitted on every phase transition so reactive systems (e.g. MusicDirector) can score
# the loop without polling. Carries the new Phase enum value.
signal phase_changed(phase: int)

# ±20 % jitter band applied to both ship and planet durations.
const JITTER: float = 0.20

var phase: int = Phase.IDLE
var phase_remaining: float = 0.0
var jump_count: int = 0
# True once the hook to GameState.episode_completed has been wired.
var _armed: bool = false  # @collection-ok: one scalar arm flag, not an enumerated set


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)  # Only tick during SHIP phase — see _begin_ship_phase / _begin_jump.
	# Register with SaveManager (autoload-tolerant: tests that run without it skip gracefully).
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "ftl_loop", self)
	# Defer hook installation so all autoloads are fully ready (mirrors
	# SaveManager._install_autosave_hooks pattern — call_deferred guarantee).
	call_deferred("_install_hooks")


func _install_hooks() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	if not gs.is_connected("episode_completed", _on_episode_completed):
		gs.connect("episode_completed", _on_episode_completed)
	if not gs.is_connected("planet_run_ended", _on_planet_run_ended):
		gs.connect("planet_run_ended", _on_planet_run_ended)
	# If we're resuming from a save that already completed the episode, re-arm
	# immediately so a mid-SHIP or mid-PLANET resume works correctly.
	if gs.get("episode_complete") == true and not _armed:
		_armed = true


# --- signal handlers ----------------------------------------------------------

func _on_episode_completed() -> void:
	if _armed:
		return
	_armed = true
	_begin_ship_phase()


func _on_planet_run_ended() -> void:
	# Only relevant when we're in the loop (PLANET phase). IDLE/SHIP/JUMPING
	# phases ignore this — the E1 path fires planet_run_ended too (recall) but
	# FtlLoop.phase is IDLE during E1, so this is a no-op.
	if phase != Phase.PLANET:
		return
	_begin_ship_phase()


# --- phase transitions --------------------------------------------------------

func _begin_ship_phase() -> void:
	phase = Phase.SHIP
	set_process(true)
	var base: float = _gs_ship_phase_base()
	phase_remaining = _jitter(base)
	var gs: Node = _autoload("GameState")
	if gs != null:
		gs.call("add_log", "Destiny is in FTL. Next gate drop in %.0f minutes." % (phase_remaining / 60.0))
	phase_changed.emit(phase)


func _begin_jump() -> void:
	phase = Phase.JUMPING
	set_process(false)  # No ticking during JUMPING / PLANET.
	jump_count += 1
	phase_changed.emit(phase)

	var gs: Node = _autoload("GameState")
	if gs != null:
		gs.call("add_log", "Destiny drops out of FTL — gate dialing. Jump #%d." % jump_count)

	# Roll next planet spec (scarcity-biased, deterministic per dial counter).
	if gs != null and gs.has_method("build_next_planet_spec"):
		gs.call("build_next_planet_spec")

	# Start the planet gate window.  start_gate_window is idempotent (first-
	# caller-wins), so calling it here before the planet scene loads means the
	# planet_timer's _biome_gate_window sees gate_window_active==true and
	# preserves our rolled duration rather than re-computing.
	var planet_window: float = _jitter(_gs_planet_window_base())
	if gs != null and gs.has_method("start_gate_window"):
		gs.call("start_gate_window", planet_window)

	# Arm the gate (post-episode branch: is_gate_open() returns true when
	# episode_complete AND gate_window_active — both are now set).
	phase = Phase.PLANET
	phase_changed.emit(phase)

	# FTL visual — skip in instant_mode (headless determinism).
	var router: Node = _autoload("SceneRouter")
	var headless: bool = router != null and router.get("instant_mode") == true
	if not headless:
		var fx: Node = load("res://scripts/ftl_drop.gd").new()
		if fx != null:
			fx.set("sound_path", "res://sounds/ftl-jump.ogg")
			get_tree().root.add_child(fx)


# --- _process -----------------------------------------------------------------

func _process(delta: float) -> void:
	if phase != Phase.SHIP:
		return
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	phase_remaining -= delta
	if phase_remaining <= 0.0:
		phase_remaining = 0.0
		_begin_jump()


# --- test hook ----------------------------------------------------------------

# Force-advance the ship phase to zero so headless tests can drive the loop
# without running a real 30-minute timer.
func _force_advance() -> void:
	if phase == Phase.SHIP:
		phase_remaining = 0.0
		_begin_jump()


# --- save / load --------------------------------------------------------------

func reset() -> void:
	phase = Phase.IDLE
	phase_remaining = 0.0
	jump_count = 0
	_armed = false
	set_process(false)


func serialize() -> Dictionary:
	return {
		"phase": phase,
		"phase_remaining": phase_remaining,
		"jump_count": jump_count,
		"armed": _armed,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	phase = int(data.get("phase", Phase.IDLE))
	# Clamp to valid enum range so a corrupt save can't stall the loop.
	if phase < Phase.IDLE or phase > Phase.PLANET:
		phase = Phase.IDLE
	phase_remaining = float(data.get("phase_remaining", 0.0))
	jump_count = int(data.get("jump_count", 0))
	_armed = data.get("armed", false) == true

	# Normalization: if we saved mid-PLANET but the window has since closed
	# (e.g. save written after recall but before phase transitioned), snap to
	# SHIP so the player doesn't get stuck.
	var gs: Node = _autoload("GameState")
	if phase == Phase.PLANET and gs != null:
		if gs.get("gate_window_active") != true:
			_begin_ship_phase()
	# Restore process state to match the deserialized phase.
	set_process(phase == Phase.SHIP)


# --- helpers ------------------------------------------------------------------

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)


func _gs_ship_phase_base() -> float:
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("ship_phase_base_seconds"):
		return float(gs.call("ship_phase_base_seconds"))
	return 1800.0


func _gs_planet_window_base() -> float:
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("planet_window_base_seconds"):
		return float(gs.call("planet_window_base_seconds"))
	return 600.0


# Apply ±JITTER randomization around a base duration.  Uses a stable RNG seeded
# from the jump count so the same jump always rolls the same duration (determinism
# for tests that call _force_advance then check phase_remaining == 0).
func _jitter(base: float) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (jump_count * 2654435761) & 0x7fffffff
	var factor: float = 1.0 + rng.randf_range(-JITTER, JITTER)
	return base * factor
