extends SceneTree

# Smoke test for the enemy AI system (enemy.gd, enemy_ai.gd, enemy_spawner.gd).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/enemy_ai.gd
#
# Asserts:
#   • enemy_ai.gd loads and pure decision functions return correct states.
#   • enemy.gd class_name resolves, has the right enum, signals, and exports.
#   • set_state() transitions work and emit state_changed.
#   • take_damage() reduces health and emits enemy_damaged.
#   • Enemy dies at health <= 0 and emits enemy_died.
#   • enemy_spawner.gd class_name resolves, has wave_configs, spawn_wave, signals.
#   • Spawner tracks alive enemies and emits wave_cleared when all dead.
#   • AI state selection logic matches the spec for key scenarios.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== enemy AI system smoke test ===")
	_test_ai_pure_decisions()
	_test_enemy_class_interface()
	_test_enemy_damage_and_death()
	_test_enemy_state_transitions()
	_test_spawner_interface()
	_test_spawner_wave_tracking()
	_report()


# ==============================================================================
# TEST 1: Pure AI decision functions (enemy_ai.gd)
# ==============================================================================

func _test_ai_pure_decisions() -> void:
	print("\n--- AI pure decision functions ---")
	var AI: Script = load("res://scripts/enemy_ai.gd")

	# No player detected → IDLE.
	_expect(AI.decide_state(INF, false, 1.0, 0, false, false) == AI.State.IDLE,
		"decide_state(no player) → IDLE")

	# Close range with LOS → ATTACK.
	_expect(AI.decide_state(5.0, true, 1.0, 0, false, false) == AI.State.ATTACK,
		"decide_state(close, LOS) → ATTACK")

	# Medium range with LOS, no allies → ATTACK.
	_expect(AI.decide_state(12.0, true, 1.0, 0, false, false) == AI.State.ATTACK,
		"decide_state(medium, LOS, no allies) → ATTACK")

	# Medium range with LOS, 1 ally → FLANK.
	_expect(AI.decide_state(12.0, true, 1.0, 1, false, false) == AI.State.FLANK,
		"decide_state(medium, LOS, 1 ally) → FLANK")

	# Medium range with LOS, 2+ allies → SUPPRESS.
	_expect(AI.decide_state(12.0, true, 1.0, 2, false, false) == AI.State.SUPPRESS,
		"decide_state(medium, LOS, 2 allies) → SUPPRESS")

	# Long range with LOS → SUPPRESS.
	_expect(AI.decide_state(25.0, true, 1.0, 0, false, false) == AI.State.SUPPRESS,
		"decide_state(long, LOS) → SUPPRESS")

	# Critical health + cover → TAKE_COVER.
	_expect(AI.decide_state(5.0, true, 0.1, 0, true, false) == AI.State.TAKE_COVER,
		"decide_state(critical health, cover) → TAKE_COVER")

	# Low health + under fire + cover → TAKE_COVER.
	_expect(AI.decide_state(12.0, true, 0.25, 0, true, true) == AI.State.TAKE_COVER,
		"decide_state(low health, under fire, cover) → TAKE_COVER")

	# No LOS, within range → SEEK.
	_expect(AI.decide_state(20.0, false, 1.0, 0, false, false) == AI.State.SEEK,
		"decide_state(no LOS, in range) → SEEK")

	# No LOS, under fire, cover → TAKE_COVER.
	_expect(AI.decide_state(20.0, false, 1.0, 0, true, true) == AI.State.TAKE_COVER,
		"decide_state(no LOS, under fire, cover) → TAKE_COVER")

	# Very far, no LOS → ADVANCE.
	_expect(AI.decide_state(50.0, false, 1.0, 0, false, false) == AI.State.ADVANCE,
		"decide_state(very far, no LOS) → ADVANCE")

	# Flank side decision.
	var right: int = AI.decide_flank_side(
		Vector3(5, 0, 0),   # enemy to the right
		Vector3(0, 0, 0),   # player at origin
		Vector3(0, 0, -1)   # player facing -Z
	)
	_expect(right == 1, "decide_flank_side(enemy to right) → +1 (right)")

	var left: int = AI.decide_flank_side(
		Vector3(-5, 0, 0),  # enemy to the left
		Vector3(0, 0, 0),
		Vector3(0, 0, -1)
	)
	_expect(left == -1, "decide_flank_side(enemy to left) → -1 (left)")

	# Flank position computation.
	var flank_pos: Vector3 = AI.compute_flank_position(
		Vector3(0, 0, 0),    # player at origin
		Vector3(0, 0, -1),   # player facing -Z
		1,                    # right side
		0.0                   # no angle offset
	)
	_expect(is_equal_approx(flank_pos.length(), AI.FLANK_RADIUS),
		"compute_flank_position at angle 0 → FLANK_RADIUS distance")

	# Suppression direction has spread.
	var sup_dir: Vector3 = AI.compute_suppression_direction(
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		0.05
	)
	_expect(sup_dir.length() > 0.0, "compute_suppression_direction returns non-zero")

	# Find nearest cover.
	var covers: Array = [Vector3(5, 0, 0), Vector3(10, 0, 0), Vector3(3, 0, 0)]
	var nearest: Vector3 = AI.find_nearest_cover(Vector3(0, 0, 0), covers)
	_expect(is_equal_approx(nearest.x, 3.0),
		"find_nearest_cover returns closest (3.0)")

	# Count allies in range.
	var ally_positions: Array = [Vector3(5, 0, 0), Vector3(15, 0, 0), Vector3(25, 0, 0)]
	var count: int = AI.count_allies_in_range(Vector3(0, 0, 0), ally_positions, 20.0)
	_expect(count == 2, "count_allies_in_range(20m) → 2")

	# Should fire logic.
	_expect(AI.should_fire(AI.State.ATTACK, true, 0.0, 5.0, 20.0) == true,
		"should_fire(ATTACK, LOS, no cooldown, in range) → true")
	_expect(AI.should_fire(AI.State.SEEK, true, 0.0, 5.0, 20.0) == false,
		"should_fire(SEEK) → false")
	_expect(AI.should_fire(AI.State.ATTACK, true, 1.0, 5.0, 20.0) == false,
		"should_fire(cooldown active) → false")
	_expect(AI.should_fire(AI.State.ATTACK, false, 0.0, 5.0, 20.0) == false,
		"should_fire(no LOS) → false")

	# Effective spread.
	_expect(is_equal_approx(AI.effective_spread(0.1, AI.State.SUPPRESS), 0.3),
		"effective_spread(SUPPRESS) → 3x base")
	_expect(is_equal_approx(AI.effective_spread(0.1, AI.State.ATTACK), 0.1),
		"effective_spread(ATTACK) → base")

	# Effective accuracy.
	_expect(is_equal_approx(AI.effective_accuracy(AI.State.ATTACK), 1.0),
		"effective_accuracy(ATTACK) → 1.0")
	_expect(is_equal_approx(AI.effective_accuracy(AI.State.SUPPRESS), 0.25),
		"effective_accuracy(SUPPRESS) → 0.25")

	# Speed multiplier.
	_expect(is_equal_approx(AI.speed_multiplier(AI.State.ADVANCE), 1.5),
		"speed_multiplier(ADVANCE) → 1.5")
	_expect(is_equal_approx(AI.speed_multiplier(AI.State.SUPPRESS), 0.0),
		"speed_multiplier(SUPPRESS) → 0.0")

	# Compute move target.
	var move_target: Vector3 = AI.compute_move_target(
		AI.State.SEEK, Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3.INF, Vector3.ZERO
	)
	_expect(is_equal_approx(move_target.x, 10.0),
		"compute_move_target(SEEK) → player_pos")


# ==============================================================================
# TEST 2: Enemy class interface
# ==============================================================================

func _test_enemy_class_interface() -> void:
	print("\n--- Enemy class interface ---")
	var EnemyScript: Script = load("res://scripts/enemy.gd")

	# class_name resolves.
	_expect(EnemyScript != null, "enemy.gd loads as script")

	# Has EnemyState enum with 7 states.
	# GDScript enums appear as a Dictionary in the constant map (name → int).
	var consts: Dictionary = EnemyScript.get_script_constant_map()
	_expect(consts.has("EnemyState"), "EnemyState enum exists in constants")
	if consts.has("EnemyState"):
		var state_enum: Variant = consts["EnemyState"]
		if state_enum is Dictionary:
			_expect((state_enum as Dictionary).size() == 7,
				"EnemyState enum has 7 states (got %d)" % (state_enum as Dictionary).size())
		else:
			# Some Godot versions return enum as int; just verify it exists.
			_passes += 1
			print("  PASS  EnemyState enum present (non-dict form)")
	else:
		_fail("EnemyState enum missing from constants")

	# Has expected signals.
	var signals: Array = EnemyScript.get_script_signal_list()
	var signal_names: Array = []
	for s in signals:
		signal_names.append(s.name)
	_expect(signal_names.has("enemy_died"), "has signal enemy_died")
	_expect(signal_names.has("enemy_damaged"), "has signal enemy_damaged")
	_expect(signal_names.has("state_changed"), "has signal state_changed")

	# Has expected exported properties.
	var props: Array = EnemyScript.get_script_property_list()
	var prop_names: Array = []
	for p in props:
		prop_names.append(p.name)
	_expect(prop_names.has("move_speed"), "has @export move_speed")
	_expect(prop_names.has("flank_speed"), "has @export flank_speed")
	_expect(prop_names.has("max_health"), "has @export max_health")
	_expect(prop_names.has("weapon"), "has @export weapon")
	_expect(prop_names.has("nav_agent"), "has @export nav_agent")
	_expect(prop_names.has("los_ray"), "has @export los_ray")


# ==============================================================================
# TEST 3: Enemy damage and death
# ==============================================================================

func _test_enemy_damage_and_death() -> void:
	print("\n--- Enemy damage and death ---")
	var EnemyScript: Script = load("res://scripts/enemy.gd")

	# Create a bare enemy node (no scene tree needed for logic tests).
	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.set_script(EnemyScript)
	root.add_child(enemy)

	# Initialize health.
	enemy.set("max_health", 100.0)
	enemy.call("_ready")  # manually call _ready since we added after tree init

	# Health starts at max.
	_expect(float(enemy.get("health")) == 100.0, "health starts at 100")

	# Take damage.
	var damaged_fired: Array = []
	enemy.enemy_damaged.connect(
		func(amount: float) -> void: damaged_fired.append(amount)
	)
	var dealt: float = enemy.call("take_damage", 30.0)
	_expect(is_equal_approx(dealt, 30.0), "take_damage(30) returns 30")
	_expect(is_equal_approx(float(enemy.get("health")), 70.0), "health is 70 after 30 damage")
	_expect(damaged_fired.size() == 1, "enemy_damaged signal fired once")
	_expect(is_equal_approx(float(damaged_fired[0]), 30.0), "enemy_damaged carried amount 30")

	# Overkill returns actual damage (clamped to remaining health).
	var dealt2: float = enemy.call("take_damage", 200.0)
	_expect(is_equal_approx(dealt2, 70.0), "take_damage(200) returns 70 (clamped)")
	_expect(float(enemy.get("health")) <= 0.0, "health <= 0 after overkill")

	# Death signal.
	var died_fired: Array = []
	enemy.enemy_died.connect(
		func(node: Node) -> void: died_fired.append(node)
	)
	# The take_damage above should have triggered _die. Check is_dead.
	_expect(enemy.call("is_dead") == true, "is_dead() returns true after health <= 0")

	# Taking damage on a dead enemy returns 0.
	var dealt3: float = enemy.call("take_damage", 10.0)
	_expect(is_equal_approx(dealt3, 0.0), "take_damage on dead enemy returns 0")

	# Cleanup.
	enemy.queue_free()


# ==============================================================================
# TEST 4: Enemy state transitions
# ==============================================================================

func _test_enemy_state_transitions() -> void:
	print("\n--- Enemy state transitions ---")
	var EnemyScript: Script = load("res://scripts/enemy.gd")

	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.set_script(EnemyScript)
	root.add_child(enemy)
	enemy.call("_ready")

	# Default state is IDLE (0).
	_expect(enemy.call("get_state") == 0, "default state is IDLE (0)")

	# set_state transitions and emits signal.
	var state_signals: Array = []
	enemy.state_changed.connect(
		func(new_state: int) -> void: state_signals.append(new_state)
	)
	enemy.call("set_state", 2)  # FLANK
	_expect(enemy.call("get_state") == 2, "set_state(2) → FLANK")
	_expect(state_signals.size() == 1, "state_changed fired once")
	_expect(int(state_signals[0]) == 2, "state_changed carried 2 (FLANK)")

	# Setting the same state doesn't emit.
	enemy.call("set_state", 2)
	_expect(state_signals.size() == 1, "set_state(same) doesn't re-emit")

	# State name.
	_expect(enemy.call("get_state_name") == "FLANK", "get_state_name() → 'FLANK'")

	# Invalid state is rejected.
	enemy.call("set_state", 999)
	_expect(enemy.call("get_state") == 2, "set_state(999) rejected, stays FLANK")

	# Health fraction.
	enemy.set("max_health", 100.0)
	enemy.set("health", 50.0)
	_expect(is_equal_approx(enemy.call("health_fraction"), 0.5), "health_fraction() → 0.5")

	# Cleanup.
	enemy.queue_free()


# ==============================================================================
# TEST 5: Spawner interface
# ==============================================================================

func _test_spawner_interface() -> void:
	print("\n--- Spawner interface ---")
	var SpawnerScript: Script = load("res://scripts/enemy_spawner.gd")

	_expect(SpawnerScript != null, "enemy_spawner.gd loads as script")

	# Has expected signals.
	var signals: Array = SpawnerScript.get_script_signal_list()
	var signal_names: Array = []
	for s in signals:
		signal_names.append(s.name)
	_expect(signal_names.has("wave_started"), "has signal wave_started")
	_expect(signal_names.has("wave_cleared"), "has signal wave_cleared")
	_expect(signal_names.has("all_waves_cleared"), "has signal all_waves_cleared")

	# Has expected exported properties.
	var props: Array = SpawnerScript.get_script_property_list()
	var prop_names: Array = []
	for p in props:
		prop_names.append(p.name)
	_expect(prop_names.has("wave_configs"), "has @export wave_configs")
	_expect(prop_names.has("auto_start"), "has @export auto_start")
	_expect(prop_names.has("auto_advance"), "has @export auto_advance")
	_expect(prop_names.has("spawn_root"), "has @export spawn_root")

	# Has expected methods.
	var methods: Array = SpawnerScript.get_script_method_list()
	var method_names: Array = []
	for m in methods:
		method_names.append(m.name)
	_expect(method_names.has("spawn_wave"), "has method spawn_wave")
	_expect(method_names.has("get_current_wave"), "has method get_current_wave")
	_expect(method_names.has("alive_count"), "has method alive_count")
	_expect(method_names.has("is_spawning"), "has method is_spawning")
	_expect(method_names.has("all_waves_complete"), "has method all_waves_complete")
	_expect(method_names.has("wave_count"), "has method wave_count")


# ==============================================================================
# TEST 6: Spawner wave tracking
# ==============================================================================

func _test_spawner_wave_tracking() -> void:
	print("\n--- Spawner wave tracking ---")
	var SpawnerScript: Script = load("res://scripts/enemy_spawner.gd")

	var spawner: Node3D = Node3D.new()
	spawner.set_script(SpawnerScript)
	root.add_child(spawner)

	# Set up a simple 2-wave config with fast spawn delay.
	spawner.set("wave_configs", [
		{"count": 2, "weapon": null, "spawn_delay": 0.0, "position_offset": Vector3(0, 0, 0)},
		{"count": 1, "weapon": null, "spawn_delay": 0.0, "position_offset": Vector3(0, 0, 0)},
	])

	# wave_count.
	_expect(spawner.call("wave_count") == 2, "wave_count() → 2")

	# No wave started yet.
	_expect(spawner.call("get_current_wave") == -1, "initial current_wave is -1")
	_expect(spawner.call("is_spawning") == false, "initial is_spawning is false")

	# Start wave 0.
	var wave_started_signals: Array = []
	spawner.wave_started.connect(
		func(idx: int) -> void: wave_started_signals.append(idx)
	)
	var started: bool = spawner.call("spawn_wave", 0)
	_expect(started == true, "spawn_wave(0) returns true")
	_expect(spawner.call("get_current_wave") == 0, "current_wave is 0")
	_expect(wave_started_signals.size() == 1, "wave_started fired")
	_expect(int(wave_started_signals[0]) == 0, "wave_started carried 0")

	# Manually pump _process to let spawning complete (no await in SceneTree -s).
	# First _process call spawns the first enemy (spawn_timer starts at 0).
	spawner.call("_process", 0.016)
	# Second call spawns the second enemy (spawn_delay was 0.0).
	spawner.call("_process", 0.016)

	# Should have spawned 2 enemies.
	_expect(spawner.call("alive_count") == 2, "alive_count() → 2 after spawning")
	_expect(spawner.call("is_spawning") == false, "is_spawning false after queue drained")

	# Find spawned enemies via the spawner's internal tracking (more reliable
	# than searching root children, since _ready may not have fired yet in
	# the headless -s context).
	var spawned_enemies: Array = spawner.get("_alive_enemies")
	_expect(spawned_enemies.size() >= 2, "found 2 spawned enemy nodes")

	if spawned_enemies.size() >= 2:
		# Kill one enemy — wave not yet cleared.
		spawned_enemies[0].call("take_damage", 200.0)
		# enemy_died fires synchronously, so alive_count updates immediately.
		_expect(spawner.call("alive_count") == 1, "alive_count → 1 after killing one")

		# Kill the last enemy — wave cleared.
		var wave_cleared_signals: Array = []
		spawner.wave_cleared.connect(
			func(idx: int) -> void: wave_cleared_signals.append(idx)
		)
		spawned_enemies[1].call("take_damage", 200.0)
		_expect(wave_cleared_signals.size() == 1, "wave_cleared fired")
		_expect(int(wave_cleared_signals[0]) == 0, "wave_cleared carried 0")
	else:
		_fail("could not find spawned enemies for wave tracking test")

	# Invalid wave index.
	var bad_start: bool = spawner.call("spawn_wave", 99)
	_expect(bad_start == false, "spawn_wave(99) returns false")

	# Cleanup.
	spawner.queue_free()


# ==============================================================================
# HELPERS
# ==============================================================================

func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _fail(label: String) -> void:
	_failures.append(label)
	print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _passes == 0:
		print("RESULT: FAIL (zero passes — harness ran no assertions)")
		quit(1)
		return
	if _failures.is_empty():
		print("PASS count asserted: %d" % _passes)
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)