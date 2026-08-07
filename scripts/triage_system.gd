extends Node

# TriageSystem — Mass casualty triage mechanic for E19 "Triage".
#
# A major crisis causes many injuries. The player must prioritize patients by
# severity, manage limited medical supplies, and race against time. Moral
# choices emerge: the player cannot save everyone.
#
# Triage categories (standard S.T.A.R.T. protocol):
#   IMMEDIATE  — red tag, life-threatening, treat first.
#   DELAYED    — yellow tag, serious but stable, treat second.
#   MINIMAL    — green tag, walking wounded, treat last.
#   EXPECTANT   — black tag, likely fatal, comfort only.
#
# Each patient has:
#   - severity (0.0 to 1.0): how close to death.
#   - time_to_critical: seconds until severity hits 1.0 without treatment.
#   - category: triage tag assigned from initial severity.
#   - status: WAITING, TREATING, STABILIZED, DECEASED, TRIAGED_OK.
#
# The player assigns treatments (stabilize, transfuse, stimulate,
# emergency_surgery). Each costs supplies and time. TJ's medical skill
# modifies severity reduction (higher skill = better results).
#
# Integration:
#   - TimerSystem: crisis countdown timer.
#   - InjurySystem: individual patient injuries feed into the registry.
#   - GameState: publishes triage stats (active patients, supplies).
#   - SaveManager: serialize/deserialize patient roster + supplies.
#
# Save contract: patients, supplies, crisis_active, crisis_elapsed.

# ── Triage category enum ──────────────────────────────────────────────────────
#
# Standard triage tags. Higher = more urgent.
#   IMMEDIATE  — life-threatening, must treat now.
#   DELAYED    — serious, can wait briefly.
#   MINIMAL    — minor, treat after others.
#   EXPECTANT  — likely fatal, comfort measures only.

enum TriageCategory { IMMEDIATE, DELAYED, MINIMAL, EXPECTANT }

# ── Patient status enum ───────────────────────────────────────────────────────

enum PatientStatus { WAITING, TREATING, STABILIZED, DECEASED, TRIAGED_OK }

# ── Treatment enum ─────────────────────────────────────────────────────────────

enum Treatment { STABILIZE, TRANSFUSE, STIMULATE, EMERGENCY_SURGERY }

signal patient_added(patient_id: String)
signal patient_removed(patient_id: String)
signal patient_status_changed(patient_id: String, status: int)
signal patient_severity_changed(patient_id: String, severity: float)
signal patient_category_changed(patient_id: String, category: int)
signal treatment_started(patient_id: String, treatment: int)
signal treatment_completed(patient_id: String, treatment: int)
signal supply_used(supply: String, amount: int)
signal supply_added(supply: String, amount: int)
signal crisis_started()
signal crisis_ended()
signal crisis_time_expired()
signal moral_choice_presented(choice_id: String)
signal moral_choice_resolved(choice_id: String, choice: int)

const TRIAGE_CONFIG_PATH: String = "res://data/triage_config.json"
const CRISIS_TIMER_ID: String = "triage_crisis"

# ── Config ────────────────────────────────────────────────────────────────────

var _crisis_duration: float = 120.0
var _deterioration_interval: float = 10.0
var _deterioration_amount: float = 0.05
var _tj_medical_skill_base: float = 0.7
var _max_supplies: Dictionary = {}
var _treatments: Dictionary = {}
var _patient_archetypes: Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────

var _patients: Dictionary = {}       # patient_id → patient dict
var _supplies: Dictionary = {}        # supply_name → int count
var _crisis_active: bool = false
var _crisis_elapsed: float = 0.0
var _deterioration_accumulator: float = 0.0
var _active_treatments: Dictionary = {}  # patient_id → {treatment, remaining, total}
var _moral_choices: Dictionary = {}     # choice_id → {description, options, resolved, choice}
var _patient_counter: int = 0
var _loaded: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_init_supplies()
	_register_with_save_manager()

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	if not _crisis_active:
		return
	_crisis_elapsed += delta
	# Deterioration tick — all waiting patients get worse over time.
	_deterioration_accumulator += delta
	if _deterioration_accumulator >= _deterioration_interval:
		_deterioration_accumulator -= _deterioration_interval
		_deteriorate_patients()
	# Tick active treatments.
	_tick_treatments(delta)
	# Check crisis timer expiry.
	if _crisis_elapsed >= _crisis_duration:
		_end_crisis()

# ── Config loading ────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(TRIAGE_CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("TriageSystem: cannot open %s" % TRIAGE_CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("TriageSystem: %s did not parse to a Dictionary" % TRIAGE_CONFIG_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_crisis_duration = float(d.get("crisis_duration_seconds", 120.0))
	_deterioration_interval = float(d.get("deterioration_interval", 10.0))
	_deterioration_amount = float(d.get("deterioration_amount", 0.05))
	_tj_medical_skill_base = float(d.get("tj_medical_skill_base", 0.7))
	var raw_max: Variant = d.get("max_medical_supplies", {})
	if raw_max is Dictionary:
		_max_supplies = (raw_max as Dictionary).duplicate(true)
	var raw_treat: Variant = d.get("treatments", {})
	if raw_treat is Dictionary:
		_treatments = (raw_treat as Dictionary).duplicate(true)
	var raw_arch: Variant = d.get("patient_archetypes", {})
	if raw_arch is Dictionary:
		_patient_archetypes = (raw_arch as Dictionary).duplicate(true)

func _init_supplies() -> void:
	_supplies.clear()
	for supply_name in _max_supplies.keys():
		_supplies[String(supply_name)] = int(_max_supplies[supply_name])

# ── Crisis management ────────────────────────────────────────────────────────

## Start the mass casualty crisis. Spawns patients from the archetype list and
## starts the TimerSystem crisis countdown. Returns false if a crisis is already
## active.
func start_crisis(patient_archetype_keys: Array = []) -> bool:
	if _crisis_active:
		return false
	_patients.clear()
	_active_treatments.clear()
	_moral_choices.clear()
	_patient_counter = 0
	_crisis_elapsed = 0.0
	_deterioration_accumulator = 0.0
	_init_supplies()
	# Spawn patients: use provided keys or all archetypes.
	var keys: Array = patient_archetype_keys
	if keys.is_empty():
		for k in _patient_archetypes.keys():
			keys.append(String(k))
	for arch_key in keys:
		if not _patient_archetypes.has(arch_key):
			push_warning("TriageSystem: unknown patient archetype '%s'" % arch_key)
			continue
		_spawn_patient(arch_key)
	_crisis_active = true
	# Start the crisis timer in TimerSystem.
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("start_timer"):
		ts.call("start_timer", CRISIS_TIMER_ID, _crisis_duration, 2, true)  # Category.CRISIS == 2
	crisis_started.emit()
	return true

## End the crisis. All waiting patients deteriorate to their final state.
## Stabilized/triaged_ok patients survive. Others may die.
func _end_crisis() -> void:
	if not _crisis_active:
		return
	_crisis_active = false
	# Resolve all remaining patients.
	for patient_id in _patients.keys():
		var p: Dictionary = _patients[patient_id]
		var status: int = int(p.get("status", PatientStatus.WAITING))
		if status == PatientStatus.WAITING or status == PatientStatus.TREATING:
			# Untreated patients at high severity die.
			var sev: float = float(p.get("severity", 0.0))
			if sev >= 0.85:
				_set_patient_status(String(patient_id), PatientStatus.DECEASED)
			else:
				# Low-severity patients survive with minor injuries.
				_set_patient_status(String(patient_id), PatientStatus.TRIAGED_OK)
	# Cancel the crisis timer.
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("cancel_timer"):
		ts.call("cancel_timer", CRISIS_TIMER_ID)
	crisis_ended.emit()
	crisis_time_expired.emit()

## Force-end the crisis immediately (for tests / debug).
func end_crisis_now() -> void:
	_end_crisis()

## Check if the crisis is active.
func is_crisis_active() -> bool:
	return _crisis_active

## Get elapsed crisis time in seconds.
func get_crisis_elapsed() -> float:
	return _crisis_elapsed

## Get remaining crisis time in seconds.
func get_crisis_remaining() -> float:
	return maxf(0.0, _crisis_duration - _crisis_elapsed)

## Get the crisis duration.
func get_crisis_duration() -> float:
	return _crisis_duration

# ── Patient management ───────────────────────────────────────────────────────

func _spawn_patient(archetype_key: String) -> String:
	_patient_counter += 1
	var pid: String = "patient_%d" % _patient_counter
	var arch: Dictionary = _patient_archetypes[archetype_key] as Dictionary
	var sev: float = float(arch.get("initial_severity", 0.5))
	var cat: int = _category_from_severity(sev)
	# Override with archetype category if specified.
	var arch_cat: String = String(arch.get("initial_category", ""))
	if not arch_cat.is_empty():
		cat = _category_string_to_enum(arch_cat)
	var ttc: float = float(arch.get("time_to_critical", 60.0))
	_patients[pid] = {
		"name": String(arch.get("name", "Unknown")),
		"injury_type": String(arch.get("injury_type", "")),
		"severity": sev,
		"initial_severity": sev,
		"category": cat,
		"status": PatientStatus.WAITING,
		"time_to_critical": ttc,
		"deterioration_rate": _compute_deterioration_rate(sev, ttc),
		"treatment_count": 0,
		"archetype_key": archetype_key,
	}
	patient_added.emit(pid)
	patient_severity_changed.emit(pid, sev)
	patient_category_changed.emit(pid, cat)
	return pid

func _compute_deterioration_rate(severity: float, time_to_critical: float) -> float:
	# Rate of severity increase per second to reach 1.0 in time_to_critical.
	if time_to_critical <= 0.0:
		return 0.0
	return (1.0 - severity) / time_to_critical

func _category_from_severity(severity: float) -> int:
	if severity >= 0.75:
		return TriageCategory.IMMEDIATE
	elif severity >= 0.45:
		return TriageCategory.DELAYED
	elif severity >= 0.20:
		return TriageCategory.MINIMAL
	else:
		return TriageCategory.EXPECTANT

func _category_string_to_enum(s: String) -> int:
	match s:
		"IMMEDIATE":
			return TriageCategory.IMMEDIATE
		"DELAYED":
			return TriageCategory.DELAYED
		"MINIMAL":
			return TriageCategory.MINIMAL
		"EXPECTANT":
			return TriageCategory.EXPECTANT
		_:
			return TriageCategory.DELAYED

func _category_enum_to_string(c: int) -> String:
	match c:
		TriageCategory.IMMEDIATE:
			return "IMMEDIATE"
		TriageCategory.DELAYED:
			return "DELAYED"
		TriageCategory.MINIMAL:
			return "MINIMAL"
		TriageCategory.EXPECTANT:
			return "EXPECTANT"
		_:
			return "DELAYED"

## Get a patient dict by id.
func get_patient(patient_id: String) -> Dictionary:
	return _patients.get(patient_id, {})

## Get all patient ids.
func get_patient_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _patients.keys():
		out.append(String(k))
	return out

## Get patient count.
func get_patient_count() -> int:
	return _patients.size()

## Get patient severity (0.0 to 1.0).
func get_patient_severity(patient_id: String) -> float:
	if not _patients.has(patient_id):
		return 0.0
	return float(_patients[patient_id].get("severity", 0.0))

## Get patient category (TriageCategory enum int).
func get_patient_category(patient_id: String) -> int:
	if not _patients.has(patient_id):
		return TriageCategory.DELAYED
	return int(_patients[patient_id].get("category", TriageCategory.DELAYED))

## Get patient status (PatientStatus enum int).
func get_patient_status(patient_id: String) -> int:
	if not _patients.has(patient_id):
		return PatientStatus.WAITING
	return int(_patients[patient_id].get("status", PatientStatus.WAITING))

## Get patient name.
func get_patient_name(patient_id: String) -> String:
	if not _patients.has(patient_id):
		return ""
	return String(_patients[patient_id].get("name", ""))

## Get patient injury type description.
func get_patient_injury_type(patient_id: String) -> String:
	if not _patients.has(patient_id):
		return ""
	return String(_patients[patient_id].get("injury_type", ""))

## Get the number of treatments applied to a patient.
func get_patient_treatment_count(patient_id: String) -> int:
	if not _patients.has(patient_id):
		return 0
	return int(_patients[patient_id].get("treatment_count", 0))

## Manually set patient severity (for tests / scripted events).
func set_patient_severity(patient_id: String, severity: float) -> void:
	if not _patients.has(patient_id):
		return
	var clamped: float = clampf(severity, 0.0, 1.0)
	_patients[patient_id]["severity"] = clamped
	# Recompute category.
	var new_cat: int = _category_from_severity(clamped)
	var prev_cat: int = int(_patients[patient_id].get("category", TriageCategory.DELAYED))
	if prev_cat != new_cat:
		_patients[patient_id]["category"] = new_cat
		patient_category_changed.emit(patient_id, new_cat)
	patient_severity_changed.emit(patient_id, clamped)

func _set_patient_status(patient_id: String, status: int) -> void:
	if not _patients.has(patient_id):
		return
	var prev: int = int(_patients[patient_id].get("status", PatientStatus.WAITING))
	if prev != status:
		_patients[patient_id]["status"] = status
		patient_status_changed.emit(patient_id, status)

## Get patients filtered by status. Returns Array[String] of patient ids.
func get_patients_by_status(status: int) -> Array[String]:
	var out: Array[String] = []
	for pid in _patients.keys():
		if int(_patients[pid].get("status", PatientStatus.WAITING)) == status:
			out.append(String(pid))
	return out

## Get patients filtered by category. Returns Array[String] of patient ids.
func get_patients_by_category(category: int) -> Array[String]:
	var out: Array[String] = []
	for pid in _patients.keys():
		if int(_patients[pid].get("category", TriageCategory.DELAYED)) == category:
			out.append(String(pid))
	return out

## Get patients sorted by priority (IMMEDIATE first, then DELAYED, MINIMAL,
## EXPECTANT). Within same category, higher severity comes first.
## Returns Array[String] of patient ids.
func get_patients_sorted_by_priority() -> Array[String]:
	var waiting: Array = []
	for pid in _patients.keys():
		var p: Dictionary = _patients[pid]
		if int(p.get("status", PatientStatus.WAITING)) == PatientStatus.WAITING:
			waiting.append(pid)
	# Sort: lower category enum = higher priority (IMMEDIATE == 0).
	waiting.sort_custom(func(a, b) -> bool:
		var cat_a: int = int(_patients[a].get("category", TriageCategory.DELAYED))
		var cat_b: int = int(_patients[b].get("category", TriageCategory.DELAYED))
		if cat_a != cat_b:
			return cat_a < cat_b
		var sev_a: float = float(_patients[a].get("severity", 0.0))
		var sev_b: float = float(_patients[b].get("severity", 0.0))
		return sev_a > sev_b
	)
	var out: Array[String] = []
	for pid in waiting:
		out.append(String(pid))
	return out

# ── Deterioration ─────────────────────────────────────────────────────────────

func _deteriorate_patients() -> void:
	for pid in _patients.keys():
		var p: Dictionary = _patients[pid]
		var status: int = int(p.get("status", PatientStatus.WAITING))
		# Only waiting patients deteriorate. Stabilized/triaged patients are safe.
		if status != PatientStatus.WAITING:
			continue
		var rate: float = float(p.get("deterioration_rate", 0.0))
		var sev: float = float(p.get("severity", 0.0))
		sev = clampf(sev + rate * _deterioration_interval + _deterioration_amount, 0.0, 1.0)
		p["severity"] = sev
		# Recompute category.
		var new_cat: int = _category_from_severity(sev)
		var prev_cat: int = int(p.get("category", TriageCategory.DELAYED))
		if prev_cat != new_cat:
			p["category"] = new_cat
			patient_category_changed.emit(String(pid), new_cat)
		patient_severity_changed.emit(String(pid), sev)
		# If severity hits 1.0, patient dies.
		if sev >= 1.0:
			_set_patient_status(String(pid), PatientStatus.DECEASED)

# ── Treatment system ─────────────────────────────────────────────────────────

## Start a treatment on a patient. Returns false if:
##   - Patient doesn't exist or is not WAITING.
##   - Treatment is unknown.
##   - A treatment is already active on this patient.
##   - Insufficient supplies.
func start_treatment(patient_id: String, treatment_key: String) -> bool:
	if not _patients.has(patient_id):
		return false
	var p: Dictionary = _patients[patient_id]
	var status: int = int(p.get("status", PatientStatus.WAITING))
	if status != PatientStatus.WAITING:
		return false
	if _active_treatments.has(patient_id):
		return false
	if not _treatments.has(treatment_key):
		return false
	var treat: Dictionary = _treatments[treatment_key] as Dictionary
	# Check supplies.
	var cost: Dictionary = treat.get("supplies", {})
	if not _has_supplies(cost):
		return false
	# Consume supplies.
	_spend_supplies(cost)
	# Mark as treating.
	_set_patient_status(patient_id, PatientStatus.TREATING)
	var duration: float = float(treat.get("duration", 3.0))
	_active_treatments[patient_id] = {
		"treatment": treatment_key,
		"remaining": duration,
		"total": duration,
		"halts_deterioration": bool(treat.get("halts_deterioration", true)),
		"severity_reduction": float(treat.get("severity_reduction", 0.15)),
	}
	treatment_started.emit(patient_id, _treatment_key_to_enum(treatment_key))
	return true

## Start a treatment using the Treatment enum.
func start_treatment_enum(patient_id: String, treatment: int) -> bool:
	return start_treatment(patient_id, _treatment_enum_to_key(treatment))

## Check if a patient is currently being treated.
func is_treatment_active(patient_id: String) -> bool:
	return _active_treatments.has(patient_id)

## Get treatment progress (0.0 to 1.0). 0.0 if no active treatment.
func get_treatment_progress(patient_id: String) -> float:
	if not _active_treatments.has(patient_id):
		return 0.0
	var job: Dictionary = _active_treatments[patient_id]
	var total: float = float(job.get("total", 0.0))
	if total <= 0.0:
		return 1.0
	return 1.0 - clampf(float(job.get("remaining", 0.0)) / total, 0.0, 1.0)

## Get the active treatment key for a patient. Empty string if none.
func get_active_treatment(patient_id: String) -> String:
	if not _active_treatments.has(patient_id):
		return ""
	return String(_active_treatments[patient_id].get("treatment", ""))

func _tick_treatments(delta: float) -> void:
	if _active_treatments.is_empty():
		return
	var completed: Array[String] = []
	for pid in _active_treatments.keys():
		var job: Dictionary = _active_treatments[pid]
		job["remaining"] = maxf(0.0, float(job["remaining"]) - delta)
		_active_treatments[pid] = job
		if float(job["remaining"]) <= 0.0:
			completed.append(String(pid))
	for pid in completed:
		var job: Dictionary = _active_treatments[pid]
		var treatment_key: String = String(job.get("treatment", "stabilize"))
		_apply_treatment_result(pid, treatment_key, job)
		_active_treatments.erase(pid)
		treatment_completed.emit(pid, _treatment_key_to_enum(treatment_key))

func _apply_treatment_result(patient_id: String, treatment_key: String, job: Dictionary) -> void:
	if not _patients.has(patient_id):
		return
	var p: Dictionary = _patients[patient_id]
	var base_reduction: float = float(job.get("severity_reduction", 0.15))
	# TJ's medical skill modifies the reduction. Higher skill = better result.
	var skill: float = _get_tj_medical_skill()
	var actual_reduction: float = base_reduction * (0.5 + skill)
	var sev: float = float(p.get("severity", 0.0))
	sev = clampf(sev - actual_reduction, 0.0, 1.0)
	p["severity"] = sev
	p["treatment_count"] = int(p.get("treatment_count", 0)) + 1
	# Recompute category.
	var new_cat: int = _category_from_severity(sev)
	var prev_cat: int = int(p.get("category", TriageCategory.DELAYED))
	if prev_cat != new_cat:
		p["category"] = new_cat
		patient_category_changed.emit(patient_id, new_cat)
	patient_severity_changed.emit(patient_id, sev)
	# If severity is low enough, patient is stabilized/triaged.
	if sev < 0.20:
		_set_patient_status(patient_id, PatientStatus.TRIAGED_OK)
	else:
		_set_patient_status(patient_id, PatientStatus.STABILIZED)
	# If treatment halts deterioration, reduce the deterioration rate.
	if bool(job.get("halts_deterioration", true)):
		p["deterioration_rate"] = 0.0

# ── Medical supplies ─────────────────────────────────────────────────────────

func _has_supplies(cost: Dictionary) -> bool:
	for supply_name in cost.keys():
		var need: int = int(cost[supply_name])
		var have: int = int(_supplies.get(supply_name, 0))
		if have < need:
			return false
	return true

func _spend_supplies(cost: Dictionary) -> void:
	for supply_name in cost.keys():
		var amount: int = int(cost[supply_name])
		var current: int = int(_supplies.get(supply_name, 0))
		_supplies[supply_name] = max(0, current - amount)
		supply_used.emit(String(supply_name), amount)

## Get the current supply count for a resource.
func get_supply(supply_name: String) -> int:
	return int(_supplies.get(supply_name, 0))

## Get all supplies as a Dictionary (supply_name → count).
func get_all_supplies() -> Dictionary:
	return _supplies.duplicate()

## Add supplies (e.g. from inventory or found cache).
func add_supply(supply_name: String, amount: int) -> void:
	var current: int = int(_supplies.get(supply_name, 0))
	var max_val: int = int(_max_supplies.get(supply_name, 999))
	_supplies[supply_name] = min(max_val, current + amount)
	supply_added.emit(supply_name, amount)

## Get the max supply count for a resource.
func get_max_supply(supply_name: String) -> int:
	return int(_max_supplies.get(supply_name, 0))

## Get the treatment cost dict for a treatment key.
func get_treatment_cost(treatment_key: String) -> Dictionary:
	if not _treatments.has(treatment_key):
		return {}
	return (_treatments[treatment_key] as Dictionary).get("supplies", {}).duplicate()

## Get the treatment duration for a treatment key.
func get_treatment_duration(treatment_key: String) -> float:
	if not _treatments.has(treatment_key):
		return 0.0
	return float(_treatments[treatment_key].get("duration", 0.0))

## Get the base severity reduction for a treatment key.
func get_treatment_severity_reduction(treatment_key: String) -> float:
	if not _treatments.has(treatment_key):
		return 0.0
	return float(_treatments[treatment_key].get("severity_reduction", 0.0))

## Get all treatment keys.
func get_treatment_keys() -> Array[String]:
	var out: Array[String] = []
	for k in _treatments.keys():
		out.append(String(k))
	return out

# ── TJ medical skill ─────────────────────────────────────────────────────────

func _get_tj_medical_skill() -> float:
	# Base skill from config. Could be modified by crew relationships or upgrades.
	return _tj_medical_skill_base

## Get TJ's current medical skill level (0.0 to 1.0).
func get_tj_medical_skill() -> float:
	return _get_tj_medical_skill()

## Set TJ's medical skill (for upgrades or tests).
func set_tj_medical_skill(value: float) -> void:
	_tj_medical_skill_base = clampf(value, 0.0, 1.0)

# ── Moral choices ─────────────────────────────────────────────────────────────

## Register a moral choice. The player must choose between options when
## supplies run low or two critical patients compete for the same resource.
func register_moral_choice(choice_id: String, description: String, options: Array) -> void:
	_moral_choices[choice_id] = {
		"description": description,
		"options": options,
		"resolved": false,
		"choice": -1,
	}
	moral_choice_presented.emit(choice_id)

## Resolve a moral choice. Returns false if the choice doesn't exist or is
## already resolved.
func resolve_moral_choice(choice_id: String, choice: int) -> bool:
	if not _moral_choices.has(choice_id):
		return false
	var mc: Dictionary = _moral_choices[choice_id]
	if bool(mc.get("resolved", false)):
		return false
	mc["resolved"] = true
	mc["choice"] = choice
	_moral_choices[choice_id] = mc
	moral_choice_resolved.emit(choice_id, choice)
	return true

## Get a moral choice dict.
func get_moral_choice(choice_id: String) -> Dictionary:
	return _moral_choices.get(choice_id, {})

## Check if a moral choice is resolved.
func is_moral_choice_resolved(choice_id: String) -> bool:
	if not _moral_choices.has(choice_id):
		return false
	return bool(_moral_choices[choice_id].get("resolved", false))

## Get the player's choice for a moral choice. -1 if unresolved or missing.
func get_moral_choice_selection(choice_id: String) -> int:
	if not _moral_choices.has(choice_id):
		return -1
	return int(_moral_choices[choice_id].get("choice", -1))

## Get all moral choice ids.
func get_moral_choice_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _moral_choices.keys():
		out.append(String(k))
	return out

# ── Triage statistics ─────────────────────────────────────────────────────────

## Get the count of patients by status.
func get_count_by_status(status: int) -> int:
	var count: int = 0
	for pid in _patients.keys():
		if int(_patients[pid].get("status", PatientStatus.WAITING)) == status:
			count += 1
	return count

## Get the count of patients by category.
func get_count_by_category(category: int) -> int:
	var count: int = 0
	for pid in _patients.keys():
		if int(_patients[pid].get("category", TriageCategory.DELAYED)) == category:
			count += 1
	return count

## Get the total number of stabilized patients (STABILIZED + TRIAGED_OK).
func get_survivors_count() -> int:
	return get_count_by_status(PatientStatus.STABILIZED) + get_count_by_status(PatientStatus.TRIAGED_OK)

## Get the number of deceased patients.
func get_deceased_count() -> int:
	return get_count_by_status(PatientStatus.DECEASED)

## Get the number of patients still waiting for treatment.
func get_waiting_count() -> int:
	return get_count_by_status(PatientStatus.WAITING)

## Get the survival rate (0.0 to 1.0). Returns 0.0 if no patients.
func get_survival_rate() -> float:
	var total: int = _patients.size()
	if total == 0:
		return 0.0
	return float(get_survivors_count()) / float(total)

## Get a summary dict for GameState / HUD.
func get_triage_summary() -> Dictionary:
	return {
		"crisis_active": _crisis_active,
		"crisis_remaining": get_crisis_remaining(),
		"total_patients": _patients.size(),
		"waiting": get_waiting_count(),
		"treating": get_count_by_status(PatientStatus.TREATING),
		"stabilized": get_count_by_status(PatientStatus.STABILIZED),
		"triaged_ok": get_count_by_status(PatientStatus.TRIAGED_OK),
		"deceased": get_deceased_count(),
		"survivors": get_survivors_count(),
		"survival_rate": get_survival_rate(),
		"supplies": _supplies.duplicate(),
	}

# ── Save / load (ISaveableSystem) ────────────────────────────────────────────

func serialize() -> Dictionary:
	var patient_data: Dictionary = {}
	for pid in _patients.keys():
		var p: Dictionary = _patients[pid]
		patient_data[pid] = {
			"name": String(p.get("name", "")),
			"injury_type": String(p.get("injury_type", "")),
			"severity": float(p.get("severity", 0.0)),
			"initial_severity": float(p.get("initial_severity", 0.0)),
			"category": int(p.get("category", TriageCategory.DELAYED)),
			"status": int(p.get("status", PatientStatus.WAITING)),
			"time_to_critical": float(p.get("time_to_critical", 60.0)),
			"deterioration_rate": float(p.get("deterioration_rate", 0.0)),
			"treatment_count": int(p.get("treatment_count", 0)),
			"archetype_key": String(p.get("archetype_key", "")),
		}
	var treatment_data: Dictionary = {}
	for pid in _active_treatments.keys():
		var job: Dictionary = _active_treatments[pid]
		treatment_data[pid] = {
			"treatment": String(job.get("treatment", "stabilize")),
			"remaining": float(job.get("remaining", 0.0)),
			"total": float(job.get("total", 0.0)),
			"halts_deterioration": bool(job.get("halts_deterioration", true)),
			"severity_reduction": float(job.get("severity_reduction", 0.15)),
		}
	var moral_data: Dictionary = {}
	for cid in _moral_choices.keys():
		var mc: Dictionary = _moral_choices[cid]
		moral_data[cid] = {
			"description": String(mc.get("description", "")),
			"options": (mc.get("options", []) as Array).duplicate(),
			"resolved": bool(mc.get("resolved", false)),
			"choice": int(mc.get("choice", -1)),
		}
	return {
		"crisis_active": _crisis_active,
		"crisis_elapsed": _crisis_elapsed,
		"patient_counter": _patient_counter,
		"patients": patient_data,
		"supplies": _supplies.duplicate(),
		"active_treatments": treatment_data,
		"moral_choices": moral_data,
		"tj_medical_skill": _tj_medical_skill_base,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_patients.clear()
	_active_treatments.clear()
	_moral_choices.clear()
	_crisis_active = bool(data.get("crisis_active", false))
	_crisis_elapsed = float(data.get("crisis_elapsed", 0.0))
	_patient_counter = int(data.get("patient_counter", 0))
	_tj_medical_skill_base = float(data.get("tj_medical_skill", 0.7))
	# Restore patients.
	var saved_patients: Variant = data.get("patients", {})
	if saved_patients is Dictionary:
		for pid in (saved_patients as Dictionary).keys():
			var p: Dictionary = (saved_patients as Dictionary)[pid] as Dictionary
			if p.is_empty():
				continue
			_patients[String(pid)] = {
				"name": String(p.get("name", "")),
				"injury_type": String(p.get("injury_type", "")),
				"severity": float(p.get("severity", 0.0)),
				"initial_severity": float(p.get("initial_severity", 0.0)),
				"category": int(p.get("category", TriageCategory.DELAYED)),
				"status": int(p.get("status", PatientStatus.WAITING)),
				"time_to_critical": float(p.get("time_to_critical", 60.0)),
				"deterioration_rate": float(p.get("deterioration_rate", 0.0)),
				"treatment_count": int(p.get("treatment_count", 0)),
				"archetype_key": String(p.get("archetype_key", "")),
			}
	# Restore supplies.
	_supplies.clear()
	var saved_supplies: Variant = data.get("supplies", {})
	if saved_supplies is Dictionary:
		for k in (saved_supplies as Dictionary).keys():
			_supplies[String(k)] = int((saved_supplies as Dictionary)[k])
	else:
		_init_supplies()
	# Restore active treatments.
	var saved_treatments: Variant = data.get("active_treatments", {})
	if saved_treatments is Dictionary:
		for pid in (saved_treatments as Dictionary).keys():
			var job: Dictionary = (saved_treatments as Dictionary)[pid] as Dictionary
			if job.is_empty():
				continue
			_active_treatments[String(pid)] = {
				"treatment": String(job.get("treatment", "stabilize")),
				"remaining": float(job.get("remaining", 0.0)),
				"total": float(job.get("total", 0.0)),
				"halts_deterioration": bool(job.get("halts_deterioration", true)),
				"severity_reduction": float(job.get("severity_reduction", 0.15)),
			}
	# Restore moral choices.
	var saved_moral: Variant = data.get("moral_choices", {})
	if saved_moral is Dictionary:
		for cid in (saved_moral as Dictionary).keys():
			var mc: Dictionary = (saved_moral as Dictionary)[cid] as Dictionary
			if mc.is_empty():
				continue
			_moral_choices[String(cid)] = {
				"description": String(mc.get("description", "")),
				"options": (mc.get("options", []) as Array).duplicate(),
				"resolved": bool(mc.get("resolved", false)),
				"choice": int(mc.get("choice", -1)),
			}

func reset() -> void:
	_patients.clear()
	_active_treatments.clear()
	_moral_choices.clear()
	_crisis_active = false
	_crisis_elapsed = 0.0
	_deterioration_accumulator = 0.0
	_patient_counter = 0
	_init_supplies()

# ── Enum conversion helpers ───────────────────────────────────────────────────

func _treatment_enum_to_key(treatment: int) -> String:
	match treatment:
		Treatment.STABILIZE:
			return "stabilize"
		Treatment.TRANSFUSE:
			return "transfuse"
		Treatment.STIMULATE:
			return "stimulate"
		Treatment.EMERGENCY_SURGERY:
			return "emergency_surgery"
		_:
			return "stabilize"

func _treatment_key_to_enum(key: String) -> int:
	match key:
		"stabilize":
			return Treatment.STABILIZE
		"transfuse":
			return Treatment.TRANSFUSE
		"stimulate":
			return Treatment.STIMULATE
		"emergency_surgery":
			return Treatment.EMERGENCY_SURGERY
		_:
			return Treatment.STABILIZE

func _category_enum_to_int(cat: int) -> int:
	return cat

# ── Test hooks ────────────────────────────────────────────────────────────────

## Advance treatment ticks by a fixed delta (bypasses _process, for tests).
func test_advance_treatments(delta: float) -> Array[String]:
	var completed: Array[String] = []
	for pid in _active_treatments.keys():
		var job: Dictionary = _active_treatments[pid]
		job["remaining"] = maxf(0.0, float(job["remaining"]) - delta)
		_active_treatments[pid] = job
		if float(job["remaining"]) <= 0.0:
			completed.append(String(pid))
	for pid in completed:
		var job: Dictionary = _active_treatments[pid]
		var treatment_key: String = String(job.get("treatment", "stabilize"))
		_apply_treatment_result(pid, treatment_key, job)
		_active_treatments.erase(pid)
		treatment_completed.emit(pid, _treatment_key_to_enum(treatment_key))
	return completed

## Advance deterioration by one tick (bypasses _process, for tests).
func test_advance_deterioration() -> void:
	_deteriorate_patients()

## Advance crisis time by delta (bypasses _process, for tests).
func test_advance_crisis(delta: float) -> void:
	if not _crisis_active:
		return
	_crisis_elapsed += delta
	_deterioration_accumulator += delta
	while _deterioration_accumulator >= _deterioration_interval:
		_deterioration_accumulator -= _deterioration_interval
		_deteriorate_patients()
	# Tick treatments.
	_tick_treatments(delta)
	if _crisis_elapsed >= _crisis_duration:
		_end_crisis()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "triage_system", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)