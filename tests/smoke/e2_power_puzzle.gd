extends SceneTree

# Smoke test for the E2: Light — ship power restoration puzzle sequence.
#
# Verifies:
#   • GameState flags start false after reset.
#   • QuestLog starts e2_explore and the first step (find_engineering) is active.
#   • mark_engineering_found advances to locate_junction.
#   • mark_junction_located advances to repair_junction.
#   • mark_junction_repaired advances to route_power.
#   • mark_power_routed advances to unlock_upper_deck (terminal step path).
#   • PowerGrid integration: after junction_repaired, repair_generator
#     restores generator output to full capacity.
#   • PowerGrid critical rooms (gate_room, control_interface_room) are POWERED
#     after the route stage clears overrides.
#   • ConduitJunction interactable: stage transitions LOCATE→REPAIR→ROUTE→DONE.
#   • GameState serialize/deserialize round-trips the 4 new flags.
#   • reset() clears all 4 flags.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/e2_power_puzzle.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== e2_power_puzzle smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var ql: Node = root.get_node_or_null("QuestLog")
	var pg: Node = root.get_node_or_null("PowerGrid")
	_expect(gs != null, "GameState autoload is attached")
	_expect(ql != null, "QuestLog autoload is attached")
	_expect(pg != null, "PowerGrid autoload is attached")
	if gs == null or ql == null or pg == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "e2_power_puzzle_smoke")

	# --- Setup: reset GameState + start E2 quest ----------------------------
	gs.reset()
	# Simulate E1 completion so the E2 quest can start.
	gs.episode_complete = true

	# Start the e2_explore quest chain.
	ql.call("start_quest", "e2_explore")
	ql.set("_tracked_quest_id", "e2_explore")
	ql.call("advance", "e2_explore")

	# --- Flags start false ---------------------------------------------------
	_expect(not gs.engineering_found, "engineering_found starts false")
	_expect(not gs.junction_located, "junction_located starts false")
	_expect(not gs.junction_repaired, "junction_repaired starts false")
	_expect(not gs.power_routed, "power_routed starts false")

	# --- Stage 0: find_engineering is active --------------------------------
	var step: String = String(ql.call("active_step_id", "e2_explore"))
	_expect(step == "find_engineering", "active step is find_engineering (got %s)" % step)

	# --- Stage 1: mark_engineering_found → locate_junction -------------------
	gs.mark_engineering_found()
	_expect(gs.engineering_found, "engineering_found is true after mark")
	ql.call("advance", "e2_explore")
	step = String(ql.call("active_step_id", "e2_explore"))
	_expect(step == "locate_junction", "active step is locate_junction (got %s)" % step)

	# --- Stage 2: mark_junction_located → repair_junction --------------------
	gs.mark_junction_located()
	_expect(gs.junction_located, "junction_located is true after mark")
	ql.call("advance", "e2_explore")
	step = String(ql.call("active_step_id", "e2_explore"))
	_expect(step == "repair_junction", "active step is repair_junction (got %s)" % step)

	# --- Stage 3: mark_junction_repaired → route_power -----------------------
	# Before repair, reduce generator output to simulate a damaged grid.
	pg.call("set_generator_output", 25.0)
	var output_before: float = float(pg.call("get_available_power"))
	_expect(output_before == 25.0, "generator output is 25 before repair (got %f)" % output_before)

	gs.mark_junction_repaired()
	_expect(gs.junction_repaired, "junction_repaired is true after mark")
	ql.call("advance", "e2_explore")
	step = String(ql.call("active_step_id", "e2_explore"))
	_expect(step == "route_power", "active step is route_power (got %s)" % step)

	# --- Stage 4: mark_power_routed → unlock_upper_deck ----------------------
	# Simulate the conduit junction's route stage: repair generator + clear
	# overrides on critical rooms.
	pg.call("repair_generator")
	pg.call("set_room_override", "gate_room", -1)
	pg.call("set_room_override", "control_interface_room", -1)
	pg.call("set_section_repaired", "gate_room")
	pg.call("set_section_repaired", "control_interface_room")

	var output_after: float = float(pg.call("get_available_power"))
	var total_cap: float = float(pg.call("get_total_capacity"))
	_expect(output_after == total_cap, "generator output at full capacity after repair (got %f / %f)" % [output_after, total_cap])

	# Critical rooms should be powered.
	var gate_powered: bool = bool(pg.call("is_room_powered", "gate_room"))
	var control_powered: bool = bool(pg.call("is_room_powered", "control_interface_room"))
	_expect(gate_powered, "gate_room is powered after route stage")
	_expect(control_powered, "control_interface_room is powered after route stage")

	gs.mark_power_routed()
	_expect(gs.power_routed, "power_routed is true after mark")
	ql.call("advance", "e2_explore")
	step = String(ql.call("active_step_id", "e2_explore"))
	_expect(step == "unlock_upper_deck", "active step is unlock_upper_deck (got %s)" % step)

	# --- ConduitJunction interactable stage transitions ---------------------
	var ConduitJunctionScript: Script = load("res://scripts/conduit_junction.gd")
	_expect(ConduitJunctionScript != null, "ConduitJunction script loads")

	# Create a fresh junction instance for a clean-slate test.
	# Reset GameState so the junction starts at Stage.LOCATE.
	gs.reset()
	gs.episode_complete = true
	var junction: Object = ConduitJunctionScript.new()
	_expect(junction != null, "ConduitJunction instance created")
	# _ready() doesn't fire for bare .new() instances (not in the tree), so
	# call _sync_stage() to initialize the prompt + enabled to stage 0 values.
	junction.call("_sync_stage")
	_expect(junction.get("_stage") == 0, "junction starts at LOCATE stage (got %d)" % int(junction.get("_stage")))
	_expect(String(junction.get("prompt")) == "Examine conduit junction", "LOCATE prompt correct")
	_expect(bool(junction.get("enabled")), "LOCATE stage is enabled")

	# Simulate interact → advances to REPAIR.
	junction.call("_on_interact", null)
	_expect(gs.junction_located, "LOCATE interact sets junction_located")
	_expect(int(junction.get("_stage")) == 1, "junction advances to REPAIR stage (got %d)" % int(junction.get("_stage")))
	_expect(String(junction.get("prompt")) == "Repair conduit junction", "REPAIR prompt correct")

	# Simulate interact → advances to ROUTE.
	junction.call("_on_interact", null)
	_expect(gs.junction_repaired, "REPAIR interact sets junction_repaired")
	_expect(int(junction.get("_stage")) == 2, "junction advances to ROUTE stage (got %d)" % int(junction.get("_stage")))
	_expect(String(junction.get("prompt")) == "Route power to critical rooms", "ROUTE prompt correct")

	# Simulate interact → advances to DONE.
	junction.call("_on_interact", null)
	_expect(gs.power_routed, "ROUTE interact sets power_routed")
	_expect(int(junction.get("_stage")) == 3, "junction advances to DONE stage (got %d)" % int(junction.get("_stage")))
	_expect(String(junction.get("prompt")) == "Power distribution complete.", "DONE prompt correct")
	_expect(not bool(junction.get("enabled")), "DONE stage is disabled")

	# --- Idempotency: re-interact on DONE is a no-op -------------------------
	junction.call("_on_interact", null)
	_expect(int(junction.get("_stage")) == 3, "DONE stage stays DONE on re-interact")

	# --- Save round-trip for the 4 new flags --------------------------------
	gs.engineering_found = true
	gs.junction_located = true
	gs.junction_repaired = true
	gs.power_routed = true
	var serialized: Dictionary = gs.serialize()
	_expect(serialized.has("engineering_found"), "serialize has engineering_found")
	_expect(serialized.has("junction_located"), "serialize has junction_located")
	_expect(serialized.has("junction_repaired"), "serialize has junction_repaired")
	_expect(serialized.has("power_routed"), "serialize has power_routed")

	gs.engineering_found = false
	gs.junction_located = false
	gs.junction_repaired = false
	gs.power_routed = false
	gs.deserialize(serialized, 1)
	_expect(gs.engineering_found, "engineering_found restored after deserialize")
	_expect(gs.junction_located, "junction_located restored after deserialize")
	_expect(gs.junction_repaired, "junction_repaired restored after deserialize")
	_expect(gs.power_routed, "power_routed restored after deserialize")

	# --- reset() clears all 4 flags -----------------------------------------
	gs.reset()
	_expect(not gs.engineering_found, "engineering_found cleared by reset")
	_expect(not gs.junction_located, "junction_located cleared by reset")
	_expect(not gs.junction_repaired, "junction_repaired cleared by reset")
	_expect(not gs.power_routed, "power_routed cleared by reset")

	# --- Predicate warning for unknown keys is safe -------------------------
	# Verify the quest log predicates are registered (no warning fires).
	var known_predicates: Array[String] = [
		"engineering_found", "junction_located", "junction_repaired", "power_routed"
	]
	for key in known_predicates:
		var result: bool = bool(ql.call("_evaluate_predicate", key))
		_expect(not result, "predicate %s is false after reset (got true)" % key)

	_report()
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("\n--- Results ---")
	print("  Passes:   %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("  FAILED:")
		for f in _failures:
			print("    - %s" % f)