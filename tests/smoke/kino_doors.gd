extends SceneTree

# Headless verification of the piloted-Kino door traversal added in issue #49
# (Kino recon Phase 3 — Kino travels through doorways with [E]).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/kino_doors.gd
#
# Covers the acceptance criteria that can be exercised without rendering:
#   • _is_pilotable_door accepts unlocked transition (room_id) doors and rejects
#     toggle-only / locked / gate-room / legacy-target_scene doors.
#   • _find_interact_target returns the aimed-at pilotable door (and null when
#     the door is out of the aim cone) so [E] pilots through vs. recalls.
#   • _route_kino_through_door stashes kino_pilot_arrival_spawn, sets next_room_id,
#     marks the door traversed, keeps kino_pilot_mode set, and refuses the gate
#     room in v1.
#   • The recall path treats a cross-ROOM hop (same room.tscn path, different
#     room id) as a scene-reload, not an in-place close.
#
# KinoDrone + Door scripts are load()ed at runtime (not preloaded) because both
# reference autoload globals (SceneRouter / GameState / Inventory) that aren't
# visible at the top-level compile pass of a `-s` SceneTree script. See
# tests/smoke/kino_autopilot.gd for the same pattern.

var KinoDroneScript: Script = null
var DoorScript: Script = null

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== kino door-traversal tests ===")
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

	# instant_mode → KinoDrone._ready early-returns before building the camera
	# rig / capturing the mouse, so spawned drones stay light in headless.
	router.set("instant_mode", true)
	gs.call("reset")
	await process_frame

	await _test_is_pilotable_door()
	await _test_find_interact_target()
	await _test_route_through_door(gs, router)
	await _test_route_refuses_gate_room(gs, router)
	await _test_recall_cross_room_reloads(gs)

	_report()


# ─── helpers ─────────────────────────────────────────────────────────────

# A door.gd instance configured as a transition door to a procedural room.
# Skips door.gd's heavy _ready (it builds a procedural mesh + reads ShipLayout)
# by NOT adding it to the tree — we only read its exported fields + duck-typed
# methods, which don't need _ready to have run.
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

func _test_is_pilotable_door() -> void:
	print("\n--- _is_pilotable_door classification ---")
	await _cleanup()
	var drone: Node = _spawn_drone("classify")
	await process_frame

	var open_door: Node = _make_door("south_corridor")
	var locked_door: Node = _make_door("engineering_bay", true)
	var gate_door: Node = _make_door("gate_room")
	var legacy_door: Node = _make_door("", false, "res://scenes/gate_room.tscn")
	# Toggle-only door: no target_room_id, no target_scene.
	var toggle_door: Node = _make_door("")

	# Note: _is_pilotable_door is intentionally permissive about target — it only
	# checks "unlocked transition door". gate_room + legacy target_scene are
	# transition doors, so they pass _is_pilotable here; _route_kino_through_door
	# is what refuses them (tested separately). This mirrors player.gd, where the
	# door's own _on_interact owns the destination policy.
	_expect(drone.call("_is_pilotable_door", open_door) == true,
		"unlocked room-id transition door is pilotable")
	_expect(drone.call("_is_pilotable_door", gate_door) == true,
		"gate-room transition door is pilotable at find-time (refused at route-time)")
	_expect(drone.call("_is_pilotable_door", legacy_door) == true,
		"legacy target_scene transition door is pilotable at find-time")
	_expect(drone.call("_is_pilotable_door", locked_door) == false,
		"LOCKED door is NOT pilotable")
	_expect(drone.call("_is_pilotable_door", toggle_door) == false,
		"toggle-only door (no destination) is NOT pilotable")

	for d in [open_door, locked_door, gate_door, legacy_door, toggle_door]:
		d.free()


func _test_find_interact_target() -> void:
	print("\n--- _find_interact_target aim cone ---")
	await _cleanup()
	var drone: Node = _spawn_drone("aim")
	# instant_mode skipped the camera build; give the drone a camera so the
	# find logic (which reads _camera.global_transform) has something to aim with.
	var cam: Camera3D = Camera3D.new()
	drone.set("_camera", cam)
	(drone as Node3D).add_child(cam)
	(drone as Node3D).global_position = Vector3.ZERO
	# Drone faces -Z (Godot default). Put a pilotable door 2 m ahead (-Z).
	var ahead: Node = _make_door("south_corridor")
	root.add_child(ahead)
	ahead.name = "TestDoor_ahead"
	(ahead as Node3D).global_position = Vector3(0.0, 0.0, -2.0)
	# A second pilotable door BEHIND the drone (+Z) — out of the aim cone.
	var behind: Node = _make_door("north_corridor")
	root.add_child(behind)
	behind.name = "TestDoor_behind"
	(behind as Node3D).global_position = Vector3(0.0, 0.0, 2.0)
	await process_frame

	var found: Node = drone.call("_find_interact_target")
	_expect(found == ahead, "_find_interact_target picks the door in front (-Z)")

	# Move the front door out of reach (>4 m) → nothing in range → null (recall).
	(ahead as Node3D).global_position = Vector3(0.0, 0.0, -9.0)
	await process_frame
	var none: Variant = drone.call("_find_interact_target")
	_expect(none == null, "_find_interact_target returns null when no door is in reach (so [E] recalls)")


func _test_route_through_door(gs: Node, router: Node) -> void:
	print("\n--- _route_kino_through_door sets the arrival baton ---")
	await _cleanup()
	gs.call("reset")
	gs.set("kino_pilot_mode", true)
	gs.set("current_scene_path", "res://scenes/room.tscn")
	# Block the real scene change so we can assert the pre-change state: change_to
	# early-returns immediately while is_transitioning is true.
	router.set("is_transitioning", true)
	var drone: Node = _spawn_drone("route")
	await process_frame

	var door: Node = _make_door("south_corridor")
	door.set("source_room_id", "control_interface_room")
	door.set("target_spawn", "FromControlInterfaceRoom")
	root.add_child(door)
	door.name = "TestDoor_route"
	await process_frame

	drone.call("_route_kino_through_door", door)

	_expect(String(gs.get("kino_pilot_arrival_spawn")) == "FromControlInterfaceRoom",
		"route stashes the door's target_spawn as kino_pilot_arrival_spawn")
	_expect(String(gs.get("next_room_id")) == "south_corridor",
		"route sets next_room_id to the door's target room")
	_expect(gs.call("door_was_traversed", "control_interface_room", "south_corridor") == true,
		"route marks the door traversed (pip dims / map lights)")
	_expect(gs.get("kino_pilot_mode") == true,
		"kino_pilot_mode persists across the hop")
	_expect(drone.get("_ending") == true,
		"route flags the drone _ending so it stops driving during the fade")

	router.set("is_transitioning", false)


func _test_route_refuses_gate_room(gs: Node, router: Node) -> void:
	print("\n--- _route_kino_through_door refuses gate_room / target_scene in v1 ---")
	await _cleanup()
	gs.call("reset")
	gs.set("kino_pilot_mode", true)
	gs.set("current_scene_path", "res://scenes/room.tscn")
	router.set("is_transitioning", true)
	var drone: Node = _spawn_drone("refuse")
	await process_frame

	var gate_door: Node = _make_door("gate_room")
	root.add_child(gate_door)
	gate_door.name = "TestDoor_gate"
	await process_frame

	drone.call("_route_kino_through_door", gate_door)
	_expect(String(gs.get("kino_pilot_arrival_spawn")) == "",
		"gate-room door is refused: no arrival baton set")
	_expect(String(gs.get("next_room_id")) == "",
		"gate-room door is refused: next_room_id untouched")
	_expect(drone.get("_ending") == false,
		"gate-room refusal does NOT flag _ending (harmless miss, drone keeps flying)")

	router.set("is_transitioning", false)


func _test_recall_cross_room_reloads(gs: Node) -> void:
	print("\n--- recall after a cross-room hop reloads the body's room ---")
	await _cleanup()
	gs.call("reset")
	# Body is waiting in control_interface_room; the Kino piloted into south_corridor.
	gs.set("kino_return_scene", "res://scenes/room.tscn")
	gs.set("kino_return_room_id", "control_interface_room")
	gs.set("kino_return_position", Vector3(1.0, 0.0, -2.0))
	gs.set("kino_return_yaw", 0.5)
	gs.set("current_scene_path", "res://scenes/room.tscn")
	gs.set("current_room_id", "south_corridor")
	gs.set("kino_pilot_mode", true)

	var drone: Node = _spawn_drone("recall")
	await process_frame
	# _exit_kino → cross-room branch → _close_to_scene, which copies the body's
	# resting spot into pending_spawn_position + sets next_room_id to the body's
	# room before SceneRouter.change_to. (No live player node in this -s scene, so
	# the in-place path would otherwise strand the player — the cross-room guard
	# routes us to the scene-reload path instead.)
	drone.call("_exit_kino")

	_expect(String(gs.get("next_room_id")) == "control_interface_room",
		"recall reloads the BODY's room (control_interface_room), not the Kino's room")
	var psp: Variant = gs.get("pending_spawn_position")
	_expect(psp is Vector3 and (psp as Vector3).is_equal_approx(Vector3(1.0, 0.0, -2.0)),
		"recall restores the body to its recorded resting position")
	_expect(gs.get("kino_pilot_mode") == false,
		"recall clears kino_pilot_mode (back in the body)")


# ─── reporting (matches kino_autopilot.gd style) ──────────────────────────

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
