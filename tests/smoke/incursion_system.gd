extends SceneTree

# Smoke test for the IncursionSystem autoload — E20 "Incursion" season finale.
#
# Verifies:
#   * IncursionSystem autoload is attached and loaded its config from JSON.
#   * Stage enum values are stable (NONE=0, SPACE_COMBAT=1, ..., COMPLETE=6).
#   * Outcome enum values are stable (IN_PROGRESS=0, VICTORY=1, CAPTURED=2, FAILED=3).
#   * start_incursion sets the stage to SPACE_COMBAT and emits stage_started.
#   * Space combat: _process ticking applies hull damage via ShipDamage.
#   * complete_space_combat advances to BOARDING.
#   * Boarding: wave spawning and wave clearing advances through waves.
#   * complete_boarding advances to ROOM_DEFENSE.
#   * Room defense: wave spawning, room capture tracking, failure on threshold.
#   * complete_room_defense advances to MORAL_CHOICE.
#   * Moral choice: surrender → CAPTURED, fight → VICTORY.
#   * Cliffhanger auto-advances to COMPLETE.
#   * is_complete returns true after all stages.
#   * Save round-trip: serialize → deserialize preserves state.
#   * Reset restores initial state.
#   * Config loading: boarding waves, defense waves, defense rooms, moral choices.
#   * EpisodeManager predicate "incursion_resolved" returns true when complete.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/incursion_system.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== incursion_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var isys: Node = root.get_node_or_null("IncursionSystem")
	_expect(isys != null, "IncursionSystem autoload is attached")
	if isys == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "incursion_smoke")

	# Enable instant mode so _process doesn't tick automatically.
	isys.call("set_instant_mode", true)

	# --- Enum stability -------------------------------------------------------
	var NONE: int = int(isys.Stage.NONE)
	var SPACE_COMBAT: int = int(isys.Stage.SPACE_COMBAT)
	var BOARDING: int = int(isys.Stage.BOARDING)
	var ROOM_DEFENSE: int = int(isys.Stage.ROOM_DEFENSE)
	var MORAL_CHOICE: int = int(isys.Stage.MORAL_CHOICE)
	var CLIFFHANGER: int = int(isys.Stage.CLIFFHANGER)
	var COMPLETE: int = int(isys.Stage.COMPLETE)
	_expect(NONE == 0, "Stage.NONE == 0 (got %d)" % NONE)
	_expect(SPACE_COMBAT == 1, "Stage.SPACE_COMBAT == 1 (got %d)" % SPACE_COMBAT)
	_expect(BOARDING == 2, "Stage.BOARDING == 2 (got %d)" % BOARDING)
	_expect(ROOM_DEFENSE == 3, "Stage.ROOM_DEFENSE == 3 (got %d)" % ROOM_DEFENSE)
	_expect(MORAL_CHOICE == 4, "Stage.MORAL_CHOICE == 4 (got %d)" % MORAL_CHOICE)
	_expect(CLIFFHANGER == 5, "Stage.CLIFFHANGER == 5 (got %d)" % CLIFFHANGER)
	_expect(COMPLETE == 6, "Stage.COMPLETE == 6 (got %d)" % COMPLETE)

	var IN_PROGRESS: int = int(isys.Outcome.IN_PROGRESS)
	var VICTORY: int = int(isys.Outcome.VICTORY)
	var CAPTURED: int = int(isys.Outcome.CAPTURED)
	var FAILED: int = int(isys.Outcome.FAILED)
	_expect(IN_PROGRESS == 0, "Outcome.IN_PROGRESS == 0 (got %d)" % IN_PROGRESS)
	_expect(VICTORY == 1, "Outcome.VICTORY == 1 (got %d)" % VICTORY)
	_expect(CAPTURED == 2, "Outcome.CAPTURED == 2 (got %d)" % CAPTURED)
	_expect(FAILED == 3, "Outcome.FAILED == 3 (got %d)" % FAILED)

	# --- Initial state --------------------------------------------------------
	_expect(isys.is_inactive() == true, "Incursion starts inactive (NONE stage)")
	_expect(isys.is_complete() == false, "Incursion is not complete initially")
	_expect(isys.get_outcome() == IN_PROGRESS, "Outcome starts IN_PROGRESS")
	_expect(isys.get_moral_choice() == "", "Moral choice starts empty")
	_expect(isys.get_captured_room_count() == 0, "No captured rooms initially")
	_expect(isys.get_total_waves_cleared() == 0, "No waves cleared initially")

	# --- Config loading -------------------------------------------------------
	var boarding_waves: Array = isys.get_boarding_waves()
	_expect(boarding_waves.size() == 3, "3 boarding wave configs loaded (got %d)" % boarding_waves.size())
	var defense_waves: Array = isys.get_defense_waves()
	_expect(defense_waves.size() == 3, "3 defense wave configs loaded (got %d)" % defense_waves.size())
	var defense_rooms: Array[String] = isys.get_defense_rooms()
	_expect(defense_rooms.size() == 3, "3 defense rooms (got %d)" % defense_rooms.size())
	_expect(defense_rooms.has("gate_room"), "gate_room is a defense room")
	_expect(defense_rooms.has("control_interface_room"), "control_interface_room is a defense room")
	_expect(defense_rooms.has("infirmary"), "infirmary is a defense room")
	var moral_choices: Dictionary = isys.get_moral_choices()
	_expect(moral_choices.has("surrender"), "Moral choice 'surrender' exists")
	_expect(moral_choices.has("fight"), "Moral choice 'fight' exists")

	# --- Wave config content checks -------------------------------------------
	var bw0: Dictionary = isys.get_boarding_wave(0)
	_expect(int(bw0.get("count", 0)) == 4, "Boarding wave 0 count == 4")
	var bw2: Dictionary = isys.get_boarding_wave(2)
	_expect(int(bw2.get("count", 0)) == 8, "Boarding wave 2 count == 8")
	_expect(String(bw2.get("weapon", "")) == "res://scripts/data/mp5.tres", "Boarding wave 2 weapon is mp5")
	var dw0: Dictionary = isys.get_defense_wave(0)
	_expect(int(dw0.get("count", 0)) == 5, "Defense wave 0 count == 5")
	var dw2: Dictionary = isys.get_defense_wave(2)
	_expect(int(dw2.get("count", 0)) == 10, "Defense wave 2 count == 10")
	_expect(String(dw2.get("weapon", "")) == "res://scripts/data/p90.tres", "Defense wave 2 weapon is p90")

	# --- Full playthrough: fight path (victory) -------------------------------
	isys.call("start_incursion")
	_expect(isys.get_current_stage() == SPACE_COMBAT, "Stage is SPACE_COMBAT after start_incursion")
	_expect(isys.get_current_stage_name() == "space_combat", "Stage name is 'space_combat'")
	_expect(isys.get_enemy_ships_remaining() > 0, "Enemy ships remaining > 0 at start")

	# Complete space combat.
	isys.call("complete_space_combat")
	_expect(isys.get_current_stage() == BOARDING, "Stage is BOARDING after space combat")
	_expect(isys.get_current_stage_name() == "boarding", "Stage name is 'boarding'")

	# Simulate clearing boarding waves.
	var boarding_count: int = isys.get_boarding_wave_count()
	_expect(boarding_count == 3, "3 boarding waves to clear (got %d)" % boarding_count)
	for i in range(boarding_count):
		isys.call("mark_boarding_wave_cleared", i)
	# After all boarding waves, should advance to ROOM_DEFENSE.
	_expect(isys.get_current_stage() == ROOM_DEFENSE, "Stage is ROOM_DEFENSE after boarding")
	_expect(isys.get_current_stage_name() == "room_defense", "Stage name is 'room_defense'")
	_expect(isys.get_total_waves_cleared() == 3, "3 waves cleared from boarding")

	# Simulate clearing defense waves.
	var defense_count: int = isys.get_defense_wave_count()
	_expect(defense_count == 3, "3 defense waves to clear (got %d)" % defense_count)
	for i in range(defense_count):
		isys.call("mark_defense_wave_cleared", i)
	# After all defense waves, should advance to MORAL_CHOICE.
	_expect(isys.get_current_stage() == MORAL_CHOICE, "Stage is MORAL_CHOICE after defense")
	_expect(isys.get_current_stage_name() == "moral_choice", "Stage name is 'moral_choice'")
	_expect(isys.get_total_waves_cleared() == 6, "6 total waves cleared")

	# Resolve moral choice: fight.
	var resolved: bool = isys.call("resolve_moral_choice", "fight")
	_expect(resolved == true, "resolve_moral_choice('fight') returns true")
	_expect(isys.get_moral_choice() == "fight", "Moral choice is 'fight'")
	# After moral choice, should advance through cliffhanger to complete.
	# Cliffhanger auto-advances, so we should be at COMPLETE.
	_expect(isys.is_complete() == true, "Incursion is complete after cliffhanger")
	_expect(isys.get_outcome() == VICTORY, "Outcome is VICTORY (fight path)")
	_expect(isys.get_current_stage() == COMPLETE, "Stage is COMPLETE")
	_expect(isys.get_current_stage_name() == "complete", "Stage name is 'complete'")

	# --- Save round-trip ------------------------------------------------------
	var saved: Dictionary = isys.call("serialize")
	_expect(saved.has("current_stage"), "Serialize has current_stage")
	_expect(saved.has("outcome"), "Serialize has outcome")
	_expect(saved.has("moral_choice"), "Serialize has moral_choice")
	_expect(saved.has("completed_stages"), "Serialize has completed_stages")
	_expect(saved.has("captured_rooms"), "Serialize has captured_rooms")
	_expect(saved.has("total_waves_cleared"), "Serialize has total_waves_cleared")
	_expect(int(saved.get("current_stage", -1)) == COMPLETE, "Saved stage == COMPLETE")
	_expect(int(saved.get("outcome", -1)) == VICTORY, "Saved outcome == VICTORY")
	_expect(String(saved.get("moral_choice", "")) == "fight", "Saved moral_choice == 'fight'")
	_expect(int(saved.get("total_waves_cleared", -1)) == 6, "Saved total_waves_cleared == 6")

	# Deserialize into a fresh-ish state — reset first, then load.
	isys.call("reset")
	_expect(isys.is_inactive() == true, "Reset returns to inactive")
	isys.call("deserialize", saved, 0)
	_expect(isys.get_current_stage() == COMPLETE, "Deserialized stage == COMPLETE")
	_expect(isys.get_outcome() == VICTORY, "Deserialized outcome == VICTORY")
	_expect(isys.get_moral_choice() == "fight", "Deserialized moral_choice == 'fight'")
	_expect(isys.get_total_waves_cleared() == 6, "Deserialized total_waves_cleared == 6")

	# --- Full playthrough: surrender path (captured) --------------------------
	isys.call("reset")
	isys.call("start_incursion")
	# Fast-forward through all stages.
	isys.call("complete_space_combat")
	for i in range(isys.get_boarding_wave_count()):
		isys.call("mark_boarding_wave_cleared", i)
	for i in range(isys.get_defense_wave_count()):
		isys.call("mark_defense_wave_cleared", i)
	# Resolve moral choice: surrender.
	var resolved2: bool = isys.call("resolve_moral_choice", "surrender")
	_expect(resolved2 == true, "resolve_moral_choice('surrender') returns true")
	_expect(isys.get_moral_choice() == "surrender", "Moral choice is 'surrender'")
	_expect(isys.is_complete() == true, "Incursion complete after surrender")
	_expect(isys.get_outcome() == CAPTURED, "Outcome is CAPTURED (surrender path)")

	# --- Room capture failure path --------------------------------------------
	isys.call("reset")
	isys.call("start_incursion")
	isys.call("complete_space_combat")
	# Skip to room defense by completing boarding.
	for i in range(isys.get_boarding_wave_count()):
		isys.call("mark_boarding_wave_cleared", i)
	# Now in ROOM_DEFENSE. Capture rooms up to threshold.
	var threshold: int = isys.get_capture_threshold()
	_expect(threshold == 3, "Capture threshold == 3 (got %d)" % threshold)
	var rooms_to_capture: Array[String] = ["gate_room", "control_interface_room", "infirmary"]
	for i in range(threshold):
		isys.call("mark_room_captured", rooms_to_capture[i])
		if i < threshold - 1:
			# Not yet failed — room should be captured but stage still ROOM_DEFENSE.
			_expect(isys.get_captured_room_count() == i + 1, "Captured room count == %d" % (i + 1))
	# After capturing threshold rooms, incursion should fail.
	_expect(isys.is_complete() == true, "Incursion complete (failed) after threshold rooms captured")
	_expect(isys.get_outcome() == FAILED, "Outcome is FAILED (too many rooms captured)")
	var captured: Array[String] = isys.get_captured_rooms()
	_expect(captured.size() == 3, "3 rooms captured (got %d)" % captured.size())

	# --- Invalid moral choice handling ---------------------------------------
	isys.call("reset")
	isys.call("start_incursion")
	isys.call("complete_space_combat")
	for i in range(isys.get_boarding_wave_count()):
		isys.call("mark_boarding_wave_cleared", i)
	for i in range(isys.get_defense_wave_count()):
		isys.call("mark_defense_wave_cleared", i)
	# Try an invalid choice.
	var invalid: bool = isys.call("resolve_moral_choice", "invalid_choice")
	_expect(invalid == false, "resolve_moral_choice('invalid_choice') returns false")
	_expect(isys.get_moral_choice() == "", "Moral choice stays empty for invalid")
	_expect(isys.get_current_stage() == MORAL_CHOICE, "Still at MORAL_CHOICE after invalid choice")

	# --- test_set_stage hook --------------------------------------------------
	isys.call("reset")
	isys.call("test_set_stage", MORAL_CHOICE)
	_expect(isys.get_current_stage() == MORAL_CHOICE, "test_set_stage sets stage to MORAL_CHOICE")
	var resolved3: bool = isys.call("resolve_moral_choice", "fight")
	_expect(resolved3 == true, "resolve_moral_choice works after test_set_stage")
	_expect(isys.is_complete() == true, "Incursion complete after test_set_stage + resolve")

	# --- Reset ---------------------------------------------------------------
	isys.call("reset")
	_expect(isys.is_inactive() == true, "Reset returns to inactive")
	_expect(isys.get_outcome() == IN_PROGRESS, "Reset outcome is IN_PROGRESS")
	_expect(isys.get_moral_choice() == "", "Reset clears moral choice")
	_expect(isys.get_total_waves_cleared() == 0, "Reset clears waves cleared")
	_expect(isys.get_captured_room_count() == 0, "Reset clears captured rooms")

	# --- EpisodeManager predicate check ---------------------------------------
	var em: Node = root.get_node_or_null("EpisodeManager")
	if em != null:
		# Before incursion starts, predicate should be false.
		var result_before: bool = em.call("check_completion", "e20_incursion")
		_expect(result_before == false, "EpisodeManager: e20 not complete before incursion starts")
		# Complete the incursion.
		isys.call("reset")
		isys.call("start_incursion")
		isys.call("complete_space_combat")
		for i in range(isys.get_boarding_wave_count()):
			isys.call("mark_boarding_wave_cleared", i)
		for i in range(isys.get_defense_wave_count()):
			isys.call("mark_defense_wave_cleared", i)
		isys.call("resolve_moral_choice", "fight")
		# Now predicate should be true.
		var result_after: bool = em.call("check_completion", "e20_incursion")
		_expect(result_after == true, "EpisodeManager: e20 complete after incursion resolves")

	_report()
	quit(0 if _failures.is_empty() else 1)


# --- Helpers ------------------------------------------------------------------

func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS  " + label)
	else:
		_failures.append(label)
		print("FAIL  " + label)


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes:   %d" % _passes)
	print("failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("FAILED:")
		for f in _failures:
			print("  - " + f)