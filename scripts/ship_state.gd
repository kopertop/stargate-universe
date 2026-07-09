extends Node

# Dynamic per-room and per-door runtime state for Destiny — the mutable
# counterpart to ShipLayout (which is static topology and stays @no-save).
#
# ONE registry per kind of thing (collection-fork policy):
#   _rooms: room_id -> { "damage_pct": float, "shield_pct": float, "module": String }
#   _doors: door_key -> { "open": bool, "locked": bool }
#
# damage_pct is the inverse of the GDD's "condition" (design/gdd/
# ship-state-system.md: condition = 100 - damage_pct) — stored as damage
# because every consumer here asks "how broken is it", not "how healthy".
# shield_pct is the per-room defensive shield strength (0-100).
#
# Rooms above BUILD_DAMAGE_THRESHOLD damage refuse module construction until
# repaired — the hook for the repair-robot loop (see design/gdd/
# ship-building-mode.md). repair_room() is the single entry point that robot
# will call.
#
# Door keys come from GameState.door_key(a, b) — sorted "a|b" pairs, the same
# key space doors_traversed already uses.

signal door_changed(door_id: String, open: bool, locked: bool)
signal room_changed(room_id: String)
signal module_built(room_id: String, module_id: String)

const MODULES_PATH: String = "res://data/room_modules.json"

# Structural damage (%) above which the build console refuses new modules.
const BUILD_DAMAGE_THRESHOLD: float = 25.0

# Room types that never take a build console / module (corridors are transit,
# elevators are machinery, the gate room is the artisan hero scene, and the
# control interface room is the ship's bridge).
const UNBUILDABLE_TYPES: Array[String] = ["corridor", "elevator", "gate_room"]
const UNBUILDABLE_ROOMS: Array[String] = ["control_interface_room"]

# ship_layout.json statuses are all "ok"; the E1 fiction says otherwise.
# Story-damaged sections seed here so the Rooms readout, damage overlays and
# the build gate agree with what the player sees in the world.
const SEED_STATE_BY_ROOM: Dictionary = {
	"breached_section_south": {"damage_pct": 65.0, "shield_pct": 20.0},
	"sealed_section_north": {"damage_pct": 85.0, "shield_pct": 0.0},
}

# Doors that start locked (story seeds). Key = GameState.door_key(a, b).
const SEED_LOCKED_DOORS: Array[String] = ["north_spur|sealed_section_north"]

# When true, transition doors route through the merged per-floor deck scenes
# (scenes/deck.tscn) instead of the one-room-at-a-time scenes/room.tscn flow.
# Off by default so the classic E1 flow (and its test suite) is untouched;
# flipped on by `--decks` in the user args, by running deck.tscn directly,
# or by loading a save written in deck mode (the flag serializes).
var merged_decks_enabled: bool = false

var _rooms: Dictionary = {}
var _doors: Dictionary = {}
var _modules: Array = []
var _modules_loaded: bool = false


func _ready() -> void:
	# Accept the flag both as a user arg (`godot -- --decks`) and a raw
	# engine arg (`godot --decks` — unknown engine args pass through).
	if OS.get_cmdline_user_args().has("--decks") or OS.get_cmdline_args().has("--decks"):
		merged_decks_enabled = true
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "ship_state", self)


# ---- rooms ------------------------------------------------------------------

# Lazily-created state row for a room. Returns a LIVE dictionary — callers
# mutate through the setters below, not directly.
func room_state(room_id: String) -> Dictionary:
	if not _rooms.has(room_id):
		var seed_row: Dictionary = SEED_STATE_BY_ROOM.get(room_id, {})
		_rooms[room_id] = {
			"damage_pct": float(seed_row.get("damage_pct", 0.0)),
			"shield_pct": float(seed_row.get("shield_pct", 100.0)),
			"module": "",
		}
	return _rooms[room_id]


func room_damage(room_id: String) -> float:
	return float(room_state(room_id)["damage_pct"])


func room_shield(room_id: String) -> float:
	return float(room_state(room_id)["shield_pct"])


func room_module(room_id: String) -> String:
	return String(room_state(room_id)["module"])


func set_room_damage(room_id: String, pct: float) -> void:
	var row: Dictionary = room_state(room_id)
	var clamped: float = clampf(pct, 0.0, 100.0)
	if is_equal_approx(float(row["damage_pct"]), clamped):
		return
	row["damage_pct"] = clamped
	room_changed.emit(room_id)


func set_room_shield(room_id: String, pct: float) -> void:
	var row: Dictionary = room_state(room_id)
	var clamped: float = clampf(pct, 0.0, 100.0)
	if is_equal_approx(float(row["shield_pct"]), clamped):
		return
	row["shield_pct"] = clamped
	room_changed.emit(room_id)


func apply_room_damage(room_id: String, delta: float) -> void:
	set_room_damage(room_id, room_damage(room_id) + delta)


# Single repair entry point — player hand-repairs now, the repair robot later.
# Returns the damage actually healed (0 when the room was already pristine).
func repair_room(room_id: String, amount: float) -> float:
	var before: float = room_damage(room_id)
	set_room_damage(room_id, before - amount)
	return before - room_damage(room_id)


func is_room_buildable(room_id: String) -> bool:
	if UNBUILDABLE_ROOMS.has(room_id):
		return false
	var row: Dictionary = ShipLayout.room(room_id)
	if row.is_empty():
		return false
	return not UNBUILDABLE_TYPES.has(String(row.get("type", "")))


# ---- module catalog + build -------------------------------------------------

func modules() -> Array:
	_load_modules()
	return _modules.duplicate()


func module(module_id: String) -> Dictionary:
	_load_modules()
	for m: Dictionary in _modules:
		if String(m.get("id", "")) == module_id:
			return m
	return {}


# Catalog entries this room's TYPE accepts (an empty allowed_types list in the
# catalog means "any buildable room").
func modules_for_room(room_id: String) -> Array:
	if not is_room_buildable(room_id):
		return []
	var room_type: String = String(ShipLayout.room(room_id).get("type", ""))
	var out: Array = []
	for m: Dictionary in modules():
		var allowed: Array = m.get("allowed_types", []) as Array
		if allowed.is_empty() or allowed.has(room_type):
			out.append(m)
	return out


# Why a build is currently impossible, or "" when it may proceed. UI surfaces
# the string verbatim.
func build_blocker(room_id: String, module_id: String) -> String:
	if not is_room_buildable(room_id):
		return "This compartment cannot host modules."
	if module(module_id).is_empty():
		return "Unknown module '%s'." % module_id
	var dmg: float = room_damage(room_id)
	if dmg > BUILD_DAMAGE_THRESHOLD:
		return ("Structural damage at %d%% — repairs required before construction. "
			+ "Dispatch a repair robot once one is found.") % int(round(dmg))
	if not modules_for_room(room_id).any(
			func(m: Dictionary) -> bool: return String(m.get("id", "")) == module_id):
		return "Module incompatible with this compartment type."
	return ""


# Returns true and records the module when the build is legal.
func build_module(room_id: String, module_id: String) -> bool:
	if build_blocker(room_id, module_id) != "":
		return false
	var row: Dictionary = room_state(room_id)
	if String(row["module"]) == module_id:
		return false
	row["module"] = module_id
	module_built.emit(room_id, module_id)
	room_changed.emit(room_id)
	return true


func clear_room_module(room_id: String) -> void:
	var row: Dictionary = room_state(room_id)
	if String(row["module"]) == "":
		return
	row["module"] = ""
	module_built.emit(room_id, "")
	room_changed.emit(room_id)


func _load_modules() -> void:
	if _modules_loaded:
		return
	_modules_loaded = true
	var f: FileAccess = FileAccess.open(MODULES_PATH, FileAccess.READ)
	if f == null:
		push_error("ShipState: cannot open %s" % MODULES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("ShipState: %s did not parse to an array" % MODULES_PATH)
		return
	for entry in parsed:
		if entry is Dictionary and entry.has("id"):
			_modules.append(entry)


# ---- doors ------------------------------------------------------------------

func door_state(door_id: String) -> Dictionary:
	if not _doors.has(door_id):
		_doors[door_id] = {
			"open": false,
			"locked": SEED_LOCKED_DOORS.has(door_id),
		}
	return _doors[door_id]


func is_door_open(door_id: String) -> bool:
	return bool(door_state(door_id)["open"])


func is_door_locked(door_id: String) -> bool:
	return bool(door_state(door_id)["locked"])


# Returns false (and leaves the door shut) when the door is locked — callers
# surface the lock message. Unlock first to force it open (console does both).
func set_door_open(door_id: String, open: bool) -> bool:
	var row: Dictionary = door_state(door_id)
	if bool(row["locked"]) and open:
		return false
	if bool(row["open"]) == open:
		return true
	row["open"] = open
	door_changed.emit(door_id, open, bool(row["locked"]))
	return true


func set_door_locked(door_id: String, locked: bool) -> void:
	var row: Dictionary = door_state(door_id)
	if bool(row["locked"]) == locked:
		return
	row["locked"] = locked
	# Locking an open door slams it shut — a locked-open door is meaningless.
	if locked and bool(row["open"]):
		row["open"] = false
	door_changed.emit(door_id, bool(row["open"]), locked)


# ---- save / reset -----------------------------------------------------------

func reset() -> void:
	_rooms.clear()
	_doors.clear()
	merged_decks_enabled = false


func serialize() -> Dictionary:
	return {
		"rooms": _rooms.duplicate(true),
		"doors": _doors.duplicate(true),
		"merged_decks_enabled": merged_decks_enabled,
	}


func deserialize(data: Dictionary, _version: int = 1) -> void:
	reset()
	var rooms_block: Variant = data.get("rooms", {})
	if rooms_block is Dictionary:
		for room_id in (rooms_block as Dictionary).keys():
			var src: Variant = rooms_block[room_id]
			if not (src is Dictionary):
				continue
			var row: Dictionary = room_state(String(room_id))
			row["damage_pct"] = clampf(float((src as Dictionary).get("damage_pct", row["damage_pct"])), 0.0, 100.0)
			row["shield_pct"] = clampf(float((src as Dictionary).get("shield_pct", row["shield_pct"])), 0.0, 100.0)
			row["module"] = String((src as Dictionary).get("module", ""))
	var doors_block: Variant = data.get("doors", {})
	if doors_block is Dictionary:
		for door_id in (doors_block as Dictionary).keys():
			var src_d: Variant = doors_block[door_id]
			if not (src_d is Dictionary):
				continue
			var row_d: Dictionary = door_state(String(door_id))
			row_d["open"] = bool((src_d as Dictionary).get("open", row_d["open"]))
			row_d["locked"] = bool((src_d as Dictionary).get("locked", row_d["locked"]))
	merged_decks_enabled = bool(data.get("merged_decks_enabled", false))
