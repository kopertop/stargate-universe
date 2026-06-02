extends SceneTree

# Headless smoke test for the Alien-tech biome — security sensors / alarms you
# must AVOID (issue #91). Asserts the acceptance criteria:
#   1. Alien-tech renders from a spec, is WALKABLE, and seats props (the
#      tech-ruin "structures" set).
#   2. The generator scatters SensorZone trip-beam volumes from the biome sensors
#      block, each TELEGRAPHED (a visible beam/strip tell) + cause-tagged.
#   3. Entering a sensor RAISES an alarm (trip()) — once, persistent, idempotent.
#   4. While the alarm is up, the defense damages on a tick AND ESCALATES (each
#      tick hits harder — security locking down).
#   5. An escalating tick that floors health routes the no-death knockout ->
#      med-bay recovery (recovering_in_infirmary armed, cause "alien_defense"),
#      never a game over.
#   6. Reaching a goal WITHOUT crossing a sensor leaves alarm_raised false — the
#      stealth path: avoidance is possible, no alarm = no consequence.
#   7. Hazard density is TUNABLE FROM DATA — a spec hazard_params.sensors override
#      changes the sensor count + damage the generator places.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/biome_alien_tech.gd
#
# Duck-types PlanetGenerator + SensorZone via script paths so a freshly-added
# class_name can't parse-error this run (feedback_godot_class_name_headless.md).
# Uses the live GameState autoload (reached via /root) for the knockout path.

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const SENSOR_PATH: String = "res://scripts/sensor_zone.gd"

const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0

var _gen: Script = null
var _sensor: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== biome_alien_tech smoke test ===")
	_gen = load(GEN_PATH)
	_sensor = load(SENSOR_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	_expect(_sensor != null, "SensorZone script loads")
	if _gen == null or _sensor == null:
		_report()
		return

	_test_alien_tech_renders_walkable()
	_test_generator_scatters_telegraphed_sensors()
	_test_sensor_trip_raises_alarm_idempotent()
	_test_alarm_damage_escalates()
	_test_lethal_tick_routes_knockout()
	_test_no_trip_leaves_alarm_quiet()
	_test_sensor_density_tunable_from_data()

	_report()


# --- 1: alien-tech renders, walkable ----------------------------------------
func _test_alien_tech_renders_walkable() -> void:
	var spec: Dictionary = _spec(424242, "alien_tech")
	var params: Dictionary = _gen.build_params(spec)
	var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
	_expect(slope < WALKABLE_MARGIN_DEG,
		"alien-tech max slope %.1f° < %.0f° (walkable, no jump)" % [slope, WALKABLE_MARGIN_DEG])
	_expect(slope < FLOOR_MAX_ANGLE_DEG, "alien-tech slope under CharacterBody3D floor limit")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	var manager: Node = _gen.build(world, spec)
	_expect(manager != null, "alien-tech build() returns a chunk manager")
	_expect(world.get_node_or_null("PlanetGround") != null, "alien-tech installs PlanetGround terrain")
	_expect(world.get_node_or_null("PlanetReturnStargate") != null, "alien-tech places return Stargate")
	var props: int = _count_prefix(world, "Prop")
	_expect(props > 0, "alien-tech seats walk-around props (%d)" % props)
	world.free()


# --- 2: generator scatters telegraphed sensor volumes -----------------------
func _test_generator_scatters_telegraphed_sensors() -> void:
	var spec: Dictionary = _spec(7, "alien_tech")
	var sensors: Dictionary = _gen.sensors_block(spec)
	_expect(not sensors.is_empty(), "alien-tech biome defines a hazard.sensors block")
	_expect(int(sensors.get("count", 0)) > 0, "alien-tech sensors block has a positive count")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, spec)
	var built: int = _count_prefix(world, "SensorZone")
	_expect(built == int(sensors.get("count", 0)),
		"generator scatters one SensorZone per sensor count (%d == %d)" % [built, int(sensors.get("count", 0))])
	_expect(built > 0, "alien-tech places sensor zones")

	# Non-alien-tech biomes scatter NO sensors (block-gated).
	var desert_world: Node3D = Node3D.new()
	root.add_child(desert_world)
	_gen.build(desert_world, _spec(7, "desert"))
	_expect(_count_prefix(desert_world, "SensorZone") == 0, "desert places no sensors (block-gated)")
	desert_world.free()

	var z: Node = world.get_node_or_null("SensorZone1")
	_expect(z != null, "SensorZone1 present")
	if z != null:
		_expect(String(z.get("cause")) == "alien_defense", "sensor cause-tagged 'alien_defense'")
		_expect(String(z.get("telegraph")) != "", "sensor carries a telegraph tell ('%s')" % String(z.get("telegraph")))
		_expect(float(z.get("base_damage_per_second")) > 0.0, "sensor has positive base damage/sec")
		_expect(z.get("alarm_raised") == false, "a freshly-built sensor starts with its alarm DOWN")
		# Telegraph: the zone owns a visible beam/strip tell (MeshInstance3D children).
		var tells: int = 0
		for c in (z as Node).get_children():
			if c is MeshInstance3D:
				tells += 1
		_expect(tells > 0, "sensor has a visible beam/strip tell (%d meshes)" % tells)
	world.free()


# --- 3: tripping a sensor raises the alarm (once, idempotent) ----------------
func _test_sensor_trip_raises_alarm_idempotent() -> void:
	var zone: Area3D = _sensor.new()
	zone.set("cause", "alien_defense")
	root.add_child(zone)
	_expect(zone.get("alarm_raised") == false, "untripped sensor alarm is down")
	var first: bool = zone.call("trip")
	_expect(first == true, "first crossing raises the alarm")
	_expect(zone.get("alarm_raised") == true, "alarm state is set after tripping")
	var second: bool = zone.call("trip")
	_expect(second == false, "re-crossing does NOT re-raise (idempotent — security already noticed)")
	_expect(zone.get("alarm_raised") == true, "alarm stays up after re-entry")
	zone.free()


# --- 4: alarm damage escalates while it stays up ----------------------------
func _test_alarm_damage_escalates() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return
	gs.call("reset")
	var start_health: float = float(gs.get("health"))
	_expect(start_health > 0.0, "player starts with health (%.0f)" % start_health)

	var zone: Area3D = _sensor.new()
	zone.set("base_damage_per_second", 10.0)
	zone.set("escalation", 2.0)
	zone.set("max_damage_per_second", 1000.0)
	zone.set("tick_interval", 0.5)
	zone.set("cause", "alien_defense")
	root.add_child(zone)

	# Untripped: a tick is a no-op (the sensor is harmless if never crossed).
	var noop: bool = zone.call("apply_tick")
	_expect(noop == false, "an untripped sensor tick is a harmless no-op")
	_expect(is_equal_approx(float(gs.get("health")), start_health), "no damage from an untripped sensor")

	zone.call("trip")
	# Tick 1: base 10 dps * 0.5 = 5 damage.
	var h0: float = float(gs.get("health"))
	zone.call("apply_tick")
	var dmg1: float = h0 - float(gs.get("health"))
	_expect(is_equal_approx(dmg1, 5.0), "first armed tick deals base damage (%.1f)" % dmg1)
	# Tick 2: escalated 10*2 = 20 dps * 0.5 = 10 damage > tick 1.
	var h1: float = float(gs.get("health"))
	zone.call("apply_tick")
	var dmg2: float = h1 - float(gs.get("health"))
	_expect(is_equal_approx(dmg2, 10.0), "second armed tick ESCALATES (%.1f > %.1f)" % [dmg2, dmg1])
	_expect(dmg2 > dmg1, "alarm damage escalates tick over tick (security locking down)")
	zone.free()


# --- 5: a flooring escalating tick routes the no-death knockout --------------
func _test_lethal_tick_routes_knockout() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	if gs == null or router == null:
		_expect(false, "GameState + SceneRouter autoloads attached (knockout)")
		return
	router.set("instant_mode", true)
	gs.call("reset")
	gs.call("damage", float(gs.get("MAX_HEALTH")) - 2.0)
	_expect(float(gs.get("health")) <= 2.0, "health pre-drained to a sliver")
	var pre_episode: bool = gs.get("episode_complete")

	var zone: Area3D = _sensor.new()
	zone.set("base_damage_per_second", 20.0)   # one tick = 10 dmg, lethal vs 2 hp
	zone.set("tick_interval", 0.5)
	zone.set("cause", "alien_defense")
	root.add_child(zone)
	zone.call("trip")
	var fired: bool = zone.call("apply_tick")
	_expect(fired == true, "lethal alarm tick fires a knockout")

	# No death — knockout heals to full and routes to the infirmary.
	_expect(float(gs.get("health")) == float(gs.get("MAX_HEALTH")), "knockout heals health to full (no death)")
	_expect(gs.get("episode_complete") == pre_episode and gs.get("episode_complete") == false,
		"alarm knockout is never a game over")
	_expect(gs.get("recovering_in_infirmary") == true, "alarm knockout arms med-bay recovery")
	_expect(String(gs.get("knockout_cause")) == "alien_defense", "knockout cause-tagged 'alien_defense'")
	_expect(String(gs.get("next_room_id")) == "infirmary", "alarm knockout routes to the infirmary")
	# The downed sensor goes quiet after the run ends.
	_expect(zone.get("alarm_raised") == false, "sensor alarm clears after the knockout run ends")

	# The cause-tagged wake-up line resolves from the alien_defense pool.
	var line_info: Dictionary = gs.call("knockout_line", "alien_defense")
	_expect(String(line_info.get("speaker", "")) == "TJ", "alarm wake-up line is spoken by TJ")
	_expect(String(line_info.get("line", "")) != "", "alarm wake-up line resolves (non-empty)")

	zone.free()
	router.set("instant_mode", false)


# --- 6: reaching the goal without tripping leaves the alarm quiet ------------
func _test_no_trip_leaves_alarm_quiet() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		_expect(false, "GameState autoload attached (no-trip path)")
		return
	gs.call("reset")
	var start_health: float = float(gs.get("health"))

	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, _spec(99, "alien_tech"))
	# Player routes AROUND every sensor: no trip() ever called. Pump several ticks.
	var any_raised: bool = false
	for c in world.get_children():
		if String(c.name).begins_with("SensorZone"):
			c.call("apply_tick")
			c.call("apply_tick")
			if c.get("alarm_raised") == true:
				any_raised = true
	_expect(any_raised == false, "no sensor raised its alarm on a no-trip run")
	_expect(is_equal_approx(float(gs.get("health")), start_health),
		"a no-trip run takes ZERO damage (avoidance is possible)")
	world.free()


# --- 7: sensor density tunable from data -------------------------------------
func _test_sensor_density_tunable_from_data() -> void:
	var base: Dictionary = _gen.sensors_block(_spec(7, "alien_tech"))
	var base_count: int = int(base.get("count", 0))
	_expect(base_count > 0, "baseline alien-tech sensor count from data (%d)" % base_count)

	var tuned_spec: Dictionary = _spec(7, "alien_tech")
	tuned_spec["hazard_params"] = {"sensors": {"count": base_count + 4, "base_damage_per_second": 77.0,
		"min_radius": 24.0, "max_radius": 150.0}}
	var tuned: Dictionary = _gen.sensors_block(tuned_spec)
	_expect(int(tuned.get("count", 0)) == base_count + 4, "spec override changes sensor count")
	_expect(float(tuned.get("base_damage_per_second", 0.0)) == 77.0, "spec override changes sensor damage")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, tuned_spec)
	var placed: int = _count_prefix(world, "SensorZone")
	_expect(placed == base_count + 4, "generator places the OVERRIDDEN sensor count (%d)" % placed)
	var z: Node = world.get_node_or_null("SensorZone1")
	if z != null:
		_expect(float(z.get("base_damage_per_second")) == 77.0, "placed sensor carries the overridden damage")
	world.free()


# --- helpers ----------------------------------------------------------------
func _spec(seed: int, biome: String) -> Dictionary:
	return {
		"seed": seed,
		"biome": biome,
		"resource_table": {"lime_nodes": 4, "lime_per_node": 1,
			"lime_min_radius": 50.0, "lime_max_radius": 120.0},
		"hazard_params": {},
		"name": "Test %s" % biome,
	}


func _count_prefix(world: Node, prefix: String) -> int:
	var n: int = 0
	for c in world.get_children():
		if String(c.name).begins_with(prefix):
			n += 1
	return n


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
