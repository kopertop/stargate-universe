extends Node

# PowerGrid — per-room power routing for the Destiny.
#
# Manages a single reactor → per-room power allocation. Each room has a demand
# and priority (data/power_grid.json). When total demand exceeds supply, the
# grid sheds load by deprioritizing non-critical rooms before critical ones.
# Each room ends up in one of three states: POWERED, DEGRADED, OFFLINE.
#
# Integration:
#   - GameState.set_power_percent(value) + power_changed signal (HUD/Kino map)
#   - door.gd: doors in OFFLINE rooms lock automatically
#   - elevator_panel.gd: elevators check PowerGrid for power state
#   - ConsumptionManager: degraded rooms reduce life support efficiency
#
# Save contract: generator output, damaged sections, per-room overrides.

# ── Power state enum ─────────────────────────────────────────────────────────

enum PowerState { POWERED, DEGRADED, OFFLINE }

signal power_state_changed(room_id: String, state: int)
signal grid_status_changed(available: float, demand: float)

const POWER_GRID_PATH: String = "res://data/power_grid.json"

# ── State ────────────────────────────────────────────────────────────────────

var _total_capacity: float = 100.0
var _generator_output: float = 100.0
var _rooms: Dictionary = {}          # room_id → {demand, priority, critical}
var _load_shed_order: Array[String] = []
var _room_states: Dictionary = {}   # room_id → PowerState
var _room_overrides: Dictionary = {}  # room_id → PowerState (designer/script forced)
var _damaged_sections: Dictionary = {}  # room_id → true (section offline, not load-shed)
var _loaded: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_distribute()
	_register_with_save_manager()
	_publish_to_game_state()

# ── Config loading ────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(POWER_GRID_PATH, FileAccess.READ)
	if f == null:
		push_error("PowerGrid: cannot open %s" % POWER_GRID_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("PowerGrid: %s did not parse to a Dictionary" % POWER_GRID_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_total_capacity = float(d.get("total_capacity", 100.0))
	_generator_output = _total_capacity
	var raw_rooms: Variant = d.get("rooms", {})
	if raw_rooms is Dictionary:
		_rooms = (raw_rooms as Dictionary).duplicate(true)
	var raw_order: Variant = d.get("load_shed_order", [])
	if raw_order is Array:
		_load_shed_order.clear()
		for entry in raw_order as Array:
			_load_shed_order.append(String(entry))
	_init_room_states()

func _init_room_states() -> void:
	for room_id in _rooms.keys():
		_room_states[String(room_id)] = PowerState.POWERED

# ── Distribution algorithm ─────────────────────────────────────────────────────

func _distribute() -> void:
	if _rooms.is_empty():
		return
	var available: float = get_available_power()
	var total_demand: float = get_total_demand()
	# Build a working set: room_id → demand, filtered by damaged sections.
	var pending: Array[Dictionary] = []  # [{id, demand, priority, critical}]
	for room_id in _rooms.keys():
		var rid: String = String(room_id)
		if _damaged_sections.has(rid):
			_set_room_state(rid, PowerState.OFFLINE)
			continue
		if _room_overrides.has(rid):
			_set_room_state(rid, int(_room_overrides[rid]))
			continue
		var row: Dictionary = _rooms[rid] as Dictionary
		pending.append({
			"id": rid,
			"demand": float(row.get("demand", 0.0)),
			"priority": int(row.get("priority", 99)),
			"critical": bool(row.get("critical", false)),
		})
	# Sort by priority (lower = higher precedence), preserving load_shed_order
	# for equal priorities.
	var shed_index: Dictionary = {}
	for i in _load_shed_order.size():
		shed_index[_load_shed_order[i]] = i
	pending.sort_custom(_compare_rooms.bind(shed_index))
	# Allocate power greedily by priority.
	var remaining: float = available
	var new_states: Dictionary = {}
	for entry in pending:
		var rid: String = entry["id"]
		var demand: float = entry["demand"]
		var critical: bool = entry["critical"]
		if remaining >= demand:
			new_states[rid] = PowerState.POWERED
			remaining -= demand
		elif remaining > 0.0 and critical:
			# Critical rooms get degraded power if some is available.
			new_states[rid] = PowerState.DEGRADED
			remaining = 0.0
		elif remaining > 0.0 and not critical:
			# Non-critical rooms with leftover power get degraded.
			new_states[rid] = PowerState.DEGRADED
			remaining = 0.0
		else:
			new_states[rid] = PowerState.OFFLINE
	# Apply states (skip overridden/damaged — already set above).
	for rid in new_states.keys():
		_set_room_state(String(rid), int(new_states[rid]))
	grid_status_changed.emit(available, total_demand)

func _compare_rooms(a: Dictionary, b: Dictionary, shed_index: Dictionary) -> bool:
	var pa: int = int(a["priority"])
	var pb: int = int(b["priority"])
	if pa != pb:
		return pa < pb
	# Tie-break via load_shed_order: rooms LATER in the shed order are kept
	# powered longer (they appear earlier in the priority-1 sort).
	var ia: int = int(shed_index.get(a["id"], 9999))
	var ib: int = int(shed_index.get(b["id"], 9999))
	return ia > ib  # later in shed order = shed last = powered longer

func _set_room_state(room_id: String, state: int) -> void:
	var prev: Variant = _room_states.get(room_id, PowerState.POWERED)
	if int(prev) != state:
		_room_states[room_id] = state
		power_state_changed.emit(room_id, state)

# ── Public API ───────────────────────────────────────────────────────────────

func get_total_capacity() -> float:
	return _total_capacity

func get_total_demand() -> float:
	var total: float = 0.0
	for room_id in _rooms.keys():
		if _damaged_sections.has(String(room_id)):
			continue
		var row: Dictionary = _rooms[String(room_id)] as Dictionary
		total += float(row.get("demand", 0.0))
	return total

func get_available_power() -> float:
	return _generator_output

func get_room_power_state(room_id: String) -> PowerState:
	if not _room_states.has(room_id):
		return PowerState.POWERED
	return int(_room_states[room_id]) as PowerState

func is_room_powered(room_id: String) -> bool:
	var state: int = get_room_power_state(room_id)
	return state != PowerState.OFFLINE

func is_room_degraded(room_id: String) -> bool:
	return get_room_power_state(room_id) == PowerState.DEGRADED

func set_generator_output(output: float) -> void:
	_generator_output = clampf(output, 0.0, _total_capacity)
	_distribute()
	_publish_to_game_state()

func repair_generator() -> void:
	_generator_output = _total_capacity
	_damaged_sections.clear()
	_distribute()
	_publish_to_game_state()

func get_load_shed_percentage() -> float:
	if _total_capacity <= 0.0:
		return 0.0
	var available: float = get_available_power()
	var demand: float = get_total_demand()
	if demand <= available:
		return 0.0
	return (demand - available) / demand * 100.0

# Per-room override: force a room to a specific state (e.g., hull breach cuts
# power to a section independent of the grid's load-shedding). Pass -1 to clear.
func set_room_override(room_id: String, state: int) -> void:
	if state < 0:
		_room_overrides.erase(room_id)
	else:
		_room_overrides[room_id] = state
	_distribute()

# Mark a section as damaged (physically offline, not load-shed). Cleared by
# repair_generator() or via set_section_repaired().
func set_section_damaged(room_id: String) -> void:
	_damaged_sections[room_id] = true
	_distribute()

func set_section_repaired(room_id: String) -> void:
	_damaged_sections.erase(room_id)
	_distribute()

func get_damaged_sections() -> Array[String]:
	var out: Array[String] = []
	for k in _damaged_sections.keys():
		out.append(String(k))
	return out

# Return all room IDs with their current state for HUD/map rendering.
func get_all_room_states() -> Dictionary:
	return _room_states.duplicate()

# ── GameState integration ─────────────────────────────────────────────────────

func _publish_to_game_state() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null or not gs.has_method("set_power_percent"):
		return
	var percent: float = 0.0
	if _total_capacity > 0.0:
		percent = (_generator_output / _total_capacity) * 100.0
	gs.call("set_power_percent", percent)

# ── Save / load (ISaveableSystem) ─────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"generator_output": _generator_output,
		"damaged_sections": _damaged_sections.keys().duplicate(),
		"room_overrides": _room_overrides.duplicate(),
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_generator_output = float(data.get("generator_output", _total_capacity))
	_damaged_sections.clear()
	var saved_damage: Variant = data.get("damaged_sections", [])
	if saved_damage is Array:
		for entry in saved_damage as Array:
			_damaged_sections[String(entry)] = true
	_room_overrides.clear()
	var saved_overrides: Variant = data.get("room_overrides", {})
	if saved_overrides is Dictionary:
		for k in (saved_overrides as Dictionary).keys():
			_room_overrides[String(k)] = int((saved_overrides as Dictionary)[k])
	_distribute()
	_publish_to_game_state()

func reset() -> void:
	_generator_output = _total_capacity
	_damaged_sections.clear()
	_room_overrides.clear()
	_distribute()
	_publish_to_game_state()

# ── Helpers ────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "power_grid", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)