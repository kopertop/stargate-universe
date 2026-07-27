"""Measure Mixamo Rifle Idle RH/LH span — the virtual prop the mocap implies."""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

IN = Path("/Users/cmoyer/Projects/personal/stargate-universe/models/mixamo_openbot/incoming")


def purge():
	for o in list(bpy.data.objects):
		if o.type not in {"CAMERA", "LIGHT"}:
			bpy.data.objects.remove(o, do_unlink=True)


def bone_w(arm, name):
	return (arm.matrix_world @ arm.pose.bones[name].matrix).translation


def palm(arm, side):
	w = bone_w(arm, f"mixamorig:{side}Hand")
	tips = []
	for f in ("Thumb4", "Index4", "Middle4"):
		n = f"mixamorig:{side}Hand{f}"
		if n in arm.pose.bones:
			tips.append(bone_w(arm, n))
	return w.lerp(sum(tips, Vector()) / len(tips), 0.65) if tips else w


def run():
	purge()
	bpy.ops.import_scene.fbx(filepath=str(IN / "Swat.fbx"), automatic_bone_orientation=True)
	host = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	before = {a.name for a in bpy.data.actions}
	bpy.ops.import_scene.fbx(filepath=str(IN / "Rifle Idle.fbx"), automatic_bone_orientation=True)
	for o in list(bpy.data.objects):
		if o.type == "ARMATURE" and o != host:
			bpy.data.objects.remove(o, do_unlink=True)
	act = next(a for a in bpy.data.actions if a.name not in before)
	if host.animation_data is None:
		host.animation_data_create()
	host.animation_data.action = act
	if hasattr(host.animation_data, "action_slot") and act.slots:
		host.animation_data.action_slot = act.slots[0]
	mid = int((act.frame_range[0] + act.frame_range[1]) // 2)
	bpy.context.scene.frame_set(mid)
	bpy.context.view_layer.update()

	rh = palm(host, "Right")
	lh = palm(host, "Left")
	rs = bone_w(host, "mixamorig:RightShoulder")
	print("frame", mid)
	print("RH palm", tuple(round(c, 4) for c in rh))
	print("LH palm", tuple(round(c, 4) for c in lh))
	print("hand_sep_m", round((lh - rh).length, 4))
	print("aim", tuple(round(c, 4) for c in (lh - rh).normalized()))
	print("shoulder", tuple(round(c, 4) for c in rs))
	print("stock_estimate_sep_to_shoulder", round((rs - rh).length, 4))
	# Typical M4: overall ~0.84–1.0m, grip-to-handguard ~0.25–0.40m
	print("implied_grip_to_support_cm", round((lh - rh).length * 100, 1))


if __name__ == "__main__":
	run()
