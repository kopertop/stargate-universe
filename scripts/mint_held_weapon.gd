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
var holster_pos: Vector3 = Vector3(0.14, 0.02, 0.04)
var holster_rot: Vector3 = Vector3(-1.57, 0.0, 0.0)
var hand_pos: Vector3 = Vector3(0.0, 0.06, 0.02)
var hand_rot: Vector3 = Vector3(0.0, -1.57, 0.0)
var muzzle_local: Vector3 = Vector3(0.18, 0.02, 0.0)
var prop_scale: float = 1.0
var supports_fire: bool = true
var grip_profile: String = "pistol"
var kind: String = "one_handed"

var _skel: Skeleton3D = null
var _holster_mount: BoneAttachment3D = null
var _hand_mount: BoneAttachment3D = null
var _prop: Node3D = null
var _grip = HandGripScript.new()
var _draw_token: int = 0


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
	_prop.scale = Vector3.ONE * prop_scale

	_holster_mount = _make_mount("HolsterMount", holster_bone)
	_hand_mount = _make_mount("HandMount", hand_bone)
	_skel.add_child(_holster_mount)
	_skel.add_child(_hand_mount)
	_attach_to_holster()
	_grip.attach(_skel, hand_bone, grip_profile)
	_set_state(State.HOLSTERED)
	return true


func unequip() -> void:
	_draw_token += 1
	_grip.detach()
	if _prop != null and is_instance_valid(_prop):
		_prop.queue_free()
	_prop = null
	if _holster_mount != null and is_instance_valid(_holster_mount):
		_holster_mount.queue_free()
	_holster_mount = null
	if _hand_mount != null and is_instance_valid(_hand_mount):
		_hand_mount.queue_free()
	_hand_mount = null
	_skel = null
	_set_state(State.HOLSTERED)


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
	if state == State.DRAWING:
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
		return _prop.global_transform * muzzle_local
	if _hand_mount != null and is_instance_valid(_hand_mount):
		return _hand_mount.global_position
	return Vector3.ZERO


func apply_grip_pose() -> void:
	_grip.apply()


func grip_status() -> String:
	return _grip.status_line()


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
	if config.has("holster_pos"):
		holster_pos = _vec3(config["holster_pos"], holster_pos)
	if config.has("holster_rot"):
		holster_rot = _vec3(config["holster_rot"], holster_rot)
	if config.has("hand_pos"):
		hand_pos = _vec3(config["hand_pos"], hand_pos)
	if config.has("hand_rot"):
		hand_rot = _vec3(config["hand_rot"], hand_rot)
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
	_prop.position = holster_pos
	_prop.rotation = holster_rot


func _attach_to_hand() -> void:
	if _prop == null or _hand_mount == null:
		return
	var parent: Node = _prop.get_parent()
	if parent != null:
		parent.remove_child(_prop)
	_hand_mount.add_child(_prop)
	_prop.position = hand_pos
	_prop.rotation = hand_rot


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
