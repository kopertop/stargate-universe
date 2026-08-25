extends SceneTree

# Combat system smoke test — exercises the weapon resource, CombatSystem
# autoload, enemy AI pure decision functions, and the cover system.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/combat_system.gd
#
# Covers:
#   1. WeaponResource loading and properties
#   2. CombatSystem autoload init, weapon switching, ammo, reload
#   3. CombatSystem pure static functions (damage calc, ammo, spread)
#   4. EnemyAI pure decision functions (state selection, flanking, cover)
#   5. Enemy node: take_damage, state injection, death
#   6. CoverPoint / CoverRegistry basic registration

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== combat system smoke test ===")

	_test_weapon_resources()
	_test_combat_system_autoload()
	_test_combat_static_functions()
	_test_enemy_ai_decisions()
	_test_enemy_node()
	_test_cover_system()

	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _fail(label: String) -> void:
	_failures.append(label)
	print("  FAIL: %s" % label)


# ---------------------------------------------------------------------------
# 1. WeaponResource loading
# ---------------------------------------------------------------------------
func _test_weapon_resources() -> void:
	print("\n--- weapon resources ---")

	var WeaponResourceScript: Script = load("res://scripts/weapon_resource.gd")
	_expect(WeaponResourceScript != null, "load WeaponResource script")

	# Load each .tres and verify fields.
	var m9: Resource = load("res://scripts/data/beretta_m9.tres")
	_expect(m9 != null, "load beretta_m9.tres")
	if m9 != null:
		_expect(is_instance_of(m9, WeaponResourceScript), "m9 is WeaponResource")
		_expect(String(m9.id) == "beretta_m9", "m9 id == beretta_m9")
		_expect(String(m9.display_name) == "Beretta M9", "m9 display_name")
		_expect(m9.damage == 25.0, "m9 damage == 25")
		_expect(m9.magazine_size == 15, "m9 mag size == 15")
		_expect(m9.auto == false, "m9 is semi-auto")
		_expect(m9.is_hitscan() == true, "m9 is hitscan")
		_expect(m9.shot_interval() > 0.0, "m9 shot_interval > 0")

	var mp5: Resource = load("res://scripts/data/mp5.tres")
	_expect(mp5 != null, "load mp5.tres")
	if mp5 != null:
		_expect(String(mp5.id) == "mp5", "mp5 id == mp5")
		_expect(mp5.damage == 18.0, "mp5 damage == 18")
		_expect(mp5.magazine_size == 30, "mp5 mag size == 30")
		_expect(mp5.auto == true, "mp5 is full-auto")

	var p90: Resource = load("res://scripts/data/p90.tres")
	_expect(p90 != null, "load p90.tres")
	if p90 != null:
		_expect(String(p90.id) == "p90", "p90 id == p90")
		_expect(p90.damage == 15.0, "p90 damage == 15")
		_expect(p90.magazine_size == 50, "p90 mag size == 50")
		_expect(p90.auto == true, "p90 is full-auto")

	# Verify load_from static helper.
	var loaded: Object = WeaponResourceScript.load_from("res://scripts/data/beretta_m9.tres")
	_expect(loaded != null, "WeaponResource.load_from returns non-null")
	var bad: Object = WeaponResourceScript.load_from("res://nonexistent.tres")
	_expect(bad == null, "WeaponResource.load_from returns null for missing file")


# ---------------------------------------------------------------------------
# 2. CombatSystem autoload
# ---------------------------------------------------------------------------
func _test_combat_system_autoload() -> void:
	print("\n--- combat system autoload ---")

	var combat: Node = root.get_node_or_null("CombatSystem")
	_expect(combat != null, "CombatSystem autoload is attached")
	if combat == null:
		return

	# Verify it loaded weapons.
	var wr: Resource = combat.call("current_weapon")
	_expect(wr != null, "current_weapon returns non-null")
	_expect(combat.call("current_weapon_id") == "beretta_m9", "default weapon is beretta_m9")
	_expect(combat.call("current_slot") == 0, "default slot is 0")

	# Ammo: full mag on init.
	_expect(combat.call("current_mag_ammo") == 15, "initial mag ammo == 15 (m9)")
	_expect(combat.call("current_reserve_ammo") == 45, "initial reserve == 45 (m9)")

	# Weapon switching.
	var switched: bool = combat.call("switch_weapon", 1)
	_expect(switched == true, "switch to slot 1 (mp5)")
	_expect(combat.call("current_weapon_id") == "mp5", "current weapon is mp5 after switch")
	_expect(combat.call("current_mag_ammo") == 30, "mp5 mag ammo == 30")
	_expect(combat.call("current_reserve_ammo") == 90, "mp5 reserve == 90")

	# Switch back to slot 0.
	combat.call("switch_weapon", 0)
	_expect(combat.call("current_weapon_id") == "beretta_m9", "switch back to m9")

	# Switch to p90 (slot 2).
	combat.call("switch_weapon", 2)
	_expect(combat.call("current_weapon_id") == "p90", "switch to p90")
	_expect(combat.call("current_mag_ammo") == 50, "p90 mag ammo == 50")

	# can_fire should be true with full mag.
	_expect(combat.call("can_fire") == true, "can_fire with full mag")

	# Reload should fail when mag is full.
	var reload_result: bool = combat.call("start_reload")
	_expect(reload_result == false, "reload fails when mag is full")

	# is_reloading should be false.
	_expect(combat.call("is_reloading") == false, "not reloading initially")

	# is_in_cover should be false initially.
	_expect(combat.call("is_in_cover") == false, "not in cover initially")

	# get_weapon for a bad id returns null.
	_expect(combat.call("get_weapon", "nonexistent") == null, "get_weapon returns null for bad id")

	# get_ammo for a bad id returns empty state.
	var bad_ammo: Dictionary = combat.call("get_ammo", "nonexistent")
	_expect(int(bad_ammo.get("current", -1)) == 0, "get_ammo returns 0 current for bad id")


# ---------------------------------------------------------------------------
# 3. CombatSystem pure static functions
# ---------------------------------------------------------------------------
func _test_combat_static_functions() -> void:
	print("\n--- combat static functions ---")

	# Use the autoload instance for static function calls (combat_system.gd
	# has no class_name, so Script.static_func() doesn't work in GDScript).
	var combat: Node = root.get_node_or_null("CombatSystem")
	if combat == null:
		_fail("CombatSystem autoload not available for static function tests")
		return

	# calc_damage_with_cover
	var dmg_full: float = combat.call("calc_damage_with_cover", 20.0, 1.0)
	_expect(dmg_full == 20.0, "cover damage: no cover = full damage")
	var dmg_half: float = combat.call("calc_damage_with_cover", 20.0, 0.5)
	_expect(dmg_half == 10.0, "cover damage: 0.5 factor = half damage")
	var dmg_zero: float = combat.call("calc_damage_with_cover", 20.0, 0.0)
	_expect(dmg_zero == 0.0, "cover damage: 0 factor = zero damage")

	# calc_hit_chance
	var hc_normal: float = combat.call("calc_hit_chance", 0.9, false)
	_expect(hc_normal == 0.9, "hit chance: no cover = base")
	var hc_cover: float = combat.call("calc_hit_chance", 0.9, true)
	_expect(hc_cover == 0.9 * combat.get("COVER_HIT_CHANCE_MULT"), "hit chance: in cover = reduced")

	# consume_round
	var ammo_state: Dictionary = {"current": 10, "reserve": 30}
	var after_consume: Dictionary = combat.call("consume_round", ammo_state)
	_expect(int(after_consume["current"]) == 9, "consume_round: decrements current")
	_expect(int(after_consume["reserve"]) == 30, "consume_round: reserve unchanged")

	# consume_round with 0 current
	var empty_state: Dictionary = {"current": 0, "reserve": 30}
	var after_empty: Dictionary = combat.call("consume_round", empty_state)
	_expect(int(after_empty["current"]) == 0, "consume_round: 0 current stays 0")

	# reload_ammo
	var partial_state: Dictionary = {"current": 5, "reserve": 30}
	var after_reload: Dictionary = combat.call("reload_ammo", partial_state, 15)
	_expect(int(after_reload["current"]) == 15, "reload_ammo: fills to mag size")
	_expect(int(after_reload["reserve"]) == 20, "reload_ammo: decrements reserve by moved amount")

	# reload_ammo with insufficient reserve
	var low_reserve: Dictionary = {"current": 12, "reserve": 2}
	var after_low: Dictionary = combat.call("reload_ammo", low_reserve, 15)
	_expect(int(after_low["current"]) == 14, "reload_ammo: partial fill with low reserve")
	_expect(int(after_low["reserve"]) == 0, "reload_ammo: reserve depleted")

	# apply_spread_static with seed for determinism
	var dir: Vector3 = Vector3.FORWARD
	var spread_dir: Vector3 = combat.call("apply_spread_static", dir, 5.0, 42)
	_expect(spread_dir != dir, "apply_spread: direction changed")
	_expect(spread_dir.is_normalized(), "apply_spread: result is normalized")
	# Same seed = same result (deterministic).
	var spread_dir2: Vector3 = combat.call("apply_spread_static", dir, 5.0, 42)
	_expect(spread_dir == spread_dir2, "apply_spread: same seed = same result")

	# Zero spread = unchanged direction.
	var no_spread: Vector3 = combat.call("apply_spread_static", dir, 0.0, 42)
	_expect(no_spread == dir, "apply_spread: 0 spread = unchanged direction")


# ---------------------------------------------------------------------------
# 4. EnemyAI pure decision functions
# ---------------------------------------------------------------------------
func _test_enemy_ai_decisions() -> void:
	print("\n--- enemy AI decisions ---")

	var EnemyAIScript: Script = load("res://scripts/enemy_ai.gd")
	_expect(EnemyAIScript != null, "load EnemyAI script")

	# decide_state: no player → IDLE
	var state: int = EnemyAIScript.decide_state(INF, false, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.IDLE, "decide_state: no player → IDLE")

	# decide_state: close range with LOS → ATTACK
	state = EnemyAIScript.decide_state(5.0, true, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.ATTACK, "decide_state: close LOS → ATTACK")

	# decide_state: medium range with LOS, no allies → ATTACK
	state = EnemyAIScript.decide_state(12.0, true, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.ATTACK, "decide_state: medium LOS, no allies → ATTACK")

	# decide_state: medium range with LOS, 1 ally → FLANK
	state = EnemyAIScript.decide_state(12.0, true, 1.0, 1, false, false)
	_expect(state == EnemyAIScript.State.FLANK, "decide_state: medium LOS, 1 ally → FLANK")

	# decide_state: medium range with LOS, 2+ allies → SUPPRESS
	state = EnemyAIScript.decide_state(15.0, true, 1.0, 2, false, false)
	_expect(state == EnemyAIScript.State.SUPPRESS, "decide_state: medium LOS, 2 allies → SUPPRESS")

	# decide_state: long range with LOS → SUPPRESS
	state = EnemyAIScript.decide_state(30.0, true, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.SUPPRESS, "decide_state: long LOS → SUPPRESS")

	# decide_state: no LOS, in range → SEEK
	state = EnemyAIScript.decide_state(20.0, false, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.SEEK, "decide_state: no LOS, in range → SEEK")

	# decide_state: critical health + cover → TAKE_COVER
	state = EnemyAIScript.decide_state(10.0, true, 0.1, 0, true, false)
	_expect(state == EnemyAIScript.State.TAKE_COVER, "decide_state: critical health + cover → TAKE_COVER")

	# decide_state: low health + under fire + cover → TAKE_COVER
	state = EnemyAIScript.decide_state(10.0, true, 0.25, 0, true, true)
	_expect(state == EnemyAIScript.State.TAKE_COVER, "decide_state: low health + under fire + cover → TAKE_COVER")

	# decide_state: very far, no LOS → ADVANCE
	state = EnemyAIScript.decide_state(50.0, false, 1.0, 0, false, false)
	_expect(state == EnemyAIScript.State.ADVANCE, "decide_state: very far, no LOS → ADVANCE")

	# decide_flank_side
	var side: int = EnemyAIScript.decide_flank_side(
		Vector3(5, 0, 0), Vector3.ZERO, Vector3.FORWARD
	)
	_expect(side == 1 or side == -1, "decide_flank_side: returns +1 or -1")

	# compute_flank_position
	var flank_pos: Vector3 = EnemyAIScript.compute_flank_position(
		Vector3.ZERO, Vector3.FORWARD, 1, 0.0
	)
	_expect(flank_pos != Vector3.ZERO, "compute_flank_position: returns non-zero")
	_expect(flank_pos.distance_to(Vector3.ZERO) > 0.0, "compute_flank_position: offset from player")

	# find_nearest_cover
	var covers: Array = [Vector3(5, 0, 0), Vector3(2, 0, 0), Vector3(10, 0, 0)]
	var nearest: Vector3 = EnemyAIScript.find_nearest_cover(Vector3.ZERO, covers)
	_expect(nearest == Vector3(2, 0, 0), "find_nearest_cover: returns closest point")

	# find_nearest_cover with empty array
	var no_cover: Vector3 = EnemyAIScript.find_nearest_cover(Vector3.ZERO, [])
	_expect(no_cover == Vector3.INF, "find_nearest_cover: empty → INF")

	# should_fire
	_expect(EnemyAIScript.should_fire(EnemyAIScript.State.ATTACK, true, 0.0, 10.0, 30.0) == true, "should_fire: ATTACK + LOS + in range → true")
	_expect(EnemyAIScript.should_fire(EnemyAIScript.State.ATTACK, false, 0.0, 10.0, 30.0) == false, "should_fire: no LOS → false")
	_expect(EnemyAIScript.should_fire(EnemyAIScript.State.ATTACK, true, 1.0, 10.0, 30.0) == false, "should_fire: on cooldown → false")
	_expect(EnemyAIScript.should_fire(EnemyAIScript.State.SEEK, true, 0.0, 10.0, 30.0) == false, "should_fire: SEEK state → false")
	_expect(EnemyAIScript.should_fire(EnemyAIScript.State.ATTACK, true, 0.0, 50.0, 30.0) == false, "should_fire: out of range → false")

	# effective_spread
	_expect(EnemyAIScript.effective_spread(2.0, EnemyAIScript.State.SUPPRESS) == 2.0 * EnemyAIScript.SUPPRESS_SPREAD_MULT, "effective_spread: SUPPRESS inflates")
	_expect(EnemyAIScript.effective_spread(2.0, EnemyAIScript.State.ATTACK) == 2.0, "effective_spread: ATTACK = base")

	# effective_accuracy
	_expect(EnemyAIScript.effective_accuracy(EnemyAIScript.State.ATTACK) == 1.0, "effective_accuracy: ATTACK = 1.0")
	_expect(EnemyAIScript.effective_accuracy(EnemyAIScript.State.SUPPRESS) == EnemyAIScript.SUPPRESS_ACCURACY_FRAC, "effective_accuracy: SUPPRESS = 0.25")

	# speed_multiplier
	_expect(EnemyAIScript.speed_multiplier(EnemyAIScript.State.ADVANCE) == 1.5, "speed_multiplier: ADVANCE = 1.5")
	_expect(EnemyAIScript.speed_multiplier(EnemyAIScript.State.IDLE) == 0.0, "speed_multiplier: IDLE = 0.0")

	# count_allies_in_range
	var ally_positions: Array = [Vector3(1, 0, 0), Vector3(5, 0, 0), Vector3(15, 0, 0)]
	var count: int = EnemyAIScript.count_allies_in_range(Vector3.ZERO, ally_positions, 10.0)
	_expect(count == 2, "count_allies_in_range: 2 within 10m")

	# compute_move_target
	var move_target: Vector3 = EnemyAIScript.compute_move_target(
		EnemyAIScript.State.SEEK, Vector3.ZERO, Vector3(10, 0, 0), Vector3.INF, Vector3.ZERO
	)
	_expect(move_target == Vector3(10, 0, 0), "compute_move_target: SEEK → player_pos")


# ---------------------------------------------------------------------------
# 5. Enemy node: take_damage, state injection, death
# ---------------------------------------------------------------------------
func _test_enemy_node() -> void:
	print("\n--- enemy node ---")

	var EnemyScript: Script = load("res://scripts/enemy.gd")
	_expect(EnemyScript != null, "load Enemy script")
	if EnemyScript == null:
		return

	# Create an enemy instance (CharacterBody3D).
	var enemy: Node = EnemyScript.new()
	_expect(enemy != null, "instantiate Enemy")
	if enemy == null:
		return

	# Add to scene tree so group operations work.
	root.add_child(enemy)

	# In headless -s mode, _ready() may not fire on add_child. Call it
	# manually if the group wasn't added.
	if not enemy.is_in_group("enemy"):
		enemy.call("_ready")

	# Verify it joined the "enemy" group.
	_expect(enemy.is_in_group("enemy"), "enemy added to 'enemy' group")

	# Verify initial health.
	_expect(float(enemy.get("health")) == 100.0, "enemy initial health == 100")

	# Take damage.
	var dmg: float = enemy.call("take_damage", 30.0)
	_expect(dmg == 30.0, "take_damage returns 30")
	_expect(float(enemy.get("health")) == 70.0, "health == 70 after 30 damage")

	# State injection.
	enemy.call("set_state", 2)  # FLANK
	_expect(enemy.call("get_state") == 2, "get_state == 2 (FLANK)")
	_expect(enemy.call("get_state_name") == "FLANK", "get_state_name == FLANK")

	# Health fraction.
	_expect(enemy.call("health_fraction") == 0.7, "health_fraction == 0.7")

	# is_dead.
	_expect(enemy.call("is_dead") == false, "is_dead == false")

	# Kill the enemy.
	enemy.call("take_damage", 70.0)
	_expect(float(enemy.get("health")) == 0.0, "health == 0 after lethal damage")
	_expect(enemy.call("is_dead") == true, "is_dead == true after lethal damage")

	# The enemy should be freed (queue_free was called). Wait a frame.
	await create_timer(0.1).timeout
	_expect(not is_instance_valid(enemy), "enemy freed after death")

	# Test take_damage on a dead enemy returns 0.
	var enemy2: Node = EnemyScript.new()
	root.add_child(enemy2)
	enemy2.call("take_damage", 100.0)
	# Now dead — further damage should return 0.
	var overkill: float = enemy2.call("take_damage", 50.0)
	_expect(overkill == 0.0, "take_damage on dead enemy returns 0")
	enemy2.queue_free()


# ---------------------------------------------------------------------------
# 6. Cover system
# ---------------------------------------------------------------------------
func _test_cover_system() -> void:
	print("\n--- cover system ---")

	var CoverRegistryScript: Script = load("res://scripts/cover_registry.gd")
	_expect(CoverRegistryScript != null, "load CoverRegistry script")

	var CoverPointScript: Script = load("res://scripts/cover_point.gd")
	_expect(CoverPointScript != null, "load CoverPoint script")

	# Create a CoverRegistry.
	var reg: Node = CoverRegistryScript.new()
	_expect(reg != null, "instantiate CoverRegistry")
	if reg == null:
		return
	root.add_child(reg)

	# Verify it has no cover points initially.
	_expect(reg.call("all_cover_points").is_empty(), "CoverRegistry starts empty")

	# is_position_in_cover returns false with no physics world (headless).
	var in_cover: bool = reg.call("is_position_in_cover", Vector3.ZERO, Vector3(10, 0, 0))
	_expect(in_cover == false, "is_position_in_cover: false in headless (no world)")

	# is_near_cover_point returns false with no points.
	_expect(reg.call("is_near_cover_point", Vector3.ZERO) == false, "is_near_cover_point: false with no points")

	# get_nearest_cover returns null with no points.
	_expect(reg.call("get_nearest_cover", Vector3.ZERO) == null, "get_nearest_cover: null with no points")

	# Create a CoverPoint and register it.
	var cp: Node = CoverPointScript.new()
	_expect(cp != null, "instantiate CoverPoint")
	if cp == null:
		return
	root.add_child(cp)
	cp.position = Vector3(5, 0, 0)

	# Register it (normally done in _ready, but headless may not fire _ready).
	reg.call("register_cover", cp)
	_expect(reg.call("all_cover_points").size() == 1, "CoverRegistry has 1 point after register")

	# get_nearest_cover should find it.
	var nearest: Node = reg.call("get_nearest_cover", Vector3.ZERO)
	_expect(nearest == cp, "get_nearest_cover returns the registered point")

	# is_near_cover_point should be true near the point.
	_expect(reg.call("is_near_cover_point", Vector3(5, 0, 0)) == true, "is_near_cover_point: true at point position")
	_expect(reg.call("is_near_cover_point", Vector3(100, 0, 0)) == false, "is_near_cover_point: false far away")

	# cover_point_at should find it.
	var at_cover: Node = reg.call("cover_point_at", Vector3(5, 0, 0))
	_expect(at_cover == cp, "cover_point_at: finds the point")

	# Unregister.
	reg.call("unregister_cover", cp)
	_expect(reg.call("all_cover_points").is_empty(), "CoverRegistry empty after unregister")

	# Cleanup.
	cp.queue_free()
	reg.queue_free()


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
func _report() -> void:
	print("\n=== combat system smoke test ===")
	print("  passes: %d" % _passes)
	print("  failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("  FAILED:")
		for f in _failures:
			print("    - %s" % f)
		print("\nRESULT: FAIL")
	else:
		print("\nRESULT: PASS")
	quit()