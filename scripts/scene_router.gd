extends Node

# @no-save: transient cross-scene transition state (fade alpha, pending
# spawn point). The destination scene path is captured by SaveManager
# directly from GameState.current_scene_path, not from this router.
#
# Cross-scene transition manager. Owns a fade-out CanvasLayer it parents to root
# at runtime, then deferred-loads the next scene. Places the player at a Marker3D
# named via metadata `spawn_point` if present.

signal scene_changed(scene_path: String)

const FADE_DURATION: float = 0.45

# When true, skip the fade animation and switch scenes synchronously. Used by
# headless tests (Tween.finished is unreliable across multiple back-to-back
# scene changes in headless mode) and available for any future fast-travel /
# instant-reload feature.
var instant_mode: bool = false

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
# Public flag — SaveManager reads this to gate auto-save (mid-fade is not
# a stable moment to capture the player transform).
var is_transitioning: bool = false
var _pending_spawn: String = ""

func _ready() -> void:
	_build_fade_layer()

func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

func change_to(scene_path: String, spawn_point: String = "") -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_pending_spawn = spawn_point
	await _fade_to(1.0)
	# Release mouse capture during transition so it doesn't carry over.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err: int = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: failed to load %s (err %d)" % [scene_path, err])
		is_transitioning = false
		await _fade_to(0.0)
		return
	# Wait until the new scene is actually in the tree. In Godot 4,
	# change_scene_to_file is deferred — current_scene is briefly null while the
	# old scene frees and the new one instantiates. A single process_frame is
	# not enough in headless mode; loop with a small ceiling so we never hang.
	var attempts: int = 0
	while get_tree().current_scene == null and attempts < 30:
		await get_tree().process_frame
		attempts += 1
	_place_player_at_spawn()
	scene_changed.emit(scene_path)
	await _fade_to(0.0)
	is_transitioning = false
	# A cutscene that ends by transporting the player here (armed via
	# Cinematic.close_on_next_scene_change) keeps its letterbox up through the
	# cut; lift it now that the destination scene has faded in.
	if Cinematic.wants_scene_change_close():
		await Cinematic.letterbox_out()

func _place_player_at_spawn() -> void:
	if _pending_spawn == "":
		return
	var tree: SceneTree = get_tree()
	var root: Node = tree.current_scene
	if root == null:
		return
	var marker: Node = _find_marker(root, _pending_spawn)
	if marker == null:
		return
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return
	var marker_n: Node3D = marker as Node3D
	# Most room-to-room markers are door-adjacent, so derive facing from the
	# nearest door. Stargate arrivals are explicit: their marker faces out from
	# the event horizon, as if the player just stepped through it.
	#
	# Different non-gate scenes authored spawn markers with different (or zero)
	# basis rotation, so we cannot blindly trust `marker_n.basis` everywhere.
	# Derive "into the room" from geometry — nearest Door to the marker — and
	# build a fresh transform that always places the player AT the door,
	# facing away from it, so the camera lands behind them and continuing
	# straight walks deeper into the room (not back through the entry door).
	var into_room: Vector3 = _direction_into_room(root, marker_n)
	# Prefer facing the active objective on arrival (unless this is the special
	# gate spawn the cinematic/tests rely on), so the player isn't pointed across
	# a narrow corridor straight into the near wall.
	var forward: Vector3 = into_room
	if marker_n.name == "FromPlanet":
		# Returning from the planet: the marker sits past the platform with its
		# -Z authored to point into the room (toward the exit). The door/waypoint
		# heuristic would flip the player back toward the gate, so trust the
		# marker's own facing here.
		forward = -marker_n.global_transform.basis.z
	elif marker_n.name != "FromGate":
		forward = _arrival_facing(marker_n, into_room)
	# Godot's default forward is -Z; rotating the body by `atan2(-fx, -fz)`
	# aligns -Z with the world-space `forward` vector.
	var yaw: float = atan2(-forward.x, -forward.z)
	var spawn_xform: Transform3D = Transform3D(Basis(Vector3.UP, yaw), marker_n.global_position)
	(player as Node3D).global_transform = spawn_xform
	# Re-sync the camera rig: View._ready() ran before the teleport, so its
	# camera_rotation still reflects the scene-authored player yaw. Without this,
	# the camera lerps to the new position but keeps the old yaw — leaving the
	# player walking sideways or backwards relative to the camera on entry.
	var view: Node = root.get_node_or_null("View")
	if view != null and view.has_method("snap_to_target"):
		view.call("snap_to_target")
	# Auto-walk forward into the room over the fade-in; sells "stepped through
	# the door" rather than "teleported in." Runs concurrently with the fade.
	if player.has_method("auto_walk_to"):
		var walk_to: Vector3 = marker_n.global_position + forward * 0.4
		player.call("auto_walk_to", walk_to, 5.0)

# On arrival, prefer facing the active quest waypoint so the player heads toward
# their objective instead of staring at whatever wall happens to be opposite the
# entry door (a real problem in long corridors entered via a door on the short
# wall). Falls back to `into_room` when there's no waypoint, it's right on top of
# the spawn, or it sits back through the entry door (dot < -0.25).
func _arrival_facing(marker_n: Node3D, into_room: Vector3) -> Vector3:
	var wp: Node = get_tree().get_first_node_in_group("quest_waypoint")
	if wp is Node3D:
		var to_wp: Vector3 = (wp as Node3D).global_position - marker_n.global_position
		to_wp.y = 0.0
		if to_wp.length() > 1.0:
			var dir: Vector3 = to_wp.normalized()
			if dir.dot(into_room) > -0.25:
				return dir
	return into_room

func _find_marker(node: Node, target_name: String) -> Node:
	if node.name == target_name and node is Marker3D:
		return node
	for c in node.get_children():
		var found: Node = _find_marker(c, target_name)
		if found != null:
			return found
	return null

# Direction "into the room" derived from geometry: nearest Door's position is
# behind the player, so we walk away from it. Falls back to the marker's local
# -Z when no door is found (e.g. test scenes without any doors).
func _direction_into_room(root: Node, marker_n: Node3D) -> Vector3:
	if marker_n.name == "FromGate":
		return _marker_forward(marker_n)
	var nearest_door: Node3D = _find_nearest_door(root, marker_n.global_position)
	if nearest_door != null:
		var away: Vector3 = marker_n.global_position - nearest_door.global_position
		away.y = 0.0
		if away.length() > 0.01:
			return away.normalized()
	return _marker_forward(marker_n)

func _marker_forward(marker_n: Node3D) -> Vector3:
	var fallback: Vector3 = -marker_n.global_transform.basis.z
	fallback.y = 0.0
	if fallback.length() < 0.01:
		return Vector3.FORWARD
	return fallback.normalized()

func _find_nearest_door(root: Node, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for n in _gather_doors(root):
		var d: float = (n.global_position - pos).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best

# Doors are scripted Node3Ds; detect by script resource path so we don't depend
# on a class_name being parsed at autoload time.
func _gather_doors(node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("door.gd") and node is Node3D:
		out.append(node)
	for c in node.get_children():
		for d in _gather_doors(c):
			out.append(d)
	return out

func _fade_to(target_alpha: float) -> void:
	if instant_mode:
		_fade_rect.color.a = target_alpha
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", target_alpha, FADE_DURATION)
	await tween.finished
