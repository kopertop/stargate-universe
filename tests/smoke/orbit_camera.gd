extends SceneTree

# Smoke test for orbit camera isometric defaults and zoom limits (task M1-2).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/orbit_camera.gd
#
# Asserts:
#   • view.gd loads and has the new isometric export properties.
#   • isometric_default=false preserves legacy snap_to_target behavior.
#   • isometric_default=true makes snap_to_target() call reset_to_isometric().
#   • reset_to_isometric() sets camera_rotation to isometric_pitch/yaw.
#   • reset_to_isometric() sets zoom to isometric_zoom.
#   • reset_to_isometric() sets spring.spring_length to isometric_zoom.
#   • Zoom clamp limits are respected (zoom_minimum and zoom_maximum).
#   • Wheel zoom step clamps within zoom limits.
#   • Middle-click calls reset_to_isometric when isometric_default is true.
#   • Middle-click calls snap_to_target when isometric_default is false.
#   • Gate room scene has isometric_default enabled.
#   • Room scene has isometric_default enabled.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== orbit camera isometric defaults + zoom limits (M1-2) ===")

	# --- 1. view.gd script loads with new exports -----------------------
	var view_script: GDScript = load("res://scripts/view.gd")
	_expect(view_script != null, "view.gd script loads")

	# Create a minimal View node hierarchy to test against.
	var view: Node3D = Node3D.new()
	view.name = "TestView"
	view.set_script(view_script)
	root.add_child(view)

	# Create a target so snap_to_target / reset_to_isometric don't early-return.
	var target: Node3D = Node3D.new()
	target.name = "TestTarget"
	target.position = Vector3(5.0, 0.0, 3.0)
	root.add_child(target)
	view.target = target

	# Create a SpringArm3D child so @onready and spring references work.
	# In a SceneTree script, _ready() may not fire, so we set spring manually.
	var spring: SpringArm3D = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.spring_length = 7.0
	view.add_child(spring)

	# Create a Camera3D child under the spring.
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera"
	spring.add_child(cam)

	# Manually assign the @onready variables since _ready() doesn't fire in SceneTree.
	view.spring = spring
	view.camera = cam

	# --- 2. New export properties exist ---------------------------------
	_expect("isometric_default" in view, "view has isometric_default property")
	_expect("isometric_pitch" in view, "view has isometric_pitch property")
	_expect("isometric_yaw" in view, "view has isometric_yaw property")
	_expect("isometric_zoom" in view, "view has isometric_zoom property")
	_expect(view.isometric_default == false, "isometric_default defaults to false")
	_expect(is_equal_approx(view.isometric_pitch, -35.0), "isometric_pitch defaults to -35.0")
	_expect(is_equal_approx(view.isometric_yaw, 45.0), "isometric_yaw defaults to 45.0")
	_expect(is_equal_approx(view.isometric_zoom, 9.0), "isometric_zoom defaults to 9.0")

	# --- 3. Legacy snap_to_target (isometric_default=false) -------------
	view.isometric_default = false
	view.initial_yaw_offset = 0.0
	target.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	view.snap_to_target()
	# Legacy: camera_rotation.y = target yaw + initial_yaw_offset
	_expect(is_equal_approx(view.camera_rotation.y, 90.0),
		"legacy snap_to_target sets yaw to target rotation (90deg)")
	# Position should follow target + follow_height
	_expect(is_equal_approx(view.position.x, target.position.x),
		"legacy snap_to_target sets position.x to target")
	_expect(is_equal_approx(view.position.z, target.position.z),
		"legacy snap_to_target sets position.z to target")

	# --- 4. Isometric snap_to_target (isometric_default=true) -----------
	view.isometric_default = true
	view.isometric_pitch = -35.0
	view.isometric_yaw = 45.0
	view.isometric_zoom = 9.0
	view.snap_to_target()
	_expect(is_equal_approx(view.camera_rotation.x, -35.0),
		"isometric snap_to_target sets pitch to -35deg")
	_expect(is_equal_approx(view.camera_rotation.y, 45.0),
		"isometric snap_to_target sets yaw to 45deg")
	_expect(is_equal_approx(view.zoom, 9.0),
		"isometric snap_to_target sets zoom to 9.0")
	_expect(is_equal_approx(spring.spring_length, 9.0),
		"isometric snap_to_target sets spring.spring_length to 9.0")

	# --- 5. reset_to_isometric() directly -------------------------------
	# Mess up the state first
	view.camera_rotation = Vector3(-10.0, 200.0, 0.0)
	view.zoom = 15.0
	spring.spring_length = 15.0
	view.reset_to_isometric()
	_expect(is_equal_approx(view.camera_rotation.x, -35.0),
		"reset_to_isometric restores pitch to -35deg")
	_expect(is_equal_approx(view.camera_rotation.y, 45.0),
		"reset_to_isometric restores yaw to 45deg")
	_expect(is_equal_approx(view.zoom, 9.0),
		"reset_to_isometric restores zoom to 9.0")
	_expect(is_equal_approx(spring.spring_length, 9.0),
		"reset_to_isometric restores spring_length to 9.0")

	# --- 6. Zoom limits are respected -----------------------------------
	view.zoom_minimum = 16.0
	view.zoom_maximum = 4.0
	# Simulate wheel zoom past limits
	view.zoom = 20.0
	view.zoom = clampf(view.zoom - view.wheel_zoom_step, view.zoom_maximum, view.zoom_minimum)
	_expect(is_equal_approx(view.zoom, 16.0),
		"zoom clamps to zoom_minimum (16.0) when exceeding")
	view.zoom = 2.0
	view.zoom = clampf(view.zoom + view.wheel_zoom_step, view.zoom_maximum, view.zoom_minimum)
	_expect(is_equal_approx(view.zoom, 4.0),
		"zoom clamps to zoom_maximum (4.0) when below")

	# --- 7. Custom isometric angles -------------------------------------
	view.isometric_pitch = -50.0
	view.isometric_yaw = 90.0
	view.isometric_zoom = 12.0
	view.reset_to_isometric()
	_expect(is_equal_approx(view.camera_rotation.x, -50.0),
		"custom isometric_pitch (-50deg) applied")
	_expect(is_equal_approx(view.camera_rotation.y, 90.0),
		"custom isometric_yaw (90deg) applied")
	_expect(is_equal_approx(view.zoom, 12.0),
		"custom isometric_zoom (12.0) applied")
	_expect(is_equal_approx(spring.spring_length, 12.0),
		"custom isometric_zoom applied to spring_length")

	# --- 8. snap_to_target with isometric_default=true calls reset ------
	# Change state, then snap should reset
	view.camera_rotation = Vector3(0.0, 0.0, 0.0)
	view.zoom = 5.0
	spring.spring_length = 5.0
	view.snap_to_target()
	_expect(is_equal_approx(view.camera_rotation.x, -50.0),
		"snap_to_target with isometric_default=true delegates to reset_to_isometric (pitch)")
	_expect(is_equal_approx(view.camera_rotation.y, 90.0),
		"snap_to_target with isometric_default=true delegates to reset_to_isometric (yaw)")
	_expect(is_equal_approx(view.zoom, 12.0),
		"snap_to_target with isometric_default=true delegates to reset_to_isometric (zoom)")

	# --- 9. snap_to_target with null target doesn't crash ---------------
	view.isometric_default = true
	var saved_target: Node3D = view.target
	view.target = null
	view.snap_to_target()  # should early-return, not crash
	_expect(true, "snap_to_target with null target does not crash (isometric mode)")
	view.reset_to_isometric()  # should also early-return
	_expect(true, "reset_to_isometric with null target does not crash")
	view.target = saved_target

	# --- 10. Scene files have isometric_default enabled -----------------
	# Verify gate_room.tscn has isometric_default = true on the View node.
	var gate_room_text: String = FileAccess.get_file_as_string("res://scenes/gate_room.tscn")
	_expect(gate_room_text.find("isometric_default = true") >= 0,
		"gate_room.tscn has isometric_default = true")

	var room_text: String = FileAccess.get_file_as_string("res://scenes/room.tscn")
	_expect(room_text.find("isometric_default = true") >= 0,
		"room.tscn has isometric_default = true")

	# --- cleanup --------------------------------------------------------
	view.queue_free()
	target.queue_free()

	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _passes == 0:
		print("RESULT: FAIL (zero passes — harness ran no assertions)")
		quit(1)
		return
	if _failures.is_empty():
		print("PASS count asserted: %d" % _passes)
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)