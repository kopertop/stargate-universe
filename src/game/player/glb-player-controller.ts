/**
 * GlbPlayerController
 *
 * Player controller that loads a standard GLB/glTF character model instead
 * of the capsule mesh. Uses Three.js AnimationMixer for embedded animations
 * (e.g., idle, walk clips baked into the GLB).
 *
 * This is the practical path for Meshy AI / non-VRM models. For VRM models
 * with humanoid metadata, use VrmPlayerController instead.
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
	AnimationAction,
	AnimationMixer,
	Group,
	MathUtils,
	Mesh,
	MeshStandardMaterial,
	PerspectiveCamera,
	SkinnedMesh,
	Vector3,
} from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { createCameraController, type CameraController, type CameraMode } from "../camera";
import type { InputManager } from "../input";
import type { PlayerController } from "../scene";

// ─── Constants ──────────────────────────────────────────────────────────────

const GROUND_MIN_NORMAL_Y = 0.45;
const GROUND_PROBE_DISTANCE = 0.2;
const GROUND_PROBE_HEIGHT = 0.12;
const JUMP_GROUND_LOCK_SECONDS = 0.12;
const MOUSE_SENSITIVITY_X = 0.0024;
const MOUSE_SENSITIVITY_Y = 0.0018;

// ─── Types ──────────────────────────────────────────────────────────────────

export type GlbPlayerControllerOptions = {
	input: InputManager;
	camera: CameraController;
	threeCamera: PerspectiveCamera;
	gameplayRuntime: GameplayRuntime;
	sceneSettings: Pick<SceneSettings, "player" | "world">;
	spawn: { position: Vec3; rotationY: number };
	world: CrashcatPhysicsWorld;
	/** URL to the character GLB model (static/idle pose). */
	modelUrl: string;
	/** Optional URL to a GLB with a walking animation. */
	walkAnimationUrl?: string;
	/** Scale multiplier for the model (default: 1). */
	modelScale?: number;
	/** Vertical offset from capsule center (default: auto-calculated). */
	modelYOffset?: number;
};

type KinematicBody = NonNullable<ReturnType<typeof rigidBody.get>>;

// ─── Controller ─────────────────────────────────────────────────────────────

export class GlbPlayerController implements PlayerController {
	readonly object = new Group();

	private readonly body: CrashcatRigidBody;
	private camera: CameraController;
	private readonly threeCamera: PerspectiveCamera;
	private readonly input: InputManager;
	private readonly gameplayRuntime: GameplayRuntime;
	private readonly sceneSettings: Pick<SceneSettings, "player" | "world">;
	private readonly world: CrashcatPhysicsWorld;

	// Capsule dimensions
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

	// Model + animation
	private readonly modelRoot = new Group();
	private mixer: AnimationMixer | undefined;
	private walkAction: AnimationAction | undefined;
	private modelLoaded = false;
	private readonly modelScale: number;
	private readonly modelYOffset: number | undefined;

	// Scratch vectors
	private readonly _eyePosition = new Vector3();
	private readonly _viewDirection = new Vector3();

	constructor(options: GlbPlayerControllerOptions) {
		this.input = options.input;
		this.camera = options.camera;
		this.threeCamera = options.threeCamera;
		this.gameplayRuntime = options.gameplayRuntime;
		this.sceneSettings = options.sceneSettings;
		this.world = options.world;
		this.modelScale = options.modelScale ?? 1;
		this.modelYOffset = options.modelYOffset;

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

		// Model root — will hold the loaded GLB scene
		this.modelRoot.name = "glb-player-model";
		this.object.add(this.modelRoot);

		// Physics body
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

		// Begin async model loading
		this.loadModel(options.modelUrl, options.walkAnimationUrl);
	}

	// ─── Public ─────────────────────────────────────────────────────────────

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
		this.mixer?.stopAllAction();
	}

	// ─── Update Hooks ───────────────────────────────────────────────────────

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

		const moveX =
			this.input.axis("KeyD", "KeyA") + this.input.axis("ArrowRight", "ArrowLeft");
		const moveZ =
			this.input.axis("KeyW", "KeyS") + this.input.axis("ArrowUp", "ArrowDown");

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

		// Rotate model to face movement direction
		this.modelRoot.rotation.set(0, this.yaw + Math.PI, 0);

		// Offset model so feet align with capsule bottom
		const yOff = this.modelYOffset ?? -this.footOffset;
		this.modelRoot.position.set(0, yOff, 0);

		// Show/hide based on camera mode
		this.modelRoot.visible = this.camera.showPlayerBody;

		// Drive animation based on movement
		if (this.mixer) {
			const velocity = this.body.motionProperties.linearVelocity;
			const horizontalSpeed = Math.hypot(velocity[0], velocity[2]);

			if (this.walkAction) {
				if (horizontalSpeed > 0.5) {
					if (!this.walkAction.isRunning()) {
						this.walkAction.play();
					}

					// Scale animation speed with movement speed
					this.walkAction.timeScale = MathUtils.clamp(horizontalSpeed / 4.5, 0.5, 2.0);
				} else {
					if (this.walkAction.isRunning()) {
						this.walkAction.fadeOut(0.2);
						// Reset so it can fade back in
						setTimeout(() => {
							this.walkAction?.reset();
							this.walkAction?.stop();
						}, 200);
					}
				}
			}

			this.mixer.update(deltaSeconds);
		}

		// Report actor
		this.gameplayRuntime.updateActor({
			height: this.standingHeight,
			id: "player",
			position: vec3(t[0], t[1], t[2]),
			radius: this.radius,
			tags: ["player"],
		});
	}

	updateCamera(deltaSeconds: number): void {
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

	// ─── Model Loading ──────────────────────────────────────────────────────

	private async loadModel(modelUrl: string, walkAnimationUrl?: string): Promise<void> {
		const loader = new GLTFLoader();

		try {
			const gltf = await loader.loadAsync(modelUrl);
			const modelScene = gltf.scene;

			// Scale model
			modelScene.scale.setScalar(this.modelScale);

			// Enable shadows on all meshes
			modelScene.traverse((child) => {
				if ((child as Mesh).isMesh || (child as SkinnedMesh).isSkinnedMesh) {
					child.castShadow = true;
					child.receiveShadow = true;
					// Disable frustum culling for skinned meshes
					child.frustumCulled = false;
				}
			});

			this.modelRoot.add(modelScene);
			this.modelLoaded = true;

			// Set up animation mixer
			this.mixer = new AnimationMixer(modelScene);

			// Check for embedded animations in the character model
			if (gltf.animations.length > 0) {
				console.info(
					`[GlbPlayerController] Found ${gltf.animations.length} embedded animation(s):`,
					gltf.animations.map((a) => a.name),
				);
			}

			// Load walking animation from separate file if provided
			if (walkAnimationUrl) {
				try {
					const walkGltf = await loader.loadAsync(walkAnimationUrl);

					if (walkGltf.animations.length > 0) {
						const walkClip = walkGltf.animations[0];
						this.walkAction = this.mixer.clipAction(walkClip, modelScene);
						this.walkAction.setLoop(2200, Infinity); // LoopRepeat
						console.info(`[GlbPlayerController] Walk animation loaded: "${walkClip.name}" (${walkClip.duration.toFixed(2)}s)`);
					}
				} catch (error) {
					console.warn("[GlbPlayerController] Failed to load walk animation:", error);
				}
			} else if (gltf.animations.length > 0) {
				// Use first embedded animation as walk
				this.walkAction = this.mixer.clipAction(gltf.animations[0]);
				this.walkAction.setLoop(2200, Infinity);
			}

			console.info(`[GlbPlayerController] Model loaded from ${modelUrl}`);
		} catch (error) {
			console.error("[GlbPlayerController] Failed to load model:", error);
		}
	}

	// ─── Ground Detection ───────────────────────────────────────────────────

	private isRunning(): boolean {
		return this.input.isKeyDown("ShiftLeft") || this.input.isKeyDown("ShiftRight");
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
