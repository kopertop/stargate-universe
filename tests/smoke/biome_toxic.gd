extends SceneTree

# Headless smoke test for the Toxic / No-atmosphere biome (issue #89), gated on
# the standalone story flag GameState.pressure_suits_found. Asserts the acceptance
# criteria:
#   1. Toxic biome is NEVER selected over many seeds while pressure_suits_found is
#      false; once the flag is set it CAN be rolled (the dial/selection flow may
#      only offer it after the flag).
#   2. The biome reports a non-breathable atmosphere and a positive on-surface
#      oxygen drain; a pressure suit SLOWS (but doesn't zero) the drain.
#   3. On-surface oxygen actually drains over a simulated window; a suit drains
#      slower than no suit.
#   4. Oxygen depletion routes the no-death knockout → med-bay recovery, cause
#      "asphyxiation" (heals to full, never a game over).
#   5. The pressure_suits_found flag persists across a save round-trip.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/biome_toxic.gd
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md). Uses the
# live GameState + SceneRouter autoloads (reached via /root) for the drain +
# knockout paths.

const GEN_PATH: String = "res://scripts/planet_generator.gd"
const TOXIC_BIOME: String = "toxic"

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== biome_toxic smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	if _gen == null:
		_report()
		return

	_test_toxic_gated_by_flag()
	_test_toxic_non_breathable_with_suit_mitigation()
	_test_oxygen_drains_on_surface_suit_slower()
	_test_oxygen_depletion_routes_knockout()
	_test_flag_persists_round_trip()

	_report()


# --- 1: toxic only generates when pressure_suits_found is true ---------------
func _test_toxic_gated_by_flag() -> void:
	# Flag false → toxic is excluded from the eligible pool entirely…
	var locked: Array = _gen.eligible_biomes({"pressure_suits_found": false})
	_expect(not locked.has(TOXIC_BIOME),
		"toxic NOT eligible while pressure_suits_found is false")
	_expect(locked.size() > 0, "other biomes remain eligible without the flag (%d)" % locked.size())

	# …so over many seeds it is NEVER selected.
	var rolled_locked: bool = false
	for seed in range(0, 400):
		if _gen.select_biome(seed, {"pressure_suits_found": false}) == TOXIC_BIOME:
			rolled_locked = true
			break
	_expect(not rolled_locked, "toxic never selected over 400 seeds while flag is false")

	# Flag true → toxic enters the pool…
	var unlocked: Array = _gen.eligible_biomes({"pressure_suits_found": true})
	_expect(unlocked.has(TOXIC_BIOME), "toxic eligible once pressure_suits_found is true")

	# …and CAN be rolled for some seed.
	var rolled_unlocked: bool = false
	for seed in range(0, 400):
		if _gen.select_biome(seed, {"pressure_suits_found": true}) == TOXIC_BIOME:
			rolled_unlocked = true
			break
	_expect(rolled_unlocked, "toxic CAN be selected with the flag set (over 400 seeds)")

	# select_biome is deterministic for a given seed + flags.
	var a: String = _gen.select_biome(12345, {"pressure_suits_found": true})
	var b: String = _gen.select_biome(12345, {"pressure_suits_found": true})
	_expect(a == b, "select_biome deterministic for a fixed seed (%s == %s)" % [a, b])

	# The biome's required-flag is surfaced from data, not hardcoded.
	_expect(String(_gen.biome_required_flag(TOXIC_BIOME)) == "pressure_suits_found",
		"toxic biome declares requires_flag pressure_suits_found in data")
	_expect(String(_gen.biome_required_flag("desert")) == "",
		"unrestricted biome (desert) declares no required flag")


# --- 2: non-breathable + suit mitigation ------------------------------------
func _test_toxic_non_breathable_with_suit_mitigation() -> void:
	var spec: Dictionary = _spec(7, TOXIC_BIOME)
	_expect(_gen.breathable_for(spec) == false, "toxic biome reports a non-breathable atmosphere")
	var unsuited: float = _gen.oxygen_drain_for(spec, false)
	var suited: float = _gen.oxygen_drain_for(spec, true)
	_expect(unsuited > 0.0, "toxic biome drains oxygen on-surface (%.2f/s unsuited)" % unsuited)
	_expect(suited > 0.0, "a suit does not make a toxic world free (%.2f/s suited)" % suited)
	_expect(suited < unsuited, "pressure suit SLOWS the oxygen drain (%.2f < %.2f)" % [suited, unsuited])

	# A breathable biome drains no oxygen regardless of suit.
	var temperate: Dictionary = _spec(7, "temperate")
	_expect(_gen.breathable_for(temperate) == true, "temperate biome is breathable")
	_expect(_gen.oxygen_drain_for(temperate, false) == 0.0, "breathable biome drains no oxygen")


# --- 3: oxygen drains on-surface; suit drains slower ------------------------
func _test_oxygen_drains_on_surface_suit_slower() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return

	# No suit: oxygen drains over a simulated window.
	gs.call("reset")
	gs.set("pressure_suits_found", false)
	gs.set("active_planet_spec", _spec(104729, TOXIC_BIOME))
	gs.call("start_gate_window", 160.0)
	var start_o2: float = float(gs.get("oxygen"))
	# Drive the drain tick directly for 5 seconds (the autoload _process tick is
	# instant_mode-gated in live play; here we exercise the internal helper).
	gs.call("_tick_atmosphere_oxygen_drain", 5.0)
	var unsuited_o2: float = float(gs.get("oxygen"))
	_expect(unsuited_o2 < start_o2, "unsuited oxygen drains on toxic surface (%.1f -> %.1f)" % [start_o2, unsuited_o2])

	# With suit: same elapsed time drains LESS.
	gs.call("reset")
	gs.set("pressure_suits_found", true)
	gs.set("active_planet_spec", _spec(104729, TOXIC_BIOME))
	gs.call("start_gate_window", 160.0)
	var suit_start: float = float(gs.get("oxygen"))
	gs.call("_tick_atmosphere_oxygen_drain", 5.0)
	var suited_o2: float = float(gs.get("oxygen"))
	var unsuited_loss: float = start_o2 - unsuited_o2
	var suited_loss: float = suit_start - suited_o2
	_expect(suited_loss > 0.0, "suited oxygen still drains (loss %.1f)" % suited_loss)
	_expect(suited_loss < unsuited_loss,
		"suit slows the drain (suited loss %.1f < unsuited loss %.1f)" % [suited_loss, unsuited_loss])


# --- 4: oxygen depletion routes the no-death knockout, cause asphyxiation ----
func _test_oxygen_depletion_routes_knockout() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	if gs == null or router == null:
		_expect(false, "GameState + SceneRouter autoloads attached (knockout)")
		return
	router.set("instant_mode", true)
	gs.call("reset")
	gs.set("pressure_suits_found", false)
	gs.set("active_planet_spec", _spec(104729, TOXIC_BIOME))
	gs.call("start_gate_window", 160.0)
	# Burn oxygen down to a sliver so the next tick floors it.
	gs.set("oxygen", 1.0)
	var pre_episode: bool = gs.get("episode_complete")
	var fired: bool = gs.call("_tick_atmosphere_oxygen_drain", 10.0)
	_expect(fired == true, "oxygen depletion tick fires a knockout")
	# No death — knockout heals to full and routes to the infirmary.
	_expect(float(gs.get("oxygen")) == float(gs.get("MAX_OXYGEN")), "asphyxiation knockout restores oxygen to full")
	_expect(float(gs.get("health")) == float(gs.get("MAX_HEALTH")), "asphyxiation knockout heals health to full (no death)")
	_expect(gs.get("episode_complete") == pre_episode and gs.get("episode_complete") == false,
		"asphyxiation knockout is never a game over")
	_expect(gs.get("recovering_in_infirmary") == true, "asphyxiation knockout arms med-bay recovery")
	_expect(String(gs.get("knockout_cause")) == "asphyxiation", "knockout cause-tagged 'asphyxiation'")
	_expect(String(gs.get("next_room_id")) == "infirmary", "asphyxiation knockout routes to the infirmary")
	_expect(gs.get("gate_window_active") == false, "asphyxiation knockout ends the run window")

	# The cause-tagged wake-up line resolves from the asphyxiation pool.
	var line_info: Dictionary = gs.call("knockout_line", "asphyxiation")
	_expect(String(line_info.get("line", "")) != "", "asphyxiation wake-up line resolves from the pool")
	router.set("instant_mode", false)


# --- 5: flag persists across a save round-trip ------------------------------
func _test_flag_persists_round_trip() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		return
	gs.call("reset")
	_expect(gs.get("pressure_suits_found") == false, "reset() clears pressure_suits_found")
	gs.call("mark_pressure_suits_found")
	_expect(gs.get("pressure_suits_found") == true, "mark_pressure_suits_found sets the flag")
	var saved: Dictionary = gs.call("serialize")
	_expect(saved.get("pressure_suits_found", false) == true, "serialize() carries pressure_suits_found")
	gs.call("reset")
	_expect(gs.get("pressure_suits_found") == false, "reset() re-clears the flag pre-deserialize")
	gs.call("deserialize", saved, 1)
	_expect(gs.get("pressure_suits_found") == true, "deserialize() restores pressure_suits_found")
	# biome_flags() maps story state → the selection-pool flag dict.
	var flags: Dictionary = gs.call("biome_flags")
	_expect(flags.get("pressure_suits_found", false) == true,
		"biome_flags() surfaces the restored flag to the selection pool")


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
