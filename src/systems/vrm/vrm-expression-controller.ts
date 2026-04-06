/**
 * VRM Expression Controller — manages facial expressions and viseme lip sync.
 *
 * Provides smooth blending between expressions, automatic blink cycles,
 * and viseme-driven lip sync for dialogue scenes. Each VRM character gets
 * its own `VrmExpressionController` instance.
 *
 * @see design/gdd/vrm-model-integration.md §Detailed Rules > Expression / Blend Shape System
 */
import type { VRM } from "@pixiv/three-vrm";
import { getVrmConfig } from "./vrm-config";

// ─── Types ──────────────────────────────────────────────────────────────────

/** Standard VRM expression preset names. */
export type VrmExpressionName =
	| "happy"
	| "angry"
	| "sad"
	| "surprised"
	| "relaxed"
	| "neutral";

/** Standard VRM viseme names for lip sync. */
export type VrmVisemeName = "aa" | "ih" | "ou" | "ee" | "oh";

export type ExpressionTarget = {
	readonly name: string;
	readonly weight: number;
};

// ─── Controller ─────────────────────────────────────────────────────────────

export class VrmExpressionController {
	private readonly vrm: VRM;

	/** Current expression target (what we're blending toward). */
	private currentExpression: ExpressionTarget = { name: "neutral", weight: 0 };

	/** Active expression weights being interpolated. */
	private readonly activeWeights = new Map<string, number>();

	/** Current viseme target. */
	private currentViseme: ExpressionTarget = { name: "aa", weight: 0 };

	/** Active viseme weight. */
	private activeVisemeWeight = 0;
	private activeVisemeName = "";

	/** Blink state. */
	private blinkTimer: number;
	private blinkActive = false;
	private blinkElapsed = 0;

	/** Whether this controller is active (near LOD). */
	private enabled = true;

	constructor(vrm: VRM) {
		this.vrm = vrm;
		this.blinkTimer = this.nextBlinkDelay();
	}

	// ─── Public API ───────────────────────────────────────────────────────────

	/**
	 * Set the target expression. Blends smoothly from current to target.
	 * @param name   Expression preset name or custom expression name
	 * @param weight Target weight (0–1)
	 */
	setExpression(name: string, weight: number): void {
		// If changing expression, fade out the old one
		if (this.currentExpression.name !== name && this.currentExpression.weight > 0) {
			this.activeWeights.set(
				this.currentExpression.name,
				this.activeWeights.get(this.currentExpression.name) ?? 0
			);
		}

		this.currentExpression = { name, weight: Math.max(0, Math.min(1, weight)) };
	}

	/**
	 * Set the active viseme for lip sync.
	 * @param name   Viseme name (aa, ih, ou, ee, oh)
	 * @param weight Viseme intensity (0–1)
	 */
	setViseme(name: VrmVisemeName | string, weight: number): void {
		this.currentViseme = { name, weight: Math.max(0, Math.min(1, weight)) };
	}

	/** Clear all visemes (silence). */
	clearViseme(): void {
		this.currentViseme = { name: "", weight: 0 };
	}

	/** Enable or disable expression updates (used by LOD system). */
	setEnabled(enabled: boolean): void {
		this.enabled = enabled;

		if (!enabled) {
			this.resetAll();
		}
	}

	/**
	 * Update expression blending and blink cycle. Call once per frame.
	 * @param delta Frame delta in seconds
	 */
	update(delta: number): void {
		if (!this.enabled || !this.vrm.expressionManager) return;

		const config = getVrmConfig().expression;

		this.updateBlink(delta, config.blinkDuration);
		this.updateExpressionBlend(delta, config.blendSpeed);
		this.updateVisemeBlend(delta, config.visemeBlendSpeed);
	}

	// ─── Internal ─────────────────────────────────────────────────────────────

	private updateExpressionBlend(delta: number, blendSpeed: number): void {
		const mgr = this.vrm.expressionManager;
		if (!mgr) return;

		// Blend current expression toward target
		const targetName = this.currentExpression.name;
		const targetWeight = this.currentExpression.weight;

		// Ensure current expression is tracked
		if (targetName && targetWeight > 0) {
			this.activeWeights.set(targetName, this.activeWeights.get(targetName) ?? 0);
		}

		// Interpolate all active expressions
		const toRemove: string[] = [];

		for (const [name, currentWeight] of this.activeWeights) {
			const target = name === targetName ? targetWeight : 0;
			const newWeight = expLerp(currentWeight, target, delta, blendSpeed);

			if (newWeight < 0.001 && target === 0) {
				toRemove.push(name);
				mgr.setValue(name, 0);
			} else {
				this.activeWeights.set(name, newWeight);
				mgr.setValue(name, newWeight);
			}
		}

		for (const name of toRemove) {
			this.activeWeights.delete(name);
		}
	}

	private updateVisemeBlend(delta: number, blendSpeed: number): void {
		const mgr = this.vrm.expressionManager;
		if (!mgr) return;

		const targetName = this.currentViseme.name;
		const targetWeight = this.currentViseme.weight;

		// Fade out old viseme if it changed
		if (this.activeVisemeName && this.activeVisemeName !== targetName) {
			const fadeOut = expLerp(this.activeVisemeWeight, 0, delta, blendSpeed);

			if (fadeOut < 0.001) {
				mgr.setValue(this.activeVisemeName, 0);
				this.activeVisemeWeight = 0;
				this.activeVisemeName = "";
			} else {
				mgr.setValue(this.activeVisemeName, fadeOut);
				this.activeVisemeWeight = fadeOut;
				return; // Wait for fade-out before starting new viseme
			}
		}

		// Blend toward target viseme
		if (targetName && targetWeight > 0) {
			this.activeVisemeName = targetName;
			this.activeVisemeWeight = expLerp(this.activeVisemeWeight, targetWeight, delta, blendSpeed);
			mgr.setValue(targetName, this.activeVisemeWeight);
		} else if (this.activeVisemeName) {
			this.activeVisemeWeight = expLerp(this.activeVisemeWeight, 0, delta, blendSpeed);

			if (this.activeVisemeWeight < 0.001) {
				mgr.setValue(this.activeVisemeName, 0);
				this.activeVisemeName = "";
				this.activeVisemeWeight = 0;
			} else {
				mgr.setValue(this.activeVisemeName, this.activeVisemeWeight);
			}
		}
	}

	private updateBlink(delta: number, blinkDuration: number): void {
		const mgr = this.vrm.expressionManager;
		if (!mgr) return;

		if (this.blinkActive) {
			this.blinkElapsed += delta;
			const halfDuration = blinkDuration / 2;

			if (this.blinkElapsed < halfDuration) {
				// Closing
				mgr.setValue("blink", this.blinkElapsed / halfDuration);
			} else if (this.blinkElapsed < blinkDuration) {
				// Opening
				mgr.setValue("blink", 1 - (this.blinkElapsed - halfDuration) / halfDuration);
			} else {
				// Done
				mgr.setValue("blink", 0);
				this.blinkActive = false;
				this.blinkElapsed = 0;
				this.blinkTimer = this.nextBlinkDelay();
			}
		} else {
			this.blinkTimer -= delta;

			if (this.blinkTimer <= 0) {
				this.blinkActive = true;
				this.blinkElapsed = 0;
			}
		}
	}

	private nextBlinkDelay(): number {
		const config = getVrmConfig().expression;
		return config.blinkBaseInterval + Math.random() * config.blinkVariance;
	}

	private resetAll(): void {
		const mgr = this.vrm.expressionManager;
		if (!mgr) return;

		mgr.resetValues();
		this.activeWeights.clear();
		this.activeVisemeWeight = 0;
		this.activeVisemeName = "";
	}
}

// ─── Math Helpers ───────────────────────────────────────────────────────────

/**
 * Exponential interpolation — smooth, frame-rate independent blending.
 * `speed` controls how fast we approach target (higher = faster).
 */
function expLerp(current: number, target: number, delta: number, speed: number): number {
	return target + (current - target) * Math.exp(-delta / Math.max(0.001, speed));
}
