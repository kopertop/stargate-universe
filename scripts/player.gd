extends CharacterBody3D

# SGU third-person player controller (Eli Wallace).
# Camera-relative WASD movement. Sprint toggle. Interact ray points where the
# camera looks. No double-jump or fall-respawn (kit platformer bits removed).

signal interact_target_changed(target: Node)

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Movement")
@export var walk_speed: float = 4.0          # m/s
@export var sprint_multiplier: float = 1.7
@export var accel_smoothing: float = 12.0
@export var gravity_strength: float = 25.0
@export var jump_strength: float = 5.5

@export_subgroup("Interact")
@export var interact_reach: float = 2.4      # metres
@export var interact_origin_height: float = 1.1  # chest height

var _gravity_velocity: float = 0.0
var _move_velocity: Vector3 = Vector3.ZERO
var _facing_yaw: float = 0.0
var _current_interactable: Node = null
var _input_locked: bool = false   # locked during cutscene / scene transitions

@onready var _particles_trail: GPUParticles3D = $ParticlesTrail
@onready var _sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var _model: Node3D = $Character
# Static meshes (Kenney Mini Characters) ship without an AnimationPlayer — keep
# the reference optional so we can swap in skeletal characters later without
# scene surgery.
@onready var _animation: AnimationPlayer = $Character.get_node_or_null("AnimationPlayer")

# Kenney Mini Characters share a palette texture; the glTF import loses the
# embedded baseColorTexture binding so meshes render pure white. Re-apply the
# shared StandardMaterial3D to every surface in the character hierarchy.
const _COLORMAP_MAT: Material = preload("res://models/colormap.tres")

func _ready() -> void:
	_apply_colormap(_model)

func _apply_colormap(root: Node) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, _COLORMAP_MAT)
	for c in root.get_children():
		_apply_colormap(c)

func _physics_process(delta: float) -> void:
	if _input_locked:
		_apply_idle(delta)
		return
	_handle_movement(delta)
	_handle_interact()

func _apply_idle(delta: float) -> void:
	_move_velocity = Vector3.ZERO
	_apply_gravity(delta)
	velocity = Vector3(0.0, -_gravity_velocity, 0.0)
	move_and_slide()
	_play_anim("idle", 0.15)

func _handle_movement(delta: float) -> void:
	# Camera-relative input.
	var input_vec: Vector3 = Vector3.ZERO
	input_vec.x = Input.get_axis("move_left", "move_right")
	input_vec.z = Input.get_axis("move_forward", "move_back")
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	if view != null:
		input_vec = input_vec.rotated(Vector3.UP, view.rotation.y)

	var target_speed: float = walk_speed
	if Input.is_action_pressed("sprint"):
		target_speed *= sprint_multiplier

	var target_velocity: Vector3 = input_vec * target_speed
	_move_velocity = _move_velocity.lerp(target_velocity, accel_smoothing * delta)

	_apply_gravity(delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		_gravity_velocity = -jump_strength
		Audio.play("res://sounds/jump.ogg")

	velocity = Vector3(_move_velocity.x, -_gravity_velocity, _move_velocity.z)
	move_and_slide()

	# Face direction of motion (or camera yaw when standing still).
	var horiz: Vector2 = Vector2(velocity.z, velocity.x)
	if horiz.length() > 0.2:
		_facing_yaw = horiz.angle()
	elif view != null:
		_facing_yaw = view.rotation.y
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 12.0)

	_drive_locomotion_anim()

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_gravity_velocity = max(_gravity_velocity, 0.0)
	else:
		_gravity_velocity += gravity_strength * delta

func _drive_locomotion_anim() -> void:
	_particles_trail.emitting = false
	_sound_footsteps.stream_paused = true
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		if horiz_speed > 0.25:
			_play_anim("walk", 0.1)
			var pitch_ratio: float = clampf(horiz_speed / walk_speed, 0.4, sprint_multiplier)
			_sound_footsteps.stream_paused = false
			_sound_footsteps.pitch_scale = 1.0 + (pitch_ratio - 1.0) * 0.6
			if _animation != null:
				_animation.speed_scale = pitch_ratio
			if pitch_ratio > 1.2:
				_particles_trail.emitting = true
		else:
			_play_anim("idle", 0.1)
			if _animation != null:
				_animation.speed_scale = 1.0
	else:
		_play_anim("jump", 0.1)
		if _animation != null:
			_animation.speed_scale = 1.0

func _play_anim(name: String, blend: float) -> void:
	if _animation == null:
		return
	if not _animation.has_animation(name):
		return
	if _animation.current_animation == name:
		return
	_animation.play(name, blend)

func _handle_interact() -> void:
	var target: Node = _find_interact_target()
	if target != _current_interactable:
		_current_interactable = target
		interact_target_changed.emit(target)
	if target != null and Input.is_action_just_pressed("interact"):
		if target.has_method("interact"):
			target.interact(self)

func _find_interact_target() -> Node:
	if view == null:
		return null
	var camera: Camera3D = view.get_node_or_null("SpringArm/Camera")
	if camera == null:
		camera = view.get_node_or_null("Camera")
	if camera == null:
		return null
	# Cast from the player's chest forward along the camera's yaw.
	var origin: Vector3 = global_position + Vector3.UP * interact_origin_height
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return null
	forward = forward.normalized()
	var to: Vector3 = origin + forward * interact_reach
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to)
	params.exclude = [self.get_rid()]
	params.collide_with_areas = true
	params.collide_with_bodies = true
	# Layer 4 reserved for interactable areas/bodies.
	params.collision_mask = 4
	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider == null:
		return null
	# Walk up the tree looking for the first node in group "interactable".
	var n: Node = collider as Node
	while n != null:
		if n.is_in_group("interactable"):
			return n
		n = n.get_parent()
	return null

func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		_move_velocity = Vector3.ZERO
