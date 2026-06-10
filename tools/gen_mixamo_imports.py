#!/usr/bin/env python3
"""Splice a Mixamo->SkeletonProfileHumanoid BoneMap into Godot .import files.

Godot's scene importer applies `retarget/bone_map` at import time: bones get
renamed to humanoid names (Hips, Spine, RightHand...), the skeleton becomes
%GeneralSkeleton, and every animation track is rewritten to match — which is
exactly the naming the godot-vrm importer gives our VRM characters. After this
runs (+ `godot --headless --import`), Mixamo clips play directly on any VRM.

Usage: python3 tools/gen_mixamo_imports.py models/vrm/anim_src/*.fbx.import
"""
import sys

# Humanoid profile bone -> Mixamo bone (colons become underscores on import).
MIXAMO = {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftEye": "mixamorig_LeftEye",
	"RightEye": "mixamorig_RightEye",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"LeftThumbMetacarpal": "mixamorig_LeftHandThumb1",
	"LeftThumbProximal": "mixamorig_LeftHandThumb2",
	"LeftThumbDistal": "mixamorig_LeftHandThumb3",
	"LeftIndexProximal": "mixamorig_LeftHandIndex1",
	"LeftIndexIntermediate": "mixamorig_LeftHandIndex2",
	"LeftIndexDistal": "mixamorig_LeftHandIndex3",
	"LeftMiddleProximal": "mixamorig_LeftHandMiddle1",
	"LeftMiddleIntermediate": "mixamorig_LeftHandMiddle2",
	"LeftMiddleDistal": "mixamorig_LeftHandMiddle3",
	"LeftRingProximal": "mixamorig_LeftHandRing1",
	"LeftRingIntermediate": "mixamorig_LeftHandRing2",
	"LeftRingDistal": "mixamorig_LeftHandRing3",
	"LeftLittleProximal": "mixamorig_LeftHandPinky1",
	"LeftLittleIntermediate": "mixamorig_LeftHandPinky2",
	"LeftLittleDistal": "mixamorig_LeftHandPinky3",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
}
# Mirror left -> right.
for k, v in list(MIXAMO.items()):
	if k.startswith("Left"):
		MIXAMO["Right" + k[4:]] = v.replace("Left", "Right")

PROFILE_ORDER = [
	"Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftEye",
	"RightEye", "Jaw", "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal",
	"LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal",
	"LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]


def bone_map_blob() -> str:
	entries = ",".join(
		'"bone_map/%s":&"%s"' % (b, MIXAMO.get(b, "")) for b in PROFILE_ORDER
	)
	profile = (
		'Object(SkeletonProfileHumanoid,"resource_local_to_scene":false,'
		'"resource_name":"","root_bone":&"Root","scale_base_bone":&"Hips",'
		'"group_size":4,"bone_size":56,"script":null)'
	)
	return (
		'Object(BoneMap,"resource_local_to_scene":false,"resource_name":"",'
		'"profile":%s\n,"bonemap":null,%s,"script":null)\n' % (profile, entries)
	)


SUBRESOURCES = (
	"_subresources={\n"
	'"nodes": {\n'
	'"PATH:Skeleton3D": {\n'
	'"retarget/bone_map": %s'
	"}\n"
	"}\n"
	"}\n" % bone_map_blob()
)


def splice(path: str) -> None:
	with open(path) as f:
		raw = f.read()
	if "retarget/bone_map" in raw:
		print("skip (already mapped):", path)
		return
	if "_subresources={}" in raw:
		raw = raw.replace("_subresources={}", SUBRESOURCES)
	elif "_subresources=" not in raw:
		raw = raw.rstrip() + "\n" + SUBRESOURCES
	else:
		print("WARN: non-empty _subresources, skipping:", path)
		return
	with open(path, "w") as f:
		f.write(raw)
	print("mapped:", path)


if __name__ == "__main__":
	for p in sys.argv[1:]:
		splice(p)
