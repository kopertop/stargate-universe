extends Node3D

## Mixamo rifle combat showcase — gameplay-style controls.
## Requires local build: tools/blender_mixamo_rifle_combat.py → Swat_rifle_combat.glb
##
## Controls:
##   WASD move · Shift sprint · Space jump
##   Mouse look · RMB aim (draws rifle; auto-crouch unless moving) · LMB fire (while aiming)
##   Esc quit · H holster-tune (dev)
##
## Body is a CharacterBody3D: dropped onto the floor, then free locomotion.

const COMBAT_GLB: String = "res://models/mixamo_openbot/Swat_rifle_combat.glb"
const IDLE_GLB: String = "res://models/mixamo_openbot/Swat_rifle_idle.glb"
const LASERS: Array[String] = [
	"res://sounds/laser_small_000.ogg",
	"res://sounds/laser_small_001.ogg",
	"res://sounds/laser_small_002.ogg",
]
const IMPACTS: Array[String] = [
	"res://sounds/impact_metal_000.ogg",
	"res://sounds/impact_metal_001.ogg",
]

const FIRE_RATE: float = 0.11
const BOLT_SPEED: float = 55.0
const RANGE: float = 28.0
const CAM_SENS: float = 0.0035
const CAM_PITCH_MIN: float = -0.55
const CAM_PITCH_MAX: float = 0.85
const CAM_ZOOM_STEP: float = 0.35
const CAM_DIST_MIN: float = 1.4
const CAM_DIST_MAX: float = 9.0
const OTS_DIST: float = 2.65
const OTS_SHOULDER: float = 0.55
const OTS_HEIGHT: float = 0.35
const OTS_LOOK_AHEAD: float = 2.8
const AIM_FOV: float = 36.0
const HIP_FOV: float = 52.0
const GRAVITY: float = 28.0
const DROP_HEIGHT: float = 1.4
const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.8
const JUMP_VELOCITY: float = 7.5
const CAPSULE_HEIGHT: float = 1.5
const CAPSULE_RADIUS: float = 0.28
# Ankle/toe bones sit above the boot sole mesh. Clearance must cover that gap
# (skinned MeshInstance AABB is rest-pose and unreliable for posed feet).
const FOOT_SOLE_CLEARANCE: float = 0.13
# Unarmed idle plants soles lower than Running — lift only while standing still.
const IDLE_EXTRA_LIFT: float = 0.045
# Holster local offsets on Spine2 BoneAttachment — tunable at runtime (H).
# Defaults are a starting guess; use the on-screen nudge tools to dial them in.
var _holster_pos: Vector3 = Vector3(0.12, 0.02, -0.28)
var _holster_rot_deg: Vector3 = Vector3(0.0, 90.0, 85.0)
var _holster_tune: bool = false
var _holster_step: float = 0.025
var _holster_rot_step: float = 8.0
var _tune_label: Label
var _tune_panel: VBoxContainer
var _tune_hold: Dictionary = {} # keycode -> bool, for hold-to-nudge
var _tune_hold_accum: float = 0.0

enum Stance { HOLSTER, AIM_MOVE, AIM_CROUCH }

var _body: CharacterBody3D
var _host: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _rifle: Node3D
var _rifle_holster: Node3D
var _muzzle: Node3D
var _hand_mount: BoneAttachment3D
var _back_mount: BoneAttachment3D
var _cam: Camera3D
var _stance: Stance = Stance.HOLSTER
var _fire_cd: float = 0.0
var _recoil_kick: float = 0.0
var _cam_punch: Vector3 = Vector3.ZERO
var _label: Label
var _aim_cursor: MeshInstance3D
var _aim_cross: Control
var _aim_cross_h: ColorRect
var _aim_cross_v: ColorRect
var _target_wall: StaticBody3D
var _rifle_hand_pos: Vector3 = Vector3.ZERO
var _rifle_hand_rot: Vector3 = Vector3.ZERO
var _rifle_holstered: bool = true
var _aiming: bool = false
var _want_fire: bool = false
var _move_input: Vector2 = Vector2.ZERO
var _sprinting: bool = false
var _jump_pressed: bool = false
# Camera: yaw turns the body; pitch orbits the OTS camera.
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.28
var _cam_dist: float = OTS_DIST
var _cam_initialized: bool = false
var _spawn_xz: Vector3 = Vector3.ZERO
var _landed: bool = false
var _ground_y: float = 0.0
var _spawn_ready: bool = false
var _host_floor_y: float = 0.0

const IDLE_CLIPS: Array[String] = ["Unarmed_Idle", "Breathing_Idle"]
# Holstered loco: Running looks right — walk is the same clip at lower speed.
const LOCO_CLIPS: Array[String] = ["Running"]
const WALK_ANIM_SPEED: float = 0.55
const RUN_ANIM_SPEED: float = 1.0
# Standing / moving aim+fire — Mixamo "Shoot Rifle" (not Walk With Rifle).
const SHOOT_CLIPS: Array[String] = ["Shoot_Rifle", "Firing_Rifle"]
const STRAFE_CLIPS: Array[String] = ["Strafe", "Strafe_Alt"]
const STRAFE_ALT_CLIPS: Array[String] = ["Strafe_Alt", "Strafe"]
const CROUCH_AIM_CLIPS: Array[String] = [
	"Rifle_Crouched_Idle_Aim", "Rifle_Kneeling_Aim", "Rifle_Stand_To_Kneel"
]
const CROUCH_FIRE_CLIPS: Array[String] = [
	"Fire_Rifle_Crouched", "Rifle_Kneeling_Aim", "Rifle_Crouched_Idle_Aim"
]


func _ready() -> void:
	_build_world()
	if not _spawn_host():
		_label.text = "Missing Swat_rifle_combat.glb — run tools/blender_mixamo_rifle_combat.py"
		return
	_play_clip(_pick_clip(IDLE_CLIPS), true)
	# Defer until AnimationPlayer + physics have ticked once.
	call_deferred("_finish_spawn")


func _finish_spawn() -> void:
	_spawn_xz = Vector3(_body.global_position.x, 0.0, _body.global_position.z)
	_landed = false
	var guard := 0
	while _body != null and not _landed and guard < 180:
		await get_tree().physics_frame
		guard += 1
	if not _landed and _body != null:
		_plant_on_floor(_body.global_position.y)
	# Pose must settle before measuring soles (clip may still be blending).
	await get_tree().process_frame
	await get_tree().process_frame
	_align_visual_feet()
	_setup_rifle_mounts()
	_stance = Stance.HOLSTER
	_set_rifle_holstered(true)
	_play_clip(_pick_clip(IDLE_CLIPS), true)
	await get_tree().process_frame
	_align_visual_feet()
	_apply_idle_foot_bias()
	_cam_yaw = _body.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_ready = true
	_refresh_label()
	if OS.is_debug_build():
		print(
			"spawn complete; landed=", _landed,
			" ground_y=", _ground_y,
			" body.y=", _body.global_position.y,
			" fall_frames=", guard,
		)


func _plant_on_floor(y: float) -> void:
	_landed = true
	_ground_y = maxf(0.0, y)
	_body.velocity = Vector3.ZERO
	_body.global_position = Vector3(_spawn_xz.x, _ground_y, _spawn_xz.z)


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	# Pre-ready: drop onto the floor, hold XZ.
	if not _spawn_ready:
		if _landed:
			_body.velocity = Vector3.ZERO
			_body.global_position = Vector3(_spawn_xz.x, _ground_y, _spawn_xz.z)
			return
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		_body.velocity.y -= GRAVITY * delta
		_body.move_and_slide()
		_body.global_position.x = _spawn_xz.x
		_body.global_position.z = _spawn_xz.z
		if _body.is_on_floor():
			_plant_on_floor(_body.global_position.y)
		return

	# Gameplay locomotion.
	var on_floor: bool = _body.is_on_floor()
	if not on_floor:
		_body.velocity.y -= GRAVITY * delta
	elif _jump_pressed:
		_body.velocity.y = JUMP_VELOCITY
	else:
		_body.velocity.y = 0.0
	_jump_pressed = false

	var speed: float = SPRINT_SPEED if _sprinting and not _aiming else WALK_SPEED
	if _aiming and _move_input.length_squared() > 0.01:
		# Slightly slower while aiming on the move.
		speed = WALK_SPEED * (1.15 if _sprinting else 0.9)

	var cam_yaw := _cam_yaw
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := (forward * -_move_input.y + right * _move_input.x)
	if wish.length_squared() > 0.001:
		wish = wish.normalized() * speed
		_body.velocity.x = wish.x
		_body.velocity.z = wish.z
		# Face move direction when holstered; face look when aiming.
		if not _aiming:
			_body.rotation.y = atan2(-wish.x, -wish.z)
		else:
			_body.rotation.y = cam_yaw
	else:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		if _aiming:
			_body.rotation.y = cam_yaw

	_body.move_and_slide()


func _process(delta: float) -> void:
	if _cam != null and _body != null:
		_update_camera(delta)
	if _anim == null or not _spawn_ready:
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_recoil_kick = move_toward(_recoil_kick, 0.0, delta * 8.0)
	_cam_punch = _cam_punch.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
	_poll_move_keys()
	_update_rifle_recoil()
	_update_aim_cursor()
	if _holster_tune:
		_poll_holster_tune_holds(delta)
		return
	_sync_gameplay_stance()
	_apply_idle_foot_bias()
	if _aiming and _want_fire and _fire_cd <= 0.0:
		_fire_shot()


func _poll_move_keys() -> void:
	_move_input = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_move_input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_move_input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_move_input.x += 1.0
	if _move_input.length_squared() > 1.0:
		_move_input = _move_input.normalized()
	_sprinting = Input.is_key_pressed(KEY_SHIFT)
	_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _holster_tune
	_want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _aiming and not _holster_tune


func _sync_gameplay_stance() -> void:
	var moving: bool = _move_input.length_squared() > 0.04
	var next: Stance = Stance.HOLSTER
	if _aiming:
		# Auto-crouch while aiming unless walking / sprinting.
		next = Stance.AIM_MOVE if moving else Stance.AIM_CROUCH

	var stance_changed: bool = next != _stance
	_stance = next
	_set_rifle_holstered(not _aiming)

	var clip := ""
	var anim_speed: float = 1.0
	match _stance:
		Stance.HOLSTER:
			if moving:
				# Same Running clip for all holstered directions — never Walking
				# (that pack walk reads as gun-ready) and never strafe when holstered.
				clip = _pick_clip(LOCO_CLIPS)
				anim_speed = RUN_ANIM_SPEED if _sprinting else WALK_ANIM_SPEED
			else:
				clip = _pick_clip(IDLE_CLIPS)
		Stance.AIM_MOVE:
			var side: float = _aim_move_side()
			if absf(side) > 0.45:
				# Strafe poses only while aiming.
				clip = _pick_clip(STRAFE_ALT_CLIPS if side > 0.0 else STRAFE_CLIPS)
			else:
				clip = _pick_clip(SHOOT_CLIPS)
		Stance.AIM_CROUCH:
			clip = _pick_clip(CROUCH_FIRE_CLIPS if _want_fire else CROUCH_AIM_CLIPS)

	if clip != "" and (
		stance_changed
		or _anim.current_animation != clip
		or not _anim.is_playing()
		or not is_equal_approx(_anim.speed_scale, anim_speed)
	):
		_play_clip(clip, true, anim_speed)
	if stance_changed:
		_refresh_label()
	# FOV punch toward ADS.
	if _cam != null:
		var want_fov: float = AIM_FOV if _aiming else HIP_FOV
		_cam.fov = lerpf(_cam.fov, want_fov, 0.15)


func _aim_move_side() -> float:
	# Camera-relative move projected onto aim-right: +1 = strafe right, -1 = left.
	var cam_yaw := _cam_yaw
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := (forward * -_move_input.y + right * _move_input.x)
	if wish.length_squared() < 0.001:
		return 0.0
	wish = wish.normalized()
	return wish.dot(right)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		var code: int = ke.keycode
		if code == KEY_NONE:
			code = ke.physical_keycode
		if ke.pressed and not ke.echo:
			if code == KEY_H:
				_toggle_holster_tune()
				get_viewport().set_input_as_handled()
				return
			if code == KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()
				return
			if code == KEY_SPACE and not _holster_tune:
				_jump_pressed = true
				get_viewport().set_input_as_handled()
				return
			if _holster_tune:
				_tune_hold[code] = true
				_nudge_holster(code, 1.0)
				get_viewport().set_input_as_handled()
				return
		elif not ke.pressed and _holster_tune:
			_tune_hold.erase(code)
			_tune_hold.erase(ke.physical_keycode)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _holster_tune:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(CAM_DIST_MIN, _cam_dist - CAM_ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(CAM_DIST_MAX, _cam_dist + CAM_ZOOM_STEP)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * CAM_SENS
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * CAM_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _play_clip(clip: String, looping: bool, speed: float = 1.0) -> void:
	if clip == "" or _anim == null:
		return
	_anim.play(clip)
	_anim.speed_scale = speed
	if looping and _anim.has_animation(clip):
		var anim := _anim.get_animation(clip)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR


func _pick_clip(prefs: Array[String]) -> String:
	if _anim == null:
		return ""
	var available: PackedStringArray = _anim.get_animation_list()
	# Exact name first — fuzzy find("Walking") must not grab Walk_With_Rifle etc.
	for want in prefs:
		for have in available:
			if str(have) == want:
				return str(have)
	for want in prefs:
		for have in available:
			if str(have).ends_with("/" + want) or str(have).ends_with("|" + want):
				return str(have)
	return ""


func _fire_shot() -> void:
	_fire_cd = FIRE_RATE
	var muzzle: Vector3 = _muzzle_world()
	var forward: Vector3 = _aim_forward(muzzle)

	_spawn_muzzle_flash(muzzle, forward)
	_spawn_projectile(muzzle, forward)
	_recoil_kick = minf(1.0, _recoil_kick + 0.55)
	_cam_punch += Vector3(randf_range(-0.01, 0.01), randf_range(0.012, 0.028), 0.0)
	_play_sfx(LASERS)


func _aim_forward(_muzzle: Vector3) -> Vector3:
	# Gameplay aim is camera-forward so loco clips can't "shoot the floor."
	if _cam != null and _aiming:
		return -_cam.global_transform.basis.z.normalized()
	if _cam != null:
		var flat := -_cam.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.001:
			return flat.normalized()
	return Vector3(0.0, 0.0, -1.0)


func _muzzle_world() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	if _rifle != null:
		return _rifle.to_global(Vector3(0.0, 0.55, 0.03))
	return _body.global_position + Vector3(0.0, 1.2, -0.4)


func _aim_hit(muzzle: Vector3, forward: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + forward * RANGE)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit.position as Vector3
	return muzzle + forward * minf(RANGE, 12.0)


func _update_aim_cursor() -> void:
	if _aim_cursor == null:
		return
	# Aim markers only while ADS — hide the ring + screen cross otherwise.
	if not _aiming or _rifle_holstered:
		_aim_cursor.visible = false
		if _aim_cross != null:
			_aim_cross.visible = false
		return

	var muzzle: Vector3 = _muzzle_world()
	var forward: Vector3 = _aim_forward(muzzle)
	var hit: Vector3 = _aim_hit(muzzle, forward)
	_aim_cursor.visible = true
	_aim_cursor.global_position = hit
	# Billboard the ring so it faces the camera (not edge-on along the shot axis).
	if _cam != null:
		_aim_cursor.look_at(_cam.global_position, Vector3.UP)

	if _cam != null and _aim_cross != null:
		var screen: Vector2 = _cam.unproject_position(hit)
		_aim_cross.position = screen - _aim_cross.size * 0.5
		_aim_cross.visible = not _cam.is_position_behind(hit)


func _spawn_muzzle_flash(at: Vector3, dir: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.35, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.15)
	mat.emission_energy_multiplier = 6.0
	flash.material_override = mat
	add_child(flash)
	flash.global_position = at + dir * 0.05

	# Cone cone spray
	var cone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.12
	cyl.height = 0.22
	cone.mesh = cyl
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.7, 0.2, 0.7)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.55, 0.1)
	cmat.emission_energy_multiplier = 4.0
	cone.material_override = cmat
	flash.add_child(cone)
	cone.position = Vector3(0.0, 0.0, -0.12)
	cone.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 5.5
	light.omni_range = 3.5
	flash.add_child(light)

	# Smoke puff
	var smoke := GPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 0.35
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(dir.x, dir.y + 0.2, dir.z)
	pmat.spread = 35.0
	pmat.initial_velocity_min = 0.4
	pmat.initial_velocity_max = 1.6
	pmat.gravity = Vector3(0.0, 1.2, 0.0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.12
	pmat.color = Color(0.45, 0.45, 0.48, 0.55)
	smoke.process_material = pmat
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	smoke.draw_pass_1 = sm
	flash.add_child(smoke)
	smoke.emitting = true

	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.parallel().tween_property(cmat, "albedo_color:a", 0.0, 0.09)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.12)
	tw.tween_callback(flash.queue_free)


func _spawn_projectile(from: Vector3, dir: Vector3) -> void:
	var body := Area3D.new()
	body.monitoring = true
	body.monitorable = false
	add_child(body)
	body.global_position = from
	if dir.length_squared() > 0.001:
		body.look_at(from + dir, Vector3.UP)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 0.28)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 5.0
	mesh.material_override = mat
	body.add_child(mesh)

	var trail := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.012, 0.012, 0.55)
	trail.mesh = tbox
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1.0, 0.7, 0.25, 0.45)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.55, 0.1)
	tmat.emission_energy_multiplier = 2.5
	trail.material_override = tmat
	trail.position = Vector3(0.0, 0.0, 0.35)
	body.add_child(trail)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.06
	col.shape = shape
	body.add_child(col)

	var runner := Node.new()
	add_child(runner)
	_drive_projectile(body, dir.normalized(), runner)


func _drive_projectile(body: Area3D, dir: Vector3, runner: Node) -> void:
	var traveled: float = 0.0
	while is_instance_valid(body) and is_instance_valid(runner):
		await get_tree().process_frame
		if not is_instance_valid(body):
			break
		var delta: float = get_process_delta_time()
		var step: float = BOLT_SPEED * delta
		body.global_position += dir * step
		traveled += step
		# Ray probe for hits
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			body.global_position - dir * step, body.global_position + dir * 0.05
		)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_spawn_impact(hit.position as Vector3, dir)
			_play_sfx(IMPACTS)
			body.queue_free()
			break
		if body.global_position.y < 0.02 or traveled >= RANGE:
			_spawn_impact(body.global_position, dir)
			body.queue_free()
			break
	if is_instance_valid(runner):
		runner.queue_free()


func _spawn_impact(at: Vector3, dir: Vector3) -> void:
	var burst := GPUParticles3D.new()
	burst.amount = 18
	burst.lifetime = 0.4
	burst.one_shot = true
	burst.explosiveness = 0.95
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = -dir + Vector3(0.0, 0.5, 0.0)
	pmat.spread = 55.0
	pmat.initial_velocity_min = 1.2
	pmat.initial_velocity_max = 3.5
	pmat.gravity = Vector3(0.0, -6.0, 0.0)
	pmat.scale_min = 0.02
	pmat.scale_max = 0.07
	pmat.color = Color(1.0, 0.7, 0.25, 1.0)
	burst.process_material = pmat
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	burst.draw_pass_1 = sm
	add_child(burst)
	burst.global_position = at
	burst.emitting = true

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 2.5
	light.omni_range = 1.8
	burst.add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.2)
	tw.tween_interval(0.45)
	tw.tween_callback(burst.queue_free)


func _update_rifle_recoil() -> void:
	if _rifle == null or _rifle_holstered:
		return
	_rifle.position = _rifle_hand_pos + Vector3(0.0, -0.02 * _recoil_kick, 0.01 * _recoil_kick)
	_rifle.rotation = _rifle_hand_rot + Vector3(deg_to_rad(-2.8 * _recoil_kick), 0.0, 0.0)


func _update_camera(delta: float) -> void:
	if _cam == null or _body == null:
		return
	var focus := _focus_world()
	var punch: Vector3 = _cam_punch
	_apply_look_camera(focus, punch, delta)


func _apply_look_camera(focus: Vector3, punch: Vector3, delta: float) -> void:
	# Third-person: orbit behind look yaw/pitch; body faces look while aiming.
	var dist: float = _cam_dist
	var shoulder: float = OTS_SHOULDER
	var height: float = OTS_HEIGHT
	match _stance:
		Stance.AIM_MOVE:
			dist = maxf(dist, 3.0)
			shoulder = 0.62
			height = 0.4
		Stance.AIM_CROUCH:
			dist = minf(dist, 2.5)
			shoulder = 0.5
			height = 0.18
		_:
			pass

	var back := Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch))
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	var desired: Vector3 = focus + back * dist + right * shoulder + Vector3.UP * height
	if not _cam_initialized:
		_cam.global_position = desired + punch
		_cam_initialized = true
	else:
		_cam.global_position = _cam.global_position.lerp(desired + punch, minf(1.0, delta * 12.0))
	var look_dir := -back.normalized()
	var look: Vector3 = focus + look_dir * OTS_LOOK_AHEAD + right * 0.12 + Vector3.UP * 0.05 + punch * 0.35
	_cam.look_at(look, Vector3.UP)


func _focus_world() -> Vector3:
	if _skel != null:
		var spine := _bone([
			"mixamorig_Spine2", "mixamorig:Spine2", "mixamorig_Spine1", "mixamorig:Spine1",
			"mixamorig_Hips", "mixamorig:Hips",
		])
		if spine != "":
			var idx: int = _skel.find_bone(spine)
			if idx >= 0:
				return _skel.to_global(_skel.get_bone_global_pose(idx).origin)
	if _body != null:
		return _body.global_position + Vector3(0.0, 1.05, 0.0)
	return Vector3(0.0, 1.05, 0.0)



func _play_sfx(paths: Array[String]) -> void:
	if paths.is_empty():
		return
	var p: String = paths[randi() % paths.size()]
	var audio_n: Node = get_node_or_null("/root/Audio")
	if audio_n != null and audio_n.has_method("play"):
		audio_n.call("play", p)
		return
	# Fallback one-shot
	if not ResourceLoader.exists(p):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(p) as AudioStream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _spawn_host() -> bool:
	var path: String = COMBAT_GLB if ResourceLoader.exists(COMBAT_GLB) else IDLE_GLB
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene

	_body = CharacterBody3D.new()
	_body.name = "CombatBody"
	_body.position = Vector3(0.0, DROP_HEIGHT, 0.0)
	_body.floor_stop_on_slope = true
	_body.floor_max_angle = deg_to_rad(55.0)
	_body.floor_snap_length = 0.15
	_body.safe_margin = 0.08
	_body.collision_layer = 1
	_body.collision_mask = 1
	add_child(_body)

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	col.shape = capsule
	# Capsule bottom sits on body origin (floor contact when body.y == 0).
	col.position.y = CAPSULE_RADIUS + CAPSULE_HEIGHT * 0.5
	_body.add_child(col)

	_host = packed.instantiate() as Node3D
	_host.rotation.y = PI
	_body.add_child(_host)
	_anim = _find_anim(_host)
	_skel = _find_skel(_host)
	_rifle = _find_weapon_mesh(_host)
	_muzzle = _find_named(_host, "Muzzle")
	_lock_root_translation_tracks()
	if _anim:
		if OS.is_debug_build():
			print("anims=", _anim.get_animation_list())
	if OS.is_debug_build():
		print(
			"host=", path,
			" rifle=", _rifle.name if _rifle else "null",
			" muzzle=", _muzzle != null,
			" drop_y=", DROP_HEIGHT,
		)
	return true


func _bone(names: Array[String]) -> String:
	if _skel == null:
		return ""
	for n in names:
		if _skel.find_bone(n) >= 0:
			return n
	# Last resort: substring scan.
	for i in _skel.get_bone_count():
		var bn := String(_skel.get_bone_name(i))
		for want in names:
			if bn.to_lower().find(want.to_lower().replace("mixamorig:", "").replace("mixamorig_", "")) >= 0:
				return bn
	return ""


func _apply_idle_foot_bias() -> void:
	if _host == null or not _spawn_ready:
		return
	var idle_stand: bool = (
		not _aiming
		and _move_input.length_squared() < 0.04
		and _stance == Stance.HOLSTER
	)
	_host.position.y = _host_floor_y + (IDLE_EXTRA_LIFT if idle_stand else 0.0)


## Capture / debug hook — drives the gameplay state machine without UI input.
func apply_capture_pose(pose: String) -> void:
	_sprinting = false
	match pose:
		"holster":
			_aiming = false
			_want_fire = false
			_move_input = Vector2.ZERO
		"aim_run":
			_aiming = true
			_want_fire = true
			_move_input = Vector2(0.0, -1.0)
			_sprinting = true
		"aim_crouch":
			_aiming = true
			_want_fire = true
			_move_input = Vector2.ZERO
		_:
			_aiming = false
			_want_fire = false
			_move_input = Vector2.ZERO
	_sync_gameplay_stance()
	_apply_idle_foot_bias()
	_refresh_label()


func _align_visual_feet() -> void:
	# Lift/drop the mesh so boot soles sit on the floor plane (body contact y).
	# Foot *bones* are ankle/toe joints — always include skinned mesh AABB so
	# sole geometry isn't buried under the floor.
	if _skel == null or _body == null or _host == null:
		return
	if _skel.has_method("force_update_transform"):
		_skel.force_update_transform()
	var floor_y: float = _body.global_position.y
	var lowest: float = _lowest_sole_world_y()
	if lowest > 1e8:
		if OS.is_debug_build():
			print("align feet FAILED — no sole samples")
		return
	var delta_y: float = (floor_y + FOOT_SOLE_CLEARANCE) - lowest
	_host.position.y += delta_y
	_host_floor_y = _host.position.y
	if OS.is_debug_build():
		print(
			"aligned feet; host.local_y=", _host.position.y,
			" sole_world_y=", lowest,
			" delta=", delta_y,
		)


func _lowest_sole_world_y() -> float:
	# Prefer posed foot bones. Rest-pose mesh AABBs ignore skinning and lie.
	var bone_lowest := 1e9
	var foot_names: Array[String] = [
		"mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftFoot", "mixamorig_RightFoot",
		"mixamorig:LeftToeBase", "mixamorig:RightToeBase", "mixamorig:LeftFoot", "mixamorig:RightFoot",
	]
	for bone_name in foot_names:
		var idx: int = _skel.find_bone(bone_name)
		if idx < 0:
			continue
		bone_lowest = minf(bone_lowest, _skel.to_global(_skel.get_bone_global_pose(idx).origin).y)
	if bone_lowest < 1e8:
		return bone_lowest

	var lowest := 1e9
	for child in _host.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var n := String(mi.name).to_lower()
		if n.find("rifle") >= 0 or n.find("muzzle") >= 0 or n == "cube":
			continue
		if n.find("soldier") < 0 and n.find("body") < 0:
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		lowest = minf(lowest, aabb.position.y)
	return lowest


func _setup_rifle_mounts() -> void:
	# Blender authors two meshes:
	#   rifle         → bone-parented to RightHand (combat)
	#   rifle_holster → bone-parented to Spine2 (idle sling)
	# Godot only toggles visibility — no runtime reparent guesswork.
	if _rifle == null:
		return
	_rifle_holster = _find_exact_named(_host, "rifle_holster")
	_rifle_hand_pos = _rifle.position
	_rifle_hand_rot = _rifle.rotation
	_muzzle = _find_named(_rifle, "Muzzle")
	if _muzzle == null:
		_muzzle = _find_named(_host, "Muzzle")
	# Dummy mounts so older tune/holster paths that null-check them don't early-out.
	_hand_mount = BoneAttachment3D.new()
	_hand_mount.name = "RifleHandMount"
	_back_mount = BoneAttachment3D.new()
	_back_mount.name = "RifleBackMount"
	if _skel != null:
		var hand_bone := _bone(["mixamorig_RightHand", "mixamorig:RightHand", "RightHand"])
		var back_bone := _bone(["mixamorig_Spine2", "mixamorig:Spine2", "Spine2"])
		if hand_bone != "":
			_hand_mount.bone_name = hand_bone
			_skel.add_child(_hand_mount)
		if back_bone != "":
			_back_mount.bone_name = back_bone
			_skel.add_child(_back_mount)
	if OS.is_debug_build():
		print(
			"rifle mounts: hand=", _rifle != null,
			" holster_mesh=", _rifle_holster != null,
			" muzzle=", _muzzle != null,
		)
	_set_rifle_holstered(true)


func _set_rifle_holstered(holstered: bool) -> void:
	if _rifle == null:
		return
	_rifle_holstered = holstered
	_recoil_kick = 0.0
	if _rifle_holster != null:
		# Preferred path: Blender-authored back mesh.
		_rifle.visible = not holstered
		_rifle_holster.visible = holstered
	else:
		# Fallback: old BoneAttachment nudge path if holster mesh missing.
		if holstered:
			if _back_mount != null and _rifle.get_parent() != _back_mount:
				var p: Node = _rifle.get_parent()
				if p:
					p.remove_child(_rifle)
				_back_mount.add_child(_rifle)
			_seat_rifle_on_back()
		else:
			if _hand_mount != null and _rifle.get_parent() != _hand_mount:
				var p2: Node = _rifle.get_parent()
				if p2:
					p2.remove_child(_rifle)
				_hand_mount.add_child(_rifle)
			_rifle.position = _rifle_hand_pos
			_rifle.rotation = _rifle_hand_rot
		_rifle.visible = true
	_refresh_label()


func _seat_rifle_on_back() -> void:
	# Only used when rifle_holster mesh is missing.
	if _rifle == null or _rifle_holster != null:
		return
	if _back_mount != null and _rifle.get_parent() != _back_mount:
		var parent_n: Node = _rifle.get_parent()
		if parent_n != null:
			parent_n.remove_child(_rifle)
		_back_mount.add_child(_rifle)
	_rifle.position = _holster_pos
	_rifle.rotation_degrees = _holster_rot_deg


func _find_exact_named(root: Node, want: String) -> Node3D:
	var want_l := want.to_lower()
	for n in root.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower() == want_l:
			return n as Node3D
	return null


func _toggle_holster_tune() -> void:
	_holster_tune = not _holster_tune
	_tune_hold.clear()
	if _holster_tune:
		_aiming = false
		_want_fire = false
		_stance = Stance.HOLSTER
		_set_rifle_holstered(true)
		_play_clip(_pick_clip(IDLE_CLIPS), true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _tune_panel != null:
			_tune_panel.visible = true
		if OS.is_debug_build():
			print("HOLSTER TUNE ON — prefer Blender for final seat; buttons are temporary")
	else:
		if _tune_panel != null:
			_tune_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if OS.is_debug_build():
			print("HOLSTER TUNE OFF")
	_refresh_tune_label()
	_refresh_label()
	_seat_rifle_on_back()


func _poll_holster_tune_holds(delta: float) -> void:
	if _tune_hold.is_empty():
		_tune_hold_accum = 0.0
		return
	_tune_hold_accum += delta
	if _tune_hold_accum < 0.08:
		return
	_tune_hold_accum = 0.0
	for code in _tune_hold.keys():
		_nudge_holster(int(code), 1.0)


func _nudge_holster(keycode: int, mult: float) -> void:
	var step: float = _holster_step * mult
	var rstep: float = _holster_rot_step * mult
	var moved := false
	match keycode:
		KEY_I, KEY_UP:
			_holster_pos.z -= step
			moved = true
		KEY_K, KEY_DOWN:
			_holster_pos.z += step
			moved = true
		KEY_J, KEY_LEFT:
			_holster_pos.x -= step
			moved = true
		KEY_L, KEY_RIGHT:
			_holster_pos.x += step
			moved = true
		KEY_U, KEY_PAGEUP:
			_holster_pos.y += step
			moved = true
		KEY_O, KEY_PAGEDOWN:
			_holster_pos.y -= step
			moved = true
		KEY_T:
			_holster_rot_deg.x += rstep
			moved = true
		KEY_G:
			_holster_rot_deg.x -= rstep
			moved = true
		KEY_F:
			_holster_rot_deg.y += rstep
			moved = true
		KEY_B:
			_holster_rot_deg.y -= rstep
			moved = true
		KEY_R:
			_holster_rot_deg.z += rstep
			moved = true
		KEY_V:
			_holster_rot_deg.z -= rstep
			moved = true
		KEY_BRACKETLEFT, KEY_MINUS:
			_holster_step = maxf(0.002, _holster_step * 0.5)
			_holster_rot_step = maxf(1.0, _holster_rot_step * 0.5)
			moved = true
		KEY_BRACKETRIGHT, KEY_EQUAL:
			_holster_step = minf(0.12, _holster_step * 2.0)
			_holster_rot_step = minf(45.0, _holster_rot_step * 2.0)
			moved = true
		KEY_P, KEY_ENTER:
			_print_holster_values()
			return
		_:
			return
	if moved:
		_seat_rifle_on_back()
		_refresh_tune_label()
		if OS.is_debug_build():
			print("holster nudge → pos=", _holster_pos, " rot=", _holster_rot_deg)


func _make_tune_btn(text: String, keycode: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(72, 32)
	b.pressed.connect(func() -> void: _nudge_holster(keycode, 1.0))
	return b


func _build_tune_panel(ui: CanvasLayer) -> void:
	_tune_panel = VBoxContainer.new()
	_tune_panel.position = Vector2(24, 220)
	_tune_panel.visible = false
	_tune_panel.add_theme_constant_override("separation", 6)
	ui.add_child(_tune_panel)
	var title := Label.new()
	title.text = "Nudge holster (temp — Blender is better)"
	_tune_panel.add_child(title)
	var row_pos := HBoxContainer.new()
	row_pos.add_theme_constant_override("separation", 4)
	_tune_panel.add_child(row_pos)
	for pair in [["-X", KEY_J], ["+X", KEY_L], ["+Y", KEY_U], ["-Y", KEY_O], ["-Z", KEY_I], ["+Z", KEY_K]]:
		row_pos.add_child(_make_tune_btn(str(pair[0]), int(pair[1])))
	var row_rot := HBoxContainer.new()
	row_rot.add_theme_constant_override("separation", 4)
	_tune_panel.add_child(row_rot)
	for pair2 in [["P+", KEY_T], ["P-", KEY_G], ["Y+", KEY_F], ["Y-", KEY_B], ["R+", KEY_R], ["R-", KEY_V]]:
		row_rot.add_child(_make_tune_btn(str(pair2[0]), int(pair2[1])))
	var copy_btn := Button.new()
	copy_btn.text = "Copy values"
	copy_btn.custom_minimum_size = Vector2(120, 32)
	copy_btn.pressed.connect(_print_holster_values)
	_tune_panel.add_child(copy_btn)


func _print_holster_values() -> void:
	var msg := (
		"HOLSTER VALUES (paste into showcase script):\n"
		+ "	_holster_pos = Vector3(%.4f, %.4f, %.4f)\n" % [_holster_pos.x, _holster_pos.y, _holster_pos.z]
		+ "	_holster_rot_deg = Vector3(%.2f, %.2f, %.2f)" % [_holster_rot_deg.x, _holster_rot_deg.y, _holster_rot_deg.z]
	)
	if OS.is_debug_build():
		print(msg)
	DisplayServer.clipboard_set(
		"_holster_pos = Vector3(%.4f, %.4f, %.4f)\n_holster_rot_deg = Vector3(%.2f, %.2f, %.2f)"
		% [_holster_pos.x, _holster_pos.y, _holster_pos.z, _holster_rot_deg.x, _holster_rot_deg.y, _holster_rot_deg.z]
	)


func _refresh_tune_label() -> void:
	if _tune_label == null:
		return
	if not _holster_tune:
		_tune_label.visible = false
		return
	_tune_label.visible = true
	_tune_label.text = (
		"HOLSTER TUNE  (H to exit) — or seat in Blender\n"
		+ "pos  %.3f  %.3f  %.3f\n" % [_holster_pos.x, _holster_pos.y, _holster_pos.z]
		+ "rot  %.1f  %.1f  %.1f\n" % [_holster_rot_deg.x, _holster_rot_deg.y, _holster_rot_deg.z]
		+ "step pos=%.3f rot=%.1f" % [_holster_step, _holster_rot_step]
	)


func _lock_root_translation_tracks() -> void:
	# Mixamo walk/run bake hip translation — freeze to first key (treadmill).
	if _anim == null:
		return
	for anim_name in _anim.get_animation_list():
		var anim: Animation = _anim.get_animation(anim_name)
		if anim == null:
			continue
		for ti in anim.get_track_count():
			if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var path_s := str(anim.track_get_path(ti)).to_lower()
			if path_s.find("hips") < 0 and path_s.find("root") < 0:
				continue
			if anim.track_get_key_count(ti) < 1:
				continue
			var rest: Vector3 = anim.track_get_key_value(ti, 0) as Vector3
			for ki in anim.track_get_key_count(ti):
				anim.track_set_key_value(ti, ki, rest)


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.2, 1.5)
	fill.light_energy = 0.55
	fill.omni_range = 8.0
	fill.light_color = Color(0.55, 0.65, 0.9)
	add_child(fill)

	var env_n := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.15
	env_n.environment = env
	add_child(env_n)

	# Solid floor only — no visible wall (avoids "walking through wall" look).
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mi.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.19)
	fmat.roughness = 0.92
	floor_mi.material_override = fmat
	add_child(floor_mi)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	# Thick slab with TOP exactly at y=0 so the capsule lands cleanly.
	floor_shape.size = Vector3(40, 2.0, 40)
	floor_col.shape = floor_shape
	floor_col.position.y = -1.0
	floor_body.add_child(floor_col)
	add_child(floor_body)

	# Invisible far target so shots / aim cursor have a hit surface.
	_target_wall = StaticBody3D.new()
	_target_wall.visible = false
	var wcol := CollisionShape3D.new()
	var wshape := BoxShape3D.new()
	wshape.size = Vector3(20, 8, 0.4)
	wcol.shape = wshape
	_target_wall.add_child(wcol)
	_target_wall.position = Vector3(0.0, 2.0, -10.0)
	add_child(_target_wall)

	# 3D aim marker on the hit surface.
	_aim_cursor = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.08
	ring.outer_radius = 0.14
	_aim_cursor.mesh = ring
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.35, 0.2, 0.95)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.4, 0.15)
	cmat.emission_energy_multiplier = 3.5
	_aim_cursor.material_override = cmat
	add_child(_aim_cursor)
	var center := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	center.mesh = dot
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(1.0, 0.85, 0.3)
	dmat.emission_enabled = true
	dmat.emission = Color(1.0, 0.75, 0.2)
	dmat.emission_energy_multiplier = 4.0
	center.material_override = dmat
	_aim_cursor.add_child(center)

	_cam = Camera3D.new()
	_cam.fov = HIP_FOV
	_cam.current = true
	add_child(_cam)

	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 18)
	ui.add_child(_label)
	_refresh_label()

	_tune_label = Label.new()
	_tune_label.position = Vector2(24, 120)
	_tune_label.add_theme_font_size_override("font_size", 16)
	_tune_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_tune_label.visible = false
	ui.add_child(_tune_label)
	_build_tune_panel(ui)

	# Screen-space crosshair tracking the aim hit.
	_aim_cross = Control.new()
	_aim_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_cross.size = Vector2(28, 28)
	ui.add_child(_aim_cross)
	_aim_cross_h = ColorRect.new()
	_aim_cross_h.color = Color(1.0, 0.45, 0.2, 0.9)
	_aim_cross_h.size = Vector2(28, 2)
	_aim_cross_h.position = Vector2(0, 13)
	_aim_cross_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_cross.add_child(_aim_cross_h)
	_aim_cross_v = ColorRect.new()
	_aim_cross_v.color = Color(1.0, 0.45, 0.2, 0.9)
	_aim_cross_v.size = Vector2(2, 28)
	_aim_cross_v.position = Vector2(13, 0)
	_aim_cross_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_cross.add_child(_aim_cross_v)


func _refresh_label() -> void:
	if _label == null:
		return
	var stance_name := "HOLSTER"
	match _stance:
		Stance.HOLSTER:
			if _move_input.length_squared() > 0.04:
				stance_name = "HOLSTER + RUN" if _sprinting else "HOLSTER + WALK"
			else:
				stance_name = "HOLSTER"
		Stance.AIM_MOVE:
			var side: float = _aim_move_side()
			if absf(side) > 0.45:
				stance_name = "AIM + STRAFE"
			else:
				stance_name = "AIM + MOVE (Shoot Rifle)"
		Stance.AIM_CROUCH:
			stance_name = "AIM + CROUCH"
	var gun_s := "HOLSTERED" if _rifle_holstered else "DRAWN"
	var tune_s := " · TUNE" if _holster_tune else ""
	_label.text = (
		"%s  ·  %s%s\nWASD move · Shift sprint · Space jump · RMB aim · LMB fire\nEsc release mouse / quit · wheel zoom · H holster-tune"
		% [stance_name, gun_s, tune_s]
	)




func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim(c)
		if f:
			return f
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null


func _find_named(n: Node, want: String) -> Node3D:
	var want_l := want.to_lower()
	if n is Node3D and n != _host and String(n.name).to_lower() == want_l:
		return n as Node3D
	for c in n.get_children():
		var f := _find_named(c, want)
		if f:
			return f
	# Soft fallback (substring), still never the packed root.
	if n is Node3D and n != _host and String(n.name).to_lower().find(want_l) >= 0:
		return n as Node3D
	for c2 in n.get_children():
		for d in c2.find_children("*", "Node3D", true, false):
			if d != _host and String(d.name).to_lower().find(want_l) >= 0:
				return d as Node3D
	return null


func _find_weapon_mesh(root: Node) -> Node3D:
	# Prefer exact "rifle" node — never the packed-scene root (Swat_rifle_combat).
	var exact: Node3D = null
	var soft: Node3D = null
	for n in root.find_children("*", "Node3D", true, false):
		var node := n as Node3D
		if node == null or node == root:
			continue
		var low := String(node.name).to_lower()
		if low == "rifle":
			exact = node
			break
		if soft == null and (low.find("rifle") >= 0 or low.find("gun") >= 0 or low == "cube"):
			# Proxies often export as joined "Cube"; skip soldier meshes.
			if low.find("soldier") >= 0 or low.find("body") >= 0 or low.find("head") >= 0:
				continue
			soft = node
	return exact if exact != null else soft
