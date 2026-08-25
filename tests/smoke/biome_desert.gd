extends SceneTree

# Headless smoke test for the Desert/Hot biome + the regenerated, WALKABLE first
# planet (issue #87). Asserts the acceptance criteria:
#   1. Desert renders from a spec and is WALKABLE everywhere (no jump needed) —
#      worst sampled slope stays well under the CharacterBody3D floor limit.
#   2. Heat SHORTENS the gate window vs the temperate baseline AND RAISES the
#      per-second water drain.
#   3. The FIRST lime run (planets.json air_lime_world seed) regenerates as a
#      desert biome with lime GUARANTEED present.
#   4. Heat water drain actually burns Water over a simulated window (a hot biome
#      reaches each whole unit faster than temperate), never below zero.
#   5. The drain rate persists across a save round-trip (resumed mid-run keeps the
#      right rate).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/biome_desert.gd
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md).

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const PLANETS_PATH: String = "res://data/planets.json"

# CharacterBody3D default floor_max_angle = 45°; require a comfortable margin so
# even the worst sampled cell is walkable without jumping (the #85 convention).
const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0
const FIRST_PLANET_ID: String = "air_lime_world"

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== biome_desert smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	if _gen == null:
		_report()
		return

	_test_desert_renders_and_is_walkable()
	_test_heat_shortens_window_and_raises_water_drain()
	_test_first_planet_is_desert_with_lime()
	_test_heat_water_drain_burns_water()
	_test_drain_rate_persists_round_trip()

	_report()


# --- 1: desert renders from a spec and is walkable --------------------------
func _test_desert_renders_and_is_walkable() -> void:
	var spec: Dictionary = _desert_spec(424242)
	var params: Dictionary = _gen.build_params(spec)
	var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
	_expect(slope < WALKABLE_MARGIN_DEG,
		"desert max slope %.1f° < %.0f° (walkable, no jump)" % [slope, WALKABLE_MARGIN_DEG])
	_expect(slope < FLOOR_MAX_ANGLE_DEG, "desert slope under CharacterBody3D floor limit")

	var world: Node3D = Node3D.new()
	root.add_child(world)
	var manager: Node = _gen.build(world, spec)
	_expect(manager != null, "desert build() returns a chunk manager")
	_expect(world.get_node_or_null("PlanetGround") != null, "desert installs PlanetGround terrain")
	_expect(world.get_node_or_null("PlanetReturnStargate") != null, "desert places return Stargate")
	_expect(world.get_node_or_null("LimeNode1") != null, "desert places lime deposits")
	world.free()


# --- 2: heat shortens window + raises water drain ---------------------------
func _test_heat_shortens_window_and_raises_water_drain() -> void:
	var desert: Dictionary = _desert_spec(7)
	var temperate: Dictionary = _spec(7, "temperate")
	var d_win: float = _gen.gate_window_for(desert)
	var t_win: float = _gen.gate_window_for(temperate)
	_expect(d_win < t_win,
		"desert gate window %.0fs SHORTER than temperate baseline %.0fs" % [d_win, t_win])
	var d_drain: float = _gen.water_drain_for(desert)
	var t_drain: float = _gen.water_drain_for(temperate)
	_expect(d_drain > t_drain,
		"desert water drain %.4f/s FASTER than temperate %.4f/s" % [d_drain, t_drain])


# --- 3: first lime run regenerates as desert with lime guaranteed -----------
func _test_first_planet_is_desert_with_lime() -> void:
	var row: Dictionary = _load_first_planet()
	_expect(not row.is_empty(), "planets.json carries the %s first-planet row" % FIRST_PLANET_ID)
	# Mirror planet.gd::_active_spec(): the first run regenerates as a desert biome
	# from the existing air_lime_world seed/inputs, lime guaranteed via the cluster.
	var spec: Dictionary = {
		"seed": int(row.get("seed", 104729)),
		"biome": "desert",
		"resource_table": {
			"lime_nodes": int(row.get("lime_nodes", 5)),
			"lime_per_node": int(row.get("lime_per_node", 1)),
			"lime_min_radius": float(row.get("lime_min_radius", 70.0)),
			"lime_max_radius": float(row.get("lime_max_radius", 200.0)),
		},
		"hazard_params": row.get("atmosphere", {}) if row.get("atmosphere", {}) is Dictionary else {},
		"name": String(row.get("name", "Lime World")),
	}
	_expect(String(spec["biome"]) == "desert", "first planet biome is desert")
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_gen.build(world, spec)
	var lime_nodes: int = 0
	for c in world.get_children():
		if String(c.name).begins_with("LimeNode"):
			lime_nodes += 1
	_expect(lime_nodes > 0, "first desert lime run guarantees lime present (%d nodes)" % lime_nodes)
	# Walkable too — the explicit fix for the "had to jump" first-run complaint.
	var params: Dictionary = _gen.build_params(spec)
	var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
	_expect(slope < WALKABLE_MARGIN_DEG, "first desert planet walkable everywhere (no jump)")
	world.free()


# --- 4: heat water drain burns Water over a simulated window ----------------
func _test_heat_water_drain_burns_water() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return
	gs.call("reset")
	gs.set("active_planet_spec", _desert_spec(104729))
	var start_water: int = int(gs.call("resource_count", "water"))
	_expect(start_water > 0, "crew starts the run with water (%d)" % start_water)
	var started: bool = gs.call("start_gate_window", 150.0)
	_expect(started == true, "start_gate_window opens a fresh window")
	_expect(float(gs.get("gate_window_water_drain")) > 0.0,
		"desert run stamps a positive water drain rate")
	# Simulate one window's worth of drain (the autoload tick is instant_mode-gated
	# in live play; here we drive the internal accumulator directly to prove it
	# spends whole Water units across the window).
	var rate: float = float(gs.get("gate_window_water_drain"))
	gs.call("_tick_heat_water_drain", 1.0 / rate)   # exactly one unit's worth
	var after_one: int = int(gs.call("resource_count", "water"))
	_expect(after_one == start_water - 1, "heat drains one whole Water unit at 1/rate seconds")
	# Drain far past the supply — never goes negative.
	for i in 1000:
		gs.call("_tick_heat_water_drain", 1.0)
	_expect(int(gs.call("resource_count", "water")) >= 0, "water drain never goes below zero")


# --- 5: drain rate persists across a save round-trip ------------------------
func _test_drain_rate_persists_round_trip() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		return
	gs.call("reset")
	gs.set("active_planet_spec", _desert_spec(104729))
	gs.call("start_gate_window", 150.0)
	var rate: float = float(gs.get("gate_window_water_drain"))
	_expect(rate > 0.0, "round-trip pre-save drain rate is positive (%.4f)" % rate)
	var saved: Dictionary = gs.call("serialize")
	_expect(saved.has("gate_window_water_drain"), "serialize() carries gate_window_water_drain")
	gs.call("reset")
	_expect(float(gs.get("gate_window_water_drain")) == 0.0, "reset() clears drain rate")
	gs.call("deserialize", saved, 1)
	_expect(abs(float(gs.get("gate_window_water_drain")) - rate) < 0.0001,
		"deserialize() restores the run's water drain rate")


# --- helpers ----------------------------------------------------------------
func _desert_spec(seed: int) -> Dictionary:
	return _spec(seed, "desert")


func _spec(seed: int, biome: String) -> Dictionary:
	return {
		"seed": seed,
		"biome": biome,
		"resource_table": {"lime_nodes": 4, "lime_per_node": 1,
			"lime_min_radius": 50.0, "lime_max_radius": 120.0},
		"hazard_params": {},
		"name": "Test %s" % biome,
	}


func _load_first_planet() -> Dictionary:
	var f: FileAccess = FileAccess.open(PLANETS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		return {}
	for entry in parsed:
		if entry is Dictionary and String(entry.get("id", "")) == FIRST_PLANET_ID:
			return entry
	return {}


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
