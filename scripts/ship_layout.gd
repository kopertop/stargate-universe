extends Node

# Destiny ship layout: 19 rooms, 7 template types, two floors. Loaded from
# data/ship_layout.json (the canonical source of truth, mirrored from the
# sibling stargate-evolution project). Autoload — read via `ShipLayout.room(id)`.
#
# JSON coordinate units are ship-plan grid units. Convert to Godot world units
# (metres) with `SCALE` — 1 unit = 5 cm, so the full ~3000-unit ship spans
# ~150 m and the gate room (800×400) maps to 40×20 m.
#
# NOTE: gate_room is reference-only — its actual scene (scenes/gate_room.tscn)
# is hand-authored. Other rooms instantiate scenes/room.tscn with a `room_id`
# and let room_builder.gd generate basic-box geometry from this data.

const LAYOUT_PATH: String = "res://data/ship_layout.json"

# 1 JSON unit = 0.05 m. Picked so the JSON gate_room (800 wide) gives a
# 40 m room — wide enough for the Destiny gate hall, small enough that
# 100-m corridors stay walkable.
const SCALE: float = 0.05

var _by_id: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	_load()


# Idempotent — safe to call from tests before _ready fires in headless mode.
func _load() -> void:
	if _loaded:
		return
	var f: FileAccess = FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		push_error("ShipLayout: cannot open %s" % LAYOUT_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_error("ShipLayout: %s did not parse to an array" % LAYOUT_PATH)
		return
	for entry in parsed:
		if entry is Dictionary and entry.has("id"):
			_by_id[entry["id"]] = entry
	_loaded = true


func room(id: String) -> Dictionary:
	_load()
	if _by_id.has(id):
		return _by_id[id]
	return {}


func all_rooms() -> Array:
	_load()
	return _by_id.values()


# JSON width/height converted to metres. Returns Vector2(width, depth) in the
# Godot XZ plane (JSON 2D plan maps to ship's floor plan).
func size_metres(id: String) -> Vector2:
	var r: Dictionary = room(id)
	if r.is_empty():
		return Vector2.ZERO
	return Vector2(float(r["width"]) * SCALE, float(r["height"]) * SCALE)
