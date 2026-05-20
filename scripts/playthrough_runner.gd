extends Node

# E1 playthrough integration test runner.
#
# Drives the actual gameplay pipeline (Doors → SceneRouter → Interactables) from
# gate-room arrival to episode_completed signal. This complements the smoke
# tests by exercising real cross-scene transitions, real autoloads, and real
# Interactable.interact() codepaths — not just GameState mutators.
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

var _episode_completed_fired: bool = false
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
	print("=== e1_playthrough integration test ===")
	if _demo_mode:
		print("  (demo mode: fade on, holds enabled)")
	if _shot_dir != "":
		print("  (screenshot capture → ", _shot_dir, ")")
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	# Skip the fade animation in test mode — Tween.finished signals are unreliable
	# across back-to-back scene changes in headless and we don't need polish there.
	SceneRouter.instant_mode = not _demo_mode
	GameState.episode_completed.connect(_on_episode_completed)
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	# Reset to a clean E1 starting state.
	GameState.reset()
	_drive()


func _demo_hold() -> void:
	if not _demo_mode:
		return
	await get_tree().create_timer(DEMO_HOLD_SEC).timeout


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	# Give the viewport a couple of frames to finalize the rendered image.
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
	# === STEP 1: gate_room (arrival) ===
	await _change_to("res://scenes/gate_room.tscn", "FromGate")
	_assert_current_scene("gate_room.tscn")
	_expect(_find_door_to("res://scenes/destiny_corridor.tscn") != null, "gate_room: door to corridor present")
	await _shot("gate_room_arrival")
	await _demo_hold()
	await _shot("gate_room_post_arrival")

	# === STEP 2: gate_room → destiny_corridor ===
	await _interact_door_to("res://scenes/destiny_corridor.tscn")
	_assert_current_scene("destiny_corridor.tscn")
	await _shot("corridor")
	await _demo_hold()

	# === STEP 3: corridor → eli_quarters (via QuartersDoor) ===
	await _interact_door_to("res://scenes/eli_quarters.tscn")
	_assert_current_scene("eli_quarters.tscn")
	await _shot("quarters")
	await _demo_hold()

	# === STEP 4: pick up the Kino Remote ===
	var kino: KinoPickup = _find_first_of_type("KinoPickup") as KinoPickup
	_expect(kino != null, "eli_quarters: KinoPickup present")
	if kino != null:
		kino.interact(null)
	_expect(GameState.kino_acquired, "GameState.kino_acquired after pickup")
	await _demo_hold()

	# === STEP 5: sleep in bed → marks quarters_found, heals, restores oxygen ===
	GameState.damage(40.0)
	GameState.consume_oxygen(30.0)
	var bed: Bed = _find_first_of_type("Bed") as Bed
	_expect(bed != null, "eli_quarters: Bed present")
	if bed != null:
		bed.interact(null)
	_expect(GameState.quarters_found, "GameState.quarters_found after sleep")
	_expect(GameState.health == GameState.MAX_HEALTH, "bed restored health to MAX")
	_expect(GameState.oxygen == GameState.MAX_OXYGEN, "bed restored oxygen to MAX")
	await _demo_hold()

	# Episode must NOT yet be complete — no breach sealed.
	_expect(GameState.episode_complete == false, "episode NOT complete pre-breach")

	# === STEP 6: eli_quarters → destiny_corridor (return via CorridorDoor) ===
	await _interact_door_to("res://scenes/destiny_corridor.tscn")
	_assert_current_scene("destiny_corridor.tscn")
	await _demo_hold()

	# === STEP 7: corridor → hull_breach ===
	await _interact_door_to("res://scenes/hull_breach.tscn")
	_assert_current_scene("hull_breach.tscn")
	await _shot("hull_breach")
	await _demo_hold()

	# === STEP 8: flip the emergency seal switch ===
	var seal: HullSealSwitch = _find_first_of_type("HullSealSwitch") as HullSealSwitch
	_expect(seal != null, "hull_breach: SealSwitch present")
	if seal != null:
		seal.interact(null)
	_expect(GameState.breaches_sealed.size() == 1, "one breach sealed")
	_expect(GameState.breaches_sealed[0] == "compartment_14b", "correct breach_id sealed")

	# === STEP 9: episode_completed should fire from check_episode_complete() ===
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	_expect(GameState.episode_complete, "GameState.episode_complete == true")
	_expect(_episode_completed_fired, "episode_completed signal fired exactly once")
	await _shot("episode_complete")

	# Hold on the episode_complete card so the screen recording captures it.
	if _demo_mode:
		await get_tree().create_timer(3.5).timeout

	_report()


# --- transitions ---------------------------------------------------------

func _change_to(scene_path: String, spawn: String) -> void:
	SceneRouter.change_to(scene_path, spawn)
	await SceneRouter.scene_changed
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _interact_door_to(target_scene: String) -> void:
	var door: Door = _find_door_to(target_scene)
	if door == null:
		_fail("could not find door to " + target_scene)
		return
	door.interact(null)
	# Door._transition kicks off SceneRouter.change_to — wait for scene_changed.
	await SceneRouter.scene_changed
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


# --- discovery -----------------------------------------------------------

func _find_door_to(target_scene: String) -> Door:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Door and (n as Door).target_scene == target_scene:
			return n
	return null


func _find_first_of_type(type_name: String) -> Node:
	for n in get_tree().get_nodes_in_group("interactable"):
		var s: Script = n.get_script()
		if s == null:
			continue
		var base: String = s.resource_path.get_file().get_basename()
		match type_name:
			"KinoPickup":
				if base == "kino_pickup":
					return n
			"Bed":
				if base == "bed":
					return n
			"HullSealSwitch":
				if base == "hull_seal_switch":
					return n
			"Door":
				if base == "door":
					return n
	return null


# --- assertions / reporting ---------------------------------------------

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


func _on_episode_completed() -> void:
	_episode_completed_fired = true
	print("  >>>>  GameState.episode_completed signal received")


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
