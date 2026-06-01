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

# ---- profile / checkpoint model -----------------------------------------
#
# The forward-looking layout (see issue #77) groups saves under named
# profiles, each owning a timeline of checkpoints:
#
#   <saves_root>/profiles/<profile_id>/
#     profile.json                  id, display_name, created, last_played, active_checkpoint
#     checkpoints/
#       autosave_<unix_ts>/         rolling ring — newest AUTOSAVE_RING_KEEP kept
#       quicksave/                  single rolling slot
#       episode_<name>/             permanent, auto-created at Episode boundaries
#       manual_<unix_ts>/           permanent, unlimited
#
# Each checkpoint dir reuses the exact same on-disk shape as a flat slot
# (save.json + rotating backups + meta.json), so all the atomic-write /
# backup-chain primitives are shared. meta.json gains: kind, label, episode,
# permanent.
#
# The flat-slot API above is retained for back-compat (SaveManager + the CLI
# tools still drive it); migrate_flat_to_profile() folds an existing flat
# layout into a "Default" profile.

const PROFILES_DIRNAME: String = "profiles"
const CHECKPOINTS_DIRNAME: String = "checkpoints"
const PROFILE_META_NAME: String = "profile.json"
const DEFAULT_PROFILE_ID: String = "default"
const DEFAULT_PROFILE_NAME: String = "Default"
const AUTOSAVE_RING_KEEP: int = 3

# Checkpoint kinds. autosave + quicksave roll; manual + episode are permanent.
const KIND_AUTOSAVE: String = "autosave"
const KIND_QUICKSAVE: String = "quicksave"
const KIND_MANUAL: String = "manual"
const KIND_EPISODE: String = "episode"
const PERMANENT_KINDS: Array[String] = [KIND_MANUAL, KIND_EPISODE]

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
	return _backup_paths_in(slot_dir(slot_id))


# ---- dir-rooted primitives ----------------------------------------------
# Every save dir (a flat slot OR a profile checkpoint) holds the same shape:
# save.json + 3 rotating backups + meta.json. These helpers operate on an
# absolute dir path with a trailing slash so both layouts share one impl.

func _primary_in(dir_path: String) -> String:
	return dir_path + _PRIMARY_NAME


func _tmp_in(dir_path: String) -> String:
	return dir_path + _TMP_NAME


func _meta_in(dir_path: String) -> String:
	return dir_path + _META_NAME


func _backup_paths_in(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for n in _BACKUP_NAMES:
		out.append(dir_path + n)
	return out


func _ensure_dir(slot_id: String) -> bool:
	return _ensure_dir_path(slot_dir(slot_id))


# make_dir_recursive accepts a user:// path and is idempotent.
func _ensure_dir_path(dir_path: String) -> bool:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_warning("SaveStore: DirAccess.open(user://) failed")
		return false
	var err: int = dir.make_dir_recursive(dir_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("SaveStore: could not create %s (err %d)" % [dir_path, err])
		return false
	return true


# ---- queries ------------------------------------------------------------

func has_slot(slot_id: String) -> bool:
	return _dir_has_save(slot_dir(slot_id))


func _dir_has_save(dir_path: String) -> bool:
	if FileAccess.file_exists(_primary_in(dir_path)):
		return true
	for p in _backup_paths_in(dir_path):
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
	return _read_snapshot_in(slot_dir(slot_id))


func _read_snapshot_in(dir_path: String) -> Dictionary:
	var candidates: Array[String] = [_primary_in(dir_path)]
	for p in _backup_paths_in(dir_path):
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
	return _write_snapshot_in(slot_dir(slot_id), snapshot, meta)


func _write_snapshot_in(dir_path: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	if not _ensure_dir_path(dir_path):
		return false
	if not _write_atomic_in(dir_path, snapshot):
		return false
	# Meta is a sidecar; a failed meta write must not fail the save, but log it.
	if not _write_plain(_meta_in(dir_path), meta):
		push_warning("SaveStore: meta write failed for %s" % dir_path)
	return true


# Rewrites the primary (and meta) in place WITHOUT rotating backups. Used by
# the save editor so a `set` doesn't burn a backup slot per field edit.
func rewrite_snapshot(slot_id: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	return _rewrite_snapshot_in(slot_dir(slot_id), snapshot, meta)


func _rewrite_snapshot_in(dir_path: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	if not _ensure_dir_path(dir_path):
		return false
	if not _write_plain(_primary_in(dir_path), snapshot):
		return false
	if not _write_plain(_meta_in(dir_path), meta):
		push_warning("SaveStore: meta rewrite failed for %s" % dir_path)
	return true


func _write_atomic_in(dir_path: String, data: Dictionary) -> bool:
	_rotate_backups_in(dir_path)
	if not _write_plain(_tmp_in(dir_path), data):
		return false
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("SaveStore: DirAccess.open(%s) failed" % dir_path)
		return false
	if dir.file_exists(_PRIMARY_NAME):
		dir.remove(_PRIMARY_NAME)
	var err: int = dir.rename(_TMP_NAME, _PRIMARY_NAME)
	if err != OK:
		push_warning("SaveStore: rename tmp -> primary failed for %s (err %d)" % [dir_path, err])
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


func _rotate_backups_in(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
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


# Recursively delete a directory tree (files + nested dirs + the dir itself).
# Used for profile / checkpoint dirs, which may nest (profiles/<id>/checkpoints/...).
func _wipe_tree(dir_path: String) -> void:
	if not dir_path.ends_with("/"):
		dir_path += "/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_wipe_tree(dir_path + name + "/")
		else:
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))


func wipe_all() -> void:
	for slot_id in all_slot_ids():
		wipe_slot(slot_id)


# =========================================================================
# PROFILE + CHECKPOINT MODEL (issue #77)
# =========================================================================
#
# Profiles are named playthroughs; each owns a checkpoints/ timeline. All
# checkpoint reads/writes reuse the dir-rooted save primitives above, so a
# checkpoint is byte-identical in shape to a flat slot.

func _profiles_root() -> String:
	return saves_root + PROFILES_DIRNAME + "/"


func profile_dir(profile_id: String) -> String:
	return _profiles_root() + profile_id + "/"


func profile_meta_path(profile_id: String) -> String:
	return profile_dir(profile_id) + PROFILE_META_NAME


func _checkpoints_root(profile_id: String) -> String:
	return profile_dir(profile_id) + CHECKPOINTS_DIRNAME + "/"


func checkpoint_dir(profile_id: String, checkpoint_id: String) -> String:
	return _checkpoints_root(profile_id) + checkpoint_id + "/"


# ---- profiles -----------------------------------------------------------

# Profile ids that exist on disk (have a profile.json), in created order.
func list_profiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root: String = _profiles_root()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "." and name != "..":
			var meta: Dictionary = read_profile(name)
			if not meta.is_empty():
				out.append(meta)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("created", 0)) < int(b.get("created", 0)))
	return out


func has_profile(profile_id: String) -> bool:
	return FileAccess.file_exists(profile_meta_path(profile_id))


# Creates a profile dir + profile.json. Returns the profile id (slugified from
# the display name, deduped against existing ids). No-op-safe if it exists.
func create_profile(display_name: String, profile_id: String = "") -> String:
	if profile_id == "":
		profile_id = _slugify(display_name)
	if profile_id == "":
		profile_id = "profile"
	# Dedupe so two "My Run"s don't collide.
	var unique: String = profile_id
	var n: int = 2
	while has_profile(unique):
		unique = "%s_%d" % [profile_id, n]
		n += 1
	profile_id = unique
	if not _ensure_dir_path(_checkpoints_root(profile_id)):
		return ""
	var now: int = int(Time.get_unix_time_from_system())
	var meta: Dictionary = {
		"id": profile_id,
		"display_name": display_name if display_name != "" else profile_id,
		"created": now,
		"last_played": now,
		"active_checkpoint": "",
	}
	_write_plain(profile_meta_path(profile_id), meta)
	return profile_id


func read_profile(profile_id: String) -> Dictionary:
	var meta: Dictionary = _read_json_dict(profile_meta_path(profile_id))
	if not meta.is_empty():
		meta["id"] = profile_id
	return meta


func write_profile(profile_id: String, meta: Dictionary) -> bool:
	if not _ensure_dir_path(profile_dir(profile_id)):
		return false
	var to_write: Dictionary = meta.duplicate(true)
	to_write["id"] = profile_id
	return _write_plain(profile_meta_path(profile_id), to_write)


func delete_profile(profile_id: String) -> void:
	_wipe_tree(profile_dir(profile_id))


# ---- checkpoints --------------------------------------------------------

# Metadata for every checkpoint in a profile (reads only meta.json per dir).
# Sorted newest-first by timestamp.
func list_checkpoints(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root: String = _checkpoints_root(profile_id)
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "." and name != "..":
			var cp_dir: String = checkpoint_dir(profile_id, name)
			if _dir_has_save(cp_dir):
				var meta: Dictionary = read_checkpoint_meta(profile_id, name)
				if meta.is_empty():
					meta = {"checkpoint_id": name, "kind": _kind_from_id(name), "timestamp": 0}
				meta["checkpoint_id"] = name
				out.append(meta)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0)))
	return out


func has_checkpoint(profile_id: String, checkpoint_id: String) -> bool:
	return _dir_has_save(checkpoint_dir(profile_id, checkpoint_id))


func read_checkpoint_meta(profile_id: String, checkpoint_id: String) -> Dictionary:
	return _read_json_dict(_meta_in(checkpoint_dir(profile_id, checkpoint_id)))


func read_checkpoint(profile_id: String, checkpoint_id: String) -> Dictionary:
	return _read_snapshot_in(checkpoint_dir(profile_id, checkpoint_id))


# Atomic write of one checkpoint. `meta` is enriched with kind/label/episode/
# permanent so list_checkpoints can classify without parsing the payload.
# After an autosave write, prunes the ring to AUTOSAVE_RING_KEEP.
func write_checkpoint(profile_id: String, checkpoint_id: String, snapshot: Dictionary, meta: Dictionary) -> bool:
	var kind: String = String(meta.get("kind", _kind_from_id(checkpoint_id)))
	var enriched: Dictionary = meta.duplicate(true)
	enriched["checkpoint_id"] = checkpoint_id
	enriched["kind"] = kind
	enriched["permanent"] = PERMANENT_KINDS.has(kind)
	if not enriched.has("label"):
		enriched["label"] = ""
	if not enriched.has("episode"):
		enriched["episode"] = ""
	var ok: bool = _write_snapshot_in(checkpoint_dir(profile_id, checkpoint_id), snapshot, enriched)
	if not ok:
		return false
	if kind == KIND_AUTOSAVE:
		prune_autosaves(profile_id, AUTOSAVE_RING_KEEP)
	return true


# Refuses to delete a permanent (manual/episode) checkpoint. Returns true if
# the checkpoint was removed.
func delete_checkpoint(profile_id: String, checkpoint_id: String) -> bool:
	var meta: Dictionary = read_checkpoint_meta(profile_id, checkpoint_id)
	if _is_permanent_meta(meta, checkpoint_id):
		push_warning("SaveStore: refusing to delete permanent checkpoint '%s'" % checkpoint_id)
		return false
	_wipe_tree(checkpoint_dir(profile_id, checkpoint_id))
	return true


# Newest checkpoint in a profile by timestamp; "" if the profile has none.
func most_recent_checkpoint(profile_id: String) -> String:
	var checkpoints: Array[Dictionary] = list_checkpoints(profile_id)
	if checkpoints.is_empty():
		return ""
	# list_checkpoints is sorted newest-first.
	return String(checkpoints[0].get("checkpoint_id", ""))


# Evicts all but the newest `keep` autosave-kind checkpoints. Pure file I/O.
func prune_autosaves(profile_id: String, keep: int = AUTOSAVE_RING_KEEP) -> void:
	var autos: Array[Dictionary] = []
	for cp in list_checkpoints(profile_id):
		if String(cp.get("kind", "")) == KIND_AUTOSAVE:
			autos.append(cp)
	# list_checkpoints is newest-first; keep the head, evict the tail.
	if autos.size() <= keep:
		return
	for i in range(keep, autos.size()):
		var cid: String = String(autos[i].get("checkpoint_id", ""))
		if cid != "":
			_wipe_tree(checkpoint_dir(profile_id, cid))


# Convenience: mint a unix-stamped autosave id. Callers that write more than
# once a second pass an explicit id to avoid collision.
static func new_autosave_id() -> String:
	return "%s_%d" % [KIND_AUTOSAVE, int(Time.get_unix_time_from_system())]


static func new_manual_id() -> String:
	return "%s_%d" % [KIND_MANUAL, int(Time.get_unix_time_from_system())]


static func episode_id(episode: String) -> String:
	return "%s_%s" % [KIND_EPISODE, _slugify_static(episode)]


# ---- profile/checkpoint helpers -----------------------------------------

func _is_permanent_meta(meta: Dictionary, checkpoint_id: String) -> bool:
	if meta.has("permanent"):
		return meta["permanent"] == true
	# Fall back to id-derived kind when meta is missing/corrupt.
	return PERMANENT_KINDS.has(_kind_from_id(checkpoint_id))


# Classifies a checkpoint by its id prefix when meta is unavailable.
func _kind_from_id(checkpoint_id: String) -> String:
	if checkpoint_id.begins_with(KIND_QUICKSAVE):
		return KIND_QUICKSAVE
	if checkpoint_id.begins_with(KIND_AUTOSAVE):
		return KIND_AUTOSAVE
	if checkpoint_id.begins_with(KIND_EPISODE):
		return KIND_EPISODE
	if checkpoint_id.begins_with(KIND_MANUAL):
		return KIND_MANUAL
	return KIND_MANUAL


func _slugify(s: String) -> String:
	return _slugify_static(s)


static func _slugify_static(s: String) -> String:
	var out: String = ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges(true, true).trim_prefix("_").trim_suffix("_")


# ---- flat -> profile migration ------------------------------------------

# Folds an existing FLAT-slot layout (autosave/quicksave/manual_N under
# saves_root) into a single "Default" profile. Idempotent: refuses to run if
# the Default profile already exists. Returns true if it migrated anything.
#
# Mapping (per the issue):
#   - flat "autosave" primary + its 3 .bak backups -> autosave RING (newest 3,
#     primary newest). Each becomes a first-class loadable autosave checkpoint.
#   - flat "quicksave"        -> quicksave checkpoint (rolling).
#   - flat "manual_N"         -> permanent manual checkpoint.
func migrate_flat_to_profile() -> bool:
	if has_profile(DEFAULT_PROFILE_ID):
		return false
	# Nothing to migrate if no flat slot has data.
	var any: bool = false
	for slot_id in all_slot_ids():
		if has_slot(slot_id):
			any = true
			break
	if not any:
		return false
	var pid: String = create_profile(DEFAULT_PROFILE_NAME, DEFAULT_PROFILE_ID)
	if pid == "":
		return false

	# Shared monotonic base so the autosave ring is always newer than migrated
	# manuals. This keeps most_recent_checkpoint() (and the active_checkpoint it
	# seeds) anchored on the real most-recent play state, not a permanent manual.
	var base_ts: int = int(Time.get_unix_time_from_system())

	# --- autosave ring: primary + backups, newest first ---
	if has_slot("autosave"):
		var auto_dir: String = slot_dir("autosave")
		var ring_sources: Array[String] = [_primary_in(auto_dir)]
		for b in _backup_paths_in(auto_dir):
			ring_sources.append(b)
		# Newest gets the largest timestamp so list/ring ordering is correct.
		var written: int = 0
		for i in range(ring_sources.size()):
			var snap: Dictionary = _read_json_dict(ring_sources[i])
			if snap.is_empty():
				continue
			if written >= AUTOSAVE_RING_KEEP:
				break
			var ts: int = base_ts - written  # primary = base_ts (newest)
			var cid: String = "%s_%d" % [KIND_AUTOSAVE, ts]
			var meta: Dictionary = build_meta_from_snapshot(cid, snap)
			meta["timestamp"] = ts
			meta["kind"] = KIND_AUTOSAVE
			meta["label"] = "Autosave"
			write_checkpoint(pid, cid, snap, meta)
			written += 1

	# --- quicksave -> rolling quicksave checkpoint ---
	if has_slot("quicksave"):
		var qsnap: Dictionary = read_snapshot("quicksave")
		if not qsnap.is_empty():
			var qmeta: Dictionary = build_meta_from_snapshot(KIND_QUICKSAVE, qsnap)
			qmeta["kind"] = KIND_QUICKSAVE
			qmeta["label"] = "Quicksave"
			write_checkpoint(pid, KIND_QUICKSAVE, qsnap, qmeta)

	# --- manual_N -> permanent manual checkpoints ---
	# Stamped strictly OLDER than the autosave ring (base_ts - ring - i) so a
	# migrated manual never outranks the real most-recent autosave in
	# most_recent_checkpoint(); manuals are permanent, so their relative order is
	# cosmetic.
	for i in range(1, MANUAL_SLOT_COUNT + 1):
		var mslot: String = "manual_%d" % i
		if not has_slot(mslot):
			continue
		var msnap: Dictionary = read_snapshot(mslot)
		if msnap.is_empty():
			continue
		var cid_m: String = "%s_%d" % [KIND_MANUAL, base_ts - AUTOSAVE_RING_KEEP - i]
		var mmeta: Dictionary = build_meta_from_snapshot(cid_m, msnap)
		mmeta["kind"] = KIND_MANUAL
		mmeta["label"] = "Manual save %d" % i
		write_checkpoint(pid, cid_m, msnap, mmeta)

	# Mark the most recent checkpoint active.
	var prof: Dictionary = read_profile(pid)
	prof["active_checkpoint"] = most_recent_checkpoint(pid)
	write_profile(pid, prof)
	return true


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
