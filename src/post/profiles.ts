/**
 * S4-06 — Post-processing profiles.
 *
 * Centralizes per-scene rendering knobs (tone mapping curve, exposure,
 * future bloom/vignette params) so scenes ask for a *named look* rather
 * than poking renderer.toneMappingExposure ad-hoc.
 *
 * Add a new look here, not in the scene module. If scenes diverge from
 * these three profiles, that's a signal we need a new profile, not a
 * one-off override. Bloom/vignette are stubs today — they activate once
 * the EffectComposer pipeline lands; until then the values are passive
 * and ignored, but profile authors should still set them to the value
 * we want when bloom is wired up.
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
	// Wide dynamic range for hero shots — high exposure pushes Destiny's
	// metal hull bright against deep-space black. Used by the opening
	// cinematic and any space-set scene.
	cinematic: {
		id: "cinematic",
		toneMapping: THREE.ACESFilmicToneMapping,
		exposure: 3.9,
		bloomStrength: 0.6,
		vignette: 0.25,
	},
	// Interiors of the ship — lower exposure so emergency lighting reads
	// dim and Ancient cabling glow stays a controlled accent rather than
	// blowing out walls. Gate-room and corridor pull this profile.
	interior: {
		id: "interior",
		toneMapping: THREE.ACESFilmicToneMapping,
		exposure: 2.2,
		bloomStrength: 0.35,
		vignette: 0.35,
	},
	// Planet surfaces / open exteriors — neutral exposure, lighter
	// vignette, more bloom headroom for sky glare and sun discs.
	exterior: {
		id: "exterior",
		toneMapping: THREE.ACESFilmicToneMapping,
		exposure: 1.15,
		bloomStrength: 0.45,
		vignette: 0.15,
	},
};

export const getPostProfile = (id: PostProfileId): PostProfile => PROFILES[id];

interface PostRestoreState {
	toneMapping: THREE.ToneMapping;
	toneMappingExposure: number;
}

/**
 * Apply a post profile to the renderer. Returns a `restore()` function
 * the caller's `dispose` should invoke to put the renderer back to its
 * prior state — this matters because scene transitions reuse the same
 * renderer and the next scene's profile will only re-apply on mount.
 */
export const applyPostProfile = (
	renderer: { toneMapping: THREE.ToneMapping; toneMappingExposure: number },
	id: PostProfileId,
): () => void => {
	const prior: PostRestoreState = {
		toneMapping: renderer.toneMapping,
		toneMappingExposure: renderer.toneMappingExposure,
	};
	const profile = PROFILES[id];
	renderer.toneMapping = profile.toneMapping;
	renderer.toneMappingExposure = profile.exposure;
	return () => {
		renderer.toneMapping = prior.toneMapping;
		renderer.toneMappingExposure = prior.toneMappingExposure;
	};
};
