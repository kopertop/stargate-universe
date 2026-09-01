extends Node

# CO2 scrubber system manager. Owns the main scrubber's charge level, the
# optional maintenance scrubber registry, and the repair/top-up/decay logic.
# Extracted from GameState (the god object) as part of the P0 refactor —
# GameState keeps thin back-compat facades that proxy here.
#
# Save contract: registers as "scrubber_system" via SaveManager.register_system.
# Serialize/deserialize own the scrubber-specific fields only.

signal scrubber_level_changed(level: float)
signal scrubber_unit_changed(id: String)

# One lime fully refills the main scrubber.
const SCRUBBER_REPAIR_LIME_COST: int = 1
const AIR_LIME_REQUIRED: int = 3
const SCRUBBER_LIME_RECHARGE: float = 100.0 / float(AIR_LIME_REQUIRED)
const SCRUBBER_DECAY_PER_SEC: float = SCRUBBER_LIME_RECHARGE / 3600.0
const SCRUBBER_WARN_PERCENT: float = 33.0
const SCRUBBER_O2_BLEED_PER_SEC: float = 1.0 / 60.0
const AIR_LIME_RESOURCE: String = "lime"

const AUX_SCRUBBERS: Array = [
	{"id": "north_corridor", "room": "north_corridor", "name": "North Section Scrubber"},
	{"id": "east_far", "room": "east_corridor_far", "name": "East Maintenance Scrubber"},
	{"id": "hydroponics", "room": "hydroponics", "name": "Hydroponics Scrubber"},
]

# Main story scrubber state (the E1 south unit has a unique diagnosis/Rush lifecycle).
var scrubber_diagnosed: bool = false
var scrubber_repaired: bool = false
var scrubber_level: float = 0.0
var _scrubber_warned: bool = false
var _scrubber_critical: bool = false

# Optional maintenance scrubbers (beyond the E1 south unit). Keyed by id →
# { "discovered": bool, "open": bool, "repaired": bool }.
var scrubber_units: Dictionary = {}


func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "scrubber_system", self)


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _inv() -> Node:
	return _autoload_node("Inventory")


func _gs() -> Node:
	return _autoload_node("GameState")


# --- Tick (called by GameState._process so the decay stays centralized) ------

func tick_scrubber(delta: float) -> void:
	var prev: float = scrubber_level
	if scrubber_level > 0.0:
		scrubber_level = maxf(0.0, scrubber_level - SCRUBBER_DECAY_PER_SEC * delta)
		scrubber_level_changed.emit(scrubber_level)
	else:
		var gs: Node = _gs()
		if gs != null and gs.has_method("consume_oxygen"):
			gs.call("consume_oxygen", SCRUBBER_O2_BLEED_PER_SEC * delta)
	# Threshold latches.
	var gs: Node = _gs()
	if not _scrubber_warned and prev > SCRUBBER_WARN_PERCENT and scrubber_level <= SCRUBBER_WARN_PERCENT:
		_scrubber_warned = true
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "CO2 scrubber charge below %d%% — lime needed soon." % int(SCRUBBER_WARN_PERCENT))
	if not _scrubber_critical and scrubber_level <= 0.0:
		_scrubber_critical = true
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "CO2 scrubber EMPTY — oxygen bleeding off, top up with lime immediately.")


# --- Main scrubber repair / top-up --------------------------------------------

func repair_scrubber_with_lime() -> bool:
	if scrubber_repaired:
		var gs: Node = _gs()
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "CO2 scrubber is already repaired.")
		return true
	if not scrubber_diagnosed:
		var gs2: Node = _gs()
		if gs2 != null and gs2.has_method("diagnose_scrubber"):
			gs2.call("diagnose_scrubber")
		return false
	var gs: Node = _gs()
	if gs == null or not gs.has_method("spend_resource"):
		return false
	if not gs.call("spend_resource", AIR_LIME_RESOURCE, SCRUBBER_REPAIR_LIME_COST, "CO2 scrubber repair"):
		return false
	scrubber_repaired = true
	scrubber_level = 100.0
	_scrubber_warned = false
	_scrubber_critical = false
	scrubber_level_changed.emit(scrubber_level)
	if gs.has_method("restore_oxygen"):
		gs.call("restore_oxygen", 100.0)  # MAX_OXYGEN
	if gs.has_method("add_log"):
		gs.call("add_log", "CO2 scrubber repaired. Life support is stabilising across this section.")
	if gs.has_method("complete_episode_air"):
		gs.call("complete_episode_air")
	return true


func top_up_scrubber() -> bool:
	if not scrubber_repaired or scrubber_level >= 100.0:
		return false
	var gs: Node = _gs()
	if gs == null or not gs.has_method("spend_resource"):
		return false
	if not gs.call("spend_resource", AIR_LIME_RESOURCE, 1, "CO2 scrubber top-up"):
		return false
	scrubber_level = minf(100.0, scrubber_level + SCRUBBER_LIME_RECHARGE)
	if scrubber_level > SCRUBBER_WARN_PERCENT:
		_scrubber_warned = false
	if scrubber_level > 0.0:
		_scrubber_critical = false
	if gs.has_method("add_log"):
		gs.call("add_log", "Topped up the CO2 scrubber. Charge at %d%%." % int(round(scrubber_level)))
	scrubber_level_changed.emit(scrubber_level)
	return true


# --- Optional maintenance scrubber registry -----------------------------------

func scrubber_unit_state(id: String) -> Dictionary:
	if not scrubber_units.has(id):
		scrubber_units[id] = {"discovered": false, "open": false, "repaired": false}
	return scrubber_units[id]


func is_scrubber_unit_discovered(id: String) -> bool:
	return scrubber_unit_state(id).get("discovered", false) == true


func is_scrubber_unit_open(id: String) -> bool:
	return scrubber_unit_state(id).get("open", false) == true


func is_scrubber_unit_repaired(id: String) -> bool:
	return scrubber_unit_state(id).get("repaired", false) == true


func discover_scrubber_unit(id: String, label: String = "CO2 Scrubber") -> bool:
	var st: Dictionary = scrubber_unit_state(id)
	if st.get("discovered", false) == true:
		return false
	st["discovered"] = true
	st["open"] = true
	var gs: Node = _gs()
	if gs != null and gs.has_method("discover_poi"):
		gs.call("discover_poi", "scrubber_" + id, "life_support", label, true)
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Found a CO2 scrubber access panel — it needs lime to recharge.")
	scrubber_unit_changed.emit(id)
	return true


func set_scrubber_unit_open(id: String, want_open: bool) -> void:
	var st: Dictionary = scrubber_unit_state(id)
	if (st.get("open", false) == true) == want_open:
		return
	st["open"] = want_open
	scrubber_unit_changed.emit(id)


func repair_scrubber_unit(id: String) -> bool:
	var st: Dictionary = scrubber_unit_state(id)
	if st.get("repaired", false) == true:
		return false
	var gs: Node = _gs()
	if gs == null or not gs.has_method("spend_resource"):
		return false
	if not gs.call("spend_resource", AIR_LIME_RESOURCE, SCRUBBER_REPAIR_LIME_COST, "scrubber recharge"):
		return false
	st["repaired"] = true
	st["open"] = false
	st["discovered"] = true
	if gs.has_method("add_log"):
		gs.call("add_log", "Recharged a CO2 scrubber. The access panel slides shut.")
	scrubber_unit_changed.emit(id)
	return true


func aux_scrubbers_repaired_count() -> int:
	var n: int = 0
	for row in AUX_SCRUBBERS:
		if is_scrubber_unit_repaired(String((row as Dictionary).get("id", ""))):
			n += 1
	return n


func scrubber_green_bars() -> int:
	return clampi(roundi(scrubber_level / (100.0 / 3.0)), 0, 3)


func reset() -> void:
	scrubber_diagnosed = false
	scrubber_repaired = false
	scrubber_level = 0.0
	_scrubber_warned = false
	_scrubber_critical = false
	scrubber_units.clear()


# --- Save / Load --------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"scrubber_diagnosed": scrubber_diagnosed,
		"scrubber_repaired": scrubber_repaired,
		"scrubber_level": scrubber_level,
		"scrubber_units": scrubber_units.duplicate(true),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	scrubber_diagnosed = data.get("scrubber_diagnosed", false) == true
	scrubber_repaired = data.get("scrubber_repaired", false) == true
	scrubber_level = float(data.get("scrubber_level", 0.0))
	var su: Variant = data.get("scrubber_units", {})
	scrubber_units = (su as Dictionary).duplicate(true) if su is Dictionary else {}