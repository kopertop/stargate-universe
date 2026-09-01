# camera_controller_test.gd
# Test script for CameraController
# This script demonstrates the camera controller's transition functionality

extends Node

## The camera controller instance
var controller: CameraController

## The camera node to manipulate (if provided)
@onready var camera_node: Camera3D = $Camera

## Debug toggle
var show_debug: bool = true

## Called when the node enters the scene tree
func _ready() -> void:
	# Create a camera controller with default settings
	controller = CameraController.new()
	controller.mode = CameraController.ViewMode.SECTOR
	controller.transition_duration = 1.0
	
	# If a camera node exists, set it up
	if camera_node:
		camera_node.position = controller.get_camera_position()
		camera_node.fov = controller.get_fov()
		add_child(camera_node)
	
	# Print initial state
	print_debug("CameraController Test Initialized")
	print_debug("Initial mode: SECTOR")
	print_debug("Initial position: ", controller.get_camera_position())
	print_debug("Initial FOV: ", controller.get_fov())

## Called every frame
func _process(delta: float) -> void:
	# Update camera controller
	controller.update_transition(delta)
	
	# Apply camera position to camera node if it exists
	if camera_node:
		camera_node.position = controller.get_camera_position()
		camera_node.fov = controller.get_fov()
	
	# Debug output
	if show_debug:
		_debug_ui()

## Press 'S' to switch to station view
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		# Toggle between sector and station views
		if controller.mode == CameraController.ViewMode.SECTOR:
			switch_to_station()
		else:
			switch_to_sector()

## Switch to station view
func switch_to_station() -> void:
	print_debug("Switching to STATION view")
	controller.switch_mode(CameraController.ViewMode.STATION)

## Switch to sector view
func switch_to_sector() -> void:
	print_debug("Switching to SECTOR view")
	controller.switch_mode(CameraController.ViewMode.SECTOR)

## Debug UI output
func _debug_ui() -> void:
	print_debug("Mode: %s" % ["SECTOR", "STATION"][controller.mode])
	print_debug("Transitioning: %s" % ["Yes", "No"][int(controller.transitioning)])
	if controller.transitioning:
		print_debug("Progress: %.2f" % [controller.transition_progress])
	print_debug("Position: %.1f, %.1f, %.1f" % [controller.get_camera_position().x,
		controller.get_camera_position().y, controller.get_camera_position().z])
	print_debug("FOV: %.1f" % [controller.get_fov()])
	print_debug("---")