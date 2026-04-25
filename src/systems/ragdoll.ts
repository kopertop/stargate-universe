/**
 * Ragdoll Physics System — creates physics-driven humanoid ragdolls using
 * Crashcat's SwingTwistConstraint joints.
 *
 * Based on the official Crashcat ragdoll example:
 * https://crashcat.dev/examples/#example-ragdoll
 *
 * Usage:
 *   const ragdoll = createRagdoll(physicsWorld, objectLayer, position, velocity);
 *   // In update loop:
 *   ragdoll.syncToVisual(threeGroup);
 *   // Cleanup:
 *   ragdoll.dispose(physicsWorld);
 */
import * as THREE from "three";
import { vec3, quat } from "mathcat";
import type { Vec3 } from "mathcat";
import type { RigidBody } from "crashcat";
import {
	box,
	ConstraintSpace,
	MotionType,
	rigidBody,
	swingTwistConstraint,
} from "crashcat";
import type { CrashcatPhysicsWorld } from "@ggez/runtime-physics-crashcat";

// ─── Body part enum ─────────────────────────────────────────────────────────

export enum BodyPart {
	PELVIS = 0,
	UPPER_BODY = 1,
	HEAD = 2,
	UPPER_LEFT_ARM = 3,
	LOWER_LEFT_ARM = 4,
	UPPER_RIGHT_ARM = 5,
	LOWER_RIGHT_ARM = 6,
	UPPER_LEFT_LEG = 7,
	LOWER_LEFT_LEG = 8,
	UPPER_RIGHT_LEG = 9,
	LOWER_RIGHT_LEG = 10,
}

const PART_COUNT = 11;

// ─── Ragdoll shape config ───────────────────────────────────────────────────

type PartConfig = {
	halfExtents: Vec3;
	position: Vec3;     // local offset from ragdoll origin
	density: number;
};

type JointDef = {
	partA: BodyPart;
	partB: BodyPart;
	pivotA: Vec3;
	pivotB: Vec3;
	twistAxis: Vec3;
	coneAngle: number;
	twistAngle: number;
};

function buildPartConfigs(scale: number): Map<BodyPart, PartConfig> {
	const s = scale;
	const shoulderW = 0.22 * s;
	const upperArmL = 0.2 * s;
	const lowerArmL = 0.2 * s;
	const armW = 0.07 * s;
	const upperBodyL = 0.3 * s;
	const pelvisL = 0.12 * s;
	const pelvisW = 0.12 * s;
	const upperLegL = 0.25 * s;
	const lowerLegL = 0.25 * s;
	const legW = 0.08 * s;
	const headR = 0.1 * s;
	const neckL = 0.05 * s;

	// Build from feet up
	const llLegY = lowerLegL / 2;
	const ulLegY = llLegY + lowerLegL / 2 + upperLegL / 2;
	const pelvisY = ulLegY + upperLegL / 2 + pelvisL / 2;
	const ubY = pelvisY + pelvisL / 2 + upperBodyL / 2;
	const headY = ubY + upperBodyL / 2 + headR / 2 + neckL;
	const armY = ubY + upperBodyL / 2;

	const m = new Map<BodyPart, PartConfig>();
	m.set(BodyPart.LOWER_LEFT_LEG,  { halfExtents: [legW, lowerLegL / 2, legW], position: [-shoulderW / 3, llLegY, 0], density: s });
	m.set(BodyPart.LOWER_RIGHT_LEG, { halfExtents: [legW, lowerLegL / 2, legW], position: [shoulderW / 3, llLegY, 0], density: s });
	m.set(BodyPart.UPPER_LEFT_LEG,  { halfExtents: [legW, upperLegL / 2, legW], position: [-shoulderW / 3, ulLegY, 0], density: s });
	m.set(BodyPart.UPPER_RIGHT_LEG, { halfExtents: [legW, upperLegL / 2, legW], position: [shoulderW / 3, ulLegY, 0], density: s });
	m.set(BodyPart.PELVIS,          { halfExtents: [shoulderW / 2, pelvisL / 2, pelvisW / 2], position: [0, pelvisY, 0], density: s });
	m.set(BodyPart.UPPER_BODY,      { halfExtents: [shoulderW / 2, upperBodyL / 2, armW * 2], position: [0, ubY, 0], density: s });
	m.set(BodyPart.HEAD,            { halfExtents: [headR * 0.6, headR * 0.7, headR * 0.6], position: [0, headY, 0], density: s });
	m.set(BodyPart.UPPER_LEFT_ARM,  { halfExtents: [upperArmL / 2, armW, armW], position: [-shoulderW / 2 - upperArmL / 2, armY, 0], density: s });
	m.set(BodyPart.LOWER_LEFT_ARM,  { halfExtents: [lowerArmL / 2, armW, armW], position: [-shoulderW / 2 - upperArmL - lowerArmL / 2, armY, 0], density: s });
	m.set(BodyPart.UPPER_RIGHT_ARM, { halfExtents: [upperArmL / 2, armW, armW], position: [shoulderW / 2 + upperArmL / 2, armY, 0], density: s });
	m.set(BodyPart.LOWER_RIGHT_ARM, { halfExtents: [lowerArmL / 2, armW, armW], position: [shoulderW / 2 + upperArmL + lowerArmL / 2, armY, 0], density: s });
	return m;
}

function buildJointDefs(scale: number): JointDef[] {
	const s = scale;
	const shoulderW = 0.22 * s;
	const upperArmL = 0.2 * s;
	const lowerArmL = 0.2 * s;
	const upperBodyL = 0.3 * s;
	const pelvisL = 0.12 * s;
	const upperLegL = 0.25 * s;
	const lowerLegL = 0.25 * s;
	const headR = 0.1 * s;
	const neckL = 0.05 * s;
	const a = Math.PI / 4;  // cone angle
	const tw = 0;            // twist

	return [
		// Spine
		{ partA: BodyPart.PELVIS, partB: BodyPart.UPPER_BODY,
			pivotA: [0, pelvisL / 2, 0], pivotB: [0, -upperBodyL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Neck
		{ partA: BodyPart.UPPER_BODY, partB: BodyPart.HEAD,
			pivotA: [0, upperBodyL / 2, 0], pivotB: [0, -headR - neckL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Left hip
		{ partA: BodyPart.PELVIS, partB: BodyPart.UPPER_LEFT_LEG,
			pivotA: [-shoulderW / 3, -pelvisL / 2, 0], pivotB: [0, upperLegL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Right hip
		{ partA: BodyPart.PELVIS, partB: BodyPart.UPPER_RIGHT_LEG,
			pivotA: [shoulderW / 3, -pelvisL / 2, 0], pivotB: [0, upperLegL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Left knee
		{ partA: BodyPart.UPPER_LEFT_LEG, partB: BodyPart.LOWER_LEFT_LEG,
			pivotA: [0, -upperLegL / 2, 0], pivotB: [0, lowerLegL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Right knee
		{ partA: BodyPart.UPPER_RIGHT_LEG, partB: BodyPart.LOWER_RIGHT_LEG,
			pivotA: [0, -upperLegL / 2, 0], pivotB: [0, lowerLegL / 2, 0],
			twistAxis: [0, 1, 0], coneAngle: a, twistAngle: tw },
		// Left shoulder
		{ partA: BodyPart.UPPER_BODY, partB: BodyPart.UPPER_LEFT_ARM,
			pivotA: [-shoulderW / 2, upperBodyL / 2, 0], pivotB: [upperArmL / 2, 0, 0],
			twistAxis: [1, 0, 0], coneAngle: a, twistAngle: tw },
		// Right shoulder
		{ partA: BodyPart.UPPER_BODY, partB: BodyPart.UPPER_RIGHT_ARM,
			pivotA: [shoulderW / 2, upperBodyL / 2, 0], pivotB: [-upperArmL / 2, 0, 0],
			twistAxis: [1, 0, 0], coneAngle: a, twistAngle: tw },
		// Left elbow
		{ partA: BodyPart.UPPER_LEFT_ARM, partB: BodyPart.LOWER_LEFT_ARM,
			pivotA: [-upperArmL / 2, 0, 0], pivotB: [lowerArmL / 2, 0, 0],
			twistAxis: [1, 0, 0], coneAngle: a, twistAngle: tw },
		// Right elbow
		{ partA: BodyPart.UPPER_RIGHT_ARM, partB: BodyPart.LOWER_RIGHT_ARM,
			pivotA: [upperArmL / 2, 0, 0], pivotB: [-lowerArmL / 2, 0, 0],
			twistAxis: [1, 0, 0], coneAngle: a, twistAngle: tw },
	];
}

// ─── Visual mesh creation ───────────────────────────────────────────────────

const _skinMat = new THREE.MeshStandardMaterial({ color: 0xf0d2a5, roughness: 0.7 });
const _bodyMat = new THREE.MeshStandardMaterial({ color: 0x3a3a4a, roughness: 0.6, metalness: 0.2 });

function createPartMesh(he: Vec3, part: BodyPart): THREE.Mesh {
	const mat = part === BodyPart.HEAD ? _skinMat : _bodyMat;
	const geo = new THREE.BoxGeometry(he[0] * 2, he[1] * 2, he[2] * 2);
	return new THREE.Mesh(geo, mat);
}

// ─── Public API ─────────────────────────────────────────────────────────────

export type RagdollInstance = {
	/** Root Three.js group — add to scene. */
	readonly group: THREE.Group;
	/** Sync physics body positions to Three.js meshes. Call each frame. */
	syncToVisual(): void;
	/** Apply a launch impulse to the entire ragdoll. */
	launch(linearVelocity: Vec3, angularVelocity: Vec3): void;
	/** Remove all physics bodies and Three.js objects. */
	dispose(): void;
	/** Check if the ragdoll has mostly come to rest on the ground. */
	isAtRest(): boolean;
};

/**
 * Create a physics-driven ragdoll at the given position, optionally launched
 * with an initial velocity. The ragdoll is made of 11 box bodies connected
 * by SwingTwistConstraints — identical to the Crashcat ragdoll example.
 *
 * @param world     The Crashcat physics world (from scene context).
 * @param objLayer  The dynamic object layer for collision.
 * @param position  World-space spawn position (feet on ground).
 * @param scale     Height multiplier (1.0 ≈ 1.8m human).
 */
export function createRagdoll(
	world: CrashcatPhysicsWorld,
	objLayer: number,
	position: THREE.Vector3,
	scale = 1.0,
): RagdollInstance {
	const parts = buildPartConfigs(scale);
	const joints = buildJointDefs(scale);
	const bodies = new Map<BodyPart, RigidBody>();
	const meshes = new Map<BodyPart, THREE.Mesh>();
	const group = new THREE.Group();
	group.name = "ragdoll";

	// Create rigid bodies for each part
	for (const [part, config] of parts) {
		const pos: Vec3 = [
			config.position[0] + position.x,
			config.position[1] + position.y,
			config.position[2] + position.z,
		];
		const body = rigidBody.create(world, {
			shape: box.create({
				halfExtents: vec3.fromValues(...config.halfExtents),
				convexRadius: 0.02,
				density: config.density,
			}),
			objectLayer: objLayer,
			motionType: MotionType.DYNAMIC,
			position: vec3.fromValues(...pos),
			quaternion: quat.create(),
			linearDamping: 0.05,
			angularDamping: 0.05,
			restitution: 0.1,
		});
		bodies.set(part, body);

		const mesh = createPartMesh(config.halfExtents, part);
		mesh.position.set(...pos);
		group.add(mesh);
		meshes.set(part, mesh);
	}

	// Create swing-twist joints
	const getTangent = (axis: Vec3): Vec3 => {
		const ax = Math.abs(axis[0]);
		const ay = Math.abs(axis[1]);
		const az = Math.abs(axis[2]);
		const out: Vec3 = [0, 0, 0];
		if (ax <= ay && ax <= az) {
			out[1] = -axis[2]; out[2] = axis[1];
		} else if (ay <= az) {
			out[0] = axis[2]; out[2] = -axis[0];
		} else {
			out[0] = -axis[1]; out[1] = axis[0];
		}
		const len = Math.sqrt(out[0] ** 2 + out[1] ** 2 + out[2] ** 2);
		if (len > 0) { out[0] /= len; out[1] /= len; out[2] /= len; }
		return out;
	};

	for (const jd of joints) {
		const bodyA = bodies.get(jd.partA);
		const bodyB = bodies.get(jd.partB);
		if (!bodyA || !bodyB) continue;

		const planeAxis = getTangent(jd.twistAxis);
		swingTwistConstraint.create(world, {
			bodyIdA: bodyA.id,
			bodyIdB: bodyB.id,
			position1: vec3.fromValues(...jd.pivotA),
			position2: vec3.fromValues(...jd.pivotB),
			twistAxis1: vec3.fromValues(...jd.twistAxis),
			twistAxis2: vec3.fromValues(...jd.twistAxis),
			planeAxis1: vec3.fromValues(...planeAxis),
			planeAxis2: vec3.fromValues(...planeAxis),
			space: ConstraintSpace.LOCAL,
			normalHalfConeAngle: jd.coneAngle,
			planeHalfConeAngle: jd.coneAngle,
			twistMinAngle: -jd.twistAngle,
			twistMaxAngle: jd.twistAngle,
		});
	}

	return {
		group,

		syncToVisual() {
			for (const [part, body] of bodies) {
				const mesh = meshes.get(part);
				if (!mesh) continue;
				// Position/quaternion are direct properties on the RigidBody
				mesh.position.set(body.position[0], body.position[1], body.position[2]);
				mesh.quaternion.set(body.quaternion[0], body.quaternion[1], body.quaternion[2], body.quaternion[3]);
			}
		},

		launch(linearVelocity: Vec3, angularVelocity: Vec3) {
			for (const body of bodies.values()) {
				rigidBody.addLinearVelocity(world, body, vec3.fromValues(...linearVelocity));
				rigidBody.addAngularVelocity(world, body, vec3.fromValues(...angularVelocity));
			}
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
			for (const mesh of meshes.values()) {
				mesh.geometry.dispose();
			}
			meshes.clear();
		},
	};
}
