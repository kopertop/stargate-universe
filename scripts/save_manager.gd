extends Node

# Owns auto-save / quicksave / resume orchestration over a slot-based store.
#
# Slots: "autosave" + "quicksave" + N manual slots ("manual_1".."manual_N").
# Each slot is its own directory with a primary snapshot, 3 rotating backups,
# and a lightweight meta.json sidecar (read on its own for menu listing).
# All file/path I/O lives in SaveStore (RefCounted, no autoload deps) so the
# headless CLI tools can reuse the exact same persistence without autoloads.
#
# Autosave triggers: GameState.objective_changed and GameState.current_room_changed
# fire on every quest advance and every room transition; each writes the
# "autosave" slot. F5 -> "quicksave"; F9 -> wipe_all.
#
# Subsystems plug in via register_system(id, system) where `system`
# implements `serialize() -> Dictionary` and `deserialize(data, version)
# -> void`. Registration order = autoload order: GameClock then GameState
# then NPCState, so deserialize is applied in that order on resume.

signal save_written()
signal save_loaded()
signal save_wiped()

const SAVE_VERSION: int = 2

# Saves root selection: real (windowed) play writes the live player slots;
# headless sessions, an explicit --save-root=<path> user-arg, or the
# SGU_SAVE_ROOT env var redirect to a sandbox so no screenshot/test/tool run
# can touch the player's slots — isolation is the DEFAULT, not opt-in. This
# is the fix for the "every capture clobbers my save" loss.
const PLAYER_SAVES_ROOT: String = "user://saves/"
const SANDBOX_SAVES_ROOT: String = "user://saves_sandbox/"

var _store: SaveStore = SaveStore.new(PLAYER_SAVES_ROOT)

var _systems: Dictionary = {}
var _autosave_hooks_ready: bool = false
# Set during deserialize so the signals fired by GameState/etc.'s hydration
# pass don't recursively trigger autosaves while we're mid-load.
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_saves_root(_resolve_saves_root())
	# Pull a pre-slots single save into the autosave slot once. Idempotent.
	_store.migrate_legacy()
	# Defer signal hookup so we don't depend on GameState being ready in
	# this _ready() — every autoload's _ready runs in registration order;
	# call_deferred guarantees ours runs after the whole batch settles.
	call_deferred("_install_autosave_hooks")


# Picks the saves root: sandbox for headless / explicit override, else the
# live player root. Override precedence: --save-root=<path> > SGU_SAVE_ROOT >
# headless detection > player root.
func _resolve_saves_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-root="):
			return arg.substr("--save-root=".length())
	var env_root: String = OS.get_environment("SGU_SAVE_ROOT")
	if env_root != "":
		return env_root
	if DisplayServer.get_name() == "headless":
		return SANDBOX_SAVES_ROOT
	return PLAYER_SAVES_ROOT


# Point all save I/O at a named root. Tests use this for a throwaway temp
# root; the playthrough/probe runners use the configure_test_paths alias.
func set_saves_root(root: String) -> void:
	_store.set_saves_root(root)


# Back-compat alias for the pre-slots API still called by the integration
# runners (playthrough_runner.gd / probe_runner.gd). Maps the old single-stem
# argument onto a sandbox root keyed by the stem so each runner stays isolated.
func configure_test_paths(stem: String = "test_save") -> void:
	set_saves_root("user://__savetest_%s/" % stem)


func register_system(id: String, system: Object) -> void:
	if id == "":
		push_error("SaveManager: refusing to register system with empty id")
		return
	if not (system.has_method("serialize") and system.has_method("deserialize")):
		push_error("SaveManager: system '%s' missing serialize/deserialize" % id)
		return
	_systems[id] = system


func _install_autosave_hooks() -> void:
	if _autosave_hooks_ready:
		return
	_autosave_hooks_ready = true
	# Autosave on every objective update and every room transition.
	# objective_changed is deliberately BROAD — it's a superset of
	# quest_step_changed that also fires on sub-step beats (collecting Kino
	# orbs, finding fuses) and planet-side objective updates. Writes are tiny
	# + atomic, so over-saving is cheap; losing progress is not.
	GameState.objective_changed.connect(_on_quest_changed)
	GameState.current_room_changed.connect(_on_room_changed)


# True if ANY slot has a save (slot_id == ""), or if the named slot does.
func has_save(slot_id := "") -> bool:
	if slot_id == "":
		return not _store.list_slots().is_empty()
	return _store.has_slot(slot_id)


# Slot ids that currently have a save, plus their meta — for the load/save UI.
func list_slots() -> Array[Dictionary]:
	return _store.list_slots()


func _on_quest_changed(_step: String) -> void:
	if _loading:
		return
	if _can_autosave():
		save("autosave")


func _on_room_changed(_room_id: String) -> void:
	if _loading:
		return
	if _can_autosave():
		save("autosave")


func _can_autosave() -> bool:
	if GameState.current_scene_path == "":
		return false
	# A save with no room id void-falls on resume (room.tscn is a template
	# that needs a room to build). Never persist one — this guards every
	# autosave path, not just the reset/Restart case that first exposed it.
	if GameState.current_room_id == "":
		return false
	if SceneRouter.is_transitioning:
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return false
	return true


# Capture live state into a snapshot + meta and write the given slot.
func save(slot_id := "autosave") -> void:
	if GameState.current_scene_path == "":
		return
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return
	var meta: Dictionary = _build_meta(slot_id, data)
	if not _store.write_snapshot(slot_id, data, meta):
		return
	save_written.emit()


# F5 entrypoint — writes the dedicated quicksave slot.
func quicksave() -> void:
	save("quicksave")


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


# Build the meta sidecar from live state. SaveStore can't reach autoloads, so
# we hand it the playtime/objective/room it needs.
func _build_meta(slot_id: String, snapshot: Dictionary) -> Dictionary:
	return {
		"version": int(snapshot.get("version", SAVE_VERSION)),
		"timestamp": int(snapshot.get("timestamp", Time.get_unix_time_from_system())),
		"playtime_seconds": GameClock.elapsed_seconds,
		"scene_path": GameState.current_scene_path,
		"room_id": GameState.current_room_id,
		"objective": GameState.current_objective,
		"slot_id": slot_id,
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


# Read a slot (or the most recent if slot_id == ""), restore every registered
# system, stage the player spawn, and trigger a scene transition. Title
# "Continue" calls this with "". Returns false if no readable save exists.
func load_and_resume(slot_id := "") -> bool:
	if slot_id == "":
		slot_id = _store.most_recent_slot()
	if slot_id == "":
		return false
	var data: Dictionary = _store.read_snapshot(slot_id)
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
	var scene: String = String(data.get("scene_path", data.get("scene", "res://scenes/gate_room.tscn")))
	# room.tscn is a template — it reads GameState.next_room_id at _ready to
	# pick which ShipLayout row to build. On resume we already know the room
	# (deserialized into current_room_id), so prime the same cross-scene
	# baton door.gd uses. Without this the template scene loads with no row
	# and the player spawns in a void with no floor.
	GameState.next_room_id = GameState.current_room_id
	# Salvage older/edited saves that recorded room.tscn with no room id
	# (e.g. a roomless autosave written before the _can_autosave guard
	# existed): drop the player in the gate room rather than the void.
	if GameState.next_room_id == "" and scene == "res://scenes/room.tscn":
		push_warning("SaveManager: save has empty room id for room.tscn; resuming in gate room")
		scene = "res://scenes/gate_room.tscn"
		GameState.pending_spawn_position = null  # let gate_room use its default spawn
	_loading = false
	save_loaded.emit()
	SceneRouter.change_to(scene, "")
	return true


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


# Wipe a single slot. With slot_id == "" wipes every slot (the F9 / "start
# over" behaviour). Emits save_wiped so listeners can refresh button states.
func wipe(slot_id := "") -> void:
	if slot_id == "":
		_store.wipe_all()
	else:
		_store.wipe_slot(slot_id)
	save_wiped.emit()


func wipe_all() -> void:
	_store.wipe_all()
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
			quicksave()
			GameState.add_log("Quicksave written.")
		else:
			GameState.add_log("Save unavailable — nothing to record yet.")
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F9:
		wipe_all()
		GameState.add_log("Save wiped.")
		get_viewport().set_input_as_handled()
