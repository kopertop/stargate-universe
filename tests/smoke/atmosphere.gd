extends SceneTree

# Pure-state smoke test for the per-room atmosphere readout (issue #47).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/atmosphere.gd
#
# Asserts GameState.room_atmosphere() derives the right dict per E1 rules:
#   • A nominal room is breathable N2/O2 NOMINAL.
#   • The unsealed south breach reads as VENTING / VACUUM / not breathable;
#     sealing it flips the SAME room back to NOMINAL + breathable (the core
#     "breached section reads differently before it's sealed" behaviour).
#   • During the air crisis (pre-repair) every non-breached room reads DEGRADED
#     with elevated CO2; repairing the scrubber clears it.
#   • An authored `atmosphere` override on a ShipLayout row merges over the base.
#   • The readout is derived — it tracks live oxygen with no stored state.
#
# Uses the live autoloads (GameState + ShipLayout) like inventory.gd / e1_flow.gd.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== atmosphere smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var sl: Node = root.get_node_or_null("ShipLayout")
	_expect(gs != null, "GameState autoload attached")
	_expect(sl != null, "ShipLayout autoload attached")
	if gs == null or sl == null:
		_report()
		return

	gs.reset()

	# --- 1. nominal room ---------------------------------------------------
	var nominal: Dictionary = gs.call("room_atmosphere", "control_interface_room")
	_expect(String(nominal.get("status", "")) == "NOMINAL", "nominal room status NOMINAL")
	_expect(nominal.get("breathable", false) == true, "nominal room breathable")
	_expect(String(nominal.get("composition", "")) == "N2/O2 NOMINAL", "nominal room composition N2/O2 NOMINAL")
	_expect(int(nominal.get("oxygen", -1)) == int(round(float(gs.get("oxygen")))),
		"nominal room oxygen tracks live GameState.oxygen")

	# --- 2. unsealed breach reads VENTING / VACUUM -------------------------
	var breached: Dictionary = gs.call("room_atmosphere", "breached_section_south")
	_expect(String(breached.get("status", "")) == "VENTING", "unsealed breach status VENTING")
	_expect(String(breached.get("composition", "")) == "VACUUM", "unsealed breach composition VACUUM")
	_expect(breached.get("breathable", true) == false, "unsealed breach NOT breathable")
	_expect(int(breached.get("oxygen", -1)) == 0, "unsealed breach oxygen 0")
	_expect(String(breached.get("temperature_note", "")) == "FREEZING", "unsealed breach FREEZING")

	# --- 3. sealing the breach flips the SAME room to NOMINAL --------------
	gs.call("seal_breach", "breach_a")
	var sealed: Dictionary = gs.call("room_atmosphere", "breached_section_south")
	_expect(String(sealed.get("status", "")) == "NOMINAL", "sealed breach status NOMINAL")
	_expect(sealed.get("breathable", false) == true, "sealed breach breathable")
	_expect(String(sealed.get("composition", "")) != "VACUUM", "sealed breach no longer VACUUM")

	# --- 4. air crisis (pre-repair) reads DEGRADED elsewhere ---------------
	gs.call("reset")
	gs.set("air_crisis_started", true)
	gs.set("scrubber_repaired", false)
	var degraded: Dictionary = gs.call("room_atmosphere", "control_interface_room")
	_expect(String(degraded.get("status", "")) == "DEGRADED", "air-crisis room status DEGRADED")
	_expect(String(degraded.get("toxins", "")) == "CO2 ELEVATED", "air-crisis room toxins CO2 ELEVATED")
	# The breach still wins over the crisis (VENTING, not DEGRADED).
	var crisis_breach: Dictionary = gs.call("room_atmosphere", "breached_section_south")
	_expect(String(crisis_breach.get("status", "")) == "VENTING",
		"unsealed breach reads VENTING even during the crisis")

	# --- 5. repairing the scrubber clears DEGRADED -------------------------
	gs.set("scrubber_repaired", true)
	var repaired: Dictionary = gs.call("room_atmosphere", "control_interface_room")
	_expect(String(repaired.get("status", "")) == "NOMINAL", "post-repair room status NOMINAL")
	_expect(String(repaired.get("toxins", "")) == "NONE", "post-repair toxins NONE")

	# --- 6. authored override merges over the base -------------------------
	# Inject an authored atmosphere onto a layout row, then confirm the merge.
	gs.call("reset")
	var row: Dictionary = sl.call("room", "control_interface_room")
	if not row.is_empty():
		row["atmosphere"] = {"composition": "ARGON RICH", "radiation": "ELEVATED"}
		var merged: Dictionary = gs.call("room_atmosphere", "control_interface_room")
		_expect(String(merged.get("composition", "")) == "ARGON RICH",
			"authored composition override merges over base")
		_expect(String(merged.get("radiation", "")) == "ELEVATED",
			"authored radiation override merges over base")
		_expect(merged.get("breathable", false) == true,
			"unspecified base fields survive the merge (still breathable)")
		row.erase("atmosphere")
	else:
		_expect(false, "could not load control_interface_room layout row for override test")

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
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
