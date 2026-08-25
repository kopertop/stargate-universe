extends SceneTree

# Smoke test for the ShipDamage autoload — hull integrity and per-room damage.
#
# Verifies:
#   • ShipDamage autoload is attached and loaded its config from JSON.
#   • Hull integrity starts at max (100%).
#   • apply_damage reduces hull and room integrity.
#   • DamageState transitions: PRISTINE → DAMAGED → CRITICAL → DESTROYED.
#   • Room at DESTROYED forces PowerGrid conduit + section damage.
#   • Repair minigame: start_repair, tick, complete restores integrity.
#   • RepairAction enum values are stable.
#   • hull_integrity_changed and room_integrity_changed signals fire.
#   • room_damage_state_changed signal fires on state transitions.
#   • Save round-trip: serialize → deserialize preserves hull + room state.
#   • Reset restores everything to pristine.
#   • GameState.hull_percent is published on damage and repair.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/ship_damage.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== ship_damage smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var sd: Node = root.get_node_or_null("ShipDamage")
	_expect(sd != null, "ShipDamage autoload is attached")
	if sd == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "ship_damage_smoke")

	# --- Enum stability -------------------------------------------------------
	# DamageState.PRISTINE == 0, DAMAGED == 1, CRITICAL == 2, DESTROYED == 3
	var PRISTINE: int = int(sd.DamageState.PRISTINE)
	var DAMAGED: int = int(sd.DamageState.DAMAGED)
	var CRITICAL: int = int(sd.DamageState.CRITICAL)
	var DESTROYED: int = int(sd.DamageState.DESTROYED)
	_expect(PRISTINE == 0, "DamageState.PRISTINE == 0 (got %d)" % PRISTINE)
	_expect(DAMAGED == 1, "DamageState.DAMAGED == 1 (got %d)" % DAMAGED)
	_expect(CRITICAL == 2, "DamageState.CRITICAL == 2 (got %d)" % CRITICAL)
	_expect(DESTROYED == 3, "DamageState.DESTROYED == 3 (got %d)" % DESTROYED)

	# RepairAction.WELD == 0, PATCH == 1, REALIGN == 2
	var WELD: int = int(sd.RepairAction.WELD)
	var PATCH: int = int(sd.RepairAction.PATCH)
	var REALIGN: int = int(sd.RepairAction.REALIGN)
	_expect(WELD == 0, "RepairAction.WELD == 0 (got %d)" % WELD)
	_expect(PATCH == 1, "RepairAction.PATCH == 1 (got %d)" % PATCH)
	_expect(REALIGN == 2, "RepairAction.REALIGN == 2 (got %d)" % REALIGN)

	# DamageSource.METEOR_IMPACT == 0, COMBAT == 1, FTL_STRESS == 2
	var METEOR: int = int(sd.DamageSource.METEOR_IMPACT)
	var COMBAT: int = int(sd.DamageSource.COMBAT)
	var FTL_STRESS: int = int(sd.DamageSource.FTL_STRESS)
	_expect(METEOR == 0, "DamageSource.METEOR_IMPACT == 0 (got %d)" % METEOR)
	_expect(COMBAT == 1, "DamageSource.COMBAT == 1 (got %d)" % COMBAT)
	_expect(FTL_STRESS == 2, "DamageSource.FTL_STRESS == 2 (got %d)" % FTL_STRESS)

	# --- Config loaded --------------------------------------------------------
	sd.call("reset")
	var hull: float = sd.get_hull_integrity()
	_expect(hull > 0.0, "hull_integrity > 0 after reset (got %f)" % hull)
	var hull_pct: float = sd.get_hull_integrity_percent()
	_expect(hull_pct == 100.0, "hull_integrity_percent == 100%% after reset (got %f)" % hull_pct)
	var room_states: Dictionary = sd.get_all_room_damage_states()
	_expect(not room_states.is_empty(), "room damage states dict is non-empty after config load")
	_expect(room_states.has("gate_room"), "gate_room is in the damage config")
	_expect(room_states.has("infirmary"), "infirmary is in the damage config")

	# --- Initial state: all rooms PRISTINE -----------------------------------
	_expect(int(sd.get_room_damage_state_int("gate_room")) == PRISTINE, "gate_room starts PRISTINE")
	_expect(int(sd.get_room_damage_state_int("aft_storage_hall")) == PRISTINE, "aft_storage_hall starts PRISTINE")
	var gate_int: float = sd.get_room_integrity("gate_room")
	_expect(gate_int == 100.0, "gate_room integrity == 100.0 initially (got %f)" % gate_int)

	# --- Apply damage: meteor impact on gate_room -----------------------------
	# meteor_impact: hull_damage=8, room_damage=20
	var hull_before: float = sd.get_hull_integrity()
	# Disable random conduit damage for deterministic test by using a source
	# with conduit_chance=0 — FTL_STRESS has 0.2, but we test damage directly.
	# Use apply_damage with a known source. We'll test conduit separately.
	sd.call("set_hull_integrity", 100.0)
	sd.call("reset")
	var dealt: float = float(sd.call("apply_damage", "meteor_impact", "gate_room"))
	_expect(dealt == 8.0, "meteor_impact dealt 8.0 hull damage (got %f)" % dealt)
	var hull_after: float = sd.get_hull_integrity()
	_expect(hull_after == 92.0, "hull_integrity == 92.0 after meteor_impact (got %f)" % hull_after)
	# Room integrity: 100 - 20 = 80 → 80% → DAMAGED (below 75%? No, 80 > 75).
	# Actually 80/100 * 100 = 80% which is >= 75%, so PRISTINE.
	# Let me recalculate: max_integrity for gate_room is 100.0, damage is 20.0.
	# 80.0 / 100.0 * 100 = 80% — still PRISTINE (>= 75%).
	var gate_int_after: float = sd.get_room_integrity("gate_room")
	_expect(gate_int_after == 80.0, "gate_room integrity == 80.0 after meteor_impact (got %f)" % gate_int_after)
	# 80% → PRISTINE (threshold is < 75% for DAMAGED)
	_expect(int(sd.get_room_damage_state_int("gate_room")) == PRISTINE, "gate_room is PRISTINE at 80%% integrity")

	# Apply another meteor impact to push gate_room into DAMAGED.
	sd.call("apply_damage", "meteor_impact", "gate_room")
	gate_int_after = sd.get_room_integrity("gate_room")
	# 80 - 20 = 60 → 60% → DAMAGED
	_expect(gate_int_after == 60.0, "gate_room integrity == 60.0 after 2nd meteor_impact (got %f)" % gate_int_after)
	_expect(int(sd.get_room_damage_state_int("gate_room")) == DAMAGED, "gate_room is DAMAGED at 60%% integrity")

	# --- Damage state transitions: DAMAGED → CRITICAL → DESTROYED ------------
	# gate_room at 60%, another meteor: 60 - 20 = 40 → CRITICAL
	sd.call("apply_damage", "meteor_impact", "gate_room")
	_expect(int(sd.get_room_damage_state_int("gate_room")) == CRITICAL, "gate_room is CRITICAL at 40%% integrity")
	# One more: 40 - 20 = 20 → DESTROYED
	sd.call("apply_damage", "meteor_impact", "gate_room")
	_expect(int(sd.get_room_damage_state_int("gate_room")) == DESTROYED, "gate_room is DESTROYED at 20%% integrity")

	# --- DESTROYED room forces PowerGrid section damage -----------------------
	var pg: Node = root.get_node_or_null("PowerGrid")
	_expect(pg != null, "PowerGrid autoload is attached")
	if pg != null:
		# gate_room should be OFFLINE because DESTROYED triggers set_section_damaged.
		# But gate_room conduit damage is random (conduit_chance 0.4).
		# Section damage is deterministic — DESTROYED always calls set_section_damaged.
		var gate_power_state: int = int(pg.call("get_room_power_state", "gate_room"))
		_expect(gate_power_state == 2, "gate_room is OFFLINE in PowerGrid when DESTROYED (state=%d)" % gate_power_state)

	# --- Signal firing on hull damage ----------------------------------------
	var hull_signals: Array = []
	sd.hull_integrity_changed.connect(func(v): hull_signals.append(v))
	sd.call("set_hull_integrity", 50.0)
	_expect(not hull_signals.is_empty(), "hull_integrity_changed signal emitted on set_hull_integrity")
	_expect(float(hull_signals[0]) == 50.0, "hull_integrity_changed signal carries 50.0 (got %f)" % float(hull_signals[0]))
	hull_signals.clear()

	var room_signals: Array = []
	sd.room_integrity_changed.connect(func(rid, v): room_signals.append([rid, v]))
	# Reset and apply damage to a fresh room.
	sd.call("reset")
	sd.call("apply_damage", "combat", "infirmary")
	_expect(not room_signals.is_empty(), "room_integrity_changed signal emitted on apply_damage")
	_expect(String(room_signals[0][0]) == "infirmary", "room_integrity_changed signal carries room_id 'infirmary'")
	room_signals.clear()

	# --- room_damage_state_changed signal -------------------------------------
	var state_signals: Array = []
	sd.room_damage_state_changed.connect(func(rid, s): state_signals.append([rid, s]))
	# infirmary is at 85 (100 - 15 combat). Apply another combat to push to 70 → DAMAGED.
	sd.call("apply_damage", "combat", "infirmary")
	# 85 - 15 = 70 → DAMAGED (below 75%)
	var found_state_signal: bool = false
	for entry in state_signals:
		if String(entry[0]) == "infirmary" and int(entry[1]) == DAMAGED:
			found_state_signal = true
			break
	_expect(found_state_signal, "room_damage_state_changed signal emitted for infirmary → DAMAGED")
	state_signals.clear()

	# --- Repair minigame: weld restores hull and room -------------------------
	sd.call("reset")
	# Damage gate_room to CRITICAL (40%).
	sd.call("apply_damage", "meteor_impact", "gate_room")
	sd.call("apply_damage", "meteor_impact", "gate_room")
	sd.call("apply_damage", "meteor_impact", "gate_room")
	var hull_pre_repair: float = sd.get_hull_integrity()
	# 3 meteor impacts: 100 - 24 = 76 hull. Room: 100 - 60 = 40.
	_expect(hull_pre_repair == 76.0, "hull == 76.0 before repair (got %f)" % hull_pre_repair)
	var room_pre_repair: float = sd.get_room_integrity("gate_room")
	_expect(room_pre_repair == 40.0, "gate_room integrity == 40.0 before repair (got %f)" % room_pre_repair)

	# Start weld repair.
	var started: bool = bool(sd.call("start_repair", "gate_room", "weld"))
	_expect(started, "start_repair for weld on gate_room succeeded")
	_expect(bool(sd.call("is_repair_active", "gate_room")), "is_repair_active returns true for gate_room")
	# Can't start a second repair on the same room.
	var double_start: bool = bool(sd.call("start_repair", "gate_room", "patch"))
	_expect(not double_start, "start_repair rejected when repair already active")

	# Progress check before ticking.
	var progress_before: float = float(sd.call("get_repair_progress", "gate_room"))
	_expect(progress_before == 0.0, "repair progress == 0.0 at start (got %f)" % progress_before)

	# Tick the repair to completion (weld duration = 3.0 seconds).
	var completed: Array = sd.call("test_advance", 3.0)
	_expect(not completed.is_empty(), "test_advance returned completed repairs")
	_expect(String(completed[0]) == "gate_room", "completed repair is gate_room")
	_expect(not bool(sd.call("is_repair_active", "gate_room")), "is_repair_active returns false after completion")

	# Weld restores: hull +5, room +25.
	# Hull: 76 + 5 = 81. Room: 40 + 25 = 65.
	var hull_post: float = sd.get_hull_integrity()
	_expect(hull_post == 81.0, "hull == 81.0 after weld repair (got %f)" % hull_post)
	var room_post: float = sd.get_room_integrity("gate_room")
	_expect(room_post == 65.0, "gate_room integrity == 65.0 after weld repair (got %f)" % room_post)

	# --- Repair cost ----------------------------------------------------------
	var weld_cost: int = int(sd.call("get_repair_cost", "weld"))
	_expect(weld_cost == 1, "weld parts_cost == 1 (got %d)" % weld_cost)
	var realign_cost: int = int(sd.call("get_repair_cost", "realign"))
	_expect(realign_cost == 0, "realign parts_cost == 0 (got %d)" % realign_cost)

	# --- Enum-based repair ----------------------------------------------------
	sd.call("reset")
	sd.call("apply_damage", "combat", "infirmary")
	var started_enum: bool = bool(sd.call("start_repair_enum", "infirmary", PATCH))
	_expect(started_enum, "start_repair_enum for PATCH succeeded")
	var completed_enum: Array = sd.call("test_advance", 2.0)
	_expect(not completed_enum.is_empty(), "test_advance completed patch repair")
	# Patch: hull +3, room +15. Combat damage: hull -5, room -15.
	# After damage: hull 95, room 85. After patch: hull 98, room 100.
	var hull_enum: float = sd.get_hull_integrity()
	_expect(hull_enum == 98.0, "hull == 98.0 after enum patch repair (got %f)" % hull_enum)

	# --- GameState.hull_percent published -------------------------------------
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload is attached")
	if gs != null:
		sd.call("reset")
		sd.call("apply_damage", "meteor_impact", "gate_room")
		# hull: 100 - 8 = 92 → 92%
		var gs_hull: float = float(gs.get("hull_percent"))
		_expect(gs_hull == 92.0, "GameState.hull_percent == 92.0 after damage (got %f)" % gs_hull)
		# Repair and check it updates.
		sd.call("start_repair", "gate_room", "weld")
		sd.call("test_advance", 3.0)
		# hull: 92 + 5 = 97
		gs_hull = float(gs.get("hull_percent"))
		_expect(gs_hull == 97.0, "GameState.hull_percent == 97.0 after repair (got %f)" % gs_hull)

	# --- Save round-trip ------------------------------------------------------
	sd.call("reset")
	sd.call("apply_damage", "meteor_impact", "gate_room")
	sd.call("apply_damage", "combat", "infirmary")
	var serialized: Dictionary = sd.call("serialize")
	_expect(serialized.has("hull_integrity"), "serialize has 'hull_integrity'")
	_expect(serialized.has("room_integrity"), "serialize has 'room_integrity'")
	_expect(serialized.has("active_repairs"), "serialize has 'active_repairs'")

	# Capture state before deserialize.
	var hull_ser: float = sd.get_hull_integrity()
	var gate_ser: float = sd.get_room_integrity("gate_room")
	var infirmary_ser: float = sd.get_room_integrity("infirmary")

	# Reset then deserialize.
	sd.call("reset")
	sd.call("deserialize", serialized, 1)
	_expect(sd.get_hull_integrity() == hull_ser, "hull_integrity restored after deserialize")
	_expect(sd.get_room_integrity("gate_room") == gate_ser, "gate_room integrity restored after deserialize")
	_expect(sd.get_room_integrity("infirmary") == infirmary_ser, "infirmary integrity restored after deserialize")

	# --- Active repair persistence --------------------------------------------
	sd.call("reset")
	sd.call("apply_damage", "meteor_impact", "gate_room")
	sd.call("start_repair", "gate_room", "weld")
	var repair_ser: Dictionary = sd.call("serialize")
	var active_ser: Dictionary = repair_ser.get("active_repairs", {})
	_expect(active_ser.has("gate_room"), "serialize captured active repair for gate_room")
	sd.call("reset")
	sd.call("deserialize", repair_ser, 1)
	_expect(bool(sd.call("is_repair_active", "gate_room")), "active repair restored after deserialize")

	# --- Reset clears everything ----------------------------------------------
	sd.call("reset")
	_expect(sd.get_hull_integrity() == 100.0, "hull_integrity == 100.0 after reset (got %f)" % sd.get_hull_integrity())
	_expect(int(sd.get_room_damage_state_int("gate_room")) == PRISTINE, "gate_room is PRISTINE after reset")
	_expect(not bool(sd.call("is_repair_active", "gate_room")), "no active repairs after reset")
	_expect(sd.get_room_integrity("gate_room") == 100.0, "gate_room integrity == 100.0 after reset")

	# --- Repair progress fraction --------------------------------------------
	sd.call("reset")
	sd.call("apply_damage", "meteor_impact", "gate_room")
	sd.call("start_repair", "gate_room", "weld")
	# weld duration = 3.0s. After 1.5s, progress should be 0.5.
	sd.call("test_advance", 1.5)
	var prog: float = float(sd.call("get_repair_progress", "gate_room"))
	_expect(prog >= 0.49 and prog <= 0.51, "repair progress ~0.5 at halfway (got %f)" % prog)
	# Complete the repair.
	sd.call("test_advance", 1.5)
	prog = float(sd.call("get_repair_progress", "gate_room"))
	_expect(prog == 0.0, "repair progress == 0.0 when no active repair (got %f)" % prog)

	# --- Unknown room damage (hull only) --------------------------------------
	sd.call("reset")
	var unknown_dealt: float = float(sd.call("apply_damage", "meteor_impact", "nonexistent_room"))
	_expect(unknown_dealt == 8.0, "damage to unknown room still deals hull damage (got %f)" % unknown_dealt)
	_expect(sd.get_hull_integrity() == 92.0, "hull_integrity == 92.0 after damage to unknown room (got %f)" % sd.get_hull_integrity())

	# --- get_all_room_integrity returns dict ----------------------------------
	sd.call("reset")
	var all_int: Dictionary = sd.call("get_all_room_integrity")
	_expect(not all_int.is_empty(), "get_all_room_integrity returns non-empty dict")
	_expect(all_int.has("gate_room"), "get_all_room_integrity has gate_room")

	# --- Repair above CRITICAL clears section damage --------------------------
	if pg != null:
		sd.call("reset")
		pg.call("reset")
		# Damage gate_room to DESTROYED.
		sd.call("apply_damage", "meteor_impact", "gate_room")
		sd.call("apply_damage", "meteor_impact", "gate_room")
		sd.call("apply_damage", "meteor_impact", "gate_room")
		sd.call("apply_damage", "meteor_impact", "gate_room")
		# gate_room at 20% → DESTROYED → section damaged in PowerGrid.
		_expect(not bool(pg.call("is_room_powered", "gate_room")), "gate_room OFFLINE when DESTROYED")
		# Repair gate_room above CRITICAL (above 50%).
		# Room at 20. Need to restore to > 50. max is 100, so > 50.
		# Weld restores 25: 20 + 25 = 45 (still CRITICAL).
		sd.call("start_repair", "gate_room", "weld")
		sd.call("test_advance", 3.0)
		# 45 → still CRITICAL, section still damaged.
		_expect(int(sd.get_room_damage_state_int("gate_room")) == CRITICAL, "gate_room CRITICAL after 1 weld (45%%)")
		# Another weld: 45 + 25 = 70 → DAMAGED (above 50% → clears section).
		sd.call("start_repair", "gate_room", "weld")
		sd.call("test_advance", 3.0)
		# 70% → DAMAGED (above 50%) → _update_room_damage_state calls _repair_section.
		var gate_state_final: int = int(sd.get_room_damage_state_int("gate_room"))
		_expect(gate_state_final == DAMAGED, "gate_room DAMAGED after 2nd weld (70%%) (state=%d)" % gate_state_final)
		# Section damage should be cleared (conduit may still be damaged from random chance).
		# Check that PowerGrid no longer has section damage for gate_room.
		var damaged_sections: Array[String] = pg.call("get_damaged_sections")
		_expect(not damaged_sections.has("gate_room"), "gate_room section damage cleared after repair above CRITICAL")

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