extends Node

# Owns auto-save / quicksave / resume orchestration.
#
# Autosave triggers: GameState.objective_changed and GameState.current_room_changed
# fire on every quest advance and every room transition. Each fire writes
# user://save.json atomically (tmp file + rename) and rotates 3 backups so a
# corrupt or partial primary doesn't lose progress.
#
# Subsystems plug in via register_system(id, system) where `system`
# implements `serialize() -> Dictionary` and `deserialize(data, version)
# -> void`. Each system handles its own forward-compat (missing keys ->
# defaults). Registration order = autoload order: GameClock then GameState
# then NPCState, so deserialize is applied in that order on resume.

signal save_written()
signal save_loaded()
signal save_wiped()

const SAVE_PATH: String = "user://save.json"
const SAVE_TMP_PATH: String = "user://save.json.tmp"
const BACKUP_PATHS: Array[String] = [
	"user://save.bak.1.json",
	"user://save.bak.2.json",
	"user://save.bak.3.json",
]
const SAVE_VERSION: int = 2

var _systems: Dictionary = {}
var _autosave_hooks_ready: bool = false
# Set during deserialize so the signals fired by GameState/etc.'s hydration
# pass don't recursively trigger autosaves while we're mid-load.
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Defer signal hookup so we don't depend on GameState being ready in
	# this _ready() — every autoload's _ready runs in registration order;
	# call_deferred guarantees ours runs after the whole batch settles.
	call_deferred("_install_autosave_hooks")


func _install_autosave_hooks() -> void:
	if _autosave_hooks_ready:
		return
	_autosave_hooks_ready = true
	GameState.objective_changed.connect(_on_quest_changed)
	GameState.current_room_changed.connect(_on_room_changed)


func register_system(id: String, system: Object) -> void:
	if id == "":
		push_error("SaveManager: refusing to register system with empty id")
		return
	if not (system.has_method("serialize") and system.has_method("deserialize")):
		push_error("SaveManager: system '%s' missing serialize/deserialize" % id)
		return
	_systems[id] = system


func has_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		return true
	for p in BACKUP_PATHS:
		if FileAccess.file_exists(p):
			return true
	return false


func _on_quest_changed(_text: String) -> void:
	if _loading:
		return
	if _can_autosave():
		save()


func _on_room_changed(_room_id: String) -> void:
	if _loading:
		return
	if _can_autosave():
		save()


func _can_autosave() -> bool:
	if GameState.current_scene_path == "":
		return false
	if SceneRouter.is_transitioning:
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return false
	return true


# Atomic snapshot write. Rotates backups (.bak.1 -> .bak.2 -> .bak.3, oldest
# discarded) before clobbering the primary, then writes tmp + renames over
# the target. Either the primary holds the new save or stays unchanged.
func save() -> void:
	if GameState.current_scene_path == "":
		return
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return
	if not _write_atomic(SAVE_PATH, data):
		return
	save_written.emit()


func _build_snapshot() -> Dictionary:
	var player_block: Dictionary = _capture_player_transform()
	if player_block.is_empty():
		return {}
	var systems_data: Dictionary = {}
	for id in _systems.keys():
		var sys: Object = _systems[id]
		var d: Variant = sys.call("serialize")
		if d is Dictionary:
			systems_data[id] = d
	return {
		"version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"scene_path": GameState.current_scene_path,
		"player": player_block,
		"systems": systems_data,
	}


func _capture_player_transform() -> Dictionary:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return {}
	var p3: Node3D = player
	return {
		"pos": [p3.global_position.x, p3.global_position.y, p3.global_position.z],
		"yaw": p3.rotation.y,
	}


func _write_atomic(target: String, data: Dictionary) -> bool:
	_rotate_backups(target)
	var tmp: FileAccess = FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if tmp == null:
		push_warning("SaveManager: could not open %s for write" % SAVE_TMP_PATH)
		return false
	tmp.store_string(JSON.stringify(data, "\t"))
	tmp.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_warning("SaveManager: DirAccess.open(user://) failed")
		return false
	var target_rel: String = target.trim_prefix("user://")
	if dir.file_exists(target_rel):
		dir.remove(target_rel)
	var err: int = dir.rename(SAVE_TMP_PATH.trim_prefix("user://"), target_rel)
	if err != OK:
		push_warning("SaveManager: rename %s -> %s failed (err %d)" % [SAVE_TMP_PATH, target, err])
		return false
	return true


func _rotate_backups(primary: String) -> void:
	# Oldest backup is discarded first to make room.
	if FileAccess.file_exists(BACKUP_PATHS[2]):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATHS[2]))
	if FileAccess.file_exists(BACKUP_PATHS[1]):
		_safe_rename(BACKUP_PATHS[1], BACKUP_PATHS[2])
	if FileAccess.file_exists(BACKUP_PATHS[0]):
		_safe_rename(BACKUP_PATHS[0], BACKUP_PATHS[1])
	if FileAccess.file_exists(primary):
		_safe_rename(primary, BACKUP_PATHS[0])


func _safe_rename(from_path: String, to_path: String) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	var to_rel: String = to_path.trim_prefix("user://")
	if dir.file_exists(to_rel):
		dir.remove(to_rel)
	dir.rename(from_path.trim_prefix("user://"), to_rel)


# Read the save file (or fall back through backup chain if primary is
# missing/corrupt), restore every registered system, stage the player
# spawn position, and trigger a scene transition. Title screen "Continue"
# calls this. Returns false if no readable save exists.
func load_and_resume() -> bool:
	var data: Dictionary = _load_snapshot()
	if data.is_empty():
		return false
	_loading = true
	var version: int = int(data.get("version", 1))
	# v1 saves: whole dict is the flat game_state payload; no `systems` key.
	var systems_block: Dictionary
	if data.has("systems") and data["systems"] is Dictionary:
		systems_block = data["systems"]
	else:
		systems_block = {"game_state": data}
	for id in _systems.keys():
		var sys: Object = _systems[id]
		var sys_data: Variant = systems_block.get(id, {})
		if sys_data is Dictionary:
			sys.call("deserialize", sys_data, version)
	_stage_player_spawn(data)
	GameState.skip_arrival_cinematic = true
	# room.tscn is a template — it reads GameState.next_room_id at _ready to
	# pick which ShipLayout row to build. On resume we already know the room
	# (deserialized into current_room_id), so prime the same cross-scene
	# baton door.gd uses. Without this the template scene loads with no row
	# and the player spawns in a void with no floor.
	GameState.next_room_id = GameState.current_room_id
	var scene: String = String(data.get("scene_path", data.get("scene", "res://scenes/gate_room.tscn")))
	_loading = false
	save_loaded.emit()
	SceneRouter.change_to(scene, "")
	return true


# Reads from primary, then walks backups in order if the primary is
# missing or malformed. Returns {} when nothing parseable was found.
func _load_snapshot() -> Dictionary:
	var candidates: Array[String] = [SAVE_PATH]
	for p in BACKUP_PATHS:
		candidates.append(p)
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var raw: String = f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
		push_warning("SaveManager: %s is malformed; falling through to backup chain" % path)
	return {}


func _stage_player_spawn(data: Dictionary) -> void:
	var player_block: Variant = data.get("player", null)
	var pos_raw: Variant = null
	var yaw_raw: Variant = 0.0
	if player_block is Dictionary:
		pos_raw = (player_block as Dictionary).get("pos", null)
		yaw_raw = (player_block as Dictionary).get("yaw", 0.0)
	else:
		# v1 fallback — pos / yaw at root.
		pos_raw = data.get("pos", null)
		yaw_raw = data.get("yaw", 0.0)
	if pos_raw is Array and (pos_raw as Array).size() == 3:
		var arr: Array = pos_raw
		GameState.pending_spawn_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	else:
		push_warning("SaveManager: 'pos' missing or malformed; defaulting to origin")
		GameState.pending_spawn_position = Vector3.ZERO
	GameState.pending_spawn_yaw = float(yaw_raw)


# Wipe primary + tmp + every backup. Called by F9 and by the Title menu's
# (future) "Delete Save" option. Emits save_wiped so listeners can refresh
# button states.
func wipe() -> void:
	var paths: Array[String] = [SAVE_PATH, SAVE_TMP_PATH]
	for p in BACKUP_PATHS:
		paths.append(p)
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	save_wiped.emit()


# Reset every registered system that exposes reset(), so "New Game" wipes
# in-memory state across the whole save graph in one call. Title.gd uses
# this instead of touching each autoload individually.
func start_new_game() -> void:
	for id in _systems.keys():
		var sys: Object = _systems[id]
		if sys.has_method("reset"):
			sys.call("reset")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F5:
		if _can_autosave():
			save()
			GameState.add_log("Quicksave written.")
		else:
			GameState.add_log("Save unavailable — nothing to record yet.")
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F9:
		wipe()
		GameState.add_log("Save wiped.")
		get_viewport().set_input_as_handled()
