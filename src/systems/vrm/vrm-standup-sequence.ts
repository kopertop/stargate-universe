/**
 * VRM Stand-Up Sequence
 *
 * Procedural 6-phase "recover from being thrown through a wormhole" animation,
 * driving VRM humanoid bones directly.
 *
 *   Phase  Time     Pose
 *   A      0.0-1.0s face-down prone (hold)
 *   B      1.0-2.5s push up onto hands and knees
 *   C      2.5-3.5s rise to kneeling upright
 *   D      3.5-4.3s hands raise to head ("where am I?")
 *   E      4.3-5.3s head shake (disoriented)
 *   F      5.3-6.8s arms drop, legs extend — character stands
 *
 * This is the fallback for when Mixamo "Getting Up" assets aren't available.
 * See `public/assets/animations/README.md` for the Mixamo upgrade path:
 * when the named clips exist, prefer the retargeted Mixamo pipeline via
 * {@link loadMixamoAnimation} — it's always higher quality than procedural.
 *
 * Drive the sequence by calling `update(delta)` each frame. It writes to
 * `char.root.rotation` (for gross prone→upright tilt) and to VRM humanoid
 * bone quaternions (for the limb choreography). Call `dispose()` to reset.
 */
import * as THREE from "three";
import type { VRM, VRMHumanBoneName } from "@pixiv/three-vrm";
import type { CharacterLoadResult } from "../../characters/character-loader";

// ─── Bone pose keyframes ──────────────────────────────────────────────────────
// Each keyframe specifies *Euler angles* for each bone (XYZ order). We convert
// to quaternions at runtime and slerp. A missing bone = rest pose (identity
// quaternion). Root rotation is a world-space X rotation applied to the
// outer group, separate from the bone poses.

type BoneEulers = Partial<Record<VRMHumanBoneName, [number, number, number]>>;

interface PoseKeyframe {
	t: number;              // seconds from sequence start
	rootRotationX: number;  // char.root.rotation.x (outer group tilt)
	bones: BoneEulers;
}

const P = Math.PI;

// Push-up pose: on hands and knees, elbows bent, hips flexed, knees at 90°.
const PUSHUP_BONES: BoneEulers = {
	leftUpperArm:  [0, 0,  P / 3],   // arm down+forward
	rightUpperArm: [0, 0, -P / 3],
	leftLowerArm:  [0, 0, -P / 2.5], // elbow bent
	rightLowerArm: [0, 0,  P / 2.5],
	leftUpperLeg:  [-P / 3, 0, 0],   // hip flexed (knee forward)
	rightUpperLeg: [-P / 3, 0, 0],
	leftLowerLeg:  [ P / 2, 0, 0],   // knee bent 90°
	rightLowerLeg: [ P / 2, 0, 0],
	spine:         [-P / 6, 0, 0],   // slight back arch
};

// Kneeling upright: hips flex so knees are planted on ground, torso vertical.
const KNEEL_BONES: BoneEulers = {
	leftUpperLeg:  [-P / 2, 0, 0],   // hip fully flexed
	rightUpperLeg: [-P / 2, 0, 0],
	leftLowerLeg:  [ P / 2, 0, 0],   // knee bent 90°
	rightLowerLeg: [ P / 2, 0, 0],
	leftUpperArm:  [0, 0, 0],        // arms down at sides
	rightUpperArm: [0, 0, 0],
	leftLowerArm:  [0, 0, 0],
	rightLowerArm: [0, 0, 0],
	spine:         [0, 0, 0],
};

// Hands-on-head: shoulders abducted 90°, elbows folded so forearms point up,
// hands near top of head. Legs still kneeling.
const HANDS_ON_HEAD_BONES: BoneEulers = {
	leftUpperLeg:  [-P / 2, 0, 0],
	rightUpperLeg: [-P / 2, 0, 0],
	leftLowerLeg:  [ P / 2, 0, 0],
	rightLowerLeg: [ P / 2, 0, 0],
	leftUpperArm:  [0, 0,  P * 0.55], // raise arm out to side
	rightUpperArm: [0, 0, -P * 0.55],
	leftLowerArm:  [0, -P * 0.8, 0],  // fold forearm toward head
	rightLowerArm: [0,  P * 0.8, 0],
	spine:         [0, 0, 0],
};

// Standing: rest pose. Root rotation back to 0. All bones identity.
const STAND_BONES: BoneEulers = {};

// Full keyframe timeline. Positions are in outer-group local frame; root
// rotation handles the prone→upright flop.
const KEYFRAMES: PoseKeyframe[] = [
	{ t: 0.0, rootRotationX: -P / 2, bones: {} },                       // prone (rest pose limbs)
	{ t: 1.0, rootRotationX: -P / 2, bones: {} },                       // hold prone
	{ t: 2.5, rootRotationX: -P / 4, bones: PUSHUP_BONES },              // push up
	{ t: 3.5, rootRotationX:  0,     bones: KNEEL_BONES },               // kneel upright
	{ t: 4.3, rootRotationX:  0,     bones: HANDS_ON_HEAD_BONES },       // hands on head
	{ t: 5.3, rootRotationX:  0,     bones: HANDS_ON_HEAD_BONES },       // (hold during head-shake phase)
	{ t: 6.8, rootRotationX:  0,     bones: STAND_BONES },               // fully standing
];

const SHAKE_WINDOW = { start: 4.3, end: 5.3 };
const SHAKE_AMPLITUDE = 0.35;  // radians — moderate head turn
const SHAKE_FREQUENCY = 7.0;   // Hz — ~3.5 full cycles over 1s window

const SEQUENCE_DURATION = KEYFRAMES[KEYFRAMES.length - 1].t;

// ─── Bone-quaternion cache ────────────────────────────────────────────────────
// We convert the Euler keyframes to quaternions once per sequence to avoid
// per-frame allocation. The CACHE map stores keyframe-index → bone → quat.

const _tmpEuler = new THREE.Euler();
const _srcQ = new THREE.Quaternion();
const _dstQ = new THREE.Quaternion();
const _outQ = new THREE.Quaternion();

// ─── Public API ───────────────────────────────────────────────────────────────

export interface StandupSequenceOptions {
	/** Uniform time scaling. 1.0 = 6.8s total. 0.7 = 4.8s (faster recovery). */
	pacing?: number;
	/** Seconds of "prone hold" before the push-up starts. Default 1.0. */
	proneHold?: number;
	/** Onfinish callback — fires once the sequence completes. */
	onComplete?: () => void;
}

export interface StandupSequence {
	/** Advance the sequence. Safe to call even after completion (no-op). */
	update(deltaSeconds: number): void;
	/** True when the character has reached the final standing pose. */
	readonly isDone: boolean;
	/** Reset any bone poses we touched and stop driving the character. */
	dispose(): void;
}

/**
 * Build the bone-euler table for this instance (copies KEYFRAMES so proneHold
 * offsets all subsequent keyframes).
 */
function buildTimeline(proneHold: number): PoseKeyframe[] {
	const shift = Math.max(0, proneHold - 1.0); // default prone hold = 1.0s
	return KEYFRAMES.map((kf, idx) => ({
		...kf,
		t: idx === 0 ? 0 : kf.t + shift,
	}));
}

/**
 * Interpolate between two keyframes. `alpha` is the normalized [0,1]
 * progress between `a.t` and `b.t`. Applies root rotation + bone quaternions
 * to `char`.
 */
function applyInterpolated(
	char: CharacterLoadResult,
	vrm: VRM,
	a: PoseKeyframe,
	b: PoseKeyframe,
	alpha: number,
): void {
	// Root rotation — linear lerp (slerp of quaternion around X axis gives
	// same result since it's one axis).
	char.root.rotation.x = a.rootRotationX + (b.rootRotationX - a.rootRotationX) * alpha;
	char.root.rotation.z = 0;

	// Bone quaternions. Every bone mentioned in either keyframe is tweened.
	const bones = new Set<VRMHumanBoneName>();
	for (const k of Object.keys(a.bones) as VRMHumanBoneName[]) bones.add(k);
	for (const k of Object.keys(b.bones) as VRMHumanBoneName[]) bones.add(k);

	for (const boneName of bones) {
		const node = vrm.humanoid.getNormalizedBoneNode(boneName);
		if (!node) continue;

		const eulerA = a.bones[boneName];
		const eulerB = b.bones[boneName];

		if (eulerA) _srcQ.setFromEuler(_tmpEuler.set(eulerA[0], eulerA[1], eulerA[2])); else _srcQ.identity();
		if (eulerB) _dstQ.setFromEuler(_tmpEuler.set(eulerB[0], eulerB[1], eulerB[2])); else _dstQ.identity();

		_outQ.copy(_srcQ).slerp(_dstQ, alpha);
		node.quaternion.copy(_outQ);
	}
}

/**
 * Create a stand-up sequence controller for a VRM character. The sequence
 * owns the character's root rotation and a specific set of VRM humanoid
 * bones while it's running — don't drive them externally at the same time.
 *
 * Requires `char.vrm` — if the character is a non-humanoid GLB, the sequence
 * falls back to the simple root-rotation-lerp that the cinematic had before.
 */
export function createStandupSequence(
	char: CharacterLoadResult,
	options: StandupSequenceOptions = {},
): StandupSequence {
	const vrm = char.vrm;
	const pacing = options.pacing ?? 1.0;
	const proneHold = options.proneHold ?? 1.0;
	const timeline = buildTimeline(proneHold);
	const totalDuration = timeline[timeline.length - 1].t;

	let elapsed = 0;
	let done = false;
	let completedFired = false;

	// If no VRM humanoid, we still can do root-rotation prone → upright lerp.
	const hasHumanoid = Boolean(vrm?.humanoid);

	return {
		update(delta) {
			if (done) return;
			elapsed += delta * pacing;

			if (elapsed >= totalDuration) {
				// Snap to final pose.
				const last = timeline[timeline.length - 1];
				char.root.rotation.x = last.rootRotationX;
				char.root.rotation.z = 0;
				if (hasHumanoid && vrm) {
					// Reset any bones we animated back to rest.
					const finalBones = new Set<VRMHumanBoneName>();
					for (const kf of timeline) {
						for (const k of Object.keys(kf.bones) as VRMHumanBoneName[]) finalBones.add(k);
					}
					for (const boneName of finalBones) {
						const node = vrm.humanoid.getNormalizedBoneNode(boneName);
						if (node) node.quaternion.identity();
					}
				}
				done = true;
				if (!completedFired) {
					completedFired = true;
					options.onComplete?.();
				}
				return;
			}

			// Find the active keyframe pair.
			let a = timeline[0];
			let b = timeline[0];
			for (let i = 1; i < timeline.length; i++) {
				if (timeline[i].t >= elapsed) {
					a = timeline[i - 1];
					b = timeline[i];
					break;
				}
			}

			// Smoothstep on the phase alpha — eases in/out of each pose.
			const rawAlpha = (elapsed - a.t) / Math.max(0.001, b.t - a.t);
			const alpha = rawAlpha * rawAlpha * (3 - 2 * rawAlpha);

			if (hasHumanoid && vrm) {
				applyInterpolated(char, vrm, a, b, alpha);

				// Overlay head shake during the designated window. Must be
				// applied AFTER the keyframe interp so it composes on top of
				// whatever neutral head rotation the keyframes produced.
				const shiftedStart = SHAKE_WINDOW.start + (proneHold - 1.0);
				const shiftedEnd   = SHAKE_WINDOW.end   + (proneHold - 1.0);
				if (elapsed >= shiftedStart && elapsed < shiftedEnd) {
					const head = vrm.humanoid.getNormalizedBoneNode("head");
					if (head) {
						const shakeT = elapsed - shiftedStart;
						const y = Math.sin(shakeT * SHAKE_FREQUENCY * 2 * P) * SHAKE_AMPLITUDE;
						// Compose with whatever keyframes set for head (rest).
						head.quaternion.setFromEuler(_tmpEuler.set(0, y, 0));
					}
				}
			} else {
				// Non-humanoid fallback: just lerp root rotation between keyframes.
				char.root.rotation.x = a.rootRotationX + (b.rootRotationX - a.rootRotationX) * alpha;
				char.root.rotation.z = 0;
			}
		},

		get isDone() { return done; },

		dispose() {
			if (!vrm || !hasHumanoid) return;
			const allBones = new Set<VRMHumanBoneName>();
			for (const kf of timeline) {
				for (const k of Object.keys(kf.bones) as VRMHumanBoneName[]) allBones.add(k);
			}
			allBones.add("head");
			for (const boneName of allBones) {
				const node = vrm.humanoid.getNormalizedBoneNode(boneName);
				if (node) node.quaternion.identity();
			}
		},
	};
}

export const STANDUP_SEQUENCE_DURATION = SEQUENCE_DURATION;

/**
 * Apply a static kneeling pose to a VRM (hips upright, knees bent 90°,
 * legs tucked under the body). Useful for non-animated idle moments —
 * e.g. TJ kneeling next to an unconscious crewmate. Also resets arms to
 * neutral by-the-sides position.
 *
 * Does NOT touch the outer `char.root` transform — callers should
 * position and rotate that group themselves before calling.
 */
export function applyKneelingPose(char: CharacterLoadResult): void {
	const vrm = char.vrm;
	if (!vrm?.humanoid) return;
	for (const boneName of Object.keys(KNEEL_BONES) as VRMHumanBoneName[]) {
		const node = vrm.humanoid.getNormalizedBoneNode(boneName);
		if (!node) continue;
		const euler = KNEEL_BONES[boneName]!;
		node.quaternion.setFromEuler(new THREE.Euler(euler[0], euler[1], euler[2]));
	}
	// Head looks slightly down (concerned look at the person on the ground).
	const head = vrm.humanoid.getNormalizedBoneNode("head");
	if (head) head.quaternion.setFromEuler(new THREE.Euler(0.25, 0, 0));
}
