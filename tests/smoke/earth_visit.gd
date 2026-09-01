extends SceneTree

# Smoke test for the EarthVisit system (E5 Earth segment).
#
# Verifies:
#   • data/earth_dialogues.json loads with 3 NPCs, briefing lines, personal moment lines.
#   • EarthVisit autoload is attached and data loaded.
#   • SGC report delivery through EarthVisit completes CommStones objectives.
#   • All 4 SGC objectives can be delivered; all_reports_delivered fires.
#   • Personal moment (Eli's mom) can be started and completes.
#   • Save round-trip: serialize → reset → deserialize preserves state.
#   • reset() clears all state.
#   • SGCReportConsole interactable delivers reports.
#   • EarthNPC loads dialogue trees and processes actions.
#   • PersonalMomentTrigger starts the personal moment.
#   • GameState mirror vars sync correctly.
#   • Quest chain e5_earth step progression works.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/earth_visit.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== earth_visit smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ev: Node = root.get_node_or_null("EarthVisit")
	_expect(ev != null, "EarthVisit autoload is attached")
	if ev == null:
		_report()
		quit(1)
		return

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

	# Save isolation.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "earth_visit")

	# Clean slate.
	gs.call("reset")
	cs.call("reset")
	ev.call("reset")

	# Enable instant mode so cinematics don't block.
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	# --- 1. Data loaded -------------------------------------------------------
	var npc_ids: Array = ev.call("get_npc_ids")
	_expect(npc_ids.size() >= 3, "at least 3 Earth NPCs loaded (got %d)" % npc_ids.size())
	_expect(npc_ids.has("general_oneill"), "General O'Neill NPC loaded")
	_expect(npc_ids.has("dr_brightman"), "Dr Brightman NPC loaded")
	_expect(npc_ids.has("elis_mom"), "Eli's mom NPC loaded")

	# NPC dialogue trees.
	var oneill_tree: Array = ev.call("get_npc_dialogue_tree", "general_oneill")
	_expect(oneill_tree.size() >= 5, "O'Neill dialogue tree has >= 5 nodes (got %d)" % oneill_tree.size())
	var brightman_tree: Array = ev.call("get_npc_dialogue_tree", "dr_brightman")
	_expect(brightman_tree.size() >= 5, "Brightman dialogue tree has >= 5 nodes (got %d)" % brightman_tree.size())
	var mom_tree: Array = ev.call("get_npc_dialogue_tree", "elis_mom")
	_expect(mom_tree.size() >= 5, "Eli's mom dialogue tree has >= 5 nodes (got %d)" % mom_tree.size())

	# NPC display names.
	_expect(ev.call("get_npc_display_name", "general_oneill") == "General O'Neill", "O'Neill display name correct")
	_expect(ev.call("get_npc_display_name", "dr_brightman") == "Dr Brightman", "Brightman display name correct")
	_expect(ev.call("get_npc_display_name", "elis_mom") == "Maryann Wallace", "Eli's mom display name correct")

	# NPC locations.
	_expect(ev.call("get_npc_location", "general_oneill") == "Stargate Command — Briefing Room", "O'Neill location correct")
	_expect(ev.call("get_npc_location", "elis_mom") == "Earth — Eli's Mother's Apartment", "Eli's mom location correct")

	# Ambient lines.
	var oneill_ambient: Array = ev.call("get_npc_ambient_lines", "general_oneill")
	_expect(oneill_ambient.size() >= 3, "O'Neill has >= 3 ambient lines (got %d)" % oneill_ambient.size())

	# --- 2. Initial state -----------------------------------------------------
	_expect(not ev.call("is_personal_moment_done"), "personal moment not done initially")
	_expect(not ev.call("is_sgc_briefing_shown"), "SGC briefing not shown initially")
	_expect(not ev.call("all_reports_delivered"), "not all reports delivered initially")

	# --- 3. Activate stones to get to Earth ----------------------------------
	await cs.call("activate_stone", "stone_01")
	_expect(String(cs.call("get_phase")) == "on_earth", "phase is on_earth after activate")
	# The body_swap_complete signal should have triggered the briefing.
	# In instant mode the signal fires synchronously.
	_expect(ev.call("is_sgc_briefing_shown"), "SGC briefing shown after body swap")

	# --- 4. Deliver SGC reports one by one -----------------------------------
	var obj_ids: Array = ev.call("get_sgc_objective_ids")
	_expect(obj_ids.size() == 4, "4 SGC objective IDs (got %d)" % obj_ids.size())

	for i in obj_ids.size():
		var oid: String = obj_ids[i]
		ev.call("deliver_report", oid)
		_expect(cs.call("is_sgc_objective_done", oid), "objective %s done after delivery" % oid)
		if i < obj_ids.size() - 1:
			_expect(not ev.call("all_reports_delivered"), "not all reports after %d/4" % [i + 1])

	_expect(ev.call("all_reports_delivered"), "all reports delivered after all 4")
	_expect(gs.get("all_sgc_objectives_done") == true, "GameState.all_sgc_objectives_done synced to true")

	# Idempotency: delivering again doesn't break.
	ev.call("deliver_report", "report_air_crisis")
	_expect(ev.call("all_reports_delivered"), "still all reports after duplicate delivery")

	# --- 5. Return to Destiny, then new visit --------------------------------
	await cs.call("return_to_destiny")
	_expect(String(cs.call("get_phase")) == "idle", "phase is idle after return")

	# Reset for a fresh visit.
	ev.call("reset_visit")
	_expect(not ev.call("is_sgc_briefing_shown"), "briefing cleared after reset_visit")

	# --- 6. Personal moment --------------------------------------------------
	ev.call("reset")
	_expect(not ev.call("is_personal_moment_done"), "personal moment not done after reset")

	ev.call("start_personal_moment")
	_expect(ev.call("is_personal_moment_done"), "personal moment done after start")
	# Starting again should be a no-op.
	ev.call("start_personal_moment")
	_expect(ev.call("is_personal_moment_done"), "personal moment still done after duplicate call")

	# --- 7. Save round-trip --------------------------------------------------
	ev.call("reset")
	ev.call("start_personal_moment")
	ev.call("visit_npc", "general_oneill")
	ev.call("visit_npc", "dr_brightman")

	var saved: Dictionary = ev.call("serialize")
	_expect(saved.get("personal_moment_done", false) == true, "saved personal_moment_done is true")
	_expect((saved.get("visited_npcs", []) as Array).size() == 2, "saved 2 visited NPCs")

	ev.call("reset")
	_expect(not ev.call("is_personal_moment_done"), "personal moment cleared after reset")

	ev.call("deserialize", saved, 2)
	_expect(ev.call("is_personal_moment_done"), "restored personal_moment_done is true")
	_expect(ev.call("has_visited_npc", "general_oneill"), "restored visited O'Neill")
	_expect(ev.call("has_visited_npc", "dr_brightman"), "restored visited Brightman")
	_expect(not ev.call("has_visited_npc", "elis_mom"), "did not visit Eli's mom")

	# --- 8. SGCReportConsole interactable ------------------------------------
	ev.call("reset")
	cs.call("reset")
	await cs.call("activate_stone", "stone_01")

	var console_script: GDScript = load("res://scripts/sgc_report_console.gd")
	var console: Node = console_script.new()
	_expect(console != null, "SGCReportConsole can be instantiated")
	if console != null:
		console.set("objective_id", "report_air_crisis")
		console.set("console_label", "Air Crisis Report")
		console.call("_ready")
		_expect(String(console.call("get_prompt")) == "Deliver report: Air Crisis Report", "console prompt correct before delivery")
		console.call("interact", null)
		_expect(cs.call("is_sgc_objective_done", "report_air_crisis"), "report_air_crisis done after console interact")
		# Prompt should show delivered.
		var post_prompt: String = String(console.call("get_prompt"))
		_expect(post_prompt.find("delivered") >= 0, "console prompt shows delivered (got: %s)" % post_prompt)
		console.queue_free()

	# --- 9. EarthNPC interactable --------------------------------------------
	var earth_npc_script: GDScript = load("res://scripts/earth_npc.gd")
	var earth_npc: Node = earth_npc_script.new()
	_expect(earth_npc != null, "EarthNPC can be instantiated")
	if earth_npc != null:
		earth_npc.set("npc_id", "general_oneill")
		earth_npc.call("_ready")
		var npc_prompt: String = String(earth_npc.call("get_prompt"))
		_expect(npc_prompt.find("O'Neill") >= 0, "EarthNPC prompt mentions O'Neill (got: %s)" % npc_prompt)
		# Interact should fire dialog_started and narrate.
		earth_npc.call("interact", null)
		_expect(ev.call("has_visited_npc", "general_oneill"), "O'Neill marked as visited after interact")
		# Process an action (deliver report).
		earth_npc.call("process_action", "report_ship_status")
		_expect(cs.call("is_sgc_objective_done", "report_ship_status"), "report_ship_status done via EarthNPC action")
		earth_npc.queue_free()

	# --- 10. PersonalMomentTrigger interactable ------------------------------
	ev.call("reset")
	var trigger_script: GDScript = load("res://scripts/personal_moment_trigger.gd")
	var trigger: Node = trigger_script.new()
	_expect(trigger != null, "PersonalMomentTrigger can be instantiated")
	if trigger != null:
		trigger.call("_ready")
		_expect(String(trigger.call("get_prompt")) == "Visit Eli's mother", "trigger prompt correct")
		trigger.call("interact", null)
		_expect(ev.call("is_personal_moment_done"), "personal moment done after trigger interact")
		# Second interact should be a no-op.
		trigger.call("interact", null)
		_expect(ev.call("is_personal_moment_done"), "personal moment still done after duplicate trigger")
		var post_trigger_prompt: String = String(trigger.call("get_prompt"))
		_expect(post_trigger_prompt.find("already") >= 0, "trigger prompt shows already visited (got: %s)" % post_trigger_prompt)
		trigger.queue_free()

	# --- 11. Quest chain e5_earth step progression ---------------------------
	gs.call("reset")
	cs.call("reset")
	ev.call("reset")
	var ql: Node = root.get_node_or_null("QuestLog")
	if ql != null and ql.has_method("start_quest"):
		ql.call("start_quest", "e5_earth")
		var step_id: String = String(ql.call("active_step_id", "e5_earth"))
		_expect(step_id == "find_comm_stones", "e5_earth starts at find_comm_stones (got %s)" % step_id)

		# Simulate finding the stones.
		gs.set("comm_stones_found", true)
		if ql.has_method("advance"):
			ql.call("advance", "e5_earth")
		step_id = String(ql.call("active_step_id", "e5_earth"))
		_expect(step_id == "activate_stones", "advanced to activate_stones (got %s)" % step_id)

		# Simulate activating the stones.
		gs.set("stones_activated", true)
		if ql.has_method("advance"):
			ql.call("advance", "e5_earth")
		step_id = String(ql.call("active_step_id", "e5_earth"))
		_expect(step_id == "report_to_sgc", "advanced to report_to_sgc (got %s)" % step_id)

		# Simulate completing all SGC objectives.
		gs.set("all_sgc_objectives_done", true)
		if ql.has_method("advance"):
			ql.call("advance", "e5_earth")
		step_id = String(ql.call("active_step_id", "e5_earth"))
		_expect(step_id == "return_to_destiny", "advanced to return_to_destiny (got %s)" % step_id)

		# Simulate returning from Earth.
		gs.set("returned_from_earth", true)
		if ql.has_method("advance"):
			ql.call("advance", "e5_earth")
		step_id = String(ql.call("active_step_id", "e5_earth"))
		_expect(step_id == "earth_complete", "advanced to earth_complete (got %s)" % step_id)

	# --- 12. GameState save round-trip with EarthVisit vars -------------------
	gs.call("reset")
	gs.set("comm_stones_found", true)
	gs.set("stones_activated", true)
	gs.set("all_sgc_objectives_done", true)
	gs.set("returned_from_earth", true)
	var gs_saved: Dictionary = gs.call("serialize")
	_expect(gs_saved.get("comm_stones_found", false) == true, "GameState saves comm_stones_found")
	_expect(gs_saved.get("stones_activated", false) == true, "GameState saves stones_activated")
	_expect(gs_saved.get("all_sgc_objectives_done", false) == true, "GameState saves all_sgc_objectives_done")
	_expect(gs_saved.get("returned_from_earth", false) == true, "GameState saves returned_from_earth")
	gs.call("reset")
	gs.call("deserialize", gs_saved, 2)
	_expect(gs.get("comm_stones_found") == true, "GameState restores comm_stones_found")
	_expect(gs.get("stones_activated") == true, "GameState restores stones_activated")
	_expect(gs.get("all_sgc_objectives_done") == true, "GameState restores all_sgc_objectives_done")
	_expect(gs.get("returned_from_earth") == true, "GameState restores returned_from_earth")

	_report()
	if _failures.is_empty():
		quit(0)
	else:
		quit(1)


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
		print("  Failed:")
		for f in _failures:
			print("    - %s" % f)
	print("=== earth_visit smoke test %s ===" % ("PASSED" if _failures.is_empty() else "FAILED"))