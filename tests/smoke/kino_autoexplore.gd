extends SceneTree

# Headless verification of the Kino ship auto-explore added in issue #50
# (Phase 4 — hands-off mapping while piloting). Covers what can be exercised
# without rendering:
#
#   • 4a: _reveal_adjacent_rooms discovers every (non-gate) neighbour of the
#     current ship room via ShipLayout.outgoing_edges — the "let go in a ship
#     room reveals adjacent rooms" payoff.
#   • 4b: _pick_next_explore_door returns the nearest undiscovered-target
#     pilotable door, skips already-discovered targets, and returns null when
#     every reachable neighbour is on the map (mission done → idle).
#   • start_ship_autopilot only engages in a ship room, refuses instant_mode
#     (so headless never triggers Kino scene churn), and arms GameState.kino_autopilot.
#   • stop_ship_autopilot / recall clears kino_autopilot cleanly.
#
# KinoDrone + Door scripts are load()ed at runtime (not preloaded) — both
# reference autoload globals not visible at the top-level compile pass of a
# `-s` SceneTree script. Same pattern as kino_doors.gd / kino_autopilot.gd.

var KinoDroneScript: Script = null
var DoorScript: Script = null

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== kino ship auto-explore tests ===")
	KinoDroneScript = load("res://scripts/kino_drone.gd")
	DoorScript = load("res://scripts/door.gd")
	if KinoDroneScript == null or DoorScript == null:
		print("SHOT_ERROR could not load KinoDrone/Door scripts")
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or router == null:
		_report()
		return

	router.set("instant_mode", true)
	gs.call("reset")
	await process_frame

	await _test_reveal_adjacent_rooms(gs)
	await _test_reveal_noop_off_ship(gs)
	await _test_pick_next_explore_door(gs)
	await _test_pick_skips_discovered(gs)
	await _test_start_requires_ship_room(gs, router)
	await _test_start_refuses_instant_mode(gs, router)
	await _test_recall_clears_autopilot(gs)

	_report()


# ─── helpers ─────────────────────────────────────────────────────────────

func _make_door(target_room_id: String, locked: bool = false, target_scene: String = "") -> Node:
	var d: StaticBody3D = StaticBody3D.new()
	d.set_script(DoorScript)
	d.set("target_room_id", target_room_id)
	d.set("target_scene", target_scene)
	d.set("source_room_id", "control_interface_room")
	d.set("target_spawn", "FromControlInterfaceRoom")
	d.set("locked", locked)
	d.add_to_group("interactable")
	return d


func _spawn_drone(name_suffix: String) -> Node:
	var dr: Node = KinoDroneScript.new()
	dr.name = "TestKino_" + name_suffix
	dr.set("launch_in_ship", false)
	root.add_child(dr)
	return dr


func _cleanup() -> void:
	for n in root.get_children():
		if n.name.begins_with("TestKino_") or n.name.begins_with("TestDoor_"):
			root.remove_child(n)
			n.free()
	await process_frame


# ─── test cases ──────────────────────────────────────────────────────────

func _test_reveal_adjacent_rooms(gs: Node) -> void:
	print("\n--- 4a: reveal adjacent rooms from a ship room ---")
	await _cleanup()
	gs.call("reset")
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	var drone: Node = _spawn_drone("reveal")
	await process_frame

	# Sanity: ShipLayout actually has outgoing edges for this room.
	var layout: Node = root.get_node_or_null("ShipLayout")
	var edges: Array = layout.call("outgoing_edges", "control_interface_room")
	_expect(edges.size() > 0, "ShipLayout has outgoing edges for control_interface_room")

	drone.call("_reveal_adjacent_rooms")
	var discovered: Array = gs.get("rooms_discovered")
	var revealed_any: bool = false
	for edge in edges:
		var to_id: String = String((edge as Dictionary).get("to", ""))
		if to_id == "" or to_id == "gate_room":
			continue
		revealed_any = true
		_expect(discovered.has(to_id),
			"neighbour '%s' is discovered after reveal" % to_id)
	_expect(revealed_any, "at least one non-gate neighbour was revealed")


func _test_reveal_noop_off_ship(gs: Node) -> void:
	print("\n--- 4a: reveal is a no-op off the ship (planet) ---")
	await _cleanup()
	gs.call("reset")
	gs.set("current_scene_path", "res://scenes/planet.tscn")
	gs.set("current_room_id", "")
	var drone: Node = _spawn_drone("revealplanet")
	await process_frame
	drone.call("_reveal_adjacent_rooms")
	_expect((gs.get("rooms_discovered") as Array).is_empty(),
		"reveal discovers nothing when not in a ship room")


func _test_pick_next_explore_door(gs: Node) -> void:
	print("\n--- 4b: pick nearest undiscovered-target door ---")
	await _cleanup()
	gs.call("reset")
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	var drone: Node = _spawn_drone("pick")
	(drone as Node3D).global_position = Vector3.ZERO
	# Near door → undiscovered target. Far door → undiscovered target. Locked door
	# (never pilotable). Gate-room door (refused by policy).
	var near: Node = _make_door("south_corridor")
	root.add_child(near); near.name = "TestDoor_near"
	(near as Node3D).global_position = Vector3(0, 0, -3)
	var far: Node = _make_door("north_corridor")
	root.add_child(far); far.name = "TestDoor_far"
	(far as Node3D).global_position = Vector3(0, 0, -30)
	var gate: Node = _make_door("gate_room")
	root.add_child(gate); gate.name = "TestDoor_gate"
	(gate as Node3D).global_position = Vector3(1, 0, -1)
	var locked: Node = _make_door("engineering_bay", true)
	root.add_child(locked); locked.name = "TestDoor_locked"
	(locked as Node3D).global_position = Vector3(2, 0, -1)
	await process_frame

	var picked: Node = drone.call("_pick_next_explore_door")
	_expect(picked == near, "picks the NEAREST undiscovered-target pilotable door")

	for d in [near, far, gate, locked]:
		d.free()


func _test_pick_skips_discovered(gs: Node) -> void:
	print("\n--- 4b: pick skips already-discovered targets, null when none left ---")
	await _cleanup()
	gs.call("reset")
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	var drone: Node = _spawn_drone("skip")
	(drone as Node3D).global_position = Vector3.ZERO
	var near: Node = _make_door("south_corridor")
	root.add_child(near); near.name = "TestDoor_near2"
	(near as Node3D).global_position = Vector3(0, 0, -3)
	var far: Node = _make_door("north_corridor")
	root.add_child(far); far.name = "TestDoor_far2"
	(far as Node3D).global_position = Vector3(0, 0, -30)
	await process_frame

	# Discover the near target → pick should jump to the far one.
	gs.call("discover_room", "south_corridor", "South Corridor")
	var picked: Node = drone.call("_pick_next_explore_door")
	_expect(picked == far, "skips the discovered near target, picks the far undiscovered one")

	# Discover the far one too → nothing undiscovered left → null (idle).
	gs.call("discover_room", "north_corridor", "North Corridor")
	var none: Variant = drone.call("_pick_next_explore_door")
	_expect(none == null, "returns null once every reachable neighbour is discovered (idle)")

	for d in [near, far]:
		d.free()


func _test_start_requires_ship_room(gs: Node, router: Node) -> void:
	print("\n--- 4b: start_ship_autopilot only engages in a ship room ---")
	await _cleanup()
	gs.call("reset")
	router.set("instant_mode", false)
	# On the planet: must NOT engage (planet patrol owns autopilot there).
	gs.set("current_scene_path", "res://scenes/planet.tscn")
	var drone_p: Node = _spawn_drone("startplanet")
	await process_frame
	drone_p.call("start_ship_autopilot")
	_expect(drone_p.get("_ship_autopilot") == false,
		"start does NOT engage on the planet (not a ship room)")
	_expect(gs.get("kino_autopilot") == false, "kino_autopilot stays false on the planet")

	# In a ship room: engages, arms the baton.
	await _cleanup()
	gs.call("reset")
	router.set("instant_mode", false)
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	var drone_s: Node = _spawn_drone("startship")
	await process_frame
	drone_s.call("start_ship_autopilot")
	_expect(drone_s.get("_ship_autopilot") == true, "start engages in a ship room")
	_expect(gs.get("kino_autopilot") == true, "start arms GameState.kino_autopilot baton")

	router.set("instant_mode", true)


func _test_start_refuses_instant_mode(gs: Node, router: Node) -> void:
	print("\n--- 4b: instant_mode never triggers auto-explore ---")
	await _cleanup()
	gs.call("reset")
	router.set("instant_mode", true)
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	var drone: Node = _spawn_drone("instant")
	await process_frame
	drone.call("start_ship_autopilot")
	_expect(drone.get("_ship_autopilot") == false,
		"start_ship_autopilot bails under instant_mode (no headless scene churn)")
	_expect(gs.get("kino_autopilot") == false, "instant_mode leaves kino_autopilot false")


func _test_recall_clears_autopilot(gs: Node) -> void:
	print("\n--- recall (close remote) clears the auto-explore baton ---")
	await _cleanup()
	gs.call("reset")
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "control_interface_room")
	gs.set("kino_autopilot", true)
	gs.set("kino_pilot_mode", true)
	var drone: Node = _spawn_drone("recall")
	drone.set("_ship_autopilot", true)
	await process_frame
	# No live player node in this -s scene; _exit_kino's in-place close handles
	# the null-player case. We only assert the baton-clearing side effects.
	drone.call("_exit_kino")
	_expect(gs.get("kino_autopilot") == false, "recall clears kino_autopilot")
	_expect(drone.get("_ship_autopilot") == false, "recall clears the drone's _ship_autopilot")
	_expect(gs.get("kino_pilot_mode") == false, "recall clears kino_pilot_mode")


# ─── reporting ────────────────────────────────────────────────────────────

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
