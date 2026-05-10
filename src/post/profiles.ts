/**
 * S4-06 — Post-processing profiles.
 *
 * Named render profiles tuned to match the concept-art references.
 *
 * On WebGPU renderer, tone mapping + exposure are the available controls.
 * Vignette is applied via a DOM overlay in pipeline.ts.
 */
import * as THREE from "three";
import type { PostPipeline } from "./pipeline";
import { getPostPipeline } from "./state";

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
		// NoToneMapping gives direct pixel control — essential for a dark
		// scene where hand-placed emissive accents must read crisply.
		toneMapping: THREE.NoToneMapping,
		// Exposure kept at 1 because NoToneMapping ignores this field.
		exposure: 1,
		bloomStrength: 0,
		vignette: 0.30,
	},
	interior: {
		id: "interior",
		toneMapping: THREE.NoToneMapping,
		exposure: 1,
		bloomStrength: 0,
		vignette: 0.25,
	},
	exterior: {
		id: "exterior",
		toneMapping: THREE.NoToneMapping,
		exposure: 1,
		bloomStrength: 0,
		vignette: 0.15,
	},
};

export const getPostProfile = (id: PostProfileId): PostProfile => PROFILES[id];

/**
 * Apply a post profile to the active renderer / pipeline.
 *
 * If a {@link PostPipeline} is active (EffectComposer), its passes are
 * updated with the profile settings. The renderer's tone mapping fields
 * are always set as a fallback for raw-render mode.
 *
 * Returns a `restore()` function that reverts both the renderer fields
 * and, if a pipeline was active, reverts the pipeline to its prior profile.
 */
export const applyPostProfile = (
	renderer: { toneMapping: THREE.ToneMapping; toneMappingExposure: number },
	id: PostProfileId,
): (() => void) => {
	const profile = PROFILES[id];
	const prevToneMapping = renderer.toneMapping;
	const prevExposure = renderer.toneMappingExposure;

	renderer.toneMapping = profile.toneMapping;
	renderer.toneMappingExposure = profile.exposure;

	const pipeline = getPostPipeline();
	if (pipeline) {
		pipeline.applyProfile(profile);
	}

	return () => {
		renderer.toneMapping = prevToneMapping;
		renderer.toneMappingExposure = prevExposure;
		if (pipeline) {
			pipeline.applyProfile({ toneMapping: prevToneMapping, exposure: prevExposure, bloomStrength: 0, vignette: 0, id: "exterior" });
		}
	};
};
