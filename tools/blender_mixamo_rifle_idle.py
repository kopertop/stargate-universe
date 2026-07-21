"""Build Mixamo Swat + Rifle Idle + seated rifle → GLB proof.

Follows docs/animation/rifle-aim-host-pipeline.md.

Blender 5 gotchas handled here:
  - Layered Actions need `animation_data.action_slot = action.slots[0]`
  - Mixamo FBX often has armature scale 0.01 + scale fcurves — strip scales and
    disable bone inherit_scale before bone-parenting props
"""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path("/Users/cmoyer/Projects/personal/stargate-universe")
IN = ROOT / "models/mixamo_openbot/incoming"
OUT_DIR = ROOT / "models/mixamo_openbot"
SHOT_DIR = ROOT / "screenshots/result/mint_rifle_aim"

HOST_FBX = IN / "Swat.fbx"
IDLE_FBX = IN / "Rifle Idle.fbx"
RIFLE_GLB = ROOT / "models/mint/props/rifle.glb"

BLEND_OUT = OUT_DIR / "Swat_rifle_idle.blend"
GLB_OUT = OUT_DIR / "Swat_rifle_idle.glb"
PNG_OUT = SHOT_DIR / "swat_rifle_idle.png"
PNG_SIDE = SHOT_DIR / "swat_rifle_idle_side.png"
PNG_CLOSE = SHOT_DIR / "swat_rifle_idle_close.png"

GRIP_LOCAL = Vector((0.003, -0.092, 0.131))
SUPPORT_LOCAL = Vector((0.004, 0.28, 0.02))


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


def _ensure_camera() -> bpy.types.Object:
	if bpy.context.scene.camera is None:
		bpy.ops.object.camera_add()
		bpy.context.scene.camera = bpy.context.active_object
	return bpy.context.scene.camera


def _ensure_sun() -> None:
	if not any(o.type == "LIGHT" for o in bpy.data.objects):
		bpy.ops.object.light_add(type="SUN", location=(3, -2, 6))
		bpy.context.active_object.data.energy = 3.5


def _world_bone(arm: bpy.types.Object, name: str) -> Matrix:
	return arm.matrix_world @ arm.pose.bones[name].matrix


def _strip_scale_fcurves(action: bpy.types.Action) -> int:
	removed = 0
	for layer in action.layers:
		for strip in layer.strips:
			for cb in strip.channelbags:
				for fc in list(cb.fcurves):
					if fc.data_path.endswith(".scale"):
						cb.fcurves.remove(fc)
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


def _opaque_rifle_material(rifle: bpy.types.Object) -> None:
	mat = bpy.data.materials.new("RifleOpaque")
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	nodes.clear()
	bsdf = nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.inputs["Base Color"].default_value = (0.04, 0.04, 0.045, 1.0)
	bsdf.inputs["Metallic"].default_value = 0.85
	bsdf.inputs["Roughness"].default_value = 0.4
	if "Emission Color" in bsdf.inputs:
		bsdf.inputs["Emission Color"].default_value = (0.08, 0.08, 0.09, 1.0)
		bsdf.inputs["Emission Strength"].default_value = 0.25
	out = nodes.new("ShaderNodeOutputMaterial")
	links.new(bsdf.outputs[0], out.inputs[0])
	rifle.data.materials.clear()
	rifle.data.materials.append(mat)


def _render(cam: bpy.types.Object, target: Vector, offset: Vector, path: Path, lens: float = 50.0) -> None:
	scene = bpy.context.scene
	cam.location = target + offset
	cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
	cam.data.lens = lens
	scene.render.filepath = str(path)
	bpy.ops.render.render(write_still=True)
	print("WROTE", path)


def run() -> None:
	_purge()
	SHOT_DIR.mkdir(parents=True, exist_ok=True)
	_ensure_sun()
	_ensure_camera()

	bpy.ops.import_scene.fbx(filepath=str(HOST_FBX), automatic_bone_orientation=True)
	host_arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	host_arm.name = "Swat"
	host_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	if host_arm.animation_data:
		host_arm.animation_data_clear()
	print("host bones", len(host_arm.data.bones), "meshes", [m.name for m in host_meshes])

	before_arms = {o.name for o in bpy.data.objects if o.type == "ARMATURE"}
	before_actions = {a.name for a in bpy.data.actions}
	bpy.ops.import_scene.fbx(filepath=str(IDLE_FBX), automatic_bone_orientation=True)
	anim_arm = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name not in before_arms)
	new_actions = [a for a in bpy.data.actions if a.name not in before_actions]
	idle_action = next((a for a in new_actions if "Layer0" in a.name), None)
	if idle_action is None:
		idle_action = max(new_actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
	idle_action.name = "Rifle_Idle"
	print("idle_action", idle_action.name, "frames", tuple(idle_action.frame_range))
	bpy.data.objects.remove(anim_arm, do_unlink=True)

	removed = _strip_scale_fcurves(idle_action)
	print("stripped scale fcurves", removed)
	_disable_inherit_scale(host_arm)
	_bind_action(host_arm, idle_action)

	scene = bpy.context.scene
	scene.frame_start = int(idle_action.frame_range[0])
	scene.frame_end = int(idle_action.frame_range[1])
	mid = (scene.frame_start + scene.frame_end) // 2
	scene.frame_set(mid)
	bpy.context.view_layer.update()

	rh = _world_bone(host_arm, "mixamorig:RightHand").translation
	lh = _world_bone(host_arm, "mixamorig:LeftHand").translation
	print("frame", mid, "RightHand", rh, "LeftHand", lh)
	if abs(rh.x) > 0.5 and abs(rh.y) < 0.15:
		raise RuntimeError(f"Rifle Idle not driving pose (RH={rh})")

	bpy.ops.import_scene.gltf(filepath=str(RIFLE_GLB))
	rifle = next(
		o for o in bpy.data.objects
		if o.type == "MESH" and o.name not in {m.name for m in host_meshes}
	)
	rifle.name = "rifle"
	rifle.parent = None
	_opaque_rifle_material(rifle)

	aim = (lh - rh).normalized()
	up = Vector((0.0, 0.0, 1.0))
	x = up.cross(aim)
	x.normalize()
	z = x.cross(aim).normalized()
	if z.dot(up) > 0.0:
		x = -x
		z = x.cross(aim).normalized()
	local_sep = (SUPPORT_LOCAL - GRIP_LOCAL).length
	scale = (lh - rh).length / max(local_sep, 1e-6)
	basis = Matrix((x, aim, z)).transposed().to_4x4()
	origin = rh - basis.to_3x3() @ (GRIP_LOCAL * scale)
	rifle.matrix_world = Matrix.Translation(origin) @ basis @ Matrix.Scale(scale, 4)
	bpy.context.view_layer.update()
	mw = rifle.matrix_world.copy()
	print(
		"scale", scale,
		"grip_err", (rifle.matrix_world @ GRIP_LOCAL - rh).length,
		"sup_err", (rifle.matrix_world @ SUPPORT_LOCAL - lh).length,
	)

	rifle.parent = host_arm
	rifle.parent_type = "BONE"
	rifle.parent_bone = "mixamorig:RightHand"
	bpy.context.view_layer.update()
	rifle.matrix_world = mw
	bpy.context.view_layer.update()
	print("parented dims", rifle.dimensions, "scale", rifle.matrix_world.to_scale())

	scene.render.engine = "BLENDER_EEVEE"
	scene.render.resolution_x = 1400
	scene.render.resolution_y = 1000
	cam = scene.camera
	host_arm.hide_render = True
	chest = _world_bone(host_arm, "mixamorig:Spine2").translation
	_render(cam, chest, Vector((1.6, -2.2, 0.35)), PNG_OUT, 50.0)
	_render(cam, chest, Vector((2.4, 0.05, 0.15)), PNG_SIDE, 50.0)
	mid_pt = rh.lerp(lh, 0.4)
	_render(cam, mid_pt, Vector((0.9, -1.1, 0.4)), PNG_CLOSE, 40.0)

	bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	host_arm.select_set(True)
	for m in host_meshes:
		m.select_set(True)
	rifle.select_set(True)
	bpy.context.view_layer.objects.active = host_arm
	bpy.ops.export_scene.gltf(
		filepath=str(GLB_OUT),
		use_selection=True,
		export_animations=True,
		export_animation_mode="ACTIONS",
		export_def_bones=True,
		export_rest_position_armature=True,
	)
	print("EXPORTED", GLB_OUT)


if __name__ == "__main__":
	run()
