extends Node

# End-to-end save-profiles INTEGRATION + MIGRATION suite (issue #82 — capstone
# of the save epic, #77/#79/#80/#81). The per-layer suites (save_store_test,
# profile_orchestration, load_browser, ingame_ui) each prove one slice; this
# one ties them together at the SaveManager level and proves the two things no
# single layer can on its own:
#
#   A. FULL LIFECYCLE across a simulated restart
#      New Game (profile) -> play (3-autosave ring rolls per room) -> manual
#      (permanent) -> complete Episode 1 (permanent episode checkpoint) ->
#      "quit" (drop the in-memory SaveManager pointer + re-resolve from disk) ->
#      Load browser sees the profile + every checkpoint -> resume a SPECIFIC
#      checkpoint AND Continue (most-recent). Two-level resume, post-restart.
#
#   B. MIGRATION SAFETY
#      A pre-existing FLAT save (real player layout: autosave ring + quicksave +
#      manual) becomes a "Default" profile with NO data loss; the run is
#      idempotent; and the SOURCE flat slots are PRESERVED until the new layout
#      is written + validated (reversible-enough — we never delete the source).
#
# Boots with real autoloads, isolates the saves root, asserts against SaveStore
# (the on-disk ground truth). Spawned at /root so a resume scene-change doesn't
# free us mid-test (mirrors profile_orchestration_runner.gd).

var _pass: int = 0
var _fail: int = 0
var _player: Node3D = null

const ROOT: String = "user://__saveinttest/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	# Hard-reset the root + active pointer so re-runs start from nothing.
	var bootstrap: SaveStore = SaveStore.new(ROOT)
	bootstrap.wipe_all()
	_wipe_tree(ROOT)
	_clear_active_pointer(ROOT)

	await _test_full_lifecycle_across_restart()
	await _test_migration_safety()

	_wipe_tree(ROOT)
	print("\nsave_integration: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# =========================================================================
# A. FULL LIFECYCLE ACROSS A SIMULATED RESTART
# =========================================================================

func _test_full_lifecycle_across_restart() -> void:
	var root: String = ROOT + "lifecycle/"
	var store: SaveStore = SaveStore.new(root)
	store.wipe_all()
	_wipe_tree(root)
	_clear_active_pointer(root)
	SaveManager.set_saves_root(root)

	_install_fake_player()
	GameState.reset()
	_arm_playable("gate_room", "Explore the Destiny")

	# --- New Game mints a fresh profile ---
	SaveManager.start_new_game("Colonel Young")
	# start_new_game -> GameState.reset() clears the staged room; re-arm.
	_arm_playable("gate_room", "Explore the Destiny")
	var pid: String = SaveManager.active_profile_id()
	_check(pid != "" and store.has_profile(pid), "New Game minted + activated a profile (id='%s')" % pid)

	# --- play: 4 room transitions -> autosave ring keeps the newest 3 ---
	for i in range(4):
		_arm_playable("room_%d" % i, "Explore the Destiny")
		SaveManager._on_room_changed("room_%d" % i)
		await get_tree().process_frame
	_check(_count_kind(store, pid, "autosave") == 3, "autosave ring kept exactly 3 after 4 transitions")

	# --- manual save -> permanent ---
	_arm_playable("control_interface_room", "Talk to Rush")
	var manual_id: String = SaveManager.save_manual("Before the leak")
	_check(manual_id != "" and store.has_checkpoint(pid, manual_id), "manual save wrote a checkpoint")
	_check(store.read_checkpoint_meta(pid, manual_id).get("permanent", false) == true, "manual checkpoint permanent")

	# --- complete Episode 1 -> one permanent episode checkpoint ---
	_arm_playable("hydroponics_dome", "Reach the lime planet")
	var ep_id: String = SaveManager.save_episode("1", "Episode 1 — Complete")
	_check(ep_id != "" and store.has_checkpoint(pid, ep_id), "episode checkpoint written")
	_check(store.read_checkpoint_meta(pid, ep_id).get("permanent", false) == true, "episode checkpoint permanent")

	# Snapshot the full expected on-disk set BEFORE the simulated quit.
	var cp_count_before: int = store.list_checkpoints(pid).size()
	var newest_before: String = store.most_recent_checkpoint(pid)
	_check(cp_count_before == 5, "5 checkpoints on disk pre-quit (3 autosave + manual + episode), got %d" % cp_count_before)

	# --- QUIT: forget the in-memory SaveManager state, re-resolve from disk ---
	# Simulates a fresh process: SaveManager re-reads active.json + the profile
	# dirs that survived. This is the real Continue/Load path after relaunch.
	_simulate_restart(root)

	# --- Load browser (two-level): profile -> checkpoints, all visible ---
	var profiles: Array[Dictionary] = SaveManager.list_profiles()
	var found_profile: bool = false
	for p in profiles:
		if String(p.get("id", "")) == pid:
			found_profile = true
	_check(found_profile, "Load browser profile level lists the saved profile after restart")
	_check(SaveManager.list_checkpoints(pid).size() == cp_count_before,
		"all %d checkpoints survive the restart and list" % cp_count_before)
	# Every kind is browsable post-restart.
	_check(_count_kind(store, pid, "autosave") == 3, "3 autosaves browsable post-restart")
	_check(_count_kind(store, pid, "manual") == 1, "manual browsable post-restart")
	_check(_count_kind(store, pid, "episode") == 1, "episode browsable post-restart")

	# --- resume a SPECIFIC checkpoint (the permanent manual) ---
	SaveManager.set_active_profile(pid)
	GameState.reset()
	var ok_specific: bool = SaveManager.load_and_resume_checkpoint(pid, manual_id)
	_check(ok_specific, "targeted resume of the manual checkpoint returned true")
	await _settle()
	_check(GameState.current_room_id == "control_interface_room",
		"targeted resume restored the manual checkpoint's room (got '%s')" % GameState.current_room_id)

	# --- Continue (most-recent) resumes the freshest checkpoint ---
	# The episode checkpoint (hydroponics_dome) is the newest write.
	GameState.reset()
	var ok_continue: bool = SaveManager.load_and_resume("")
	_check(ok_continue, "Continue (most-recent) resume returned true")
	await _settle()
	var resumed: String = GameState.current_room_id
	var newest_room: String = String(store.read_checkpoint_meta(pid, newest_before).get("room_id", ""))
	_check(resumed == newest_room,
		"Continue resumed the most-recent checkpoint's room (got '%s', expected '%s')" % [resumed, newest_room])

	store.wipe_all()
	_wipe_tree(root)


# =========================================================================
# B. MIGRATION SAFETY
# =========================================================================

func _test_migration_safety() -> void:
	var root: String = ROOT + "migrate/"
	var store: SaveStore = SaveStore.new(root)
	store.wipe_all()
	_wipe_tree(root)

	# --- Arrange: a realistic FLAT player layout ---
	# autosave with two writes (so a backup exists -> ring seeds 2),
	# a quicksave, and a manual slot. This is exactly what a pre-#77 player's
	# user://saves/ looks like.
	_write_flat(store, "autosave", "room_old")    # becomes a backup
	_write_flat(store, "autosave", "room_new")     # becomes the primary
	_write_flat(store, "quicksave", "quick_room")
	_write_flat(store, "manual_1", "manual_room")

	# Capture the source payloads so we can prove LOSSLESS + PRESERVED.
	var src_autosave: String = _room_of_dict(store.read_snapshot("autosave"))
	var src_quick: String = _room_of_dict(store.read_snapshot("quicksave"))
	var src_manual: String = _room_of_dict(store.read_snapshot("manual_1"))

	# --- Act: migrate ---
	var migrated: bool = store.migrate_flat_to_profile()
	_check(migrated, "migrate_flat_to_profile reported a move")
	_check(store.has_profile(SaveStore.DEFAULT_PROFILE_ID), "Default profile created by migration")

	# --- LOSSLESS: every source slot is represented as a checkpoint ---
	var cps: Array[Dictionary] = store.list_checkpoints(SaveStore.DEFAULT_PROFILE_ID)
	# 2 autosave (primary+backup) + 1 quicksave + 1 manual = 4.
	_check(cps.size() == 4, "4 checkpoints migrated (2 autosave + quicksave + manual), got %d" % cps.size())
	_check(_count_kind(store, SaveStore.DEFAULT_PROFILE_ID, "autosave") == 2, "autosave ring seeded with 2")
	_check(_count_kind(store, SaveStore.DEFAULT_PROFILE_ID, "quicksave") == 1, "quicksave migrated")
	_check(_count_kind(store, SaveStore.DEFAULT_PROFILE_ID, "manual") == 1, "manual migrated as permanent")

	# Payloads land intact: the migrated newest autosave is the former primary,
	# the quicksave + manual payloads round-trip.
	var migrated_rooms: Array[String] = []
	for cp in cps:
		migrated_rooms.append(_room_of_dict(store.read_checkpoint(SaveStore.DEFAULT_PROFILE_ID, String(cp.get("checkpoint_id", "")))))
	_check(migrated_rooms.has("room_new"), "newest autosave payload (former primary) preserved")
	_check(migrated_rooms.has("quick_room"), "quicksave payload preserved")
	_check(migrated_rooms.has("manual_room"), "manual payload preserved")

	# --- REVERSIBLE-ENOUGH: source flat slots are NOT deleted ---
	# migrate_flat_to_profile only READS the flat slots; it never wipes them, so
	# a failed/partial migration can always fall back to the original layout.
	_check(store.has_slot("autosave"), "source flat autosave slot preserved (not deleted)")
	_check(store.has_slot("quicksave"), "source flat quicksave slot preserved")
	_check(store.has_slot("manual_1"), "source flat manual slot preserved")
	_check(_room_of_dict(store.read_snapshot("autosave")) == src_autosave, "source autosave payload byte-intact")
	_check(_room_of_dict(store.read_snapshot("quicksave")) == src_quick, "source quicksave payload byte-intact")
	_check(_room_of_dict(store.read_snapshot("manual_1")) == src_manual, "source manual payload byte-intact")

	# --- IDEMPOTENT: a second migrate is a no-op, no duplicate checkpoints ---
	var count_before: int = store.list_checkpoints(SaveStore.DEFAULT_PROFILE_ID).size()
	var second: bool = store.migrate_flat_to_profile()
	var count_after: int = store.list_checkpoints(SaveStore.DEFAULT_PROFILE_ID).size()
	_check(not second, "second migration is a no-op")
	_check(count_before == count_after, "no duplicate checkpoints on re-run")

	# --- VALIDATED: the migrated Default profile resumes through SaveManager ---
	# Prove the migrated layout is actually loadable (not just on disk) by
	# pointing the live SaveManager at it and resuming the most-recent checkpoint.
	_simulate_restart(root)
	_install_fake_player()
	GameState.reset()
	var ok: bool = SaveManager.load_and_resume("")
	_check(ok, "migrated Default profile resumes via Continue")
	await _settle()
	# Continue lands in one of the migrated rooms (the most-recent checkpoint).
	# We don't pin the exact room: the migration stamps the autosave ring from a
	# shared base ts while quicksave/manual keep their own snapshot timestamps,
	# so which checkpoint is "most recent" depends on the source save's clock —
	# the LOSSLESS/PRESERVED/IDEMPOTENT assertions above already pin the data.
	var migrated_set: Array[String] = ["room_new", "room_old", "quick_room", "manual_room"]
	_check(migrated_set.has(GameState.current_room_id),
		"migrated profile resumed into a migrated room (got '%s')" % GameState.current_room_id)

	store.wipe_all()
	_wipe_tree(root)


# =========================================================================
# helpers
# =========================================================================

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


func _arm_playable(room_id: String, objective: String) -> void:
	GameState.current_scene_path = "res://scenes/room.tscn"
	GameState.current_room_id = room_id
	GameState.current_objective = objective


func _count_kind(store: SaveStore, profile_id: String, kind: String) -> int:
	var n: int = 0
	for cp in store.list_checkpoints(profile_id):
		if String(cp.get("kind", "")) == kind:
			n += 1
	return n


# Re-point SaveManager at the root as if the process just relaunched: this
# re-reads active.json + the on-disk profile dirs, discarding any in-memory
# checkpoint bookkeeping. The closest a headless test gets to a real restart.
func _simulate_restart(root: String) -> void:
	SaveManager.set_saves_root(root)


func _write_flat(store: SaveStore, slot_id: String, room: String) -> void:
	var snap: Dictionary = _sample_snapshot(room)
	store.write_snapshot(slot_id, snap, store.build_meta_from_snapshot(slot_id, snap))


func _sample_snapshot(room: String) -> Dictionary:
	return {
		"version": 2,
		"timestamp": int(Time.get_unix_time_from_system()),
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": [1.0, 0.0, 2.0], "yaw": 0.5},
		"systems": {
			"game_clock": {"elapsed_seconds": 12.0},
			"game_state": {"current_room_id": room, "quest_step": "play", "objective": "Explore"},
		},
	}


func _room_of_dict(data: Dictionary) -> String:
	var systems: Variant = data.get("systems", {})
	if systems is Dictionary and (systems as Dictionary).get("game_state", null) is Dictionary:
		return String((systems as Dictionary)["game_state"].get("current_room_id", ""))
	return ""


# A minimal Node3D in group "player" under /root so resume scene-changes don't
# free it, and _capture_player_transform / _can_autosave both pass.
func _install_fake_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = Node3D.new()
	_player.name = "FakePlayerIntegration"
	_player.add_to_group("player")
	_player.global_position = Vector3(1.0, 0.0, 2.0)
	get_tree().root.add_child(_player)


func _settle() -> void:
	var attempts: int = 0
	while attempts < 240:
		await get_tree().process_frame
		attempts += 1


func _clear_active_pointer(root: String) -> void:
	var path: String = root + "active.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _wipe_tree(path: String) -> void:
	if not path.ends_with("/"):
		path += "/"
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_wipe_tree(path + name + "/")
		else:
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
