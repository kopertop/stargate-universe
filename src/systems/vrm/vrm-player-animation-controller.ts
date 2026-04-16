/**
 * VRM Player Animation Controller — drives idle/walk/run/jump animations
 * on the player's VRM character using Three.js AnimationMixer.
 *
 * Uses speed-based weight blending for locomotion (idle/walk/run) and
 * crossfade transitions for jump.
 *
 * Animation clips are loaded from Mixamo FBX files on R2, retargeted to the
 * VRM skeleton at load time via vrm-animation-retarget.ts.
 *
 * @see src/systems/vrm/vrm-animation-retarget.ts
 */
import type { VRM } from "@pixiv/three-vrm";
import {
	AnimationAction,
	AnimationMixer,
	LoopOnce,
	LoopRepeat,
} from "three";

import { resolveAssetUrl } from "../asset-resolver";
import { loadAnimation } from "./vrm-animation-retarget";

function randomRange(min: number, max: number): number {
	return min + Math.random() * (max - min);
}

// ─── Types ─────────────────────────────────────────────────────────────────────

/** Parameters passed from the player controller each frame. */
export type PlayerAnimationParams = {
	/** Current horizontal movement speed (m/s). */
	readonly speed: number;
	/** Configured walking speed from scene settings. */
	readonly walkSpeed: number;
	/** Configured running speed from scene settings. */
	readonly runSpeed: number;
	/** Whether the character is on the ground. */
	readonly isGrounded: boolean;
	/** Whether a jump was just triggered (ground lock active). */
	readonly jumpTriggered: boolean;
	/** Lateral movement input: -1 = left, 0 = none, 1 = right. */
	readonly strafeInput: number;
	/** Forward movement input: -1 = backward, 0 = none, 1 = forward. */
	readonly forwardInput: number;
	/** Whether the player is currently performing a repair action. */
	readonly isRepairing: boolean;
};

type AnimState = "locomotion" | "jump" | "repair";

// ─── Constants ─────────────────────────────────────────────────────────────────

/** Speed below which the character is considered idle. */
const IDLE_THRESHOLD = 0.1;

/** Crossfade duration into jump (seconds). */
const JUMP_FADE_IN = 0.15;

/** Crossfade duration from jump back to locomotion (seconds). */
const JUMP_FADE_OUT = 0.25;

/** How much locomotion blends through during a jump (0 = none, 1 = full). */
const JUMP_LOCOMOTION_BLEND = 0.5;

/** Crossfade duration into repair (seconds). */
const REPAIR_FADE_IN = 0.4;

/** Crossfade duration from repair back to locomotion (seconds). */
const REPAIR_FADE_OUT = 0.35;

/** Weight smoothing factor — higher = snappier, lower = smoother. */
const WEIGHT_SMOOTHING = 8.0;

/** Minimum seconds between idle variant cycles. */
const IDLE_VARIANT_MIN_INTERVAL = 8.0;

/** Maximum seconds between idle variant cycles. */
const IDLE_VARIANT_MAX_INTERVAL = 20.0;

/** Crossfade duration for idle variant transitions. */
const IDLE_VARIANT_FADE = 0.5;

/** Idle variant filenames (loaded from R2 alongside core clips). */
const IDLE_VARIANTS = [
	"breathing-idle",
	"happy-idle",
	"sad-idle",
	"warrior-idle",
	"idle-variant-1",
	"idle-variant-2",
	"idle-variant-3",
	"neutral-idle",
	"idle-looking-behind",
	"idle-standing",
	"idle-happy",
	"idle-standing-02",
] as const;

// ─── Controller ────────────────────────────────────────────────────────────────

export class VrmPlayerAnimationController {
	private readonly vrm: VRM;
	private readonly mixer: AnimationMixer;

	private idleAction: AnimationAction | undefined;
	private walkAction: AnimationAction | undefined;
	private runAction: AnimationAction | undefined;
	private jumpAction: AnimationAction | undefined;
	private repairAction: AnimationAction | undefined;
	private strafeLeftAction: AnimationAction | undefined;
	private strafeRightAction: AnimationAction | undefined;

	/** Pool of idle variant actions for cycling. */
	private idleVariants: AnimationAction[] = [];
	/** Currently playing idle variant (or undefined = default idle). */
	private activeIdleVariant: AnimationAction | undefined;
	/** Countdown until next idle variant switch. */
	private idleVariantTimer = 0;
	/** Whether we're currently in idle (for variant cycling). */
	private isIdling = false;

	private state: AnimState = "locomotion";
	private loaded = false;
	private loading = false;

	// Smooth weight targets
	private idleWeight = 1;
	private walkWeight = 0;
	private runWeight = 0;
	private strafeLeftWeight = 0;
	private strafeRightWeight = 0;

	constructor(vrm: VRM) {
		this.vrm = vrm;
		this.mixer = new AnimationMixer(vrm.scene);
	}

	/**
	 * Load animation clips from the given base path.
	 *
	 * Tries multiple formats per clip in order of preference:
	 * 1. `.vrma` — native VRM Animation (best compatibility)
	 * 2. `.fbx` — Mixamo FBX (retargeted automatically)
	 * 3. `.glb` — Mixamo GLB (retargeted automatically)
	 *
	 * Files that fail to load are skipped gracefully — the character will
	 * hold T-pose for missing clips.
	 */
	async loadClips(basePath: string): Promise<void> {
		if (this.loading || this.loaded) return;
		this.loading = true;

		const clipNames = ["idle", "walk", "run", "jump", "strafe-left", "strafe-right", "repair"] as const;
		const extensions = ["fbx", "glb", "vrma"];

		const results = await Promise.allSettled(
			clipNames.map(async (name) => {
				// Try each extension until one succeeds
				for (const ext of extensions) {
					try {
						const url = resolveAssetUrl(`${basePath}/${name}.${ext}`);
						const clip = await loadAnimation(url, this.vrm, name);
						return { name, clip };
					} catch {
						// Try next extension
					}
				}
				throw new Error(`No animation file found for "${name}" at ${basePath}`);
			})
		);

		for (const result of results) {
			if (result.status !== "fulfilled") {
				console.error("[VrmPlayerAnimController] Failed to load clip:", result.reason);
				continue;
			}

			const { name, clip } = result.value;
			const action = this.mixer.clipAction(clip);

			switch (name) {
				case "idle":
					this.idleAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.play();
					action.setEffectiveWeight(1);
					break;

				case "walk":
					this.walkAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.play();
					action.setEffectiveWeight(0);
					break;

				case "run":
					this.runAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.play();
					action.setEffectiveWeight(0);
					break;

				case "jump":
					this.jumpAction = action;
					action.setLoop(LoopOnce, 1);
					action.clampWhenFinished = true;
					// Don't play until triggered
					break;

				case "repair":
					this.repairAction = action;
					action.setLoop(LoopRepeat, Infinity);
					// Don't play until triggered
					break;

				case "strafe-left":
					this.strafeLeftAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.play();
					action.setEffectiveWeight(0);
					break;

				case "strafe-right":
					this.strafeRightAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.play();
					action.setEffectiveWeight(0);
					break;
			}
		}

		// Listen for jump animation to finish
		this.mixer.addEventListener("finished", (e) => {
			if (e.action === this.jumpAction) {
				this.returnToLocomotion();
			}
		});

		this.loaded = true;
		this.loading = false;
		this.resetIdleVariantTimer();

		const loadedCount = results.filter((r) => r.status === "fulfilled").length;

		// Load idle variants in the background (non-blocking, optional)
		this.loadIdleVariants(basePath);
	}

	/** Load idle variant clips asynchronously. Failures are silently ignored. */
	private async loadIdleVariants(basePath: string): Promise<void> {
		const extensions = ["fbx", "glb", "vrma"];

		for (const variantName of IDLE_VARIANTS) {
			for (const ext of extensions) {
				try {
					const url = resolveAssetUrl(`${basePath}/${variantName}.${ext}`);
					const clip = await loadAnimation(url, this.vrm, variantName);
					const action = this.mixer.clipAction(clip);
					action.setLoop(LoopRepeat, Infinity);
					// Don't play yet — will crossfade in when cycled
					this.idleVariants.push(action);
					break; // Found this variant, move to next
				} catch {
					// Try next extension
				}
			}
		}

		if (this.idleVariants.length > 0) {
			// Idle variants ready
		}
	}

	/**
	 * Update animations each frame. Call before `vrm.update()` so spring bones
	 * simulate on top of the animated pose.
	 */
	update(delta: number, params: PlayerAnimationParams): void {
		if (!this.loaded) return;

		// Always update locomotion weights — during jump they blend at reduced strength
		const locoScale = this.state === "jump" ? JUMP_LOCOMOTION_BLEND : this.state === "repair" ? 0 : 1;
		this.updateLocomotionWeights(delta, params, locoScale);

		if (this.state === "locomotion") {
			// Track idle state for variant cycling
			const nowIdling = params.speed < IDLE_THRESHOLD;
			if (nowIdling && this.isIdling) {
				this.updateIdleVariantCycle(delta);
			} else if (nowIdling && !this.isIdling) {
				// Just entered idle — reset timer and return to default idle
				this.isIdling = true;
				this.resetIdleVariantTimer();
				this.returnToDefaultIdle();
			} else if (!nowIdling && this.isIdling) {
				// Left idle — return to default idle immediately
				this.isIdling = false;
				this.returnToDefaultIdle();
			}

			// Check for jump trigger
			if (params.jumpTriggered && this.jumpAction) {
				this.triggerJump();
			}

			// Check for repair start
			if (params.isRepairing && this.repairAction) {
				this.triggerRepair();
			}
		} else if (this.state === "jump") {
			// Auto-return to locomotion when grounded and jump animation done
			if (params.isGrounded && this.jumpAction && !this.jumpAction.isRunning()) {
				this.returnToLocomotion();
			}
		} else if (this.state === "repair") {
			// Return to locomotion when repair ends
			if (!params.isRepairing) {
				this.endRepair();
			}
		}

		this.mixer.update(delta);
	}

	/** Clean up mixer and all actions. */
	dispose(): void {
		this.mixer.stopAllAction();
		this.mixer.uncacheRoot(this.vrm.scene);
	}

	// ─── Internal ──────────────────────────────────────────────────────────────

	private updateLocomotionWeights(delta: number, params: PlayerAnimationParams, scale = 1): void {
		const { speed, walkSpeed, runSpeed, strafeInput, forwardInput } = params;
		const smoothing = 1 - Math.exp(-WEIGHT_SMOOTHING * delta);

		// Determine if purely strafing (lateral movement without forward/back)
		const isStrafing = Math.abs(strafeInput) > 0.1 && Math.abs(forwardInput) < 0.1;
		const strafeAmount = Math.abs(strafeInput);

		// Compute target weights based on speed and direction
		let targetIdle = 0;
		let targetWalk = 0;
		let targetRun = 0;
		let targetStrafeLeft = 0;
		let targetStrafeRight = 0;

		if (speed < IDLE_THRESHOLD) {
			targetIdle = 1;
		} else if (isStrafing) {
			// Pure strafe — use strafe animations
			if (strafeInput < 0) {
				targetStrafeLeft = strafeAmount;
				targetIdle = 1 - strafeAmount;
			} else {
				targetStrafeRight = strafeAmount;
				targetIdle = 1 - strafeAmount;
			}
		} else if (speed <= walkSpeed) {
			// Blend idle → walk (with partial strafe blending for diagonal movement)
			const t = speed / Math.max(walkSpeed, 0.01);
			targetIdle = 1 - t;
			targetWalk = t * (1 - strafeAmount * 0.5);
			if (strafeInput < -0.1) targetStrafeLeft = t * strafeAmount * 0.5;
			if (strafeInput > 0.1) targetStrafeRight = t * strafeAmount * 0.5;
		} else if (speed <= runSpeed) {
			// Blend walk → run
			const t = (speed - walkSpeed) / Math.max(runSpeed - walkSpeed, 0.01);
			targetWalk = 1 - t;
			targetRun = t;
		} else {
			targetRun = 1;
		}

		// Apply scale (reduced during jump so locomotion shows through at partial weight)
		targetIdle *= scale;
		targetWalk *= scale;
		targetRun *= scale;
		targetStrafeLeft *= scale;
		targetStrafeRight *= scale;

		// Smooth toward targets
		this.idleWeight += (targetIdle - this.idleWeight) * smoothing;
		this.walkWeight += (targetWalk - this.walkWeight) * smoothing;
		this.runWeight += (targetRun - this.runWeight) * smoothing;
		this.strafeLeftWeight += (targetStrafeLeft - this.strafeLeftWeight) * smoothing;
		this.strafeRightWeight += (targetStrafeRight - this.strafeRightWeight) * smoothing;

		// Apply weights
		this.idleAction?.setEffectiveWeight(this.idleWeight);
		this.walkAction?.setEffectiveWeight(this.walkWeight);
		this.runAction?.setEffectiveWeight(this.runWeight);
		this.strafeLeftAction?.setEffectiveWeight(this.strafeLeftWeight);
		this.strafeRightAction?.setEffectiveWeight(this.strafeRightWeight);
	}

	private triggerJump(): void {
		if (!this.jumpAction) return;

		this.state = "jump";

		// Don't fade out locomotion — updateLocomotionWeights will scale them
		// down via JUMP_LOCOMOTION_BLEND, keeping directional movement visible.

		// Play jump from start
		this.jumpAction.reset();
		this.jumpAction.setEffectiveWeight(1);
		this.jumpAction.fadeIn(JUMP_FADE_IN);
		this.jumpAction.play();
	}

	private returnToLocomotion(): void {
		this.state = "locomotion";

		// Fade jump out — locomotion weights will ramp back to full (scale=1)
		// naturally on the next updateLocomotionWeights call
		this.jumpAction?.fadeOut(JUMP_FADE_OUT);
	}

	private triggerRepair(): void {
		if (!this.repairAction) return;

		this.state = "repair";

		// Fade out locomotion and idle variants
		this.idleAction?.fadeOut(REPAIR_FADE_IN);
		this.walkAction?.fadeOut(REPAIR_FADE_IN);
		this.runAction?.fadeOut(REPAIR_FADE_IN);
		this.strafeLeftAction?.fadeOut(REPAIR_FADE_IN);
		this.strafeRightAction?.fadeOut(REPAIR_FADE_IN);
		this.returnToDefaultIdle();

		// Play repair loop
		this.repairAction.reset();
		this.repairAction.setEffectiveWeight(1);
		this.repairAction.fadeIn(REPAIR_FADE_IN);
		this.repairAction.play();
	}

	private endRepair(): void {
		this.state = "locomotion";

		// Fade repair out, restore locomotion
		this.repairAction?.fadeOut(REPAIR_FADE_OUT);

		this.idleAction?.reset().fadeIn(REPAIR_FADE_OUT).play();
		this.walkAction?.reset().fadeIn(REPAIR_FADE_OUT).play();
		this.runAction?.reset().fadeIn(REPAIR_FADE_OUT).play();
		this.strafeLeftAction?.reset().fadeIn(REPAIR_FADE_OUT).play();
		this.strafeRightAction?.reset().fadeIn(REPAIR_FADE_OUT).play();
	}

	// ─── Idle Variant Cycling ──────────────────────────────────────────────────

	private resetIdleVariantTimer(): void {
		this.idleVariantTimer = randomRange(IDLE_VARIANT_MIN_INTERVAL, IDLE_VARIANT_MAX_INTERVAL);
	}

	private updateIdleVariantCycle(delta: number): void {
		if (this.idleVariants.length === 0) return;

		this.idleVariantTimer -= delta;
		if (this.idleVariantTimer > 0) return;

		// Time to switch!
		this.resetIdleVariantTimer();

		if (this.activeIdleVariant) {
			// Currently playing a variant — return to default idle
			this.returnToDefaultIdle();
		} else {
			// Currently on default idle — pick a random variant
			this.playRandomIdleVariant();
		}
	}

	private playRandomIdleVariant(): void {
		if (this.idleVariants.length === 0) return;

		const variant = this.idleVariants[Math.floor(Math.random() * this.idleVariants.length)];
		if (!variant) return;

		// Crossfade default idle out, variant in
		this.idleAction?.fadeOut(IDLE_VARIANT_FADE);
		variant.reset().fadeIn(IDLE_VARIANT_FADE).play();
		variant.setEffectiveWeight(1);

		this.activeIdleVariant = variant;
	}

	private returnToDefaultIdle(): void {
		if (this.activeIdleVariant) {
			this.activeIdleVariant.fadeOut(IDLE_VARIANT_FADE);
			this.activeIdleVariant = undefined;
		}

		if (this.idleAction) {
			this.idleAction.reset().fadeIn(IDLE_VARIANT_FADE).play();
			this.idleAction.setEffectiveWeight(this.idleWeight);
		}
	}
}
