class_name EnemySpawner
extends Node3D

# Spawns enemy waves for the Lucian Alliance boarding scenario.
#
# Place this Node in a scene (e.g. the gate room or corridor where boarders
# arrive). Configure wave_configs in the inspector, then call spawn_wave(index)
# from a quest event, interactable, or trigger zone.
#
# Wave config dictionary keys:
#   count           — int, number of enemies in this wave
#   weapon          — Resource path (String) or Resource, the weapon to equip
#   spawn_delay     — float, seconds between each enemy spawn in the wave
#   position_offset — Vector3, offset from the spawner's position for the spawn point
#
# Signals:
#   wave_started(index)  — fired when a wave begins spawning
#   wave_cleared(index)  — fired when all enemies in a wave are dead
#   all_waves_cleared    — fired when the last wave is cleared
#
# Tracks alive enemies per wave. When all enemies in the current wave are dead,
# emits wave_cleared. If more waves remain, the caller can spawn the next one;
# if all waves are done, emits all_waves_cleared.

signal wave_started(index: int)
signal wave_cleared(index: int)
signal all_waves_cleared

# --- Enemy scene (CharacterBody3D with enemy.gd) ------------------------------
# Can be overridden per-wave via the wave config's "enemy_scene" key.
const DEFAULT_ENEMY_SCRIPT: Script = preload("res://scripts/enemy.gd")

# --- Default wave configs (can be overridden via @export) ---------------------
const DEFAULT_WAVES: Array = [
	{
		"count": 3,
		"weapon": "res://scripts/data/beretta_m9.tres",
		"spawn_delay": 0.8,
		"position_offset": Vector3(0, 0, 2),
	},
	{
		"count": 4,
		"weapon": "res://scripts/data/beretta_m9.tres",
		"spawn_delay": 0.6,
		"position_offset": Vector3(0, 0, 2),
	},
	{
		"count": 5,
		"weapon": "res://scripts/data/beretta_m9.tres",
		"spawn_delay": 0.5,
		"position_offset": Vector3(0, 0, 2),
	},
]

@export var wave_configs: Array = []:
	set = _set_wave_configs

@export_subgroup("Spawning")
@export var auto_start: bool = false       # start first wave on _ready
@export var auto_advance: bool = false     # auto-spawn next wave when current clears
@export var spawn_root: NodePath = NodePath("")  # parent node for spawned enemies (default: self)

# --- Runtime state ------------------------------------------------------------
var _current_wave: int = -1
var _alive_enemies: Array[Node] = []
var _spawning: bool = false
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _all_waves_done: bool = false


func _ready() -> void:
	if wave_configs.is_empty():
		wave_configs = DEFAULT_WAVES.duplicate(true)
	if auto_start:
		spawn_wave(0)


func _process(delta: float) -> void:
	# Process the spawn queue (staggered spawning within a wave).
	if _spawn_queue.is_empty():
		set_process(false)
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		var cfg: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(cfg)
		if not _spawn_queue.is_empty():
			_spawn_timer = _spawn_queue[0].get("spawn_delay", 0.5)
		# If the queue is now empty, spawning is done for this wave.
		if _spawn_queue.is_empty():
			_spawning = false


# ==============================================================================
# PUBLIC API
# ==============================================================================

# Start spawning a wave by index (0-based). Returns true if the wave was started.
func spawn_wave(wave_index: int) -> bool:
	if wave_index < 0 or wave_index >= wave_configs.size():
		push_warning("EnemySpawner.spawn_wave: invalid wave index %d" % wave_index)
		return false
	if _spawning:
		push_warning("EnemySpawner.spawn_wave: already spawning wave %d" % _current_wave)
		return false
	if _all_waves_done:
		push_warning("EnemySpawner.spawn_wave: all waves already cleared")
		return false

	_current_wave = wave_index
	_alive_enemies.clear()

	var wave_cfg: Dictionary = wave_configs[wave_index]
	var count: int = int(wave_cfg.get("count", 1))
	var delay: float = float(wave_cfg.get("spawn_delay", 0.5))

	# Build the spawn queue.
	_spawn_queue.clear()
	for i in range(count):
		var cfg: Dictionary = wave_cfg.duplicate(true)
		# Apply per-enemy offset variation.
		var base_offset: Vector3 = cfg.get("position_offset", Vector3.ZERO)
		cfg["position_offset"] = base_offset + Vector3(
			randf_range(-1.5, 1.5),
			0.0,
			randf_range(-1.5, 1.5)
		)
		cfg["spawn_delay"] = delay
		_spawn_queue.append(cfg)

	_spawning = true
	_spawn_timer = 0.0  # spawn first enemy immediately
	wave_started.emit(wave_index)
	set_process(true)
	return true


# Get the current wave index (-1 if no wave has been started).
func get_current_wave() -> int:
	return _current_wave


# Get the number of alive enemies in the current wave.
func alive_count() -> int:
	_clean_dead_enemies()
	return _alive_enemies.size()


# Check if the spawner is currently spawning enemies.
func is_spawning() -> bool:
	return _spawning


# Check if all waves have been cleared.
func all_waves_complete() -> bool:
	return _all_waves_done


# Get the total number of wave configs.
func wave_count() -> int:
	return wave_configs.size()


# Force-clear the current wave (e.g. for debugging or scripted sequences).
func clear_current_wave() -> void:
	_clean_dead_enemies()
	if _alive_enemies.size() == 0 and _current_wave >= 0:
		_on_wave_cleared(_current_wave)


# ==============================================================================
# SPAWNING
# ==============================================================================

func _spawn_enemy(cfg: Dictionary) -> void:
	# Create the enemy node.
	var enemy: CharacterBody3D = _create_enemy_node(cfg)
	if enemy == null:
		push_error("EnemySpawner: failed to create enemy node")
		return

	# Position the enemy (use local position since the enemy is added as a
	# sibling of the spawner, not a child — so global = local relative to
	# the shared parent).
	var offset: Vector3 = cfg.get("position_offset", Vector3.ZERO)
	enemy.position = (global_position if is_inside_tree() else position) + offset

	# Assign weapon if specified.
	var weapon_path: Variant = cfg.get("weapon", null)
	if weapon_path != null:
		_assign_weapon(enemy, weapon_path)

	# Track the enemy. Listen to enemy_died for immediate notification
	# (tree_exiting fires at end of frame, which is too late in headless tests).
	_alive_enemies.append(enemy)
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy))
	enemy.tree_exiting.connect(_on_enemy_exiting.bind(enemy))

	# Add to the scene tree.
	var parent: Node = _get_spawn_parent()
	parent.add_child(enemy)


func _create_enemy_node(cfg: Dictionary) -> CharacterBody3D:
	# Check for a custom enemy scene in the wave config.
	var scene_path: String = cfg.get("enemy_scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		if scene != null:
			return scene.instantiate() as CharacterBody3D

	# Create a bare CharacterBody3D with the enemy script.
	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.set_script(DEFAULT_ENEMY_SCRIPT)

	# Add a NavigationAgent3D child for pathfinding.
	var nav: NavigationAgent3D = NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	enemy.add_child(nav)

	# Add a RayCast3D child for LOS checks.
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "RayCast3D"
	ray.enabled = true
	ray.collision_mask = 1  # collide with world geometry
	enemy.add_child(ray)

	return enemy


func _assign_weapon(enemy: CharacterBody3D, weapon_path: Variant) -> void:
	if weapon_path == null:
		return
	var resource: Resource = null
	if weapon_path is Resource:
		resource = weapon_path as Resource
	elif weapon_path is String and ResourceLoader.exists(weapon_path):
		resource = load(weapon_path)
	if resource != null and enemy.has_method("set"):
		enemy.set("weapon", resource)


# ==============================================================================
# WAVE TRACKING
# ==============================================================================

func _on_enemy_died(_node: Node, enemy: Node) -> void:
	# Called immediately when the enemy emits enemy_died — faster than
	# tree_exiting for wave-clear detection.
	var idx: int = _alive_enemies.find(enemy)
	if idx >= 0:
		_alive_enemies.remove_at(idx)
	_check_wave_cleared()


func _on_enemy_exiting(enemy: Node) -> void:
	# Called when an enemy node is being freed (death or removal).
	var idx: int = _alive_enemies.find(enemy)
	if idx >= 0:
		_alive_enemies.remove_at(idx)
	_check_wave_cleared()


func _check_wave_cleared() -> void:
	_clean_dead_enemies()
	if not _spawning and _alive_enemies.size() == 0 and _current_wave >= 0:
		_on_wave_cleared(_current_wave)


func _on_wave_cleared(wave_index: int) -> void:
	wave_cleared.emit(wave_index)

	# Check if all waves are done.
	if wave_index >= wave_configs.size() - 1:
		_all_waves_done = true
		all_waves_cleared.emit()
	elif auto_advance:
		# Auto-advance to the next wave.
		spawn_wave(wave_index + 1)


func _clean_dead_enemies() -> void:
	# Remove any null/freed entries from the alive list.
	var i: int = _alive_enemies.size() - 1
	while i >= 0:
		var e: Node = _alive_enemies[i]
		if e == null or not is_instance_valid(e):
			_alive_enemies.remove_at(i)
		i -= 1


# ==============================================================================
# HELPERS
# ==============================================================================

func _get_spawn_parent() -> Node:
	if spawn_root != NodePath(""):
		var parent: Node = get_node_or_null(spawn_root)
		if parent != null:
			return parent
	# Default: add as children of the spawner's parent (or root).
	if get_parent() != null:
		return get_parent()
	return get_tree().current_scene


func _set_wave_configs(value: Array) -> void:
	wave_configs = value