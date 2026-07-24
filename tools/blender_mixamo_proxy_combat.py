"""Build a local Mixamo-rigged combat pack WITHOUT Adobe Swat downloads.

Uses:
  - Mixamo skeleton from models/vrm/anim_src/*.fbx (already in-repo, mixamorig)
  - Procedural sci-fi mannequin mesh (bone-parented boxes — Y-Bot-like stand-in)
  - Procedural M4 proxy (same span rules as blender_mixamo_rifle_combat.py)
  - Clip map from available rifle/loco FBXs → showcase clip names

Output (gitignored ToS-adjacent / local rebuild):
  models/mixamo_openbot/Swat_rifle_combat.glb

When real Mixamo Swat + Shooter Pack FBXs land in incoming/, prefer
tools/blender_mixamo_rifle_combat.py instead.
"""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
ANIM_DIR = ROOT / "models/vrm/anim_src"
OUT_DIR = ROOT / "models/mixamo_openbot"
GLB_OUT = OUT_DIR / "Swat_rifle_combat.glb"
BLEND_OUT = OUT_DIR / "Swat_rifle_combat.blend"
PROXY_GLB = OUT_DIR / "mixamo_virtual_rifle.glb"

MIXAMO_HAND_SPAN = 0.322

# Showcase clip names → best-available in-repo Mixamo FBX (without skin).
CLIPS: dict[str, Path] = {
	"Unarmed_Idle": ANIM_DIR / "standingidle.fbx",
	"Breathing_Idle": ANIM_DIR / "happy-idle.fbx",
	"Walking": ANIM_DIR / "walking.fbx",
	"Running": ANIM_DIR / "runningfast.fbx",
	"Strafe": ANIM_DIR / "runningfast.fbx",
	"Strafe_Alt": ANIM_DIR / "walking.fbx",
	"Rifle_Idle": ANIM_DIR / "stoprunningtoaimingrifleidle.fbx",
	"Firing_Rifle": ANIM_DIR / "firingwhilewalkingwithrifle.fbx",
	"Shoot_Rifle": ANIM_DIR / "firingwhilewalkingwithrifle.fbx",
	"Walk_With_Rifle": ANIM_DIR / "riflewalkforward.fbx",
	"Rifle_Start_Run": ANIM_DIR / "runningwithrifledown.fbx",
	"Fire_Rifle_Crouched": ANIM_DIR / "firingwhilewalkingwithrifle.fbx",
	"Rifle_Kneeling_Aim": ANIM_DIR / "stoprunningtoaimingrifleidle.fbx",
	"Rifle_Stand_To_Kneel": ANIM_DIR / "standingtoreadyposegrabbingriflefromtheback.fbx",
	"Rifle_Crouched_Idle_Aim": ANIM_DIR / "stoprunningtoaimingrifleidle.fbx",
	# Interact stub (mining/repair backlog) — cheap pose until Digging FBX lands.
	"Interact_Stub": ANIM_DIR / "pointingwitharmbent.fbx",
}

HIP_STRIP_CLIPS = {
	"Walk_With_Rifle",
	"Rifle_Start_Run",
	"Walking",
	"Running",
	"Shoot_Rifle",
	"Strafe",
	"Strafe_Alt",
	"Fire_Rifle_Crouched",
	"Firing_Rifle",
	"Rifle_Crouched_Idle_Aim",
	"Rifle_Kneeling_Aim",
	"Rifle_Stand_To_Kneel",
	"Rifle_Idle",
}

GRIP_LOCAL = Vector((0.0, 0.0, -0.035))
SUPPORT_LOCAL = Vector((0.0, MIXAMO_HAND_SPAN, -0.020))
MUZZLE_LOCAL = Vector((0.0, 0.55, 0.03))
STOCK_LOCAL = Vector((0.0, -0.28, 0.04))

# Bone → (half-extents XYZ, local center offset) for mannequin boxes.
# Units are Mixamo centimetre-scale before host.scale (typically 0.01).
MANNEQUIN_PARTS: dict[str, tuple[Vector, Vector]] = {
	"mixamorig:Hips": (Vector((18, 12, 14)), Vector((0, 0, 2))),
	"mixamorig:Spine": (Vector((16, 10, 12)), Vector((0, 0, 4))),
	"mixamorig:Spine1": (Vector((18, 11, 14)), Vector((0, 0, 5))),
	"mixamorig:Spine2": (Vector((20, 12, 16)), Vector((0, 0, 6))),
	"mixamorig:Neck": (Vector((6, 6, 8)), Vector((0, 0, 4))),
	"mixamorig:Head": (Vector((12, 14, 14)), Vector((0, 0, 8))),
	"mixamorig:LeftShoulder": (Vector((8, 6, 6)), Vector((4, 0, 0))),
	"mixamorig:RightShoulder": (Vector((8, 6, 6)), Vector((-4, 0, 0))),
	"mixamorig:LeftArm": (Vector((7, 7, 18)), Vector((0, 0, 8))),
	"mixamorig:RightArm": (Vector((7, 7, 18)), Vector((0, 0, 8))),
	"mixamorig:LeftForeArm": (Vector((6, 6, 16)), Vector((0, 0, 8))),
	"mixamorig:RightForeArm": (Vector((6, 6, 16)), Vector((0, 0, 8))),
	"mixamorig:LeftHand": (Vector((5, 8, 10)), Vector((0, 0, 4))),
	"mixamorig:RightHand": (Vector((5, 8, 10)), Vector((0, 0, 4))),
	"mixamorig:LeftUpLeg": (Vector((9, 9, 22)), Vector((0, 0, 10))),
	"mixamorig:RightUpLeg": (Vector((9, 9, 22)), Vector((0, 0, 10))),
	"mixamorig:LeftLeg": (Vector((7, 7, 22)), Vector((0, 0, 10))),
	"mixamorig:RightLeg": (Vector((7, 7, 22)), Vector((0, 0, 10))),
	"mixamorig:LeftFoot": (Vector((8, 14, 5)), Vector((0, 4, 0))),
	"mixamorig:RightFoot": (Vector((8, 14, 5)), Vector((0, 4, 0))),
}


def _purge() -> None:
	if bpy.context.object and bpy.context.object.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	for obj in list(bpy.data.objects):
		if obj.type not in {"CAMERA", "LIGHT"}:
			bpy.data.objects.remove(obj, do_unlink=True)
	for act in list(bpy.data.actions):
		bpy.data.actions.remove(act)
	for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
		for item in list(block):
			if item.users == 0:
				block.remove(item)


def _iter_action_fcurves(action: bpy.types.Action):
	"""Yield (container, fcurve) for Blender 4.0 fcurves and 4.4+ layered actions."""
	if hasattr(action, "fcurves") and action.fcurves is not None:
		for fc in list(action.fcurves):
			yield action.fcurves, fc
		return
	if not hasattr(action, "layers"):
		return
	for layer in action.layers:
		for strip in layer.strips:
			for cb in strip.channelbags:
				for fc in list(cb.fcurves):
					yield cb.fcurves, fc


def _strip_scale_fcurves(action: bpy.types.Action) -> int:
	removed = 0
	for container, fc in _iter_action_fcurves(action):
		if fc.data_path.endswith(".scale"):
			container.remove(fc)
			removed += 1
	return removed


def _strip_hip_location(action: bpy.types.Action) -> int:
	removed = 0
	for container, fc in _iter_action_fcurves(action):
		dp = fc.data_path
		if "Hips" in dp and "location" in dp:
			container.remove(fc)
			removed += 1
	return removed


def _disable_inherit_scale(arm: bpy.types.Object) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for b in arm.data.edit_bones:
		if hasattr(b, "inherit_scale"):
			b.inherit_scale = "NONE"
	bpy.ops.object.mode_set(mode="POSE")


def _bind_action(arm: bpy.types.Object, action: bpy.types.Action) -> None:
	if arm.animation_data is None:
		arm.animation_data_create()
	ad = arm.animation_data
	ad.action = action
	if hasattr(ad, "action_slot") and action.slots:
		ad.action_slot = action.slots[0]


def _world_bone(arm: bpy.types.Object, name: str) -> Matrix:
	return arm.matrix_world @ arm.pose.bones[name].matrix


def _palm(arm: bpy.types.Object, side: str) -> Vector:
	wrist = _world_bone(arm, f"mixamorig:{side}Hand").translation
	tips: list[Vector] = []
	for finger in ("Thumb4", "Index4", "Middle4"):
		n = f"mixamorig:{side}Hand{finger}"
		if n in arm.pose.bones:
			tips.append(_world_bone(arm, n).translation)
	if not tips:
		return wrist
	return wrist.lerp(sum(tips, Vector()) / len(tips), 0.65)


def _foot_z_min(arm: bpy.types.Object) -> float:
	zmin = 1e9
	for name in arm.pose.bones.keys():
		if "Toe" in name or name.endswith("Foot"):
			zmin = min(zmin, _world_bone(arm, name).translation.z)
	return zmin


def _ground_across_clips(arm: bpy.types.Object, actions: dict[str, bpy.types.Action]) -> None:
	worst = 0.0
	for name, act in actions.items():
		_bind_action(arm, act)
		mid = int((act.frame_range[0] + act.frame_range[1]) // 2)
		bpy.context.scene.frame_set(mid)
		bpy.context.view_layer.update()
		z = _foot_z_min(arm)
		worst = min(worst, z)
		print(f"  footZ {name:28} {z:.4f}")
	arm.location.z -= worst - 0.01
	bpy.context.view_layer.update()
	print("grounded; worst was", round(worst, 4), "host.z", round(arm.location.z, 4))


def _import_clip_action(path: Path, name: str) -> bpy.types.Action | None:
	if not path.exists():
		print("SKIP missing", path)
		return None
	before_arms = {o.name for o in bpy.data.objects if o.type == "ARMATURE"}
	before_actions = {a.name for a in bpy.data.actions}
	bpy.ops.import_scene.fbx(filepath=str(path), automatic_bone_orientation=True)
	for o in list(bpy.data.objects):
		if o.type == "ARMATURE" and o.name not in before_arms:
			bpy.data.objects.remove(o, do_unlink=True)
	new_actions = [a for a in bpy.data.actions if a.name not in before_actions]
	if not new_actions:
		print("SKIP no action", path.name)
		return None
	act = next((a for a in new_actions if "Layer0" in a.name), None)
	if act is None:
		act = max(new_actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
	for a in new_actions:
		if a != act:
			bpy.data.actions.remove(a)
	# Duplicate when the same FBX backs multiple clip names.
	if act.name in bpy.data.actions and act.name != name and name in {a.name for a in bpy.data.actions}:
		pass
	dup = act.copy()
	dup.name = name
	if act.name != name:
		# Keep original only if still referenced elsewhere; remove temp import name.
		try:
			bpy.data.actions.remove(act)
		except RuntimeError:
			pass
	act = dup
	_strip_scale_fcurves(act)
	if name in HIP_STRIP_CLIPS:
		print("stripped hip loc", name, _strip_hip_location(act))
	print("CLIP", name, "frames", tuple(act.frame_range), "from", path.name)
	return act


def _make_mat(name: str, color: tuple[float, float, float]) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	nodes.clear()
	bsdf = nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Metallic"].default_value = 0.55
	bsdf.inputs["Roughness"].default_value = 0.38
	out = nodes.new("ShaderNodeOutputMaterial")
	links.new(bsdf.outputs[0], out.inputs[0])
	return mat


def _box(name: str, size: Vector, loc: Vector, mat: bpy.types.Material) -> bpy.types.Object:
	bpy.ops.mesh.primitive_cube_add(size=2.0, location=loc)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size * 0.5
	bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
	obj.data.materials.append(mat)
	return obj


def _build_mixamo_proxy_rifle() -> bpy.types.Object:
	body_mat = _make_mat("ProxyRifleBody", (0.12, 0.13, 0.14))
	dark_mat = _make_mat("ProxyRifleDark", (0.05, 0.055, 0.06))
	parts: list[bpy.types.Object] = []
	parts.append(_box("recv", Vector((0.045, 0.28, 0.07)), Vector((0.0, 0.10, 0.02)), body_mat))
	parts.append(_box("guard", Vector((0.04, 0.18, 0.05)), Vector((0.0, MIXAMO_HAND_SPAN, 0.02)), dark_mat))
	parts.append(_box("barrel", Vector((0.018, 0.28, 0.018)), Vector((0.0, 0.42, 0.03)), dark_mat))
	parts.append(_box("stock", Vector((0.035, 0.22, 0.06)), Vector((0.0, -0.18, 0.03)), dark_mat))
	parts.append(_box("stock_pad", Vector((0.05, 0.04, 0.09)), Vector((0.0, -0.28, 0.04)), dark_mat))
	parts.append(_box("grip", Vector((0.028, 0.04, 0.11)), GRIP_LOCAL + Vector((0.0, 0.0, -0.02)), dark_mat))
	parts.append(_box("mag", Vector((0.025, 0.05, 0.12)), Vector((0.0, 0.06, -0.08)), dark_mat))
	parts.append(_box("optic", Vector((0.03, 0.12, 0.035)), Vector((0.0, 0.08, 0.08)), body_mat))
	bpy.ops.object.select_all(action="DESELECT")
	for p in parts:
		p.select_set(True)
	bpy.context.view_layer.objects.active = parts[0]
	bpy.ops.object.join()
	rifle = bpy.context.active_object
	rifle.name = "rifle"
	rifle.location = (0.0, 0.0, 0.0)
	bpy.context.view_layer.update()
	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	rifle.select_set(True)
	bpy.context.view_layer.objects.active = rifle
	bpy.ops.export_scene.gltf(filepath=str(PROXY_GLB), use_selection=True, export_animations=False)
	print("WROTE proxy", PROXY_GLB)
	return rifle


def _build_mannequin(arm: bpy.types.Object) -> list[bpy.types.Object]:
	"""Bone-parented sci-fi boxes on the Mixamo armature (Y-Bot-like stand-in)."""
	mat = _make_mat("EliProxyBody", (0.55, 0.62, 0.68))
	accent = _make_mat("EliProxyAccent", (0.18, 0.55, 0.72))
	meshes: list[bpy.types.Object] = []
	for bone_name, (size, offset) in MANNEQUIN_PARTS.items():
		if bone_name not in arm.pose.bones:
			print("SKIP mannequin bone", bone_name)
			continue
		use_mat = accent if "Head" in bone_name or "Spine2" in bone_name else mat
		# Mixamo bone-local space is centimetres; host.scale (~0.01) converts to metres.
		# Do NOT pre-scale by 0.01 or parts become millimetre-invisible after parent scale.
		obj = _box(f"part_{bone_name.split(':')[-1]}", size, Vector((0, 0, 0)), use_mat)
		obj.parent = arm
		obj.parent_type = "BONE"
		obj.parent_bone = bone_name
		bpy.context.view_layer.update()
		obj.location = offset
		obj.rotation_euler = (0.0, 0.0, 0.0)
		obj.scale = Vector((1.0, 1.0, 1.0))
		meshes.append(obj)
	print("mannequin parts", len(meshes))
	return meshes


def _seat_rifle(arm: bpy.types.Object, rifle: bpy.types.Object) -> None:
	rh = _palm(arm, "Right")
	lh = _palm(arm, "Left")
	mesh_forward = (MUZZLE_LOCAL - GRIP_LOCAL).normalized()
	hand_aim = (lh - rh).normalized()
	up = Vector((0.0, 0.0, 1.0))
	x = up.cross(hand_aim)
	if x.length < 1e-5:
		x = Vector((1.0, 0.0, 0.0))
	x.normalize()
	z = x.cross(hand_aim).normalized()
	if z.dot(up) < 0.0:
		x = -x
		z = x.cross(hand_aim).normalized()
	world_basis = Matrix((x, hand_aim, z)).transposed().to_4x4()
	mx = up.cross(mesh_forward)
	if mx.length < 1e-5:
		mx = Vector((1.0, 0.0, 0.0))
	mx.normalize()
	mz = mesh_forward.cross(mx).normalized()
	if mz.dot(up) < 0.0:
		mx = -mx
		mz = -mz
	mesh_basis = Matrix((mx, mesh_forward, mz)).transposed().to_4x4()
	local_sep = (SUPPORT_LOCAL - GRIP_LOCAL).length
	hand_sep = (lh - rh).length
	scale = hand_sep / max(local_sep, 1e-6)
	print("hand_sep", round(hand_sep, 4), "scale", round(scale, 4))
	R = world_basis @ mesh_basis.inverted()
	origin = rh - R.to_3x3() @ (GRIP_LOCAL * scale)
	mw = Matrix.Translation(origin) @ R @ Matrix.Scale(scale, 4)
	rifle.constraints.clear()
	rifle.parent = None
	rifle.matrix_world = mw
	bpy.context.view_layer.update()
	rifle.matrix_world = mw
	bpy.context.view_layer.update()
	grip_err = (rifle.matrix_world @ GRIP_LOCAL - rh).length
	sup_err = (rifle.matrix_world @ SUPPORT_LOCAL - lh).length
	print("seat grip_err", round(grip_err, 4), "sup_err", round(sup_err, 4))
	if grip_err > 0.03:
		print("WARN grip seating loose", grip_err)


def _mount_bone_parent(arm: bpy.types.Object, rifle: bpy.types.Object) -> None:
	mw = rifle.matrix_world.copy()
	rifle.constraints.clear()
	rifle.parent = arm
	rifle.parent_type = "BONE"
	rifle.parent_bone = "mixamorig:RightHand"
	bpy.context.view_layer.update()
	rifle.matrix_world = mw
	bpy.context.view_layer.update()


def _author_rifle_holster(arm: bpy.types.Object, rifle_hand: bpy.types.Object) -> bpy.types.Object:
	holster = rifle_hand.copy()
	holster.data = rifle_hand.data.copy()
	bpy.context.collection.objects.link(holster)
	holster.name = "rifle_holster"
	holster.constraints.clear()
	holster.parent = None
	bpy.context.view_layer.update()
	holster.parent = arm
	holster.parent_type = "BONE"
	holster.parent_bone = "mixamorig:Spine2"
	bpy.context.view_layer.update()
	# Approximate back sling for centimetre Mixamo bone space (host.scale ~0.01).
	holster.location = Vector((0.0, -0.08, 0.02))
	holster.rotation_euler = (1.2, 0.15, 1.57)
	holster.scale = Vector((1.0, 1.0, 1.0))
	bpy.context.view_layer.update()
	print("holster parent", holster.parent_bone)
	return holster


def _add_muzzle(rifle: bpy.types.Object) -> bpy.types.Object:
	existing = bpy.data.objects.get("Muzzle")
	if existing:
		bpy.data.objects.remove(existing, do_unlink=True)
	bpy.ops.object.empty_add(type="PLAIN_AXES")
	muzzle = bpy.context.active_object
	muzzle.name = "Muzzle"
	muzzle.empty_display_size = 0.04
	muzzle.parent = rifle
	muzzle.matrix_parent_inverse.identity()
	muzzle.location = MUZZLE_LOCAL.copy()
	bpy.context.view_layer.update()
	return muzzle


def run() -> None:
	_purge()
	OUT_DIR.mkdir(parents=True, exist_ok=True)

	# Host skeleton from Unarmed idle FBX (Mixamo armature, no skin).
	host_fbx = CLIPS["Unarmed_Idle"]
	if not host_fbx.exists():
		raise RuntimeError(f"missing host skeleton source {host_fbx}")
	bpy.ops.import_scene.fbx(filepath=str(host_fbx), automatic_bone_orientation=True)
	host = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	host.name = "Swat"
	# Drop the idle action imported with the host — clips re-imported below.
	if host.animation_data:
		host.animation_data_clear()
	for act in list(bpy.data.actions):
		bpy.data.actions.remove(act)
	print("keeping Mixamo scale", tuple(host.scale), "bones", len(host.data.bones))
	_disable_inherit_scale(host)

	meshes = _build_mannequin(host)

	actions: dict[str, bpy.types.Action] = {}
	seen_paths: dict[str, bpy.types.Action] = {}
	for name, path in CLIPS.items():
		key = str(path)
		if key in seen_paths and name != "Unarmed_Idle":
			# Reuse baked action data via copy for alternate clip names.
			dup = seen_paths[key].copy()
			dup.name = name
			if name in HIP_STRIP_CLIPS:
				_strip_hip_location(dup)
			actions[name] = dup
			print("CLIP", name, "dup from", path.name)
			continue
		act = _import_clip_action(path, name)
		if act is not None:
			actions[name] = act
			seen_paths[key] = act
	if "Rifle_Idle" not in actions or "Unarmed_Idle" not in actions or "Running" not in actions:
		raise RuntimeError("required clips missing: need Unarmed_Idle, Running, Rifle_Idle")

	print("grounding across clips…")
	_ground_across_clips(host, actions)

	_bind_action(host, actions["Rifle_Idle"])
	mid = int((actions["Rifle_Idle"].frame_range[0] + actions["Rifle_Idle"].frame_range[1]) // 2)
	bpy.context.scene.frame_set(mid)
	bpy.context.view_layer.update()

	rifle = _build_mixamo_proxy_rifle()
	_seat_rifle(host, rifle)
	_mount_bone_parent(host, rifle)
	holster = _author_rifle_holster(host, rifle)
	muzzle = _add_muzzle(rifle)

	if host.animation_data is None:
		host.animation_data_create()
	while host.animation_data.nla_tracks:
		host.animation_data.nla_tracks.remove(host.animation_data.nla_tracks[0])
	for name, act in actions.items():
		track = host.animation_data.nla_tracks.new()
		track.name = name
		strip = track.strips.new(name, 1, act)
		strip.action = act

	_bind_action(host, actions["Unarmed_Idle"])
	bpy.context.scene.frame_set(1)
	bpy.context.view_layer.update()

	bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	host.select_set(True)
	for m in meshes:
		m.select_set(True)
	rifle.select_set(True)
	holster.select_set(True)
	muzzle.select_set(True)
	bpy.context.view_layer.objects.active = host
	bpy.ops.export_scene.gltf(
		filepath=str(GLB_OUT),
		use_selection=True,
		export_animations=True,
		export_animation_mode="NLA_TRACKS",
		export_nla_strips=True,
		export_def_bones=True,
		export_rest_position_armature=True,
		export_extras=True,
	)
	print("EXPORTED", GLB_OUT)
	print("NOTE: proxy pack from vrm/anim_src — replace with Swat builder when incoming/ FBXs available")


if __name__ == "__main__":
	run()
