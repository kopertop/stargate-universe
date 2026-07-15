extends Node

## CombatSystem autoload — manages player weapon inventory, damage
## application, weapon switching, reload, and cover detection for the
## Lucian Alliance boarding scenario (third-person combat).
##
## Weapons: Beretta M9 (pistol), H&K MP5 (SMG), FN P90 (SMG).
## Damage model: player damage flows through GameState.damage(); when
## health hits 0, GameState.knock_out("hostile") fires — NO DEATH, the
## player wakes in the med-bay. Enemy damage is applied directly to the
## enemy node's health property.
##
## Save contract: registers as "combat_system" via SaveManager.register_system.
## serialize() / deserialize() persist ammo counts per weapon + current weapon.
##
## Headless-testable: pure static functions for damage calc and ammo logic.

signal weapon_fired(weapon_id: String)
signal weapon_switched(weapon_id: String)
signal ammo_changed(current: int, reserve: int)
signal reload_started()
signal reload_finished()
signal enemy_damaged(enemy_id: String, amount: float)
signal enemy_killed(enemy_id: String)
signal player_in_cover_changed(in_cover: bool)

const _WeaponResource: Script = preload("res://scripts/weapon_resource.gd")

# --- Weapon slot order (1/2/3 keys map to these) ---------------------------
const WEAPON_PATHS: Array[String] = [
	"res://scripts/data/beretta_m9.tres",
	"res://scripts/data/mp5.tres",
	"res://scripts/data/p90.tres",
]
const WEAPON_SLOTS: Array[String] = ["beretta_m9", "mp5", "p90"]

# --- Combat tuning ---------------------------------------------------------
const COVER_HIT_CHANCE_MULT: float = 0.4   # in cover → incoming hit chance * 0.4
const COVER_PROXIMITY_RADIUS: float = 1.5  # metres from a CoverPoint to count as "in cover"
const RELOAD_ALLOW_INTERRUPT: bool = true
const ENEMY_GROUP: String = "enemy"
const PLAYER_GROUP: String = "player"
const COLLISION_LAYER_WORLD: int = 1

# --- Per-weapon ammo state -------------------------------------------------
# weapon_id → { "current": int, "reserve": int }
var _ammo: Dictionary = {}
# Starting reserve ammo per weapon (designers can tune).
const STARTING_RESERVE: Dictionary = {
	"beretta_m9": 45,   # 3 extra mags
	"mp5": 90,           # 3 extra mags
	"p90": 150,          # 3 extra mags
}

var _weapons: Dictionary = {}       # weapon_id → Resource (WeaponResource)
var _current_weapon_id: String = ""
var _current_slot: int = 0
var _fire_cooldown: float = 0.0
var _is_reloading: bool = false
var _reload_timer: float = 0.0
var _player_in_cover: bool = false
var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()
	set_process(true)


# Idempotent lazy init — autoloads AND headless -s test scripts both reach
# this on first public call. Mirrors InjurySystem._ensure_initialized.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_weapon_resources()
	_init_ammo()
	# Register with SaveManager (autoload-tolerant).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "combat_system", self)


func _load_weapon_resources() -> void:
	for i in WEAPON_PATHS.size():
		var path: String = WEAPON_PATHS[i]
		var res: Resource = load(path)
		if res == null or not is_instance_of(res, _WeaponResource):
			push_error("CombatSystem: failed to load weapon resource at %s" % path)
			continue
		var wr: Resource = res
		_weapons[wr.get("id")] = wr
	# Default to first weapon.
	if _weapons.size() > 0:
		_current_weapon_id = WEAPON_SLOTS[0]
		_current_slot = 0


func _init_ammo() -> void:
	for weapon_id in _weapons.keys():
		var wr: Resource = _weapons[weapon_id]
		_ammo[weapon_id] = {
			"current": int(wr.get("magazine_size")),
			"reserve": int(STARTING_RESERVE.get(weapon_id, int(wr.get("magazine_size")) * 3)),
		}


func _process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Returns the currently equipped weapon Resource, or null.
func current_weapon() -> Resource:
	_ensure_initialized()
	return _weapons.get(_current_weapon_id)


## Returns the current weapon id string.
func current_weapon_id() -> String:
	_ensure_initialized()
	return _current_weapon_id


## Returns the current slot index (0-based).
func current_slot() -> int:
	_ensure_initialized()
	return _current_slot


## Returns the weapon Resource for a given id, or null.
func get_weapon(weapon_id: String) -> Resource:
	_ensure_initialized()
	return _weapons.get(weapon_id)


## Returns ammo state for a weapon: { "current": int, "reserve": int }.
func get_ammo(weapon_id: String) -> Dictionary:
	_ensure_initialized()
	return _ammo.get(weapon_id, {"current": 0, "reserve": 0})


## Returns current mag ammo for the equipped weapon.
func current_mag_ammo() -> int:
	_ensure_initialized()
	var state: Dictionary = _ammo.get(_current_weapon_id, {})
	return int(state.get("current", 0))


## Returns reserve ammo for the equipped weapon.
func current_reserve_ammo() -> int:
	_ensure_initialized()
	var state: Dictionary = _ammo.get(_current_weapon_id, {})
	return int(state.get("reserve", 0))


## Returns true if the player is currently reloading.
func is_reloading() -> bool:
	return _is_reloading


## Returns true if the player can fire the current weapon right now
## (cooldown elapsed, not reloading, has ammo).
func can_fire() -> bool:
	_ensure_initialized()
	if _is_reloading or _fire_cooldown > 0.0:
		return false
	return current_mag_ammo() > 0


## Switch to weapon slot (0-based index). Returns true if the switch
## succeeded. Emits weapon_switched on success.
func switch_weapon(slot: int) -> bool:
	_ensure_initialized()
	if slot < 0 or slot >= WEAPON_SLOTS.size():
		return false
	var weapon_id: String = WEAPON_SLOTS[slot]
	if not _weapons.has(weapon_id):
		return false
	if weapon_id == _current_weapon_id:
		return false
	# Cancel any in-progress reload.
	if _is_reloading:
		_is_reloading = false
		_reload_timer = 0.0
	_current_weapon_id = weapon_id
	_current_slot = slot
	_fire_cooldown = 0.0
	weapon_switched.emit(weapon_id)
	_emit_ammo_changed()
	return true


## Attempt to fire the current weapon from `origin` toward `direction`.
## Returns true if a shot was fired. For hitscan weapons, performs a raycast
## and applies damage to the first enemy hit. For projectile weapons, spawns
## a projectile (not yet implemented — stub returns false for non-hitscan).
##
## origin:      global position of the muzzle / camera.
## direction:   normalized aim direction (before spread).
func fire(origin: Vector3, direction: Vector3) -> bool:
	_ensure_initialized()
	if not can_fire():
		return false
	var wr: Resource = current_weapon()
	if wr == null:
		return false
	# Apply spread.
	var actual_dir: Vector3 = _apply_spread(direction, float(wr.get("spread")))
	# Consume ammo.
	var state: Dictionary = _ammo[_current_weapon_id]
	state["current"] = int(state["current"]) - 1
	_ammo[_current_weapon_id] = state
	# Set cooldown.
	_fire_cooldown = wr.call("shot_interval")
	# Play fire sound.
	var sfx: String = String(wr.get("sound_fire"))
	if sfx != "":
		var audio: Node = _autoload_node("Audio")
		if audio != null and audio.has_method("play_sfx"):
			audio.call("play_sfx", sfx)
	weapon_fired.emit(String(wr.get("id")))
	_emit_ammo_changed()
	# Damage application.
	if wr.call("is_hitscan"):
		_perform_hitscan(origin, actual_dir, wr)
	else:
		_spawn_projectile(origin, actual_dir, wr)
	return true


## Start reloading the current weapon. Returns true if reload started.
func start_reload() -> bool:
	_ensure_initialized()
	if _is_reloading:
		return false
	var wr: Resource = current_weapon()
	if wr == null:
		return false
	var state: Dictionary = _ammo[_current_weapon_id]
	var current: int = int(state.get("current", 0))
	var reserve: int = int(state.get("reserve", 0))
	if current >= int(wr.get("magazine_size")) or reserve <= 0:
		return false
	_is_reloading = true
	_reload_timer = float(wr.get("reload_time"))
	reload_started.emit()
	var sfx_val: Variant = wr.get("sound_reload")
	var sfx: String = String(sfx_val) if sfx_val != null else ""
	if sfx != "":
		var audio: Node = _autoload_node("Audio")
		if audio != null and audio.has_method("play_sfx"):
			audio.call("play_sfx", sfx)
	return true


## Cancel an in-progress reload.
func cancel_reload() -> void:
	if not _is_reloading:
		return
	_is_reloading = false
	_reload_timer = 0.0


## Returns true if the player is currently in cover.
func is_in_cover() -> bool:
	return _player_in_cover


## Update the player's cover status. Called by CoverPoint when the player
## enters/exits, or by the player controller each frame. When in cover,
## incoming enemy fire has a reduced hit chance.
func set_player_in_cover(in_cover: bool) -> void:
	if _player_in_cover == in_cover:
		return
	_player_in_cover = in_cover
	player_in_cover_changed.emit(in_cover)


## Check cover status from the player's position against a threat position.
## Uses the CoverRegistry's raycast if available, otherwise falls back to
## proximity check against cover_point group.
func update_cover_status(player_position: Vector3, threat_position: Vector3) -> void:
	var reg: Node = _find_cover_registry()
	if reg != null and reg.has_method("is_position_in_cover"):
		set_player_in_cover(reg.call("is_position_in_cover", player_position, threat_position))
		return
	# Fallback: proximity to any cover point.
	for cp in get_tree().get_nodes_in_group("cover_point"):
		if not (cp is Node3D):
			continue
		var n3d: Node3D = cp as Node3D
		if n3d.global_position.distance_to(player_position) <= COVER_PROXIMITY_RADIUS:
			set_player_in_cover(true)
			return
	set_player_in_cover(false)


## Apply damage from an enemy to the player. Routes through GameState.damage()
## and checks for knockout at 0 health. Cover reduces the effective damage.
##
## enemy_id:     identifier of the attacking enemy.
## base_damage:  raw damage before cover mitigation.
## hit_chance:   base probability (0-1) the shot connects.
func apply_damage_to_player(enemy_id: String, base_damage: float, hit_chance: float = 1.0) -> void:
	_ensure_initialized()
	# Cover reduces hit chance.
	var effective_hit: float = hit_chance
	if _player_in_cover:
		effective_hit *= COVER_HIT_CHANCE_MULT
	# Roll for hit.
	if randf() > effective_hit:
		return
	# Apply damage through GameState.
	var gs: Node = _autoload_node("GameState")
	if gs == null or not gs.has_method("damage"):
		return
	gs.call("damage", base_damage)
	# Check for knockout (no-death model).
	if float(gs.get("health")) <= 0.0:
		# Route through InjurySystem for the HOSTILE cause tag, then knock_out.
		var isys: Node = _autoload_node("InjurySystem")
		if isys != null and isys.has_method("register_injury"):
			# InjurySystem.register_injury delegates to GameState.knock_out.
			var cause_enum: Dictionary = isys.get("InjuryCause")
			isys.call("register_injury", "eli", int(cause_enum.HOSTILE), 0.5)
		else:
			gs.call("knock_out", "hostile")


## Apply damage from the player to an enemy. Looks up the enemy node by
## id (via the "enemy" group) and calls `take_damage(amount)` on it.
## Emits enemy_damaged and enemy_killed (if the enemy's health drops to 0).
func apply_damage_to_enemy(enemy_id: String, amount: float) -> void:
	_ensure_initialized()
	var enemy: Node = _find_enemy(enemy_id)
	if enemy == null:
		return
	# Apply damage directly to the enemy's health.
	if enemy.has_method("take_damage"):
		enemy.call("take_damage", amount)
		enemy_damaged.emit(enemy_id, amount)
		# Check if the enemy is dead.
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			enemy_killed.emit(enemy_id)
	elif enemy.get("health") != null:
		enemy.set("health", float(enemy.get("health")) - amount)
		enemy_damaged.emit(enemy_id, amount)
		if float(enemy.get("health")) <= 0.0:
			enemy_killed.emit(enemy_id)


# ===========================================================================
# STATIC PURE FUNCTIONS (headless-testable, no autoload deps)
# ===========================================================================

## Pure function: calculate effective damage after cover mitigation.
## cover_factor: 1.0 = no cover, 0.3 = high cover (70% reduction).
static func calc_damage_with_cover(base_damage: float, cover_factor: float) -> float:
	return base_damage * clampf(cover_factor, 0.0, 1.0)


## Pure function: calculate hit chance after cover reduction.
## base_hit_chance: 0.0–1.0. in_cover: whether the target is in cover.
static func calc_hit_chance(base_hit_chance: float, in_cover: bool) -> float:
	if in_cover:
		return base_hit_chance * COVER_HIT_CHANCE_MULT
	return base_hit_chance


## Pure function: compute ammo after consuming one round.
## Returns { "current": int, "reserve": int } with current decremented.
## If current is 0, returns the input unchanged (can't fire empty).
static func consume_round(state: Dictionary) -> Dictionary:
	var current: int = int(state.get("current", 0))
	if current <= 0:
		return state
	return {
		"current": current - 1,
		"reserve": int(state.get("reserve", 0)),
	}


## Pure function: compute ammo after a reload.
## Moves rounds from reserve to current, up to magazine_size.
## Returns the new state.
static func reload_ammo(state: Dictionary, magazine_size: int) -> Dictionary:
	var current: int = int(state.get("current", 0))
	var reserve: int = int(state.get("reserve", 0))
	var needed: int = maxi(0, magazine_size - current)
	var to_move: int = mini(needed, reserve)
	return {
		"current": current + to_move,
		"reserve": reserve - to_move,
	}


## Pure function: compute a spread-perturbed direction.
## base_dir: normalized aim direction. spread_deg: cone half-angle in degrees.
## Returns a new normalized direction within the spread cone.
## Uses a deterministic seed if provided (for testability).
static func apply_spread_static(base_dir: Vector3, spread_deg: float, seed_val: int = -1) -> Vector3:
	if spread_deg <= 0.0:
		return base_dir
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	var spread_rad: float = deg_to_rad(spread_deg)
	# Pick a random angle within the spread cone.
	var angle: float = rng.randf_range(0.0, spread_rad)
	var azimuth: float = rng.randf_range(0.0, TAU)
	# Build a perturbation in the plane perpendicular to base_dir.
	var up: Vector3 = Vector3.UP if absf(base_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right: Vector3 = base_dir.cross(up).normalized()
	var forward: Vector3 = right.cross(base_dir).normalized()
	var offset: Vector3 = (right * cos(azimuth) + forward * sin(azimuth)) * sin(angle)
	return (base_dir + offset).normalized()


# ===========================================================================
# INTERNAL HELPERS
# ===========================================================================

func _apply_spread(direction: Vector3, spread_deg: float) -> Vector3:
	return apply_spread_static(direction, spread_deg)


func _perform_hitscan(origin: Vector3, direction: Vector3, wr: Resource) -> void:
	var space: PhysicsDirectSpaceState3D = _get_space_state()
	if space == null:
		return
	var end: Vector3 = origin + direction * float(wr.get("range"))
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	params.from = origin
	params.to = end
	params.collision_mask = 0xFFFFFFFF  # all layers
	params.exclude = []
	var result: Dictionary = space.intersect_ray(params)
	if result.is_empty():
		return
	var collider: Object = result.get("collider", null)
	if collider == null:
		return
	# Check if we hit an enemy.
	if collider.is_in_group(ENEMY_GROUP):
		var enemy_id: String = String(collider.get("enemy_id")) if collider.get("enemy_id") != null else collider.name
		apply_damage_to_enemy(enemy_id, float(wr.get("damage")))


func _spawn_projectile(origin: Vector3, direction: Vector3, wr: Resource) -> void:
	# Projectile spawning is a stub — the enemy AI agent will implement
	# the projectile node. For now, treat as hitscan with reduced range.
	_perform_hitscan(origin, direction, wr)


func _finish_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0
	var wr: Resource = current_weapon()
	if wr == null:
		return
	var state: Dictionary = _ammo[_current_weapon_id]
	_ammo[_current_weapon_id] = reload_ammo(state, int(wr.get("magazine_size")))
	reload_finished.emit()
	_emit_ammo_changed()


func _emit_ammo_changed() -> void:
	ammo_changed.emit(current_mag_ammo(), current_reserve_ammo())


func _find_enemy(enemy_id: String) -> Node:
	for enemy in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var eid: Variant = enemy.get("enemy_id")
		if eid != null and String(eid) == enemy_id:
			return enemy
		if enemy.name == enemy_id:
			return enemy
	return null


func _find_cover_registry() -> Node:
	# Check the current scene for a CoverRegistry (by group or script check).
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	for child in scene.get_children():
		if child.is_in_group("cover_registry"):
			return child
	# Fallback: group search.
	var nodes: Array[Node] = get_tree().get_nodes_in_group("cover_registry")
	if not nodes.is_empty():
		return nodes[0]
	return null


func _get_space_state() -> PhysicsDirectSpaceState3D:
	# As a Node (not Node3D), we don't have get_world_3d(). Find the
	# player or any Node3D in the scene to access the world.
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	# Try the player first.
	var player: Node = get_tree().get_first_node_in_group(PLAYER_GROUP)
	if player != null and player is Node3D:
		var n3d: Node3D = player as Node3D
		var ws: World3D = n3d.get_world_3d()
		if ws != null:
			return ws.direct_space_state
	# Fall back to any Node3D in the scene.
	for child in scene.get_children():
		if child is Node3D:
			var ws2: World3D = (child as Node3D).get_world_3d()
			if ws2 != null:
				return ws2.direct_space_state
	return null


# Same autoload-tolerant lookup as GameState._autoload_node.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# ===========================================================================
# SAVE ROUND-TRIP
# ===========================================================================

func serialize() -> Dictionary:
	return {
		"current_weapon_id": _current_weapon_id,
		"current_slot": _current_slot,
		"ammo": _ammo.duplicate(true),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_initialized()
	_current_weapon_id = String(data.get("current_weapon_id", _current_weapon_id))
	_current_slot = int(data.get("current_slot", 0))
	var saved_ammo: Variant = data.get("ammo", {})
	if saved_ammo is Dictionary:
		_ammo = (saved_ammo as Dictionary).duplicate(true)
	# Ensure all expected weapon ids exist in the ammo dict.
	for weapon_id in _weapons.keys():
		if not _ammo.has(weapon_id):
			var wr: Resource = _weapons[weapon_id]
			_ammo[weapon_id] = {
				"current": int(wr.get("magazine_size")),
				"reserve": int(STARTING_RESERVE.get(weapon_id, int(wr.get("magazine_size")) * 3)),
			}
	_emit_ammo_changed()
	weapon_switched.emit(_current_weapon_id)