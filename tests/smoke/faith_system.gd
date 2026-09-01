extends SceneTree

# Smoke test for the FaithSystem autoload — Episode 11: Faith.
#
# Verifies:
#   • FaithSystem autoload is attached and loaded its config from JSON.
#   • Phase enum values are stable (INACTIVE=0 through RESOLVED=7).
#   • Scenario data loaded correctly (id, title, planet_name, biome, etc.).
#   • Camp structures loaded (7 structures with build_time, resource_cost).
#   • Exploration sites loaded (5 sites with explore_time, resources).
#   • Survival events loaded (5 events with damage, mitigated_by).
#   • Philosophical dialogues loaded (8 dialogues with speaker, stance, weight).
#   • Moral choices loaded (stay, continue, split).
#   • start_faith initializes state and sets phase to DEBATE.
#   • begin_landing transitions to LANDING and fires landing_started.
#   • complete_landing transitions to SETTLEMENT (success and hard landing).
#   • start_build deduces resources and starts the build timer.
#   • tick_build progresses and completes structures.
#   • test_complete_build builds structures instantly for tests.
#   • begin_exploration requires mandatory structures.
#   • start_explore begins exploration, tick_explore completes it.
#   • Exploration awards resources.
#   • begin_survival requires 3+ explored sites.
#   • tick_survival advances day timer and event timer.
#   • Survival events apply damage and can be mitigated by structures.
#   • begin_moral_choice requires surviving all configured days.
#   • make_moral_choice applies effects and transitions to RESOLVED.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • Reset restores everything to initial state.
#   • Signals fire: phase_changed, structure_built, site_explored,
#     survival_event_triggered, survival_event_mitigated, dialogue_triggered,
#     landing_started, landing_completed, moral_choice_made, faith_resolved,
#     day_passed, crew_count_changed, morale_changed, health_changed.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/faith_system.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal trackers.
var _phase_changed_count: int = 0
var _structure_built_count: int = 0
var _site_explored_count: int = 0
var _survival_event_triggered_count: int = 0
var _survival_event_mitigated_count: int = 0
var _dialogue_triggered_count: int = 0
var _landing_started_count: int = 0
var _landing_completed_count: int = 0
var _moral_choice_made_count: int = 0
var _faith_resolved_count: int = 0
var _day_passed_count: int = 0
var _crew_count_changed_count: int = 0
var _morale_changed_count: int = 0
var _health_changed_count: int = 0


func _initialize() -> void:
	print("=== faith_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var fs: Node = root.get_node_or_null("FaithSystem")
	_expect(fs != null, "FaithSystem autoload is attached")
	if fs == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "faith_smoke")

	# --- Enum stability -------------------------------------------------------
	var INACTIVE: int = int(fs.Phase.INACTIVE)
	var DEBATE: int = int(fs.Phase.DEBATE)
	var LANDING: int = int(fs.Phase.LANDING)
	var SETTLEMENT: int = int(fs.Phase.SETTLEMENT)
	var EXPLORATION: int = int(fs.Phase.EXPLORATION)
	var SURVIVAL: int = int(fs.Phase.SURVIVAL)
	var MORAL_CHOICE: int = int(fs.Phase.MORAL_CHOICE)
	var RESOLVED: int = int(fs.Phase.RESOLVED)
	_expect(INACTIVE == 0, "Phase.INACTIVE == 0 (got %d)" % INACTIVE)
	_expect(DEBATE == 1, "Phase.DEBATE == 1 (got %d)" % DEBATE)
	_expect(LANDING == 2, "Phase.LANDING == 2 (got %d)" % LANDING)
	_expect(SETTLEMENT == 3, "Phase.SETTLEMENT == 3 (got %d)" % SETTLEMENT)
	_expect(EXPLORATION == 4, "Phase.EXPLORATION == 4 (got %d)" % EXPLORATION)
	_expect(SURVIVAL == 5, "Phase.SURVIVAL == 5 (got %d)" % SURVIVAL)
	_expect(MORAL_CHOICE == 6, "Phase.MORAL_CHOICE == 6 (got %d)" % MORAL_CHOICE)
	_expect(RESOLVED == 7, "Phase.RESOLVED == 7 (got %d)" % RESOLVED)

	# --- Config loaded --------------------------------------------------------
	fs.call("reset")
	var scenario: Dictionary = fs.call("get_scenario")
	_expect(not scenario.is_empty(), "scenario dict is non-empty after config load")
	_expect(fs.call("get_scenario_id") == "e11_faith", "scenario_id == e11_faith (got %s)" % fs.call("get_scenario_id"))
	_expect(fs.call("get_scenario_title") == "Faith", "scenario_title == Faith (got %s)" % fs.call("get_scenario_title"))
	_expect(not String(fs.call("get_scenario_description")).is_empty(), "scenario_description is non-empty")
	_expect(fs.call("get_planet_name") == "Eden", "planet_name == Eden (got %s)" % fs.call("get_planet_name"))
	_expect(fs.call("get_planet_biome") == "temperate", "planet_biome == temperate (got %s)" % fs.call("get_planet_biome"))

	# --- Camp structures loaded ----------------------------------------------
	var structure_ids: Array[String] = fs.call("get_all_structure_ids")
	_expect(structure_ids.size() == 7, "camp_structures count == 7 (got %d)" % structure_ids.size())
	_expect(structure_ids.has("shelter"), "shelter is in camp_structures")
	_expect(structure_ids.has("water_well"), "water_well is in camp_structures")
	_expect(structure_ids.has("farm_plot"), "farm_plot is in camp_structures")
	_expect(structure_ids.has("perimeter_fence"), "perimeter_fence is in camp_structures")
	_expect(structure_ids.has("med_station"), "med_station is in camp_structures")
	_expect(structure_ids.has("power_array"), "power_array is in camp_structures")
	_expect(structure_ids.has("communication_relay"), "communication_relay is in camp_structures")
	var shelter: Dictionary = fs.call("get_structure", "shelter")
	_expect(not shelter.is_empty(), "shelter structure data exists")
	_expect(float(shelter.get("build_time", 0.0)) > 0.0, "shelter build_time > 0")
	_expect(int(shelter.get("crew_required", 0)) >= 1, "shelter crew_required >= 1")
	_expect(bool(shelter.get("required_for_next_phase", false)), "shelter is required_for_next_phase")
	var farm: Dictionary = fs.call("get_structure", "farm_plot")
	_expect(bool(farm.get("required_for_next_phase", false)), "farm_plot is required_for_next_phase")

	# --- Exploration sites loaded --------------------------------------------
	var site_ids: Array[String] = fs.call("get_all_site_ids")
	_expect(site_ids.size() == 5, "exploration_sites count == 5 (got %d)" % site_ids.size())
	_expect(site_ids.has("northern_ridge"), "northern_ridge is in exploration_sites")
	_expect(site_ids.has("eastern_forest"), "eastern_forest is in exploration_sites")
	_expect(site_ids.has("southern_river"), "southern_river is in exploration_sites")
	_expect(site_ids.has("western_caves"), "western_caves is in exploration_sites")
	_expect(site_ids.has("central_valley"), "central_valley is in exploration_sites")
	var ridge: Dictionary = fs.call("get_site", "northern_ridge")
	_expect(not ridge.is_empty(), "northern_ridge site data exists")
	_expect(float(ridge.get("explore_time", 0.0)) > 0.0, "northern_ridge explore_time > 0")
	var ridge_res: Dictionary = ridge.get("resources", {})
	_expect(not ridge_res.is_empty(), "northern_ridge has resources")

	# --- Survival events loaded ----------------------------------------------
	_expect(int(fs.call("get_total_survival_events")) == 5, "survival_events count == 5 (got %d)" % int(fs.call("get_total_survival_events")))

	# --- Philosophical dialogues loaded --------------------------------------
	var dialogue_ids: Array[String] = fs.call("get_all_dialogue_ids")
	_expect(dialogue_ids.size() == 8, "philosophical_dialogues count == 8 (got %d)" % dialogue_ids.size())
	_expect(dialogue_ids.has("rush_mission"), "rush_mission is in dialogues")
	_expect(dialogue_ids.has("young_safety"), "young_safety is in dialogues")
	_expect(dialogue_ids.has("chloe_future"), "chloe_future is in dialogues")
	var rush_dialogue: Dictionary = fs.call("get_dialogue", "rush_mission")
	_expect(String(rush_dialogue.get("speaker", "")) == "Rush", "rush_mission speaker == Rush")
	_expect(String(rush_dialogue.get("stance", "")) == "continue", "rush_mission stance == continue")
	var chloe_dialogue: Dictionary = fs.call("get_dialogue", "chloe_future")
	_expect(String(chloe_dialogue.get("stance", "")) == "stay", "chloe_future stance == stay")

	# --- Moral choices loaded ------------------------------------------------
	var choices: Array[String] = fs.call("get_all_moral_choices")
	_expect(choices.size() == 3, "moral_choices count == 3 (got %d)" % choices.size())
	_expect(choices.has("stay"), "stay is in moral_choices")
	_expect(choices.has("continue"), "continue is in moral_choices")
	_expect(choices.has("split"), "split is in moral_choices")
	var stay_choice: Dictionary = fs.call("get_moral_choice_data", "stay")
	_expect(String(stay_choice.get("outcome", "")) == "settled", "stay outcome == settled")
	var continue_choice: Dictionary = fs.call("get_moral_choice_data", "continue")
	_expect(String(continue_choice.get("outcome", "")) == "continued", "continue outcome == continued")
	var split_choice: Dictionary = fs.call("get_moral_choice_data", "split")
	_expect(String(split_choice.get("outcome", "")) == "split", "split outcome == split")

	# --- Signal connections ---------------------------------------------------
	fs.phase_changed.connect(_on_phase_changed)
	fs.structure_built.connect(_on_structure_built)
	fs.site_explored.connect(_on_site_explored)
	fs.survival_event_triggered.connect(_on_survival_event_triggered)
	fs.survival_event_mitigated.connect(_on_survival_event_mitigated)
	fs.dialogue_triggered.connect(_on_dialogue_triggered)
	fs.landing_started.connect(_on_landing_started)
	fs.landing_completed.connect(_on_landing_completed)
	fs.moral_choice_made.connect(_on_moral_choice_made)
	fs.faith_resolved.connect(_on_faith_resolved)
	fs.day_passed.connect(_on_day_passed)
	fs.crew_count_changed.connect(_on_crew_count_changed)
	fs.morale_changed.connect(_on_morale_changed)
	fs.health_changed.connect(_on_health_changed)

	# --- Phase starts at INACTIVE --------------------------------------------
	_expect(int(fs.call("get_phase")) == INACTIVE, "phase == INACTIVE after reset (got %d)" % int(fs.call("get_phase")))
	_expect(String(fs.call("get_phase_name")) == "Inactive", "phase_name == Inactive (got %s)" % String(fs.call("get_phase_name")))

	# --- start_faith initializes state ---------------------------------------
	fs.call("start_faith")
	_expect(int(fs.call("get_phase")) == DEBATE, "phase == DEBATE after start_faith (got %d)" % int(fs.call("get_phase")))
	_expect(String(fs.call("get_phase_name")) == "Debate", "phase_name == Debate (got %s)" % String(fs.call("get_phase_name")))
	_expect(_phase_changed_count >= 1, "phase_changed signal fired at least once (got %d)" % _phase_changed_count)
	_expect(int(fs.call("get_crew_count")) == 15, "crew_count == 15 after start (got %d)" % int(fs.call("get_crew_count")))
	_expect(int(fs.call("get_morale")) == 70, "morale == 70 after start (got %d)" % int(fs.call("get_morale")))
	_expect(int(fs.call("get_health")) == 100, "health == 100 after start (got %d)" % int(fs.call("get_health")))
	_expect(int(fs.call("get_current_day")) == 1, "current_day == 1 after start (got %d)" % int(fs.call("get_current_day")))
	var resources: Dictionary = fs.call("get_resources")
	_expect(int(resources.get("wood", 0)) == 10, "wood == 10 after start (got %d)" % int(resources.get("wood", 0)))
	_expect(int(resources.get("metal", 0)) == 8, "metal == 8 after start (got %d)" % int(resources.get("metal", 0)))
	_expect(_crew_count_changed_count >= 1, "crew_count_changed signal fired (got %d)" % _crew_count_changed_count)
	_expect(_morale_changed_count >= 1, "morale_changed signal fired (got %d)" % _morale_changed_count)
	_expect(_health_changed_count >= 1, "health_changed signal fired (got %d)" % _health_changed_count)

	# --- begin_landing transitions to LANDING --------------------------------
	var landing_result: bool = bool(fs.call("begin_landing"))
	_expect(landing_result, "begin_landing returns true from DEBATE")
	_expect(int(fs.call("get_phase")) == LANDING, "phase == LANDING after begin_landing (got %d)" % int(fs.call("get_phase")))
	_expect(_landing_started_count >= 1, "landing_started signal fired (got %d)" % _landing_started_count)
	_expect(not String(fs.call("get_landing_zone")).is_empty(), "landing_zone is set after begin_landing")

	# begin_landing fails when not in DEBATE phase.
	fs.call("reset")
	fs.call("start_faith")
	fs.call("test_set_phase", int(fs.Phase.SETTLEMENT))
	var bad_landing: bool = bool(fs.call("begin_landing"))
	_expect(not bad_landing, "begin_landing returns false when not in DEBATE phase")

	# --- complete_landing (success) ------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	_expect(int(fs.call("get_phase")) == SETTLEMENT, "phase == SETTLEMENT after successful landing (got %d)" % int(fs.call("get_phase")))
	_expect(bool(fs.call("is_landing_success")), "is_landing_success == true")
	_expect(_landing_completed_count >= 1, "landing_completed signal fired (got %d)" % _landing_completed_count)

	# --- complete_landing (hard landing) -------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	var health_before: int = int(fs.call("get_health"))
	fs.call("complete_landing", false)
	_expect(int(fs.call("get_phase")) == SETTLEMENT, "phase == SETTLEMENT after hard landing (got %d)" % int(fs.call("get_phase")))
	_expect(not bool(fs.call("is_landing_success")), "is_landing_success == false after hard landing")
	_expect(int(fs.call("get_health")) < health_before, "health decreased after hard landing (got %d, was %d)" % [int(fs.call("get_health")), health_before])

	# --- Build structures -----------------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	# Build shelter using test helper.
	var build_ok: bool = bool(fs.call("test_complete_build", "shelter"))
	_expect(build_ok, "test_complete_build(shelter) returns true")
	_expect(bool(fs.call("is_structure_built", "shelter")), "shelter is built after test_complete_build")
	_expect(_structure_built_count >= 1, "structure_built signal fired (got %d)" % _structure_built_count)
	# Build shelter again returns false.
	var rebuild: bool = bool(fs.call("test_complete_build", "shelter"))
	_expect(not rebuild, "test_complete_build(shelter) returns false for already-built")

	# Build unknown structure fails.
	var unknown_build: bool = bool(fs.call("test_complete_build", "nonexistent"))
	_expect(not unknown_build, "test_complete_build(nonexistent) returns false")

	# Build farm_plot (required for next phase).
	fs.call("test_complete_build", "farm_plot")
	_expect(bool(fs.call("is_structure_built", "farm_plot")), "farm_plot is built")
	var built_list: Array[String] = fs.call("get_built_structures")
	_expect(built_list.size() == 2, "2 structures built (got %d)" % built_list.size())

	# --- start_build with insufficient resources -----------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	# Drain wood to test resource check.
	fs.call("set_resources", "wood", 0)
	var no_res_build: bool = bool(fs.call("start_build", "shelter"))
	_expect(not no_res_build, "start_build fails when insufficient resources")

	# --- Build progression via tick_build ------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	var start_ok: bool = bool(fs.call("start_build", "shelter"))
	_expect(start_ok, "start_build(shelter) returns true with resources")
	_expect(String(fs.call("get_active_build")) == "shelter", "active_build == shelter")
	# Tick build partway.
	fs.call("test_advance_build", 10.0)
	_expect(float(fs.call("get_build_progress")) > 0.0, "build_progress > 0 after tick (got %f)" % float(fs.call("get_build_progress")))
	# Complete the build with more ticks.
	var shelter_data: Dictionary = fs.call("get_structure", "shelter")
	var build_time: float = float(shelter_data.get("build_time", 120.0))
	fs.call("test_advance_build", build_time)
	_expect(bool(fs.call("is_structure_built", "shelter")), "shelter built after tick_build completes")
	_expect(String(fs.call("get_active_build")) == "", "active_build == empty after completion")

	# --- begin_exploration requires mandatory structures ---------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	# No structures built — should fail.
	var explore_no_build: bool = bool(fs.call("begin_exploration"))
	_expect(not explore_no_build, "begin_exploration fails without mandatory structures")
	# Build mandatory structures.
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	var explore_ok: bool = bool(fs.call("begin_exploration"))
	_expect(explore_ok, "begin_exploration succeeds with mandatory structures")
	_expect(int(fs.call("get_phase")) == EXPLORATION, "phase == EXPLORATION after begin_exploration (got %d)" % int(fs.call("get_phase")))

	# begin_exploration fails when not in SETTLEMENT.
	fs.call("reset")
	fs.call("start_faith")
	var wrong_phase_explore: bool = bool(fs.call("begin_exploration"))
	_expect(not wrong_phase_explore, "begin_exploration fails when not in SETTLEMENT phase")

	# --- Exploration ---------------------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	# Start exploring a site.
	var explore_start: bool = bool(fs.call("start_explore", "northern_ridge"))
	_expect(explore_start, "start_explore(northern_ridge) returns true")
	_expect(String(fs.call("get_active_explore")) == "northern_ridge", "active_explore == northern_ridge")
	# Can't start another explore while one is active.
	var concurrent_explore: bool = bool(fs.call("start_explore", "eastern_forest"))
	_expect(not concurrent_explore, "start_explore fails while another explore is active")
	# Tick explore partway.
	fs.call("test_advance_explore", 10.0)
	_expect(float(fs.call("get_explore_progress")) > 0.0, "explore_progress > 0 after tick")
	# Complete exploration.
	var ridge_data: Dictionary = fs.call("get_site", "northern_ridge")
	var explore_time: float = float(ridge_data.get("explore_time", 60.0))
	fs.call("test_advance_explore", explore_time)
	_expect(bool(fs.call("is_site_explored", "northern_ridge")), "northern_ridge explored after tick completes")
	_expect(_site_explored_count >= 1, "site_explored signal fired (got %d)" % _site_explored_count)
	# Explore already-explored site fails.
	var re_explore: bool = bool(fs.call("start_explore", "northern_ridge"))
	_expect(not re_explore, "start_explore returns false for already-explored site")
	# Unknown site fails.
	var unknown_site: bool = bool(fs.call("start_explore", "nonexistent"))
	_expect(not unknown_site, "start_explore(nonexistent) returns false")

	# Use test_complete_explore for remaining sites.
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	_expect(int(fs.call("get_explored_site_count")) == 3, "3 sites explored (got %d)" % int(fs.call("get_explored_site_count")))
	_expect(int(fs.call("get_total_sites")) == 5, "total_sites == 5 (got %d)" % int(fs.call("get_total_sites")))

	# --- begin_survival requires 3+ explored sites ---------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	# Only 0 sites explored — should fail.
	var survive_no_explore: bool = bool(fs.call("begin_survival"))
	_expect(not survive_no_explore, "begin_survival fails with 0 explored sites")
	# Explore 2 sites — still fails.
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	var survive_2: bool = bool(fs.call("begin_survival"))
	_expect(not survive_2, "begin_survival fails with 2 explored sites")
	# Explore 3rd site — should succeed.
	fs.call("test_complete_explore", "southern_river")
	var survive_ok: bool = bool(fs.call("begin_survival"))
	_expect(survive_ok, "begin_survival succeeds with 3 explored sites")
	_expect(int(fs.call("get_phase")) == SURVIVAL, "phase == SURVIVAL after begin_survival (got %d)" % int(fs.call("get_phase")))

	# begin_survival fails when not in EXPLORATION.
	fs.call("reset")
	fs.call("start_faith")
	var wrong_phase_survive: bool = bool(fs.call("begin_survival"))
	_expect(not wrong_phase_survive, "begin_survival fails when not in EXPLORATION phase")

	# --- Survival day advancement --------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	# Set fast day duration for testing.
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)  # Disable events for day test.
	var day_before: int = int(fs.call("get_current_day"))
	fs.call("test_advance_survival", 1.1)
	_expect(int(fs.call("get_current_day")) == day_before + 1, "current_day advanced by 1 (got %d, expected %d)" % [int(fs.call("get_current_day")), day_before + 1])
	_expect(_day_passed_count >= 1, "day_passed signal fired (got %d)" % _day_passed_count)

	# --- Survival event triggering -------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	# Set fast event interval for testing.
	fs.call("test_set_day_duration", 999.0)  # Disable day advancement.
	fs.call("test_set_event_interval", 1.0)
	var morale_before_event: int = int(fs.call("get_morale"))
	fs.call("test_advance_survival", 1.1)
	_expect(_survival_event_triggered_count >= 1, "survival_event_triggered signal fired (got %d)" % _survival_event_triggered_count)
	# The first event is "storm" which damages shelter_rating (reduces morale).
	_expect(bool(fs.call("is_event_triggered", "storm")), "storm event was triggered")

	# --- Survival event mitigation -------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	# Build perimeter_fence to mitigate storm.
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("test_complete_build", "perimeter_fence")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	fs.call("test_set_day_duration", 999.0)
	fs.call("test_set_event_interval", 1.0)
	fs.call("test_advance_survival", 1.1)
	# Storm should be mitigated by perimeter_fence.
	_expect(bool(fs.call("is_event_mitigated", "storm")), "storm event was mitigated by perimeter_fence")
	_expect(_survival_event_mitigated_count >= 1, "survival_event_mitigated signal fired (got %d)" % _survival_event_mitigated_count)

	# --- Direct event trigger for test ---------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	var health_before_illness: int = int(fs.call("get_health"))
	fs.call("test_trigger_event", "illness")
	_expect(bool(fs.call("is_event_triggered", "illness")), "illness event was triggered via test_trigger_event")
	# Without med_station, illness applies full damage.
	_expect(int(fs.call("get_health")) < health_before_illness, "health decreased after unmitigated illness (got %d, was %d)" % [int(fs.call("get_health")), health_before_illness])

	# --- Philosophical dialogue ----------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	var dialogue_ok: bool = bool(fs.call("trigger_dialogue", "rush_mission"))
	_expect(dialogue_ok, "trigger_dialogue(rush_mission) returns true")
	_expect(bool(fs.call("is_dialogue_triggered", "rush_mission")), "rush_mission dialogue is triggered")
	_expect(_dialogue_triggered_count >= 1, "dialogue_triggered signal fired (got %d)" % _dialogue_triggered_count)
	# Re-trigger fails.
	var re_dialogue: bool = bool(fs.call("trigger_dialogue", "rush_mission"))
	_expect(not re_dialogue, "trigger_dialogue returns false for already-triggered dialogue")
	# Unknown dialogue fails.
	var unknown_dialogue: bool = bool(fs.call("trigger_dialogue", "nonexistent"))
	_expect(not unknown_dialogue, "trigger_dialogue(nonexistent) returns false")
	# Trigger multiple dialogues and check dominant stance.
	fs.call("trigger_dialogue", "chloe_future")
	fs.call("trigger_dialogue", "young_safety")
	fs.call("trigger_dialogue", "tj_healing")
	fs.call("trigger_dialogue", "camille_home")
	# stay_weight = 2+2+2+2 = 8, continue_weight = 3 → stay.
	_expect(String(fs.call("get_dominant_stance")) == "stay", "dominant_stance == stay (got %s)" % String(fs.call("get_dominant_stance")))
	var triggered_dialogues: Array[String] = fs.call("get_triggered_dialogues")
	_expect(triggered_dialogues.size() == 5, "5 dialogues triggered (got %d)" % triggered_dialogues.size())

	# --- begin_moral_choice requires surviving all days ----------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	# Set days_to_survive to 2 and fast day duration.
	fs.call("test_set_days_to_survive", 2)
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)
	# Day 1.
	fs.call("test_advance_survival", 1.1)
	_expect(int(fs.call("get_current_day")) == 2, "current_day == 2 after first day (got %d)" % int(fs.call("get_current_day")))
	# Day 2 — should auto-advance to MORAL_CHOICE.
	fs.call("test_advance_survival", 1.1)
	_expect(int(fs.call("get_phase")) == MORAL_CHOICE, "phase == MORAL_CHOICE after surviving all days (got %d)" % int(fs.call("get_phase")))

	# begin_moral_choice fails when not in SURVIVAL.
	fs.call("reset")
	fs.call("start_faith")
	var wrong_phase_moral: bool = bool(fs.call("begin_moral_choice"))
	_expect(not wrong_phase_moral, "begin_moral_choice fails when not in SURVIVAL phase")

	# --- Moral choice: stay --------------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	fs.call("test_set_days_to_survive", 1)
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)
	fs.call("test_advance_survival", 1.1)
	_expect(int(fs.call("get_phase")) == MORAL_CHOICE, "phase == MORAL_CHOICE before moral choice")
	_expect(bool(fs.call("can_make_moral_choice")), "can_make_moral_choice == true in MORAL_CHOICE phase")
	var stay_result: bool = bool(fs.call("make_moral_choice", "stay"))
	_expect(stay_result, "make_moral_choice(stay) returns true")
	_expect(String(fs.call("get_moral_choice")) == "stay", "moral_choice == stay")
	_expect(String(fs.call("get_resolution_outcome")) == "settled", "resolution_outcome == settled")
	_expect(int(fs.call("get_phase")) == RESOLVED, "phase == RESOLVED after moral choice (got %d)" % int(fs.call("get_phase")))
	_expect(bool(fs.call("is_complete")), "is_complete == true after resolution")
	_expect(_moral_choice_made_count >= 1, "moral_choice_made signal fired (got %d)" % _moral_choice_made_count)
	_expect(_faith_resolved_count >= 1, "faith_resolved signal fired (got %d)" % _faith_resolved_count)

	# --- Moral choice: continue ----------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	fs.call("test_set_days_to_survive", 1)
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)
	fs.call("test_advance_survival", 1.1)
	var continue_result: bool = bool(fs.call("make_moral_choice", "continue"))
	_expect(continue_result, "make_moral_choice(continue) returns true")
	_expect(String(fs.call("get_resolution_outcome")) == "continued", "resolution_outcome == continued")

	# --- Moral choice: split -------------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	fs.call("test_set_days_to_survive", 1)
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)
	fs.call("test_advance_survival", 1.1)
	var split_result: bool = bool(fs.call("make_moral_choice", "split"))
	_expect(split_result, "make_moral_choice(split) returns true")
	_expect(String(fs.call("get_resolution_outcome")) == "split", "resolution_outcome == split")

	# --- Invalid moral choice fails ------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("test_set_phase", int(fs.Phase.MORAL_CHOICE))
	var bad_choice: bool = bool(fs.call("make_moral_choice", "nonexistent"))
	_expect(not bad_choice, "make_moral_choice(nonexistent) returns false")

	# Moral choice when not in MORAL_CHOICE phase fails.
	fs.call("reset")
	fs.call("start_faith")
	var wrong_phase_choice: bool = bool(fs.call("make_moral_choice", "stay"))
	_expect(not wrong_phase_choice, "make_moral_choice fails when not in MORAL_CHOICE phase")

	# --- Save round-trip -----------------------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("trigger_dialogue", "rush_mission")
	fs.call("test_set_phase", int(fs.Phase.SURVIVAL))
	var serialized: Dictionary = fs.call("serialize")
	_expect(serialized.has("current_phase"), "serialize has current_phase")
	_expect(serialized.has("built_structures"), "serialize has built_structures")
	_expect(serialized.has("explored_sites"), "serialize has explored_sites")
	_expect(serialized.has("triggered_events"), "serialize has triggered_events")
	_expect(serialized.has("triggered_dialogues"), "serialize has triggered_dialogues")
	_expect(serialized.has("crew_count"), "serialize has crew_count")
	_expect(serialized.has("morale"), "serialize has morale")
	_expect(serialized.has("health"), "serialize has health")
	_expect(serialized.has("current_day"), "serialize has current_day")
	_expect(serialized.has("resources"), "serialize has resources")
	_expect(serialized.has("landing_zone"), "serialize has landing_zone")
	_expect(serialized.has("landing_success"), "serialize has landing_success")
	_expect(serialized.has("moral_choice_id"), "serialize has moral_choice_id")
	_expect(serialized.has("resolution_outcome"), "serialize has resolution_outcome")

	var saved_phase: int = int(serialized.get("current_phase", 0))
	var saved_built: int = (serialized.get("built_structures", []) as Array).size()
	var saved_explored: int = (serialized.get("explored_sites", []) as Array).size()

	fs.call("reset")
	fs.call("deserialize", serialized, 1)
	_expect(int(fs.call("get_phase")) == saved_phase, "phase restored after deserialize (got %d, expected %d)" % [int(fs.call("get_phase")), saved_phase])
	_expect(bool(fs.call("is_structure_built", "shelter")), "shelter restored after deserialize")
	_expect(bool(fs.call("is_site_explored", "northern_ridge")), "northern_ridge restored after deserialize")
	_expect(bool(fs.call("is_dialogue_triggered", "rush_mission")), "rush_mission dialogue restored after deserialize")
	var built_after_restore: Array[String] = fs.call("get_built_structures")
	_expect(built_after_restore.size() == saved_built, "built_structures count restored (got %d, expected %d)" % [built_after_restore.size(), saved_built])
	var explored_after_restore: Array[String] = fs.call("get_explored_sites")
	_expect(explored_after_restore.size() == saved_explored, "explored_sites count restored (got %d, expected %d)" % [explored_after_restore.size(), saved_explored])

	# --- Full save round-trip with moral choice ------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	fs.call("test_set_days_to_survive", 1)
	fs.call("test_set_day_duration", 1.0)
	fs.call("test_set_event_interval", 999.0)
	fs.call("test_advance_survival", 1.1)
	fs.call("make_moral_choice", "stay")
	var full_ser: Dictionary = fs.call("serialize")
	_expect(String(full_ser.get("moral_choice_id", "")) == "stay", "serialize moral_choice_id == stay")
	_expect(String(full_ser.get("resolution_outcome", "")) == "settled", "serialize resolution_outcome == settled")
	fs.call("reset")
	fs.call("deserialize", full_ser, 1)
	_expect(String(fs.call("get_moral_choice")) == "stay", "moral_choice restored after full deserialize")
	_expect(String(fs.call("get_resolution_outcome")) == "settled", "resolution_outcome restored after full deserialize")
	_expect(int(fs.call("get_phase")) == RESOLVED, "phase == RESOLVED restored after full deserialize (got %d)" % int(fs.call("get_phase")))
	_expect(bool(fs.call("is_complete")), "is_complete == true after full deserialize")

	# --- Reset clears everything ---------------------------------------------
	fs.call("reset")
	_expect(int(fs.call("get_phase")) == INACTIVE, "phase == INACTIVE after reset (got %d)" % int(fs.call("get_phase")))
	_expect(fs.call("get_built_structures").is_empty(), "built_structures empty after reset")
	_expect(fs.call("get_explored_sites").is_empty(), "explored_sites empty after reset")
	_expect(fs.call("get_triggered_events").is_empty(), "triggered_events empty after reset")
	_expect(String(fs.call("get_moral_choice")) == "", "moral_choice empty after reset")
	_expect(String(fs.call("get_resolution_outcome")) == "", "resolution_outcome empty after reset")
	_expect(int(fs.call("get_current_day")) == 1, "current_day == 1 after reset (got %d)" % int(fs.call("get_current_day")))
	_expect(String(fs.call("get_active_build")) == "", "active_build empty after reset")
	_expect(String(fs.call("get_active_explore")) == "", "active_explore empty after reset")

	# --- Phase name for all phases -------------------------------------------
	fs.call("reset")
	fs.call("test_set_phase", int(fs.Phase.INACTIVE))
	_expect(String(fs.call("get_phase_name")) == "Inactive", "phase_name == Inactive")
	fs.call("test_set_phase", int(fs.Phase.DEBATE))
	_expect(String(fs.call("get_phase_name")) == "Debate", "phase_name == Debate")
	fs.call("test_set_phase", int(fs.Phase.LANDING))
	_expect(String(fs.call("get_phase_name")) == "Landing", "phase_name == Landing")
	fs.call("test_set_phase", int(fs.Phase.SETTLEMENT))
	_expect(String(fs.call("get_phase_name")) == "Settlement", "phase_name == Settlement")
	fs.call("test_set_phase", int(fs.Phase.EXPLORATION))
	_expect(String(fs.call("get_phase_name")) == "Exploration", "phase_name == Exploration")
	fs.call("test_set_phase", int(fs.Phase.SURVIVAL))
	_expect(String(fs.call("get_phase_name")) == "Survival", "phase_name == Survival")
	fs.call("test_set_phase", int(fs.Phase.MORAL_CHOICE))
	_expect(String(fs.call("get_phase_name")) == "Moral Choice", "phase_name == Moral Choice")
	fs.call("test_set_phase", int(fs.Phase.RESOLVED))
	_expect(String(fs.call("get_phase_name")) == "Resolved", "phase_name == Resolved")

	# --- Survival does not tick in INACTIVE ----------------------------------
	fs.call("reset")
	var day_before_inactive: int = int(fs.call("get_current_day"))
	fs.call("test_advance_survival", 100.0)
	_expect(int(fs.call("get_current_day")) == day_before_inactive, "current_day unchanged in INACTIVE phase")

	# --- Survival does not tick in RESOLVED ----------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("test_set_phase", int(fs.Phase.RESOLVED))
	var day_before_resolved: int = int(fs.call("get_current_day"))
	fs.call("test_advance_survival", 100.0)
	_expect(int(fs.call("get_current_day")) == day_before_resolved, "current_day unchanged in RESOLVED phase")

	# --- Resources change on exploration -------------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	var wood_before_explore: int = int(fs.call("get_resources").get("wood", 0))
	fs.call("test_complete_explore", "eastern_forest")
	var wood_after_explore: int = int(fs.call("get_resources").get("wood", 0))
	_expect(wood_after_explore > wood_before_explore, "wood increased after exploring eastern_forest (got %d, was %d)" % [wood_after_explore, wood_before_explore])

	# --- Crew death when health drops too low --------------------------------
	fs.call("reset")
	fs.call("start_faith")
	fs.call("begin_landing")
	fs.call("complete_landing", true)
	fs.call("test_complete_build", "shelter")
	fs.call("test_complete_build", "farm_plot")
	fs.call("begin_exploration")
	fs.call("test_complete_explore", "northern_ridge")
	fs.call("test_complete_explore", "eastern_forest")
	fs.call("test_complete_explore", "southern_river")
	fs.call("begin_survival")
	var crew_before: int = int(fs.call("get_crew_count"))
	fs.call("test_set_health", 20)
	fs.call("test_trigger_event", "illness")
	# Illness damage to crew_health with health < 30 should cause crew death.
	_expect(int(fs.call("get_crew_count")) < crew_before, "crew_count decreased when health < 30 during illness (got %d, was %d)" % [int(fs.call("get_crew_count")), crew_before])

	_report()
	quit(0 if _failures.is_empty() else 1)


# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_phase_changed(_old: int, _new: int) -> void:
	_phase_changed_count += 1

func _on_structure_built(_structure_id: String) -> void:
	_structure_built_count += 1

func _on_site_explored(_site_id: String) -> void:
	_site_explored_count += 1

func _on_survival_event_triggered(_event_id: String) -> void:
	_survival_event_triggered_count += 1

func _on_survival_event_mitigated(_event_id: String, _structure_id: String) -> void:
	_survival_event_mitigated_count += 1

func _on_dialogue_triggered(_dialogue_id: String) -> void:
	_dialogue_triggered_count += 1

func _on_landing_started(_zone_id: String) -> void:
	_landing_started_count += 1

func _on_landing_completed(_zone_id: String, _success: bool) -> void:
	_landing_completed_count += 1

func _on_moral_choice_made(_choice_id: String) -> void:
	_moral_choice_made_count += 1

func _on_faith_resolved(_outcome: String) -> void:
	_faith_resolved_count += 1

func _on_day_passed(_day: int) -> void:
	_day_passed_count += 1

func _on_crew_count_changed(_count: int) -> void:
	_crew_count_changed_count += 1

func _on_morale_changed(_value: int) -> void:
	_morale_changed_count += 1

func _on_health_changed(_value: int) -> void:
	_health_changed_count += 1


# ── Helpers ────────────────────────────────────────────────────────────────────

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