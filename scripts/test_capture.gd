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
# Walk-phase frame budget — WALK_FRAMES for the short in-room stroll, longer
# when `toward=<group>` covers real distance to an interactable.
var _walk_frames: int = WALK_FRAMES
# Camera mode: "" = default over-the-shoulder walk-in; "overview" = elevated
# pulled-back establishing shot (for outdoor scenes / large rooms the 3/4 walk
# can't frame). Parsed from `cam=overview` user arg.
var _cam_mode: String = ""

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
		elif arg.begins_with("cam="):
			_cam_mode = arg.substr(4)
		elif arg.begins_with("biome="):
			# Force a specific biome for planet captures. Autoloads _ready runs
			# before the scene's, so planet.gd::_active_spec picks this up.
			# Optional "biome=<id>:<seed>" pins the sky/terrain roll too.
			var parts: PackedStringArray = arg.substr(6).split(":")
			var forced_seed: int = int(parts[1]) if parts.size() > 1 else -1
			GameState.build_next_planet_spec("", parts[0], forced_seed)
			print("[test_capture] biome=%s seed=%s" % [parts[0], str(forced_seed)])
	print("[test_capture] active cam=%s" % _cam_mode)

# Put GameState into a named quest state so room.gd stages the right beat (e.g.
# the control-room Rush standoff needs find_rush + met_rush==false). Dev-only.
func _preset_quest(which: String) -> void:
	match which:
		"find_rush":
			GameState.met_scott = true
			GameState.advance_air_quest()   # talk_scott → find_rush (met_rush stays false)
		"find_rest":
			# Past the Rush standoff: Eli heads to his quarters to cool off.
			GameState.met_scott = true
			GameState.advance_air_quest()   # → find_rush
			GameState.met_rush = true
			GameState.advance_air_quest()   # → find_rest
		"air_crisis":
			# Air crisis active, no breach sealed yet → ShipAlert.is_alert_active()
			# returns true, so rooms render under the red-alert tint (the breach beat).
			GameState.air_crisis_started = true
		"coldopen_done":
			# Post-cold-open gate room: skip the cinematic and drop the player into the
			# playable hand-off state (Find Rush active), spawned mid-room facing the
			# exit so the waypoint/minimap guidance toward the control room is framed.
			GameState.met_scott = true
			GameState.advance_air_quest()   # → find_rush
			GameState.skip_arrival_cinematic = true
			GameState.pending_spawn_position = Vector3(0.0, 0.05, 3.5)
			GameState.pending_spawn_yaw = 0.0   # face -Z (the exit wall / corridors)
	print("[test_capture] quest preset=%s step=%s" % [which, GameState.get("quest_step")])

func _process(_delta: float) -> void:
	if _state == 2:
		return
	_frames += 1
	if _state == 0 and _frames >= SETTLE_FRAMES:
		if _cam_mode == "overview":
			_setup_overview()
		else:
			_start_walk()
		_frames = 0
		_state = 1
		return
	if _state == 1 and _frames >= _walk_frames:
		_state = 2
		_capture()

# Elevated pulled-back establishing shot — for outdoor scenes / large rooms the
# over-the-shoulder walk can't frame. Spawns a temp Camera3D looking down at the
# player (or scene origin), makes it current. Overridable via cam_h=/cam_back=/fov=.
func _setup_overview() -> void:
	var tree: SceneTree = get_tree()
	var focus: Vector3 = Vector3.ZERO
	var player: Node = tree.get_first_node_in_group("player")
	if player is Node3D:
		focus = (player as Node3D).global_position
	var height: float = 11.0
	var back: float = 16.0
	var side: float = 6.0
	var fov: float = 62.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cam_h="):
			height = arg.substr(6).to_float()
		elif arg.begins_with("cam_back="):
			back = arg.substr(9).to_float()
		elif arg.begins_with("fov="):
			fov = arg.substr(4).to_float()
	var cam: Camera3D = Camera3D.new()
	cam.name = "OverviewCaptureCam"
	cam.fov = fov
	var scene: Node = tree.current_scene
	if scene != null:
		scene.add_child(cam)               # in tree before look_at
		cam.global_position = focus + Vector3(side, height, back)
		cam.look_at(focus + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true


func _start_walk() -> void:
	var tree: SceneTree = get_tree()
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not (player is Node3D) or not player.has_method("auto_walk_to"):
		return
	var pn: Node3D = player as Node3D
	var walk_distance: float = WALK_DISTANCE
	var yaw_offset: float = DEFAULT_CAMERA_YAW_OFFSET
	var pitch: float = NAN
	var toward_group: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("yaw="):
			yaw_offset = arg.substr(4).to_float()
		elif arg.begins_with("walk="):
			walk_distance = arg.substr(5).to_float()
		elif arg.begins_with("toward="):
			toward_group = arg.substr(7)
		elif arg.begins_with("pitch="):
			pitch = arg.substr(6).to_float()
	if toward_group != "":
		_walk_to_group_member(tree, pn, toward_group)
		_apply_yaw_offset(tree, yaw_offset, pitch)
		return
	# Authored Player facings are inconsistent across scenes (some face into the
	# room, some face back at the door they "came from"). Derive direction from
	# geometry: nearest Door is "behind", walk AWAY from it. Scenes with no doors
	# at all (planet surfaces) use the facing fallback inside — planet spawns are
	# authored to face open terrain, away from the return gate.
	var root: Node = tree.current_scene
	var forward: Vector3 = _direction_into_room(root, pn)
	if forward.length() < 0.01:
		return
	player.call("auto_walk_to", pn.global_position + forward * walk_distance, 4.0)
	_apply_yaw_offset(tree, yaw_offset, pitch)


# Offset the camera into a 3/4 angle so character isn't directly between
# camera and any central prop. snap_to_target reads initial_yaw_offset.
# An explicit pitch (degrees; positive tilts the view up toward the sky —
# used by the alien-sky showcase shots) overrides the authored rig pitch.
func _apply_yaw_offset(tree: SceneTree, yaw_offset: float, pitch: float = NAN) -> void:
	var root_view: Node = tree.current_scene.get_node_or_null("View")
	if root_view == null or not ("initial_yaw_offset" in root_view):
		return
	root_view.initial_yaw_offset = yaw_offset
	if root_view.has_method("snap_to_target"):
		root_view.call("snap_to_target")
	if not is_nan(pitch) and "camera_rotation" in root_view:
		var rot: Vector3 = root_view.camera_rotation
		rot.x = pitch
		root_view.camera_rotation = rot
		root_view.rotation_degrees = rot


# `toward=<group>`: frame an INTERACTION — jump the player to just outside the
# nearest member of a node group (e.g. lime_node on a planet run), then walk
# the last stretch toward it so the shot lands with the interactable in front
# of the character and its prompt live. The long-range teleport keeps captures
# fast; the short real walk keeps facing/animation/prompt honest.
const _TOWARD_TELEPORT_DIST: float = 6.5
const _TOWARD_STOP_DIST: float = 1.6
const _TOWARD_WALK_FRAMES: int = 170

func _walk_to_group_member(tree: SceneTree, pn: Node3D, group: String) -> void:
	var best: Node3D = null
	var best_d: float = INF
	for n in tree.get_nodes_in_group(group):
		if not (n is Node3D):
			continue
		var d: float = ((n as Node3D).global_position - pn.global_position).length_squared()
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		print("[test_capture] toward=%s: no group members found" % group)
		return
	# Approach from the spawn side so the camera looks out over where the player
	# came from (gate/terrain in the far background).
	var approach: Vector3 = pn.global_position - best.global_position
	approach.y = 0.0
	approach = approach.normalized() if approach.length() > 0.5 else Vector3.FORWARD
	var start: Vector3 = best.global_position + approach * _TOWARD_TELEPORT_DIST
	start.y = best.global_position.y + 1.2   # drop onto terrain via gravity
	pn.global_position = start
	pn.call("auto_walk_to", best.global_position + approach * _TOWARD_STOP_DIST, 4.0)
	_walk_frames = _TOWARD_WALK_FRAMES
	print("[test_capture] toward=%s target=%s" % [group, best.name])

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
