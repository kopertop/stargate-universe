/**
 * Gender-aware idle variant cycling — crossfades base idle with VRMA emotes.
 *
 * Male: alternates Look Around ↔ Thinking on each variant beat.
 * Female: occasional Model Pose (VRoid VRMA_06) between female-idle holds.
 */
import type { VRM } from "@pixiv/three-vrm";
import { AnimationAction, LoopRepeat } from "three";

import { resolveAssetUrl } from "../asset-resolver";
import { loadAnimation } from "./vrm-animation-retarget";

const ANIMATIONS_BASE = "/assets/animations";

const MALE_VARIANT_FILES = [
	"tk256-emotes/LookAround.vrma",
	"tk256-emotes/Thinking.vrma",
] as const;

const FEMALE_VARIANT_FILE = "vroid-motion-pack/vrma/VRMA_06.vrma";

/** Minimum seconds between idle variant cycles. */
export const IDLE_VARIANT_MIN_INTERVAL = 8.0;

/** Maximum seconds between idle variant cycles. */
export const IDLE_VARIANT_MAX_INTERVAL = 20.0;

/** Crossfade duration for idle variant transitions (seconds). */
export const IDLE_VARIANT_FADE = 0.5;

/** Chance a female idle beat plays model pose instead of extending base idle. */
const FEMALE_MODEL_POSE_CHANCE = 0.4;

function randomRange(min: number, max: number): number {
	return min + Math.random() * (max - min);
}

export type VrmIdleVariantCycleOptions = {
	readonly gender: "male" | "female";
	readonly vrm: VRM;
	readonly baseIdleAction: AnimationAction;
	readonly getBaseIdleWeight: () => number;
};

export class VrmIdleVariantCycle {
	private readonly gender: "male" | "female";
	private readonly vrm: VRM;
	private readonly baseIdleAction: AnimationAction;
	private readonly getBaseIdleWeight: () => number;

	private variantActions: AnimationAction[] = [];
	private activeVariant: AnimationAction | undefined;
	private idleVariantTimer = 0;
	private isIdling = false;
	private maleVariantIndex = 0;
	private loaded = false;

	constructor(options: VrmIdleVariantCycleOptions) {
		this.gender = options.gender;
		this.vrm = options.vrm;
		this.baseIdleAction = options.baseIdleAction;
		this.getBaseIdleWeight = options.getBaseIdleWeight;
	}

	async load(): Promise<void> {
		const files =
			this.gender === "male"
				? MALE_VARIANT_FILES
				: ([FEMALE_VARIANT_FILE] as const);

		for (const file of files) {
			try {
				const url = resolveAssetUrl(`${ANIMATIONS_BASE}/${file}`);
				const clip = await loadAnimation(url, this.vrm, file);
				const action = this.baseIdleAction.getMixer().clipAction(clip);
				action.setLoop(LoopRepeat, Infinity);
				this.variantActions.push(action);
			} catch {
				// Variant clips are optional — base idle still works.
			}
		}

		this.loaded = true;
	}

	get hasVariants(): boolean {
		return this.variantActions.length > 0;
	}

	enterIdle(): void {
		this.isIdling = true;
		this.resetIdleVariantTimer();
		this.returnToDefaultIdle();
	}

	leaveIdle(): void {
		this.isIdling = false;
		this.returnToDefaultIdle();
	}

	update(delta: number): void {
		if (!this.loaded || !this.isIdling || this.variantActions.length === 0) return;

		this.idleVariantTimer -= delta;
		if (this.idleVariantTimer > 0) return;

		this.resetIdleVariantTimer();

		if (this.activeVariant) {
			this.returnToDefaultIdle();
			return;
		}

		this.playNextVariant();
	}

	dispose(): void {
		this.leaveIdle();
		this.variantActions = [];
		this.loaded = false;
	}

	private resetIdleVariantTimer(): void {
		this.idleVariantTimer = randomRange(IDLE_VARIANT_MIN_INTERVAL, IDLE_VARIANT_MAX_INTERVAL);
	}

	private playNextVariant(): void {
		if (this.gender === "female") {
			if (Math.random() >= FEMALE_MODEL_POSE_CHANCE) {
				return;
			}
		}

		const variant = this.pickNextVariant();
		if (!variant) return;

		this.baseIdleAction.fadeOut(IDLE_VARIANT_FADE);
		variant.reset().fadeIn(IDLE_VARIANT_FADE).play();
		variant.setEffectiveWeight(1);
		this.activeVariant = variant;
	}

	private pickNextVariant(): AnimationAction | undefined {
		if (this.variantActions.length === 0) return undefined;

		if (this.gender === "male") {
			const variant = this.variantActions[this.maleVariantIndex];
			this.maleVariantIndex = (this.maleVariantIndex + 1) % this.variantActions.length;
			return variant;
		}

		return this.variantActions[0];
	}

	private returnToDefaultIdle(): void {
		if (this.activeVariant) {
			this.activeVariant.fadeOut(IDLE_VARIANT_FADE);
			this.activeVariant = undefined;
		}

		this.baseIdleAction.reset().fadeIn(IDLE_VARIANT_FADE).play();
		this.baseIdleAction.setEffectiveWeight(this.getBaseIdleWeight());
	}
}
