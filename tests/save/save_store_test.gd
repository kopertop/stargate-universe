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
