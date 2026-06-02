extends SceneTree

# Headless integration smoke test for the procedural-planets epic (issue #93).
# This is the LAST planet suite: it proves the per-biome pieces are wired
# together through the GameState dial / selection flow rather than re-testing
# each biome in isolation (the biome_* suites cover those). Asserts:
#   1. Dial flow: build_next_planet_spec() yields a complete, well-formed spec
#      (seed + biome + resource_table + hazard_params) and persists it into
#      GameState.active_planet_spec.
#   2. Determinism: the Nth dial always rolls the SAME biome + seed (the run
#      seed is derived from planets_dialed), and a save/reload BEFORE the next
#      dial rebuilds the IDENTICAL upcoming planet.
#   3. Per-biome generation + walkability: every biome in biomes.json builds a
#      world with terrain + return gate and stays walkable (no jump required).
#   4. Scarcity targeting: a dialed spec's resource_table guarantees the
#      scarcest tracked resource as the primary cluster.
#   5. Toxic gating: build_next_planet_spec() never rolls Toxic until
#      pressure_suits_found is set; once set, Toxic becomes eligible.
#   6. Knockout recovery: a downed run on a generated planet routes to the
#      infirmary, ends the window, banks the minimum target, and heals — no
#      death, no stranding.
#   7. Kino scan profile: planet_scan_profile() summarizes the upcoming planet's
#      biome + hazard + breathability + resources for the recon HUD surface.
#   8. Save/reload rebuild: a persisted spec round-trips through serialize /
#      deserialize and rebuilds the same world (same terrain height field).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/planet_integration.gd
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md). GameState +
# Inventory are reached via /root (autoloads ARE attached under -s).

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== planet_integration smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if _gen == null or gs == null:
		_report()
		return

	_test_dial_flow_builds_and_persists_spec(gs)
	_test_gameplay_dial_entry_builds_spec(gs)
	_test_dial_seed_and_biome_deterministic(gs)
	_test_every_biome_generates_and_is_walkable()
	_test_dialed_spec_guarantees_scarcest(gs)
	_test_toxic_gated_by_pressure_suits(gs)
	_test_knockout_recovery_loop(gs)
	_test_scan_profile_summarizes_planet(gs)
	_test_spec_round_trip_rebuilds_identical(gs)

	_report()


# --- 1: dial flow builds + persists a complete spec -------------------------
func _test_dial_flow_builds_and_persists_spec(gs: Node) -> void:
	gs.call("reset")
	var spec: Dictionary = gs.call("build_next_planet_spec")
	_expect(spec is Dictionary and not spec.is_empty(), "build_next_planet_spec returns a spec")
	_expect(spec.has("seed") and int(spec["seed"]) > 0, "spec carries a positive run seed")
	_expect(String(spec.get("biome", "")) != "", "spec carries a biome")
	_expect(spec.get("resource_table", null) is Dictionary, "spec carries a resource_table")
	_expect(spec.get("hazard_params", null) is Dictionary, "spec carries hazard_params")
	var active: Dictionary = gs.get("active_planet_spec")
	_expect(active == spec, "build_next_planet_spec persists into active_planet_spec")
	_expect(int(gs.get("planets_dialed")) == 1, "first dial increments planets_dialed to 1")


# --- 1b: the REAL gate-dial gameplay entry point builds + persists a spec ----
# Regression for the integration gap: build_next_planet_spec()/build_air_lime_spec()
# must be reached from gameplay, not only from this suite calling the builder
# directly. Drives GameState.dial_lime_planet() (the entry gate_console.gd hits)
# and asserts a spec was assembled and persisted — so a future refactor that
# unwires the dial from spec-building fails HERE.
func _test_gameplay_dial_entry_builds_spec(gs: Node) -> void:
	gs.call("reset")
	# Precondition: the gate only dials after Destiny drops from FTL.
	gs.set("ftl_drop_triggered", true)
	_expect((gs.get("active_planet_spec") as Dictionary).is_empty(),
		"no active spec before the gate is dialed")
	gs.call("dial_lime_planet")
	_expect(bool(gs.get("lime_planet_dialed")), "dial_lime_planet latches the dial")
	var active: Dictionary = gs.get("active_planet_spec")
	_expect(active is Dictionary and not active.is_empty(),
		"dial_lime_planet builds + persists active_planet_spec (gameplay entry)")
	_expect(active.has("seed") and active.has("biome") and active.has("resource_table"),
		"gameplay-dialed spec is well-formed (seed + biome + resource_table)")
	_expect(int(gs.get("planets_dialed")) >= 1, "gameplay dial advances planets_dialed")


# --- 2: Nth dial deterministic in seed + biome ------------------------------
func _test_dial_seed_and_biome_deterministic(gs: Node) -> void:
	gs.call("reset")
	var first_a: Dictionary = gs.call("build_next_planet_spec")
	var second_a: Dictionary = gs.call("build_next_planet_spec")
	gs.call("reset")
	var first_b: Dictionary = gs.call("build_next_planet_spec")
	var second_b: Dictionary = gs.call("build_next_planet_spec")
	_expect(int(first_a["seed"]) == int(first_b["seed"]),
		"dial #1 rolls the same seed every game")
	_expect(String(first_a["biome"]) == String(first_b["biome"]),
		"dial #1 rolls the same biome every game")
	_expect(int(second_a["seed"]) == int(second_b["seed"]),
		"dial #2 rolls the same seed every game")
	_expect(int(first_a["seed"]) != int(second_a["seed"]),
		"consecutive dials use distinct seeds")


# --- 3: every biome generates + is walkable ---------------------------------
func _test_every_biome_generates_and_is_walkable() -> void:
	var table: Dictionary = _gen.biome_table()
	_expect(not table.is_empty(), "biomes.json parses to a non-empty table")
	for biome in table.keys():
		var spec: Dictionary = _spec(int(hash(biome)) & 0x7fffffff, String(biome))
		var params: Dictionary = _gen.build_params(spec)
		var slope: float = _gen.max_slope_deg(params, 200.0, 4.0)
		_expect(slope < WALKABLE_MARGIN_DEG,
			"%s walkable (max slope %.1f° < %.0f°)" % [biome, slope, WALKABLE_MARGIN_DEG])
		_expect(slope < FLOOR_MAX_ANGLE_DEG, "%s slope under CharacterBody3D floor limit" % biome)
		var world: Node3D = Node3D.new()
		root.add_child(world)
		var manager: Node = _gen.build(world, spec)
		_expect(manager != null, "%s build() returns a chunk manager" % biome)
		_expect(world.get_node_or_null("PlanetGround") != null, "%s installs terrain" % biome)
		_expect(world.get_node_or_null("PlanetReturnStargate") != null, "%s places return gate" % biome)
		world.free()


# --- 4: dialed spec guarantees the scarcest resource as primary -------------
func _test_dialed_spec_guarantees_scarcest(gs: Node) -> void:
	gs.call("reset")
	var ranked: Array = gs.call("resource_scarcity")
	_expect(not ranked.is_empty(), "scarcity query returns ranked tracked resources")
	var scarcest: String = String((ranked[0] as Dictionary)["id"]) if not ranked.is_empty() else ""
	var spec: Dictionary = gs.call("build_next_planet_spec")
	var rt: Dictionary = spec.get("resource_table", {})
	var clusters: Variant = rt.get("clusters", [])
	_expect(clusters is Array and not (clusters as Array).is_empty(),
		"dialed spec carries resource clusters")
	if clusters is Array and not (clusters as Array).is_empty():
		var primary: String = String(((clusters as Array)[0] as Dictionary).get("type", ""))
		_expect(primary == scarcest,
			"dialed spec primary cluster is the scarcest resource (%s)" % scarcest)


# --- 5: Toxic biome gated by pressure_suits_found ---------------------------
func _test_toxic_gated_by_pressure_suits(gs: Node) -> void:
	# Without suits: Toxic must never appear in the eligible pool, and no dial over
	# many seeds may roll it.
	gs.call("reset")
	var pool_locked: Array = _gen.eligible_biomes(gs.call("biome_flags"))
	_expect(not pool_locked.has("toxic"),
		"toxic excluded from eligible pool without pressure_suits_found")
	var rolled_toxic_locked: bool = false
	for i in 60:
		if _gen.select_biome(i * 911, gs.call("biome_flags")) == "toxic":
			rolled_toxic_locked = true
			break
	_expect(not rolled_toxic_locked, "no seed rolls toxic while suits are not found")
	# After the story flag is set: Toxic becomes eligible.
	gs.call("mark_pressure_suits_found")
	var pool_open: Array = _gen.eligible_biomes(gs.call("biome_flags"))
	_expect(pool_open.has("toxic"),
		"toxic eligible once pressure_suits_found is set")


# --- 6: no-death knockout → infirmary recovery loop -------------------------
func _test_knockout_recovery_loop(gs: Node) -> void:
	gs.call("reset")
	# instant_mode so the downed route flips state directly (no async scene load,
	# which would hang/error under a bare -s script). Mirrors knockout.gd.
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(router != null, "SceneRouter autoload attached")
	if router != null:
		router.set("instant_mode", true)
	# Dial a planet + open a window so a run snapshot exists; bank some target.
	var spec: Dictionary = gs.call("build_next_planet_spec")
	var target: String = gs.call("run_target_resource")
	gs.call("start_gate_window", float(_gen.gate_window_for(spec)))
	gs.call("add_resource", target, 5)
	gs.set("health", 10.0)
	gs.call("knock_out", "trap")
	_expect(gs.get("recovering_in_infirmary") == true, "knockout arms infirmary recovery beat")
	_expect(String(gs.get("knockout_cause")) == "trap", "knockout records the cause tag")
	_expect(gs.get("gate_window_active") == false, "knockout ends the gate window (run over)")
	# MAX_HEALTH is a const (Object.get skips consts → null); use the known 100.0.
	_expect(float(gs.get("health")) >= 99.99,
		"knockout heals the player fully (no death)")
	_expect(String(gs.get("current_room_id")) == "infirmary",
		"knockout routes the downed player to the infirmary")
	var line: Dictionary = gs.call("knockout_line", "trap")
	_expect(String(line.get("line", "")) != "", "knockout surfaces a wake-up line for the cause")


# --- 7: Kino scan profile summarizes the upcoming planet --------------------
func _test_scan_profile_summarizes_planet(gs: Node) -> void:
	gs.call("reset")
	# Pin a toxic spec (suits found) so the breathability / hazard fields are
	# exercised, not just the all-clear desert case.
	gs.call("mark_pressure_suits_found")
	var spec: Dictionary = gs.call("build_next_planet_spec", "Test World", "toxic")
	var profile: Dictionary = gs.call("planet_scan_profile", spec)
	_expect(String(profile.get("biome", "")) == "toxic", "scan profile reports the biome")
	_expect(String(profile.get("label", "")) != "", "scan profile carries a human biome label")
	_expect(profile.get("breathable", true) == false, "toxic scan profile reports NOT breathable")
	_expect(String(profile.get("hazard", "")) == "TOXIN", "toxic scan profile reports the hazard")
	_expect(profile.get("resources", []) is Array and not (profile.get("resources", []) as Array).is_empty(),
		"scan profile lists the planet's resources")
	_expect(float(profile.get("gate_window", 0.0)) > 0.0, "scan profile reports the gate window")
	# A breathable biome reports breathable + no toxins.
	var desert: Dictionary = gs.call("build_next_planet_spec", "", "desert")
	var dprofile: Dictionary = gs.call("planet_scan_profile", desert)
	_expect(dprofile.get("breathable", false) == true, "desert scan profile reports breathable")


# --- 8: persisted spec round-trips + rebuilds identical ---------------------
func _test_spec_round_trip_rebuilds_identical(gs: Node) -> void:
	gs.call("reset")
	var spec: Dictionary = gs.call("build_next_planet_spec")
	var saved: Dictionary = gs.call("serialize")
	_expect(saved.has("active_planet_spec"), "serialize() carries the active planet spec")
	_expect(saved.has("planets_dialed"), "serialize() carries planets_dialed")
	var dialed_before: int = int(gs.get("planets_dialed"))
	gs.call("reset")
	_expect(gs.get("active_planet_spec").is_empty(), "reset() clears the active spec")
	_expect(int(gs.get("planets_dialed")) == 0, "reset() clears planets_dialed")
	gs.call("deserialize", saved, 1)
	var restored: Dictionary = gs.get("active_planet_spec")
	_expect(int(restored.get("seed", -1)) == int(spec["seed"]),
		"deserialize() restores the spec seed")
	_expect(String(restored.get("biome", "")) == String(spec["biome"]),
		"deserialize() restores the spec biome")
	_expect(int(gs.get("planets_dialed")) == dialed_before,
		"deserialize() restores planets_dialed (no re-roll on reload)")
	# Rebuild from the original + the restored spec: same terrain height field.
	var p_orig: Dictionary = _gen.build_params(spec)
	var p_rest: Dictionary = _gen.build_params(restored)
	var same: bool = true
	for sample in [Vector3(30, 0, 18), Vector3(-44, 0, 70), Vector3(120, 0, -90)]:
		var ho: float = _gen.height_at(sample.x, sample.z, p_orig)
		var hr: float = _gen.height_at(sample.x, sample.z, p_rest)
		if abs(ho - hr) > 0.0001:
			same = false
	_expect(same, "rebuilt world height field is identical after save/reload")


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
