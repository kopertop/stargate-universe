extends Node

# Phase A playthrough integration test runner.
#
# Drives the actual gameplay pipeline (Doors → SceneRouter → Interactables) from
# gate-room arrival, through the FTL console interact, into the dead-end
# corridor, and back. This complements the smoke tests by exercising real
# cross-scene transitions, real autoloads, and real Interactable.interact()
# codepaths.
#
# Lives as a direct child of /root (sibling to autoloads) so it survives
# SceneRouter.change_to() — which frees current_scene. Bootstrapped from
# tests/playthrough/playthrough.tscn (see tests/playthrough/bootstrap.gd).
#
# Run with:
#   godot --headless res://tests/playthrough/playthrough.tscn

const TIMEOUT_SEC: float = 180.0
const SETTLE_FRAMES: int = 3

# When PLAYTHROUGH_DEMO env var is set, the runner paces itself visibly: fade
# transitions stay on and we hold each scene for DEMO_HOLD_SEC. This is for
# windowed screen recordings, not the headless test suite.
const DEMO_HOLD_SEC: float = 1.6

var _failures: Array[String] = []
var _passes: int = 0
var _started: bool = false
var _demo_mode: bool = false
var _shot_dir: String = ""
var _shot_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Defer one frame so autoloads finish wiring up before we start driving.
	call_deferred("_begin")


func _begin() -> void:
	if _started:
		return
	_started = true
	_demo_mode = OS.get_environment("PLAYTHROUGH_DEMO") != ""
	_shot_dir = OS.get_environment("PLAYTHROUGH_SHOTS")
	print("=== phase-a playthrough integration test ===")
	if _demo_mode:
		print("  (demo mode: fade on, holds enabled)")
	if _shot_dir != "":
		print("  (screenshot capture → ", _shot_dir, ")")
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	SceneRouter.instant_mode = not _demo_mode
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	GameState.reset()
	_drive()


func _demo_hold() -> void:
	if not _demo_mode:
		return
	_dismiss_dialogs()
	await get_tree().create_timer(DEMO_HOLD_SEC, true).timeout
	_dismiss_dialogs()


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp: Viewport = get_tree().root
	var img: Image = vp.get_texture().get_image()
	if img == null:
		return
	_shot_index += 1
	var name: String = "%02d_%s.png" % [_shot_index, label]
	var path: String = _shot_dir.path_join(name)
	var err: int = img.save_png(path)
	if err == OK:
		print("    shot → ", path)
	else:
		print("    shot FAILED (", err, ") → ", path)


func _drive() -> void:
	# === STEP 1: arrive in gate_room and talk to Scott ===
	await _change_to("res://scenes/gate_room.tscn", "FromGate")
	_assert_current_scene("gate_room.tscn")
	_expect_player_faces_world(Vector3(0.0, 0.0, -1.0), "gate_room: FromGate spawn faces away from the gate")
	_expect(GameState.rooms_discovered.has("gate_room"), "gate_room: discover_room fired")
	_expect(_find_door_to_room("stargate_corridor_east_connector") != null,
		"gate_room: exit door to east-connector present")
	await _shot("gate_room_arrival")
	var scott: Node = _find_node_named("LtScott")
	await _interact_node(scott, "Scott briefing")
	if scott != null:
		scott.set("auto_greet", false)
		scott.set_process(false)
	_expect(GameState.met_scott, "quest: talked to Scott")
	_expect(GameState.quest_step == GameState.QUEST_FIND_RUSH, "quest: Scott sends player to Rush")
	await _demo_hold()

	# === STEP 2: find Rush ===
	await _travel_path([
		"stargate_corridor_east_connector",
		"east_corridor",
		"north_corridor",
		"control_approach_north",
		"control_interface_room",
	])
	await _interact_node(_find_node_named("DrRush"), "Rush briefing")
	_expect(GameState.met_rush, "quest: talked to Rush")
	_expect(GameState.quest_step == GameState.QUEST_FIND_REST, "quest: Rush sends Eli to rest")

	# === STEP 3: head to Eli's quarters, inspect strange device, sleep into Air crisis ===
	await _travel_path([
		"cr_corridor_2",
		"eli_quarters",
	])
	_expect(GameState.eli_quarters_visited, "quest: entering Eli's quarters flips the flag")
	_expect(GameState.quest_step == GameState.QUEST_FIND_KINO, "quest: in quarters -> inspect strange device")
	await _interact_node(_find_node_named("KinoPickup"), "Kino pickup")
	var kino_wait_frames: int = 900 if _demo_mode else 90
	await _wait_until(func() -> bool: return GameState.kino_acquired, "Kino acquisition", kino_wait_frames)
	_expect(GameState.quest_step == GameState.QUEST_SLEEP, "quest: device inspected -> sleep")
	await _interact_node(_find_node_named("Bed"), "sleep")
	_expect(GameState.air_crisis_started, "quest: sleep starts Air crisis")
	_expect(GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT, "quest: crisis -> diagnose life support")

	# === STEP 6: diagnose life support in gate room ===
	# Leaves from Eli's quarters now (not Crew Quarters Alpha on the upper floor).
	await _travel_path([
		"cr_corridor_2",
		"control_interface_room",
		"control_approach_north",
		"north_corridor",
		"east_corridor",
		"stargate_corridor_east_connector",
		"gate_room",
	])
	var gate_ctrl: Node = _find_console("gate_control")
	_expect(gate_ctrl != null, "gate_room: Gate Control console present")
	await _interact_node(gate_ctrl, "life support diagnostic")
	_expect(GameState.life_support_diagnosed, "quest: life support diagnosed")
	_expect(GameState.quest_step == GameState.QUEST_SEAL_BREACH, "quest: diagnostic -> seal breach")

	# === STEP 7: lock off exposed ship section ===
	await _travel_path([
		"stargate_corridor_east_connector",
		"east_corridor",
	])
	await _interact_node(_find_node_named("HullSealSwitch"), "hull seal switch")
	_expect(GameState.breaches_sealed.has("breach_a"), "quest: breach sealed")
	_expect(GameState.quest_step == GameState.QUEST_FIND_SCRUBBER, "quest: breach -> find scrubber")

	# === STEP 8: diagnose broken CO2 scrubber ===
	await _travel_path([
		"north_corridor",
		"elevator_north",
		"elevator_room_floor_1",
		"hydroponics",
	])
	await _interact_node(_find_node_named("CO2Scrubber"), "scrubber diagnosis")
	_expect(GameState.scrubber_diagnosed, "quest: scrubber diagnosed")
	_expect(GameState.quest_step == GameState.QUEST_WAIT_FTL, "quest: scrubber -> FTL drop")

	# === STEP 9: trigger FTL drop and dial lime planet ===
	await _travel_path([
		"elevator_room_floor_1",
		"elevator_north",
		"north_corridor",
		"east_corridor",
		"stargate_corridor_east_connector",
		"gate_room",
	])
	var ftl: Node = _find_console("ftl_countdown")
	_expect(ftl != null, "gate_room: FTL console present")
	await _interact_node(ftl, "FTL drop")
	_expect(GameState.ftl_drop_triggered, "quest: FTL drop triggered")
	await _interact_node(_find_console("gate_control"), "dial lime planet")
	_expect(GameState.lime_planet_dialed, "quest: lime planet dialed")
	_expect(GameState.is_lime_gate_open(), "quest: ship gate open to lime planet")
	await _shot("gate_room_lime_dial")
	await _demo_hold()

	# === STEP 10: travel to planet, mine lime, return ===
	await _activate_gate(_find_planet_gate("to_planet"), "ship gate to planet")
	_assert_current_scene("planet.tscn")
	await _shot("planet_landing")
	await _demo_hold()
	var mined: int = 0
	for node in _find_resource_nodes():
		await _interact_node(node, "lime node")
		mined += 1
		if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
			break
	_expect(mined >= GameState.AIR_LIME_REQUIRED, "planet: mined enough lime nodes")
	_expect(GameState.quest_step == GameState.QUEST_RETURN_DESTINY, "quest: enough lime -> return to Destiny")
	await _shot("lime_mining")
	await _demo_hold()
	await _activate_gate(_find_planet_gate("to_ship"), "planet gate to Destiny")
	_assert_current_scene("gate_room.tscn")
	_expect(GameState.returned_from_lime_planet, "quest: returned from planet")
	_expect(GameState.quest_step == GameState.QUEST_REPAIR_SCRUBBER, "quest: return -> repair scrubber")
	await _shot("gate_room_return_from_planet")
	await _demo_hold()

	# === STEP 11: repair scrubber and complete Episode 1 ===
	await _travel_path([
		"stargate_corridor_east_connector",
		"east_corridor",
		"north_corridor",
		"elevator_north",
		"elevator_room_floor_1",
		"hydroponics",
	])
	await _interact_node(_find_node_named("CO2Scrubber"), "scrubber repair")
	_expect(GameState.scrubber_repaired, "quest: scrubber repaired")
	_expect(GameState.episode_complete, "quest: Episode 1 complete")
	await _shot("scrubber_repair")
	await _demo_hold()
	_report()


# --- transitions ---------------------------------------------------------

func _change_to(scene_path: String, spawn: String) -> void:
	SceneRouter.change_to(scene_path, spawn)
	await SceneRouter.scene_changed
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _interact_door_to_room(target_room_id: String) -> void:
	var door: Door = _find_door_to_room(target_room_id)
	if door == null:
		_fail("could not find door to room " + target_room_id)
		return
	await _walk_through(door)
	if target_room_id == "gate_room":
		_assert_current_scene("gate_room.tscn")
	else:
		_assert_room_id(target_room_id)


func _travel_path(room_ids: Array) -> void:
	for room_id in room_ids:
		await _interact_door_to_room(String(room_id))


func _interact_node(node: Node, label: String) -> void:
	if node == null:
		_fail(label + ": missing interactable")
		return
	if not node.has_method("interact"):
		_fail(label + ": node has no interact()")
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	node.call("interact", player)
	_dismiss_dialogs()
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		_dismiss_dialogs()


func _activate_gate(gate: Node, label: String) -> void:
	if gate == null:
		_fail(label + ": missing gate trigger")
		return
	var mode: String = String(gate.get("mode"))
	var scene_path: String = String(gate.get("target_scene"))
	var spawn: String = String(gate.get("target_spawn"))
	if scene_path == "":
		_fail(label + ": gate trigger has no target_scene")
		return
	if mode == "to_planet":
		if not GameState.can_travel_to_lime_planet():
			_fail(label + ": GameState does not allow lime planet travel")
			return
		GameState.add_log("Playthrough: stepping through the active Stargate.")
	elif mode == "to_ship":
		if GameState.quest_step == GameState.QUEST_MINE_LIME and not GameState.has_resource(
				GameState.AIR_LIME_RESOURCE,
				GameState.AIR_LIME_REQUIRED
			):
			_fail(label + ": cannot return before mining enough lime")
			return
		GameState.return_from_lime_planet()
	await SceneRouter.change_to(scene_path, spawn)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _wait_until(predicate: Callable, label: String, max_frames: int = 90) -> bool:
	for i in max_frames:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	_dismiss_dialogs()
	_fail(label + " timed out")
	return false


# Route through the same SceneRouter destination data as Door.interact(). The
# long quest harness bypasses per-door walk-up animation so fade-enabled demo
# captures cannot hang on approach geometry or un-awaited door coroutines.
func _walk_through(door: Door) -> void:
	var scene_path: String = ""
	var spawn: String = door.target_spawn
	if door.target_room_id != "":
		if door.target_room_id == "gate_room":
			scene_path = "res://scenes/gate_room.tscn"
		else:
			GameState.next_room_id = door.target_room_id
			scene_path = "res://scenes/room.tscn"
	elif door.target_scene != "":
		scene_path = door.target_scene
	else:
		_fail("door has no transition destination")
		return
	await SceneRouter.change_to(scene_path, spawn)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


# --- discovery -----------------------------------------------------------

func _find_door_to_room(target_room_id: String) -> Door:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Door and (n as Door).target_room_id == target_room_id:
			return n
	return null


func _find_console(kind: String) -> Node:
	# Duck-type rather than relying on class_name GateConsole — the class index
	# may not be rebuilt in a single headless run.
	for n in get_tree().get_nodes_in_group("interactable"):
		var script: Script = n.get_script()
		if script == null:
			continue
		if script.resource_path.ends_with("gate_console.gd") and String(n.get("kind")) == kind:
			return n
	return null


func _find_node_named(node_name: String) -> Node:
	return _find_node_named_in(get_tree().current_scene, node_name)


func _find_node_named_in(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found: Node = _find_node_named_in(child, node_name)
		if found != null:
			return found
	return null


func _find_resource_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group("interactable"):
		var script: Script = n.get_script()
		if script != null and script.resource_path.ends_with("resource_node.gd"):
			out.append(n)
	return out


func _find_planet_gate(mode: String) -> Node:
	for n in get_tree().get_nodes_in_group("planet_gate"):
		if String(n.get("mode")) == mode:
			return n
	return null


func _dismiss_dialogs() -> void:
	if get_tree().paused:
		get_tree().paused = false
	_free_dialog_screens(get_tree().root)


func _free_dialog_screens(root: Node) -> void:
	if root == null:
		return
	var script: Script = root.get_script()
	if script != null and script.resource_path.ends_with("dialog_screen.gd"):
		root.queue_free()
		return
	for child in root.get_children():
		_free_dialog_screens(child)


# --- assertions / reporting ---------------------------------------------

# Post-arrival, the entry door is the one in the new scene whose target points
# back at `from_room_id`. The player must face AWAY from it (forward vector has
# positive component along player - door) and be within 4.5m of it.
func _expect_player_faces_away_from_entry_door_room(from_room_id: String, label: String) -> void:
	var entry: Door = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Door and (n as Door).target_room_id == from_room_id:
			entry = n
			break
	_assert_faces_away(entry, label, "target_room_id=" + from_room_id)


func _expect_player_faces_world(direction: Vector3, label: String) -> void:
	var player_n: Node = get_tree().get_first_node_in_group("player")
	if player_n == null or not (player_n is Node3D):
		_fail(label + ": no player Node3D found")
		return
	var expected: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if expected.length() < 0.01:
		_fail(label + ": expected direction is zero")
		return
	var player: Node3D = player_n as Node3D
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		_fail(label + ": player forward vector is zero")
		return
	var dot: float = forward.normalized().dot(expected.normalized())
	_expect(dot > 0.8, label + " (dot=%.2f, want > 0.8)" % dot)


func _assert_faces_away(entry: Door, label: String, key_for_msg: String) -> void:
	if entry == null:
		_fail(label + ": no entry door (" + key_for_msg + ") in arrival scene")
		return
	var player_n: Node = get_tree().get_first_node_in_group("player")
	if player_n == null or not (player_n is Node3D):
		_fail(label + ": no player Node3D found post-arrival")
		return
	var player: Node3D = player_n as Node3D
	var to_player: Vector3 = player.global_position - entry.global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	_expect(dist < 4.5, label + ": player spawned within 4.5m of entry door (got %.2fm)" % dist)
	if dist < 0.01:
		return
	var player_forward: Vector3 = -player.global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length() < 0.01:
		_fail(label + ": player forward vector is zero")
		return
	var dot: float = player_forward.normalized().dot(to_player.normalized())
	_expect(dot > 0.5, label + ": player faces AWAY from entry door (dot=%.2f, want > 0.5)" % dot)


func _assert_current_scene(expected_filename: String) -> void:
	var cs: Node = get_tree().current_scene
	if cs == null:
		_fail("current_scene is null (expected " + expected_filename + ")")
		return
	var path: String = cs.scene_file_path
	_expect(path.ends_with(expected_filename), "current_scene == " + expected_filename + " (got: " + path + ")")


func _assert_room_id(expected_room_id: String) -> void:
	_assert_current_scene("room.tscn")
	var cs: Node = get_tree().current_scene
	if cs == null:
		return
	_expect(String(cs.get("room_id")) == expected_room_id,
		"room_id == " + expected_room_id + " (got: " + String(cs.get("room_id")) + ")")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _fail(reason: String) -> void:
	print("  FAIL  ", reason)
	_failures.append(reason)


func _on_timeout() -> void:
	print("\n!!! TIMEOUT after ", TIMEOUT_SEC, "s — playthrough hung")
	_fail("timeout (test exceeded " + str(TIMEOUT_SEC) + "s)")
	_report()


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	get_tree().quit(1)
