extends SceneTree

# Smoke test for the CommStones autoload (communication stones body-swap system).
#
# Verifies:
#   • data/comm_stones.json loads with expected stones, bodies, and objectives.
#   • activate_stone transitions through phases (idle → swapping → on_earth).
#   • Body cycling: each visit assigns a different Earth body.
#   • SGC objective completion: individual + all-done check.
#   • return_to_destiny transitions back to idle.
#   • Save round-trip: serialize → reset → deserialize preserves state.
#   • reset() clears all state.
#   • GameState mirror vars sync correctly.
#   • CommStonePedestal interactable first-examination + activation flow.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/comm_stones.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== comm_stones smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var cs: Node = root.get_node_or_null("CommStones")
	_expect(cs != null, "CommStones autoload is attached")
	if cs == null:
		_report()
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload is attached")
	if gs == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory before touching GameState.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "comm_stones")

	# Clean slate.
	gs.call("reset")
	cs.call("reset")

	# Enable instant mode so cinematics don't block.
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	# --- 1. Data loaded -------------------------------------------------------
	var stones: Array = cs.call("get_stones")
	_expect(stones.size() >= 1, "at least 1 stone definition loaded (got %d)" % stones.size())
	var stone: Dictionary = stones[0] if not stones.is_empty() else {}
	_expect(String(stone.get("id", "")) == "stone_01", "first stone id is stone_01")
	_expect(String(stone.get("display_name", "")) == "Communication Stone", "stone display_name correct")

	var bodies: Array = cs.call("get_earth_bodies")
	_expect(bodies.size() >= 3, "at least 3 Earth bodies loaded (got %d)" % bodies.size())

	var objectives: Array = cs.call("get_sgc_objectives")
	_expect(objectives.size() >= 4, "at least 4 SGC objectives loaded (got %d)" % objectives.size())

	# --- 2. Initial state -----------------------------------------------------
	_expect(String(cs.call("get_phase")) == "idle", "initial phase is idle")
	_expect(not cs.call("is_on_earth"), "not on earth initially")
	_expect(int(cs.call("get_earth_visits")) == 0, "0 earth visits initially")
	_expect(int(cs.call("get_stones_used")) == 0, "0 stones used initially")

	# --- 3. Activate stone (body swap) ---------------------------------------
	# In instant mode, activate_stone completes synchronously (no cinematic).
	await cs.call("activate_stone", "stone_01")
	# The call is async (uses await internally); in instant mode the state
	# mutations happen synchronously before the coroutine returns.
	_expect(String(cs.call("get_phase")) == "on_earth", "phase is on_earth after activate")
	_expect(cs.call("is_on_earth"), "is_on_earth true after activate")
	_expect(int(cs.call("get_stones_used")) == 1, "stones_used == 1 after activate")
	_expect(int(cs.call("get_earth_visits")) == 1, "earth_visits == 1 after activate")

	var active_body: Dictionary = cs.call("get_active_earth_body")
	_expect(not active_body.is_empty(), "active earth body is set")
	var first_body_id: String = String(active_body.get("id", ""))
	_expect(first_body_id != "", "first body id is non-empty")

	# --- 4. Body cycling (second visit uses a different body) -----------------
	await cs.call("return_to_destiny")
	_expect(String(cs.call("get_phase")) == "idle", "phase is idle after return")
	_expect(not cs.call("is_on_earth"), "not on earth after return")

	await cs.call("activate_stone", "stone_01")
	_expect(int(cs.call("get_earth_visits")) == 2, "earth_visits == 2 after second activate")
	var second_body: Dictionary = cs.call("get_active_earth_body")
	var second_body_id: String = String(second_body.get("id", ""))
	_expect(second_body_id != first_body_id, "second visit uses different body (%s vs %s)" % [first_body_id, second_body_id])

	# --- 5. SGC objective completion -----------------------------------------
	# Reset to a clean earth visit for objective testing.
	await cs.call("return_to_destiny")
	cs.call("reset")
	await cs.call("activate_stone", "stone_01")

	# None complete initially.
	_expect(not cs.call("all_sgc_objectives_done"), "not all SGC objectives done initially")
	_expect(not cs.call("is_sgc_objective_done", "report_air_crisis"), "report_air_crisis not done initially")

	# Complete objectives one by one.
	var obj_ids: Array = ["report_air_crisis", "report_ship_status", "report_alien_encounter", "request_supplies"]
	for i in obj_ids.size():
		var oid: String = obj_ids[i]
		cs.call("complete_sgc_objective", oid)
		_expect(cs.call("is_sgc_objective_done", oid), "objective %s is done after completion" % oid)
		if i < obj_ids.size() - 1:
			_expect(not cs.call("all_sgc_objectives_done"), "not all done after %d/%d" % [i + 1, obj_ids.size()])

	_expect(cs.call("all_sgc_objectives_done"), "all SGC objectives done after completing all 4")

	# Idempotency: completing again doesn't re-emit or break.
	cs.call("complete_sgc_objective", "report_air_crisis")
	_expect(cs.call("all_sgc_objectives_done"), "still all done after duplicate completion")

	# --- 6. Return to Destiny ------------------------------------------------
	await cs.call("return_to_destiny")
	_expect(String(cs.call("get_phase")) == "idle", "phase is idle after return")
	_expect(not cs.call("is_on_earth"), "not on earth after return")

	# --- 7. Save round-trip --------------------------------------------------
	# Set up a known state.
	cs.call("reset")
	await cs.call("activate_stone", "stone_01")
	cs.call("complete_sgc_objective", "report_air_crisis")
	cs.call("complete_sgc_objective", "report_ship_status")

	var saved: Dictionary = cs.call("serialize")
	_expect(String(saved.get("phase", "")) == "on_earth", "saved phase is on_earth")
	_expect(int(saved.get("stones_used", 0)) == 1, "saved stones_used == 1")
	_expect(int(saved.get("earth_visits", 0)) == 1, "saved earth_visits == 1")
	_expect((saved.get("completed_sgc_objectives", []) as Array).size() == 2, "saved 2 completed objectives")

	# Reset and restore.
	cs.call("reset")
	_expect(String(cs.call("get_phase")) == "idle", "phase is idle after reset")
	_expect(int(cs.call("get_stones_used")) == 0, "stones_used == 0 after reset")

	cs.call("deserialize", saved, 2)
	_expect(String(cs.call("get_phase")) == "on_earth", "restored phase is on_earth")
	_expect(int(cs.call("get_stones_used")) == 1, "restored stones_used == 1")
	_expect(int(cs.call("get_earth_visits")) == 1, "restored earth_visits == 1")
	_expect(cs.call("is_sgc_objective_done", "report_air_crisis"), "restored report_air_crisis done")
	_expect(cs.call("is_sgc_objective_done", "report_ship_status"), "restored report_ship_status done")
	_expect(not cs.call("is_sgc_objective_done", "report_alien_encounter"), "restored report_alien_encounter not done")

	# --- 8. Mid-swap save snaps to idle --------------------------------------
	var mid_swap: Dictionary = {
		"phase": "swapping",
		"active_stone_id": "stone_01",
		"active_earth_body_id": "",
		"completed_sgc_objectives": [],
		"stones_used": 1,
		"earth_visits": 0,
		"body_index": 0,
	}
	cs.call("deserialize", mid_swap, 2)
	_expect(String(cs.call("get_phase")) == "idle", "mid-swap save snaps to idle")
	_expect(String(cs.call("get_active_stone").get("id", "")) == "", "active stone cleared after mid-swap restore")

	# --- 9. GameState mirror vars --------------------------------------------
	cs.call("reset")
	gs.call("reset")
	gs.set("comm_stones_found", true)
	gs.set("stones_activated", true)
	gs.set("all_sgc_objectives_done", true)
	gs.set("returned_from_earth", true)

	# Serialize GameState and verify the new vars are in the snapshot.
	var gs_saved: Dictionary = gs.call("serialize")
	_expect(gs_saved.get("comm_stones_found", false) == true, "GameState serializes comm_stones_found")
	_expect(gs_saved.get("stones_activated", false) == true, "GameState serializes stones_activated")
	_expect(gs_saved.get("all_sgc_objectives_done", false) == true, "GameState serializes all_sgc_objectives_done")
	_expect(gs_saved.get("returned_from_earth", false) == true, "GameState serializes returned_from_earth")

	# Deserialize and verify.
	gs.call("reset")
	_expect(not gs.get("comm_stones_found"), "comm_stones_found is false after reset")
	gs.call("deserialize", gs_saved, 2)
	_expect(gs.get("comm_stones_found") == true, "GameState deserializes comm_stones_found")
	_expect(gs.get("stones_activated") == true, "GameState deserializes stones_activated")
	_expect(gs.get("all_sgc_objectives_done") == true, "GameState deserializes all_sgc_objectives_done")
	_expect(gs.get("returned_from_earth") == true, "GameState deserializes returned_from_earth")

	# --- 10. CommStonePedestal interactable ----------------------------------
	# Create a pedestal in code and test the interact flow.
	var pedestal_script: GDScript = load("res://scripts/comm_stone_pedestal.gd")
	var pedestal: Node = pedestal_script.new()
	_expect(pedestal != null, "CommStonePedestal can be instantiated")
	if pedestal != null:
		# First examination.
		pedestal.call("_ready")
		_expect(String(pedestal.call("get_prompt")) == "Examine the Ancient stones", "first-use prompt correct")
		pedestal.call("interact", null)
		_expect(gs.get("comm_stones_found") == true, "comm_stones_found set after first examination")
		_expect(String(pedestal.call("get_prompt")) == "Place your hand on the stone", "activate prompt after first examination")

		# Stone activation.
		pedestal.call("interact", null)
		await process_frame
		# The pedestal calls cs.activate_stone() without await, so we need
		# a frame for the coroutine to complete in instant mode.
		_expect(gs.get("stones_activated") == true, "stones_activated set after pedestal activation")
		_expect(String(cs.call("get_phase")) == "on_earth", "CommStones is on_earth after pedestal activation")

		# Return via return pedestal.
		await cs.call("return_to_destiny")

		var return_pedestal: Node = pedestal_script.new()
		if return_pedestal != null:
			return_pedestal.set("is_return_pedestal", true)
			return_pedestal.call("_ready")
			_expect(String(return_pedestal.call("get_prompt")) == "Use the stone to return to Destiny", "return pedestal prompt correct")
			return_pedestal.call("interact", null)
			await process_frame
			_expect(String(cs.call("get_phase")) == "idle", "phase is idle after return pedestal interact")
			return_pedestal.queue_free()

		pedestal.queue_free()

	# --- 11. Quest chain data integrity --------------------------------------
	# Verify the e5_earth quest chain exists in quests.json.
	# Reset GameState first so predicates don't auto-advance.
	gs.call("reset")
	var ql: Node = root.get_node_or_null("QuestLog")
	if ql != null:
		# The quest data is loaded by QuestLog; check it has e5_earth.
		var has_e5: bool = ql.call("has_quest", "e5_earth") if ql.has_method("has_quest") else false
		# has_quest may not exist; try start_quest as a probe.
		if not has_e5 and ql.has_method("start_quest"):
			ql.call("start_quest", "e5_earth")
			var step_id: String = String(ql.call("active_step_id", "e5_earth"))
			_expect(step_id == "find_comm_stones", "e5_earth starts at find_comm_stones (got %s)" % step_id)
		else:
			_expect(has_e5, "QuestLog has e5_earth quest")

	_report()
	if _failures.is_empty():
		quit(0)
	else:
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		# print("  PASS: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("\n--- Results ---")
	print("  Passes:   %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("  Failed:")
		for f in _failures:
			print("    - %s" % f)
	print("=== comm_stones smoke test %s ===" % ("PASSED" if _failures.is_empty() else "FAILED"))