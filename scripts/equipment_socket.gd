extends Node3D
class_name EquipmentSocket

# BoneAttachment3D-based sockets for mounting gear to character bones (#72).
#
# Creates one BoneAttachment3D per equipment slot, bound to the mapped skeleton
# bone. When the skeleton is unavailable (headless, static mesh), falls back to
# a fixed-offset Node3D on the model wrapper so gear is still testable.
#
# Used by EquipmentSystem to physically attach 3D gear models to the character.
# The socket layer is decoupled from the equipment logic: it only knows how to
# find/create attach points and parent gear nodes under them.

signal socket_attached(slot: String, gear: Node3D)
signal socket_detached(slot: String)

# Slot → preferred bone name. Resolved case-insensitively against the actual
# skeleton. Falls back through SLOT_BONE_FALLBACK if the preferred bone is absent.
const SLOT_BONE_PREFERRED: Dictionary = {
	"helmet": "Head",
	"vest": "Spine",
	"backpack": "Spine",
	"pants": "Hips",
	"boots": "Hips",
}

# Kenney Mini Characters rig fallbacks (7 bones: root, leg-left, leg-right,
# torso, arm-left, arm-right, head). Map each slot to the closest real bone.
const SLOT_BONE_FALLBACK: Dictionary = {
	"helmet": "head",
	"vest": "torso",
	"backpack": "torso",
	"pants": "root",
	"boots": "root",
}

const COLORMAP_PATH: String = "res://models/characters/Textures/colormap.png"

var _model_root: Node3D = null
var _skeleton: Skeleton3D = null
# slot → attach point (BoneAttachment3D or fallback Node3D)
var _sockets: Dictionary = {}
# slot → currently mounted gear Node3D
var _mounted: Dictionary = {}


func setup(model_root: Node3D) -> void:
	_model_root = model_root
	_resolve_skeleton()


func _resolve_skeleton() -> void:
	if _skeleton != null and is_instance_valid(_skeleton):
		return
	if _model_root == null:
		return
	_skeleton = _find_skeleton(_model_root)


# Returns the attach point for `slot`, creating it lazily if needed.
func socket_for(slot: String) -> Node3D:
	if _sockets.has(slot):
		var cached: Variant = _sockets[slot]
		if cached != null and is_instance_valid(cached):
			return cached as Node3D
		_sockets.erase(slot)
	_resolve_skeleton()
	var node: Node3D = null
	if _skeleton != null:
		var bone_idx: int = _resolve_bone(slot)
		if bone_idx >= 0:
			var att: BoneAttachment3D = BoneAttachment3D.new()
			att.name = "EquipSocket_%s" % slot
			att.bone_idx = bone_idx
			att.bone_name = _skeleton.get_bone_name(bone_idx)
			_skeleton.add_child(att)
			node = att
	if node == null:
		# Fallback: fixed-offset Node3D on the model wrapper.
		var off: Node3D = Node3D.new()
		off.name = "EquipOffset_%s" % slot
		if _model_root != null:
			_model_root.add_child(off)
		node = off
	_sockets[slot] = node
	return node


# Mount `gear` (a Node3D) into `slot`. Frees any existing gear in that slot first.
func attach(slot: String, gear: Node3D) -> void:
	if gear == null:
		return
	detach(slot)
	var socket: Node3D = socket_for(slot)
	if socket == null:
		return
	gear.set_meta("equip_slot", slot)
	socket.add_child(gear)
	_mounted[slot] = gear
	socket_attached.emit(slot, gear)


# Remove and free the gear in `slot`. No-op if the slot is empty.
func detach(slot: String) -> void:
	var gear: Variant = _mounted.get(slot, null)
	_mounted.erase(slot)
	if gear != null and is_instance_valid(gear):
		var n: Node = gear as Node
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	socket_detached.emit(slot)


# Gear Node3D currently in `slot`, or null.
func gear_in(slot: String) -> Node3D:
	var v: Variant = _mounted.get(slot, null)
	if v == null or not is_instance_valid(v):
		return null
	return v as Node3D


# True if `slot` has gear mounted.
func has_gear(slot: String) -> bool:
	return _mounted.has(slot) and is_instance_valid(_mounted[slot])


# Number of currently mounted gear pieces.
func mounted_count() -> int:
	var n: int = 0
	for slot in _mounted:
		if is_instance_valid(_mounted[slot]):
			n += 1
	return n


# Resolve a slot to a bone index via preferred → fallback bone names.
func _resolve_bone(slot: String) -> int:
	var candidates: Array[String] = []
	if SLOT_BONE_PREFERRED.has(slot):
		candidates.append(String(SLOT_BONE_PREFERRED[slot]))
	if SLOT_BONE_FALLBACK.has(slot):
		candidates.append(String(SLOT_BONE_FALLBACK[slot]))
	for cand in candidates:
		var idx: int = _find_bone_ci(cand)
		if idx >= 0:
			return idx
	return -1


func _find_bone_ci(bone_name: String) -> int:
	if _skeleton == null or bone_name == "":
		return -1
	var lower: String = bone_name.to_lower()
	for i in range(_skeleton.get_bone_count()):
		if _skeleton.get_bone_name(i).to_lower() == lower:
			return i
	return -1


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null