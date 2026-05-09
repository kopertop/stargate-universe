/**
 * TestAnimatedCharacterController
 *
 * Debug controller that replaces the VRM with a simple box character animated
 * via AnimationMixer. Used to isolate whether the character-disappears-on-
 * animation bug is WebGPU+Mixer-specific vs. VRM/MToon-specific.
 *
 * Builds a simple humanoid from box geometries, creates an idle animation
 * clip, and plays it through Three.js AnimationMixer — zero VRM, zero
 * MToon, zero file loading.
 */
import type { GameplayRuntime } from "@ggez/gameplay-runtime";
import { vec3, type SceneSettings, type Vec3 } from "@ggez/shared";
import {
	CRASHCAT_OBJECT_LAYER_MOVING,
	CastRayStatus,
	MotionQuality,
	MotionType,
	capsule,
	castRay,
	createClosestCastRayCollector,
	createDefaultCastRaySettings,
	dof,
	filter,
	rigidBody,
	type CrashcatPhysicsWorld,
	type CrashcatRigidBody,
} from "@ggez/runtime-physics-crashcat";
import {
	AnimationClip,
	AnimationMixer,
	BoxGeometry,
	Group,
	MathUtils,
	Mesh,
	MeshStandardMaterial,
	PerspectiveCamera,
	QuaternionKeyframeTrack,
	VectorKeyframeTrack,
	LoopRepeat,
	Vector3,
} from "three";
import { createCameraController, type CameraController, type CameraMode } from "../camera";
import type { InputManager } from "../input";
import type { PlayerController } from "../scene";

const GROUND_MIN_NORMAL_Y = 0.45;
const GROUND_PROBE_DISTANCE = 0.2;
const GROUND_PROBE_HEIGHT = 0.12;
const JUMP_GROUND_LOCK_SECONDS = 0.12;
const MOUSE_SENSITIVITY_X = 0.0024;
const MOUSE_SENSITIVITY_Y = 0.0018;

type KinematicBody = NonNullable<ReturnType<typeof rigidBody.get>>;

type TestSpawn = {
	position: Vec3;
	rotationY: number;
};

type TestControllerOptions = {
	input: InputManager;
	camera: CameraController;
	threeCamera: PerspectiveCamera;
	gameplayRuntime: GameplayRuntime;
	sceneSettings: Pick<SceneSettings, "player" | "world">;
	spawn: TestSpawn;
	world: CrashcatPhysicsWorld;
};

// ─── Helpers ─────────────────────────────────────────────────────────────

function makePart(
	width: number,
	height: number,
	depth: number,
	color: number,
	x: number,
	y: number,
	z: number,
): Mesh {
	const geo = new BoxGeometry(width, height, depth);
	const mat = new MeshStandardMaterial({ color });
	const mesh = new Mesh(geo, mat);
	mesh.position.set(x, y, z);
	mesh.castShadow = true;
	mesh.receiveShadow = true;
	return mesh;
}

function defaultPitchForCameraMode(mode: CameraMode): number {
	if (mode === "fps") return 0;
	if (mode === "third-person") return -0.22;
	return -0.78;
}

function resolveViewDirection(yaw: number, pitch: number, target: Vector3): Vector3 {
	return target.set(
		-Math.sin(yaw) * Math.cos(pitch),
		Math.sin(pitch),
		-Math.cos(yaw) * Math.cos(pitch),
	);
}

const DOWN_DIRECTION: [number, number, number] = [0, -1, 0];

// ─── Controller ──────────────────────────────────────────────────────────

export class TestAnimatedCharacterController implements PlayerController {
	readonly object = new Group();
	inputEnabled = true;

	private readonly threeCamera: PerspectiveCamera;
	private camera: CameraController;
	private readonly input: InputManager;
	private readonly gameplayRuntime: GameplayRuntime;
	private readonly sceneSettings: Pick<SceneSettings, "player" | "world">;
	private readonly world: CrashcatPhysicsWorld;

	private readonly body: CrashcatRigidBody;
	private readonly standingHeight: number;
	private readonly radius: number;
	private readonly halfHeight: number;
	private readonly footOffset: number;

	private yaw: number;
	private pitch: number;
	private jumpQueued = false;
	private spaceWasDown = false;
	private jumpGroundLockRemaining = 0;
	private externalForwardInput = 0;
	private externalStrafeInput = 0;
	private sprintOverride = false;
	private grounded = false;

	// Ground tracking
	private readonly groundProbeCollector = createClosestCastRayCollector();
	private readonly groundProbeFilter: ReturnType<typeof filter.create>;
	private readonly groundProbeSettings = createDefaultCastRaySettings();
	private readonly supportVelocity = new Vector3();

	// Scratch vectors
	private readonly _eyePosition = new Vector3();
	private readonly _viewDirection = new Vector3();

	// Animated character parts
	private readonly characterRoot = new Group();
	private readonly torso: Mesh;

	// Mixer
	private readonly mixer: AnimationMixer;

	constructor(options: TestControllerOptions) {
		this.input = options.input;
		this.camera = options.camera;
		this.threeCamera = options.threeCamera;
		this.gameplayRuntime = options.gameplayRuntime;
		this.sceneSettings = options.sceneSettings;
		this.world = options.world;

		this.standingHeight = Math.max(1.2, options.sceneSettings.player.height);
		this.radius = MathUtils.clamp(this.standingHeight * 0.18, 0.24, 0.42);
		this.halfHeight = Math.max(0.12, this.standingHeight * 0.5 - this.radius);
		this.footOffset = this.halfHeight + this.radius;
		this.yaw = options.spawn.rotationY;
		this.pitch = defaultPitchForCameraMode(this.camera.mode);

		this.camera.setStandingHeight(this.standingHeight);

		this.groundProbeFilter = filter.create(this.world.settings.layers);
		this.groundProbeSettings.collideWithBackfaces = true;
		this.groundProbeSettings.treatConvexAsSolid = false;

		// ── Build box character ──────────────────────────────────────────
		const bodyColor = 0x4488ff;
		const skinColor = 0xffcc99;
		const pantsColor = 0x335599;
		const shoeColor = 0x333333;

		this.torso = makePart(0.5, 0.55, 0.28, bodyColor, 0, 0.95, 0);
		this.characterRoot.add(this.torso);

		this.characterRoot.add(makePart(0.22, 0.22, 0.22, skinColor, 0, 1.35, 0));
		this.characterRoot.add(makePart(0.12, 0.35, 0.12, bodyColor, 0.32, 1.0, 0));
		this.characterRoot.add(makePart(0.12, 0.35, 0.12, bodyColor, -0.32, 1.0, 0));
		this.characterRoot.add(makePart(0.10, 0.3, 0.10, skinColor, 0.32, 0.65, 0));
		this.characterRoot.add(makePart(0.10, 0.3, 0.10, skinColor, -0.32, 0.65, 0));
		this.characterRoot.add(makePart(0.18, 0.35, 0.18, pantsColor, 0.13, 0.5, 0));
		this.characterRoot.add(makePart(0.18, 0.35, 0.18, pantsColor, -0.13, 0.5, 0));
		this.characterRoot.add(makePart(0.14, 0.35, 0.14, shoeColor, 0.13, 0.15, 0));
		this.characterRoot.add(makePart(0.14, 0.35, 0.14, shoeColor, -0.13, 0.15, 0));

		this.characterRoot.position.y = -this.footOffset;
		this.object.add(this.characterRoot);

		// ── Set up animation mixer ───────────────────────────────────────
		this.mixer = new AnimationMixer(this.torso);

		const times = [0, 0.5, 1.0, 1.5, 2.0];
		const quats = [
			0, 0, 0, 1,
			0, 0, 0.05, 0.999,
			0, 0, 0, 1,
			0, 0, -0.05, 0.999,
			0, 0, 0, 1,
		];
		const swayTrack = new QuaternionKeyframeTrack(".quaternion", times, quats);

		const bobTimes = [0, 1.0, 2.0];
		const bobVals = [0, 0.03, 0];
		const bobTrack = new VectorKeyframeTrack(".position", bobTimes, bobVals);

		const clip = new AnimationClip("idle", 2, [swayTrack, bobTrack]);
		const action = this.mixer.clipAction(clip);
		action.setLoop(LoopRepeat, Infinity);
		action.play();

		// ── Physics body ─────────────────────────────────────────────────
		const spawnPos = {
			x: options.spawn.position.x,
			y: options.spawn.position.y + this.standingHeight * 0.5 + 0.04,
			z: options.spawn.position.z,
		};

		this.body = rigidBody.create(this.world, {
			allowSleeping: false,
			allowedDegreesOfFreedom: dof(true, true, true, false, false, false),
			friction: 0,
			linearDamping: 0.8,
			motionQuality: MotionQuality.LINEAR_CAST,
			motionType: MotionType.DYNAMIC,
			objectLayer: CRASHCAT_OBJECT_LAYER_MOVING,
			position: [spawnPos.x, spawnPos.y, spawnPos.z],
			shape: capsule.create({ halfHeightOfCylinder: this.halfHeight, radius: this.radius }),
		});

		this.object.position.set(spawnPos.x, spawnPos.y, spawnPos.z);
	}

	setCameraMode(mode: CameraMode): void {
		this.camera = createCameraController(mode, this.threeCamera);
		this.camera.setStandingHeight(this.standingHeight);
		this.pitch = MathUtils.clamp(this.pitch, this.camera.pitchMin, this.camera.pitchMax);
	}

	releasePointerLock(): void {
		this.input.releasePointerLock();
	}

	dispose(): void {
		this.gameplayRuntime.removeActor("player");
		rigidBody.remove(this.world, this.body);
		this.mixer.stopAllAction();
	}

	// ─── Update ──────────────────────────────────────────────────────────

	updateBeforeStep(deltaSeconds: number): void {
		this.jumpGroundLockRemaining = Math.max(0, this.jumpGroundLockRemaining - deltaSeconds);

		const translation = this.body.position;
		const linearVelocity = this.body.motionProperties.linearVelocity;
		const groundedHit =
			this.jumpGroundLockRemaining > 0 ? undefined : this.resolveGroundHit(translation);
		this.grounded = groundedHit !== undefined;

		const speed =
			this.sceneSettings.player.canRun && this.isRunning()
				? this.sceneSettings.player.runningSpeed
				: this.sceneSettings.player.movementSpeed;

		resolveViewDirection(this.yaw, this.pitch, this._viewDirection);
		const vx = this._viewDirection.x;
		const vz = this._viewDirection.z;
		const fLen = Math.hypot(vx, vz) || 1;
		const fx = vx / fLen;
		const fz = vz / fLen;
		const rx = -fz;
		const rz = fx;

		const moveX = MathUtils.clamp(
			this.input.axis("KeyD", "KeyA") +
				this.input.axis("ArrowRight", "ArrowLeft") +
				this.externalStrafeInput,
			-1,
			1,
		);
		const moveZ = MathUtils.clamp(
			this.input.axis("KeyW", "KeyS") +
				this.input.axis("ArrowUp", "ArrowDown") +
				this.externalForwardInput,
			-1,
			1,
		);

		let wishX = rx * moveX + fx * moveZ;
		let wishZ = rz * moveX + fz * moveZ;
		const wishLen = Math.hypot(wishX, wishZ);

		if (wishLen > 0) {
			wishX = (wishX / wishLen) * speed;
			wishZ = (wishZ / wishLen) * speed;
		}

		if (groundedHit) {
			const vel = groundedHit.body.motionProperties.linearVelocity;
			this.supportVelocity.set(vel[0], vel[1], vel[2]);
		} else {
			this.supportVelocity.set(0, 0, 0);
		}

		rigidBody.setLinearVelocity(this.world, this.body, [
			wishX + this.supportVelocity.x,
			this.grounded && linearVelocity[1] <= this.supportVelocity.y
				? this.supportVelocity.y
				: linearVelocity[1],
			wishZ + this.supportVelocity.z,
		]);

		const spaceDown = this.input.isKeyDown("Space");

		if (spaceDown && !this.spaceWasDown) {
			this.jumpQueued = true;
		}

		this.spaceWasDown = spaceDown;

		if (this.jumpQueued) {
			if (this.sceneSettings.player.canJump && this.grounded) {
				const gravityMagnitude = Math.max(
					0.001,
					Math.hypot(
						this.sceneSettings.world.gravity.x,
						this.sceneSettings.world.gravity.y,
						this.sceneSettings.world.gravity.z,
					),
				);
				const currentVel = this.body.motionProperties.linearVelocity;
				rigidBody.setLinearVelocity(this.world, this.body, [
					currentVel[0],
					this.supportVelocity.y +
						Math.sqrt(2 * gravityMagnitude * this.sceneSettings.player.jumpHeight),
					currentVel[2],
				]);
				this.jumpGroundLockRemaining = JUMP_GROUND_LOCK_SECONDS;
			}

			this.jumpQueued = false;
		}
	}

	updateAfterStep(deltaSeconds: number): void {
		const t = this.body.position;
		this.object.position.set(t[0], t[1], t[2]);

		this.mixer.update(deltaSeconds);

		this.gameplayRuntime.updateActor({
			height: this.standingHeight,
			id: "player",
			position: vec3(t[0], t[1], t[2]),
			radius: this.radius,
			tags: ["player"],
		});
	}

	updateCamera(deltaSeconds: number): void {
		if (!this.inputEnabled) return;
		const delta = this.input.consumeMouseDelta();
		this.yaw -= delta.x * MOUSE_SENSITIVITY_X;
		this.pitch = MathUtils.clamp(
			this.pitch - delta.y * MOUSE_SENSITIVITY_Y,
			this.camera.pitchMin,
			this.camera.pitchMax,
		);

		const t = this.body.position;
		this._eyePosition.set(t[0], t[1] + this.standingHeight * 0.42, t[2]);
		resolveViewDirection(this.yaw, this.pitch, this._viewDirection);

		this.camera.update(this._eyePosition, this._viewDirection, deltaSeconds);
	}

	setRepairing(_isRepairing: boolean): void {}
	setExternalMoveInput(forward: number, strafe: number): void {
		this.externalForwardInput = forward;
		this.externalStrafeInput = strafe;
	}
	setSprintOverride(sprinting: boolean): void {
		this.sprintOverride = sprinting;
	}
	applyOrbitDelta(dx: number, dy: number): void {
		this.yaw -= dx * MOUSE_SENSITIVITY_X;
		this.pitch = MathUtils.clamp(
			this.pitch - dy * MOUSE_SENSITIVITY_Y,
			this.camera.pitchMin,
			this.camera.pitchMax,
		);
	}
	setProne(_prone: boolean): void {}

	// ─── Private ─────────────────────────────────────────────────────────

	private isRunning(): boolean {
		return this.sprintOverride || this.input.isKeyDown("ShiftLeft") || this.input.isKeyDown("ShiftRight");
	}

	private resolveGroundHit(
		translation: CrashcatRigidBody["position"],
	): { body: KinematicBody; fraction: number; normal: [number, number, number] } | undefined {
		for (const contact of this.world.contacts.contacts) {
			if (contact.contactIndex < 0 || contact.numContactPoints === 0) continue;
			if (contact.bodyIdA !== this.body.id && contact.bodyIdB !== this.body.id) continue;

			const supportId = contact.bodyIdA === this.body.id ? contact.bodyIdB : contact.bodyIdA;
			const supportBody = rigidBody.get(this.world, supportId);

			if (!supportBody) continue;

			const normalY =
				contact.bodyIdB === this.body.id ? contact.contactNormal[1] : -contact.contactNormal[1];

			if (normalY < GROUND_MIN_NORMAL_Y) continue;

			return { body: supportBody, fraction: 0, normal: [0, normalY, 0] };
		}

		const probeOriginY = translation[1] - this.footOffset + GROUND_PROBE_HEIGHT;
		const probeOffset = this.radius + 0.05;

		for (const [offsetX, offsetZ] of [
			[probeOffset, 0],
			[-probeOffset, 0],
			[0, probeOffset],
			[0, -probeOffset],
		] as const) {
			const origin: [number, number, number] = [
				translation[0] + offsetX,
				probeOriginY,
				translation[2] + offsetZ,
			];

			this.groundProbeCollector.reset();
			castRay(
				this.world,
				this.groundProbeCollector,
				this.groundProbeSettings,
				origin,
				DOWN_DIRECTION,
				GROUND_PROBE_DISTANCE,
				this.groundProbeFilter,
			);

			const hit = this.groundProbeCollector.hit;

			if (hit.status !== CastRayStatus.COLLIDING) continue;

			const body = rigidBody.get(this.world, hit.bodyIdB);

			if (!body || body.id === this.body.id) continue;

			const hitPoint: [number, number, number] = [
				origin[0],
				origin[1] - GROUND_PROBE_DISTANCE * hit.fraction,
				origin[2],
			];
			const normal = rigidBody.getSurfaceNormal([0, 0, 0], body, hitPoint, hit.subShapeId);

			if (Math.abs(normal[1]) < GROUND_MIN_NORMAL_Y) continue;

			return { body, fraction: hit.fraction, normal };
		}

		return undefined;
	}
}
