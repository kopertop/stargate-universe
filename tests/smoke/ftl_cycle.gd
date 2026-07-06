extends SceneTree

# Smoke test for the post-E1 CORE LOOP — the FTL resupply cycle:
#
#   FTL --timer--> STOPPED (drop-out) --dial + cross--> AWAY (mining run)
#   AWAY --return / recall / knockout--> FTL (jump; repair + build en route)
#   STOPPED --timer, never dialed--> FTL (missed window)
#
# plus the mine→build/repair economy seam:
#   * ResourceNode.interact() banks resources into the shared Inventory pool,
#   * ShipState.build_module CHARGES the module's data-declared build_cost,
#   * ShipState.repair_room_with_parts spends Ship Parts to restore damage,
#     unblocking construction in story-damaged rooms.
#
# Run with:
#   godot --headless --quit-after 300 -s res://tests/smoke/ftl_cycle.gd

var _failures: Array[String] = []
var _passes: int = 0

# Autoloads fetched from root — a bare `-s` SceneTree script can't reference
# autoload identifiers at compile time (same pattern as deck_boot.gd).
var _gs: Node = null
var _ship: Node = null
var _inv: Node = null


func _initialize() -> void:
	print("=== ftl-cycle smoke test ===")
	for autoload_name in ["GameState", "ShipState", "ShipLayout", "Inventory"]:
		if root.get_node_or_null(autoload_name) == null:
			_fail("autoload", "%s not found at /root (check project.godot)" % autoload_name)
	if not _failures.is_empty():
		_report()
		return
	_gs = root.get_node("GameState")
	_ship = root.get_node("ShipState")
	_inv = root.get_node("Inventory")
	call_deferred("_run")


func _run() -> void:
	_check_cycle_engages_after_e1()
	_check_drop_out_and_dial()
	_check_mining_interact()
	_check_return_jump_and_repeat()
	_check_missed_window_jumps()
	_check_recall_keeps_haul()
	_check_knockout_ends_run()
	_check_build_economy()
	_check_repair_economy()
	_check_save_round_trip()
	_report()


# ---- 1. cycle engagement -------------------------------------------------------

func _check_cycle_engages_after_e1() -> void:
	_gs.reset()
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_NONE, "fresh game: no cycle phase")
	_expect(_gs.dial_next_planet().is_empty(), "cycle dial refused before E1 resolves")
	_expect(not _gs.cycle_planet_dialed, "refused dial locks nothing")

	# Resolve the Air crisis: episode completion hands the game to the loop.
	_gs.scrubber_repaired = true
	_gs.check_episode_complete()
	_expect(_gs.episode_complete, "episode 1 completes once the scrubber is repaired")
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL, "cycle engages in FTL on E1 completion")
	_expect(is_equal_approx(_gs.ftl_cycle_remaining, _gs.FTL_CYCLE_FTL_SECONDS),
		"first FTL leg starts at the full duration")
	_expect(_gs.ftl_cycle_count == 0, "no stops reached yet")


# ---- 2. drop-out + dial ---------------------------------------------------------

func _check_drop_out_and_dial() -> void:
	var dials_before: int = _gs.planets_dialed
	_gs._tick_ftl_cycle(_gs.FTL_CYCLE_FTL_SECONDS + 1.0)
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_STOPPED, "FTL leg expiring drops the ship out")
	_expect(_gs.ftl_cycle_count == 1, "drop-out counts the stop")
	_expect(is_equal_approx(_gs.ftl_cycle_remaining, _gs.FTL_CYCLE_STOP_SECONDS),
		"stop window opens at the full duration")
	_expect(not _gs.is_gate_open(), "gate stays shut until dialed")

	var spec: Dictionary = _gs.dial_next_planet()
	_expect(not spec.is_empty(), "dial at a stop rolls a planet spec")
	_expect(_gs.planets_dialed == dials_before + 1, "cycle dial advances the dial counter")
	_expect(String(spec.get("biome", "")) != "", "rolled spec carries a biome")
	_expect(_gs.cycle_planet_dialed, "dial locks the gate to the stop's planet")
	_expect(_gs.is_gate_open(), "gate reads open after the cycle dial")
	_expect(_gs.can_travel_to_planet(), "on-foot crossing permitted after the cycle dial")
	_expect(not _gs.can_travel_to_lime_planet(), "the E1 lime window stays closed post-E1")

	var again: Dictionary = _gs.dial_next_planet()
	_expect(int(again.get("seed", -1)) == int(spec.get("seed", -2)),
		"re-dialing the same stop returns the already-locked spec")
	_expect(_gs.planets_dialed == dials_before + 1, "re-dial does not advance the counter")


# ---- 3. the mining run ----------------------------------------------------------

func _check_mining_interact() -> void:
	_gs.begin_cycle_run()
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_AWAY, "crossing out starts the away run")
	_expect(_gs.is_gate_open(), "gate stays open for the whole surface window")
	_expect(_gs.start_gate_window(120.0), "departure window starts on the surface")

	_inv.call("set_count", "parts", 0)
	var node_script: Script = load("res://scripts/resource_node.gd")
	var node: StaticBody3D = node_script.new()
	node.resource_type = "parts"
	node.amount = 3
	root.add_child(node)
	node.interact(null)
	_expect(_gs.resource_count("parts") == 3, "mining a deposit banks its resource")
	_expect(node.depleted, "mined deposit depletes")
	node.interact(null)
	_expect(_gs.resource_count("parts") == 3, "a depleted deposit yields nothing more")
	node.queue_free()


# ---- 4. return → jump → next stop ------------------------------------------------

func _check_return_jump_and_repeat() -> void:
	var first_seed: int = int(_gs.active_planet_spec.get("seed", -1))
	_gs.complete_cycle_run()
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL, "returning aboard jumps Destiny to FTL")
	_expect(not _gs.cycle_planet_dialed, "the jump closes the gate")
	_expect(not _gs.gate_window_active, "the jump ends the departure window")
	_expect(_gs.resource_count("parts") == 3, "the haul survives the trip home")
	_expect(is_equal_approx(_gs.ftl_cycle_remaining, _gs.FTL_CYCLE_FTL_SECONDS),
		"the next FTL leg starts fresh")

	# The loop REPEATS: next drop-out reaches a different world.
	_gs._tick_ftl_cycle(_gs.FTL_CYCLE_FTL_SECONDS + 1.0)
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_STOPPED, "second FTL leg drops out again")
	_expect(_gs.ftl_cycle_count == 2, "second stop counts")
	var spec: Dictionary = _gs.dial_next_planet()
	_expect(int(spec.get("seed", -1)) != first_seed,
		"the next stop rolls a DIFFERENT planet (seed advances with the dial counter)")


# ---- 5. a stop the crew sleeps through ---------------------------------------------

func _check_missed_window_jumps() -> void:
	# Currently STOPPED + dialed (from the previous check). A dialed stop holds
	# for the away run — the timer only expires an UNdialed stop.
	_gs.cycle_planet_dialed = false
	_gs._tick_ftl_cycle(_gs.FTL_CYCLE_STOP_SECONDS + 1.0)
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL,
		"an undialed stop window expiring jumps the ship on")
	_expect(not _gs.is_gate_open(), "gate shut after the missed stop")


# ---- 6. recall at 0:00 keeps the haul ----------------------------------------------

func _check_recall_keeps_haul() -> void:
	_gs._tick_ftl_cycle(_gs.FTL_CYCLE_FTL_SECONDS + 1.0)
	_gs.dial_next_planet()
	_gs.begin_cycle_run()
	_gs.start_gate_window(90.0)
	_inv.call("set_count", "parts", 5)
	_gs.recall_after_window_close()
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL, "recall at 0:00 ends the stop (jump)")
	_expect(not _gs.cycle_planet_dialed, "recall closes the gate")
	_expect(not _gs.gate_window_active, "recall ends the window")
	_expect(_gs.resource_count("parts") == 5, "the scramble back keeps everything gathered")


# ---- 7. a downed run still ends the stop -------------------------------------------

func _check_knockout_ends_run() -> void:
	_gs._tick_ftl_cycle(_gs.FTL_CYCLE_FTL_SECONDS + 1.0)
	_gs.dial_next_planet()
	_gs.begin_cycle_run()
	_gs.start_gate_window(90.0)
	_gs.knock_out("trap")
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL, "a knockout on a cycle run jumps the ship")
	_expect(not _gs.cycle_planet_dialed, "knockout closes the gate")
	_expect(not _gs.gate_window_active, "knockout ends the window")
	_expect(_gs.recovering_in_infirmary, "knockout still routes the recovery beat")


# ---- 8. build economy (mined parts are the sink) -----------------------------------

func _check_build_economy() -> void:
	_gs.reset()
	_ship.reset()
	_inv.call("set_count", "parts", 0)
	var blocker: String = _ship.build_blocker("eli_quarters", "hydroponics_unit")
	_expect(blocker != "", "build refused with an empty parts pool")
	_expect(blocker.contains("Parts"), "blocker names the missing resource")

	_inv.call("set_count", "parts", 5)
	_expect(_ship.build_blocker("eli_quarters", "hydroponics_unit") != "",
		"build refused when parts fall short of the module cost")

	_inv.call("set_count", "parts", 7)
	_expect(_ship.build_cost("hydroponics_unit").get("parts", 0) == 6,
		"hydroponics cost read from data/room_modules.json")
	_expect(_ship.build_module("eli_quarters", "hydroponics_unit"),
		"build succeeds once the pool covers the cost")
	_expect(_gs.resource_count("parts") == 1, "build charges EXACTLY the module cost")
	_expect(not _ship.build_module("eli_quarters", "research_lab"),
		"next build refused — pool spent")


# ---- 9. repair economy (parts restore damage, unblocking builds) --------------------

func _check_repair_economy() -> void:
	_gs.reset()
	_ship.reset()
	_ship.set_room_damage("eli_quarters", 50.0)
	_inv.call("set_count", "parts", 0)
	_expect(_ship.repair_blocker("eli_quarters") != "", "repair refused with no parts")
	_expect(not _ship.repair_room_with_parts("eli_quarters"), "priced repair fails dry")

	_inv.call("set_count", "parts", 10)
	_expect(_ship.repair_room_with_parts("eli_quarters"), "repair spends parts")
	_expect(is_equal_approx(_ship.room_damage("eli_quarters"), 25.0),
		"one spend restores %d%%" % int(_ship.REPAIR_PER_SPEND_PCT))
	_expect(_gs.resource_count("parts") == 9, "repair charged 1 part")
	_expect(_ship.repair_room_with_parts("eli_quarters"), "second repair spends again")
	_expect(is_equal_approx(_ship.room_damage("eli_quarters"), 0.0), "room fully restored")
	_expect(_ship.repair_blocker("eli_quarters") != "", "pristine room refuses further repairs")

	# The story-damaged section: repair down past the threshold, then build in it.
	_expect(_ship.build_blocker("breached_section_south", "storage_depot") != "",
		"story-damaged section refuses builds at 65% damage")
	_expect(_ship.repair_room_with_parts("breached_section_south"), "repair 65% → 40%")
	_expect(_ship.repair_room_with_parts("breached_section_south"), "repair 40% → 15%")
	_expect(_ship.build_blocker("breached_section_south", "storage_depot") == "",
		"repaired section accepts builds (parts remain for the depot cost)")
	_expect(_ship.build_module("breached_section_south", "storage_depot"),
		"module built in the repaired section")


# ---- 10. save round-trip + migration ------------------------------------------------

func _check_save_round_trip() -> void:
	_gs.reset()
	_gs.episode_complete = true
	_gs.ftl_cycle_phase = _gs.FTL_PHASE_STOPPED
	_gs.ftl_cycle_remaining = 123.5
	_gs.ftl_cycle_count = 4
	_gs.cycle_planet_dialed = true
	var snap: Dictionary = _gs.serialize()
	_gs.reset()
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_NONE, "reset clears the cycle")
	_gs.deserialize(snap, 1)
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_STOPPED, "round-trip restores the phase")
	_expect(is_equal_approx(_gs.ftl_cycle_remaining, 123.5), "round-trip restores the clock")
	_expect(_gs.ftl_cycle_count == 4, "round-trip restores the stop count")
	_expect(_gs.cycle_planet_dialed, "round-trip restores the dial lock")

	# Migration: a pre-cycle save already past E1 joins the loop on load.
	var legacy: Dictionary = snap.duplicate(true)
	legacy.erase("ftl_cycle_phase")
	legacy.erase("ftl_cycle_remaining")
	legacy.erase("ftl_cycle_count")
	legacy.erase("cycle_planet_dialed")
	legacy["episode_complete"] = true
	_gs.reset()
	_gs.deserialize(legacy, 1)
	_expect(_gs.ftl_cycle_phase == _gs.FTL_PHASE_FTL,
		"pre-cycle save at episode-complete migrates into the FTL leg")
	_gs.reset()


# ---- harness -------------------------------------------------------------------

func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _fail(context: String, message: String) -> void:
	_failures.append("%s: %s" % [context, message])
	print("  FAIL  %s: %s" % [context, message])


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes: %d" % _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("failures: %d" % _failures.size())
		for f in _failures:
			print("  - %s" % f)
		print("RESULT: FAIL")
		quit(1)
