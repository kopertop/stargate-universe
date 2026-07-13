extends SceneTree

# Smoke test for the Achievements autoload (issue P3).
#
# Verifies:
#   • Achievement definitions load from data/achievements.json.
#   • Predicate-driven unlocks fire on GameState state changes.
#   • Direct unlock() works for scripted beats.
#   • Hidden achievements mask their description until unlocked.
#   • Progress percentage and progress_text are correct.
#   • Idempotency: unlocking twice does not re-emit the signal.
#   • Save round-trip: serialize/deserialize preserves unlocked + notified.
#   • reset() clears all state.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/achievements.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== achievements smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ach: Node = root.get_node_or_null("Achievements")
	_expect(ach != null, "Achievements autoload is attached")
	if ach == null:
		_report()
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload is attached")
	if gs == null:
		_report()
		quit(1)
		return

	# Clean slate.
	gs.call("reset")
	ach.call("reset")

	# --- Definitions loaded ---------------------------------------------------
	var total: int = ach.call("total_count")
	_expect(total >= 12, "total_count >= 12 (got %d)" % total)
	_expect(ach.call("unlocked_count") == 0, "unlocked_count == 0 after reset")
	_expect(ach.call("progress_percentage") == 0.0, "progress_percentage == 0.0 after reset")
	_expect(ach.call("progress_text") == "0/%d" % total, "progress_text == '0/%d'" % total)

	# --- Hidden description masking -------------------------------------------
	# "episode_air" is hidden — description should be "???" while locked.
	var hidden_def: Dictionary = ach.call("get_definition", "episode_air")
	_expect(String(hidden_def.get("description", "")) == "???", "hidden achievement description masked while locked")
	# "first_gate_dial" is NOT hidden — description should be visible.
	var visible_def: Dictionary = ach.call("get_definition", "first_gate_dial")
	_expect(String(visible_def.get("description", "")) != "???", "non-hidden achievement description visible while locked")

	# --- Signal-driven unlock: first_gate_dial --------------------------------
	var signal_received: Array = []
	ach.achievement_unlocked.connect(func(id, title, desc): signal_received.append([id, title, desc]))

	# Simulate dialing a planet — planets_dialed goes from 0 to 1.
	gs.set("planets_dialed", 1)
	# The checker fires on quest_step_changed; simulate the signal.
	gs.emit_signal("quest_step_changed", "fake_step")
	# Allow deferred calls to process.
	await create_timer(0.1).timeout

	_expect(ach.call("is_unlocked", "first_gate_dial"), "first_gate_dial unlocked after planets_dialed >= 1")
	_expect(signal_received.size() >= 1, "achievement_unlocked signal emitted")
	if not signal_received.is_empty():
		_expect(String(signal_received[0][0]) == "first_gate_dial", "signal carried correct id")

	# --- Idempotency: re-emitting the signal should NOT unlock twice -----------
	var count_before: int = ach.call("unlocked_count")
	gs.emit_signal("quest_step_changed", "fake_step")
	await create_timer(0.1).timeout
	_expect(ach.call("unlocked_count") == count_before, "idempotent: no double-unlock on re-signal")

	# --- Direct unlock for scripted beat --------------------------------------
	signal_received.clear()
	var ok: bool = ach.call("unlock", "first_planet")
	_expect(ok == true, "direct unlock('first_planet') returns true")
	_expect(ach.call("is_unlocked", "first_planet"), "first_planet is unlocked after direct unlock")
	_expect(not ach.call("unlock", "first_planet"), "direct unlock('first_planet') returns false on second call (idempotent)")

	# --- Progress percentage updates -----------------------------------------
	var unlocked: int = ach.call("unlocked_count")
	_expect(unlocked == 2, "unlocked_count == 2 after two unlocks")
	var pct: float = ach.call("progress_percentage")
	_expect(pct > 0.0, "progress_percentage > 0.0 after unlocks")
	_expect(ach.call("progress_text") == "2/%d" % total, "progress_text == '2/%d'" % total)

	# --- Hidden achievement description revealed after unlock ----------------
	ach.call("unlock", "episode_air")
	var revealed_def: Dictionary = ach.call("get_definition", "episode_air")
	_expect(String(revealed_def.get("description", "")) != "???", "hidden achievement description revealed after unlock")

	# --- Save round-trip ------------------------------------------------------
	var serialized: Dictionary = ach.call("serialize")
	_expect(serialized.has("unlocked"), "serialize has 'unlocked' key")
	_expect(serialized.has("notified"), "serialize has 'notified' key")
	_expect((serialized["unlocked"] as Array).size() >= 3, "serialized unlocked list has >= 3 entries")

	# Mark one as notified, then deserialize and verify notified persists.
	ach.call("mark_notified", "first_gate_dial")
	serialized = ach.call("serialize")
	_expect((serialized["notified"] as Array).has("first_gate_dial"), "notified list contains first_gate_dial")

	# Simulate a save/load: reset, then deserialize.
	ach.call("reset")
	_expect(ach.call("unlocked_count") == 0, "unlocked_count == 0 after reset")
	ach.call("deserialize", serialized, 2)
	_expect(ach.call("is_unlocked", "first_gate_dial"), "first_gate_dial restored after deserialize")
	_expect(ach.call("is_unlocked", "first_planet"), "first_planet restored after deserialize")
	_expect(ach.call("is_unlocked", "episode_air"), "episode_air restored after deserialize")
	_expect(ach.call("is_notified", "first_gate_dial"), "first_gate_dial notified flag restored after deserialize")

	# --- Pending notifications -------------------------------------------------
	var pending: Array = ach.call("pending_notifications")
	# first_planet and episode_air should be pending (not notified yet).
	_expect(pending.size() >= 2, "pending_notifications >= 2 (unlocked but not notified)")

	# --- all_definitions returns ordered list with masked hidden -------------
	var all_defs: Array = ach.call("all_definitions")
	_expect(all_defs.size() == total, "all_definitions size == total_count")

	# --- Unknown id handling --------------------------------------------------
	var unknown_ok: bool = ach.call("unlock", "nonexistent_achievement")
	_expect(unknown_ok == false, "unlock unknown id returns false")

	# --- Clean up signal connection ------------------------------------------
	# Lambda connections are auto-disconnected when the callable goes out of
	# scope; explicit disconnect would error if already gone. Skip.

	_report()
	quit(0 if _failures.is_empty() else 1)


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
		print("  FAILED:")
		for f in _failures:
			print("    - %s" % f)