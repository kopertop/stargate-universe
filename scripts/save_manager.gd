extends Node

# Owns auto-save / manual / episode / resume orchestration over the PROFILE +
# CHECKPOINT store (SaveStore, issue #77). A profile is one named playthrough;
# it owns a checkpoints/ timeline:
#
#   autosave_<ts>   rolling ring — newest SaveStore.AUTOSAVE_RING_KEEP kept
#   quicksave       single rolling slot (F5)
#   manual_<ts>     permanent, written by the in-game "Save" action
#   episode_<id>    permanent, auto-created once at each episode boundary
#
# Triggers:
#   - GameState.objective_changed / current_room_changed -> a NEW autosave
#     checkpoint in the active profile, then prune the ring to 3.
#   - GameState.episode_completed -> a permanent episode checkpoint, idempotent.
#   - save_manual(label) -> a permanent manual checkpoint.
#   - F5 -> quicksave; F9 -> wipe the active profile's checkpoints.
#
# Resume:
#   - load_and_resume(profile_id, checkpoint_id) restores a specific point.
#   - Continue calls load_and_resume("") which resumes the active profile's
#     most-recent checkpoint.
#
# Back-compat: the pre-#79 slot-based API (save("autosave"|"manual_1"|...),
# quicksave(), list_slots(), load_and_resume("manual_2"), has_save()) is
# retained and transparently mapped onto the active profile's checkpoints, so
# title.gd / pause_menu.gd keep working unchanged. A single string arg to
# load_and_resume is resolved as a checkpoint id in the active profile, falling
# back to a flat slot for legacy on-disk layouts (slot_resume probe).
#
# All file/path I/O lives in SaveStore (RefCounted, no autoload deps) so the
# headless CLI tools can reuse the exact same persistence without autoloads.
#
# Subsystems plug in via register_system(id, system) where `system`
# implements `serialize() -> Dictionary` and `deserialize(data, version)
# -> void`. Registration order = autoload order: GameClock then GameState
# then NPCState, so deserialize is applied in that order on resume.

signal save_written()
signal save_loaded()
signal save_wiped()
signal profile_changed(profile_id: String)

const SAVE_VERSION: int = 2

# Saves root selection: real (windowed) play writes the live player slots;
# headless sessions, an explicit --save-root=<path> user-arg, or the
# SGU_SAVE_ROOT env var redirect to a sandbox so no screenshot/test/tool run
# can touch the player's slots — isolation is the DEFAULT, not opt-in. This
# is the fix for the "every capture clobbers my save" loss.
const PLAYER_SAVES_ROOT: String = "user://saves/"
const SANDBOX_SAVES_ROOT: String = "user://saves_sandbox/"

# Top-level sidecar (under saves_root) tracking which profile is active. Kept
# alongside the profiles/ dir so each isolated root has its own pointer.
const ACTIVE_PROFILE_FILE: String = "active.json"

# Legacy flat slot ids still accepted by save()/load_and_resume for back-compat.
const _LEGACY_QUICKSAVE: String = "quicksave"
const _LEGACY_AUTOSAVE: String = "autosave"

var _store: SaveStore = SaveStore.new(PLAYER_SAVES_ROOT)

var _systems: Dictionary = {}
var _autosave_hooks_ready: bool = false
# Set during deserialize so the signals fired by GameState/etc.'s hydration
# pass don't recursively trigger autosaves while we're mid-load.
var _loading: bool = false
# Active profile id (in-memory); persisted in saves_root/active.json. "" until
# resolved/created. Lazily ensured by _ensure_active_profile().
var _active_profile_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_saves_root(_resolve_saves_root())
	# Pull a pre-slots single save into the autosave slot once. Idempotent.
	_store.migrate_legacy()
	# Fold any existing FLAT slot layout into a Default profile, once.
	_store.migrate_flat_to_profile()
	# Resolve the active profile pointer from disk (may be empty for a fresh
	# install — created lazily on first New Game / first autosave).
	_active_profile_id = _read_active_profile()
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
# Re-resolves the active profile pointer for the new root.
func set_saves_root(root: String) -> void:
	_store.set_saves_root(root)
	_active_profile_id = _read_active_profile()


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
	# Episode boundary -> one permanent checkpoint per episode.
	if GameState.has_signal("episode_completed"):
		GameState.episode_completed.connect(_on_episode_completed)


# =========================================================================
# ACTIVE PROFILE
# =========================================================================

func active_profile_id() -> String:
	return _active_profile_id


# Returns the active profile id, creating a Default profile if none is set.
# Called lazily on the first write so a fresh install autosaves into a real
# profile without forcing New Game through any extra ceremony.
func _ensure_active_profile() -> String:
	if _active_profile_id != "" and _store.has_profile(_active_profile_id):
		return _active_profile_id
	# Prefer an existing Default; otherwise mint one.
	if _store.has_profile(SaveStore.DEFAULT_PROFILE_ID):
		_set_active_profile(SaveStore.DEFAULT_PROFILE_ID)
		return _active_profile_id
	var pid: String = _store.create_profile(SaveStore.DEFAULT_PROFILE_NAME, SaveStore.DEFAULT_PROFILE_ID)
	if pid == "":
		return ""
	_set_active_profile(pid)
	return pid


# Creates a new profile and makes it active. New Game calls this.
func create_profile(display_name: String) -> String:
	var pid: String = _store.create_profile(display_name)
	if pid == "":
		return ""
	_set_active_profile(pid)
	return pid


func set_active_profile(profile_id: String) -> bool:
	if not _store.has_profile(profile_id):
		return false
	_set_active_profile(profile_id)
	return true


# Permanently delete a profile and its entire checkpoint set (permanent
# manual / episode checkpoints included — the player-facing copy must warn).
# If the deleted profile was active, clears the active pointer so the next
# write mints a fresh Default rather than resurrecting a dead profile dir.
# Returns true if the profile existed and was removed.
func delete_profile(profile_id: String) -> bool:
	if profile_id == "" or not _store.has_profile(profile_id):
		return false
	_store.delete_profile(profile_id)
	if _active_profile_id == profile_id:
		_active_profile_id = ""
		_write_active_profile("")
		profile_changed.emit("")
	save_wiped.emit()
	return true


func _set_active_profile(profile_id: String) -> void:
	_active_profile_id = profile_id
	_write_active_profile(profile_id)
	profile_changed.emit(profile_id)


func list_profiles() -> Array[Dictionary]:
	return _store.list_profiles()


func _active_profile_path() -> String:
	return _store.saves_root + ACTIVE_PROFILE_FILE


func _read_active_profile() -> String:
	var path: String = _active_profile_path()
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return String((parsed as Dictionary).get("active_profile", ""))
	return ""


func _write_active_profile(profile_id: String) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive(_store.saves_root)
	var f: FileAccess = FileAccess.open(_active_profile_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"active_profile": profile_id}, "\t"))
	f.close()


# Stamps the active checkpoint pointer + last_played on the active profile.
func _touch_active_checkpoint(checkpoint_id: String) -> void:
	if _active_profile_id == "":
		return
	var prof: Dictionary = _store.read_profile(_active_profile_id)
	if prof.is_empty():
		return
	prof["active_checkpoint"] = checkpoint_id
	prof["last_played"] = int(Time.get_unix_time_from_system())
	_store.write_profile(_active_profile_id, prof)


# =========================================================================
# QUERIES (back-compat surface for title.gd / pause_menu.gd)
# =========================================================================

# True if ANY checkpoint exists in the active profile (slot_id == ""), or if a
# named checkpoint/slot does. Powers the title Continue button's enabled state.
func has_save(slot_id := "") -> bool:
	if slot_id == "":
		if _active_profile_id != "":
			if not _store.list_checkpoints(_active_profile_id).is_empty():
				return true
		# Any profile with a checkpoint counts as "has a save".
		for prof in _store.list_profiles():
			if not _store.list_checkpoints(String(prof.get("id", ""))).is_empty():
				return true
		# Legacy flat slots (un-migrated on-disk layouts).
		return not _store.list_slots().is_empty()
	if _active_profile_id != "" and _store.has_checkpoint(_active_profile_id, slot_id):
		return true
	return _store.has_slot(slot_id)


# Checkpoints in the active profile, each with its meta — for the load/save UI.
# Falls back to legacy flat slots when no profile is active. Each entry carries
# `slot_id` (its checkpoint/slot id) for back-compat with the existing UI.
func list_slots() -> Array[Dictionary]:
	if _active_profile_id != "":
		var out: Array[Dictionary] = []
		for cp in _store.list_checkpoints(_active_profile_id):
			var entry: Dictionary = cp.duplicate(true)
			entry["slot_id"] = String(cp.get("checkpoint_id", ""))
			out.append(entry)
		if not out.is_empty():
			return out
	return _store.list_slots()


# Checkpoint metas for an explicit profile (load UI / profile picker).
func list_checkpoints(profile_id: String) -> Array[Dictionary]:
	return _store.list_checkpoints(profile_id)


# =========================================================================
# AUTOSAVE / MANUAL / EPISODE TRIGGERS
# =========================================================================

func _on_quest_changed(_step: String) -> void:
	if _loading:
		return
	if _can_autosave():
		_write_autosave()


func _on_room_changed(_room_id: String) -> void:
	if _loading:
		return
	if _can_autosave():
		_write_autosave()


func _on_episode_completed() -> void:
	if _loading:
		return
	# An episode checkpoint is gameplay-critical: write it even mid-transition
	# as long as we can capture a player + scene. Idempotent per episode id.
	var episode: String = GameState.current_episode if "current_episode" in GameState else "1"
	save_episode(episode)


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


# Writes a NEW autosave checkpoint into the active profile, then prunes the
# ring to AUTOSAVE_RING_KEEP (prune happens inside SaveStore.write_checkpoint).
func _write_autosave() -> void:
	var pid: String = _ensure_active_profile()
	if pid == "":
		return
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return
	var cid: String = SaveStore.new_autosave_id()
	# Two autosaves within the same second would collide on the unix-stamped id
	# and the second would rotate-overwrite the first. Disambiguate so the ring
	# truly holds distinct entries.
	if _store.has_checkpoint(pid, cid):
		cid = "%s_%d" % [cid, _store.list_checkpoints(pid).size()]
	var meta: Dictionary = _build_meta(cid, data)
	meta["kind"] = SaveStore.KIND_AUTOSAVE
	meta["label"] = "Autosave"
	if not _store.write_checkpoint(pid, cid, data, meta):
		return
	_touch_active_checkpoint(cid)
	save_written.emit()


# In-game "Save" action — writes a PERMANENT manual checkpoint in the active
# profile. Returns the checkpoint id, or "" on failure.
func save_manual(label := "") -> String:
	var pid: String = _ensure_active_profile()
	if pid == "":
		return ""
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return ""
	var cid: String = SaveStore.new_manual_id()
	if _store.has_checkpoint(pid, cid):
		cid = "%s_%d" % [cid, _store.list_checkpoints(pid).size()]
	var meta: Dictionary = _build_meta(cid, data)
	meta["kind"] = SaveStore.KIND_MANUAL
	meta["label"] = label if label != "" else "Manual save"
	if not _store.write_checkpoint(pid, cid, data, meta):
		return ""
	_touch_active_checkpoint(cid)
	save_written.emit()
	return cid


# Episode boundary — writes a PERMANENT episode_<id> checkpoint. Idempotent:
# a second call for the same episode is a no-op (the checkpoint already exists).
func save_episode(episode: String, label := "") -> String:
	var pid: String = _ensure_active_profile()
	if pid == "":
		return ""
	var cid: String = SaveStore.episode_id(episode)
	if _store.has_checkpoint(pid, cid):
		return cid  # already recorded — idempotent
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return ""
	var meta: Dictionary = _build_meta(cid, data)
	meta["kind"] = SaveStore.KIND_EPISODE
	meta["episode"] = episode
	meta["label"] = label if label != "" else "Episode %s — Complete" % episode
	if not _store.write_checkpoint(pid, cid, data, meta):
		return ""
	_touch_active_checkpoint(cid)
	save_written.emit()
	return cid


# Quicksave (F5) — single rolling quicksave checkpoint in the active profile.
func quicksave() -> void:
	var pid: String = _ensure_active_profile()
	if pid == "":
		return
	var data: Dictionary = _build_snapshot()
	if data.is_empty():
		return
	var meta: Dictionary = _build_meta(SaveStore.KIND_QUICKSAVE, data)
	meta["kind"] = SaveStore.KIND_QUICKSAVE
	meta["label"] = "Quicksave"
	if not _store.write_checkpoint(pid, SaveStore.KIND_QUICKSAVE, data, meta):
		return
	_touch_active_checkpoint(SaveStore.KIND_QUICKSAVE)
	save_written.emit()


# Back-compat slot entrypoint still called by pause_menu.gd / playthrough
# runners. Maps a legacy slot id onto the right checkpoint write in the active
# profile: "autosave"->autosave ring, "quicksave"->quicksave, "manual_N"->
# permanent manual. An empty/unknown id is treated as an autosave.
func save(slot_id := _LEGACY_AUTOSAVE) -> void:
	if GameState.current_scene_path == "":
		return
	if slot_id == _LEGACY_QUICKSAVE:
		quicksave()
	elif slot_id.begins_with("manual"):
		save_manual()
	else:
		_write_autosave()


# =========================================================================
# RESUME
# =========================================================================

# Resume a specific (profile, checkpoint): read it, restore every registered
# system, stage the player spawn, and trigger a scene transition. Returns
# false if no readable checkpoint exists.
func load_and_resume_checkpoint(profile_id: String, checkpoint_id: String) -> bool:
	if profile_id == "":
		profile_id = _active_profile_id
	if profile_id == "":
		return false
	if checkpoint_id == "":
		checkpoint_id = _store.most_recent_checkpoint(profile_id)
	if checkpoint_id == "":
		return false
	var data: Dictionary = _store.read_checkpoint(profile_id, checkpoint_id)
	if data.is_empty():
		return false
	_set_active_profile(profile_id)
	_touch_active_checkpoint(checkpoint_id)
	return _resume_from_snapshot(data)


# Back-compat single-arg resume. "" = the active profile's most-recent
# checkpoint (the Continue path). A non-empty arg is resolved as a checkpoint
# id in the active profile, then as a flat slot for legacy on-disk layouts
# (the slot_resume probe writes flat slots directly into the store).
func load_and_resume(slot_id := "") -> bool:
	# Continue: most-recent checkpoint of the active (or any) profile.
	if slot_id == "":
		var pid: String = _active_profile_id
		if pid == "" or _store.most_recent_checkpoint(pid) == "":
			pid = _newest_profile_with_checkpoint()
		if pid != "":
			var cid: String = _store.most_recent_checkpoint(pid)
			if cid != "":
				return load_and_resume_checkpoint(pid, cid)
		# Legacy flat fallback.
		return _resume_flat_slot("")
	# Named: prefer a checkpoint in the active profile, else a flat slot.
	if _active_profile_id != "" and _store.has_checkpoint(_active_profile_id, slot_id):
		return load_and_resume_checkpoint(_active_profile_id, slot_id)
	return _resume_flat_slot(slot_id)


# Most-recent checkpoint id in the active profile — powers Continue.
func most_recent(profile_id := "") -> String:
	if profile_id == "":
		profile_id = _active_profile_id
	if profile_id == "":
		return ""
	return _store.most_recent_checkpoint(profile_id)


func _newest_profile_with_checkpoint() -> String:
	var best_pid: String = ""
	var best_ts: int = -1
	for prof in _store.list_profiles():
		var pid: String = String(prof.get("id", ""))
		var cps: Array[Dictionary] = _store.list_checkpoints(pid)
		if cps.is_empty():
			continue
		var ts: int = int(cps[0].get("timestamp", 0))  # list is newest-first
		if ts > best_ts:
			best_ts = ts
			best_pid = pid
	return best_pid


# Legacy flat-slot resume (un-migrated on-disk layouts / the slot_resume probe).
func _resume_flat_slot(slot_id: String) -> bool:
	if slot_id == "":
		slot_id = _store.most_recent_slot()
	if slot_id == "":
		return false
	var data: Dictionary = _store.read_snapshot(slot_id)
	if data.is_empty():
		return false
	return _resume_from_snapshot(data)


# Shared hydrate + stage + transition path for both checkpoint and flat resume.
func _resume_from_snapshot(data: Dictionary) -> bool:
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


# =========================================================================
# SNAPSHOT / META BUILDERS
# =========================================================================

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
func _build_meta(checkpoint_id: String, snapshot: Dictionary) -> Dictionary:
	return {
		"version": int(snapshot.get("version", SAVE_VERSION)),
		"timestamp": int(snapshot.get("timestamp", Time.get_unix_time_from_system())),
		"playtime_seconds": GameClock.elapsed_seconds,
		"scene_path": GameState.current_scene_path,
		"room_id": GameState.current_room_id,
		"objective": GameState.current_objective,
		"episode": GameState.current_episode if "current_episode" in GameState else "",
		"slot_id": checkpoint_id,
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


# =========================================================================
# WIPE / NEW GAME
# =========================================================================

# Wipe a single checkpoint/slot. With slot_id == "" wipes the active profile's
# rolling checkpoints (the F9 / "start over" behaviour); permanent manual /
# episode checkpoints survive. Emits save_wiped so listeners refresh.
func wipe(slot_id := "") -> void:
	if slot_id == "":
		if _active_profile_id != "":
			for cp in _store.list_checkpoints(_active_profile_id):
				_store.delete_checkpoint(_active_profile_id, String(cp.get("checkpoint_id", "")))
		else:
			_store.wipe_all()
	else:
		if _active_profile_id != "" and _store.has_checkpoint(_active_profile_id, slot_id):
			_store.delete_checkpoint(_active_profile_id, slot_id)
		else:
			_store.wipe_slot(slot_id)
	save_wiped.emit()


# Full wipe of the active profile (every checkpoint, permanent included) plus
# the legacy flat slots. Used by hard "delete profile" flows.
func wipe_all() -> void:
	if _active_profile_id != "":
		_store.delete_profile(_active_profile_id)
		_active_profile_id = ""
		_write_active_profile("")
	_store.wipe_all()
	save_wiped.emit()


# Reset every registered system that exposes reset(), so "New Game" wipes
# in-memory state across the whole save graph in one call, and mint a fresh
# active profile so the first autosave lands in a clean timeline. Title.gd uses
# this instead of touching each autoload individually.
func start_new_game(profile_name := "") -> void:
	for id in _systems.keys():
		var sys: Object = _systems[id]
		if sys.has_method("reset"):
			sys.call("reset")
	# GameState.reset seeds the access tablet AFTER wiping Inventory — but Inventory
	# is its own registered system, so a later Inventory.reset() in this loop
	# would clobber that seed. Re-seed opening tools + soft-locks AFTER every
	# system has wiped (weapons-tools New Game empty-hotbar bug).
	# Use the SceneTree root (not get_node("/root/...")) so -s smoke tests work.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree != null and tree.root != null else null
	if gs != null:
		if gs.has_method("seed_default_resources"):
			gs.call("seed_default_resources")
		if gs.has_method("seed_starter_tools"):
			gs.call("seed_starter_tools")
		if gs.has_method("seed_opening_soft_locks"):
			gs.call("seed_opening_soft_locks")
	# A fresh playthrough gets a fresh profile so its autosave ring + permanent
	# checkpoints never mingle with a prior run's. New Game passes the
	# player-chosen display name; an empty name falls back to "Default".
	if profile_name == "":
		profile_name = SaveStore.DEFAULT_PROFILE_NAME
	create_profile(profile_name)


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
		wipe()
		GameState.add_log("Save wiped.")
		get_viewport().set_input_as_handled()
