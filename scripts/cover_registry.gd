class_name CoverRegistry
extends Node

## Utility node (NOT an autoload) that tracks all CoverPoint nodes in the
## current scene. CoverPoint Area3D nodes register themselves on _ready and
## unregister on _exit_tree. Provides spatial queries for the combat system:
##
##   get_nearest_cover(from_position) → CoverPoint or null
##   is_position_in_cover(position, threat_position) → bool
##
## Cover detection uses a 3D raycast from the threat toward the position. If
## the ray hits a StaticBody3D (wall, crate, console) before reaching the
## target position, the position is "in cover" — the line of sight is blocked.
##
## Lifecycle: a CoverRegistry is auto-created by the first CoverPoint that
## registers, or manually placed in a scene. It lives in the scene tree (not
## as an autoload) so it's naturally scoped to the current level and is
## cleaned up on scene change.

signal cover_entered(point: Node)
signal cover_exited(point: Node)

const COVER_GROUP: String = "cover_point"
const RAY_MARGIN: float = 0.1
const COVER_RAY_LENGTH: float = 100.0

var _cover_points: Array[Node] = []


func _ready() -> void:
	set_process(false)


## Register a CoverPoint node. Called by CoverPoint._ready().
func register_cover(point: Node) -> void:
	if point == null or _cover_points.has(point):
		return
	_cover_points.append(point)
	cover_entered.emit(point)


## Unregister a CoverPoint node. Called by CoverPoint._exit_tree().
func unregister_cover(point: Node) -> void:
	_cover_points.erase(point)
	cover_exited.emit(point)


## Returns all registered cover points.
func all_cover_points() -> Array[Node]:
	return _cover_points.duplicate()


## Returns the nearest CoverPoint to `from_position`, or null if none exist.
func get_nearest_cover(from_position: Vector3) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for cp in _cover_points:
		if not (cp is Node3D):
			continue
		var n3d: Node3D = cp as Node3D
		var cp_pos: Vector3 = n3d.global_position if n3d.is_inside_tree() else n3d.position
		var d: float = cp_pos.distance_squared_to(from_position)
		if d < best_dist:
			best_dist = d
			best = cp
	return best


## Returns true if the line from `threat_position` to `position` is blocked
## by a static collider (wall, furniture, etc.). Uses a raycast query against
## the physics world — safe in headless (returns false if no world_3d).
func is_position_in_cover(position: Vector3, threat_position: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = _get_space_state()
	if space == null:
		return false
	var dir: Vector3 = (position - threat_position).normalized()
	var dist: float = position.distance_to(threat_position)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	params.from = threat_position + dir * RAY_MARGIN
	params.to = threat_position + dir * minf(dist, COVER_RAY_LENGTH)
	params.collision_mask = 1  # World geometry layer
	params.exclude = []
	var result: Dictionary = space.intersect_ray(params)
	if result.is_empty():
		return false
	# If the ray hit something BEFORE reaching the target position, the
	# target is behind cover.
	var hit_pos: Vector3 = result.get("position", Vector3.ZERO)
	var hit_dist: float = threat_position.distance_to(hit_pos)
	return hit_dist < dist - RAY_MARGIN


## Returns true if `position` is within `radius` metres of any registered
## CoverPoint. Used by CombatSystem for the "in cover" status that reduces
## enemy hit chance.
func is_near_cover_point(position: Vector3, radius: float = 1.5) -> bool:
	var r_sq: float = radius * radius
	for cp in _cover_points:
		if not (cp is Node3D):
			continue
		var n3d: Node3D = cp as Node3D
		var cp_pos: Vector3 = n3d.global_position if n3d.is_inside_tree() else n3d.position
		if cp_pos.distance_squared_to(position) <= r_sq:
			return true
	return false


## Returns the CoverPoint the player is currently standing in, or null.
func cover_point_at(position: Vector3, radius: float = 1.5) -> Node:
	var best: Node = null
	var best_dist: float = INF
	var r_sq: float = radius * radius
	for cp in _cover_points:
		if not (cp is Node3D):
			continue
		var n3d: Node3D = cp as Node3D
		var cp_pos: Vector3 = n3d.global_position if n3d.is_inside_tree() else n3d.position
		var d: float = cp_pos.distance_squared_to(position)
		if d <= r_sq and d < best_dist:
			best_dist = d
			best = cp
	return best


func _get_space_state() -> PhysicsDirectSpaceState3D:
	# CoverRegistry extends Node (not Node3D), so we find a World3D
	# via the scene root or any Node3D child in the tree.
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var scene: Node = tree.current_scene
	# Try the scene root's children for a Node3D with a world.
	for child in scene.get_children():
		if child is Node3D:
			var ws: World3D = (child as Node3D).get_world_3d()
			if ws != null:
				return ws.direct_space_state
	# Fall back to any Node3D in the tree.
	var n3d: Node = tree.get_first_node_in_group("cover_point")
	if n3d != null and n3d is Node3D:
		var ws2: World3D = (n3d as Node3D).get_world_3d()
		if ws2 != null:
			return ws2.direct_space_state
	return null