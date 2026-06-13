extends Node3D

@export_group("Properties")
@export var target: Node3D
# Vertical offset added to the target position when placing the view rig — keeps
# the camera framed on the character's chest instead of its feet. Tuned for the
# real-scale modular avatar (~1.6 m); the old kit chibi used 0.9.
@export var follow_height: float = 1.15

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
# Pitch limits. PITCH_MAX > 0 lets the camera dip BELOW the character and
# point UP at the ceiling. Negative = looking down; positive = looking up.
@export var pitch_min: float = -80.0
@export var pitch_max: float = 20.0
# Above this pitch (i.e. as the rig swings under the horizon), the spring
# arm interpolates from the player-chosen `zoom` toward `zoom_maximum` so
# the character stays framed instead of receding to the bottom of screen.
@export var pitch_zoom_in_threshold: float = -10.0

var camera_rotation: Vector3
var zoom: float = 10.0
var mouselook_active: bool = false

@onready var camera: Camera3D = $SpringArm/Camera
@onready var spring: SpringArm3D = $SpringArm

func _ready() -> void:
	# Preserve the scene's tuned pitch/distance; only nudge yaw to sit behind the target.
	camera_rotation = rotation_degrees
	snap_to_target()
	# Seed zoom from the spring length the scene was authored with, so the lerp
	# in _physics_process doesn't crash-zoom out to the 10.0 default on entry.
	if spring != null:
		zoom = spring.spring_length
	# Dialog/pause hook: _input stops firing once the tree is paused, so a player
	# who hits E while holding RMB never gets the RMB-release event delivered.
	# We listen for the dialog lifecycle directly (signals are pause-immune) and
	# drop mouselook + un-capture the cursor so dialog choices are clickable.
	GameState.dialog_started.connect(_on_dialog_started)
	GameState.dialog_closed.connect(_on_dialog_closed)
	GameState.kino_closed.connect(_on_dialog_closed)


func _on_dialog_started(_npc: Node3D, _tree: Array) -> void:
	_release_mouselook()


func _on_dialog_closed() -> void:
	_release_mouselook()


func _release_mouselook() -> void:
	mouselook_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Snap the camera rig to sit directly behind the target with the authored pitch.
# Called from _ready() at scene load, and from SceneRouter after a cross-scene
# transition (which teleports the player without firing _ready again).
func snap_to_target() -> void:
	if target == null:
		return
	# Match view yaw to player yaw so SpringArm3D's local +Z lands behind the
	# player. Skips the body snap-rotation that an offset would trigger.
	camera_rotation.y = rad_to_deg(target.rotation.y) + initial_yaw_offset
	rotation_degrees = camera_rotation
	position = target.position + Vector3.UP * follow_height

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
		camera_rotation.x = clampf(camera_rotation.x, pitch_min, pitch_max)

func _physics_process(delta: float) -> void:
	if target != null:
		position = position.lerp(target.position + Vector3.UP * follow_height, delta * follow_speed)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6.0)
	# SpringArm3D auto-raycasts to keep camera from clipping walls/ceiling.
	# When pitch swings above the horizon threshold (rig dipping under the
	# player to look up), pull the spring in toward `zoom_maximum` so the
	# character doesn't recede off-screen.
	var target_spring: float = zoom
	if camera_rotation.x > pitch_zoom_in_threshold:
		var t: float = inverse_lerp(pitch_zoom_in_threshold, pitch_max, camera_rotation.x)
		target_spring = lerpf(zoom, zoom_maximum, clampf(t, 0.0, 1.0))
	spring.spring_length = lerpf(spring.spring_length, target_spring, 8.0 * delta)
	handle_input(delta)

func handle_input(delta: float) -> void:
	var input: Vector3 = Vector3.ZERO
	input.y = Input.get_axis("camera_left", "camera_right")
	input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clampf(camera_rotation.x, pitch_min, pitch_max)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clampf(zoom, zoom_maximum, zoom_minimum)
