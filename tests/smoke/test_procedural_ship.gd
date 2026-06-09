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
	_test_floor_generation(ps)
	_test_special_pool_limits(ps)
	_test_save_round_trip(ps)

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
