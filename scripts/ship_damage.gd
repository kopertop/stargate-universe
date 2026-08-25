extends Node

# ShipDamage — hull integrity and per-room damage system for the Destiny.
#
# Numeric hull integrity (0-100%). Damage sources: meteor impacts, combat,
# FTL stress. Each damage event reduces overall hull integrity and damages
# the room it hits. Per-room integrity is tracked separately.
#
# Visual damage states: PRISTINE, DAMAGED, CRITICAL, DESTROYED.
# A room at DESTROYED forces PowerGrid conduit damage (electrical outage).
#
# Repair minigame: three repair actions (weld, patch, realign) each restore
# hull and room integrity at different rates and parts costs. The repair
# console interactable calls these methods.
#
# Integration:
#   - GameState.hull_percent + hull_changed signal (HUD)
#   - PowerGrid.damage_conduit when a room hits DESTROYED
#   - PowerGrid.set_section_damaged when a room drops below CRITICAL threshold
#   - ConsumptionManager reads hull integrity for life-support efficiency
#
# Save contract: hull integrity, per-room integrity, active repair jobs.

# ── Damage state enum ─────────────────────────────────────────────────────────
#
# Visual / functional damage states per room. Derived from room integrity
# percentage:
#   PRISTINE  — 100% to 75%
#   DAMAGED   — 74% to 50%
#   CRITICAL  — 49% to 25%
#   DESTROYED — below 25% (room offline, conduit damaged)

enum DamageState { PRISTINE, DAMAGED, CRITICAL, DESTROYED }

# ── Damage source enum ───────────────────────────────────────────────────────

enum DamageSource { METEOR_IMPACT, COMBAT, FTL_STRESS }

# ── Repair action enum ────────────────────────────────────────────────────────

enum RepairAction { WELD, PATCH, REALIGN }

signal hull_integrity_changed(value: float)
signal room_integrity_changed(room_id: String, value: float)
signal room_damage_state_changed(room_id: String, state: int)
signal repair_started(room_id: String, action: int)
signal repair_completed(room_id: String, action: int)

const SHIP_DAMAGE_PATH: String = "res://data/ship_damage.json"

# ── Config ────────────────────────────────────────────────────────────────────

var _max_hull: float = 100.0
var _critical_hull_threshold: float = 25.0
var _warning_hull_threshold: float = 50.0
var _damage_sources: Dictionary = {}
var _repair_actions: Dictionary = {}
var _room_configs: Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────

var _hull_integrity: float = 100.0
var _room_integrity: Dictionary = {}   # room_id → float (0 to max)
var _room_damage_states: Dictionary = {}  # room_id → DamageState
var _active_repairs: Dictionary = {}   # room_id → {action, remaining, total}
var _loaded: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_init_rooms()
	_register_with_save_manager()
	_publish_to_game_state()

# ── Config loading ──────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(SHIP_DAMAGE_PATH, FileAccess.READ)
	if f == null:
		push_error("ShipDamage: cannot open %s" % SHIP_DAMAGE_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ShipDamage: %s did not parse to a Dictionary" % SHIP_DAMAGE_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_max_hull = float(d.get("max_hull", 100.0))
	_critical_hull_threshold = float(d.get("critical_hull_threshold", 25.0))
	_warning_hull_threshold = float(d.get("warning_hull_threshold", 50.0))
	var raw_sources: Variant = d.get("damage_sources", {})
	if raw_sources is Dictionary:
		_damage_sources = (raw_sources as Dictionary).duplicate(true)
	var raw_repairs: Variant = d.get("repair_actions", {})
	if raw_repairs is Dictionary:
		_repair_actions = (raw_repairs as Dictionary).duplicate(true)
	var raw_rooms: Variant = d.get("rooms", {})
	if raw_rooms is Dictionary:
		_room_configs = (raw_rooms as Dictionary).duplicate(true)
	_hull_integrity = _max_hull

func _init_rooms() -> void:
	for room_id in _room_configs.keys():
		var rid: String = String(room_id)
		var row: Dictionary = _room_configs[rid] as Dictionary
		var max_int: float = float(row.get("max_integrity", 100.0))
		_room_integrity[rid] = max_int
		_room_damage_states[rid] = DamageState.PRISTINE

# ── Damage application ──────────────────────────────────────────────────────────

## Apply damage from a named source to the ship hull and a specific room.
## source_key must match a key in data/ship_damage.json damage_sources.
## room_id is the room that takes the hit. Returns the total hull damage dealt.
func apply_damage(source_key: String, room_id: String) -> float:
	if not _damage_sources.has(source_key):
		push_warning("ShipDamage: unknown damage source '%s'" % source_key)
		return 0.0
	if not _room_integrity.has(room_id):
		# Unknown room — apply hull damage only.
		var src: Dictionary = _damage_sources[source_key] as Dictionary
		var hull_dmg: float = float(src.get("hull_damage", 0.0))
		_hull_integrity = maxf(0.0, _hull_integrity - hull_dmg)
		hull_integrity_changed.emit(_hull_integrity)
		_publish_to_game_state()
		return hull_dmg
	var src: Dictionary = _damage_sources[source_key] as Dictionary
	var hull_dmg: float = float(src.get("hull_damage", 0.0))
	var room_dmg: float = float(src.get("room_damage", 0.0))
	var conduit_chance: float = float(src.get("conduit_chance", 0.0))
	# Apply hull damage.
	_hull_integrity = maxf(0.0, _hull_integrity - hull_dmg)
	hull_integrity_changed.emit(_hull_integrity)
	# Apply room damage.
	var prev_room: float = float(_room_integrity[room_id])
	var new_room: float = maxf(0.0, prev_room - room_dmg)
	_room_integrity[room_id] = new_room
	_update_room_damage_state(room_id)
	room_integrity_changed.emit(room_id, new_room)
	# Conduit damage chance — propagate to PowerGrid.
	if conduit_chance > 0.0 and randf() < conduit_chance:
		_damage_conduit(room_id)
	# If room hit DESTROYED, force section damage on PowerGrid.
	if int(_room_damage_states[room_id]) == DamageState.DESTROYED:
		_damage_section(room_id)
	_publish_to_game_state()
	return hull_dmg

## Apply damage from an enum source. Convenience wrapper for code using the
## DamageSource enum rather than string keys.
func apply_damage_enum(source: int, room_id: String) -> float:
	var key: String = _source_enum_to_key(source)
	return apply_damage(key, room_id)

# ── Per-room integrity ─────────────────────────────────────────────────────────

func get_room_integrity(room_id: String) -> float:
	if not _room_integrity.has(room_id):
		return 0.0
	return float(_room_integrity[room_id])

func get_room_integrity_percent(room_id: String) -> float:
	if not _room_integrity.has(room_id):
		return 0.0
	var row: Dictionary = _room_configs.get(room_id, {})
	var max_int: float = float(row.get("max_integrity", 100.0))
	if max_int <= 0.0:
		return 0.0
	return clampf(float(_room_integrity[room_id]) / max_int * 100.0, 0.0, 100.0)

func get_room_damage_state(room_id: String) -> DamageState:
	if not _room_damage_states.has(room_id):
		return DamageState.PRISTINE
	return int(_room_damage_states[room_id]) as DamageState

func get_room_damage_state_int(room_id: String) -> int:
	if not _room_damage_states.has(room_id):
		return int(DamageState.PRISTINE)
	return int(_room_damage_states[room_id])

func _update_room_damage_state(room_id: String) -> void:
	var pct: float = get_room_integrity_percent(room_id)
	var new_state: int = DamageState.PRISTINE
	if pct < 25.0:
		new_state = DamageState.DESTROYED
	elif pct < 50.0:
		new_state = DamageState.CRITICAL
	elif pct < 75.0:
		new_state = DamageState.DAMAGED
	var prev: int = int(_room_damage_states.get(room_id, DamageState.PRISTINE))
	if prev != new_state:
		_room_damage_states[room_id] = new_state
		room_damage_state_changed.emit(room_id, new_state)
		# When a room leaves DESTROYED/CRITICAL, clear section damage.
		if new_state < DamageState.CRITICAL:
			_repair_section(room_id)

func get_all_room_damage_states() -> Dictionary:
	return _room_damage_states.duplicate()

func get_all_room_integrity() -> Dictionary:
	return _room_integrity.duplicate()

# ── Hull integrity ──────────────────────────────────────────────────────────────

func get_hull_integrity() -> float:
	return _hull_integrity

func get_hull_integrity_percent() -> float:
	if _max_hull <= 0.0:
		return 0.0
	return clampf(_hull_integrity / _max_hull * 100.0, 0.0, 100.0)

func is_hull_critical() -> bool:
	return _hull_integrity <= _critical_hull_threshold

func is_hull_warning() -> bool:
	return _hull_integrity <= _warning_hull_threshold

func set_hull_integrity(value: float) -> void:
	_hull_integrity = clampf(value, 0.0, _max_hull)
	hull_integrity_changed.emit(_hull_integrity)
	_publish_to_game_state()

# ── Repair minigame ─────────────────────────────────────────────────────────────
#
# Three repair actions: weld, patch, realign. Each restores hull and room
# integrity at different rates. The repair console interactable starts a
# repair job; the system ticks it down over time (or completes it instantly
# under SceneRouter.instant_mode for headless tests).

## Start a repair action on a room. Returns false if a repair is already
## active on that room or the action is unknown.
func start_repair(room_id: String, action_key: String) -> bool:
	if not _room_integrity.has(room_id):
		return false
	if _active_repairs.has(room_id):
		return false
	if not _repair_actions.has(action_key):
		return false
	var action: Dictionary = _repair_actions[action_key] as Dictionary
	var duration: float = float(action.get("duration", 3.0))
	_active_repairs[room_id] = {
		"action": action_key,
		"remaining": duration,
		"total": duration,
	}
	repair_started.emit(room_id, _action_key_to_enum(action_key))
	return true

## Start a repair using the RepairAction enum.
func start_repair_enum(room_id: String, action: int) -> bool:
	var key: String = _action_enum_to_key(action)
	return start_repair(room_id, key)

## Process a repair tick. Called by _process or test_advance. Returns the
## list of room_ids whose repairs completed this tick.
func _tick_repairs(delta: float) -> Array[String]:
	if _active_repairs.is_empty():
		return []
	var completed: Array[String] = []
	for room_id in _active_repairs.keys():
		var rid: String = String(room_id)
		var job: Dictionary = _active_repairs[rid]
		job["remaining"] = maxf(0.0, float(job["remaining"]) - delta)
		if float(job["remaining"]) <= 0.0:
			completed.append(rid)
	# Complete finished repairs.
	for rid in completed:
		var job: Dictionary = _active_repairs[rid]
		var action_key: String = String(job.get("action", "weld"))
		_apply_repair_result(rid, action_key)
		_active_repairs.erase(rid)
		repair_completed.emit(rid, _action_key_to_enum(action_key))
	return completed

## Apply the repair result to hull and room integrity.
func _apply_repair_result(room_id: String, action_key: String) -> void:
	if not _repair_actions.has(action_key):
		return
	var action: Dictionary = _repair_actions[action_key] as Dictionary
	var hull_restore: float = float(action.get("hull_restore", 0.0))
	var room_restore: float = float(action.get("room_restore", 0.0))
	_hull_integrity = minf(_max_hull, _hull_integrity + hull_restore)
	hull_integrity_changed.emit(_hull_integrity)
	if _room_integrity.has(room_id):
		var row: Dictionary = _room_configs.get(room_id, {})
		var max_int: float = float(row.get("max_integrity", 100.0))
		var prev: float = float(_room_integrity[room_id])
		var new_val: float = minf(max_int, prev + room_restore)
		_room_integrity[room_id] = new_val
		_update_room_damage_state(room_id)
		room_integrity_changed.emit(room_id, new_val)
	_publish_to_game_state()

## Get the parts cost for a repair action.
func get_repair_cost(action_key: String) -> int:
	if not _repair_actions.has(action_key):
		return 0
	var action: Dictionary = _repair_actions[action_key] as Dictionary
	return int(action.get("parts_cost", 0))

## Get the parts cost for a repair action enum.
func get_repair_cost_enum(action: int) -> int:
	return get_repair_cost(_action_enum_to_key(action))

## Check if a room has an active repair in progress.
func is_repair_active(room_id: String) -> bool:
	return _active_repairs.has(room_id)

## Get the repair progress fraction (0.0 to 1.0) for a room. 0.0 if no active
## repair.
func get_repair_progress(room_id: String) -> float:
	if not _active_repairs.has(room_id):
		return 0.0
	var job: Dictionary = _active_repairs[room_id]
	var total: float = float(job.get("total", 0.0))
	if total <= 0.0:
		return 1.0
	return 1.0 - clampf(float(job.get("remaining", 0.0)) / total, 0.0, 1.0)

## Get all rooms with active repairs.
func get_active_repair_rooms() -> Array[String]:
	var out: Array[String] = []
	for k in _active_repairs.keys():
		out.append(String(k))
	return out

# ── _process ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var router: Node = _autoload("SceneRouter")
	if router != null and router.get("instant_mode") == true:
		return
	_tick_repairs(delta)

# ── PowerGrid integration ──────────────────────────────────────────────────────
#
# When a room drops to DESTROYED, its power conduit is damaged and the
# section is marked as physically offline. When a room is repaired above
# CRITICAL, the section damage is cleared (conduit repair is a separate
# action handled by PowerGrid.repair_conduit).

func _damage_conduit(room_id: String) -> void:
	var pg: Node = _autoload("PowerGrid")
	if pg == null or not pg.has_method("damage_conduit"):
		return
	pg.call("damage_conduit", room_id)

func _damage_section(room_id: String) -> void:
	var pg: Node = _autoload("PowerGrid")
	if pg == null or not pg.has_method("set_section_damaged"):
		return
	pg.call("set_section_damaged", room_id)

func _repair_section(room_id: String) -> void:
	var pg: Node = _autoload("PowerGrid")
	if pg == null or not pg.has_method("set_section_repaired"):
		return
	pg.call("set_section_repaired", room_id)

# ── GameState integration ──────────────────────────────────────────────────────

func _publish_to_game_state() -> void:
	var gs: Node = _autoload("GameState")
	if gs == null or not gs.has_method("set_hull_percent"):
		return
	var pct: float = get_hull_integrity_percent()
	gs.call("set_hull_percent", pct)

# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	var room_data: Dictionary = {}
	for room_id in _room_integrity.keys():
		room_data[String(room_id)] = float(_room_integrity[room_id])
	var repair_data: Dictionary = {}
	for room_id in _active_repairs.keys():
		repair_data[String(room_id)] = {
			"action": String(_active_repairs[room_id].get("action", "weld")),
			"remaining": float(_active_repairs[room_id].get("remaining", 0.0)),
			"total": float(_active_repairs[room_id].get("total", 0.0)),
		}
	return {
		"hull_integrity": _hull_integrity,
		"room_integrity": room_data,
		"active_repairs": repair_data,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_hull_integrity = float(data.get("hull_integrity", _max_hull))
	_room_integrity.clear()
	var saved_rooms: Variant = data.get("room_integrity", {})
	if saved_rooms is Dictionary:
		for k in (saved_rooms as Dictionary).keys():
			_room_integrity[String(k)] = float((saved_rooms as Dictionary)[k])
	# Ensure all configured rooms exist even if the save pre-dates a new room.
	for room_id in _room_configs.keys():
		var rid: String = String(room_id)
		if not _room_integrity.has(rid):
			var row: Dictionary = _room_configs[rid] as Dictionary
			_room_integrity[rid] = float(row.get("max_integrity", 100.0))
	# Recompute damage states.
	_room_damage_states.clear()
	for room_id in _room_integrity.keys():
		var rid: String = String(room_id)
		var pct: float = get_room_integrity_percent(rid)
		var state: int = DamageState.PRISTINE
		if pct < 25.0:
			state = DamageState.DESTROYED
		elif pct < 50.0:
			state = DamageState.CRITICAL
		elif pct < 75.0:
			state = DamageState.DAMAGED
		_room_damage_states[rid] = state
	# Restore active repairs.
	_active_repairs.clear()
	var saved_repairs: Variant = data.get("active_repairs", {})
	if saved_repairs is Dictionary:
		for k in (saved_repairs as Dictionary).keys():
			var rid: String = String(k)
			var job: Dictionary = (saved_repairs as Dictionary)[k] as Dictionary
			if job == null or job.is_empty():
				continue
			_active_repairs[rid] = {
				"action": String(job.get("action", "weld")),
				"remaining": float(job.get("remaining", 0.0)),
				"total": float(job.get("total", 0.0)),
			}
	_publish_to_game_state()

func reset() -> void:
	_hull_integrity = _max_hull
	_active_repairs.clear()
	for room_id in _room_configs.keys():
		var rid: String = String(room_id)
		var row: Dictionary = _room_configs[rid] as Dictionary
		_room_integrity[rid] = float(row.get("max_integrity", 100.0))
		_room_damage_states[rid] = DamageState.PRISTINE
	_publish_to_game_state()

# ── Enum conversion helpers ─────────────────────────────────────────────────────

func _source_enum_to_key(source: int) -> String:
	match source:
		DamageSource.METEOR_IMPACT:
			return "meteor_impact"
		DamageSource.COMBAT:
			return "combat"
		DamageSource.FTL_STRESS:
			return "ftl_stress"
		_:
			return "meteor_impact"

func _action_enum_to_key(action: int) -> String:
	match action:
		RepairAction.WELD:
			return "weld"
		RepairAction.PATCH:
			return "patch"
		RepairAction.REALIGN:
			return "realign"
		_:
			return "weld"

func _action_key_to_enum(key: String) -> int:
	match key:
		"weld":
			return RepairAction.WELD
		"patch":
			return RepairAction.PATCH
		"realign":
			return RepairAction.REALIGN
		_:
			return RepairAction.WELD

# ── Test hooks ──────────────────────────────────────────────────────────────────

## Advance repair ticks by a fixed delta (bypasses _process, for tests).
func test_advance(delta: float) -> Array[String]:
	return _tick_repairs(delta)

# ── Helpers ──────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "ship_damage", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)