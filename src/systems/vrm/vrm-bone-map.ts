/**
 * VRM Humanoid Bone Mapping — maps VRM standard bone names to ggez rig joints.
 *
 * VRM 1.0 defines a standardized humanoid bone hierarchy. This module provides
 * a static mapping table that bridges VRM bone names to ggez `RigDefinition`
 * joint names, enabling any VRM model to use any humanoid animation clip
 * without per-model retargeting.
 *
 * @see design/gdd/vrm-model-integration.md §Detailed Rules > Humanoid Bone Mapping
 */

/**
 * VRM humanoid bone names (VRM 1.0 specification).
 * Required bones are marked; optional bones may not exist on all models.
 */
export const VRM_REQUIRED_BONES = [
	"hips",
	"spine",
	"chest",
	"neck",
	"head",
	"leftUpperArm",
	"leftLowerArm",
	"leftHand",
	"rightUpperArm",
	"rightLowerArm",
	"rightHand",
	"leftUpperLeg",
	"leftLowerLeg",
	"leftFoot",
	"rightUpperLeg",
	"rightLowerLeg",
	"rightFoot",
] as const;

export const VRM_OPTIONAL_BONES = [
	"upperChest",
	"leftShoulder",
	"rightShoulder",
	"leftEye",
	"rightEye",
	"jaw",
	"leftToes",
	"rightToes",
	"leftThumbMetacarpal",
	"leftThumbProximal",
	"leftThumbDistal",
	"leftIndexProximal",
	"leftIndexIntermediate",
	"leftIndexDistal",
	"leftMiddleProximal",
	"leftMiddleIntermediate",
	"leftMiddleDistal",
	"leftRingProximal",
	"leftRingIntermediate",
	"leftRingDistal",
	"leftLittleProximal",
	"leftLittleIntermediate",
	"leftLittleDistal",
	"rightThumbMetacarpal",
	"rightThumbProximal",
	"rightThumbDistal",
	"rightIndexProximal",
	"rightIndexIntermediate",
	"rightIndexDistal",
	"rightMiddleProximal",
	"rightMiddleIntermediate",
	"rightMiddleDistal",
	"rightRingProximal",
	"rightRingIntermediate",
	"rightRingDistal",
	"rightLittleProximal",
	"rightLittleIntermediate",
	"rightLittleDistal",
] as const;

export type VrmBoneName =
	| (typeof VRM_REQUIRED_BONES)[number]
	| (typeof VRM_OPTIONAL_BONES)[number];

/**
 * Mapping from VRM humanoid bone names to ggez rig joint names.
 *
 * The ggez animation pipeline uses `RigDefinition` with joint names derived
 * from the Three.js `Skeleton.bones[].name` property. VRM models set these
 * bone names according to the VRM humanoid spec. This table maps VRM names
 * to the ggez convention (which by default mirrors the Three.js bone names).
 *
 * Since ggez's `createRigFromSkeleton()` reads bone names directly from the
 * Three.js Skeleton, and VRM sets those names to its humanoid standard, the
 * mapping is identity in most cases. This table exists for cases where
 * animation clips use different naming conventions (e.g., Mixamo clips).
 */
export const VRM_TO_GGEZ_BONE_MAP: ReadonlyMap<string, string> = new Map([
	// Core spine chain
	["hips", "hips"],
	["spine", "spine"],
	["chest", "chest"],
	["upperChest", "upperChest"],
	["neck", "neck"],
	["head", "head"],

	// Left arm
	["leftShoulder", "leftShoulder"],
	["leftUpperArm", "leftUpperArm"],
	["leftLowerArm", "leftLowerArm"],
	["leftHand", "leftHand"],

	// Right arm
	["rightShoulder", "rightShoulder"],
	["rightUpperArm", "rightUpperArm"],
	["rightLowerArm", "rightLowerArm"],
	["rightHand", "rightHand"],

	// Left leg
	["leftUpperLeg", "leftUpperLeg"],
	["leftLowerLeg", "leftLowerLeg"],
	["leftFoot", "leftFoot"],
	["leftToes", "leftToes"],

	// Right leg
	["rightUpperLeg", "rightUpperLeg"],
	["rightLowerLeg", "rightLowerLeg"],
	["rightFoot", "rightFoot"],
	["rightToes", "rightToes"],

	// Eyes & jaw
	["leftEye", "leftEye"],
	["rightEye", "rightEye"],
	["jaw", "jaw"],

	// Left hand fingers
	["leftThumbMetacarpal", "leftThumbMetacarpal"],
	["leftThumbProximal", "leftThumbProximal"],
	["leftThumbDistal", "leftThumbDistal"],
	["leftIndexProximal", "leftIndexProximal"],
	["leftIndexIntermediate", "leftIndexIntermediate"],
	["leftIndexDistal", "leftIndexDistal"],
	["leftMiddleProximal", "leftMiddleProximal"],
	["leftMiddleIntermediate", "leftMiddleIntermediate"],
	["leftMiddleDistal", "leftMiddleDistal"],
	["leftRingProximal", "leftRingProximal"],
	["leftRingIntermediate", "leftRingIntermediate"],
	["leftRingDistal", "leftRingDistal"],
	["leftLittleProximal", "leftLittleProximal"],
	["leftLittleIntermediate", "leftLittleIntermediate"],
	["leftLittleDistal", "leftLittleDistal"],

	// Right hand fingers
	["rightThumbMetacarpal", "rightThumbMetacarpal"],
	["rightThumbProximal", "rightThumbProximal"],
	["rightThumbDistal", "rightThumbDistal"],
	["rightIndexProximal", "rightIndexProximal"],
	["rightIndexIntermediate", "rightIndexIntermediate"],
	["rightIndexDistal", "rightIndexDistal"],
	["rightMiddleProximal", "rightMiddleProximal"],
	["rightMiddleIntermediate", "rightMiddleIntermediate"],
	["rightMiddleDistal", "rightMiddleDistal"],
	["rightRingProximal", "rightRingProximal"],
	["rightRingIntermediate", "rightRingIntermediate"],
	["rightRingDistal", "rightRingDistal"],
	["rightLittleProximal", "rightLittleProximal"],
	["rightLittleIntermediate", "rightLittleIntermediate"],
	["rightLittleDistal", "rightLittleDistal"],
]);

/**
 * Mixamo bone names → VRM humanoid bone names.
 * Used when retargeting Mixamo animation clips to VRM skeletons.
 */
export const MIXAMO_TO_VRM_BONE_MAP: ReadonlyMap<string, string> = new Map([
	["mixamorigHips", "hips"],
	["mixamorigSpine", "spine"],
	["mixamorigSpine1", "chest"],
	["mixamorigSpine2", "upperChest"],
	["mixamorigNeck", "neck"],
	["mixamorigHead", "head"],
	["mixamorigLeftShoulder", "leftShoulder"],
	["mixamorigLeftArm", "leftUpperArm"],
	["mixamorigLeftForeArm", "leftLowerArm"],
	["mixamorigLeftHand", "leftHand"],
	["mixamorigRightShoulder", "rightShoulder"],
	["mixamorigRightArm", "rightUpperArm"],
	["mixamorigRightForeArm", "rightLowerArm"],
	["mixamorigRightHand", "rightHand"],
	["mixamorigLeftUpLeg", "leftUpperLeg"],
	["mixamorigLeftLeg", "leftLowerLeg"],
	["mixamorigLeftFoot", "leftFoot"],
	["mixamorigLeftToeBase", "leftToes"],
	["mixamorigRightUpLeg", "rightUpperLeg"],
	["mixamorigRightLeg", "rightLowerLeg"],
	["mixamorigRightFoot", "rightFoot"],
	["mixamorigRightToeBase", "rightToes"],
]);

/**
 * Validate that a VRM humanoid has all required bones.
 * Returns a list of missing bone names (empty if valid).
 */
export function validateRequiredBones(
	availableBones: ReadonlySet<string>
): readonly string[] {
	const missing: string[] = [];

	for (const bone of VRM_REQUIRED_BONES) {
		if (!availableBones.has(bone)) {
			missing.push(bone);
		}
	}

	return missing;
}
