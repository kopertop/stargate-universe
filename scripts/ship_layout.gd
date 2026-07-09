extends Node

# @no-save: static ship topology loaded from data/ship_layout.json — read-only
# at runtime, so nothing to persist (the layout itself never changes).
#
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
const CONNECTIONS_PATH: String = "res://data/room_connections.json"

# 1 JSON unit = 0.05 m. Picked so the JSON gate_room (800 wide) gives a
# 40 m room — wide enough for the Destiny gate hall, small enough that
# 100-m corridors stay walkable.
const SCALE: float = 0.05

var _by_id: Dictionary = {}
var _loaded: bool = false
# Adjacency map for BFS: room_id -> Array[String] of neighbouring room ids.
# Built from data/room_connections.json with reverse edges mirrored in (the
# JSON only declares each connection once, like room.gd::_setup_doors expects).
var _adjacency: Dictionary = {}
# Direction-tagged edges keyed by room_id. Each entry is an Array of
# Dictionaries `{ "to": String, "dir": String, "plaque": String }`. Reverse
# edges are mirrored with the direction flipped (+x ↔ -x, +z ↔ -z) so the
# Kino map can place pips on the correct wall from either side.
var _outgoing_edges: Dictionary = {}
var _connections_loaded: bool = false


# Flip an "axis-aligned" direction string for reverse-edge mirroring.
static func _flip_dir(d: String) -> String:
	match d:
		"+x": return "-x"
		"-x": return "+x"
		"+z": return "-z"
		"-z": return "+z"
		_:    return d


func _ready() -> void:
	_load()
	_load_connections()


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


# ============================================================================
# KEY ROOMS  —  ⚠️ COORDINATION SEAM (read before editing)
# ============================================================================
# A "key room" is a story-/system-critical room (Control Interface Room, Kino
# Room, …) that earns a SPECIAL discovery sting — sounds/discovery_stinger_key.ogg
# (the "magical discovery" cue) — instead of the normal one. The room-discovery
# audio (scripts/hud.gd::_on_room_deciphered) decides which sting to play by
# calling THIS function and nothing else.
#
# ──────────────────────────────────────────────────────────────────────────
# 🛑 A SEPARATE WORK STREAM OWNS THE KEY-ROOM DEFINITIONS. 🛑
# ──────────────────────────────────────────────────────────────────────────
# The CANONICAL way to mark a room "key" is a per-room flag in
# data/ship_layout.json:   { "id": "...", ..., "key_room": true }
# `is_key_room()` reads that flag FIRST, so as soon as those flags land the
# audio routing is automatically correct — no code change here.
#
# `_KEY_ROOMS_FALLBACK` below is a TEMPORARY hardcoded list so the key-room
# sting works TODAY, before the flags exist. When the key-room definitions
# land, DELETE the fallback list and the `or … .has(id)` clause so
# ship_layout.json is the single source of truth (avoid the project's
# scattered-collection anti-pattern — do NOT keep two lists of key rooms).
# If the definitions end up living somewhere other than the JSON flag, update
# THIS function to read them and keep is_key_room() the ONLY key-room query.
const _KEY_ROOMS_FALLBACK: PackedStringArray = [
	"control_interface_room",  # Control Interface Room
	"eli_quarters",            # "Kino Room" (the Kino Remote lives here)
]


func is_key_room(id: String) -> bool:
	if room(id).get("key_room", false) == true:
		return true
	return _KEY_ROOMS_FALLBACK.has(id)


# Rooms whose `floor` field matches (0 = main deck, 1 = upper deck).
func rooms_on_floor(floor_index: int) -> Array:
	var out: Array = []
	for r: Dictionary in all_rooms():
		if int(r.get("floor", 0)) == floor_index:
			out.append(r)
	return out


# Every unique door connection, ONE entry per pair regardless of the JSON's
# single-direction authoring. Each entry: { "a": String, "b": String,
# "dir": String (a's wall toward b), "plaque": String }. Used by the merged
# deck builder and the ship-systems door list.
func door_pairs() -> Array:
	_load_connections()
	var seen: Dictionary = {}
	var out: Array = []
	for from_id: String in _outgoing_edges.keys():
		for edge: Dictionary in _outgoing_edges[from_id] as Array:
			var to_id: String = String(edge.get("to", ""))
			var key: String = "%s|%s" % [from_id, to_id] if from_id <= to_id else "%s|%s" % [to_id, from_id]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({
				"a": from_id,
				"b": to_id,
				"dir": String(edge.get("dir", "")),
				"plaque": String(edge.get("plaque", "")),
			})
	return out


# JSON width/height converted to metres. Returns Vector2(width, depth) in the
# Godot XZ plane (JSON 2D plan maps to ship's floor plan).
func size_metres(id: String) -> Vector2:
	var r: Dictionary = room(id)
	if r.is_empty():
		return Vector2.ZERO
	return Vector2(float(r["width"]) * SCALE, float(r["height"]) * SCALE)


# Room centre in JSON-grid units (Vector2 on the X/Y plane). Useful for the
# Kino Remote map and for picking the midpoint between two room rectangles
# when drawing a route polyline.
func grid_centre(id: String) -> Vector2:
	var r: Dictionary = room(id)
	if r.is_empty():
		return Vector2.ZERO
	return Vector2(
		(float(r["startX"]) + float(r["endX"])) * 0.5,
		(float(r["startY"]) + float(r["endY"])) * 0.5,
	)


# ---- Room graph (BFS) -----------------------------------------------------

# Load room_connections.json once and fold reverse edges in so the resulting
# adjacency dict is symmetric — matches room.gd's reverse-edge mirror logic
# (the JSON only lists each connection in one direction).
func _load_connections() -> void:
	if _connections_loaded:
		return
	var f: FileAccess = FileAccess.open(CONNECTIONS_PATH, FileAccess.READ)
	if f == null:
		push_error("ShipLayout: cannot open %s" % CONNECTIONS_PATH)
		_connections_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ShipLayout: %s did not parse to a dictionary" % CONNECTIONS_PATH)
		_connections_loaded = true
		return
	var raw: Dictionary = parsed
	for from_id in raw.keys():
		var edges: Variant = raw[from_id]
		if not (edges is Array):
			continue
		for edge in edges:
			if not (edge is Dictionary):
				continue
			var edge_dict: Dictionary = edge
			var to_id: String = String(edge_dict.get("to", ""))
			if to_id == "":
				continue
			var dir: String = String(edge_dict.get("dir", ""))
			var plaque: String = String(edge_dict.get("plaque", ""))
			_add_edge(String(from_id), to_id)
			_add_edge(to_id, String(from_id))
			_add_directed_edge(String(from_id), to_id, dir, plaque)
			_add_directed_edge(to_id, String(from_id), _flip_dir(dir), plaque)
	_connections_loaded = true


func _add_edge(a: String, b: String) -> void:
	if not _adjacency.has(a):
		_adjacency[a] = []
	var neighbours: Array = _adjacency[a]
	if not neighbours.has(b):
		neighbours.append(b)


# Stores ONE direction-tagged edge. Skips duplicates (same to + same dir).
func _add_directed_edge(from_id: String, to_id: String, dir: String, plaque: String) -> void:
	if not _outgoing_edges.has(from_id):
		_outgoing_edges[from_id] = []
	var arr: Array = _outgoing_edges[from_id]
	for existing in arr:
		var e: Dictionary = existing
		if String(e.get("to", "")) == to_id and String(e.get("dir", "")) == dir:
			return
	arr.append({"to": to_id, "dir": dir, "plaque": plaque})


# Direction-aware outgoing edges of `id` — used by the Kino map to place door
# pips on the correct wall. Each entry: { "to": String, "dir": String,
# "plaque": String }. Returns empty array for unknown ids.
func outgoing_edges(id: String) -> Array:
	_load_connections()
	return (_outgoing_edges.get(id, []) as Array).duplicate()


# Neighbours of `id`. Returns empty array for unknown ids.
func neighbours(id: String) -> Array:
	_load_connections()
	return (_adjacency.get(id, []) as Array).duplicate()


# Shortest path between two rooms over the door graph. Returns ordered
# PackedStringArray including both endpoints, or empty if unreachable.
# Same-room requests return a single-element array.
func path_through_rooms(from_id: String, to_id: String) -> PackedStringArray:
	_load_connections()
	var out: PackedStringArray = PackedStringArray()
	if from_id == "" or to_id == "":
		return out
	if from_id == to_id:
		out.append(from_id)
		return out
	if not _adjacency.has(from_id):
		return out
	# BFS — parent map reconstructs the path.
	var parent: Dictionary = {from_id: ""}
	var queue: Array[String] = [from_id]
	var found: bool = false
	while queue.size() > 0:
		var current: String = queue.pop_front()
		if current == to_id:
			found = true
			break
		for neighbour in _adjacency.get(current, []) as Array:
			var n: String = String(neighbour)
			if parent.has(n):
				continue
			parent[n] = current
			queue.append(n)
	if not found:
		return out
	# Walk back from to_id to from_id, then reverse.
	var reversed: Array[String] = []
	var cursor: String = to_id
	while cursor != "":
		reversed.append(cursor)
		cursor = String(parent.get(cursor, ""))
	reversed.reverse()
	for r in reversed:
		out.append(r)
	return out


# Second hop on the BFS path from from_id toward to_id. Returns "" if either
# endpoint is invalid, the rooms are identical, or there is no path.
func next_room_toward(from_id: String, to_id: String) -> String:
	var path: PackedStringArray = path_through_rooms(from_id, to_id)
	if path.size() < 2:
		return ""
	return path[1]
