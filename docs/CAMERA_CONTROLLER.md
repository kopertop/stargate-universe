# Camera Controller Documentation

## Overview

The CameraController manages view transitions between wide sector views and close-up station views in the Stargate Universe. It handles smooth camera interpolation with configurable easing for a polished cinematic experience.

## File Locations

- **Module**: `res://scripts/camera_controller.gd`
- **Test Script**: `res://scripts/camera_controller_test.gd`
- **Test Scene**: `res://scenes/camera_controller_test.tscn`

## Core Concepts

### View Modes

The system supports two camera views:

1. **SECTOR VIEW** (`ViewMode.SECTOR`)
   - Wide orbital perspective
   - Position: `Vector3(0, 40, 60)`
   - FOV: `50.0`
   - Ideal for seeing the whole station and surrounding space

2. **STATION VIEW** (`ViewMode.STATION`)
   - Close-up first-person/perspective view
   - Position: `Vector3(0, 12, 18)`
   - FOV: `55.0`
   - Ideal for detailed inspection of modules and areas

### Camera States

The controller tracks:
- `mode`: Current view mode (SECTOR or STATION)
- `transitioning`: Whether a transition is in progress
- `transition_progress`: Animation progress (0.0 to 1.0)
- `from_mode`: The mode we're transitioning from (only valid during transitions)

## Usage Guide

### Basic Setup

```gdscript
extends Node3D

@onready var camera: Camera3D = $Camera

var controller: CameraController

func _ready() -> void:
	# Create the camera controller
	controller = CameraController.new()
	
	# Set initial mode
	controller.mode = CameraController.ViewMode.SECTOR
	
	# Configure transition duration
	controller.transition_duration = 1.5
	
	# Set initial camera position
	camera.position = controller.get_camera_position()
	camera.fov = controller.get_fov()
```

### Using in the Game Loop

```gdscript
func _process(delta: float) -> void:
	# Update the controller
	controller.update_transition(delta)
	
	# Apply position to your camera
	if camera:
		camera.position = controller.get_camera_position()
		camera.fov = controller.get_fov()
	
	# Optionally look at a target
	if camera and target:
		camera.look_at(target.global_position)
```

### Switching Views Programmatically

```gdscript
# Switch to station view
controller.switch_mode(CameraController.ViewMode.STATION)

# Switch back to sector view
controller.switch_mode(CameraController.ViewMode.SECTOR)
```

### Custom Presets

You can customize camera positions:

```gdscript
# Get current preset position
var position = controller.get_preset_position(CameraController.ViewMode.STATION)
print("Station view position: ", position)
```

## API Reference

### CameraController Class

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `mode` | `ViewMode` | Current view mode (SECTOR or STATION) |
| `transitioning` | `bool` | Whether a transition is in progress |
| `transition_progress` | `float` | Animation progress (0.0 to 1.0) |
| `from_mode` | `ViewMode` | Mode we're transitioning from |
| `transition_duration` | `float` | Duration of transition in seconds (default: 1.0) |

#### Methods

##### `switch_mode(new_mode: ViewMode) -> void`

Switches the view mode and starts the transition animation.
- `new_mode`: The target ViewMode (SECTOR or STATION)
- The transition automatically interpolates position and FOV using ease-in-out cubic easing

##### `update_transition(delta_time: float) -> void`

Updates the transition animation. Call this every frame in `_process()`.
- `delta_time`: Time elapsed since the last frame

##### `get_camera_position() -> Vector3`

Returns the interpolated camera position.
- Returns current mode's preset position if not transitioning
- Returns interpolated position during transition

##### `get_fov() -> float`

Returns the interpolated field of view.
- Returns current mode's preset FOV if not transitioning
- Returns interpolated FOV during transition

##### `get_preset_position(mode: ViewMode) -> Vector3`

Returns the preset position for a specific view mode.
- `mode`: Target ViewMode

##### `get_preset_fov(mode: ViewMode) -> float`

Returns the preset FOV for a specific view mode.
- `mode`: Target ViewMode

## Easing

The camera uses an **ease-in-out cubic** function for smooth animation:

- First 50% of transition: Accelerates (ease-in)
- Middle: Constant rate
- Last 50% of transition: Decelerates (ease-out)

This provides a natural, cinematic camera movement.

## Integration Examples

### Example 1: View Transition Trigger

```gdscript
# In some interactable or UI event
func on_enter_station_inspection() -> void:
	# Switch to station view
	controller.switch_mode(CameraController.ViewMode.STATION)
	
	# Optionally disable controls during transition
	is_transitioning = true

func _process(delta: float) -> void:
	controller.update_transition(delta)
	if controller.mode == CameraController.ViewMode.STATION:
		camera.position = controller.get_camera_position()
		camera.look_at_inspection_target()
	
	if not controller.transitioning:
		is_transitioning = false
```

### Example 2: Dynamic Duration

```gdscript
# Switch to station view with different duration
controller.switch_mode(CameraController.ViewMode.STATION)
controller.transition_duration = 0.5  # Quick transition

# Or use a variable duration
var inspection_duration: float = 3.0
controller.transition_duration = inspection_duration
controller.switch_mode(CameraController.ViewMode.STATION)
```

### Example 3: Multiple Cameras

```gdscript
extends Node3D

@onready var camera1: Camera3D = $Camera1
@onready var camera2: Camera3D = $Camera2
@onready var ui_camera: Camera3D = $UI/CanvasLayer/Camera

var controller: CameraController

func _ready() -> void:
	controller = CameraController.new()
	
	# During gameplay
	camera1.position = controller.get_camera_position()
	camera2.position = controller.get_camera_position()
	ui_camera.position = controller.get_camera_position()

func switch_to_station_inspection() -> void:
	controller.switch_mode(CameraController.ViewMode.STATION)
	
	# Force camera update to be current
	camera1.make_current()
```

## Best Practices

1. **Always call `update_transition(delta)`** every frame in `_process()`
2. **Check `transitioning` flag** before triggering other UI/controls during animation
3. **Use appropriate durations**:
   - Quick transitions (0.5-1.0s) for navigation
   - Medium transitions (1.0-2.0s) for scene changes
   - Longer transitions (2.0s+) for cinematic moments
4. **Preserve `look_at` targets** during transitions if camera has a target

## Testing

Run the test scene to verify functionality:
```
res://scenes/camera_controller_test.tscn
```

Press the UI accept key (typically Space or Enter) to toggle between sector and station views and observe the smooth animation.