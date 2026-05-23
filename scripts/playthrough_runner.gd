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

const TIMEOUT_SEC: float = 60.0
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
	await get_tree().create_timer(DEMO_HOLD_SEC).timeout


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
	# === STEP 1: arrive in gate_room ===
	await _change_to("res://scenes/gate_room.tscn", "FromGate")
	_assert_current_scene("gate_room.tscn")
	_expect(GameState.rooms_discovered.has("gate_room"), "gate_room: discover_room fired")
	_expect(_find_door_to_room("stargate_corridor_east_connector") != null,
		"gate_room: exit door to east-connector present")
	await _shot("gate_room_arrival")
	await _demo_hold()

	# === STEP 2: read the FTL console — verify the readout text mutates ===
	var ftl: Node = _find_console("ftl_countdown")
	_expect(ftl != null, "gate_room: FTL console present")
	if ftl != null:
		var before: float = float(ftl.get("ftl_seconds_remaining"))
		# Let one process tick pass so the countdown advances.
		await get_tree().process_frame
		await get_tree().process_frame
		var after: float = float(ftl.get("ftl_seconds_remaining"))
		_expect(after < before, "FTL countdown ticks down")
		ftl.interact(null)
		_expect(GameState.log_entries.size() >= 1, "FTL console interact added log")
	await _shot("gate_room_post_ftl")
	await _demo_hold()

	# === STEP 3: read the Gate Control console ===
	var gate_ctrl: Node = _find_console("gate_control")
	_expect(gate_ctrl != null, "gate_room: Gate Control console present")
	if gate_ctrl != null:
		gate_ctrl.interact(null)
	await _demo_hold()

	# === STEP 4: gate_room → east_connector corridor via the data-driven factory ===
	await _interact_door_to_room("stargate_corridor_east_connector")
	_assert_current_scene("room.tscn")
	var arrival_room: Node = get_tree().current_scene
	_expect(arrival_room != null and String(arrival_room.get("room_id")) == "stargate_corridor_east_connector",
		"corridor: room.gd resolved room_id from baton")
	# Spawn-marker basis must NOT leave the player facing the door they came
	# through (forward-press would walk straight back into it).
	_expect_player_faces_away_from_entry_door_room("gate_room", "corridor")
	await _shot("corridor_dead_end")
	await _demo_hold()

	# === STEP 5: return to gate room — verify re-entry doesn't replay cinematic ===
	await _interact_door_to_room("gate_room")
	_assert_current_scene("gate_room.tscn")
	# rooms_discovered.has("gate_room") should still be true (idempotent).
	_expect(GameState.rooms_discovered.has("gate_room"), "gate_room: discovery preserved on re-entry")
	_expect_player_faces_away_from_entry_door_room("stargate_corridor_east_connector", "gate_room")
	await _shot("gate_room_return")
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


# Teleport the player ~0.9m in front of the door before triggering the
# interact so the auto_walk completes within the headless --quit-after
# frame budget. Passing the real player exercises the production
# walk-up-then-transition codepath rather than the null-skip branch.
func _walk_through(door: Door) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D and door is Node3D:
		var to_player: Vector3 = (player as Node3D).global_position - (door as Node3D).global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var approach: Vector3 = (door as Node3D).global_position + to_player.normalized() * 0.9
			(player as Node3D).global_position = Vector3(approach.x, (player as Node3D).global_position.y, approach.z)
	door.interact(player)
	await SceneRouter.scene_changed
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
