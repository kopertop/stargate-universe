class_name EnemyAI
extends RefCounted

# Companion AI decision engine for enemy.gd (Lucian Alliance boarders).
#
# Loaded as a const by enemy.gd — NOT an autoload. All decision functions are
# PURE: they take a state Dictionary (distance, health, allies, cover, LOS)
# and return an action Dictionary or state enum int. This keeps the AI logic
# headless-testable without needing a live scene tree, NavigationAgent, or
# RayCast.
#
# State machine:
#   IDLE       — no player detected; stand still or patrol.
#   SEEK       — move toward player's last known position via NavigationAgent3D.
#   FLANK      — circle around player at medium distance, approaching from the side.
#   SUPPRESS   — stay at range, fire toward player's position to keep them pinned.
#   ADVANCE    — rush toward player aggressively.
#   TAKE_COVER — find nearest cover point (group "cover_point"), move there.
#   ATTACK     — in line of sight, fire weapon at player.
#
# State selection logic considers: distance to player, health level, nearby
# cover availability, and number of allied enemies nearby.
#
# Suppression fire: fires in player's general direction with high spread / low
# accuracy (the weapon's spread is inflated and fire rate is sustained).
# Flanking: picks a side (left or right based on relative position), moves to
# a flank position offset perpendicular to the player-facing vector.

# --- State enum (mirrors enemy.gd's EnemyState) -------------------------------
# Kept here so pure decision functions can return the int without depending
# on the enemy node. enemy.gd defines its own enum with the same order.
enum State { IDLE, SEEK, FLANK, SUPPRESS, ADVANCE, TAKE_COVER, ATTACK }

# --- Distance thresholds (metres) ---------------------------------------------
const CLOSE_RANGE: float = 8.0
const MEDIUM_RANGE: float = 18.0
const LONG_RANGE: float = 35.0

# --- Health thresholds (fraction of max) --------------------------------------
const LOW_HEALTH_FRAC: float = 0.3
const CRITICAL_HEALTH_FRAC: float = 0.15

# --- Flank parameters ---------------------------------------------------------
const FLANK_RADIUS: float = 12.0    # medium-distance orbit around the player
const FLANK_ANGLE_STEP: float = 0.6 # radians per tick to circle around

# --- Suppression parameters ---------------------------------------------------
const SUPPRESS_SPREAD_MULT: float = 3.0  # multiply weapon spread for suppression
const SUPPRESS_ACCURACY_FRAC: float = 0.25  # only 25% of shots are aimed

# ==============================================================================
# PUBLIC — pure decision functions (headless-testable)
# ==============================================================================

# Given the current tactical situation, decide which state the enemy should be in.
# All params are plain values so this can be called headlessly.
#
#   distance_to_player  — metres to the player (or INF if unknown)
#   has_los             — true if RayCast3D has line of sight to the player
#   health_frac         — current health / max health (0.0–1.0)
#   ally_count           — number of other alive enemies within ALLY_RANGE
#   cover_available      — true if at least one "cover_point" node exists nearby
#   under_fire           — true if the enemy was recently damaged
#
# Returns a State enum int.
static func decide_state(
	distance_to_player: float,
	has_los: bool,
	health_frac: float,
	ally_count: int,
	cover_available: bool,
	under_fire: bool
) -> int:
	# No player detected — idle.
	if distance_to_player == INF or distance_to_player < 0.0:
		return State.IDLE

	# Critical health + cover available → take cover to recover.
	if health_frac <= CRITICAL_HEALTH_FRAC and cover_available:
		return State.TAKE_COVER

	# Low health + under fire → take cover if possible.
	if health_frac <= LOW_HEALTH_FRAC and under_fire and cover_available:
		return State.TAKE_COVER

	# In line of sight and close enough → attack.
	if has_los and distance_to_player <= CLOSE_RANGE:
		return State.ATTACK

	# In line of sight at medium range with allies → suppress while others advance.
	if has_los and distance_to_player <= MEDIUM_RANGE and ally_count >= 2:
		return State.SUPPRESS

	# In line of sight at medium range → attack or flank.
	if has_los and distance_to_player <= MEDIUM_RANGE:
		# With at least one ally, flank to approach from the side.
		if ally_count >= 1:
			return State.FLANK
		return State.ATTACK

	# In line of sight at long range → suppress to pin the player.
	if has_los and distance_to_player <= LONG_RANGE:
		return State.SUPPRESS

	# No line of sight but have a last known position → seek.
	if distance_to_player <= LONG_RANGE:
		# Under fire while seeking → take cover if available.
		if under_fire and cover_available:
			return State.TAKE_COVER
		return State.SEEK

	# Very far away with no LOS → advance to close the gap.
	return State.ADVANCE


# Decide which side to flank on (left or right) based on the enemy's position
# relative to the player's facing direction.
#
#   enemy_pos       — enemy global position
#   player_pos      — player global position
#   player_forward  — player's facing direction (Vector3, normalized)
#
# Returns +1 for right flank, -1 for left flank.
static func decide_flank_side(
	enemy_pos: Vector3,
	player_pos: Vector3,
	player_forward: Vector3
) -> int:
	var to_enemy: Vector3 = (enemy_pos - player_pos).normalized()
	# Cross product of player_forward and to_enemy gives the side.
	# Positive Y cross → enemy is to the right; negative → left.
	var cross: float = player_forward.x * to_enemy.z - player_forward.z * to_enemy.x
	return 1 if cross >= 0.0 else -1


# Compute the target position for flanking — a point at FLANK_RADIUS from the
# player, offset to the chosen side, and circling over time.
#
#   player_pos      — player global position
#   player_forward  — player's facing direction (normalized)
#   flank_side      — +1 (right) or -1 (left)
#   angle_offset    — accumulated angle for circling (radians)
#
# Returns the flank target position in world space.
static func compute_flank_position(
	player_pos: Vector3,
	player_forward: Vector3,
	flank_side: int,
	angle_offset: float
) -> Vector3:
	# Perpendicular to player's forward (in the XZ plane).
	var perp: Vector3 = Vector3(-player_forward.z, 0.0, player_forward.x) * flank_side
	var angle: float = angle_offset
	# Rotate the perpendicular vector by the angle to circle around.
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	var offset: Vector3 = perp * cos_a + player_forward * sin_a
	return player_pos + offset * FLANK_RADIUS


# Compute a suppression fire direction — the player's general direction with
# extra spread applied. Returns a normalized direction vector.
#
#   enemy_pos   — enemy global position
#   player_pos  — player's current (or last known) position
#   weapon_spread — the weapon's base spread (radians)
#
# Returns a Vector3 direction (normalized) with suppression spread baked in.
static func compute_suppression_direction(
	enemy_pos: Vector3,
	player_pos: Vector3,
	weapon_spread: float
) -> Vector3:
	var base_dir: Vector3 = (player_pos - enemy_pos).normalized()
	var spread: float = weapon_spread * SUPPRESS_SPREAD_MULT
	# Apply random angular offset within the spread cone.
	var rand_yaw: float = randf_range(-spread, spread)
	var rand_pitch: float = randf_range(-spread, spread)
	# Rotate around Y (yaw) then around the right axis (pitch).
	var dir: Vector3 = base_dir.rotated(Vector3.UP, rand_yaw)
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	dir = dir.rotated(right, rand_pitch)
	return dir.normalized()


# Find the nearest cover point from the available cover nodes.
#
#   enemy_pos      — enemy global position
#   cover_points   — Array of Vector3 positions of cover nodes
#
# Returns the nearest cover position, or Vector3.INF if none available.
static func find_nearest_cover(
	enemy_pos: Vector3,
	cover_points: Array
) -> Vector3:
	var best_pos: Vector3 = Vector3.INF
	var best_dist: float = INF
	for cp in cover_points:
		if cp is Vector3:
			var d: float = enemy_pos.distance_to(cp)
			if d < best_dist:
				best_dist = d
				best_pos = cp
	return best_pos


# Count allies within a given range of the enemy.
#
#   enemy_pos    — enemy global position
#   ally_positions — Array of Vector3 positions of other alive enemies
#   range_m      — detection range in metres
#
# Returns the count of allies within range.
static func count_allies_in_range(
	enemy_pos: Vector3,
	ally_positions: Array,
	range_m: float
) -> int:
	var count: int = 0
	for pos in ally_positions:
		if pos is Vector3:
			if enemy_pos.distance_to(pos) <= range_m:
				count += 1
	return count


# Determine if the enemy should fire its weapon this tick.
#
#   current_state   — the enemy's current State
#   has_los         — line of sight to player
#   fire_cooldown   — seconds remaining until the weapon can fire again
#   distance        — distance to player
#   weapon_range    — effective range of the weapon
#
# Returns true if the enemy should fire.
static func should_fire(
	current_state: int,
	has_los: bool,
	fire_cooldown: float,
	distance: float,
	weapon_range: float
) -> bool:
	if fire_cooldown > 0.0:
		return false
	if not has_los:
		return false
	if distance > weapon_range:
		return false
	# ATTACK and SUPPRESS states fire; others don't.
	return current_state == State.ATTACK or current_state == State.SUPPRESS


# Compute the effective spread for the current state.
#
#   base_spread   — the weapon's base spread (radians)
#   current_state — the enemy's current State
#
# Returns the effective spread.
static func effective_spread(base_spread: float, current_state: int) -> float:
	if current_state == State.SUPPRESS:
		return base_spread * SUPPRESS_SPREAD_MULT
	return base_spread


# Compute the effective accuracy for the current state (0.0–1.0).
#
#   current_state — the enemy's current State
#
# Returns the accuracy fraction.
static func effective_accuracy(current_state: int) -> float:
	if current_state == State.SUPPRESS:
		return SUPPRESS_ACCURACY_FRAC
	# ATTACK is fully aimed; other combat states are slightly less accurate.
	if current_state == State.ATTACK:
		return 1.0
	return 0.5


# Compute the movement speed multiplier for the current state.
#
#   current_state — the enemy's current State
#
# Returns a speed multiplier (1.0 = normal speed).
static func speed_multiplier(current_state: int) -> float:
	match current_state:
		State.ADVANCE:
			return 1.5   # rush aggressively
		State.FLANK:
			return 1.0   # normal flank speed (enemy.gd uses flank_speed)
		State.SEEK:
			return 1.0
		State.TAKE_COVER:
			return 1.2   # hurry to cover
		State.SUPPRESS:
			return 0.0   # hold position while suppressing
		State.ATTACK:
			return 0.3   # slow strafe while attacking
		_:
			return 0.0   # IDLE — no movement


# Compute the desired move target for the current state.
#
#   current_state  — the enemy's current State
#   enemy_pos      — enemy global position
#   player_pos     — player's current or last known position
#   cover_pos      — nearest cover position (or Vector3.INF)
#   flank_target   — computed flank position
#
# Returns the desired movement target position.
static func compute_move_target(
	current_state: int,
	enemy_pos: Vector3,
	player_pos: Vector3,
	cover_pos: Vector3,
	flank_target: Vector3
) -> Vector3:
	match current_state:
		State.SEEK:
			return player_pos
		State.ADVANCE:
			return player_pos
		State.FLANK:
			return flank_target
		State.TAKE_COVER:
			return cover_pos if cover_pos != Vector3.INF else enemy_pos
		State.SUPPRESS:
			return enemy_pos  # hold position
		State.ATTACK:
			return enemy_pos  # stand and fire
		_:
			return enemy_pos  # IDLE — stay put