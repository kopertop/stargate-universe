extends SceneTree

# Smoke test for the no-death knockout → med-bay recovery loop (issue #92).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/knockout.gd
#
# Asserts (acceptance criteria):
#   • knock_out(cause) is the single downed entry point — flips state, never a
#     game over (episode_complete stays false, health/oxygen full).
#   • The player is routed to the infirmary, healed, with recovering_in_infirmary
#     armed and the cause stashed for the ward's TJ line.
#   • Lines are semi-random within a per-cause pool and resolve from the correct
#     cause pool in data/knockout_lines.json. Unknown causes fall back to generic.
#   • A downed run banks ONLY the minimum-necessary target resource; everything
#     else gathered this run + the remaining window is forfeited.
#   • instant_mode flips state without a scene change/cutscene.
#   • The recovery flag round-trips through serialize/deserialize.
#
# Uses the live autoloads (GameState + Inventory + SceneRouter) like e1_flow.gd.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== knockout (no-death) smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(inv != null, "Inventory autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or inv == null or router == null:
		_report()
		return

	# Headless: flip state without the fade/cutscene/scene-load.
	router.set("instant_mode", true)

	# --- 1. data file loads with every required cause pool -----------------
	var data: Dictionary = gs.call("_load_knockout_data")
	_expect(not data.is_empty(), "knockout_lines.json loads")
	var pools: Dictionary = data.get("pools", {})
	for cause in ["trap", "asphyxiation", "heat", "alarm", "alien_defense", "window_closed", "generic"]:
		var pool: Variant = pools.get(cause, null)
		_expect(pool is Array and not (pool as Array).is_empty(),
			"cause '%s' has a non-empty line pool" % cause)

	# --- 2. window_closed knockout: heal + route + bank minimum lime -------
	gs.call("reset")
	# Stage a planet run: spec targeting lime, a fresh window, and resources
	# gathered DURING the run (so we can verify forfeit vs. bank).
	gs.set("active_planet_spec", {
		"seed": 42,
		"resource_table": {"clusters": [{"type": "lime", "nodes": 5}]},
	})
	var lime_start: int = int(inv.call("count", "lime"))      # 0 after reset
	var water_start: int = int(inv.call("count", "water"))    # seeded default
	_expect(gs.call("start_gate_window", 180.0) == true, "gate window opens (snapshots run start)")
	# Gather during the run: 4 lime + 5 water.
	inv.call("add_item", "lime", 4, "mined this run")
	inv.call("add_item", "water", 5, "scooped this run")
	_expect(int(inv.call("count", "lime")) == lime_start + 4, "pre-knockout: 4 lime gathered")
	_expect(int(inv.call("count", "water")) == water_start + 5, "pre-knockout: 5 water gathered")

	# Damage + suffocate the player so we can prove the heal-to-full on wake.
	gs.call("damage", 80.0)
	gs.call("consume_oxygen", 90.0)
	_expect(gs.health < 30.0, "pre-knockout: health damaged")
	_expect(gs.oxygen < 30.0, "pre-knockout: oxygen depleted")

	var pre_episode_complete: bool = gs.episode_complete

	gs.call("knock_out", "window_closed")

	# Heal to full — NO death.
	_expect(gs.health == gs.MAX_HEALTH, "knockout heals health to full")
	_expect(gs.oxygen == gs.MAX_OXYGEN, "knockout heals oxygen to full")
	_expect(gs.episode_complete == pre_episode_complete and gs.episode_complete == false,
		"knockout is never a game over (episode not completed)")

	# Routed to the infirmary, recovery beat armed.
	_expect(gs.recovering_in_infirmary == true, "recovering_in_infirmary armed")
	_expect(String(gs.knockout_cause) == "window_closed", "knockout_cause stashed for the ward")
	_expect(String(gs.next_room_id) == "infirmary", "next_room_id baton -> infirmary")
	_expect(String(gs.current_room_id) == "infirmary", "instant_mode flips current room to infirmary (no scene load)")

	# Banked minimum target (lime): start + 1, NOT the 4 gathered.
	_expect(int(inv.call("count", "lime")) == lime_start + 1,
		"downed run banks exactly the minimum target (1 lime), forfeiting the rest")
	# Forfeit non-target gathered resource (water) back to the run-start snapshot.
	_expect(int(inv.call("count", "water")) == water_start,
		"downed run forfeits non-target resource gathered this run (water)")

	# Window + run snapshot ended.
	_expect(gs.gate_window_active == false, "knockout ends the gate window")
	_expect(is_equal_approx(gs.gate_window_remaining, 0.0), "knockout zeroes remaining window")
	_expect((gs.run_start_resources as Dictionary).is_empty(), "run snapshot cleared after reconcile")

	# --- 3. cause-tagged line comes from the correct pool ------------------
	var line_info: Dictionary = gs.call("knockout_line", "window_closed")
	_expect(String(line_info.get("speaker", "")) == "TJ", "wake-up line speaker is TJ")
	var wc_pool: Array = pools.get("window_closed", [])
	_expect(wc_pool.has(String(line_info.get("line", ""))),
		"selected line is from the window_closed pool")

	var asphyx: Dictionary = gs.call("knockout_line", "asphyxiation")
	_expect((pools.get("asphyxiation", []) as Array).has(String(asphyx.get("line", ""))),
		"asphyxiation line comes from the asphyxiation pool")
	_expect(not (pools.get("window_closed", []) as Array).has(String(asphyx.get("line", ""))),
		"asphyxiation line is NOT a window_closed line (pools are distinct)")

	# Unknown cause falls back to the generic pool.
	var unknown: Dictionary = gs.call("knockout_line", "meteor_strike")
	_expect((pools.get("generic", []) as Array).has(String(unknown.get("line", ""))),
		"unknown cause falls back to the generic pool")

	# Semi-random within the pool: across many draws we should see >1 distinct
	# line from a multi-line pool (probabilistic but the pools have 3 lines, so
	# 40 draws collapsing to one would be ~1e-7 — effectively never).
	var seen: Dictionary = {}
	for i in 40:
		seen[String(gs.call("knockout_line", "trap").get("line", ""))] = true
	_expect(seen.size() > 1, "lines are semi-random within a per-cause pool (saw %d distinct)" % seen.size())

	# --- 4. minimum-bank when NOTHING was gathered: keep start only --------
	gs.call("reset")
	gs.set("active_planet_spec", {"resource_table": {"clusters": [{"type": "lime"}]}})
	var lime_start2: int = int(inv.call("count", "lime"))
	gs.call("start_gate_window", 180.0)
	# Gather nothing this run.
	gs.call("knock_out", "trap")
	_expect(int(inv.call("count", "lime")) == lime_start2,
		"gathered nothing → bank stays at run-start (no phantom lime)")

	# --- 5. no run snapshot (hazard with no open window) → no resource strip
	gs.call("reset")
	inv.call("add_item", "lime", 2, "carried from before")
	_expect((gs.run_start_resources as Dictionary).is_empty(), "no window → no run snapshot")
	gs.call("knock_out", "heat")
	_expect(int(inv.call("count", "lime")) == 2,
		"no run snapshot → knockout doesn't strip resources the player legitimately holds")
	_expect(String(gs.knockout_cause) == "heat", "heat cause stashed")

	# --- 6. leaving infirmary is the only thing that clears the flag -------
	_expect(gs.recovering_in_infirmary == true, "still recovering before leaving the ward")
	gs.call("clear_infirmary_recovery")
	_expect(gs.recovering_in_infirmary == false, "clear_infirmary_recovery resets the flag")
	_expect(String(gs.knockout_cause) == "", "clear_infirmary_recovery clears the cause")

	# --- 7. recovery state round-trips through save/load -------------------
	gs.call("reset")
	gs.set("active_planet_spec", {"resource_table": {"clusters": [{"type": "lime"}]}})
	gs.call("start_gate_window", 180.0)
	gs.call("knock_out", "asphyxiation")
	var snap: Dictionary = gs.call("serialize")
	_expect(snap.get("recovering_in_infirmary", false) == true, "serialize captures recovering_in_infirmary")
	_expect(String(snap.get("knockout_cause", "")) == "asphyxiation", "serialize captures knockout_cause")
	gs.call("reset")
	_expect(gs.recovering_in_infirmary == false, "reset clears recovery flag before load")
	gs.call("deserialize", snap, 2)
	_expect(gs.recovering_in_infirmary == true, "deserialize restores recovering_in_infirmary")
	_expect(String(gs.knockout_cause) == "asphyxiation", "deserialize restores knockout_cause")

	# Leave instant_mode as we found it.
	router.set("instant_mode", false)
	_report()


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
			print("  - " + f)
		quit(1)
