extends Node3D

@export_group("Properties")
@export var target: Node

@export_group("Zoom")
@export var zoom_minimum = 16
@export var zoom_maximum = 4
@export var zoom_speed = 10
@export var wheel_zoom_step = 1.0

@export_group("Rotation")
@export var rotation_speed = 120
@export var mouse_sensitivity = 0.2

var camera_rotation: Vector3
var zoom = 10
var mouselook_active := false

@onready var camera = $Camera

func _ready():
	camera_rotation = rotation_degrees

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mouselook_active = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clamp(zoom - wheel_zoom_step, zoom_maximum, zoom_minimum)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clamp(zoom + wheel_zoom_step, zoom_maximum, zoom_minimum)
	elif event is InputEventMouseMotion and mouselook_active:
		camera_rotation.y -= event.relative.x * mouse_sensitivity
		camera_rotation.x -= event.relative.y * mouse_sensitivity
		camera_rotation.x = clamp(camera_rotation.x, -80, -10)

func _physics_process(delta):
	self.position = self.position.lerp(target.position, delta * 4)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), 8 * delta)
	handle_input(delta)

func handle_input(delta):
	var input := Vector3.ZERO
	input.y = Input.get_axis("camera_left", "camera_right")
	input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clamp(camera_rotation.x, -80, -10)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clamp(zoom, zoom_maximum, zoom_minimum)
