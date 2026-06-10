#!/usr/bin/env python3
"""Splice a SkeletonProfileHumanoid BoneMap into Godot .import files.

Godot's scene importer applies `retarget/bone_map` at import time: bones get
renamed to humanoid names (Hips, Spine, RightHand...), the skeleton becomes
%GeneralSkeleton, and every animation track is rewritten to match — which is
exactly the naming the godot-vrm importer gives our VRM characters. After this
runs (+ `godot --headless --import`), the rigs join the shared humanoid
ecosystem: animations and skinned gear interchange by bone name.

Profiles: mixamo (mixamorig_*) and ue (Unreal-mannequin-style names, used by
Quaternius Universal Base Characters / Modular Outfits).

Usage:
  python3 tools/gen_mixamo_imports.py models/vrm/anim_src/*.fbx.import
  python3 tools/gen_mixamo_imports.py --profile ue --skelpath Armature/Skeleton3D \\
      models/quaternius/**/*.gltf.import
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

# Unreal-mannequin-style naming (Quaternius Universal Base / Modular Outfits).
UE = {
	"Root": "root",
	"Hips": "pelvis",
	"Spine": "spine_01",
	"Chest": "spine_02",
	"UpperChest": "spine_03",
	"Neck": "neck_01",
	"Head": "Head",
	"LeftShoulder": "clavicle_l",
	"LeftUpperArm": "upperarm_l",
	"LeftLowerArm": "lowerarm_l",
	"LeftHand": "hand_l",
	"LeftThumbMetacarpal": "thumb_01_l",
	"LeftThumbProximal": "thumb_02_l",
	"LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l",
	"LeftIndexIntermediate": "index_02_l",
	"LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l",
	"LeftMiddleIntermediate": "middle_02_l",
	"LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l",
	"LeftRingIntermediate": "ring_02_l",
	"LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l",
	"LeftLittleIntermediate": "pinky_02_l",
	"LeftLittleDistal": "pinky_03_l",
	"LeftUpperLeg": "thigh_l",
	"LeftLowerLeg": "calf_l",
	"LeftFoot": "foot_l",
	"LeftToes": "ball_l",
}
for k, v in list(UE.items()):
	if k.startswith("Left"):
		UE["Right" + k[4:]] = v[:-2] + "_r" if v.endswith("_l") else v

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


def bone_map_blob(mapping: dict) -> str:
	entries = ",".join(
		'"bone_map/%s":&"%s"' % (b, mapping.get(b, "")) for b in PROFILE_ORDER
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


def subresources(mapping: dict, skelpath: str) -> str:
	return (
		"_subresources={\n"
		'"nodes": {\n'
		'"PATH:%s": {\n'
		'"retarget/bone_map": %s'
		"}\n"
		"}\n"
		"}\n" % (skelpath, bone_map_blob(mapping))
	)


def splice(path: str, mapping: dict, skelpath: str) -> None:
	with open(path) as f:
		raw = f.read()
	if "retarget/bone_map" in raw:
		print("skip (already mapped):", path)
		return
	blob = subresources(mapping, skelpath)
	if "_subresources={}" in raw:
		raw = raw.replace("_subresources={}", blob)
	elif "_subresources=" not in raw:
		raw = raw.rstrip() + "\n" + blob
	else:
		print("WARN: non-empty _subresources, skipping:", path)
		return
	with open(path, "w") as f:
		f.write(raw)
	print("mapped:", path)


if __name__ == "__main__":
	args = sys.argv[1:]
	mapping, skelpath = MIXAMO, "Skeleton3D"
	if "--profile" in args:
		i = args.index("--profile")
		mapping = {"mixamo": MIXAMO, "ue": UE}[args[i + 1]]
		del args[i:i + 2]
	if "--skelpath" in args:
		i = args.index("--skelpath")
		skelpath = args[i + 1]
		del args[i:i + 2]
	for p in args:
		splice(p, mapping, skelpath)
