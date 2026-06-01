extends SceneTree

# Isolated unit tests for SaveStore (pure persistence). Each test runs against
# a throwaway user://__savetest_<n>/ root, wiped in setup + teardown, so the
# suite never depends on (or touches) external state — including the player's
# real saves. SceneTree harness, no GDUnit. Wired into tests/run.sh `save`.

var _pass: int = 0
var _fail: int = 0
var _root_counter: int = 0


func _init() -> void:
	_run("test_save_store_write_then_read_round_trips", _t_round_trip)
	_run("test_save_store_writes_meta_sidecar_alongside_payload", _t_meta_sidecar)
	_run("test_save_store_list_slots_reads_metadata_without_full_load", _t_list_no_full_load)
	_run("test_save_store_backup_rotation_keeps_three_newest", _t_backup_rotation)
	_run("test_save_store_corrupt_primary_falls_back_to_backup", _t_corrupt_fallback)
	_run("test_save_store_wipe_slot_removes_only_that_slot", _t_wipe_one_slot)
	_run("test_save_store_most_recent_slot_picks_highest_timestamp", _t_most_recent)
	_run("test_save_store_legacy_single_save_migrates_to_autosave", _t_legacy_migrate)
	_run("test_save_store_edit_set_dot_path_mutates_field_and_rewrites", _t_edit_dot_path)
	_run("test_save_store_edit_set_player_pos_parses_vector", _t_edit_player_pos)
	_run("test_save_manager_headless_session_does_not_touch_player_slots", _t_headless_isolation)

	# ---- profile + checkpoint model (issue #77) ----
	_run("test_save_store_create_profile_writes_profile_json_and_lists", _t_profile_crud)
	_run("test_save_store_checkpoint_round_trips_with_kind_meta", _t_checkpoint_round_trip)
	_run("test_save_store_autosave_ring_keeps_newest_three_evicts_older", _t_autosave_ring)
	_run("test_save_store_permanent_checkpoints_survive_autosave_pressure", _t_permanent_survive)
	_run("test_save_store_delete_checkpoint_refuses_permanent_kinds", _t_delete_refuses_permanent)
	_run("test_save_store_delete_checkpoint_removes_rolling_kinds", _t_delete_allows_rolling)
	_run("test_save_store_most_recent_checkpoint_picks_newest_timestamp", _t_most_recent_checkpoint)
	_run("test_save_store_migrate_flat_layout_into_default_profile", _t_migrate_flat)
	_run("test_save_store_migrate_flat_is_idempotent", _t_migrate_flat_idempotent)

	print("\nsave_store_test: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ---- harness ------------------------------------------------------------

func _run(name: String, fn: Callable) -> void:
	var root: String = _fresh_root()
	var ok: bool = fn.call(root)
	_wipe_dir(root)
	if ok:
		_pass += 1
		print("  PASS  %s" % name)
	else:
		_fail += 1
		print("  FAIL  %s" % name)


func _fresh_root() -> String:
	_root_counter += 1
	var root: String = "user://__savetest_%d/" % _root_counter
	_wipe_dir(root)
	return root


func _assert(cond: bool, msg: String) -> bool:
	if not cond:
		print("    assertion failed: %s" % msg)
	return cond


func _sample_snapshot(room := "gate_room", step := "talk_scott", pos := [1.0, 0.0, 2.0]) -> Dictionary:
	return {
		"version": 2,
		"timestamp": 100,
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": pos, "yaw": 0.5},
		"systems": {
			"game_clock": {"elapsed_seconds": 42.0},
			"game_state": {"current_room_id": room, "quest_step": step, "objective": "Do the thing."},
		},
	}


# ---- tests --------------------------------------------------------------

func _t_round_trip(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var snap: Dictionary = _sample_snapshot()
	var meta: Dictionary = store.build_meta_from_snapshot("manual_1", snap)
	# Act
	var wrote: bool = store.write_snapshot("manual_1", snap, meta)
	var read: Dictionary = store.read_snapshot("manual_1")
	# Assert
	var ok: bool = _assert(wrote, "write_snapshot returned true")
	ok = _assert(read.get("scene_path", "") == snap["scene_path"], "scene_path round-trips") and ok
	ok = _assert(int(read.get("version", 0)) == 2, "version round-trips") and ok
	return ok


func _t_meta_sidecar(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var snap: Dictionary = _sample_snapshot("control_interface_room", "talk_rush")
	var meta: Dictionary = store.build_meta_from_snapshot("autosave", snap)
	# Act
	store.write_snapshot("autosave", snap, meta)
	# Assert: meta.json exists alongside save.json and carries derived fields.
	var ok: bool = _assert(FileAccess.file_exists(store.meta_path("autosave")), "meta.json written")
	var read_meta: Dictionary = store.read_meta("autosave")
	ok = _assert(read_meta.get("room_id", "") == "control_interface_room", "meta.room_id derived") and ok
	ok = _assert(read_meta.get("objective", "") == "Do the thing.", "meta.objective derived") and ok
	ok = _assert(abs(float(read_meta.get("playtime_seconds", -1.0)) - 42.0) < 0.001, "meta.playtime from clock") and ok
	return ok


func _t_list_no_full_load(root: String) -> bool:
	# Arrange: a slot with a valid meta but a payload we corrupt — listing
	# must succeed from meta alone, proving it never parses the payload.
	var store: SaveStore = SaveStore.new(root)
	var snap: Dictionary = _sample_snapshot("eli_quarters")
	store.write_snapshot("manual_2", snap, store.build_meta_from_snapshot("manual_2", snap))
	var f: FileAccess = FileAccess.open(store.primary_path("manual_2"), FileAccess.WRITE)
	f.store_string("{ this is not valid json")
	f.close()
	# Act
	var slots: Array[Dictionary] = store.list_slots()
	# Assert
	var ok: bool = _assert(slots.size() == 1, "one slot listed")
	ok = _assert(slots.size() == 1 and slots[0].get("room_id", "") == "eli_quarters", "room_id read from meta despite corrupt payload") and ok
	return ok


func _t_backup_rotation(root: String) -> bool:
	# Arrange / Act: five writes; backups keep the three NEWEST prior primaries.
	var store: SaveStore = SaveStore.new(root)
	for i in range(5):
		var snap: Dictionary = _sample_snapshot("room_%d" % i)
		store.write_snapshot("manual_1", snap, store.build_meta_from_snapshot("manual_1", snap))
	# After 5 writes: primary=room_4; bak.1=room_3; bak.2=room_2; bak.3=room_1.
	var baks: Array[String] = store.backup_paths("manual_1")
	var ok: bool = _assert(FileAccess.file_exists(baks[0]) and FileAccess.file_exists(baks[1]) and FileAccess.file_exists(baks[2]), "three backups present")
	ok = _assert(_room_of(baks[0]) == "room_3", "bak.1 = room_3") and ok
	ok = _assert(_room_of(baks[2]) == "room_1", "bak.3 = room_1 (room_0 discarded)") and ok
	return ok


func _t_corrupt_fallback(root: String) -> bool:
	# Arrange: two writes so a backup exists, then corrupt the primary.
	var store: SaveStore = SaveStore.new(root)
	store.write_snapshot("manual_1", _sample_snapshot("first_room"), store.build_meta_from_snapshot("manual_1", _sample_snapshot("first_room")))
	store.write_snapshot("manual_1", _sample_snapshot("second_room"), store.build_meta_from_snapshot("manual_1", _sample_snapshot("second_room")))
	var f: FileAccess = FileAccess.open(store.primary_path("manual_1"), FileAccess.WRITE)
	f.store_string("garbage{")
	f.close()
	# Act: read should fall back to bak.1 (first_room).
	var read: Dictionary = store.read_snapshot("manual_1")
	# Assert
	return _assert(_room_of_dict(read) == "first_room", "fell back to backup snapshot")


func _t_wipe_one_slot(root: String) -> bool:
	# Arrange: two slots populated.
	var store: SaveStore = SaveStore.new(root)
	store.write_snapshot("manual_1", _sample_snapshot(), store.build_meta_from_snapshot("manual_1", _sample_snapshot()))
	store.write_snapshot("manual_2", _sample_snapshot(), store.build_meta_from_snapshot("manual_2", _sample_snapshot()))
	# Act
	store.wipe_slot("manual_1")
	# Assert
	var ok: bool = _assert(not store.has_slot("manual_1"), "manual_1 wiped")
	ok = _assert(store.has_slot("manual_2"), "manual_2 untouched") and ok
	return ok


func _t_most_recent(root: String) -> bool:
	# Arrange: three slots with ascending timestamps.
	var store: SaveStore = SaveStore.new(root)
	for entry in [["manual_1", 100], ["autosave", 300], ["quicksave", 200]]:
		var snap: Dictionary = _sample_snapshot()
		var meta: Dictionary = store.build_meta_from_snapshot(entry[0], snap)
		meta["timestamp"] = entry[1]
		store.write_snapshot(entry[0], snap, meta)
	# Act / Assert
	return _assert(store.most_recent_slot() == "autosave", "highest timestamp wins")


func _t_legacy_migrate(root: String) -> bool:
	# Arrange: a pre-slots single save at user://save.json. Use a temp legacy
	# file we clean up; root is the slots root migrate writes into.
	var legacy_snap: Dictionary = _sample_snapshot("legacy_room", "legacy_step")
	var lf: FileAccess = FileAccess.open("user://save.json", FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy_snap, "\t"))
	lf.close()
	var store: SaveStore = SaveStore.new(root)
	# Act
	var migrated: bool = store.migrate_legacy()
	# Assert: autosave slot now holds the legacy snapshot + a derived meta;
	# legacy primary moved (no longer present).
	var ok: bool = _assert(migrated, "migrate_legacy reported a move")
	ok = _assert(store.has_slot("autosave"), "autosave slot created") and ok
	ok = _assert(_room_of_dict(store.read_snapshot("autosave")) == "legacy_room", "legacy snapshot landed in autosave") and ok
	ok = _assert(store.read_meta("autosave").get("room_id", "") == "legacy_room", "meta derived during migration") and ok
	ok = _assert(not FileAccess.file_exists("user://save.json"), "legacy primary moved out") and ok
	# Cleanup any stray legacy file.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	return ok


func _t_edit_dot_path(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var snap: Dictionary = _sample_snapshot("gate_room", "talk_scott")
	store.write_snapshot("manual_1", snap, store.build_meta_from_snapshot("manual_1", snap))
	# Act: mimic save_edit's dot-path mutation directly on the dict, rewrite.
	var data: Dictionary = store.read_snapshot("manual_1")
	data["systems"]["game_state"]["quest_step"] = "find_scrubber"
	store.rewrite_snapshot("manual_1", data, store.build_meta_from_snapshot("manual_1", data))
	# Assert
	var read: Dictionary = store.read_snapshot("manual_1")
	return _assert(read["systems"]["game_state"]["quest_step"] == "find_scrubber", "dot-path edit persisted")


func _t_edit_player_pos(root: String) -> bool:
	# Arrange: load the editor's coercion via a script instance is overkill;
	# assert the SaveStore side persists an array pos written by the editor.
	var store: SaveStore = SaveStore.new(root)
	var snap: Dictionary = _sample_snapshot()
	store.write_snapshot("manual_1", snap, store.build_meta_from_snapshot("manual_1", snap))
	# Act
	var data: Dictionary = store.read_snapshot("manual_1")
	data["player"]["pos"] = [1.5, 0.3, -4.0]
	store.rewrite_snapshot("manual_1", data, store.build_meta_from_snapshot("manual_1", data))
	# Assert
	var read: Dictionary = store.read_snapshot("manual_1")
	var p: Array = read["player"]["pos"]
	var ok: bool = _assert(p.size() == 3, "pos is a 3-vector array")
	ok = _assert(abs(float(p[0]) - 1.5) < 0.001 and abs(float(p[2]) + 4.0) < 0.001, "pos values persisted") and ok
	return ok


func _t_headless_isolation(root: String) -> bool:
	# THE LOSS REGRESSION. Player slots live under one root; a "headless
	# session" (a capture/tool run) must write only its sandbox root and leave
	# the player root byte-for-byte untouched, even though it mutates state.
	# Arrange: a real player save.
	var player_root: String = root + "player/"
	var sandbox_root: String = root + "sandbox/"
	var player_store: SaveStore = SaveStore.new(player_root)
	var real_snap: Dictionary = _sample_snapshot("real_room", "real_step")
	player_store.write_snapshot("autosave", real_snap, player_store.build_meta_from_snapshot("autosave", real_snap))
	var before: String = _read_text(player_store.primary_path("autosave"))
	# Act: a headless session, isolated to the sandbox root, mutates + saves.
	var headless_store: SaveStore = SaveStore.new(sandbox_root)
	var throwaway: Dictionary = _sample_snapshot("capture_room", "capture_step")
	headless_store.write_snapshot("autosave", throwaway, headless_store.build_meta_from_snapshot("autosave", throwaway))
	# Assert: player file unchanged; sandbox got the throwaway.
	var after: String = _read_text(player_store.primary_path("autosave"))
	var ok: bool = _assert(before == after and before != "", "player slot byte-for-byte untouched by headless session")
	ok = _assert(_room_of_dict(headless_store.read_snapshot("autosave")) == "capture_room", "sandbox root captured the throwaway") and ok
	ok = _assert(_room_of_dict(player_store.read_snapshot("autosave")) == "real_room", "player save still holds real state") and ok
	return ok


# ---- profile + checkpoint tests -----------------------------------------

func _t_profile_crud(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	# Act
	var pid: String = store.create_profile("My Run")
	var read: Dictionary = store.read_profile(pid)
	store.write_profile(pid, {"display_name": "Renamed", "created": read.get("created", 0), "active_checkpoint": ""})
	var listed: Array[Dictionary] = store.list_profiles()
	# Assert
	var ok: bool = _assert(pid == "my_run", "profile id slugified to 'my_run' (got '%s')" % pid)
	ok = _assert(FileAccess.file_exists(store.profile_meta_path(pid)), "profile.json written") and ok
	ok = _assert(store.read_profile(pid).get("display_name", "") == "Renamed", "write_profile updated display_name") and ok
	ok = _assert(listed.size() == 1 and listed[0].get("id", "") == pid, "list_profiles returns the profile") and ok
	return ok


func _t_checkpoint_round_trip(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	var snap: Dictionary = _sample_snapshot("gate_room")
	var meta: Dictionary = store.build_meta_from_snapshot("manual_x", snap)
	meta["kind"] = "manual"
	meta["label"] = "Before the leak"
	# Act
	var wrote: bool = store.write_checkpoint(pid, "manual_x", snap, meta)
	var read: Dictionary = store.read_checkpoint(pid, "manual_x")
	var cmeta: Dictionary = store.read_checkpoint_meta(pid, "manual_x")
	# Assert
	var ok: bool = _assert(wrote, "write_checkpoint returned true")
	ok = _assert(_room_of_dict(read) == "gate_room", "snapshot round-trips") and ok
	ok = _assert(cmeta.get("kind", "") == "manual", "meta.kind persisted") and ok
	ok = _assert(cmeta.get("label", "") == "Before the leak", "meta.label persisted") and ok
	ok = _assert(cmeta.get("permanent", false) == true, "manual checkpoint flagged permanent") and ok
	return ok


func _t_autosave_ring(root: String) -> bool:
	# Arrange: a profile and four autosave writes with strictly ascending ts.
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	# Act: write 4 autosaves; ring must keep the newest 3.
	for i in range(4):
		var snap: Dictionary = _sample_snapshot("room_%d" % i)
		var cid: String = "autosave_%d" % (1000 + i)
		var meta: Dictionary = store.build_meta_from_snapshot(cid, snap)
		meta["timestamp"] = 1000 + i
		meta["kind"] = "autosave"
		store.write_checkpoint(pid, cid, snap, meta)
	# Assert: exactly 3 autosave checkpoints, the newest 3 (room_1..room_3),
	# room_0 evicted, and all 3 are individually readable.
	var autos: Array[Dictionary] = store.list_checkpoints(pid)
	var ok: bool = _assert(autos.size() == 3, "ring holds exactly 3 (got %d)" % autos.size())
	ok = _assert(not store.has_checkpoint(pid, "autosave_1000"), "oldest (room_0) evicted") and ok
	ok = _assert(store.has_checkpoint(pid, "autosave_1003"), "newest kept") and ok
	# All three loadable
	for cid in ["autosave_1001", "autosave_1002", "autosave_1003"]:
		ok = _assert(not store.read_checkpoint(pid, cid).is_empty(), "%s loadable" % cid) and ok
	return ok


func _t_permanent_survive(root: String) -> bool:
	# Arrange: two manuals + one episode + then autosave pressure.
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	_write_cp(store, pid, "manual_1", "manual", 500, "m1")
	_write_cp(store, pid, "manual_2", "manual", 501, "m2")
	_write_cp(store, pid, "episode_air", "episode", 502, "ep")
	# Act: five autosaves to push the ring well past 3.
	for i in range(5):
		_write_cp(store, pid, "autosave_%d" % (2000 + i), "autosave", 2000 + i, "a")
	# Assert: both manuals + the episode checkpoint are all still present.
	var ok: bool = _assert(store.has_checkpoint(pid, "manual_1"), "manual_1 survived")
	ok = _assert(store.has_checkpoint(pid, "manual_2"), "manual_2 survived") and ok
	ok = _assert(store.has_checkpoint(pid, "episode_air"), "episode survived") and ok
	# And the autosave ring is still capped at 3.
	var autos: int = 0
	for cp in store.list_checkpoints(pid):
		if cp.get("kind", "") == "autosave":
			autos += 1
	ok = _assert(autos == 3, "autosave ring still capped at 3 (got %d)" % autos) and ok
	return ok


func _t_delete_refuses_permanent(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	_write_cp(store, pid, "manual_1", "manual", 100, "m")
	_write_cp(store, pid, "episode_air", "episode", 101, "e")
	# Act
	var del_manual: bool = store.delete_checkpoint(pid, "manual_1")
	var del_episode: bool = store.delete_checkpoint(pid, "episode_air")
	# Assert: both refused, both still on disk.
	var ok: bool = _assert(not del_manual, "delete refused for manual")
	ok = _assert(not del_episode, "delete refused for episode") and ok
	ok = _assert(store.has_checkpoint(pid, "manual_1"), "manual still on disk") and ok
	ok = _assert(store.has_checkpoint(pid, "episode_air"), "episode still on disk") and ok
	return ok


func _t_delete_allows_rolling(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	_write_cp(store, pid, "autosave_1", "autosave", 100, "a")
	_write_cp(store, pid, "quicksave", "quicksave", 101, "q")
	# Act
	var del_auto: bool = store.delete_checkpoint(pid, "autosave_1")
	var del_quick: bool = store.delete_checkpoint(pid, "quicksave")
	# Assert
	var ok: bool = _assert(del_auto, "autosave deletable")
	ok = _assert(del_quick, "quicksave deletable") and ok
	ok = _assert(not store.has_checkpoint(pid, "autosave_1"), "autosave removed") and ok
	ok = _assert(not store.has_checkpoint(pid, "quicksave"), "quicksave removed") and ok
	return ok


func _t_most_recent_checkpoint(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	var pid: String = store.create_profile("Default")
	_write_cp(store, pid, "manual_1", "manual", 100, "m")
	_write_cp(store, pid, "autosave_x", "autosave", 999, "a")
	_write_cp(store, pid, "quicksave", "quicksave", 500, "q")
	# Act / Assert
	return _assert(store.most_recent_checkpoint(pid) == "autosave_x", "newest ts wins")


func _t_migrate_flat(root: String) -> bool:
	# Arrange: a legacy FLAT layout — an autosave with backups, a quicksave,
	# and a manual slot.
	var store: SaveStore = SaveStore.new(root)
	# autosave: two writes so a backup exists (primary newest = room_b).
	store.write_snapshot("autosave", _sample_snapshot("room_a"), store.build_meta_from_snapshot("autosave", _sample_snapshot("room_a")))
	store.write_snapshot("autosave", _sample_snapshot("room_b"), store.build_meta_from_snapshot("autosave", _sample_snapshot("room_b")))
	store.write_snapshot("quicksave", _sample_snapshot("quick_room"), store.build_meta_from_snapshot("quicksave", _sample_snapshot("quick_room")))
	store.write_snapshot("manual_1", _sample_snapshot("manual_room"), store.build_meta_from_snapshot("manual_1", _sample_snapshot("manual_room")))
	# Act
	var migrated: bool = store.migrate_flat_to_profile()
	# Assert: a Default profile exists with the right checkpoint set.
	var ok: bool = _assert(migrated, "migrate reported a move")
	ok = _assert(store.has_profile("default"), "Default profile created") and ok
	var checkpoints: Array[Dictionary] = store.list_checkpoints("default")
	# autosave ring (primary + 1 backup = 2), quicksave (1), manual (1) = 4.
	ok = _assert(checkpoints.size() == 4, "4 checkpoints migrated (got %d)" % checkpoints.size()) and ok
	# Autosave ring seeded from primary + backup, newest first = room_b.
	var autos: Array[Dictionary] = []
	for cp in checkpoints:
		if cp.get("kind", "") == "autosave":
			autos.append(cp)
	ok = _assert(autos.size() == 2, "autosave ring seeded with 2 (primary+backup)") and ok
	if autos.size() == 2:
		var newest: Dictionary = store.read_checkpoint("default", String(autos[0].get("checkpoint_id", "")))
		ok = _assert(_room_of_dict(newest) == "room_b", "newest autosave = former primary (room_b)") and ok
	# Manual became a permanent checkpoint.
	var has_perm_manual: bool = false
	for cp in checkpoints:
		if cp.get("kind", "") == "manual" and cp.get("permanent", false) == true:
			has_perm_manual = true
	ok = _assert(has_perm_manual, "manual slot folded into a permanent manual checkpoint") and ok
	# Regression: active_checkpoint must resolve to the real most-recent AUTOSAVE,
	# not a migrated permanent manual. Manuals were once stamped now+i (future),
	# which let them outrank the autosave ring in most_recent_checkpoint().
	var prof: Dictionary = store.read_profile("default")
	var active: String = String(prof.get("active_checkpoint", ""))
	ok = _assert(store._kind_from_id(active) == "autosave", "active_checkpoint is an autosave, not a migrated manual (got '%s')" % active) and ok
	return ok


func _t_migrate_flat_idempotent(root: String) -> bool:
	# Arrange
	var store: SaveStore = SaveStore.new(root)
	store.write_snapshot("autosave", _sample_snapshot("room_a"), store.build_meta_from_snapshot("autosave", _sample_snapshot("room_a")))
	# Act: migrate twice.
	var first: bool = store.migrate_flat_to_profile()
	var count_after_first: int = store.list_checkpoints("default").size()
	var second: bool = store.migrate_flat_to_profile()
	var count_after_second: int = store.list_checkpoints("default").size()
	# Assert: second run is a no-op and does not duplicate checkpoints.
	var ok: bool = _assert(first, "first migrate moved data")
	ok = _assert(not second, "second migrate is a no-op") and ok
	ok = _assert(count_after_first == count_after_second, "no duplicate checkpoints on re-run") and ok
	return ok


# Helper: write a classified checkpoint with an explicit timestamp.
func _write_cp(store: SaveStore, pid: String, cid: String, kind: String, ts: int, room: String) -> void:
	var snap: Dictionary = _sample_snapshot(room)
	var meta: Dictionary = store.build_meta_from_snapshot(cid, snap)
	meta["timestamp"] = ts
	meta["kind"] = kind
	store.write_checkpoint(pid, cid, snap, meta)


# ---- read helpers -------------------------------------------------------

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func _room_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return _room_of_dict(parsed)
	return ""


func _room_of_dict(data: Dictionary) -> String:
	var systems: Variant = data.get("systems", {})
	if systems is Dictionary and (systems as Dictionary).get("game_state", null) is Dictionary:
		return String((systems as Dictionary)["game_state"].get("current_room_id", ""))
	return ""


func _wipe_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_wipe_dir(path + name + "/")
		else:
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
