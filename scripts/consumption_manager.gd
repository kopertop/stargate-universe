extends Node

# Crew/ship resource consumption over the ship phase (issue #134).
#
# Implements GDD: Resource-pressure economy — crew consume water/food and the
# ship consumes parts each ~30-min ship cycle, so scarcity pushes the player to
# gate to planets. Lime is NOT consumed here; its pressure comes entirely from
# the existing _tick_scrubber() loop in game_state.gd (rate = 0 in json).
#
# Data-driven: all rates live in data/consumption.json so designers can tune
# without touching code.  Per-resource fractional accumulators (same pattern as
# _tick_heat_water_drain) spend whole units via GameState.spend_resource().
#
# _process is gated on _phase_active() AND NOT SceneRouter.instant_mode so
# headless smoke tests never tick the 30-min clock. Tests drive via
# simulate_seconds(s) / tick(delta) directly.
#
# Save registration: register_system("consumption", self) — accumulators are
# the only state that must survive a save (resource counts persist in Inventory,
# cycle_seconds / rates reload from JSON each _ready).

const CONSUMPTION_PATH: String = "res://data/consumption.json"

# Loaded from JSON; ONE table, never named in code (collection-fork safe).
var _rates: Dictionary = {}       # id → {base, per_crew, per_section}
var _cycle_seconds: float = 1800.0

# Fractional accumulators: keyed by resource id, value is the sub-unit
# carry from the last tick. Persisted so a reload doesn't lose the partial
# drain accumulated since the last whole-unit spend.
var _accum: Dictionary = {}       # id → float


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)  # Only tick during SHIP phase — see _reevaluate_process.
	_load_rates()
	# Register with SaveManager so accumulators survive save/load.
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "consumption", self)
	call_deferred("_install_phase_hooks")


# --- rate loading -------------------------------------------------------------

func _load_rates() -> void:
	var f: FileAccess = FileAccess.open(CONSUMPTION_PATH, FileAccess.READ)
	if f == null:
		push_error("ConsumptionManager: cannot open %s" % CONSUMPTION_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ConsumptionManager: %s did not parse to a Dictionary" % CONSUMPTION_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_cycle_seconds = float(d.get("cycle_seconds", 1800.0))
	var raw_rates: Variant = d.get("rates", {})
	if raw_rates is Dictionary:
		_rates = raw_rates as Dictionary
	# Seed accumulators for every tracked id (zero-init, won't overwrite a
	# prior deserialize that already populated them).
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("tracked_resource_ids"):
		for id in gs.call("tracked_resource_ids"):
			if not _accum.has(id):
				_accum[id] = 0.0


# --- per-cycle amount ---------------------------------------------------------

# Whole-cycle amount for a given resource id, scaled by crew + sections.
# Returns 0.0 when the id has no entry in _rates (lime, unlisted).
func per_cycle_amount(id: String) -> float:
	if not _rates.has(id):
		return 0.0
	var row: Variant = _rates[id]
	if not (row is Dictionary):
		return 0.0
	var r: Dictionary = row as Dictionary
	var base: float = float(r.get("base", 0.0))
	var per_crew: float = float(r.get("per_crew", 0.0))
	var per_section: float = float(r.get("per_section", 0.0))
	var gs: Node = _autoload("GameState")
	var crew: int = 6
	var sections: int = 3
	if gs != null:
		if gs.has_method("crew_size"):
			crew = int(gs.call("crew_size"))
		if gs.has_method("active_section_count"):
			sections = int(gs.call("active_section_count"))
	return base + per_crew * float(crew) + per_section * float(sections)


# --- tick API (also used by tests) --------------------------------------------

# Advance consumption by `delta` seconds. Spends whole units when the
# fractional accumulator crosses 1.0. Does NOT check instant_mode / phase
# (callers are responsible — _process checks both; tests call directly).
func tick(delta: float) -> void:
	if _rates.is_empty():
		return
	var gs: Node = _autoload("GameState")
	if gs == null:
		return
	# Combined multiplier: power-grid penalty (>1.0) * emergency-rationing
	# reduction (<1.0 when ConsequencesSystem says both food+water are
	# critically low). Emergency rationing lets the ship limp longer.
	var power_mult: float = _power_efficiency_multiplier()
	var ration_mult: float = _emergency_rationing_multiplier()
	var combined_mult: float = power_mult * ration_mult
	for id in _accum.keys():
		var amount: float = per_cycle_amount(id)
		if amount <= 0.0:
			continue
		var rate_per_sec: float = (amount / _cycle_seconds) * combined_mult
		_accum[id] = float(_accum[id]) + rate_per_sec * delta
		while float(_accum[id]) >= 1.0:
			_accum[id] = float(_accum[id]) - 1.0
			if int(gs.call("resource_count", id)) <= 0:
				_accum[id] = 0.0
				break
			gs.call("spend_resource", id, 1, "crew consumption")


# Deterministic helper for tests: advance by an arbitrary number of seconds
# without _process needing to tick (instant_mode / phase don't apply here).
func simulate_seconds(seconds: float) -> void:
	tick(seconds)


# --- phase gate ---------------------------------------------------------------

# True while consumption should actively tick. Checks the #130 FtlLoop phase
# first (SHIP = 1); if FtlLoop is absent or IDLE, falls back to: aboard ship
# (episode_complete true). One-line rebind when a future system replaces the
# fallback.
func _phase_active() -> bool:
	var loop: Node = _autoload("FtlLoop")
	if loop != null:
		# FtlLoop.Phase.SHIP == 1
		if int(loop.get("phase")) == 1:
			return true
		# Non-IDLE non-SHIP phase means we're in JUMPING or PLANET — not ship phase.
		if int(loop.get("phase")) != 0:
			return false
	# Fallback: FtlLoop absent or IDLE (pre-E1 / test) — consume only when aboard
	# ship after episode completion.
	var gs: Node = _autoload("GameState")
	if gs == null:
		return false
	return gs.get("episode_complete") == true


# --- phase-gate hooks ----------------------------------------------------------

# Wire to FtlLoop.phase_changed and GameState.episode_completed so
# _reevaluate_process() fires on every relevant state transition.
func _install_phase_hooks() -> void:
	var loop: Node = _autoload("FtlLoop")
	if loop != null and loop.has_signal("phase_changed"):
		if not loop.is_connected("phase_changed", _reevaluate_process):
			loop.connect("phase_changed", _reevaluate_process)
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_signal("episode_completed"):
		if not gs.is_connected("episode_completed", _reevaluate_process):
			gs.connect("episode_completed", _reevaluate_process)
	# Evaluate once on init in case we're resuming mid-SHIP.
	_reevaluate_process()


# Toggle _process based on phase activity and instant_mode guard.
func _reevaluate_process(_arg: Variant = null) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		set_process(false)
		return
	set_process(_phase_active())


# --- _process -----------------------------------------------------------------

func _process(delta: float) -> void:
	# set_process(false) gates this when inactive — the checks below are safety nets.
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	if not _phase_active():
		return
	tick(delta)


# --- save / load --------------------------------------------------------------

func reset() -> void:
	_accum.clear()
	set_process(false)
	# Re-seed zero accumulators for all tracked ids after a reset.
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("tracked_resource_ids"):
		for id in gs.call("tracked_resource_ids"):
			_accum[id] = 0.0


func serialize() -> Dictionary:
	return {"accum": _accum.duplicate()}


func deserialize(data: Dictionary, _version: int) -> void:
	_accum.clear()
	var saved: Variant = data.get("accum", {})
	if saved is Dictionary:
		for k in (saved as Dictionary).keys():
			_accum[String(k)] = float((saved as Dictionary)[k])
	# Ensure every tracked id has an entry even if the save pre-dates a new resource.
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("tracked_resource_ids"):
		for id in gs.call("tracked_resource_ids"):
			if not _accum.has(id):
				_accum[id] = 0.0


# --- power-grid integration ---------------------------------------------------

# Returns a multiplier >= 1.0 representing how much harder consumption works
# when ship power is degraded. 1.0 = all rooms POWERED (no penalty). Each
# DEGRADED room adds POWER_DEGRADED_PENALTY; each OFFLINE room adds
# POWER_OFFLINE_PENALTY. The multiplier scales per-cycle consumption so that
# life support in a dark ship burns resources faster (pumps labour harder,
# backup systems waste more).
#
# Ties to PowerGrid per the power-grid task contract: degraded rooms reduce
# life-support efficiency, offline rooms force emergency rationing.
const POWER_DEGRADED_PENALTY: float = 0.05   # +5% per degraded room
const POWER_OFFLINE_PENALTY: float = 0.15   # +15% per offline room

func _power_efficiency_multiplier() -> float:
	var pg: Node = _autoload("PowerGrid")
	if pg == null or not pg.has_method("get_all_room_states"):
		return 1.0
	var states: Dictionary = pg.call("get_all_room_states")
	if states.is_empty():
		return 1.0
	# PowerState enum: POWERED=0, DEGRADED=1, OFFLINE=2
	var degraded: int = 0
	var offline: int = 0
	for room_id in states.keys():
		var s: int = int(states[room_id])
		if s == 1:
			degraded += 1
		elif s == 2:
			offline += 1
	return 1.0 + (float(degraded) * POWER_DEGRADED_PENALTY) + (float(offline) * POWER_OFFLINE_PENALTY)


# --- emergency-rationing integration -----------------------------------------

# Returns a multiplier <= 1.0 representing how much consumption is reduced
# when ConsequencesSystem declares emergency rationing (both food AND water
# critically low). 1.0 = no rationing (normal consumption). When rationing is
# active, returns ConsequencesSystem.consumption_multiplier() (< 1.0) so the
# crew ekes out the remaining stores longer.
func _emergency_rationing_multiplier() -> float:
	var cs: Node = _autoload("ConsequencesSystem")
	if cs == null or not cs.has_method("consumption_multiplier"):
		return 1.0
	return float(cs.call("consumption_multiplier"))


# --- helpers ------------------------------------------------------------------

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)
