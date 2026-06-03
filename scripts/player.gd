extends CharacterBody3D

# SGU third-person player controller (Eli Wallace).
# Camera-relative WASD movement. Sprint toggle. Interact ray points where the
# camera looks. No double-jump or fall-respawn (kit platformer bits removed).

signal interact_target_changed(target: Node)
signal auto_walk_finished

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Movement")
@export var walk_speed: float = 8.0          # m/s
@export var sprint_multiplier: float = 1.7
@export var accel_smoothing: float = 12.0
@export var gravity_strength: float = 25.0
@export var jump_strength: float = 5.5

@export_subgroup("Interact")
@export var interact_reach: float = 3.5      # metres — general "look + E" range
# Clicking an interactable selects it and lets you interact from this larger
# range, so you can pick someone slightly further off and step in to talk.
@export var interact_reach_targeted: float = 6.0
@export var interact_origin_height: float = 1.1  # chest height
# Minimum facing alignment (dot of camera-forward vs direction to target) for a
# candidate to count — keeps us from grabbing something behind the player.
@export var interact_min_aim: float = 0.1

var _gravity_velocity: float = 0.0
var _move_velocity: Vector3 = Vector3.ZERO
var _facing_yaw: float = 0.0
var _current_interactable: Node = null
# Sticky target set by clicking an interactable. Wins over the look-based pick
# and is reachable from the extended range. Cleared when it leaves range, gets
# disabled, or the player clicks empty space / another interactable.
var _clicked_target: Node = null
var _input_locked: bool = false   # locked during cutscene / scene transitions
# When set, the locked idle pose plays this clip instead of "idle" (e.g.
# "holding-both" while Eli holds the Kino remote, piloting the drone).
var _pose_override: String = ""
var _auto_walking: bool = false
var _auto_walk_target: Vector3 = Vector3.ZERO
var _auto_walk_speed: float = 5.0
var _auto_walk_arrive_dist: float = 0.18
# Cinematic dash: collision-FREE sprint to a point (used by cutscenes so the
# actor can never snag on terrain/props). Moves by direct position + a ground
# ray, with body collision disabled — clipping is intentionally off here.
var _cinematic_dash: bool = false
var _dash_target: Vector3 = Vector3.ZERO
var _dash_speed: float = 12.0

# Footsteps — random individual samples played on a distance-based cadence: one
# step per ~FOOTSTEP_STRIDE metres of floor travel, so faster speeds produce
# faster steps without per-frame timing math. Pitch jitters per step so repeats
# don't sound mechanical. The SAMPLE SET is chosen per-environment by
# FootstepLibrary (issue #33): metal on the ship / alien-tech decks, dirt /
# desert / water / swamp on planet surfaces. LOCATION is authoritative — the
# player defaults to metal (so EVERY ship scene sounds metal regardless of any
# lingering active_planet_spec), and the planet scene PUSHES its biome surface
# via set_footstep_surface() once its spec is finalized. (Reading the persisted
# spec in _ready was the "clanky metal on the desert planet" bug: the player's
# _ready runs before the parent planet assigns the spec.) Per-surface gain keeps
# soft ground quieter than metal.
const _FOOTSTEP_LIBRARY: Script = preload("res://scripts/footstep_library.gd")
const FOOTSTEP_STRIDE: float = 1.9
var _footstep_surface: String = "metal"   # FootstepLibrary.DEFAULT_SURFACE
var _footstep_streams: Array = []
var _footstep_distance: float = 0.0
# The SoundFootsteps node's authored volume_db; the per-surface gain is added to it.
var _footstep_base_volume_db: float = 0.0

@onready var _particles_trail: GPUParticles3D = $ParticlesTrail
@onready var _sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var _model: Node3D = $Character
# AnimationPlayer lives inside the glTF root (e.g. Character/Model/AnimationPlayer
# for Kenney Mini Characters). Recursive find keeps player.gd resilient if the
# asset wrapper ever moves it around. Kept optional so static-mesh characters
# still boot without animation.
@onready var _animation: AnimationPlayer = _find_animation_player($Character)

# Kenney Mini Characters share a palette texture; the glTF import loses the
# embedded baseColorTexture binding so meshes render pure white. Re-apply the
# shared StandardMaterial3D to every surface in the character hierarchy.
const _COLORMAP_MAT: Material = preload("res://models/colormap.tres")
const _EQUIPMENT_MOUNT_SCRIPT: Script = preload("res://scripts/equipment_mount.gd")

# Renders equipped gear (#72) on the character. Lives under $Character so its
# BoneAttachment3D sockets can find the Skeleton3D inside $Character/Model.
var _equipment_mount: Node3D = null

func _ready() -> void:
	_apply_colormap(_model)
	_setup_equipment_mount()
	_init_footsteps()

func _setup_equipment_mount() -> void:
	if _model == null:
		return
	var mount: Node3D = _EQUIPMENT_MOUNT_SCRIPT.new()
	mount.name = "EquipmentMount"
	var inv: Node = get_tree().root.get_node_or_null("Inventory") if get_tree() != null else null
	mount.call("setup", _model, inv)
	# Parent under the model wrapper so fallback offset nodes ride the body and
	# the mount can locate the skeleton. add_child triggers the mount's _ready,
	# which does the first reconcile against the current loadout.
	_model.add_child(mount)
	_equipment_mount = mount

func _apply_colormap(root: Node) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, _COLORMAP_MAT)
	for c in root.get_children():
		_apply_colormap(c)

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null

func _physics_process(delta: float) -> void:
	if _cinematic_dash:
		_drive_cinematic_dash(delta)
		return
	if _auto_walking:
		_drive_auto_walk(delta)
		return
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
	# A pose override (e.g. "holding-both" while piloting the Kino) takes the
	# place of plain idle. Driven every frame so the locomotion logic can't
	# stomp it back to "idle".
	_play_anim(_pose_override if _pose_override != "" else "idle", 0.15)

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
	# Negated atan2 args put body yaw in Godot's -Z-forward convention so the
	# body yaw at idle (= view yaw) matches the body yaw during forward motion.
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.2:
		_facing_yaw = atan2(-velocity.x, -velocity.z)
	elif view != null:
		_facing_yaw = view.rotation.y
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 12.0)

	_drive_locomotion_anim()
	_update_footsteps(delta)

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_gravity_velocity = max(_gravity_velocity, 0.0)
	else:
		_gravity_velocity += gravity_strength * delta

func _drive_locomotion_anim() -> void:
	_particles_trail.emitting = false
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		if horiz_speed > 0.25:
			var is_sprinting: bool = horiz_speed > walk_speed * 1.15
			_play_anim("sprint" if is_sprinting else "walk", 0.1)
			# Sprint clip is already fast; only scale walk by speed ratio.
			var pitch_ratio: float = clampf(horiz_speed / walk_speed, 0.4, sprint_multiplier)
			if _animation != null:
				_animation.speed_scale = 1.0 if is_sprinting else pitch_ratio
			if pitch_ratio > 1.2:
				_particles_trail.emitting = true
		else:
			_play_anim("idle", 0.1)
			if _animation != null:
				_animation.speed_scale = 1.0
	else:
		# Rising → jump clip; descending → fall clip (graceful fallback to jump
		# if the model only has one airborne anim).
		var airborne_anim: String = "jump" if _gravity_velocity < 0.0 else "fall"
		_play_anim(airborne_anim, 0.1)
		if _animation != null:
			_animation.speed_scale = 1.0


# Capture the authored footstep volume and default to the ship surface (metal).
# Ship scenes never override, so they always sound metal; the planet scene calls
# set_footstep_surface() with its biome surface once its spec is resolved.
func _init_footsteps() -> void:
	if _sound_footsteps != null:
		_footstep_base_volume_db = _sound_footsteps.volume_db
	set_footstep_surface(_FOOTSTEP_LIBRARY.DEFAULT_SURFACE)


# Switch the active footstep surface (sample set + per-surface volume). Public so
# the planet scene can push the biome's surface; falls back to metal for an
# unknown id. Volume = authored base + the surface's gain (soft ground = quieter).
func set_footstep_surface(surface_id: String) -> void:
	_footstep_surface = surface_id if _FOOTSTEP_LIBRARY.has_surface(surface_id) else _FOOTSTEP_LIBRARY.DEFAULT_SURFACE
	_footstep_streams = _FOOTSTEP_LIBRARY.load_streams(_footstep_surface)
	if _sound_footsteps != null:
		_sound_footsteps.volume_db = _footstep_base_volume_db + _FOOTSTEP_LIBRARY.gain_db_for(_footstep_surface)


# Distance-based footstep cadence: accumulate horizontal travel and emit a
# random footstep sample every FOOTSTEP_STRIDE metres on the floor. Resets
# when airborne or stopped so the next stride starts fresh.
func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		_footstep_distance = 0.0
		return
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed < 0.5:
		_footstep_distance = 0.0
		return
	_footstep_distance += horiz_speed * delta
	if _footstep_distance >= FOOTSTEP_STRIDE:
		_footstep_distance -= FOOTSTEP_STRIDE
		_emit_footstep()


func _emit_footstep() -> void:
	if _footstep_streams.is_empty() or _sound_footsteps == null:
		return
	_sound_footsteps.stream = _footstep_streams[randi() % _footstep_streams.size()]
	_sound_footsteps.stream_paused = false
	_sound_footsteps.pitch_scale = randf_range(0.9, 1.1)
	_sound_footsteps.play()

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
	var camera: Camera3D = _interact_camera()
	if camera == null:
		return null
	var origin: Vector3 = global_position + Vector3.UP * interact_origin_height
	# A clicked target wins while it's still valid + within the extended range.
	if _target_in_range(_clicked_target, origin, interact_reach_targeted):
		return _clicked_target
	_clicked_target = null
	# Otherwise pick the best in-range interactable in FRONT of the player.
	# Score = facing alignment minus a small distance penalty, with a big bonus
	# for the current quest target so the "diamond" NPC wins when two are close.
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return null
	forward = forward.normalized()
	var quest_anchor: String = _quest_anchor_name()
	var best: Node = null
	var best_score: float = -INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var n3: Node3D = node as Node3D
		if n3 == null or not _interactable_enabled(n3):
			continue
		var to: Vector3 = n3.global_position - origin
		to.y = 0.0
		var dist: float = to.length()
		if dist > interact_reach or dist < 0.05:
			continue
		var aim: float = forward.dot(to / dist)
		if aim < interact_min_aim:
			continue
		var score: float = aim - dist * 0.05
		if quest_anchor != "" and n3.name == quest_anchor:
			score += 100.0
		if score > best_score:
			best_score = score
			best = n3
	return best


func _interact_camera() -> Camera3D:
	if view == null:
		return null
	var cam: Camera3D = view.get_node_or_null("SpringArm/Camera")
	if cam == null:
		cam = view.get_node_or_null("Camera")
	return cam


func _interactable_enabled(n: Node) -> bool:
	# Skip nodes disabled (e.g. Kino pickup after acquisition) so the HUD prompt
	# doesn't stick on a stale target.
	return not ("enabled" in n and not n.get("enabled"))


func _target_in_range(node: Node, origin: Vector3, reach: float) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_in_group("interactable"):
		return false
	if not _interactable_enabled(node):
		return false
	var n3: Node3D = node as Node3D
	if n3 == null:
		return false
	var flat: Vector3 = n3.global_position - origin
	flat.y = 0.0
	return flat.length() <= reach


# Node name of the current quest target's anchor (the "diamond" NPC/object), so
# the look-based pick can prefer it. Empty for sentinel anchors (e.g. nearest-
# console) which aren't real node names — those fall back to facing/nearest.
func _quest_anchor_name() -> String:
	if GameState == null or not GameState.has_method("quest_target"):
		return ""
	var t: Variant = GameState.call("quest_target")
	if t is Dictionary:
		return String((t as Dictionary).get("anchor", ""))
	return ""


# Click an interactable to select it (extends reach + makes the target obvious
# via the HUD prompt). Clicking empty space clears the selection.
func _unhandled_input(event: InputEvent) -> void:
	if _input_locked or _auto_walking:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_click_target(mb.position)


func _try_click_target(screen_pos: Vector2) -> void:
	var camera: Camera3D = _interact_camera()
	if camera == null:
		return
	# Mouselook captures the cursor at screen centre — pick from there instead.
	var pos: Vector2 = screen_pos
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pos = get_viewport().get_visible_rect().size * 0.5
	var from: Vector3 = camera.project_ray_origin(pos)
	var dir: Vector3 = camera.project_ray_normal(pos)
	var to: Vector3 = from + dir * (interact_reach_targeted + 6.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self.get_rid()]
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 4
	var hit: Dictionary = space.intersect_ray(params)
	var picked: Node = null
	if not hit.is_empty():
		var n: Node = hit.get("collider") as Node
		while n != null:
			if n.is_in_group("interactable"):
				picked = n
				break
			n = n.get_parent()
	var origin: Vector3 = global_position + Vector3.UP * interact_origin_height
	if picked != null and _target_in_range(picked, origin, interact_reach_targeted):
		_clicked_target = picked
	else:
		_clicked_target = null

func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		_move_velocity = Vector3.ZERO

# Override the locked-idle pose with a specific clip (""/empty restores idle).
func set_pose_override(anim: String) -> void:
	_pose_override = anim

# Drive the player toward a world-space target on a straight line. Locks input
# for the duration. Used by door transitions to sell "walked through the door"
# rather than fade-cutting between scenes. Emits `auto_walk_finished` when the
# player arrives within `_auto_walk_arrive_dist` of the target.
func auto_walk_to(target_world_pos: Vector3, speed: float = 5.0) -> void:
	_auto_walk_target = Vector3(target_world_pos.x, global_position.y, target_world_pos.z)
	_auto_walk_speed = max(speed, 0.1)
	_auto_walking = true
	_input_locked = true

# Cinematic dash — collision-FREE sprint to a world point. For cutscenes only:
# the actor cannot snag on terrain/props (clipping off) and won't trip scene
# triggers (collision_layer cleared). Emits auto_walk_finished on arrival.
func cinematic_dash_to(target_world_pos: Vector3, speed: float = 12.0) -> void:
	_dash_target = target_world_pos
	_dash_speed = maxf(speed, 0.1)
	_cinematic_dash = true
	_auto_walking = false
	_input_locked = true
	collision_layer = 0          # don't trip Area triggers (e.g. the return gate)
	collision_mask = 0           # we move by position, not move_and_slide

func _drive_cinematic_dash(delta: float) -> void:
	var to_target: Vector3 = _dash_target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < _auto_walk_arrive_dist:
		_cinematic_dash = false
		_play_anim("idle", 0.1)
		auto_walk_finished.emit()
		return
	var dir: Vector3 = to_target.normalized()
	var np: Vector3 = global_position + dir * _dash_speed * delta
	np.y = _ground_y(np, global_position.y)
	global_position = np
	_facing_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 16.0)
	_play_anim("sprint", 0.1)
	if _animation != null:
		_animation.speed_scale = 1.0

# Ground height under `at` via a downward ray against the terrain (layer 1), so
# the dash follows hills instead of clipping through or floating over them.
func _ground_y(at: Vector3, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return fallback
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(at.x, at.y + 30.0, at.z), Vector3(at.x, at.y - 80.0, at.z), 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		return (hit["position"] as Vector3).y
	return fallback

func _drive_auto_walk(delta: float) -> void:
	var to_target: Vector3 = _auto_walk_target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < _auto_walk_arrive_dist:
		_auto_walking = false
		_input_locked = false
		_move_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		_apply_gravity(delta)
		move_and_slide()
		_play_anim("idle", 0.1)
		auto_walk_finished.emit()
		return
	var dir: Vector3 = to_target.normalized()
	_move_velocity = dir * _auto_walk_speed
	_facing_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 16.0)
	_apply_gravity(delta)
	velocity = Vector3(_move_velocity.x, -_gravity_velocity, _move_velocity.z)
	move_and_slide()
	_play_anim("walk", 0.1)
	if _animation != null:
		_animation.speed_scale = 1.0
	_update_footsteps(delta)
