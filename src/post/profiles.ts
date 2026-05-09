/**
 * S4-06 — Post-processing profiles.
 *
 * Named render profiles are intentionally neutral while tone mapping and
 * post-processing are disabled. Keep this module so scenes can continue to
 * request a profile without reintroducing hidden exposure changes.
 */
import * as THREE from "three";

export type PostProfileId = "cinematic" | "interior" | "exterior";

export interface PostProfile {
	id: PostProfileId;
	toneMapping: THREE.ToneMapping;
	exposure: number;
	/** Bloom strength when EffectComposer is active. 0 = disabled. */
	bloomStrength: number;
	/** Vignette darkening at frame edges (0–1). 0 = disabled. */
	vignette: number;
}

const PROFILES: Record<PostProfileId, PostProfile> = {
	cinematic: {
		id: "cinematic",
		toneMapping: THREE.NoToneMapping,
		exposure: 1,
		bloomStrength: 0,
		vignette: 0,
	},
	interior: {
		id: "interior",
		toneMapping: THREE.NoToneMapping,
		exposure: 1,
		bloomStrength: 0,
		vignette: 0,
	},
	exterior: {
		id: "exterior",
		toneMapping: THREE.NoToneMapping,
		exposure: 1,
		bloomStrength: 0,
		vignette: 0,
	},
};

export const getPostProfile = (id: PostProfileId): PostProfile => PROFILES[id];

/**
 * Apply a post profile to the renderer. Returns a `restore()` function
 * the caller's `dispose` can invoke. While post is disabled, both apply and
 * restore force the renderer back to the neutral baseline.
 */
export const applyPostProfile = (
	renderer: { toneMapping: THREE.ToneMapping; toneMappingExposure: number },
	id: PostProfileId,
): () => void => {
	const profile = PROFILES[id];
	renderer.toneMapping = profile.toneMapping;
	renderer.toneMappingExposure = profile.exposure;
	return () => {
		renderer.toneMapping = THREE.NoToneMapping;
		renderer.toneMappingExposure = 1;
	};
};
