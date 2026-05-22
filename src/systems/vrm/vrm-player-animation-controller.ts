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
import { VrmIdleVariantCycle } from "./vrm-idle-variant-cycle";

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

/** Locomotion blend while jump clip plays (lower = clearer jump pose). */
const JUMP_LOCOMOTION_BLEND = 0.05;

/** Playback rate for in-place jump clip (~1s source). */
const JUMP_TIME_SCALE = 1.35;

/** Crossfade duration into repair (seconds). */
const REPAIR_FADE_IN = 0.4;

/** Crossfade duration from repair back to locomotion (seconds). */
const REPAIR_FADE_OUT = 0.35;

/** Weight smoothing factor — higher = snappier, lower = smoother. */
const WEIGHT_SMOOTHING = 8.0;

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
	/** Mixamo "Getting Up" — plays once, cinematic wake-up, LoopOnce. */
	private gettingUpAction: AnimationAction | undefined;
	/** Resolves when the getting-up clip finishes and we've returned to idle. */
	private gettingUpDone: (() => void) | undefined;

	private idleVariantCycle: VrmIdleVariantCycle | undefined;
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
	/** True when at least one lateral strafe clip loaded (optional assets). */
	private hasStrafeClips = false;

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
	async loadClips(
		basePath: string,
		options?: { readonly gender?: "male" | "female" },
	): Promise<void> {
		if (this.loading || this.loaded) return;
		this.loading = true;

		// Each entry is the canonical clip name plus filename aliases tried in
		// order. Aliases let us reuse Mixamo-style filenames (e.g.
		// `walking-forward.glb`) without renaming
		// assets on disk or in R2.
		const clipSpecs = [
			{
				name: "idle",
				aliases: [
					"eli-idle",
					"idle",
					"standing-short-idle",
					"Relax",
				],
			},
			{
				name: "walk",
				aliases: [
					"eli-walk",
					"cc0-locomotion/CC0-walk",
					"CC0-walk",
					"walk",
					"walking-forward",
					"walking",
				],
			},
			{
				name: "run",
				aliases: [
					"eli-run",
					"cc0-locomotion/CC0-run",
					"cc0-locomotion/CC0-slowrun",
					"CC0-run",
					"CC0-slowrun",
					"run",
					"running",
					"running-forward",
				],
			},
			{
				name: "jump",
				aliases: ["eli-jump", "Jump", "jump", "jumping", "standing-jump"],
			},
			{
				name: "strafe-left",
				aliases: ["eli-strafe-left", "strafe-left", "strafe-walk-left"],
			},
			{
				name: "strafe-right",
				aliases: ["eli-strafe-right", "strafe-right", "strafe-walk-right"],
			},
			{ name: "repair", aliases: ["repair", "interaction"] },
			{ name: "getting-up", aliases: ["getting-up", "stand-up"] },
		] as const;
		const extensions = ["vrma", "glb", "fbx"];

		const results = await Promise.allSettled(
			clipSpecs.map(async (spec) => {
				for (const alias of spec.aliases) {
				for (const ext of extensions) {
						try {
							const url = resolveAssetUrl(`${basePath}/${alias}.${ext}`);
							const clip = await loadAnimation(url, this.vrm, spec.name);
							return { name: spec.name, clip };
						} catch {
							// Try next alias / extension
						}
					}
				}
				throw new Error(`No animation file found for "${spec.name}" at ${basePath}`);
			})
		);

		for (const result of results) {
			if (result.status !== "fulfilled") {
				// Optional clips not on disk yet (e.g. run, jump, repair) — character
				// just falls back to loaded clips. Keep this below warn-level so
				// browser smoke checks don't report expected missing optional clips.
				console.debug("[VrmPlayerAnimController] Skipping missing optional clip:", String(result.reason));
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
					action.timeScale = JUMP_TIME_SCALE;
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
					action.timeScale = 1.4;
					action.play();
					action.setEffectiveWeight(0);
					break;

				case "strafe-right":
					this.strafeRightAction = action;
					action.setLoop(LoopRepeat, Infinity);
					action.timeScale = 1.4;
					action.play();
					action.setEffectiveWeight(0);
					break;

				case "getting-up":
					this.gettingUpAction = action;
					action.setLoop(LoopOnce, 1);
					action.clampWhenFinished = true;
					// Don't play until startGettingUp() — stay at bind pose.
					break;
			}
		}

		// Listen for jump / get-up animation to finish
		this.mixer.addEventListener("finished", (e) => {
			if (e.action === this.jumpAction) {
				this.returnToLocomotion();
			} else if (e.action === this.gettingUpAction) {
				// Return to idle weight; release the waiting caller.
				if (this.idleAction) this.idleAction.setEffectiveWeight(1);
				if (this.gettingUpAction) this.gettingUpAction.setEffectiveWeight(0);
				const cb = this.gettingUpDone;
				this.gettingUpDone = undefined;
				cb?.();
			}
		});

		this.hasStrafeClips = Boolean(this.strafeLeftAction || this.strafeRightAction);
		this.loaded = true;
		this.loading = false;
		if (!this.idleAction) {
			console.warn(
				"[VrmPlayerAnimController] No idle clip — locomotion may be walk-only until clips load",
			);
		} else {
			this.idleVariantCycle = new VrmIdleVariantCycle({
				gender: options?.gender ?? "male",
				vrm: this.vrm,
				baseIdleAction: this.idleAction,
				getBaseIdleWeight: () => this.idleWeight,
			});
			void this.idleVariantCycle.load();
		}
	}

	/**
	 * Update animations each frame. Call after `vrm.update()` (see
	 * character-loader.ts: vrm.update → mixer.update).
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
				this.idleVariantCycle?.update(delta);
			} else if (nowIdling && !this.isIdling) {
				this.isIdling = true;
				this.idleVariantCycle?.enterIdle();
			} else if (!nowIdling && this.isIdling) {
				this.isIdling = false;
				this.idleVariantCycle?.leaveIdle();
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
			// Land → locomotion; also finish if the one-shot clip ends in air (edge case).
			if (
				params.isGrounded ||
				(this.jumpAction && !this.jumpAction.isRunning())
			) {
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

	/**
	 * Freeze / unfreeze the animation mixer. Use while the player is in
	 * a manually-posed state (prone, sitting, custom rig) so the idle
	 * loop doesn't compound with the manual pose and cause spinning.
	 */
	setPaused(paused: boolean): void {
		this.mixer.timeScale = paused ? 0 : 1;
	}

	/**
	 * Pose the character in the first frame of the "getting up"
	 * animation — supine (lying on back). Useful for the cinematic
	 * wake-up. Pair with `finishGettingUp()` to play the clip forward
	 * when the player hits a movement key.
	 *
	 * @returns true if the clip is available and was cued, false
	 *          otherwise (clip not loaded → caller should fall back).
	 */
	startGettingUp(): boolean {
		if (!this.gettingUpAction) return false;
		// Suppress idle so the supine pose reads cleanly.
		this.idleAction?.setEffectiveWeight(0);
		// Pin the action to frame 0 and let the mixer keep it posed.
		// Setting timeScale=0 stops time for everything else too; set
		// action.paused = true to freeze just this action.
		this.gettingUpAction.reset();
		this.gettingUpAction.play();
		this.gettingUpAction.setEffectiveWeight(1);
		this.gettingUpAction.paused = true;
		// Mixer must be running for the pose to render. Explicitly
		// unpause in case a prior setPaused(true) froze the whole thing.
		this.mixer.timeScale = 1;
		return true;
	}

	/**
	 * Resume playing the cued "getting up" animation. Returns a
	 * promise that resolves when the clip finishes (and idle has
	 * taken back over). Slow playback multiplier available for
	 * "groggy" wake-up feel.
	 */
	finishGettingUp(speed = 1): Promise<void> {
		if (!this.gettingUpAction) return Promise.resolve();
		this.gettingUpAction.paused = false;
		this.gettingUpAction.timeScale = speed;
		return new Promise<void>((resolve) => {
			// Timer safety — if finished event never fires (e.g. missing
			// clip binding), resolve after the nominal clip duration.
			const safetyMs = ((this.gettingUpAction?.getClip().duration ?? 2) / Math.max(0.1, speed)) * 1000 + 500;
			const safetyTimer = setTimeout(() => {
				this.gettingUpDone = undefined;
				resolve();
			}, safetyMs);
			this.gettingUpDone = () => { clearTimeout(safetyTimer); resolve(); };
		});
	}

	/** Clean up mixer and all actions. */
	dispose(): void {
		this.idleVariantCycle?.dispose();
		this.idleVariantCycle = undefined;
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

		if (isStrafing && this.hasStrafeClips) {
			// Dedicated lateral clips (works even when speed is near-zero from input alone)
			if (strafeInput < 0) {
				targetStrafeLeft = strafeAmount;
				targetIdle = 1 - strafeAmount;
			} else {
				targetStrafeRight = strafeAmount;
				targetIdle = 1 - strafeAmount;
			}
		} else if (speed < IDLE_THRESHOLD) {
			targetIdle = 1;
		} else if (isStrafing) {
			// No lateral clips: walk/run by speed while mesh faces velocity (see player controller).
			if (speed <= walkSpeed) {
				const t = speed / Math.max(walkSpeed, 0.01);
				targetIdle = 1 - t;
				targetWalk = t;
			} else if (speed <= runSpeed) {
				const t = (speed - walkSpeed) / Math.max(runSpeed - walkSpeed, 0.01);
				targetWalk = 1 - t;
				targetRun = t;
			} else {
				targetRun = 1;
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
		this.idleVariantCycle?.leaveIdle();

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
		if (this.isIdling) {
			this.idleVariantCycle?.enterIdle();
		}
	}

	/** Whether a locomotion idle clip was loaded (voidborne always boots into idle). */
	hasIdleClip(): boolean {
		return Boolean(this.idleAction);
	}
}
