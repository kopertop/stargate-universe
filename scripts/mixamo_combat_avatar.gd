extends Node3D

# Mixamo combat host for gameplay. Prefers Y Bot pack when present, else Swat.
# Mirrors the signed-off showcase rules: unarmed holster idle/loco, dual rifle
# visibility, camera-forward shots, hip-location strip, one-shot foot align +
# idle-only sole lift. See docs/animation/mixamo-rifle-combat-showcase.md.

const YBOT_COMBAT_GLB: String = "res://models/mixamo_openbot/YBot_rifle_combat.glb"
const SWAT_COMBAT_GLB: String = "res://models/mixamo_openbot/Swat_rifle_combat.glb"
const SWAT_IDLE_GLB: String = "res://models/mixamo_openbot/Swat_rifle_idle.glb"

const FIRE_RATE: float = 0.11
const BOLT_SPEED: float = 55.0
const RANGE: float = 28.0
const FOOT_SOLE_CLEARANCE: float = 0.13
const IDLE_EXTRA_LIFT: float = 0.045
const WALK_ANIM_SPEED: float = 0.55
const RUN_ANIM_SPEED: float = 1.0

const IDLE_CLIPS: Array[String] = ["Unarmed_Idle", "Breathing_Idle"]
const LOCO_CLIPS: Array[String] = ["Running"]
const SHOOT_CLIPS: Array[String] = ["Shoot_Rifle", "Firing_Rifle"]
const STRAFE_CLIPS: Array[String] = ["Strafe", "Strafe_Alt"]
const STRAFE_ALT_CLIPS: Array[String] = ["Strafe_Alt", "Strafe"]
const CROUCH_AIM_CLIPS: Array[String] = [
	"Rifle_Crouched_Idle_Aim", "Crouch_Idle_Aim", "Rifle_Idle",
]
const CROUCH_FIRE_CLIPS: Array[String] = [
	"Fire_Rifle_Crouched", "Firing_Rifle", "Shoot_Rifle",
]
const TOOL_DIGGING_CLIPS: Array[String] = [
	"Digging", "Digging_01", "Interact_Stub",
]
const TOOL_REPAIR_CLIPS: Array[String] = [
	"Working_On_Device", "Working", "Working_On_Device_01", "Interact_Stub",
]

const LASERS: Array[String] = [
	"res://sounds/laser_small_000.ogg",
	"res://sounds/laser_small_001.ogg",
	"res://sounds/laser_small_002.ogg",
]
const IMPACTS: Array[String] = [
	"res://sounds/impact_metal_000.ogg",
	"res://sounds/impact_metal_001.ogg",
]

enum Stance { HOLSTER, AIM_MOVE, AIM_CROUCH }

var _host: Node3D = null
var _anim: AnimationPlayer = null
var _skel: Skeleton3D = null
var _rifle: Node3D = null
var _rifle_holster: Node3D = null
var _muzzle: Node3D = null
var _stance: Stance = Stance.HOLSTER
var _fire_cd: float = 0.0
var _recoil_kick: float = 0.0
var _rifle_hand_pos: Vector3 = Vector3.ZERO
var _rifle_hand_rot: Vector3 = Vector3.ZERO
var _rifle_holstered: bool = true
var _host_floor_y: float = 0.0
var _feet_aligned: bool = false
var _ready_ok: bool = false
var _aiming: bool = false
var _tool_use_active: bool = false
var _tool_use_kind: String = ""
var _tool_use_clip: String = ""
var _tool_use_fallback: bool = false


static func resolve_combat_glb() -> String:
	if ResourceLoader.exists(YBOT_COMBAT_GLB):
		return YBOT_COMBAT_GLB
	if ResourceLoader.exists(SWAT_COMBAT_GLB):
		return SWAT_COMBAT_GLB
	return ""


static func combat_pack_available() -> bool:
	return resolve_combat_glb() != "" or ResourceLoader.exists(SWAT_IDLE_GLB)


static func create() -> Node3D:
	var avatar: Node3D = (load("res://scripts/mixamo_combat_avatar.gd") as GDScript).new() as Node3D
	avatar.name = "MixamoCombatAvatar"
	return avatar


func is_combat_ready() -> bool:
	return _ready_ok and _anim != null


func is_aiming_stance() -> bool:
	return _aiming and not _tool_use_active


func is_tool_use_active() -> bool:
	return _tool_use_active


func is_tool_use_fallback() -> bool:
	return _tool_use_active and _tool_use_fallback


func begin_tool_use(kind: String) -> void:
	if not _ready_ok:
		return
	_tool_use_active = true
	_tool_use_kind = kind
	_aiming = false
	_set_rifle_holstered(true)
	var prefs: Array[String] = TOOL_DIGGING_CLIPS if kind == "digging" else TOOL_REPAIR_CLIPS
	_tool_use_clip = _pick_clip(prefs)
	_tool_use_fallback = _tool_use_clip == ""
	if _tool_use_fallback:
		_tool_use_clip = _pick_clip(IDLE_CLIPS)
	if _tool_use_clip != "":
		_play_clip(_tool_use_clip, true)


func end_tool_use() -> void:
	if not _tool_use_active:
		return
	_tool_use_active = false
	_tool_use_kind = ""
	_tool_use_clip = ""
	_tool_use_fallback = false


func find_skeleton() -> Skeleton3D:
	return _skel


func mount() -> bool:
	var path: String = resolve_combat_glb()
	if path == "":
		path = SWAT_IDLE_GLB
	if not ResourceLoader.exists(path):
		push_warning(
			"MixamoCombatAvatar: missing combat pack — rebuild via "
			+ "tools/blender_mixamo_rifle_combat.py (--host ybot or swat)"
		)
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	_host = packed.instantiate() as Node3D
	if _host == null:
		return false
	# Mixamo faces +Z; gameplay characters face -Z like Mint/modular.
	_host.rotation.y = PI
	add_child(_host)
	_anim = _find_anim(_host)
	_skel = _find_skel(_host)
	_rifle = _find_weapon_mesh(_host)
	_muzzle = _find_named(_host, "Muzzle")
	_lock_root_translation_tracks()
	_setup_rifle_mounts()
	_play_clip(_pick_clip(IDLE_CLIPS), true)
	_ready_ok = _anim != null
	return _ready_ok


func align_feet_once() -> void:
	if _host == null or _feet_aligned:
		return
	var sole_y: float = _lowest_sole_y()
	if sole_y >= 1e8:
		_host_floor_y = _host.position.y
		_feet_aligned = true
		return
	# Capsule/player origin is floor; lift host so soles clear the floor.
	var body_floor_y: float = global_position.y
	var delta: float = (body_floor_y + FOOT_SOLE_CLEARANCE) - sole_y
	_host.position.y += delta
	_host_floor_y = _host.position.y
	_feet_aligned = true


func tick(delta: float, aiming: bool, want_fire: bool, move_input: Vector2, sprinting: bool, cam_yaw: float) -> void:
	if not _ready_ok:
		return
	if _tool_use_active:
		_aiming = false
		_fire_cd = maxf(0.0, _fire_cd - delta)
		_recoil_kick = move_toward(_recoil_kick, 0.0, delta * 8.0)
		_set_rifle_holstered(true)
		if _tool_use_clip != "" and (
			_anim.current_animation != _tool_use_clip
			or not _anim.is_playing()
		):
			_play_clip(_tool_use_clip, true)
		_apply_idle_foot_bias(false, move_input)
		return
	_aiming = aiming
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_recoil_kick = move_toward(_recoil_kick, 0.0, delta * 8.0)
	_sync_stance(aiming, want_fire, move_input, sprinting, cam_yaw)
	_apply_idle_foot_bias(aiming, move_input)
	_update_rifle_recoil()


func try_fire(camera: Camera3D) -> bool:
	if not _ready_ok or _fire_cd > 0.0 or _rifle_holstered:
		return false
	_fire_cd = FIRE_RATE
	_recoil_kick = 1.0
	var muzzle: Vector3 = _muzzle_world()
	var forward: Vector3 = _aim_forward(camera, muzzle)
	_spawn_muzzle_flash(muzzle, forward)
	_spawn_projectile(muzzle, forward)
	_play_sfx(LASERS)
	return true


func _sync_stance(aiming: bool, want_fire: bool, move_input: Vector2, sprinting: bool, cam_yaw: float) -> void:
	var moving: bool = move_input.length_squared() > 0.04
	var next: Stance = Stance.HOLSTER
	if aiming:
		next = Stance.AIM_MOVE if moving else Stance.AIM_CROUCH
	var stance_changed: bool = next != _stance
	_stance = next
	_set_rifle_holstered(not aiming)

	var clip := ""
	var anim_speed: float = 1.0
	match _stance:
		Stance.HOLSTER:
			if moving:
				clip = _pick_clip(LOCO_CLIPS)
				anim_speed = RUN_ANIM_SPEED if sprinting else WALK_ANIM_SPEED
			else:
				clip = _pick_clip(IDLE_CLIPS)
		Stance.AIM_MOVE:
			var side: float = _aim_move_side(move_input, cam_yaw)
			if absf(side) > 0.45:
				clip = _pick_clip(STRAFE_ALT_CLIPS if side > 0.0 else STRAFE_CLIPS)
			else:
				clip = _pick_clip(SHOOT_CLIPS)
		Stance.AIM_CROUCH:
			clip = _pick_clip(CROUCH_FIRE_CLIPS if want_fire else CROUCH_AIM_CLIPS)

	if clip != "" and (
		stance_changed
		or _anim.current_animation != clip
		or not _anim.is_playing()
		or not is_equal_approx(_anim.speed_scale, anim_speed)
	):
		_play_clip(clip, true, anim_speed)


func _aim_move_side(move_input: Vector2, cam_yaw: float) -> float:
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := (forward * -move_input.y + right * move_input.x)
	if wish.length_squared() < 0.001:
		return 0.0
	return wish.normalized().dot(right)


func _apply_idle_foot_bias(aiming: bool, move_input: Vector2) -> void:
	if _host == null or not _feet_aligned:
		return
	var idle_stand: bool = (
		not aiming
		and move_input.length_squared() < 0.04
		and _stance == Stance.HOLSTER
	)
	_host.position.y = _host_floor_y + (IDLE_EXTRA_LIFT if idle_stand else 0.0)


func _aim_forward(camera: Camera3D, _muzzle: Vector3) -> Vector3:
	if camera != null:
		var dir: Vector3 = -camera.global_transform.basis.z
		if dir.length_squared() > 0.001:
			return dir.normalized()
	return -global_transform.basis.z


func _muzzle_world() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	if _rifle != null:
		return _rifle.global_position + Vector3(0.0, 0.05, -0.35)
	return global_position + Vector3(0.0, 1.2, -0.4)


func _update_rifle_recoil() -> void:
	if _rifle == null or _rifle_holstered:
		return
	_rifle.position = _rifle_hand_pos + Vector3(0.0, -0.02 * _recoil_kick, 0.01 * _recoil_kick)
	_rifle.rotation = _rifle_hand_rot + Vector3(deg_to_rad(-2.8 * _recoil_kick), 0.0, 0.0)


func _setup_rifle_mounts() -> void:
	if _rifle == null:
		return
	_rifle_holster = _find_exact_named(_host, "rifle_holster")
	_rifle_hand_pos = _rifle.position
	_rifle_hand_rot = _rifle.rotation
	_muzzle = _find_named(_rifle, "Muzzle")
	if _muzzle == null:
		_muzzle = _find_named(_host, "Muzzle")
	_set_rifle_holstered(true)


func _set_rifle_holstered(holstered: bool) -> void:
	if _rifle == null:
		return
	_rifle_holstered = holstered
	_recoil_kick = 0.0
	if _rifle_holster != null:
		_rifle.visible = not holstered
		_rifle_holster.visible = holstered
	else:
		_rifle.visible = true


func _lock_root_translation_tracks() -> void:
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
	for want in prefs:
		for have in available:
			if str(have) == want:
				return str(have)
	for want in prefs:
		for have in available:
			if str(have).ends_with("/" + want) or str(have).ends_with("|" + want):
				return str(have)
	return ""


func _lowest_sole_y() -> float:
	if _skel == null:
		return 1e9
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
	return bone_lowest


func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var found: AnimationPlayer = _find_anim(c)
		if found != null:
			return found
	return null


func _find_skel(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for c in root.get_children():
		var found: Skeleton3D = _find_skel(c)
		if found != null:
			return found
	return null


func _find_named(root: Node, want: String) -> Node3D:
	var want_l := want.to_lower()
	for n in root.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower() == want_l:
			return n as Node3D
	return null


func _find_exact_named(root: Node, want: String) -> Node3D:
	return _find_named(root, want)


func _find_weapon_mesh(root: Node) -> Node3D:
	# Exact "rifle" only — packed root name can contain "rifle" as substring.
	var exact: Node3D = _find_exact_named(root, "rifle")
	if exact != null:
		return exact
	return null


func _play_sfx(paths: Array[String]) -> void:
	if paths.is_empty():
		return
	var p: String = paths[randi() % paths.size()]
	var audio_n: Node = get_node_or_null("/root/Audio")
	if audio_n != null and audio_n.has_method("play"):
		audio_n.call("play", p)
		return
	if not ResourceLoader.exists(p):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(p) as AudioStream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


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
	var flash_parent: Node = get_tree().current_scene if get_tree().current_scene != null else self
	flash_parent.add_child(flash)
	flash.global_position = at + dir * 0.05
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)


func _spawn_projectile(from: Vector3, dir: Vector3) -> void:
	var parent_n: Node = get_tree().current_scene if get_tree().current_scene != null else self
	var body := Area3D.new()
	body.monitoring = true
	body.monitorable = false
	parent_n.add_child(body)
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
	var runner := Node.new()
	parent_n.add_child(runner)
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
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			body.global_position - dir * step, body.global_position + dir * 0.05
		)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_spawn_impact(hit.position as Vector3)
			_play_sfx(IMPACTS)
			body.queue_free()
			break
		if body.global_position.y < 0.02 or traveled >= RANGE:
			_spawn_impact(body.global_position)
			body.queue_free()
			break
	if is_instance_valid(runner):
		runner.queue_free()


func _spawn_impact(at: Vector3) -> void:
	var parent_n: Node = get_tree().current_scene if get_tree().current_scene != null else self
	var burst := GPUParticles3D.new()
	burst.amount = 14
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 0.95
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 55.0
	pmat.initial_velocity_min = 1.0
	pmat.initial_velocity_max = 3.0
	pmat.gravity = Vector3(0.0, -6.0, 0.0)
	pmat.scale_min = 0.02
	pmat.scale_max = 0.06
	pmat.color = Color(1.0, 0.7, 0.25, 1.0)
	burst.process_material = pmat
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	burst.draw_pass_1 = sm
	parent_n.add_child(burst)
	burst.global_position = at
	burst.emitting = true
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(burst.queue_free)
