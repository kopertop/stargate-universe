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
	_load_rates()
	# Register with SaveManager so accumulators survive save/load.
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "consumption", self)


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
	for id in _accum.keys():
		var amount: float = per_cycle_amount(id)
		if amount <= 0.0:
			continue
		var rate_per_sec: float = amount / _cycle_seconds
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


# --- _process -----------------------------------------------------------------

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	if not _phase_active():
		return
	tick(delta)


# --- save / load --------------------------------------------------------------

func reset() -> void:
	_accum.clear()
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


# --- helpers ------------------------------------------------------------------

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)
