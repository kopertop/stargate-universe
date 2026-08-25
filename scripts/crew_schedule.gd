extends Node

# CrewSchedule — daily routines, event reactions, and dynamic placement for
# the 16 crew members aboard Destiny.
#
# Each crew member has a daily schedule (data/crew_schedules.json) defined as
# a list of time-blocked activities (sleep, eat, work, patrol, social). The
# schedule advances with GameClock.elapsed_seconds, wrapping at day_length.
#
# When a ship event fires (red alert, air crisis, power failure), the system
# overrides the routine: crew rush to their alert_station room, sorted by
# alert_priority. When the event clears, they resume their schedule.
#
# Movement uses ShipLayout.path_through_rooms (BFS over the door graph) to
# plan multi-room routes. Crew positions are tracked in world space and can
# be queried by other systems (NPC spawning, HUD, cutscenes).
#
# Integration:
#   - GameClock: drives schedule advancement via elapsed_seconds
#   - ShipLayout: room graph for pathfinding + room center positions
#   - GameState: listens to air_crisis_started for auto-alert
#   - PowerGrid: monitors power state for emergency reactions
#   - NPCState: crew positions ride along in the save snapshot
#
# Save contract: per-crew current room, activity, alert state, and movement
# progress so a save/load mid-route resumes correctly.

signal crew_moved(crew_name: String, from_room: String, to_room: String)
signal activity_changed(crew_name: String, activity: String, room: String)
signal alert_state_changed(active: bool, reason: String)
signal schedule_advanced(day_fraction: float)

const SCHEDULE_PATH: String = "res://data/crew_schedules.json"

# ── Activity enum ────────────────────────────────────────────────────────────

enum Activity { SLEEP, EAT, WORK, PATROL, SOCIAL, ALERT, IDLE }

const ACTIVITY_NAMES: Dictionary = {
	"sleep": Activity.SLEEP,
	"eat": Activity.EAT,
	"work": Activity.WORK,
	"patrol": Activity.PATROL,
	"social": Activity.SOCIAL,
	"alert": Activity.ALERT,
	"idle": Activity.IDLE,
}

# ── State ────────────────────────────────────────────────────────────────────

var _day_length: float = 1200.0          # seconds per full day cycle
var _crew: Dictionary = {}              # crew_name → CrewEntry (see _CrewEntry)
var _loaded: bool = false
var _alert_active: bool = false
var _alert_reason: String = ""
# Movement speed in metres/second for crew walking between rooms.
var _move_speed: float = 2.5
# How close to a room center counts as "arrived" (metres).
var _arrive_threshold: float = 1.5

# Public setter for move speed (used by tests / scripted events).
func set_move_speed(speed: float) -> void:
	_move_speed = speed

# Internal class for per-crew runtime state.
class _CrewEntry:
	var name: String
	var role: String
	var home_room: String
	var shift_start: float
	var schedule: Array       # Array of Dictionary { t, activity, room }
	var alert_station: String
	var alert_priority: int

	# Runtime state.
	var current_room: String
	var current_activity: int = Activity.IDLE
	var target_room: String = ""
	var world_pos: Vector3 = Vector3.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var path: PackedStringArray = PackedStringArray()
	var path_index: int = 0
	var moving: bool = false
	var alert_overridden: bool = false
	# Save/restore: progress fraction toward next room center (0..1).
	var move_progress: float = 0.0

	func _init(n: String) -> void:
		name = n


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	# Wire to GameState for auto-alert on air crisis.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		# GameState doesn't have a dedicated signal; poll in _process.
		pass
	# Start with all crew at their t=0 position.
	_initialize_positions()


func _process(_delta: float) -> void:
	if not _loaded:
		return
	# Check for alert state changes from GameState.
	_check_ship_events()
	# Advance schedules.
	_advance_schedules()
	# Move crew that have a pending route.
	_advance_movement(_delta)


# ── Config loading ────────────────────────────────────────────────────────────

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(SCHEDULE_PATH, FileAccess.READ)
	if f == null:
		push_error("CrewSchedule: cannot open %s" % SCHEDULE_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("CrewSchedule: %s did not parse to a Dictionary" % SCHEDULE_PATH)
		return
	var d: Dictionary = parsed as Dictionary
	_day_length = float(d.get("day_length_seconds", 1200.0))
	var raw_crew: Variant = d.get("crew", {})
	if not (raw_crew is Dictionary):
		push_error("CrewSchedule: 'crew' is not a Dictionary")
		return
	for crew_name in (raw_crew as Dictionary).keys():
		var cd: Dictionary = (raw_crew as Dictionary)[crew_name]
		var entry: _CrewEntry = _CrewEntry.new(String(crew_name))
		entry.role = String(cd.get("role", "crew"))
		entry.home_room = String(cd.get("home_room", "gate_room"))
		entry.shift_start = float(cd.get("shift_start", 0.0))
		entry.alert_station = String(cd.get("alert_station", "gate_room"))
		entry.alert_priority = int(cd.get("alert_priority", 5))
		var raw_sched: Variant = cd.get("schedule", [])
		if raw_sched is Array:
			entry.schedule = (raw_sched as Array).duplicate(true)
		entry.current_room = entry.home_room
		entry.current_activity = Activity.IDLE
		_crew[entry.name] = entry


# ── Position initialization ──────────────────────────────────────────────────

func _initialize_positions() -> void:
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl == null:
		return
	var frac: float = _day_fraction()
	for entry in _crew.values():
		entry = entry as _CrewEntry
		var slot: Dictionary = _eval_schedule(entry, frac)
		entry.current_room = String(slot.get("room", entry.home_room))
		entry.current_activity = int(slot.get("activity_idx", Activity.IDLE))
		entry.world_pos = _room_center_world(sl, entry.current_room)
		entry.target_pos = entry.world_pos
		entry.target_room = entry.current_room
		entry.moving = false
		entry.path = PackedStringArray()
		entry.path_index = 0


# ── Schedule evaluation ──────────────────────────────────────────────────────

# Returns the day fraction [0, 1) from GameClock.elapsed_seconds.
func _day_fraction() -> float:
	var gc: Node = get_node_or_null("/root/GameClock")
	if gc == null:
		return 0.0
	var elapsed: float = float(gc.get("elapsed_seconds"))
	if _day_length <= 0.0:
		return 0.0
	return fmod(elapsed, _day_length) / _day_length


# Evaluate which schedule slot is active at day fraction `frac`.
# Returns { "room": String, "activity": String, "activity_idx": int }.
func _eval_schedule(entry: _CrewEntry, frac: float) -> Dictionary:
	var result: Dictionary = {"room": entry.home_room, "activity": "idle", "activity_idx": Activity.IDLE}
	if entry.schedule.is_empty():
		return result
	# Find the last slot whose t <= frac. Schedule wraps, so if frac < first
	# slot's t, the last slot (previous day's final) is active.
	var best: Dictionary = entry.schedule[entry.schedule.size() - 1]
	for slot in entry.schedule:
		var t: float = float(slot.get("t", 0.0))
		if t <= frac:
			best = slot
		else:
			break
	result["room"] = String(best.get("room", entry.home_room))
	result["activity"] = String(best.get("activity", "idle"))
	result["activity_idx"] = int(ACTIVITY_NAMES.get(result["activity"], Activity.IDLE))
	return result


# ── Schedule advancement ──────────────────────────────────────────────────────

func _advance_schedules() -> void:
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl == null:
		return
	var frac: float = _day_fraction()
	for entry in _crew.values():
		entry = entry as _CrewEntry
		# Skip crew in alert override — they stay at their station.
		if entry.alert_overridden and _alert_active:
			continue
		var slot: Dictionary = _eval_schedule(entry, frac)
		var new_room: String = String(slot.get("room", entry.home_room))
		var new_activity: int = int(slot.get("activity_idx", Activity.IDLE))
		# If the schedule says a new room, dispatch movement.
		if new_room != entry.current_room and not entry.moving:
			_dispatch_movement(entry, new_room)
		# If activity changed, fire signal.
		if new_activity != entry.current_activity:
			entry.current_activity = new_activity
			activity_changed.emit(entry.name, String(slot.get("activity", "idle")), entry.current_room)
	# Emit the schedule-advanced signal for HUD/clock displays.
	schedule_advanced.emit(frac)


# ── Movement ──────────────────────────────────────────────────────────────────

# Plan a route from the crew member's current room to `dest_room` using BFS
# over the ShipLayout door graph, then begin stepping through it.
func _dispatch_movement(entry: _CrewEntry, dest_room: String) -> void:
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl == null:
		return
	var path: PackedStringArray = sl.call("path_through_rooms", entry.current_room, dest_room)
	if path.is_empty():
		# No path found — teleport (room may be disconnected / locked).
		entry.current_room = dest_room
		entry.world_pos = _room_center_world(sl, dest_room)
		entry.target_pos = entry.world_pos
		entry.moving = false
		return
	entry.path = path
	entry.path_index = 0
	entry.target_room = dest_room
	entry.moving = true
	# Start moving toward the first room in the path (skip current room
	# if it's the path[0]).
	if path.size() > 1 and path[0] == entry.current_room:
		entry.path_index = 1
	_set_next_waypoint(entry, sl)


func _set_next_waypoint(entry: _CrewEntry, sl: Node) -> void:
	if entry.path_index >= entry.path.size():
		entry.moving = false
		entry.current_room = entry.target_room
		entry.world_pos = entry.target_pos
		return
	var next_room: String = entry.path[entry.path_index]
	entry.target_pos = _room_center_world(sl, next_room)


func _advance_movement(delta: float) -> void:
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl == null:
		return
	for entry in _crew.values():
		entry = entry as _CrewEntry
		if not entry.moving:
			continue
		# Move toward target_pos.
		var to_target: Vector3 = entry.target_pos - entry.world_pos
		var dist: float = to_target.length()
		if dist < _arrive_threshold:
			# Arrived at this waypoint room.
			var arrived_room: String = entry.path[entry.path_index]
			var old_room: String = entry.current_room
			entry.current_room = arrived_room
			entry.world_pos = entry.target_pos
			entry.path_index += 1
			if old_room != arrived_room:
				crew_moved.emit(entry.name, old_room, arrived_room)
			_set_next_waypoint(entry, sl)
			continue
		# Step toward target.
		var dir: Vector3 = to_target.normalized()
		var step: float = _move_speed * delta
		if step > dist:
			step = dist
		entry.world_pos += dir * step
		entry.move_progress = 1.0 - (dist / maxf(dist + step, 0.001))


# ── Alert / event reactions ───────────────────────────────────────────────────

# Check GameState for conditions that trigger/clear alert mode.
func _check_ship_events() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var crisis: bool = bool(gs.get("air_crisis_started"))
		if crisis and not _alert_active:
			trigger_alert("air_crisis")
		elif not crisis and _alert_active and _alert_reason == "air_crisis":
			clear_alert()
	# Monitor PowerGrid for widespread power failure.
	# When generator output drops below 30% of capacity, engineering crew
	# rush to their stations. Clears when output recovers above 50%.
	# (Normal load-shedding of low-priority rooms doesn't trigger this —
	# only a major generator failure does.)
	# Air crisis takes priority: don't override an active air_crisis alert.
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg != null:
		var output: float = float(pg.call("get_available_power"))
		var capacity: float = float(pg.call("get_total_capacity"))
		if capacity > 0.0:
			var ratio: float = output / capacity
			if ratio < 0.3 and not _alert_active:
				trigger_alert("power_failure")
			elif ratio > 0.5 and _alert_active and _alert_reason == "power_failure":
				clear_alert()


# External callers can trigger an alert directly (e.g. red alert button,
# hull breach event, power failure).
func trigger_alert(reason: String) -> void:
	if _alert_active and _alert_reason == reason:
		return
	_alert_active = true
	_alert_reason = reason
	var sl: Node = get_node_or_null("/root/ShipLayout")
	# Sort crew by alert_priority (1 = highest).
	var sorted: Array = _crew.values().duplicate()
	sorted.sort_custom(func(a: _CrewEntry, b: _CrewEntry) -> bool:
		return a.alert_priority < b.alert_priority)
	for entry in sorted:
		entry = entry as _CrewEntry
		entry.alert_overridden = true
		# Rush to alert station.
		if entry.alert_station != entry.current_room:
			if sl != null:
				_dispatch_movement(entry, entry.alert_station)
			else:
				entry.current_room = entry.alert_station
		entry.current_activity = Activity.ALERT
	alert_state_changed.emit(true, reason)


func clear_alert() -> void:
	if not _alert_active:
		return
	_alert_active = false
	_alert_reason = ""
	for entry in _crew.values():
		entry = entry as _CrewEntry
		entry.alert_overridden = false
	# Re-evaluate schedules so crew resume their routine.
	_advance_schedules()
	alert_state_changed.emit(false, "")


# ── Public API ────────────────────────────────────────────────────────────────

# How many crew are registered.
func crew_count() -> int:
	return _crew.size()


# All crew names.
func crew_names() -> Array:
	return _crew.keys()


# Get a crew member's current room.
func get_crew_room(crew_name: String) -> String:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return ""
	return entry.current_room


# Get a crew member's current activity (as the Activity enum int).
func get_crew_activity(crew_name: String) -> int:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return Activity.IDLE
	return entry.current_activity


# Get a crew member's world position.
func get_crew_position(crew_name: String) -> Vector3:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return Vector3.ZERO
	return entry.world_pos


# Get a crew member's target room (where they're heading, or current if stationary).
func get_crew_target(crew_name: String) -> String:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return ""
	if entry.moving:
		return entry.target_room
	return entry.current_room


# Is a crew member currently moving?
func is_crew_moving(crew_name: String) -> bool:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return false
	return entry.moving


# Is alert mode active?
func is_alert_active() -> bool:
	return _alert_active


# Get the alert reason string (empty if no alert).
func get_alert_reason() -> String:
	return _alert_reason


# Get the day fraction [0, 1).
func get_day_fraction() -> float:
	return _day_fraction()


# Get the day length in seconds.
func get_day_length() -> float:
	return _day_length


# Get a crew member's full schedule (read-only Array of Dictionaries).
func get_crew_schedule(crew_name: String) -> Array:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return []
	return entry.schedule.duplicate(true)


# Get a crew member's role.
func get_crew_role(crew_name: String) -> String:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return ""
	return entry.role


# Get a crew member's alert station.
func get_crew_alert_station(crew_name: String) -> String:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return ""
	return entry.alert_station


# Get a crew member's alert priority (1 = highest).
func get_crew_alert_priority(crew_name: String) -> int:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return 99
	return entry.alert_priority


# Force a crew member to a specific room immediately (cutscene / scripted event).
func force_crew_to_room(crew_name: String, room_id: String) -> void:
	var entry: _CrewEntry = _crew.get(crew_name, null) as _CrewEntry
	if entry == null:
		return
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl != null:
		entry.world_pos = _room_center_world(sl, room_id)
	entry.current_room = room_id
	entry.target_room = room_id
	entry.target_pos = entry.world_pos
	entry.moving = false
	entry.path = PackedStringArray()
	entry.path_index = 0


# Get a summary of all crew positions and activities for HUD/minimap.
# Returns Array of { name, role, room, activity, moving, target, alert }.
func get_all_crew_summary() -> Array:
	var result: Array = []
	for entry in _crew.values():
		entry = entry as _CrewEntry
		result.append({
			"name": entry.name,
			"role": entry.role,
			"room": entry.current_room,
			"activity": entry.current_activity,
			"moving": entry.moving,
			"target": entry.target_room if entry.moving else entry.current_room,
			"alert": entry.alert_overridden,
		})
	return result


# Get all crew currently in a given room.
func crew_in_room(room_id: String) -> Array:
	var result: Array = []
	for entry in _crew.values():
		entry = entry as _CrewEntry
		if entry.current_room == room_id:
			result.append(entry.name)
	return result


# ── Utilities ──────────────────────────────────────────────────────────────────

# Convert a room id to a world-space center position (Vector3 on the XZ plane).
func _room_center_world(sl: Node, room_id: String) -> Vector3:
	if sl == null:
		return Vector3.ZERO
	var r: Dictionary = sl.call("room", room_id)
	if r.is_empty():
		return Vector3.ZERO
	var scale: float = float(sl.get("SCALE"))
	if scale <= 0.0:
		scale = 0.05
	var cx: float = (float(r.get("startX", 0.0)) + float(r.get("endX", 0.0))) * 0.5 * scale
	var cz: float = (float(r.get("startY", 0.0)) + float(r.get("endY", 0.0))) * 0.5 * scale
	return Vector3(cx, 0.0, cz)


# ── Save / Load ───────────────────────────────────────────────────────────────

func _register_with_save_manager() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "crew_schedule", self)


func serialize() -> Dictionary:
	var data: Dictionary = {}
	for entry in _crew.values():
		entry = entry as _CrewEntry
		data[entry.name] = {
			"current_room": entry.current_room,
			"current_activity": entry.current_activity,
			"target_room": entry.target_room,
			"world_pos": [entry.world_pos.x, entry.world_pos.y, entry.world_pos.z],
			"target_pos": [entry.target_pos.x, entry.target_pos.y, entry.target_pos.z],
			"moving": entry.moving,
			"alert_overridden": entry.alert_overridden,
			"path": Array(entry.path),
			"path_index": entry.path_index,
			"move_progress": entry.move_progress,
		}
	return {"crew": data, "alert_active": _alert_active, "alert_reason": _alert_reason}


func deserialize(data: Dictionary, _version: int) -> void:
	var raw_crew: Variant = data.get("crew", {})
	if raw_crew is Dictionary:
		for crew_name in (raw_crew as Dictionary).keys():
			var entry: _CrewEntry = _crew.get(String(crew_name), null) as _CrewEntry
			if entry == null:
				continue
			var cd: Dictionary = (raw_crew as Dictionary)[crew_name]
			entry.current_room = String(cd.get("current_room", entry.home_room))
			entry.current_activity = int(cd.get("current_activity", Activity.IDLE))
			entry.target_room = String(cd.get("target_room", entry.current_room))
			var wp: Array = cd.get("world_pos", [0.0, 0.0, 0.0])
			if wp is Array and wp.size() >= 3:
				entry.world_pos = Vector3(float(wp[0]), float(wp[1]), float(wp[2]))
			var tp: Array = cd.get("target_pos", [0.0, 0.0, 0.0])
			if tp is Array and tp.size() >= 3:
				entry.target_pos = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
			entry.moving = bool(cd.get("moving", false))
			entry.alert_overridden = bool(cd.get("alert_overridden", false))
			var raw_path: Variant = cd.get("path", [])
			if raw_path is Array:
				entry.path = PackedStringArray(raw_path as Array)
			entry.path_index = int(cd.get("path_index", 0))
			entry.move_progress = float(cd.get("move_progress", 0.0))
	_alert_active = bool(data.get("alert_active", false))
	_alert_reason = String(data.get("alert_reason", ""))


func reset() -> void:
	_alert_active = false
	_alert_reason = ""
	for entry in _crew.values():
		entry = entry as _CrewEntry
		entry.alert_overridden = false
		entry.moving = false
		entry.path = PackedStringArray()
		entry.path_index = 0
		entry.move_progress = 0.0
	_initialize_positions()