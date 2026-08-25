extends Node3D
class_name EquipmentMount

# Renders the player's equipped gear on the character model (#72). Driven by
# Inventory.equipment_changed (#71): on _ready and on every loadout change it
# reconciles the mounted gear against Inventory.equipped_items() — instantiate
# the slot item's `model` GLB, parent it to the right skeleton socket, apply the
# Kenney colormap so it isn't white, and free the previous gear in that slot.
#
# This node is attached UNDER the character wrapper (Player/Character), beside
# the imported Model. It locates the Skeleton3D inside the model and creates one
# BoneAttachment3D per slot bound to the mapped bone. If the skeleton or a bone
# is missing it falls back to a fixed-offset Node3D on the model wrapper (the
# data model carries an `attach_offset` for exactly this case).
#
# Written generically (the model + inventory are injected) so NPCs can adopt it
# later; player.gd wires it for the player only this pass.
#
# Stateless w.r.t. the save system: the loadout is owned by Inventory (which IS
# save-registered); this node only renders it. No autoload, no register needed.

# Canonical slot -> preferred socket name. The data model also carries a per-item
# `socket`; that takes precedence when present. These defaults match the issue's
# head→Head, torso→Spine/Chest, back→Spine, legs→Hips intent. Socket names are
# resolved against the ACTUAL skeleton bones case-insensitively, with the Kenney
# fallback table below, so they need not match the rig literally.
const SLOT_SOCKET_DEFAULT: Dictionary = {
	"head": "Head",
	"torso": "Spine",
	"back": "Spine",
	"legs": "Hips",
}

# Kenney Mini Characters 1 rig exposes 7 bones: root, leg-left, leg-right,
# torso, arm-left, arm-right, head (verified via Step-0 probe). Map each slot
# to the closest real bone so BoneAttachment3D binds instead of falling back.
const SLOT_BONE_FALLBACK: Dictionary = {
	"head": "head",
	"torso": "torso",
	"back": "torso",
	"legs": "root",
}

const COLORMAP_PATH: String = "res://models/characters/Textures/colormap.png"

# The character wrapper this mount renders gear onto (Player/Character). Set via
# setup() before _ready does its first reconcile.
var _model_root: Node3D = null
# The Inventory autoload (injected for testability / headless safety).
var _inventory: Node = null
var _skeleton: Skeleton3D = null
# slot -> the gear instance currently mounted there (ONE registry, no per-slot
# bools — collection-fork policy). Absent key = empty slot.
var _mounted: Dictionary = {}
# slot -> the attach point (BoneAttachment3D or fallback Node3D) we parent gear
# under. Built lazily so a slot only gets a socket when first equipped.
var _sockets: Dictionary = {}
var _wired: bool = false


# Inject the model wrapper to render gear on, and the Inventory node to read the
# loadout from. Call before the node enters the tree (player.gd does). Safe to
# call with nulls in headless paths — reconcile then no-ops.
func setup(model_root: Node3D, inventory: Node) -> void:
	_model_root = model_root
	_inventory = inventory


func _ready() -> void:
	reconcile()


# Resolve the skeleton + wire the Inventory signal once. Called from _ready in
# real play; also called from reconcile() so the mount self-heals when driven
# directly (e.g. headless tests, where no frame has ticked and _ready has not
# fired — see memory: SceneTree-script gotchas).
func _ensure_ready() -> void:
	_resolve_skeleton()
	_connect_inventory()


func _resolve_skeleton() -> void:
	if _skeleton != null and is_instance_valid(_skeleton):
		return
	if _model_root == null:
		return
	_skeleton = _find_skeleton(_model_root)


func _connect_inventory() -> void:
	if _wired:
		return
	if _inventory == null:
		_inventory = _autoload("Inventory")
	if _inventory != null and _inventory.has_signal("equipment_changed"):
		if not _inventory.is_connected("equipment_changed", _on_equipment_changed):
			_inventory.connect("equipment_changed", _on_equipment_changed)
		_wired = true


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	reconcile()


# Reconcile mounted gear against the current loadout. Idempotent: re-running
# never stacks duplicates — each slot is freed and rebuilt only when its item id
# differs from what is already mounted. No-ops gracefully with no model.
func reconcile() -> void:
	if _model_root == null:
		return
	_ensure_ready()
	if _inventory == null:
		_inventory = _autoload("Inventory")
	if _inventory == null or not _inventory.has_method("equipped_items"):
		return
	var loadout: Dictionary = _inventory.call("equipped_items")
	# Drop gear in slots that are now empty or changed.
	for slot in _mounted.keys():
		var want_id: String = String(loadout.get(slot, ""))
		var have_id: String = _mounted_id(slot)
		if want_id != have_id:
			_clear_slot(String(slot))
	# Mount/replace gear for filled slots.
	for slot in loadout.keys():
		var slot_s: String = String(slot)
		var item_id: String = String(loadout[slot])
		if item_id == "":
			continue
		if _mounted_id(slot_s) == item_id:
			continue
		_mount(slot_s, item_id)


# --- internals ---------------------------------------------------------------

func _mounted_id(slot: String) -> String:
	var inst: Variant = _mounted.get(slot, null)
	if inst == null or not is_instance_valid(inst):
		return ""
	return String((inst as Node).get_meta("equip_item_id", ""))


func _clear_slot(slot: String) -> void:
	var inst: Variant = _mounted.get(slot, null)
	_mounted.erase(slot)
	if inst != null and is_instance_valid(inst):
		var n: Node = inst as Node
		# queue_free sync-cap trap: detach first so it leaves the socket
		# immediately, then queue the deferred free.
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


func _mount(slot: String, item_id: String) -> void:
	# Replace whatever is in the slot first (clean swap, no duplicates).
	if _mounted.has(slot):
		_clear_slot(slot)
	var def: Dictionary = _definition(item_id)
	if def.is_empty():
		return
	var socket: Node3D = _socket_for(slot, def)
	if socket == null:
		return
	var gear: Node3D = _build_gear(def)
	if gear == null:
		return
	gear.set_meta("equip_item_id", item_id)
	gear.set_meta("equip_slot", slot)
	socket.add_child(gear)
	# Apply per-item offset AFTER add_child (look_at-style ordering not needed
	# here, but transform reads/writes only make sense once parented).
	gear.transform = Transform3D(Basis.IDENTITY, _offset_of(def))
	_apply_colormap(gear)
	_mounted[slot] = gear


# Resolve (and cache) the attach point for a slot. Prefers a BoneAttachment3D
# bound to the mapped bone; falls back to a fixed-offset Node3D on the model
# wrapper when no skeleton/bone is available (head/back/legs read fine static).
func _socket_for(slot: String, def: Dictionary) -> Node3D:
	if _sockets.has(slot):
		var cached: Variant = _sockets[slot]
		if cached != null and is_instance_valid(cached):
			return cached as Node3D
		_sockets.erase(slot)
	var node: Node3D = null
	if _skeleton != null:
		var bone: int = _resolve_bone(slot, def)
		if bone >= 0:
			var att: BoneAttachment3D = BoneAttachment3D.new()
			att.name = "EquipSocket_%s" % slot
			att.bone_idx = bone
			att.bone_name = _skeleton.get_bone_name(bone)
			_skeleton.add_child(att)
			node = att
	if node == null:
		# Fallback: fixed offset node on the model wrapper.
		var off: Node3D = Node3D.new()
		off.name = "EquipOffset_%s" % slot
		_model_root.add_child(off)
		node = off
	_sockets[slot] = node
	return node


# Resolve a slot to a bone index. Order: per-item `socket`, slot default socket,
# then the Kenney slot->bone fallback. All matched case-insensitively against
# the real bone names. Returns -1 if nothing matches (→ fixed-offset fallback).
func _resolve_bone(slot: String, def: Dictionary) -> int:
	var candidates: Array[String] = []
	var item_socket: String = String(def.get("socket", ""))
	if item_socket != "":
		candidates.append(item_socket)
	if SLOT_SOCKET_DEFAULT.has(slot):
		candidates.append(String(SLOT_SOCKET_DEFAULT[slot]))
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


# Instantiate the gear visual: the item's `model` GLB if it loads, otherwise a
# small procedural placeholder so equipping is still visible/testable when the
# art asset is missing. Either way the returned node is a Node3D ready to parent.
func _build_gear(def: Dictionary) -> Node3D:
	var model_path: String = String(def.get("model", ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				return inst as Node3D
			inst.queue_free()
	return _placeholder_gear(def)


# Procedural fallback gear: a small colored box sized per slot. Tagged so tests
# can tell a placeholder from a real GLB if needed.
func _placeholder_gear(def: Dictionary) -> Node3D:
	var slot: String = String(def.get("slot", ""))
	var box: BoxMesh = BoxMesh.new()
	var size: Vector3 = Vector3(0.22, 0.18, 0.22)
	match slot:
		"head":
			size = Vector3(0.2, 0.18, 0.2)
		"torso":
			size = Vector3(0.34, 0.34, 0.22)
		"back":
			size = Vector3(0.28, 0.34, 0.16)
		"legs":
			size = Vector3(0.3, 0.28, 0.26)
	box.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = box
	mi.name = "GearPlaceholder"
	mi.set_meta("equip_placeholder", true)
	return mi


func _offset_of(def: Dictionary) -> Vector3:
	var raw: Variant = def.get("attach_offset", null)
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func _definition(item_id: String) -> Dictionary:
	if _inventory != null and _inventory.has_method("definition"):
		var d: Variant = _inventory.call("definition", item_id)
		if d is Dictionary:
			return d
	return {}


# Apply the Kenney colormap to every MeshInstance3D in the gear so GLB gear that
# lost its baseColorTexture on import isn't white. Placeholders also get it for a
# consistent palette. No-op if the texture can't load.
func _apply_colormap(root: Node) -> void:
	var tex: Texture2D = load(COLORMAP_PATH) as Texture2D
	if tex == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.78
	mat.metallic = 0.0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
