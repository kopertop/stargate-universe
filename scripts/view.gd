extends Node3D

@export_group("Properties")
@export var target: Node3D
# Vertical offset added to the target position when placing the view rig — keeps
# the camera framed on the character's chest instead of its feet.
@export var follow_height: float = 0.9

@export_group("Zoom")
@export var zoom_minimum: float = 16.0
@export var zoom_maximum: float = 4.0
@export var zoom_speed: float = 10.0
@export var wheel_zoom_step: float = 1.0

@export_group("Rotation")
@export var rotation_speed: float = 120.0
# Degrees-per-pixel; 0.15 ≈ comfortable WoW-ish feel.
@export var mouse_sensitivity: float = 0.15
# Initial yaw offset behind the player (degrees). 0 = directly behind.
@export var initial_yaw_offset: float = 0.0
@export var follow_speed: float = 10.0

var camera_rotation: Vector3
var zoom: float = 10.0
var mouselook_active: bool = false

@onready var camera: Camera3D = $SpringArm/Camera
@onready var spring: SpringArm3D = $SpringArm

func _ready() -> void:
	# Preserve the scene's tuned pitch/distance; only nudge yaw to sit behind the target.
	camera_rotation = rotation_degrees
	if target != null:
		# SpringArm3D extends along view's local +Z. With view yaw = player yaw
		# (= π at spawn), view's +Z in world = -Z, putting the camera BEHIND the
		# player (player faces +Z after the spawn 180° rotation). No yaw offset
		# needed; matching view yaw to player yaw also avoids a spawn-time
		# snap-rotation of the body.
		camera_rotation.y = rad_to_deg(target.rotation.y) + initial_yaw_offset
		rotation_degrees = camera_rotation
		# Snap position to target so the very first frame is framed correctly —
		# otherwise the lerp in _physics_process gives a few frames where the
		# camera sits at world origin and the player is offscreen.
		position = target.position + Vector3.UP * follow_height
	# Seed zoom from the spring length the scene was authored with, so the lerp
	# in _physics_process doesn't crash-zoom out to the 10.0 default on entry.
	if spring != null:
		zoom = spring.spring_length

# Use _input (not _unhandled_input) so the HUD Control doesn't eat mouse events.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mouselook_active = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clampf(zoom - wheel_zoom_step, zoom_maximum, zoom_minimum)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clampf(zoom + wheel_zoom_step, zoom_maximum, zoom_minimum)
	elif event is InputEventMouseMotion and mouselook_active:
		# screen_relative is resolution-independent; relative is viewport pixels.
		camera_rotation.y -= event.screen_relative.x * mouse_sensitivity
		camera_rotation.x -= event.screen_relative.y * mouse_sensitivity
		camera_rotation.x = clampf(camera_rotation.x, -80.0, -10.0)

func _physics_process(delta: float) -> void:
	if target != null:
		position = position.lerp(target.position + Vector3.UP * follow_height, delta * follow_speed)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6.0)
	# SpringArm3D auto-raycasts to keep camera from clipping walls/ceiling.
	spring.spring_length = lerpf(spring.spring_length, zoom, 8.0 * delta)
	handle_input(delta)

func handle_input(delta: float) -> void:
	var input: Vector3 = Vector3.ZERO
	input.y = Input.get_axis("camera_left", "camera_right")
	input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clampf(camera_rotation.x, -80.0, -10.0)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clampf(zoom, zoom_maximum, zoom_minimum)
