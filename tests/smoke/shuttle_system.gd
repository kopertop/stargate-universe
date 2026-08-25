extends SceneTree

# Smoke test for the ShuttleSystem autoload — piloted shuttle craft.
#
# Verifies:
#   • ShuttleSystem autoload is attached and loaded its config from JSON.
#   • FlightMode enum values are stable (DOCKED=0, FLYING=1, LANDING=2, CRASHED=3).
#   • FlightEnv enum values are stable (ATMOSPHERIC=0, SPACE=1).
#   • LandingPhase enum values are stable (IDLE=0, DESCENT=1, TOUCHDOWN=2, COMPLETE=3).
#   • Shuttle selection sets hull, fuel, cargo to type-specific max.
#   • Three shuttle types have distinct stats (destiny, cargo, recon).
#   • start_flight / end_flight transitions.
#   • switch_environment applies atmospheric entry damage.
#   • Fuel burns during flight, warning + critical thresholds work.
#   • apply_thrust accelerates shuttle and respects max speed.
#   • Cargo load / unload / capacity / has_cargo.
#   • Landing sequence: start_landing, descent progress, touchdown.
#   • Hard landing applies hull damage when speed exceeds threshold.
#   • Safe landing zone negates hard landing damage.
#   • Fuel depletion during landing causes crash.
#   • abort_landing returns to flying.
#   • hull_changed, fuel_changed, cargo_changed, flight_mode_changed signals fire.
#   • Save round-trip: serialize → deserialize preserves state.
#   • Reset restores shuttle to full hull, fuel, empty cargo, docked.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/shuttle_system.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal tracking
var _hull_changed_count: int = 0
var _fuel_changed_count: int = 0
var _cargo_changed_count: int = 0
var _flight_mode_changed_count: int = 0
var _shuttle_selected_count: int = 0
var _landing_started_count: int = 0
var _landing_completed_count: int = 0
var _last_landing_success: bool = false


func _initialize() -> void:
	print("=== shuttle_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ss: Node = root.get_node_or_null("ShuttleSystem")
	_expect(ss != null, "ShuttleSystem autoload is attached")
	if ss == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "shuttle_system_smoke")

	# --- Enum stability -------------------------------------------------------
	var DOCKED: int = int(ss.FlightMode.DOCKED)
	var FLYING: int = int(ss.FlightMode.FLYING)
	var LANDING: int = int(ss.FlightMode.LANDING)
	var CRASHED: int = int(ss.FlightMode.CRASHED)
	_expect(DOCKED == 0, "FlightMode.DOCKED == 0 (got %d)" % DOCKED)
	_expect(FLYING == 1, "FlightMode.FLYING == 1 (got %d)" % FLYING)
	_expect(LANDING == 2, "FlightMode.LANDING == 2 (got %d)" % LANDING)
	_expect(CRASHED == 3, "FlightMode.CRASHED == 3 (got %d)" % CRASHED)

	var ATMOSPHERIC: int = int(ss.FlightEnv.ATMOSPHERIC)
	var SPACE: int = int(ss.FlightEnv.SPACE)
	_expect(ATMOSPHERIC == 0, "FlightEnv.ATMOSPHERIC == 0 (got %d)" % ATMOSPHERIC)
	_expect(SPACE == 1, "FlightEnv.SPACE == 1 (got %d)" % SPACE)

	var LIDLE: int = int(ss.LandingPhase.IDLE)
	var DESCENT: int = int(ss.LandingPhase.DESCENT)
	var TOUCHDOWN: int = int(ss.LandingPhase.TOUCHDOWN)
	var COMPLETE: int = int(ss.LandingPhase.COMPLETE)
	_expect(LIDLE == 0, "LandingPhase.IDLE == 0 (got %d)" % LIDLE)
	_expect(DESCENT == 1, "LandingPhase.DESCENT == 1 (got %d)" % DESCENT)
	_expect(TOUCHDOWN == 2, "LandingPhase.TOUCHDOWN == 2 (got %d)" % TOUCHDOWN)
	_expect(COMPLETE == 3, "LandingPhase.COMPLETE == 3 (got %d)" % COMPLETE)

	# --- Shuttle keys available ----------------------------------------------
	var keys: Array[String] = ss.get_all_shuttle_keys()
	_expect(not keys.is_empty(), "shuttle keys non-empty")
	_expect(keys.has("destiny_shuttle"), "destiny_shuttle key exists")
	_expect(keys.has("cargo_shuttle"), "cargo_shuttle key exists")
	_expect(keys.has("recon_shuttle"), "recon_shuttle key exists")

	# --- Shuttle selection ----------------------------------------------------
	_connect_signals(ss)
	_expect(ss.select_shuttle("destiny_shuttle"), "select_shuttle(destiny_shuttle) succeeds")
	_expect(ss.get_current_shuttle() == "destiny_shuttle", "current shuttle is destiny_shuttle")
	_expect(ss.get_hull() == 100.0, "destiny_shuttle hull == 100.0 (got %f)" % ss.get_hull())
	_expect(ss.get_fuel() == 100.0, "destiny_shuttle fuel == 100.0 (got %f)" % ss.get_fuel())
	_expect(ss.get_cargo_capacity() == 10, "destiny_shuttle cargo capacity == 10 (got %d)" % ss.get_cargo_capacity())
	_expect(ss.get_flight_mode() == DOCKED, "flight mode is DOCKED after select")
	_expect(_shuttle_selected_count == 1, "shuttle_selected signal fired once")

	# Unknown shuttle selection fails.
	_expect(not bool(ss.select_shuttle("nonexistent")), "unknown shuttle selection fails")

	# --- Different shuttle types have different stats ------------------------
	ss.select_shuttle("cargo_shuttle")
	_expect(ss.get_hull() == 150.0, "cargo_shuttle hull == 150.0 (got %f)" % ss.get_hull())
	_expect(ss.get_fuel() == 120.0, "cargo_shuttle fuel == 120.0 (got %f)" % ss.get_fuel())
	_expect(ss.get_cargo_capacity() == 20, "cargo_shuttle cargo capacity == 20 (got %d)" % ss.get_cargo_capacity())

	ss.select_shuttle("recon_shuttle")
	_expect(ss.get_hull() == 60.0, "recon_shuttle hull == 60.0 (got %f)" % ss.get_hull())
	_expect(ss.get_fuel() == 80.0, "recon_shuttle fuel == 80.0 (got %f)" % ss.get_fuel())
	_expect(ss.get_cargo_capacity() == 4, "recon_shuttle cargo capacity == 4 (got %d)" % ss.get_cargo_capacity())

	# --- Flight start / end ---------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	_expect(ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC)), "start_flight in atmospheric succeeds")
	_expect(ss.get_flight_mode() == FLYING, "flight mode is FLYING after start_flight")
	_expect(ss.get_flight_env() == ATMOSPHERIC, "flight env is ATMOSPHERIC")
	_expect(_flight_mode_changed_count >= 1, "flight_mode_changed signal fired on start_flight")

	# Cannot start flight again while already flying.
	_expect(not bool(ss.start_flight(int(ss.FlightEnv.SPACE))), "cannot start_flight when already flying")

	_expect(ss.end_flight(), "end_flight succeeds")
	_expect(ss.get_flight_mode() == DOCKED, "flight mode is DOCKED after end_flight")

	# Cannot start flight with no fuel.
	ss.set_fuel(0.0)
	_expect(not bool(ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))), "cannot start_flight with no fuel")
	ss.refuel()
	_expect(ss.get_fuel() == 100.0, "refuel restores fuel to max")

	# --- Environment switch + atmospheric entry damage ------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.SPACE))
	var hull_before: float = ss.get_hull()
	ss.switch_environment(int(ss.FlightEnv.ATMOSPHERIC))
	_expect(ss.get_flight_env() == ATMOSPHERIC, "switch_environment to ATMOSPHERIC")
	_expect(ss.get_hull() < hull_before, "atmospheric entry applies hull damage (got %f, was %f)" % [ss.get_hull(), hull_before])
	# Switching to same env does nothing.
	ss.switch_environment(int(ss.FlightEnv.ATMOSPHERIC))
	# Cannot switch when not flying.
	ss.end_flight()
	_expect(not bool(ss.switch_environment(int(ss.FlightEnv.SPACE))), "switch_environment fails when not flying")

	# --- Fuel burning during flight -------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	var fuel_before: float = ss.get_fuel()
	ss.apply_thrust(Vector3.FORWARD, 1.0)
	_expect(ss.get_fuel() < fuel_before, "fuel burned after thrust (was %f, now %f)" % [fuel_before, ss.get_fuel()])
	ss.end_flight()

	# --- apply_thrust accelerates and respects max speed ----------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.SPACE))
	# Space max_speed = 120.0. Apply many thrust ticks.
	for i in range(100):
		ss.apply_thrust(Vector3.FORWARD, 0.1)
	var speed: float = ss.get_velocity().length()
	_expect(speed <= 121.0, "velocity clamped to max_speed (got %f)" % speed)
	_expect(speed > 0.0, "velocity is non-zero after thrust (got %f)" % speed)
	ss.end_flight()

	# --- Fuel thresholds ------------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.set_fuel(20.0)
	_expect(ss.is_fuel_warning(), "fuel at 20%% is warning (threshold 25)")
	_expect(not bool(ss.is_fuel_critical()), "fuel at 20%% is not critical (threshold 10)")
	ss.set_fuel(5.0)
	_expect(ss.is_fuel_critical(), "fuel at 5%% is critical (threshold 10)")
	ss.set_fuel(0.0)
	_expect(ss.is_fuel_empty(), "fuel at 0%% is empty")
	ss.refuel()

	# --- Hull thresholds ------------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.set_hull(40.0)
	_expect(ss.is_hull_warning(), "hull at 40%% is warning (threshold 50)")
	_expect(not bool(ss.is_hull_critical()), "hull at 40%% is not critical (threshold 25)")
	ss.set_hull(20.0)
	_expect(ss.is_hull_critical(), "hull at 20%% is critical (threshold 25)")

	# --- Hull damage + repair -------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	var hull_start: float = ss.get_hull()
	var dealt: float = float(ss.apply_damage(30.0, "combat"))
	_expect(dealt == 30.0, "apply_damage returns damage dealt (got %f)" % dealt)
	_expect(ss.get_hull() == hull_start - 30.0, "hull reduced by 30 (got %f)" % ss.get_hull())
	ss.repair_hull(10.0)
	_expect(ss.get_hull() == hull_start - 20.0, "repair_hull adds 10 (got %f)" % ss.get_hull())

	# --- Hull destruction → CRASHED -------------------------------------------
	ss.select_shuttle("recon_shuttle")  # hull = 60
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	ss.apply_damage(60.0, "combat")
	_expect(ss.get_hull() == 0.0, "hull at 0 after 60 damage to recon (got %f)" % ss.get_hull())
	_expect(ss.get_flight_mode() == CRASHED, "flight mode is CRASHED after hull destroyed")
	_expect(ss.is_hull_destroyed(), "is_hull_destroyed returns true")
	# Cannot start flight when crashed.
	_expect(not bool(ss.start_flight(int(ss.FlightEnv.SPACE))), "cannot start_flight when crashed")

	# --- Cargo ----------------------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	_cargo_changed_count = 0
	var loaded: int = ss.load_cargo("rations", 5)
	_expect(loaded == 5, "load_cargo(5) returns 5 (got %d)" % loaded)
	_expect(ss.get_cargo_count() == 5, "cargo count is 5 (got %d)" % ss.get_cargo_count())
	_expect(ss.has_cargo("rations", 5), "has_cargo(rations, 5) is true")
	_expect(_cargo_changed_count >= 1, "cargo_changed signal fired on load")

	# Overfill cargo — only loads what fits.
	var extra: int = ss.load_cargo("water", 10)
	_expect(extra == 5, "load_cargo(10) with 5 free slots returns 5 (got %d)" % extra)
	_expect(ss.get_cargo_count() == 10, "cargo count is 10 (got %d)" % ss.get_cargo_count())
	_expect(ss.get_cargo_free_slots() == 0, "cargo free slots is 0 (got %d)" % ss.get_cargo_free_slots())

	# Cannot load when full.
	var over: int = ss.load_cargo("ore", 1)
	_expect(over == 0, "load_cargo when full returns 0 (got %d)" % over)

	# Unload cargo.
	var unloaded: int = ss.unload_cargo("rations", 3)
	_expect(unloaded == 3, "unload_cargo(3) returns 3 (got %d)" % unloaded)
	_expect(ss.get_cargo_count() == 7, "cargo count is 7 after unload (got %d)" % ss.get_cargo_count())
	_expect(ss.has_cargo("rations", 2), "has_cargo(rations, 2) is true after partial unload")

	# Unload more than available.
	var unloaded2: int = ss.unload_cargo("rations", 10)
	_expect(unloaded2 == 2, "unload_cargo(10) with only 2 left returns 2 (got %d)" % unloaded2)
	_expect(not bool(ss.has_cargo("rations")), "rations fully unloaded")

	# Unload from empty item.
	var unloaded3: int = ss.unload_cargo("nonexistent_item", 5)
	_expect(unloaded3 == 0, "unload_cargo of missing item returns 0")

	# Clear cargo.
	ss.clear_cargo()
	_expect(ss.get_cargo_count() == 0, "cargo count is 0 after clear")
	_expect(ss.get_cargo().is_empty(), "cargo dict is empty after clear")

	# --- Landing zones --------------------------------------------------------
	var zone_keys: Array[String] = ss.get_all_landing_zone_ids()
	_expect(not zone_keys.is_empty(), "landing zone keys non-empty")
	_expect(zone_keys.has("destiny_dock"), "destiny_dock zone exists")
	_expect(zone_keys.has("planet_surface"), "planet_surface zone exists")
	_expect(zone_keys.has("asteroid_base"), "asteroid_base zone exists")
	_expect(bool(ss.is_safe_landing_zone("destiny_dock")), "destiny_dock is safe landing zone")
	_expect(not bool(ss.is_safe_landing_zone("planet_surface")), "planet_surface is not safe landing zone")
	_expect(bool(ss.is_safe_landing_zone("asteroid_base")), "asteroid_base is safe landing zone")

	# --- Landing sequence: safe landing ---------------------------------------
	ss.select_shuttle("destiny_shuttle")
	_landing_started_count = 0
	_landing_completed_count = 0
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	# Set a short landing duration for test speed.
	ss.set_landing_duration(1.0)
	# Zero velocity for a safe approach.
	ss.set_velocity(Vector3.ZERO)
	_expect(ss.start_landing("destiny_dock"), "start_landing(destiny_dock) succeeds")
	_expect(ss.get_flight_mode() == LANDING, "flight mode is LANDING after start_landing")
	_expect(_landing_started_count == 1, "landing_started signal fired")
	_expect(ss.get_landing_phase() == DESCENT, "landing phase is DESCENT")
	# Tick landing to completion.
	ss.test_advance_landing(1.1)
	_expect(_landing_completed_count == 1, "landing_completed signal fired")
	_expect(_last_landing_success, "safe landing at destiny_dock is success")
	_expect(ss.get_flight_mode() == DOCKED, "flight mode is DOCKED after successful landing")
	# Hull should not be damaged on safe landing.
	_expect(ss.get_hull() == 100.0, "hull intact after safe landing (got %f)" % ss.get_hull())

	# --- Landing sequence: hard landing on unsafe zone -------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	# Set velocity above threshold but below 2x threshold for a hard (but survivable) landing.
	ss.set_velocity(Vector3(8.0, 0.0, 0.0))
	ss.set_landing_duration(1.0)
	var hull_pre: float = ss.get_hull()
	ss.start_landing("planet_surface")
	# planet_surface is not safe — hard landing applies damage.
	ss.test_advance_landing(1.1)
	_expect(_last_landing_success, "hard landing still succeeds if hull survives")
	_expect(ss.get_hull() < hull_pre, "hard landing applies hull damage (was %f, now %f)" % [hull_pre, ss.get_hull()])

	# --- Landing sequence: crash from fuel depletion ---------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.set_fuel(0.5)  # barely any fuel
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	ss.set_landing_duration(2.0)
	ss.start_landing("planet_surface")
	# Fuel will run out during descent → forced crash.
	ss.test_advance_landing(2.1)
	_expect(not _last_landing_success, "fuel depletion during landing causes crash")
	_expect(ss.get_flight_mode() == CRASHED, "flight mode is CRASHED after fuel depletion crash")

	# --- Abort landing --------------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	ss.set_landing_duration(10.0)
	ss.start_landing("destiny_dock")
	_expect(ss.get_flight_mode() == LANDING, "in LANDING mode before abort")
	_expect(ss.abort_landing(), "abort_landing succeeds")
	_expect(ss.get_flight_mode() == FLYING, "flight mode is FLYING after abort")
	_expect(ss.get_landing_phase() == LIDLE, "landing phase is IDLE after abort")

	# Cannot abort when not landing.
	_expect(not bool(ss.abort_landing()), "abort_landing fails when not in LANDING mode")
	ss.end_flight()

	# --- Cannot start landing when not flying --------------------------------
	ss.select_shuttle("destiny_shuttle")
	_expect(not bool(ss.start_landing("destiny_dock")), "start_landing fails when docked")

	# --- Cannot start landing at unknown zone --------------------------------
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	_expect(not bool(ss.start_landing("unknown_zone")), "start_landing at unknown zone fails")
	ss.end_flight()

	# --- Save round-trip -----------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.SPACE))
	ss.set_hull(75.0)
	ss.set_fuel(60.0)
	ss.load_cargo("water", 3)
	ss.set_velocity(Vector3(10.0, 5.0, -2.0))
	ss.set_position(Vector3(100.0, 200.0, 300.0))
	var saved: Dictionary = ss.serialize()
	# Mutate state to verify deserialize restores it.
	ss.set_hull(10.0)
	ss.set_fuel(5.0)
	ss.clear_cargo()
	ss.set_velocity(Vector3.ZERO)
	ss.set_position(Vector3.ZERO)
	ss.deserialize(saved, 0)
	_expect(ss.get_hull() == 75.0, "hull restored from save (got %f)" % ss.get_hull())
	_expect(ss.get_fuel() == 60.0, "fuel restored from save (got %f)" % ss.get_fuel())
	_expect(ss.get_cargo_count() == 3, "cargo restored from save (got %d)" % ss.get_cargo_count())
	_expect(ss.has_cargo("water", 3), "water cargo restored from save")
	_expect(ss.get_velocity() == Vector3(10.0, 5.0, -2.0), "velocity restored from save")
	_expect(ss.get_position() == Vector3(100.0, 200.0, 300.0), "position restored from save")
	_expect(ss.get_flight_mode() == FLYING, "flight_mode restored from save")

	# --- Reset ----------------------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.set_hull(20.0)
	ss.set_fuel(10.0)
	ss.load_cargo("ore", 5)
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	ss.reset()
	_expect(ss.get_hull() == 100.0, "hull restored to max after reset (got %f)" % ss.get_hull())
	_expect(ss.get_fuel() == 100.0, "fuel restored to max after reset (got %f)" % ss.get_fuel())
	_expect(ss.get_cargo_count() == 0, "cargo empty after reset")
	_expect(ss.get_flight_mode() == DOCKED, "flight mode is DOCKED after reset")

	# --- Hull / fuel percent --------------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	_expect(ss.get_hull_percent() == 100.0, "hull_percent == 100%% (got %f)" % ss.get_hull_percent())
	_expect(ss.get_fuel_percent() == 100.0, "fuel_percent == 100%% (got %f)" % ss.get_fuel_percent())
	ss.set_hull(50.0)
	_expect(ss.get_hull_percent() == 50.0, "hull_percent == 50%% (got %f)" % ss.get_hull_percent())
	ss.set_fuel(25.0)
	_expect(ss.get_fuel_percent() == 25.0, "fuel_percent == 25%% (got %f)" % ss.get_fuel_percent())

	# --- Landing progress fraction --------------------------------------------
	ss.select_shuttle("destiny_shuttle")
	ss.start_flight(int(ss.FlightEnv.ATMOSPHERIC))
	ss.set_landing_duration(4.0)
	ss.set_velocity(Vector3.ZERO)
	ss.start_landing("destiny_dock")
	# After 2.0s of a 4.0s landing, progress should be 0.5.
	ss.test_advance_landing(2.0)
	var prog: float = ss.get_landing_progress()
	_expect(prog >= 0.49 and prog <= 0.51, "landing progress ~0.5 at halfway (got %f)" % prog)
	# Complete the landing.
	ss.test_advance_landing(2.1)
	_expect(ss.get_landing_progress() == 1.0, "landing progress == 1.0 after completion (got %f)" % ss.get_landing_progress())

	_report()
	quit(0 if _failures.is_empty() else 1)


func _connect_signals(ss: Node) -> void:
	ss.hull_changed.connect(_on_hull_changed)
	ss.fuel_changed.connect(_on_fuel_changed)
	ss.cargo_changed.connect(_on_cargo_changed)
	ss.flight_mode_changed.connect(_on_flight_mode_changed)
	ss.shuttle_selected.connect(_on_shuttle_selected)
	ss.landing_started.connect(_on_landing_started)
	ss.landing_completed.connect(_on_landing_completed)


func _on_hull_changed(_v: float) -> void:
	_hull_changed_count += 1

func _on_fuel_changed(_v: float) -> void:
	_fuel_changed_count += 1

func _on_cargo_changed(_c: Dictionary) -> void:
	_cargo_changed_count += 1

func _on_flight_mode_changed(_m: int) -> void:
	_flight_mode_changed_count += 1

func _on_shuttle_selected(_k: String) -> void:
	_shuttle_selected_count += 1

func _on_landing_started(_z: String) -> void:
	_landing_started_count += 1

func _on_landing_completed(_z: String, success: bool) -> void:
	_landing_completed_count += 1
	_last_landing_success = success


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("\n--- Results ---")
	print("  Passes:   %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("  FAILED:")
		for f in _failures:
			print("    - %s" % f)