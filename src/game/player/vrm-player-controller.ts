/**
 * VrmPlayerController
 *
 * Extends the StarterPlayerController's physics and movement logic with a
 * VRM character model visual instead of the capsule mesh. The invisible
 * physics capsule still provides collision; the VRM model root is a child
 * of `this.object` and follows the capsule position.
 *
 * Owns a VrmAnimatorBridge that is updated each frame, driving Mixamo-sourced
 * animation clips from the ggez animation editor on the VRM skeleton.
 *
 * @see design/gdd/vrm-model-integration.md
 */
import type { VRM } from "@pixiv/three-vrm";
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
	Group,
	MathUtils,
	PerspectiveCamera,
	Vector3,
} from "three";
import { createCameraController, type CameraController, type CameraMode } from "../camera";
import type { InputManager } from "../input";
import type { PlayerController } from "../scene";
import type { VrmCharacterManager, VrmCharacterInstance } from "../../systems/vrm/vrm-character-instance";
import { getVrmConfig } from "../../systems/vrm/vrm-config";
import type { VrmAnimatorBridge } from "../../systems/vrm/vrm-retarget-bridge";
import type { VrmPlayerAnimationController } from "../../systems/vrm/vrm-player-animation-controller";

// ─── Constants ──────────────────────────────────────────────────────────────

const GROUND_MIN_NORMAL_Y = 0.45;
const GROUND_PROBE_DISTANCE = 0.2;
const GROUND_PROBE_HEIGHT = 0.12;
const JUMP_GROUND_LOCK_SECONDS = 0.12;
const MOUSE_SENSITIVITY_X = 0.0024;
const MOUSE_SENSITIVITY_Y = 0.0018;
/** Horizontal speed above which the mesh faces velocity instead of camera yaw. */
const FACING_SPEED_THRESHOLD = 0.1;

/** Fallback when no idle clip loads — arms down instead of T-pose. */
const applyRelaxedArmPose = (vrm: VRM): void => {
	const angle = 1.05;
	const leftArm = vrm.humanoid?.getNormalizedBoneNode("leftUpperArm");
	const rightArm = vrm.humanoid?.getNormalizedBoneNode("rightUpperArm");
	if (leftArm) leftArm.rotation.z = -angle;
	if (rightArm) rightArm.rotation.z = angle;
};

// ─── Types ──────────────────────────────────────────────────────────────────

type VrmPlayerSpawn = {
	position: Vec3;
	rotationY: number;
};

export type VrmPlayerControllerOptions = {
	input: InputManager;
	camera: CameraController;
	threeCamera: PerspectiveCamera;
	gameplayRuntime: GameplayRuntime;
	sceneSettings: Pick<SceneSettings, "player" | "world">;
	spawn: VrmPlayerSpawn;
	world: CrashcatPhysicsWorld;
	/** VRM character manager instance for this scene. */
	characterManager: VrmCharacterManager;
	/** The VRM character instance (already registered with the manager). */
	characterInstance: VrmCharacterInstance;
	/** Animation bridge — may be undefined if no animation bundle is configured. */
	animatorBridge?: VrmAnimatorBridge;
};

type KinematicBody = NonNullable<ReturnType<typeof rigidBody.get>>;

// ─── Controller ─────────────────────────────────────────────────────────────

export class VrmPlayerController implements PlayerController {
	readonly object = new Group();
	inputEnabled = true;

	private readonly body: CrashcatRigidBody;
	private camera: CameraController;
	private readonly threeCamera: PerspectiveCamera;
	private readonly input: InputManager;
	private readonly gameplayRuntime: GameplayRuntime;
	private readonly sceneSettings: Pick<SceneSettings, "player" | "world">;
	private readonly world: CrashcatPhysicsWorld;
	private readonly characterManager: VrmCharacterManager;
	private readonly characterInstance: VrmCharacterInstance;
	private readonly animatorBridge?: VrmAnimatorBridge;
	private playerAnimController: VrmPlayerAnimationController | undefined;
	private isRepairing = false;
	private lastForwardInput = 0;
	private lastStrafeInput = 0;
	private externalForwardInput = 0;
	private externalStrafeInput = 0;
	private sprintOverride = false;
	private jumpTriggeredFrame = false;

	// Capsule dimensions (physics only — no visible capsule)
	private readonly standingHeight: number;
	private readonly radius: number;
	private readonly halfHeight: number;
	private readonly footOffset: number;

	// Look state
	private yaw: number;
	private pitch: number;

	// Jump state
	private jumpQueued = false;
	private spaceWasDown = false;
	private jumpGroundLockRemaining = 0;

	// Ground tracking
	private grounded = false;
	private readonly groundProbeCollector = createClosestCastRayCollector();
	private readonly groundProbeFilter: ReturnType<typeof filter.create>;
	private readonly groundProbeSettings = createDefaultCastRaySettings();
	private readonly supportVelocity = new Vector3();

	// Scratch vectors
	private readonly _eyePosition = new Vector3();
	private readonly _viewDirection = new Vector3();

	constructor(options: VrmPlayerControllerOptions) {
		this.input = options.input;
		this.camera = options.camera;
		this.threeCamera = options.threeCamera;
		this.gameplayRuntime = options.gameplayRuntime;
		this.sceneSettings = options.sceneSettings;
		this.world = options.world;
		this.characterManager = options.characterManager;
		this.characterInstance = options.characterInstance;
		this.animatorBridge = options.animatorBridge;

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

		// Add VRM character root as the visual (no capsule mesh)
		this.object.add(this.characterInstance.root);

		// Physics body — invisible capsule for collision
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

		this.groundProbeFilter.bodyFilter = (candidate) => candidate.id !== this.body.id;
		this.object.position.set(spawnPos.x, spawnPos.y, spawnPos.z);
	}

	// ─── Public ─────────────────────────────────────────────────────────────

	/** Attach the AnimationMixer-driven player animation controller. */
	setAnimationController(controller: VrmPlayerAnimationController): void {
		this.playerAnimController = controller;
		// If no idle clip, nudge arms down from T-pose (voidborne always plays idle).
		if (!controller.hasIdleClip() && this.characterInstance.vrm) {
			applyRelaxedArmPose(this.characterInstance.vrm);
		}
	}

	setCameraMode(mode: CameraMode): void {
		this.camera = createCameraController(mode, this.threeCamera);
		this.camera.setStandingHeight(this.standingHeight);
		this.pitch = MathUtils.clamp(this.pitch, this.camera.pitchMin, this.camera.pitchMax);

		// Toggle first-person head hiding
		this.characterManager.setFirstPersonMode(mode === "fps");
	}

  releasePointerLock(): void {
    this.input.releasePointerLock();
  }

  dispose(): void {
		this.gameplayRuntime.removeActor("player");
		rigidBody.remove(this.world, this.body);
		this.animatorBridge?.dispose();
		this.playerAnimController?.dispose();
		this.characterManager.dispose();
	}

	// ─── Update Hooks ───────────────────────────────────────────────────────

	/**
	 * Fixed-rate update (60 Hz). Apply movement and jump forces.
	 * Identical physics to StarterPlayerController.
	 */
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

		this.lastStrafeInput = MathUtils.clamp(moveX, -1, 1);
		this.lastForwardInput = MathUtils.clamp(moveZ, -1, 1);

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

		// Jump
		const spaceDown = this.input.isKeyDown("Space");

		if (spaceDown && !this.spaceWasDown) {
			this.jumpQueued = true;
		}

		this.spaceWasDown = spaceDown;

		if (this.jumpQueued) {
			if (this.sceneSettings.player.canJump && this.grounded) {
				this.jumpTriggeredFrame = true;
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

  /** Fixed-rate update — sync visual to physics, update animator. */
  updateAfterStep(deltaSeconds: number): void {
    const t = this.body.position;
    this.object.position.set(t[0], t[1], t[2]);

    const velocity = this.body.motionProperties.linearVelocity;
    const horizontalSpeed = Math.hypot(velocity[0], velocity[2]);

    // Grounded movement: face velocity. Idle / airborne: face camera (jump clips are forward-facing).
    const airborne = !this.grounded || velocity[1] > 0.35;
    let facingYaw = this.yaw + Math.PI;
    if (horizontalSpeed > FACING_SPEED_THRESHOLD && !airborne) {
      facingYaw = Math.atan2(velocity[0], velocity[2]);
    }
    this.characterInstance.root.rotation.set(0, facingYaw, 0);

    // Offset VRM model so feet align with capsule bottom
    this.characterInstance.root.position.set(0, -this.footOffset, 0);

    // Show/hide based on camera mode
    this.characterInstance.root.visible = this.camera.showPlayerBody;

    // Drive animation parameters from movement state

    if (this.animatorBridge) {
      this.animatorBridge.animator.setFloat("speed", horizontalSpeed);
      this.animatorBridge.animator.setBool("isGrounded", this.grounded);
      this.animatorBridge.animator.setBool("isRunning", this.isRunning());
      this.animatorBridge.animator.setBool("isJumping", !this.grounded && velocity[1] > 0.5);
      this.animatorBridge.update(deltaSeconds);
    }

    // Match character-loader.ts / voidborne: spring bones + humanoid pass
    // BEFORE the mixer advances clips. Mixer-after-vrm.update was making the
    // skinned mesh vanish on WebGPU (bind pose copied over animated bones).
    if (this.characterInstance.vrm) {
      const config = getVrmConfig();
      const clampedDelta = Math.min(deltaSeconds, config.springBone.maxDeltaSeconds);
      this.characterInstance.vrm.update(clampedDelta);
    }

    if (this.playerAnimController) {
      this.playerAnimController.update(deltaSeconds, {
        speed: horizontalSpeed,
        walkSpeed: this.sceneSettings.player.movementSpeed,
        runSpeed: this.sceneSettings.player.runningSpeed,
        isGrounded: this.grounded,
        jumpTriggered: this.jumpTriggeredFrame,
        strafeInput: this.lastStrafeInput,
        forwardInput: this.lastForwardInput,
        isRepairing: this.isRepairing,
      });
    }
    this.jumpTriggeredFrame = false;

    // Propagate bone transforms to skinned meshes (WebGPU needs explicit sync).
    if (this.characterInstance.vrm) {
      this.characterInstance.vrm.scene.updateMatrixWorld(true);
      this.characterInstance.vrm.scene.traverse((child) => {
        const sk = child as import("three").SkinnedMesh;
        if (sk.isSkinnedMesh && sk.skeleton) {
          sk.skeleton.update();
        }
      });
    }

    // Report actor to gameplay runtime
    this.gameplayRuntime.updateActor({
      height: this.standingHeight,
      id: "player",
      position: vec3(t[0], t[1], t[2]),
      radius: this.radius,
      tags: ["player"]
    });
  }

  /** Called when player starts/stops repairing a subsystem. */
  setRepairing(isRepairing: boolean): void {
    this.isRepairing = isRepairing;
    if (this.animatorBridge) {
      this.animatorBridge.animator.setBool("isRepairing", isRepairing);
    }
  }

  /** Set external movement axes (e.g. gamepad) in [-1, 1]. */
  setExternalMoveInput(forward: number, strafe: number): void {
    this.externalForwardInput = MathUtils.clamp(forward, -1, 1);
    this.externalStrafeInput = MathUtils.clamp(strafe, -1, 1);
  }

  /** Override sprint state (e.g. gamepad trigger held). */
  setSprintOverride(sprinting: boolean): void {
    this.sprintOverride = sprinting;
  }

  /** Apply an orbit delta to the camera directly (e.g. gamepad right stick). */
  applyOrbitDelta(dx: number, dy: number): void {
    this.yaw -= dx * MOUSE_SENSITIVITY_X;
    this.pitch = MathUtils.clamp(
      this.pitch - dy * MOUSE_SENSITIVITY_Y,
      this.camera.pitchMin,
      this.camera.pitchMax,
    );
  }

  /** Set the player prone state (e.g. entering a crawl space). */
  setProne(prone: boolean): void {
    // Not yet implemented for VRM controller
  }

	/** Variable-rate update — camera. */
	updateCamera(deltaSeconds: number): void {
		// When input is disabled (photo mode, opening cinematic, dialogue
		// camera takeover) we yield camera control to whatever set it
		// externally — running our follow update would clobber that pose
		// every frame and produce jitter / wrong framing in screenshots.
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

	// ─── Private ────────────────────────────────────────────────────────────

	private isRunning(): boolean {
		return this.sprintOverride || this.input.isKeyDown("ShiftLeft") || this.input.isKeyDown("ShiftRight");
	}

	private resolveGroundHit(
		translation: CrashcatRigidBody["position"],
	): { body: KinematicBody; fraction: number; normal: [number, number, number] } | undefined {
		// Pass 1 — contacts in manifold
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

		// Pass 2 — ray probes
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

// ─── Module Helpers ─────────────────────────────────────────────────────────

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
