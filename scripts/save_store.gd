extends RefCounted
class_name SaveStore

# Pure persistence layer for the slot-based save system. NO autoload refs:
# a Godot `-s tool.gd` run skips autoloads, so the CLI inspector/editor
# (tests/tools/save_*.gd) instantiate this directly with a configurable root.
# SaveManager owns orchestration (when to save, what to capture) and delegates
# every read/write here.
#
# Directory layout (one dir per slot under `saves_root`):
#   <saves_root>/<slot>/
#     save.json          primary snapshot
#     save.bak.1.json    rotating backups (1 = newest, 3 = oldest)
#     save.bak.2.json
#     save.bak.3.json
#     meta.json          lightweight sidecar — read on its own for menu listing
#     save.json.tmp      transient write-then-rename target
#
# Slot ids: "autosave", "quicksave", "manual_1".."manual_N".

const SAVE_VERSION: int = 2
const MANUAL_SLOT_COUNT: int = 3

# Required keys validated by --validate / `save.sh validate`.
const REQUIRED_SNAPSHOT_KEYS: Array[String] = ["version", "scene_path", "player", "systems"]
const REQUIRED_META_KEYS: Array[String] = ["version", "timestamp", "scene_path", "slot_id"]

const _PRIMARY_NAME: String = "save.json"
const _TMP_NAME: String = "save.json.tmp"
const _META_NAME: String = "meta.json"
const _BACKUP_NAMES: Array[String] = ["save.bak.1.json", "save.bak.2.json", "save.bak.3.json"]

# All I/O is rooted here. Trailing slash is normalised in the setter.
var saves_root: String = "user://saves/"


func _init(root: String = "user://saves/") -> void:
	set_saves_root(root)


func set_saves_root(root: String) -> void:
	if root == "":
		root = "user://saves/"
	if not root.ends_with("/"):
		root += "/"
	saves_root = root


# Every slot id the system recognises, in display order.
static func all_slot_ids() -> Array[String]:
	var ids: Array[String] = ["autosave", "quicksave"]
	for i in range(1, MANUAL_SLOT_COUNT + 1):
		ids.append("manual_%d" % i)
	return ids


# ---- path helpers -------------------------------------------------------

func slot_dir(slot_id: String) -> String:
	return saves_root + slot_id + "/"


func primary_path(slot_id: String) -> String:
	return slot_dir(slot_id) + _PRIMARY_NAME


func tmp_path(slot_id: String) -> String:
	return slot_dir(slot_id) + _TMP_NAME


func meta_path(slot_id: String) -> String:
	return slot_dir(slot_id) + _META_NAME


func backup_paths(slot_id: String) -> Array[String]:
	var dir: String = slot_dir(slot_id)
	var out: Array[String] = []
	for n in _BACKUP_NAMES:
		out.append(dir + n)
	return out


func _ensure_dir(slot_id: String) -> bool:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_warning("SaveStore: DirAccess.open(user://) failed")
		return false
	# make_dir_recursive accepts a user:// path and is idempotent.
	var err: int = dir.make_dir_recursive(slot_dir(slot_id))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("SaveStore: could not create %s (err %d)" % [slot_dir(slot_id), err])
		return false
	return true


# ---- queries ------------------------------------------------------------

func has_slot(slot_id: String) -> bool:
	if FileAccess.file_exists(primary_path(slot_id)):
		return true
	for p in backup_paths(slot_id):
		if FileAccess.file_exists(p):
			return true
	return false


# Returns the metadata dict for every slot that has a payload on disk.
# Reads ONLY meta.json (never the full save) so the load menu stays cheap.
# A slot with a payload but a missing/corrupt meta.json yields a minimal
# stub so the menu can still list (and load) it.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot_id in all_slot_ids():
		if not has_slot(slot_id):
			continue
		var meta: Dictionary = read_meta(slot_id)
		if meta.is_empty():
			meta = {"slot_id": slot_id, "timestamp": 0, "scene_path": "", "objective": "", "room_id": "", "playtime_seconds": 0.0, "version": SAVE_VERSION}
		else:
			meta["slot_id"] = slot_id
		out.append(meta)
	return out


# Slot id with the highest meta timestamp; "" if no slots exist.
func most_recent_slot() -> String:
	var best_id: String = ""
	var best_ts: int = -1
	for slot_id in all_slot_ids():
		if not has_slot(slot_id):
			continue
		var ts: int = int(read_meta(slot_id).get("timestamp", 0))
		if ts > best_ts:
			best_ts = ts
			best_id = slot_id
	return best_id


# ---- reads --------------------------------------------------------------

func read_meta(slot_id: String) -> Dictionary:
	return _read_json_dict(meta_path(slot_id))


# Reads the primary snapshot, falling back through the backup chain if the
# primary is missing or malformed. Returns {} when nothing parseable exists.
func read_snapshot(slot_id: String) -> Dictionary:
	var candidates: Array[String] = [primary_path(slot_id)]
	for p in backup_paths(slot_id):
		candidates.append(p)
	for path in candidates:
		var parsed: Dictionary = _read_json_dict(path)
		if not parsed.is_empty():
			return parsed
		if FileAccess.file_exists(path):
			push_warning("SaveStore: %s is malformed; falling through to backup chain" % path)
	return {}


func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


# ---- writes -------------------------------------------------------------

# Atomic snapshot + meta write. Rotates backups (.bak.1 -> .bak.2 -> .bak.3,
# oldest discarded) before clobbering the primary, then writes tmp + renames
# over the target so the primary either holds the new save or stays unchanged.
func write_snapshot(slot_id: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	if not _ensure_dir(slot_id):
		return false
	if not _write_atomic(slot_id, snapshot):
		return false
	# Meta is a sidecar; a failed meta write must not fail the save, but log it.
	if not _write_plain(meta_path(slot_id), meta):
		push_warning("SaveStore: meta write failed for slot %s" % slot_id)
	return true


# Rewrites the primary (and meta) in place WITHOUT rotating backups. Used by
# the save editor so a `set` doesn't burn a backup slot per field edit.
func rewrite_snapshot(slot_id: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	if not _ensure_dir(slot_id):
		return false
	if not _write_plain(primary_path(slot_id), snapshot):
		return false
	if not _write_plain(meta_path(slot_id), meta):
		push_warning("SaveStore: meta rewrite failed for slot %s" % slot_id)
	return true


func _write_atomic(slot_id: String, data: Dictionary) -> bool:
	_rotate_backups(slot_id)
	var tmp: String = tmp_path(slot_id)
	if not _write_plain(tmp, data):
		return false
	var dir: DirAccess = DirAccess.open(slot_dir(slot_id))
	if dir == null:
		push_warning("SaveStore: DirAccess.open(%s) failed" % slot_dir(slot_id))
		return false
	if dir.file_exists(_PRIMARY_NAME):
		dir.remove(_PRIMARY_NAME)
	var err: int = dir.rename(_TMP_NAME, _PRIMARY_NAME)
	if err != OK:
		push_warning("SaveStore: rename tmp -> primary failed for %s (err %d)" % [slot_id, err])
		return false
	return true


func _write_plain(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveStore: could not open %s for write" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func _rotate_backups(slot_id: String) -> void:
	var dir: DirAccess = DirAccess.open(slot_dir(slot_id))
	if dir == null:
		return
	# Oldest backup is discarded first to make room.
	if dir.file_exists(_BACKUP_NAMES[2]):
		dir.remove(_BACKUP_NAMES[2])
	if dir.file_exists(_BACKUP_NAMES[1]):
		_safe_rename(dir, _BACKUP_NAMES[1], _BACKUP_NAMES[2])
	if dir.file_exists(_BACKUP_NAMES[0]):
		_safe_rename(dir, _BACKUP_NAMES[0], _BACKUP_NAMES[1])
	if dir.file_exists(_PRIMARY_NAME):
		_safe_rename(dir, _PRIMARY_NAME, _BACKUP_NAMES[0])


func _safe_rename(dir: DirAccess, from_name: String, to_name: String) -> void:
	if dir.file_exists(to_name):
		dir.remove(to_name)
	dir.rename(from_name, to_name)


# ---- wipes --------------------------------------------------------------

# Removes every file in a single slot's directory (and the directory itself).
func wipe_slot(slot_id: String) -> void:
	var dir_path: String = slot_dir(slot_id)
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	var parent: DirAccess = DirAccess.open(saves_root)
	if parent != null and parent.dir_exists(slot_id):
		parent.remove(slot_id)


func wipe_all() -> void:
	for slot_id in all_slot_ids():
		wipe_slot(slot_id)


# ---- legacy migration ---------------------------------------------------

# Moves a pre-slots single save (user://save.json + 3 backups) into the
# autosave slot, deriving a meta sidecar from the snapshot. Idempotent:
# no-op once the autosave slot already exists. Returns true if it migrated.
func migrate_legacy() -> bool:
	if has_slot("autosave"):
		return false
	var legacy_primary: String = "user://save.json"
	var legacy_backups: Array[String] = [
		"user://save.bak.1.json", "user://save.bak.2.json", "user://save.bak.3.json",
	]
	var legacy_present: bool = FileAccess.file_exists(legacy_primary)
	for p in legacy_backups:
		if FileAccess.file_exists(p):
			legacy_present = true
	if not legacy_present:
		return false
	if not _ensure_dir("autosave"):
		return false
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return false
	var dest_dir: String = slot_dir("autosave")
	_move_into(dir, legacy_primary, dest_dir + _PRIMARY_NAME)
	for i in range(legacy_backups.size()):
		_move_into(dir, legacy_backups[i], dest_dir + _BACKUP_NAMES[i])
	# Build a meta sidecar from whatever snapshot survived.
	var snapshot: Dictionary = read_snapshot("autosave")
	var meta: Dictionary = build_meta_from_snapshot("autosave", snapshot)
	_write_plain(meta_path("autosave"), meta)
	return true


func _move_into(dir: DirAccess, from_path: String, to_abs: String) -> void:
	if not dir.file_exists(from_path.trim_prefix("user://")):
		return
	var to_rel: String = to_abs.trim_prefix("user://")
	if dir.file_exists(to_rel):
		dir.remove(to_rel)
	dir.rename(from_path.trim_prefix("user://"), to_rel)


# ---- meta builders ------------------------------------------------------

# Derives a meta sidecar from a snapshot dict alone (no autoload access), so
# the CLI tools and legacy migration can refresh meta without GameClock/etc.
func build_meta_from_snapshot(slot_id: String, snapshot: Dictionary) -> Dictionary:
	var gs: Dictionary = {}
	var systems: Variant = snapshot.get("systems", {})
	if systems is Dictionary and (systems as Dictionary).get("game_state", null) is Dictionary:
		gs = (systems as Dictionary)["game_state"]
	var clock: Dictionary = {}
	if systems is Dictionary and (systems as Dictionary).get("game_clock", null) is Dictionary:
		clock = (systems as Dictionary)["game_clock"]
	return {
		"version": int(snapshot.get("version", SAVE_VERSION)),
		"timestamp": int(snapshot.get("timestamp", 0)),
		"playtime_seconds": float(clock.get("elapsed_seconds", 0.0)),
		"scene_path": String(snapshot.get("scene_path", "")),
		"room_id": String(gs.get("current_room_id", "")),
		"objective": String(gs.get("objective", gs.get("current_objective", ""))),
		"slot_id": slot_id,
	}
