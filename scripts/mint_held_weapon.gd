extends Node
class_name MintHeldWeapon

# One mesh, two mounts (holster + hand). Same contract a repair tool will use:
# LT draw/aim → RT use/fire → release holster.

const HandGripScript: Script = preload("res://scripts/mint_hand_grip.gd")

enum State { HOLSTERED, DRAWING, AIMED, FIRING, HOLSTERING }

signal state_changed(new_state: int)
signal drawn
signal holstered

const DEFAULT_GLB: String = "res://models/quaternius/guns/Gun_Pistol.gltf"
const DRAW_SWAP_FRAC: float = 0.4
const HOLSTER_SWAP_FRAC: float = 0.35

var state: int = State.HOLSTERED
var weapon_id: String = ""
var display_name: String = "Weapon"
var glb_path: String = DEFAULT_GLB
var holster_bone: String = "Hips"
var hand_bone: String = "RightHand"
var support_bone: String = ""
var holster_pos: Vector3 = Vector3(0.14, 0.02, 0.04)
var holster_rot: Vector3 = Vector3(-1.57, 0.0, 0.0)
var hand_pos: Vector3 = Vector3(0.0, 0.06, 0.02)
var hand_rot: Vector3 = Vector3(0.0, -1.57, 0.0)
var support_pos: Vector3 = Vector3.ZERO
var support_local: Vector3 = Vector3(0.18, 0.0, 0.0)
var muzzle_local: Vector3 = Vector3(0.18, 0.02, 0.0)
var prop_scale: float = 1.0
var supports_fire: bool = true
var grip_profile: String = "pistol"
var kind: String = "one_handed"

var _skel: Skeleton3D = null
var _holster_mount: BoneAttachment3D = null
var _hand_mount: BoneAttachment3D = null
var _support_mount: BoneAttachment3D = null
var _prop: Node3D = null
var _aim_socket: Node3D = null
var _grip = HandGripScript.new()
var _draw_token: int = 0
## True after orient_for_character_aim — stationary rifle uses IK, not soft pull.
var _ik_two_hand_active: bool = false
var _ik_right: TwoBoneIK3D = null
var _ik_left: TwoBoneIK3D = null
var _ik_target_r: Marker3D = null
var _ik_target_l: Marker3D = null
var _ik_pole_r: Marker3D = null
var _ik_pole_l: Marker3D = null


func equip(skeleton: Skeleton3D, config: Dictionary = {}) -> bool:
	unequip()
	_skel = skeleton
	if _skel == null:
		return false
	_apply_config(config)
	if _skel.find_bone(holster_bone) < 0:
		# Spine may be missing on some Mint exports — fall back to Hips.
		if holster_bone != "Hips" and _skel.find_bone("Hips") >= 0:
			holster_bone = "Hips"
		else:
			push_warning("MintHeldWeapon: missing holster bone %s" % holster_bone)
			return false
	if _skel.find_bone(hand_bone) < 0:
		push_warning("MintHeldWeapon: missing hand bone %s" % hand_bone)
		return false
	if not ResourceLoader.exists(glb_path):
		push_warning("MintHeldWeapon: missing %s" % glb_path)
		return false
	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		return false
	_prop = packed.instantiate() as Node3D
	if _prop == null:
		return false
	_prop.name = "WeaponProp"

	_holster_mount = _make_mount("HolsterMount", holster_bone)
	_hand_mount = _make_mount("HandMount", hand_bone)
	_skel.add_child(_holster_mount)
	_skel.add_child(_hand_mount)
	if support_bone != "" and _skel.find_bone(support_bone) >= 0:
		_support_mount = _make_mount("SupportMount", support_bone)
		_skel.add_child(_support_mount)
	_attach_to_holster()
	_apply_prop_scale()
	_grip.attach(_skel, hand_bone, grip_profile)
	_set_state(State.HOLSTERED)
	return true


func unequip() -> void:
	_draw_token += 1
	_grip.detach()
	# Free mounts/prop immediately. queue_free leaves "HolsterMount"/"HandMount"
	# names in the skeleton until end of frame, so the next equip's mounts get
	# renamed and look-ups / visual harnesses attach to the wrong nodes.
	_free_node(_prop)
	_prop = null
	_free_node(_holster_mount)
	_holster_mount = null
	_free_node(_hand_mount)
	_hand_mount = null
	_free_node(_support_mount)
	_support_mount = null
	_free_node(_aim_socket)
	_aim_socket = null
	_teardown_rifle_ik()
	_skel = null
	_ik_two_hand_active = false
	_set_state(State.HOLSTERED)


func _free_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var parent: Node = n.get_parent()
	if parent != null:
		parent.remove_child(n)
	n.free()


func has_support_mount() -> bool:
	return _support_mount != null and is_instance_valid(_support_mount)


func is_drawn() -> bool:
	return state == State.AIMED or state == State.FIRING or state == State.DRAWING


func is_ready_to_fire() -> bool:
	return supports_fire and (state == State.AIMED or state == State.FIRING)


func request_draw(draw_duration: float = 0.55) -> void:
	if state == State.AIMED or state == State.DRAWING or state == State.FIRING:
		return
	_draw_token += 1
	var token: int = _draw_token
	_set_state(State.DRAWING)
	_draw_swap_async(token, clampf(draw_duration * DRAW_SWAP_FRAC, 0.08, 0.45))


func request_holster(holster_duration: float = 0.35) -> void:
	if state == State.HOLSTERED or state == State.HOLSTERING:
		return
	_draw_token += 1
	var token: int = _draw_token
	_ik_two_hand_active = false
	_set_state(State.HOLSTERING)
	_grip.set_grip(false)
	_holster_swap_async(token, clampf(holster_duration * HOLSTER_SWAP_FRAC, 0.05, 0.25))


func _draw_swap_async(token: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if token != _draw_token or state != State.DRAWING:
		return
	_attach_to_hand()
	_grip.set_grip(true)
	_set_state(State.AIMED)
	drawn.emit()


func _holster_swap_async(token: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if token != _draw_token or state != State.HOLSTERING:
		return
	_attach_to_holster()
	_set_state(State.HOLSTERED)
	holstered.emit()


func notify_draw_finished() -> void:
	# Allow force-aim from HOLSTERED (capture harness / tests skipping the timer).
	if state == State.DRAWING or state == State.HOLSTERED:
		_attach_to_hand()
		_grip.set_grip(true)
		_set_state(State.AIMED)
		drawn.emit()


func notify_holster_finished() -> void:
	if state == State.HOLSTERING:
		_attach_to_holster()
		_set_state(State.HOLSTERED)
		holstered.emit()


func notify_fire_started() -> void:
	if state == State.AIMED:
		_set_state(State.FIRING)


func notify_fire_finished() -> void:
	if state == State.FIRING:
		_set_state(State.AIMED)


func muzzle_global_position() -> Vector3:
	if _prop != null and is_instance_valid(_prop):
		# Author offsets are meters on the prop facing — not pre-scaled by the
		# compensatory prop.scale used for Mint's cm-scale skeleton.
		return _prop_point_world(muzzle_local)
	if _hand_mount != null and is_instance_valid(_hand_mount):
		return _hand_mount.global_position
	return Vector3.ZERO


func apply_grip_pose() -> void:
	_grip.apply()
	if kind == "two_handed" and (state == State.AIMED or state == State.FIRING):
		# seat_rifle_on_hand() owns the rifle local seat after grip bias.
		return
	apply_support_pose()


## Seat rifle in the two-hand hold space from the frozen Meshy shoot pose.
## Mint Meshy bone axes break TwoBoneIK (arms flip behind the back), so we do
## NOT IK hands to the gun — we place the gun between the animated hands.
func seat_rifle_on_hand() -> void:
	if _prop == null or _hand_mount == null:
		return
	if state != State.AIMED and state != State.FIRING and state != State.DRAWING:
		return
	if kind != "two_handed":
		return
	_ik_two_hand_active = false
	_set_rifle_ik_influence(0.0)
	var host: Node3D = get_parent() as Node3D
	if host == null or not has_support_mount():
		_seat_rifle_on_right_hand_only()
		return
	var right_p: Vector3 = _hand_mount.global_position
	var left_p: Vector3 = _support_mount.global_position
	var aim_dir: Vector3 = (-host.global_transform.basis.z).normalized()
	var hand_span: Vector3 = left_p - right_p
	# Prefer character forward; if hands already form a clear aim line, blend in.
	if hand_span.length() > 0.08:
		var along_hands: Vector3 = hand_span.normalized()
		if along_hands.dot(aim_dir) < 0.0:
			along_hands = -along_hands
		aim_dir = aim_dir.lerp(along_hands, 0.25).normalized()
	var up: Vector3 = host.global_transform.basis.y.normalized()
	if absf(aim_dir.dot(up)) > 0.92:
		up = host.global_transform.basis.x.normalized()
	# Pistol grip near the right palm; mild pull-back so stock reads nearer the body.
	var grip: Vector3 = right_p.lerp(left_p, 0.18)
	grip -= aim_dir * 0.07
	grip += up * 0.01
	var z_axis: Vector3 = aim_dir
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	if x_axis.length_squared() < 1e-6:
		x_axis = host.global_transform.basis.x.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	var world_basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	_reparent_prop_to_aim_socket()
	_prop.global_transform = Transform3D(world_basis, grip)
	_prop.scale = Vector3.ONE * prop_scale


func _seat_rifle_on_right_hand_only() -> void:
	if _prop.get_parent() != _hand_mount:
		var prev: Node = _prop.get_parent()
		if prev != null:
			prev.remove_child(_prop)
		_hand_mount.add_child(_prop)
	_prop.position = _meters_to_bone_local(hand_pos)
	_prop.rotation = hand_rot
	_apply_prop_scale()


func _reparent_prop_to_aim_socket() -> void:
	if _prop == null:
		return
	if _aim_socket == null or not is_instance_valid(_aim_socket):
		_aim_socket = Node3D.new()
		_aim_socket.name = "RifleAimSocket"
		var host: Node = get_parent()
		if host == null:
			host = self
		host.add_child(_aim_socket)
	if _prop.get_parent() == _aim_socket:
		return
	var prev: Node = _prop.get_parent()
	if prev != null:
		prev.remove_child(_prop)
	_aim_socket.add_child(_prop)


func clear_ik_two_hand() -> void:
	_ik_two_hand_active = false
	_set_rifle_ik_influence(0.0)


func _set_rifle_ik_influence(amount: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	if _ik_right != null and is_instance_valid(_ik_right):
		_ik_right.influence = a
	if _ik_left != null and is_instance_valid(_ik_left):
		_ik_left.influence = a


func _teardown_rifle_ik() -> void:
	_set_rifle_ik_influence(0.0)
	_free_node(_ik_right)
	_ik_right = null
	_free_node(_ik_left)
	_ik_left = null
	_free_node(_ik_target_r)
	_ik_target_r = null
	_free_node(_ik_target_l)
	_ik_target_l = null
	_free_node(_ik_pole_r)
	_ik_pole_r = null
	_free_node(_ik_pole_l)
	_ik_pole_l = null
	_free_node(_aim_socket)
	_aim_socket = null


## Soft two-hand: bias forestock toward LeftHand when the shoot pose keeps hands close.
func apply_support_pose() -> void:
	if _prop == null or _hand_mount == null or _support_mount == null:
		return
	if state != State.AIMED and state != State.FIRING and state != State.DRAWING:
		return
	if _prop.get_parent() != _hand_mount:
		return
	var seat: Vector3 = _meters_to_bone_local(hand_pos)
	_prop.position = seat
	_prop.rotation = hand_rot
	var hand_sep: float = _hand_mount.global_position.distance_to(_support_mount.global_position)
	if hand_sep > 0.55:
		return
	var target_world: Vector3 = _support_mount.to_global(_meters_to_bone_local(support_pos))
	var current_world: Vector3 = _prop_point_world(support_local)
	var delta_world: Vector3 = target_world - current_world
	var pull: float = 0.65
	var delta_local: Vector3 = _hand_mount.global_transform.basis.inverse() * delta_world
	var cap_local: float = 0.12 / maxf(_skel_uniform_scale(), 1e-5)
	if delta_local.length() > cap_local:
		delta_local = delta_local.normalized() * cap_local
	_prop.position = seat + delta_local * pull


## World point for an authored meter-offset on the prop (ignores prop.scale).
func _prop_point_world(local_m: Vector3) -> Vector3:
	if _prop == null:
		return Vector3.ZERO
	var xf: Transform3D = _prop.global_transform
	return xf.origin + xf.basis.orthonormalized() * local_m


func grip_status() -> String:
	var base: String = _grip.status_line()
	if has_support_mount() and (state == State.AIMED or state == State.FIRING):
		return "%s · 2H" % base
	return base


func _apply_config(config: Dictionary) -> void:
	if config.has("id"):
		weapon_id = str(config["id"])
	if config.has("display_name"):
		display_name = str(config["display_name"])
	if config.has("glb"):
		glb_path = str(config["glb"])
	if config.has("holster_bone"):
		holster_bone = str(config["holster_bone"])
	if config.has("hand_bone"):
		hand_bone = str(config["hand_bone"])
	if config.has("support_bone"):
		support_bone = str(config["support_bone"])
	if config.has("holster_pos"):
		holster_pos = _vec3(config["holster_pos"], holster_pos)
	if config.has("holster_rot"):
		holster_rot = _vec3(config["holster_rot"], holster_rot)
	if config.has("hand_pos"):
		hand_pos = _vec3(config["hand_pos"], hand_pos)
	if config.has("hand_rot"):
		hand_rot = _vec3(config["hand_rot"], hand_rot)
	if config.has("support_pos"):
		support_pos = _vec3(config["support_pos"], support_pos)
	if config.has("support_local"):
		support_local = _vec3(config["support_local"], support_local)
	if config.has("muzzle_local"):
		muzzle_local = _vec3(config["muzzle_local"], muzzle_local)
	if config.has("scale"):
		prop_scale = float(config["scale"])
	if config.has("supports_fire"):
		supports_fire = bool(config["supports_fire"])
	if config.has("grip_profile"):
		grip_profile = str(config["grip_profile"])
	if config.has("kind"):
		kind = str(config["kind"])


func _attach_to_holster() -> void:
	if _prop == null or _holster_mount == null:
		return
	var parent: Node = _prop.get_parent()
	if parent != null:
		parent.remove_child(_prop)
	_holster_mount.add_child(_prop)
	# Holster offsets are authored in meters (body clearance). Mint's skeleton
	# node is ~0.01 scale, so convert like prop_scale or a "0.22 behind" sits
	# 2mm inside the gut.
	_prop.position = _meters_to_bone_local(holster_pos)
	_prop.rotation = holster_rot
	_apply_prop_scale()


func _attach_to_hand() -> void:
	if _prop == null or _hand_mount == null:
		return
	var parent: Node = _prop.get_parent()
	if parent != null:
		parent.remove_child(_prop)
	_hand_mount.add_child(_prop)
	# Hand seat authored in meters (same as holster). Mint skeleton is ~0.01
	# scale — raw 0.05 "looks like" a palm bias but is 0.5mm in world.
	_prop.position = _meters_to_bone_local(hand_pos)
	_prop.rotation = hand_rot
	_apply_prop_scale()
	apply_support_pose()


## Mint skeletons are ~0.01 global scale (cm rig). Prop GLBs are ~1m meters —
## without compensation, scale 0.24 becomes a 2mm speck. Author prop_scale in
## meters of desired world size on a unit parent; we divide by skeleton scale.
func _apply_prop_scale() -> void:
	if _prop == null:
		return
	var parent_s: float = _skel_uniform_scale()
	_prop.scale = Vector3.ONE * (prop_scale / parent_s)


func _skel_uniform_scale() -> float:
	if _skel == null:
		return 1.0
	var parent_s: float = absf(_skel.global_transform.basis.get_scale().x)
	return parent_s if parent_s >= 1e-5 else 1.0


func _meters_to_bone_local(meters: Vector3) -> Vector3:
	return meters / _skel_uniform_scale()


func _bone_local_to_meters(local: Vector3) -> Vector3:
	return local * _skel_uniform_scale()


func _make_mount(mount_name: String, bone: String) -> BoneAttachment3D:
	var m := BoneAttachment3D.new()
	m.name = mount_name
	m.bone_name = bone
	return m


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _vec3(v: Variant, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		return v as Vector3
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v as Array
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v as Dictionary
		return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	return fallback


func state_name() -> String:
	match state:
		State.HOLSTERED:
			return "HOLSTERED"
		State.DRAWING:
			return "DRAWING"
		State.AIMED:
			return "AIMED"
		State.FIRING:
			return "FIRING"
		State.HOLSTERING:
			return "HOLSTERING"
		_:
			return "?"
