extends Node

# Aim assist system for Stargate Universe. Provides three modes:
#   1. Magnetic pull — gently biases the camera/aim toward nearby interactables
#      and valid targets. Strength scales from 0 (off) to 1 (strong).
#   2. Snap-to-target — on interact press, snaps the crosshair to the nearest
#      valid target within a wider cone.
#   3. Friction — slows mouse/look speed when hovering near a valid target,
#      making it easier to hold aim on a target.
#
# This is a UTILITY node, not an autoload. The player controller or view
# queries AimAssist each frame for a bias vector or snap target. The system
# reads from AccessibilitySettings for configuration.
#
# Usage from view.gd / player.gd:
#   var bias := AimAssist.get_aim_bias(camera_forward, camera_global_pos)
#   if bias.length() > 0:
#       camera_yaw += bias.x * delta
#       camera_pitch += bias.y * delta

signal target_snapped(target: Node)

const SNAP_CONE_DOT: float = 0.7        # ~45° half-angle for snap eligibility
const SNAP_MAX_DISTANCE: float = 15.0   # metres
const PULL_CONE_DOT: float = 0.9        # ~25° half-angle for magnetic pull
const PULL_MAX_DISTANCE: float = 10.0   # metres
const FRICTION_RADIUS_DOT: float = 0.95 # ~18° radius for friction zone
const FRICTION_FACTOR: float = 0.4      # multiplier applied to look speed in friction zone

var _settings: Node = null


func _ready() -> void:
	_settings = get_node_or_null("/root/AccessibilitySettings")
	set_process(false)  # Passive — queried by the player controller, not ticked.


# Get a 2D bias vector (yaw, pitch) to add to the camera look this frame.
# Returns Vector2.ZERO if aim assist is off or no target is in range.
# camera_forward: the current camera forward direction (Vector3, global)
# camera_origin: the camera's global position (Vector3)
func get_aim_bias(camera_forward: Vector3, camera_origin: Vector3) -> Vector2:
	if _settings == null:
		return Vector2.ZERO
	var strength: float = _settings.aim_assist_strength
	if strength <= 0.0:
		return Vector2.ZERO

	var target := _find_best_target(camera_forward, camera_origin, PULL_CONE_DOT, PULL_MAX_DISTANCE)
	if target == null:
		return Vector2.ZERO

	# Direction from camera to target.
	var to_target: Vector3 = (target.global_position - camera_origin).normalized()
	# Compute yaw and pitch delta to steer toward the target.
	var current_yaw: float = atan2(-camera_forward.x, -camera_forward.z)
	var target_yaw: float = atan2(-to_target.x, -to_target.z)
	var yaw_delta: float = _shortest_angle_delta(current_yaw, target_yaw)

	var current_pitch: float = asin(camera_forward.y)
	var target_pitch: float = asin(to_target.y)
	var pitch_delta: float = target_pitch - current_pitch

	# Scale by strength and a gentle ramp (stronger when closer to target).
	var dot: float = camera_forward.dot(to_target)
	var ramp: float = clampf((dot - PULL_CONE_DOT) / (1.0 - PULL_CONE_DOT), 0.0, 1.0)
	var scale: float = strength * ramp * 2.0  # degrees per frame at max

	return Vector2(rad_to_deg(yaw_delta) * scale, rad_to_deg(pitch_delta) * scale)


# Snap to the nearest valid target. Called on interact press when snap is enabled.
# Returns the target Node if a snap occurred, null otherwise.
func try_snap(camera_forward: Vector3, camera_origin: Vector3) -> Node:
	if _settings == null or not _settings.aim_assist_snap:
		return null
	var target := _find_best_target(camera_forward, camera_origin, SNAP_CONE_DOT, SNAP_MAX_DISTANCE)
	if target != null:
		target_snapped.emit(target)
	return target


# Check if the current aim is within the friction zone of a target.
# Returns a friction multiplier (1.0 = no friction, FRICTION_FACTOR = max friction).
func get_look_friction(camera_forward: Vector3, camera_origin: Vector3) -> float:
	if _settings == null or not _settings.aim_assist_friction:
		return 1.0
	var target := _find_best_target(camera_forward, camera_origin, FRICTION_RADIUS_DOT, PULL_MAX_DISTANCE)
	if target == null:
		return 1.0
	var to_target: Vector3 = (target.global_position - camera_origin).normalized()
	var dot: float = camera_forward.dot(to_target)
	# Smooth ramp: at FRICTION_RADIUS_DOT, friction starts; at dot=1.0, full friction.
	var t: float = clampf((dot - FRICTION_RADIUS_DOT) / (1.0 - FRICTION_RADIUS_DOT), 0.0, 1.0)
	return lerpf(1.0, FRICTION_FACTOR, t)


# ── Internal ───────────────────────────────────────────────────────────────────────

func _find_best_target(camera_forward: Vector3, camera_origin: Vector3,
		min_dot: float, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_dot: float = min_dot
	# Search interactables group (populated by Interactable nodes).
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node3D:
			continue
		var n3d: Node3D = node as Node3D
		var to_target: Vector3 = n3d.global_position - camera_origin
		var dist: float = to_target.length()
		if dist > max_dist:
			continue
		var dir: Vector3 = to_target.normalized()
		var dot: float = camera_forward.dot(dir)
		if dot > best_dot:
			best_dot = dot
			best = n3d
	# Also search NPCs (for combat / dialogue targeting).
	for node in get_tree().get_nodes_in_group("npc"):
		if not node is Node3D:
			continue
		var n3d: Node3D = node as Node3D
		var to_target: Vector3 = n3d.global_position - camera_origin
		var dist: float = to_target.length()
		if dist > max_dist:
			continue
		var dir: Vector3 = to_target.normalized()
		var dot: float = camera_forward.dot(dir)
		if dot > best_dot:
			best_dot = dot
			best = n3d
	return best


func _shortest_angle_delta(from: float, to: float) -> float:
	var delta: float = to - from
	while delta > PI:
		delta -= TAU
	while delta < -PI:
		delta += TAU
	return delta