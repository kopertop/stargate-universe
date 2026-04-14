/**
 * CinematicCamera — reusable camera controller for scripted sequences.
 *
 * Provides named presets (`set('overhead', target)`) and utility methods
 * (`shake()`, `lookAt()`, `lerp()`) so cinematic scripts stay readable
 * instead of juggling raw Vector3 math.
 *
 * Usage:
 *   const cc = new CinematicCamera(camera);
 *   cc.set('overhead', gateCenter);        // top-down centered on the gate
 *   cc.shake(0.3, 0.85);                   // impact shake
 *   cc.lerpTo(posB, lookB, 0.4, 'smooth'); // 40% through a transition
 */
import * as THREE from "three";

export type EasingMode = "linear" | "ease-in" | "ease-out" | "smooth";

/** Named camera presets. `target` adjusts the lookAt / offset center. */
export type CameraPreset =
	| "overhead"       // top-down centered on target
	| "establishing"   // wide, elevated, looking at target from +Z
	| "low-angle"      // floor-level, looking up at target
	| "closeup"        // tight on target from slight offset
	| "pov";           // first-person at target position

/** Smoothstep (Hermite) interpolation. */
function smoothstep(t: number): number {
	return t * t * (3 - 2 * t);
}

function applyEasing(t: number, mode: EasingMode): number {
	switch (mode) {
		case "ease-in":  return t * t;
		case "ease-out": return 1 - (1 - t) * (1 - t);
		case "smooth":   return smoothstep(t);
		default:         return t;
	}
}

// Scratch vectors to avoid per-frame allocation
const _shakeVec = new THREE.Vector3();
const _lerpPos  = new THREE.Vector3();

export class CinematicCamera {
	private camera: THREE.PerspectiveCamera;
	private shakeIntensity = 0;
	private shakeDecay = 0.85;
	private shakeOffset = new THREE.Vector3();

	constructor(camera: THREE.PerspectiveCamera) {
		this.camera = camera;
	}

	// ── Presets ──────────────────────────────────────────────────────────

	/**
	 * Snap camera to a named preset centered on `target`.
	 *
	 * @param preset  Named camera position / angle.
	 * @param target  World-space point to frame (default origin).
	 * @param opts    Override height / distance / lookAt offset per preset.
	 */
	set(
		preset: CameraPreset,
		target: THREE.Vector3 = new THREE.Vector3(),
		opts: { height?: number; distance?: number; lookAtOffset?: THREE.Vector3 } = {},
	): void {
		const lookTarget = opts.lookAtOffset
			? new THREE.Vector3().copy(target).add(opts.lookAtOffset)
			: target;

		switch (preset) {
			case "overhead": {
				const h = opts.height ?? 14;
				const d = opts.distance ?? 0;
				this.camera.position.set(target.x, target.y + h, target.z + d);
				this.camera.lookAt(lookTarget);
				break;
			}
			case "establishing": {
				const h = opts.height ?? 6;
				const d = opts.distance ?? 22;
				this.camera.position.set(target.x, target.y + h, target.z + d);
				this.camera.lookAt(lookTarget);
				break;
			}
			case "low-angle": {
				const h = opts.height ?? 0.6;
				const d = opts.distance ?? 4;
				this.camera.position.set(target.x + 1, target.y + h, target.z + d);
				this.camera.lookAt(lookTarget);
				break;
			}
			case "closeup": {
				const d = opts.distance ?? 2;
				this.camera.position.set(target.x + d * 0.3, target.y + 0.2, target.z + d);
				this.camera.lookAt(lookTarget);
				break;
			}
			case "pov": {
				this.camera.position.copy(target);
				if (opts.lookAtOffset) this.camera.lookAt(lookTarget);
				break;
			}
		}
	}

	// ── Interpolated movement ────────────────────────────────────────────

	/**
	 * Interpolate camera between two positions + lookAt targets.
	 *
	 * @param from      Start position.
	 * @param to        End position.
	 * @param lookAt    Where the camera points throughout.
	 * @param t         Progress 0→1 (unclamped OK — will be clamped).
	 * @param easing    Easing curve applied to `t`.
	 */
	lerpTo(
		from: THREE.Vector3,
		to: THREE.Vector3,
		lookAt: THREE.Vector3,
		t: number,
		easing: EasingMode = "linear",
	): void {
		const et = applyEasing(Math.min(1, Math.max(0, t)), easing);
		_lerpPos.lerpVectors(from, to, et);
		// Apply accumulated shake offset
		if (this.shakeIntensity > 0.001) {
			_lerpPos.add(this.shakeOffset);
		}
		this.camera.position.copy(_lerpPos);
		this.camera.lookAt(lookAt);
	}

	// ── Shake ────────────────────────────────────────────────────────────

	/**
	 * Trigger a camera shake. Subsequent `updateShake()` calls decay it.
	 *
	 * @param intensity  Peak displacement in world units (0.1 = subtle, 0.5 = heavy impact).
	 * @param decay      Per-tick multiplier (0.85 = fast decay, 0.95 = lingering).
	 */
	shake(intensity: number, decay = 0.85): void {
		this.shakeIntensity = Math.max(this.shakeIntensity, intensity);
		this.shakeDecay = decay;
	}

	/**
	 * Advance the shake simulation. Call once per frame BEFORE lerpTo().
	 * Also kills shake if explicitly requested (e.g. during calm establishing shots).
	 */
	updateShake(): void {
		if (this.shakeIntensity > 0.001) {
			_shakeVec.set(
				(Math.random() - 0.5) * this.shakeIntensity,
				(Math.random() - 0.5) * this.shakeIntensity,
				(Math.random() - 0.5) * this.shakeIntensity,
			);
			this.shakeOffset.copy(_shakeVec);
			this.shakeIntensity *= this.shakeDecay;
		} else {
			this.shakeOffset.set(0, 0, 0);
			this.shakeIntensity = 0;
		}
	}

	/** Hard-kill any active shake (use during calm establishing shots). */
	killShake(): void {
		this.shakeIntensity = 0;
		this.shakeOffset.set(0, 0, 0);
	}

	/** Current shake intensity (read-only, for conditionals). */
	get currentShakeIntensity(): number {
		return this.shakeIntensity;
	}

	// ── Direct access ────────────────────────────────────────────────────

	/** The underlying Three.js camera (escape hatch for one-offs). */
	get raw(): THREE.PerspectiveCamera {
		return this.camera;
	}
}
