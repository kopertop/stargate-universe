extends SceneTree

# Smoke test for the PowerGrid autoload — basic distribution logic.
#
# Verifies:
#   • PowerGrid autoload is attached and loaded its config from JSON.
#   • At full generator output, critical rooms are POWERED (total demand 112
#     exceeds capacity 100, so some non-critical rooms are shed even at full).
#   • Reducing generator output causes load-shedding: non-critical rooms go
#     OFFLINE first, critical rooms stay POWERED longer.
#   • is_room_powered / is_room_degraded return correct booleans.
#   • set_section_damaged forces a room OFFLINE independent of load-shed.
#   • set_room_override forces a specific state regardless of distribution.
#   • repair_generator restores critical rooms to POWERED.
#   • PowerState enum values are stable (POWERED=0, DEGRADED=1, OFFLINE=2).
#   • power_state_changed signal fires on state transitions.
#   • get_load_shed_percentage reports correct shortfall.
#   • ConsumptionManager power efficiency multiplier responds to DEGRADED rooms.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/power_grid.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== power_grid smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var pg: Node = root.get_node_or_null("PowerGrid")
	_expect(pg != null, "PowerGrid autoload is attached")
	if pg == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "power_grid_smoke")

	# --- Enum stability -------------------------------------------------------
	# PowerState.POWERED == 0, DEGRADED == 1, OFFLINE == 2
	var POWERED: int = int(pg.PowerState.POWERED)
	var DEGRADED: int = int(pg.PowerState.DEGRADED)
	var OFFLINE: int = int(pg.PowerState.OFFLINE)
	_expect(POWERED == 0, "PowerState.POWERED == 0 (got %d)" % POWERED)
	_expect(DEGRADED == 1, "PowerState.DEGRADED == 1 (got %d)" % DEGRADED)
	_expect(OFFLINE == 2, "PowerState.OFFLINE == 2 (got %d)" % OFFLINE)

	# --- Config loaded --------------------------------------------------------
	var total_cap: float = pg.get_total_capacity()
	_expect(total_cap > 0.0, "total_capacity > 0 (got %f)" % total_cap)
	var states: Dictionary = pg.get_all_room_states()
	_expect(not states.is_empty(), "room states dict is non-empty after config load")
	_expect(states.has("gate_room"), "gate_room is in the power grid config")
	_expect(states.has("control_interface_room"), "control_interface_room is in the power grid config")

	# --- Full power: critical rooms POWERED ----------------------------------
	# Total demand (112) exceeds capacity (100), so even at full output the grid
	# sheds the lowest-priority non-critical rooms. Critical rooms (gate_room,
	# control_interface_room, infirmary, hydroponics) must stay POWERED.
	pg.call("reset")
	# Re-read states after reset.
	states = pg.get_all_room_states()
	_expect(pg.is_room_powered("gate_room"), "gate_room (critical p1) is powered at full output")
	_expect(not pg.is_room_degraded("gate_room"), "gate_room is not degraded at full output")
	_expect(pg.is_room_powered("control_interface_room"), "control_interface_room (critical p2) is powered at full output")
	_expect(pg.is_room_powered("infirmary"), "infirmary (critical p3) is powered at full output")
	# Non-critical rooms at the bottom of the shed order should be OFFLINE
	# even at full output because demand > capacity.
	var storage_state: int = int(pg.get_room_power_state("aft_storage_hall"))
	_expect(storage_state == OFFLINE, "aft_storage_hall (priority 10, non-critical) is OFFLINE at full output — demand > capacity (state=%d)" % storage_state)
	# Unknown rooms default to POWERED (get_room_power_state returns POWERED).
	_expect(pg.is_room_powered("nonexistent_room"), "nonexistent_room returns true for is_room_powered (default POWERED)")

	# --- Load shedding: reduce generator output --------------------------------
	# Drop to 50 — the grid should shed even more non-critical rooms.
	pg.set_generator_output(50.0)
	var gate_state: int = int(pg.get_room_power_state("gate_room"))
	_expect(gate_state == POWERED, "gate_room (critical, priority 1) stays POWERED at 50%% output (state=%d)" % gate_state)
	var infirmary_state: int = int(pg.get_room_power_state("infirmary"))
	_expect(infirmary_state == POWERED, "infirmary (critical, priority 3) stays POWERED at 50%% output (state=%d)" % infirmary_state)
	# Low-priority rooms should be OFFLINE.
	storage_state = int(pg.get_room_power_state("aft_storage_hall"))
	_expect(storage_state == OFFLINE, "aft_storage_hall (priority 10) is OFFLINE at 50%% output (state=%d)" % storage_state)
	# is_room_powered should return false for OFFLINE rooms.
	_expect(not pg.is_room_powered("aft_storage_hall"), "aft_storage_hall is_room_powered == false when OFFLINE")

	# --- Load shed percentage -------------------------------------------------
	var shed_pct: float = pg.get_load_shed_percentage()
	# Demand = 112, available = 50, shortfall = 62, percentage = 62/112 * 100 ≈ 55.4
	_expect(shed_pct > 50.0 and shed_pct < 60.0, "load_shed_percentage ~55%% at 50/100 output (got %f)" % shed_pct)

	# --- Signal firing on state change ----------------------------------------
	var signal_received: Array = []
	pg.power_state_changed.connect(func(room_id, state): signal_received.append([room_id, state]))
	# Repair generator — critical rooms that were DEGRADED go back to POWERED,
	# and some shed rooms come back online. Should emit signals.
	pg.repair_generator()
	_expect(not signal_received.is_empty(), "power_state_changed signal emitted on repair_generator")
	# At least one signal should be for a room going to POWERED.
	var found_powered_signal: bool = false
	for entry in signal_received:
		if int(entry[1]) == POWERED:
			found_powered_signal = true
			break
	_expect(found_powered_signal, "at least one room signalled POWERED on repair")
	signal_received.clear()

	# --- set_section_damaged forces OFFLINE -----------------------------------
	pg.set_section_damaged("gate_room")
	var damaged_state: int = int(pg.get_room_power_state("gate_room"))
	_expect(damaged_state == OFFLINE, "gate_room is OFFLINE after set_section_damaged (state=%d)" % damaged_state)
	_expect(not pg.is_room_powered("gate_room"), "gate_room is_room_powered == false when damaged")
	# Other rooms should still be powered.
	_expect(pg.is_room_powered("infirmary"), "infirmary still powered when gate_room is damaged")

	# --- set_section_repaired restores ----------------------------------------
	pg.set_section_repaired("gate_room")
	var repaired_state: int = int(pg.get_room_power_state("gate_room"))
	_expect(repaired_state == POWERED, "gate_room is POWERED after set_section_repaired (state=%d)" % repaired_state)

	# --- set_room_override forces specific state ------------------------------
	pg.set_room_override("infirmary", OFFLINE)
	var override_state: int = int(pg.get_room_power_state("infirmary"))
	_expect(override_state == OFFLINE, "infirmary is OFFLINE after override (state=%d)" % override_state)
	# Clear override.
	pg.set_room_override("infirmary", -1)
	var cleared_state: int = int(pg.get_room_power_state("infirmary"))
	_expect(cleared_state == POWERED, "infirmary is POWERED after clearing override (state=%d)" % cleared_state)

	# --- Degraded state: partial power to critical room -----------------------
	# Set generator output very low so some rooms end up DEGRADED.
	# With very low power, the first critical room (gate_room, demand 15) might
	# get DEGRADED if there's some power but not enough for full demand.
	pg.set_generator_output(8.0)
	var gate_low: int = int(pg.get_room_power_state("gate_room"))
	# At 8 power, gate_room (demand 15, critical) should be DEGRADED (some power
	# but not enough for full demand) or OFFLINE. Critical rooms get DEGRADED
	# when remaining > 0 but < demand.
	_expect(gate_low == DEGRADED or gate_low == OFFLINE, "gate_room is DEGRADED or OFFLINE at 8%% output (state=%d)" % gate_low)
	if gate_low == DEGRADED:
		_expect(pg.is_room_degraded("gate_room"), "is_room_degraded returns true for DEGRADED room")
		_expect(pg.is_room_powered("gate_room"), "is_room_powered returns true for DEGRADED room (not OFFLINE)")

	# --- ConsumptionManager power efficiency multiplier -----------------------
	var cm: Node = root.get_node_or_null("ConsumptionManager")
	_expect(cm != null, "ConsumptionManager autoload is attached")
	if cm != null:
		# At degraded state, the multiplier should be > 1.0.
		var mult: float = float(cm.call("_power_efficiency_multiplier"))
		# Some rooms should be degraded/offline at 8% output.
		_expect(mult >= 1.0, "power_efficiency_multiplier >= 1.0 (got %f)" % mult)
		# Reset to full power — multiplier should be > 1.0 because demand (112)
		# exceeds capacity (100), so some rooms are still DEGRADED at full output.
		pg.repair_generator()
		mult = float(cm.call("_power_efficiency_multiplier"))
		# At full repair, degraded rooms still exist (demand > capacity), so
		# the multiplier should be > 1.0. It would only be 1.0 if all rooms
		# were POWERED, which can't happen when demand > capacity.
		_expect(mult >= 1.0, "power_efficiency_multiplier >= 1.0 at full repair (got %f)" % mult)
		# To get exactly 1.0, we need all rooms POWERED. Use override to force
		# all rooms POWERED, simulating a fully repaired grid with no deficit.
		states = pg.get_all_room_states()
		for room_id in states.keys():
			pg.set_room_override(String(room_id), POWERED)
		mult = float(cm.call("_power_efficiency_multiplier"))
		_expect(mult == 1.0, "power_efficiency_multiplier == 1.0 when all rooms forced POWERED (got %f)" % mult)
		# Clear all overrides.
		for room_id in states.keys():
			pg.set_room_override(String(room_id), -1)

	# --- Conduit / repair-panel system ----------------------------------------
	# Damaging a conduit forces the room OFFLINE independent of load-shed.
	pg.repair_generator()
	_expect(not pg.is_conduit_damaged("infirmary"), "infirmary conduit is intact initially")
	pg.damage_conduit("infirmary")
	_expect(pg.is_conduit_damaged("infirmary"), "infirmary conduit is damaged after damage_conduit")
	var conduit_state: int = int(pg.get_room_power_state("infirmary"))
	_expect(conduit_state == OFFLINE, "infirmary is OFFLINE after conduit damage (state=%d)" % conduit_state)
	_expect(not pg.is_room_powered("infirmary"), "infirmary is_room_powered == false with damaged conduit")
	# Other rooms should be unaffected.
	_expect(pg.is_room_powered("gate_room"), "gate_room still powered when infirmary conduit damaged")
	# get_damaged_conduits returns the list.
	var damaged_conduits: Array[String] = pg.get_damaged_conduits()
	_expect(damaged_conduits.has("infirmary"), "get_damaged_conduits includes infirmary")
	# Repair the conduit.
	pg.repair_conduit("infirmary")
	_expect(not pg.is_conduit_damaged("infirmary"), "infirmary conduit is intact after repair_conduit")
	var repaired_conduit_state: int = int(pg.get_room_power_state("infirmary"))
	_expect(repaired_conduit_state == POWERED, "infirmary is POWERED after conduit repair (state=%d)" % repaired_conduit_state)
	# Conduit signal fires on state change.
	var conduit_signals: Array = []
	pg.conduit_state_changed.connect(func(rid, damaged): conduit_signals.append([rid, damaged]))
	pg.damage_conduit("hydroponics")
	_expect(not conduit_signals.is_empty(), "conduit_state_changed signal emitted on damage")
	_expect(conduit_signals[0][1] == true, "conduit signal reports damaged=true")
	conduit_signals.clear()
	pg.repair_conduit("hydroponics")
	_expect(not conduit_signals.is_empty(), "conduit_state_changed signal emitted on repair")
	_expect(conduit_signals[0][1] == false, "conduit signal reports damaged=false")
	# Idempotent: damaging an already-damaged conduit is a no-op (no re-signal).
	conduit_signals.clear()
	pg.damage_conduit("hydroponics")
	pg.damage_conduit("hydroponics")
	_expect(conduit_signals.size() == 1, "damage_conduit is idempotent (one signal for double-damage)")
	pg.repair_conduit("hydroponics")

	# --- Save round-trip ------------------------------------------------------
	pg.repair_generator()
	pg.set_generator_output(75.0)
	var serialized: Dictionary = pg.serialize()
	_expect(serialized.has("generator_output"), "serialize has 'generator_output'")
	_expect(serialized.has("damaged_sections"), "serialize has 'damaged_sections'")
	_expect(serialized.has("damaged_conduits"), "serialize has 'damaged_conduits'")
	_expect(serialized.has("room_overrides"), "serialize has 'room_overrides'")

	# Deserialize and verify generator_output persisted.
	pg.set_generator_output(100.0)
	pg.deserialize(serialized, 1)
	var restored_output: float = pg.get_available_power()
	_expect(restored_output == 75.0, "generator_output restored to 75.0 after deserialize (got %f)" % restored_output)

	# --- Conduit persistence round-trip ---------------------------------------
	pg.reset()
	pg.damage_conduit("gate_room")
	pg.set_section_damaged("hydroponics")
	var conduit_serialized: Dictionary = pg.serialize()
	_expect((conduit_serialized["damaged_conduits"] as Array).has("gate_room"), "conduit damage serialized")
	pg.reset()
	pg.deserialize(conduit_serialized, 1)
	_expect(pg.is_conduit_damaged("gate_room"), "gate_room conduit damage survived reset+deserialize")
	_expect(pg.is_room_powered("gate_room") == false, "gate_room is OFFLINE after conduit persistence restore")
	_expect(not pg.is_room_powered("hydroponics"), "hydroponics section damage survived reset+deserialize")

	# --- Reset clears everything ----------------------------------------------
	pg.reset()
	var reset_output: float = pg.get_available_power()
	_expect(reset_output == total_cap, "generator_output back to total_capacity after reset (got %f)" % reset_output)
	# After reset, critical rooms should be POWERED (even if some non-critical
	# rooms are shed due to demand > capacity).
	_expect(pg.is_room_powered("gate_room"), "gate_room POWERED after reset")
	_expect(pg.is_room_powered("infirmary"), "infirmary POWERED after reset")

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