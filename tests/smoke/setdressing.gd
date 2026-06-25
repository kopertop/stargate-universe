extends SceneTree

# Smoke test for authored set-dressing (issue #135).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/setdressing.gd
#
# Assertions:
#   A) bridge   — shell + >=1 KenneyProp node + a Label3D with text=="BRIDGE"
#   B) obs_deck — emissive ObservationWindow MeshInstance3D + a Signage Label3D
#   C) no white-mesh — every MeshInstance3D inside a KenneyProp has >=1 surface
#                      override material set (guards stripped-glTF white-mesh trap)
#   D) doorway clearance — no SetDressBlocker* AABB centroid within 1.5 m of
#                          representative door positions (wall midpoints at Y=0)
#   E) springarm safety — no SetDressBlocker* node has collision_layer bit 2 set
#                         (layer 2 is the SpringArm/camera layer — blockers must
#                          be layer 1 only)
#   F) cost curve — floor_unlock_cost is monotonically escalating; for floors 3..6
#                   (MAX_FLOOR=6), floor_parts_budget(n) >= floor_unlock_cost(n+1)
#
# Implementation note: RoomBuilder is an Object (not a Node), preloaded directly
# to avoid class_name registration lag in headless -s runs (see memory entry
# feedback_godot_class_name_headless). ProceduralShip is reached via autoload.

const RoomBuilderScript: Script = preload("res://scripts/room_builder.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== setdressing smoke test ===")

	var ps: Node = root.get_node_or_null("ProceduralShip")
	_expect(ps != null, "ProceduralShip autoload attached")
	if ps == null:
		_report()
		return

	# ── A+C+D+E: bridge ─────────────────────────────────────────────────────
	print("\n-- A: bridge build --")
	var bridge_world: Node3D = _build_room("bridge", "control-room-template", 300, 300)
	_test_has_kenney_prop(bridge_world, "bridge has >=1 KenneyProp")
	_test_has_signage(bridge_world, "BRIDGE", "bridge has Label3D text==BRIDGE")
	_test_no_white_mesh(bridge_world, "bridge")
	_test_doorway_clearance(bridge_world, 300, 300, "bridge")
	_test_no_layer2_blockers(bridge_world, "bridge")
	bridge_world.queue_free()

	# ── B+C+D+E: observation_deck ────────────────────────────────────────────
	print("\n-- B: observation_deck build --")
	var obs_world: Node3D = _build_room("observation_deck", "quarters-template", 300, 300)
	_test_has_observation_window(obs_world, "observation_deck has ObservationWindow slab")
	_test_has_signage(obs_world, "OBSERVATION DECK", "observation_deck has Label3D text==OBSERVATION DECK")
	_test_no_white_mesh(obs_world, "observation_deck")
	_test_doorway_clearance(obs_world, 300, 300, "observation_deck")
	_test_no_layer2_blockers(obs_world, "observation_deck")
	obs_world.queue_free()

	# ── G: quarters (eli_quarters) at REAL dims (200x240 units = 10x12m) ───────
	# Regression coverage for the shipped quarters dressing. Props are visual-only
	# (no blockers), so doorway-clearance is vacuously clear; the real value is the
	# prop-presence + no-white-mesh guard at the ACTUAL room size.
	print("\n-- G: quarters build --")
	var q_world: Node3D = _build_room("quarters", "quarters-template", 200, 240)
	_test_has_kenney_prop(q_world, "quarters has >=1 KenneyProp")
	_test_no_white_mesh(q_world, "quarters")
	_test_doorway_clearance(q_world, 200, 240, "quarters")
	_test_no_layer2_blockers(q_world, "quarters")
	q_world.queue_free()

	# ── H: control_room at REAL dims (700x560 units = 35x28m) ──────────────────
	# The control room is large; its perimeter storage carries BLOCKERS, so this is
	# the real doorway-clearance gate (verifies no blocker traps a wall-midpoint door
	# at the room's true size — which the generic 300x300 build would not catch).
	print("\n-- H: control_room build --")
	var cr_world: Node3D = _build_room("control_room", "control-room-template", 700, 560)
	_test_has_kenney_prop(cr_world, "control_room has >=1 KenneyProp")
	_test_no_white_mesh(cr_world, "control_room")
	_test_doorway_clearance(cr_world, 700, 560, "control_room")
	_test_no_layer2_blockers(cr_world, "control_room")
	cr_world.queue_free()

	# ── F: cost curve ────────────────────────────────────────────────────────
	print("\n-- F: cost curve --")
	_test_cost_curve(ps)

	_report()


# Build a room using RoomBuilder.build() with a synthetic room_data dict.
# Width/height are in JSON grid units (ShipLayout units); RoomBuilder converts
# via ShipLayout.SCALE internally. Returns the world Node3D (caller must free).
func _build_room(type_id: String, template_id: String, w_units: int, h_units: int) -> Node3D:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var room_data: Dictionary = {
		"id": "test_%s" % type_id,
		"type": type_id,
		"template_id": template_id,
		"width": w_units,
		"height": h_units,
		"name": type_id.to_upper().replace("_", " "),
	}
	RoomBuilderScript.build(world, room_data)
	return world


# ── assertion helpers ─────────────────────────────────────────────────────────

func _test_has_kenney_prop(world: Node3D, label: String) -> void:
	var found: bool = _find_node_by_name_prefix(world, "KenneyProp") != null
	_expect(found, label)


func _test_has_signage(world: Node3D, expected_text: String, label: String) -> void:
	# GDScript passes primitives by value — use a return-value walker instead of
	# a mutable bool argument (mutation inside a recursive call never propagates back).
	_expect(_find_signage(world, expected_text), label)


func _find_signage(node: Node, text: String) -> bool:
	if node is Label3D:
		if (node as Label3D).text == text:
			return true
	for child in node.get_children():
		if _find_signage(child, text):
			return true
	return false


func _test_has_observation_window(world: Node3D, label: String) -> void:
	# ObservationWindow is a MeshInstance3D named "ObservationWindow" placed by
	# _add_observation_window when the setdressing dict has window_slab=true.
	# Use a return-value walker (same reason as signage — no mutable bool by ref).
	_expect(_find_observation_window(world), label)


func _find_observation_window(node: Node) -> bool:
	if node is MeshInstance3D and node.name == "ObservationWindow":
		return true
	for child in node.get_children():
		if _find_observation_window(child):
			return true
	return false


# C: every MeshInstance3D that is a direct child of a KenneyProp holder (or
# nested under it) must have at least one surface override material set.
# _spawn_kenney_prop calls _apply_material_recursive which stamps overrides on
# every surface — if any surface is nil the GLB lost its texture on import.
func _test_no_white_mesh(world: Node3D, room_label: String) -> void:
	var violations: Array[String] = []
	_walk_kenney_props(world, violations)
	_expect(violations.is_empty(),
		"%s: no white-mesh (all KenneyProp meshes have material overrides) — violations: %d"
		% [room_label, violations.size()])
	if not violations.is_empty():
		for v in violations:
			print("    white-mesh violation: " + v)


func _walk_kenney_props(node: Node, violations: Array[String]) -> void:
	if node.name == "KenneyProp":
		_check_mesh_materials(node, violations)
		return  # Don't recurse past the KenneyProp holder into its own sub-checks
	for child in node.get_children():
		_walk_kenney_props(child, violations)


func _check_mesh_materials(node: Node, violations: Array[String]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			var surf_count: int = mi.mesh.get_surface_count()
			for i in surf_count:
				if mi.get_surface_override_material(i) == null:
					violations.append("%s surface %d" % [mi.name, i])
	for child in node.get_children():
		_check_mesh_materials(child, violations)


# D: no SetDressBlocker AABB centroid within 1.5 m of a representative door
# position. Doors stamp at wall midpoints: (+-half_w, 0, 0) and (0, 0, +-half_d).
# half_w/half_d = (w_units * ShipLayout.SCALE) / 2.
func _test_doorway_clearance(world: Node3D, w_units: int, h_units: int, room_label: String) -> void:
	const SCALE: float = 0.05
	const CLEARANCE: float = 1.5
	var half_w: float = (w_units * SCALE) * 0.5
	var half_d: float = (h_units * SCALE) * 0.5
	# Representative door positions at wall midpoints, Y=0.
	var door_positions: Array[Vector3] = [
		Vector3(half_w,  0.0, 0.0),
		Vector3(-half_w, 0.0, 0.0),
		Vector3(0.0, 0.0,  half_d),
		Vector3(0.0, 0.0, -half_d),
	]
	var violations: Array[String] = []
	_walk_blockers_clearance(world, door_positions, CLEARANCE, violations)
	_expect(violations.is_empty(),
		"%s: doorway clearance (no blocker centroid within %.1fm of door) — violations: %d"
		% [room_label, CLEARANCE, violations.size()])
	if not violations.is_empty():
		for v in violations:
			print("    clearance violation: " + v)


func _walk_blockers_clearance(node: Node, door_positions: Array[Vector3],
		clearance: float, violations: Array[String]) -> void:
	if node is StaticBody3D and node.name.begins_with("SetDressBlocker"):
		var body: StaticBody3D = node
		# Centroid is the body's position (blockers are positioned at prop centre
		# + size.y/2 by _add_walk_blocker which raises by size.y/2).
		# Use the body position as the clearance check point.
		var centroid: Vector3 = body.position
		for dp in door_positions:
			# Only check horizontal distance (Y is irrelevant for doorway clearance).
			var horiz_dist: float = Vector2(centroid.x - dp.x, centroid.z - dp.z).length()
			if horiz_dist < clearance:
				violations.append("%s at (%.2f, %.2f) is %.2fm from door at (%.2f, %.2f)"
					% [node.name, centroid.x, centroid.z, horiz_dist, dp.x, dp.z])
	for child in node.get_children():
		_walk_blockers_clearance(child, door_positions, clearance, violations)


# E: no SetDressBlocker* CollisionShape owner has collision_layer bit 2 set.
# Layer 2 is the SpringArm/camera curtain layer — set-dressing blockers are
# layer 1 only (_add_walk_blocker hardcodes collision_layer=1).
func _test_no_layer2_blockers(world: Node3D, room_label: String) -> void:
	var violations: Array[String] = []
	_walk_blockers_layer2(world, violations)
	_expect(violations.is_empty(),
		"%s: springarm safety (no SetDressBlocker on camera layer 2) — violations: %d"
		% [room_label, violations.size()])
	if not violations.is_empty():
		for v in violations:
			print("    layer-2 violation: " + v)


func _walk_blockers_layer2(node: Node, violations: Array[String]) -> void:
	if node is StaticBody3D and node.name.begins_with("SetDressBlocker"):
		var body: StaticBody3D = node
		if (body.collision_layer & 2) != 0:
			violations.append("%s has collision_layer=%d (bit 2 set)" % [node.name, body.collision_layer])
	for child in node.get_children():
		_walk_blockers_layer2(child, violations)


# F: cost curve validation.
#   1. floor_unlock_cost is strictly increasing (monotonic escalating).
#   2. floor_parts_budget(n) >= floor_unlock_cost(n+1) for floors 3..MAX_FLOOR.
#
# MAX_FLOOR=6 (procedural_ship.gd const). Floor 7+ is out of bounds —
# ensure_floor_generated silently no-ops and floor_parts_budget returns 0.
# Use the actual generatable range 3..6.
func _test_cost_curve(ps: Node) -> void:
	# Generatable floors: 3 through MAX_FLOOR=6 (floor 1 authored, floor 2 free).
	var floors_to_check: Array[int] = [3, 4, 5, 6]

	# Generate each floor so _ensure_parts_budget populates floor_parts_budget.
	for n in floors_to_check:
		ps.call("ensure_floor_generated", n)

	# 1. Monotonic escalation: cost(n) > cost(n-1) for n in [3..6].
	var prev_cost: int = int(ps.call("floor_unlock_cost", 2))
	var monotonic: bool = true
	for n in floors_to_check:
		var cost: int = int(ps.call("floor_unlock_cost", n))
		if cost <= prev_cost:
			monotonic = false
			print("    monotonic fail: floor %d cost %d <= floor %d cost %d" % [n, cost, n - 1, prev_cost])
		prev_cost = cost
	_expect(monotonic, "cost curve: floor_unlock_cost is strictly increasing (floors 3..6)")

	# 2. Affordability invariant: floor_parts_budget(n) >= floor_unlock_cost(n+1).
	# Holds by construction: budget = floor_unlock_cost(n+1) * 120/100 >= next_cost.
	var affordable: bool = true
	for n in floors_to_check:
		var budget: int = int(ps.call("floor_parts_budget", n))
		var next_cost: int = int(ps.call("floor_unlock_cost", n + 1))
		if budget < next_cost:
			affordable = false
			print("    affordability fail: floor %d budget %d < floor %d cost %d"
				% [n, budget, n + 1, next_cost])
		else:
			print("    floor %d: budget=%d >= next_cost=%d (OK)" % [n, budget, next_cost])
	_expect(affordable,
		"cost curve: floor_parts_budget(n) >= floor_unlock_cost(n+1) for floors 3..6")


# ── generic tree walker ───────────────────────────────────────────────────────

func _find_node_by_name_prefix(node: Node, prefix: String) -> Node:
	if node.name.begins_with(prefix):
		return node
	for child in node.get_children():
		var found: Node = _find_node_by_name_prefix(child, prefix)
		if found != null:
			return found
	return null


# ── reporter ─────────────────────────────────────────────────────────────────

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
