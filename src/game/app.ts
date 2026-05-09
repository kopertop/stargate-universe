/**
 * createGameApp
 *
 * Bootstraps the renderer, shared scene graph, input, and game loop, then
 * manages the lifecycle of individual game scenes. Key design decisions:
 *
 *  - InputManager is created once and shared across all scenes.
 *  - GameLoop drives fixed-step physics and variable-rate camera/render.
 *  - Camera and player controller are decoupled — swap camera mode at runtime
 *    via player.setCameraMode() without rebuilding the player.
 *  - setStatus() renders a visible overlay so users know what's loading.
 *  - Scene transitions are guarded by a load token so stale async results
 *    from navigating away mid-load never contaminate the live scene.
 *  - Adaptive physics rate slows down when frame budget is exceeded.
 */

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
import { createCameraController, frameCameraOnObject } from "./camera";
import { AudioManager } from "../systems/audio";
import { installDebugApi, toggleDebugOverlay } from "../systems/debug-api";
import { pollInput, getInput, SguAction } from "../systems/input";
import { mountTouchControls } from "../ui/touch-controls";
import { mountHud, type HudHandle } from "../ui/hud";
import { mountPauseMenu, type PauseMenuHandle } from "../ui/pause-menu";
import { mountConsole, type ConsoleHandle } from "../ui/restoration-console";
import {
	onEscapeRequested,
	requestFullscreenAndPointerLock,
} from "../systems/fullscreen";
import { createDefaultGameplaySystems, createStarterGameplayHost, mergeGameplaySystems } from "./gameplay";
import { GameLoop, FIXED_STEP_SECONDS } from "./loop";
import { InputManager } from "./input";
import { installAssetDecoders } from "./loaders/install-decoders";
import { createRuntimePhysicsSession, type RuntimePhysicsSession } from "./physics";
import type {
  GameSceneContext,
  GameSceneDefinition,
  GameSceneLifecycle,
  GameSceneLoaderContext,
  PlayerController
} from "./scene";
import { StarterPlayerController, VrmPlayerController } from "./player";
import { VrmCharacterManager } from "../systems/vrm";
import { VrmPlayerAnimationController } from "../systems/vrm/vrm-player-animation-controller";

const PLAYER_ANIMATIONS_BASE_PATH = "/assets/animations";

// ------------------------------------------------------------------
// Types

type GameAppOptions = {
  initialSceneId: string;
  root: HTMLDivElement;
  scenes: Record<string, GameSceneDefinition>;
};

type SceneBundle = {
  gameplayRuntime: GameplayRuntime;
  id: string;
  lifecycle: GameSceneLifecycle;
  player: PlayerController | null;
  physicsWorld: CrashcatPhysicsWorld;
  runtimePhysics: RuntimePhysicsSession;
  runtimeScene: ThreeRuntimeSceneInstance;
};

const DEFAULT_FIXED_STEP_SECONDS = 1 / 60;
const MIN_FIXED_STEP_SECONDS = 1 / 20;
const MAX_PHYSICS_CATCH_UP_STEPS = 4;
const ADAPT_UP_THRESHOLD = 0.8;
const ADAPT_DOWN_THRESHOLD = 0.4;
const ADAPT_RATE = 0.02;

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

// ------------------------------------------------------------------

export async function createGameApp(options: GameAppOptions) {
  // DOM shell
  options.root.innerHTML = `
    <div class="game-shell">
      <div class="game-status" data-game-status hidden></div>
    </div>
  `;

  const shell = options.root.querySelector<HTMLDivElement>(".game-shell");
  const statusEl = options.root.querySelector<HTMLDivElement>("[data-game-status]");

  if (!shell || !statusEl) {
    throw new Error("Failed to initialise game shell.");
  }

  // Allow ?webgl query param to force the WebGL backend — used by Playwright
  // visual tests running in headless Chromium where WebGPU is unavailable.
  const forceWebGL = new URLSearchParams(window.location.search).has("webgl");
  const renderer = new WebGPURenderer({ antialias: true, forceWebGL });
  await renderer.init();
  // Install DRACO + KTX2 + Meshopt decoders globally so every GLTFLoader
  // (ours, ggez's, VRM's) auto-handles compressed assets. Must run after
  // renderer.init() — KTX2 transcoder format selection reads capabilities.
  installAssetDecoders(renderer);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  // Keep the renderer un-tonemapped while the art direction is being rebuilt.
  // Scene lighting should carry the look directly instead of being pushed
  // through a global exposure/post stack.
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.toneMappingExposure = 1;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  shell.append(renderer.domElement);

  // Shared Three.js objects
  const scene = new THREE.Scene();
  // FOV 50° = telephoto-ish, more cinematic compression. Wider FOVs flatten
  // scale and make even huge rooms feel small; 50 makes the ship feel grand.
  const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 4000);

  // Attach the shared audio listener to the camera once for the life of the
  // app. Scenes just call `AudioManager.getInstance().play(id)` to play
  // cataloged sounds. The listener follows the camera across scene swaps.
  AudioManager.getInstance().attachListener(camera);
  const clock = new THREE.Clock();

  // Shared systems
  const input = new InputManager();
  input.mount(renderer.domElement);

  // State
  let activeBundle: SceneBundle | undefined;
  let loadToken = 0;

  // Dev hook surface — exposes window.__sgu for Playwright/MCP/console
  // automation and renders an on-screen dev overlay. Only live in dev;
  // the overlay is hidden until the player double-taps Backquote (or
  // clicks the "open dev tools" hook).
  const hostHooks = {
    getCurrentSceneId: () => activeBundle?.id,
    getPlayerPosition: () => {
      if (!activeBundle?.player) return undefined;
      const p = activeBundle.player.object.position;
      return { x: p.x, y: p.y, z: p.z };
    },
    setExternalMove: (forward: number, strafe: number) => {
      activeBundle?.player?.setExternalMoveInput?.(forward, strafe);
    },
    gotoScene: (sceneId: string) => loadScene(sceneId),
    getCanvas: () => renderer.domElement as unknown as HTMLCanvasElement,
    getCamera: () => camera,
    getRenderer: () => renderer,
    getScene: () => scene,
  };
  if (import.meta.env.DEV) {
    installDebugApi(hostHooks);
    (window as unknown as { __sguRenderer?: unknown }).__sguRenderer = renderer;
    (window as unknown as { __sguSceneRoot?: THREE.Scene }).__sguSceneRoot = scene;
    const toggleDev = (e: KeyboardEvent) => {
      if (e.code === "Backquote") toggleDebugOverlay(hostHooks);
    };
    window.addEventListener("keydown", toggleDev);
  }
  // S4-09 — touch controls mount only on coarse pointers (returns null on
  // desktop, keeping the DOM clean and avoiding stray pointer captures).
  const touchControls = mountTouchControls(getInput());
  // Player HUD — mounted once at app boot, hidden on scenes that opt out
  // (start-screen, opening cinematic) by setting `hud: false` in the
  // scene definition. Refreshed on every scene transition so the quest
  // panel reflects the newly-active quest manager.
  let hud: HudHandle | null = null;
  let pauseMenu: PauseMenuHandle | null = null;
  let disposed = false;

  const resumeGame = () => {
    if (!pauseMenu?.isVisible()) return;
    pauseMenu.hide();
    loop.resume();
    // Restore the immersive presentation that was interrupted.
    void requestFullscreenAndPointerLock(renderer.domElement as unknown as HTMLElement);
  };

  const pauseGame = () => {
    if (pauseMenu?.isVisible()) return;
    // Only pause + show menu on gameplay scenes. Menu/cinematic scenes
    // (hud === false) shouldn't trap the player in a pause overlay.
    if (!hud) return;
    loop.pause();
    pauseMenu?.show();
  };

	pauseMenu = mountPauseMenu({
		onResume: () => resumeGame(),
		onQuit: () => {
			if (pauseMenu?.isVisible()) pauseMenu.hide();
			loop.resume();
			void loadScene("start-screen");
		},
	});

	// ── Restoration Console ────────────────────────────────────────────────

	let consoleHandle: ConsoleHandle | null = null;
	let isConsoleOpen = false;

	const closeConsole = () => {
		if (!consoleHandle) return;
		consoleHandle.dispose();
		// onClose callback handles cleanup + loop.resume()
	};

	const openConsole = () => {
		if (isConsoleOpen || !hud || pauseMenu?.isVisible()) return;
		isConsoleOpen = true;
		consoleHandle = mountConsole({
			onClose: () => {
				isConsoleOpen = false;
				consoleHandle = null;
				loop.resume();
			},
		});
		loop.pause();
	};

	const toggleConsole = () => {
		if (isConsoleOpen) {
			closeConsole();
		} else {
			openConsole();
		}
	};

	const handleTabKey = (e: KeyboardEvent) => {
		if (e.key === "Tab") {
			e.preventDefault();
			if (isConsoleOpen) closeConsole();
		}
	};
	window.addEventListener("keydown", handleTabKey);

	// ── Escape (pause / console) ───────────────────────────────────────────

	const unsubscribeEscape = onEscapeRequested(() => {
		if (isConsoleOpen) {
			closeConsole();
			return;
		}
		if (pauseMenu?.isVisible()) {
			resumeGame();
		} else {
			pauseGame();
		}
	});

  // Adaptive physics state
  let adaptiveStepSeconds = DEFAULT_FIXED_STEP_SECONDS;
  let fpsFrames = 0;
  let fpsTime = 0;

  // ------------------------------------------------------------------
  // Status overlay

  const setStatus = (message: string) => {
    statusEl.hidden = message.length === 0;
    statusEl.textContent = message;
  };

  // ------------------------------------------------------------------
  // Fixed-step helpers

  const runFixedStep = () => {
    if (!activeBundle) return;
    activeBundle.player?.updateBeforeStep(FIXED_STEP_SECONDS);
    activeBundle.lifecycle.fixedUpdate?.(FIXED_STEP_SECONDS);
    stepCrashcatPhysicsWorld(activeBundle.physicsWorld, FIXED_STEP_SECONDS);
    activeBundle.runtimePhysics.syncVisuals();
    activeBundle.player?.updateAfterStep(FIXED_STEP_SECONDS);
  };

  // ------------------------------------------------------------------
  // Game loop

  const loop = new GameLoop({
    onFixedUpdate: (_dt) => {
      runFixedStep();
    },
    onUpdate: (dt) => {
      // Push touch joystick axis into InputManager *before* polling — pollInput
      // snapshots the merged keyboard+gamepad+touch movement for this frame.
      const touchAxis = touchControls?.tickAxis();
      if (touchAxis) {
        activeBundle?.player?.setExternalMoveInput(touchAxis.forward, touchAxis.strafe);
      }
      // Controller + keyboard snapshot (edge-detection for just-pressed actions)
      pollInput();
      if (getInput().isActionJustPressed(SguAction.RestorationConsole)) {
        toggleConsole();
      }

      activeBundle?.lifecycle.update?.(dt);
      activeBundle?.gameplayRuntime.update(dt);
      // Camera is updated at variable rate for smooth motion at high refresh rates.
      activeBundle?.player?.updateCamera(dt);
    },
    onRender: () => {
      renderer.render(scene, camera);
    }
  });

  // ------------------------------------------------------------------
  // Scene disposal helper — used both on navigation and on stale loads

  const disposeBundle = async (bundle: SceneBundle) => {
    scene.remove(bundle.runtimeScene.root);

    if (bundle.player) {
      scene.remove(bundle.player.object);
    }

    await bundle.lifecycle.dispose?.();
    bundle.player?.dispose();
    bundle.gameplayRuntime.dispose();
    bundle.runtimeScene.dispose();
    bundle.runtimePhysics.dispose();
  };

  // ------------------------------------------------------------------
  // Scene navigation

  const preloadScene = async (sceneId: string) => {
    const definition = options.scenes[sceneId];

    if (!definition) {
      throw new Error(`Unknown scene "${sceneId}".`);
    }

    if (definition.source.preload) {
      await definition.source.preload();
    } else {
      await definition.source.load();
    }
  };

	const loadScene = async (sceneId: string) => {
		const definition = options.scenes[sceneId];

		if (!definition) {
			throw new Error(`Unknown scene "${sceneId}".`);
		}

		const token = ++loadToken;
		(window as unknown as { __sguVisualReady?: boolean; __sguActiveSceneId?: string }).__sguVisualReady = false;
		(window as unknown as { __sguVisualReady?: boolean; __sguActiveSceneId?: string }).__sguActiveSceneId = sceneId;
		setStatus(`Loading ${definition.title}…`);

    let runtimeScene: ThreeRuntimeSceneInstance | undefined;
    let player: PlayerController | null = null;
    let gameplayRuntime: GameplayRuntime | undefined;
    let physicsWorld: CrashcatPhysicsWorld | undefined;
    let runtimePhysics: RuntimePhysicsSession | undefined;
    let mountResult: GameSceneLifecycle | undefined;

    try {
      await ensureCrashcatRuntimePhysics();
      const runtimeManifest = await definition.source.load();

      if (disposed || token !== loadToken) return;

      // Build scene-level objects
      runtimeScene = await createThreeRuntimeSceneInstance(runtimeManifest, {
        applyToScene: scene,
        resolveAssetUrl: ({ path }) => path
      });

      if (disposed || token !== loadToken) {
        runtimeScene.dispose();
        return;
      }

      renderer.setClearColor(runtimeScene.scene.settings.world.fogColor || "#dfe8f2");

      physicsWorld = createCrashcatPhysicsWorld(runtimeScene.scene.settings);
      runtimePhysics = createRuntimePhysicsSession({ runtimeScene, world: physicsWorld });
      const gameplayHost = createStarterGameplayHost({ physicsWorld, runtimePhysics, runtimeScene });

      // Build loader context (available to systems factory)
      const loaderContext: GameSceneLoaderContext = {
        camera,
        gotoScene: loadScene,
        physicsWorld,
        preloadScene,
        renderer,
        runtimeScene,
        scene,
        sceneId,
        sceneSettings: runtimeScene.scene.settings,
        setStatus
      };

      const systems = resolveSceneSystems(definition, loaderContext);
      gameplayRuntime = createGameplayRuntime({
        host: gameplayHost,
        scene: createGameplayRuntimeSceneFromRuntimeScene(runtimeScene.scene),
        systems
      });

      player = await buildPlayer({
        camera,
        definition,
        gameplayRuntime,
        input,
        physicsWorld,
        runtimeScene
      });

      gameplayRuntime.start();

      // Full context — available to mount()
      const fullContext: GameSceneContext = {
        ...loaderContext,
        gameplayRuntime,
        player,
        runtimePhysics
      };

      // mount() is awaited before we commit the scene to activeBundle.
      // This prevents UI or actor setup from racing against scene teardown.
      mountResult = (await definition.mount?.(fullContext)) || undefined;

      if (disposed || token !== loadToken) {
        // Another loadScene() won the race — clean up what we just built.
        scene.remove(runtimeScene.root);
        if (player) scene.remove(player.object);
        await mountResult?.dispose?.();
        player?.dispose();
        gameplayRuntime.dispose();
        runtimeScene.dispose();
        runtimePhysics.dispose();
        return;
      }
    } catch (err) {
      // Scene load failed — clean up anything we managed to create.
      console.error(`[App] Failed to load scene "${sceneId}":`, err);
      if (player) scene.remove(player.object);
      player?.dispose();
      gameplayRuntime?.dispose();
      runtimeScene?.dispose();
      runtimePhysics?.dispose();
      setStatus(`Failed to load "${definition.title}"`);
      return;
    }

    const lifecycle: GameSceneLifecycle = mountResult ?? {};

    // Tear down the previous scene only after the new one is fully ready.
    const previous = activeBundle;

    // Add new scene to the Three graph and expose it.
    scene.add(runtimeScene.root);

    if (player) {
      scene.add(player.object);
      player.updateAfterStep(FIXED_STEP_SECONDS);
      // ?photo=1 — capture/screenshot mode: hide the player so it doesn't
      // appear in cinematic camera shots driven by __sgu.setCamera.
      if (new URLSearchParams(window.location.search).has("photo")) {
        player.object.visible = false;
      }
    } else {
      frameCameraOnObject(camera, runtimeScene.root);
    }

    activeBundle = { gameplayRuntime, id: sceneId, lifecycle, player, physicsWorld, runtimePhysics, runtimeScene };

    if (previous) {
      await disposeBundle(previous);
    }

    // HUD lifecycle — mount/unmount based on scene's `hud` flag (default
    // true). Refresh after every successful mount so the quest panel
    // picks up the freshly-registered quest manager.
    const showHud = definition.hud !== false;
    if (showHud && !hud) {
      hud = mountHud();
    } else if (!showHud && hud) {
      hud.dispose();
      hud = null;
    }
    hud?.refresh();

    setStatus("");
    (window as unknown as { __sguVisualReady?: boolean }).__sguVisualReady = true;
  };

  const start = () => {
    loop.start();
    return loadScene(options.initialSceneId);
  };

	const dispose = async () => {
		disposed = true;
		window.removeEventListener("resize", handleResize);
		window.removeEventListener("keydown", handleTabKey);
		closeConsole();
		touchControls?.dispose();
		hud?.dispose();
		hud = null;
		pauseMenu?.dispose();
		pauseMenu = null;
		unsubscribeEscape();
		if (activeBundle) {
			await disposeBundle(activeBundle);
		}
		renderer.dispose();
	};

  const handleResize = () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  };

  window.addEventListener("resize", handleResize);

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

async function buildPlayer(options: {
  camera: THREE.PerspectiveCamera;
  definition: GameSceneDefinition;
  gameplayRuntime: GameplayRuntime;
  input: InputManager;
  physicsWorld: CrashcatPhysicsWorld;
  runtimeScene: ThreeRuntimeSceneInstance;
}): Promise<PlayerController | null> {
  if (options.definition.player === false) {
    return null;
  }

  const playerConfig = options.definition.player ?? {};
  const playerSpawn = options.runtimeScene.entities.find((entity) => {
    if (entity.type !== "player-spawn") return false;
    return playerConfig.spawnEntityId ? entity.id === playerConfig.spawnEntityId : true;
  });

  if (!playerSpawn) {
    return null;
  }

  const spawn = {
    position: playerSpawn.transform.position,
    rotationY: playerSpawn.transform.rotation.y
  };

  const cameraMode = playerConfig.cameraMode ?? options.runtimeScene.scene.settings.player.cameraMode;

  // Build camera controller — needed by both VRM and starter controllers.
  const cameraController = createCameraController(cameraMode, options.camera);

  // VRM character path — check if the player config specifies a VRM URL.
  const vrmUrl = playerConfig.vrmUrl;

  if (vrmUrl) {
    (window as unknown as { __sguHasPlayerVrm?: boolean; __sguAnimWire?: string }).__sguHasPlayerVrm = true;
    (window as unknown as { __sguHasPlayerVrm?: boolean; __sguAnimWire?: string }).__sguAnimWire = "pending";
    // Create VRM character manager and register the player character.
    const characterManager = new VrmCharacterManager(options.camera);
    const characterInstance = characterManager.addCharacter({
      id: "player",
      vrmUrl,
      isPlayer: true,
      priority: 0
    });

    const controller = new VrmPlayerController({
      camera: cameraController,
      input: options.input,
      threeCamera: options.camera,
      gameplayRuntime: options.gameplayRuntime,
      sceneSettings: options.runtimeScene.scene.settings,
      spawn,
      world: options.physicsWorld,
      characterManager,
      characterInstance
    });

    // Wire AnimationMixer-driven locomotion once the VRM scene is loaded.
    // Failures (missing clips, bad VRM) only mean the character holds T-pose
    // — they shouldn't block scene start, so we fire-and-forget.
    const animationReady = characterInstance.whenLoaded
      .then(async (vrm) => {
        const animController = new VrmPlayerAnimationController(vrm);
        try {
          await animController.loadClips(PLAYER_ANIMATIONS_BASE_PATH);
        } catch (err) {
          console.error("[buildPlayer] Failed loading player animation clips:", err);
        }
        controller.setAnimationController(animController);
        // Marker used by the character-poses E2E test to wait until clips
        // have actually been loaded and the controller is bound to the
        // player. Without this, screenshots can capture before the mixer
        // ever ticks and report a false T-pose.
        (window as unknown as { __sguAnimWire?: string }).__sguAnimWire = "controller-attached";
      })
      .catch((err) => {
        console.error("[buildPlayer] Player VRM failed to load — animation skipped:", err);
        (window as unknown as { __sguAnimWire?: string }).__sguAnimWire = "failed";
      });

    await Promise.race([
      animationReady,
      new Promise<void>((resolve) => window.setTimeout(resolve, 6_000)),
    ]);

    return controller;
  }

  // Fall back to starter controller (capsule physics only).
  (window as unknown as { __sguHasPlayerVrm?: boolean; __sguAnimWire?: string }).__sguHasPlayerVrm = false;
  (window as unknown as { __sguHasPlayerVrm?: boolean; __sguAnimWire?: string }).__sguAnimWire = "none";
  return new StarterPlayerController({
    camera: cameraController,
    input: options.input,
    threeCamera: options.camera,
    gameplayRuntime: options.gameplayRuntime,
    sceneSettings: options.runtimeScene.scene.settings,
    spawn,
    world: options.physicsWorld
  });
}

function resolveSceneSystems(definition: GameSceneDefinition, context: GameSceneLoaderContext): GameplayRuntimeSystemRegistration[] {
  const starterSystems = createDefaultGameplaySystems(context.sceneSettings);

  if (!definition.systems) {
    return starterSystems;
  }

  const sceneSystems = typeof definition.systems === "function" ? definition.systems(context) : definition.systems;
  return mergeGameplaySystems(starterSystems, sceneSystems);
}
