extends Node3D

# Pause-immune cinematic camera for in-game choreographed beats (the #136
# control-room standoff). While a WoW dialog has the tree paused, this rig
# (PROCESS_MODE_ALWAYS) keeps interpolating: it pulls the view back, glides
# between shots on dialogue cues, and slowly pans around the action so the
# choreography reads instead of hiding behind the dialog panel. The panel
# anchors LEFT, so a negative h_offset biases subjects into the right half
# of the frame.
#
# Pure presentation — never created under SceneRouter.instant_mode, and the
# previous camera is restored on release(). No class_name (headless cold-load
# gotcha); owners preload the script.

var _cam: Camera3D = null
var _prev_cam: Camera3D = null
var _from_pos: Vector3 = Vector3.ZERO
var _from_look: Vector3 = Vector3.ZERO
var _shot_pos: Vector3 = Vector3.ZERO
var _shot_look: Vector3 = Vector3.ZERO
var _last_look: Vector3 = Vector3.ZERO
var _shot_t: float = 0.0
var _shot_dur: float = 1.0
var _orbit_speed: float = 0.0
var _orbit_angle: float = 0.0
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cam = Camera3D.new()
	_cam.name = "CinematicCamera"
	# Wider lens — the first cut at 45° read "zoomed in too much" in play.
	_cam.fov = 55.0
	# Compose the look target right of centre, clear of the dialog window.
	_cam.h_offset = -0.85
	add_child(_cam)


# Per-use lens setup (call after add_child): the standoff uses a wide lens
# with subjects biased right; conversation OTS shots want a tighter lens with
# the speaker biased LEFT (choices float on the right). POSITIVE h_offset
# moves the camera right → subject appears LEFT of frame centre.
func configure(fov: float, h_offset: float) -> void:
	if _cam != null:
		_cam.fov = fov
		_cam.h_offset = h_offset


# Remember the gameplay camera so release() can hand control back.
func activate() -> void:
	if _active:
		return
	_prev_cam = get_viewport().get_camera_3d()
	_active = true


func release() -> void:
	if not _active:
		return
	_active = false
	if _cam != null:
		_cam.current = false
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.current = true


# Move to a new shot: hard cut on the first call, smoothstep glide (`dur`
# seconds) afterwards. `orbit` keeps a slow rad/s pan around the look target
# while the shot holds, so held dialogue beats never feel frozen.
func frame(pos: Vector3, look: Vector3, dur: float = 1.8, orbit: float = 0.1) -> void:
	if _cam == null or not _active:
		return
	var first: bool = not _cam.current
	_from_pos = pos if first else _cam.global_position
	_from_look = look if first else _last_look
	_shot_pos = pos
	_shot_look = look
	_shot_t = 0.0
	_shot_dur = maxf(dur, 0.01)
	_orbit_speed = orbit
	_orbit_angle = 0.0
	_cam.current = true
	_apply(1.0 if first else 0.0)


func _process(delta: float) -> void:
	if not _active or _cam == null or not _cam.current:
		return
	_shot_t += delta
	_orbit_angle += _orbit_speed * delta
	_apply(clampf(_shot_t / _shot_dur, 0.0, 1.0))


func _apply(a: float) -> void:
	a = a * a * (3.0 - 2.0 * a)
	var pos: Vector3 = _from_pos.lerp(_orbited(_shot_pos), a)
	var look: Vector3 = _from_look.lerp(_shot_look, a)
	pos = _pull_clear(pos, look)
	_cam.global_position = pos
	if pos.distance_to(look) > 0.05:
		_cam.look_at(look, Vector3.UP)
	_last_look = look


# The shot position swung around the look target by the accumulated pan angle
# (rotation about UP preserves height).
func _orbited(p: Vector3) -> Vector3:
	return _shot_look + (p - _shot_look).rotated(Vector3.UP, _orbit_angle)


# Keep the camera out of walls: ray from the subject toward the desired
# position (world layer 1); on a hit, tuck the camera just in front of it.
# Tucks that would land on top of the subject (a console edge clipping the
# ray) are rejected — better to graze a prop than stare at the floor from
# inside the furniture.
func _pull_clear(pos: Vector3, look: Vector3) -> Vector3:
	var w3d: World3D = get_world_3d()
	if w3d == null:
		return pos
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	if space == null:
		return pos
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(look, pos, 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		var hp: Vector3 = hit["position"]
		var tucked: Vector3 = hp + (look - hp).normalized() * 0.35
		if tucked.distance_to(look) >= 3.2 and tucked.y >= 1.4:
			return tucked
	return pos
