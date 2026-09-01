extends SceneTree

# Smoke test for the injury system + med-bay recovery loop (issue #148).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/injury_system.gd
#
# Asserts (acceptance criteria):
#   • register_injury tags RECOVERABLE below the fatal threshold and FATAL at/above.
#   • injury_registered fires with the right cause + tag.
#   • attempt_recovery arms only RECOVERABLE, not-yet-recovered injuries.
#   • MedBay.begin_recovery starts a time-based countdown, emits recovery_started,
#     emits TJ dialog lines, and on completion flips the InjurySystem record to
#     recovered (emitting recovery_complete).
#   • FATAL injuries never recover — begin_recovery + attempt_recovery both refuse.
#   • Save round-trip preserves the injury registry.
#   • PASS count is asserted at the end.
#
# Uses the live autoloads (GameState + InjurySystem + MedBay + SceneRouter) like
# knockout.gd / e1_flow.gd. instant_mode keeps the knock_out routing headless.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== injury system + med-bay smoke test (issue #148) ===")

	var gs: Node = root.get_node_or_null("GameState")
	var isys: Node = root.get_node_or_null("InjurySystem")
	var med: Node = root.get_node_or_null("MedBay")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(isys != null, "InjurySystem autoload attached")
	_expect(med != null, "MedBay autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or isys == null or med == null or router == null:
		_report()
		return

	# Headless: flip state without the fade/cutscene/scene-load.
	router.set("instant_mode", true)

	# --- 1. injury registration + tagging --------------------------------
	gs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")

	# RECOVERABLE: suffocation at severity 0.5 (the E1 case).
	var reg_sig_fired: Array = []
	isys.injury_registered.connect(
		func(cause: int, tag: int) -> void: reg_sig_fired.append([cause, tag])
	)
	var tag: int = isys.call("register_injury", "eli", isys.InjuryCause.SUFFOCATION, 0.5)
	_expect(tag == isys.InjuryTag.RECOVERABLE,
		"register_injury(0.5) → RECOVERABLE")
	_expect(isys.call("has_injury", "eli"), "injury registry has eli")
	_expect(isys.call("is_recoverable", "eli"), "eli is recoverable")
	_expect(not isys.call("is_fatal", "eli"), "eli is not fatal")
	_expect(not isys.call("is_recovered", "eli"), "eli not yet recovered")
	_expect(reg_sig_fired.size() == 1,
		"injury_registered fired once")
	_expect(int(reg_sig_fired[0][0]) == isys.InjuryCause.SUFFOCATION,
		"injury_registered cause == SUFFOCATION")
	_expect(int(reg_sig_fired[0][1]) == isys.InjuryTag.RECOVERABLE,
		"injury_registered tag == RECOVERABLE")
	# register_injury delegates to GameState.knock_out → routed to infirmary.
	_expect(gs.recovering_in_infirmary == true,
		"register_injury routed player to infirmary (recovering_in_infirmary)")
	_expect(String(gs.knockout_cause) == "asphyxiation",
		"register_injury stashed legacy cause_str (asphyxiation)")
	# knock_out heals to full — no death.
	_expect(gs.health == gs.MAX_HEALTH,
		"register_injury heals to full (no death)")

	# FATAL: impact at severity 0.9 (above the 0.85 threshold).
	var fatal_tag: int = isys.call("register_injury", "rush", isys.InjuryCause.IMPACT, 0.9)
	_expect(fatal_tag == isys.InjuryTag.FATAL,
		"register_injury(0.9) → FATAL")
	_expect(isys.call("is_fatal", "rush"), "rush is fatal")
	_expect(not isys.call("is_recoverable", "rush"), "rush not recoverable")

	# --- 2. recovery flow -----------------------------------------------
	var rec_sig_fired: Array = []
	isys.recovery_complete.connect(
		func(cid: String) -> void: rec_sig_fired.append(cid)
	)
	var start_sig_fired: Array = []
	med.recovery_started.connect(
		func(cid: String) -> void: start_sig_fired.append(cid)
	)
	var fin_sig_fired: Array = []
	med.recovery_finished.connect(
		func(cid: String) -> void: fin_sig_fired.append(cid)
	)

	# begin_recovery on a RECOVERABLE injury → starts the countdown.
	var started: bool = med.call("begin_recovery", "eli")
	_expect(started == true, "begin_recovery(eli) starts recovery")
	_expect(med.call("is_recovering", "eli"), "med-bay is recovering eli")
	_expect(start_sig_fired.size() == 1, "recovery_started fired for eli")
	_expect(String(start_sig_fired[0]) == "eli", "recovery_started carried eli")
	# attempt_recovery already armed by begin_recovery — idempotent re-arm.
	_expect(isys.call("is_recovering", "eli"),
		"injury system shows eli recovering after begin_recovery")
	# Severity 0.5 → 8 + 0.5*30 = 23 s.
	var expected_dur: float = med.call("recovery_duration", 0.5)
	_expect(is_equal_approx(expected_dur, 23.0),
		"recovery_duration(0.5) == 23s (8 + 0.5*30)")

	# Force-finish recovery (don't wait the full countdown in headless).
	var finished: bool = med.call("finish_now", "eli")
	_expect(finished == true, "finish_now(eli) completes recovery")
	_expect(not med.call("is_recovering", "eli"), "med-bay no longer recovering eli")
	_expect(isys.call("is_recovered", "eli"), "injury system marks eli recovered")
	_expect(fin_sig_fired.size() == 1, "recovery_finished fired for eli")
	_expect(rec_sig_fired.size() == 1, "recovery_complete fired for eli")
	_expect(String(rec_sig_fired[0]) == "eli", "recovery_complete carried eli")

	# --- 3. fatal injuries don't recover -------------------------------
	var fatal_started: bool = med.call("begin_recovery", "rush")
	_expect(fatal_started == false, "begin_recovery(rush) refuses FATAL injury")
	_expect(not med.call("is_recovering", "rush"), "med-bay never recovers rush")
	var fatal_attempt: bool = isys.call("attempt_recovery", "rush")
	_expect(fatal_attempt == false, "attempt_recovery(rush) refuses FATAL injury")
	_expect(not isys.call("is_recovered", "rush"), "rush never recovered")
	# complete_recovery on a fatal injury is also a no-op.
	var fatal_complete: bool = isys.call("complete_recovery", "rush")
	_expect(fatal_complete == false, "complete_recovery(rush) refuses FATAL injury")

	# --- 4. already-recovered injury can't re-recover ------------------
	var re_started: bool = med.call("begin_recovery", "eli")
	_expect(re_started == false, "begin_recovery(eli) refuses already-recovered")

	# --- 5. unknown character is a clean no-op -------------------------
	_expect(not med.call("begin_recovery", "nobody"), "begin_recovery(unknown) false")
	_expect(not isys.call("attempt_recovery", "nobody"), "attempt_recovery(unknown) false")

	# --- 6. save round-trip --------------------------------------------
	isys.call("clear_all")
	isys.call("register_injury", "chloe", isys.InjuryCause.HOSTILE, 0.4)
	med.call("begin_recovery", "chloe")
	var snap: Dictionary = isys.call("serialize")
	_expect((snap.get("injuries", {}) as Dictionary).has("chloe"),
		"serialize captures chloe's injury")
	isys.call("clear_all")
	_expect(not isys.call("has_injury", "chloe"), "cleared registry before load")
	isys.call("deserialize", snap, 2)
	_expect(isys.call("has_injury", "chloe"), "deserialize restores chloe's injury")
	_expect(isys.call("is_recoverable", "chloe"), "restored injury is recoverable")
	# Note: live recovery state (_recoveries in MedBay) is NOT serialized by
	# design — it's a transient countdown. The InjurySystem record's
	# recovering flag round-trips so a resumed game knows the patient is mid-recovery.
	var rec2: Dictionary = isys.call("injury", "chloe")
	_expect(bool(rec2.get("recovering", false)),
		"deserialize restores recovering flag")

	# --- 7. TJ dialog lines are the issue #148 spec lines --------------
	var tj_lines: Array = med.TJ_LINES
	_expect(tj_lines.has("Can you move your fingers?"),
		"TJ_LINES has 'Can you move your fingers?'")
	_expect(tj_lines.has("We'll get it in a sling."),
		"TJ_LINES has 'We'll get it in a sling.'")
	_expect(tj_lines.has("Are you okay?"),
		"TJ_LINES has 'Are you okay?'")

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
	# Assert the PASS count is non-zero (we ran assertions, not an empty harness).
	if _passes == 0:
		print("RESULT: FAIL (zero passes — harness ran no assertions)")
		quit(1)
		return
	if _failures.is_empty():
		print("PASS count asserted: %d" % _passes)
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)