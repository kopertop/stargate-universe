/**
 * VRM Clip Retargeter — remaps animation track bone names between skeletons.
 *
 * When animation clips are authored against a Mixamo skeleton (bone names like
 * "mixamorigHips") but need to play on a VRM skeleton (bone names like "hips"),
 * this module remaps the track names so the clips target the correct bones.
 *
 * @see design/gdd/vrm-model-integration.md §Retargeting
 */
import { AnimationClip, KeyframeTrack } from "three";
import { MIXAMO_TO_VRM_BONE_MAP } from "./vrm-bone-map";

/**
 * Create a copy of an AnimationClip with track names remapped from source
 * skeleton naming to VRM humanoid naming.
 *
 * Track names in Three.js follow the pattern: `boneName.property`
 * (e.g., `mixamorigHips.position`, `mixamorigSpine.quaternion`).
 *
 * @param clip           Source animation clip (not mutated)
 * @param sourceNameMap  Mapping from source bone names to VRM bone names.
 *                       Defaults to MIXAMO_TO_VRM_BONE_MAP.
 * @returns              New clip with remapped track names
 */
export function retargetClipToVrmSkeleton(
	clip: AnimationClip,
	sourceNameMap: ReadonlyMap<string, string> = MIXAMO_TO_VRM_BONE_MAP,
): AnimationClip {
	const remappedTracks: KeyframeTrack[] = [];

	for (const track of clip.tracks) {
		const dotIndex = track.name.lastIndexOf(".");

		if (dotIndex === -1) {
			// No property suffix — keep as-is
			remappedTracks.push(track.clone());
			continue;
		}

		const boneName = track.name.substring(0, dotIndex);
		const property = track.name.substring(dotIndex);
		const vrmBoneName = sourceNameMap.get(boneName);

		if (vrmBoneName) {
			const cloned = track.clone();
			cloned.name = `${vrmBoneName}${property}`;
			remappedTracks.push(cloned);
		} else {
			// No mapping found — keep original name (may match if already VRM naming)
			remappedTracks.push(track.clone());
		}
	}

	return new AnimationClip(clip.name, clip.duration, remappedTracks, clip.blendMode);
}
