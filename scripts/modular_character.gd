extends Node3D
class_name ModularCharacter

# WoW-style modular character on the Quaternius Universal Base + Modular
# Outfit packs (all BoneMap-retargeted to %GeneralSkeleton humanoid names).
#
# Key insight from the pack README: outfit parts REPLACE body regions ("only
# the head of the model is required; using the full body will result in
# clipping"). Since the pack ships no split body, we split the FullBody
# skinned mesh ourselves AT LOAD by bone weights into region meshes
# (head/torso/arms/legs/feet) and show only regions whose slot is empty —
# bare base, full outfits, and mixed outfits all render clip-free.
#
#   var c := ModularCharacter.create("Male")
#   add_child(c)
#   c.set_slot("Body", "Male_Ranger_Body")   # tunic on
#   c.set_slot("Legs", "Male_Peasant_Legs")  # mixed outfit
#   c.set_slot("Hair", "Hair_Buzzed")
#   c.play_clip("walk"); c.set_rifle(true, true)

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const BASE_DIR: String = "res://models/quaternius/base"
const PARTS_DIR: String = "res://models/quaternius/parts"
const HAIR_DIR: String = "res://models/quaternius/hair"
const BODY_LIB: String = "res://models/vrm/anim/crew_body.res"
# Real gun props (Quaternius Sci-Fi Essentials) — replace the procedural kit.
const RIFLE_GLTF: String = "res://models/quaternius/guns/Gun_Rifle.gltf"
const PISTOL_GLTF: String = "res://models/quaternius/guns/Gun_Pistol.gltf"

const SLOTS: Array[String] = ["Body", "Arms", "Legs", "Feet", "Head", "Acc", "Hair"]

# Which split-body regions an occupied slot hides.
const SLOT_COVERS: Dictionary = {
	"Body": ["torso"], "Arms": ["arms"], "Legs": ["legs"], "Feet": ["feet"],
	"Head": [], "Acc": [], "Hair": [],
}

# Region -> humanoid bones whose weights claim a triangle.
const REGION_BONES: Dictionary = {
	"head": ["Head", "Neck"],
	"torso": ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"],
	"arms": ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
		"RightLowerArm", "RightHand"],
	"legs": ["Hips", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"],
	"feet": ["LeftFoot", "LeftToes", "RightFoot", "RightToes"],
}

# Clothing inflation: garment vertices pushed along their normals so gear
# sits proud of the (muscular) base body instead of skin-tight — kills
# poke-through at region boundaries and animation extremes.
const CLOTH_INFLATE: float = 0.008

# gender -> {region -> ArrayMesh} (split once, shared by every instance).
static var _region_cache: Dictionary = {}
# part stem -> inflated ArrayMesh (built once, shared).
static var _inflated_cache: Dictionary = {}

var gender: String = "Male"

var _base: Node3D = null
var _skel: Skeleton3D = null
var _anim: AnimationPlayer = null
var _region_meshes: Dictionary = {}   # region -> MeshInstance3D
var _equipped: Dictionary = {}        # slot -> {"stem": String, "nodes": Array}
# Equipment calls made before _ready (spawners often dress before add_child);
# replayed once the skeleton exists.
var _pending: Array = []


static func create(body_gender: String = "Male") -> Node3D:
	var c: Node3D = new()
	c.set("gender", body_gender)
	c.name = "Modular_" + body_gender
	return c


func _ready() -> void:
	_base = (load("%s/Superhero_%s_FullBody.gltf" % [BASE_DIR, gender]) as PackedScene).instantiate()
	add_child(_base)
	_skel = _base.get_node_or_null("%GeneralSkeleton")
	if _skel == null:
		_skel = _find_skeleton(_base)
	_split_base_body()
	_anim = AnimationPlayer.new()
	_base.add_child(_anim)
	_anim.root_node = _anim.get_path_to(_base)
	if ResourceLoader.exists(BODY_LIB):
		_anim.add_animation_library("body", load(BODY_LIB))
	play_clip("idle")
	# Replay equipment configured before we entered the tree.
	var queued: Array = _pending
	_pending = []
	for call_args in queued:
		callv(call_args[0], call_args[1])


# ----------------------------- body splitting --------------------------------

# Replace the FullBody mesh with five region meshes so equipment can hide the
# body underneath (the pack's intended anti-clipping model).
func _split_base_body() -> void:
	var body_mi: MeshInstance3D = null
	for mi in _skinned_meshes(_base):
		# Pack naming is inconsistent: SuperHero_Male vs Superhero_Female.
		if String(mi.name).to_lower().begins_with("superhero"):
			body_mi = mi
	if body_mi == null:
		return
	var regions: Dictionary = _split_regions(body_mi)
	for region in regions:
		var rmi: MeshInstance3D = MeshInstance3D.new()
		rmi.name = "BaseRegion_" + region
		rmi.mesh = regions[region]
		rmi.skin = body_mi.skin
		_skel.add_child(rmi)
		_region_meshes[region] = rmi
	body_mi.visible = false


func _split_regions(body_mi: MeshInstance3D) -> Dictionary:
	var key: String = gender
	if _region_cache.has(key):
		return _region_cache[key]
	var mesh: ArrayMesh = body_mi.mesh as ArrayMesh
	var skin: Skin = body_mi.skin
	# Skin bind index -> region name.
	var bind_region: Dictionary = {}
	for i in range(skin.get_bind_count()):
		var bone: String = String(skin.get_bind_name(i))
		for region in REGION_BONES:
			if (REGION_BONES[region] as Array).has(bone) \
					or _finger_of(bone, region):
				bind_region[i] = region
	var out: Dictionary = {}
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var influences: int = bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# Region index buffers.
		var region_indices: Dictionary = {}
		for t in range(0, indices.size(), 3):
			var votes: Dictionary = {}
			for k in range(3):
				var v: int = indices[t + k]
				for j in range(influences):
					var w: float = weights[v * influences + j]
					if w <= 0.0:
						continue
					var region: String = String(bind_region.get(bones[v * influences + j], "torso"))
					votes[region] = float(votes.get(region, 0.0)) + w
			var best: String = "torso"
			var best_w: float = -1.0
			for region in votes:
				if float(votes[region]) > best_w:
					best_w = votes[region]
					best = region
			if not region_indices.has(best):
				region_indices[best] = PackedInt32Array()
			var buf: PackedInt32Array = region_indices[best]
			buf.append(indices[t])
			buf.append(indices[t + 1])
			buf.append(indices[t + 2])
			region_indices[best] = buf
		for region in region_indices:
			var rarrays: Array = arrays.duplicate()
			rarrays[Mesh.ARRAY_INDEX] = region_indices[region]
			if not out.has(region):
				out[region] = ArrayMesh.new()
			var am: ArrayMesh = out[region]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rarrays)
			am.surface_set_material(am.get_surface_count() - 1, mesh.surface_get_material(s))
	_region_cache[key] = out
	return out


func _finger_of(bone: String, region: String) -> bool:
	if region != "arms":
		return false
	for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		if bone.contains(finger):
			return true
	return false


# ------------------------------- equipment -----------------------------------

# Equip a part into a slot ("" or "(none)" clears it). Returns true on change.
func set_slot(slot: String, stem: String) -> bool:
	if not SLOTS.has(slot):
		return false
	if _skel == null:
		_pending.append(["set_slot", [slot, stem]])
		return true
	# Clear current.
	if _equipped.has(slot):
		for n in _equipped[slot]["nodes"]:
			if is_instance_valid(n):
				n.queue_free()
		_equipped.erase(slot)
	if stem != "" and stem != "(none)":
		var dir: String = HAIR_DIR if slot == "Hair" else PARTS_DIR
		var packed: PackedScene = load("%s/%s.gltf" % [dir, stem])
		if packed == null:
			_refresh_regions()
			return false
		var part: Node = packed.instantiate()
		var nodes: Array = []
		for mi in _skinned_meshes(part):
			var worn: MeshInstance3D = mi.duplicate() as MeshInstance3D
			worn.name = "Part_%s_%s" % [slot, worn.name]
			if slot != "Hair":
				worn.mesh = _inflated("%s|%s" % [stem, worn.name], worn.mesh)
			_skel.add_child(worn)
			nodes.append(worn)
		part.free()
		_equipped[slot] = {"stem": stem, "nodes": nodes}
	_refresh_regions()
	return true


func equipped(slot: String) -> String:
	return String(_equipped.get(slot, {}).get("stem", ""))


# Hide base regions covered by occupied slots; bare regions show base skin.
func _refresh_regions() -> void:
	var hidden: Array = []
	for slot in _equipped:
		hidden.append_array(SLOT_COVERS.get(slot, []))
	for region in _region_meshes:
		(_region_meshes[region] as MeshInstance3D).visible = not hidden.has(region)


# Push every vertex along its normal so the garment sits slightly off the
# body (skinning arrays untouched — only ARRAY_VERTEX changes).
static func _inflated(cache_key: String, mesh: Mesh) -> ArrayMesh:
	if _inflated_cache.has(cache_key):
		return _inflated_cache[cache_key]
	var out: ArrayMesh = ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if normals.size() == verts.size():
			for i in range(verts.size()):
				verts[i] += normals[i] * CLOTH_INFLATE
			arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	_inflated_cache[cache_key] = out
	return out


# ------------------------------ rigid gear -----------------------------------

# Rifle in the right hand (aimed) or slung via Chest mount (stowed).
func set_rifle(carried: bool, aimed: bool = false) -> void:
	if _skel == null:
		_pending.append(["set_rifle", [carried, aimed]])
		return
	_clear_mounts(["RifleHand", "RifleBack"])
	if not carried:
		return
	var mount: BoneAttachment3D = _mount("RifleHand" if aimed else "RifleBack",
		"RightHand" if aimed else "Chest")
	var rifle: Node3D = _gun(RIFLE_GLTF, "Rifle")
	if aimed:
		# Hand-bone axes are rig-specific; tuned via rifle_grip_tune capture
		# (symptom ladder: backwards = flip Rx; sideways = add Ry90;
		# upside-down = add Rz180). Don't reason about axes — render the grid.
		rifle.position = Vector3(0.0, 0.08, 0.07)
		rifle.rotation = Vector3(-1.57, 1.57, 3.14)
	else:
		# Slung UP the back (reference-matched via tests/capture/
		# sling_tune_grid.gd, Karpathy rounds 1-3): muzzle just above the
		# shoulder, stock at the hip, slight diagonal, tucked tight. KEY
		# FACT from round 1: the rifle model's long axis is X — Rx spins it
		# about its own barrel; vertical carry comes from Rz ≈ -90°.
		rifle.position = Vector3(-0.04, -0.12, -0.20)
		rifle.rotation = Vector3(0.15, 0.0, -1.45)
	mount.add_child(rifle)


# Sidearm: right hand (aimed) or holstered on the right hip. Same canonical
# gear frame as the rifle, so the hand transform family matches.
func set_sidearm(carried: bool, aimed: bool = false) -> void:
	if _skel == null:
		_pending.append(["set_sidearm", [carried, aimed]])
		return
	_clear_mounts(["SidearmHand", "SidearmHip"])
	if not carried:
		return
	var mount: BoneAttachment3D = _mount("SidearmHand" if aimed else "SidearmHip",
		"RightHand" if aimed else "Hips")
	var gun: Node3D = _gun(PISTOL_GLTF, "Sidearm")
	if aimed:
		# Picked from tests/capture/pistol_grip_grid.gd — the pistol model's
		# frame shares NOTHING with the rifle's (rifle values pointed it
		# right; a single-axis "fix" pointed it up). Candidate #6 runs the
		# barrel flat down the aim line.
		gun.position = Vector3(0.0, 0.06, 0.02)
		gun.rotation = Vector3(0.0, -1.57, 0.0)
	else:
		gun.position = Vector3(0.19, 0.02, 0.02)
		gun.rotation = Vector3(-1.57, 0.0, 0.0)   # barrel down along the thigh
	mount.add_child(gun)


# Combat helmet on the Head bone (standoff/military kit).
func set_helmet(worn: bool) -> void:
	if _skel == null:
		_pending.append(["set_helmet", [worn]])
		return
	_clear_mounts(["HelmetMount"])
	if not worn:
		return
	var mount: BoneAttachment3D = _mount("HelmetMount", "Head")
	var helmet: Node3D = FactoryRef.build_helmet()
	helmet.name = "Helmet"
	helmet.scale = Vector3.ONE * 0.42
	helmet.position = Vector3(0.0, 0.11, 0.02)
	mount.add_child(helmet)


# Instantiate a gun prop scene under a named pivot (so mount code can address
# it as "Rifle"/"Sidearm" regardless of the prop's internal node names).
func _gun(path: String, gun_name: String) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = gun_name
	var packed: PackedScene = load(path)
	if packed != null:
		pivot.add_child(packed.instantiate())
	return pivot


func _mount(mount_name: String, bone: String) -> BoneAttachment3D:
	var mount: BoneAttachment3D = BoneAttachment3D.new()
	mount.name = mount_name
	_skel.add_child(mount)
	mount.bone_name = bone
	return mount


func _clear_mounts(names: Array) -> void:
	for mount_name in names:
		var old: Node = _skel.get_node_or_null(mount_name)
		if old != null:
			old.name = mount_name + "_retired"
			old.queue_free()


# Color the equipped hairstyle (hair gltfs arrive with unbound/white
# materials — also how crew get distinct hair colors).
func set_hair_color(color: Color) -> void:
	if _skel == null:
		_pending.append(["set_hair_color", [color]])
		return
	for n in _equipped.get("Hair", {}).get("nodes", []):
		if not (is_instance_valid(n) and n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		for s in range(mi.mesh.get_surface_count()):
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.roughness = 0.75
			mi.set_surface_override_material(s, mat)


# Swap the base body's albedo texture to a pack-shipped skin variant
# ("Dark" — e.g. T_Superhero_Male_Dark.png). Applies to all split regions.
func set_skin_variant(variant: String) -> void:
	if _skel == null:
		_pending.append(["set_skin_variant", [variant]])
		return
	var candidates: Array = [
		"%s/T_Superhero_%s_%s_BaseColor.png" % [BASE_DIR, gender, variant],
		"%s/T_Superhero_%s_%s.png" % [BASE_DIR, gender, variant],
	]
	var tex: Texture2D = null
	for path in candidates:
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	if tex == null:
		push_warning("set_skin_variant: no texture for '%s' (%s)" % [variant, candidates])
		return
	for region in _region_meshes:
		var mi: MeshInstance3D = _region_meshes[region]
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var mat: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
				mat.albedo_texture = tex
				mi.set_surface_override_material(s, mat)


# Multiply a tint over every equipped garment's albedo (ship duty blacks vs
# natural "field" colors) and optionally the base skin texture variant.
func tint_clothing(tint: Color) -> void:
	if _skel == null:
		_pending.append(["tint_clothing", [tint]])
		return
	for slot in _equipped:
		if slot == "Hair":
			continue
		_tint_slot_nodes(String(slot), tint)


# Tint ONE slot's garment (per-character looks: Eli's red tee over civvies).
func tint_slot(slot: String, tint: Color) -> void:
	if _skel == null:
		_pending.append(["tint_slot", [slot, tint]])
		return
	_tint_slot_nodes(slot, tint)


func _tint_slot_nodes(slot: String, tint: Color) -> void:
	for n in _equipped.get(slot, {}).get("nodes", []):
		if not (is_instance_valid(n) and n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var mat: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
				mat.albedo_color = tint
				mi.set_surface_override_material(s, mat)


# ------------------------------- animation -----------------------------------

func play_clip(clip: String, blend: float = 0.3) -> void:
	if _anim == null:
		# Pre-tree (spawners pose before add_child) — replayed in _ready, after
		# the default idle, so the requested clip wins.
		_pending.append(["play_clip", [clip, blend]])
		return
	var full: String = "body/" + clip
	if _anim.has_animation(full):
		_anim.play(full, blend)


# Freeze the current pose (tableau bodies — the unconscious shouldn't
# breathe-sway). Pre-tree calls queue like equipment does.
func freeze_pose() -> void:
	if _anim == null:
		_pending.append(["freeze_pose", []])
		return
	_anim.pause()


# Play a clip LOOPED even if the library authored it one-shot. The clip is
# duplicated into an instance-local "extra" library with looping enabled, so
# the shared crew_body resource is never mutated.
func play_clip_looped(clip: String) -> void:
	if _anim == null:
		_pending.append(["play_clip_looped", [clip]])
		return
	var full: String = "extra/" + clip
	if not _anim.has_animation(full):
		if not _anim.has_animation("body/" + clip):
			return
		var anim: Animation = _anim.get_animation("body/" + clip).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		if not _anim.has_animation_library("extra"):
			_anim.add_animation_library("extra", AnimationLibrary.new())
		_anim.get_animation_library("extra").add_animation(clip, anim)
	_anim.play(full, 0.3)


# Hold a clip frozen at `fraction` of its length — a posing tool for working
# NPCs. The paused AnimationPlayer stops re-applying poses, so callers may
# adjust bones afterward.
func freeze_clip_at(clip: String, fraction: float) -> void:
	if _anim == null:
		_pending.append(["freeze_clip_at", [clip, fraction]])
		return
	var full: String = "body/" + clip
	if not _anim.has_animation(full):
		return
	var length: float = _anim.get_animation(full).length
	_anim.play(full)
	_anim.seek(clampf(fraction, 0.0, 1.0) * length, true)
	_anim.pause()


# Console-work pose (Rush at his station): the pickup reach frozen mid-bend
# — slightly hunched, head down — with the LEFT arm mirrored from the right
# so BOTH hands sit forward over the controls. No two-handed work clip
# exists in the library; mirroring the frozen pose builds one. Local-pose
# mirror across the sagittal plane = negate the quaternion's y/z.
func pose_console_work() -> void:
	if _skel == null:
		_pending.append(["pose_console_work", []])
		return
	freeze_clip_at("pickup", 0.40)
	for pair in [["RightUpperArm", "LeftUpperArm"], ["RightLowerArm", "LeftLowerArm"],
			["RightHand", "LeftHand"]]:
		var src: int = _skel.find_bone(String(pair[0]))
		var dst: int = _skel.find_bone(String(pair[1]))
		if src < 0 or dst < 0:
			continue
		var q: Quaternion = _skel.get_bone_pose_rotation(src)
		_skel.set_bone_pose_rotation(dst, Quaternion(q.x, -q.y, -q.z, q.w))
	# Deepen the lean — the raw freeze reads "standing sad" from the front.
	for lean in [["Spine", 0.22], ["Chest", 0.16]]:
		var idx: int = _skel.find_bone(String(lean[0]))
		if idx < 0:
			continue
		var add: Quaternion = Quaternion(Vector3.RIGHT, float(lean[1]))
		_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx) * add)


func clip_names() -> PackedStringArray:
	if _anim != null and _anim.has_animation_library("body"):
		return _anim.get_animation_library("body").get_animation_list()
	return PackedStringArray()


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation("body/" + clip)


# The internal AnimationPlayer — for callers that need speed_scale / pause
# (player locomotion pitch, tableau "unconscious" pose freeze).
func anim_player() -> AnimationPlayer:
	return _anim


func skeleton() -> Skeleton3D:
	return _skel


# Available parts for a slot/gender: scans the import folders.
static func parts_for_slot(slot: String, body_gender: String) -> Array:
	var out: Array = []
	var dir_path: String = HAIR_DIR if slot == "Hair" else PARTS_DIR
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".gltf"):
			continue
		var stem: String = f.get_basename()
		if slot == "Hair":
			out.append(stem)
			continue
		var bits: PackedStringArray = stem.split("_")
		if bits.size() >= 3 and bits[0] == body_gender and bits[2] == slot:
			out.append(stem)
	return out


# ------------------------------- helpers -------------------------------------

func _skinned_meshes(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
