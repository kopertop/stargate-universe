/**
 * VRM LookAt Controller — manages gaze direction for VRM characters.
 *
 * Supports three modes:
 * - **camera**: Eyes track the active camera (crew NPCs looking at player)
 * - **target**: Eyes track a specific world position (dialogue partner)
 * - **manual**: Direct yaw/pitch control for cutscene choreography
 *
 * Integrates with VRM's built-in `VRMLookAt` system which supports both
 * bone-based and expression-based eye movement.
 *
 * @see design/gdd/vrm-model-integration.md §Detailed Rules > Interactions
 */
import type { VRM } from "@pixiv/three-vrm";
import { Object3D, Vector3 } from "three";

// ─── Types ──────────────────────────────────────────────────────────────────

export type LookAtMode = "camera" | "target" | "manual" | "none";

export type LookAtState = {
	mode: LookAtMode;
	/** World-space target position (used when mode is "target"). */
	targetPosition: Vector3;
	/** Manual yaw/pitch in degrees (used when mode is "manual"). */
	manualYaw: number;
	manualPitch: number;
	/** Blend speed for transitioning between targets (higher = faster). */
	blendSpeed: number;
};

// ─── Controller ─────────────────────────────────────────────────────────────

export class VrmLookAtController {
	private readonly vrm: VRM;
	private readonly state: LookAtState;
	private readonly scratchTarget = new Vector3();
	private enabled = true;

	constructor(vrm: VRM) {
		this.vrm = vrm;
		this.state = {
			mode: "none",
			targetPosition: new Vector3(),
			manualYaw: 0,
			manualPitch: 0,
			blendSpeed: 6.0,
		};

		// Disable VRM's auto-update — we drive lookAt manually
		if (this.vrm.lookAt) {
			this.vrm.lookAt.autoUpdate = false;
		}
	}

	// ─── Public API ───────────────────────────────────────────────────────────

	/**
	 * Set gaze to track the camera. Common for crew NPCs in dialogue.
	 * Pass the camera object so the controller can extract its world position.
	 */
	lookAtCamera(camera: Object3D): void {
		this.state.mode = "camera";
		camera.getWorldPosition(this.state.targetPosition);
	}

	/**
	 * Set gaze to track a specific world position.
	 * Used for NPCs looking at objects, doors, consoles, etc.
	 */
	lookAtPosition(position: Vector3): void {
		this.state.mode = "target";
		this.state.targetPosition.copy(position);
	}

	/**
	 * Set gaze via direct yaw/pitch in degrees.
	 * Used for cutscene choreography.
	 */
	lookAtDirection(yaw: number, pitch: number): void {
		this.state.mode = "manual";
		this.state.manualYaw = yaw;
		this.state.manualPitch = pitch;
	}

	/** Release gaze — eyes return to forward. */
	clearLookAt(): void {
		this.state.mode = "none";
	}

	/** Set the blend speed for gaze transitions. */
	setBlendSpeed(speed: number): void {
		this.state.blendSpeed = Math.max(0.1, speed);
	}

	/** Enable or disable the lookAt system (used by LOD). */
	setEnabled(enabled: boolean): void {
		this.enabled = enabled;

		if (!enabled && this.vrm.lookAt) {
			this.vrm.lookAt.reset();
		}
	}

	/**
	 * Update gaze direction. Call once per frame after VRM pose is applied.
	 * @param delta Frame delta in seconds
	 * @param camera The active camera (if mode is "camera", used to get position)
	 */
	update(delta: number, camera?: Object3D): void {
		if (!this.enabled || !this.vrm.lookAt) return;

		switch (this.state.mode) {
			case "camera": {
				if (camera) {
					camera.getWorldPosition(this.scratchTarget);
					this.vrm.lookAt.lookAt(this.scratchTarget);
				}
				break;
			}
			case "target": {
				this.vrm.lookAt.lookAt(this.state.targetPosition);
				break;
			}
			case "manual": {
				this.vrm.lookAt.yaw = this.state.manualYaw;
				this.vrm.lookAt.pitch = this.state.manualPitch;
				break;
			}
			case "none": {
				// Blend back to forward gaze
				const currentYaw = this.vrm.lookAt.yaw;
				const currentPitch = this.vrm.lookAt.pitch;

				if (Math.abs(currentYaw) > 0.01 || Math.abs(currentPitch) > 0.01) {
					const t = 1 - Math.exp(-delta * this.state.blendSpeed);
					this.vrm.lookAt.yaw = currentYaw * (1 - t);
					this.vrm.lookAt.pitch = currentPitch * (1 - t);
				}
				break;
			}
		}

		// Manually trigger the lookAt update since we disabled autoUpdate
		this.vrm.lookAt.update(delta);
	}
}
