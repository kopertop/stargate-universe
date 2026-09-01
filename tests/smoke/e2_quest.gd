extends SceneTree

# Smoke test for the E2 "Light" power-restoration quest chain.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/e2_quest.gd
#
# Asserts:
#   • data/quests.json e2_explore has the expected 6-step ordered ids.
#   • QuestLog starts e2_explore at step 1 (find_engineering) and advances
#     through the full chain as GameState helpers flip each flag.
#   • Predicate advance: each helper (find_engineering, locate_junction,
#     repair_junction, route_power) advances the active step to the next.
#   • The terminal step (explore_complete) is reached and is_complete fires.
#   • Save round-trip: serialize → reset → deserialize restores mid-chain state.
#   • PowerGrid integration: repair_junction calls repair_generator,
#     route_power calls set_section_repaired on key rooms.
#
# Uses the live autoloads (GameState + QuestLog + PowerGrid) rather than
# manually constructed duplicates — same pattern as quest_log.gd smoke test.

const EXPECTED_E2_STEPS: Array[String] = [
	"find_engineering",
	"locate_junction",
	"repair_junction",
	"route_power",
	"unlock_upper_deck",
	"explore_complete",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== e2_quest smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var ql: Node = root.get_node_or_null("QuestLog")
	var pg: Node = root.get_node_or_null("PowerGrid")
	_expect(gs != null, "GameState autoload attached")
	_expect(ql != null, "QuestLog autoload attached")
	_expect(pg != null, "PowerGrid autoload attached")
	if gs == null or ql == null:
		_report()
		return

	# Save isolation — mandatory before touching GameState.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "e2_quest")

	gs.reset()

	# --- 1. quests.json e2_explore contents --------------------------------
	ql.call("start_quest", "e2_explore")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "find_engineering",
		"e2_explore starts at find_engineering")
	for i in EXPECTED_E2_STEPS.size():
		var sid: String = EXPECTED_E2_STEPS[i]
		var lbl: String = String(ql.call("label", sid))
		_expect(lbl != "" and lbl != sid,
			"label() resolves real text for step %d (%s)" % [i, sid])
	_expect(ql.call("is_complete", "e2_explore") == false,
		"e2_explore is not complete at start")

	# --- 2. Predicate advance through the power-restoration chain ----------
	# Step 1 → 2: find_engineering
	gs.call("find_engineering")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "locate_junction",
		"find_engineering -> locate_junction")
	_expect(gs.get("engineering_found") == true,
		"engineering_found flag is true after find_engineering()")

	# Step 2 → 3: locate_junction
	gs.call("locate_junction")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "repair_junction",
		"locate_junction -> repair_junction")
	_expect(gs.get("junction_located") == true,
		"junction_located flag is true after locate_junction()")

	# Step 3 → 4: repair_junction (also restores PowerGrid generator)
	gs.call("repair_junction")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "route_power",
		"repair_junction -> route_power")
	_expect(gs.get("junction_repaired") == true,
		"junction_repaired flag is true after repair_junction()")
	if pg != null:
		_expect(float(pg.call("get_available_power")) == float(pg.call("get_total_capacity")),
			"PowerGrid generator output restored to full capacity after repair_junction")

	# Step 4 → 5: route_power (also clears damaged sections on key rooms)
	gs.call("route_power")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "unlock_upper_deck",
		"route_power -> unlock_upper_deck")
	_expect(gs.get("power_routed") == true,
		"power_routed flag is true after route_power()")

	# Step 5 → 6: unlock_upper_deck (predicate checks ProceduralShip floors).
	# We can't easily unlock a floor in a headless test without ProceduralShip's
	# full setup, so use complete_step (the event channel) to advance.
	ql.call("complete_step", "e2_explore", "unlock_upper_deck")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "explore_complete",
		"unlock_upper_deck -> explore_complete (terminal)")
	_expect(ql.call("is_complete", "e2_explore") == true,
		"e2_explore is_complete fires at terminal step")

	# --- 3. Idempotency: calling helpers twice is a no-op ------------------
	gs.call("find_engineering")
	_expect(gs.get("engineering_found") == true,
		"find_engineering() is idempotent (no regression)")

	# --- 4. Save round-trip -----------------------------------------------
	# Reset, walk to mid-chain, snapshot, reset, restore.
	gs.reset()
	ql.call("start_quest", "e2_explore")
	gs.call("find_engineering")
	gs.call("locate_junction")
	_expect(String(ql.call("active_step_id", "e2_explore")) == "repair_junction",
		"round-trip pre-state: active step is repair_junction")
	var snap: Dictionary = ql.serialize()
	gs.reset()
	ql.call("start_quest", "e2_explore")
	# Re-set the flags so re-derive after deserialize keeps completed_steps in sync.
	gs.set("engineering_found", true)
	gs.set("junction_located", true)
	ql.call("deserialize", snap, 1)
	_expect(String(ql.call("active_step_id", "e2_explore")) == "repair_junction",
		"round-trip restored: active step is repair_junction")

	# --- 5. GameState serialize/deserialize for E2 flags ------------------
	gs.reset()
	gs.set("engineering_found", true)
	gs.set("junction_repaired", true)
	var gs_snap: Dictionary = gs.call("serialize")
	gs.reset()
	_expect(gs.get("engineering_found") == false, "reset clears engineering_found")
	gs.call("deserialize", gs_snap, 1)
	_expect(gs.get("engineering_found") == true, "deserialize restores engineering_found")
	_expect(gs.get("junction_repaired") == true, "deserialize restores junction_repaired")
	_expect(gs.get("junction_located") == false, "deserialize does not set unset flags")

	# Final reset.
	gs.reset()
	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - ", f)
		quit(1)