extends Node3D

# Mint Animation Studio — stick-driven quick test for Mint-native characters.
# Opened from title → Characters (also F6 on this scene).
#
# SIMULATE mode (default) — Subnautica-style aim-then-use (third person):
#   Left stick  — walk / run (default) / turn in place
#   L3 / Shift  — latch sprint until you stop moving (then back to run)
#   A / jump    — jump
#   LT / RMB    — AIM (OTS camera + off-center reticle + gun in hand)
#   RT / LMB    — FIRE / USE (only while aiming — same scheme as a repair tool)
#   Right stick — orbit camera (look = aim direction while aiming)
#   Y           — toggle auto-turntable (off in simulate by default)
#   B / Esc     — back to title
#   Select / [M]— flip Simulate ↔ Manual clip picker

const MintCharacterRef: Script = preload("res://scripts/mint_character.gd")
const TITLE_SCENE: String = "res://scenes/title.tscn"

const WALK_THRESH: float = 0.22
const RUN_THRESH: float = 0.72
const TURN_THRESH: float = 0.35
const TURN_RATE: float = 3.2
const WALK_SPEED: float = 1.55
const RUN_SPEED: float = 4.0
const SPRINT_SPEED: float = 6.2
const AIM_MOVE_SPEED: float = 1.25
const JUMP_SPEED: float = 4.8
const GRAVITY: float = 16.0
const AIR_CONTROL: float = 0.35
const AIR_DRAG: float = 1.2
const AIM_CAM_DIST: float = 2.35
const AIM_SHOULDER: float = 0.72
const AIM_LOOK_AHEAD: float = 0.35
# Off-center reticle (right-shoulder OTS) — fraction of viewport size.
const AIM_RETICLE_UV: Vector2 = Vector2(0.62, 0.42)
const AIM_RAY_LEN: float = 40.0
const FIRE_COOLDOWN: float = 0.28
const FIRE_LASERS: Array[String] = [
	"res://sounds/laser_small_000.ogg",
	"res://sounds/laser_small_001.ogg",
	"res://sounds/laser_small_002.ogg",
]
const FIRE_IMPACTS: Array[String] = [
	"res://sounds/impact_metal_000.ogg",
	"res://sounds/impact_metal_001.ogg",
]

# Semantic clip aliases → preferred Mint export names (first match wins).
const CLIP_IDLE: Array[String] = ["Idle"]
const CLIP_WALK: Array[String] = ["Casual_Walk_inplace", "Walk"]
const CLIP_RUN: Array[String] = ["run_fast_3_inplace", "Run"]
const CLIP_JUMP: Array[String] = ["Regular_Jump", "Jump"]
const CLIP_TURN_L: Array[String] = ["Idle_Turn_Left"]
const CLIP_TURN_R: Array[String] = ["Idle_Turn_Right"]
const CLIP_AIM: Array[String] = [
	"Gesture_with_Hand_on_Gun", "Female_Crouch_Pick_Gun_Point_Forward"
]
const CLIP_FIRE: Array[String] = [
	"Cowboy_Quick_Draw_Shooting", "Draw_and_Shoot_from_Back",
	"Draw_and_Shoot_from_Back_1", "Draw_and_Shoot_from_Back_2"
]
const CLIP_FIRE_ADV: Array[String] = ["Walk_Forward_While_Shooting"]
const CLIP_FIRE_RET: Array[String] = ["Walk_Backward_While_Shooting"]
const CLIP_RELOAD: Array[String] = ["Forward_Reload_Subtle"]

var _char: Node3D = null
var _cam: Camera3D = null
var _cam_yaw: float = 0.35
var _cam_pitch: float = 0.28
var _cam_dist: float = 3.4
var _orbiting: bool = false
var _turntable: bool = false
var _simulate: bool = true

var _char_pick: OptionButton
var _anim_pick: OptionButton
var _mode_btn: Button
var _back_btn: Button
var _status: Label
var _clips: PackedStringArray = PackedStringArray()
var _clip_idx: int = 0

var _state: String = "idle"
var _oneshot_busy: bool = false
var _aiming: bool = false
var _facing: float = 0.0
var _rt_was_down: bool = false
var _floor_root: Node3D = null
var _move_vel: Vector3 = Vector3.ZERO
var _aim_was: bool = false
var _fire_cd: float = 0.0
var _reticle: Control = null
var _aim_marker: MeshInstance3D = null
var _aim_point: Vector3 = Vector3(0.0, 0.0, -4.0)
var _ui_layer: CanvasLayer = null
var _default_cam_dist: float = 3.4
var _sprint_latched: bool = false
var _shoulder_blend: float = 0.0
var _vert_vel: float = 0.0
var _airborne: bool = false
var _air_move: Vector3 = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.current_scene_path = "res://scenes/mint_character_lab.tscn"
	_build_stage()
	_build_ui()
	_rebuild_character()
	await get_tree().process_frame
	_apply_mode_ui()


func _process(delta: float) -> void:
	if _turntable and _char != null and not _simulate:
		_char.rotation.y += delta * 0.7
	_update_camera()
	_poll_camera_orbit(delta)
	# Keep stick loco + world travel alive under jump/fire oneshots.
	if _simulate and _char != null:
		_update_simulate(delta)
	_update_aim_presentation(delta)
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(1.6, _cam_dist - 0.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(12.0, _cam_dist + 0.25)
		elif _simulate and mb.button_index == MOUSE_BUTTON_RIGHT:
			# RMB hold = aim (mirrors LT). Release handled via _process poll.
			_aiming = mb.pressed
			get_viewport().set_input_as_handled()
		elif _simulate and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		_cam_yaw -= mm.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.006, 0.05, 1.35)
		return

	if event.is_action_pressed("ui_cancel") or (
		event.is_action_pressed("kino_remote") and not _simulate
	):
		_return_to_title()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("kino_autopilot"):
		_turntable = not _turntable
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_M:
				_set_simulate(not _simulate)
			KEY_ESCAPE:
				_return_to_title()
			KEY_R:
				if _simulate:
					_try_reload()

	if not _simulate:
		if event.is_action_pressed("ui_left"):
			_step_clip(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_step_clip(1)
			get_viewport().set_input_as_handled()
		return

	# Simulate: jump / fire / aim / L3 sprint latch.
	if event.is_action_pressed("jump"):
		_try_jump()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_try_fire()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sprint"):
		# Latch sprint until movement stops (default gait is run).
		_sprint_latched = not _sprint_latched
		get_viewport().set_input_as_handled()


func _update_simulate(delta: float) -> void:
	# Left stick → move_*; keyboard WASD also works.
	var mx: float = Input.get_axis("move_left", "move_right")
	var my: float = Input.get_axis("move_forward", "move_back")
	var stick := Vector2(mx, my)
	var mag: float = clampf(stick.length(), 0.0, 1.0)

	# LT (zoom_out) or held RMB = aim. Subnautica-style hold-to-aim.
	_aiming = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.get_action_strength("zoom_out") > 0.35
	)

	# RT rising edge → fire/use only while aiming.
	var rt: float = Input.get_action_strength("zoom_in")
	if rt > 0.55 and not _rt_was_down:
		_try_fire()
	_rt_was_down = rt > 0.55
	if _fire_cd > 0.0:
		_fire_cd = maxf(0.0, _fire_cd - delta)

	# Camera-relative ground axes.
	var into_scene := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	var move_dir := (right * stick.x + into_scene * (-stick.y))
	if move_dir.length() > 0.001:
		move_dir = move_dir.normalized()

	# While aiming, face look direction (camera forward on ground).
	if _aiming:
		var look_yaw: float = atan2(into_scene.x, into_scene.z)
		_facing = lerp_angle(_facing, look_yaw, clampf(delta * 10.0, 0.0, 1.0))

	# --- Horizontal loco (parkour: keep momentum + gait while airborne) ---
	var moving_amt: float = 0.0
	var gait_amt: float = 0.0
	if mag < WALK_THRESH and not _airborne:
		_sprint_latched = false
		_move_vel = Vector3.ZERO
		if not _aiming and absf(stick.x) > TURN_THRESH and absf(stick.y) < WALK_THRESH:
			_facing += (-stick.x) * TURN_RATE * delta
			_set_loco_state("turn_l" if stick.x < 0.0 else "turn_r")
		else:
			_set_loco_state("idle")
	else:
		if not _aiming and not _airborne:
			var desired: float = atan2(move_dir.x, move_dir.z)
			_facing = lerp_angle(_facing, desired, clampf(delta * 8.0, 0.0, 1.0))
		var speed: float = RUN_SPEED
		if _sprint_latched and not _aiming:
			_set_loco_state("run")
			speed = SPRINT_SPEED
			gait_amt = 1.0
		elif mag < RUN_THRESH and not _sprint_latched and not _airborne:
			_set_loco_state("walk")
			speed = WALK_SPEED
			gait_amt = 0.0
		else:
			_set_loco_state("run")
			speed = RUN_SPEED
			gait_amt = 1.0 if (_sprint_latched or mag >= RUN_THRESH) else lerpf(0.35, 1.0, (mag - WALK_THRESH) / maxf(0.001, RUN_THRESH - WALK_THRESH))
		if _aiming:
			speed = minf(speed, AIM_MOVE_SPEED)
			_sprint_latched = false
			gait_amt = minf(gait_amt, 0.45)
		moving_amt = 1.0
		var desired_vel: Vector3 = move_dir * speed * maxf(mag, 0.55 if _airborne else mag)
		if _airborne:
			# Soft air control — don't cancel run momentum.
			_move_vel = _move_vel.lerp(desired_vel, clampf(delta * AIR_CONTROL * 8.0, 0.0, 1.0))
			_move_vel *= clampf(1.0 - AIR_DRAG * delta * 0.15, 0.0, 1.0)
			if mag < WALK_THRESH:
				moving_amt = 1.0  # keep run cycle in air
				gait_amt = maxf(gait_amt, 0.85)
		else:
			_move_vel = desired_vel
			_air_move = _move_vel

	if _char != null and _char.has_method("set_move_blend") and _state != "turn_l" and _state != "turn_r":
		_char.call("set_move_blend", moving_amt, gait_amt)

	var aim_amt: float = 0.0
	if _aiming:
		# Arms-only aim filter — keep lighter blend so hands still read motion.
		aim_amt = 0.65 if mag >= WALK_THRESH or _airborne else 0.9
	if _char != null and _char.has_method("set_aim_blend"):
		_char.call("set_aim_blend", aim_amt)

	# --- Vertical hop (parkour) ---
	if _airborne:
		_vert_vel -= GRAVITY * delta
	if _char != null:
		_char.rotation.y = _facing
		var p: Vector3 = _char.global_position
		p += _move_vel * delta
		p.y += _vert_vel * delta
		if p.y <= 0.0:
			p.y = 0.0
			if _airborne:
				_airborne = false
				_vert_vel = 0.0
		_char.global_position = p


func _set_loco_state(next: String) -> void:
	if next == _state:
		return
	_state = next
	# Walk/run/idle are normally driven via set_move_blend each frame.
	# Apply a one-shot blend here so mode switches / rebuilds settle immediately.
	if _char != null and _char.has_method("set_move_blend"):
		match next:
			"idle":
				_char.call("set_move_blend", 0.0, 0.0)
			"walk":
				_char.call("set_move_blend", 1.0, 0.0)
			"run":
				_char.call("set_move_blend", 1.0, 1.0)
	if next != "turn_l" and next != "turn_r":
		return
	var clip: String = _resolve(CLIP_TURN_L if next == "turn_l" else CLIP_TURN_R)
	if clip != "":
		_play_loop(clip)


func _try_jump() -> void:
	if _airborne:
		return
	_airborne = true
	_vert_vel = JUMP_SPEED
	# Keep current horizontal carry into the hop.
	if _move_vel.length() > 0.05:
		_air_move = _move_vel
	if _char != null and _char.has_method("request_jump"):
		_char.call("request_jump")
		return
	var clip: String = _resolve(CLIP_JUMP)
	if clip == "":
		return
	_play_oneshot(clip)


func _try_fire() -> void:
	# Subnautica contract: USE only works while aiming (LT held).
	# Repair tool will reuse this gate — aim the spot, then RT to apply.
	if not _aiming:
		return
	if _fire_cd > 0.0:
		return
	_fire_cd = FIRE_COOLDOWN
	if _char != null and _char.has_method("request_fire"):
		_char.call("request_fire")
		if _char.has_method("set_aim_blend"):
			_char.call("set_aim_blend", 0.85)
		_spawn_fire_fx()
		return
	var clip: String = _resolve(CLIP_FIRE)
	if clip == "":
		return
	_play_oneshot(clip)
	_spawn_fire_fx()


func _try_reload() -> void:
	var clip: String = _resolve(CLIP_RELOAD)
	if clip == "":
		return
	if _char != null and _char.has_method("request_action"):
		_char.call("request_action", clip)
		_sync_manual_picker(clip)
		return
	_play_oneshot(clip)


func _update_aim_presentation(_delta: float) -> void:
	if not _simulate:
		_aiming = false
	_resolve_aim_point()
	_set_reticle_visible(_simulate and _aiming)
	if _aim_marker != null:
		_aim_marker.visible = _simulate and _aiming
		if _aim_marker.visible:
			_aim_marker.global_position = _aim_point

	# Pull camera in + blend toward over-the-shoulder while aiming.
	var target_dist: float = AIM_CAM_DIST if (_simulate and _aiming) else _default_cam_dist
	_cam_dist = lerpf(_cam_dist, target_dist, 0.14)
	var want_shoulder: float = 1.0 if (_simulate and _aiming) else 0.0
	_shoulder_blend = lerpf(_shoulder_blend, want_shoulder, 0.16)

	# Draw / holster sidearm on aim edge.
	if _char == null or not _char.has_method("set_held_sidearm"):
		_aim_was = _aiming
		return
	if _aiming == _aim_was:
		return
	_aim_was = _aiming
	if _aiming:
		_char.call("set_held_sidearm", true, true)
	else:
		_char.call("set_held_sidearm", true, false)  # holstered on hip


func _reticle_screen_pos() -> Vector2:
	var vp: Viewport = get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	if _simulate and _aiming:
		return size * AIM_RETICLE_UV
	return size * 0.5


func _resolve_aim_point() -> void:
	if _cam == null:
		return
	var screen: Vector2 = _reticle_screen_pos()
	var origin: Vector3 = _cam.project_ray_origin(screen)
	var dir: Vector3 = _cam.project_ray_normal(screen)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RAY_LEN)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		_aim_point = hit.position as Vector3
		return
	# Fallback: intersect ground plane y=0.
	if absf(dir.y) > 0.001:
		var t: float = -origin.y / dir.y
		if t > 0.0:
			_aim_point = origin + dir * t
			return
	_aim_point = origin + dir * 8.0


func _spawn_fire_fx() -> void:
	var from: Vector3 = _aim_point
	if _char != null and _char.has_method("muzzle_global_position"):
		from = _char.call("muzzle_global_position") as Vector3
	var to: Vector3 = _aim_point
	_play_random_sfx(FIRE_LASERS)
	_spawn_muzzle_flash(from)
	_spawn_bullet_bolt(from, to)


func _play_random_sfx(paths: Array[String]) -> void:
	if paths.is_empty():
		return
	Audio.play(paths[randi() % paths.size()])


func _spawn_muzzle_flash(at: Vector3) -> void:
	var flash: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	flash.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 4.0
	flash.material_override = mat
	add_child(flash)
	flash.global_position = at

	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.35)
	light.light_energy = 3.2
	light.omni_range = 2.2
	flash.add_child(light)

	var tw: Tween = create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.1)
	tw.tween_callback(flash.queue_free)


func _spawn_bullet_bolt(from: Vector3, to: Vector3) -> void:
	var dist: float = from.distance_to(to)
	if dist < 0.05:
		_spawn_impact_fx(to)
		return

	var bolt: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.04, 0.04, maxf(0.35, minf(0.9, dist * 0.12)))
	bolt.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.35, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.5
	bolt.material_override = mat
	add_child(bolt)
	bolt.global_position = from
	bolt.look_at(to, Vector3.UP)

	# Soft beam linger behind the bolt for one frame of readability.
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.018, 0.018, dist)
	beam.mesh = beam_box
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(1.0, 0.78, 0.3, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.65, 0.15)
	bmat.emission_energy_multiplier = 1.6
	beam.material_override = bmat
	add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	var beam_tw: Tween = create_tween()
	beam_tw.tween_property(bmat, "albedo_color:a", 0.0, 0.12)
	beam_tw.tween_callback(beam.queue_free)

	var travel: float = clampf(dist / 55.0, 0.045, 0.12)
	var tw: Tween = create_tween()
	tw.tween_property(bolt, "global_position", to, travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(bolt):
			bolt.queue_free()
		_spawn_impact_fx(to)
	)


func _spawn_impact_fx(at: Vector3) -> void:
	_play_random_sfx(FIRE_IMPACTS)

	var burst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	burst.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.25, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 5.0
	burst.material_override = mat
	add_child(burst)
	burst.global_position = at + Vector3(0.0, 0.04, 0.0)

	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.25)
	light.light_energy = 2.4
	light.omni_range = 1.8
	burst.add_child(light)

	# Tiny spark chips.
	for i in 5:
		var chip: MeshInstance3D = MeshInstance3D.new()
		var cmesh: BoxMesh = BoxMesh.new()
		cmesh.size = Vector3(0.03, 0.03, 0.08)
		chip.mesh = cmesh
		var cmat: StandardMaterial3D = StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		chip.material_override = cmat
		add_child(chip)
		chip.global_position = at + Vector3(0.0, 0.05, 0.0)
		var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		var end: Vector3 = chip.global_position + dir * randf_range(0.25, 0.55)
		var ctw: Tween = create_tween()
		ctw.tween_property(chip, "global_position", end, 0.18)
		ctw.parallel().tween_property(cmat, "albedo_color:a", 0.0, 0.18)
		ctw.tween_callback(chip.queue_free)

	var tw: Tween = create_tween()
	tw.tween_property(burst, "scale", Vector3(2.2, 2.2, 2.2), 0.14)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.14)
	tw.tween_callback(burst.queue_free)


func _set_reticle_visible(on: bool) -> void:
	if _reticle != null:
		_reticle.visible = on
		if on:
			_reticle.queue_redraw()


func _play_loop(clip: String) -> void:
	if _char == null or not _char.has_method("play"):
		return
	if str(_char.call("current_clip")) == clip:
		return
	_char.call("play", clip, 0.12)
	_sync_manual_picker(clip)


func _play_oneshot(clip: String) -> void:
	if _char == null or clip == "" or not _char.has_method("play"):
		return
	_oneshot_busy = true
	_char.call("play", clip, 0.05)
	_sync_manual_picker(clip)
	var player: AnimationPlayer = _char.get("_anim") as AnimationPlayer
	# Duck-typed: MintCharacter stores _anim privately — use call/current + timer.
	var anim: Animation = null
	if _char.has_method("clip_names"):
		# Estimate duration from AnimationPlayer if reachable.
		var node: Node = _char.get_node_or_null("Model")
		if node != null:
			player = _find_anim(node)
	if player != null and player.has_animation(clip):
		anim = player.get_animation(clip)
	var dur: float = 0.9
	if anim != null:
		dur = maxf(0.35, anim.length)
	await get_tree().create_timer(dur).timeout
	_oneshot_busy = false
	_state = ""  # force re-apply loco after oneshot
	if _simulate:
		_update_simulate(0.016)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f: AnimationPlayer = _find_anim(c)
		if f != null:
			return f
	return null


func _resolve(candidates: Array[String]) -> String:
	for name in candidates:
		if _has_clip(name):
			return name
	# Fuzzy: any clip containing a distinctive token.
	for name in candidates:
		var token: String = name.substr(0, mini(8, name.length())).to_lower()
		for existing in _clips:
			if String(existing).to_lower().find(token) >= 0:
				return existing
	return ""


func _has_clip(clip: String) -> bool:
	for existing in _clips:
		if existing == clip:
			return true
	return false


func _sync_manual_picker(clip: String) -> void:
	for i in _clips.size():
		if _clips[i] == clip:
			_clip_idx = i
			if _anim_pick != null and not _anim_pick.disabled:
				_anim_pick.select(i)
			break


func _poll_camera_orbit(delta: float) -> void:
	var look_x: float = Input.get_axis("camera_left", "camera_right")
	var look_y: float = Input.get_axis("camera_up", "camera_down")
	if absf(look_x) > 0.15 or absf(look_y) > 0.15:
		_cam_yaw -= look_x * delta * 2.2
		_cam_pitch = clampf(_cam_pitch + look_y * delta * 1.6, 0.05, 1.35)
	var zoom_in: float = Input.get_action_strength("zoom_in")
	var zoom_out: float = Input.get_action_strength("zoom_out")
	# In simulate, triggers are aim/fire — don't also zoom with them.
	if not _simulate:
		if zoom_in > 0.2:
			_cam_dist = maxf(1.6, _cam_dist - delta * 2.5 * zoom_in)
		if zoom_out > 0.2:
			_cam_dist = minf(12.0, _cam_dist + delta * 2.5 * zoom_out)


func _set_simulate(on: bool) -> void:
	_simulate = on
	_oneshot_busy = false
	_aiming = false
	_aim_was = false
	_sprint_latched = false
	_shoulder_blend = 0.0
	_airborne = false
	_vert_vel = 0.0
	_air_move = Vector3.ZERO
	_state = ""
	_apply_mode_ui()
	_set_reticle_visible(false)
	if _aim_marker != null:
		_aim_marker.visible = false
	if _simulate:
		_turntable = false
		get_viewport().gui_release_focus()
		_set_loco_state("idle")
		if _char != null and _char.has_method("set_held_sidearm"):
			_char.call("set_held_sidearm", true, false)
	else:
		if _char != null and _char.has_method("set_held_sidearm"):
			_char.call("set_held_sidearm", false, false)
		if _char_pick != null and not _char_pick.disabled:
			_char_pick.grab_focus()


func _apply_mode_ui() -> void:
	if _mode_btn != null:
		_mode_btn.text = "Mode: Simulate [M]" if _simulate else "Mode: Manual [M]"
	if _anim_pick != null:
		_anim_pick.disabled = _simulate or _clips.is_empty()
	if _simulate:
		get_viewport().gui_release_focus()


func _return_to_title() -> void:
	GameState.current_scene_path = ""
	get_tree().change_scene_to_file(TITLE_SCENE)


func _build_stage() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(32.0), 0.0)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(-2.2, 2.4, 2.0)
	fill.light_energy = 0.55
	fill.omni_range = 8.0
	add_child(fill)

	# Large static floor; world-space shader grid so travel reads as real progress.
	_floor_root = Node3D.new()
	_floor_root.name = "FloorRoot"
	add_child(_floor_root)
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	floor_mi.mesh = pm
	var grid_shader: Shader = load("res://shaders/mint_studio_grid.gdshader") as Shader
	if grid_shader != null:
		var smat: ShaderMaterial = ShaderMaterial.new()
		smat.shader = grid_shader
		floor_mi.material_override = smat
	else:
		var fmat: StandardMaterial3D = StandardMaterial3D.new()
		fmat.albedo_color = Color(0.14, 0.15, 0.18)
		floor_mi.material_override = fmat
	_floor_root.add_child(floor_mi)

	# Collision so aim rays hit the floor (Subnautica-style world cursor).
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "FloorBody"
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(200.0, 0.05, 200.0)
	col.shape = box
	col.position = Vector3(0.0, -0.025, 0.0)
	floor_body.add_child(col)
	_floor_root.add_child(floor_body)

	_aim_marker = MeshInstance3D.new()
	_aim_marker.name = "AimCursor"
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.08
	ring.outer_radius = 0.14
	ring.rings = 12
	ring.ring_segments = 24
	_aim_marker.mesh = ring
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.45, 0.9, 1.0, 0.95)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_marker.material_override = rmat
	_aim_marker.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_aim_marker.visible = false
	add_child(_aim_marker)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()
	_default_cam_dist = _cam_dist


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(400, 0)
	_ui_layer.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Animation Studio · Mint"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hint: Label = Label.new()
	hint.text = "L3 sprint latch · LT OTS aim · RT fire/use"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92, 0.9))
	vbox.add_child(hint)

	_char_pick = OptionButton.new()
	_char_pick.focus_mode = Control.FOCUS_ALL
	_char_pick.item_selected.connect(_on_char_selected)
	vbox.add_child(_char_pick)

	_mode_btn = Button.new()
	_mode_btn.focus_mode = Control.FOCUS_ALL
	_mode_btn.pressed.connect(func() -> void: _set_simulate(not _simulate))
	vbox.add_child(_mode_btn)

	_anim_pick = OptionButton.new()
	_anim_pick.focus_mode = Control.FOCUS_ALL
	_anim_pick.item_selected.connect(_on_anim_selected)
	vbox.add_child(_anim_pick)

	_back_btn = Button.new()
	_back_btn.text = "Back to Title"
	_back_btn.focus_mode = Control.FOCUS_ALL
	_back_btn.pressed.connect(_return_to_title)
	vbox.add_child(_back_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_status)

	_char_pick.focus_neighbor_bottom = _mode_btn.get_path()
	_mode_btn.focus_neighbor_top = _char_pick.get_path()
	_mode_btn.focus_neighbor_bottom = _anim_pick.get_path()
	_anim_pick.focus_neighbor_top = _mode_btn.get_path()
	_anim_pick.focus_neighbor_bottom = _back_btn.get_path()
	_back_btn.focus_neighbor_top = _anim_pick.get_path()

	_build_reticle()
	_populate_char_picker()
	for c in [_char_pick, _mode_btn, _anim_pick, _back_btn]:
		Audio.attach_ui_hover(c)


func _build_reticle() -> void:
	# Screen-center aim cursor (Subnautica-style). Visible only while LT/RMB aim.
	_reticle = Control.new()
	_reticle.name = "AimReticle"
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.visible = false
	_reticle.draw.connect(_draw_reticle)
	_ui_layer.add_child(_reticle)


func _draw_reticle() -> void:
	if _reticle == null:
		return
	var c: Vector2 = _reticle_screen_pos()
	var col := Color(0.55, 0.92, 1.0, 0.9)
	var gap: float = 6.0
	var arm: float = 14.0
	var thick: float = 2.0
	_reticle.draw_line(c + Vector2(-gap - arm, 0), c + Vector2(-gap, 0), col, thick)
	_reticle.draw_line(c + Vector2(gap, 0), c + Vector2(gap + arm, 0), col, thick)
	_reticle.draw_line(c + Vector2(0, -gap - arm), c + Vector2(0, -gap), col, thick)
	_reticle.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + arm), col, thick)
	_reticle.draw_arc(c, 18.0, 0.0, TAU, 48, col, 1.5, true)
	_reticle.draw_circle(c, 2.0, col)


func _populate_char_picker() -> void:
	_char_pick.clear()
	var slugs: Array = MintCharacterRef.profile_slugs()
	if slugs.is_empty():
		_char_pick.add_item("(no mint characters yet)")
		_char_pick.disabled = true
		_status.text = "Add entries to data/mint/characters.json after Mint export."
		return
	_char_pick.disabled = false
	for i in slugs.size():
		var slug: String = str(slugs[i])
		_char_pick.add_item(MintCharacterRef.display_name_for(slug), i)
		_char_pick.set_item_metadata(i, slug)
	_char_pick.select(0)


func _rebuild_character() -> void:
	if _char != null:
		_char.queue_free()
		_char = null
	_clips = PackedStringArray()
	_anim_pick.clear()
	_oneshot_busy = false
	_state = ""
	_aiming = false
	_aim_was = false
	_set_reticle_visible(false)
	if _aim_marker != null:
		_aim_marker.visible = false

	var slugs: Array = MintCharacterRef.profile_slugs()
	if slugs.is_empty():
		_refresh_status()
		return

	var idx: int = maxi(0, _char_pick.selected)
	var slug: String = str(slugs[idx])
	var meta: Variant = _char_pick.get_item_metadata(idx)
	if meta != null and str(meta) != "":
		slug = str(meta)
	_char = MintCharacterRef.load_profile(slug)
	if _char == null:
		_status.text = "Failed to load slug '%s'" % slug
		return
	add_child(_char)
	_facing = 0.0
	_char.rotation.y = 0.0

	await get_tree().process_frame
	await get_tree().process_frame
	if _char.has_method("clip_names"):
		_clips = _char.call("clip_names")
	_anim_pick.clear()
	if _clips.is_empty():
		_anim_pick.add_item("(no clips)")
		_anim_pick.disabled = true
	else:
		for i in _clips.size():
			_anim_pick.add_item(_clips[i], i)
		_clip_idx = 0
		_anim_pick.select(0)
	_apply_mode_ui()
	if _simulate:
		_set_loco_state("idle")
		if _char.has_method("set_held_sidearm"):
			_char.call("set_held_sidearm", true, false)
	elif not _clips.is_empty():
		_play_clip_at(0)
	_refresh_status()


func _on_char_selected(_index: int) -> void:
	_rebuild_character()


func _on_anim_selected(index: int) -> void:
	if _simulate:
		return
	_clip_idx = index
	_play_clip_at(_clip_idx)


func _step_clip(delta: int) -> void:
	if _clips.is_empty() or _simulate:
		return
	_clip_idx = (_clip_idx + delta) % _clips.size()
	if _clip_idx < 0:
		_clip_idx += _clips.size()
	_anim_pick.select(_clip_idx)
	_play_clip_at(_clip_idx)


func _play_clip_at(index: int) -> void:
	if _char == null or _clips.is_empty():
		return
	if index < 0 or index >= _clips.size():
		return
	_char.call("play", _clips[index])


func _refresh_status() -> void:
	if _status == null:
		return
	var clip: String = "(none)"
	if _char != null and _char.has_method("current_clip"):
		var cur: Variant = _char.call("current_clip")
		if str(cur) != "":
			clip = str(cur)
	var name_txt: String = "?"
	if _char != null:
		name_txt = str(_char.get("display_name"))
		if name_txt == "":
			name_txt = str(_char.get("slug"))
	var layers: PackedStringArray = PackedStringArray()
	if _aiming:
		layers.append("aim")
	if _char != null and _char.has_method("is_jump_active") and bool(_char.call("is_jump_active")):
		layers.append("jump")
	if _char != null and _char.has_method("is_fire_active") and bool(_char.call("is_fire_active")):
		layers.append("fire")
	if _char != null and _char.has_method("is_action_active") and bool(_char.call("is_action_active")):
		layers.append("action")
	var layer_txt: String = " · ".join(layers) if not layers.is_empty() else "—"
	var gait: String = "SPRINT" if _sprint_latched else _state.to_upper()
	if _simulate:
		_status.text = (
			"%s · loco %s · base %s · layers %s\n"
			+ "L3/Shift sprint latch · LT AIM (OTS) · RT FIRE while aiming · A jump · R-stick look"
		) % [name_txt, gait, clip, layer_txt]
	else:
		_status.text = (
			"%s · MANUAL · clip %s\n"
			+ "[M] simulate · D-pad clips · Y turntable · B back"
		) % [name_txt, clip]


func _update_camera() -> void:
	if _cam == null:
		return
	var target: Vector3 = Vector3(0.0, 1.0, 0.0)
	if _char != null:
		target = _char.global_position + Vector3(0.0, 1.15, 0.0)
	var back: Vector3 = Vector3(
		sin(_cam_yaw) * cos(_cam_pitch),
		sin(_cam_pitch),
		cos(_cam_yaw) * cos(_cam_pitch)
	)
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	# God-of-War OTS: sit over the right shoulder; character frames left.
	var shoulder: Vector3 = right * (AIM_SHOULDER * _shoulder_blend)
	var lift: Vector3 = Vector3(0.0, 0.12 * _shoulder_blend, 0.0)
	_cam.position = target + back * _cam_dist + shoulder + lift
	var look: Vector3 = target + right * (AIM_LOOK_AHEAD * _shoulder_blend) + Vector3(0.0, 0.05 * _shoulder_blend, 0.0)
	_cam.look_at(look)
