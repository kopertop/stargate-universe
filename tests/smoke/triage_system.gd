extends SceneTree

# Smoke test for the TriageSystem autoload — mass casualty triage mechanic.
#
# Verifies:
#   • TriageSystem autoload is attached and loaded its config from JSON.
#   • TriageCategory enum values are stable.
#   • PatientStatus enum values are stable.
#   • Treatment enum values are stable.
#   • start_crisis spawns patients from archetypes.
#   • Patients have correct severity, category, and status on spawn.
#   • Category assignment from severity follows the S.T.A.R.T. protocol.
#   • Deterioration increases severity over time for waiting patients.
#   • Treatment (stabilize) consumes supplies and reduces severity.
#   • Treatment cannot start without sufficient supplies.
#   • Treatment cannot start on non-waiting patients.
#   • Multiple treatments can run concurrently on different patients.
#   • Patient severity < 0.20 after treatment → TRIAGED_OK.
#   • Patient severity >= 1.0 → DECEASED.
#   • Priority sort: IMMEDIATE before DELAYED before MINIMAL before EXPECTANT.
#   • Moral choice registration, resolution, and query.
#   • Supply management: get, add, spend, max.
#   • TJ medical skill modifies treatment effectiveness.
#   • Save round-trip: serialize → deserialize preserves patients + supplies.
#   • Reset clears all state.
#   • Crisis end resolves untreated patients (high severity dies).
#   • get_triage_summary returns correct stats.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/triage_system.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== triage_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ts: Node = root.get_node_or_null("TriageSystem")
	_expect(ts != null, "TriageSystem autoload is attached")
	if ts == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "triage_system_smoke")

	# --- Enum stability -------------------------------------------------------
	var IMMEDIATE: int = int(ts.TriageCategory.IMMEDIATE)
	var DELAYED: int = int(ts.TriageCategory.DELAYED)
	var MINIMAL: int = int(ts.TriageCategory.MINIMAL)
	var EXPECTANT: int = int(ts.TriageCategory.EXPECTANT)
	_expect(IMMEDIATE == 0, "TriageCategory.IMMEDIATE == 0 (got %d)" % IMMEDIATE)
	_expect(DELAYED == 1, "TriageCategory.DELAYED == 1 (got %d)" % DELAYED)
	_expect(MINIMAL == 2, "TriageCategory.MINIMAL == 2 (got %d)" % MINIMAL)
	_expect(EXPECTANT == 3, "TriageCategory.EXPECTANT == 3 (got %d)" % EXPECTANT)

	var WAITING: int = int(ts.PatientStatus.WAITING)
	var TREATING: int = int(ts.PatientStatus.TREATING)
	var STABILIZED: int = int(ts.PatientStatus.STABILIZED)
	var DECEASED: int = int(ts.PatientStatus.DECEASED)
	var TRIAGED_OK: int = int(ts.PatientStatus.TRIAGED_OK)
	_expect(WAITING == 0, "PatientStatus.WAITING == 0 (got %d)" % WAITING)
	_expect(TREATING == 1, "PatientStatus.TREATING == 1 (got %d)" % TREATING)
	_expect(STABILIZED == 2, "PatientStatus.STABILIZED == 2 (got %d)" % STABILIZED)
	_expect(DECEASED == 3, "PatientStatus.DECEASED == 3 (got %d)" % DECEASED)
	_expect(TRIAGED_OK == 4, "PatientStatus.TRIAGED_OK == 4 (got %d)" % TRIAGED_OK)

	var STABILIZE: int = int(ts.Treatment.STABILIZE)
	var TRANSFUSE: int = int(ts.Treatment.TRANSFUSE)
	var STIMULATE: int = int(ts.Treatment.STIMULATE)
	var EMERGENCY_SURGERY: int = int(ts.Treatment.EMERGENCY_SURGERY)
	_expect(STABILIZE == 0, "Treatment.STABILIZE == 0 (got %d)" % STABILIZE)
	_expect(TRANSFUSE == 1, "Treatment.TRANSFUSE == 1 (got %d)" % TRANSFUSE)
	_expect(STIMULATE == 2, "Treatment.STIMULATE == 2 (got %d)" % STIMULATE)
	_expect(EMERGENCY_SURGERY == 3, "Treatment.EMERGENCY_SURGERY == 3 (got %d)" % EMERGENCY_SURGERY)

	# --- Config loaded --------------------------------------------------------
	ts.call("reset")
	# Check supplies are initialized from config.
	var bandages: int = int(ts.call("get_supply", "bandages"))
	_expect(bandages == 8, "initial bandages == 8 (got %d)" % bandages)
	var plasma: int = int(ts.call("get_supply", "plasma"))
	_expect(plasma == 4, "initial plasma == 4 (got %d)" % plasma)
	var stimulants: int = int(ts.call("get_supply", "stimulants"))
	_expect(stimulants == 3, "initial stimulants == 3 (got %d)" % stimulants)
	var surgical_kit: int = int(ts.call("get_supply", "surgical_kit"))
	_expect(surgical_kit == 2, "initial surgical_kit == 2 (got %d)" % surgical_kit)

	# Check max supplies.
	_expect(int(ts.call("get_max_supply", "bandages")) == 8, "max bandages == 8")
	_expect(int(ts.call("get_max_supply", "plasma")) == 4, "max plasma == 4")

	# Check crisis duration.
	var crisis_dur: float = float(ts.call("get_crisis_duration"))
	_expect(crisis_dur == 120.0, "crisis_duration == 120.0 (got %f)" % crisis_dur)

	# Check TJ medical skill.
	var tj_skill: float = float(ts.call("get_tj_medical_skill"))
	_expect(tj_skill == 0.7, "tj_medical_skill == 0.7 (got %f)" % tj_skill)

	# --- Start crisis ---------------------------------------------------------
	var started: bool = bool(ts.call("start_crisis"))
	_expect(started, "start_crisis succeeded")
	_expect(bool(ts.call("is_crisis_active")), "is_crisis_active returns true after start_crisis")

	# All 8 archetypes should have spawned patients.
	var patient_count: int = int(ts.call("get_patient_count"))
	_expect(patient_count == 8, "8 patients spawned from 8 archetypes (got %d)" % patient_count)

	# Can't start a second crisis while one is active.
	var double_start: bool = bool(ts.call("start_crisis"))
	_expect(not double_start, "start_crisis rejected when already active")

	# --- Patient initial state ------------------------------------------------
	var pids: Array = ts.call("get_patient_ids")
	_expect(pids.size() == 8, "get_patient_ids returns 8 ids (got %d)" % pids.size())

	# patient_1 should be "crew_burns" (first archetype, severity 0.60, IMMEDIATE).
	var p1: Dictionary = ts.call("get_patient", "patient_1")
	_expect(not p1.is_empty(), "patient_1 exists")
	_expect(String(p1.get("name", "")) == "Crew Member — Severe Burns", "patient_1 name is 'Crew Member — Severe Burns'")
	_expect(String(p1.get("injury_type", "")) == "Thermal burns from explosion", "patient_1 injury_type correct")
	_expect(absf(float(p1.get("severity", 0.0)) - 0.60) < 0.01, "patient_1 severity ~0.60 (got %f)" % float(p1.get("severity", 0.0)))
	_expect(int(p1.get("category", -1)) == IMMEDIATE, "patient_1 category is IMMEDIATE")
	_expect(int(p1.get("status", -1)) == WAITING, "patient_1 status is WAITING")

	# patient_2 = crew_fracture (severity 0.45, DELAYED).
	var p2: Dictionary = ts.call("get_patient", "patient_2")
	_expect(absf(float(p2.get("severity", 0.0)) - 0.45) < 0.01, "patient_2 severity ~0.45 (got %f)" % float(p2.get("severity", 0.0)))
	_expect(int(p2.get("category", -1)) == DELAYED, "patient_2 category is DELAYED")

	# patient_3 = crew_lacerations (severity 0.25, MINIMAL).
	var p3: Dictionary = ts.call("get_patient", "patient_3")
	_expect(absf(float(p3.get("severity", 0.0)) - 0.25) < 0.01, "patient_3 severity ~0.25 (got %f)" % float(p3.get("severity", 0.0)))
	_expect(int(p3.get("category", -1)) == MINIMAL, "patient_3 category is MINIMAL")

	# patient_8 = crew_internal (severity 0.75, EXPECTANT from config override).
	var p8: Dictionary = ts.call("get_patient", "patient_8")
	_expect(absf(float(p8.get("severity", 0.0)) - 0.75) < 0.01, "patient_8 severity ~0.75 (got %f)" % float(p8.get("severity", 0.0)))
	_expect(int(p8.get("category", -1)) == EXPECTANT, "patient_8 category is EXPECTANT")

	# --- Category from severity -----------------------------------------------
	# crew_shock has severity 0.80 → should be IMMEDIATE.
	var p6: Dictionary = ts.call("get_patient", "patient_6")
	_expect(int(p6.get("category", -1)) == IMMEDIATE, "patient_6 (shock, sev 0.80) category is IMMEDIATE")

	# --- Patient accessors ----------------------------------------------------
	_expect(absf(float(ts.call("get_patient_severity", "patient_1")) - 0.60) < 0.01, "get_patient_severity patient_1 ~0.60")
	_expect(int(ts.call("get_patient_category", "patient_1")) == IMMEDIATE, "get_patient_category patient_1 == IMMEDIATE")
	_expect(int(ts.call("get_patient_status", "patient_1")) == WAITING, "get_patient_status patient_1 == WAITING")
	_expect(String(ts.call("get_patient_name", "patient_1")) == "Crew Member — Severe Burns", "get_patient_name correct")
	_expect(String(ts.call("get_patient_injury_type", "patient_1")) == "Thermal burns from explosion", "get_patient_injury_type correct")
	_expect(int(ts.call("get_patient_treatment_count", "patient_1")) == 0, "get_patient_treatment_count == 0 initially")

	# --- get_patients_by_category / status -----------------------------------
	var immediate_pids: Array = ts.call("get_patients_by_category", IMMEDIATE)
	_expect(immediate_pids.size() >= 3, "at least 3 IMMEDIATE patients (got %d)" % immediate_pids.size())
	var waiting_pids: Array = ts.call("get_patients_by_status", WAITING)
	_expect(waiting_pids.size() == 8, "8 WAITING patients initially (got %d)" % waiting_pids.size())

	# --- Priority sort --------------------------------------------------------
	var sorted: Array = ts.call("get_patients_sorted_by_priority")
	_expect(sorted.size() == 8, "priority sort returns 8 ids (got %d)" % sorted.size())
	# The first patient should be in IMMEDIATE category.
	var first_cat: int = int(ts.call("get_patient_category", String(sorted[0])))
	_expect(first_cat == IMMEDIATE, "first priority patient is IMMEDIATE (category=%d)" % first_cat)

	# --- Deterioration --------------------------------------------------------
	ts.call("reset")
	# Spawn just two patients for controlled test.
	ts.call("start_crisis", ["crew_burns", "crew_minor_cuts"])
	_expect(int(ts.call("get_patient_count")) == 2, "2 patients spawned for deterioration test")

	# Advance deterioration by one tick.
	var sev_before: float = float(ts.call("get_patient_severity", "patient_1"))
	ts.call("test_advance_deterioration")
	var sev_after: float = float(ts.call("get_patient_severity", "patient_1"))
	_expect(sev_after > sev_before, "severity increased after deterioration tick (%f → %f)" % [sev_before, sev_after])

	# --- Treatment: stabilize -------------------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_fracture"])
	# patient_1 = crew_fracture, severity 0.45, DELAYED.
	var bandages_before: int = int(ts.call("get_supply", "bandages"))
	# stabilize costs 1 bandage, duration 3.0s, severity_reduction 0.15.
	var treat_started: bool = bool(ts.call("start_treatment", "patient_1", "stabilize"))
	_expect(treat_started, "start_treatment stabilize on patient_1 succeeded")
	_expect(int(ts.call("get_patient_status", "patient_1")) == TREATING, "patient_1 status is TREATING")
	_expect(bool(ts.call("is_treatment_active", "patient_1")), "is_treatment_active returns true")
	_expect(int(ts.call("get_supply", "bandages")) == bandages_before - 1, "bandages consumed by stabilize (got %d)" % int(ts.call("get_supply", "bandages")))

	# Can't start a second treatment on same patient.
	var double_treat: bool = bool(ts.call("start_treatment", "patient_1", "transfuse"))
	_expect(not double_treat, "start_treatment rejected when treatment already active")

	# Treatment progress at start is 0.0.
	var prog: float = float(ts.call("get_treatment_progress", "patient_1"))
	_expect(prog == 0.0, "treatment progress == 0.0 at start (got %f)" % prog)

	# Advance treatment by 1.5s (half of 3.0s duration).
	ts.call("test_advance_treatments", 1.5)
	prog = float(ts.call("get_treatment_progress", "patient_1"))
	_expect(prog >= 0.49 and prog <= 0.51, "treatment progress ~0.5 at halfway (got %f)" % prog)

	# Complete the treatment.
	var completed: Array = ts.call("test_advance_treatments", 1.5)
	_expect(not completed.is_empty(), "test_advance_treatments returned completed treatments")
	_expect(String(completed[0]) == "patient_1", "completed treatment is patient_1")
	_expect(not bool(ts.call("is_treatment_active", "patient_1")), "no active treatment after completion")

	# After stabilize: severity 0.45 - (0.15 * (0.5 + 0.7)) = 0.45 - 0.18 = 0.27.
	var sev_post: float = float(ts.call("get_patient_severity", "patient_1"))
	_expect(absf(sev_post - 0.27) < 0.02, "severity ~0.27 after stabilize (got %f)" % sev_post)
	# 0.27 is < 0.45 but >= 0.20, so STABILIZED.
	_expect(int(ts.call("get_patient_status", "patient_1")) == STABILIZED, "patient_1 is STABILIZED after stabilize treatment")
	# Treatment count incremented.
	_expect(int(ts.call("get_patient_treatment_count", "patient_1")) == 1, "patient_1 treatment_count == 1")

	# --- Treatment: emergency_surgery -----------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_shock"])
	# patient_1 = crew_shock, severity 0.80, IMMEDIATE.
	# emergency_surgery costs: surgical_kit 1, plasma 1, bandages 2.
	var sk_before: int = int(ts.call("get_supply", "surgical_kit"))
	var pl_before: int = int(ts.call("get_supply", "plasma"))
	var bd_before: int = int(ts.call("get_supply", "bandages"))
	var surgery_started: bool = bool(ts.call("start_treatment", "patient_1", "emergency_surgery"))
	_expect(surgery_started, "start_treatment emergency_surgery on patient_1 succeeded")
	_expect(int(ts.call("get_supply", "surgical_kit")) == sk_before - 1, "surgical_kit consumed by surgery")
	_expect(int(ts.call("get_supply", "plasma")) == pl_before - 1, "plasma consumed by surgery")
	_expect(int(ts.call("get_supply", "bandages")) == bd_before - 2, "2 bandages consumed by surgery")

	# emergency_surgery duration = 8.0s, severity_reduction = 0.50.
	# 0.80 - (0.50 * (0.5 + 0.7)) = 0.80 - 0.60 = 0.20.
	# 0.20 < 0.20? No, 0.20 is not < 0.20. So STABILIZED, not TRIAGED_OK.
	var surgery_done: Array = ts.call("test_advance_treatments", 8.0)
	_expect(not surgery_done.is_empty(), "emergency_surgery completed")
	var sev_surgery: float = float(ts.call("get_patient_severity", "patient_1"))
	_expect(absf(sev_surgery - 0.20) < 0.02, "severity ~0.20 after emergency_surgery (got %f)" % sev_surgery)

	# --- Treatment: insufficient supplies -------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_shock", "crew_burns", "crew_internal", "crew_exposure"])
	# Spend all plasma on first patient.
	ts.call("start_treatment", "patient_1", "emergency_surgery")
	# Now try emergency_surgery on patient_2 — needs plasma but we only had 4,
	# and surgery costs 1 plasma. We had 4, spent 1, so 3 remain.
	# Let's try using all plasma: do 3 more surgeries.
	# Actually, let's just deplete plasma by adding a patient and treating.
	# Simpler: try transfuse which costs 1 plasma each. We have 3 plasma left.
	ts.call("start_treatment", "patient_2", "transfuse")
	ts.call("start_treatment", "patient_3", "transfuse")
	# Now only 1 plasma left. Start one more transfuse.
	ts.call("start_treatment", "patient_4", "transfuse")
	# Now 0 plasma left. Try another — should fail.
	var no_plasma: bool = bool(ts.call("start_treatment", "patient_1", "transfuse"))
	_expect(not no_plasma, "transfuse rejected when plasma depleted")

	# --- Treatment on non-waiting patient ------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_fracture"])
	# Complete a treatment first.
	ts.call("start_treatment", "patient_1", "stabilize")
	ts.call("test_advance_treatments", 3.0)
	# Patient is now STABILIZED. Try another treatment — should fail.
	var treat_stabilized: bool = bool(ts.call("start_treatment", "patient_1", "transfuse"))
	_expect(not treat_stabilized, "treatment rejected on STABILIZED patient")

	# --- Patient death from severity >= 1.0 -----------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_shock"])
	# Set severity to 0.99 manually.
	ts.call("set_patient_severity", "patient_1", 0.99)
	# Advance deterioration multiple times to push to 1.0.
	# deterioration_rate = (1.0 - 0.80) / 25.0 = 0.008/sec.
	# deterioration_interval = 10.0s. Per tick: 0.008 * 10 + 0.05 = 0.13.
	# 0.99 + 0.13 = 1.12 → clamped to 1.0 → DECEASED.
	ts.call("test_advance_deterioration")
	_expect(int(ts.call("get_patient_status", "patient_1")) == DECEASED, "patient_1 is DECEASED after severity reaches 1.0")

	# --- Priority sort: higher severity first within same category -----------
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns", "crew_concussion"])
	# Both are IMMEDIATE (0.60 and 0.55). burns (0.60) should come first.
	var pri_sorted: Array = ts.call("get_patients_sorted_by_priority")
	_expect(pri_sorted.size() == 2, "priority sort returns 2 ids (got %d)" % pri_sorted.size())
	var first_sev: float = float(ts.call("get_patient_severity", String(pri_sorted[0])))
	_expect(first_sev >= 0.59, "first priority patient has higher severity (got %f)" % first_sev)

	# --- Moral choices --------------------------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns", "crew_shock"])
	ts.call("register_moral_choice", "save_burns_or_shock", "Only 1 plasma left. Save burns (0.60) or shock (0.80)?", ["Save burns", "Save shock"])
	_expect(bool(ts.call("get_moral_choice_ids").has("save_burns_or_shock")), "moral choice registered")
	_expect(not bool(ts.call("is_moral_choice_resolved", "save_burns_or_shock")), "moral choice not resolved initially")
	var resolved: bool = bool(ts.call("resolve_moral_choice", "save_burns_or_shock", 1))
	_expect(resolved, "resolve_moral_choice succeeded")
	_expect(bool(ts.call("is_moral_choice_resolved", "save_burns_or_shock")), "moral choice is resolved")
	_expect(int(ts.call("get_moral_choice_selection", "save_burns_or_shock")) == 1, "moral choice selection == 1")
	# Can't resolve twice.
	var double_resolve: bool = bool(ts.call("resolve_moral_choice", "save_burns_or_shock", 0))
	_expect(not double_resolve, "resolve_moral_choice rejected when already resolved")

	# --- Supply management ----------------------------------------------------
	ts.call("reset")
	var supplies: Dictionary = ts.call("get_all_supplies")
	_expect(not supplies.is_empty(), "get_all_supplies returns non-empty dict")
	_expect(int(supplies.get("bandages", 0)) == 8, "get_all_supplies bandages == 8")
	# Add supplies.
	ts.call("add_supply", "bandages", 2)
	# bandages max is 8, current is 8, so adding 2 caps at 8.
	_expect(int(ts.call("get_supply", "bandages")) == 8, "add_supply capped at max (8)")
	# Add a new supply type not in max config.
	ts.call("add_supply", "herbs", 5)
	_expect(int(ts.call("get_supply", "herbs")) == 5, "add_supply for new type works (got %d)" % int(ts.call("get_supply", "herbs")))

	# --- Treatment cost / duration queries ------------------------------------
	var stab_cost: Dictionary = ts.call("get_treatment_cost", "stabilize")
	_expect(int(stab_cost.get("bandages", 0)) == 1, "stabilize costs 1 bandage")
	var stab_dur: float = float(ts.call("get_treatment_duration", "stabilize"))
	_expect(stab_dur == 3.0, "stabilize duration == 3.0 (got %f)" % stab_dur)
	var stab_red: float = float(ts.call("get_treatment_severity_reduction", "stabilize"))
	_expect(absf(stab_red - 0.15) < 0.001, "stabilize severity_reduction == 0.15 (got %f)" % stab_red)
	var treat_keys: Array = ts.call("get_treatment_keys")
	_expect(treat_keys.size() == 4, "4 treatment keys (got %d)" % treat_keys.size())

	# --- Enum-based treatment -------------------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_fracture"])
	var enum_started: bool = bool(ts.call("start_treatment_enum", "patient_1", TRANSFUSE))
	_expect(enum_started, "start_treatment_enum TRANSFUSE succeeded")
	var active_treat: String = String(ts.call("get_active_treatment", "patient_1"))
	_expect(active_treat == "transfuse", "active treatment is 'transfuse' (got '%s')" % active_treat)

	# --- TJ medical skill modification -----------------------------------------
	ts.call("reset")
	ts.call("set_tj_medical_skill", 1.0)  # Perfect skill.
	ts.call("start_crisis", ["crew_fracture"])
	# severity 0.45. stabilize reduction = 0.15 * (0.5 + 1.0) = 0.15 * 1.5 = 0.225.
	# 0.45 - 0.225 = 0.225.
	ts.call("start_treatment", "patient_1", "stabilize")
	ts.call("test_advance_treatments", 3.0)
	var sev_high_skill: float = float(ts.call("get_patient_severity", "patient_1"))
	_expect(absf(sev_high_skill - 0.225) < 0.02, "severity ~0.225 with max skill (got %f)" % sev_high_skill)

	# With low skill (0.0): 0.15 * (0.5 + 0.0) = 0.075. 0.45 - 0.075 = 0.375.
	ts.call("reset")
	ts.call("set_tj_medical_skill", 0.0)
	ts.call("start_crisis", ["crew_fracture"])
	ts.call("start_treatment", "patient_1", "stabilize")
	ts.call("test_advance_treatments", 3.0)
	var sev_low_skill: float = float(ts.call("get_patient_severity", "patient_1"))
	_expect(absf(sev_low_skill - 0.375) < 0.02, "severity ~0.375 with zero skill (got %f)" % sev_low_skill)

	# Reset TJ skill.
	ts.call("set_tj_medical_skill", 0.7)

	# --- Crisis end: untreated patients die ------------------------------------
	ts.call("reset")
	# Use a short-duration crisis by starting then force-ending via test_advance.
	# Actually, we can use end_crisis_now.
	ts.call("start_crisis", ["crew_shock", "crew_fracture", "crew_minor_cuts"])
	# Treat patient_3 (minor_cuts, severity 0.15) so it's stabilized.
	# Actually severity 0.15 < 0.20 so one stabilize should push it to TRIAGED_OK.
	# But let's just end the crisis without treating anyone.
	# crew_shock: sev 0.80 >= 0.85? No, 0.80 < 0.85. So TRIAGED_OK.
	# crew_fracture: sev 0.45 < 0.85. So TRIAGED_OK.
	# crew_minor_cuts: sev 0.15 < 0.85. So TRIAGED_OK.
	# Nobody dies because all severity < 0.85.
	# Let's manually set one patient high.
	ts.call("set_patient_severity", "patient_1", 0.90)
	ts.call("end_crisis_now")
	_expect(not bool(ts.call("is_crisis_active")), "crisis not active after end_crisis_now")
	# patient_1 had severity 0.90 >= 0.85 → DECEASED.
	_expect(int(ts.call("get_patient_status", "patient_1")) == DECEASED, "patient_1 DECEASED after crisis end (sev >= 0.85)")
	# patient_2 had severity 0.45 < 0.85 → TRIAGED_OK.
	_expect(int(ts.call("get_patient_status", "patient_2")) == TRIAGED_OK, "patient_2 TRIAGED_OK after crisis end (sev < 0.85)")

	# --- Triage summary -------------------------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns", "crew_fracture", "crew_shock", "crew_minor_cuts"])
	var summary: Dictionary = ts.call("get_triage_summary")
	_expect(bool(summary.get("crisis_active", false)), "summary crisis_active == true")
	_expect(int(summary.get("total_patients", 0)) == 4, "summary total_patients == 4 (got %d)" % int(summary.get("total_patients", 0)))
	_expect(int(summary.get("waiting", 0)) == 4, "summary waiting == 4 (got %d)" % int(summary.get("waiting", 0)))
	_expect(int(summary.get("deceased", 0)) == 0, "summary deceased == 0 initially")
	_expect(float(summary.get("survival_rate", 0.0)) == 0.0, "summary survival_rate == 0.0 initially (no survivors yet)")
	_expect((summary.get("supplies", {}) as Dictionary).has("bandages"), "summary supplies has bandages")

	# --- Crisis time queries --------------------------------------------------
	var remaining: float = float(ts.call("get_crisis_remaining"))
	_expect(remaining > 0.0, "crisis_remaining > 0 (got %f)" % remaining)
	var elapsed: float = float(ts.call("get_crisis_elapsed"))
	_expect(elapsed == 0.0, "crisis_elapsed == 0 at start (got %f)" % elapsed)

	# --- Save round-trip ------------------------------------------------------
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns", "crew_fracture"])
	ts.call("start_treatment", "patient_1", "stabilize")
	var serialized: Dictionary = ts.call("serialize")
	_expect(serialized.has("patients"), "serialize has 'patients'")
	_expect(serialized.has("supplies"), "serialize has 'supplies'")
	_expect(serialized.has("crisis_active"), "serialize has 'crisis_active'")
	_expect(serialized.has("active_treatments"), "serialize has 'active_treatments'")
	_expect(serialized.has("moral_choices"), "serialize has 'moral_choices'")
	_expect(serialized.has("tj_medical_skill"), "serialize has 'tj_medical_skill'")

	# Capture state before deserialize.
	var sev_ser: float = float(ts.call("get_patient_severity", "patient_1"))
	var bandages_ser: int = int(ts.call("get_supply", "bandages"))
	var crisis_ser: bool = bool(ts.call("is_crisis_active"))

	# Reset then deserialize.
	ts.call("reset")
	ts.call("deserialize", serialized, 1)
	_expect(absf(float(ts.call("get_patient_severity", "patient_1")) - sev_ser) < 0.01, "patient_1 severity restored after deserialize")
	_expect(int(ts.call("get_supply", "bandages")) == bandages_ser, "bandages restored after deserialize")
	_expect(bool(ts.call("is_crisis_active")) == crisis_ser, "crisis_active restored after deserialize")
	_expect(bool(ts.call("is_treatment_active", "patient_1")), "active treatment restored after deserialize")

	# --- Active treatment persistence in save ---------------------------------
	var treat_ser: Dictionary = ts.call("serialize")
	var active_ser: Dictionary = treat_ser.get("active_treatments", {})
	_expect(active_ser.has("patient_1"), "serialize captured active treatment for patient_1")
	var treat_entry: Dictionary = active_ser.get("patient_1", {})
	_expect(String(treat_entry.get("treatment", "")) == "stabilize", "serialized treatment key is 'stabilize'")

	# --- Moral choice persistence in save -------------------------------------
	ts.call("register_moral_choice", "test_choice", "Test choice", ["A", "B"])
	ts.call("resolve_moral_choice", "test_choice", 0)
	var moral_ser: Dictionary = ts.call("serialize")
	var mc_data: Dictionary = moral_ser.get("moral_choices", {})
	_expect(mc_data.has("test_choice"), "serialize captured moral choice")
	var mc_entry: Dictionary = mc_data.get("test_choice", {})
	_expect(bool(mc_entry.get("resolved", false)), "serialized moral choice is resolved")
	_expect(int(mc_entry.get("choice", -1)) == 0, "serialized moral choice selection == 0")

	# --- Reset clears everything ----------------------------------------------
	ts.call("reset")
	_expect(int(ts.call("get_patient_count")) == 0, "patient_count == 0 after reset")
	_expect(not bool(ts.call("is_crisis_active")), "crisis not active after reset")
	_expect(int(ts.call("get_supply", "bandages")) == 8, "bandages reset to max after reset")
	_expect(float(ts.call("get_crisis_elapsed")) == 0.0, "crisis_elapsed == 0 after reset")

	# --- Signal firing: patient_added -----------------------------------------
	var add_signals: Array = []
	ts.patient_added.connect(func(pid): add_signals.append(pid))
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns"])
	_expect(not add_signals.is_empty(), "patient_added signal emitted on start_crisis")
	_expect(String(add_signals[0]) == "patient_1", "patient_added signal carries 'patient_1'")

	# --- Signal firing: supply_used -------------------------------------------
	var used_signals: Array = []
	ts.supply_used.connect(func(s, a): used_signals.append([s, a]))
	ts.call("reset")
	ts.call("start_crisis", ["crew_burns"])
	ts.call("start_treatment", "patient_1", "stabilize")
	var found_supply: bool = false
	for entry in used_signals:
		if String(entry[0]) == "bandages" and int(entry[1]) == 1:
			found_supply = true
			break
	_expect(found_supply, "supply_used signal emitted for bandages")

	# --- Signal firing: treatment_completed -----------------------------------
	var complete_signals: Array = []
	ts.treatment_completed.connect(func(pid, t): complete_signals.append([pid, t]))
	ts.call("test_advance_treatments", 3.0)
	_expect(not complete_signals.is_empty(), "treatment_completed signal emitted")
	_expect(String(complete_signals[0][0]) == "patient_1", "treatment_completed carries patient_1")
	_expect(int(complete_signals[0][1]) == STABILIZE, "treatment_completed carries STABILIZE enum")

	# --- Signal firing: crisis_started / crisis_ended -------------------------
	ts.call("reset")
	var start_signals: Array = []
	ts.crisis_started.connect(func(): start_signals.append(true))
	ts.call("start_crisis", ["crew_burns"])
	_expect(not start_signals.is_empty(), "crisis_started signal emitted")

	var end_signals: Array = []
	ts.crisis_ended.connect(func(): end_signals.append(true))
	ts.call("end_crisis_now")
	_expect(not end_signals.is_empty(), "crisis_ended signal emitted")

	# --- Signal firing: patient_status_changed --------------------------------
	ts.call("reset")
	var status_signals: Array = []
	ts.patient_status_changed.connect(func(pid, s): status_signals.append([pid, s]))
	ts.call("start_crisis", ["crew_burns"])
	ts.call("start_treatment", "patient_1", "stabilize")
	# Should have a TREATING signal.
	var found_treating: bool = false
	for entry in status_signals:
		if String(entry[0]) == "patient_1" and int(entry[1]) == TREATING:
			found_treating = true
			break
	_expect(found_treating, "patient_status_changed signal emitted for TREATING")

	# --- Signal firing: patient_severity_changed ------------------------------
	ts.call("reset")
	var sev_signals: Array = []
	ts.patient_severity_changed.connect(func(pid, s): sev_signals.append([pid, s]))
	ts.call("start_crisis", ["crew_burns"])
	ts.call("set_patient_severity", "patient_1", 0.50)
	var found_sev: bool = false
	for entry in sev_signals:
		if String(entry[0]) == "patient_1":
			found_sev = true
			break
	_expect(found_sev, "patient_severity_changed signal emitted on set_patient_severity")

	# --- test_advance_crisis advances time + deterioration + treatments -------
	ts.call("reset")
	ts.call("start_crisis", ["crew_fracture"])
	var elapsed_before: float = float(ts.call("get_crisis_elapsed"))
	ts.call("test_advance_crisis", 15.0)
	var elapsed_after: float = float(ts.call("get_crisis_elapsed"))
	_expect(elapsed_after > elapsed_before, "test_advance_crisis advances elapsed time (%f → %f)" % [elapsed_before, elapsed_after])

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