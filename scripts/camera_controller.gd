# CameraController.gd
# Camera controller for view transitions between sector and station views.
# Manages camera position interpolation between wide sector view and close-up station view.

## View modes for the camera
enum ViewMode {
	SECTOR = 0,
	STATION = 1
}

## Camera state tracked by the controller
class_name CameraController
extends Node

## Current view mode
var mode: ViewMode = ViewMode.SECTOR

## Whether a transition between views is in progress
var transitioning: bool = false

## Transition progress: 0 = start (previous mode), 1 = complete (current mode)
var transition_progress: float = 1.0

## The mode we're transitioning FROM (set when transitioning begins)
var from_mode: ViewMode = ViewMode.SECTOR

## Default transition duration in seconds
var transition_duration: float = 1.0

## Accumulated transition time in seconds
var _transition_time: float = 0.0

## Preset camera positions for each view
const CAMERA_PRESETS = {
	ViewMode.SECTOR: {
		"position": Vector3(0.0, 40.0, 60.0),
		"fov": 50.0
	},
	ViewMode.STATION: {
		"position": Vector3(0.0, 12.0, 18.0),
		"fov": 55.0
	}
}

## Called when the node enters the scene tree
func _ready() -> void:
	pass

## Switch to a different view mode.
## Starts a transition animation from the current mode to the new one.
func switch_mode(new_mode: ViewMode) -> void:
	if mode == new_mode and not transitioning:
		return
	
	from_mode = mode
	mode = new_mode
	transitioning = true
	transition_progress = 0.0
	_transition_time = 0.0

## Update the transition animation by a delta time.
## Call this every frame from the main loop.
func update_transition(delta_time: float) -> void:
	if not transitioning:
		return
	
	_transition_time += delta_time
	var raw_progress = minf(_transition_time / transition_duration, 1.0)
	transition_progress = raw_progress
	
	if raw_progress >= 1.0:
		transitioning = false
		transition_progress = 1.0

## Get the current camera position, interpolated during transitions.
func get_camera_position() -> Vector3:
	if not transitioning:
		return CAMERA_PRESETS[mode].position
	
	var from_pos = CAMERA_PRESETS[from_mode].position
	var to_pos = CAMERA_PRESETS[mode].position
	var t = _ease_in_out_cubic(transition_progress)
	return from_pos.lerp(to_pos, t)

## Get the current field of view, interpolated during transitions.
func get_fov() -> float:
	if not transitioning:
		return CAMERA_PRESETS[mode].fov
	
	var from_fov = CAMERA_PRESETS[from_mode].fov
	var to_fov = CAMERA_PRESETS[mode].fov
	var t = _ease_in_out_cubic(transition_progress)
	return lerp(from_fov, to_fov, t)

## Get the preset camera position for a specific mode.
func get_preset_position(mode: ViewMode) -> Vector3:
	return CAMERA_PRESETS[mode].position

## Get the preset FOV for a specific mode.
func get_preset_fov(mode: ViewMode) -> float:
	return CAMERA_PRESETS[mode].fov

## Easing function: ease-in-out cubic for smooth camera movement.
func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0