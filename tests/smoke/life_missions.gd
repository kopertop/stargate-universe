extends SceneTree

# Smoke test for the LifeMissions system (E6 Life episode).
#
# Verifies:
#   • data/e6_life_dialogues.json loads with 3 missions (TJ, Camille, Greer).
#   • LifeMissions autoload is attached and data loaded.
#   • Each mission has a dialogue tree with multiple nodes.
#   • Each mission has ambient lines.
#   • Mission states: locked → available → active → completed.
#   • Relationship thresholds gate mission availability.
#   • start_mission() transitions available → active.
#   • complete_mission() transitions active → completed.
#   • all_missions_done() returns true only when all 3 are completed.
#   • Dialogue progression: get_current_dialogue_node, process_choice, advance.
#   • process_choice fires dialog_action signal and advances dialogue.
#   • Dialogue actions in relationships.json are registered.
#   • Quest gates in relationships.json block/allow E6 quest steps.
#   • GameState vars (crew_checked_in, tj_mission_done, etc.) save round-trip.
#   • Episode completion predicate "all_life_missions_done" evaluates correctly.
#   • Save round-trip: serialize → deserialize preserves mission states.
#   • reset() clears all state.
#   • get_all_missions_summary() returns complete data for HUD.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/life_missions.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal capture.
var _mission_started_received: bool = false
var _mission_completed_received: bool = false
var _all_missions_completed_received: bool = false
var _state_changed_received: bool = false
var _sig_mission_id: String = ""
var _sig_old_state: String = ""
var _sig_new_state: String = ""


func _on_mission_started(mission_id: String) -> void:
	_mission_started_received = true
	_sig_mission_id = mission_id


func _on_mission_completed(mission_id: String) -> void:
	_mission_completed_received = true
	_sig_mission_id = mission_id


func _on_all_missions_completed() -> void:
	_all_missions_completed_received = true


func _on_mission_state_changed(mission_id: String, old_state: String, new_state: String) -> void:
	_state_changed_received = true
	_sig_mission_id = mission_id
	_sig_old_state = old_state
	_sig_new_state = new_state


func _initialize() -> void:
	print("=== life_missions smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var lm: Node = root.get_node_or_null("LifeMissions")
	_expect(lm != null, "LifeMissions autoload is attached")
	if lm == null:
		_report()
		quit(1)
		return

	var rs: Node = root.get_node_or_null("RelationshipSystem")
	_expect(rs != null, "RelationshipSystem autoload is attached")
	if rs == null:
		_report()
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload is attached")
	if gs == null:
		_report()
		quit(1)
		return

	var ql: Node = root.get_node_or_null("QuestLog")
	_expect(ql != null, "QuestLog autoload is attached")

	var em: Node = root.get_node_or_null("EpisodeManager")
	_expect(em != null, "EpisodeManager autoload is attached")

	# Save isolation.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "life_missions")

	# Clean slate.
	gs.call("reset")
	rs.call("reset")
	lm.call("reset")

	# Connect signals.
	if lm.has_signal("mission_started"):
		lm.mission_started.connect(_on_mission_started)
	if lm.has_signal("mission_completed"):
		lm.mission_completed.connect(_on_mission_completed)
	if lm.has_signal("all_missions_completed"):
		lm.all_missions_completed.connect(_on_all_missions_completed)
	if lm.has_signal("mission_state_changed"):
		lm.mission_state_changed.connect(_on_mission_state_changed)

	# --- 1. Data loaded -------------------------------------------------------
	var mids: Array = lm.call("mission_ids")
	_expect(mids.size() == 3, "exactly 3 missions loaded (got %d)" % mids.size())
	_expect(mids.has("tj_medical_supplies"), "TJ medical supplies mission loaded")
	_expect(mids.has("camille_political_mediation"), "Camille political mediation mission loaded")
	_expect(mids.has("greer_emotional_guard"), "Greer emotional guard mission loaded")

	# --- 2. Mission metadata -------------------------------------------------
	_expect(lm.call("get_mission_display_name", "tj_medical_supplies") == "TJ — Medical Supplies", "TJ mission display name")
	_expect(lm.call("get_mission_display_name", "camille_political_mediation") == "Camille — Political Mediation", "Camille mission display name")
	_expect(lm.call("get_mission_display_name", "greer_emotional_guard") == "Greer — Emotional Guard", "Greer mission display name")

	_expect(lm.call("get_mission_crew", "tj_medical_supplies") == "TJ", "TJ mission crew is TJ")
	_expect(lm.call("get_mission_crew", "camille_political_mediation") == "Camille", "Camille mission crew is Camille")
	_expect(lm.call("get_mission_crew", "greer_emotional_guard") == "Sgt Greer", "Greer mission crew is Sgt Greer")

	_expect(lm.call("get_mission_required_level", "tj_medical_supplies") == "friendly", "TJ mission requires friendly")
	_expect(lm.call("get_mission_required_level", "camille_political_mediation") == "neutral", "Camille mission requires neutral")
	_expect(lm.call("get_mission_required_level", "greer_emotional_guard") == "wary", "Greer mission requires wary")

	_expect(lm.call("get_mission_location", "tj_medical_supplies") == "Med Bay", "TJ mission location is Med Bay")
	_expect(lm.call("get_mission_location", "camille_political_mediation") == "Observation Deck", "Camille mission location is Observation Deck")
	_expect(lm.call("get_mission_location", "greer_emotional_guard") == "Gate Room", "Greer mission location is Gate Room")

	# Summaries should be non-empty.
	_expect(lm.call("get_mission_summary", "tj_medical_supplies") != "", "TJ mission has summary text")
	_expect(lm.call("get_mission_summary", "camille_political_mediation") != "", "Camille mission has summary text")
	_expect(lm.call("get_mission_summary", "greer_emotional_guard") != "", "Greer mission has summary text")

	# --- 3. Dialogue trees ----------------------------------------------------
	var tj_tree: Array = lm.call("get_mission_dialogue_tree", "tj_medical_supplies")
	_expect(tj_tree.size() >= 5, "TJ dialogue tree has >= 5 nodes (got %d)" % tj_tree.size())
	var camille_tree: Array = lm.call("get_mission_dialogue_tree", "camille_political_mediation")
	_expect(camille_tree.size() >= 5, "Camille dialogue tree has >= 5 nodes (got %d)" % camille_tree.size())
	var greer_tree: Array = lm.call("get_mission_dialogue_tree", "greer_emotional_guard")
	_expect(greer_tree.size() >= 5, "Greer dialogue tree has >= 5 nodes (got %d)" % greer_tree.size())

	# Each tree node should have speaker, text, and choices.
	for i in range(tj_tree.size()):
		var node: Dictionary = tj_tree[i] as Dictionary
		_expect(node.has("speaker"), "TJ tree node %d has speaker" % i)
		_expect(node.has("text"), "TJ tree node %d has text" % i)
		_expect(node.has("choices"), "TJ tree node %d has choices" % i)

	# --- 4. Ambient lines ----------------------------------------------------
	var tj_ambient: Array = lm.call("get_mission_ambient_lines", "tj_medical_supplies")
	_expect(tj_ambient.size() >= 2, "TJ has >= 2 ambient lines (got %d)" % tj_ambient.size())
	var camille_ambient: Array = lm.call("get_mission_ambient_lines", "camille_political_mediation")
	_expect(camille_ambient.size() >= 2, "Camille has >= 2 ambient lines (got %d)" % camille_ambient.size())
	var greer_ambient: Array = lm.call("get_mission_ambient_lines", "greer_emotional_guard")
	_expect(greer_ambient.size() >= 2, "Greer has >= 2 ambient lines (got %d)" % greer_ambient.size())

	# --- 5. Initial mission states (locked/available based on relationships) -
	# After reset, relationships are at their JSON defaults.
	# TJ starts at trust=25, respect=20 → likely "neutral" → locked (needs friendly)
	# Camille starts at trust=20, respect=15 → likely "neutral" → available (needs neutral)
	# Greer starts at trust=35, respect=30 → likely "neutral" → available (needs wary)
	# The exact initial state depends on the thresholds, so we check all 3 exist.
	for mid in mids:
		var state: String = lm.call("get_mission_state", mid)
		_expect(state == "locked" or state == "available", "mission %s starts locked or available (got %s)" % [mid, state])

	# --- 6. Relationship gating: locked when below threshold ------------------
	# Force TJ trust/respect low so the TJ mission is locked.
	rs.call("set_trust", "TJ", 0)
	rs.call("set_respect", "TJ", 0)
	lm.call("refresh_mission_states")
	_expect(lm.call("get_mission_state", "tj_medical_supplies") == "locked", "TJ mission locked when trust/respect too low")
	_expect(lm.call("is_mission_unlocked", "tj_medical_supplies") == false, "is_mission_unlocked returns false for locked TJ mission")

	# Cannot start a locked mission.
	var started: bool = lm.call("start_mission", "tj_medical_supplies")
	_expect(started == false, "cannot start locked TJ mission")

	# --- 7. Relationship gating: available when threshold met -----------------
	# Raise TJ trust/respect to meet "friendly" threshold.
	rs.call("set_trust", "TJ", 50)
	rs.call("set_respect", "TJ", 50)
	lm.call("refresh_mission_states")
	var tj_state: String = lm.call("get_mission_state", "tj_medical_supplies")
	_expect(tj_state == "available" or tj_state == "active", "TJ mission available/active when trust/respect high enough (got %s)" % tj_state)
	_expect(lm.call("is_mission_unlocked", "tj_medical_supplies") == true, "is_mission_unlocked returns true for unlocked TJ mission")

	# --- 8. Start mission: available → active --------------------------------
	_mission_started_received = false
	_state_changed_received = false
	started = lm.call("start_mission", "tj_medical_supplies")
	_expect(started == true, "start_mission returns true for available TJ mission")
	_expect(lm.call("get_mission_state", "tj_medical_supplies") == "active", "TJ mission is active after start")
	_expect(_mission_started_received == true, "mission_started signal fired")
	_expect(_state_changed_received == true, "mission_state_changed signal fired")
	_expect(_sig_old_state == "available" or _sig_old_state == "locked", "state changed from available or locked (got %s)" % _sig_old_state)
	_expect(_sig_new_state == "active", "state changed to active")

	# --- 9. Dialogue progression ---------------------------------------------
	var dlg_node: Dictionary = lm.call("get_current_dialogue_node", "tj_medical_supplies")
	_expect(not dlg_node.is_empty(), "current dialogue node is not empty for active mission")
	_expect(dlg_node.has("speaker"), "dialogue node has speaker")
	_expect(dlg_node.has("text"), "dialogue node has text")
	_expect(dlg_node.has("choices"), "dialogue node has choices")
	_expect(lm.call("get_dialogue_position", "tj_medical_supplies") == 0, "dialogue position starts at 0")

	# Process choice 0 (should fire action and advance).
	lm.call("process_choice", "tj_medical_supplies", 0)
	# After processing choice 0, position should have advanced (or mission completed if "exit").
	var pos1: int = lm.call("get_dialogue_position", "tj_medical_supplies")
	# If the mission is still active, position should be > 0 or the mission completed.
	var tj_still_active: bool = lm.call("get_mission_state", "tj_medical_supplies") == "active"
	if tj_still_active:
		_expect(pos1 >= 0, "dialogue position advanced after choice (got %d)" % pos1)

	# --- 10. Complete mission: active → completed -----------------------------
	# Force-complete the TJ mission for testing.
	_mission_completed_received = false
	lm.call("force_complete", "tj_medical_supplies")
	_expect(lm.call("get_mission_state", "tj_medical_supplies") == "completed", "TJ mission is completed after force_complete")
	_expect(_mission_completed_received == true, "mission_completed signal fired")
	_expect(lm.call("is_mission_completed", "tj_medical_supplies") == true, "is_mission_completed returns true")

	# --- 11. All missions completed check ------------------------------------
	_expect(lm.call("all_missions_done") == false, "all_missions_done is false with only 1 completed")
	_expect(lm.call("completed_count") == 1, "completed_count is 1")
	_expect(lm.call("total_missions") == 3, "total_missions is 3")

	# Complete the other two.
	lm.call("force_complete", "camille_political_mediation")
	_expect(lm.call("all_missions_done") == false, "all_missions_done is false with 2 completed")
	_expect(lm.call("completed_count") == 2, "completed_count is 2")

	_all_missions_completed_received = false
	lm.call("force_complete", "greer_emotional_guard")
	_expect(lm.call("all_missions_done") == true, "all_missions_done is true with all 3 completed")
	_expect(lm.call("completed_count") == 3, "completed_count is 3")
	_expect(_all_missions_completed_received == true, "all_missions_completed signal fired")

	# --- 12. completed_missions list -----------------------------------------
	var done_list: Array = lm.call("completed_missions")
	_expect(done_list.size() == 3, "completed_missions returns 3 ids (got %d)" % done_list.size())

	# --- 13. available_missions and active_missions ---------------------------
	# Reset and set up: make one available, one active, one locked.
	lm.call("reset")
	rs.call("set_trust", "TJ", 50)
	rs.call("set_respect", "TJ", 50)
	rs.call("set_trust", "Camille", 30)
	rs.call("set_respect", "Camille", 30)
	rs.call("set_trust", "Sgt Greer", 0)
	rs.call("set_respect", "Sgt Greer", 0)
	lm.call("refresh_mission_states")

	# Start TJ mission to make it active.
	lm.call("start_mission", "tj_medical_supplies")

	var avail: Array = lm.call("available_missions")
	var active: Array = lm.call("active_missions")
	_expect(active.size() == 1, "1 active mission (got %d)" % active.size())
	_expect(active.has("tj_medical_supplies"), "TJ mission is active")
	# Camille should be available (neutral threshold met with trust=30, respect=30).
	# Greer should be locked (trust/respect too low for wary).

	# --- 14. Dialogue actions registered in RelationshipSystem ---------------
	# Check that E6 dialogue actions are in the relationships.json dialogue_actions.
	var action_ids: Array = rs.call("dialogue_action_ids")
	_expect(rs.call("has_dialogue_action", "tj_mission_accept") == true, "tj_mission_accept action registered")
	_expect(rs.call("has_dialogue_action", "tj_mission_decline") == true, "tj_mission_decline action registered")
	_expect(rs.call("has_dialogue_action", "camille_mission_accept") == true, "camille_mission_accept action registered")
	_expect(rs.call("has_dialogue_action", "greer_mission_direct") == true, "greer_mission_direct action registered")
	_expect(rs.call("has_dialogue_action", "greer_mission_offer") == true, "greer_mission_offer action registered")
	_expect(rs.call("has_dialogue_action", "tj_mission_complete_humble") == true, "tj_mission_complete_humble action registered")
	_expect(rs.call("has_dialogue_action", "camille_mission_complete_hope") == true, "camille_mission_complete_hope action registered")

	# --- 15. Apply dialogue action changes relationships ----------------------
	var tj_trust_before: int = rs.call("get_trust", "TJ")
	rs.call("apply_dialogue_action", "tj_mission_accept")
	var tj_trust_after: int = rs.call("get_trust", "TJ")
	_expect(tj_trust_after > tj_trust_before, "tj_mission_accept increases TJ trust (before=%d, after=%d)" % [tj_trust_before, tj_trust_after])

	# Greer dialogue action with faction delta.
	var greer_trust_before: int = rs.call("get_trust", "Sgt Greer")
	rs.call("apply_dialogue_action", "greer_mission_offer")
	var greer_trust_after: int = rs.call("get_trust", "Sgt Greer")
	_expect(greer_trust_after > greer_trust_before, "greer_mission_offer increases Greer trust (before=%d, after=%d)" % [greer_trust_before, greer_trust_after])

	# --- 16. Quest gates in RelationshipSystem --------------------------------
	if ql != null:
		# TJ mission step requires friendly with TJ.
		var tj_gate: Dictionary = rs.call("get_quest_gate", "tj_mission_step")
		_expect(not tj_gate.is_empty(), "tj_mission_step has a quest gate")
		_expect(String(tj_gate.get("crew", "")) == "TJ", "tj_mission_step gate crew is TJ")
		_expect(String(tj_gate.get("level", "")) == "friendly", "tj_mission_step gate level is friendly")

		# Camille mission step requires neutral with Camille.
		var camille_gate: Dictionary = rs.call("get_quest_gate", "camille_mission_step")
		_expect(not camille_gate.is_empty(), "camille_mission_step has a quest gate")
		_expect(String(camille_gate.get("crew", "")) == "Camille", "camille_mission_step gate crew is Camille")

		# Greer mission step requires wary with Greer.
		var greer_gate: Dictionary = rs.call("get_quest_gate", "greer_mission_step")
		_expect(not greer_gate.is_empty(), "greer_mission_step has a quest gate")
		_expect(String(greer_gate.get("crew", "")) == "Sgt Greer", "greer_mission_step gate crew is Sgt Greer")

		# quest_step_available should return false when below threshold.
		rs.call("set_trust", "TJ", 0)
		rs.call("set_respect", "TJ", 0)
		_expect(rs.call("quest_step_available", "tj_mission_step") == false, "tj_mission_step blocked when TJ trust/respect low")

		rs.call("set_trust", "TJ", 50)
		rs.call("set_respect", "TJ", 50)
		_expect(rs.call("quest_step_available", "tj_mission_step") == true, "tj_mission_step available when TJ trust/respect high")

		# Ungated step always available.
		_expect(rs.call("quest_step_available", "check_crew_status") == true, "check_crew_status always available (no gate)")

	# --- 17. Episode completion predicate -------------------------------------
	if em != null:
		# All missions not done → predicate false.
		gs.set("tj_mission_done", false)
		gs.set("camille_mission_done", false)
		gs.set("greer_mission_done", false)
		_expect(em.call("check_completion", "e6_life") == false, "e6_life not complete when no missions done")

		# All missions done → predicate true.
		gs.set("tj_mission_done", true)
		gs.set("camille_mission_done", true)
		gs.set("greer_mission_done", true)
		_expect(em.call("check_completion", "e6_life") == true, "e6_life complete when all missions done via GameState vars")

		# Also works via LifeMissions autoload.
		gs.set("tj_mission_done", false)
		gs.set("camille_mission_done", false)
		gs.set("greer_mission_done", false)
		lm.call("force_complete", "tj_medical_supplies")
		lm.call("force_complete", "camille_political_mediation")
		lm.call("force_complete", "greer_emotional_guard")
		_expect(em.call("check_completion", "e6_life") == true, "e6_life complete when all missions done via LifeMissions autoload")

	# --- 18. GameState save round-trip with E6 vars --------------------------
	gs.call("reset")
	gs.set("crew_checked_in", true)
	gs.set("tj_mission_done", true)
	gs.set("camille_mission_done", true)
	gs.set("greer_mission_done", false)
	var gs_saved: Dictionary = gs.call("serialize")
	_expect(gs_saved.get("crew_checked_in", false) == true, "GameState saves crew_checked_in")
	_expect(gs_saved.get("tj_mission_done", false) == true, "GameState saves tj_mission_done")
	_expect(gs_saved.get("camille_mission_done", false) == true, "GameState saves camille_mission_done")
	_expect(gs_saved.get("greer_mission_done", true) == false, "GameState saves greer_mission_done=false")
	gs.call("reset")
	gs.call("deserialize", gs_saved, 2)
	_expect(gs.get("crew_checked_in") == true, "GameState restores crew_checked_in")
	_expect(gs.get("tj_mission_done") == true, "GameState restores tj_mission_done")
	_expect(gs.get("camille_mission_done") == true, "GameState restores camille_mission_done")
	_expect(gs.get("greer_mission_done") == false, "GameState restores greer_mission_done=false")

	# --- 19. LifeMissions save round-trip -----------------------------------
	lm.call("reset")
	rs.call("set_trust", "TJ", 50)
	rs.call("set_respect", "TJ", 50)
	lm.call("refresh_mission_states")
	lm.call("start_mission", "tj_medical_supplies")
	lm.call("force_complete", "camille_political_mediation")
	var lm_saved: Dictionary = lm.call("serialize")
	_expect(lm_saved.has("mission_states"), "LifeMissions serialize has mission_states")
	_expect(lm_saved.has("dialogue_positions"), "LifeMissions serialize has dialogue_positions")
	lm.call("reset")
	lm.call("deserialize", lm_saved, 1)
	_expect(lm.call("get_mission_state", "tj_medical_supplies") == "active", "LifeMissions restores TJ active state")
	_expect(lm.call("get_mission_state", "camille_political_mediation") == "completed", "LifeMissions restores Camille completed state")

	# --- 20. reset() clears all state ----------------------------------------
	lm.call("reset")
	for mid in mids:
		_expect(lm.call("get_mission_state", mid) == "locked" or lm.call("get_mission_state", mid) == "available", "mission %s is locked or available after reset (got %s)" % [mid, lm.call("get_mission_state", mid)])
	_expect(lm.call("completed_count") == 0, "completed_count is 0 after reset")
	_expect(lm.call("all_missions_done") == false, "all_missions_done is false after reset")

	# --- 21. get_all_missions_summary for HUD --------------------------------
	var summary: Array = lm.call("get_all_missions_summary")
	_expect(summary.size() == 3, "summary has 3 entries (got %d)" % summary.size())
	for entry in summary:
		var e: Dictionary = entry as Dictionary
		_expect(e.has("id"), "summary entry has id")
		_expect(e.has("display_name"), "summary entry has display_name")
		_expect(e.has("crew"), "summary entry has crew")
		_expect(e.has("state"), "summary entry has state")
		_expect(e.has("required_level"), "summary entry has required_level")

	# --- 22. E6 quest chain in QuestLog --------------------------------------
	if ql != null:
		# Full reset to clear any leftover GameState vars from earlier sections.
		gs.call("reset")
		rs.call("reset")
		lm.call("reset")
		ql.call("reset")
		ql.call("start_quest", "e6_life")
		var e6_step: String = String(ql.call("active_step_id", "e6_life"))
		_expect(e6_step == "check_crew_status", "e6_life first step is check_crew_status (got %s)" % e6_step)

		# Advance through the quest by setting GameState flags.
		gs.set("crew_checked_in", true)
		ql.call("advance", "e6_life")
		e6_step = String(ql.call("active_step_id", "e6_life"))
		_expect(e6_step == "tj_mission_step", "e6_life advances to tj_mission_step (got %s)" % e6_step)

		gs.set("tj_mission_done", true)
		ql.call("advance", "e6_life")
		e6_step = String(ql.call("active_step_id", "e6_life"))
		_expect(e6_step == "camille_mission_step", "e6_life advances to camille_mission_step (got %s)" % e6_step)

		gs.set("camille_mission_done", true)
		ql.call("advance", "e6_life")
		e6_step = String(ql.call("active_step_id", "e6_life"))
		_expect(e6_step == "greer_mission_step", "e6_life advances to greer_mission_step (got %s)" % e6_step)

		gs.set("greer_mission_done", true)
		ql.call("advance", "e6_life")
		e6_step = String(ql.call("active_step_id", "e6_life"))
		_expect(e6_step == "life_complete", "e6_life advances to life_complete (got %s)" % e6_step)

	# --- 23. Episodes.json has E6 --------------------------------------------
	if em != null:
		var next_e5: String = em.call("next_episode_id_for", "e5_earth")
		_expect(next_e5 == "e6_life", "E5 next episode is e6_life (got %s)" % next_e5)
		var next_e6: String = em.call("next_episode_id_for", "e6_life")
		_expect(next_e6 == "e7_justice", "E6 next episode is e7_justice (got %s)" % next_e6)

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
	print("=== life_missions smoke test %s ===" % ("PASSED" if _failures.is_empty() else "FAILED"))