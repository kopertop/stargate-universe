class_name Enemy
extends CharacterBody3D

# Lucian Alliance boarder — enemy combatant for the boarding scenario.
#
# A CharacterBody3D with a state-machine AI driven by enemy_ai.gd (loaded as
# const). Uses NavigationAgent3D for pathfinding and RayCast3D for line-of-sight
# to the player. Communicates via signals and group-based detection.
#
# Design rules (matching project conventions):
#   * NO-DEATH for the PLAYER: when this enemy shoots the player, damage routes
#     through CombatSystem.apply_enemy_damage() (or falls back to
#     GameState.damage() + InjurySystem). The player never dies — they get
#     knocked out and recover in the med-bay.
#   * Enemies CAN die: take_damage() reduces health; at health <= 0 the enemy
#     emits enemy_died and is freed.
#   * Collision layer 8 (enemy layer). Masks player (layer 1) and environment.
#   * Headless-testable: set_state() injects state directly, and all AI
#     decision functions are pure (in enemy_ai.gd).
#
# Scene composition (author in the editor or spawn at runtime):
#   Enemy (CharacterBody3D, layer 8)
#     ├── NavigationAgent3D
#     ├── RayCast3D          (targets player for LOS checks)
#     └── Character (Node3D)  (visual model — optional)

signal enemy_died(node: Node)
signal enemy_damaged(amount: float)
signal state_changed(new_state: int)

# --- State enum (mirrors EnemyAI.State) ---------------------------------------
enum EnemyState { IDLE, SEEK, FLANK, SUPPRESS, ADVANCE, TAKE_COVER, ATTACK }

# --- AI engine (pure decision functions) --------------------------------------
const AI: Script = preload("res://scripts/enemy_ai.gd")

# --- Default weapon (another agent creates the .tres) -------------------------
# Preloaded lazily in _ready to avoid load errors if the resource doesn't exist
# yet during development. Falls back to null gracefully.
const DEFAULT_WEAPON_PATH: String = "res://scripts/data/beretta_m9.tres"

# --- Ally detection range ----------------------------------------------------
const ALLY_RANGE: float = 20.0

# --- Cover detection range ---------------------------------------------------
const COVER_SEARCH_RANGE: float = 25.0

# --- Fire timing --------------------------------------------------------------
# Time between shots when in ATTACK state (seconds). Overridden by weapon
# fire_rate if a WeaponResource is assigned.
const DEFAULT_FIRE_INTERVAL: float = 0.8

# --- LOS check frequency ------------------------------------------------------
# RayCast3D is updated every N physics frames to save perf.
const LOS_CHECK_FRAMES: int = 3

@export_subgroup("Movement")
@export var move_speed: float = 4.0
@export var flank_speed: float = 5.5
@export var acceleration: float = 10.0
@export var gravity_strength: float = 25.0
@export var rotation_speed: float = 6.0

@export_subgroup("Combat")
@export var max_health: float = 100.0
@export var weapon: Resource = null  # WeaponResource .tres
@export var fire_interval_override: float = -1.0  # < 0 = use weapon fire_rate
@export var damage_to_player: float = 8.0  # per hit, if no weapon resource

@export_subgroup("AI Tuning")
@export var detection_range: float = 35.0
@export var los_check_frames: int = LOS_CHECK_FRAMES
@export var ally_range: float = ALLY_RANGE
@export var cover_search_range: float = COVER_SEARCH_RANGE

@export_subgroup("Nodes")
@export var nav_agent: NavigationAgent3D = null
@export var los_ray: RayCast3D = null
@export var model: Node3D = null

# --- Runtime state ------------------------------------------------------------
var health: float = 100.0
var _current_state: int = EnemyState.IDLE
var _player: Node = null
var _player_pos: Vector3 = Vector3.ZERO  # last known position
var _has_los: bool = false
var _fire_cooldown: float = 0.0
var _flank_side: int = 1
var _flank_angle: float = 0.0
var _frame_count: int = 0
var _dead: bool = false
var _under_fire: bool = false
var _under_fire_timer: float = 0.0
var _cover_target: Vector3 = Vector3.INF
var _flank_target: Vector3 = Vector3.ZERO
var _weapon_resource: Resource = null  # cached weapon resource

# --- Gravity ----------------------------------------------------------------
var _gravity_velocity: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	# Collision layer 8 = enemy layer. Mask player (1) + environment (world).
	collision_layer = 8
	collision_mask = 1  # collide with world geometry for movement

	health = max_health

	# Resolve nodes if not @export-assigned.
	if nav_agent == null:
		nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if los_ray == null:
		los_ray = get_node_or_null("RayCast3D") as RayCast3D
	if model == null:
		model = get_node_or_null("Character")

	# Load default weapon if none assigned (graceful if missing).
	if weapon == null:
		if ResourceLoader.exists(DEFAULT_WEAPON_PATH):
			weapon = load(DEFAULT_WEAPON_PATH)
	if weapon != null:
		_weapon_resource = weapon

	# Find the player via group.
	_find_player()


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_frame_count += 1

	# Update player reference if lost.
	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Update LOS periodically.
	if _frame_count % los_check_frames == 0:
		_update_los()

	# Update under-fire timer.
	if _under_fire_timer > 0.0:
		_under_fire_timer -= delta
		if _under_fire_timer <= 0.0:
			_under_fire = false

	# Update fire cooldown.
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	# Run AI decision and state behavior.
	_ai_tick(delta)

	# Apply gravity.
	if not is_on_floor():
		_gravity_velocity -= gravity_strength * delta
	else:
		_gravity_velocity = 0.0

	velocity.y += _gravity_velocity
	move_and_slide()


# ==============================================================================
# PUBLIC API — damage, state injection, queries
# ==============================================================================

# Apply damage to this enemy. Returns the actual damage dealt (clamped).
func take_damage(amount: float) -> float:
	if _dead:
		return 0.0
	var actual: float = minf(amount, health)
	health = maxf(health - amount, 0.0)
	enemy_damaged.emit(actual)
	_under_fire = true
	_under_fire_timer = 3.0
	if health <= 0.0:
		_die()
	return actual


# Directly set the AI state — for testing or scripted sequences.
func set_state(new_state: int) -> void:
	if new_state < 0 or new_state >= EnemyState.size():
		push_warning("Enemy.set_state: invalid state %d" % new_state)
		return
	if _current_state == new_state:
		return
	_current_state = new_state
	state_changed.emit(new_state)


# Get the current state (int matching EnemyState enum).
func get_state() -> int:
	return _current_state


# Get the current state as a string (for debugging / tests).
func get_state_name() -> String:
	return EnemyState.keys()[_current_state]


# Check if this enemy is dead.
func is_dead() -> bool:
	return _dead


# Get the current health fraction (0.0–1.0).
func health_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


# Get the distance to the player (or INF if no player).
func distance_to_player() -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	return global_position.distance_to(_player.global_position)


# Check if the enemy currently has line of sight to the player.
func has_line_of_sight() -> bool:
	return _has_los


# Get the player node (or null).
func get_player() -> Node:
	return _player


# Get the last known player position.
func get_last_known_player_pos() -> Vector3:
	return _player_pos


# Get the number of alive allies within ally_range.
func count_nearby_allies() -> int:
	var allies: Array = get_tree().get_nodes_in_group("enemy")
	var count: int = 0
	for ally in allies:
		if ally == self or not is_instance_valid(ally):
			continue
		if ally.has_method("is_dead") and ally.is_dead():
			continue
		if global_position.distance_to(ally.global_position) <= ally_range:
			count += 1
	return count


# Find all cover point positions within cover_search_range.
func get_nearby_cover_points() -> Array:
	var covers: Array = get_tree().get_nodes_in_group("cover_point")
	var positions: Array = []
	for cp in covers:
		if not is_instance_valid(cp):
			continue
		var pos: Vector3 = cp.global_position if cp is Node3D else Vector3.INF
		if pos != Vector3.INF and global_position.distance_to(pos) <= cover_search_range:
			positions.append(pos)
	return positions


# Fire the weapon at the player. Routes damage through CombatSystem if available,
# otherwise falls back to GameState.damage() + InjurySystem.
func fire_weapon() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Determine damage amount.
	var dmg: float = damage_to_player
	if _weapon_resource != null and _weapon_resource.has_method("get") and "damage" in _weapon_resource:
		dmg = float(_weapon_resource.get("damage"))

	# Route through CombatSystem if available, else fall back to GameState.
	var combat: Node = _get_combat_system()
	if combat != null and combat.has_method("apply_damage_to_player"):
		var enemy_id: String = name
		combat.call("apply_damage_to_player", enemy_id, dmg)
	else:
		_fallback_damage_player(dmg)


# ==============================================================================
# AI TICK — state machine logic
# ==============================================================================

func _ai_tick(delta: float) -> void:
	# Gather tactical info.
	var dist: float = distance_to_player()
	var health_frac: float = health_fraction()
	var ally_count: int = count_nearby_allies()
	var cover_pts: Array = get_nearby_cover_points()
	var cover_available: bool = cover_pts.size() > 0

	# Let the pure AI decide the state.
	var desired_state: int = AI.decide_state(
		dist, _has_los, health_frac, ally_count, cover_available, _under_fire
	)

	# Transition if changed.
	if desired_state != _current_state:
		set_state(desired_state)

	# Execute state behavior.
	match _current_state:
		EnemyState.IDLE:
			_state_idle(delta)
		EnemyState.SEEK:
			_state_seek(delta)
		EnemyState.FLANK:
			_state_flank(delta)
		EnemyState.SUPPRESS:
			_state_suppress(delta)
		EnemyState.ADVANCE:
			_state_advance(delta)
		EnemyState.TAKE_COVER:
			_state_take_cover(delta, cover_pts)
		EnemyState.ATTACK:
			_state_attack(delta)


func _state_idle(delta: float) -> void:
	# Stand still. Decelerate to zero.
	_apply_horizontal_velocity(Vector3.ZERO, delta)


func _state_seek(delta: float) -> void:
	# Move toward player's last known position via NavigationAgent.
	var target: Vector3 = _player_pos
	_navigate_to(target, move_speed, delta)


func _state_flank(delta: float) -> void:
	# Circle around the player at medium distance.
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector3 = _player.global_position
	var player_fwd: Vector3 = -_player.global_transform.basis.z.normalized()
	_flank_side = AI.decide_flank_side(global_position, player_pos, player_fwd)
	_flank_angle += AI.FLANK_ANGLE_STEP * delta * 2.0
	_flank_target = AI.compute_flank_position(player_pos, player_fwd, _flank_side, _flank_angle)
	_navigate_to(_flank_target, flank_speed, delta)


func _state_suppress(delta: float) -> void:
	# Hold position and fire toward the player with high spread.
	_apply_horizontal_velocity(Vector3.ZERO, delta)
	# Fire if possible.
	var weapon_range: float = _get_weapon_range()
	if AI.should_fire(_current_state, _has_los, _fire_cooldown, distance_to_player(), weapon_range):
		fire_weapon()
		_fire_cooldown = _get_fire_interval()


func _state_advance(delta: float) -> void:
	# Rush toward the player aggressively.
	var target: Vector3 = _player_pos
	var speed: float = move_speed * AI.speed_multiplier(EnemyState.ADVANCE)
	_navigate_to(target, speed, delta)


func _state_take_cover(delta: float, cover_pts: Array) -> void:
	# Find nearest cover and move there.
	if _cover_target == Vector3.INF or _cover_target == Vector3.ZERO:
		_cover_target = AI.find_nearest_cover(global_position, cover_pts)
	if _cover_target != Vector3.INF:
		var speed: float = move_speed * AI.speed_multiplier(EnemyState.TAKE_COVER)
		_navigate_to(_cover_target, speed, delta)
		# If we've arrived, clear the cover target so we re-evaluate.
		if global_position.distance_to(_cover_target) < 1.5:
			_cover_target = Vector3.INF
	else:
		# No cover available — fall back to seeking.
		_state_seek(delta)


func _state_attack(delta: float) -> void:
	# Stand and fire at the player.
	_apply_horizontal_velocity(Vector3.ZERO, delta)
	# Face the player.
	_face_target(_player_pos, delta)
	# Fire if possible.
	var weapon_range: float = _get_weapon_range()
	if AI.should_fire(_current_state, _has_los, _fire_cooldown, distance_to_player(), weapon_range):
		fire_weapon()
		_fire_cooldown = _get_fire_interval()


# ==============================================================================
# MOVEMENT HELPERS
# ==============================================================================

func _navigate_to(target: Vector3, speed: float, delta: float) -> void:
	if nav_agent != null and is_instance_valid(nav_agent):
		nav_agent.target_position = target
		if nav_agent.is_navigation_ready():
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			var dir: Vector3 = (next_pos - global_position).normalized()
			_apply_horizontal_velocity(dir * speed, delta)
			_face_target(next_pos, delta)
			return
	# Fallback: direct movement (no nav mesh).
	var dir: Vector3 = (target - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	_apply_horizontal_velocity(dir * speed, delta)
	_face_target(target, delta)


func _apply_horizontal_velocity(desired: Vector3, delta: float) -> void:
	# Smoothly interpolate horizontal velocity toward the desired value.
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)


func _face_target(target: Vector3, delta: float) -> void:
	var dir: Vector3 = target - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	var target_yaw: float = atan2(-dir.x, -dir.z)
	var current_yaw: float = rotation.y
	# Shortest-angle interpolation.
	var diff: float = angle_difference(target_yaw, current_yaw)
	rotation.y = current_yaw + diff * rotation_speed * delta


# ==============================================================================
# LOS & PLAYER DETECTION
# ==============================================================================

func _find_player() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_player = null
		return
	var players: Array = tree.get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		if _player is Node3D:
			_player_pos = _player.global_position
	else:
		_player = null


func _update_los() -> void:
	if _player == null or not is_instance_valid(_player):
		_has_los = false
		return

	# Update last known position.
	_player_pos = _player.global_position

	# Use RayCast3D if available.
	if los_ray != null and is_instance_valid(los_ray):
		# Aim the ray at the player.
		var from: Vector3 = global_position + Vector3(0.0, 1.0, 0.0)
		var to: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
		los_ray.target_position = to - from
		los_ray.global_position = from
		los_ray.force_raycast_update()
		var collider: Object = los_ray.get_collider()
		# If the ray hits the player (or nothing blocking), we have LOS.
		_has_los = (collider == _player) or (collider == null and not los_ray.is_colliding())
	else:
		# Fallback: simple distance + no obstacle check (assume LOS if close).
		_has_los = distance_to_player() <= detection_range


# ==============================================================================
# COMBAT HELPERS
# ==============================================================================

func _get_weapon_range() -> float:
	if _weapon_resource != null and "range" in _weapon_resource:
		return float(_weapon_resource.get("range"))
	return 20.0  # default effective range


func _get_fire_interval() -> float:
	if fire_interval_override >= 0.0:
		return fire_interval_override
	if _weapon_resource != null and "fire_rate" in _weapon_resource:
		var fr: float = float(_weapon_resource.get("fire_rate"))
		if fr > 0.0:
			return 1.0 / fr
	return DEFAULT_FIRE_INTERVAL


func _get_combat_system() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("CombatSystem")


func _fallback_damage_player(amount: float) -> void:
	# Direct GameState.damage() fallback when CombatSystem isn't available.
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	var gs: Node = loop.root.get_node_or_null("GameState")
	if gs == null:
		return
	gs.call("damage", amount)
	# If health hits 0, route through InjurySystem for hostile knockout.
	if float(gs.get("health")) <= 0.0:
		var isys: Node = loop.root.get_node_or_null("InjurySystem")
		if isys != null:
			# Register a HOSTILE injury (recoverable — no death).
			isys.call("register_injury", "eli", isys.InjuryCause.HOSTILE, 0.5)
		else:
			# Last resort: knock_out directly.
			gs.call("knock_out", "hostile")


# ==============================================================================
# DEATH
# ==============================================================================

func _die() -> void:
	if _dead:
		return
	_dead = true
	enemy_died.emit(self)
	# Remove from groups so ally counts update immediately.
	remove_from_group("enemy")
	# Notify any spawner tracking this enemy via the tree_exiting signal.
	# queue_free fires tree_exiting at end of frame, but in headless tests
	# we also emit a direct notification so listeners can react immediately.
	# Free the node after the signal has been emitted.
	queue_free()