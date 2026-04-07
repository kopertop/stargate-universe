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
import { loadMixamoAnimation } from "./vrm-animation-retarget";

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
};

type AnimState = "locomotion" | "jump";

// ─── Constants ─────────────────────────────────────────────────────────────────

/** Speed below which the character is considered idle. */
const IDLE_THRESHOLD = 0.1;

/** Crossfade duration into jump (seconds). */
const JUMP_FADE_IN = 0.15;

/** Crossfade duration from jump back to locomotion (seconds). */
const JUMP_FADE_OUT = 0.25;

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

	private state: AnimState = "locomotion";
	private loaded = false;
	private loading = false;

	// Smooth weight targets
	private idleWeight = 1;
	private walkWeight = 0;
	private runWeight = 0;

	constructor(vrm: VRM) {
		this.vrm = vrm;
		this.mixer = new AnimationMixer(vrm.scene);
	}

	/**
	 * Load animation clips from FBX files at the given base path.
	 * Expects: `{basePath}/idle.fbx`, `walk.fbx`, `run.fbx`, `jump.fbx`
	 *
	 * Also supports .glb extensions. Files that fail to load are skipped
	 * gracefully — the character will hold T-pose for missing clips.
	 */
	async loadClips(basePath: string): Promise<void> {
		if (this.loading || this.loaded) return;
		this.loading = true;

		const clipDefs = [
			{ name: "idle", file: "idle.fbx" },
			{ name: "walk", file: "walk.fbx" },
			{ name: "run", file: "run.fbx" },
			{ name: "jump", file: "jump.fbx" },
		] as const;

		const results = await Promise.allSettled(
			clipDefs.map(async (def) => {
				const url = resolveAssetUrl(`${basePath}/${def.file}`);
				const clip = await loadMixamoAnimation(url, this.vrm, def.name);
				return { name: def.name, clip };
			})
		);

		for (const result of results) {
			if (result.status !== "fulfilled") {
				console.warn("[VrmPlayerAnimController] Failed to load clip:", result.reason);
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

		const loadedCount = results.filter((r) => r.status === "fulfilled").length;
		console.info(`[VrmPlayerAnimController] Loaded ${loadedCount}/${clipDefs.length} animation clips`);
	}

	/**
	 * Update animations each frame. Call before `vrm.update()` so spring bones
	 * simulate on top of the animated pose.
	 */
	update(delta: number, params: PlayerAnimationParams): void {
		if (!this.loaded) return;

		if (this.state === "locomotion") {
			this.updateLocomotionWeights(delta, params);

			// Check for jump trigger
			if (params.jumpTriggered && this.jumpAction) {
				this.triggerJump();
			}
		} else if (this.state === "jump") {
			// Auto-return to locomotion when grounded and jump animation done
			if (params.isGrounded && this.jumpAction && !this.jumpAction.isRunning()) {
				this.returnToLocomotion();
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

	private updateLocomotionWeights(delta: number, params: PlayerAnimationParams): void {
		const { speed, walkSpeed, runSpeed } = params;
		const smoothing = 1 - Math.exp(-WEIGHT_SMOOTHING * delta);

		// Compute target weights based on speed
		let targetIdle = 0;
		let targetWalk = 0;
		let targetRun = 0;

		if (speed < IDLE_THRESHOLD) {
			targetIdle = 1;
		} else if (speed <= walkSpeed) {
			// Blend idle → walk
			const t = speed / Math.max(walkSpeed, 0.01);
			targetIdle = 1 - t;
			targetWalk = t;
		} else if (speed <= runSpeed) {
			// Blend walk → run
			const t = (speed - walkSpeed) / Math.max(runSpeed - walkSpeed, 0.01);
			targetWalk = 1 - t;
			targetRun = t;
		} else {
			targetRun = 1;
		}

		// Smooth toward targets
		this.idleWeight += (targetIdle - this.idleWeight) * smoothing;
		this.walkWeight += (targetWalk - this.walkWeight) * smoothing;
		this.runWeight += (targetRun - this.runWeight) * smoothing;

		// Apply weights
		this.idleAction?.setEffectiveWeight(this.idleWeight);
		this.walkAction?.setEffectiveWeight(this.walkWeight);
		this.runAction?.setEffectiveWeight(this.runWeight);
	}

	private triggerJump(): void {
		if (!this.jumpAction) return;

		this.state = "jump";

		// Fade out locomotion
		this.idleAction?.fadeOut(JUMP_FADE_IN);
		this.walkAction?.fadeOut(JUMP_FADE_IN);
		this.runAction?.fadeOut(JUMP_FADE_IN);

		// Play jump from start
		this.jumpAction.reset();
		this.jumpAction.setEffectiveWeight(1);
		this.jumpAction.fadeIn(JUMP_FADE_IN);
		this.jumpAction.play();
	}

	private returnToLocomotion(): void {
		this.state = "locomotion";

		// Fade jump out
		this.jumpAction?.fadeOut(JUMP_FADE_OUT);

		// Fade locomotion back in
		this.idleAction?.reset().fadeIn(JUMP_FADE_OUT).play();
		this.walkAction?.reset().fadeIn(JUMP_FADE_OUT).play();
		this.runAction?.reset().fadeIn(JUMP_FADE_OUT).play();

		// Reset weights to current targets (will be smoothed next frame)
		this.idleAction?.setEffectiveWeight(this.idleWeight);
		this.walkAction?.setEffectiveWeight(this.walkWeight);
		this.runAction?.setEffectiveWeight(this.runWeight);
	}
}
