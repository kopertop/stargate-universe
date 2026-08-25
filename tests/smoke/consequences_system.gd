extends SceneTree

# Smoke test for ConsequencesSystem (issue #134 consequences task).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/consequences_system.gd
#
# Asserts:
#   1. ConsequencesSystem autoload present; config loads (stamina max = 100).
#   2. Stamina starts at max; sprint_allowed() true at full stamina.
#   3. Sprint drains stamina; rest regenerates it.
#   4. Zero water → dehydration: is_dehydrated() true, stamina drains, warning fires.
#   5. Zero food → starvation: is_starved() true, movement_multiplier < 1.0, health drains.
#   6. Emergency rationing: both food+water low → is_emergency_rationing() true,
#      consumption_multiplier < 1.0, stamina regen throttled.
#   7. Sustained dehydration → knockout via InjurySystem (DEHYDRATION cause).
#   8. Sustained starvation → knockout via InjurySystem (STARVATION cause).
#   9. on_recovery clears knockout flag; consequences resume.
#  10. Save round-trip: serialize → reset → deserialize restores stamina + timers.
#  11. InjurySystem has DEHYDRATION + STARVATION causes with cause strings.
#  12. knockout_lines.json has "dehydration" and "starvation" pools.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== consequences system smoke test ===")
	call_deferred("_run")


func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	var router: Node = root.get_node_or_null("SceneRouter")
	var cs: Node = root.get_node_or_null("ConsequencesSystem")
	var isys: Node = root.get_node_or_null("InjurySystem")
	var med: Node = root.get_node_or_null("MedBay")

	_expect(gs != null, "GameState autoload present")
	_expect(inv != null, "Inventory autoload present")
	_expect(router != null, "SceneRouter autoload present")
	_expect(cs != null, "ConsequencesSystem autoload present")
	_expect(isys != null, "InjurySystem autoload present")
	_expect(med != null, "MedBay autoload present")

	if gs == null or inv == null or router == null or cs == null or isys == null or med == null:
		_report()
		return

	# Isolate saves per the smoke-test convention.
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null and sm.has_method("configure_test_paths"):
		sm.call("configure_test_paths", "consequences_test")

	router.set("instant_mode", true)

	# --- 1. Config loads --------------------------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")

	var stamina_max: float = float(cs.call("stamina_max"))
	_expect(stamina_max > 0.0, "stamina_max loaded from config (= %.1f)" % stamina_max)
	_expect(stamina_max == 100.0, "stamina_max == 100.0 (config default)")

	# --- 2. Stamina starts at max; sprint allowed --------------------------
	_expect(is_equal_approx(float(cs.call("stamina")), stamina_max),
		"stamina starts at max (= %.1f)" % float(cs.call("stamina")))
	_expect(bool(cs.call("sprint_allowed")),
		"sprint_allowed() true at full stamina")

	# --- 3. Sprint drains; rest regenerates --------------------------------
	# Tick sprint for 5 seconds → drain = 8 * 5 = 40 stamina.
	cs.call("set_stamina", stamina_max)
	cs.call("tick_sprint", true)
	cs.call("simulate_seconds", 5.0)
	var after_sprint: float = float(cs.call("stamina"))
	_expect(after_sprint < stamina_max,
		"stamina drains during sprint (%.1f < %.1f)" % [after_sprint, stamina_max])
	_expect(after_sprint <= stamina_max - 35.0,
		"stamina drains meaningfully during 5s sprint (>= 35 spent, got %.1f spent)" % (stamina_max - after_sprint))

	# Rest → regen.
	cs.call("tick_sprint", false)
	cs.call("simulate_seconds", 5.0)
	var after_rest: float = float(cs.call("stamina"))
	_expect(after_rest > after_sprint,
		"stamina regenerates at rest (%.1f > %.1f)" % [after_rest, after_sprint])

	# --- 4. Zero water → dehydration --------------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)

	var dehyd_warning: Array = []
	cs.dehydration_warning.connect(
		func(active: bool) -> void: dehyd_warning.append(active)
	)

	cs.call("set_stamina", stamina_max)
	cs.call("tick_sprint", false)
	cs.call("simulate_seconds", 2.0)

	_expect(bool(cs.call("is_dehydrated")),
		"is_dehydrated() true when water == 0")
	_expect(dehyd_warning.size() >= 1 and bool(dehyd_warning[0]),
		"dehydration_warning signal fired with active=true")
	# Stamina should have drained due to dehydration.
	_expect(float(cs.call("stamina")) < stamina_max,
		"stamina drains when dehydrated (%.1f < %.1f)" % [float(cs.call("stamina")), stamina_max])
	# Vision blur should be non-zero once stamina drops below the threshold.
	var blur: float = float(cs.call("vision_blur_intensity"))
	# After 2s of drain at 2.5/s, stamina = 95 — blur may still be 0 until
	# stamina drops below 25%. Tick longer to drive it down.
	cs.call("simulate_seconds", 40.0)
	blur = float(cs.call("vision_blur_intensity"))
	_expect(blur > 0.0,
		"vision_blur_intensity > 0 when dehydrated and stamina low (%.2f)" % blur)

	# --- 5. Zero food → starvation ----------------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 20)
	inv.call("set_count", "food", 0)

	var starv_warning: Array = []
	cs.starvation_warning.connect(
		func(active: bool) -> void: starv_warning.append(active)
	)

	var health_before: float = float(gs.get("health"))
	cs.call("simulate_seconds", 5.0)
	_expect(bool(cs.call("is_starved")),
		"is_starved() true when food == 0")
	_expect(starv_warning.size() >= 1 and bool(starv_warning[0]),
		"starvation_warning signal fired with active=true")
	_expect(float(cs.call("movement_multiplier")) < 1.0,
		"movement_multiplier < 1.0 when starved (%.2f)" % float(cs.call("movement_multiplier")))
	var health_after: float = float(gs.get("health"))
	_expect(health_after < health_before,
		"health drains during starvation (%.1f < %.1f)" % [health_after, health_before])

	# --- 6. Emergency rationing: both food+water critically low ------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 2)
	inv.call("set_count", "food", 2)

	var rationing_sig: Array = []
	cs.emergency_rationing_changed.connect(
		func(active: bool) -> void: rationing_sig.append(active)
	)

	cs.call("simulate_seconds", 1.0)
	_expect(bool(cs.call("is_emergency_rationing")),
		"is_emergency_rationing() true when both food+water <= critical (2/2)")
	_expect(rationing_sig.size() >= 1 and bool(rationing_sig[0]),
		"emergency_rationing_changed signal fired with active=true")
	_expect(float(cs.call("consumption_multiplier")) < 1.0,
		"consumption_multiplier < 1.0 during emergency rationing (%.2f)" % float(cs.call("consumption_multiplier")))

	# Stamina regen should be throttled during emergency rationing.
	cs.call("set_stamina", 50.0)
	cs.call("tick_sprint", false)
	cs.call("simulate_seconds", 10.0)
	var regen_stamina: float = float(cs.call("stamina"))
	# Normal regen = 4.0/s * 0.3 = 1.2/s → 12 over 10s; normal would be 40.
	_expect(regen_stamina < 50.0 + 20.0,
		"stamina regen throttled during emergency rationing (%.1f < 70.0)" % regen_stamina)
	_expect(regen_stamina > 50.0,
		"stamina still regenerates (slowly) during emergency rationing (%.1f > 50.0)" % regen_stamina)

	# --- 7. Sustained dehydration → knockout -------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)

	var knockout_sig: Array = []
	cs.consequence_knockout.connect(
		func(cause: int) -> void: knockout_sig.append(cause)
	)

	# Tick past DEHYDRATION_KNOCKOUT_SECONDS (120s).
	cs.call("simulate_seconds", 130.0)
	_expect(knockout_sig.size() >= 1,
		"consequence_knockout fired after sustained dehydration")
	if knockout_sig.size() >= 1:
		var dehyd_cause: int = _injury_cause_dehydration(isys)
		_expect(int(knockout_sig[0]) == dehyd_cause,
			"knockout cause == DEHYDRATION")
	_expect(isys.call("has_injury", "eli"),
		" InjurySystem registered eli's dehydration injury")
	_expect(isys.call("is_recoverable", "eli"),
		"dehydration injury is recoverable (not fatal)")

	# --- 8. Sustained starvation → knockout --------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 20)
	inv.call("set_count", "food", 0)

	knockout_sig.clear()
	cs.consequence_knockout.connect(
		func(cause: int) -> void: knockout_sig.append(cause)
	)

	# Tick past STARVATION_KNOCKOUT_SECONDS (300s).
	cs.call("simulate_seconds", 310.0)
	_expect(knockout_sig.size() >= 1,
		"consequence_knockout fired after sustained starvation")
	if knockout_sig.size() >= 1:
		var starv_cause: int = _injury_cause_starvation(isys)
		_expect(int(knockout_sig[0]) == starv_cause,
			"knockout cause == STARVATION")
	_expect(isys.call("has_injury", "eli"),
		" InjurySystem registered eli's starvation injury")

	# --- 9. on_recovery clears knockout flag -------------------------------
	# Simulate MedBay recovery completion.
	isys.call("clear_all")
	cs.call("on_recovery", "eli")
	# After recovery, a fresh dehydration tick should NOT be blocked.
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	cs.call("simulate_seconds", 1.0)
	_expect(bool(cs.call("is_dehydrated")),
		"consequences resume after on_recovery (dehydrated again)")

	# --- 10. Save round-trip ------------------------------------------------
	gs.call("reset")
	cs.call("reset")
	isys.call("clear_all")
	med.call("clear_all")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	cs.call("set_stamina", 42.0)
	# Dehydration is active (water=0) so stamina will drain during the tick.
	# Capture the value AFTER the tick as the expected round-trip value.
	cs.call("simulate_seconds", 10.0)  # build up dehydration_timer
	var expected_stamina: float = float(cs.call("stamina"))

	var saved: Dictionary = cs.call("serialize") as Dictionary
	_expect(saved.has("stamina"), "serialize() has 'stamina' key")
	_expect(saved.has("dehydration_timer"), "serialize() has 'dehydration_timer' key")

	cs.call("reset")
	var post_reset_stamina: float = float(cs.call("stamina"))
	_expect(is_equal_approx(post_reset_stamina, float(cs.call("stamina_max"))),
		"reset restores stamina to max")

	cs.call("deserialize", saved, 1)
	var restored_stamina: float = float(cs.call("stamina"))
	_expect(is_equal_approx(restored_stamina, expected_stamina),
		"deserialize restores stamina (%.1f == %.1f)" % [restored_stamina, expected_stamina])
	var restored_timer: float = float((cs.call("serialize") as Dictionary).get("dehydration_timer", -1.0))
	_expect(restored_timer > 0.0,
		"deserialize restores dehydration_timer (> 0, got %.2f)" % restored_timer)

	# --- 11. InjurySystem has DEHYDRATION + STARVATION causes ---------------
	var cause_strings: Dictionary = isys.get("CAUSE_STRINGS") as Dictionary
	_expect(cause_strings.size() >= 7,
		"CAUSE_STRINGS has >= 7 entries (got %d)" % cause_strings.size())
	var dehyd_str: String = ""
	var starv_str: String = ""
	# The dict is keyed by enum int; find the dehydration/starvation strings.
	for k in cause_strings.keys():
		var v: String = String(cause_strings[k])
		if v == "dehydration":
			dehyd_str = v
		elif v == "starvation":
			starv_str = v
	_expect(dehyd_str == "dehydration",
		"CAUSE_STRINGS contains 'dehydration'")
	_expect(starv_str == "starvation",
		"CAUSE_STRINGS contains 'starvation'")

	# --- 12. knockout_lines.json has dehydration + starvation pools --------
	var f: FileAccess = FileAccess.open("res://data/knockout_lines.json", FileAccess.READ)
	if f == null:
		_expect(false, "knockout_lines.json readable")
	else:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			_expect(false, "knockout_lines.json parsed to Dictionary")
		else:
			var kl: Dictionary = parsed as Dictionary
			var pools: Dictionary = kl.get("pools", {}) as Dictionary
			_expect(pools.has("dehydration"),
				"knockout_lines.json has 'dehydration' pool")
			_expect(pools.has("starvation"),
				"knockout_lines.json has 'starvation' pool")
			var dehyd_pool: Variant = pools.get("dehydration", [])
			_expect(dehyd_pool is Array and (dehyd_pool as Array).size() >= 1,
				"'dehydration' pool non-empty")
			var starv_pool: Variant = pools.get("starvation", [])
			_expect(starv_pool is Array and (starv_pool as Array).size() >= 1,
				"'starvation' pool non-empty")

	router.set("instant_mode", false)
	_report()


# Helper: get the InjuryCause.DEHYDRATION int from the InjurySystem enum.
func _injury_cause_dehydration(isys: Node) -> int:
	var enum_dict: Dictionary = isys.get("InjuryCause") as Dictionary
	return int(enum_dict.get("DEHYDRATION", 5))


func _injury_cause_starvation(isys: Node) -> int:
	var enum_dict: Dictionary = isys.get("InjuryCause") as Dictionary
	return int(enum_dict.get("STARVATION", 6))


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
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)