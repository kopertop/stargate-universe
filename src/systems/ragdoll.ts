/**
 * Ragdoll Physics System — creates physics-driven humanoid ragdolls using
 * Crashcat's SwingTwistConstraint joints, mass-ratio stabilization, and a
 * named-joint skeleton hierarchy.
 *
 * This file is a near-direct port of the official Crashcat ragdoll example
 *   https://raw.githubusercontent.com/isaac-mason/crashcat/refs/heads/main/examples/src/example-ragdoll.ts
 *
 * with two adjustments:
 *   1. Public API is wrapped in a `RagdollInstance` so scenes can dispose
 *      everything cleanly, launch with an initial velocity, and drive a
 *      Three.js group each frame via `syncToVisual()`.
 *   2. Optional `visualRoot` lets a VRM character ride the pelvis body
 *      instead of (or in addition to) the debug box meshes.
 *
 * Usage:
 *   const ragdoll = createRagdoll(world, {
 *       objectLayer: CRASHCAT_OBJECT_LAYER_DYNAMIC,
 *       position:    [0, 3, 0],
 *       scale:       1.0,
 *   });
 *   scene.add(ragdoll.group);
 *   ragdoll.launch([0, 5, 0], [0, 0, 20]);
 *   // In update loop:
 *   ragdoll.syncToVisual();
 *   // Cleanup:
 *   ragdoll.dispose();
 */
import * as THREE from "three";
import { mat3, mat4, quat, vec3 } from "mathcat";
import type { Mat3, Vec3 } from "mathcat";
import type { RigidBody } from "crashcat";
import {
	box,
	ConstraintSpace,
	MotionType,
	massProperties,
	motionProperties,
	rigidBody,
	swingTwistConstraint,
} from "crashcat";
import type { CrashcatPhysicsWorld } from "@ggez/runtime-physics-crashcat";

// ─── Body part enum ─────────────────────────────────────────────────────────

export enum BodyPart {
	UPPER_BODY = 0,
	HEAD = 1,
	UPPER_LEFT_ARM = 2,
	LOWER_LEFT_ARM = 3,
	UPPER_RIGHT_ARM = 4,
	LOWER_RIGHT_ARM = 5,
	PELVIS = 6,
	UPPER_LEFT_LEG = 7,
	LOWER_LEFT_LEG = 8,
	UPPER_RIGHT_LEG = 9,
	LOWER_RIGHT_LEG = 10,
}

// ─── Ragdoll shape config ───────────────────────────────────────────────────

type ShapeConfig = {
	/** Full half-extents of the box shape (x/y/z). */
	args: Vec3;
	density: number;
	/** Local offset from ragdoll origin (feet-on-ground). */
	position: Vec3;
};

type JointConfig = {
	pivotA: Vec3;
	pivotB: Vec3;
	axisA: Vec3;
	axisB: Vec3;
	angle: number;
	twistAngle: number;
};

type SkeletonJoint = {
	bodyPart: BodyPart;
	parentBodyPart: BodyPart | null;
};

type RagdollSettings = {
	shapes: Map<BodyPart, ShapeConfig>;
	joints: Record<string, JointConfig>;
	skeleton: SkeletonJoint[];
};

/**
 * Build shape + joint + skeleton definitions for a ragdoll of the given
 * scale. `angleA` is the default cone angle for most joints; `angleB` is
 * used for shoulders (wider range of motion).
 */
function createRagdollSettings(
	scale: number,
	angleA: number,
	angleB: number,
	twistAngle: number,
): RagdollSettings {
	const shouldersDistance = 0.45 * scale;
	const upperArmLength    = 0.4 * scale;
	const lowerArmLength    = 0.4 * scale;
	const upperArmSize      = 0.15 * scale;
	const lowerArmSize      = 0.15 * scale;
	const neckLength        = 0.1 * scale;
	const headRadius        = 0.2 * scale;
	const upperBodyLength   = 0.6 * scale;
	const pelvisLength      = 0.2 * scale;
	const pelvisSize        = 0.25 * scale;
	const upperLegLength    = 0.5 * scale;
	const upperLegSize      = 0.15 * scale;
	const lowerLegSize      = 0.15 * scale;
	const lowerLegLength    = 0.5 * scale;

	// Build from feet up
	const lowerLeftLegPos: Vec3  = [-shouldersDistance / 3, lowerLegLength / 2, 0];
	const lowerRightLegPos: Vec3 = [ shouldersDistance / 3, lowerLegLength / 2, 0];

	const upperLeftLegPos: Vec3  = [-shouldersDistance / 3, lowerLeftLegPos[1]  + lowerLegLength / 2 + upperLegLength / 2, 0];
	const upperRightLegPos: Vec3 = [ shouldersDistance / 3, lowerRightLegPos[1] + lowerLegLength / 2 + upperLegLength / 2, 0];

	const pelvisPos: Vec3    = [0, upperLeftLegPos[1]  + upperLegLength / 2 + pelvisLength / 2, 0];
	const upperBodyPos: Vec3 = [0, pelvisPos[1]        + pelvisLength / 2   + upperBodyLength / 2, 0];
	const headPos: Vec3      = [0, upperBodyPos[1]     + upperBodyLength / 2 + headRadius / 2 + neckLength, 0];

	const upperLeftArmPos: Vec3  = [-shouldersDistance / 2 - upperArmLength / 2, upperBodyPos[1] + upperBodyLength / 2, 0];
	const upperRightArmPos: Vec3 = [ shouldersDistance / 2 + upperArmLength / 2, upperBodyPos[1] + upperBodyLength / 2, 0];

	const lowerLeftArmPos: Vec3  = [upperLeftArmPos[0]  - lowerArmLength / 2 - upperArmLength / 2, upperLeftArmPos[1], 0];
	const lowerRightArmPos: Vec3 = [upperRightArmPos[0] + lowerArmLength / 2 + upperArmLength / 2, upperRightArmPos[1], 0];

	const shapes = new Map<BodyPart, ShapeConfig>([
		[BodyPart.LOWER_LEFT_LEG,  { args: [lowerLegSize * 0.5,      lowerLegLength * 0.5, lowerLegSize * 0.5],  density: scale, position: lowerLeftLegPos }],
		[BodyPart.LOWER_RIGHT_LEG, { args: [lowerLegSize * 0.5,      lowerLegLength * 0.5, lowerLegSize * 0.5],  density: scale, position: lowerRightLegPos }],
		[BodyPart.UPPER_LEFT_LEG,  { args: [upperLegSize * 0.5,      upperLegLength * 0.5, upperLegSize * 0.5],  density: scale, position: upperLeftLegPos }],
		[BodyPart.UPPER_RIGHT_LEG, { args: [upperLegSize * 0.5,      upperLegLength * 0.5, upperLegSize * 0.5],  density: scale, position: upperRightLegPos }],
		[BodyPart.PELVIS,          { args: [shouldersDistance * 0.5, pelvisLength * 0.5,   pelvisSize * 0.5],    density: scale, position: pelvisPos }],
		[BodyPart.UPPER_BODY,      { args: [shouldersDistance * 0.5, upperBodyLength * 0.5, lowerArmSize * 0.75], density: scale, position: upperBodyPos }],
		[BodyPart.HEAD,            { args: [headRadius * 0.6,        headRadius * 0.7,     headRadius * 0.6],    density: scale, position: headPos }],
		[BodyPart.UPPER_LEFT_ARM,  { args: [upperArmLength * 0.5,    upperArmSize * 0.5,   upperArmSize * 0.5],  density: scale, position: upperLeftArmPos }],
		[BodyPart.UPPER_RIGHT_ARM, { args: [upperArmLength * 0.5,    upperArmSize * 0.5,   upperArmSize * 0.5],  density: scale, position: upperRightArmPos }],
		[BodyPart.LOWER_LEFT_ARM,  { args: [lowerArmLength * 0.5,    lowerArmSize * 0.5,   lowerArmSize * 0.5],  density: scale, position: lowerLeftArmPos }],
		[BodyPart.LOWER_RIGHT_ARM, { args: [lowerArmLength * 0.5,    lowerArmSize * 0.5,   lowerArmSize * 0.5],  density: scale, position: lowerRightArmPos }],
	]);

	const joints: Record<string, JointConfig> = {
		neckJoint: {
			pivotA: [0, -headRadius - neckLength / 2, 0],
			pivotB: [0, upperBodyLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		leftKneeJoint: {
			pivotA: [0, lowerLegLength / 2, 0],
			pivotB: [0, -upperLegLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		rightKneeJoint: {
			pivotA: [0, lowerLegLength / 2, 0],
			pivotB: [0, -upperLegLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		leftHipJoint: {
			pivotA: [0, upperLegLength / 2, 0],
			pivotB: [-shouldersDistance / 3, -pelvisLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		rightHipJoint: {
			pivotA: [0, upperLegLength / 2, 0],
			pivotB: [ shouldersDistance / 3, -pelvisLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		spineJoint: {
			pivotA: [0, pelvisLength / 2, 0],
			pivotB: [0, -upperBodyLength / 2, 0],
			axisA: [0, 1, 0], axisB: [0, 1, 0],
			angle: angleA, twistAngle,
		},
		leftShoulder: {
			pivotA: [-shouldersDistance / 2, upperBodyLength / 2, 0],
			pivotB: [ upperArmLength / 2, 0, 0],
			axisA: [1, 0, 0], axisB: [1, 0, 0],
			angle: angleB, twistAngle,
		},
		rightShoulder: {
			pivotA: [ shouldersDistance / 2, upperBodyLength / 2, 0],
			pivotB: [-upperArmLength / 2, 0, 0],
			axisA: [1, 0, 0], axisB: [1, 0, 0],
			angle: angleB, twistAngle,
		},
		leftElbowJoint: {
			pivotA: [ lowerArmLength / 2, 0, 0],
			pivotB: [-upperArmLength / 2, 0, 0],
			axisA: [1, 0, 0], axisB: [1, 0, 0],
			angle: angleA, twistAngle,
		},
		rightElbowJoint: {
			pivotA: [-lowerArmLength / 2, 0, 0],
			pivotB: [ upperArmLength / 2, 0, 0],
			axisA: [1, 0, 0], axisB: [1, 0, 0],
			angle: angleA, twistAngle,
		},
	};

	const skeleton: SkeletonJoint[] = [
		{ bodyPart: BodyPart.PELVIS,          parentBodyPart: null },
		{ bodyPart: BodyPart.UPPER_BODY,      parentBodyPart: BodyPart.PELVIS },
		{ bodyPart: BodyPart.HEAD,            parentBodyPart: BodyPart.UPPER_BODY },
		{ bodyPart: BodyPart.UPPER_LEFT_ARM,  parentBodyPart: BodyPart.UPPER_BODY },
		{ bodyPart: BodyPart.LOWER_LEFT_ARM,  parentBodyPart: BodyPart.UPPER_LEFT_ARM },
		{ bodyPart: BodyPart.UPPER_RIGHT_ARM, parentBodyPart: BodyPart.UPPER_BODY },
		{ bodyPart: BodyPart.LOWER_RIGHT_ARM, parentBodyPart: BodyPart.UPPER_RIGHT_ARM },
		{ bodyPart: BodyPart.UPPER_LEFT_LEG,  parentBodyPart: BodyPart.PELVIS },
		{ bodyPart: BodyPart.LOWER_LEFT_LEG,  parentBodyPart: BodyPart.UPPER_LEFT_LEG },
		{ bodyPart: BodyPart.UPPER_RIGHT_LEG, parentBodyPart: BodyPart.PELVIS },
		{ bodyPart: BodyPart.LOWER_RIGHT_LEG, parentBodyPart: BodyPart.UPPER_RIGHT_LEG },
	];

	return { shapes, joints, skeleton };
}

// ─── Mass stabilization (from JoltPhysics, via Oliver Strunk/Havok) ────────
//
// Prevents constraints from blowing up by:
//   1. Clamping parent/child mass ratios into [0.8, 1.2]
//   2. Inflating parent inertia to be ≥ sum of children inertia
//
// Skipping this is the #1 cause of jittery or exploding ragdolls.

function stabilizeRagdoll(bodies: Map<BodyPart, RigidBody>, skeleton: SkeletonJoint[]): void {
	const MIN_MASS_RATIO = 0.8;
	const MAX_MASS_RATIO = 1.2;
	const MAX_INERTIA_INCREASE = 2.0;

	const visited = new Set<BodyPart>();
	const massRatios = new Map<BodyPart, number>();

	const roots = skeleton.filter((j) => j.parentBodyPart === null);

	for (const root of roots) {
		const chain: BodyPart[] = [];
		const toProcess: BodyPart[] = [root.bodyPart];

		while (toProcess.length > 0) {
			const current = toProcess.shift()!;
			if (visited.has(current)) continue;
			visited.add(current);
			chain.push(current);
			for (const joint of skeleton) {
				if (joint.parentBodyPart === current && !visited.has(joint.bodyPart)) {
					toProcess.push(joint.bodyPart);
				}
			}
		}

		if (chain.length === 1) continue;

		// Step 1: clamp mass ratios
		let totalMassRatio = 1.0;
		massRatios.set(chain[0], 1.0);

		for (let i = 1; i < chain.length; i++) {
			const childPart = chain[i];
			const parentPart = skeleton.find((j) => j.bodyPart === childPart)!.parentBodyPart!;

			const childBody  = bodies.get(childPart)!;
			const parentBody = bodies.get(parentPart)!;

			const ratio = childBody.massProperties.mass / parentBody.massProperties.mass;
			const clampedRatio = Math.max(MIN_MASS_RATIO, Math.min(MAX_MASS_RATIO, ratio));

			const parentRatio = massRatios.get(parentPart)!;
			massRatios.set(childPart, parentRatio * clampedRatio);
			totalMassRatio += massRatios.get(childPart)!;
		}

		let totalMass = 0;
		for (const part of chain) totalMass += bodies.get(part)!.massProperties.mass;

		const ratioToMass = totalMass / totalMassRatio;

		for (const part of chain) {
			const body = bodies.get(part)!;
			const oldMass = body.massProperties.mass;
			const newMass = massRatios.get(part)! * ratioToMass;

			body.massProperties.mass = newMass;

			const massScale = newMass / oldMass;
			for (let i = 0; i < 15; i++) body.massProperties.inertia[i] *= massScale;
			body.massProperties.inertia[15] = 1.0;
		}

		// Step 2: inflate parent inertia based on children
		type Principal = { rotation: Mat3; diagonal: Vec3; childSum: number };
		const principals = new Map<BodyPart, Principal>();

		for (const part of chain) {
			const body = bodies.get(part)!;
			const rotation = mat3.create();
			const diagonal = vec3.create();
			if (!motionProperties.decomposePrincipalMomentsOfInertia(body.massProperties.inertia, rotation, diagonal)) {
				console.warn(`[ragdoll] decompose failed for body part ${part}`);
				continue;
			}
			principals.set(part, { rotation, diagonal, childSum: 0 });
		}

		for (let i = chain.length - 1; i > 0; i--) {
			const childPart = chain[i];
			const parentPart = skeleton.find((j) => j.bodyPart === childPart)!.parentBodyPart!;
			const childPrincipal  = principals.get(childPart);
			const parentPrincipal = principals.get(parentPart);
			if (childPrincipal && parentPrincipal) {
				parentPrincipal.childSum += childPrincipal.diagonal[0] + childPrincipal.childSum;
			}
		}

		for (const part of chain) {
			const principal = principals.get(part);
			if (!principal || principal.childSum === 0) continue;

			const body = bodies.get(part)!;
			const minimum = Math.min(MAX_INERTIA_INCREASE * principal.diagonal[0], principal.childSum);

			principal.diagonal[0] = Math.max(principal.diagonal[0], minimum);
			principal.diagonal[1] = Math.max(principal.diagonal[1], minimum);
			principal.diagonal[2] = Math.max(principal.diagonal[2], minimum);

			// Reconstruct inertia tensor: I = R * D * R^T
			const scaleMat = mat4.create();
			mat4.fromScaling(scaleMat, principal.diagonal);

			const rot4x4 = mat4.create();
			mat4.identity(rot4x4);
			for (let i = 0; i < 3; i++) {
				for (let j = 0; j < 3; j++) {
					rot4x4[i + j * 4] = principal.rotation[i + j * 3];
				}
			}

			const temp1 = mat4.create();
			const temp2 = mat4.create();
			mat4.multiply(temp1, rot4x4, scaleMat);
			mat4.transpose(temp2, rot4x4);
			mat4.multiply(body.massProperties.inertia, temp1, temp2);
			body.massProperties.inertia[15] = 1.0;
		}
	}

	// Apply final mass/inertia to motion properties
	for (const [, body] of bodies) {
		if (body.motionType === MotionType.DYNAMIC) {
			const mp = massProperties.create();
			massProperties.copy(mp, body.massProperties);
			body.massPropertiesOverride = rigidBody.MassPropertiesOverride.MASS_AND_INERTIA_PROVIDED;

			const tempMp = body.motionProperties;
			tempMp.invMass = mp.mass > 0 ? 1.0 / mp.mass : 0;

			const rotation = mat3.create();
			const diagonal = vec3.create();
			if (motionProperties.decomposePrincipalMomentsOfInertia(mp.inertia, rotation, diagonal)) {
				vec3.set(
					tempMp.invInertiaDiagonal,
					diagonal[0] !== 0 ? 1.0 / diagonal[0] : 0,
					diagonal[1] !== 0 ? 1.0 / diagonal[1] : 0,
					diagonal[2] !== 0 ? 1.0 / diagonal[2] : 0,
				);
				quat.fromMat3(tempMp.inertiaRotation, rotation);
			}
		}
	}
}

// ─── Visual debug meshes ─────────────────────────────────────────────────────

const _skinMat = new THREE.MeshStandardMaterial({ color: 0xf0d2a5, roughness: 0.7 });
const _bodyMat = new THREE.MeshStandardMaterial({ color: 0x3a3a4a, roughness: 0.6, metalness: 0.2 });

function createPartMesh(halfExtents: Vec3, part: BodyPart): THREE.Mesh {
	const mat = part === BodyPart.HEAD ? _skinMat : _bodyMat;
	const geo = new THREE.BoxGeometry(halfExtents[0] * 2, halfExtents[1] * 2, halfExtents[2] * 2);
	return new THREE.Mesh(geo, mat);
}

// ─── Public API ──────────────────────────────────────────────────────────────

export interface CreateRagdollOptions {
	/** Physics dynamic object layer. */
	objectLayer: number;
	/** World-space spawn position (feet on ground). */
	position: THREE.Vector3 | Vec3;
	/** Height multiplier (1.0 ≈ 1.8m). Defaults to 1.0. */
	scale?: number;
	/** Default cone angle for hips/knees/elbows/spine/neck. Defaults to π/4. */
	angleA?: number;
	/** Cone angle for shoulders (wider). Defaults to π/4. */
	angleB?: number;
	/** Twist range (+/-). Defaults to 0. */
	twistAngle?: number;
	/** Whether to run mass-ratio + inertia stabilization (strongly recommended). */
	stabilize?: boolean;
	/** Whether to create the debug box meshes. Off when attaching a VRM. */
	createDebugMeshes?: boolean;
}

export interface RagdollInstance {
	/** Root Three.js group — add to scene. */
	readonly group: THREE.Group;
	/** Physics bodies keyed by BodyPart — exposed for attaching VRM bones. */
	readonly bodies: Map<BodyPart, RigidBody>;
	/** Sync physics body positions to the debug meshes each frame. */
	syncToVisual(): void;
	/** Apply a linear + angular impulse to every body. */
	launch(linearVelocity: Vec3 | THREE.Vector3, angularVelocity?: Vec3 | THREE.Vector3): void;
	/** Pelvis world position (for camera tracking). */
	getPelvisPosition(out: THREE.Vector3): THREE.Vector3;
	/** True when the pelvis is near the floor and roughly at rest. */
	isAtRest(): boolean;
	/** Remove all physics bodies and Three.js objects. */
	dispose(): void;
}

function toVec3(v: THREE.Vector3 | Vec3): Vec3 {
	if (Array.isArray(v)) return v as Vec3;
	return [v.x, v.y, v.z];
}

/**
 * Create a physics-driven ragdoll at the given position. Defaults match the
 * canonical Crashcat example: 1.8m human, π/4 cone joints, stabilized.
 */
export function createRagdoll(
	world: CrashcatPhysicsWorld,
	options: CreateRagdollOptions,
): RagdollInstance {
	const scale      = options.scale ?? 1.0;
	const angleA     = options.angleA ?? Math.PI / 4;
	const angleB     = options.angleB ?? Math.PI / 4;
	const twistAngle = options.twistAngle ?? 0;
	const stabilize  = options.stabilize ?? true;
	const createDebug = options.createDebugMeshes ?? true;

	const settings = createRagdollSettings(scale, angleA, angleB, twistAngle);
	const bodies = new Map<BodyPart, RigidBody>();
	const meshes = new Map<BodyPart, THREE.Mesh>();
	const group = new THREE.Group();
	group.name = "ragdoll";

	const offset = toVec3(options.position);

	// 1. Create all rigid bodies
	for (const [part, config] of settings.shapes) {
		const [halfW, halfH, halfD] = config.args;
		const worldPos: Vec3 = [
			config.position[0] + offset[0],
			config.position[1] + offset[1],
			config.position[2] + offset[2],
		];

		const body = rigidBody.create(world, {
			shape: box.create({
				halfExtents: vec3.fromValues(halfW, halfH, halfD),
				convexRadius: 0.05,
				density: config.density,
			}),
			objectLayer: options.objectLayer,
			motionType: MotionType.DYNAMIC,
			position: vec3.fromValues(...worldPos),
			quaternion: quat.create(),
			linearDamping: 0.05,
			angularDamping: 0.05,
			restitution: 0,
		});
		bodies.set(part, body);

		if (createDebug) {
			const mesh = createPartMesh(config.args, part);
			mesh.position.set(worldPos[0], worldPos[1], worldPos[2]);
			group.add(mesh);
			meshes.set(part, mesh);
		}
	}

	// 2. Stabilize mass + inertia BEFORE creating constraints
	if (stabilize) stabilizeRagdoll(bodies, settings.skeleton);

	// 3. Create swing-twist constraints, matched to the named-joint table
	const jointToBodies: Record<string, [BodyPart, BodyPart]> = {
		neckJoint:       [BodyPart.HEAD,            BodyPart.UPPER_BODY],
		leftKneeJoint:   [BodyPart.LOWER_LEFT_LEG,  BodyPart.UPPER_LEFT_LEG],
		rightKneeJoint:  [BodyPart.LOWER_RIGHT_LEG, BodyPart.UPPER_RIGHT_LEG],
		leftHipJoint:    [BodyPart.UPPER_LEFT_LEG,  BodyPart.PELVIS],
		rightHipJoint:   [BodyPart.UPPER_RIGHT_LEG, BodyPart.PELVIS],
		spineJoint:      [BodyPart.PELVIS,          BodyPart.UPPER_BODY],
		leftShoulder:    [BodyPart.UPPER_BODY,      BodyPart.UPPER_LEFT_ARM],
		rightShoulder:   [BodyPart.UPPER_BODY,      BodyPart.UPPER_RIGHT_ARM],
		leftElbowJoint:  [BodyPart.LOWER_LEFT_ARM,  BodyPart.UPPER_LEFT_ARM],
		rightElbowJoint: [BodyPart.LOWER_RIGHT_ARM, BodyPart.UPPER_RIGHT_ARM],
	};

	const getTangent = (out: Vec3, axis: Vec3): Vec3 => {
		const ax = Math.abs(axis[0]);
		const ay = Math.abs(axis[1]);
		const az = Math.abs(axis[2]);
		if (ax <= ay && ax <= az) {
			vec3.set(out, 0, -axis[2], axis[1]);
		} else if (ay <= az) {
			vec3.set(out, axis[2], 0, -axis[0]);
		} else {
			vec3.set(out, -axis[1], axis[0], 0);
		}
		vec3.normalize(out, out);
		return out;
	};

	for (const [jointName, jointConfig] of Object.entries(settings.joints)) {
		const ab = jointToBodies[jointName];
		if (!ab) continue;
		const bodyA = bodies.get(ab[0]);
		const bodyB = bodies.get(ab[1]);
		if (!bodyA || !bodyB) {
			console.warn(`[ragdoll] missing bodies for joint ${jointName}`);
			continue;
		}

		const twistAxis1 = vec3.fromValues(...jointConfig.axisA);
		const twistAxis2 = vec3.fromValues(...jointConfig.axisB);
		const planeAxis1 = vec3.create();
		const planeAxis2 = vec3.create();
		getTangent(planeAxis1, twistAxis1);
		getTangent(planeAxis2, twistAxis2);

		swingTwistConstraint.create(world, {
			bodyIdA: bodyA.id,
			bodyIdB: bodyB.id,
			position1:  vec3.fromValues(...jointConfig.pivotA),
			position2:  vec3.fromValues(...jointConfig.pivotB),
			twistAxis1, twistAxis2,
			planeAxis1, planeAxis2,
			space: ConstraintSpace.LOCAL,
			normalHalfConeAngle: jointConfig.angle,
			planeHalfConeAngle:  jointConfig.angle,
			twistMinAngle: jointConfig.twistAngle !== undefined ? -jointConfig.twistAngle : 0,
			twistMaxAngle: jointConfig.twistAngle !== undefined ?  jointConfig.twistAngle : 0,
		});
	}

	return {
		group,
		bodies,

		syncToVisual() {
			for (const [part, body] of bodies) {
				const mesh = meshes.get(part);
				if (!mesh) continue;
				mesh.position.set(body.position[0], body.position[1], body.position[2]);
				mesh.quaternion.set(body.quaternion[0], body.quaternion[1], body.quaternion[2], body.quaternion[3]);
			}
		},

		launch(linearVelocity, angularVelocity) {
			const lv = vec3.fromValues(...toVec3(linearVelocity));
			const av = angularVelocity ? vec3.fromValues(...toVec3(angularVelocity)) : vec3.create();
			for (const body of bodies.values()) {
				rigidBody.addLinearVelocity(world, body, lv);
				rigidBody.addAngularVelocity(world, body, av);
			}
		},

		getPelvisPosition(out) {
			const p = bodies.get(BodyPart.PELVIS)?.position ?? [0, 0, 0];
			out.set(p[0], p[1], p[2]);
			return out;
		},

		isAtRest() {
			const pelvis = bodies.get(BodyPart.PELVIS);
			if (!pelvis) return true;
			return pelvis.position[1] < 0.5;
		},

		dispose() {
			for (const body of bodies.values()) {
				rigidBody.remove(world, body);
			}
			bodies.clear();
			group.parent?.remove(group);
			for (const mesh of meshes.values()) mesh.geometry.dispose();
			meshes.clear();
		},
	};
}
