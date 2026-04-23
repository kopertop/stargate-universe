/**
 * @file index.ts
 * @description Entry point for the Destiny Gate Room scene.
 * Handles scene initialization and component registration.
 */

     1|import * as THREE from "three";
import {
  createColocatedRuntimeSceneSource,
  defineGameScene
} from "../../game/loaders/scene-sources";
import type { GameSceneContext, GameSceneLifecycle } from "../../game/scene";
import { ShipState, SHIP_STATE_CONFIG, type Section, type Subsystem } from "../../systems/ship-state";
import { emit, scopedBus } from "../../systems/event-bus";
import { initResources, getResource, addResource, consumeResource, hasResource, getAllResources } from "../../systems/resources";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
  import: "default",
  query: "?url"
}) as Record<string, () => Promise<string>>;

// ─── Constants ───────────────────────────────────────────────────────────────

const ROOM_WIDTH = 26;
const ROOM_DEPTH = 40;
const ROOM_HEIGHT = 8;
const GATE_RADIUS = 2.8;
const GATE_TUBE = 0.22;
const GATE_CENTER = new THREE.Vector3(0, GATE_RADIUS + GATE_TUBE - 0.3, 0); // centered in room
const CHEVRON_COUNT = 7; // Standard dial is 7 chevrons; 8-9 only for special events

// SGU color palette
const COLOR_ANCIENT_METAL = 0x2a2a3a;
const COLOR_ANCIENT_GLOW = 0x4488ff;
const COLOR_CHEVRON_OFF = 0x111122;
const COLOR_CHEVRON_ON = 0x44aaff;
const COLOR_EVENT_HORIZON = 0x88bbff;
const COLOR_WALL = 0x1a1a2e;
const COLOR_CEILING = 0x141425;

// Wall transparency — track wall meshes for camera occlusion
const wallMeshes: THREE.Mesh[] = [];

// ─── Gate activation state ───────────────────────────────────────────────────

type GateState = "idle" | "dialing" | "kawoosh" | "active" | "shutdown";

type GateRuntime = {
  chevronMeshes: THREE.Mesh[];
  dialElapsed: number;
  eventHorizon: THREE.Mesh;
  innerRing: THREE.Mesh;
  kawooshElapsed: number;
  lockedChevrons: number;
  outerRing: THREE.Mesh;
  pointLights: THREE.PointLight[];
  state: GateState;
};

// ─── Room construction ───────────────────────────────────────────────────────

function createWallMaterial(): THREE.MeshStandardMaterial {
  return new THREE.MeshStandardMaterial({
    color: 0x222238,
    emissive: 0x141428,
    emissiveIntensity: 1.0,
    roughness: 0.9,
    metalness: 0.1,
    side: THREE.DoubleSide
  });
}

function buildRoom(scene: THREE.Scene): void {
  const ceilingMat = new THREE.MeshStandardMaterial({
    color: 0x181828,
    emissive: 0x060612,
    emissiveIntensity: 1.0,
    roughness: 0.95,
    metalness: 0.05,
    side: THREE.DoubleSide
  });

  // Back wall (behind gate)
  const backWall = new THREE.Mesh(
    new THREE.BoxGeometry(ROOM_WIDTH, ROOM_HEIGHT, 0.5),
    createWallMaterial()
  );
  backWall.position.set(0, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2);
  scene.add(backWall);
  wallMeshes.push(backWall);

  // Front wall — split into two pieces with doorway gap (4m wide)
  const doorwayWidth = 4;
  const frontPieceWidth = (ROOM_WIDTH - doorwayWidth) / 2;
  for (const xSign of [-1, 1]) {
    const piece = new THREE.Mesh(
      new THREE.BoxGeometry(frontPieceWidth, ROOM_HEIGHT, 0.5),
      createWallMaterial()
    );
    piece.position.set(
      xSign * (doorwayWidth / 2 + frontPieceWidth / 2),
      ROOM_HEIGHT / 2,
      ROOM_DEPTH / 2
    );
    scene.add(piece);
    wallMeshes.push(piece);
  }
  // Door frame top piece
  const doorTop = new THREE.Mesh(
    new THREE.BoxGeometry(doorwayWidth + 0.5, ROOM_HEIGHT - 3.5, 0.5),
    createWallMaterial()
  );
  doorTop.position.set(0, ROOM_HEIGHT - (ROOM_HEIGHT - 3.5) / 2, ROOM_DEPTH / 2);
  scene.add(doorTop);
  wallMeshes.push(doorTop);

  // Left wall
  const leftWall = new THREE.Mesh(
    new THREE.BoxGeometry(0.5, ROOM_HEIGHT, ROOM_DEPTH),
    createWallMaterial()
  );
  leftWall.position.set(-ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 0);
  scene.add(leftWall);
  wallMeshes.push(leftWall);

  // Right wall
  const rightWall = new THREE.Mesh(
    new THREE.BoxGeometry(0.5, ROOM_HEIGHT, ROOM_DEPTH),
    createWallMaterial()
  );
  rightWall.position.set(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 0);
  scene.add(rightWall);
  wallMeshes.push(rightWall);

  // Ceiling
  const ceiling = new THREE.Mesh(
    new THREE.BoxGeometry(ROOM_WIDTH, 0.5, ROOM_DEPTH),
    ceilingMat
  );
  ceiling.position.set(0, ROOM_HEIGHT, 0);
  scene.add(ceiling);
  wallMeshes.push(ceiling);

  // Structural arch supports on walls — heavy Ancient architecture
  const archMat = new THREE.MeshStandardMaterial({ color: 0x15152a, roughness: 0.8, metalness: 0.2 });
  for (let i = -2; i <= 2; i++) {
    if (i === 0) continue;
    // Left wall arches
    const leftArch = new THREE.Mesh(
      new THREE.BoxGeometry(0.4, ROOM_HEIGHT, 0.6),
      archMat
    );
    leftArch.position.set(-ROOM_WIDTH / 2 + 0.4, ROOM_HEIGHT / 2, i * 4);
    scene.add(leftArch);

    // Right wall arches
    const rightArch = new THREE.Mesh(
      new THREE.BoxGeometry(0.4, ROOM_HEIGHT, 0.6),
      archMat
    );
    rightArch.position.set(ROOM_WIDTH / 2 - 0.4, ROOM_HEIGHT / 2, i * 4);
    scene.add(rightArch);
  }

  // Back wall structural frame around gate area
  const frameMat = new THREE.MeshStandardMaterial({ color: 0x1a1a30, roughness: 0.75, metalness: 0.25 });
  // Top beam
  const topBeam = new THREE.Mesh(
    new THREE.BoxGeometry(10, 0.8, 0.6),
    frameMat
  );
  topBeam.position.set(0, ROOM_HEIGHT - 1, -ROOM_DEPTH / 2 + 0.5);
  scene.add(topBeam);
  // Side columns
  for (const xSign of [-1, 1]) {
    const column = new THREE.Mesh(
      new THREE.BoxGeometry(0.8, ROOM_HEIGHT, 0.6),
      frameMat
    );
    column.position.set(xSign * 4.5, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2 + 0.5);
    scene.add(column);
  }

  // Amber floor guide strips — run the full room length, through the gate
  const stripMat = new THREE.MeshStandardMaterial({
    color: 0xddaa33,
    emissive: 0xddaa33,
    emissiveIntensity: 0.4,
    roughness: 0.6,
    metalness: 0.3
  });
  const stripStartZ = ROOM_DEPTH / 2 - 2;
  const stripEndZ = -ROOM_DEPTH / 2 + 2;
  const stripSpacing = 1.4;
  for (let z = stripStartZ; z >= stripEndZ; z -= stripSpacing) {
    for (const x of [-1.2, 1.2]) {
      const strip = new THREE.Mesh(
        new THREE.BoxGeometry(0.12, 0.02, 0.5),
        stripMat
      );
      strip.position.set(x, 0.01, z);
      scene.add(strip);
    }
  }
}

// ─── Stargate construction ───────────────────────────────────────────────────

/** Create a flat-profiled ring (rectangular cross-section) using LatheGeometry */
function createFlatRingGeometry(radius: number, width: number, depth: number, segments: number = 64): THREE.BufferGeometry {
  // Profile: a rectangle at distance `radius` from the Y axis, extruded around Y
  // LatheGeometry rotates a 2D profile around Y. Profile points are (x, y) = (radius, z-offset)
  const halfW = width / 2;
  const halfD = depth / 2;
  const outerR = radius + halfW;
  const innerR = radius - halfW;

  const points = [
    new THREE.Vector2(innerR, -halfD),
    new THREE.Vector2(outerR, -halfD),
    new THREE.Vector2(outerR, halfD),
    new THREE.Vector2(innerR, halfD),
  ];

  const geo = new THREE.LatheGeometry(points, segments);
  // LatheGeometry produces a ring lying in the XZ plane — rotate so it faces forward (XY plane)
  geo.rotateX(Math.PI / 2);
  return geo;
}

async function buildStargate(scene: THREE.Scene): Promise<GateRuntime> {
  const { GLTFLoader } = await import("three/examples/jsm/loaders/GLTFLoader.js");

  // Load the stargate GLB model
  const loader = new GLTFLoader();
  const gateModelUrl = new URL("./assets/stargate.glb", import.meta.url).href;

  let outerRing: THREE.Object3D = new THREE.Group(); // fallback

  try {
    const gltf = await loader.loadAsync(gateModelUrl);
    const gateModel = gltf.scene;

    // The GLB model is unit-sized (~1.0 radius). Scale to match GATE_RADIUS.
    const modelScale = GATE_RADIUS;
    gateModel.scale.setScalar(modelScale);
    gateModel.position.copy(GATE_CENTER);

    // Hide any existing event horizon / portal mesh inside the model
    // (the downloaded model may show an active portal)
    gateModel.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.castShadow = true;
        child.receiveShadow = true;
        child.frustumCulled = false;

        // Check if this mesh is the inner portal/event horizon
        // (typically a flat disc or plane in the center)
        const mat = child.material as THREE.MeshStandardMaterial;
        if (mat && mat.transparent) {
          child.visible = false; // Hide built-in portal — we have our own event horizon
        }
      }
    });

    scene.add(gateModel);
    outerRing = gateModel;
    console.log("[GateRoom] Loaded stargate GLB model");
  } catch (error: Error) {
    console.log("[GateRoom] Failed to load stargate GLB from:", gateModelUrl, ". Using fallback ring. Error:", error.message || error.toString());
    // Fallback: simple torus
    const fallbackMat = new THREE.MeshStandardMaterial({
      color: COLOR_ANCIENT_METAL, 
      roughness: 0.3, 
      metalness: 0.85
    });
    const fallback = new THREE.Mesh(
      new THREE.TorusGeometry(GATE_RADIUS, GATE_TUBE * 2, 32, 64),
      fallbackMat
    );
    fallback.position.copy(GATE_CENTER);
    scene.add(fallback);
    outerRing = fallback;
  }

  // Inner ring — still procedural for spinning animation
  const innerRingMat = new THREE.MeshStandardMaterial({
    color: 0x222235, 
    roughness: 0.25, 
    metalness: 0.9
  });
  const innerRing = new THREE.Mesh(
    createFlatRingGeometry(GATE_RADIUS - 0.05, GATE_TUBE * 1.4, GATE_TUBE * 1.0),
    innerRingMat
  );
  innerRing.position.copy(GATE_CENTER);
  scene.add(innerRing);

  // Chevrons — 7 emissive markers + point lights around the ring
  const chevronMeshes: THREE.Mesh[] = [];
  for (let i = 0; i < CHEVRON_COUNT; i++) {
    const angle = (i / CHEVRON_COUNT) * Math.PI * 2 - Math.PI / 2;
    const chevronGeo = new THREE.BoxGeometry(0.18, 0.3, 0.15);
    const chevronMat = new THREE.MeshStandardMaterial({
      color: COLOR_CHEVRON_OFF,
      roughness: 0.4,
      metalness: 0.7,
      emissive: COLOR_CHEVRON_OFF,
      emissiveIntensity: 0.1
    });
    const chevron = new THREE.Mesh(chevronGeo, chevronMat);
    chevron.position.set(
      GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 0.15),
      GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 0.15),
      GATE_CENTER.z + 0.15
    );
    chevron.lookAt(
      GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 2),
      GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 2),
      GATE_CENTER.z + 0.15
    );
    scene.add(chevron);
    chevronMeshes.push(chevron);
  }

  // Event horizon — our own wormhole surface (hidden until active)
  const horizonMat = new THREE.MeshStandardMaterial({
    color: COLOR_EVENT_HORIZON,
    emissive: COLOR_EVENT_HORIZON,
    emissiveIntensity: 0.8,
    transparent: true,
    opacity: 0,
    side: THREE.DoubleSide,
    roughness: 0.1,
    metalness: 0.0
  });
  const eventHorizon = new THREE.Mesh(
    new THREE.CircleGeometry(GATE_RADIUS - GATE_TUBE - 0.05, 64),
    horizonMat
  );
  eventHorizon.position.copy(GATE_CENTER);
  eventHorizon.visible = false;
  scene.add(eventHorizon);

  return {
    chevronMeshes,
    dialElapsed: 0,
    eventHorizon,
    innerRing,
    kawooshElapsed: 0,
    lockedChevrons: 0,
    outerRing: outerRing as THREE.Mesh,
    pointLights: [],
    state: "idle"
  };
}

// ─── Atmospheric lighting ────────────────────────────────────────────────────

function buildLighting(scene: THREE.Scene, debugObjects: THREE.Object3D[]): THREE.PointLight[] {
  // PERFORMANCE: keep point lights to a minimum (< 8).
  // Use emissive materials for accent glow instead of point lights.
  const lights: THREE.PointLight[] = [];
  const gateZ = GATE_CENTER.z;

  // 1. Single overhead directional-style light for general visibility
  const overheadLight = new THREE.PointLight(0xffeedd, 1.2, 40, 1.5);
  overheadLight.position.set(0, 7.5, 2);
  scene.add(overheadLight);
  lights.push(overheadLight);

  // 2. Gate front — blue Ancient glow
  const gateFrontLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 3, 15, 1.5);
  gateFrontLight.position.set(0, 2, gateZ + 2);
  scene.add(gateFrontLight);
  lights.push(gateFrontLight);

  // 3. Gate back — backlight the ring
  const gateBackLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 2.5, 12, 1.5);
  gateBackLight.position.set(0, 3.5, gateZ - 3);
  scene.add(gateBackLight);
  lights.push(gateBackLight);

  // 4. Gate top — highlights the upper ring
  const gateTopLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 1.5, 10, 2);
  gateTopLight.position.set(0, 7, gateZ);
  scene.add(gateTopLight);
  lights.push(gateTopLight);

  // 5-6. Warm amber side lights (just 2, not 10)
  const COLOR_WARM_ACCENT = 0xffaa44;
  const leftSide = new THREE.PointLight(COLOR_WARM_ACCENT, 1.0, 18, 1.5);
  leftSide.position.set(-ROOM_WIDTH / 2 + 2, 3, 0);
  scene.add(leftSide);
  lights.push(leftSide);

  const rightSide = new THREE.PointLight(COLOR_WARM_ACCENT, 1.0, 18, 1.5);
  rightSide.position.set(ROOM_WIDTH / 2 - 2, 3, 0);
  scene.add(rightSide);
  lights.push(rightSide);

  // 7-10. Floor spotlights aimed at gate faces — restored from working prototype
  const gateY = GATE_CENTER.y;
  const spotPositions = [
    { pos: [-2.5, 0.1, gateZ + 3.5], target: [-GATE_RADIUS * 0.5, gateY, gateZ + 0.15], zDir: -1 },
    { pos: [2.5, 0.1, gateZ + 3.5], target: [GATE_RADIUS * 0.5, gateY, gateZ + 0.15], zDir: -1 },
    { pos: [-2.5, 0.1, gateZ - 3.5], target: [-GATE_RADIUS * 0.5, gateY, gateZ - 0.15], zDir: 1 },
    { pos: [2.5, 0.1, gateZ - 3.5], target: [GATE_RADIUS * 0.5, gateY, gateZ - 0.15], zDir: 1 }
  ];

  const housingMat = new THREE.MeshStandardMaterial({ color: 0x222233, roughness: 0.6, metalness: 0.4 });
  const lensMat = new THREE.MeshStandardMaterial({ color: 0xccddff, emissive: 0xbbddff, emissiveIntensity: 1.5 });

  for (const sp of spotPositions) {
    const spot = new THREE.SpotLight(0xbbddff, 30, 20, Math.PI / 5, 0.5, 1.0);
    spot.position.set(sp.pos[0], sp.pos[1], sp.pos[2]);
    spot.target.position.set(sp.target[0], sp.target[1], sp.target[2]);
    scene.add(spot);
    scene.add(spot.target);

    const helper = new THREE.SpotLightHelper(spot, 0xffff00);
    helper.visible = false;
    scene.add(helper);
    requestAnimationFrame(() => helper.update());
    debugObjects.push(helper);

    const fixtureGroup = new THREE.Group();
    fixtureGroup.position.set(sp.pos[0], 0.18, sp.pos[2]);
    const dx = sp.target[0] - sp.pos[0];
    const dy = sp.target[1] - sp.pos[1];
    const dz = sp.target[2] - sp.pos[2];
    const horizontalDist = Math.sqrt(dx * dx + dz * dz);
    const tiltAngle = Math.atan2(dy, horizontalDist);
    fixtureGroup.rotation.x = sp.zDir * -tiltAngle;

    const housing = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.35, 0.6), housingMat);
    fixtureGroup.add(housing);
    const lens = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.25, 0.05), lensMat);
    lens.position.set(0, 0, sp.zDir * 0.33);
    fixtureGroup.add(lens);
    scene.add(fixtureGroup);
  }

  // NOTE: corridor/storage point lights created in mount() for direct reference

  // Use EMISSIVE MATERIALS instead of point lights for accent strips
  const stripMat = new THREE.MeshStandardMaterial({
    color: COLOR_ANCIENT_GLOW,
    emissive: COLOR_ANCIENT_GLOW,
    emissiveIntensity: 0.5
  });

  // Floor strips along walls
  for (const xSign of [-1, 1]) {
    const strip = new THREE.Mesh(
      new THREE.BoxGeometry(0.06, 0.12, ROOM_DEPTH - 2),
      stripMat
    );
    strip.position.set(xSign * (ROOM_WIDTH / 2 - 0.3), 0.1, 0);
    scene.add(strip);
  }

  // Emissive panels behind gate (cheaper than point lights)
  const backGlowMat = new THREE.MeshStandardMaterial({
    color: 0x2244aa,
    emissive: 0x2244aa,
    emissiveIntensity: 0.6
  });
  for (const xSign of [-1, 1]) {
    const panel = new THREE.Mesh(
      new THREE.BoxGeometry(0.1, 4, 2),
      backGlowMat
    );
    panel.position.set(xSign * 3, 2.5, gateZ - 2);
    scene.add(panel);
  }

  return lights;
}

// ─── HUD overlay (safe DOM creation) ─────────────────────────────────────────

function createHUD(): HTMLDivElement {
  const hud = document.createElement("div");
  hud.id = "gate-hud";

  const container = document.createElement("div");
  Object.assign(container.style, {
    position: "fixed",
    bottom: "40px",
    left: "50%",
    transform: "translateX(-50%)",
    background: "rgba(0, 0, 0, 0.7)",
    color: "white",
    padding: "12px 18px",
    borderRadius: "8px",
    fontFamily: "monospace",
    fontSize: "14px",
    pointerEvents: "none"
  });

  const status = document.createElement("div");
  status.id = "gate-status";
  status.textContent = "Gate Status: Idle";
  container.appendChild(status);

  const chevrons = document.createElement("div");
  chevrons.id = "chevrons-status";
  chevrons.textContent = "Chevrons: 0/7 Engaged";
  container.appendChild(chevrons);

  hud.appendChild(container);
  return hud;
}

// ─── Scene Definition ────────────────────────────────────────────────────────

export default defineGameScene<GateRuntime, {}>({
  id: "destiny-gate-room",
  displayName: "Destiny Gate Room",
  async build(scene, context) {
    // Environment
    buildRoom(scene);
    const gate = await buildStargate(scene);
    const debugObjects: THREE.Object3D[] = [];
    const lights = buildLighting(scene, debugObjects);

    return {
      ...gate,
      scene,
      debugObjects,
      lights
    };
  },
  async mount(context) {
    const { scene, chevronMeshes, eventHorizon, lights, state } = context;
    const gateCenter = new THREE.Vector3(0, 2.8, 0);
    const clock = new THREE.Clock();

    // HUD
    const hud = createHUD();
    document.body.appendChild(hud);

    // Ambient audio
    const ambientAudio = new Audio("./assets/ambient-hum.mp3");
    ambientAudio.loop = true;
    ambientAudio.volume = 0.3;
    ambientAudio.play().catch(() => {}); // Ignore autoplay restrictions

    // Event listeners
    window.addEventListener("keydown", (e) => {
      if (e.key === " " && state === "idle") {
        emit("gate:toggle");
      }
    });

    // Main loop
    context.onRender((delta) => {
      const elapsed = clock.getElapsedTime();

      // Room lights subtle pulse
      const pulseIntensity = 0.5 + Math.sin(elapsed * 0.5) * 0.5;
      lights.forEach(light => {
        if (light instanceof THREE.PointLight) {
          light.intensity = light.userData?.baseIntensity ?? 1.0;
          light.intensity *= pulseIntensity * 0.3 + 0.7;
        }
      });

      // Chevron interaction feedback
      chevronMeshes.forEach((chevron, index) => {
        const mat = chevron.material as THREE.MeshStandardMaterial;
        if (index < (context.lockedChevrons ?? 0)) {
          mat.color.set(context.COLOR_CHEVRON_ON);
          mat.emissive.set(context.COLOR_CHEVRON_ON);
          mat.emissiveIntensity = 0.8;
        } else {
          mat.color.set(context.COLOR_CHEVRON_OFF);
          mat.emissive.set(context.COLOR_CHEVRON_OFF);
          mat.emissiveIntensity = 0.1;
        }
      });

      // Update HUD
      const statusEl = document.getElementById("gate-status");
      if (statusEl) {
        statusEl.textContent = `Gate Status: ${context.state.charAt(0).toUpperCase() + context.state.slice(1)}`;
      }
      const chevronsEl = document.getElementById("chevrons-status");
      if (chevronsEl) {
        chevronsEl.textContent = `Chevrons: ${context.lockedChevrons ?? 0}/7 Engaged`;
      }

      // Auto-update helpers
      scene.traverse((obj) => {
        if (obj instanceof THREE.SpotLightHelper) {
          obj.update();
        }
      });
    });
  },
  async unmount(context) {
    const { scene } = context;

    // Cleanup
    document.body.removeChild(document.getElementById("gate-hud"));

    scene.traverse((object) => {
      if (object instanceof THREE.Mesh || object instanceof THREE.Light || object instanceof THREE.Object3D) {
        object.geometry?.dispose();
        object.material?.dispose();
        object.parent?.remove(object);
      }
    });

    // Clear event listeners
    window.removeEventListener("keydown", (e) => {
      if (e.key === " " && state === "idle") {
        emit("gate:toggle");
      }
    });
  }
});