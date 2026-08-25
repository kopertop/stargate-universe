extends Node

# Squad command system for planetary away missions (E2 Light +).
#
# Provides a simple command state machine the player issues to their AI
# companions (Greer + scientist) while on a planetary surface. Three commands:
#
#   HOLD     — companions hold their current position and do not follow.
#   ADVANCE  — companions move toward the squad waypoint (player-facing by
#              default, or a world position set via set_waypoint()).
#   COVER_FIRE — companions hold position and suppress nearby threats. In
#              the current implementation this means: hold position, face
#              the nearest enemy/hostile, and play a "firing" animation.
#
# The autoload owns the CURRENT command (a single enum) and a waypoint Vector3.
# Companion.gd reads both every _process tick and adjusts its behaviour.
# A signal (command_changed) lets the HUD / companion commentary react.
#
# Save/load: the command + waypoint are serialized so a mid-mission save
# restores the squad's standing orders. Reset clears to the default (ADVANCE
# with no waypoint — companions follow the player, matching E1 behaviour).
#
# Headless-safe: all state is plain data; no scene dependencies. The smoke
# test drives it directly without loading planet.tscn.

signal command_changed(command: String)
signal waypoint_changed(position: Vector3)

enum Command { HOLD, ADVANCE, COVER_FIRE }


func _ready() -> void:
	# Register with SaveManager (autoload-tolerant for -s SceneTree tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "squad_command", self)

const COMMAND_HOLD: String = "hold"
const COMMAND_ADVANCE: String = "advance"
const COMMAND_COVER_FIRE: String = "cover_fire"

var _command: Command = Command.ADVANCE
var _waypoint: Vector3 = Vector3.ZERO
var _waypoint_set: bool = false
# Mission context — which planetary mission is active. Set by planet.gd
# when the away team deploys so commentary can reference the right mission.
var _mission_id: String = ""

# --- Public API ------------------------------------------------------------

func get_command() -> String:
	match _command:
		Command.HOLD: return COMMAND_HOLD
		Command.ADVANCE: return COMMAND_ADVANCE
		Command.COVER_FIRE: return COMMAND_COVER_FIRE
	return COMMAND_ADVANCE

func get_command_enum() -> Command:
	return _command

func set_command(cmd: String) -> void:
	var new_cmd: Command = _parse_command(cmd)
	if new_cmd == _command:
		return
	_command = new_cmd
	command_changed.emit(get_command())

func has_waypoint() -> bool:
	return _waypoint_set

func get_waypoint() -> Vector3:
	return _waypoint

func set_waypoint(pos: Vector3) -> void:
	_waypoint = pos
	_waypoint_set = true
	waypoint_changed.emit(pos)

func clear_waypoint() -> void:
	_waypoint_set = false
	_waypoint = Vector3.ZERO

func get_mission_id() -> String:
	return _mission_id

func set_mission_id(id: String) -> void:
	_mission_id = id

# --- Serialization ---------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"command": get_command(),
		"waypoint": {"x": _waypoint.x, "y": _waypoint.y, "z": _waypoint.z},
		"waypoint_set": _waypoint_set,
		"mission_id": _mission_id,
	}

func deserialize(data: Dictionary, _version: int = 0) -> void:
	_command = _parse_command(String(data.get("command", COMMAND_ADVANCE)))
	var wp: Variant = data.get("waypoint", {})
	if wp is Dictionary:
		_waypoint = Vector3(
			float((wp as Dictionary).get("x", 0.0)),
			float((wp as Dictionary).get("y", 0.0)),
			float((wp as Dictionary).get("z", 0.0)),
		)
	_waypoint_set = data.get("waypoint_set", false) == true
	_mission_id = String(data.get("mission_id", ""))

func reset() -> void:
	_command = Command.ADVANCE
	_waypoint = Vector3.ZERO
	_waypoint_set = false
	_mission_id = ""

# --- Helpers ---------------------------------------------------------------

func _parse_command(cmd: String) -> Command:
	match cmd:
		COMMAND_HOLD: return Command.HOLD
		COMMAND_ADVANCE: return Command.ADVANCE
		COMMAND_COVER_FIRE: return Command.COVER_FIRE
	return Command.ADVANCE


# Same autoload-tolerant pattern as GameState._autoload_node.
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)