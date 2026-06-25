extends Node

# @no-save: dev-only screenshot helper; never engaged during real play.
#
# Auto-screenshot helper for AI-driven iteration.
# Enabled when the project is launched with `--cli-arg capture` (or any positional arg
# containing "capture"). Walks the player a couple metres forward from spawn so the
# camera frames the room (not the back of the door), then saves a PNG to
# user://capture.png.

const OUT_PATH: String = "user://capture.png"
const SETTLE_FRAMES: int = 6
const WALK_FRAMES: int = 60
const WALK_DISTANCE: float = 1.6
# 3/4 over-the-shoulder angle so the character sits off-center and the room
# (not just the central prop directly ahead) is visible behind them. Can be
# overridden per-scene via `++ capture yaw=0` user arg for decor-heavy rooms
# where the angled SpringArm clips inside a wall/prop.
const DEFAULT_CAMERA_YAW_OFFSET: float = 28.0

var _state: int = 0   # 0=settle, 1=walking, 2=done
var _frames: int = 0

func _ready() -> void:
	if not _capture_requested():
		queue_free()
		return
	# Autoloads run their _ready BEFORE the main scene's _ready, so setting
	# GameState.next_room_id here is read in time by room.gd::_ready when we
	# launch with `godot res://scenes/room.tscn --cli-arg room_id=<id>`.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("room_id="):
			GameState.next_room_id = arg.substr(8)
			print("[test_capture] room_id=", GameState.next_room_id)
		elif arg.begins_with("quest="):
			_preset_quest(arg.substr(6))
	print("[test_capture] active")

# Put GameState into a named quest state so room.gd stages the right beat (e.g.
# the control-room Rush standoff needs find_rush + met_rush==false). Dev-only.
func _preset_quest(which: String) -> void:
	match which:
		"find_rush":
			GameState.met_scott = true
			GameState.advance_air_quest()   # talk_scott → find_rush (met_rush stays false)
	print("[test_capture] quest preset=%s step=%s" % [which, GameState.get("quest_step")])

func _process(_delta: float) -> void:
	if _state == 2:
		return
	_frames += 1
	if _state == 0 and _frames >= SETTLE_FRAMES:
		_start_walk()
		_frames = 0
		_state = 1
		return
	if _state == 1 and _frames >= WALK_FRAMES:
		_state = 2
		_capture()

func _start_walk() -> void:
	var tree: SceneTree = get_tree()
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not (player is Node3D) or not player.has_method("auto_walk_to"):
		return
	var pn: Node3D = player as Node3D
	# Authored Player facings are inconsistent across scenes (some face into the
	# room, some face back at the door they "came from"). Derive direction from
	# geometry: nearest Door is "behind", walk AWAY from it.
	var root: Node = tree.current_scene
	var forward: Vector3 = _direction_into_room(root, pn)
	if forward.length() < 0.01:
		return
	var walk_distance: float = WALK_DISTANCE
	var yaw_offset: float = DEFAULT_CAMERA_YAW_OFFSET
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("yaw="):
			yaw_offset = arg.substr(4).to_float()
		elif arg.begins_with("walk="):
			walk_distance = arg.substr(5).to_float()
	player.call("auto_walk_to", pn.global_position + forward * walk_distance, 4.0)
	# Offset the camera into a 3/4 angle so character isn't directly between
	# camera and any central prop. snap_to_target reads initial_yaw_offset.
	var root_view: Node = tree.current_scene.get_node_or_null("View")
	if root_view != null and "initial_yaw_offset" in root_view:
		root_view.initial_yaw_offset = yaw_offset
		if root_view.has_method("snap_to_target"):
			root_view.call("snap_to_target")

func _direction_into_room(root: Node, pn: Node3D) -> Vector3:
	var nearest: Node3D = _find_nearest_door(root, pn.global_position)
	if nearest != null:
		var away: Vector3 = pn.global_position - nearest.global_position
		away.y = 0.0
		if away.length() > 0.01:
			return away.normalized()
	var fallback: Vector3 = -pn.global_transform.basis.z
	fallback.y = 0.0
	return fallback.normalized() if fallback.length() > 0.01 else Vector3.FORWARD

func _find_nearest_door(node: Node, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for d in _gather_doors(node):
		var dist: float = (d.global_position - pos).length_squared()
		if dist < best_d:
			best_d = dist
			best = d
	return best

func _gather_doors(node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var s: Script = node.get_script()
	if s != null and s.resource_path.ends_with("door.gd") and node is Node3D:
		out.append(node)
	for c in node.get_children():
		for d in _gather_doors(c):
			out.append(d)
	return out

func _capture() -> void:
	_dump_scene()
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(OUT_PATH)
	print("[test_capture] saved=%s err=%s abs=%s" % [OUT_PATH, err, ProjectSettings.globalize_path(OUT_PATH)])
	get_tree().quit()

func _dump_scene() -> void:
	var root: Window = get_tree().root
	for w in root.get_children():
		_dump_node(w, 0)

func _dump_node(n: Node, depth: int) -> void:
	var prefix: String = "  ".repeat(depth)
	var info: String = "%s%s [%s]" % [prefix, n.name, n.get_class()]
	if n is Node3D:
		info += " pos=" + str((n as Node3D).global_position)
		info += " visible=" + str((n as Node3D).visible)
	print(info)
	if depth < 3:
		for c in n.get_children():
			_dump_node(c, depth + 1)

func _capture_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.contains("capture"):
			return true
	return false
