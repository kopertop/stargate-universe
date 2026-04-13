import {
  createGameplayRuntime,
  createGameplayRuntimeSceneFromRuntimeScene,
  type GameplayRuntime,
  type GameplayRuntimeSystemRegistration
} from "@ggez/gameplay-runtime";
import {
  createCrashcatPhysicsWorld,
  ensureCrashcatRuntimePhysics,
  stepCrashcatPhysicsWorld,
  type CrashcatPhysicsWorld
} from "@ggez/runtime-physics-crashcat";
import { createThreeRuntimeSceneInstance, type ThreeRuntimeSceneInstance } from "@ggez/three-runtime";
import * as THREE from "three";
import { WebGPURenderer } from "three/webgpu";
import { frameCameraOnObject } from "./camera";
import { AudioManager } from "../systems/audio";
import { pollInput } from "../systems/input";
import { createDefaultGameplaySystems, createStarterGameplayHost, mergeGameplaySystems } from "./gameplay";
import { createRuntimePhysicsSession, type RuntimePhysicsSession } from "./runtime-physics";
import type { GameSceneBootstrapContext, GameSceneDefinition, GameSceneLifecycle } from "./scene-types";
import { StarterPlayerController } from "./starter-player-controller";

type GameAppOptions = {
  initialSceneId: string;
  root: HTMLDivElement;
  scenes: Record<string, GameSceneDefinition>;
};

type ActiveScene = {
  accumulatorSeconds: number;
  gameplayRuntime: GameplayRuntime;
  id: string;
  lifecycle: GameSceneLifecycle;
  player: StarterPlayerController | null;
  physicsWorld: CrashcatPhysicsWorld;
  runtimePhysics: RuntimePhysicsSession;
  runtimeScene: ThreeRuntimeSceneInstance;
};

const DEFAULT_FIXED_STEP_SECONDS = 1 / 60;
const MIN_FIXED_STEP_SECONDS = 1 / 20;   // lowest physics rate: 20 Hz
const MAX_PHYSICS_CATCH_UP_STEPS = 4;
const ADAPT_UP_THRESHOLD = 0.8;   // if frame budget used > 80%, slow physics
const ADAPT_DOWN_THRESHOLD = 0.4; // if frame budget used < 40%, speed physics back up
const ADAPT_RATE = 0.02;          // how fast the step adjusts per frame

/** Performance metrics exposed for debug overlays */
export const perfMetrics = {
	fps: 0,
	frameMs: 0,
	physicsMs: 0,
	physicsHz: 60,
	physicsSteps: 0,
	renderMs: 0,
	drawCalls: 0,
	triangles: 0,
};

export async function createGameApp(options: GameAppOptions) {
  options.root.innerHTML = `
    <div class="game-shell"></div>
  `;

  const shell = options.root.querySelector<HTMLDivElement>(".game-shell");

  if (!shell) {
    throw new Error("Failed to initialize game shell.");
  }

  // Allow ?webgl query param to force the WebGL backend — used by Playwright
  // visual tests running in headless Chromium where WebGPU is unavailable.
  const forceWebGL = new URLSearchParams(window.location.search).has("webgl");
  const renderer = new WebGPURenderer({ antialias: true, forceWebGL });
  await renderer.init();
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  // WebGPU uses physically-based light units (candela/lux).
  // ACESFilmic tone mapping + exposure compensates so legacy intensity values
  // look correct without rewriting every scene's light intensities.
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 3.0;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  shell.append(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 4000);
  // Attach the shared audio listener to the camera once for the life of the
  // app. Scenes just call `AudioManager.getInstance().play(id)` to play
  // cataloged sounds. The listener follows the camera across scene swaps.
  AudioManager.getInstance().attachListener(camera);
  const clock = new THREE.Clock();
  let activeScene: ActiveScene | undefined;
  let currentLoadToken = 0;
  let disposed = false;

  const setStatus = (_message: string) => {};

  let adaptiveStepSeconds = DEFAULT_FIXED_STEP_SECONDS;
  let fpsFrames = 0;
  let fpsTime = 0;

  const stepActiveScene = (deltaSeconds: number) => {
    if (!activeScene) {
      return;
    }

    const maxCatchUp = adaptiveStepSeconds * MAX_PHYSICS_CATCH_UP_STEPS;
    activeScene.accumulatorSeconds = Math.min(
      activeScene.accumulatorSeconds + deltaSeconds,
      maxCatchUp
    );

    let steps = 0;
    while (activeScene.accumulatorSeconds >= adaptiveStepSeconds) {
      activeScene.player?.updateBeforeStep(adaptiveStepSeconds);
      activeScene.lifecycle.fixedUpdate?.(adaptiveStepSeconds);
      stepCrashcatPhysicsWorld(activeScene.physicsWorld, adaptiveStepSeconds);
      activeScene.runtimePhysics.syncVisuals();
      activeScene.player?.updateAfterStep(adaptiveStepSeconds);
      activeScene.accumulatorSeconds -= adaptiveStepSeconds;
      steps++;
    }

    perfMetrics.physicsSteps = steps;
    perfMetrics.physicsHz = Math.round(1 / adaptiveStepSeconds);
  };

  const renderFrame = () => {
    if (disposed) {
      return;
    }

    requestAnimationFrame(renderFrame);
    const frameStart = performance.now();
    const delta = Math.min(clock.getDelta(), 0.1);

    // Controller + keyboard snapshot (edge-detection for just-pressed actions)
    pollInput();

    // Physics step
    const physicsStart = performance.now();
    stepActiveScene(delta);
    perfMetrics.physicsMs = performance.now() - physicsStart;

    activeScene?.lifecycle.update?.(delta);
    activeScene?.gameplayRuntime.update(delta);

    // Render
    const renderStart = performance.now();
    renderer.render(scene, camera);
    perfMetrics.renderMs = performance.now() - renderStart;

    // Frame metrics
    const frameMs = performance.now() - frameStart;
    perfMetrics.frameMs = frameMs;
    perfMetrics.drawCalls = renderer.info.render.calls;
    perfMetrics.triangles = renderer.info.render.triangles;

    // FPS counter (averaged over 1 second)
    fpsFrames++;
    fpsTime += delta;
    if (fpsTime >= 1.0) {
      perfMetrics.fps = Math.round(fpsFrames / fpsTime);
      fpsFrames = 0;
      fpsTime = 0;
    }

    // Adaptive physics: if frames are slow, reduce physics rate
    const budgetUsed = frameMs / 16.67; // fraction of 60fps budget
    if (budgetUsed > ADAPT_UP_THRESHOLD) {
      adaptiveStepSeconds = Math.min(
        adaptiveStepSeconds + ADAPT_RATE * adaptiveStepSeconds,
        MIN_FIXED_STEP_SECONDS
      );
    } else if (budgetUsed < ADAPT_DOWN_THRESHOLD && adaptiveStepSeconds > DEFAULT_FIXED_STEP_SECONDS) {
      adaptiveStepSeconds = Math.max(
        adaptiveStepSeconds - ADAPT_RATE * adaptiveStepSeconds,
        DEFAULT_FIXED_STEP_SECONDS
      );
    }
  };

  const disposeActiveScene = async () => {
    if (!activeScene) {
      return;
    }

    const sceneToDispose = activeScene;
    activeScene = undefined;
    scene.remove(sceneToDispose.runtimeScene.root);
    if (sceneToDispose.player) {
      scene.remove(sceneToDispose.player.object);
    }
    await sceneToDispose.lifecycle.dispose?.();
    sceneToDispose.player?.dispose();
    sceneToDispose.gameplayRuntime.dispose();
    sceneToDispose.runtimeScene.dispose();
    sceneToDispose.runtimePhysics.dispose();
  };

  const preloadScene = async (sceneId: string) => {
    const definition = options.scenes[sceneId];

    if (!definition) {
      throw new Error(`Unknown scene "${sceneId}".`);
    }

    if (definition.source.preload) {
      await definition.source.preload();
      return;
    }

    await definition.source.load();
  };

  const loadScene = async (sceneId: string) => {
    const definition = options.scenes[sceneId];

    if (!definition) {
      throw new Error(`Unknown scene "${sceneId}".`);
    }

    const loadToken = ++currentLoadToken;
    setStatus(`Loading ${definition.title}...`);

    await ensureCrashcatRuntimePhysics();
    const runtimeManifest = await definition.source.load();

    if (disposed || loadToken !== currentLoadToken) {
      return;
    }

    const runtimeScene = await createThreeRuntimeSceneInstance(runtimeManifest, {
      applyToScene: scene,
      resolveAssetUrl: ({ path }) => path
    });
    renderer.setClearColor(runtimeScene.scene.settings.world.fogColor || "#dfe8f2");
    const physicsWorld = createCrashcatPhysicsWorld(runtimeScene.scene.settings);
    const runtimePhysics = createRuntimePhysicsSession({
      runtimeScene,
      world: physicsWorld
    });
    const gameplayHost = createStarterGameplayHost({
      physicsWorld,
      runtimePhysics,
      runtimeScene
    });
    const bootstrapContext = createBootstrapContext({
      camera,
      gotoScene: loadScene,
      physicsWorld,
      preloadScene,
      renderer,
      runtimeScene,
      scene,
      sceneId,
      setStatus
    });
    const systems = resolveSceneSystems(definition, bootstrapContext);
    const gameplayRuntime = createGameplayRuntime({
      host: gameplayHost,
      scene: createGameplayRuntimeSceneFromRuntimeScene(runtimeScene.scene),
      systems
    });
    const player = createStarterPlayerController({
      camera,
      definition,
      domElement: renderer.domElement,
      gameplayRuntime,
      physicsWorld,
      runtimeScene,
      scene
    });

    gameplayRuntime.start();
    scene.add(runtimeScene.root);
    if (player) {
      scene.add(player.object);
      player.updateAfterStep(DEFAULT_FIXED_STEP_SECONDS);
    } else {
      frameCameraOnObject(camera, runtimeScene.root);
    }

    // Cleanup helper for both the cancelled-load path and the mount() failure path.
    const teardownPartialLoad = async (lifecycle?: GameSceneLifecycle) => {
      scene.remove(runtimeScene.root);
      if (player) {
        scene.remove(player.object);
      }
      await lifecycle?.dispose?.();
      player?.dispose();
      gameplayRuntime.dispose();
      runtimeScene.dispose();
      runtimePhysics.dispose();
    };

    let lifecycle: GameSceneLifecycle;
    try {
      const mountedLifecycle = await definition.mount?.({
        camera,
        gameplayRuntime,
        gotoScene: loadScene,
        player,
        physicsWorld,
        preloadScene,
        renderer,
        runtimePhysics,
        runtimeScene,
        scene,
        sceneId,
        sceneSettings: runtimeScene.scene.settings,
        setStatus
      });
      lifecycle = mountedLifecycle ?? {};
    } catch (error) {
      // mount() threw — clean up the partially attached scene before propagating
      // so we don't leak the runtime scene root, player, or physics world.
      await teardownPartialLoad();
      throw error;
    }

    if (disposed || loadToken !== currentLoadToken) {
      await teardownPartialLoad(lifecycle);
      return;
    }

    const previousScene = activeScene;
    activeScene = {
      accumulatorSeconds: 0,
      gameplayRuntime,
      id: sceneId,
      lifecycle,
      player,
      physicsWorld,
      runtimePhysics,
      runtimeScene
    };

    if (previousScene) {
      scene.remove(previousScene.runtimeScene.root);
      if (previousScene.player) {
        scene.remove(previousScene.player.object);
      }
      await previousScene.lifecycle.dispose?.();
      previousScene.player?.dispose();
      previousScene.gameplayRuntime.dispose();
      previousScene.runtimeScene.dispose();
      previousScene.runtimePhysics.dispose();
    }
  };

  const start = () => loadScene(options.initialSceneId);

  const dispose = async () => {
    disposed = true;
    window.removeEventListener("resize", handleResize);
    await disposeActiveScene();
    renderer.dispose();
  };

  const handleResize = () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  };

  window.addEventListener("resize", handleResize);
  renderFrame();

  return {
    camera,
    dispose,
    initialSceneId: options.initialSceneId,
    loadScene,
    preloadScene,
    renderer,
    scene,
    start,
    setStatus
  };
}

function createBootstrapContext(options: {
  camera: THREE.PerspectiveCamera;
  gotoScene: (sceneId: string) => Promise<void>;
  physicsWorld: CrashcatPhysicsWorld;
  preloadScene: (sceneId: string) => Promise<void>;
  renderer: WebGPURenderer;
  runtimeScene: ThreeRuntimeSceneInstance;
  scene: THREE.Scene;
  sceneId: string;
  setStatus: (message: string) => void;
}): GameSceneBootstrapContext {
  return {
    camera: options.camera,
    gotoScene: options.gotoScene,
    physicsWorld: options.physicsWorld,
    preloadScene: options.preloadScene,
    renderer: options.renderer,
    runtimeScene: options.runtimeScene,
    scene: options.scene,
    sceneId: options.sceneId,
    sceneSettings: options.runtimeScene.scene.settings,
    setStatus: options.setStatus
  };
}

function createStarterPlayerController(options: {
  camera: THREE.PerspectiveCamera;
  definition: GameSceneDefinition;
  domElement: HTMLCanvasElement;
  gameplayRuntime: GameplayRuntime;
  physicsWorld: CrashcatPhysicsWorld;
  runtimeScene: ThreeRuntimeSceneInstance;
  scene: THREE.Scene;
}) {
  if (options.definition.player === false) {
    return null;
  }

  const playerConfig = options.definition.player ?? {};
  const playerSpawn = options.runtimeScene.entities.find((entity) => {
    if (entity.type !== "player-spawn") {
      return false;
    }

    return playerConfig.spawnEntityId ? entity.id === playerConfig.spawnEntityId : true;
  });

  if (!playerSpawn) {
    return null;
  }

  return new StarterPlayerController({
    camera: options.camera,
    cameraMode: playerConfig.cameraMode ?? options.runtimeScene.scene.settings.player.cameraMode,
    domElement: options.domElement,
    gameplayRuntime: options.gameplayRuntime,
    scene: options.scene,
    sceneSettings: options.runtimeScene.scene.settings,
    spawn: {
      position: playerSpawn.transform.position,
      rotationY: playerSpawn.transform.rotation.y
    },
    vrmUrl: playerConfig.vrmUrl,
    world: options.physicsWorld
  });
}

function resolveSceneSystems(definition: GameSceneDefinition, context: GameSceneBootstrapContext): GameplayRuntimeSystemRegistration[] {
  const starterSystems = createDefaultGameplaySystems(context.sceneSettings);

  if (!definition.systems) {
    return starterSystems;
  }

  const sceneSystems = typeof definition.systems === "function" ? definition.systems(context) : definition.systems;
  return mergeGameplaySystems(starterSystems, sceneSystems);
}
