extends SceneTree

# Smoke test for the elevator power-restore mechanic (issue #132).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/elevator_power.gd
#
# Assertions (plan §7):
#   A) Offline by default — unlock_floor(3) blocked, parts NOT spent.
#   B) has_elevator_fuses gating — none / partial / full.
#   C) Mini-game stub gating — fuses NOT consumed until minigame solved.
#   D) restore_elevator_power → powered → unlock works; fuses consumed exactly
#      once; idempotent second restore call.
#   E) Floor 2 stairs unaffected — path_through_rooms(gate_room→hydroponics)
#      works while elevator offline; path excludes elevator_north.
#   F) Persistence round-trip — elevator_powered + minigame_solved survive
#      serialize → reset → deserialize.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== elevator_power smoke test ===")

	var ps: Node = root.get_node_or_null("ProceduralShip")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(ps != null, "ProceduralShip autoload reachable")
	_expect(inv != null, "Inventory autoload reachable")
	if ps == null or inv == null:
		_report()
		return

	# Fresh state for every sub-test.
	ps.call("reset")
	await process_frame

	await _test_offline_blocks_unlock(ps, inv)
	await _test_fuse_gating(ps, inv)
	await _test_minigame_gating(ps, inv)
	await _test_full_restore_and_idempotent(ps, inv)
	await _test_stairs_unaffected(ps, inv)
	await _test_persistence_round_trip(ps, inv)

	_report()


# ── A: Offline by default + unlock_floor(3) blocked, parts not spent ──────────

func _test_offline_blocks_unlock(ps: Node, inv: Node) -> void:
	print("\n-- A: offline by default --")
	ps.call("reset")
	await process_frame

	_expect(not ps.call("is_elevator_powered"), "elevator starts unpowered after reset")
	_expect(not ps.call("is_elevator_minigame_solved"), "minigame starts unsolved after reset")

	# generate floor 3 so unlock_floor can run its full path.
	ps.call("ensure_floor_generated", 3)
	await process_frame
	ps.call("mark_floor_code_known", 3)

	inv.call("set_count", "parts", 50)
	var ok: bool = ps.call("unlock_floor", 3)
	_expect(not ok, "unlock_floor(3) returns false while elevator offline")
	_expect(not ps.call("is_floor_unlocked", 3), "floor 3 still locked (offline)")
	_expect(inv.call("count", "parts") == 50, "parts NOT spent on offline-blocked unlock attempt")


# ── B: has_elevator_fuses gating — none / partial / full ─────────────────────

func _test_fuse_gating(ps: Node, inv: Node) -> void:
	print("\n-- B: fuse gating --")
	ps.call("reset")
	await process_frame

	# Clear fuses.
	inv.call("set_count", "large_fuse", 0)
	inv.call("set_count", "bus_fuse", 0)
	_expect(not ps.call("has_elevator_fuses"), "has_elevator_fuses false with no fuses")

	# Partial: only large_fuse (still need 2x bus_fuse).
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 0)
	_expect(not ps.call("has_elevator_fuses"), "has_elevator_fuses false with only large_fuse (missing bus_fuse)")

	# Partial: both types but insufficient bus_fuse count.
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 1)
	_expect(not ps.call("has_elevator_fuses"), "has_elevator_fuses false with 1 bus_fuse (need 2)")

	# Full requirement met.
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 2)
	_expect(ps.call("has_elevator_fuses"), "has_elevator_fuses true with 1x large_fuse + 2x bus_fuse")


# ── C: Mini-game gating — fuses NOT consumed until minigame solved ─────────────

func _test_minigame_gating(ps: Node, inv: Node) -> void:
	print("\n-- C: minigame gating --")
	ps.call("reset")
	await process_frame

	# Seat full fuses but do NOT solve mini-game.
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 2)
	_expect(ps.call("has_elevator_fuses"), "fuses seated before restore attempt")
	_expect(not ps.call("is_elevator_minigame_solved"), "minigame not solved yet")

	var ok: bool = ps.call("restore_elevator_power")
	_expect(not ok, "restore_elevator_power returns false when minigame not solved")
	_expect(not ps.call("is_elevator_powered"), "elevator still offline after failed restore")

	# Fuses must NOT have been consumed.
	_expect(inv.call("count", "large_fuse") == 1, "large_fuse NOT consumed on failed restore (no minigame)")
	_expect(inv.call("count", "bus_fuse") == 2, "bus_fuse NOT consumed on failed restore (no minigame)")


# ── D: Full restore + idempotent + fuses consumed exactly once ─────────────────

func _test_full_restore_and_idempotent(ps: Node, inv: Node) -> void:
	print("\n-- D: full restore + idempotent --")
	ps.call("reset")
	await process_frame

	# Provide required fuses + solve mini-game.
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 2)
	inv.call("set_count", "parts", 0)
	ps.call("solve_elevator_minigame")
	_expect(ps.call("is_elevator_minigame_solved"), "solve_elevator_minigame marks minigame solved")

	var ok: bool = ps.call("restore_elevator_power")
	_expect(ok, "restore_elevator_power returns true with fuses + minigame")
	_expect(ps.call("is_elevator_powered"), "elevator is powered after restore")

	# Fuses consumed exactly once.
	_expect(inv.call("count", "large_fuse") == 0, "large_fuse consumed after successful restore")
	_expect(inv.call("count", "bus_fuse") == 0, "bus_fuse consumed after successful restore")

	# Idempotent — second call must return true without re-consuming or erroring.
	var ok2: bool = ps.call("restore_elevator_power")
	_expect(ok2, "restore_elevator_power idempotent (returns true when already powered)")
	_expect(inv.call("count", "large_fuse") == 0, "large_fuse count unchanged on idempotent call")
	_expect(inv.call("count", "bus_fuse") == 0, "bus_fuse count unchanged on idempotent call")

	# Now unlock_floor should work (code + parts required but power gate cleared).
	ps.call("ensure_floor_generated", 3)
	await process_frame
	ps.call("mark_floor_code_known", 3)
	var cost3: int = ps.call("floor_unlock_cost", 3)
	inv.call("set_count", "parts", cost3)
	var unlock_ok: bool = ps.call("unlock_floor", 3)
	_expect(unlock_ok, "unlock_floor(3) succeeds after elevator powered (code known + parts)")
	_expect(ps.call("is_floor_unlocked", 3), "floor 3 is unlocked after powered unlock")
	_expect(inv.call("count", "parts") == 0, "parts deducted after powered unlock")


# ── E: Floor 2 stairs unaffected while elevator offline ───────────────────────

func _test_stairs_unaffected(ps: Node, inv: Node) -> void:
	print("\n-- E: stairs unaffected while offline --")
	ps.call("reset")
	ps.call("ensure_floor_generated", 2)
	await process_frame

	# Elevator must be offline.
	_expect(not ps.call("is_elevator_powered"), "elevator offline for stairs test")

	# Floor 2 is still unlocked via stairs (unlocked=true in reset).
	_expect(ps.call("is_floor_unlocked", 2), "floor 2 unlocked (stairs bypass) while elevator offline")

	# path_through_rooms gate_room → hydroponics must work offline.
	var path: PackedStringArray = ps.call("path_through_rooms", "gate_room", "hydroponics")
	_expect(path.size() > 0, "path gate_room→hydroponics non-empty while elevator offline (got %d hops)" % path.size())

	# The path must NOT go through elevator_north (proves stairs route, not elevator).
	var uses_elevator: bool = false
	for room_id: String in path:
		if room_id == "elevator_north":
			uses_elevator = true
	_expect(not uses_elevator, "path gate_room→hydroponics excludes elevator_north while offline")

	# The path should pass through the obs-deck entry (f2_r00) confirming stairs.
	var obs_id: String = ps.call("floor2_obs_entry_id")
	_expect(obs_id != "", "floor2_obs_entry_id non-empty after floor 2 generated")
	if obs_id != "":
		var via_obs: bool = false
		for room_id: String in path:
			if room_id == obs_id:
				via_obs = true
		_expect(via_obs, "path gate_room→hydroponics passes through obs-deck (%s) via stairs" % obs_id)


# ── F: Persistence round-trip ─────────────────────────────────────────────────

func _test_persistence_round_trip(ps: Node, inv: Node) -> void:
	print("\n-- F: persistence round-trip --")
	ps.call("reset")
	await process_frame

	# Restore power so we have a non-default state to round-trip.
	inv.call("set_count", "large_fuse", 1)
	inv.call("set_count", "bus_fuse", 2)
	ps.call("solve_elevator_minigame")
	ps.call("restore_elevator_power")
	_expect(ps.call("is_elevator_powered"), "powered before snapshot")
	_expect(ps.call("is_elevator_minigame_solved"), "minigame solved before snapshot")

	var snap: Dictionary = ps.call("serialize")
	_expect(snap.has("elevator_powered"), "serialize includes 'elevator_powered' key")
	_expect(snap.has("minigame_solved"), "serialize includes 'minigame_solved' key")
	_expect(snap.get("elevator_powered", false) == true, "snapshot elevator_powered = true")
	_expect(snap.get("minigame_solved", false) == true, "snapshot minigame_solved = true")

	# Reset wipes state.
	ps.call("reset")
	_expect(not ps.call("is_elevator_powered"), "elevator offline after reset")
	_expect(not ps.call("is_elevator_minigame_solved"), "minigame unsolved after reset")

	# Deserialize restores.
	ps.call("deserialize", snap, 2)
	await process_frame
	_expect(ps.call("is_elevator_powered"), "elevator powered restored after deserialize")
	_expect(ps.call("is_elevator_minigame_solved"), "minigame solved restored after deserialize")

	# Also verify that absent keys default to false (backwards-compat with old saves).
	var old_snap: Dictionary = {"floors": {}, "rooms": {}, "edges": {}}
	ps.call("reset")
	ps.call("deserialize", old_snap, 2)
	await process_frame
	_expect(not ps.call("is_elevator_powered"), "absent elevator_powered key defaults to false (old save compat)")
	_expect(not ps.call("is_elevator_minigame_solved"), "absent minigame_solved key defaults to false (old save compat)")


# ── helpers ───────────────────────────────────────────────────────────────────

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
