extends SceneTree

# Smoke test for ProceduralShip (Phase A): generated multi-floor topology,
# save round-trip, and base-room passthrough.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/test_procedural_ship.gd
#
# Assertions:
#   (a) door-overlap: every generated edge's parent/child rectangles overlap on
#       the shared axis (hi > lo) so _door_along_offset never falls back to 0.
#   (b) special pool: special_once types appear at most max_count=1 across two
#       generated floors; special_limited never exceed their max_count; each
#       floor has <= 3 specials placed.
#   (c) save round-trip: generate floor 2, serialize(), reset(), deserialize(),
#       assert floor 2 rooms/edges are identical.
#   (d) base passthrough: ProceduralShip.room("east_corridor") equals
#       ShipLayout.room("east_corridor") byte-for-byte; door_edges produces a
#       superset that includes all targets that room.gd's old two-loop code
#       would have stamped.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== procedural_ship smoke test ===")

	var ps: Node = root.get_node_or_null("ProceduralShip")
	var sl: Node = root.get_node_or_null("ShipLayout")
	_expect(ps != null, "ProceduralShip autoload attached")
	_expect(sl != null, "ShipLayout autoload attached")
	if ps == null or sl == null:
		_report()
		return

	# Ensure a clean state.
	ps.call("reset")
	await process_frame

	_test_base_passthrough(ps, sl)
	await _test_floor_generation(ps)
	await _test_special_pool_limits(ps)
	await _test_save_round_trip(ps)
	await _test_floor_unlock(ps)
	await _test_assign_function(ps)
	await _test_floor_code_poi(ps)
	await _test_key_rooms(ps)

	_report()


# ── (d) Base passthrough ─────────────────────────────────────────────────────

func _test_base_passthrough(ps: Node, sl: Node) -> void:
	print("\n-- base passthrough --")

	var ec_ps: Dictionary = ps.call("room", "east_corridor")
	var ec_sl: Dictionary = sl.call("room", "east_corridor")
	_expect(not ec_ps.is_empty(), "ProceduralShip.room(east_corridor) is non-empty")
	_expect(not ec_sl.is_empty(), "ShipLayout.room(east_corridor) is non-empty")
	_expect(ec_ps.has("startX") and int(ec_ps.get("startX", -1)) == int(ec_sl.get("startX", -2)),
		"ProceduralShip delegates startX correctly for east_corridor")
	_expect(ec_ps.has("template_id") and String(ec_ps.get("template_id", "")) == String(ec_sl.get("template_id", "")),
		"ProceduralShip delegates template_id correctly for east_corridor")

	# door_edges must include all targets that room.gd's original two-loop code
	# would have stamped. For east_corridor the JSON declares:
	#   forward:  +x→north_corridor, +x→south_corridor, -x→east_corridor_far
	#   reverse:  stargate_corridor_east_connector declares -x→east_corridor (so
	#             east_corridor gets a reverse +x→stargate_corridor_east_connector)
	var expected_targets: Array = [
		"north_corridor", "south_corridor", "east_corridor_far",
		"stargate_corridor_east_connector",
	]
	var door_edges: Array = ps.call("door_edges", "east_corridor")
	_expect(door_edges.size() >= expected_targets.size(),
		"door_edges(east_corridor) has >= %d entries (got %d)" % [expected_targets.size(), door_edges.size()])

	var targets_seen: Array = []
	for e in door_edges:
		var d: Dictionary = e
		targets_seen.append(String(d.get("to", "")))

	for expected in expected_targets:
		_expect(targets_seen.has(expected),
			"door_edges(east_corridor) includes target %s" % expected)

	# Forward edges from east_corridor should retain their plaque keys.
	# Reverse edges (no plaque key) are also included — verify forward entries
	# have a plaque key present.
	var forward_has_plaque: bool = false
	for e in door_edges:
		var d: Dictionary = e
		if String(d.get("to", "")) == "north_corridor" and d.has("plaque"):
			forward_has_plaque = true
	_expect(forward_has_plaque, "forward edge to north_corridor has plaque key")

	# Reverse edges should NOT have a plaque key (room.gd auto-derives the name).
	var reverse_no_plaque: bool = false
	for e in door_edges:
		var d: Dictionary = e
		if String(d.get("to", "")) == "stargate_corridor_east_connector" and not d.has("plaque"):
			reverse_no_plaque = true
	_expect(reverse_no_plaque,
		"reverse edge to stargate_corridor_east_connector has no plaque key")

	# ProceduralShip.is_generated("east_corridor") must be false.
	_expect(not ps.call("is_generated", "east_corridor"),
		"east_corridor is not marked as generated")


# ── (a) Door overlap ─────────────────────────────────────────────────────────

func _test_floor_generation(ps: Node) -> void:
	print("\n-- floor generation + door overlap --")

	ps.call("ensure_floor_generated", 2)
	await process_frame

	var floors: Dictionary = ps.get("_floors")
	_expect(floors.has(2), "floor 2 entry exists after ensure_floor_generated(2)")
	var floor2: Dictionary = floors.get(2, {})
	_expect(floor2.get("generated", false), "floor 2 is marked generated")

	var rooms_list: Array = floor2.get("rooms", [])
	_expect(rooms_list.size() >= 12, "floor 2 has >= 12 rooms (got %d)" % rooms_list.size())
	_expect(rooms_list.size() <= 20, "floor 2 has <= 20 rooms (got %d)" % rooms_list.size())

	# (a) Verify every generated edge has parent/child rects that overlap on
	# the shared axis — hi > lo — so _door_along_offset returns non-zero.
	var rooms_dict: Dictionary = ps.get("_rooms")
	var edges_dict: Dictionary = ps.get("_edges")
	var overlap_failures: int = 0
	var edge_count: int = 0

	for from_id in edges_dict.keys():
		var from_row: Dictionary = rooms_dict.get(String(from_id), {})
		if from_row.is_empty():
			continue
		var from_sx: int = int(from_row.get("startX", 0))
		var from_ex: int = int(from_row.get("endX", 0))
		var from_sy: int = int(from_row.get("startY", 0))
		var from_ey: int = int(from_row.get("endY", 0))

		for edge in edges_dict[from_id] as Array:
			var e: Dictionary = edge
			var to_id: String = String(e.get("to", ""))
			var dir: String = String(e.get("dir", ""))
			var to_row: Dictionary = rooms_dict.get(to_id, {})
			if to_row.is_empty():
				continue
			var to_sx: int = int(to_row.get("startX", 0))
			var to_ex: int = int(to_row.get("endX", 0))
			var to_sy: int = int(to_row.get("startY", 0))
			var to_ey: int = int(to_row.get("endY", 0))

			var lo: int = 0
			var hi: int = 0
			if dir == "+x" or dir == "-x":
				lo = max(from_sy, to_sy)
				hi = min(from_ey, to_ey)
			else:
				lo = max(from_sx, to_sx)
				hi = min(from_ex, to_ex)

			edge_count += 1
			if hi <= lo:
				overlap_failures += 1
				print("  OVERLAP FAIL: %s -(%s)-> %s  lo=%d hi=%d" % [from_id, dir, to_id, lo, hi])

	_expect(edge_count > 0, "at least one generated edge exists (got %d)" % edge_count)
	_expect(overlap_failures == 0,
		"all %d generated edges have hi>lo overlap (failures: %d)" % [edge_count, overlap_failures])

	# Every generated room id should be marked is_generated.
	var gen_id_check_ok: bool = true
	for rid in rooms_list:
		if not ps.call("is_generated", String(rid)):
			gen_id_check_ok = false
	_expect(gen_id_check_ok, "all generated room ids are flagged is_generated")


# ── (b) Special pool limits ───────────────────────────────────────────────────

func _test_special_pool_limits(ps: Node) -> void:
	print("\n-- special pool limits --")

	# Generate floor 3 as well for cross-floor special_once check.
	ps.call("ensure_floor_generated", 3)
	await process_frame

	var rooms_dict: Dictionary = ps.get("_rooms")
	var catalog: Dictionary = {}
	for rt in ps.call("all_room_types") as Array:
		var d: Dictionary = rt
		catalog[String(d.get("id", ""))] = d

	# Count how many times each type appears across ALL generated floors.
	var type_count: Dictionary = {}
	for row in rooms_dict.values():
		var d: Dictionary = row
		var type_id: String = String(d.get("type", ""))
		if type_id == "":
			continue
		if not type_count.has(type_id):
			type_count[type_id] = 0
		type_count[type_id] = int(type_count[type_id]) + 1

	# Check special_once: max_count == 1 globally.
	var once_ok: bool = true
	for type_id in type_count.keys():
		var cat_row: Dictionary = catalog.get(String(type_id), {})
		if String(cat_row.get("category", "")) == "special_once":
			var cnt: int = int(type_count[type_id])
			if cnt > 1:
				once_ok = false
				print("  FAIL special_once %s appears %d times (max 1)" % [type_id, cnt])
	_expect(once_ok, "no special_once type appears more than once across all generated floors")

	# Check special_limited: max_count == 2 globally.
	var limited_ok: bool = true
	for type_id in type_count.keys():
		var cat_row: Dictionary = catalog.get(String(type_id), {})
		if String(cat_row.get("category", "")) == "special_limited":
			var max_c: int = int(cat_row.get("max_count", 2))
			var cnt: int = int(type_count[type_id])
			if cnt > max_c:
				limited_ok = false
				print("  FAIL special_limited %s appears %d times (max %d)" % [type_id, cnt, max_c])
	_expect(limited_ok, "no special_limited type exceeds its max_count across all generated floors")

	# Check per-floor specials_placed <= 3.
	var floors: Dictionary = ps.get("_floors")
	var per_floor_ok: bool = true
	for fn in floors.keys():
		var floor_rec: Dictionary = floors[fn]
		var sp: int = int(floor_rec.get("specials_placed", 0))
		if sp > 3:
			per_floor_ok = false
			print("  FAIL floor %s has specials_placed=%d (max 3)" % [fn, sp])
	_expect(per_floor_ok, "every floor has specials_placed <= 3")


# ── (c) Save round-trip ───────────────────────────────────────────────────────

func _test_save_round_trip(ps: Node) -> void:
	print("\n-- save round-trip --")

	ps.call("reset")
	ps.call("ensure_floor_generated", 2)
	await process_frame

	# Capture state before serialization.
	var floors_before: Dictionary = (ps.get("_floors") as Dictionary).duplicate(true)
	var rooms_before: Dictionary = (ps.get("_rooms") as Dictionary).duplicate(true)
	var edges_before: Dictionary = (ps.get("_edges") as Dictionary).duplicate(true)

	_expect(floors_before.has(2) and (floors_before[2] as Dictionary).get("generated", false),
		"floor 2 generated before serialize")

	var snap: Dictionary = ps.call("serialize")
	_expect(snap.has("floors") and snap.has("rooms") and snap.has("edges") and snap.has("special_pool_remaining"),
		"serialize produces expected top-level keys")

	ps.call("reset")
	var floors_after_reset: Dictionary = ps.get("_floors")
	_expect(not (floors_after_reset.has(2) and (floors_after_reset.get(2, {}) as Dictionary).get("generated", false)),
		"reset clears generated state for floor 2")

	ps.call("deserialize", snap, 2)
	await process_frame

	var floors_restored: Dictionary = ps.get("_floors")
	var rooms_restored: Dictionary = ps.get("_rooms")
	var edges_restored: Dictionary = ps.get("_edges")

	_expect(floors_restored.has(2), "floor 2 entry restored after deserialize")
	var floor2_restored: Dictionary = floors_restored.get(2, {})
	_expect(floor2_restored.get("generated", false), "floor 2 still marked generated after deserialize")
	_expect(int(floor2_restored.get("cap", 0)) == int((floors_before.get(2, {}) as Dictionary).get("cap", -1)),
		"floor 2 cap identical after round-trip")

	# Room count and ids must match.
	var rooms_before_f2: Array = (floors_before.get(2, {}) as Dictionary).get("rooms", [])
	var rooms_restored_f2: Array = floor2_restored.get("rooms", [])
	_expect(rooms_before_f2.size() == rooms_restored_f2.size(),
		"floor 2 room count identical after round-trip (%d)" % rooms_before_f2.size())

	var room_ids_match: bool = true
	for rid in rooms_before_f2:
		if not rooms_restored.has(String(rid)):
			room_ids_match = false
			print("  FAIL: room %s missing after round-trip" % rid)
	_expect(room_ids_match, "all floor 2 room ids present in restored _rooms")

	# Edge count must match.
	var edge_count_before: int = 0
	for k in edges_before.keys():
		edge_count_before += (edges_before[k] as Array).size()
	var edge_count_restored: int = 0
	for k in edges_restored.keys():
		edge_count_restored += (edges_restored[k] as Array).size()
	_expect(edge_count_before == edge_count_restored,
		"edge count identical after round-trip (before=%d, after=%d)" % [edge_count_before, edge_count_restored])


# ── (e) Floor unlock gating, cost deduction, escalation ─────────────────────

func _test_floor_unlock(ps: Node) -> void:
	print("\n-- floor unlock --")
	ps.call("reset")
	await process_frame

	# Access inventory from autoload root. In headless -s SceneTree scripts,
	# autoloads live on /root. Duck-type via get_node_or_null.
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(inv != null, "Inventory autoload reachable from test")
	if inv == null:
		return

	# Floor 2 is FREE — reached via the gate-room stairs, unlocked + code-known by default.
	_expect(ps.call("is_floor_unlocked", 2), "floor 2 is free/unlocked by default (stairs access)")

	# Floor 3 is the first PARTS-GATED floor. Generate it so the cost calc works.
	ps.call("ensure_floor_generated", 3)
	await process_frame

	# --- unlock_floor FAILS without the code ---
	# Give the player plenty of parts so the only gating variable is the code.
	inv.call("set_count", "parts", 50)
	var ok_no_code: bool = ps.call("unlock_floor", 3)
	_expect(not ok_no_code, "unlock_floor(3) fails when code is not known")
	_expect(not ps.call("is_floor_unlocked", 3), "floor 3 remains locked after failed attempt")
	# Parts must NOT have been spent on a failed attempt.
	_expect(inv.call("count", "parts") == 50, "parts not deducted on failed unlock attempt")

	# --- unlock_floor FAILS with insufficient resources even if code known ---
	ps.call("mark_floor_code_known", 3)
	_expect(ps.call("is_floor_code_known", 3), "mark_floor_code_known(3) marks the code known")
	inv.call("set_count", "parts", 0)  # Zero parts — can't afford.
	var ok_no_parts: bool = ps.call("unlock_floor", 3)
	_expect(not ok_no_parts, "unlock_floor(3) fails with 0 parts (cost = %d)" % ps.call("floor_unlock_cost", 3))
	_expect(not ps.call("is_floor_unlocked", 3), "floor 3 still locked after insufficient-parts attempt")

	# --- unlock_floor SUCCEEDS with code + sufficient resources ---
	var cost3: int = ps.call("floor_unlock_cost", 3)
	inv.call("set_count", "parts", cost3)
	var ok_full: bool = ps.call("unlock_floor", 3)
	_expect(ok_full, "unlock_floor(3) succeeds with code known + %d parts" % cost3)
	_expect(ps.call("is_floor_unlocked", 3), "floor 3 is now unlocked")
	# Cost must have been deducted.
	var parts_after: int = inv.call("count", "parts")
	_expect(parts_after == 0, "parts deducted after successful unlock (expected 0, got %d)" % parts_after)

	# --- cost escalates with floor index ---
	var cost2: int = ps.call("floor_unlock_cost", 2)
	var cost4: int = ps.call("floor_unlock_cost", 4)
	_expect(cost3 > cost2, "floor 3 cost (%d) > floor 2 cost (%d)" % [cost3, cost2])
	_expect(cost4 > cost3, "floor 4 cost (%d) > floor 3 cost (%d)" % [cost4, cost3])

	# --- floor_entry_room ---
	var entry3: String = ps.call("floor_entry_room", 3)
	_expect(entry3 != "", "floor_entry_room(3) returns non-empty string")
	_expect(String(entry3).begins_with("f3_"), "floor_entry_room(3) is a generated id (got '%s')" % entry3)
	var entry1: String = ps.call("floor_entry_room", 1)
	_expect(entry1 == "elevator_room_floor_1", "floor_entry_room(1) = authored elevator room (got '%s')" % entry1)


# ── (f) assign_function — persists across serialize/reset/deserialize, rejects non-storage ──

func _test_assign_function(ps: Node) -> void:
	print("\n-- assign_function --")
	ps.call("reset")
	await process_frame

	var inv: Node = root.get_node_or_null("Inventory")
	if inv == null:
		return

	# Generate floor 2 so we have rooms to assign.
	ps.call("ensure_floor_generated", 2)
	await process_frame

	var floors: Dictionary = ps.get("_floors")
	var f2_rooms: Array = (floors.get(2, {}) as Dictionary).get("rooms", [])
	_expect(f2_rooms.size() > 0, "floor 2 has rooms to assign (got %d)" % f2_rooms.size())
	if f2_rooms.is_empty():
		return

	# Find the first storage room in floor 2.
	var storage_id: String = ""
	var rooms_dict: Dictionary = ps.get("_rooms")
	for rid in f2_rooms:
		var row: Dictionary = rooms_dict.get(String(rid), {})
		if String(row.get("type", "")) == "storage":
			storage_id = String(rid)
			break
	_expect(storage_id != "", "floor 2 has at least one storage room")
	if storage_id == "":
		return

	# --- assign_function FAILS without sufficient parts ---
	inv.call("set_count", "parts", 0)
	var ok_no_parts: bool = ps.call("assign_function", storage_id, "armory")
	_expect(not ok_no_parts, "assign_function fails with 0 parts")
	_expect(ps.call("assigned_function", storage_id) == "", "assigned_function is empty after failed assign")

	# --- assign_function SUCCEEDS with enough parts ---
	var assign_cost: int = ps.get("ROOM_ASSIGN_COST")
	inv.call("set_count", "parts", assign_cost)
	var ok_assign: bool = ps.call("assign_function", storage_id, "armory")
	_expect(ok_assign, "assign_function succeeds with %d parts" % assign_cost)
	_expect(ps.call("assigned_function", storage_id) == "armory",
		"assigned_function returns 'armory' after assignment")
	_expect(inv.call("count", "parts") == 0, "parts deducted after assignment")
	# Room type updated in _rooms.
	var updated_row: Dictionary = (ps.get("_rooms") as Dictionary).get(storage_id, {})
	_expect(String(updated_row.get("type", "")) == "armory",
		"room type updated to 'armory' in _rooms after assignment")

	# --- assign_function rejects a base (non-generated) room ---
	inv.call("set_count", "parts", 50)
	var base_ok: bool = ps.call("assign_function", "east_corridor", "armory")
	_expect(not base_ok, "assign_function rejects base (non-generated) room 'east_corridor'")

	# --- assign_function rejects a non-storage generated room ---
	# Find a corridor room.
	var corridor_id: String = ""
	for rid in f2_rooms:
		var row: Dictionary = rooms_dict.get(String(rid), {})
		if String(row.get("type", "")) == "corridor":
			corridor_id = String(rid)
			break
	if corridor_id != "":
		var corr_ok: bool = ps.call("assign_function", corridor_id, "armory")
		_expect(not corr_ok, "assign_function rejects corridor room (not storage type)")
	else:
		print("  SKIP  no corridor room found on floor 2 for rejection test")
		_passes += 1

	# --- Persists across serialize / reset / deserialize ---
	var snap: Dictionary = ps.call("serialize")
	_expect(snap.has("floor_assignments"), "serialize includes floor_assignments key")
	var snap_assignments: Dictionary = snap.get("floor_assignments", {})
	_expect(snap_assignments.get(storage_id, "") == "armory",
		"floor_assignments in snapshot carries 'armory' for storage room")

	ps.call("reset")
	_expect(ps.call("assigned_function", storage_id) == "",
		"assigned_function empty after reset")

	ps.call("deserialize", snap, 2)
	await process_frame
	_expect(ps.call("assigned_function", storage_id) == "armory",
		"assigned_function restored to 'armory' after deserialize")
	# Room row type should also be restored.
	var restored_row: Dictionary = (ps.get("_rooms") as Dictionary).get(storage_id, {})
	_expect(String(restored_row.get("type", "")) == "armory",
		"room type is 'armory' in _rooms after deserialize")


# ── (g) floor-code POI marks code known ──────────────────────────────────────

func _test_floor_code_poi(ps: Node) -> void:
	print("\n-- floor code POI --")
	ps.call("reset")
	await process_frame

	# Floor 2 is free (gate-room stairs) → code known by default, no terminal needed.
	_expect(ps.call("is_floor_code_known", 2), "floor 2 code known by default (free via stairs)")

	# Floor 3 is the first code-gated floor.
	_expect(not ps.call("is_floor_code_known", 3), "floor 3 code not known after reset")
	ps.call("mark_floor_code_known", 3)
	_expect(ps.call("is_floor_code_known", 3), "mark_floor_code_known(3) sets code_known to true")

	# Mark for floor 4 (creates the record on the fly).
	_expect(not ps.call("is_floor_code_known", 4), "floor 4 code not known initially")
	ps.call("mark_floor_code_known", 4)
	_expect(ps.call("is_floor_code_known", 4), "mark_floor_code_known(4) works for uncreated floor")

	# floor 1 ignores mark (no code needed).
	ps.call("mark_floor_code_known", 1)
	_expect(not ps.call("is_floor_code_known", 1), "mark_floor_code_known(1) is a no-op (floor 1 needs no code)")

	# floor_code_terminal_room(3) lives on floor 2 — generate it first so the
	# terminal has a room to live in.
	ps.call("ensure_floor_generated", 2)
	await process_frame
	var code_room: String = ps.call("floor_code_terminal_room", 3)
	_expect(code_room != "", "floor_code_terminal_room(3) returns non-empty string (got '%s')" % code_room)

	# Survives round-trip.
	var snap: Dictionary = ps.call("serialize")
	ps.call("reset")
	_expect(not ps.call("is_floor_code_known", 3), "floor 3 code not known after reset")
	ps.call("deserialize", snap, 2)
	await process_frame
	_expect(ps.call("is_floor_code_known", 3), "floor 3 code_known restored after deserialize")
	_expect(ps.call("is_floor_code_known", 4), "floor 4 code_known restored after deserialize")


# ── (h) is_key_room — base delegation + generated catalog flag ────────────────

func _test_key_rooms(ps: Node) -> void:
	print("\n-- is_key_room --")
	ps.call("reset")
	await process_frame

	# Base rooms delegate to ShipLayout.is_key_room (JSON key_room flag + fallback).
	_expect(ps.call("is_key_room", "control_interface_room") == true,
		"is_key_room(control_interface_room) true (base key room)")
	_expect(ps.call("is_key_room", "gate_room") == true,
		"is_key_room(gate_room) true (base key room)")
	_expect(ps.call("is_key_room", "east_corridor") == false,
		"is_key_room(east_corridor) false (base non-key room)")

	# Generated rooms read the catalog key_room flag for their effective type.
	ps.call("ensure_floor_generated", 2)
	await process_frame
	var floors: Dictionary = ps.get("_floors")
	var f2_rooms: Array = (floors.get(2, {}) as Dictionary).get("rooms", [])
	var rooms_dict: Dictionary = ps.get("_rooms")

	# Generic filler storage is NOT key; once converted to armory it IS.
	var storage_id: String = ""
	for rid in f2_rooms:
		if String((rooms_dict.get(String(rid), {}) as Dictionary).get("type", "")) == "storage":
			storage_id = String(rid)
			break
	_expect(storage_id != "", "floor 2 has a storage room for key-room test")
	if storage_id != "":
		_expect(ps.call("is_key_room", storage_id) == false,
			"is_key_room(generated storage) false before assignment")
		var inv: Node = root.get_node_or_null("Inventory")
		if inv != null:
			inv.call("set_count", "parts", ps.get("ROOM_ASSIGN_COST"))
			var ok: bool = ps.call("assign_function", storage_id, "armory")
			_expect(ok, "assigned generated storage room to armory")
			_expect(ps.call("is_key_room", storage_id) == true,
				"is_key_room(generated room) true after armory assignment")

	# Any generated special room on this floor must read as key.
	for rid in f2_rooms:
		var t: String = String((rooms_dict.get(String(rid), {}) as Dictionary).get("type", ""))
		var cat: String = String((ps.call("room_type", t) as Dictionary).get("category", ""))
		if cat == "special_once" or cat == "special_limited":
			_expect(ps.call("is_key_room", String(rid)) == true,
				"is_key_room(generated special '%s') true" % t)
			break


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
