extends Node3D

@export_group("Properties")
@export var target: Node3D

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
@export var initial_pitch: float = -25.0
@export var follow_speed: float = 10.0

var camera_rotation: Vector3
var zoom: float = 10.0
var mouselook_active: bool = false

@onready var camera: Camera3D = $Camera

func _ready() -> void:
	# Start behind the target: yaw matches target's facing + offset, pitch is a sane down-angle.
	var target_yaw_deg: float = 0.0
	if target != null:
		target_yaw_deg = rad_to_deg(target.rotation.y) + 180.0 + initial_yaw_offset
	camera_rotation = Vector3(initial_pitch, target_yaw_deg, 0.0)
	rotation_degrees = camera_rotation
	if target != null:
		position = target.position

func _unhandled_input(event: InputEvent) -> void:
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
		position = position.lerp(target.position, delta * follow_speed)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6.0)
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), 8.0 * delta)
	handle_input(delta)

func handle_input(delta: float) -> void:
	var input: Vector3 = Vector3.ZERO
	input.y = Input.get_axis("camera_left", "camera_right")
	input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clampf(camera_rotation.x, -80.0, -10.0)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clampf(zoom, zoom_maximum, zoom_minimum)
