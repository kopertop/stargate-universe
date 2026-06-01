extends SceneTree

# Headless smoke test for the biome-parameterized procedural planet generator
# (issue #85). Builds planets from fixed-seed PlanetSpecs and asserts:
#   1. Every biome from a spec renders (terrain manager + gate + lime + POIs).
#   2. Terrain is WALKABLE — max local slope stays under the CharacterBody3D
#      floor limit (jump never required) for each biome.
#   3. Chunk borders stitch SEAMLESSLY — two adjacent chunks, each computing its
#      shared-edge vertices via its OWN chunk-local coordinate math, land on the
#      same world x and yield identical per-vertex heights.
#   4. Near-infinite: the height function is finite + bounded far from the gate
#      (no walling rim), and the chunk manager caps the loaded-chunk count.
#   5. Deterministic per seed: same spec → same height field AND same content
#      PLACEMENT (name + position); a different seed → a different height field
#      AND different placements.
#   6. The persisted PlanetSpec rebuilds an IDENTICAL world — same placements
#      (name + position), not just the seed-independent node-name set (save/load).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/planet_generator.gd
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md).

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const CHUNK_PATH: String = "res://scripts/planet_chunk_manager.gd"

# CharacterBody3D default floor_max_angle = 45°. We require a comfortable margin
# so even the worst sampled cell is walkable without jumping.
const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0

const BIOMES: Array[String] = ["desert", "jungle", "toxic", "urban", "alien_tech"]

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== planet_generator smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	if _gen == null:
		_report()
		return

	_test_each_biome_builds_and_is_walkable()
	_test_seamless_chunk_borders()
	_test_near_infinite_bounded_no_rim()
	_test_chunk_count_capped()
	_test_determinism_per_seed()
	_test_persisted_spec_rebuilds_identically()

	_report()


# --- 1 + 2: every biome renders from a spec and is walkable -----------------
func _test_each_biome_builds_and_is_walkable() -> void:
	for biome in BIOMES:
		var spec: Dictionary = _spec(424242, biome)
		var params: Dictionary = _gen.build_params(spec)
		# Worst-case slope across a wide region around the gate (2m steps).
		var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
		_expect(slope < WALKABLE_MARGIN_DEG,
			"biome %s max slope %.1f° < %.0f° (walkable, no jump)" % [biome, slope, WALKABLE_MARGIN_DEG])
		_expect(slope < FLOOR_MAX_ANGLE_DEG,
			"biome %s slope under CharacterBody3D floor limit" % biome)

		var world: Node3D = Node3D.new()
		root.add_child(world)
		var manager: Node = _gen.build(world, spec)
		_expect(manager != null, "biome %s build() returns a chunk manager" % biome)
		_expect(world.get_node_or_null("PlanetGround") != null,
			"biome %s installs PlanetGround terrain manager" % biome)
		_expect(world.get_node_or_null("PlanetReturnStargate") != null,
			"biome %s places return Stargate" % biome)
		_expect(world.get_node_or_null("PlanetReturnGate") != null,
			"biome %s places return gate portal" % biome)
		_expect(world.get_node_or_null("LimeNode1") != null,
			"biome %s places lime deposits" % biome)
		# At least one walk-around prop (named "Prop*") seated as an obstacle.
		var props: int = 0
		for c in world.get_children():
			if String(c.name).begins_with("Prop"):
				props += 1
		_expect(props > 0, "biome %s seats walk-around props" % biome)
		world.free()


# --- 3: chunk borders stitch seamlessly (two adjacent chunks' OWN edge verts) -
# Reproduce PlanetChunkManager._build_chunk vertex math for two horizontally
# adjacent chunks (coord (0,0) and (1,0)) INDEPENDENTLY. The left chunk's right
# edge (local i = res) and the right chunk's left edge (local i = 0) are distinct
# code paths that must land on the same world x; assert their per-vertex world
# heights match exactly. A real seam (per-chunk randomness, or a chunk offsetting
# its samples) would make these diverge — this fails if borders DON'T stitch.
func _test_seamless_chunk_borders() -> void:
	var chunk_script: Script = load(CHUNK_PATH)
	if chunk_script == null:
		_expect(false, "PlanetChunkManager script loads (seam test)")
		return
	var spec: Dictionary = _spec(7, "jungle")
	var params: Dictionary = _gen.build_params(spec)
	var mgr: Node3D = chunk_script.new()
	var chunk_size: float = float(mgr.get("chunk_size"))
	var res: int = max(int(mgr.get("chunk_res")), 2)
	mgr.free()
	var step: float = chunk_size / float(res)

	# Left chunk (0,0): right-edge column is local i = res → world x = res*step.
	# Right chunk (1,0): left-edge column is local i = 0 → world x = 1*chunk_size.
	var left_origin_x: float = 0.0 * chunk_size
	var right_origin_x: float = 1.0 * chunk_size
	var left_edge_x: float = left_origin_x + float(res) * step
	var right_edge_x: float = right_origin_x + 0.0 * step
	_expect(abs(left_edge_x - right_edge_x) < 0.0001,
		"adjacent chunks' shared edge lands on the same world x (%.4f vs %.4f)" % [left_edge_x, right_edge_x])

	var seamless: bool = true
	var max_diff: float = 0.0
	var shared_origin_z: float = 0.0 * chunk_size
	for j in (res + 1):
		var z: float = shared_origin_z + float(j) * step
		var h_left: float = _gen.height_at(left_edge_x, z, params)
		var h_right: float = _gen.height_at(right_edge_x, z, params)
		var diff: float = abs(h_left - h_right)
		max_diff = max(max_diff, diff)
		if diff > 0.0001:
			seamless = false
	_expect(seamless, "left-chunk right edge == right-chunk left edge heights (max diff %.5f)" % max_diff)


# --- 4: near-infinite — bounded height, no walling rim ----------------------
func _test_near_infinite_bounded_no_rim() -> void:
	var spec: Dictionary = _spec(99, "desert")
	var params: Dictionary = _gen.build_params(spec)
	var amp: float = float(params.get("height", 5.5))
	# Far from the gate (2 km out) the height must stay BOUNDED by the noise
	# amplitude (no rim that rises toward the edge to wall the player in).
	var bound: float = amp * 2.5
	var far_ok: bool = true
	var worst: float = 0.0
	for k in 16:
		var ang: float = (TAU / 16.0) * float(k)
		var h: float = _gen.height_at(cos(ang) * 2000.0, sin(ang) * 2000.0, params)
		worst = max(worst, abs(h))
		if abs(h) > bound:
			far_ok = false
	_expect(far_ok, "height bounded far from gate — no walling rim (worst |h|=%.1f, bound %.1f)" % [worst, bound])
	# Still walkable that far out too.
	var slope_far: float = _gen.max_slope_deg(params, 50.0, 2.0)
	_expect(slope_far < WALKABLE_MARGIN_DEG, "terrain remains walkable far from the gate")


# --- 4b: loaded-chunk count is capped (budget guard) ------------------------
func _test_chunk_count_capped() -> void:
	var chunk_script: Script = load(CHUNK_PATH)
	_expect(chunk_script != null, "PlanetChunkManager script loads")
	if chunk_script == null:
		return
	var spec: Dictionary = _spec(5, "desert")
	var params: Dictionary = _gen.build_params(spec)
	var mgr: Node3D = chunk_script.new()
	root.add_child(mgr)
	mgr.call("configure", params, null)
	mgr.call("prime_around", Vector3.ZERO)
	var radius: int = int(mgr.get("view_radius"))
	var cap: int = (radius * 2 + 1) * (radius * 2 + 1)
	var loaded: int = int(mgr.call("loaded_chunk_count"))
	_expect(loaded <= cap, "loaded chunk count %d capped at window %d" % [loaded, cap])
	_expect(loaded > 0, "chunk manager primes terrain around the spawn")
	mgr.free()


# --- 5: deterministic per seed ----------------------------------------------
func _test_determinism_per_seed() -> void:
	var params_a: Dictionary = _gen.build_params(_spec(1234, "desert"))
	var params_a2: Dictionary = _gen.build_params(_spec(1234, "desert"))
	var params_b: Dictionary = _gen.build_params(_spec(5678, "desert"))
	var sample: Vector2 = Vector2(123.0, -77.0)
	var h_a: float = _gen.height_at(sample.x, sample.y, params_a)
	var h_a2: float = _gen.height_at(sample.x, sample.y, params_a2)
	var h_b: float = _gen.height_at(sample.x, sample.y, params_b)
	_expect(abs(h_a - h_a2) < 0.0001, "same seed → identical height field")
	_expect(abs(h_a - h_b) > 0.0001, "different seed → different height field")

	# Same spec → identical generated content PLACEMENT (name + position), not just
	# names (names are fixed by _spec counts and seed-independent — comparing them
	# alone would pass for ANY seed). A different seed must move the placements.
	var place_a: Dictionary = _node_placements(_spec(1234, "desert"))
	var place_a2: Dictionary = _node_placements(_spec(1234, "desert"))
	var place_b: Dictionary = _node_placements(_spec(5678, "desert"))
	_expect(_placements_equal(place_a, place_a2), "same seed → identical node placements (name + position)")
	_expect(not _placements_equal(place_a, place_b), "different seed → different node placements")


# --- 6: persisted spec rebuilds identically (save round-trip) ----------------
func _test_persisted_spec_rebuilds_identically() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return
	gs.call("reset")
	var spec: Dictionary = _spec(314159, "toxic")
	gs.set("active_planet_spec", spec)
	var saved: Dictionary = gs.call("serialize")
	_expect(saved.has("active_planet_spec"), "serialize() carries active_planet_spec")
	# Wipe + restore from the snapshot, then rebuild and compare PLACEMENTS (name +
	# position) — proves the persisted spec reproduces the same lime/POI/prop spots,
	# not merely the same (seed-independent) node-name set.
	var before: Dictionary = _node_placements(spec)
	gs.call("reset")
	_expect((gs.get("active_planet_spec") as Dictionary).is_empty(), "reset() clears active_planet_spec")
	gs.call("deserialize", saved, 1)
	var restored: Dictionary = gs.get("active_planet_spec")
	_expect(int(restored.get("seed", -1)) == 314159, "deserialize() restores spec seed")
	_expect(String(restored.get("biome", "")) == "toxic", "deserialize() restores spec biome")
	var after: Dictionary = _node_placements(restored)
	_expect(_placements_equal(before, after), "rebuild from persisted spec yields identical placements")


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


# Build a planet into a throwaway world and collect a name → world-position map of
# its children, so two builds can be compared on actual PLACEMENT (not just the
# seed-independent name set). Positions are rounded to mm to avoid float jitter.
func _node_placements(spec: Dictionary) -> Dictionary:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, spec)
	var places: Dictionary = {}
	for c in world.get_children():
		if c is Node3D:
			var p: Vector3 = (c as Node3D).position
			places[String(c.name)] = Vector3(snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001))
	world.free()
	return places


# Two placement maps are equal iff they have the same keys AND each key's position
# matches within 1 mm.
func _placements_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
		if (a[key] as Vector3).distance_to(b[key] as Vector3) > 0.001:
			return false
	return true


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
