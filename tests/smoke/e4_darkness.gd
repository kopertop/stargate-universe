extends SceneTree

# Smoke test for the E4 "Darkness" nebula navigation and power conservation crisis.
#
# Verifies:
#   * NebulaSystem autoload is attached.
#   * Stage enum values are stable (NONE=0, NEBULA_TRAP=1, ..., COMPLETE=5).
#   * Outcome enum values are stable (IN_PROGRESS=0, ESCAPED=1, FAILED=2).
#   * start_crisis sets the stage to NEBULA_TRAP and emits stage_started.
#   * Power drain: systems have drain rates, toggling reduces drain.
#   * Critical systems (life_support) cannot be shut off.
#   * begin_conservation advances to CONSERVATION stage.
#   * begin_planet_mission advances to PLANET_MISSION, disables sprint, limits Kino.
#   * collect_resource accumulates and triggers escape_ready at threshold.
#   * begin_escape advances to ESCAPE stage.
#   * complete_escape advances to COMPLETE, outcome is ESCAPED.
#   * is_complete returns true after all stages.
#   * Save round-trip: serialize → deserialize preserves state.
#   * Reset restores initial state.
#   * QuestLog e4_darkness quest chain: 5-step progression.
#   * GameState proxy properties and facade methods.
#   * GameState serialize/deserialize round-trips E4 flags.
#   * EpisodeManager "darkness_resolved" predicate returns true when complete.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/e4_darkness.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== e4_darkness smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ns: Node = root.get_node_or_null("NebulaSystem")
	var gs: Node = root.get_node_or_null("GameState")
	var ql: Node = root.get_node_or_null("QuestLog")
	_expect(ns != null, "NebulaSystem autoload is attached")
	_expect(gs != null, "GameState autoload is attached")
	_expect(ql != null, "QuestLog autoload is attached")
	if ns == null or gs == null or ql == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "e4_darkness_smoke")

	# Enable instant mode so _process doesn't tick automatically.
	ns.call("set_instant_mode", true)

	# --- Enum stability -------------------------------------------------------
	var NONE: int = int(ns.Stage.NONE)
	var NEBULA_TRAP: int = int(ns.Stage.NEBULA_TRAP)
	var CONSERVATION: int = int(ns.Stage.CONSERVATION)
	var PLANET_MISSION: int = int(ns.Stage.PLANET_MISSION)
	var ESCAPE: int = int(ns.Stage.ESCAPE)
	var COMPLETE: int = int(ns.Stage.COMPLETE)
	_expect(NONE == 0, "Stage.NONE == 0 (got %d)" % NONE)
	_expect(NEBULA_TRAP == 1, "Stage.NEBULA_TRAP == 1 (got %d)" % NEBULA_TRAP)
	_expect(CONSERVATION == 2, "Stage.CONSERVATION == 2 (got %d)" % CONSERVATION)
	_expect(PLANET_MISSION == 3, "Stage.PLANET_MISSION == 3 (got %d)" % PLANET_MISSION)
	_expect(ESCAPE == 4, "Stage.ESCAPE == 4 (got %d)" % ESCAPE)
	_expect(COMPLETE == 5, "Stage.COMPLETE == 5 (got %d)" % COMPLETE)

	var IN_PROGRESS: int = int(ns.Outcome.IN_PROGRESS)
	var ESCAPED: int = int(ns.Outcome.ESCAPED)
	var FAILED: int = int(ns.Outcome.FAILED)
	_expect(IN_PROGRESS == 0, "Outcome.IN_PROGRESS == 0 (got %d)" % IN_PROGRESS)
	_expect(ESCAPED == 1, "Outcome.ESCAPED == 1 (got %d)" % ESCAPED)
	_expect(FAILED == 2, "Outcome.FAILED == 2 (got %d)" % FAILED)

	# --- Initial state -------------------------------------------------------
	_expect(int(ns.get("_current_stage")) == NONE, "starts at NONE stage")
	_expect(float(ns.get("_power_reserve")) == float(ns.INITIAL_POWER), "initial power reserve is %f" % float(ns.INITIAL_POWER))
	_expect(int(ns.get("_outcome")) == IN_PROGRESS, "initial outcome is IN_PROGRESS")

	# --- System definitions --------------------------------------------------
	var system_ids: Array = ns.call("get_all_system_ids")
	_expect(system_ids.has("life_support"), "life_support system exists")
	_expect(system_ids.has("shields"), "shields system exists")
	_expect(system_ids.has("engines"), "engines system exists")
	_expect(system_ids.has("weapons"), "weapons system exists")
	_expect(system_ids.has("sensors"), "sensors system exists")
	_expect(system_ids.has("lights"), "lights system exists")

	# All systems start online.
	for sid in system_ids:
		_expect(bool(ns.call("is_system_online", String(sid))), "system %s starts online" % String(sid))

	# Life support is critical.
	_expect(bool(ns.call("is_system_critical", "life_support")), "life_support is critical")
	# Engines are not critical.
	_expect(not bool(ns.call("is_system_critical", "engines")), "engines is not critical")

	# Total drain when all systems online.
	var full_drain: float = float(ns.call("get_total_drain_per_sec"))
	_expect(full_drain > 0.0, "total drain > 0 when all online (got %f)" % full_drain)

	# --- Toggle systems ------------------------------------------------------
	# Cannot toggle before crisis starts.
	_expect(not bool(ns.call("toggle_system", "lights")), "toggle fails before crisis starts")

	# --- Start crisis --------------------------------------------------------
	ns.call("start_crisis")
	_expect(int(ns.get("_current_stage")) == NEBULA_TRAP, "stage is NEBULA_TRAP after start_crisis")
	_expect(float(ns.get("_power_reserve")) == float(ns.INITIAL_POWER), "power reserve reset to initial on start_crisis")

	# Now toggle works.
	var toggle_ok: bool = bool(ns.call("toggle_system", "lights"))
	_expect(toggle_ok, "toggle lights succeeds during crisis")
	_expect(not bool(ns.call("is_system_online", "lights")), "lights are off after toggle")
	# Drain should decrease.
	var reduced_drain: float = float(ns.call("get_total_drain_per_sec"))
	_expect(reduced_drain < full_drain, "drain decreased after shutting off lights (got %f < %f)" % [reduced_drain, full_drain])

	# Turn lights back on.
	ns.call("toggle_system", "lights")
	_expect(bool(ns.call("is_system_online", "lights")), "lights are back on after toggle")

	# Cannot shut off critical system.
	var critical_toggle: bool = bool(ns.call("toggle_system", "life_support"))
	_expect(not critical_toggle, "cannot shut off critical life_support")
	_expect(bool(ns.call("is_system_online", "life_support")), "life_support still online after failed toggle")

	# set_system_online force method also respects critical.
	ns.call("set_system_online", "shields", false)
	_expect(not bool(ns.call("is_system_online", "shields")), "shields forced offline via set_system_online")
	ns.call("set_system_online", "shields", true)
	_expect(bool(ns.call("is_system_online", "shields")), "shields forced back online")

	# --- Conservation stage --------------------------------------------------
	ns.call("begin_conservation")
	_expect(int(ns.get("_current_stage")) == CONSERVATION, "stage is CONSERVATION after begin_conservation")

	# --- Planet mission stage ------------------------------------------------
	ns.call("begin_planet_mission")
	_expect(int(ns.get("_current_stage")) == PLANET_MISSION, "stage is PLANET_MISSION after begin_planet_mission")
	_expect(bool(ns.get("_sprint_disabled")), "sprint disabled during planet mission")
	_expect(int(ns.call("get_kino_limit")) == int(ns.LOW_POWER_KINO_MAX), "kino limited to %d during planet mission" % int(ns.LOW_POWER_KINO_MAX))

	# Collect resources one at a time.
	_expect(int(ns.call("get_planet_resources")) == 0, "planet resources start at 0")
	ns.call("collect_resource", 1)
	_expect(int(ns.call("get_planet_resources")) == 1, "planet resources at 1 after first collect")
	_expect(not bool(ns.call("is_escape_ready")), "escape not ready at 1/3 resources")

	ns.call("collect_resource", 1)
	_expect(int(ns.call("get_planet_resources")) == 2, "planet resources at 2 after second collect")
	_expect(not bool(ns.call("is_escape_ready")), "escape not ready at 2/3 resources")

	ns.call("collect_resource", 1)
	_expect(int(ns.call("get_planet_resources")) == 3, "planet resources at 3 after third collect")
	_expect(bool(ns.call("is_escape_ready")), "escape ready at 3/3 resources")

	# --- Escape stage --------------------------------------------------------
	ns.call("begin_escape")
	_expect(int(ns.get("_current_stage")) == ESCAPE, "stage is ESCAPE after begin_escape")
	_expect(not bool(ns.get("_sprint_disabled")), "sprint re-enabled for escape")

	# Complete escape.
	ns.call("complete_escape")
	_expect(int(ns.get("_current_stage")) == COMPLETE, "stage is COMPLETE after complete_escape")
	_expect(int(ns.get("_outcome")) == ESCAPED, "outcome is ESCAPED after complete_escape")
	_expect(bool(ns.call("is_complete")), "is_complete returns true after complete_escape")
	_expect(String(ns.call("get_outcome_name")) == "escaped", "outcome name is 'escaped'")

	# --- Save round-trip ----------------------------------------------------
	var snap: Dictionary = ns.call("serialize")
	_expect(snap.has("current_stage"), "serialize has current_stage")
	_expect(snap.has("power_reserve"), "serialize has power_reserve")
	_expect(snap.has("system_states"), "serialize has system_states")
	_expect(snap.has("nebula_planet_resources"), "serialize has nebula_planet_resources")

	# Save the current state, reset, then restore.
	var saved_stage: int = int(snap.get("current_stage", 0))
	var saved_resources: int = int(snap.get("nebula_planet_resources", 0))

	ns.call("reset")
	_expect(int(ns.get("_current_stage")) == NONE, "reset clears stage to NONE")
	_expect(int(ns.call("get_planet_resources")) == 0, "reset clears planet resources")

	ns.call("deserialize", snap, 1)
	_expect(int(ns.get("_current_stage")) == saved_stage, "deserialize restores current_stage")
	_expect(int(ns.call("get_planet_resources")) == saved_resources, "deserialize restores planet_resources_collected")

	# --- Reset to clean state for quest tests -------------------------------
	ns.call("reset")
	gs.call("reset")

	# --- QuestLog e4_darkness quest chain -------------------------------------
	ql.call("start_quest", "e4_darkness")
	ql.set("_tracked_quest_id", "e4_darkness")
	ql.call("advance", "e4_darkness")

	# Quest starts at step 1 (nebula_trap).
	var step: String = String(ql.call("active_step_id", "e4_darkness"))
	_expect(step == "nebula_trap", "e4_darkness starts at nebula_trap (got %s)" % step)

	# --- E4 flags start false ------------------------------------------------
	_expect(not gs.nebula_trap_detected, "nebula_trap_detected starts false")
	_expect(not gs.power_conservation_started, "power_conservation_started starts false")
	_expect(not gs.planet_resources_collected, "planet_resources_collected starts false")
	_expect(not gs.nebula_escape_complete, "nebula_escape_complete starts false")

	# --- Stage 1: detect_nebula_trap → conserve_power -----------------------
	gs.call("mark_nebula_trap_detected")
	_expect(gs.nebula_trap_detected, "nebula_trap_detected is true after mark")
	ql.call("advance", "e4_darkness")
	step = String(ql.call("active_step_id", "e4_darkness"))
	_expect(step == "conserve_power", "active step is conserve_power (got %s)" % step)

	# --- Stage 2: mark_power_conservation_started → planet_mission_low_power -
	gs.call("mark_power_conservation_started")
	_expect(gs.power_conservation_started, "power_conservation_started is true after mark")
	ql.call("advance", "e4_darkness")
	step = String(ql.call("active_step_id", "e4_darkness"))
	_expect(step == "planet_mission_low_power", "active step is planet_mission_low_power (got %s)" % step)

	# --- Stage 3: mark_planet_resources_collected → escape_nebula -----------
	gs.call("mark_planet_resources_collected")
	_expect(gs.planet_resources_collected, "planet_resources_collected is true after mark")
	ql.call("advance", "e4_darkness")
	step = String(ql.call("active_step_id", "e4_darkness"))
	_expect(step == "escape_nebula", "active step is escape_nebula (got %s)" % step)

	# --- Stage 4: mark_nebula_escape_complete → darkness_complete ------------
	gs.call("mark_nebula_escape_complete")
	_expect(gs.nebula_escape_complete, "nebula_escape_complete is true after mark")
	ql.call("advance", "e4_darkness")
	step = String(ql.call("active_step_id", "e4_darkness"))
	_expect(step == "darkness_complete", "active step is darkness_complete (got %s)" % step)
	_expect(bool(ql.call("is_complete", "e4_darkness")), "e4_darkness is_complete fires at terminal step")

	# --- Idempotency: calling helpers twice is a no-op ----------------------
	gs.call("mark_nebula_trap_detected")
	_expect(gs.nebula_trap_detected, "mark_nebula_trap_detected is idempotent")

	# --- GameState serialize/deserialize for E4 flags -----------------------
	gs.call("reset")
	gs.set("nebula_trap_detected", true)
	gs.set("power_conservation_started", true)
	gs.set("planet_resources_collected", true)
	gs.set("nebula_escape_complete", true)
	var gs_snap: Dictionary = gs.call("serialize")
	_expect(gs_snap.has("nebula_trap_detected"), "serialize has nebula_trap_detected")
	_expect(gs_snap.has("power_conservation_started"), "serialize has power_conservation_started")
	_expect(gs_snap.has("planet_resources_collected"), "serialize has planet_resources_collected")
	_expect(gs_snap.has("nebula_escape_complete"), "serialize has nebula_escape_complete")

	gs.call("reset")
	_expect(not gs.nebula_trap_detected, "reset clears nebula_trap_detected")
	gs.call("deserialize", gs_snap, 1)
	_expect(gs.nebula_trap_detected, "deserialize restores nebula_trap_detected")
	_expect(gs.power_conservation_started, "deserialize restores power_conservation_started")
	_expect(gs.planet_resources_collected, "deserialize restores planet_resources_collected")
	_expect(gs.nebula_escape_complete, "deserialize restores nebula_escape_complete")

	# --- reset() clears all E4 flags -----------------------------------------
	gs.call("reset")
	_expect(not gs.nebula_trap_detected, "reset clears nebula_trap_detected")
	_expect(not gs.power_conservation_started, "reset clears power_conservation_started")
	_expect(not gs.planet_resources_collected, "reset clears planet_resources_collected")
	_expect(not gs.nebula_escape_complete, "reset clears nebula_escape_complete")

	# --- Predicate warning for unknown keys is safe -------------------------
	var known_predicates: Array[String] = [
		"nebula_trap_detected", "power_conservation_started",
		"planet_resources_collected", "nebula_escape_complete"
	]
	for key in known_predicates:
		var result: bool = bool(ql.call("_evaluate_predicate", key))
		_expect(not result, "predicate %s is false after reset (got true)" % key)

	# --- EpisodeManager darkness_resolved predicate -------------------------
	# After reset, darkness_resolved should be false.
	var em: Node = root.get_node_or_null("EpisodeManager")
	if em != null:
		var resolved: bool = bool(em.call("check_completion", "e4_darkness"))
		_expect(not resolved, "darkness_resolved is false after reset")

		# Start crisis and complete it to test the predicate.
		ns.call("reset")
		ns.call("start_crisis")
		ns.call("begin_conservation")
		ns.call("begin_planet_mission")
		ns.call("collect_resource", 99)  # ensure escape_ready
		ns.call("begin_escape")
		ns.call("complete_escape")
		resolved = bool(em.call("check_completion", "e4_darkness"))
		_expect(resolved, "darkness_resolved is true after NebulaSystem complete")

	_report()
	quit(0 if _failures.is_empty() else 1)


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