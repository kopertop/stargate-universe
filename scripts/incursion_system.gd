extends Node

# IncursionSystem — E20 "Incursion" season finale.
#
# Multi-stage Lucian Alliance invasion of the Destiny:
#   1. SPACE COMBAT — enemy ships attack. Ship systems take hull damage
#      over time. The player must survive the bombardment.
#   2. BOARDING — enemy soldiers breach the hull and enter the corridors.
#      Multiple waves of boarders spawn via EnemySpawner patterns. The
#      player fights them off using the CombatSystem.
#   3. ROOM DEFENSE — hold critical rooms (gate_room, control_interface,
#      infirmary). If too many rooms are captured, the mission fails.
#   4. MORAL CHOICE — the Lucian commander offers terms: surrender the
#      ship (captured) or fight on (victory at a hull cost).
#   5. CLIFFHANGER — the episode ends on a cliffhanger beat regardless
#      of the choice. FTL drops and something appears.
#
# Integration:
#   - CombatSystem: boarding + defense waves use enemy spawner configs.
#   - ShipDamage: hull damage from space combat + the fight choice.
#   - TimerSystem: per-stage countdown timers.
#   - PowerGrid: conduit damage when rooms are captured.
#   - EpisodeManager: completion predicate "incursion_resolved".
#   - GameState: publishes incursion stage + stats for HUD.
#   - SaveManager: serialize/deserialize incursion state.
#
# Save contract: current stage, stages completed, moral choice, ship stats,
# captured rooms, wave progress.

signal stage_started(stage_id: String)
signal stage_completed(stage_id: String)
signal all_stages_completed()
signal wave_spawned(wave_index: int, stage_id: String)
signal room_captured(room_id: String)
signal moral_choice_presented()
signal moral_choice_resolved(choice_id: String, choice: String)
signal cliffhanger_triggered()
signal incursion_failed(reason: String)

enum Stage { NONE, SPACE_COMBAT, BOARDING, ROOM_DEFENSE, MORAL_CHOICE, CLIFFHANGER, COMPLETE }
enum Outcome { IN_PROGRESS, VICTORY, CAPTURED, FAILED }

const CONFIG_PATH: String = "res://data/incursion_config.json"

# ── Config ────────────────────────────────────────────────────────────────────

var _stages_config: Dictionary = {}
var _space_combat_duration: float = 90.0
var _boarding_wave_delay: float = 5.0
var _defense_hold_time: float = 60.0
var _max_hull_threshold: float = 30.0
var _space_tick_interval: float = 5.0
var _space_hull_damage_per_tick: float = 2.0
var _enemy_ship_count: int = 3
var _enemy_ship_names: Array[String] = []
var _boarding_waves: Array = []
var _defense_waves: Array = []
var _defense_rooms: Array[String] = []
var _capture_threshold: int = 3
var _moral_choices: Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────

var _current_stage: int = Stage.NONE
var _completed_stages: Array[int] = []
var _outcome: int = Outcome.IN_PROGRESS
var _moral_choice: String = ""
var _moral_choice_resolved: bool = false
var _space_tick_accumulator: float = 0.0
var _current_wave_index: int = -1
var _total_waves_cleared: int = 0
var _captured_rooms: Array[String] = []
var _space_timer_id: String = ""
var _boarding_timer_id: String = ""
var _defense_timer_id: String = ""
var _enemy_ships_remaining: int = 0
var _loaded: bool = false
var _instant_mode: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()

func _process(delta: float) -> void:
	if _instant_mode:
		return
	if _current_stage == Stage.SPACE_COMBAT:
		_tick_space_combat(delta)

# ── Config loading ──────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("IncursionSystem: cannot open %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("IncursionSystem: %s did not parse to a Dictionary" % CONFIG_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_max_hull_threshold = float(d.get("max_hull_threshold", 30.0))
	_space_combat_duration = float(d.get("space_combat_duration", 90.0))
	_boarding_wave_delay = float(d.get("boarding_wave_delay", 5.0))
	_defense_hold_time = float(d.get("defense_hold_time", 60.0))
	var stages_raw: Variant = d.get("stages", {})
	if stages_raw is Dictionary:
		_stages_config = (stages_raw as Dictionary).duplicate(true)
	# Parse space combat stage.
	var sc: Dictionary = _stages_config.get("space_combat", {})
	_space_tick_interval = float(sc.get("tick_interval", 5.0))
	_space_hull_damage_per_tick = float(sc.get("hull_damage_per_tick", 2.0))
	_enemy_ship_count = int(sc.get("enemy_ship_count", 3))
	var names_raw: Variant = sc.get("enemy_ship_names", [])
	_enemy_ship_names.clear()
	if names_raw is Array:
		for n in names_raw:
			_enemy_ship_names.append(String(n))
	# Parse boarding waves.
	var board: Dictionary = _stages_config.get("boarding", {})
	var bw_raw: Variant = board.get("waves", [])
	_boarding_waves.clear()
	if bw_raw is Array:
		for w in bw_raw:
			if w is Dictionary:
				_boarding_waves.append((w as Dictionary).duplicate(true))
	# Parse defense stage.
	var defense: Dictionary = _stages_config.get("room_defense", {})
	_defense_hold_time = float(defense.get("timer_duration", 60.0))
	_capture_threshold = int(defense.get("capture_threshold", 3))
	var dr_raw: Variant = defense.get("defense_rooms", [])
	_defense_rooms.clear()
	if dr_raw is Array:
		for r in dr_raw:
			_defense_rooms.append(String(r))
	var dw_raw: Variant = defense.get("waves", [])
	_defense_waves.clear()
	if dw_raw is Array:
		for w in dw_raw:
			if w is Dictionary:
				_defense_waves.append((w as Dictionary).duplicate(true))
	# Parse moral choices.
	var mc: Dictionary = _stages_config.get("moral_choice", {})
	var choices_raw: Variant = mc.get("choices", {})
	if choices_raw is Dictionary:
		_moral_choices = (choices_raw as Dictionary).duplicate(true)

# ── Public API: stage management ───────────────────────────────────────────────

## Start the incursion from the beginning. Resets all state.
func start_incursion() -> void:
	_current_stage = Stage.SPACE_COMBAT
	_completed_stages.clear()
	_outcome = Outcome.IN_PROGRESS
	_moral_choice = ""
	_moral_choice_resolved = false
	_space_tick_accumulator = 0.0
	_current_wave_index = -1
	_total_waves_cleared = 0
	_captured_rooms.clear()
	_enemy_ships_remaining = _enemy_ship_count
	stage_started.emit("space_combat")
	_start_space_timer()

## Advance to the next stage. Called internally when a stage completes.
func advance_stage() -> void:
	match _current_stage:
		Stage.SPACE_COMBAT:
			_complete_stage(Stage.SPACE_COMBAT)
			_start_boarding()
		Stage.BOARDING:
			_complete_stage(Stage.BOARDING)
			_start_room_defense()
		Stage.ROOM_DEFENSE:
			_complete_stage(Stage.ROOM_DEFENSE)
			_start_moral_choice()
		Stage.MORAL_CHOICE:
			_complete_stage(Stage.MORAL_CHOICE)
			_start_cliffhanger()
		Stage.CLIFFHANGER:
			_complete_stage(Stage.CLIFFHANGER)
			_outcome = _resolve_outcome()
			_current_stage = Stage.COMPLETE
			all_stages_completed.emit()

## Get the current stage as an int (Stage enum).
func get_current_stage() -> int:
	return _current_stage

## Get the current stage name as a string.
func get_current_stage_name() -> String:
	return _stage_name(_current_stage)

## Get the current outcome (IN_PROGRESS, VICTORY, CAPTURED, FAILED).
func get_outcome() -> int:
	return _outcome

## Get the moral choice that was made ("surrender" or "fight"). "" if none.
func get_moral_choice() -> String:
	return _moral_choice

## True if the incursion is complete (all stages done).
func is_complete() -> bool:
	return _current_stage == Stage.COMPLETE

## True if the incursion has not started.
func is_inactive() -> bool:
	return _current_stage == Stage.NONE

## Get the number of captured rooms.
func get_captured_room_count() -> int:
	return _captured_rooms.size()

## Get the list of captured room ids.
func get_captured_rooms() -> Array[String]:
	return _captured_rooms.duplicate()

## Get the number of enemy ships remaining in space combat.
func get_enemy_ships_remaining() -> int:
	return _enemy_ships_remaining

## Get the total waves cleared across boarding + defense stages.
func get_total_waves_cleared() -> int:
	return _total_waves_cleared

## Get the current wave index (-1 if no wave active).
func get_current_wave_index() -> int:
	return _current_wave_index

## Get the boarding wave configs.
func get_boarding_waves() -> Array:
	return _boarding_waves.duplicate(true)

## Get the defense wave configs.
func get_defense_waves() -> Array:
	return _defense_waves.duplicate(true)

## Get the defense room ids.
func get_defense_rooms() -> Array[String]:
	return _defense_rooms.duplicate()

## Get the moral choice options dictionary.
func get_moral_choices() -> Dictionary:
	return _moral_choices.duplicate(true)

# ── Space combat stage ─────────────────────────────────────────────────────────

func _start_space_timer() -> void:
	_space_timer_id = "incursion_space_combat"
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("start_timer"):
		ts.call("start_timer", _space_timer_id, _space_combat_duration)

func _tick_space_combat(delta: float) -> void:
	_space_tick_accumulator += delta
	if _space_tick_accumulator < _space_tick_interval:
		return
	_space_tick_accumulator = 0.0
	# Apply hull damage to the ship.
	var sd: Node = _autoload("ShipDamage")
	if sd != null and sd.has_method("apply_damage"):
		sd.call("apply_damage", "combat", "gate_room")
	_enemy_ships_remaining = maxi(0, _enemy_ships_remaining - 1)
	# Check if space combat is done.
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("has_timer"):
		if not ts.call("has_timer", _space_timer_id):
			advance_stage()

## Resolve a space combat tick headlessly (for tests). Returns true if the
## stage completed this tick.
func test_space_combat_tick(delta: float) -> bool:
	if _current_stage != Stage.SPACE_COMBAT:
		return false
	_tick_space_combat(delta)
	return _current_stage != Stage.SPACE_COMBAT

## Force-complete the space combat timer (for tests / scripted sequences).
func complete_space_combat() -> void:
	if _current_stage != Stage.SPACE_COMBAT:
		return
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("cancel_timer"):
		ts.call("cancel_timer", _space_timer_id)
	advance_stage()

# ── Boarding stage ─────────────────────────────────────────────────────────────

func _start_boarding() -> void:
	_current_stage = Stage.BOARDING
	_current_wave_index = -1
	_boarding_timer_id = "incursion_boarding"
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("start_timer"):
		ts.call("start_timer", _boarding_timer_id, 120.0)
	stage_started.emit("boarding")
	# Spawn the first wave immediately.
	_spawn_boarding_wave(0)

## Spawn a boarding wave by index. Returns true if the wave was started.
func _spawn_boarding_wave(wave_index: int) -> bool:
	if wave_index < 0 or wave_index >= _boarding_waves.size():
		return false
	_current_wave_index = wave_index
	wave_spawned.emit(wave_index, "boarding")
	return true

## Mark a boarding wave as cleared. Advances to the next wave or completes
## the boarding stage if all waves are done.
func mark_boarding_wave_cleared(wave_index: int) -> void:
	if _current_stage != Stage.BOARDING:
		return
	_total_waves_cleared += 1
	var next_idx: int = wave_index + 1
	if next_idx >= _boarding_waves.size():
		# All boarding waves cleared — advance.
		advance_stage()
	else:
		_spawn_boarding_wave(next_idx)

## Force-complete the boarding stage (for tests / scripted sequences).
func complete_boarding() -> void:
	if _current_stage != Stage.BOARDING:
		return
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("cancel_timer"):
		ts.call("cancel_timer", _boarding_timer_id)
	advance_stage()

## Get the number of boarding waves.
func get_boarding_wave_count() -> int:
	return _boarding_waves.size()

## Get a boarding wave config by index.
func get_boarding_wave(wave_index: int) -> Dictionary:
	if wave_index < 0 or wave_index >= _boarding_waves.size():
		return {}
	return _boarding_waves[wave_index]

# ── Room defense stage ─────────────────────────────────────────────────────────

func _start_room_defense() -> void:
	_current_stage = Stage.ROOM_DEFENSE
	_current_wave_index = -1
	_captured_rooms.clear()
	_defense_timer_id = "incursion_defense"
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("start_timer"):
		ts.call("start_timer", _defense_timer_id, _defense_hold_time)
	stage_started.emit("room_defense")
	# Spawn the first defense wave.
	_spawn_defense_wave(0)

## Spawn a defense wave by index. Returns true if the wave was started.
func _spawn_defense_wave(wave_index: int) -> bool:
	if wave_index < 0 or wave_index >= _defense_waves.size():
		return false
	_current_wave_index = wave_index
	wave_spawned.emit(wave_index, "room_defense")
	return true

## Mark a defense wave as cleared. Advances to the next wave or completes
## the defense stage if all waves are done.
func mark_defense_wave_cleared(wave_index: int) -> void:
	if _current_stage != Stage.ROOM_DEFENSE:
		return
	_total_waves_cleared += 1
	var next_idx: int = wave_index + 1
	if next_idx >= _defense_waves.size():
		advance_stage()
	else:
		_spawn_defense_wave(next_idx)

## Mark a room as captured by the enemy. If enough rooms are captured, the
## incursion fails.
func mark_room_captured(room_id: String) -> void:
	if _captured_rooms.has(room_id):
		return
	_captured_rooms.append(room_id)
	room_captured.emit(room_id)
	# Propagate to PowerGrid.
	var pg: Node = _autoload("PowerGrid")
	if pg != null and pg.has_method("set_section_damaged"):
		pg.call("set_section_damaged", room_id)
	if _captured_rooms.size() >= _capture_threshold:
		_fail_incursion("too_many_rooms_captured")

## Force-complete the room defense stage (for tests / scripted sequences).
func complete_room_defense() -> void:
	if _current_stage != Stage.ROOM_DEFENSE:
		return
	var ts: Node = _autoload("TimerSystem")
	if ts != null and ts.has_method("cancel_timer"):
		ts.call("cancel_timer", _defense_timer_id)
	advance_stage()

## Get the number of defense waves.
func get_defense_wave_count() -> int:
	return _defense_waves.size()

## Get a defense wave config by index.
func get_defense_wave(wave_index: int) -> Dictionary:
	if wave_index < 0 or wave_index >= _defense_waves.size():
		return {}
	return _defense_waves[wave_index]

## Get the capture threshold (how many rooms lost = failure).
func get_capture_threshold() -> int:
	return _capture_threshold

# ── Moral choice stage ─────────────────────────────────────────────────────────

func _start_moral_choice() -> void:
	_current_stage = Stage.MORAL_CHOICE
	moral_choice_presented.emit()
	stage_started.emit("moral_choice")

## Resolve the moral choice. choice_id must be "surrender" or "fight".
func resolve_moral_choice(choice_id: String) -> bool:
	if _current_stage != Stage.MORAL_CHOICE:
		return false
	if not _moral_choices.has(choice_id):
		return false
	_moral_choice = choice_id
	_moral_choice_resolved = true
	var choice: Dictionary = _moral_choices[choice_id] as Dictionary
	var hull_dmg: float = float(choice.get("hull_damage", 0.0))
	if hull_dmg > 0.0:
		var sd: Node = _autoload("ShipDamage")
		if sd != null and sd.has_method("apply_damage"):
			sd.call("apply_damage", "combat", "gate_room")
	moral_choice_resolved.emit(choice_id, String(choice.get("consequence", "")))
	advance_stage()
	return true

# ── Cliffhanger stage ──────────────────────────────────────────────────────────

func _start_cliffhanger() -> void:
	_current_stage = Stage.CLIFFHANGER
	cliffhanger_triggered.emit()
	stage_started.emit("cliffhanger")
	# The cliffhanger auto-advances to complete — it's a narrative beat.
	advance_stage()

# ── Internal helpers ───────────────────────────────────────────────────────────

func _complete_stage(stage: int) -> void:
	_completed_stages.append(stage)
	stage_completed.emit(_stage_name(stage))

func _fail_incursion(reason: String) -> void:
	_outcome = Outcome.FAILED
	_current_stage = Stage.COMPLETE
	incursion_failed.emit(reason)
	all_stages_completed.emit()

func _resolve_outcome() -> int:
	if _outcome == Outcome.FAILED:
		return Outcome.FAILED
	if _moral_choice == "surrender":
		return Outcome.CAPTURED
	return Outcome.VICTORY

func _stage_name(stage: int) -> String:
	match stage:
		Stage.NONE:
			return "none"
		Stage.SPACE_COMBAT:
			return "space_combat"
		Stage.BOARDING:
			return "boarding"
		Stage.ROOM_DEFENSE:
			return "room_defense"
		Stage.MORAL_CHOICE:
			return "moral_choice"
		Stage.CLIFFHANGER:
			return "cliffhanger"
		Stage.COMPLETE:
			return "complete"
		_:
			return "unknown"

# ── Test hooks ──────────────────────────────────────────────────────────────────

## Set instant mode — disables _process ticking (for headless tests that
## drive stages manually).
func set_instant_mode(enabled: bool) -> void:
	_instant_mode = enabled

## Advance the incursion to a specific stage (for testing). Skips intermediate
## stage logic. Does NOT start timers or spawn waves — use start_incursion()
## for the full flow.
func test_set_stage(stage: int) -> void:
	_current_stage = stage

# ── Save / load (ISaveableSystem) ───────────────────────────────────────────────

func serialize() -> Dictionary:
	var completed: Array[int] = []
	for s in _completed_stages:
		completed.append(int(s))
	return {
		"current_stage": int(_current_stage),
		"completed_stages": completed,
		"outcome": int(_outcome),
		"moral_choice": _moral_choice,
		"moral_choice_resolved": _moral_choice_resolved,
		"current_wave_index": _current_wave_index,
		"total_waves_cleared": _total_waves_cleared,
		"captured_rooms": _captured_rooms.duplicate(),
		"enemy_ships_remaining": _enemy_ships_remaining,
		"space_tick_accumulator": _space_tick_accumulator,
	}

func deserialize(data: Dictionary, _version: int) -> void:
	_current_stage = int(data.get("current_stage", Stage.NONE))
	_completed_stages.clear()
	var saved_completed: Variant = data.get("completed_stages", [])
	if saved_completed is Array:
		for s in saved_completed:
			_completed_stages.append(int(s))
	_outcome = int(data.get("outcome", Outcome.IN_PROGRESS))
	_moral_choice = String(data.get("moral_choice", ""))
	_moral_choice_resolved = bool(data.get("moral_choice_resolved", false))
	_current_wave_index = int(data.get("current_wave_index", -1))
	_total_waves_cleared = int(data.get("total_waves_cleared", 0))
	_captured_rooms.clear()
	var saved_rooms: Variant = data.get("captured_rooms", [])
	if saved_rooms is Array:
		for r in saved_rooms:
			_captured_rooms.append(String(r))
	_enemy_ships_remaining = int(data.get("enemy_ships_remaining", _enemy_ship_count))
	_space_tick_accumulator = float(data.get("space_tick_accumulator", 0.0))

func reset() -> void:
	_current_stage = Stage.NONE
	_completed_stages.clear()
	_outcome = Outcome.IN_PROGRESS
	_moral_choice = ""
	_moral_choice_resolved = false
	_space_tick_accumulator = 0.0
	_current_wave_index = -1
	_total_waves_cleared = 0
	_captured_rooms.clear()
	_enemy_ships_remaining = _enemy_ship_count

# ── Helpers ─────────────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = _autoload("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "incursion_system", self)

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)