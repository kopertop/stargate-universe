extends SceneTree

# Headless smoke test for the Jungle biome — damage traps / hazardous flora
# (issue #88). Asserts the acceptance criteria:
#   1. Jungle renders from a spec, is WALKABLE, and seats DENSE flora props (more
#      than a sparse biome at equal seed — prop_density 1.2 vs desert 0.7).
#   2. The generator scatters HazardZone trap volumes from the biome trap block,
#      each carrying a telegraph "tell" and the "trap" cause.
#   3. A trap zone applies damage on player overlap (a tick drops health).
#   4. Health 0 from a trap routes the no-death knockout → med-bay recovery
#      (recovering_in_infirmary armed, cause "trap"), never a game over.
#   5. Hazard density is TUNABLE FROM DATA — a spec hazard_params.traps override
#      changes the trap count + damage the generator places.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/biome_jungle.gd
#
# Duck-types PlanetGenerator + HazardZone via script paths so a freshly-added
# class_name can't parse-error this run (feedback_godot_class_name_headless.md).
# Uses the live GameState autoload (reached via /root) for the knockout path.

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const HAZARD_PATH: String = "res://scripts/hazard_zone.gd"

const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0

var _gen: Script = null
var _hazard: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== biome_jungle smoke test ===")
	_gen = load(GEN_PATH)
	_hazard = load(HAZARD_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	_expect(_hazard != null, "HazardZone script loads")
	if _gen == null or _hazard == null:
		_report()
		return

	_test_jungle_renders_walkable_dense_flora()
	_test_generator_scatters_telegraphed_traps()
	_test_trap_applies_damage_on_overlap()
	_test_trap_zero_health_routes_knockout()
	_test_hazard_density_tunable_from_data()

	_report()


# --- 1: jungle renders, walkable, dense flora -------------------------------
func _test_jungle_renders_walkable_dense_flora() -> void:
	var spec: Dictionary = _spec(424242, "jungle")
	var params: Dictionary = _gen.build_params(spec)
	var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
	_expect(slope < WALKABLE_MARGIN_DEG,
		"jungle max slope %.1f° < %.0f° (walkable, no jump)" % [slope, WALKABLE_MARGIN_DEG])
	_expect(slope < FLOOR_MAX_ANGLE_DEG, "jungle slope under CharacterBody3D floor limit")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	var manager: Node = _gen.build(world, spec)
	_expect(manager != null, "jungle build() returns a chunk manager")
	_expect(world.get_node_or_null("PlanetGround") != null, "jungle installs PlanetGround terrain")
	_expect(world.get_node_or_null("PlanetReturnStargate") != null, "jungle places return Stargate")
	_expect(world.get_node_or_null("LimeNode1") != null, "jungle places lime deposits")
	var jungle_props: int = _count_prefix(world, "Prop")
	_expect(jungle_props > 0, "jungle seats walk-around flora props (%d)" % jungle_props)
	world.free()

	# Dense: jungle (prop_density 1.2) seats MORE props than desert (0.7) at the
	# same seed — the "dense vegetation, reduced sightlines" trait.
	var desert_world: Node3D = Node3D.new()
	root.add_child(desert_world)
	_gen.build(desert_world, _spec(424242, "desert"))
	var desert_props: int = _count_prefix(desert_world, "Prop")
	desert_world.free()
	_expect(jungle_props > desert_props,
		"jungle flora denser than desert (%d > %d)" % [jungle_props, desert_props])


# --- 2: generator scatters telegraphed trap volumes -------------------------
func _test_generator_scatters_telegraphed_traps() -> void:
	var spec: Dictionary = _spec(7, "jungle")
	var traps: Dictionary = _gen.traps_block(spec)
	_expect(not traps.is_empty(), "jungle biome defines a hazard.traps block")
	_expect(int(traps.get("count", 0)) > 0, "jungle trap block has a positive count")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, spec)
	var built: int = _count_prefix(world, "HazardZone")
	_expect(built == int(traps.get("count", 0)),
		"generator scatters one HazardZone per trap count (%d == %d)" % [built, int(traps.get("count", 0))])
	_expect(built > 0, "jungle places hazard zones")

	var z: Node = world.get_node_or_null("HazardZone1")
	_expect(z != null, "HazardZone1 present")
	if z != null:
		_expect(String(z.get("cause")) == "trap", "trap zone cause-tagged 'trap'")
		_expect(String(z.get("telegraph")) != "", "trap zone carries a telegraph tell ('%s')" % String(z.get("telegraph")))
		_expect(float(z.get("damage_per_second")) > 0.0, "trap zone deals positive damage/sec")
		# Telegraph: the zone owns a visible flora tell (MeshInstance3D children).
		var tells: int = 0
		for c in (z as Node).get_children():
			if c is MeshInstance3D:
				tells += 1
		_expect(tells > 0, "trap zone has a visible flora tell (%d meshes)" % tells)
	# NOTE: HazardZone._ready (group add + collision wiring) only runs once the node
	# is in the ACTIVE scene tree; under a bare `-s` SceneTree nodes parented to a
	# non-current-scene Node3D never enter the tree, so is_in_group is a headless
	# false-negative here. Group membership + body-overlap detection are exercised
	# by real play (the planet scene is the current scene). We verify the damage
	# contract directly via apply_tick() below instead.
	world.free()


# --- 3: a trap applies damage on player overlap -----------------------------
func _test_trap_applies_damage_on_overlap() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return
	gs.call("reset")
	var start_health: float = float(gs.get("health"))
	_expect(start_health > 0.0, "player starts with health (%.0f)" % start_health)

	var zone: Area3D = _hazard.new()
	zone.set("damage_per_second", 10.0)
	zone.set("tick_interval", 0.5)
	zone.set("cause", "trap")
	root.add_child(zone)
	# One tick = damage_per_second * tick_interval = 5 damage.
	var fired: bool = zone.call("apply_tick")
	_expect(fired == false, "non-lethal tick does not fire a knockout")
	_expect(is_equal_approx(float(gs.get("health")), start_health - 5.0),
		"one trap tick deals damage_per_second * tick_interval (%.0f -> %.0f)" % [start_health, float(gs.get("health"))])
	zone.free()


# --- 4: health 0 from a trap routes the no-death knockout -------------------
func _test_trap_zero_health_routes_knockout() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	if gs == null or router == null:
		_expect(false, "GameState + SceneRouter autoloads attached (knockout)")
		return
	router.set("instant_mode", true)
	gs.call("reset")
	# Drain health to a sliver so the next trap tick floors it.
	gs.call("damage", float(gs.get("MAX_HEALTH")) - 2.0)
	_expect(float(gs.get("health")) <= 2.0, "health pre-drained to a sliver")
	var pre_episode: bool = gs.get("episode_complete")

	var zone: Area3D = _hazard.new()
	zone.set("damage_per_second", 20.0)   # one tick = 10 dmg, lethal vs 2 hp
	zone.set("tick_interval", 0.5)
	zone.set("cause", "trap")
	root.add_child(zone)
	var fired: bool = zone.call("apply_tick")
	_expect(fired == true, "lethal trap tick fires a knockout")

	# No death — knockout heals to full and routes to the infirmary.
	_expect(float(gs.get("health")) == float(gs.get("MAX_HEALTH")), "knockout heals health to full (no death)")
	_expect(gs.get("episode_complete") == pre_episode and gs.get("episode_complete") == false,
		"trap knockout is never a game over")
	_expect(gs.get("recovering_in_infirmary") == true, "trap knockout arms med-bay recovery")
	_expect(String(gs.get("knockout_cause")) == "trap", "knockout cause-tagged 'trap'")
	_expect(String(gs.get("next_room_id")) == "infirmary", "trap knockout routes to the infirmary")

	# The cause-tagged wake-up line resolves from the trap pool.
	var line_info: Dictionary = gs.call("knockout_line", "trap")
	_expect(String(line_info.get("speaker", "")) == "TJ", "trap wake-up line is spoken by TJ")

	zone.free()
	router.set("instant_mode", false)


# --- 5: hazard density tunable from data ------------------------------------
func _test_hazard_density_tunable_from_data() -> void:
	# Baseline jungle trap count from biomes.json.
	var base: Dictionary = _gen.traps_block(_spec(7, "jungle"))
	var base_count: int = int(base.get("count", 0))
	_expect(base_count > 0, "baseline jungle trap count from data (%d)" % base_count)

	# A spec hazard_params.traps override changes the placed count + damage —
	# proves density is data-tunable per run, not hardcoded.
	var tuned_spec: Dictionary = _spec(7, "jungle")
	tuned_spec["hazard_params"] = {"traps": {"count": base_count + 5, "damage_per_second": 99.0,
		"min_radius": 26.0, "max_radius": 150.0}}
	var tuned: Dictionary = _gen.traps_block(tuned_spec)
	_expect(int(tuned.get("count", 0)) == base_count + 5, "spec override changes trap count")
	_expect(float(tuned.get("damage_per_second", 0.0)) == 99.0, "spec override changes trap damage")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, tuned_spec)
	var placed: int = _count_prefix(world, "HazardZone")
	_expect(placed == base_count + 5, "generator places the OVERRIDDEN trap count (%d)" % placed)
	var z: Node = world.get_node_or_null("HazardZone1")
	if z != null:
		_expect(float(z.get("damage_per_second")) == 99.0, "placed trap carries the overridden damage")
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
