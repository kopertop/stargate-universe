extends SceneTree

# Headless smoke test for resource-scarcity targeting + tracked resources
# (issue #86). Exercises the GameState tracked-resource registry + scarcity
# query + resource-table builder, and the generator's generalized per-type
# deposit placement. Asserts:
#   1. Water/Food/Ship Parts (and lime) are tracked via ONE registry, each with
#      an amount (Inventory count) + a low threshold.
#   2. resource_scarcity() ranks needs correctly (deepest deficit first,
#      registry order breaks ties; clamps non-negative).
#   3. build_resource_table() GUARANTEES the scarcest resource as primary +
#      adds exactly 1-2 secondary types, deterministically per seed.
#   4. A generated planet from such a table contains the scarcest resource's
#      deposit cluster and exactly 1-2 secondary resource types (mineable per
#      type via the generalized resource_node).
#   5. Targeting is deterministic given the seed (same seed → same chosen types).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/planet_resources.gd
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md). GameState +
# Inventory are reached via /root (autoloads ARE attached under -s).

const GEN_PATH: String = "res://scripts/planet_generator.gd"

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== planet_resources smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(gs != null, "GameState autoload attached")
	_expect(inv != null, "Inventory autoload attached")
	if _gen == null or gs == null or inv == null:
		_report()
		return

	_test_tracked_registry(gs)
	_test_scarcity_ranking(gs, inv)
	_test_resource_table_guarantees_scarcest(gs, inv)
	_test_generated_planet_has_scarcest_plus_extras(gs, inv)
	_test_targeting_deterministic(gs, inv)

	_report()


# --- 1: tracked resources via one registry with amount + threshold -----------
func _test_tracked_registry(gs: Node) -> void:
	var ids: Array = gs.call("tracked_resource_ids")
	for needed in ["water", "food", "parts"]:
		_expect(ids.has(needed), "tracked registry includes %s" % needed)
	# Every tracked row exposes an amount + a low threshold via the scarcity query.
	var scarcity: Array = gs.call("resource_scarcity")
	_expect(scarcity.size() == ids.size(), "scarcity covers every tracked resource")
	for row in scarcity:
		var r: Dictionary = row
		_expect(r.has("amount") and r.has("threshold"),
			"%s exposes amount + threshold" % String(r.get("id", "?")))


# --- 2: scarcity ranks needs correctly --------------------------------------
func _test_scarcity_ranking(gs: Node, inv: Node) -> void:
	# Arrange: water deep below threshold, food slightly below, parts well stocked.
	gs.call("seed_default_resources")
	inv.call("set_count", "water", 1)    # threshold 10 → deficit 9 (scarcest)
	inv.call("set_count", "food", 8)     # threshold 10 → deficit 2
	inv.call("set_count", "parts", 20)   # threshold 6  → deficit 0
	inv.call("set_count", "lime", 0)     # threshold 3  → deficit 3
	# Act
	var ranked: Array = gs.call("resource_scarcity")
	# Assert: order by deficit desc → water(9), lime(3), food(2), parts(0)
	_expect(String((ranked[0] as Dictionary)["id"]) == "water", "scarcest is water (deepest deficit)")
	_expect(int((ranked[0] as Dictionary)["deficit"]) == 9, "water deficit computed as 9")
	_expect(String((ranked[ranked.size() - 1] as Dictionary)["id"]) == "parts",
		"well-stocked parts ranks last")
	_expect(int((ranked[ranked.size() - 1] as Dictionary)["deficit"]) == 0,
		"over-threshold resource clamps deficit at 0 (never negative)")
	# resource_deficit() agrees with the ranking.
	_expect(int(gs.call("resource_deficit", "water")) == 9, "resource_deficit(water) == 9")
	_expect(int(gs.call("resource_deficit", "parts")) == 0, "resource_deficit(parts) == 0")


# --- 3: resource table guarantees scarcest + 1-2 extras ----------------------
func _test_resource_table_guarantees_scarcest(gs: Node, inv: Node) -> void:
	# Arrange: make food the single scarcest.
	gs.call("seed_default_resources")
	inv.call("set_count", "food", 0)     # deficit 10 (scarcest)
	inv.call("set_count", "water", 12)   # deficit 0
	inv.call("set_count", "parts", 12)   # deficit 0
	inv.call("set_count", "lime", 10)    # deficit 0
	# Act
	var table: Dictionary = gs.call("build_resource_table", 90210)
	var clusters: Array = table.get("clusters", [])
	var types: Array = _cluster_types(clusters)
	# Assert: scarcest present as PRIMARY (first cluster) + 1-2 extras total.
	_expect(not clusters.is_empty(), "build_resource_table emits clusters")
	_expect(String((clusters[0] as Dictionary)["type"]) == "food",
		"scarcest (food) is the guaranteed PRIMARY cluster")
	var extras: int = types.size() - 1
	_expect(extras >= 1 and extras <= 2, "exactly 1-2 secondary resource types added (got %d)" % extras)
	# No duplicate types.
	_expect(types.size() == _unique(types).size(), "no duplicate cluster types")
	# Primary cluster is the richer one (more nodes than a secondary).
	_expect(int((clusters[0] as Dictionary)["nodes"]) >= int((clusters[1] as Dictionary)["nodes"]),
		"primary cluster is at least as rich as a secondary")


# --- 4: generated planet contains scarcest + 1-2 extra types -----------------
func _test_generated_planet_has_scarcest_plus_extras(gs: Node, inv: Node) -> void:
	# Arrange: water scarcest.
	gs.call("seed_default_resources")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "parts", 20)
	inv.call("set_count", "lime", 20)
	var table: Dictionary = gs.call("build_resource_table", 4242)
	var spec: Dictionary = {
		"seed": 4242, "biome": "desert", "resource_table": table,
		"hazard_params": {}, "name": "Scarce Water World",
	}
	# Act
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, spec)
	# Assert: at least one WATER deposit node present + mineable per type.
	var present: Dictionary = _resource_node_types(world)
	_expect(present.has("water"), "generated planet contains a water deposit cluster")
	_expect(int(present["water"]) > 0, "water cluster has mineable deposit nodes")
	# Exactly the chosen types appear (scarcest + 1-2 extras), nothing else.
	var expected: Array = _cluster_types(table.get("clusters", []))
	_expect(present.size() == expected.size(),
		"planet places exactly the targeted resource types (%d)" % expected.size())
	for t in expected:
		_expect(present.has(t), "planet places targeted type %s" % t)
	# Each deposit node is a mineable ResourceNode (has resource_type + amount).
	var sample_ok: bool = false
	for c in world.get_children():
		if String(c.name).ends_with("Node1") and (c as Node).get("resource_type") != null:
			sample_ok = int((c as Node).get("amount")) >= 1
			break
	_expect(sample_ok, "deposit nodes are mineable (resource_type + amount set)")
	world.free()


# --- 5: targeting deterministic given the seed ------------------------------
func _test_targeting_deterministic(gs: Node, inv: Node) -> void:
	gs.call("seed_default_resources")
	inv.call("set_count", "parts", 0)    # parts scarcest
	inv.call("set_count", "water", 20)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "lime", 20)
	var a: Array = _cluster_types((gs.call("build_resource_table", 555) as Dictionary).get("clusters", []))
	var b: Array = _cluster_types((gs.call("build_resource_table", 555) as Dictionary).get("clusters", []))
	_expect(a == b, "same seed → identical chosen resource types %s" % str(a))
	_expect(String(a[0]) == "parts", "scarcest (parts) is primary regardless of seed")


# --- helpers ----------------------------------------------------------------
func _cluster_types(clusters: Array) -> Array:
	var out: Array = []
	for c in clusters:
		out.append(String((c as Dictionary)["type"]))
	return out


func _unique(arr: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for v in arr:
		if not seen.has(v):
			seen[v] = true
			out.append(v)
	return out


# Count of resource-deposit nodes per resource_type present in a built world.
func _resource_node_types(world: Node3D) -> Dictionary:
	var counts: Dictionary = {}
	for c in world.get_children():
		var rt: Variant = (c as Node).get("resource_type") if c.has_method("get") else null
		if rt != null and String(c.name).find("Node") >= 0:
			var t: String = String(rt)
			counts[t] = int(counts.get(t, 0)) + 1
	return counts


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
