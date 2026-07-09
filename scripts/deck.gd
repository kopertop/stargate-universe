extends Node3D

# Merged-deck scene: EVERY room on one floor of Destiny, built at its absolute
# ship-plan position in a single navigable scene. Doors between rooms are
# physical (open/close in place, state persisted in ShipState) instead of the
# classic one-room-per-scene transitions; corridors are walked, not loaded.
#
# What stays a scene transition:
#   - the artisan gate room (scenes/gate_room.tscn) via the east connector
#   - the inter-deck elevator pair (deck 0 ↔ deck 1)
#
# room.tscn + room.gd remain the classic flow (E1 story beats + tests run
# there). This scene is the merged-floor gameplay core those beats migrate to
# — see design/gdd/ship-building-mode.md → Migration.
#
# Run standalone (F6) to preview `floor_index`, or launch the game with
# `--decks` to route all door transitions through here.

const DOOR_SCENE: PackedScene = preload("res://objects/door.tscn")
const RoomBuilderRef: Script = preload("res://scripts/room_builder.gd")
const RoomConsoleScript: Script = preload("res://scripts/room_console.gd")
const ShipSystemsPanelScript: Script = preload("res://scripts/ship_systems_panel.gd")
const PowerConsoleScript: Script = preload("res://scripts/power_console.gd")

# Player-position → room resolution cadence (seconds). 20 rect tests every
# 0.3 s is noise-level; signals stay event-driven everywhere else.
const ROOM_TRACK_INTERVAL: float = 0.3
# Structural damage (%) above which a room gets the hazard dressing.
const DAMAGE_OVERLAY_THRESHOLD: float = 30.0
# Arrival markers sit this far inside the room from their door.
const MARKER_INSET: float = 1.2
# Room consoles sit this far off their wall.
const CONSOLE_WALL_INSET: float = 1.1

@export var floor_index: int = 0

@onready var world: Node3D = $World
@onready var markers: Node3D = $Markers
@onready var player: Node3D = $Player
@onready var view: Node3D = $View

var _room_roots: Dictionary = {}        # room_id -> Node3D at the room's plan centre
var _openings_by_room: Dictionary = {}  # room_id -> Array[opening dicts] (RoomBuilder format)
var _track_accum: float = 0.0
var _floor_rooms: Array = []
# Lift doors spawn locked while power is down. The classic flow re-evaluates
# locks on every scene load; a merged deck never reloads, so the tracking
# tick unlocks these live once GameState.elevator_repaired flips.
var _lift_doors: Array[Node] = []


func _ready() -> void:
	# Running the deck IS opting into the merged flow — covers F6 previews,
	# --decks launches, and resumed deck saves alike (door.gd routes by it).
	ShipState.merged_decks_enabled = true

	var arrival_room: String = GameState.next_room_id
	GameState.next_room_id = ""
	if arrival_room != "":
		var row: Dictionary = ShipLayout.room(arrival_room)
		if not row.is_empty():
			floor_index = int(row.get("floor", floor_index))

	_floor_rooms = ShipLayout.rooms_on_floor(floor_index).filter(
		func(r: Dictionary) -> bool: return String(r["id"]) != "gate_room")
	_collect_openings()
	_build_rooms()
	_stamp_doors()
	_spawn_room_consoles()
	_spawn_power_console()
	for room: Dictionary in _floor_rooms:
		_apply_module_visuals(String(room["id"]))
		_refresh_damage_overlay(String(room["id"]))
	ShipState.module_built.connect(_on_module_built)
	ShipState.room_changed.connect(_on_room_state_changed)

	_place_player(arrival_room)
	if arrival_room != "":
		GameState.discover_room(arrival_room)
		GameState.set_current_room(arrival_room)
	GameState.current_scene_path = "res://scenes/deck.tscn"


# Control-room consoles call this (control_console.gd probes for it) — the
# deck flavour of "use control terminal" is the ship-systems door/room panel.
func open_ship_systems_panel() -> void:
	var panel: CanvasLayer = ShipSystemsPanelScript.new()
	get_tree().root.add_child(panel)


# ---- geometry -----------------------------------------------------------------

func _is_deck_room(room_id: String) -> bool:
	return _room_roots.has(room_id) or _floor_rooms.any(
		func(r: Dictionary) -> bool: return String(r["id"]) == room_id)


# Wall openings per room, derived from the connection graph: every same-floor
# adjacent edge cuts a doorway in BOTH rooms' facing walls. Gate-room and
# elevator edges keep SOLID walls — their doors are scene transitions sitting
# flush against the wall (classic room.tscn look; no void behind the cut).
func _collect_openings() -> void:
	for room: Dictionary in _floor_rooms:
		_openings_by_room[String(room["id"])] = []
	for pair: Dictionary in ShipLayout.door_pairs():
		var dir: String = String(pair["dir"])
		if dir == "elevator":
			continue
		var a: String = String(pair["a"])
		var b: String = String(pair["b"])
		if a == "gate_room" or b == "gate_room":
			continue
		if not (_is_deck_room(a) and _is_deck_room(b)):
			continue
		# Detached-but-connected pairs (bad data) keep solid walls; their doors
		# fall back to scene transitions in _stamp_doors.
		if not _pair_adjacent(a, b, dir):
			continue
		_add_opening(a, b, dir)
		_add_opening(b, a, _flip_dir(dir))


# True when the two rooms genuinely share a wall along `dir` from a: matching
# boundary planes AND enough rect overlap to fit a doorway cut.
func _pair_adjacent(a: String, b: String, dir: String) -> bool:
	var ra: Dictionary = ShipLayout.room(a)
	var rb: Dictionary = ShipLayout.room(b)
	if ra.is_empty() or rb.is_empty():
		return false
	var plane_ok: bool = false
	var lo: float = 0.0
	var hi: float = 0.0
	match dir:
		"+x":
			plane_ok = is_equal_approx(float(ra["endX"]), float(rb["startX"]))
			lo = maxf(float(ra["startY"]), float(rb["startY"]))
			hi = minf(float(ra["endY"]), float(rb["endY"]))
		"-x":
			plane_ok = is_equal_approx(float(ra["startX"]), float(rb["endX"]))
			lo = maxf(float(ra["startY"]), float(rb["startY"]))
			hi = minf(float(ra["endY"]), float(rb["endY"]))
		"+z":
			plane_ok = is_equal_approx(float(ra["endY"]), float(rb["startY"]))
			lo = maxf(float(ra["startX"]), float(rb["startX"]))
			hi = minf(float(ra["endX"]), float(rb["endX"]))
		"-z":
			plane_ok = is_equal_approx(float(ra["startY"]), float(rb["endY"]))
			lo = maxf(float(ra["startX"]), float(rb["startX"]))
			hi = minf(float(ra["endX"]), float(rb["endX"]))
		_:
			return false
	return plane_ok and (hi - lo) * ShipLayout.SCALE >= RoomBuilderRef.DOOR_OPENING_WIDTH


func _add_opening(room_id: String, other_id: String, dir: String) -> void:
	if not _openings_by_room.has(room_id):
		return
	(_openings_by_room[room_id] as Array).append({
		"dir": dir,
		"along": _door_along_offset(room_id, other_id, dir),
	})


func _build_rooms() -> void:
	for room: Dictionary in _floor_rooms:
		var room_id: String = String(room["id"])
		var root: Node3D = Node3D.new()
		root.name = "Room_%s" % room_id
		root.position = _room_centre(room_id)
		world.add_child(root)
		_room_roots[room_id] = root
		RoomBuilderRef.build_merged(root, room, _openings_by_room.get(room_id, []) as Array)


func _room_centre(room_id: String) -> Vector3:
	var c: Vector2 = ShipLayout.grid_centre(room_id)
	return Vector3(c.x * ShipLayout.SCALE, 0.0, c.y * ShipLayout.SCALE)


# Overlap-midpoint offset along `dir`'s wall, in metres relative to the room
# centre — same math as room.gd::_door_along_offset, world-rect based.
func _door_along_offset(room_id: String, other_id: String, dir: String) -> float:
	var mine: Dictionary = ShipLayout.room(room_id)
	var other: Dictionary = ShipLayout.room(other_id)
	if mine.is_empty() or other.is_empty():
		return 0.0
	var lo: float
	var hi: float
	var my_centre: float
	if dir == "+x" or dir == "-x":
		lo = maxf(float(mine["startY"]), float(other["startY"]))
		hi = minf(float(mine["endY"]), float(other["endY"]))
		my_centre = (float(mine["startY"]) + float(mine["endY"])) * 0.5
	else:
		lo = maxf(float(mine["startX"]), float(other["startX"]))
		hi = minf(float(mine["endX"]), float(other["endX"]))
		my_centre = (float(mine["startX"]) + float(mine["endX"])) * 0.5
	if hi <= lo:
		return 0.0
	return ((lo + hi) * 0.5 - my_centre) * ShipLayout.SCALE


static func _flip_dir(d: String) -> String:
	match d:
		"+x": return "-x"
		"-x": return "+x"
		"+z": return "-z"
		"-z": return "+z"
		_:    return d


# ---- doors ---------------------------------------------------------------------

func _stamp_doors() -> void:
	for pair: Dictionary in ShipLayout.door_pairs():
		var a: String = String(pair["a"])
		var b: String = String(pair["b"])
		var dir: String = String(pair["dir"])
		if dir == "elevator":
			if _is_deck_room(a):
				_stamp_lift_door(a, b)
			if _is_deck_room(b):
				_stamp_lift_door(b, a)
			continue
		if a == "gate_room" and _is_deck_room(b):
			_stamp_gate_transition_door(b, _flip_dir(dir))
			continue
		if b == "gate_room" and _is_deck_room(a):
			_stamp_gate_transition_door(a, dir)
			continue
		if _is_deck_room(a) and _is_deck_room(b):
			if _pair_adjacent(a, b, dir):
				_stamp_physical_door(a, b, dir, String(pair["plaque"]))
			else:
				# Connected but not touching (data gap): keep the classic
				# transition-door behaviour on both sides — routing re-enters
				# this deck at the far room's marker.
				_stamp_detached_pair_door(a, b, dir, String(pair["plaque"]))
				_stamp_detached_pair_door(b, a, _flip_dir(dir), String(pair["plaque"]))


# One shared physical door on the boundary between two merged rooms, keyed
# into ShipState so its open/closed/locked state persists and the console can
# drive it remotely. Arrival markers are stamped on both sides for the
# cross-scene entries (gate room / elevator) that land near this door.
func _stamp_physical_door(a: String, b: String, dir: String, plaque: String) -> void:
	var pos: Vector3 = _boundary_door_point(a, b, dir)
	var yaw: float = _yaw_for_dir(dir)
	var door_id: String = GameState.door_key(a, b)
	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = yaw
	door.set("physical_mode", true)
	door.set("door_id", door_id)
	door.set("source_room_id", a)
	door.set("target_room_id", b)
	if plaque != "":
		door.set("plaque_label", plaque)
	door.set("open_prompt", "Open door")
	door.add_to_group("interactable")
	add_child(door)

	var dir_vec: Vector3 = _dir_vector(dir)
	# Into room a = opposite of a→b; into room b = along a→b.
	_stamp_marker("Deck_%s_From_%s" % [a, b], pos - dir_vec * MARKER_INSET, yaw + PI)
	_stamp_marker("Deck_%s_From_%s" % [b, a], pos + dir_vec * MARKER_INSET, yaw)


# Inter-deck lift: a scene-transition door on the elevator room's -Z wall
# (matches room.gd's elevator convention), locked until main power is back.
func _stamp_lift_door(room_id: String, other_id: String) -> void:
	var room: Dictionary = ShipLayout.room(room_id)
	var half_z: float = float(room.get("height", 200)) * ShipLayout.SCALE * 0.5
	var pos: Vector3 = _room_centre(room_id) + Vector3(0.0, 0.0, -half_z)
	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = 0.0
	door.set("source_room_id", room_id)
	door.set("target_room_id", other_id)
	door.set("plaque_label", "Upper Deck" if floor_index == 0 else "Main Deck")
	door.set("transition_prompt", "Take the lift")
	if not GameState.elevator_repaired:
		door.set("locked", true)
		door.set("lock_message", "LOCKED — power offline. Restore power at the Engineering Bay (south of cr corridor).")
		_lift_doors.append(door)
	door.add_to_group("interactable")
	add_child(door)
	_stamp_marker("Deck_%s_From_%s" % [room_id, other_id], pos + Vector3(0.0, 0.0, MARKER_INSET), PI)


# Wall-centre transition door for a connected-but-detached pair. Behaves like
# the classic room.tscn doors: E walks you through a fade into the same deck
# scene, arriving at the far room.
func _stamp_detached_pair_door(room_id: String, other_id: String, dir: String, plaque: String) -> void:
	var room: Dictionary = ShipLayout.room(room_id)
	if room.is_empty():
		return
	var half_x: float = float(room.get("width", 200)) * ShipLayout.SCALE * 0.5
	var half_z: float = float(room.get("height", 200)) * ShipLayout.SCALE * 0.5
	var pos: Vector3 = _room_centre(room_id)
	match dir:
		"+x": pos += Vector3(half_x, 0.0, 0.0)
		"-x": pos += Vector3(-half_x, 0.0, 0.0)
		"+z": pos += Vector3(0.0, 0.0, half_z)
		"-z": pos += Vector3(0.0, 0.0, -half_z)
	var yaw: float = _yaw_for_dir(dir)
	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = yaw
	door.set("source_room_id", room_id)
	door.set("target_room_id", other_id)
	if plaque != "":
		door.set("plaque_label", plaque)
	door.add_to_group("interactable")
	add_child(door)
	_stamp_marker("Deck_%s_From_%s" % [room_id, other_id],
		pos - _dir_vector(dir) * MARKER_INSET, yaw + PI)


# Transition door into the artisan gate room, flush against the connector's
# solid wall (classic room.tscn presentation). Arrivals FROM the gate room
# land at the mirrored deck marker beside it.
func _stamp_gate_transition_door(room_id: String, dir: String) -> void:
	var room: Dictionary = ShipLayout.room(room_id)
	if room.is_empty():
		return
	var pos: Vector3 = _boundary_door_point(room_id, "gate_room", dir)
	var yaw: float = _yaw_for_dir(dir)
	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = yaw
	door.set("source_room_id", room_id)
	door.set("target_room_id", "gate_room")
	# gate_room.gd authored this reverse-edge landing marker explicitly.
	door.set("target_spawn", "FromStargateCorridorEastConnector")
	door.set("plaque_label", "Gate Room")
	door.set("transition_prompt", "Step through to the Gate Room")
	door.add_to_group("interactable")
	add_child(door)
	_stamp_marker("Deck_%s_From_%s" % [room_id, "gate_room"],
		pos - _dir_vector(dir) * MARKER_INSET, yaw + PI)


# World-space door point on the shared boundary between two rooms: the
# boundary plane along `dir` from room a, at the rects' overlap midpoint.
func _boundary_door_point(a: String, b: String, dir: String) -> Vector3:
	var ra: Dictionary = ShipLayout.room(a)
	var centre: Vector3 = _room_centre(a)
	var half_x: float = float(ra.get("width", 200)) * ShipLayout.SCALE * 0.5
	var half_z: float = float(ra.get("height", 200)) * ShipLayout.SCALE * 0.5
	var along: float = _door_along_offset(a, b, dir)
	match dir:
		"+x":
			return centre + Vector3(half_x, 0.0, along)
		"-x":
			return centre + Vector3(-half_x, 0.0, along)
		"+z":
			return centre + Vector3(along, 0.0, half_z)
		"-z":
			return centre + Vector3(along, 0.0, -half_z)
	return centre


static func _yaw_for_dir(dir: String) -> float:
	match dir:
		"+x": return -PI * 0.5
		"-x": return PI * 0.5
		"+z": return PI
		_:    return 0.0


static func _dir_vector(dir: String) -> Vector3:
	match dir:
		"+x": return Vector3.RIGHT
		"-x": return Vector3.LEFT
		"+z": return Vector3.BACK
		_:    return Vector3.FORWARD


func _stamp_marker(marker_name: String, pos: Vector3, yaw: float) -> void:
	if markers.has_node(NodePath(marker_name)):
		return
	var m: Marker3D = Marker3D.new()
	m.name = marker_name
	m.position = Vector3(pos.x, 0.0, pos.z)
	m.rotation.y = yaw
	markers.add_child(m)


# ---- room consoles ---------------------------------------------------------------

# Every buildable room gets a wall-mounted room-systems console (the build
# interface). Wall picked to keep clear of doorway cuts.
func _spawn_room_consoles() -> void:
	for room: Dictionary in _floor_rooms:
		var room_id: String = String(room["id"])
		if not ShipState.is_room_buildable(room_id):
			continue
		var root: Node3D = _room_roots.get(room_id, null)
		if root == null:
			continue
		var half_x: float = float(room.get("width", 200)) * ShipLayout.SCALE * 0.5
		var half_z: float = float(room.get("height", 200)) * ShipLayout.SCALE * 0.5
		var spot: Dictionary = _console_spot(room_id, half_x, half_z)
		var console: StaticBody3D = StaticBody3D.new()
		console.set_script(RoomConsoleScript)
		console.name = "RoomConsole"
		console.position = spot["pos"]
		console.rotation.y = spot["yaw"]
		console.set("room_id", room_id)
		root.add_child(console)
		RoomBuilderRef.attach_console_mesh(console)

		var tag: Label3D = Label3D.new()
		tag.text = "ROOM SYSTEMS"
		tag.pixel_size = 0.0038
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 6
		tag.shaded = false
		tag.modulate = Color(0.55, 0.85, 1.0, 1.0)
		tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		tag.position = spot["pos"] + Vector3(0.0, 1.6, 0.0)
		root.add_child(tag)


# First wall midpoint (west, east, north, south) without a doorway cut within
# 2.5 m of it; consoles face into the room. Falls back to the west wall.
func _console_spot(room_id: String, half_x: float, half_z: float) -> Dictionary:
	var openings: Array = _openings_by_room.get(room_id, []) as Array
	var candidates: Array = [
		{"dir": "-x", "pos": Vector3(-half_x + CONSOLE_WALL_INSET, 0.0, 0.0), "yaw": -PI * 0.5},
		{"dir": "+x", "pos": Vector3(half_x - CONSOLE_WALL_INSET, 0.0, 0.0), "yaw": PI * 0.5},
		{"dir": "-z", "pos": Vector3(0.0, 0.0, -half_z + CONSOLE_WALL_INSET), "yaw": PI},
		{"dir": "+z", "pos": Vector3(0.0, 0.0, half_z - CONSOLE_WALL_INSET), "yaw": 0.0},
	]
	for c: Dictionary in candidates:
		var blocked: bool = false
		for o: Dictionary in openings:
			if String(o["dir"]) == String(c["dir"]) and absf(float(o["along"])) < 2.5:
				blocked = true
				break
		if not blocked:
			return c
	return candidates[0]


# The Engineering Bay breaker gates the inter-deck lift, so deck play needs it
# too — minimal port of room.gd::_spawn_power_console (same script, same -X
# wall placement; offset +Z so it doesn't share the wall midpoint with the
# room's build console). Skipped once power is already restored — the lift
# doors spawn unlocked in that case and the wall switch has served its beat.
func _spawn_power_console() -> void:
	var root: Node3D = _room_roots.get("engineering_bay", null)
	if root == null:
		return
	var row: Dictionary = ShipLayout.room("engineering_bay")
	var half_x: float = float(row.get("width", 200)) * ShipLayout.SCALE * 0.5
	var pos: Vector3 = Vector3(-half_x + 0.25, 1.4, 3.0)
	var restored: bool = GameState.elevator_repaired

	var console: StaticBody3D = StaticBody3D.new()
	console.set_script(PowerConsoleScript)
	console.name = "PowerConsole"
	console.position = pos
	var cs: CollisionShape3D = CollisionShape3D.new()
	var s_box: BoxShape3D = BoxShape3D.new()
	s_box.size = Vector3(0.5, 0.8, 0.7)
	cs.shape = s_box
	console.add_child(cs)
	root.add_child(console)

	var housing: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.75, 0.65)
	housing.mesh = housing_box
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.20, 0.20, 0.22)
	housing_mat.metallic = 0.55
	housing_mat.roughness = 0.42
	housing.material_override = housing_mat
	housing.position = pos
	root.add_child(housing)

	var btn: MeshInstance3D = MeshInstance3D.new()
	var btn_box: BoxMesh = BoxMesh.new()
	btn_box.size = Vector3(0.04, 0.32, 0.32)
	btn.mesh = btn_box
	var btn_mat: StandardMaterial3D = StandardMaterial3D.new()
	var btn_color: Color = Color(0.35, 1.0, 0.55) if restored else Color(1.0, 0.30, 0.10)
	btn_mat.albedo_color = btn_color
	btn_mat.emission_enabled = true
	btn_mat.emission = btn_color
	btn_mat.emission_energy_multiplier = 3.2
	btn.material_override = btn_mat
	btn.position = pos + Vector3(0.02, 0.0, 0.0)
	root.add_child(btn)

	var label: Label3D = Label3D.new()
	label.name = "PowerLabel"
	label.text = "MAIN POWER\n(Elevator)"
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.95, 0.92, 0.78, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = pos + Vector3(0.05, 0.6, 0.0)
	root.add_child(label)


# ---- module visuals + damage overlays ---------------------------------------------

func _on_module_built(room_id: String, _module_id: String) -> void:
	_apply_module_visuals(room_id)


func _on_room_state_changed(room_id: String) -> void:
	_refresh_damage_overlay(room_id)


# Placeholder build visuals: re-dress the room with the module's accent
# template (a Hydroponics Unit drops the grow-beds set into the room, etc.).
# Full placement/construction phases live in design/gdd/ship-building-mode.md.
func _apply_module_visuals(room_id: String) -> void:
	var root: Node3D = _room_roots.get(room_id, null)
	if root == null:
		return
	var old: Node = root.get_node_or_null("ModuleVisuals")
	if old != null:
		# Rename before the deferred free so a same-frame rebuild can claim
		# the canonical name without Godot auto-suffixing it.
		old.name = "ModuleVisualsStale"
		old.queue_free()
	var module_id: String = ShipState.room_module(room_id)
	if module_id == "":
		return
	var template: String = String(ShipState.module(module_id).get("accent_template", ""))
	if template == "":
		return
	var room: Dictionary = ShipLayout.room(room_id)
	var width: float = float(room.get("width", 200)) * ShipLayout.SCALE
	var depth: float = float(room.get("height", 200)) * ShipLayout.SCALE
	var height: float = float(RoomBuilderRef.CEILING_BY_TEMPLATE.get(String(room.get("template_id", "")), 3.5))
	var holder: Node3D = Node3D.new()
	holder.name = "ModuleVisuals"
	root.add_child(holder)
	RoomBuilderRef.apply_template_accents(holder, template, width, depth, height)


# Hazard dressing for structurally damaged rooms: red warning light, sparking
# strip, debris. Cleared automatically once repairs bring damage back under
# the threshold (room_changed → this).
func _refresh_damage_overlay(room_id: String) -> void:
	var root: Node3D = _room_roots.get(room_id, null)
	if root == null:
		return
	var old: Node = root.get_node_or_null("DamageOverlay")
	if old != null:
		old.name = "DamageOverlayStale"
		old.queue_free()
	var dmg: float = ShipState.room_damage(room_id)
	if dmg < DAMAGE_OVERLAY_THRESHOLD:
		return
	var room: Dictionary = ShipLayout.room(room_id)
	var width: float = float(room.get("width", 200)) * ShipLayout.SCALE
	var depth: float = float(room.get("height", 200)) * ShipLayout.SCALE
	var overlay: Node3D = Node3D.new()
	overlay.name = "DamageOverlay"
	root.add_child(overlay)

	var alarm: OmniLight3D = OmniLight3D.new()
	alarm.light_color = Color(1.0, 0.16, 0.08)
	alarm.light_energy = 0.8 + 2.2 * (dmg / 100.0)
	alarm.omni_range = maxf(width, depth) * 0.7
	alarm.omni_attenuation = 1.5
	alarm.shadow_enabled = false
	alarm.position = Vector3(0.0, 2.6, 0.0)
	overlay.add_child(alarm)

	var debris_mat: StandardMaterial3D = StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.10, 0.10, 0.12)
	debris_mat.roughness = 0.9
	var count: int = 3 + int(dmg / 25.0)
	for i in count:
		# Deterministic scatter (stable across loads — no RNG).
		var t: float = float(i) / float(count)
		var mi: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.5 + 0.4 * sin(float(i) * 2.7), 0.25, 0.4 + 0.3 * cos(float(i) * 1.9))
		mi.mesh = box
		mi.material_override = debris_mat
		mi.position = Vector3(
			sin(t * TAU + 0.7) * width * 0.3,
			0.12,
			cos(t * TAU * 1.3 + 0.4) * depth * 0.3)
		mi.rotation.y = t * TAU
		overlay.add_child(mi)


# ---- player placement + room tracking ------------------------------------------

func _place_player(arrival_room: String) -> void:
	# Save-restored transform wins; SceneRouter's marker placement (when a
	# spawn key was passed) overrides the default below AFTER _ready.
	if GameState.pending_spawn_position != null:
		player.global_position = GameState.pending_spawn_position
		player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
		if view.has_method("snap_to_target"):
			view.snap_to_target()
		return
	var room_id: String = arrival_room
	if room_id == "" or not _is_deck_room(room_id):
		room_id = "stargate_corridor_east_connector" if floor_index == 0 else "elevator_room_floor_1"
	if not _is_deck_room(room_id) and not _floor_rooms.is_empty():
		room_id = String((_floor_rooms[0] as Dictionary)["id"])
	player.global_position = _room_centre(room_id)
	player.rotation.y = 0.0
	if view.has_method("snap_to_target"):
		view.snap_to_target()


func _process(delta: float) -> void:
	_track_accum += delta
	if _track_accum < ROOM_TRACK_INTERVAL:
		return
	_track_accum = 0.0
	if GameState.elevator_repaired and not _lift_doors.is_empty():
		for door in _lift_doors:
			if is_instance_valid(door) and door.has_method("unlock"):
				door.call("unlock")
		_lift_doors.clear()
	if player == null or not is_instance_valid(player):
		return
	var room_id: String = _room_at(player.global_position)
	if room_id == "" or room_id == GameState.current_room_id:
		return
	var prev: String = GameState.current_room_id
	GameState.discover_room(room_id, String(ShipLayout.room(room_id).get("name", room_id)))
	GameState.set_current_room(room_id)
	# Walking across a doorway counts as traversing it (Kino map pip dimming).
	if prev != "" and (ShipLayout.neighbours(prev) as Array).has(room_id):
		GameState.mark_door_traversed(prev, room_id)


func _room_at(pos: Vector3) -> String:
	var gx: float = pos.x / ShipLayout.SCALE
	var gy: float = pos.z / ShipLayout.SCALE
	for room: Dictionary in _floor_rooms:
		if gx >= float(room["startX"]) and gx <= float(room["endX"]) \
				and gy >= float(room["startY"]) and gy <= float(room["endY"]):
			return String(room["id"])
	return ""
