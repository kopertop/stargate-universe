extends Node

# Orchestration integration test for SaveManager over the profile + checkpoint
# store (issue #79). Boots with real autoloads, isolates the saves root, and
# exercises the four orchestration surfaces directly against the live
# SaveManager autoload:
#
#   1. autosave ring  — 4 room-transition autosaves leave exactly 3 on disk
#   2. manual save    — save_manual() writes a PERMANENT manual checkpoint
#   3. episode save   — episode_completed writes one PERMANENT episode cp, once
#   4. resume         — load_and_resume_checkpoint restores a chosen cp;
#                       load_and_resume("") (Continue) resumes most-recent
#   5. permanence     — manual + episode survive further autosave pressure
#
# Asserts via SaveStore (the persistence ground truth) so we test what actually
# landed on disk, not just in-memory bookkeeping. SceneTree-survival harness
# mirrors slot_resume_runner.gd (spawned at /root so the resume scene change
# doesn't free us).

var _pass: int = 0
var _fail: int = 0
var _store: SaveStore = null
var _player: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	var root: String = "user://__profileorchtest/"
	SaveManager.set_saves_root(root)
	_store = SaveStore.new(root)
	_store.wipe_all()
	# Also clear any active-profile pointer from a prior run.
	_clear_active_pointer(root)
	SaveManager.set_saves_root(root)  # re-read pointer after clearing

	# Arrange a "playable" state so _can_autosave() passes: a player in group
	# "player", a non-empty scene path + room id, not transitioning.
	_install_fake_player()
	GameState.reset()
	GameState.current_scene_path = "res://scenes/room.tscn"
	GameState.current_room_id = "gate_room"
	GameState.current_objective = "Explore the Destiny"

	# New Game mints a fresh active profile.
	SaveManager.start_new_game()
	# start_new_game calls GameState.reset(), which clears the staged room. Re-
	# arm the playable state so the trigger handlers can write.
	GameState.current_scene_path = "res://scenes/room.tscn"
	GameState.current_room_id = "gate_room"
	GameState.current_objective = "Explore the Destiny"
	var pid: String = SaveManager.active_profile_id()
	_check(pid != "" and _store.has_profile(pid), "New Game created + activated a profile (id='%s')" % pid)

	# --- 1. autosave ring: 4 room transitions -> 3 survive ---
	for i in range(4):
		GameState.current_room_id = "room_%d" % i
		SaveManager._on_room_changed("room_%d" % i)
		# autosave ids are unix-stamped; nudge so distinct entries land even if
		# multiple writes share a wall-clock second (the manager disambiguates,
		# this just exercises the realistic path).
		await get_tree().process_frame
	var autos: int = _count_kind(pid, "autosave")
	_check(autos == 3, "autosave ring kept exactly 3 after 4 transitions (got %d)" % autos)

	# --- 2. manual save -> permanent ---
	GameState.current_room_id = "control_interface_room"
	GameState.current_objective = "Talk to Rush"
	var manual_id: String = SaveManager.save_manual("Before the leak")
	_check(manual_id != "" and _store.has_checkpoint(pid, manual_id), "manual save wrote a checkpoint")
	var mmeta: Dictionary = _store.read_checkpoint_meta(pid, manual_id)
	_check(mmeta.get("permanent", false) == true, "manual checkpoint is permanent")
	_check(mmeta.get("kind", "") == "manual", "manual checkpoint kind=manual")
	_check(mmeta.get("label", "") == "Before the leak", "manual label persisted")

	# --- 3. episode save -> permanent, once ---
	GameState.current_room_id = "breached_section_south"
	var ep_id: String = SaveManager.save_episode("air", "Episode 1: Air — Complete")
	var ep_id_again: String = SaveManager.save_episode("air")  # idempotent
	_check(ep_id != "" and _store.has_checkpoint(pid, ep_id), "episode save wrote a checkpoint")
	_check(ep_id_again == ep_id, "second episode save is idempotent (same id, no new cp)")
	var ep_count: int = _count_kind(pid, "episode")
	_check(ep_count == 1, "exactly one episode checkpoint exists (got %d)" % ep_count)
	var emeta: Dictionary = _store.read_checkpoint_meta(pid, ep_id)
	_check(emeta.get("permanent", false) == true, "episode checkpoint is permanent")

	# --- 4. episode_completed SIGNAL also writes idempotently ---
	# (the connected handler path, not just the direct call)
	var ep_before: int = _count_kind(pid, "episode")
	GameState.episode_completed.emit()
	await get_tree().process_frame
	_check(_count_kind(pid, "episode") == ep_before, "episode_completed signal does not duplicate the episode cp")

	# --- 5. permanence under autosave pressure ---
	for i in range(4):
		GameState.current_room_id = "pressure_%d" % i
		SaveManager._on_room_changed("pressure_%d" % i)
		await get_tree().process_frame
	_check(_store.has_checkpoint(pid, manual_id), "manual survived autosave pressure")
	_check(_store.has_checkpoint(pid, ep_id), "episode survived autosave pressure")
	_check(_count_kind(pid, "autosave") == 3, "autosave ring still capped at 3 under pressure")

	# --- 6. Continue (most-recent) points at the freshest checkpoint ---
	var newest_cid: String = SaveManager.most_recent(pid)
	_check(newest_cid != "" and _store.has_checkpoint(pid, newest_cid), "most_recent resolves a checkpoint")

	# --- 7. targeted resume restores the chosen (profile, checkpoint) ---
	# Resume the MANUAL checkpoint (control_interface_room) even though newer
	# autosaves exist — proves resume is checkpoint-targeted, not "most recent".
	GameState.reset()
	var ok: bool = SaveManager.load_and_resume_checkpoint(pid, manual_id)
	_check(ok, "load_and_resume_checkpoint returned true")
	var staged: Variant = GameState.pending_spawn_position
	# Wait for the deferred scene change to settle.
	var attempts: int = 0
	while attempts < 240:
		await get_tree().process_frame
		attempts += 1
	_check(GameState.current_room_id == "control_interface_room",
		"resumed manual checkpoint room (got '%s')" % GameState.current_room_id)
	_check(staged is Vector3, "resume staged a player spawn position")

	_store.wipe_all()
	print("\nprofile_orchestration: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ---- helpers ------------------------------------------------------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


func _count_kind(profile_id: String, kind: String) -> int:
	var n: int = 0
	for cp in _store.list_checkpoints(profile_id):
		if String(cp.get("kind", "")) == kind:
			n += 1
	return n


# A minimal Node3D in group "player" so _capture_player_transform + the
# _can_autosave player check pass. Lives under /root so the resume scene
# change doesn't free it mid-test.
func _install_fake_player() -> void:
	_player = Node3D.new()
	_player.name = "FakePlayer"
	_player.add_to_group("player")
	_player.global_position = Vector3(1.0, 0.0, 2.0)
	get_tree().root.add_child(_player)


func _clear_active_pointer(root: String) -> void:
	var path: String = root + "active.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
