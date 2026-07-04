extends Node3D

## Raycast-driven occluder fading system for gameplay and cinematic cameras.
## When geometry blocks the view of tracked subjects, fade it to ~25% alpha
## instead of pulling the camera in or hiding the actor.
##
## Usage (in camera scripts):
##   @onready var xray = $XRay if has_node("XRay") else null
##   if xray: xray.track_subject(active_subject)
##
## To mark props as xray-able (should auto-populate at spawn):
##   extends RoomBuilder or set-dressing script
##   if instance is MeshInstance3D and has_colliding_bodies():
##       XRayRegistry.register(instance, colliding_bodies[0])
##
## Excluded categories (no fade):
##   Floors, skybox/hull, doors mid-transition, gate, anything with "no_xray" tag

class_name CameraXRay extends Node3D

var _camera: Camera3D = null
var _subjects: Array[Node3D] = []
var _occluders: Dictionary = {}
var _exclude_tags: PackedStringArray = [
	"no_xray", "floor", "skybox", "hull", "door", "gate"
]

# Raycast settings
const _max_distance: float = 30.0
const _fade_threshold: float = 0.3  # Alpha level below which we restore
const _fade_speed: float = 6.67  # 0.15s to reach 0.25 alpha (lerp factor)

# Hysteresis: require N consecutive clear frames before restore
const _restore_hysteresis_threshold: int = 3
var _clear_frames: int = 0


func _ready() -> void:
	# Auto-find camera node
	_camera = $Camera3D if has_node("Camera3D") else self
	if _camera == self and !has_node("Camera3D"):
		push_error("CameraXRay requires a Camera3D child node named 'Camera3D'")
		set_process(false)
		return


func track_subject(subject: Node3D) -> void:
	if subject == null:
		_subjects.clear()
		return

	if not _subjects.has(subject):
		_subjects.append(subject)


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return

	if _subjects.is_empty():
		_restore_all_fades()
		return

	var space = get_world_3d().direct_space_state
	if space == null:
		return

	# Raycast from camera toward each subject
	for subject in _subjects:
		if not is_instance_valid(subject):
			continue

		var start = _camera.global_position
		var end = subject.global_position
		var direction = (end - start).normalized()

		var hits = space.intersect_ray(
			start, end, direction, _max_distance,
			CollisionMask3D.DEFAULT, true
		)

		# Process each hit
		for hit in hits:
			var collider = hit.collider
			if not is_instance_valid(collider):
				continue

			var mesh = _get_mesh_for_collider(collider)
			if mesh != null and not mesh is Viewport:
				_fade_occluder(mesh, hit.distance)


# Fade an occluder toward 25% alpha over configured speed
func _fade_occluder(mesh: MeshInstance3D, distance: float) -> void:
	if not mesh is GeometryInstance3D:
		return

	# Check if already at or below target fade level
	if mesh.transparency >= _fade_threshold - 0.01:
		_clear_frames += 1
	else:
		_clear_frames = 0
		_restore_all_fades()
		return

	# Fade in only if occluder is in front of camera (not behind)
	var mesh_pos = mesh.global_position
	var to_camera = _camera.global_position.distance_to(mesh_pos)
	# Allow slightly behind for objects clipped at edge of view
	if to_camera > _max_distance * 1.5:
		return

	var current_t = mesh.transparency
	var target_t = 0.25

	# Smoothly fade toward target
	if current_t < target_t:
		var lerped = lerp(current_t, target_t, delta * _fade_speed)
		mesh.transparency = lerped
	else:
		mesh.transparency = target_t


# Restore all faded occluders (gradual restore for natural feel)
func _restore_all_fades() -> void:
	for mesh in _occluders.values():
		if mesh is GeometryInstance3D and mesh.transparency > 0.01:
			mesh.transparency = maxf(mesh.transparency - delta * 5.0, 0.0)


# Find the MeshInstance3D associated with a collider
# Maintains a reverse lookup for room builder/set-dressing
func _get_mesh_for_collider(collider: Node3D) -> MeshInstance3D | null:
	# Check direct parent chain for MeshInstance3D
	var node = collider
	while node != null:
		if node is MeshInstance3D:
			return node
		node = node.get_parent()

	return null


## Registry for collider → MeshInstance3D mappings.
## Room builder and set-dressing scripts should call this at spawn.
class_name XRayRegistry extends Node3D

static var _registry: Dictionary = {}

static func register(mesh: MeshInstance3D, collider: Node3D) -> void:
	# Store mapping from collider to the mesh that provides visual
	if not _registry.has(collider):
		_registry[collider] = mesh

static func get_mesh(collider: Node3D) -> MeshInstance3D | null:
	return _registry.get(collider, null)

static func clear() -> void:
	_registry.clear()