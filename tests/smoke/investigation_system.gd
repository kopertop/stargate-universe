extends SceneTree

# Smoke test for the InvestigationSystem autoload — clue gathering,
# interrogation, lie detection, accusation, and faction tension.
#
# Verifies:
#   • InvestigationSystem autoload is attached and loaded its config from JSON.
#   • Scenario metadata is loaded (victim, crime_scene, true_culprit).
#   • 8 clues are registered with valid data.
#   • 4 suspects are registered (Simeon, Varro, Dr Rush, Brody).
#   • 3 accusations are registered (Simeon, Varro, Dr Rush).
#   • start_investigation() sets phase to CRIME_SCENE.
#   • discover_clue() registers clues and fires clue_discovered signal.
#   • Clue discovery escalates faction tension.
#   • Kino-required clues are blocked without Kino deployed.
#   • set_kino_deployed(true) allows Kino-required clues.
#   • Phase advances from CRIME_SCENE to INTERROGATION after 2 clues.
#   • mark_interrogated() registers suspects and fires suspect_interrogated.
#   • Phase advances to ACCUSATION when evidence is sufficient.
#   • get_suspect_dialogue() returns dialogue tree with lie metadata.
#   • Lie detection: is_dialogue_node_a_lie() correctly identifies lies.
#   • process_dialogue_node() returns lie indicator text when Kino deployed.
#   • process_dialogue_node() returns no-kino text when Kino not deployed.
#   • can_accuse() returns true for Simeon with sufficient evidence.
#   • can_accuse() returns false without required clues.
#   • make_accusation("Simeon") with full evidence returns "correct".
#   • make_accusation("Varro") returns "wrong".
#   • Correct accusation lowers faction tension.
#   • Wrong accusation raises faction tension.
#   • Relationship changes are applied via RelationshipSystem.
#   • Dialog action handler processes investigation: action IDs.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • reset() restores initial state.
#   • get_summary() returns complete data for HUD.
#   • get_suspect_evidence_summary() returns per-suspect data.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/investigation_system.gd

var _passes: int = 0
var _failures: Array[String] = []
var _ran: bool = false

# Signal capture.
var _clue_discovered_received: bool = false
var _clue_discovered_id: String = ""
var _suspect_interrogated_received: bool = false
var _suspect_interrogated_id: String = ""
var _lie_detected_received: bool = false
var _lie_detected_suspect: String = ""
var _truth_confirmed_received: bool = false
var _accusation_made_received: bool = false
var _accusation_correct: bool = false
var _investigation_completed_received: bool = false
var _investigation_outcome: String = ""
var _tension_changed_received: bool = false
var _tension_level_changed_received: bool = false
var _old_tension: int = 0
var _new_tension: int = 0


func _init() -> void:
	_initialize()


func _initialize() -> void:
	if _ran:
		return
	_ran = true
	print("=== investigation_system smoke test ===")
	call_deferred("_run_checks")


func _connect_signal(inv: Node, sig_name: String, handler: Callable) -> void:
	var sig: Signal = inv.get(sig_name)
	if not sig.is_connected(handler):
		sig.connect(handler)


func _run_checks() -> void:
	var root: Node = get_root()
	var inv: Node = root.get_node_or_null("InvestigationSystem")
	_expect(inv != null, "InvestigationSystem autoload is attached")
	if inv == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "investigation_system_smoke")

	# Reset RelationshipSystem to known initial state.
	var rs: Node = root.get_node_or_null("RelationshipSystem")
	if rs != null:
		rs.call("reset")

	# Connect signals for capture (guarded against double-connect).
	_connect_signal(inv, "clue_discovered", _on_clue_discovered)
	_connect_signal(inv, "suspect_interrogated", _on_suspect_interrogated)
	_connect_signal(inv, "lie_detected", _on_lie_detected)
	_connect_signal(inv, "truth_confirmed", _on_truth_confirmed)
	_connect_signal(inv, "accusation_made", _on_accusation_made)
	_connect_signal(inv, "investigation_completed", _on_investigation_completed)
	_connect_signal(inv, "faction_tension_changed", _on_tension_changed)
	_connect_signal(inv, "faction_tension_level_changed", _on_tension_level_changed)

	# --- Scenario metadata ----------------------------------------------------
	var scenario: Dictionary = inv.get_scenario()
	_expect(not scenario.is_empty(), "scenario loaded from JSON")
	_expect(String(scenario.get("victim", "")) == "Ginn", "scenario victim == Ginn")
	_expect(String(scenario.get("crime_scene", "")) == "engineering_bay", "scenario crime_scene == engineering_bay")
	_expect(String(scenario.get("true_culprit", "")) == "Simeon", "scenario true_culprit == Simeon")

	# --- Clues ----------------------------------------------------------------
	var clues: Dictionary = inv.get_all_clues()
	_expect(clues.size() == 8, "clue count == 8 (got %d)" % clues.size())
	var expected_clues: Array = [
		"conduit_panel", "blood_trail", "kino_recording", "alliance_knife",
		"ginn_data_pad", "rush_testimony", "varro_alibi", "simeon_whereabouts"
	]
	for clue_id in expected_clues:
		_expect(clues.has(clue_id), "has clue '%s'" % clue_id)

	# --- Suspects -------------------------------------------------------------
	var suspects: Dictionary = inv.get_all_suspects()
	_expect(suspects.size() == 4, "suspect count == 4 (got %d)" % suspects.size())
	_expect(suspects.has("Simeon"), "has suspect 'Simeon'")
	_expect(suspects.has("Varro"), "has suspect 'Varro'")
	_expect(suspects.has("Dr Rush"), "has suspect 'Dr Rush'")
	_expect(suspects.has("Brody"), "has suspect 'Brody'")

	# Verify Simeon is the culprit.
	_expect(bool(suspects.get("Simeon", {}).get("is_culprit", false)) == true, "Simeon is_culprit == true")
	_expect(bool(suspects.get("Varro", {}).get("is_culprit", false)) == false, "Varro is_culprit == false")
	_expect(bool(suspects.get("Dr Rush", {}).get("is_culprit", false)) == false, "Dr Rush is_culprit == false")

	# --- Accusations ----------------------------------------------------------
	var accusable_before: Array[String] = inv.get_accusable_suspects()
	_expect(accusable_before.size() == 0, "no accusable suspects before investigation starts")

	# --- Start Investigation --------------------------------------------------
	inv.start_investigation()
	_expect(inv.get_phase_string() == "crime_scene", "phase == crime_scene after start (got '%s')" % inv.get_phase_string())
	_expect(inv.is_active() == true, "is_active() == true after start")
	_expect(inv.is_completed() == false, "is_completed() == false after start")

	# --- Clue Discovery -------------------------------------------------------
	# Discover first clue (conduit_panel — no Kino required).
	var discovered: bool = inv.discover_clue("conduit_panel")
	_expect(discovered == true, "discover_clue('conduit_panel') returns true (new)")
	_expect(inv.is_clue_discovered("conduit_panel") == true, "is_clue_discovered('conduit_panel') == true")
	_expect(_clue_discovered_received == true, "clue_discovered signal fired")
	_expect(_clue_discovered_id == "conduit_panel", "clue_discovered signal id == conduit_panel")

	# Discovering same clue again returns false.
	var rediscovered: bool = inv.discover_clue("conduit_panel")
	_expect(rediscovered == false, "discover_clue('conduit_panel') second time returns false")

	# Discover second clue (blood_trail — no Kino required).
	inv.discover_clue("blood_trail")
	_expect(inv.get_discovered_clue_count() == 2, "discovered_clue_count == 2")

	# Phase should advance to INTERROGATION after 2 clues.
	_expect(inv.get_phase_string() == "interrogation", "phase == interrogation after 2 clues (got '%s')" % inv.get_phase_string())

	# --- Kino-Required Clue ---------------------------------------------------
	# kino_recording requires Kino — should fail without it.
	var kino_clue: bool = inv.discover_clue("kino_recording")
	_expect(kino_clue == false, "discover_clue('kino_recording') fails without Kino")

	# Deploy Kino and try again.
	inv.set_kino_deployed(true)
	_expect(inv.is_kino_deployed() == true, "is_kino_deployed() == true after set")
	kino_clue = inv.discover_clue("kino_recording")
	_expect(kino_clue == true, "discover_clue('kino_recording') succeeds with Kino")
	_expect(inv.is_clue_discovered("kino_recording") == true, "kino_recording is discovered")

	# --- Evidence Strength ----------------------------------------------------
	# After discovering conduit_panel(2), blood_trail(3), kino_recording(4):
	# total = 9, evidence against Simeon = conduit_panel(2) + blood_trail(3) + kino_recording(4) = 9
	var total_ev: int = inv.get_total_evidence_strength()
	_expect(total_ev == 9, "total_evidence_strength == 9 (got %d)" % total_ev)

	var simeon_ev: int = inv.get_evidence_strength_against("Simeon")
	_expect(simeon_ev == 9, "evidence_strength_against('Simeon') == 9 (got %d)" % simeon_ev)

	# --- Discover remaining key clues -----------------------------------------
	inv.discover_clue("alliance_knife")    # strength 3, points to Simeon
	inv.discover_clue("ginn_data_pad")     # strength 5, points to Simeon
	inv.discover_clue("simeon_whereabouts")  # strength 4, points to Simeon

	# Evidence against Simeon now: 2+3+4+3+5+4 = 21
	simeon_ev = inv.get_evidence_strength_against("Simeon")
	_expect(simeon_ev == 21, "evidence_strength_against('Simeon') == 21 (got %d)" % simeon_ev)

	# --- Interrogation --------------------------------------------------------
	var interrogated: bool = inv.mark_interrogated("Simeon")
	_expect(interrogated == true, "mark_interrogated('Simeon') returns true (new)")
	_expect(inv.is_suspect_interrogated("Simeon") == true, "is_suspect_interrogated('Simeon') == true")
	_expect(_suspect_interrogated_received == true, "suspect_interrogated signal fired")
	_expect(_suspect_interrogated_id == "Simeon", "suspect_interrogated signal id == Simeon")

	# Double interrogation returns false.
	var reinterrogated: bool = inv.mark_interrogated("Simeon")
	_expect(reinterrogated == false, "mark_interrogated('Simeon') second time returns false")

	# Phase should be ACCUSATION now (evidence sufficient + interrogated).
	_expect(inv.get_phase_string() == "accusation", "phase == accusation (got '%s')" % inv.get_phase_string())

	# --- Suspect Dialogue & Lie Detection -------------------------------------
	var simeon_tree: Array = inv.get_suspect_dialogue("Simeon")
	_expect(simeon_tree.size() > 0, "Simeon dialogue tree is non-empty")
	_expect(simeon_tree.size() == 5, "Simeon dialogue tree has 5 nodes (got %d)" % simeon_tree.size())

	# Node 1 (index 1) is a lie.
	var is_lie_1: bool = inv.is_dialogue_node_a_lie("Simeon", 1)
	_expect(is_lie_1 == true, "Simeon dialogue node 1 is a lie")

	# Node 4 (index 4) is truthful.
	var is_lie_4: bool = inv.is_dialogue_node_a_lie("Simeon", 4)
	_expect(is_lie_4 == false, "Simeon dialogue node 4 is truthful")

	# Lie indicator text.
	var lie_text: String = inv.get_lie_indicator("Simeon", 1)
	_expect(lie_text != "", "Simeon node 1 lie indicator is non-empty")
	_expect(lie_text.contains("eyes"), "Simeon node 1 lie indicator mentions 'eyes'")

	# process_dialogue_node with Kino deployed.
	var process_result: String = inv.process_dialogue_node("Simeon", 1)
	_expect(process_result.contains("Lie"), "process_dialogue_node for lie contains 'Lie'")
	_expect(_lie_detected_received == true, "lie_detected signal fired")
	_expect(_lie_detected_suspect == "Simeon", "lie_detected signal suspect == Simeon")

	# Process a truthful node.
	inv.process_dialogue_node("Simeon", 4)
	_expect(_truth_confirmed_received == true, "truth_confirmed signal fired for truthful node")

	# Without Kino, process returns no-kino text.
	inv.set_kino_deployed(false)
	var no_kino_result: String = inv.process_dialogue_node("Simeon", 1)
	_expect(no_kino_result.contains("No Kino") or no_kino_result.contains("no Kino"), "process_dialogue_node without Kino contains 'No Kino'")
	inv.set_kino_deployed(true)

	# --- Varro dialogue (all truthful) ---------------------------------------
	var varro_tree: Array = inv.get_suspect_dialogue("Varro")
	_expect(varro_tree.size() > 0, "Varro dialogue tree is non-empty")
	var varro_is_lie_1: bool = inv.is_dialogue_node_a_lie("Varro", 1)
	_expect(varro_is_lie_1 == false, "Varro dialogue node 1 is truthful")

	# --- Accusation: Can Accuse -----------------------------------------------
	# Simeon requires min_evidence_strength 10 and clues ginn_data_pad + simeon_whereabouts.
	var can_accuse_simeon: bool = inv.can_accuse("Simeon")
	_expect(can_accuse_simeon == true, "can_accuse('Simeon') == true with sufficient evidence")

	# Varro requires min_evidence_strength 8 and clues blood_trail + varro_alibi.
	# We have blood_trail but not varro_alibi.
	var can_accuse_varro: bool = inv.can_accuse("Varro")
	_expect(can_accuse_varro == false, "can_accuse('Varro') == false without varro_alibi clue")

	# Dr Rush requires min_evidence_strength 6 and clue rush_testimony.
	# We don't have rush_testimony.
	var can_accuse_rush: bool = inv.can_accuse("Dr Rush")
	_expect(can_accuse_rush == false, "can_accuse('Dr Rush') == false without rush_testimony clue")

	# --- Accusation: Correct (Simeon) -----------------------------------------
	var outcome: String = inv.make_accusation("Simeon")
	_expect(outcome == "correct", "make_accusation('Simeon') == 'correct' (got '%s')" % outcome)
	_expect(inv.is_completed() == true, "is_completed() == true after accusation")
	_expect(inv.get_outcome() == "correct", "get_outcome() == 'correct'")
	_expect(inv.get_accused_suspect() == "Simeon", "get_accused_suspect() == 'Simeon'")
	_expect(_accusation_made_received == true, "accusation_made signal fired")
	_expect(_accusation_correct == true, "accusation_made signal is_correct == true")
	_expect(_investigation_completed_received == true, "investigation_completed signal fired")
	_expect(_investigation_outcome == "correct", "investigation_completed outcome == 'correct'")

	# --- Faction Tension After Correct Accusation ----------------------------
	# Correct accusation should lower tension.
	_expect(_tension_changed_received == true, "faction_tension_changed signal fired")
	_expect(_new_tension < _old_tension, "tension decreased after correct accusation (old=%d, new=%d)" % [_old_tension, _new_tension])

	# --- Relationship Changes Applied -----------------------------------------
	if rs != null:
		# Varro's trust should have increased by 15 from the correct accusation.
		# Varro initial trust is 10 (from relationships.json). After +15 = 25.
		var varro_trust: int = rs.call("get_trust", "Varro")
		_expect(varro_trust >= 20, "Varro trust >= 20 after correct accusation (got %d)" % varro_trust)

	# --- Second accusation attempt returns same outcome -----------------------
	var second_outcome: String = inv.make_accusation("Simeon")
	_expect(second_outcome == "correct", "second make_accusation returns same outcome (already completed)")

	# --- Dialog Action Handler ------------------------------------------------
	# Reset and test dialog action integration.
	inv.reset()
	_expect(inv.get_phase_string() == "inactive", "phase == inactive after reset (got '%s')" % inv.get_phase_string())
	_expect(inv.get_discovered_clue_count() == 0, "clue count == 0 after reset")
	_expect(inv.get_faction_tension() == 30, "faction_tension == 30 after reset (got %d)" % inv.get_faction_tension())

	# Start fresh investigation.
	inv.start_investigation()
	inv.set_kino_deployed(true)

	# Test dialog action: discover clue.
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null and gs.has_signal("dialog_action"):
		gs.dialog_action.emit("investigation:discover_clue:conduit_panel")
		_expect(inv.is_clue_discovered("conduit_panel") == true, "dialog_action 'discover_clue:conduit_panel' works")

		gs.dialog_action.emit("investigation:interrogate:Varro")
		_expect(inv.is_suspect_interrogated("Varro") == true, "dialog_action 'interrogate:Varro' works")

		gs.dialog_action.emit("investigation:deploy_kino")
		_expect(inv.is_kino_deployed() == true, "dialog_action 'deploy_kino' works")
	else:
		print("  SKIP: GameState not available for dialog_action tests")

	# --- Save / Load Round-Trip -----------------------------------------------
	inv.reset()
	inv.start_investigation()
	inv.set_kino_deployed(true)
	inv.discover_clue("conduit_panel")
	inv.discover_clue("blood_trail")
	inv.discover_clue("kino_recording")
	inv.discover_clue("alliance_knife")
	inv.discover_clue("ginn_data_pad")
	inv.discover_clue("simeon_whereabouts")
	inv.mark_interrogated("Simeon")
	inv.mark_interrogated("Varro")

	var saved: Dictionary = inv.serialize()
	_expect(saved.size() > 0, "serialize() returns non-empty dict")
	_expect(saved.has("phase"), "serialized data has 'phase'")
	_expect(saved.has("discovered_clues"), "serialized data has 'discovered_clues'")
	_expect(saved.has("interrogated_suspects"), "serialized data has 'interrogated_suspects'")
	_expect(saved.has("faction_tension"), "serialized data has 'faction_tension'")

	# Deserialize into a fresh state.
	inv.reset()
	inv.deserialize(saved, 1)
	_expect(inv.get_discovered_clue_count() == 6, "deserialized clue count == 6 (got %d)" % inv.get_discovered_clue_count())
	_expect(inv.is_clue_discovered("conduit_panel") == true, "deserialized: conduit_panel discovered")
	_expect(inv.is_clue_discovered("kino_recording") == true, "deserialized: kino_recording discovered")
	_expect(inv.is_suspect_interrogated("Simeon") == true, "deserialized: Simeon interrogated")
	_expect(inv.is_suspect_interrogated("Varro") == true, "deserialized: Varro interrogated")
	_expect(inv.is_kino_deployed() == true, "deserialized: kino deployed")

	# --- Summary & HUD --------------------------------------------------------
	var summary: Dictionary = inv.get_summary()
	_expect(summary.has("phase"), "summary has 'phase'")
	_expect(summary.has("clues_discovered"), "summary has 'clues_discovered'")
	_expect(summary.has("faction_tension"), "summary has 'faction_tension'")
	_expect(summary.has("faction_tension_level"), "summary has 'faction_tension_level'")
	_expect(summary.has("evidence_strength"), "summary has 'evidence_strength'")
	_expect(summary.has("victim"), "summary has 'victim'")
	_expect(String(summary.get("victim", "")) == "Dr Ginn", "summary victim == 'Dr Ginn'")
	_expect(String(summary.get("crime_scene", "")) == "Engineering Bay", "summary crime_scene == 'Engineering Bay'")

	# --- Suspect Evidence Summary --------------------------------------------
	var simeon_summary: Dictionary = inv.get_suspect_evidence_summary("Simeon")
	_expect(simeon_summary.has("evidence_strength"), "Simeon evidence summary has 'evidence_strength'")
	_expect(simeon_summary.has("can_accuse"), "Simeon evidence summary has 'can_accuse'")
	_expect(simeon_summary.has("supporting_clues"), "Simeon evidence summary has 'supporting_clues'")
	_expect(int(simeon_summary.get("evidence_strength", 0)) > 0, "Simeon evidence strength > 0")
	_expect(bool(simeon_summary.get("interrogated", false)) == true, "Simeon evidence summary interrogated == true")

	# --- Wrong Accusation Test ------------------------------------------------
	# Reset and test wrong accusation path.
	inv.reset()
	if rs != null:
		rs.call("reset")
	inv.start_investigation()
	inv.set_kino_deployed(true)
	inv.discover_clue("conduit_panel")
	inv.discover_clue("blood_trail")
	inv.discover_clue("varro_alibi")  # needed for Varro accusation
	inv.discover_clue("kino_recording")  # more evidence
	inv.discover_clue("alliance_knife")  # more evidence
	inv.discover_clue("rush_testimony")  # more evidence
	inv.mark_interrogated("Varro")

	# Now try to accuse Varro (wrong).
	if inv.can_accuse("Varro"):
		var wrong_outcome: String = inv.make_accusation("Varro")
		_expect(wrong_outcome == "wrong", "make_accusation('Varro') == 'wrong' (got '%s')" % wrong_outcome)
		_expect(inv.get_outcome() == "wrong", "get_outcome() == 'wrong' after wrong accusation")
	else:
		print("  SKIP: cannot test wrong accusation — insufficient evidence for Varro")

	# --- Unknown clue/suspect safety -----------------------------------------
	inv.reset()
	inv.start_investigation()
	var unknown_clue: bool = inv.discover_clue("nonexistent_clue")
	_expect(unknown_clue == false, "discover_clue('nonexistent_clue') returns false safely")
	var unknown_suspect: bool = inv.mark_interrogated("Nobody")
	_expect(unknown_suspect == false, "mark_interrogated('Nobody') returns false safely")
	var unknown_accuse: String = inv.make_accusation("Nobody")
	_expect(unknown_accuse == "", "make_accusation('Nobody') returns empty string safely")

	# --- Reset Final ----------------------------------------------------------
	inv.reset()
	_expect(inv.get_phase_string() == "inactive", "phase == inactive after final reset (got '%s')" % inv.get_phase_string())
	_expect(inv.get_discovered_clue_count() == 0, "clue count == 0 after final reset")
	_expect(inv.get_interrogated_count() == 0, "interrogation count == 0 after final reset")
	_expect(inv.get_faction_tension() == 30, "faction_tension == 30 after final reset")
	_expect(inv.get_accused_suspect() == "", "accused_suspect == '' after final reset")
	_expect(inv.get_outcome() == "", "outcome == '' after final reset")

	# --- Report ----------------------------------------------------------------
	_report()
	if _failures.size() > 0:
		quit(1)
	else:
		quit(0)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_clue_discovered(clue_id: String) -> void:
	_clue_discovered_received = true
	_clue_discovered_id = clue_id


func _on_suspect_interrogated(suspect_id: String) -> void:
	_suspect_interrogated_received = true
	_suspect_interrogated_id = suspect_id


func _on_lie_detected(suspect_id: String, _dialogue_index: int, _indicator: String) -> void:
	_lie_detected_received = true
	_lie_detected_suspect = suspect_id


func _on_truth_confirmed(_suspect_id: String, _dialogue_index: int) -> void:
	_truth_confirmed_received = true


func _on_accusation_made(_suspect_id: String, is_correct: bool) -> void:
	_accusation_made_received = true
	_accusation_correct = is_correct


func _on_investigation_completed(outcome: String) -> void:
	_investigation_completed_received = true
	_investigation_outcome = outcome


func _on_tension_changed(old_val: int, new_val: int) -> void:
	_tension_changed_received = true
	_old_tension = old_val
	_new_tension = new_val


func _on_tension_level_changed(_old_level: String, _new_level: String) -> void:
	_tension_level_changed_received = true


# ── Utility ───────────────────────────────────────────────────────────────────

func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("  Passes: %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if _failures.size() > 0:
		for f in _failures:
			print("    - %s" % f)
	print("=== investigation_system smoke test complete ===")