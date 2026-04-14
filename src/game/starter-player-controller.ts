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
  type CrashcatRigidBody
} from "@ggez/runtime-physics-crashcat";
import {
  BoxGeometry,
  CapsuleGeometry,
  Group,
  MathUtils,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  Scene,
  SphereGeometry,
  Vector3
} from "three";

import { AudioManager } from "../systems/audio";
import {
  addCharacter,
  getCharacter,
  removeCharacter,
  RepairVfx,
  setActiveCamera,
  setFirstPersonMode,
  updateVrmCharacters,
  VrmPlayerAnimationController,
  type VrmCharacterInstance,
} from "../systems/vrm";

type StarterPlayerSpawn = {
  position: Vec3;
  rotationY: number;
};

type StarterPlayerControllerOptions = {
  camera: PerspectiveCamera;
  cameraMode: SceneSettings["player"]["cameraMode"];
  domElement: HTMLCanvasElement;
  gameplayRuntime: GameplayRuntime;
  scene: Scene;
  sceneSettings: Pick<SceneSettings, "player" | "world">;
  spawn: StarterPlayerSpawn;
  /** Optional path to a VRM model file for the player character. */
  vrmUrl?: string;
  world: CrashcatPhysicsWorld;
};

const GROUND_MIN_NORMAL_Y = 0.45;
const GROUND_PROBE_DISTANCE = 0.2;
const GROUND_PROBE_HEIGHT = 0.12;
const JUMP_GROUND_LOCK_SECONDS = 0.12;

export class StarterPlayerController {
  readonly object = new Group();

  private readonly body: CrashcatRigidBody;
  private readonly camera: PerspectiveCamera;
  private cameraMode: SceneSettings["player"]["cameraMode"];
  private readonly domElement: HTMLCanvasElement;
  private readonly footOffset: number;
  private readonly gameplayRuntime: GameplayRuntime;
  private readonly groundProbeCollector = createClosestCastRayCollector();
  private readonly groundProbeFilter: ReturnType<typeof filter.create>;
  private readonly groundProbeSettings = createDefaultCastRaySettings();
  private readonly halfHeight: number;
  private jumpGroundLockRemaining = 0;
  private jumpQueued = false;
  private readonly keyState = new Set<string>();
  private lastGrounded = false;
  private pitch = 0;
  private pointerLocked = false;
  private readonly radius: number;
  private readonly scene: Scene;
  private readonly sceneSettings: Pick<SceneSettings, "player" | "world">;
  private readonly standingHeight: number;
  private readonly supportVelocity = new Vector3();
  private readonly visual: Group;
  private animController: VrmPlayerAnimationController | undefined;
  private forwardInput = 0;
  private isRepairing = false;
  private repairVfx: RepairVfx | undefined;
  private strafeInput = 0;
  private vrmCharacter: VrmCharacterInstance | undefined;
  private readonly world: CrashcatPhysicsWorld;
  private yaw = 0;
  /** Separate yaw for the character mesh — lerps toward movement direction independently of camera. */
  private meshYaw = 0;

  // ── External (gamepad) input override ──────────────────────────────────────
  /** External forward/strafe axes [-1, 1]. Blended with keyboard via max-magnitude. */
  private _extForward = 0;
  private _extStrafe = 0;
  /** When true, counts as sprint regardless of Shift key. */
  private _extSprint = false;

  // ── Cinematic input gate ───────────────────────────────────────────────────
  private _inputEnabled = true;

  get inputEnabled() { return this._inputEnabled; }
  set inputEnabled(v: boolean) {
    this._inputEnabled = v;
    if (!v) {
      this.keyState.clear();
      this.releasePointerLock();
    }
  }

  // ── Prone / stand-up state ────────────────────────────────────────────────
  // Three-phase wake-up driven by the Mixamo "Getting Up" clip:
  //   'prone'    — getting-up anim paused at frame 0 (supine pose);
  //                mixer runs but the anim is frozen
  //   'standing' — getting-up anim playing forward (slow = 0.6x) toward
  //                its final standing pose; movement still locked
  //   'none'     — normal gameplay, idle anim has taken over
  private _pronePhase: "prone" | "standing" | "none" = "none";
  private _proneStartedAt = 0;   // performance.now() when setProne(true) fired
  private _standStartedAt = 0;   // performance.now() when phase flipped to 'standing'
  private readonly PRONE_MIN_HOLD_MS = 2500;   // hold flat for this long before reacting to input
  private readonly STAND_DURATION_MS = 2200;   // slow-mo get-up lerp time

  get isProne(): boolean { return this._pronePhase !== "none"; }

  /**
   * Begin the prone wake-up sequence. Cues the Mixamo "Getting Up"
   * clip paused at frame 0 so the player model is posed supine.
   * Movement is blocked until the standing clip finishes.
   *
   * If the clip isn't loaded (e.g. R2 fetch failed), the controller
   * falls back to a simple rotation hack so the player still reads
   * as "on their back".
   */
  setProne(prone: boolean): void {
    if (prone) {
      this._pronePhase = "prone";
      this._proneStartedAt = performance.now();
      this.applyProneRotation();
      // PAUSE the animation mixer so the idle clip doesn't spin the
      // character while we've manually rotated the root.
      this.animController?.setPaused(true);
      this.keyState.clear();
    } else {
      this._pronePhase = "none";
      if (this.vrmCharacter?.vrm) this.vrmCharacter.root.rotation.x = 0;
      this.animController?.setPaused(false);
    }
  }

  /**
   * Apply the supine rotation to the VRM root. Idempotent — safe to
   * call every frame while prone. Also re-applies after VRM finishes
   * loading if setProne(true) was called before the model was ready.
   */
  private applyProneRotation(): void {
    if (this.vrmCharacter?.vrm) {
      this.vrmCharacter.root.rotation.x = -Math.PI / 2;
    }
  }

  /** Advance the wake-up state machine. Called from updateAfterStep. */
  private updateProne(): void {
    if (this._pronePhase === "prone") {
      // Re-apply supine rotation each frame — updateAfterStep below
      // writes yaw, and we want X to stay locked at -π/2 regardless.
      this.applyProneRotation();
      const now = performance.now();
      // Hold on the ground for at least PRONE_MIN_HOLD_MS for drama —
      // the cinematic just ended, Scott's dialogue is about to start.
      if (now - this._proneStartedAt < this.PRONE_MIN_HOLD_MS) return;
      // Auto-transition to standing after the hold — the player should be
      // "slowly getting up" as the dialogue opens, not frozen until they
      // tap a movement key. Movement intent also works as a fast-forward.
      this._pronePhase = "standing";
      this._standStartedAt = now;
    } else if (this._pronePhase === "standing") {
      // Manual slow lerp back to upright so the player sees a
      // 2-second "getting up" motion. Once the Mixamo clip lands
      // on R2 and we can confirm its frame-0 pose, swap to the
      // animation-driven path (see old commits).
      const t = Math.min(1, (performance.now() - this._standStartedAt) / this.STAND_DURATION_MS);
      const eased = 1 - Math.pow(1 - t, 2);
      if (this.vrmCharacter?.vrm) {
        this.vrmCharacter.root.rotation.x = -Math.PI / 2 * (1 - eased);
      }
      if (t >= 1) {
        this._pronePhase = "none";
        if (this.vrmCharacter?.vrm) this.vrmCharacter.root.rotation.x = 0;
        this.animController?.setPaused(false);
      }
    }
  }

  /** Detect movement intent — used to auto-stand up from prone. */
  private hasMovementIntent(): boolean {
    if (Math.abs(this._extForward) > 0.1 || Math.abs(this._extStrafe) > 0.1) return true;
    return this.keyState.has("KeyW") || this.keyState.has("KeyA")
        || this.keyState.has("KeyS") || this.keyState.has("KeyD")
        || this.keyState.has("ArrowUp") || this.keyState.has("ArrowDown")
        || this.keyState.has("ArrowLeft") || this.keyState.has("ArrowRight");
  }

  constructor(options: StarterPlayerControllerOptions) {
    this.camera = options.camera;
    this.cameraMode = options.cameraMode;
    this.domElement = options.domElement;
    this.gameplayRuntime = options.gameplayRuntime;
    this.scene = options.scene;
    this.sceneSettings = options.sceneSettings;
    this.world = options.world;
    this.standingHeight = Math.max(1.2, options.sceneSettings.player.height);
    this.radius = MathUtils.clamp(this.standingHeight * 0.18, 0.24, 0.42);
    this.halfHeight = Math.max(0.12, this.standingHeight * 0.5 - this.radius);
    this.footOffset = this.halfHeight + this.radius;
    this.yaw = options.spawn.rotationY;
    this.pitch = defaultPitchForCameraMode(this.cameraMode);
    this.groundProbeFilter = filter.create(this.world.settings.layers);
    this.groundProbeFilter.bodyFilter = (candidate) => candidate.id !== this.body.id;
    this.groundProbeSettings.collideWithBackfaces = true;
    this.groundProbeSettings.treatConvexAsSolid = false;

    // ── Soldier character mesh (primitives: body + head + shoulders) ──────────
    // Entire group is positioned so feet align with the base of the physics capsule.
    const h = this.standingHeight;
    const r = this.radius;

    const torsoMat = new MeshStandardMaterial({ color: 0x1e2033, roughness: 0.75, metalness: 0.15 });
    const legMat   = new MeshStandardMaterial({ color: 0x14141e, roughness: 0.85 });
    const headMat  = new MeshStandardMaterial({ color: 0x2a2a3c, roughness: 0.65 });
    const padMat   = new MeshStandardMaterial({ color: 0x111122, roughness: 0.6, metalness: 0.3 });

    // Legs (lower capsule)
    const legMesh  = new Mesh(new CapsuleGeometry(r * 0.88, h * 0.3, 4, 8), legMat);
    legMesh.position.y = h * 0.22;
    legMesh.castShadow = true; legMesh.receiveShadow = true;

    // Torso (upper capsule)
    const torsoMesh = new Mesh(new CapsuleGeometry(r * 1.05, h * 0.22, 4, 8), torsoMat);
    torsoMesh.position.y = h * 0.6;
    torsoMesh.castShadow = true; torsoMesh.receiveShadow = true;

    // Head (sphere, slight forward offset for over-the-shoulder readability)
    const headMesh = new Mesh(new SphereGeometry(r * 0.82, 10, 8), headMat);
    headMesh.position.set(0, h * 0.88, r * 0.08);
    headMesh.castShadow = true; headMesh.receiveShadow = true;

    // Shoulder pads
    const padGeo = new BoxGeometry(r * 0.72, r * 0.44, r * 0.88);
    const leftPad  = new Mesh(padGeo, padMat);
    const rightPad = new Mesh(padGeo, padMat);
    leftPad.position.set(-r * 1.35, h * 0.69, 0);
    rightPad.position.set( r * 1.35, h * 0.69, 0);
    leftPad.castShadow = true;  leftPad.receiveShadow = true;
    rightPad.castShadow = true; rightPad.receiveShadow = true;

    this.visual = new Group();
    this.visual.name = "capsule-fallback";
    // Offset so feet sit at the bottom of the physics capsule
    this.visual.position.y = -this.footOffset;
    this.visual.add(legMesh, torsoMesh, headMesh, leftPad, rightPad);

    const spawnPosition = {
      x: options.spawn.position.x,
      y: options.spawn.position.y + this.standingHeight * 0.5 + 0.04,
      z: options.spawn.position.z
    };
    this.body = rigidBody.create(this.world, {
      allowSleeping: false,
      allowedDegreesOfFreedom: dof(true, true, true, false, false, false),
      friction: 0,
      linearDamping: 0.8,
      motionQuality: MotionQuality.LINEAR_CAST,
      motionType: MotionType.DYNAMIC,
      objectLayer: CRASHCAT_OBJECT_LAYER_MOVING,
      position: [spawnPosition.x, spawnPosition.y, spawnPosition.z],
      shape: capsule.create({
        halfHeightOfCylinder: this.halfHeight,
        radius: this.radius
      })
    });
    this.groundProbeFilter.bodyFilter = (candidate) => candidate.id !== this.body.id;

    this.object.add(this.visual);
    this.object.position.set(spawnPosition.x, spawnPosition.y, spawnPosition.z);
    this.meshYaw = this.yaw; // sync initial mesh facing to spawn rotation

    // Attach audio listener to camera
    AudioManager.getInstance().attachListener(this.camera);

    // VRM character model (replaces capsule visual when loaded)
    if (options.vrmUrl) {
      this.initVrmCharacter(options.vrmUrl);
    }

    this.domElement.addEventListener("click", this.handleCanvasClick);
    window.addEventListener("blur", this.handleWindowBlur);
    window.addEventListener("keydown", this.handleKeyDown);
    window.addEventListener("keyup", this.handleKeyUp);
    window.addEventListener("mousemove", this.handleMouseMove);
  }

  dispose() {
    this.releasePointerLock();
    this.domElement.removeEventListener("click", this.handleCanvasClick);
    window.removeEventListener("blur", this.handleWindowBlur);
    window.removeEventListener("keydown", this.handleKeyDown);
    window.removeEventListener("keyup", this.handleKeyUp);
    window.removeEventListener("mousemove", this.handleMouseMove);
    this.gameplayRuntime.removeActor("player");
    rigidBody.remove(this.world, this.body);

    if (this.repairVfx) {
      this.repairVfx.dispose();
      this.repairVfx = undefined;
    }

    if (this.animController) {
      this.animController.dispose();
      this.animController = undefined;
    }

    if (this.vrmCharacter) {
      removeCharacter("player");
      this.vrmCharacter = undefined;
    }
  }

  releasePointerLock() {
    if (document.pointerLockElement === this.domElement) {
      document.exitPointerLock();
    }

    this.pointerLocked = false;
  }

  /** Get the VRM character instance (if VRM loading was initiated). */
  getVrmCharacter(): VrmCharacterInstance | undefined {
    return this.vrmCharacter;
  }

  /** Set whether the player is currently performing a repair action. */
  setRepairing(repairing: boolean): void {
    if (this.isRepairing === repairing) return;
    this.isRepairing = repairing;

    const audio = AudioManager.getInstance();
    if (repairing) {
      this.repairVfx?.start();
      audio.play("repair-sparks", this.object);
    } else {
      this.repairVfx?.stop();
      audio.stop("repair-sparks", this.object);
    }
  }

  /**
   * Apply a yaw/pitch delta from an external source (e.g. right gamepad stick).
   * Pitch is clamped to the same limits as mouse look.
   */
  applyOrbitDelta(deltaYaw: number, deltaPitch: number): void {
    this.yaw -= deltaYaw;
    const pitchMin = this.cameraMode === "fps" ? -1.35 : -1.25;
    const pitchMax = this.cameraMode === "fps" ? 1.35 : this.cameraMode === "top-down" ? -0.12 : 0.4;
    this.pitch = MathUtils.clamp(this.pitch - deltaPitch, pitchMin, pitchMax);
  }

  /**
   * Set external movement axes (e.g. left gamepad stick) in [-1, 1].
   * These are blended with keyboard input: the axis with higher magnitude wins.
   */
  setExternalMoveInput(forward: number, strafe: number): void {
    this._extForward = MathUtils.clamp(forward, -1, 1);
    this._extStrafe = MathUtils.clamp(strafe, -1, 1);
  }

  /** Override sprint state from an external source (e.g. B/Circle button). */
  setSprintOverride(active: boolean): void {
    this._extSprint = active;
  }

  setCameraMode(cameraMode: SceneSettings["player"]["cameraMode"]) {
    this.cameraMode = cameraMode;

    // Update first-person head hiding when camera mode changes
    if (this.vrmCharacter?.vrm) {
      setFirstPersonMode(cameraMode === "fps", this.camera);
    }
  }

  updateAfterStep(deltaSeconds: number) {
    const translation = this.body.position;
    this.object.position.set(translation[0], translation[1], translation[2]);
    // Advance the wake-up state machine (prone / standing / none).
    this.updateProne();
    // Use meshYaw so the character faces movement direction, not camera direction
    this.visual.rotation.set(0, this.meshYaw, 0);

    // VRM character: rotate the VRM root to face movement direction.
    // While prone, the getting-up animation owns the X rotation — only
    // set the Y yaw so we don't trample the supine pose.
    if (this.vrmCharacter?.vrm) {
      const root = this.vrmCharacter.root;
      root.rotation.y = this.meshYaw + Math.PI;
      if (this._pronePhase === "none") {
        root.rotation.x = 0;
        root.rotation.z = 0;
      }
      // Permanently remove capsule fallback once VRM is loaded — setting
      // visible=false was unreliable because restorePlayerVisual and other
      // traversals could re-enable children. Removing from parent is final.
      if (this.visual.parent) {
        this.visual.parent.remove(this.visual);
      }
      // Handle first-person head hiding
      setFirstPersonMode(this.cameraMode === "fps", this.camera);

      // Lazy-init animation controller and repair VFX once VRM is loaded
      if (!this.animController) {
        this.animController = new VrmPlayerAnimationController(this.vrmCharacter.vrm);
        this.animController.loadClips("/animations/player");
        this.repairVfx = new RepairVfx(this.vrmCharacter.vrm, this.scene);
      }

      // Update animations BEFORE vrm.update() so spring bones run on animated pose
      if (this.animController) {
        const velocity = this.body.motionProperties.linearVelocity;
        const horizontalSpeed = Math.sqrt(velocity[0] ** 2 + velocity[2] ** 2);
        this.animController.update(deltaSeconds, {
          speed: horizontalSpeed,
          walkSpeed: this.sceneSettings.player.movementSpeed,
          runSpeed: this.sceneSettings.player.runningSpeed,
          isGrounded: this.lastGrounded,
          jumpTriggered: this.jumpGroundLockRemaining > 0,
          strafeInput: this.strafeInput,
          forwardInput: this.forwardInput,
          isRepairing: this.isRepairing,
        });
      }

      // Update repair VFX (spark particles)
      this.repairVfx?.update(deltaSeconds);

      // Update VRM systems (spring bones, expressions, LOD)
      updateVrmCharacters(deltaSeconds, 60);
    } else {
      this.visual.visible = this.cameraMode !== "fps";
    }

    const eyePosition = new Vector3(
      translation[0],
      translation[1] + this.standingHeight * 0.42,
      translation[2]
    );
    const viewDirection = resolveViewDirection(this.yaw, this.pitch, new Vector3());

    if (this.cameraMode === "fps") {
      this.camera.position.copy(eyePosition);
      this.camera.lookAt(eyePosition.clone().add(viewDirection));
    } else if (this.cameraMode === "third-person") {
      // Over-the-shoulder orbit: pivot at chest/shoulder height, 3.5 units back.
      // Camera orbits freely via yaw/pitch; character mesh faces movement direction.
      const ORBIT_DISTANCE = 7.0;
      const lookTarget = scratchLookTarget.set(
        translation[0],
        translation[1] + this.standingHeight * 0.72, // chest/shoulder pivot
        translation[2]
      );
      const targetCameraPosition = scratchTargetCamPos
        .copy(lookTarget)
        .addScaledVector(viewDirection, -ORBIT_DISTANCE);
      // Guarantee at least 1.5 units above player center (prevents floor-clipping on steep downward pitch)
      const minCamY = translation[1] + 1.5;
      if (targetCameraPosition.y < minCamY) targetCameraPosition.y = minCamY;
      // Spring-lerp for smooth follow — exp(-8t) gives ~33% remaining lag at 60fps
      this.camera.position.lerp(targetCameraPosition, 1 - Math.exp(-deltaSeconds * 8));
      this.camera.lookAt(lookTarget);
    } else {
      const followDistance = Math.max(14, this.standingHeight * 10);
      const targetCameraPosition = eyePosition.clone().addScaledVector(viewDirection, -followDistance);
      targetCameraPosition.y += this.standingHeight * 1.8;
      this.camera.position.lerp(targetCameraPosition, 1 - Math.exp(-deltaSeconds * 8));
      this.camera.lookAt(eyePosition);
    }

    this.gameplayRuntime.updateActor({
      height: this.standingHeight,
      id: "player",
      position: vec3(translation[0], translation[1], translation[2]),
      radius: this.radius,
      tags: ["player"]
    });
  }

  updateBeforeStep(deltaSeconds: number) {
    this.jumpGroundLockRemaining = Math.max(0, this.jumpGroundLockRemaining - deltaSeconds);
    const translation = this.body.position;
    const linearVelocity = this.body.motionProperties.linearVelocity;
    const groundedHit = this.jumpGroundLockRemaining > 0 ? undefined : this.resolveGroundHit(translation);
    const grounded = groundedHit !== undefined;
    const speed =
      this.sceneSettings.player.canRun && this.isRunning()
        ? this.sceneSettings.player.runningSpeed
        : this.sceneSettings.player.movementSpeed;
    const viewDirection = resolveViewDirection(this.yaw, this.pitch, scratchViewDirection);
    const forward = scratchForward.set(viewDirection.x, 0, viewDirection.z);

    if (forward.lengthSq() > 0) {
      forward.normalize();
    } else {
      forward.set(0, 0, -1);
    }

    const right = scratchRight.set(-forward.z, 0, forward.x).normalize();

    // Store raw input axes for the animation system — blend keyboard with external (gamepad)
    const kbStrafe = this.axis("KeyD", "ArrowRight") - this.axis("KeyA", "ArrowLeft");
    const kbForward = this.axis("KeyW", "ArrowUp") - this.axis("KeyS", "ArrowDown");
    // Pick whichever source has higher magnitude on each axis
    this.strafeInput = Math.abs(this._extStrafe) > Math.abs(kbStrafe) ? this._extStrafe : kbStrafe;
    this.forwardInput = Math.abs(this._extForward) > Math.abs(kbForward) ? this._extForward : kbForward;

    // Prone / standing — zero movement axes so the character doesn't
    // slide on the floor during the wake-up animation. The phase
    // machine in updateProne() handles the transition out.
    if (this._pronePhase !== "none") {
      this.strafeInput = 0;
      this.forwardInput = 0;
    }

    const moveDirection = scratchMoveDirection
      .set(0, 0, 0)
      .addScaledVector(right, this.strafeInput)
      .addScaledVector(forward, this.forwardInput);

    // ── Decouple mesh yaw from camera yaw ───────────────────────────────────
    // Rotate the character mesh toward movement direction so camera can orbit
    // freely while the player mesh faces where they're going (Skyrim-style).
    if (moveDirection.lengthSq() > 1e-4) {
      const targetMeshYaw = Math.atan2(-moveDirection.x, -moveDirection.z);
      let yawDelta = targetMeshYaw - this.meshYaw;
      // Shortest-path wrap to [-π, π]
      while (yawDelta >  Math.PI) yawDelta -= 2 * Math.PI;
      while (yawDelta < -Math.PI) yawDelta += 2 * Math.PI;
      this.meshYaw += yawDelta * Math.min(1, deltaSeconds * 12);
    }

    if (moveDirection.lengthSq() > 0) {
      moveDirection.normalize().multiplyScalar(speed);
    }

    if (groundedHit) {
      const velocity = groundedHit.body.motionProperties.linearVelocity;
      this.supportVelocity.set(velocity[0], velocity[1], velocity[2]);
    } else {
      this.supportVelocity.set(0, 0, 0);
    }

    rigidBody.setLinearVelocity(this.world, this.body, [
      moveDirection.x + this.supportVelocity.x,
      grounded && linearVelocity[1] <= this.supportVelocity.y ? this.supportVelocity.y : linearVelocity[1],
      moveDirection.z + this.supportVelocity.z
    ]);

    if (this.jumpQueued) {
      if (this.sceneSettings.player.canJump && grounded) {
        const gravityMagnitude = Math.max(
          0.001,
          Math.hypot(
            this.sceneSettings.world.gravity.x,
            this.sceneSettings.world.gravity.y,
            this.sceneSettings.world.gravity.z
          )
        );
        const currentVelocity = this.body.motionProperties.linearVelocity;
        rigidBody.setLinearVelocity(this.world, this.body, [
          currentVelocity[0],
          this.supportVelocity.y + Math.sqrt(2 * gravityMagnitude * this.sceneSettings.player.jumpHeight),
          currentVelocity[2]
        ]);
        this.jumpGroundLockRemaining = JUMP_GROUND_LOCK_SECONDS;
      }

      this.jumpQueued = false;
    }

    this.lastGrounded = grounded;
  }

  private initVrmCharacter(vrmUrl: string): void {
    setActiveCamera(this.camera);
    this.vrmCharacter = addCharacter({
      id: "player",
      vrmUrl,
      isPlayer: true,
      priority: 0,
    });
    // Offset VRM root down so feet align with the bottom of the physics capsule.
    // The controller's object.position is at capsule center; VRM feet are at Y=0.
    this.vrmCharacter.root.position.y = -this.footOffset;
    // Attach VRM root to the controller's scene group
    this.object.add(this.vrmCharacter.root);
  }

  private axis(primary: string, secondary: string) {
    return this.keyState.has(primary) || this.keyState.has(secondary) ? 1 : 0;
  }

  private isRunning() {
    return this._extSprint || this.keyState.has("ShiftLeft") || this.keyState.has("ShiftRight");
  }

  private resolveGroundHit(translation: CrashcatRigidBody["position"]) {
    for (const contact of this.world.contacts.contacts) {
      if (contact.contactIndex < 0 || contact.numContactPoints === 0) {
        continue;
      }

      if (contact.bodyIdA !== this.body.id && contact.bodyIdB !== this.body.id) {
        continue;
      }

      const supportBodyId = contact.bodyIdA === this.body.id ? contact.bodyIdB : contact.bodyIdA;
      const supportBody = rigidBody.get(this.world, supportBodyId);

      if (!supportBody) {
        continue;
      }

      const normalY = contact.bodyIdB === this.body.id ? contact.contactNormal[1] : -contact.contactNormal[1];

      if (normalY < GROUND_MIN_NORMAL_Y) {
        continue;
      }

      return {
        body: supportBody,
        fraction: 0,
        normal: [0, normalY, 0] as [number, number, number]
      };
    }

    const probeOriginY = translation[1] - this.footOffset + GROUND_PROBE_HEIGHT;
    const probeOffset = this.radius + 0.05;

    for (const [offsetX, offsetZ] of [
      [probeOffset, 0],
      [-probeOffset, 0],
      [0, probeOffset],
      [0, -probeOffset]
    ] as const) {
      const origin: [number, number, number] = [
        translation[0] + offsetX,
        probeOriginY,
        translation[2] + offsetZ
      ];

      this.groundProbeCollector.reset();
      castRay(
        this.world,
        this.groundProbeCollector,
        this.groundProbeSettings,
        origin,
        DOWN_DIRECTION,
        GROUND_PROBE_DISTANCE,
        this.groundProbeFilter
      );

      const hit = this.groundProbeCollector.hit;

      if (hit.status !== CastRayStatus.COLLIDING) {
        continue;
      }

      const body = rigidBody.get(this.world, hit.bodyIdB);

      if (!body || body.id === this.body.id) {
        continue;
      }

      const hitPoint: [number, number, number] = [
        origin[0],
        origin[1] - GROUND_PROBE_DISTANCE * hit.fraction,
        origin[2]
      ];
      const normal = rigidBody.getSurfaceNormal([0, 0, 0], body, hitPoint, hit.subShapeId);

      if (Math.abs(normal[1]) < GROUND_MIN_NORMAL_Y) {
        continue;
      }

      return {
        body,
        fraction: hit.fraction,
        normal
      };
    }

    return undefined;
  }

  private readonly handleCanvasClick = () => {
    if (document.pointerLockElement === this.domElement) {
      return;
    }

    void this.domElement.requestPointerLock();
  };

  private readonly handleKeyDown = (event: KeyboardEvent) => {
    if (!this._inputEnabled) return;
    if (isTextInputTarget(event.target)) {
      return;
    }

    this.keyState.add(event.code);

    if (event.code === "Space") {
      this.jumpQueued = true;
      event.preventDefault();
    }
  };

  private readonly handleKeyUp = (event: KeyboardEvent) => {
    if (!this._inputEnabled) return;
    this.keyState.delete(event.code);
  };

  private readonly handleMouseMove = (event: MouseEvent) => {
    if (!this._inputEnabled) return;
    this.pointerLocked = document.pointerLockElement === this.domElement;

    if (!this.pointerLocked) {
      return;
    }

    this.yaw -= event.movementX * 0.0024;
    this.pitch = MathUtils.clamp(
      this.pitch - event.movementY * 0.0018,
      this.cameraMode === "fps" ? -1.35 : -1.25,
      this.cameraMode === "fps" ? 1.35 : this.cameraMode === "top-down" ? -0.12 : 0.4
    );
  };

  private readonly handleWindowBlur = () => {
    this.keyState.clear();
    this.jumpQueued = false;
    this.releasePointerLock();
  };
}

function defaultPitchForCameraMode(cameraMode: SceneSettings["player"]["cameraMode"]) {
  if (cameraMode === "fps") {
    return 0;
  }

  if (cameraMode === "third-person") {
    return -0.22;
  }

  return -0.78;
}

function isTextInputTarget(target: EventTarget | null) {
  return target instanceof HTMLElement && (target.isContentEditable || target.tagName === "INPUT" || target.tagName === "TEXTAREA");
}

function resolveViewDirection(yaw: number, pitch: number, target: Vector3) {
  target.set(
    -Math.sin(yaw) * Math.cos(pitch),
    Math.sin(pitch),
    -Math.cos(yaw) * Math.cos(pitch)
  );

  return target.normalize();
}

const scratchForward = new Vector3();
const scratchLookTarget = new Vector3();
const scratchMoveDirection = new Vector3();
const scratchRight = new Vector3();
const scratchTargetCamPos = new Vector3();
const scratchViewDirection = new Vector3();
const DOWN_DIRECTION: [number, number, number] = [0, -1, 0];
