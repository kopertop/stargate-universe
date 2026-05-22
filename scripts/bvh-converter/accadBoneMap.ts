import * as THREE from 'three';
import type { VRMHumanBoneName } from '@pixiv/three-vrm';

/** BVH "End Site" leaf nodes must never participate in humanoid mapping. */
export function isEndSiteBone(obj: THREE.Object3D): boolean {
	const name = obj.name.toLowerCase().replace(/\s+/g, '');
	return name === 'endsite' || name.includes('endsite');
}

/** First non–end-site child, if any. */
export function firstAnimatableChild(bone: THREE.Bone): THREE.Bone | undefined {
	for (const child of bone.children) {
		if (!isEndSiteBone(child)) {
			return child as THREE.Bone;
		}
	}
	return undefined;
}

/**
 * ACCAD / Ohio State mocap subjects (Male1, Female1, …) share a stable naming
 * convention. When detected, map by name instead of heuristics — same approach
 * as the official bvh2vrma web tool + GeminiVRM ACCAD Female1 exports.
 */
const ACCAD_BONE_NAMES: Partial<Record<VRMHumanBoneName, string>> = {
	hips: 'Hips',
	spine: 'ToSpine',
	chest: 'Spine',
	upperChest: 'Spine1',
	neck: 'Neck',
	head: 'Head',
	leftShoulder: 'LeftShoulder',
	leftUpperArm: 'LeftArm',
	leftLowerArm: 'LeftForeArm',
	leftHand: 'LeftHand',
	rightShoulder: 'RightShoulder',
	rightUpperArm: 'RightArm',
	rightLowerArm: 'RightForeArm',
	rightHand: 'RightHand',
	leftUpperLeg: 'LeftUpLeg',
	leftLowerLeg: 'LeftLeg',
	leftFoot: 'LeftFoot',
	leftToes: 'LeftToeBase',
	rightUpperLeg: 'RightUpLeg',
	rightLowerLeg: 'RightLeg',
	rightFoot: 'RightFoot',
	rightToes: 'RightToeBase',
};

/** ACCAD BVH bone name → VRM glTF node name (matches eli-walk.vrma). */
export const ACCAD_TO_VRM_EXPORT_NODE_NAME: Readonly<Record<string, string>> = {
	Hips: 'Hips',
	ToSpine: 'Spine',
	Spine: 'Chest',
	Spine1: 'UpperChest',
	Neck: 'Neck',
	Head: 'Head',
	LeftShoulder: 'LeftShoulder',
	LeftArm: 'LeftUpperArm',
	LeftForeArm: 'LeftLowerArm',
	LeftHand: 'LeftHand',
	RightShoulder: 'RightShoulder',
	RightArm: 'RightUpperArm',
	RightForeArm: 'RightLowerArm',
	RightHand: 'RightHand',
	LeftUpLeg: 'LeftUpperLeg',
	LeftLeg: 'LeftLowerLeg',
	LeftFoot: 'LeftFoot',
	LeftToeBase: 'LeftToes',
	RightUpLeg: 'RightUpperLeg',
	RightLeg: 'RightLowerLeg',
	RightFoot: 'RightFoot',
	RightToeBase: 'RightToes',
};

const ACCAD_REQUIRED: readonly VRMHumanBoneName[] = [
	'hips',
	'spine',
	'chest',
	'head',
	'leftUpperArm',
	'rightUpperArm',
	'leftUpperLeg',
	'rightUpperLeg',
];

function findBoneByExactName(root: THREE.Object3D, name: string): THREE.Bone | null {
	let found: THREE.Bone | null = null;
	root.traverse((obj) => {
		if (found == null && obj.name === name && !isEndSiteBone(obj)) {
			found = obj as THREE.Bone;
		}
	});
	return found;
}

/** Returns a VRM humanoid map when the skeleton matches ACCAD naming. */
export function tryMapAccadSkeletonToVRM(
	root: THREE.Bone,
): Map<VRMHumanBoneName, THREE.Bone> | null {
	const probe = findBoneByExactName(root, 'Hips');
	if (probe == null || findBoneByExactName(root, 'ToSpine') == null) {
		return null;
	}

	const result = new Map<VRMHumanBoneName, THREE.Bone>();

	for (const [vrmName, bvhName] of Object.entries(ACCAD_BONE_NAMES) as [
		VRMHumanBoneName,
		string,
	][]) {
		const bone = findBoneByExactName(root, bvhName);
		if (bone != null) {
			result.set(vrmName, bone);
		}
	}

	for (const required of ACCAD_REQUIRED) {
		if (!result.has(required)) {
			return null;
		}
	}

	return result;
}

/** Remove End Site leaves before VRMA export (they break humanoid mapping). */
export function removeAccadEndSiteBones(rootBone: THREE.Bone): void {
	rootBone.traverse((obj) => {
		if (isEndSiteBone(obj)) {
			obj.parent?.remove(obj);
		}
	});
}

/**
 * Rename ACCAD BVH bones + clip tracks to VRM-standard glTF node names (Spine, Chest, …)
 * so createVRMAnimationClip retargets on VRoid models the same way as eli-walk.vrma.
 */
export function renameAccadBonesForVrmExport(
	rootBone: THREE.Bone,
	clip: THREE.AnimationClip,
): void {
	// Two-pass rename avoids collisions (ToSpine→Spine before Spine→Chest).
	const tempPrefix = "__accad_";
	for (const boneName of Object.keys(ACCAD_TO_VRM_EXPORT_NODE_NAME)) {
		const bone = findBoneByExactName(rootBone, boneName);
		if (bone != null) {
			bone.name = `${tempPrefix}${boneName}`;
		}
	}
	for (const [accadName, vrmName] of Object.entries(ACCAD_TO_VRM_EXPORT_NODE_NAME)) {
		const bone = findBoneByExactName(rootBone, `${tempPrefix}${accadName}`);
		if (bone != null) {
			bone.name = vrmName;
		}
	}

	for (const track of clip.tracks) {
		const dot = track.name.indexOf(".");
		if (dot === -1) continue;
		const boneName = track.name.slice(0, dot);
		const property = track.name.slice(dot);
		const vrmName = ACCAD_TO_VRM_EXPORT_NODE_NAME[boneName];
		if (vrmName != null) {
			track.name = `${vrmName}${property}`;
		}
	}
}
