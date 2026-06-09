extends Node

# ProceduralShip — generated multi-floor ship topology.
#
# Wraps ShipLayout (base authored rooms, floor 0–1) and owns the procedurally
# grown floors (floor 2+). Exposes the same lookup surface as ShipLayout so
# callers use one API regardless of which floor a room lives on.
#
# SAVE CONTRACT: state is serialized in full because the grown graph is stored
# by value, not re-derived from a seed. Generated rooms are discovered incrementally
# by the player; regenerating from a seed is not an option because the pool of
# once-only specials would differ between runs.
#
# Data that lives here (all JSON-serializable, no acquisition-vocab bools):
#   _floors   {int -> {unlocked, code_known, generated, rooms, specials_placed, cap, seed}}
#   _rooms    {room_id -> room row (same shape as ShipLayout rows)}
#   _edges    {room_id -> [{dir, to, plaque}]}  — forward declarations only; reverse mirrored at read time
#   _special_pool_remaining {type_id -> int}    — draw-without-replacement pool
#
# Autoload — reach as ProceduralShip.room("id") from game scripts.
# In headless -s SceneTree tests reach via root.get_node_or_null("/root/ProceduralShip").

const ROOM_TYPES_PATH: String = "res://data/room_types.json"

# Typed direction flip — shared with ShipLayout conventions.
const DIR_FLIP: Dictionary = {
	"+x": "-x",
	"-x": "+x",
	"+z": "-z",
	"-z": "+z",
}

# Floor index bounds — generatable range excludes 0 (JSON-internal authored index)
# and the authored spine (floor 1). Down-floors run from -1 to MIN_FLOOR (negative).
const MIN_FLOOR: int = -3
const MAX_FLOOR: int = 6
# Authored floors — floors whose room layout is the hand-authored spine, never
# regenerated. Floor 2 is NOT in this list: it has a pre-seeded floor record
# (unlocked + code_known) but its rooms are grown by _generate_floor just like
# floors 3+. Only floor 1 is truly authored (ShipLayout base rooms, no generation).
const AUTHORED_FLOORS: Array = [1]

# Stairs connection: special edge direction for the gate-room ↔ Floor-2 stairs link.
# Not a real cardinal direction — treated as a named vertical connector, same role
# as "elevator" in room.gd (dir remapped to a wall at stamp time). Used only in
# door_edges() so gate_room.gd can read the edge and room.gd can mirror it back.
const STAIRS_DIR: String = "stairs"
# The arrival spawn key that the Observation Deck stamps for the return trip,
# and that gate_room.gd creates a matching Marker3D for on the stair landing.
const STAIRS_GATE_SPAWN: String = "FromObservationDeck"
const STAIRS_OBS_SPAWN: String = "FromGateRoomStairs"

# Upper-deck link: virtual edge connecting Floor-2 Observation Deck (f2_r00) to
# the authored hydroponics room so the upper-deck cluster is reachable on foot
# via the gate stairs (no elevator required).
#
# Two separate dir tokens decouple the wall remap on each side:
#   UPPER_DECK_DIR        — used on the f2_r00 (obs-deck) side → remapped to +z
#   UPPER_DECK_RETURN_DIR — used on the hydroponics side       → remapped to +z
#
# Wall-stacking audit (non-overlap doors → wall-centre, stacking is visual only):
#   f2_r00     -z = stairs (reserved), +z = upper-deck link (free cardinal)
#   hydroponics +z = upper-deck link (free; only occupied wall is -x reverse from
#                    elevator_room_floor_1 +x forward edge)
#
# The elevator edge (elevator_north → elevator_room_floor_1) stays intact; the
# elevator hub is now an ALTERNATE route to the upper deck, not the sole one.
const UPPER_DECK_DIR: String = "upper_deck"
const UPPER_DECK_RETURN_DIR: String = "upper_deck_return"
# Room ids for the upper-deck link endpoints. Hydroponics is the hub of the
# authored upper-deck cluster (elevator_room_floor_1 → +x → hydroponics and the
# cluster's other rooms hang off the hub).
const UPPER_DECK_TARGET: String = "hydroponics"

# Parts budget per-floor: each generated floor seeds this many parts (via crates +
# salvage panels) so the player can always afford to unlock the NEXT floor.
# Budget = FLOOR_UNLOCK_COST_BASE * (n+1) * PARTS_BUDGET_MARGIN_PCT / 100
const PARTS_BUDGET_MARGIN_PCT: int = 120   # 20% headroom over bare unlock cost
# Parts granted per salvage panel interact.
const SALVAGE_PANEL_GRANT: int = 3

# Per-filler-type approximate size in JSON grid units (width x height).
# Corridors are long on one axis; rooms are more square.
const _FILLER_SIZES: Dictionary = {
	"corridor":   {"w": 400, "h": 120},
	"storage":    {"w": 200, "h": 200},
	"power_node": {"w": 300, "h": 250},
	"recycling":  {"w": 250, "h": 200},
	"crew_quarters": {"w": 200, "h": 200},
}
const _SPECIAL_SIZE: Dictionary = {"w": 300, "h": 300}

# Floor N grid origin offset in JSON units (so floor 2 doesn't collide with floor 1).
const _FLOOR_GRID_STRIDE_Y: int = 4000
# Retry limit before capping a branch during layout growth.
const _MAX_PLACE_RETRIES: int = 12
# Minimum overlap (in JSON units) for a door to read as physically aligned.
const _MIN_OVERLAP: int = 40
# Minimum room gap tolerance before rectangles are considered colliding.
const _ROOM_GAP: int = 10

var _catalog: Dictionary = {}           # type_id -> row
var _catalog_loaded: bool = false

# Serialized state.
var _floors: Dictionary = {}            # int_floor -> FloorRecord
var _rooms: Dictionary = {}             # room_id -> row Dictionary
var _edges: Dictionary = {}             # room_id -> Array[{dir,to,plaque}]
var _special_pool_remaining: Dictionary = {}  # type_id -> int remaining
# Phase B: room assignments. ONE collection (collection-fork policy). Only
# generated storage rooms can be assigned; keyed room_id -> assigned type_id.
var _floor_assignments: Dictionary = {} # room_id -> assigned_function type_id

# Floor unlock cost parameters — tunable consts. Floor N costs BASE * N parts.
const FLOOR_UNLOCK_COST_BASE: int = 5
# Inventory item id used as the unlock currency.
const FLOOR_UNLOCK_ITEM: String = "parts"
# Assignment cost in parts per assignment.
const ROOM_ASSIGN_COST: int = 3

# Elevator power-restore requirement (issue #132).
# Fuses the player must hold before restore_elevator_power() will succeed.
# Requirement is ONE dict (not per-fuse bools) — collection-fork policy.
const ELEVATOR_FUSE_REQUIREMENT: Dictionary = {"large_fuse": 1, "bus_fuse": 2}

# Signal — emitted by restore_elevator_power() after the flag flips.
signal elevator_power_changed(powered: bool)

# Serialized power-state fields.
# World-state verbs (not acquisition vocab) — lint-safe.
var _elevator_powered: bool = false   # @collection-ok: single world-state flag, not an enumerated collection
var _minigame_solved: bool = false    # @collection-ok: single world-state flag, not an enumerated collection
# Bridge-discovered flag — set via mark_bridge_discovered(); also checked via
# GameState.rooms_discovered scan (is_bridge_discovered reads both).
# Persisted so elevator-panel down-floor reveal survives save/load.
var _bridge_discovered: bool = false  # @collection-ok: single world-state flag, not an enumerated collection


func _ready() -> void:
	_load_catalog()
	_seed_special_pool()
	# Default: floor 1 is unlocked (authored spine). Others locked until Phase B.
	if not _floors.has(1):
		_floors[1] = {
			"unlocked": true,
			"code_known": false,
			"generated": false,
			"rooms": [],
			"specials_placed": 0,
			"cap": 0,
			"seed": 0,
		}
	# Floor 2 is free — reachable via the gate-room stairs (no parts/code required).
	if not _floors.has(2):
		_floors[2] = {
			"unlocked": true,
			"code_known": true,
			"generated": false,
			"rooms": [],
			"specials_placed": 0,
			"cap": 0,
			"seed": 0,
		}
	# Register with SaveManager (duck-typed: works under autoload AND headless).
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.call("register_system", "procedural_ship", self)


# ============================================================
# CATALOG
# ============================================================

func _load_catalog() -> void:
	if _catalog_loaded:
		return
	var f: FileAccess = FileAccess.open(ROOM_TYPES_PATH, FileAccess.READ)
	if f == null:
		push_error("ProceduralShip: cannot open %s" % ROOM_TYPES_PATH)
		_catalog_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("ProceduralShip: %s did not parse to array" % ROOM_TYPES_PATH)
		_catalog_loaded = true
		return
	for entry in parsed:
		if entry is Dictionary and (entry as Dictionary).has("id"):
			var d: Dictionary = entry
			_catalog[String(d["id"])] = d
	_catalog_loaded = true


# Enumerate every room type in the catalog.
func all_room_types() -> Array:
	_load_catalog()
	return _catalog.values()


# Single room type row by id.
func room_type(type_id: String) -> Dictionary:
	_load_catalog()
	if _catalog.has(type_id):
		return _catalog[type_id]
	return {}


# ============================================================
# SPECIAL POOL
# ============================================================

func _seed_special_pool() -> void:
	_load_catalog()
	_special_pool_remaining.clear()
	for entry in _catalog.values():
		var d: Dictionary = entry
		var cat: String = String(d.get("category", ""))
		if cat == "special_once" or cat == "special_limited":
			var mc: int = int(d.get("max_count", 1))
			_special_pool_remaining[String(d["id"])] = mc


# ============================================================
# FACADE — delegates base ids to ShipLayout, answers generated ids itself
# ============================================================

# True when this id was generated by ProceduralShip (not from ShipLayout).
func is_generated(id: String) -> bool:
	return _rooms.has(id)


# Room row for any id — base or generated. Returns {} when unknown.
func room(id: String) -> Dictionary:
	if _rooms.has(id):
		return _rooms[id]
	var sl: Node = _ship_layout()
	if sl != null:
		return sl.call("room", id)
	return {}


# Grid centre in JSON units. Delegates to ShipLayout for base rooms.
func grid_centre(id: String) -> Vector2:
	var r: Dictionary = room(id)
	if r.is_empty():
		return Vector2.ZERO
	return Vector2(
		(float(r.get("startX", 0)) + float(r.get("endX", 0))) * 0.5,
		(float(r.get("startY", 0)) + float(r.get("endY", 0))) * 0.5,
	)


# All known rooms: base authored list + discovered generated rooms.
func all_known_rooms() -> Array:
	var sl: Node = _ship_layout()
	var out: Array = []
	if sl != null:
		out.append_array(sl.call("all_rooms"))
	for r in _rooms.values():
		out.append(r)
	return out


# THE single key-room query (drives the special discovery sting in hud.gd). Base
# ids delegate to ShipLayout.is_key_room (its JSON key_room flag + fallback list);
# generated ids read the catalog key_room flag for their EFFECTIVE type — so a
# storage room converted to e.g. an armory becomes a key room too.
func is_key_room(id: String) -> bool:
	if is_generated(id):
		_load_catalog()
		var t: String = String(room(id).get("type", ""))
		return _catalog.get(t, {}).get("key_room", false) == true
	var sl: Node = _ship_layout()
	if sl != null and sl.has_method("is_key_room"):
		return sl.call("is_key_room", id)
	return false


# Returns true when the Bridge has been discovered.
# Source of truth: the explicit _bridge_discovered flag (serialized, set by
# mark_bridge_discovered) OR the live scan of GameState.rooms_discovered.
# Both paths are checked so #133's discovery hook (rooms_discovered scan) and
# the serialized flag both work as expected — no duplicate bool for the same
# state; the flag is additive. Down-floors read this to gate their panel reveal.
func is_bridge_discovered() -> bool:
	if _bridge_discovered:
		return true
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var discovered: Array = gs.get("rooms_discovered") as Array
	_load_catalog()
	for rid in discovered:
		var r: Dictionary = room(String(rid)) as Dictionary
		# Base rooms: type field is set directly.
		var t: String = String(r.get("type", ""))
		if t == "bridge":
			return true
		# Generated rooms: effective type from catalog.
		if is_generated(String(rid)):
			var cat_entry: Dictionary = _catalog.get(t, {}) as Dictionary
			if String(cat_entry.get("id", "")) == "bridge":
				return true
	return false


# Explicitly mark the Bridge as discovered. Called from bridge_console.gd /
# #133's discovery hook. Sets the persistent _bridge_discovered flag so the
# state survives save/load without requiring rooms_discovered to be re-scanned.
func mark_bridge_discovered() -> void:
	_bridge_discovered = true


# Direction-tagged outgoing edges (ShipLayout-compatible: forward + reverse mirrored).
# Both forward edges (with plaque) and reverse edges (with plaque from ShipLayout
# mirror logic, plaque key present for ShipLayout consistency) are returned here.
# This variant is used by ShipLayout consumers (Kino map).
func outgoing_edges(id: String) -> Array:
	if is_generated(id):
		return _mirror_edges(id)
	var sl: Node = _ship_layout()
	if sl != null:
		return sl.call("outgoing_edges", id)
	return []


# room.gd-compatible door edge set: forward edges KEEP plaque; reverse (mirrored)
# edges OMIT the "plaque" key so room.gd's _stamp_door auto-derives the name.
# This reproduces room.gd's old two-loop behavior exactly.
func door_edges(room_id: String) -> Array:
	var all_rooms_data: Array = []
	# Collect forward edges that originate at room_id.
	var forward: Array = _get_forward_edges(room_id)
	# Collect reverse edges: rooms that point TO room_id, mirrored back.
	var reverse: Array = _get_reverse_edges(room_id)
	all_rooms_data.append_array(forward)
	all_rooms_data.append_array(reverse)
	# Inject the stairs return edge for the Floor-2 Observation Deck entry.
	all_rooms_data = _inject_stairs_return(room_id, all_rooms_data)
	# Inject the upper-deck link (obs deck ↔ hydroponics).
	all_rooms_data = _inject_upper_deck_link(room_id, all_rooms_data)
	return all_rooms_data


# Forward edges for room_id from both stores.
func _get_forward_edges(room_id: String) -> Array:
	if is_generated(room_id):
		if _edges.has(room_id):
			return (_edges[room_id] as Array).duplicate(true)
		return []
	# Base room: read from room_connections.json via ShipLayout's loaded data.
	# ShipLayout stores outgoing_edges with BOTH forward and mirrored reverse.
	# We need only the forward declarations (ones declared in room_connections.json
	# as originating from this room). We extract those by looking at what ShipLayout
	# says are "outgoing" edges from this id — all have plaque keys present.
	# ShipLayout.outgoing_edges already has both forward+reverse with plaque filled,
	# but we need only the JSON-declared forward edges for door_edges() forward pass.
	# Strategy: read raw connections.json to get only the declared edges.
	var result: Array = []
	var sl: Node = _ship_layout()
	if sl == null:
		return result
	# ShipLayout doesn't expose raw forward-only edges separately, so load directly.
	var conn: Dictionary = _load_base_connections()
	var raw_edges: Variant = conn.get(room_id, [])
	if not (raw_edges is Array):
		return result
	for e in raw_edges:
		if e is Dictionary:
			result.append((e as Dictionary).duplicate())
	return result


# Reverse edges: find all rooms (base + generated) that declare an edge TO room_id,
# mirror them. Result edges have no "plaque" key (room.gd derives from target name).
func _get_reverse_edges(room_id: String) -> Array:
	var result: Array = []
	# Scan generated edges.
	for from_id in _edges.keys():
		if String(from_id) == room_id:
			continue
		for edge in _edges[from_id] as Array:
			var e: Dictionary = edge
			if String(e.get("to", "")) == room_id:
				var rev: Dictionary = {}
				rev["dir"] = _flip_dir(String(e.get("dir", "")))
				rev["to"] = String(from_id)
				# No "plaque" key — room.gd auto-derives from target.
				result.append(rev)
	# Scan base connections.
	var conn: Dictionary = _load_base_connections()
	for from_id in conn.keys():
		if String(from_id) == room_id:
			continue
		var edges_raw: Variant = conn[from_id]
		if not (edges_raw is Array):
			continue
		for edge in edges_raw as Array:
			if not (edge is Dictionary):
				continue
			var e: Dictionary = edge
			if String(e.get("to", "")) == room_id:
				var rev: Dictionary = {}
				rev["dir"] = _flip_dir(String(e.get("dir", "")))
				rev["to"] = String(from_id)
				# No "plaque" key — room.gd auto-derives.
				result.append(rev)
	return result


# Full mirror of _edges[room_id] (forward + symmetric reverse with plaque).
# Used by outgoing_edges() for Kino map compatibility.
func _mirror_edges(room_id: String) -> Array:
	var result: Array = []
	if _edges.has(room_id):
		for e in _edges[room_id] as Array:
			result.append((e as Dictionary).duplicate())
	# Mirror: any generated edge pointing TO room_id.
	for from_id in _edges.keys():
		if String(from_id) == room_id:
			continue
		for edge in _edges[from_id] as Array:
			var e: Dictionary = edge
			if String(e.get("to", "")) == room_id:
				var rev: Dictionary = {
					"dir": _flip_dir(String(e.get("dir", ""))),
					"to": String(from_id),
					"plaque": String(e.get("plaque", "")),
				}
				result.append(rev)
	return result


# Neighbours for BFS. Uses door_edges() so virtual injections (stairs, upper-deck
# link) are visible to pathfinding — outgoing_edges() only covers stored edges.
func neighbours(id: String) -> Array:
	var edges: Array = door_edges(id)
	var out: Array = []
	for e in edges:
		var d: Dictionary = e
		var n: String = String(d.get("to", ""))
		if n != "" and not out.has(n):
			out.append(n)
	return out


# BFS shortest path (both base and generated rooms).
func path_through_rooms(from_id: String, to_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if from_id == "" or to_id == "":
		return out
	if from_id == to_id:
		out.append(from_id)
		return out
	# NOTE: the "both base rooms" ShipLayout shortcut is intentionally skipped
	# here. When Floor 2 is generated, the upper-deck link creates a cross-floor
	# path (e.g. gate_room → f2_r00 → hydroponics) that ShipLayout cannot see.
	# We always use the full BFS over the combined graph so virtual edges are
	# included. Performance cost is negligible for the room counts in this game.
	# BFS over combined graph.
	var parent: Dictionary = {from_id: ""}
	var queue: Array[String] = [from_id]
	var target_found: bool = false
	while queue.size() > 0:
		var current: String = queue.pop_front()
		if current == to_id:
			target_found = true
			break
		for n in neighbours(current):
			var ns: String = String(n)
			if parent.has(ns):
				continue
			parent[ns] = current
			queue.append(ns)
	if not target_found:
		return out
	var reversed: Array[String] = []
	var cursor: String = to_id
	while cursor != "":
		reversed.append(cursor)
		cursor = String(parent.get(cursor, ""))
	reversed.reverse()
	for r in reversed:
		out.append(r)
	return out


# Next hop toward to_id.
func next_room_toward(from_id: String, to_id: String) -> String:
	var path: PackedStringArray = path_through_rooms(from_id, to_id)
	if path.size() < 2:
		return ""
	return path[1]


# Current floor derived from GameState.current_room_id. Defaults to 1 if room
# unknown (authored spine is floor 0 in JSON but game convention uses 1-based display).
func current_floor() -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return 1
	var room_id: String = String(gs.get("current_room_id") if gs.get("current_room_id") != null else "")
	if room_id == "":
		return 1
	var r: Dictionary = room(room_id)
	if r.is_empty():
		return 1
	return int(r.get("floor", 0)) + 1


# ============================================================
# FLOOR SEMANTIC HELPERS
# ============================================================

# True if floor n is one of the authored floors (always present, never generated).
func _is_authored_floor(n: int) -> bool:
	return AUTHORED_FLOORS.has(n)


# True if floor n can be procedurally generated.
# n==0 is the JSON-internal authored index — excluded.
# Authored floors (1, 2) are excluded (they're stamped in _ready / reset).
# All other integers within [MIN_FLOOR, MAX_FLOOR] are generatable.
func _is_generatable_floor(n: int) -> bool:
	if n == 0:
		return false
	if _is_authored_floor(n):
		return false
	if n < MIN_FLOOR or n > MAX_FLOOR:
		return false
	return true


# ============================================================
# GENERATION CORE
# ============================================================

# Idempotent: if floor n is already generated, return.
# Authored floors (1, 2) are never regenerated.
# Bounds-check: n must be in [MIN_FLOOR, MAX_FLOOR] and not 0 or an authored floor.
func ensure_floor_generated(n: int) -> void:
	if not _is_generatable_floor(n):
		return
	_load_catalog()
	if not _floors.has(n):
		_floors[n] = {
			"unlocked": false,
			"code_known": false,
			"generated": false,
			"rooms": [],
			"specials_placed": 0,
			"cap": 0,
			"seed": 0,
		}
	var floor_rec: Dictionary = _floors[n]
	if floor_rec.get("generated", false):
		return
	_generate_floor(n, floor_rec)


func _generate_floor(n: int, floor_rec: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Deterministic per-floor seed derived from floor index + salt. Using
	# integer arithmetic (no float random) as required by project conventions.
	var seed_val: int = (n * 0x9e3779b9) ^ 0xdeadbeef
	seed_val = seed_val & 0x7fffffff  # keep positive
	floor_rec["seed"] = seed_val
	rng.seed = seed_val

	var cap: int = 12 + (rng.randi() % 9)  # 12..20
	floor_rec["cap"] = cap

	# Origin in JSON grid units for this floor. Large Y offset keeps it visually
	# separate from other floors if ever rendered together.
	var origin_x: int = 0
	var origin_y: int = n * _FLOOR_GRID_STRIDE_Y

	# Room counter for id generation.
	var room_counter: int = 0

	# Track placed rectangles for collision detection.
	# Each entry: {startX, endX, startY, endY, id}
	var placed_rects: Array = []

	# Place entry room.
	# Floor 2: force entry to be the Observation Deck (deliberate narrative choice;
	# reachable via gate-room stairs, not the elevator). Consume it from the
	# special pool so it doesn't appear a second time on any floor.
	var entry_id: String = "f%d_r%02d" % [n, room_counter]
	room_counter += 1
	var entry_w: int = 400
	var entry_h: int = 300
	var entry_type: String = "corridor"
	var entry_name: String = "Corridor"
	var entry_template: String = "corridor-template"
	if n == 2:
		entry_type = "observation_deck"
		entry_name = "Observation Deck"
		entry_template = "quarters-template"  # observation_deck uses quarters-template
		entry_w = 400
		entry_h = 300
		# Consume observation_deck from the special pool so it can't appear again.
		if _special_pool_remaining.has("observation_deck") and int(_special_pool_remaining["observation_deck"]) > 0:
			_special_pool_remaining["observation_deck"] = int(_special_pool_remaining["observation_deck"]) - 1
		floor_rec["specials_placed"] = int(floor_rec.get("specials_placed", 0)) + 1
	var entry_row: Dictionary = _make_room_row(
		entry_id, entry_type, entry_name, entry_template, n,
		origin_x, origin_x + entry_w, origin_y, origin_y + entry_h
	)
	_rooms[entry_id] = entry_row
	placed_rects.append({"startX": origin_x, "endX": origin_x + entry_w,
		"startY": origin_y, "endY": origin_y + entry_h, "id": entry_id})
	floor_rec["rooms"].append(entry_id)

	# Growth queue: [room_id, open_dir_count_remaining]
	# Corridors get >= 2 exits (back edge is 1, so add at least 1 more).
	# Observation Deck / regular rooms get 1-2 additional exits.
	var growth_queue: Array = [[entry_id, 2]]

	while growth_queue.size() > 0 and floor_rec["rooms"].size() < cap:
		var item: Array = growth_queue.pop_front()
		var parent_id: String = String(item[0])
		var exits_remaining: int = int(item[1])

		# Count already-stamped edges from this room.
		var existing_exits: int = (_edges.get(parent_id, []) as Array).size()
		var total_budget: int = 3  # max outgoing edges per room (4th is the back-edge)

		var parent_row: Dictionary = _rooms.get(parent_id, {})
		if parent_row.is_empty():
			continue

		var tries_for_parent: int = 0
		while (existing_exits + (_edges.get(parent_id, []) as Array).size() - existing_exits) < min(exits_remaining, total_budget) and floor_rec["rooms"].size() < cap:
			tries_for_parent += 1
			if tries_for_parent > _MAX_PLACE_RETRIES * 4:
				break

			# Pick a free cardinal direction.
			var dir: String = _pick_free_dir(parent_id, parent_row, rng)
			if dir == "":
				break

			# Choose child type.
			var child_type_id: String = _draw_child_type(floor_rec, rng)
			if child_type_id == "":
				break

			var child_type_row: Dictionary = _catalog.get(child_type_id, {})
			var child_template: String = String(child_type_row.get("template_id", "storage-template"))
			var child_name: String = String(child_type_row.get("display_name", "Room"))

			# Size from table or special size.
			var sz: Dictionary = _FILLER_SIZES.get(child_type_id, _SPECIAL_SIZE)
			var child_w: int = int(sz["w"])
			var child_h: int = int(sz["h"])

			# For corridor type: orient the long axis based on direction.
			if child_type_id == "corridor":
				if dir == "+x" or dir == "-x":
					child_w = 400
					child_h = 120
				else:
					child_w = 120
					child_h = 400

			# Compute child rectangle that ABUTS the parent wall AND OVERLAPS it.
			var child_rect: Dictionary = _compute_child_rect(parent_row, dir, child_w, child_h, rng)
			if child_rect.is_empty():
				continue

			# Check for rectangle collisions with all existing placed rooms EXCEPT
			# the parent — a child is intentionally placed abutting its parent
			# (shared wall, 0 gap), which would false-trigger the gap check.
			var collision_rects: Array = []
			for pr in placed_rects:
				if String((pr as Dictionary).get("id", "")) != parent_id:
					collision_rects.append(pr)
			if _has_collision(child_rect, collision_rects):
				continue

			# Verify the overlap is sufficient for a door alignment.
			var overlap: int = _compute_overlap(parent_row, child_rect, dir)
			if overlap < _MIN_OVERLAP:
				continue

			# All checks pass — place the room.
			var child_id: String = "f%d_r%02d" % [n, room_counter]
			room_counter += 1

			var child_row: Dictionary = _make_room_row(
				child_id, child_type_id, child_name, child_template, n,
				child_rect["startX"], child_rect["endX"],
				child_rect["startY"], child_rect["endY"]
			)
			_rooms[child_id] = child_row
			placed_rects.append({
				"startX": child_rect["startX"], "endX": child_rect["endX"],
				"startY": child_rect["startY"], "endY": child_rect["endY"],
				"id": child_id,
			})
			floor_rec["rooms"].append(child_id)

			# Stamp edge parent -> child.
			_add_gen_edge(parent_id, child_id, dir)

			# Update specials count.
			var cat: String = String(child_type_row.get("category", ""))
			if cat == "special_once" or cat == "special_limited":
				floor_rec["specials_placed"] = int(floor_rec.get("specials_placed", 0)) + 1

			# Enqueue child for further growth.
			var is_corridor: bool = (child_type_id == "corridor")
			var child_exits: int = 2 if is_corridor else (rng.randi() % 2)  # 0 or 1 extra
			if child_exits > 0 and floor_rec["rooms"].size() < cap:
				growth_queue.append([child_id, child_exits])
			# Do NOT break here — let the inner while continue so this parent
			# can fill all its exits_remaining slots in one pass. The condition
			# re-checks _edges[parent_id].size() each iteration, so it stops
			# naturally when the budget is met or the retry ceiling fires.

	floor_rec["generated"] = true
	_floors[n] = floor_rec

	# Guarantee parts budget: ensure the floor has at least enough parts recorded
	# so the player can afford to unlock the NEXT floor. The actual Salvage panels
	# and crates are physical nodes spawned by room.gd; the budget here is metadata
	# that tests and the HUD can read to verify the floor is sufficiently seeded.
	_ensure_parts_budget(n, floor_rec)


# Compute how many parts this floor should guarantee and store in floor_rec.
# The budget covers the cost to unlock floor (n+1) with a margin.
func _ensure_parts_budget(n: int, floor_rec: Dictionary) -> void:
	var next_cost: int = floor_unlock_cost(n + 1)
	var budget: int = (next_cost * PARTS_BUDGET_MARGIN_PCT) / 100
	if budget < next_cost:
		budget = next_cost  # Always at least the bare unlock cost.
	floor_rec["parts_budget"] = budget


# The parts budget for floor n (parts placed via salvage + crates on that floor).
# Used by room.gd and tests to verify the guarantee.
func floor_parts_budget(n: int) -> int:
	if not _floors.has(n):
		return 0
	return int((_floors[n] as Dictionary).get("parts_budget", 0))


# Pick a cardinal direction that this room has not yet used as a forward edge
# AND that also respects the 4-door-max budget.
func _pick_free_dir(room_id: String, room_row: Dictionary, rng: RandomNumberGenerator) -> String:
	# Directions already used as outgoing edges from this room.
	var used_dirs: Array = []
	for e in (_edges.get(room_id, []) as Array):
		var ed: Dictionary = e
		used_dirs.append(String(ed.get("dir", "")))
	# Also check reverse edges pointing back at this room — those walls are occupied.
	# We can't stamp a door on a wall that already has one from a reverse edge.
	# Build a set of blocked walls: reverse edges that COME INTO this room.
	# (The back-edge from the parent will have been added as a reverse edge on child's wall.)
	var all_dirs: Array = ["+x", "-x", "+z", "-z"]
	var candidates: Array = []
	for d in all_dirs:
		if not used_dirs.has(d) and used_dirs.size() < 3:
			candidates.append(d)
	if candidates.is_empty():
		return ""
	# Shuffle via rng.
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	return String(candidates[0])


# Weighted draw for a filler or special child type.
func _draw_child_type(floor_rec: Dictionary, rng: RandomNumberGenerator) -> String:
	var specials_placed: int = int(floor_rec.get("specials_placed", 0))
	var cap: int = int(floor_rec.get("cap", 12))
	var rooms_placed: int = (floor_rec.get("rooms", []) as Array).size()

	# 20% chance to place a special if budget allows and we're past the first 3 rooms.
	if specials_placed < 3 and rooms_placed > 3 and rng.randf() < 0.20:
		var special_id: String = _draw_special(rng)
		if special_id != "":
			return special_id

	# Weighted filler draw.
	var total_weight: int = 0
	var filler_ids: Array = []
	var filler_weights: Array = []
	for entry in _catalog.values():
		var d: Dictionary = entry
		if String(d.get("category", "")) == "filler":
			var w: int = int(d.get("floor_weight", 0))
			if w > 0:
				filler_ids.append(String(d["id"]))
				filler_weights.append(w)
				total_weight += w
	if total_weight == 0:
		return "storage"
	var roll: int = rng.randi() % total_weight
	var accumulated: int = 0
	for i in filler_ids.size():
		accumulated += int(filler_weights[i])
		if roll < accumulated:
			return String(filler_ids[i])
	return "storage"


# Draw a special type without replacement from the pool.
func _draw_special(rng: RandomNumberGenerator) -> String:
	var available: Array = []
	for type_id in _special_pool_remaining.keys():
		if int(_special_pool_remaining[type_id]) > 0:
			available.append(String(type_id))
	if available.is_empty():
		return ""
	var idx: int = rng.randi() % available.size()
	var chosen: String = String(available[idx])
	_special_pool_remaining[chosen] = int(_special_pool_remaining[chosen]) - 1
	return chosen


# Compute child rectangle that abuts the parent wall on `dir` side AND overlaps
# it so _door_along_offset produces hi>lo. Returns {} if computation fails.
func _compute_child_rect(parent: Dictionary, dir: String, child_w: int, child_h: int, rng: RandomNumberGenerator) -> Dictionary:
	var psx: int = int(parent.get("startX", 0))
	var pex: int = int(parent.get("endX", 0))
	var psy: int = int(parent.get("startY", 0))
	var pey: int = int(parent.get("endY", 0))

	# Parent dimensions in JSON units.
	var parent_span_x: int = pex - psx
	var parent_span_y: int = pey - psy

	var child_sx: int = 0
	var child_ex: int = 0
	var child_sy: int = 0
	var child_ey: int = 0

	match dir:
		"+x":
			# Child placed to the right of parent; wall at pex.
			child_sx = pex
			child_ex = pex + child_w
			# Overlap on Y: child must share some of [psy, pey] range.
			var max_jitter: int = max(0, parent_span_y - child_h - _MIN_OVERLAP)
			var jitter: int = 0 if max_jitter <= 0 else (rng.randi() % (max_jitter + 1))
			child_sy = psy + jitter
			child_ey = child_sy + child_h
		"-x":
			child_ex = psx
			child_sx = psx - child_w
			var max_jitter: int = max(0, parent_span_y - child_h - _MIN_OVERLAP)
			var jitter: int = 0 if max_jitter <= 0 else (rng.randi() % (max_jitter + 1))
			child_sy = psy + jitter
			child_ey = child_sy + child_h
		"+z":
			# In JSON coordinates: +z maps to larger startY/endY (south).
			child_sy = pey
			child_ey = pey + child_h
			var max_jitter: int = max(0, parent_span_x - child_w - _MIN_OVERLAP)
			var jitter: int = 0 if max_jitter <= 0 else (rng.randi() % (max_jitter + 1))
			child_sx = psx + jitter
			child_ex = child_sx + child_w
		"-z":
			child_ey = psy
			child_sy = psy - child_h
			var max_jitter: int = max(0, parent_span_x - child_w - _MIN_OVERLAP)
			var jitter: int = 0 if max_jitter <= 0 else (rng.randi() % (max_jitter + 1))
			child_sx = psx + jitter
			child_ex = child_sx + child_w
		_:
			return {}

	return {"startX": child_sx, "endX": child_ex, "startY": child_sy, "endY": child_ey}


# Returns the overlap length (in JSON units) on the shared axis between parent and child.
# For +x/-x doors: overlap is on the Y axis. For +z/-z: on the X axis.
func _compute_overlap(parent: Dictionary, child: Dictionary, dir: String) -> int:
	if dir == "+x" or dir == "-x":
		var lo: int = max(int(parent.get("startY", 0)), int(child.get("startY", 0)))
		var hi: int = min(int(parent.get("endY", 0)), int(child.get("endY", 0)))
		return max(0, hi - lo)
	else:
		var lo: int = max(int(parent.get("startX", 0)), int(child.get("startX", 0)))
		var hi: int = min(int(parent.get("endX", 0)), int(child.get("endX", 0)))
		return max(0, hi - lo)


# Axis-aligned rectangle collision check. Two rects DO NOT collide when they
# are separated by at least _ROOM_GAP on either axis.
func _has_collision(candidate: Dictionary, placed: Array) -> bool:
	var csx: int = int(candidate.get("startX", 0))
	var cex: int = int(candidate.get("endX", 0))
	var csy: int = int(candidate.get("startY", 0))
	var cey: int = int(candidate.get("endY", 0))
	for p in placed:
		var d: Dictionary = p
		var psx: int = int(d.get("startX", 0))
		var pex: int = int(d.get("endX", 0))
		var psy: int = int(d.get("startY", 0))
		var pey: int = int(d.get("endY", 0))
		# Separated on X or Y by at least _ROOM_GAP? If not, they collide.
		var sep_x: bool = (cex + _ROOM_GAP <= psx) or (pex + _ROOM_GAP <= csx)
		var sep_y: bool = (cey + _ROOM_GAP <= psy) or (pey + _ROOM_GAP <= csy)
		if not sep_x and not sep_y:
			return true
	return false


# Build a room row in the same shape as ship_layout.json rows.
func _make_room_row(id: String, type_id: String, display_name: String, template_id: String,
		floor_n: int, sx: int, ex: int, sy: int, ey: int) -> Dictionary:
	return {
		"id": id,
		"template_id": template_id,
		"layout_id": "destiny_generated",
		"type": type_id,
		"name": display_name,
		"description": "",
		"startX": sx,
		"endX": ex,
		"startY": sy,
		"endY": ey,
		"floor": floor_n,
		"width": ex - sx,
		"height": ey - sy,
		"found": false,
		"locked": false,
		"explored": false,
		"status": "ok",
	}


# Add a forward edge declaration.
func _add_gen_edge(from_id: String, to_id: String, dir: String) -> void:
	if not _edges.has(from_id):
		_edges[from_id] = []
	var arr: Array = _edges[from_id]
	# Avoid duplicates.
	for e in arr:
		var ed: Dictionary = e
		if String(ed.get("to", "")) == to_id and String(ed.get("dir", "")) == dir:
			return
	# Use destination display name as plaque.
	var dest_row: Dictionary = _rooms.get(to_id, {})
	var plaque: String = String(dest_row.get("name", to_id))
	arr.append({"dir": dir, "to": to_id, "plaque": plaque})


# ============================================================
# PHASE B — FLOOR UNLOCK / ACCESS CODE / ROOM ASSIGNMENT
# ============================================================

# Escalating cost (in FLOOR_UNLOCK_ITEM units) to unlock floor n.
# Uses absi(n) so down-floors (negative n) yield positive costs — SL-1=5, SL-2=10…
# Never passes a negative cost to Inventory.remove_item.
func floor_unlock_cost(n: int) -> int:
	return FLOOR_UNLOCK_COST_BASE * absi(n)


# True when the player has discovered floor n's access code.
func is_floor_code_known(n: int) -> bool:
	if not _floors.has(n):
		return false
	return (_floors[n] as Dictionary).get("code_known", false)


# True when floor n is unlocked (playable).
func is_floor_unlocked(n: int) -> bool:
	if _is_authored_floor(n):
		return true  # Authored floors (1, 2) are always unlocked.
	if not _floors.has(n):
		return false
	return (_floors[n] as Dictionary).get("unlocked", false)


# Mark floor n's access code as known (called by floor_code_terminal.gd).
# Ensures the floor record exists so the panel can mark it without generating.
func mark_floor_code_known(n: int) -> void:
	if _is_authored_floor(n):
		return  # Authored floors need no code (floor 1 always free; floor 2 via stairs).
	if not _floors.has(n):
		_floors[n] = {
			"unlocked": false,
			"code_known": false,
			"generated": false,
			"rooms": [],
			"specials_placed": 0,
			"cap": 0,
			"seed": 0,
		}
	(_floors[n] as Dictionary)["code_known"] = true


# Attempt to unlock floor n. Returns true on success, false on failure.
# Failure reasons: code not known, insufficient resources, floor already unlocked.
# On success: spends the item cost via Inventory, generates the floor, sets unlocked.
func unlock_floor(n: int) -> bool:
	if _is_authored_floor(n):
		return true  # Authored floors (1, 2) are always unlocked.
	if is_floor_unlocked(n):
		return true  # Already unlocked — success (idempotent).
	# Elevator must be powered before the floor-select mechanism works.
	# Authored floors bypass this via their default unlocked=true state above.
	if not _elevator_powered:
		return false  # Elevator offline — restore power first.
	if not is_floor_code_known(n):
		return false  # Code not found yet.
	var cost: int = floor_unlock_cost(n)
	# cost is always positive (absi(n) * BASE); safe to pass to remove_item.
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false  # No inventory system — cannot spend.
	var held: int = inv.call("count", FLOOR_UNLOCK_ITEM)
	if held < cost:
		return false  # Insufficient resources.
	# Spend the cost.
	inv.call("remove_item", FLOOR_UNLOCK_ITEM, cost, "floor_unlock_%d" % n)
	# Generate the floor (idempotent if already generated from a save).
	ensure_floor_generated(n)
	(_floors[n] as Dictionary)["unlocked"] = true
	return true


# The room_id of the elevator-landing room for floor n.
# Floor 1 → authored elevator room. Generated floors (2+, and -1, -2…) → "f{n}_r00".
# Note: "f-1_r00" is a valid Godot String — no special handling needed for negatives.
func floor_entry_room(n: int) -> String:
	if n == 1:
		return "elevator_room_floor_1"
	# The entry corridor is always the first room placed (index 0, see _generate_floor).
	# For negative n: "f%d_r00" % -1 → "f-1_r00" — valid, no collision with positive floors.
	return "f%d_r00" % n


# Deterministic room_id in floor n-1 where floor n's access code terminal lives.
# Uses the floor n seed to pick from the available rooms; for floor 2 the seed
# picks from ShipLayout base rooms (authored) — we fix it to a stable authored room.
func floor_code_terminal_room(n: int) -> String:
	if n <= 2:
		# Floor 1 (base) rooms — seed the terminal in the control_interface_room
		# (a plausible spot for a computer terminal with floor access data).
		return "control_interface_room"
	# Generated floor n-1: pick the first non-corridor room (index 1+).
	var floor_rec: Dictionary = _floors.get(n - 1, {})
	var rooms: Array = floor_rec.get("rooms", [])
	if rooms.size() > 1:
		return String(rooms[1])  # Second room (first non-entry corridor).
	if rooms.size() > 0:
		return String(rooms[0])
	return ""


# ============================================================
# STAIRS EDGE — gate_room ↔ Floor-2 Observation Deck
# ============================================================
#
# The stair connection is an always-open vertical link that bypasses the code/
# parts gate. It is exposed as a virtual edge so:
#   • door_edges(obs_entry_id) includes a return edge to "gate_room" (direction
#     "stairs"), letting room.gd stamp a door back to the gate room.
#   • gate_room.gd calls floor2_obs_entry_id() to get the destination room id
#     and stamps its own transition door at the stair-top landing.
#
# The "stairs" direction is remapped to "-z" when room.gd calls _stamp_door,
# exactly like the "elevator" direction remap — so the door ends up on the -Z
# wall of the Observation Deck (the back wall facing away from the stair-top).

# Room id of the Floor-2 entry (Observation Deck). Requires floor 2 to have
# been generated; returns "" before generation.
func floor2_obs_entry_id() -> String:
	# Entry is always f2_r00 (first room placed in _generate_floor for n=2).
	# ensure_floor_generated(2) must have been called first.
	if _floors.has(2) and (_floors[2] as Dictionary).get("generated", false):
		return "f2_r00"
	return ""


# Ensure floor 2 exists and return the obs-deck entry id. Generates on demand.
func get_or_generate_floor2_entry() -> String:
	ensure_floor_generated(2)
	return floor2_obs_entry_id()


# True when the stairs link is active (floor 2 generated, obs-deck entry placed).
func stairs_link_active() -> bool:
	return floor2_obs_entry_id() != ""


# Returns the stairs virtual edge for door_edges() to inject into the obs-deck
# entry room's edge list. The "stairs" dir is remapped to "-z" by room.gd
# (same pattern as elevator → -z). plaque deliberately absent (room.gd derives
# from target name = "Gate Room").
func _stairs_return_edge() -> Dictionary:
	return {"dir": STAIRS_DIR, "to": "gate_room"}


# Override door_edges to include the gate_room ↔ Floor-2 stairs edges.
# Two virtual edges are injected (routing only — gate_room.gd stamps its own
# physical door; room.gd does not build gate_room, so no double-stamp occurs):
#   • gate_room side:  forward edge gate_room → f2_r00, dir=STAIRS_DIR, with plaque.
#                      This makes neighbours("gate_room") include f2_r00 so BFS
#                      can route gate_room → f2_r00 → hydroponics via stairs, not
#                      just via elevator_north → elevator_room_floor_1.
#   • f2_r00 side:     return edge f2_r00 → gate_room, dir=STAIRS_DIR, no plaque
#                      (room.gd derives the name from "gate_room").
# Both are kept out of _edges so the door-overlap assertion ignores them.
func _inject_stairs_return(room_id: String, edges: Array) -> Array:
	var entry_id: String = floor2_obs_entry_id()
	if entry_id == "":
		return edges  # Floor 2 not generated yet — nothing to inject.

	# Gate-room side: forward edge toward the obs-deck (for BFS routing).
	if room_id == "gate_room":
		for e in edges:
			var d: Dictionary = e
			if String(d.get("to", "")) == entry_id and String(d.get("dir", "")) == STAIRS_DIR:
				return edges  # Already present.
		var out: Array = edges.duplicate(true)
		out.append({"dir": STAIRS_DIR, "to": entry_id, "plaque": "Upper Deck — Observation"})
		return out

	# Obs-deck side: return edge back to gate_room (room.gd stamps the door here).
	if room_id == entry_id:
		for e in edges:
			var d: Dictionary = e
			if String(d.get("to", "")) == "gate_room" and String(d.get("dir", "")) == STAIRS_DIR:
				return edges  # Already present.
		var out: Array = edges.duplicate(true)
		out.append(_stairs_return_edge())
		return out

	return edges


# ============================================================
# UPPER-DECK LINK — f2_r00 ↔ hydroponics (on-foot via stairs)
# ============================================================
#
# Injects a virtual edge on BOTH endpoints so room.gd stamps doors on each side
# without any special case logic in the room scripts:
#   • f2_r00 side:      dir = UPPER_DECK_DIR        → room.gd remaps to +z
#   • hydroponics side: dir = UPPER_DECK_RETURN_DIR → room.gd remaps to +z
#
# Called from door_edges() for both rooms. The edge is virtual (never stored in
# _edges), preserving the save contract and the generation's forward-edge tracking.

func _inject_upper_deck_link(room_id: String, edges: Array) -> Array:
	var entry_id: String = floor2_obs_entry_id()
	if entry_id == "":
		return edges  # Floor 2 not yet generated — no link to inject.

	if room_id == entry_id:
		# Obs-deck side: forward edge to hydroponics with a plaque so the player
		# sees "Hydroponics" on the door in the Observation Deck.
		for e in edges:
			var d: Dictionary = e
			if String(d.get("dir", "")) == UPPER_DECK_DIR and String(d.get("to", "")) == UPPER_DECK_TARGET:
				return edges  # Already injected.
		var out: Array = edges.duplicate(true)
		out.append({"dir": UPPER_DECK_DIR, "to": UPPER_DECK_TARGET, "plaque": "Hydroponics"})
		return out

	if room_id == UPPER_DECK_TARGET:
		# Hydroponics side: reverse edge back to obs deck. No "plaque" key so
		# room.gd auto-derives the label from the target room name ("Observation Deck").
		for e in edges:
			var d: Dictionary = e
			if String(d.get("dir", "")) == UPPER_DECK_RETURN_DIR and String(d.get("to", "")) == entry_id:
				return edges  # Already injected.
		var out: Array = edges.duplicate(true)
		out.append({"dir": UPPER_DECK_RETURN_DIR, "to": entry_id})
		return out

	return edges


# Assign a function to a generated storage room. Spends ROOM_ASSIGN_COST parts.
# Returns true on success. The room's template_id and type are updated in _rooms.
func assign_function(room_id: String, fn_type_id: String) -> bool:
	if not is_generated(room_id):
		return false  # Only generated rooms can be assigned.
	var row: Dictionary = _rooms.get(room_id, {})
	if row.is_empty():
		return false
	# Only storage-type rooms (unassigned) can be converted.
	var current_type: String = String(row.get("type", ""))
	if current_type != "storage":
		return false
	# Validate the target type is in the assignable catalog category.
	_load_catalog()
	var type_row: Dictionary = _catalog.get(fn_type_id, {})
	if type_row.is_empty():
		return false
	if String(type_row.get("category", "")) != "assignable":
		return false
	# Spend the assignment cost.
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	var held: int = inv.call("count", FLOOR_UNLOCK_ITEM)
	if held < ROOM_ASSIGN_COST:
		return false
	inv.call("remove_item", FLOOR_UNLOCK_ITEM, ROOM_ASSIGN_COST, "room_assign_%s" % room_id)
	# Record the assignment.
	_floor_assignments[room_id] = fn_type_id
	# Update the room row so room.gd reads the new template.
	var new_template: String = String(type_row.get("template_id", "storage-template"))
	var new_name: String = String(type_row.get("display_name", fn_type_id))
	(_rooms[room_id] as Dictionary)["type"] = fn_type_id
	(_rooms[room_id] as Dictionary)["template_id"] = new_template
	(_rooms[room_id] as Dictionary)["name"] = new_name
	return true


# Current assignment for a generated room ("" if none / not a generated room).
func assigned_function(room_id: String) -> String:
	return String(_floor_assignments.get(room_id, ""))


# All catalog types marked assignable == true.
func assignable_types() -> Array:
	_load_catalog()
	var out: Array = []
	for entry in _catalog.values():
		var d: Dictionary = entry
		if d.get("assignable", false) == true:
			out.append(d.duplicate())
	return out


# ============================================================
# HELPERS
# ============================================================

static func _flip_dir(d: String) -> String:
	match d:
		"+x": return "-x"
		"-x": return "+x"
		"+z": return "-z"
		"-z": return "+z"
		_:    return d


func _ship_layout() -> Node:
	return get_node_or_null("/root/ShipLayout")


# Cache for base connections (loaded once, never modified).
var _base_connections_cache: Dictionary = {}
var _base_connections_loaded: bool = false

func _load_base_connections() -> Dictionary:
	if _base_connections_loaded:
		return _base_connections_cache
	var f: FileAccess = FileAccess.open("res://data/room_connections.json", FileAccess.READ)
	if f == null:
		_base_connections_loaded = true
		return _base_connections_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_base_connections_cache = parsed
	_base_connections_loaded = true
	return _base_connections_cache


# ============================================================
# ELEVATOR POWER — issue #132
# ============================================================
#
# The elevator starts unpowered. The player must:
#   1. Hold the required fuses (ELEVATOR_FUSE_REQUIREMENT).
#   2. Complete the mini-game (solve_elevator_minigame() — deterministic stub now,
#      seam for a real puzzle later).
#   3. Call restore_elevator_power() which verifies both guards, consumes fuses
#      atomically, sets _elevator_powered, and emits elevator_power_changed.
#
# unlock_floor(n) is gated on _elevator_powered (after idempotency checks so
# Floor 1/2 remain unaffected). mark_floor_code_known and Floor-2 stairs
# reachability are intentionally NOT gated.

func is_elevator_powered() -> bool:
	return _elevator_powered


func is_elevator_minigame_solved() -> bool:
	return _minigame_solved


# Returns true if the player holds ALL fuses in ELEVATOR_FUSE_REQUIREMENT.
func has_elevator_fuses() -> bool:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	for item_id: String in ELEVATOR_FUSE_REQUIREMENT.keys():
		var required: int = int(ELEVATOR_FUSE_REQUIREMENT[item_id])
		var held: int = int(inv.call("count", item_id))
		if held < required:
			return false
	return true


# Stub mini-game — sets _minigame_solved deterministically.
# The real puzzle later calls this same method on success, so the seam is stable.
func solve_elevator_minigame() -> void:
	_minigame_solved = true


# Attempt to restore elevator power.
# Guards: fuses present + mini-game solved. On success: consumes fuses atomically,
# sets _elevator_powered = true, emits elevator_power_changed. Idempotent.
func restore_elevator_power() -> bool:
	if _elevator_powered:
		return true  # Already powered — idempotent.
	if not _minigame_solved:
		return false  # Mini-game not yet solved.
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	# Verify fuses atomically before consuming anything.
	if not has_elevator_fuses():
		return false
	# Consume fuses.
	for item_id: String in ELEVATOR_FUSE_REQUIREMENT.keys():
		var required: int = int(ELEVATOR_FUSE_REQUIREMENT[item_id])
		inv.call("remove_item", item_id, required, "elevator_power_restore")
	_elevator_powered = true
	elevator_power_changed.emit(true)
	return true


# ============================================================
# SAVE CONTRACT
# ============================================================

func serialize() -> Dictionary:
	return {
		"floors": _floors.duplicate(true),
		"rooms": _rooms.duplicate(true),
		"edges": _edges.duplicate(true),
		"special_pool_remaining": _special_pool_remaining.duplicate(true),
		"floor_assignments": _floor_assignments.duplicate(true),
		"elevator_powered": _elevator_powered,
		"minigame_solved": _minigame_solved,
		"bridge_discovered": _bridge_discovered,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	if data.has("floors") and data["floors"] is Dictionary:
		# CRITICAL: JSON.stringify turns int keys into strings on disk.
		# JSON.parse_string restores them as strings, so after a real disk
		# save/load _floors.has(2) (int) would be FALSE.  Normalize here so
		# int(-1)→-1 and int("2")→2 both work — covers in-memory and disk paths.
		_floors.clear()
		for k in (data["floors"] as Dictionary).keys():
			_floors[int(k)] = ((data["floors"] as Dictionary)[k] as Dictionary).duplicate(true)
	if data.has("rooms") and data["rooms"] is Dictionary:
		_rooms = (data["rooms"] as Dictionary).duplicate(true)
	if data.has("edges") and data["edges"] is Dictionary:
		_edges = (data["edges"] as Dictionary).duplicate(true)
	if data.has("special_pool_remaining") and data["special_pool_remaining"] is Dictionary:
		_special_pool_remaining = (data["special_pool_remaining"] as Dictionary).duplicate(true)
	if data.has("floor_assignments") and data["floor_assignments"] is Dictionary:
		_floor_assignments = (data["floor_assignments"] as Dictionary).duplicate(true)
	# Absent key → false (starts unpowered / undiscovered). No SAVE_VERSION bump needed.
	_elevator_powered = data.get("elevator_powered", false) == true
	_minigame_solved  = data.get("minigame_solved", false) == true
	_bridge_discovered = data.get("bridge_discovered", false) == true


func reset() -> void:
	_floors.clear()
	_rooms.clear()
	_edges.clear()
	_floor_assignments.clear()
	_elevator_powered = false
	_minigame_solved  = false
	_bridge_discovered = false
	# Re-seed pool from catalog.
	_seed_special_pool()
	# Restore default floor 1 entry.
	_floors[1] = {
		"unlocked": true,
		"code_known": false,
		"generated": false,
		"rooms": [],
		"specials_placed": 0,
		"cap": 0,
		"seed": 0,
	}
	# Floor 2 is always free (gate-room stairs bypass the code/parts gate).
	_floors[2] = {
		"unlocked": true,
		"code_known": true,
		"generated": false,
		"rooms": [],
		"specials_placed": 0,
		"cap": 0,
		"seed": 0,
	}
