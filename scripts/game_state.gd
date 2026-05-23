extends Node

# Global persistent game state. Cross-scene singleton.
# Survives scene_router transitions; reset() returns to clean E1 start.

signal health_changed(value: float)
signal oxygen_changed(value: float)
signal objective_changed(text: String)
signal room_discovered(room_id: String)
signal kino_changed(acquired: bool)
signal episode_completed()
signal log_added(line: String)
signal save_written()
signal save_wiped()

const MAX_HEALTH: float = 100.0
const MAX_OXYGEN: float = 100.0
const SAVE_PATH: String = "user://save.json"

# Set by scene scripts (currently only gate_room.gd) when the player is
# in a scene that should be considered "in-world" for save purposes. Title
# screen / cutscenes leave this empty so F5 doesn't write garbage.
var current_scene_path: String = ""
# Player spawn override: when a scene loads after a "Continue from save",
# the room script reads this to know where to put the player, then clears it.
var pending_spawn_position: Variant = null   # Vector3 or null
var pending_spawn_yaw: float = 0.0
# Cross-scene baton: door.gd sets this before SceneRouter.change_to(room.tscn);
# room.gd::_ready() reads it to pick the right ShipLayout row, then clears it.
var next_room_id: String = ""
# True for the next room load only — tells the gate-room arrival cinematic
# to skip itself because we're resuming, not arriving.
var skip_arrival_cinematic: bool = false

var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var kino_acquired: bool = false
var quarters_found: bool = false
var rooms_discovered: Array[String] = []
var breaches_sealed: Array[String] = []
var current_objective: String = "Explore the Destiny"
var episode_complete: bool = false
var log_entries: Array[String] = []

func reset() -> void:
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	kino_acquired = false
	quarters_found = false
	rooms_discovered.clear()
	breaches_sealed.clear()
	current_objective = "Explore the Destiny"
	episode_complete = false
	log_entries.clear()
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(kino_acquired)

func damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	health_changed.emit(health)

func heal_full() -> void:
	health = MAX_HEALTH
	health_changed.emit(health)

func consume_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen - amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)
	# Below 25% oxygen, health starts ticking down too.
	if oxygen < 25.0:
		damage(amount * 0.5)

func restore_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen + amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)

func discover_room(room_id: String, display_name: String = "") -> void:
	if rooms_discovered.has(room_id):
		return
	rooms_discovered.append(room_id)
	room_discovered.emit(room_id)
	if display_name != "":
		add_log("Discovered: " + display_name)

func acquire_kino() -> void:
	if kino_acquired:
		return
	kino_acquired = true
	kino_changed.emit(true)
	add_log("Acquired the Kino Remote.")
	_recompute_objective()

func mark_quarters_found() -> void:
	if quarters_found:
		return
	quarters_found = true
	add_log("Found Eli's quarters.")
	_recompute_objective()

func seal_breach(breach_id: String) -> void:
	if breaches_sealed.has(breach_id):
		return
	breaches_sealed.append(breach_id)
	restore_oxygen(MAX_OXYGEN)
	add_log("Hull breach sealed: " + breach_id)
	_recompute_objective()

# Joins the still-outstanding E1 tasks into a single objective line so the
# HUD/Pip-Boy always tells the player what's left. Called by each mission
# mutator after the flag flips.
func _recompute_objective() -> void:
	if episode_complete:
		return
	var todo: Array[String] = []
	if not kino_acquired:
		todo.append("find the Kino Remote")
	if breaches_sealed.is_empty():
		todo.append("seal the hull breach")
	if not quarters_found:
		todo.append("find your quarters")
	if todo.is_empty():
		check_episode_complete()
		return
	var first: String = todo[0]
	# Capitalize first letter for the objective line.
	first = first.substr(0, 1).to_upper() + first.substr(1)
	if todo.size() == 1:
		set_objective(first + ".")
	else:
		set_objective(first + " (" + str(todo.size()) + " tasks remain)")

func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)

func add_log(line: String) -> void:
	log_entries.append(line)
	log_added.emit(line)

# Episode 1 completion: Kino acquired, quarters found, at least one breach sealed.
func check_episode_complete() -> void:
	if episode_complete:
		return
	if kino_acquired and quarters_found and breaches_sealed.size() > 0:
		episode_complete = true
		set_objective("Episode 1: Air — Complete")
		episode_completed.emit()

# --- save / wipe -------------------------------------------------------------
#
# F5 quick-save and F9 wipe are intentionally bare-bones: the savefile captures
# enough state that the player resumes inside whichever room they left, with
# their progression flags intact. Inventory and world objects below the scene
# layer are NOT serialized — Phase A's loop is too small to need it.

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		_quicksave()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F9:
		wipe_save()
		get_viewport().set_input_as_handled()

func _quicksave() -> void:
	# Only save when a real gameplay scene has registered itself. Title menu
	# and headless tests leave current_scene_path empty.
	if current_scene_path == "":
		add_log("Save unavailable — nothing to record yet.")
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		add_log("Save unavailable — no player in scene.")
		return
	var p3: Node3D = player
	save_game(current_scene_path, p3.global_position, p3.rotation.y)

func save_game(scene_path: String, pos: Vector3, yaw: float) -> void:
	var data: Dictionary = {
		"version": 1,
		"scene": scene_path,
		"pos": [pos.x, pos.y, pos.z],
		"yaw": yaw,
		"health": health,
		"oxygen": oxygen,
		"kino_acquired": kino_acquired,
		"quarters_found": quarters_found,
		"rooms_discovered": rooms_discovered,
		"breaches_sealed": breaches_sealed,
		"objective": current_objective,
		"episode_complete": episode_complete,
		"log_entries": log_entries,
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		add_log("Save failed (couldn't open %s)." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	add_log("Quicksave written.")
	save_written.emit()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# Load the save file and switch to the saved scene at the saved position.
# Called by the title screen "Continue" path. Returns false if no save.
func load_and_resume() -> bool:
	if not has_save():
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("save.json is malformed")
		return false
	var data: Dictionary = parsed
	# Hydrate persistent state.
	health = float(data.get("health", MAX_HEALTH))
	oxygen = float(data.get("oxygen", MAX_OXYGEN))
	kino_acquired = bool(data.get("kino_acquired", false))
	quarters_found = bool(data.get("quarters_found", false))
	episode_complete = bool(data.get("episode_complete", false))
	current_objective = String(data.get("objective", current_objective))
	rooms_discovered.clear()
	for r in data.get("rooms_discovered", []):
		rooms_discovered.append(String(r))
	breaches_sealed.clear()
	for b in data.get("breaches_sealed", []):
		breaches_sealed.append(String(b))
	log_entries.clear()
	for l in data.get("log_entries", []):
		log_entries.append(String(l))
	# Fire signals so the HUD picks the loaded values up.
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(kino_acquired)
	# Stage the spawn override for the next scene load.
	var pos_arr: Array = data.get("pos", [0.0, 0.0, 0.0])
	pending_spawn_position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	pending_spawn_yaw = float(data.get("yaw", 0.0))
	skip_arrival_cinematic = true
	var scene: String = String(data.get("scene", "res://scenes/gate_room.tscn"))
	SceneRouter.change_to(scene, "")
	return true

func wipe_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		add_log("Save wiped.")
		save_wiped.emit()
	else:
		add_log("Nothing to wipe.")
