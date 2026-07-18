extends RefCounted
class_name MintHandGrip

# Finger / grip posing for Mint characters.
# Prefer real finger bones when the skeleton has them; otherwise build a
# lightweight finger proxy chain under the hand so grips still read AAA.

const FINGER_HINTS: Array[String] = [
	"Thumb", "Index", "Middle", "Ring", "Pinky", "Little", "Finger",
]

# Mixamo-style + common Autodesk/UE names (substring match, case-insensitive).
const RIGHT_HAND_ALIASES: Array[String] = ["RightHand", "Hand_R", "hand_r", "mixamorig:RightHand"]
const LEFT_HAND_ALIASES: Array[String] = ["LeftHand", "Hand_L", "hand_l", "mixamorig:LeftHand"]

var mode: String = "proxy" # "bones" | "proxy" | "none"
var profile: String = "pistol"
var bone_count: int = 0
var finger_bone_count: int = 0

var _skel: Skeleton3D = null
var _hand_idx: int = -1
var _hand_rest: Quaternion = Quaternion.IDENTITY
var _finger_idxs: Array[int] = []
var _finger_rests: Array[Quaternion] = []
var _proxy_root: Node3D = null
var _proxy_joints: Array[Node3D] = []
var _active: bool = false
var _hand_euler: Vector3 = Vector3(deg_to_rad(10.0), deg_to_rad(-6.0), deg_to_rad(14.0))


func attach(skeleton: Skeleton3D, hand_bone: String = "RightHand", grip_profile: String = "pistol") -> bool:
	detach()
	_skel = skeleton
	profile = grip_profile
	if _skel == null:
		mode = "none"
		return false
	bone_count = _skel.get_bone_count()
	_hand_idx = _resolve_hand(hand_bone)
	if _hand_idx < 0:
		mode = "none"
		return false
	_hand_rest = _skel.get_bone_pose_rotation(_hand_idx)
	_collect_finger_bones()
	# Only use skinned finger bones when the bind looks sane. A bad Blender
	# post-process (wrong rests / over-weighted verts) turns grips into spaghetti.
	if finger_bone_count >= 10 and finger_bind_rests_sane(_skel, _finger_idxs):
		mode = "bones"
		_configure_hand_euler()
		return true
	# Fall back to proxy even if bad finger bones exist — don't drive them.
	_finger_idxs.clear()
	_finger_rests.clear()
	finger_bone_count = 0
	# Hand-leaf bias only for now — visible proxy capsules read as junk geometry
	# on Mint's mitten hands. Skinned fingers return once bind tooling is solid.
	mode = "proxy"
	_configure_hand_euler()
	return true


func detach() -> void:
	_set_active(false)
	if _proxy_root != null and is_instance_valid(_proxy_root):
		_proxy_root.queue_free()
	_proxy_root = null
	_proxy_joints.clear()
	_finger_idxs.clear()
	_finger_rests.clear()
	_skel = null
	_hand_idx = -1
	finger_bone_count = 0
	bone_count = 0
	mode = "none"


func set_profile(grip_profile: String) -> void:
	profile = grip_profile
	_configure_hand_euler()
	if _active:
		_apply_proxy_pose(1.0)
		_apply_bone_pose(1.0)


func set_grip(on: bool) -> void:
	_set_active(on)


func apply() -> void:
	# Call after AnimationTree so grip wins the hand/fingers this frame.
	if not _active or _skel == null or _hand_idx < 0:
		return
	var add: Quaternion = Quaternion.from_euler(_hand_euler)
	_skel.set_bone_pose_rotation(_hand_idx, _skel.get_bone_pose_rotation(_hand_idx) * add)
	if mode == "bones":
		_apply_bone_pose(1.0)
	elif mode == "proxy" and _proxy_root != null:
		_apply_proxy_pose(1.0)


func status_line() -> String:
	match mode:
		"bones":
			return "fingers: %d bones (%s)" % [finger_bone_count, profile]
		"proxy":
			return "fingers: hand-bias (%s) · skel %d bones" % [profile, bone_count]
		_:
			return "fingers: —"


func _set_active(on: bool) -> void:
	_active = on
	if _proxy_root != null and is_instance_valid(_proxy_root):
		_proxy_root.visible = on
	if not on and _skel != null:
		if _hand_idx >= 0:
			_skel.set_bone_pose_rotation(_hand_idx, _hand_rest)
		for i in _finger_idxs.size():
			_skel.set_bone_pose_rotation(_finger_idxs[i], _finger_rests[i])


func _resolve_hand(preferred: String) -> int:
	var idx: int = _skel.find_bone(preferred)
	if idx >= 0:
		return idx
	var aliases: Array[String] = RIGHT_HAND_ALIASES
	if preferred.to_lower().find("left") >= 0:
		aliases = LEFT_HAND_ALIASES
	for name in aliases:
		idx = _skel.find_bone(name)
		if idx >= 0:
			return idx
	return -1


func _collect_finger_bones() -> void:
	_finger_idxs.clear()
	_finger_rests.clear()
	finger_bone_count = 0
	var hand_name: String = _skel.get_bone_name(_hand_idx)
	var want_right: bool = hand_name.to_lower().find("left") < 0
	for i in list_finger_bone_indices(_skel):
		var nm: String = _skel.get_bone_name(i)
		var lower: String = nm.to_lower()
		var is_left: bool = lower.find("left") >= 0 or lower.ends_with("_l") or lower.find(".l") >= 0
		var is_right: bool = lower.find("right") >= 0 or lower.ends_with("_r") or lower.find(".r") >= 0
		if want_right and is_left and not is_right:
			continue
		if not want_right and is_right and not is_left:
			continue
		# Prefer descendants of the hand bone when parent chain is available.
		if not _is_under_hand(i):
			continue
		_finger_idxs.append(i)
		_finger_rests.append(_skel.get_bone_pose_rotation(i))
	finger_bone_count = _finger_idxs.size()


## Finger-named bones on a skeleton (both hands). Used by grip + bind audits.
static func list_finger_bone_indices(skel: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	if skel == null:
		return out
	for i in skel.get_bone_count():
		if looks_like_finger_bone(skel.get_bone_name(i)):
			out.append(i)
	return out


static func looks_like_finger_bone(nm: String) -> bool:
	for hint in FINGER_HINTS:
		if nm.find(hint) >= 0:
			return true
	return false


## Proximal/metacarpal rests must point mostly along +Y (Mint/Godot hand convention).
## Bad Blender post-process rests are the first half of the spaghetti-mesh failure.
static func finger_bind_rests_sane(skel: Skeleton3D, finger_idxs: Array[int] = []) -> bool:
	if skel == null:
		return false
	var idxs: Array[int] = finger_idxs
	if idxs.is_empty():
		idxs = list_finger_bone_indices(skel)
	if idxs.is_empty():
		return true
	var checked: int = 0
	for idx in idxs:
		var nm: String = skel.get_bone_name(idx)
		if nm.find("Proximal") < 0 and nm.find("Metacarpal") < 0:
			continue
		var origin: Vector3 = skel.get_bone_rest(idx).origin
		var len: float = origin.length()
		if len < 1e-6:
			return false
		# Mostly along +Y in parent space (scale-agnostic). Lateral-dominant
		# rests from bad Blender post-process are the spaghetti trigger.
		if absf(origin.y) / len < 0.55:
			return false
		checked += 1
	return checked >= 4


## Full host audit: rests + skin-weight locality. Empty finger set is OK (Meshy 24-bone).
## Returns { ok: bool, errors: PackedStringArray, finger_bones: int }.
static func audit_finger_host(skel: Skeleton3D, mesh_root: Node) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var fingers: Array[int] = list_finger_bone_indices(skel)
	if fingers.is_empty():
		return {"ok": true, "errors": errors, "finger_bones": 0}
	if not finger_bind_rests_sane(skel, fingers):
		errors.append("finger proximal/metacarpal rests are not +Y-aligned (spaghetti risk)")
	var skin_errs: PackedStringArray = _audit_finger_skin_weights(skel, mesh_root, fingers)
	for e in skin_errs:
		errors.append(e)
	return {"ok": errors.is_empty(), "errors": errors, "finger_bones": fingers.size()}


const _MAX_FINGER_VERTS_PER_HAND: int = 280
const _MAX_FINGER_VERT_HAND_DIST: float = 0.28


static func _audit_finger_skin_weights(
	skel: Skeleton3D, mesh_root: Node, fingers: Array[int]
) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if mesh_root == null:
		return errors
	var finger_names: Dictionary = {}
	for idx in fingers:
		finger_names[skel.get_bone_name(idx)] = idx
	var left_hand: int = skel.find_bone("LeftHand")
	var right_hand: int = skel.find_bone("RightHand")
	var left_origin: Vector3 = (
		skel.get_bone_global_rest(left_hand).origin if left_hand >= 0 else Vector3.ZERO
	)
	var right_origin: Vector3 = (
		skel.get_bone_global_rest(right_hand).origin if right_hand >= 0 else Vector3.ZERO
	)
	var left_weighted: int = 0
	var right_weighted: int = 0
	var far_verts: int = 0
	for node in _walk_nodes(mesh_root):
		if not (node is MeshInstance3D):
			continue
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var skin: Skin = mi.skin
		var bind_is_finger: Array[bool] = []
		var bind_is_left: Array[bool] = []
		bind_is_finger.resize(skin.get_bind_count())
		bind_is_left.resize(skin.get_bind_count())
		var any_finger_bind: bool = false
		for bi in skin.get_bind_count():
			var bname: String = String(skin.get_bind_name(bi))
			var is_f: bool = finger_names.has(bname)
			bind_is_finger[bi] = is_f
			bind_is_left[bi] = bname.to_lower().find("left") >= 0
			if is_f:
				any_finger_bind = true
		if not any_finger_bind:
			continue
		var to_skel: Transform3D = Transform3D.IDENTITY
		if skel.is_ancestor_of(mi):
			to_skel = skel.global_transform.affine_inverse() * mi.global_transform
		else:
			to_skel = mi.transform
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones_a: Variant = arrays[Mesh.ARRAY_BONES]
			var weights_a: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones_a == null or weights_a == null:
				continue
			var bone_ids: PackedInt32Array = bones_a as PackedInt32Array
			var weights: PackedFloat32Array = weights_a as PackedFloat32Array
			if bone_ids.size() < verts.size() * 4 or weights.size() < verts.size() * 4:
				continue
			for vi in verts.size():
				var finger_w: float = 0.0
				var left_w: float = 0.0
				var right_w: float = 0.0
				for k in 4:
					var bi2: int = bone_ids[vi * 4 + k]
					var w: float = weights[vi * 4 + k]
					if bi2 < 0 or bi2 >= bind_is_finger.size() or w < 0.05:
						continue
					if not bind_is_finger[bi2]:
						continue
					finger_w += w
					if bind_is_left[bi2]:
						left_w += w
					else:
						right_w += w
				if finger_w < 0.05:
					continue
				if left_w >= right_w:
					left_weighted += 1
					var p: Vector3 = to_skel * verts[vi]
					if left_hand >= 0 and p.distance_to(left_origin) > _MAX_FINGER_VERT_HAND_DIST:
						far_verts += 1
				else:
					right_weighted += 1
					var p2: Vector3 = to_skel * verts[vi]
					if right_hand >= 0 and p2.distance_to(right_origin) > _MAX_FINGER_VERT_HAND_DIST:
						far_verts += 1
	if left_weighted > _MAX_FINGER_VERTS_PER_HAND:
		errors.append(
			"left finger skin overbind: %d verts (max %d) — arm/body pulled into fingers"
			% [left_weighted, _MAX_FINGER_VERTS_PER_HAND]
		)
	if right_weighted > _MAX_FINGER_VERTS_PER_HAND:
		errors.append(
			"right finger skin overbind: %d verts (max %d) — arm/body pulled into fingers"
			% [right_weighted, _MAX_FINGER_VERTS_PER_HAND]
		)
	# Far verts are the smoking gun of the Idle spaghetti bind (~680/hand).
	if far_verts > 40:
		errors.append(
			"finger-weighted verts far from hands: %d (max 40) — bind not localized"
			% far_verts
		)
	return errors


static func _walk_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n == null:
		return out
	out.append(n)
	for c in n.get_children():
		out.append_array(_walk_nodes(c))
	return out


func _is_under_hand(bone_idx: int) -> bool:
	var cur: int = bone_idx
	var guard: int = 0
	while cur >= 0 and guard < 64:
		if cur == _hand_idx:
			return true
		cur = _skel.get_bone_parent(cur)
		guard += 1
	# Some Mint exports flatten hierarchy — accept side-matched finger names.
	return true


func _looks_like_finger(nm: String) -> bool:
	return looks_like_finger_bone(nm)


func _configure_hand_euler() -> void:
	# Keep subtle — combat clips already pose the hand; this is a polish bias.
	match profile:
		"rifle":
			_hand_euler = Vector3(deg_to_rad(8.0), deg_to_rad(-2.0), deg_to_rad(10.0))
		"tool":
			_hand_euler = Vector3(deg_to_rad(4.0), deg_to_rad(-4.0), deg_to_rad(6.0))
		"baton":
			_hand_euler = Vector3(deg_to_rad(3.0), deg_to_rad(-1.0), deg_to_rad(4.0))
		"open":
			_hand_euler = Vector3(deg_to_rad(-2.0), 0.0, deg_to_rad(-3.0))
		_:
			_hand_euler = Vector3(deg_to_rad(6.0), deg_to_rad(-4.0), deg_to_rad(8.0))


func _apply_bone_pose(amount: float) -> void:
	var curls: Dictionary = _curl_map()
	for i in _finger_idxs.size():
		var idx: int = _finger_idxs[i]
		var nm: String = _skel.get_bone_name(idx).to_lower()
		var curl: float = float(curls.get("default", 0.55))
		if nm.find("thumb") >= 0:
			curl = float(curls.get("thumb", 0.35))
		elif nm.find("index") >= 0:
			curl = float(curls.get("index", 0.5))
		elif nm.find("middle") >= 0:
			curl = float(curls.get("middle", 0.6))
		elif nm.find("ring") >= 0:
			curl = float(curls.get("ring", 0.65))
		elif nm.find("pinky") >= 0 or nm.find("little") >= 0:
			curl = float(curls.get("pinky", 0.7))
		# Distal joints curl a bit more — but keep angles modest.
		if nm.find("distal") >= 0 or nm.ends_with("3") or nm.find("tip") >= 0:
			curl *= 1.1
		elif nm.find("intermediate") >= 0 or nm.ends_with("2"):
			curl *= 1.05
		var axis := Vector3(1.0, 0.0, 0.0)
		if nm.find("thumb") >= 0:
			axis = Vector3(0.35, 0.9, 0.15).normalized()
		var deg: float = clampf(curl * amount * 28.0, 0.0, 35.0)
		var add: Quaternion = Quaternion(axis, deg_to_rad(deg))
		# Compose onto the live animated pose, not a stale rest snapshot.
		_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx) * add)


func _curl_map() -> Dictionary:
	match profile:
		"rifle":
			return {"thumb": 0.45, "index": 0.35, "middle": 0.7, "ring": 0.75, "pinky": 0.8, "default": 0.65}
		"tool":
			return {"thumb": 0.4, "index": 0.55, "middle": 0.6, "ring": 0.55, "pinky": 0.5, "default": 0.55}
		"baton":
			return {"thumb": 0.5, "index": 0.7, "middle": 0.75, "ring": 0.75, "pinky": 0.7, "default": 0.7}
		"open":
			return {"thumb": 0.1, "index": 0.08, "middle": 0.08, "ring": 0.1, "pinky": 0.12, "default": 0.1}
		_:
			return {"thumb": 0.4, "index": 0.45, "middle": 0.7, "ring": 0.75, "pinky": 0.8, "default": 0.65}


func _build_proxy_fingers() -> void:
	# Parent under skeleton so we can follow the live hand pose via BoneAttachment.
	var mount := BoneAttachment3D.new()
	mount.name = "FingerProxyMount"
	mount.bone_name = _skel.get_bone_name(_hand_idx)
	_skel.add_child(mount)
	_proxy_root = mount
	_proxy_joints.clear()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.68, 0.55)
	mat.roughness = 0.72
	mat.metallic = 0.05
	# Slightly translucent so it reads as grip helper, not a second glove.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.92

	var specs: Array = _proxy_finger_specs()
	for spec in specs:
		var base: Node3D = Node3D.new()
		base.name = str(spec["name"])
		base.position = spec["pos"] as Vector3
		base.rotation = spec["rot"] as Vector3
		mount.add_child(base)
		var prev: Node3D = base
		_proxy_joints.append(base)
		for s in 3:
			var joint := Node3D.new()
			joint.name = "%s_%d" % [str(spec["name"]), s]
			prev.add_child(joint)
			joint.position = Vector3(0.0, 0.0, -0.018 if s == 0 else -0.014)
			var seg := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.0045 if bool(spec.get("thumb", false)) else 0.0038
			cap.height = 0.016 if s < 2 else 0.012
			seg.mesh = cap
			seg.material_override = mat
			seg.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			seg.position = Vector3(0.0, 0.0, -cap.height * 0.35)
			joint.add_child(seg)
			_proxy_joints.append(joint)
			prev = joint
	_proxy_root.visible = false


func _proxy_finger_specs() -> Array:
	# Local hand space: +Z out of palm-ish, +X toward thumb for right hand.
	match profile:
		"open":
			return [
				{"name": "Thumb", "pos": Vector3(0.018, 0.01, 0.01), "rot": Vector3(0.2, 0.8, 0.4), "thumb": true},
				{"name": "Index", "pos": Vector3(0.01, 0.02, -0.01), "rot": Vector3(0.1, 0.0, 0.0)},
				{"name": "Middle", "pos": Vector3(0.0, 0.022, -0.012), "rot": Vector3(0.08, 0.0, 0.0)},
				{"name": "Ring", "pos": Vector3(-0.01, 0.02, -0.01), "rot": Vector3(0.1, 0.0, 0.0)},
				{"name": "Pinky", "pos": Vector3(-0.018, 0.016, -0.006), "rot": Vector3(0.12, 0.0, 0.0)},
			]
		_:
			return [
				{"name": "Thumb", "pos": Vector3(0.02, 0.008, 0.012), "rot": Vector3(0.55, 1.1, 0.6), "thumb": true},
				{"name": "Index", "pos": Vector3(0.012, 0.018, -0.004), "rot": Vector3(0.35, 0.05, 0.1)},
				{"name": "Middle", "pos": Vector3(0.002, 0.02, -0.008), "rot": Vector3(0.55, 0.0, 0.05)},
				{"name": "Ring", "pos": Vector3(-0.01, 0.018, -0.006), "rot": Vector3(0.62, -0.05, 0.0)},
				{"name": "Pinky", "pos": Vector3(-0.02, 0.014, -0.002), "rot": Vector3(0.68, -0.1, -0.05)},
			]


func _apply_proxy_pose(amount: float) -> void:
	if _proxy_root == null:
		return
	var curls: Dictionary = _curl_map()
	for child in _proxy_root.get_children():
		if not (child is Node3D):
			continue
		var root_f: Node3D = child as Node3D
		var key: String = "default"
		var n: String = root_f.name.to_lower()
		if n.find("thumb") >= 0:
			key = "thumb"
		elif n.find("index") >= 0:
			key = "index"
		elif n.find("middle") >= 0:
			key = "middle"
		elif n.find("ring") >= 0:
			key = "ring"
		elif n.find("pinky") >= 0:
			key = "pinky"
		var curl: float = float(curls.get(key, curls.get("default", 0.6))) * amount
		_curl_proxy_chain(root_f, curl, key == "thumb")


func _curl_proxy_chain(root_f: Node3D, curl: float, is_thumb: bool) -> void:
	var joint: Node3D = root_f
	var depth: int = 0
	while joint != null and depth < 4:
		var bend: float = deg_to_rad(curl * (28.0 + depth * 12.0))
		if is_thumb:
			joint.rotation = Vector3(bend * 0.6, bend * 0.85, bend * 0.35)
		else:
			joint.rotation = Vector3(bend, 0.0, 0.0)
		var next: Node3D = null
		for c in joint.get_children():
			if c is Node3D and not (c is MeshInstance3D):
				next = c as Node3D
				break
		joint = next
		depth += 1
