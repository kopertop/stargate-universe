extends Node3D

const _DEMO_CAPTURE: Script = preload("res://scripts/demo_capture.gd")

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

@export_group("Combat")
# Mixamo combat: mouse always looks while captured; RMB is aim (owned by player).
# Distances match the signed-off rifle showcase (OTS ~2.65 hip / ~2.5 aim), not
# the ship platformer spring (~7 m).
@export var combat_look: bool = false
@export var combat_aiming: bool = false
@export var combat_crouching: bool = false
@export var combat_hip_zoom: float = 3.2
@export var combat_aim_zoom: float = 2.55
@export var combat_aim_shoulder: float = 0.55
@export var combat_hip_fov: float = 52.0
@export var combat_aim_fov: float = 36.0
# Standing chest follow vs crouch (showcase drops OTS height on AIM_CROUCH).
@export var combat_hip_follow_height: float = 1.28
@export var combat_aim_follow_height: float = 1.12
@export var combat_crouch_follow_height: float = 0.88
# While ADS, look_at a point ahead of the follow pivot so screen-center is the
# aim point (showcase OTS_LOOK_AHEAD). Without this, shoulder offset alone leaves
# the camera parallel to the spring and the crosshair drifts off true aim.
@export var combat_aim_look_ahead: float = 2.8
@export var combat_aim_look_right: float = 0.12
@export var combat_aim_look_up: float = 0.05
# ADS settle rates — kept snappy so aim framing does not wait on Target Lock.
@export var combat_ads_blend_rate: float = 16.0
@export var combat_follow_height_rate: float = 14.0

var camera_rotation: Vector3
var zoom: float = 10.0
var mouselook_active: bool = false
var _shoulder_blend: float = 0.0
var _follow_height_live: float = -1.0

@onready var camera: Camera3D = $SpringArm/Camera
@onready var spring: SpringArm3D = $SpringArm
var xray: CameraXRay = null

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

	# X-ray occlusion fade (issue #139): created dynamically so scenes don't
	# need to carry the node. Headless / instant_mode skips it entirely so
	# smoke tests stay deterministic.
	var sr: Node = get_tree().root.get_node_or_null("SceneRouter")
	var instant: bool = sr != null and bool(sr.get("instant_mode"))
	if not instant:
		xray = CameraXRay.new()
		xray.name = "CameraXRay"
		add_child(xray)
		xray.setup(camera)
		# Track the player (the view's @export target) as the primary subject.
		if target != null:
			xray.track_subject(target)


func set_combat_look(enabled: bool) -> void:
	combat_look = enabled
	if enabled:
		# Pull the spring in to showcase hip distance (scene springs are ~7 m).
		zoom = combat_hip_zoom
		if spring != null:
			spring.spring_length = combat_hip_zoom
		if camera != null:
			camera.fov = combat_hip_fov
		if not _capture_suppressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _capture_suppressed() -> bool:
	return bool(_DEMO_CAPTURE.is_demo_capture(get_tree()))


func set_combat_aiming(aiming: bool, crouching: bool = false) -> void:
	combat_aiming = aiming
	combat_crouching = aiming and crouching


func set_combat_crouching(crouching: bool) -> void:
	combat_crouching = crouching and combat_aiming


func _on_dialog_started(_npc: Node3D, _tree: Array) -> void:
	combat_aiming = false
	combat_crouching = false
	_release_mouselook()


func _on_dialog_closed() -> void:
	_release_mouselook()
	if combat_look and not _capture_suppressed():
		# Dialog/Kino closed — resume always-look capture for Mixamo combat.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	var h: float = follow_height
	if combat_look:
		h = combat_hip_follow_height
	_follow_height_live = h
	position = target.position + Vector3.UP * h

# Use _input (not _unhandled_input) so the HUD Control doesn't eat mouse events.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if combat_look:
				# RMB is aim — owned by player. Still ensure capture for look.
				if event.pressed and not _capture_suppressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				mouselook_active = event.pressed
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_LEFT and combat_look and event.pressed:
			if not _capture_suppressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if combat_look:
				var lo: float = 2.2
				var hi: float = 6.5
				if combat_aiming:
					combat_aim_zoom = clampf(combat_aim_zoom - wheel_zoom_step, lo, hi)
				else:
					combat_hip_zoom = clampf(combat_hip_zoom - wheel_zoom_step, lo, hi)
			else:
				zoom = clampf(zoom - wheel_zoom_step, zoom_maximum, zoom_minimum)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if combat_look:
				var lo2: float = 2.2
				var hi2: float = 6.5
				if combat_aiming:
					combat_aim_zoom = clampf(combat_aim_zoom + wheel_zoom_step, lo2, hi2)
				else:
					combat_hip_zoom = clampf(combat_hip_zoom + wheel_zoom_step, lo2, hi2)
			else:
				zoom = clampf(zoom + wheel_zoom_step, zoom_maximum, zoom_minimum)
	elif event is InputEventMouseMotion:
		var looking: bool = combat_look and (
			_capture_suppressed() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		)
		looking = looking or (not combat_look and mouselook_active)
		# Movie Maker / demo capture: ignore host OS mouse so recording stays clean.
		if _capture_suppressed():
			looking = false
		if looking:
			# screen_relative is resolution-independent; relative is viewport pixels.
			camera_rotation.y -= event.screen_relative.x * mouse_sensitivity
			camera_rotation.x -= event.screen_relative.y * mouse_sensitivity
			camera_rotation.x = clampf(camera_rotation.x, pitch_min, pitch_max)

func _physics_process(delta: float) -> void:
	var height: float = _combat_follow_height(delta)
	if target != null:
		# ADS / crouch: track the body more tightly so framing does not lag the pose.
		var track: float = follow_speed * (1.55 if combat_look and combat_aiming else 1.0)
		position = position.lerp(target.position + Vector3.UP * height, delta * track)
	_steer_toward_target_lock(delta)
	var rot_rate: float = 14.0 if (combat_look and combat_aiming) else 6.0
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * rot_rate)
	# SpringArm3D auto-raycasts to keep camera from clipping walls/ceiling.
	# When pitch swings above the horizon threshold (rig dipping under the
	# player to look up), pull the spring in toward `zoom_maximum` so the
	# character doesn't recede off-screen.
	var want_zoom: float = zoom
	if combat_look:
		want_zoom = combat_aim_zoom if combat_aiming else combat_hip_zoom
	var target_spring: float = want_zoom
	if camera_rotation.x > pitch_zoom_in_threshold and not (combat_look and combat_aiming):
		var t: float = inverse_lerp(pitch_zoom_in_threshold, pitch_max, camera_rotation.x)
		target_spring = lerpf(want_zoom, zoom_maximum, clampf(t, 0.0, 1.0))
	var zoom_rate: float = combat_ads_blend_rate if (combat_look and combat_aiming) else 8.0
	spring.spring_length = lerpf(spring.spring_length, target_spring, zoom_rate * delta)

	# Soft OTS shoulder offset while aiming — snappy so ADS does not wait on lock.
	var want_shoulder: float = 1.0 if (combat_look and combat_aiming) else 0.0
	var shoulder_rate: float = combat_ads_blend_rate if combat_aiming else 10.0
	_shoulder_blend = lerpf(_shoulder_blend, want_shoulder, minf(1.0, delta * shoulder_rate))
	if spring != null:
		spring.position.x = combat_aim_shoulder * _shoulder_blend

	if camera != null and combat_look:
		var want_fov: float = combat_aim_fov if combat_aiming else combat_hip_fov
		var fov_rate: float = combat_ads_blend_rate if combat_aiming else 10.0
		camera.fov = lerpf(camera.fov, want_fov, minf(1.0, delta * fov_rate))
		_apply_combat_aim_look(delta)
	elif camera != null:
		# Leave non-combat cameras on spring-local identity.
		camera.rotation = camera.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))

	handle_input(delta)


func _combat_follow_height(delta: float) -> float:
	var want: float = follow_height
	if combat_look:
		if combat_aiming and combat_crouching:
			want = combat_crouch_follow_height
		elif combat_aiming:
			want = combat_aim_follow_height
		else:
			want = combat_hip_follow_height
	if _follow_height_live < 0.0:
		_follow_height_live = want
	else:
		var rate: float = combat_follow_height_rate if combat_look else follow_speed
		_follow_height_live = lerpf(_follow_height_live, want, minf(1.0, delta * rate))
	return _follow_height_live


## Converge Camera3D so viewport center is the aim cursor.
## Locked: look at the lock point (crosshair == target). Unlocked: look-ahead.
func _apply_combat_aim_look(delta: float) -> void:
	if camera == null:
		return
	# Apply as soon as ADS starts — do not wait for shoulder blend to wake up.
	if not combat_aiming and _shoulder_blend < 0.02:
		camera.rotation = camera.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
		return
	var look: Vector3
	var locked_look: Vector3 = _lock_look_point()
	if locked_look != Vector3.INF:
		look = locked_look
	else:
		var blend: float = maxf(_shoulder_blend, 1.0 if combat_aiming else 0.0)
		var focus: Vector3 = global_position
		var forward: Vector3 = -global_transform.basis.z
		var right: Vector3 = global_transform.basis.x
		look = (
			focus
			+ forward * combat_aim_look_ahead
			+ right * (combat_aim_look_right * blend)
			+ Vector3.UP * combat_aim_look_up
		)
	if camera.global_position.distance_squared_to(look) < 0.0001:
		return
	camera.look_at(look, Vector3.UP)


func _lock_look_point() -> Vector3:
	if target == null:
		return Vector3.INF
	if not target.has_method("has_target_lock") or not bool(target.call("has_target_lock")):
		return Vector3.INF
	if not target.has_method("get_lock_aim_point"):
		return Vector3.INF
	return target.call("get_lock_aim_point") as Vector3


## Soft-steer camera yaw/pitch toward the player's Target Lock aim point.
func _steer_toward_target_lock(delta: float) -> void:
	if not combat_look or target == null:
		return
	if not target.has_method("has_target_lock") or not bool(target.call("has_target_lock")):
		return
	if not target.has_method("get_lock_aim_point"):
		return
	var aim: Vector3 = target.call("get_lock_aim_point") as Vector3
	var from: Vector3 = global_position
	var to: Vector3 = aim - from
	if to.length_squared() < 0.01:
		return
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return
	# Match player/body yaw convention: -Z forward.
	var want_yaw: float = rad_to_deg(atan2(-flat.x, -flat.z))
	var elev: float = rad_to_deg(atan2(to.y, flat.length()))
	# camera_rotation.x: negative = look down (same as mouse look in this rig).
	var want_pitch: float = clampf(-elev * 0.85, pitch_min, pitch_max)
	var t: float = minf(1.0, delta * 14.0)
	camera_rotation.y = rad_to_deg(lerp_angle(deg_to_rad(camera_rotation.y), deg_to_rad(want_yaw), t))
	camera_rotation.x = lerpf(camera_rotation.x, want_pitch, t)


## Instant snap used by Movie Maker / tests after acquiring a lock.
func snap_toward_aim_point(aim: Vector3) -> void:
	var from: Vector3 = global_position
	var to: Vector3 = aim - from
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return
	camera_rotation.y = rad_to_deg(atan2(-flat.x, -flat.z))
	var elev: float = rad_to_deg(atan2(to.y, flat.length()))
	camera_rotation.x = clampf(-elev * 0.85, pitch_min, pitch_max)
	rotation_degrees = camera_rotation



func handle_input(delta: float) -> void:
	var input: Vector3 = Vector3.ZERO
	input.y = Input.get_axis("camera_left", "camera_right")
	input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clampf(camera_rotation.x, pitch_min, pitch_max)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clampf(zoom, zoom_maximum, zoom_minimum)
