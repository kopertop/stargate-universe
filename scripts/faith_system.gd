extends Node

# FaithSystem — planet settlement and long-term survival for Episode 11: Faith.
#
# Destiny discovers a habitable planet. The crew debates whether to settle
# permanently or continue the mission. The player builds a camp, explores the
# planet, survives environmental events, engages in philosophical dialogue,
# and makes the moral choice: stay, continue, or split the crew.
#
# Phase progression:
#   INACTIVE → DEBATE → LANDING → SETTLEMENT → EXPLORATION → SURVIVAL →
#   MORAL_CHOICE → RESOLVED
#
# Integration:
#   - ShuttleSystem → start_landing / landing completion for shuttle descent
#   - RelationshipSystem → apply_dialogue_action for moral choice effects
#   - FactionSystem → adjust_tension for faction tension changes
#   - GameState → narrate() for story beats, set_flag for world state
#   - QuestLog → quest_step_available checks faith state
#   - SaveManager → serialize/deserialize for save/load round-trip
#
# Data: res://data/faith.json

signal phase_changed(old_phase: int, new_phase: int)
signal structure_built(structure_id: String)
signal site_explored(site_id: String)
signal survival_event_triggered(event_id: String)
signal survival_event_mitigated(event_id: String, structure_id: String)
signal dialogue_triggered(dialogue_id: String)
signal landing_started(zone_id: String)
signal landing_completed(zone_id: String, success: bool)
signal moral_choice_made(choice_id: String)
signal faith_resolved(outcome: String)
signal crew_count_changed(count: int)
signal morale_changed(value: int)
signal health_changed(value: int)
signal day_passed(day: int)
signal resources_changed(resources: Dictionary)
signal build_progress_updated(structure_id: String, progress: float)
signal explore_progress_updated(site_id: String, progress: float)

const DATA_PATH: String = "res://data/faith.json"

# ── Phase enum ────────────────────────────────────────────────────────────────

enum Phase {
	INACTIVE,       # No faith event active.
	DEBATE,         # Crew debates staying vs. continuing.
	LANDING,        # Shuttle descending to planet surface.
	SETTLEMENT,     # Building camp structures.
	EXPLORATION,    # Exploring planet sites.
	SURVIVAL,       # Long-term survival events.
	MORAL_CHOICE,   # Player makes the stay/continue/split choice.
	RESOLVED        # Episode resolved.
}

# ── Config ────────────────────────────────────────────────────────────────────

var _scenario: Dictionary = {}
var _phases_config: Dictionary = {}
var _camp_structures: Dictionary = {}
var _exploration_sites: Dictionary = {}
var _survival_events: Dictionary = {}
var _philosophical_dialogues: Dictionary = {}
var _moral_choices: Dictionary = {}
var _survival_config: Dictionary = {}
var _landing_config: Dictionary = {}

# Ordered structure ids and survival event ids.
var _ordered_structures: Array[String] = []
var _ordered_survival_events: Array[String] = []

# ── State ─────────────────────────────────────────────────────────────────────

var _current_phase: int = Phase.INACTIVE
var _built_structures: Dictionary = {}       # structure_id → true
var _explored_sites: Dictionary = {}         # site_id → true
var _triggered_events: Dictionary = {}       # event_id → true
var _mitigated_events: Dictionary = {}       # event_id → structure_id
var _triggered_dialogues: Dictionary = {}    # dialogue_id → true
var _crew_count: int = 15
var _morale: int = 70
var _health: int = 100
var _current_day: int = 1
var _day_timer: float = 0.0
var _event_timer: float = 0.0
var _next_event_order: int = 1
var _resources: Dictionary = {}
var _landing_zone: String = ""
var _landing_success: bool = false
var _moral_choice_id: String = ""
var _resolution_outcome: String = ""
var _active_build: String = ""
var _build_progress: float = 0.0
var _active_explore: String = ""
var _explore_progress: float = 0.0
var _loaded: bool = false
var _initialized: bool = false

# Default starting resources for the settlement.
const _DEFAULT_RESOURCES: Dictionary = {
	"wood": 10, "stone": 10, "metal": 8, "seeds": 5,
	"water": 10, "food": 10, "crystals": 3, "medicine": 4
}


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_initialized()
	_register_with_save_manager()
	_publish_to_game_state()

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	tick_survival(delta)
	tick_build(delta)
	tick_explore(delta)

func _ensure_initialized() -> void:
	if _initialized:
		return
	_load_config()
	_initialized = true

func _load_config() -> void:
	if _loaded:
		return
	if not FileAccess.file_exists(DATA_PATH):
		push_error("FaithSystem: data file not found: " + DATA_PATH)
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("FaithSystem: cannot open " + DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("FaithSystem: JSON parse error: " + json.get_error_message())
		return
	var data: Dictionary = json.data as Dictionary
	_scenario = data.get("scenario", {})
	_phases_config = data.get("phases", {})
	_camp_structures = data.get("camp_structures", {})
	_exploration_sites = data.get("exploration_sites", {})
	_survival_events = data.get("survival_events", {})
	_philosophical_dialogues = data.get("philosophical_dialogues", {})
	_moral_choices = data.get("moral_choices", {})
	_survival_config = data.get("survival_config", {})
	_landing_config = data.get("landing_config", {})
	# Build ordered lists.
	_ordered_structures.clear()
	var structures_arr: Array = []
	for sid in _camp_structures.keys():
		structures_arr.append(_camp_structures[sid])
	structures_arr.sort_custom(_compare_order)
	for s in structures_arr:
		_ordered_structures.append(String(s.get("id", "")))
	_ordered_survival_events.clear()
	var events_arr: Array = []
	for eid in _survival_events.keys():
		events_arr.append(_survival_events[eid])
	events_arr.sort_custom(_compare_order)
	for e in events_arr:
		_ordered_survival_events.append(String(e.get("id", "")))
	_loaded = true

static func _compare_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))


# ── Phase management ──────────────────────────────────────────────────────────

func get_phase() -> int:
	return _current_phase

func get_phase_name() -> String:
	match _current_phase:
		Phase.INACTIVE: return "Inactive"
		Phase.DEBATE: return "Debate"
		Phase.LANDING: return "Landing"
		Phase.SETTLEMENT: return "Settlement"
		Phase.EXPLORATION: return "Exploration"
		Phase.SURVIVAL: return "Survival"
		Phase.MORAL_CHOICE: return "Moral Choice"
		Phase.RESOLVED: return "Resolved"
		_: return "Unknown"

func _set_phase(new_phase: int) -> void:
	if _current_phase == new_phase:
		return
	var old: int = _current_phase
	_current_phase = new_phase
	phase_changed.emit(old, new_phase)

## Start the faith episode. Sets phase to DEBATE and initializes resources.
func start_faith() -> void:
	_ensure_initialized()
	_crew_count = int(_survival_config.get("crew_count_start", 15))
	_morale = int(_survival_config.get("morale_start", 70))
	_health = int(_survival_config.get("health_start", 100))
	_current_day = 1
	_day_timer = 0.0
	_event_timer = 0.0
	_next_event_order = 1
	_resources = _DEFAULT_RESOURCES.duplicate(true)
	_built_structures.clear()
	_explored_sites.clear()
	_triggered_events.clear()
	_mitigated_events.clear()
	_triggered_dialogues.clear()
	_landing_zone = ""
	_landing_success = false
	_moral_choice_id = ""
	_resolution_outcome = ""
	_active_build = ""
	_build_progress = 0.0
	_active_explore = ""
	_explore_progress = 0.0
	crew_count_changed.emit(_crew_count)
	morale_changed.emit(_morale)
	health_changed.emit(_health)
	resources_changed.emit(_resources.duplicate())
	_set_phase(Phase.DEBATE)

## Advance from DEBATE to LANDING. Initiates the shuttle landing sequence.
func begin_landing() -> bool:
	if _current_phase != Phase.DEBATE:
		return false
	_landing_zone = String(_landing_config.get("landing_zone_id", "plateau_north"))
	# Try to use ShuttleSystem for the landing sequence.
	var shuttle: Node = _autoload("ShuttleSystem")
	if shuttle != null:
		var shuttle_type: String = String(_scenario.get("shuttle_type", "destiny_shuttle"))
		if shuttle.has_method("select_shuttle"):
			shuttle.call("select_shuttle", shuttle_type)
		if shuttle.has_method("start_flight"):
			shuttle.call("start_flight", int(shuttle.FlightEnv.ATMOSPHERIC))
		if shuttle.has_method("start_landing"):
			shuttle.call("start_landing", _landing_zone)
	landing_started.emit(_landing_zone)
	_set_phase(Phase.LANDING)
	return true

## Complete the landing. Called when ShuttleSystem reports landing success
## or called directly for tests.
func complete_landing(success: bool) -> void:
	if _current_phase != Phase.LANDING:
		return
	_landing_success = success
	landing_completed.emit(_landing_zone, success)
	if success:
		_set_phase(Phase.SETTLEMENT)
		_narrate("The shuttle touches down on the plateau. The air is breathable. The sky is blue. For the first time, the crew stands on solid ground.")
	else:
		# Hard landing — still survive, but with damage.
		_health = maxi(0, _health - int(float(_landing_config.get("hard_landing_damage", 5.0))))
		health_changed.emit(_health)
		_set_phase(Phase.SETTLEMENT)
		_narrate("The shuttle hits the ground hard. The crew stumbles out, bruised but alive. The camp must be built quickly.")

## Advance from SETTLEMENT to EXPLORATION. Requires at least the mandatory
## structures to be built.
func begin_exploration() -> bool:
	if _current_phase != Phase.SETTLEMENT:
		return false
	if not _mandatory_structures_built():
		return false
	_set_phase(Phase.EXPLORATION)
	_narrate("The camp takes shape. Shelters stand against the wind. Crops push through the soil. It is time to see what this world offers.")
	return true

## Advance from EXPLORATION to SURVIVAL. Requires at least 3 sites explored.
func begin_survival() -> bool:
	if _current_phase != Phase.EXPLORATION:
		return false
	if _explored_sites.size() < 3:
		return false
	_set_phase(Phase.SURVIVAL)
	_day_timer = 0.0
	_event_timer = 0.0
	_narrate("Days stretch into weeks. The settlement faces the challenges of a new world. Storms, illness, scarcity — the planet tests the crew.")
	return true

## Advance from SURVIVAL to MORAL_CHOICE. Requires surviving all configured days.
func begin_moral_choice() -> bool:
	if _current_phase != Phase.SURVIVAL:
		return false
	var days_needed: int = int(_survival_config.get("days_to_survive", 5))
	if _current_day < days_needed:
		return false
	_set_phase(Phase.MORAL_CHOICE)
	_narrate("The crew gathers. The debate returns, sharper now. They have lived on this world. They know what it offers and what it costs. The choice must be made.")
	return true

# ── Camp building ─────────────────────────────────────────────────────────────

## Start building a structure. Returns false if structure is unknown, already
## built, or another build is in progress.
func start_build(structure_id: String) -> bool:
	if not _camp_structures.has(structure_id):
		return false
	if _built_structures.has(structure_id):
		return false
	if _active_build != "":
		return false
	# Check resource costs.
	var s: Dictionary = _camp_structures[structure_id] as Dictionary
	var costs: Dictionary = s.get("resource_cost", {})
	for resource in costs.keys():
		var needed: int = int(costs[resource])
		var have: int = int(_resources.get(resource, 0))
		if have < needed:
			return false
	# Check crew requirement.
	var crew_req: int = int(s.get("crew_required", 1))
	if _crew_count < crew_req:
		return false
	# Deduct resources.
	for resource in costs.keys():
		var needed: int = int(costs[resource])
		_resources[resource] = int(_resources.get(resource, 0)) - needed
	resources_changed.emit(_resources.duplicate())
	_active_build = structure_id
	_build_progress = 0.0
	return true

## Tick the active build. Called by _process or test_advance_build.
func tick_build(delta: float) -> void:
	if _active_build == "":
		return
	if not _camp_structures.has(_active_build):
		_active_build = ""
		return
	var s: Dictionary = _camp_structures[_active_build] as Dictionary
	var build_time: float = float(s.get("build_time", 120.0))
	_build_progress += delta / build_time
	build_progress_updated.emit(_active_build, _build_progress)
	if _build_progress >= 1.0:
		_complete_build(_active_build)

func _complete_build(structure_id: String) -> void:
	_built_structures[structure_id] = true
	_active_build = ""
	_build_progress = 0.0
	structure_built.emit(structure_id)
	# Apply provides effects.
	var s: Dictionary = _camp_structures[structure_id] as Dictionary
	var provides: String = String(s.get("provides", ""))
	var provides_value: int = int(s.get("provides_value", 0))
	if not provides.is_empty() and provides_value != 0:
		_apply_structure_bonus(provides, provides_value)
	# Narrate.
	var label: String = String(s.get("label", structure_id))
	var desc: String = String(s.get("description", ""))
	if not desc.is_empty():
		_narrate(label + ": " + desc)
	# Publish to GameState.
	_publish_to_game_state()

## Force-complete a build instantly (for tests).
func test_complete_build(structure_id: String) -> bool:
	if not _camp_structures.has(structure_id):
		return false
	if _built_structures.has(structure_id):
		return false
	# Deduct resources if not already deducted (start_build path).
	var s: Dictionary = _camp_structures[structure_id] as Dictionary
	var costs: Dictionary = s.get("resource_cost", {})
	for resource in costs.keys():
		var needed: int = int(costs[resource])
		var have: int = int(_resources.get(resource, 0))
		if have < needed:
			# Grant resources for test.
			_resources[resource] = needed
		_resources[resource] = int(_resources.get(resource, 0)) - needed
	resources_changed.emit(_resources.duplicate())
	_complete_build(structure_id)
	return true

## Cancel the active build (for tests or player cancel).
func cancel_build() -> void:
	_active_build = ""
	_build_progress = 0.0

func is_structure_built(structure_id: String) -> bool:
	return _built_structures.has(structure_id)

func get_built_structures() -> Array[String]:
	var out: Array[String] = []
	for sid in _built_structures.keys():
		out.append(String(sid))
	return out

func get_structure(structure_id: String) -> Dictionary:
	return _camp_structures.get(structure_id, {})

func get_all_structure_ids() -> Array[String]:
	var out: Array[String] = []
	for sid in _camp_structures.keys():
		out.append(String(sid))
	return out

func get_active_build() -> String:
	return _active_build

func get_build_progress() -> float:
	return _build_progress

func _mandatory_structures_built() -> bool:
	for sid in _camp_structures.keys():
		var s: Dictionary = _camp_structures[sid] as Dictionary
		if bool(s.get("required_for_next_phase", false)):
			if not _built_structures.has(sid):
				return false
	return true

func _apply_structure_bonus(provides: String, value: int) -> void:
	match provides:
		"shelter_rating":
			# Shelters boost morale.
			_morale = mini(100, _morale + value / 5)
			morale_changed.emit(_morale)
		"water_supply":
			_resources["water"] = int(_resources.get("water", 0)) + value
			resources_changed.emit(_resources.duplicate())
		"food_production":
			_resources["food"] = int(_resources.get("food", 0)) + value
			resources_changed.emit(_resources.duplicate())
		"defense_rating":
			# Defense reduces damage from wildlife attacks.
			pass  # Checked during survival events.
		"medical_rating":
			# Medical station boosts health regen.
			_health = mini(100, _health + value / 5)
			health_changed.emit(_health)
		"power_supply":
			# Power boosts morale.
			_morale = mini(100, _morale + value / 10)
			morale_changed.emit(_morale)
		"comm_link":
			# Comm link provides morale boost.
			_morale = mini(100, _morale + value / 10)
			morale_changed.emit(_morale)


# ── Exploration ───────────────────────────────────────────────────────────────

## Start exploring a site. Returns false if site is unknown, already explored,
## or another explore is in progress.
func start_explore(site_id: String) -> bool:
	if not _exploration_sites.has(site_id):
		return false
	if _explored_sites.has(site_id):
		return false
	if _active_explore != "":
		return false
	_active_explore = site_id
	_explore_progress = 0.0
	return true

## Tick the active exploration. Called by _process or test_advance_explore.
func tick_explore(delta: float) -> void:
	if _active_explore == "":
		return
	if not _exploration_sites.has(_active_explore):
		_active_explore = ""
		return
	var site: Dictionary = _exploration_sites[_active_explore] as Dictionary
	var explore_time: float = float(site.get("explore_time", 60.0))
	_explore_progress += delta / explore_time
	explore_progress_updated.emit(_active_explore, _explore_progress)
	if _explore_progress >= 1.0:
		_complete_explore(_active_explore)

func _complete_explore(site_id: String) -> void:
	_explored_sites[site_id] = true
	_active_explore = ""
	_explore_progress = 0.0
	# Award resources.
	var site: Dictionary = _exploration_sites[site_id] as Dictionary
	var resources: Dictionary = site.get("resources", {})
	for resource in resources.keys():
		var amount: int = int(resources[resource])
		_resources[resource] = int(_resources.get(resource, 0)) + amount
	resources_changed.emit(_resources.duplicate())
	# Narrate.
	var label: String = String(site.get("label", site_id))
	var desc: String = String(site.get("description", ""))
	if not desc.is_empty():
		_narrate(label + ": " + desc)
	site_explored.emit(site_id)

## Force-complete an explore instantly (for tests).
func test_complete_explore(site_id: String) -> bool:
	if not _exploration_sites.has(site_id):
		return false
	if _explored_sites.has(site_id):
		return false
	_complete_explore(site_id)
	return true

func cancel_explore() -> void:
	_active_explore = ""
	_explore_progress = 0.0

func is_site_explored(site_id: String) -> bool:
	return _explored_sites.has(site_id)

func get_explored_sites() -> Array[String]:
	var out: Array[String] = []
	for sid in _explored_sites.keys():
		out.append(String(sid))
	return out

func get_site(site_id: String) -> Dictionary:
	return _exploration_sites.get(site_id, {})

func get_all_site_ids() -> Array[String]:
	var out: Array[String] = []
	for sid in _exploration_sites.keys():
		out.append(String(sid))
	return out

func get_active_explore() -> String:
	return _active_explore

func get_explore_progress() -> float:
	return _explore_progress

func get_explored_site_count() -> int:
	return _explored_sites.size()

func get_total_sites() -> int:
	return _exploration_sites.size()


# ── Survival ──────────────────────────────────────────────────────────────────

## Tick survival: advance day timer and event timer.
func tick_survival(delta: float) -> void:
	if _current_phase != Phase.SURVIVAL:
		return
	if _current_phase == Phase.MORAL_CHOICE or _current_phase == Phase.RESOLVED:
		return
	var day_duration: float = float(_survival_config.get("day_duration", 300.0))
	var event_interval: float = float(_survival_config.get("event_interval", 60.0))
	_day_timer += delta
	_event_timer += delta
	if _day_timer >= day_duration:
		_day_timer = 0.0
		_advance_day()
	if _event_timer >= event_interval:
		_event_timer = 0.0
		_trigger_next_survival_event()

func _advance_day() -> void:
	_current_day += 1
	# Apply morale decay.
	var morale_decay: int = int(_survival_config.get("morale_decay_per_day", 5))
	_morale = maxi(0, _morale - morale_decay)
	# Apply health regen if medical station built.
	var health_regen: int = int(_survival_config.get("health_regen_per_day", 10))
	if _built_structures.has("med_station"):
		_health = mini(100, _health + health_regen)
	# Consume food and water.
	var food_consume: int = int(_survival_config.get("food_consumption_per_day", 3))
	var water_consume: int = int(_survival_config.get("water_consumption_per_day", 2))
	_resources["food"] = maxi(0, int(_resources.get("food", 0)) - food_consume)
	_resources["water"] = maxi(0, int(_resources.get("water", 0)) - water_consume)
	# If food or water is zero, apply penalties.
	if int(_resources.get("food", 0)) <= 0:
		_morale = maxi(0, _morale - 10)
		_health = maxi(0, _health - 10)
	if int(_resources.get("water", 0)) <= 0:
		_morale = maxi(0, _morale - 15)
		_health = maxi(0, _health - 15)
	crew_count_changed.emit(_crew_count)
	morale_changed.emit(_morale)
	health_changed.emit(_health)
	resources_changed.emit(_resources.duplicate())
	day_passed.emit(_current_day)
	# Check if we've survived long enough.
	var days_needed: int = int(_survival_config.get("days_to_survive", 5))
	if _current_day >= days_needed:
		# Auto-advance to moral choice.
		begin_moral_choice()

func _trigger_next_survival_event() -> void:
	if _next_event_order > _ordered_survival_events.size():
		return
	var event_id: String = _ordered_survival_events[_next_event_order - 1]
	var evt: Dictionary = _survival_events.get(event_id, {})
	if evt.is_empty():
		return
	_next_event_order += 1
	_triggered_events[event_id] = true
	# Check mitigation.
	var mitigated_by: String = String(evt.get("mitigated_by", ""))
	var mitigation_value: int = int(evt.get("mitigation_value", 0))
	var is_mitigated: bool = false
	if not mitigated_by.is_empty() and _built_structures.has(mitigated_by):
		is_mitigated = true
		_mitigated_events[event_id] = mitigated_by
		survival_event_mitigated.emit(event_id, mitigated_by)
	# Apply damage if not fully mitigated.
	if not is_mitigated:
		_apply_event_damage(evt, 1.0)
	elif mitigation_value < 100:
		_apply_event_damage(evt, float(100 - mitigation_value) / 100.0)
	survival_event_triggered.emit(event_id)
	# Narrate.
	var label: String = String(evt.get("label", event_id))
	var desc: String = String(evt.get("description", ""))
	if not desc.is_empty():
		_narrate(label + ": " + desc)
	# Check for crew death.
	var crew_min: int = int(_survival_config.get("crew_count_min", 8))
	if _crew_count < crew_min:
		# Crew too low — force moral choice early.
		begin_moral_choice()

func _apply_event_damage(evt: Dictionary, multiplier: float) -> void:
	var damage: Dictionary = evt.get("damage", {})
	for key in damage.keys():
		var raw_dmg: int = absi(int(damage[key]))
		var actual_dmg: int = int(float(raw_dmg) * multiplier)
		match key:
			"crew_health":
				_health = maxi(0, _health - actual_dmg)
				health_changed.emit(_health)
				# Health below 30 risks crew death.
				if _health < 30:
					_crew_count = maxi(0, _crew_count - 1)
					crew_count_changed.emit(_crew_count)
			"crew_morale":
				_morale = maxi(0, _morale - actual_dmg)
				morale_changed.emit(_morale)
			"shelter_rating":
				# Damage shelters — reduce morale.
				_morale = maxi(0, _morale - actual_dmg / 2)
				morale_changed.emit(_morale)
			"food_production":
				_resources["food"] = maxi(0, int(_resources.get("food", 0)) - actual_dmg)
				resources_changed.emit(_resources.duplicate())
			"water_supply":
				_resources["water"] = maxi(0, int(_resources.get("water", 0)) - actual_dmg)
				resources_changed.emit(_resources.duplicate())
			"defense_rating":
				# Defense damage risks crew.
				if actual_dmg > 10:
					_crew_count = maxi(0, _crew_count - 1)
					crew_count_changed.emit(_crew_count)

func is_event_triggered(event_id: String) -> bool:
	return _triggered_events.has(event_id)

func is_event_mitigated(event_id: String) -> bool:
	return _mitigated_events.has(event_id)

func get_triggered_events() -> Array[String]:
	var out: Array[String] = []
	for eid in _triggered_events.keys():
		out.append(String(eid))
	return out

func get_total_survival_events() -> int:
	return _ordered_survival_events.size()

func get_current_day() -> int:
	return _current_day

func get_crew_count() -> int:
	return _crew_count

func get_morale() -> int:
	return _morale

func get_health() -> int:
	return _health

func get_resources() -> Dictionary:
	return _resources.duplicate()

func set_resources(resource: String, amount: int) -> void:
	_resources[resource] = amount
	resources_changed.emit(_resources.duplicate())


# ── Philosophical dialogue ────────────────────────────────────────────────────

## Trigger a philosophical dialogue. Returns true if newly triggered.
func trigger_dialogue(dialogue_id: String) -> bool:
	if not _philosophical_dialogues.has(dialogue_id):
		return false
	if _triggered_dialogues.has(dialogue_id):
		return false
	_triggered_dialogues[dialogue_id] = true
	dialogue_triggered.emit(dialogue_id)
	# Apply small morale effect based on stance.
	var dialogue: Dictionary = _philosophical_dialogues[dialogue_id] as Dictionary
	var stance: String = String(dialogue.get("stance", ""))
	match stance:
		"stay":
			_morale = mini(100, _morale + 2)
		"continue":
			_morale = maxi(0, _morale - 1)
		"ambiguous":
			pass
	morale_changed.emit(_morale)
	# Narrate the dialogue line.
	var speaker: String = String(dialogue.get("speaker", ""))
	var text: String = String(dialogue.get("text", ""))
	if not text.is_empty():
		_narrate(speaker + ": " + text)
	return true

func is_dialogue_triggered(dialogue_id: String) -> bool:
	return _triggered_dialogues.has(dialogue_id)

func get_dialogue(dialogue_id: String) -> Dictionary:
	return _philosophical_dialogues.get(dialogue_id, {})

func get_all_dialogue_ids() -> Array[String]:
	var out: Array[String] = []
	for did in _philosophical_dialogues.keys():
		out.append(String(did))
	return out

func get_triggered_dialogues() -> Array[String]:
	var out: Array[String] = []
	for did in _triggered_dialogues.keys():
		out.append(String(did))
	return out

## Get the dominant stance from triggered dialogues. Returns "stay", "continue",
## or "ambiguous".
func get_dominant_stance() -> String:
	var stay_weight: int = 0
	var continue_weight: int = 0
	for did in _triggered_dialogues.keys():
		var dialogue: Dictionary = _philosophical_dialogues.get(String(did), {})
		var stance: String = String(dialogue.get("stance", ""))
		var weight: int = int(dialogue.get("weight", 1))
		match stance:
			"stay":
				stay_weight += weight
			"continue":
				continue_weight += weight
	if stay_weight > continue_weight:
		return "stay"
	elif continue_weight > stay_weight:
		return "continue"
	return "ambiguous"


# ── Moral choice ──────────────────────────────────────────────────────────────

## Check if the player can make the moral choice (must be in MORAL_CHOICE phase).
func can_make_moral_choice() -> bool:
	return _current_phase == Phase.MORAL_CHOICE

## Make the moral choice. Returns true if the choice was valid.
func make_moral_choice(choice_id: String) -> bool:
	if not _moral_choices.has(choice_id):
		return false
	if _current_phase != Phase.MORAL_CHOICE:
		return false
	_moral_choice_id = choice_id
	var choice: Dictionary = _moral_choices[choice_id] as Dictionary
	var outcome: String = String(choice.get("outcome", ""))
	_resolution_outcome = outcome
	# Apply relationship effects.
	_apply_relationship_effects(choice)
	# Apply faction tension.
	var tension_delta: int = int(choice.get("faction_tension_delta", 0))
	_apply_faction_tension(tension_delta)
	# Narrate the outcome.
	var narrative: String = String(choice.get("narrative", ""))
	if not narrative.is_empty():
		_narrate(narrative)
	moral_choice_made.emit(choice_id)
	faith_resolved.emit(outcome)
	_set_phase(Phase.RESOLVED)
	_publish_to_game_state()
	return true

func get_moral_choice() -> String:
	return _moral_choice_id

func get_resolution_outcome() -> String:
	return _resolution_outcome

func get_all_moral_choices() -> Array[String]:
	var out: Array[String] = []
	for cid in _moral_choices.keys():
		out.append(String(cid))
	return out

func get_moral_choice_data(choice_id: String) -> Dictionary:
	return _moral_choices.get(choice_id, {})

func is_complete() -> bool:
	return _current_phase == Phase.RESOLVED


# ── Scenario info ─────────────────────────────────────────────────────────────

func get_scenario() -> Dictionary:
	return _scenario

func get_scenario_id() -> String:
	return String(_scenario.get("id", ""))

func get_scenario_title() -> String:
	return String(_scenario.get("title", ""))

func get_scenario_description() -> String:
	return String(_scenario.get("description", ""))

func get_planet_name() -> String:
	return String(_scenario.get("planet_name", ""))

func get_planet_biome() -> String:
	return String(_scenario.get("planet_biome", ""))

func get_landing_zone() -> String:
	return _landing_zone

func is_landing_success() -> bool:
	return _landing_success


# ── Relationship / faction effects ────────────────────────────────────────────

func _apply_relationship_effects(choice: Dictionary) -> void:
	var effects: Dictionary = choice.get("relationship_effects", {})
	var rs: Node = _autoload("RelationshipSystem")
	if rs == null or not rs.has_method("adjust_trust"):
		return
	for crew_name in effects.keys():
		var cn: String = String(crew_name)
		var vals: Dictionary = effects[cn] as Dictionary
		var trust_delta: int = int(vals.get("trust", 0))
		var respect_delta: int = int(vals.get("respect", 0))
		if trust_delta != 0 and rs.has_method("adjust_trust"):
			rs.call("adjust_trust", cn, trust_delta)
		if respect_delta != 0 and rs.has_method("adjust_respect"):
			rs.call("adjust_respect", cn, respect_delta)

func _apply_faction_tension(delta: int) -> void:
	if delta == 0:
		return
	var fs: Node = _autoload("FactionSystem")
	if fs != null and fs.has_method("adjust_tension"):
		fs.call("adjust_tension", delta)


# ── GameState publishing ──────────────────────────────────────────────────────

func _publish_to_game_state() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	if gs.has_method("set_flag"):
		gs.call("set_flag", "faith_started", _current_phase != Phase.INACTIVE)
		gs.call("set_flag", "faith_resolved", _current_phase == Phase.RESOLVED)
		gs.call("set_flag", "faith_landing_success", _landing_success)
		gs.call("set_flag", "faith_choice_made", not _moral_choice_id.is_empty())

func _narrate(text: String) -> void:
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("narrate"):
		gs.call("narrate", text)


# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	var built_arr: Array[String] = []
	for sid in _built_structures.keys():
		built_arr.append(String(sid))
	var explored_arr: Array[String] = []
	for sid in _explored_sites.keys():
		explored_arr.append(String(sid))
	var events_arr: Array[String] = []
	for eid in _triggered_events.keys():
		events_arr.append(String(eid))
	var mitigated_arr: Array[String] = []
	for eid in _mitigated_events.keys():
		mitigated_arr.append(String(eid))
	var dialogues_arr: Array[String] = []
	for did in _triggered_dialogues.keys():
		dialogues_arr.append(String(did))
	return {
		"current_phase": _current_phase,
		"built_structures": built_arr,
		"explored_sites": explored_arr,
		"triggered_events": events_arr,
		"mitigated_events": mitigated_arr,
		"triggered_dialogues": dialogues_arr,
		"crew_count": _crew_count,
		"morale": _morale,
		"health": _health,
		"current_day": _current_day,
		"day_timer": _day_timer,
		"event_timer": _event_timer,
		"next_event_order": _next_event_order,
		"resources": _resources.duplicate(),
		"landing_zone": _landing_zone,
		"landing_success": _landing_success,
		"moral_choice_id": _moral_choice_id,
		"resolution_outcome": _resolution_outcome,
		"active_build": _active_build,
		"build_progress": _build_progress,
		"active_explore": _active_explore,
		"explore_progress": _explore_progress,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_initialized()
	_current_phase = int(data.get("current_phase", Phase.INACTIVE))
	_built_structures.clear()
	var built_arr: Variant = data.get("built_structures", [])
	if built_arr is Array:
		for sid in built_arr:
			_built_structures[String(sid)] = true
	_explored_sites.clear()
	var explored_arr: Variant = data.get("explored_sites", [])
	if explored_arr is Array:
		for sid in explored_arr:
			_explored_sites[String(sid)] = true
	_triggered_events.clear()
	var events_arr: Variant = data.get("triggered_events", [])
	if events_arr is Array:
		for eid in events_arr:
			_triggered_events[String(eid)] = true
	_mitigated_events.clear()
	var mitigated_arr: Variant = data.get("mitigated_events", [])
	if mitigated_arr is Array:
		for eid in mitigated_arr:
			_mitigated_events[String(eid)] = String(eid)
	_triggered_dialogues.clear()
	var dialogues_arr: Variant = data.get("triggered_dialogues", [])
	if dialogues_arr is Array:
		for did in dialogues_arr:
			_triggered_dialogues[String(did)] = true
	_crew_count = int(data.get("crew_count", 15))
	_morale = int(data.get("morale", 70))
	_health = int(data.get("health", 100))
	_current_day = int(data.get("current_day", 1))
	_day_timer = float(data.get("day_timer", 0.0))
	_event_timer = float(data.get("event_timer", 0.0))
	_next_event_order = int(data.get("next_event_order", 1))
	_resources.clear()
	var saved_resources: Variant = data.get("resources", {})
	if saved_resources is Dictionary:
		_resources = (saved_resources as Dictionary).duplicate()
	_landing_zone = String(data.get("landing_zone", ""))
	_landing_success = bool(data.get("landing_success", false))
	_moral_choice_id = String(data.get("moral_choice_id", ""))
	_resolution_outcome = String(data.get("resolution_outcome", ""))
	_active_build = String(data.get("active_build", ""))
	_build_progress = float(data.get("build_progress", 0.0))
	_active_explore = String(data.get("active_explore", ""))
	_explore_progress = float(data.get("explore_progress", 0.0))

func reset() -> void:
	_current_phase = Phase.INACTIVE
	_built_structures.clear()
	_explored_sites.clear()
	_triggered_events.clear()
	_mitigated_events.clear()
	_triggered_dialogues.clear()
	_crew_count = int(_survival_config.get("crew_count_start", 15))
	_morale = int(_survival_config.get("morale_start", 70))
	_health = int(_survival_config.get("health_start", 100))
	_current_day = 1
	_day_timer = 0.0
	_event_timer = 0.0
	_next_event_order = 1
	_resources.clear()
	_landing_zone = ""
	_landing_success = false
	_moral_choice_id = ""
	_resolution_outcome = ""
	_active_build = ""
	_build_progress = 0.0
	_active_explore = ""
	_explore_progress = 0.0


# ── Test hooks ────────────────────────────────────────────────────────────────

## Advance the survival timer by a fixed delta (bypasses _process, for tests).
func test_advance_survival(delta: float) -> void:
	tick_survival(delta)

## Advance the build timer by a fixed delta (bypasses _process, for tests).
func test_advance_build(delta: float) -> void:
	tick_build(delta)

## Advance the explore timer by a fixed delta (bypasses _process, for tests).
func test_advance_explore(delta: float) -> void:
	tick_explore(delta)

## Force-set the phase (for tests).
func test_set_phase(p: int) -> void:
	_set_phase(p)

## Force-trigger the next survival event (for tests, bypasses timer).
func test_trigger_survival_event() -> void:
	_trigger_next_survival_event()

## Force-advance to the next day (for tests).
func test_advance_day() -> void:
	_advance_day()

## Force-set crew count (for tests).
func test_set_crew_count(count: int) -> void:
	_crew_count = count
	crew_count_changed.emit(_crew_count)

## Force-set morale (for tests).
func test_set_morale(value: int) -> void:
	_morale = value
	morale_changed.emit(_morale)

## Force-set health (for tests).
func test_set_health(value: int) -> void:
	_health = value
	health_changed.emit(_health)

## Force-set current day (for tests).
func test_set_current_day(day: int) -> void:
	_current_day = day

## Set day timer override for fast testing.
func test_set_day_duration(duration: float) -> void:
	_survival_config["day_duration"] = duration

## Set event interval override for fast testing.
func test_set_event_interval(interval: float) -> void:
	_survival_config["event_interval"] = interval

## Force set days to survive (for tests).
func test_set_days_to_survive(days: int) -> void:
	_survival_config["days_to_survive"] = days

## Directly trigger a survival event by id (for tests).
func test_trigger_event(event_id: String) -> void:
	if not _survival_events.has(event_id):
		return
	_triggered_events[event_id] = true
	var evt: Dictionary = _survival_events[event_id] as Dictionary
	var mitigated_by: String = String(evt.get("mitigated_by", ""))
	if not mitigated_by.is_empty() and _built_structures.has(mitigated_by):
		_mitigated_events[event_id] = mitigated_by
		survival_event_mitigated.emit(event_id, mitigated_by)
		_apply_event_damage(evt, 0.25)
	else:
		_apply_event_damage(evt, 1.0)
	survival_event_triggered.emit(event_id)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "faith_system", self)

func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)