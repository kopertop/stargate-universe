extends SceneTree

# Smoke test for the EVASystem autoload — EVA spacewalk mechanic.
#
# Verifies:
#   • EVASystem autoload is attached and loaded its config from JSON.
#   • SuitType, EVAState, RepairTask enum values are stable.
#   • start_eva / end_eva transitions.
#   • Oxygen drains while EVA active; stops when inside.
#   • Radiation zones increase oxygen drain.
#   • Suit integrity damage and repair.
#   • Suit type changes oxygen max and tether length.
#   • Tether snap when length exceeds max; recovery returns to EVA_ACTIVE.
#   • Zero-G velocity computation applies drag.
#   • Exterior repair tasks: start, tick, complete restores hull via ShipDamage.
#   • Meteoroid impact damages suit and hull.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • Reset restores everything to defaults.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/eva_system.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== eva_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var eva: Node = root.get_node_or_null("EVASystem")
	_expect(eva != null, "EVASystem autoload is attached")
	if eva == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "eva_system_smoke")

	# --- Enum stability -------------------------------------------------------
	var STANDARD: int = int(eva.SuitType.STANDARD)
	var REINFORCED: int = int(eva.SuitType.REINFORCED)
	var LIGHT: int = int(eva.SuitType.LIGHT)
	_expect(STANDARD == 0, "SuitType.STANDARD == 0 (got %d)" % STANDARD)
	_expect(REINFORCED == 1, "SuitType.REINFORCED == 1 (got %d)" % REINFORCED)
	_expect(LIGHT == 2, "SuitType.LIGHT == 2 (got %d)" % LIGHT)

	var INSIDE: int = int(eva.EVAState.INSIDE)
	var EVA_ACTIVE: int = int(eva.EVAState.EVA_ACTIVE)
	var TETHER_SNAP: int = int(eva.EVAState.TETHER_SNAP)
	var RETURNING: int = int(eva.EVAState.RETURNING)
	_expect(INSIDE == 0, "EVAState.INSIDE == 0 (got %d)" % INSIDE)
	_expect(EVA_ACTIVE == 1, "EVAState.EVA_ACTIVE == 1 (got %d)" % EVA_ACTIVE)
	_expect(TETHER_SNAP == 2, "EVAState.TETHER_SNAP == 2 (got %d)" % TETHER_SNAP)
	_expect(RETURNING == 3, "EVAState.RETURNING == 3 (got %d)" % RETURNING)

	var PLATE_WELD: int = int(eva.RepairTask.PLATE_WELD)
	var SEAL_BREACH: int = int(eva.RepairTask.SEAL_BREACH)
	var REALIGN_PANEL: int = int(eva.RepairTask.REALIGN_PANEL)
	_expect(PLATE_WELD == 0, "RepairTask.PLATE_WELD == 0 (got %d)" % PLATE_WELD)
	_expect(SEAL_BREACH == 1, "RepairTask.SEAL_BREACH == 1 (got %d)" % SEAL_BREACH)
	_expect(REALIGN_PANEL == 2, "RepairTask.REALIGN_PANEL == 2 (got %d)" % REALIGN_PANEL)

	# --- Config loaded --------------------------------------------------------
	eva.call("reset")
	var zones: Array = eva.call("get_all_zone_ids")
	_expect(not zones.is_empty(), "exterior zones dict is non-empty after config load")
	_expect(zones.has("hull_exterior"), "hull_exterior is in the config")
	_expect(zones.has("engine_nacelle_port"), "engine_nacelle_port is in the config")
	_expect(zones.has("engine_nacelle_starboard"), "engine_nacelle_starboard is in the config")
	_expect(zones.has("observation_deck_ext"), "observation_deck_ext is in the config")
	_expect(zones.has("shield_generator"), "shield_generator is in the config")

	# --- Initial state -------------------------------------------------------
	_expect(eva.get_oxygen() == 100.0, "oxygen starts at 100.0 (got %f)" % eva.get_oxygen())
	_expect(eva.get_suit_integrity() == 100.0, "suit_integrity starts at 100.0 (got %f)" % eva.get_suit_integrity())
	_expect(int(eva.get_current_suit()) == STANDARD, "default suit is STANDARD")
	_expect(eva.get_current_zone() == "", "current_zone is empty initially")

	# --- start_eva / end_eva --------------------------------------------------
	var started: bool = bool(eva.call("start_eva", "hull_exterior"))
	_expect(started, "start_eva for hull_exterior succeeded")
	_expect(eva.get_current_zone() == "hull_exterior", "current_zone is hull_exterior after start_eva")
	# Can't start a second EVA.
	var double_start: bool = bool(eva.call("start_eva", "observation_deck_ext"))
	_expect(not double_start, "start_eva rejected when EVA already active")
	# Unknown zone.
	var bad_start: bool = bool(eva.call("start_eva", "nonexistent_zone"))
	_expect(not bad_start, "start_eva rejected for unknown zone")

	var ended: bool = bool(eva.call("end_eva"))
	_expect(ended, "end_eva succeeded")
	_expect(eva.get_current_zone() == "", "current_zone is empty after end_eva")
	# Can't end when not active.
	var double_end: bool = bool(eva.call("end_eva"))
	_expect(not double_end, "end_eva rejected when not active")

	# --- Oxygen drain ---------------------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "observation_deck_ext")
	var o2_before: float = eva.get_oxygen()
	eva.call("test_advance", 1.0)
	var o2_after: float = eva.get_oxygen()
	_expect(o2_after < o2_before, "oxygen drained during EVA (before=%f, after=%f)" % [o2_before, o2_after])

	# Oxygen stops draining when inside.
	eva.call("end_eva")
	o2_before = eva.get_oxygen()
	eva.call("test_advance", 1.0)
	o2_after = eva.get_oxygen()
	_expect(o2_after == o2_before, "oxygen does not drain when inside (before=%f, after=%f)" % [o2_before, o2_after])

	# --- Radiation increases oxygen drain -------------------------------------
	eva.call("reset")
	eva.call("start_eva", "observation_deck_ext")  # radiation 0.1
	eva.call("test_advance", 1.0)
	var o2_low_rad: float = eva.get_oxygen()
	eva.call("reset")
	eva.call("start_eva", "engine_nacelle_port")  # radiation 0.8
	eva.call("test_advance", 1.0)
	var o2_high_rad: float = eva.get_oxygen()
	_expect(o2_high_rad < o2_low_rad, "high radiation zone drains more oxygen than low (low=%f, high=%f)" % [o2_low_rad, o2_high_rad])

	# --- Suit integrity damage and repair ------------------------------------
	eva.call("reset")
	eva.call("set_suit_integrity", 80.0)
	_expect(eva.get_suit_integrity() == 80.0, "suit_integrity set to 80.0 (got %f)" % eva.get_suit_integrity())
	# suit_damage_warning = 50.0, so is_suit_damaged = integrity < 50.
	# 80 > 50 → not damaged.
	_expect(not bool(eva.call("is_suit_damaged")), "is_suit_damaged returns false at 80.0 (above warning threshold)")

	eva.call("set_suit_integrity", 40.0)
	_expect(bool(eva.call("is_suit_damaged")), "is_suit_damaged returns true at 40.0 (below warning 50)")
	_expect(not bool(eva.call("is_suit_critical")), "is_suit_critical returns false at 40.0 (above critical 25)")

	eva.call("set_suit_integrity", 20.0)
	_expect(bool(eva.call("is_suit_critical")), "is_suit_critical returns true at 20.0 (below critical 25)")

	eva.call("repair_suit", 30.0)
	_expect(eva.get_suit_integrity() == 50.0, "suit_integrity == 50.0 after repair +30 from 20 (got %f)" % eva.get_suit_integrity())

	# --- Suit type changes ----------------------------------------------------
	eva.call("reset")
	eva.call("set_suit", REINFORCED)
	_expect(int(eva.get_current_suit()) == REINFORCED, "suit changed to REINFORCED")
	# Reinforced max_oxygen = 120.0, tether_length = 25.0
	_expect(eva.get_tether_max_length() == 25.0, "reinforced tether max == 25.0 (got %f)" % eva.get_tether_max_length())

	eva.call("set_suit", LIGHT)
	_expect(eva.get_tether_max_length() == 40.0, "light tether max == 40.0 (got %f)" % eva.get_tether_max_length())

	eva.call("set_suit", STANDARD)
	_expect(eva.get_tether_max_length() == 30.0, "standard tether max == 30.0 (got %f)" % eva.get_tether_max_length())

	# --- Tether snap ----------------------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "hull_exterior")
	_expect(bool(eva.call("is_tether_attached")), "tether is attached at start of EVA")
	# Update tether length beyond max (30.0) to trigger snap.
	eva.call("update_tether_length", 35.0)
	_expect(not bool(eva.call("is_tether_attached")), "tether detached after snap")
	_expect(int(eva.get_current_suit()) == STANDARD, "suit still standard after snap")
	# Suit should be damaged from snap (10.0 base - armor).
	var suit_after_snap: float = eva.get_suit_integrity()
	_expect(suit_after_snap < 100.0, "suit_integrity reduced after tether snap (got %f)" % suit_after_snap)

	# Recover from snap.
	var recovered: bool = bool(eva.call("recover_tether"))
	_expect(recovered, "recover_tether succeeded")
	_expect(bool(eva.call("is_tether_attached")), "tether re-attached after recovery")

	# Can't recover when not in snap state.
	var double_recover: bool = bool(eva.call("recover_tether"))
	_expect(not double_recover, "recover_tether rejected when not in snap state")

	# --- Zero-G velocity ------------------------------------------------------
	var drag: float = eva.call("get_zero_g_drag")
	var accel: float = eva.call("get_zero_g_accel")
	_expect(drag > 0.0 and drag < 1.0, "zero_g_drag is between 0 and 1 (got %f)" % drag)
	_expect(accel > 0.0, "zero_g_accel is positive (got %f)" % accel)
	var vel: Vector3 = eva.call("compute_zero_g_velocity", Vector3.ZERO, Vector3(1, 0, 0), 1.0)
	# After 1 second: (0 + 8 * 1) * 0.92 = 7.36
	_expect(absf(vel.x - 7.36) < 0.01, "zero_g velocity x ~= 7.36 after 1s (got %f)" % vel.x)
	# No input → velocity decays.
	var vel2: Vector3 = eva.call("compute_zero_g_velocity", Vector3(10, 0, 0), Vector3.ZERO, 1.0)
	# (10 + 0) * 0.92 = 9.2
	_expect(absf(vel2.x - 9.2) < 0.01, "zero_g velocity decays with drag (10 * 0.92 = 9.2, got %f)" % vel2.x)

	# --- Exterior repair tasks ------------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "hull_exterior")
	# Damage ShipDamage hull so we can verify restoration.
	var sd: Node = root.get_node_or_null("ShipDamage")
	_expect(sd != null, "ShipDamage autoload is attached")
	if sd != null:
		sd.call("reset")
		sd.call("set_hull_integrity", 50.0)
		var hull_before: float = float(sd.call("get_hull_integrity"))
		_expect(hull_before == 50.0, "hull set to 50.0 before exterior repair (got %f)" % hull_before)

		# plate_weld: hull_restore=8, oxygen_cost=5, duration=4.0
		var repair_started: bool = bool(eva.call("start_exterior_repair", "hull_exterior", "plate_weld"))
		_expect(repair_started, "start_exterior_repair for plate_weld on hull_exterior succeeded")
		_expect(bool(eva.call("is_exterior_repair_active", "hull_exterior")), "is_exterior_repair_active returns true")

		# Can't start a second repair on the same zone.
		var double_repair: bool = bool(eva.call("start_exterior_repair", "hull_exterior", "seal_breach"))
		_expect(not double_repair, "start_exterior_repair rejected when repair already active")

		# Progress before tick.
		var prog_before: float = float(eva.call("get_exterior_repair_progress", "hull_exterior"))
		_expect(prog_before == 0.0, "repair progress == 0.0 at start (got %f)" % prog_before)

		# Tick repair to completion (plate_weld duration = 4.0s).
		var completed: Array = eva.call("test_advance", 4.0)
		_expect(not completed.is_empty(), "test_advance returned completed repairs")
		_expect(String(completed[0]) == "hull_exterior", "completed repair is hull_exterior")
		_expect(not bool(eva.call("is_exterior_repair_active", "hull_exterior")), "repair no longer active after completion")

		# Hull should be restored by 8.0: 50 + 8 = 58.
		var hull_after: float = float(sd.call("get_hull_integrity"))
		_expect(hull_after == 58.0, "hull == 58.0 after plate_weld (+8 from 50) (got %f)" % hull_after)

		# Oxygen should be reduced by 5.0.
		var o2_after_repair: float = eva.get_oxygen()
		_expect(o2_after_repair < 100.0, "oxygen reduced after exterior repair (got %f)" % o2_after_repair)

	# --- Enum-based repair ----------------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "hull_exterior")
	if sd != null:
		sd.call("set_hull_integrity", 50.0)
	var started_enum: bool = bool(eva.call("start_exterior_repair_enum", "hull_exterior", SEAL_BREACH))
	_expect(started_enum, "start_exterior_repair_enum for SEAL_BREACH succeeded")
	# seal_breach duration = 5.0s.
	var completed_enum: Array = eva.call("test_advance", 5.0)
	_expect(not completed_enum.is_empty(), "test_advance completed seal_breach repair")
	if sd != null:
		# seal_breach: hull_restore=12. 50 + 12 = 62.
		var hull_enum: float = float(sd.call("get_hull_integrity"))
		_expect(hull_enum == 62.0, "hull == 62.0 after seal_breach (+12 from 50) (got %f)" % hull_enum)

	# --- Repair cost ----------------------------------------------------------
	var weld_cost: int = int(eva.call("get_exterior_repair_cost", "plate_weld"))
	_expect(weld_cost == 1, "plate_weld parts_cost == 1 (got %d)" % weld_cost)
	var realign_cost: int = int(eva.call("get_exterior_repair_cost", "realign_panel"))
	_expect(realign_cost == 0, "realign_panel parts_cost == 0 (got %d)" % realign_cost)

	# --- Meteoroid impact ------------------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "hull_exterior")
	if sd != null:
		sd.call("reset")
	var suit_before_met: float = eva.get_suit_integrity()
	var hull_before_met: float = 100.0
	if sd != null:
		hull_before_met = float(sd.call("get_hull_integrity"))
	# Trigger meteoroid directly (bypass warning timer).
	eva.call("trigger_meteoroid", "hull_exterior")
	var suit_after_met: float = eva.get_suit_integrity()
	_expect(suit_after_met < suit_before_met, "suit_integrity reduced after meteoroid (before=%f, after=%f)" % [suit_before_met, suit_after_met])
	if sd != null:
		var hull_after_met: float = float(sd.call("get_hull_integrity"))
		_expect(hull_after_met < hull_before_met, "hull reduced after meteoroid (before=%f, after=%f)" % [hull_before_met, hull_after_met])

	# --- Zone danger check ----------------------------------------------------
	_expect(bool(eva.call("is_zone_dangerous", "engine_nacelle_port")), "engine_nacelle_port is dangerous (rad 0.8)")
	_expect(not bool(eva.call("is_zone_dangerous", "observation_deck_ext")), "observation_deck_ext is not dangerous (rad 0.1, met 0.08)")

	# --- Signal firing --------------------------------------------------------
	var eva_start_signals: Array = []
	eva.eva_started.connect(func(zid): eva_start_signals.append(zid))
	eva.call("reset")
	eva.call("start_eva", "shield_generator")
	_expect(not eva_start_signals.is_empty(), "eva_started signal emitted on start_eva")
	_expect(String(eva_start_signals[0]) == "shield_generator", "eva_started signal carries zone_id 'shield_generator'")

	var o2_signals: Array = []
	eva.oxygen_changed.connect(func(v): o2_signals.append(v))
	eva.call("set_oxygen", 75.0)
	_expect(not o2_signals.is_empty(), "oxygen_changed signal emitted on set_oxygen")
	_expect(float(o2_signals[0]) == 75.0, "oxygen_changed signal carries 75.0 (got %f)" % float(o2_signals[0]))

	var suit_signals: Array = []
	eva.suit_integrity_changed.connect(func(v): suit_signals.append(v))
	eva.call("set_suit_integrity", 60.0)
	_expect(not suit_signals.is_empty(), "suit_integrity_changed signal emitted")
	_expect(float(suit_signals[0]) == 60.0, "suit_integrity_changed signal carries 60.0 (got %f)" % float(suit_signals[0]))

	var tether_signals: Array = []
	eva.tether_status_changed.connect(func(attached): tether_signals.append(attached))
	eva.call("detach_tether")
	_expect(not tether_signals.is_empty(), "tether_status_changed signal emitted on detach")
	_expect(not bool(tether_signals[0]), "tether_status_changed signal carries false on detach")

	# --- Save round-trip -----------------------------------------------------
	eva.call("reset")
	eva.call("set_suit", REINFORCED)
	eva.call("set_oxygen", 65.0)
	eva.call("set_suit_integrity", 70.0)
	eva.call("start_eva", "engine_nacelle_starboard")
	eva.call("start_exterior_repair", "engine_nacelle_starboard", "plate_weld")
	var serialized: Dictionary = eva.call("serialize")
	_expect(serialized.has("current_suit"), "serialize has 'current_suit'")
	_expect(serialized.has("oxygen"), "serialize has 'oxygen'")
	_expect(serialized.has("suit_integrity"), "serialize has 'suit_integrity'")
	_expect(serialized.has("eva_state"), "serialize has 'eva_state'")
	_expect(serialized.has("current_zone"), "serialize has 'current_zone'")
	_expect(serialized.has("tether_attached"), "serialize has 'tether_attached'")
	_expect(serialized.has("active_exterior_repairs"), "serialize has 'active_exterior_repairs'")

	var suit_ser: int = int(serialized["current_suit"])
	var o2_ser: float = float(serialized["oxygen"])
	var integ_ser: float = float(serialized["suit_integrity"])
	var zone_ser: String = String(serialized["current_zone"])
	var repairs_ser: Dictionary = serialized.get("active_exterior_repairs", {})
	_expect(suit_ser == REINFORCED, "serialized suit == REINFORCED")
	_expect(o2_ser == 65.0, "serialized oxygen == 65.0 (got %f)" % o2_ser)
	_expect(integ_ser == 70.0, "serialized suit_integrity == 70.0 (got %f)" % integ_ser)
	_expect(zone_ser == "engine_nacelle_starboard", "serialized zone == engine_nacelle_starboard")
	_expect(repairs_ser.has("engine_nacelle_starboard"), "serialized repairs has engine_nacelle_starboard")

	# Reset then deserialize.
	eva.call("reset")
	eva.call("deserialize", serialized, 1)
	_expect(int(eva.get_current_suit()) == REINFORCED, "suit restored after deserialize")
	_expect(eva.get_oxygen() == 65.0, "oxygen restored after deserialize (got %f)" % eva.get_oxygen())
	_expect(eva.get_suit_integrity() == 70.0, "suit_integrity restored after deserialize (got %f)" % eva.get_suit_integrity())
	_expect(eva.get_current_zone() == "engine_nacelle_starboard", "zone restored after deserialize")
	_expect(bool(eva.call("is_exterior_repair_active", "engine_nacelle_starboard")), "active repair restored after deserialize")

	# --- Reset clears everything ----------------------------------------------
	eva.call("reset")
	_expect(int(eva.get_current_suit()) == STANDARD, "suit is STANDARD after reset")
	_expect(eva.get_oxygen() == 100.0, "oxygen == 100.0 after reset (got %f)" % eva.get_oxygen())
	_expect(eva.get_suit_integrity() == 100.0, "suit_integrity == 100.0 after reset (got %f)" % eva.get_suit_integrity())
	_expect(eva.get_current_zone() == "", "zone is empty after reset")
	_expect(bool(eva.call("is_tether_attached")), "tether is attached after reset")
	# Check no active repairs.
	var active_repairs: Array = eva.call("get_active_exterior_repair_zones")
	_expect(active_repairs.is_empty(), "no active exterior repairs after reset")

	# --- get_exterior_repair_progress when no repair --------------------------
	eva.call("reset")
	var no_prog: float = float(eva.call("get_exterior_repair_progress", "hull_exterior"))
	_expect(no_prog == 0.0, "repair progress == 0.0 when no active repair (got %f)" % no_prog)

	# --- Repair progress at halfway -------------------------------------------
	eva.call("reset")
	eva.call("start_eva", "hull_exterior")
	eva.call("start_exterior_repair", "hull_exterior", "plate_weld")
	# plate_weld duration = 4.0s. After 2.0s, progress should be 0.5.
	eva.call("test_advance_repairs", 2.0)
	var half_prog: float = float(eva.call("get_exterior_repair_progress", "hull_exterior"))
	_expect(half_prog >= 0.49 and half_prog <= 0.51, "repair progress ~0.5 at halfway (got %f)" % half_prog)

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