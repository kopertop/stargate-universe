/**
 * VRM Animation Loading — supports both native VRMA format and Mixamo FBX retargeting.
 *
 * - `.vrma` files: Loaded via @pixiv/three-vrm-animation (native VRM animation format)
 * - `.fbx` / `.glb` files: Loaded and retargeted from Mixamo using rest-pose correction
 *
 * Based on the official three-vrm humanoidAnimation example:
 * https://github.com/pixiv/three-vrm/tree/dev/packages/three-vrm/examples/humanoidAnimation
 */
import type { VRM, VRMHumanBoneName } from "@pixiv/three-vrm";
import { createVRMAnimationClip, VRMAnimationLoaderPlugin } from "@pixiv/three-vrm-animation";
import {
	AnimationClip,
	Quaternion,
	QuaternionKeyframeTrack,
	Vector3,
	VectorKeyframeTrack,
} from "three";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

/**
 * Mixamo rig name → VRM humanoid bone name mapping.
 * Sourced from pixiv/three-vrm official example.
 */
const MIXAMO_TO_VRM: Record<string, VRMHumanBoneName> = {
	mixamorigHips: "hips",
	mixamorigSpine: "spine",
	mixamorigSpine1: "chest",
	mixamorigSpine2: "upperChest",
	mixamorigNeck: "neck",
	mixamorigHead: "head",
	mixamorigLeftShoulder: "leftShoulder",
	mixamorigLeftArm: "leftUpperArm",
	mixamorigLeftForeArm: "leftLowerArm",
	mixamorigLeftHand: "leftHand",
	mixamorigLeftHandThumb1: "leftThumbMetacarpal",
	mixamorigLeftHandThumb2: "leftThumbProximal",
	mixamorigLeftHandThumb3: "leftThumbDistal",
	mixamorigLeftHandIndex1: "leftIndexProximal",
	mixamorigLeftHandIndex2: "leftIndexIntermediate",
	mixamorigLeftHandIndex3: "leftIndexDistal",
	mixamorigLeftHandMiddle1: "leftMiddleProximal",
	mixamorigLeftHandMiddle2: "leftMiddleIntermediate",
	mixamorigLeftHandMiddle3: "leftMiddleDistal",
	mixamorigLeftHandRing1: "leftRingProximal",
	mixamorigLeftHandRing2: "leftRingIntermediate",
	mixamorigLeftHandRing3: "leftRingDistal",
	mixamorigLeftHandPinky1: "leftLittleProximal",
	mixamorigLeftHandPinky2: "leftLittleIntermediate",
	mixamorigLeftHandPinky3: "leftLittleDistal",
	mixamorigRightShoulder: "rightShoulder",
	mixamorigRightArm: "rightUpperArm",
	mixamorigRightForeArm: "rightLowerArm",
	mixamorigRightHand: "rightHand",
	mixamorigRightHandThumb1: "rightThumbMetacarpal",
	mixamorigRightHandThumb2: "rightThumbProximal",
	mixamorigRightHandThumb3: "rightThumbDistal",
	mixamorigRightHandIndex1: "rightIndexProximal",
	mixamorigRightHandIndex2: "rightIndexIntermediate",
	mixamorigRightHandIndex3: "rightIndexDistal",
	mixamorigRightHandMiddle1: "rightMiddleProximal",
	mixamorigRightHandMiddle2: "rightMiddleIntermediate",
	mixamorigRightHandMiddle3: "rightMiddleDistal",
	mixamorigRightHandRing1: "rightRingProximal",
	mixamorigRightHandRing2: "rightRingIntermediate",
	mixamorigRightHandRing3: "rightRingDistal",
	mixamorigRightHandPinky1: "rightLittleProximal",
	mixamorigRightHandPinky2: "rightLittleIntermediate",
	mixamorigRightHandPinky3: "rightLittleDistal",
	mixamorigLeftUpLeg: "leftUpperLeg",
	mixamorigLeftLeg: "leftLowerLeg",
	mixamorigLeftFoot: "leftFoot",
	mixamorigLeftToeBase: "leftToes",
	mixamorigRightUpLeg: "rightUpperLeg",
	mixamorigRightLeg: "rightLowerLeg",
	mixamorigRightFoot: "rightFoot",
	mixamorigRightToeBase: "rightToes",
} as Record<string, VRMHumanBoneName>;

// Scratch quaternions (reused per frame to avoid GC)
const _restRotationInverse = new Quaternion();
const _parentRestWorldRotation = new Quaternion();
const _quatA = new Quaternion();

/** Shared FBX loader for Mixamo animation loading. */
const fbxLoader = new FBXLoader();

/** Shared GLTF loader for GLB/VRMA animation loading (with VRMAnimation plugin). */
const gltfLoader = new GLTFLoader();
gltfLoader.register((parser) => new VRMAnimationLoaderPlugin(parser));

/**
 * Load a Mixamo animation from an FBX or GLB URL and retarget it for a VRM model.
 *
 * Performs rest-pose correction and hip height scaling so the animation plays
 * correctly on VRM's normalized skeleton.
 *
 * @param url Path to an FBX or GLB file containing a Mixamo animation
 * @param vrm The target VRM model
 * @param clipName Name for the resulting AnimationClip
 * @returns Retargeted AnimationClip ready for use with AnimationMixer on vrm.scene
 */
export async function loadMixamoAnimation(
	url: string,
	vrm: VRM,
	clipName: string,
): Promise<AnimationClip> {
	const ext = url.split(".").pop()?.toLowerCase() ?? "";
	let asset: { animations: AnimationClip[]; getObjectByName: (name: string) => any };

	if (ext === "glb" || ext === "gltf") {
		const gltf = await gltfLoader.loadAsync(url);
		asset = {
			animations: gltf.animations,
			getObjectByName: (name: string) => gltf.scene.getObjectByName(name),
		};
	} else {
		// Default to FBX
		const fbx = await fbxLoader.loadAsync(url);
		asset = {
			animations: fbx.animations,
			getObjectByName: (name: string) => fbx.getObjectByName(name),
		};
	}

	// Find the animation clip — Mixamo FBX typically names it "mixamo.com"
	const clip = asset.animations[0]
		?? AnimationClip.findByName(asset.animations, "mixamo.com");

	if (!clip) {
		throw new Error(`[VrmAnimRetarget] No animation clip found in ${url}`);
	}

	// Detect VRM version for coordinate system handling
	const isVrm0 = (vrm.meta as any)?.metaVersion === "0";

	// Debug: log track names from the FBX to check bone naming
	const trackBoneNames = new Set(clip.tracks.map((t) => t.name.split(".")[0]));
	console.info(`[VrmAnimRetarget] "${clipName}" from ${url} (VRM ${isVrm0 ? "0.x" : "1.x"})`);
	console.info(`  Clip tracks: ${clip.tracks.length}, bones: [${[...trackBoneNames].slice(0, 8).join(", ")}...]`);

	// Calculate hip height ratio for position scaling
	const mixamoHips = asset.getObjectByName("mixamorigHips");
	console.info(`  mixamorigHips found: ${!!mixamoHips}, pos.y: ${mixamoHips?.position?.y ?? "N/A"}`);

	const vrmHipsY = vrm.humanoid.normalizedRestPose.hips?.position?.[1] ?? 1.0;
	const motionHipsY = mixamoHips?.position?.y ?? 1.0;
	const hipsPositionScale = vrmHipsY / motionHipsY;
	console.info(`  Hip scale: vrm=${vrmHipsY.toFixed(3)} / motion=${motionHipsY.toFixed(3)} = ${hipsPositionScale.toFixed(3)}`);

	const tracks: (QuaternionKeyframeTrack | VectorKeyframeTrack)[] = [];
	let matchedTracks = 0;
	let unmatchedBones = 0;

	for (const track of clip.tracks) {
		const [mixamoRigName, propertyName] = track.name.split(".");
		const vrmBoneName = MIXAMO_TO_VRM[mixamoRigName];

		if (!vrmBoneName) {
			unmatchedBones++;
			continue;
		}

		const vrmNode = vrm.humanoid.getNormalizedBoneNode(vrmBoneName);
		if (!vrmNode) continue;

		const vrmNodeName = vrmNode.name;
		const mixamoRigNode = asset.getObjectByName(mixamoRigName);
		if (!mixamoRigNode) continue;

		matchedTracks++;

		if (track instanceof QuaternionKeyframeTrack) {
			// Retarget rotation: apply rest-pose correction
			// Use fresh quaternions per track to avoid mutation issues
			const restRotInv = new Quaternion();
			const parentRestWorld = new Quaternion();

			mixamoRigNode.getWorldQuaternion(restRotInv).invert();
			if (mixamoRigNode.parent) {
				mixamoRigNode.parent.getWorldQuaternion(parentRestWorld);
			}

			const values = new Float32Array(track.values.length);
			for (let i = 0; i < track.values.length; i += 4) {
				_quatA.fromArray(track.values, i);

				// parent rest world rotation × track rotation × rest rotation inverse
				_quatA.premultiply(parentRestWorld).multiply(restRotInv);

				_quatA.toArray(values, i);
			}

			// VRM 0.x uses a different coordinate system — flip X and Z
			if (isVrm0) {
				for (let i = 0; i < values.length; i += 4) {
					values[i] = -values[i];     // x
					// values[i+1] unchanged     // y
					values[i + 2] = -values[i + 2]; // z
					// values[i+3] unchanged     // w
				}
			}

			tracks.push(
				new QuaternionKeyframeTrack(
					`${vrmNodeName}.${propertyName}`,
					track.times as unknown as Float32Array,
					values,
				)
			);
		} else if (track instanceof VectorKeyframeTrack) {
			// Retarget position: scale by hip height ratio
			const values = new Float32Array(track.values.length);
			for (let i = 0; i < track.values.length; i++) {
				values[i] = track.values[i] * hipsPositionScale;
			}

			// VRM 0.x coordinate flip — negate X and Z
			if (isVrm0) {
				for (let i = 0; i < values.length; i += 3) {
					values[i] = -values[i];         // x
					// values[i+1] unchanged         // y
					values[i + 2] = -values[i + 2]; // z
				}
			}

			tracks.push(
				new VectorKeyframeTrack(
					`${vrmNodeName}.${propertyName}`,
					track.times as unknown as Float32Array,
					values,
				)
			);
		}
	}

	console.info(`  Retargeted: ${matchedTracks} matched, ${unmatchedBones} unmatched, ${tracks.length} output tracks`);

	return new AnimationClip(clipName, clip.duration, tracks);
}

/**
 * Load a native VRM Animation (.vrma) file and create an AnimationClip for the given VRM.
 *
 * Uses @pixiv/three-vrm-animation's `createVRMAnimationClip` which handles
 * humanoid bone mapping natively — no manual retargeting needed.
 *
 * @param url Path to a `.vrma` file
 * @param vrm The target VRM model
 * @param clipName Name for the resulting AnimationClip
 * @returns AnimationClip ready for use with AnimationMixer on vrm.scene
 */
export async function loadVrmaAnimation(
	url: string,
	vrm: VRM,
	clipName: string,
): Promise<AnimationClip> {
	const gltf = await gltfLoader.loadAsync(url);
	const vrmAnimations = gltf.userData.vrmAnimations as Array<{ createAnimationClip?: (vrm: VRM) => AnimationClip }> | undefined;

	if (!vrmAnimations?.length) {
		throw new Error(`[VrmAnimRetarget] No VRM animations found in ${url}`);
	}

	const clip = createVRMAnimationClip(vrmAnimations[0] as any, vrm);
	clip.name = clipName;
	return clip;
}

/**
 * Load an animation clip from any supported format and apply it to a VRM.
 *
 * Auto-detects format by file extension:
 * - `.vrma` → native VRM Animation (best quality, no retargeting needed)
 * - `.fbx` → Mixamo FBX with retargeting
 * - `.glb` / `.gltf` → Mixamo GLB with retargeting
 *
 * @param url Path to the animation file
 * @param vrm The target VRM model
 * @param clipName Name for the resulting AnimationClip
 */
export async function loadAnimation(
	url: string,
	vrm: VRM,
	clipName: string,
): Promise<AnimationClip> {
	const ext = url.split(".").pop()?.toLowerCase() ?? "";

	if (ext === "vrma") {
		return loadVrmaAnimation(url, vrm, clipName);
	}

	return loadMixamoAnimation(url, vrm, clipName);
}
