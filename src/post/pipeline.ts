/**
 * S4-06 — Post-processing pipeline (WebGPU-native).
 *
 * Since this project uses WebGPURenderer (even with forceWebGL,
 * EffectComposer is incompatible because it relies on ShaderMaterial).
 * Instead, we implement:
 *  - Tone mapping + exposure (renderer-level, always works)
 *  - Vignette via DOM overlay (lightweight, always visible)
 *  - Bloom via increased emissive intensity on key materials
 *
 * If we ever switch to pure WebGLRenderer, EffectComposer can be restored.
 */
import * as THREE from "three";
import type { PostProfile } from "./profiles";

export type PostPipeline = {
	/** Apply a profile to the renderer. */
	applyProfile: (profile: PostProfile) => void;
	/** True if tone mapping is active (profile ≠ NoToneMapping). */
	isActive: () => boolean;
	/** Update vignette overlay darkness. 0 = remove. */
	setVignette: (value: number) => void;
};

let vignetteEl: HTMLDivElement | null = null;

function ensureVignetteOverlay(): HTMLDivElement {
	if (vignetteEl) return vignetteEl;
	const el = document.createElement("div");
	el.id = "post-vignette";
	el.style.position = "fixed";
	el.style.inset = "0";
	el.style.pointerEvents = "none";
	el.style.zIndex = "2"; // above canvas, below menus
	el.style.transition = "opacity 0.4s ease";
	document.body.appendChild(el);
	vignetteEl = el;
	return el;
}

function updateVignetteOverlay(darkness: number): void {
	const el = vignetteEl ?? ensureVignetteOverlay();
	if (darkness <= 0) {
		el.style.opacity = "0";
		return;
	}
	el.style.background = `radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,0,0,${darkness}) 100%)`;
	el.style.opacity = "1";
}

export function createPostPipeline(
	renderer: { toneMapping: THREE.ToneMapping; toneMappingExposure: number },
): PostPipeline {
	return {
		applyProfile(profile: PostProfile) {
			renderer.toneMapping = profile.toneMapping;
			renderer.toneMappingExposure = profile.exposure;
			updateVignetteOverlay(profile.vignette);
		},
		isActive() {
			return renderer.toneMapping !== THREE.NoToneMapping;
		},
		setVignette(value: number) {
			updateVignetteOverlay(value);
		},
	};
}

/** Called during app dispose to clean up the vignette overlay. */
export function disposePostPipeline(): void {
	if (vignetteEl) {
		vignetteEl.remove();
		vignetteEl = null;
	}
}
