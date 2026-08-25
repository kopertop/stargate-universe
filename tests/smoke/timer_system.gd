extends SceneTree

# Smoke test for the TimerSystem autoload (P1: timer & pressure system).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/timer_system.gd
#
# Asserts (acceptance criteria):
#   • TimerSystem autoload is attached to /root.
#   • start_timer creates a concurrent countdown and fires timer_started.
#   • Multiple concurrent timers run independently.
#   • test_advance ticks timers and fires timer_tick + timer_expired.
#   • cancel_timer removes a timer and fires timer_cancelled.
#   • force_expire immediately expires a timer and fires timer_expired.
#   • restart_timer overwrites an existing timer.
#   • Time acceleration multiplies the tick rate.
#   • Drama dilation engages via engage_dilation and sets Engine.time_scale.
#   • Drama dilation releases when all locks are released.
#   • Crisis auto-dilation engages when a crisis timer crosses the threshold.
#   • Crisis auto-dilation releases when the crisis timer expires.
#   • FTL countdown display query returns remaining time.
#   • format_countdown produces correct human-readable strings.
#   • Save round-trip preserves timer state.
#   • PASS count is asserted at the end.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== timer system smoke test (P1 timer & pressure) ===")

	var ts: Node = root.get_node_or_null("TimerSystem")
	_expect(ts != null, "TimerSystem autoload attached")
	if ts == null:
		_report()
		return

	# Isolate saves so we never clobber the player's real save.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "timer_system")

	# --- 1. Basic timer lifecycle ---------------------------------------
	ts.call("reset")

	var started_sig: Array = []
	ts.timer_started.connect(
		func(id: String) -> void: started_sig.append(id)
	)

	var ok: bool = ts.call("start_timer", "test_a", 10.0)
	_expect(ok, "start_timer(test_a, 10s) returns true")
	_expect(ts.call("has_timer", "test_a"), "has_timer(test_a) is true")
	_expect(not ts.call("is_expired", "test_a"), "test_a not expired")
	_expect(is_equal_approx(float(ts.call("remaining", "test_a")), 10.0),
		"remaining(test_a) == 10.0")
	_expect(is_equal_approx(float(ts.call("total", "test_a")), 10.0),
		"total(test_a) == 10.0")
	_expect(started_sig.size() == 1, "timer_started fired once")
	_expect(String(started_sig[0]) == "test_a", "timer_started carried test_a")

	# Duplicate start fails.
	var dup: bool = ts.call("start_timer", "test_a", 5.0)
	_expect(not dup, "start_timer on existing timer returns false")

	# --- 2. Multiple concurrent timers ----------------------------------
	ts.call("start_timer", "test_b", 20.0)
	ts.call("start_timer", "test_c", 5.0)
	var active: Array = ts.call("active_timer_ids")
	_expect(active.size() == 3, "three concurrent timers active")
	_expect(active.has("test_a"), "active list has test_a")
	_expect(active.has("test_b"), "active list has test_b")
	_expect(active.has("test_c"), "active list has test_c")

	# --- 3. Tick via test_advance ---------------------------------------
	var tick_sig: Array = []
	ts.timer_tick.connect(
		func(id: String, rem: float) -> void: tick_sig.append([id, rem])
	)

	var expired_sig: Array = []
	ts.timer_expired.connect(
		func(id: String) -> void: expired_sig.append(id)
	)

	ts.call("test_advance", 3.0)
	_expect(is_equal_approx(float(ts.call("remaining", "test_a")), 7.0),
		"after 3s: remaining(test_a) == 7.0")
	_expect(is_equal_approx(float(ts.call("remaining", "test_b")), 17.0),
		"after 3s: remaining(test_b) == 17.0")
	_expect(is_equal_approx(float(ts.call("remaining", "test_c")), 2.0),
		"after 3s: remaining(test_c) == 2.0")
	_expect(tick_sig.size() >= 3, "timer_tick fired for all three timers")

	# Advance test_c to expiry.
	ts.call("test_advance", 2.0)
	_expect(ts.call("is_expired", "test_c"), "test_c expired after 5s total")
	_expect(not ts.call("has_timer", "test_c"), "test_c no longer active")
	_expect(expired_sig.size() == 1, "timer_expired fired once (test_c)")
	_expect(String(expired_sig[0]) == "test_c", "timer_expired carried test_c")
	_expect(is_equal_approx(float(ts.call("remaining", "test_a")), 5.0),
		"after 5s: remaining(test_a) == 5.0")

	# --- 4. Cancel timer ------------------------------------------------
	var cancelled_sig: Array = []
	ts.timer_cancelled.connect(
		func(id: String) -> void: cancelled_sig.append(id)
	)

	var cancelled: bool = ts.call("cancel_timer", "test_b")
	_expect(cancelled, "cancel_timer(test_b) returns true")
	_expect(not ts.call("has_timer", "test_b"), "test_b no longer active after cancel")
	_expect(cancelled_sig.size() == 1, "timer_cancelled fired once")
	_expect(String(cancelled_sig[0]) == "test_b", "timer_cancelled carried test_b")

	# Cancel already-cancelled timer fails.
	var cancel2: bool = ts.call("cancel_timer", "test_b")
	_expect(not cancel2, "cancel_timer on missing timer returns false")

	# --- 5. Force expire ------------------------------------------------
	ts.call("start_timer", "force_test", 100.0)
	var expired_before: int = expired_sig.size()
	var forced: bool = ts.call("force_expire", "force_test")
	_expect(forced, "force_expire returns true")
	_expect(ts.call("is_expired", "force_test"), "force_test is expired")
	_expect(expired_sig.size() == expired_before + 1, "timer_expired fired for force_expire")

	# --- 6. Restart timer -----------------------------------------------
	ts.call("restart_timer", "test_a", 15.0)
	_expect(is_equal_approx(float(ts.call("remaining", "test_a")), 15.0),
		"restart_timer overwrites remaining to 15.0")
	_expect(ts.call("has_timer", "test_a"), "test_a active after restart")

	# --- 7. Time acceleration -------------------------------------------
	ts.call("reset")
	ts.call("start_timer", "accel_test", 100.0)
	ts.call("set_acceleration", 2.0)
	_expect(is_equal_approx(float(ts.call("get_acceleration")), 2.0),
		"get_acceleration == 2.0")
	ts.call("test_advance", 10.0)
	# 10s * 2.0 acceleration = 20s elapsed
	_expect(is_equal_approx(float(ts.call("remaining", "accel_test")), 80.0),
		"with 2x acceleration, 10s tick removes 20s (remaining == 80.0)")
	ts.call("reset_acceleration")
	_expect(is_equal_approx(float(ts.call("get_acceleration")), 1.0),
		"reset_acceleration sets back to 1.0")

	# --- 8. Drama dilation ----------------------------------------------
	ts.call("reset")
	var dilation_sig: Array = []
	ts.dilation_changed.connect(
		func(active: bool, scale: float) -> void: dilation_sig.append([active, scale])
	)

	# Save current Engine.time_scale for restoration.
	var original_ts: float = Engine.time_scale

	ts.call("engage_dilation", "story_drama", 0.35)
	_expect(ts.call("is_dilation_active"), "dilation active after engage")
	_expect(is_equal_approx(float(ts.call("get_dilation_scale")), 0.35),
		"dilation scale == 0.35")
	_expect(is_equal_approx(Engine.time_scale, 0.35),
		"Engine.time_scale == 0.35 during dilation")
	_expect(dilation_sig.size() >= 1, "dilation_changed fired on engage")
	_expect(bool(dilation_sig[0][0]) == true, "dilation_changed active=true on engage")

	# Multiple locks — dilation stays until all released.
	ts.call("engage_dilation", "combat_drama", 0.5)
	_expect(ts.call("is_dilation_active"), "dilation still active with two locks")
	ts.call("release_dilation", "story_drama")
	_expect(ts.call("is_dilation_active"), "dilation still active after first lock released")
	ts.call("release_dilation", "combat_drama")
	_expect(not ts.call("is_dilation_active"), "dilation inactive after all locks released")
	_expect(is_equal_approx(Engine.time_scale, 1.0),
		"Engine.time_scale restored to 1.0 after dilation")

	# Restore Engine.time_scale in case test env had it different.
	Engine.time_scale = original_ts

	# --- 9. Crisis auto-dilation ----------------------------------------
	ts.call("reset")
	ts.call("set_crisis_auto_dilation", true)
	_expect(ts.call("is_crisis_auto_dilation_enabled"), "crisis auto-dilation enabled")

	# Crisis timer: 100s total, auto-dilate at 25% (25s remaining).
	ts.call("start_timer", "crisis_air", 100.0, ts.Category.CRISIS, true)
	# No dilation yet.
	_expect(not ts.call("is_dilation_active"), "no dilation at full crisis timer")

	# Advance 76s — remaining 24s, crosses 25% threshold.
	ts.call("test_advance", 76.0)
	_expect(ts.call("is_dilation_active"), "crisis auto-dilation engaged below 25% threshold")
	_expect(is_equal_approx(float(ts.call("get_dilation_scale")), 0.35),
		"crisis dilation scale == 0.35 (default)")

	# Advance to expiry — dilation releases.
	ts.call("test_advance", 24.0)
	_expect(ts.call("is_expired", "crisis_air"), "crisis_air expired")
	_expect(not ts.call("is_dilation_active"), "dilation released after crisis timer expired")

	# --- 10. Crisis auto-dilation disabled ------------------------------
	ts.call("reset")
	ts.call("set_crisis_auto_dilation", false)
	ts.call("start_timer", "crisis_test2", 100.0, ts.Category.CRISIS, true)
	ts.call("test_advance", 80.0)
	_expect(not ts.call("is_dilation_active"), "no auto-dilation when disabled")
	ts.call("set_crisis_auto_dilation", true)  # restore default

	# --- 11. FTL countdown display --------------------------------------
	ts.call("reset")
	# Start a named ftl_countdown timer.
	ts.call("start_timer", "ftl_countdown", 3600.0, ts.Category.FTL)
	var ftl_rem: float = float(ts.call("ftl_countdown_remaining"))
	_expect(is_equal_approx(ftl_rem, 3600.0),
		"ftl_countdown_remaining returns 3600.0 from timer")
	ts.call("test_advance", 600.0)
	ftl_rem = float(ts.call("ftl_countdown_remaining"))
	_expect(is_equal_approx(ftl_rem, 3000.0),
		"ftl_countdown_remaining returns 3000.0 after 600s tick")

	# Without a timer, falls back to GameClock (should return >= 0).
	ts.call("cancel_timer", "ftl_countdown")
	ftl_rem = float(ts.call("ftl_countdown_remaining"))
	_expect(ftl_rem >= 0.0, "ftl_countdown_remaining fallback returns >= 0.0")

	# --- 12. format_countdown -------------------------------------------
	var formatted: String = ts.call("format_countdown", 3661.0)
	_expect(formatted == "1h 01m 01s", "format_countdown(3661) == '1h 01m 01s'")
	formatted = ts.call("format_countdown", 59.0)
	_expect(formatted == "0h 00m 59s", "format_countdown(59) == '0h 00m 59s'")
	formatted = ts.call("format_countdown", 0.0)
	_expect(formatted == "0h 00m 00s", "format_countdown(0) == '0h 00m 00s'")

	# --- 13. Save round-trip --------------------------------------------
	ts.call("reset")
	ts.call("start_timer", "save_a", 50.0, ts.Category.CRISIS, true)
	ts.call("start_timer", "save_b", 100.0)
	ts.call("test_advance", 10.0)
	ts.call("set_acceleration", 1.5)

	var saved: Dictionary = ts.call("serialize")
	_expect(saved.has("timers"), "serialize has timers key")
	_expect(saved.has("acceleration"), "serialize has acceleration key")
	_expect(is_equal_approx(float(saved["acceleration"]), 1.5),
		"serialize acceleration == 1.5")

	var timers_saved: Dictionary = saved.get("timers", {})
	_expect(timers_saved.has("save_a"), "serialized timers have save_a")
	_expect(timers_saved.has("save_b"), "serialized timers have save_b")

	# Deserialize into a fresh state.
	ts.call("reset")
	_expect(not ts.call("has_timer", "save_a"), "save_a gone after reset")
	ts.call("deserialize", saved, 2)
	_expect(ts.call("has_timer", "save_a"), "save_a restored after deserialize")
	_expect(ts.call("has_timer", "save_b"), "save_b restored after deserialize")
	_expect(is_equal_approx(float(ts.call("remaining", "save_a")), 40.0),
		"save_a remaining == 40.0 after round-trip (50 - 10)")
	_expect(is_equal_approx(float(ts.call("remaining", "save_b")), 90.0),
		"save_b remaining == 90.0 after round-trip (100 - 10)")
	_expect(is_equal_approx(float(ts.call("get_acceleration")), 1.5),
		"acceleration restored to 1.5 after round-trip")
	_expect(int(ts.call("get_category", "save_a")) == ts.Category.CRISIS,
		"save_a category preserved as CRISIS")
	_expect(bool(timers_saved["save_a"]["auto_dilate"]) == true,
		"save_a auto_dilate flag preserved")

	# --- 14. fraction_remaining -----------------------------------------
	ts.call("reset")
	ts.call("start_timer", "frac_test", 100.0)
	ts.call("test_advance", 25.0)
	_expect(is_equal_approx(float(ts.call("fraction_remaining", "frac_test")), 0.75),
		"fraction_remaining == 0.75 at 75% remaining")
	ts.call("test_advance", 75.0)
	_expect(is_equal_approx(float(ts.call("fraction_remaining", "frac_test")), 0.0),
		"fraction_remaining == 0.0 at expiry")

	# --- 15. remove_timer (silent) --------------------------------------
	ts.call("reset")
	ts.call("start_timer", "rem_test", 50.0)
	var rem_sig_count_before: int = cancelled_sig.size()
	ts.call("remove_timer", "rem_test")
	_expect(not ts.call("has_timer", "rem_test"), "rem_test gone after remove_timer")
	_expect(cancelled_sig.size() == rem_sig_count_before,
		"remove_timer does NOT fire timer_cancelled")

	# --- 16. all_timer_ids includes expired -----------------------------
	ts.call("reset")
	ts.call("start_timer", "expire_me", 10.0)
	ts.call("test_advance", 10.0)
	_expect(ts.call("is_expired", "expire_me"), "expire_me is expired")
	var all_ids: Array = ts.call("all_timer_ids")
	_expect(all_ids.has("expire_me"), "all_timer_ids includes expired timer")
	var active_ids: Array = ts.call("active_timer_ids")
	_expect(not active_ids.has("expire_me"), "active_timer_ids excludes expired timer")

	# Cleanup.
	ts.call("reset")
	Engine.time_scale = 1.0

	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("PASS  %s" % label)
	else:
		_failures.append(label)
		print("FAIL  %s" % label)


func _report() -> void:
	print("=== summary ===")
	print("passes:   %d" % _passes)
	print("failures: %d" % _failures.size())
	if _failures.size() > 0:
		print("FAILED ASSERTIONS:")
		for f: String in _failures:
			print("  - %s" % f)
		quit(1)
	else:
		quit(0)