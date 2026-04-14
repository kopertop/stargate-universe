import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { perfMetrics } from "../../game/app";
import { ShipState, SHIP_STATE_CONFIG, type Section, type Subsystem } from "../../systems/ship-state";
import { emit, scopedBus } from "../../systems/event-bus";
import { Action, SguAction, getInput } from "../../systems/input";
import { createDialogueManager } from "../../systems/dialogue-manager";
import { createNpcManager } from "../../systems/npc-manager";
import { createQuestManager } from "../../systems/quest-manager";
import { createSaveManager } from "../../systems/save-manager";
import { drRushNpc } from "../../npcs/dr-rush";
import { drRushDialogue } from "../../dialogues/dr-rush";
import { registerDestinyPowerCrisis } from "../../quests/destiny-power-crisis";
import { registerAirCrisis, QUEST_ID as AIR_CRISIS_QUEST_ID } from "../../quests/air-crisis";
import type { NpcInstance } from "../../types/npc";
import { setSceneManagers } from "./context";
import { initResources, getResource, addResource, consumeResource, hasResource, getAllResources } from "../../systems/resources";
import { isLimeCollected, setLimeCollected } from "../../systems/scene-transition-state";
import { createHud, createDialoguePanel } from "@kopertop/vibe-game-engine";
import {
	NeuralLocomotionController,
	encodeInput,
	SEQ_LENGTH,
	SEQ_WINDOW,
	BONE_COUNT,
	type SequenceOutput,
} from "@kopertop/vibe-game-engine";
import { createHorizontalCompass } from "../../ui/horizontal-compass";
import { box } from "crashcat";
import {
	CRASHCAT_OBJECT_LAYER_STATIC,
	MotionType,
	rigidBody,
	type CrashcatRigidBody,
} from "@ggez/runtime-physics-crashcat";
import type { DialoguePanelEventBus } from "@kopertop/vibe-game-engine";
import { loadVRMCharacter, type CharacterLoadResult } from "../../characters/character-loader";
import { GateRoomCinematicController } from "./cinematic-controller";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url"
}) as Record<string, () => Promise<string>>;

// ─── Constants ───────────────────────────────────────────────────────────────

// Gate room scaled to match the show's Destiny gate room — a massive
// cavernous Ancient chamber. Gate and characters are NOT scaled — only
// the architectural envelope grows. The room needs to be large enough
// for crew to be thrown 15-20m from the gate during the arrival cinematic.
const ROOM_WIDTH = 100;
const ROOM_DEPTH = 160;
const ROOM_HEIGHT = 32;
// Gate scaled up to fill the frame like the reference — the SGU gate is
// a massive structure. GATE_RADIUS=4 gives an 8-meter diameter ring that
// dominates the establishing shot the way the show's gate does.
const GATE_RADIUS = 4.0;
const GATE_TUBE = 0.7;  // thick visible ring profile
const GATE_CENTER = new THREE.Vector3(0, GATE_RADIUS + 0.2, 0); // bottom of ring just above floor
const CHEVRON_COUNT = 9;

// SGU color palette — blue-grey Ancient metal, matching the reference
const COLOR_ANCIENT_METAL = 0x1e2030;  // dark blue-grey hull metal
const COLOR_ANCIENT_GLOW = 0x4488ff;   // blue accent glow
const COLOR_CHEVRON_OFF = 0x223355;  // visible dim blue even when unlit
const COLOR_CHEVRON_ON = 0x44aaff;
const COLOR_EVENT_HORIZON = 0x88bbff;
// Wall and ceiling — dark blue-grey to match the SGU reference. The room
// should feel like a dimly-lit Ancient military chamber, not a bright hall.
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
		color: COLOR_WALL,
		emissive: 0x0a0a18,
		emissiveIntensity: 0.8,
		roughness: 0.92,
		metalness: 0.2,
		side: THREE.DoubleSide,
	});
}

function buildRoom(scene: THREE.Scene): void {
	const ceilingMat = new THREE.MeshStandardMaterial({
		color: COLOR_CEILING,
		emissive: 0x060612,
		emissiveIntensity: 0.5,
		roughness: 0.95,
		metalness: 0.1,
		side: THREE.DoubleSide,
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

	// Structural arch supports — heavy Ancient buttresses along both walls,
	// matching the reference's repeating arch motif. Spaced along Z with
	// warm alcove lights between them (the amber glow panels in the ref).
	const archMat = new THREE.MeshStandardMaterial({
		color: 0x12122a,
		roughness: 0.85,
		metalness: 0.25,
	});
	const alcoveLightMat = new THREE.MeshStandardMaterial({
		color: 0xffcc88,
		emissive: 0xffaa55,
		emissiveIntensity: 3.0,
		roughness: 0.2,
		metalness: 0,
	});
	const archSpacing = 8;
	const archCount = Math.floor(ROOM_DEPTH / archSpacing);
	for (let i = 0; i < archCount; i++) {
		const z = -ROOM_DEPTH / 2 + 4 + i * archSpacing;
		for (const xSign of [-1, 1]) {
			const xBase = xSign * (ROOM_WIDTH / 2 - 0.3);
			// Buttress column
			const arch = new THREE.Mesh(
				new THREE.BoxGeometry(0.6, ROOM_HEIGHT, 0.8),
				archMat,
			);
			arch.position.set(xBase, ROOM_HEIGHT / 2, z);
			scene.add(arch);
			// Alcove warm light panel between buttresses (like the reference)
			const alcove = new THREE.Mesh(
				new THREE.BoxGeometry(0.1, 2.5, archSpacing - 1.5),
				alcoveLightMat,
			);
			alcove.position.set(xBase + xSign * 0.1, 3.5, z + archSpacing / 2);
			scene.add(alcove);
		}
	}

	// Back wall structural frame around gate area
	const frameMat = new THREE.MeshStandardMaterial({
		color: 0x1a1a30,
		roughness: 0.75,
		metalness: 0.25
	});
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

	// Amber embedded floor lights — matching the SGU reference: two rows of
	// warm rectangular lights flanking the center aisle, like runway markers.
	// Wider and more orange than before to match the reference's amber tone.
	const floorLightMat = new THREE.MeshStandardMaterial({
		color: 0xffaa44,
		emissive: 0xffaa44,
		emissiveIntensity: 2.0,
		roughness: 0.3,
		metalness: 0.1,
	});
	const stripStartZ = ROOM_DEPTH / 2 - 2;
	const stripEndZ = -2;  // stop near the gate
	const stripSpacing = 2.2;
	for (let z = stripStartZ; z >= stripEndZ; z -= stripSpacing) {
		for (const x of [-1.8, 1.8]) {
			const strip = new THREE.Mesh(
				new THREE.BoxGeometry(0.6, 0.02, 0.25),
				floorLightMat,
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

function buildStargate(scene: THREE.Scene): GateRuntime {
	// ── Main ring — TorusGeometry for a thick, visible cross-section ────
	// The old LatheGeometry with 0.22 tube was invisible from 50 units.
	// A torus with tube radius 0.4 gives a bold ring clearly readable at
	// any distance. The emissive glow ensures it self-illuminates even in
	// the dark establishing shot.
	const outerRingMat = new THREE.MeshStandardMaterial({
		color: COLOR_ANCIENT_METAL,
		roughness: 0.3,
		metalness: 0.85,
		emissive: 0x4488cc,
		emissiveIntensity: 4.0,
	});
	const outerRing = new THREE.Mesh(
		new THREE.TorusGeometry(GATE_RADIUS, 0.4, 16, 64),
		outerRingMat,
	);
	outerRing.position.copy(GATE_CENTER);
	scene.add(outerRing);

	// Inner detail ring — slightly smaller, thinner torus
	const innerRingMat = new THREE.MeshStandardMaterial({
		color: 0x222235,
		roughness: 0.25,
		metalness: 0.9,
		emissive: 0x3366aa,
		emissiveIntensity: 3.0,
	});
	const innerRing = new THREE.Mesh(
		new THREE.TorusGeometry(GATE_RADIUS - 0.15, 0.2, 12, 64),
		innerRingMat,
	);

	// ── Glow halo — a flat ring behind the torus that catches distant views ──
	// MeshBasicMaterial ignores lighting and always renders at full colour,
	// guaranteeing the gate silhouette is visible even from 80 units out.
	const glowRingMat = new THREE.MeshBasicMaterial({
		color: 0x2244aa,
		transparent: true,
		opacity: 0.35,
		side: THREE.DoubleSide,
		depthWrite: false,
	});
	const glowRing = new THREE.Mesh(
		new THREE.RingGeometry(GATE_RADIUS - 0.8, GATE_RADIUS + 0.8, 64),
		glowRingMat,
	);
	glowRing.position.copy(GATE_CENTER);
	glowRing.position.z -= 0.1; // slightly behind the torus
	scene.add(glowRing);
	innerRing.position.copy(GATE_CENTER);
	scene.add(innerRing);

	// (Ring segments / symbol-wheel dots REMOVED — 36 decorative bumps
	// visually conflicted with the 9 chevrons and made the gate read as
	// "too busy". The clean silhouette matches the show's look better.)

	// Chevrons — 9 triangular markers around the ring. Each chevron is an
	// isoceles triangle whose apex points radially INWARD toward the gate
	// center (matching the canon Stargate — the pointed end of the V faces
	// the event horizon). Local coordinate convention for the shape:
	//   +Y = apex (will be rotated to face the center)
	//   base sits on the outer ring surface
	const CHEVRON_HEIGHT = 0.42;   // radial length (apex → base)
	const CHEVRON_HALF_W = 0.26;   // tangential width at the base
	const CHEVRON_DEPTH  = 0.14;   // extrusion depth (out of ring plane)
	const chevronShape = new THREE.Shape();
	chevronShape.moveTo( 0,               CHEVRON_HEIGHT / 2);  // apex (will point inward)
	chevronShape.lineTo(-CHEVRON_HALF_W, -CHEVRON_HEIGHT / 2);  // base corner (tangent-left)
	chevronShape.lineTo( CHEVRON_HALF_W, -CHEVRON_HEIGHT / 2);  // base corner (tangent-right)
	chevronShape.closePath();
	const chevronGeo = new THREE.ExtrudeGeometry(chevronShape, {
		depth: CHEVRON_DEPTH,
		bevelEnabled: false,
	});
	// Center extrusion on z=0 so the chevron sits half in front of / half
	// behind the ring plane (matches the recessed-setting on the show gate).
	chevronGeo.translate(0, 0, -CHEVRON_DEPTH / 2);

	const chevronMeshes: THREE.Mesh[] = [];
	// Ring of 9 chevrons, evenly spaced. First chevron at the TOP of the
	// gate (12 o'clock) — that's the canonical "primary chevron" position.
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		const angle = Math.PI / 2 + (i / CHEVRON_COUNT) * Math.PI * 2;
		const chevronMat = new THREE.MeshStandardMaterial({
			color: COLOR_CHEVRON_OFF,
			roughness: 0.4,
			metalness: 0.7,
			emissive: COLOR_CHEVRON_OFF,
			emissiveIntensity: 0.1,
		});
		const chevron = new THREE.Mesh(chevronGeo, chevronMat);
		// Position the mesh origin on the ring radius and offset slightly
		// forward (+Z) so the chevron clearly sits on the front face of the
		// ring rather than embedded / occluded by its geometry.
		const radialOffset = GATE_RADIUS;
		chevron.position.set(
			GATE_CENTER.x + Math.cos(angle) * radialOffset,
			GATE_CENTER.y + Math.sin(angle) * radialOffset,
			GATE_CENTER.z + 0.18,
		);
		// Rotate so local +Y (apex) points radially INWARD toward gate
		// center. The direction "from chevron position to gate center" is
		// (−cos(angle), −sin(angle)), whose atan2 is (angle + π). Since
		// local +Y is already a π/2 rotation from local +X, we subtract
		// π/2 to align local +Y with that inward vector.
		chevron.rotation.z = angle + Math.PI - Math.PI / 2;
		scene.add(chevron);
		chevronMeshes.push(chevron);
	}

	// Event horizon — the wormhole surface (hidden until active)
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
		outerRing,
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

	// ── Global fill (distance-independent) ──────────────────────────────
	// Room is 100×160×32. Point lights with physical decay can't reach
	// across 80+ units. Use distance-independent lights for base fill,
	// then add point-light accents for local colour only.
	// Low ambient — just enough to keep surfaces readable, not washed out.
	const ambientLight = new THREE.AmbientLight(0x334455, 3.0);
	scene.add(ambientLight);
	const hemisphereLight = new THREE.HemisphereLight(0x556688, 0x222233, 2.0);
	scene.add(hemisphereLight);

	// Directional from above-front — gentle fill, not blinding.
	const dirLight = new THREE.DirectionalLight(0xaabbcc, 1.5);
	dirLight.position.set(0, 25, 40);
	dirLight.target.position.set(0, 0, 0);
	scene.add(dirLight);
	scene.add(dirLight.target);

	// ── Gate-area accent lights ──────────────────────────────────────────
	// All decay:0 (infinite range) so the blue glow reads from the
	// establishing shot 50+ units away.

	// Directly IN FRONT of the gate ring — illuminates the ring face
	// so the dormant gate silhouette is unmistakable.
	const gateRingLight = new THREE.PointLight(0x6699ff, 6, 0, 0);
	gateRingLight.position.set(0, GATE_CENTER.y, gateZ + 2);
	scene.add(gateRingLight);
	lights.push(gateRingLight);

	// Wider gate-area blue glow
	const gateFrontLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 4, 0, 0);
	gateFrontLight.position.set(0, 4, gateZ + 8);
	scene.add(gateFrontLight);
	lights.push(gateFrontLight);

	const gateBackLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 3, 0, 0);
	gateBackLight.position.set(0, 5, gateZ - 6);
	scene.add(gateBackLight);
	lights.push(gateBackLight);

	const gateTopLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 3, 0, 0);
	gateTopLight.position.set(0, 12, gateZ);
	scene.add(gateTopLight);
	lights.push(gateTopLight);

	// Overhead room light — decay:0 for even fill
	const overheadLight = new THREE.PointLight(0xffeedd, 2, 0, 0);
	overheadLight.position.set(0, ROOM_HEIGHT - 3, ROOM_DEPTH / 4);
	scene.add(overheadLight);
	lights.push(overheadLight);

	// Warm amber side accents — three rows along Z, both sides
	const COLOR_WARM_ACCENT = 0xffaa44;
	for (const zOff of [0, ROOM_DEPTH / 3, 2 * ROOM_DEPTH / 3]) {
		for (const xSign of [-1, 1]) {
			const side = new THREE.PointLight(COLOR_WARM_ACCENT, 1.5, 0, 0);
			side.position.set(xSign * (ROOM_WIDTH / 3), 6, zOff);
			scene.add(side);
			lights.push(side);
		}
	}

	// 7-10. Floor spotlights aimed at gate faces — restored from working prototype
	const gateY = GATE_CENTER.y;
	const spotPositions = [
		{ pos: [-2.5, 0.1, gateZ + 3.5], target: [-GATE_RADIUS * 0.5, gateY, gateZ + 0.15], zDir: -1 },
		{ pos: [2.5, 0.1, gateZ + 3.5], target: [GATE_RADIUS * 0.5, gateY, gateZ + 0.15], zDir: -1 },
		{ pos: [-2.5, 0.1, gateZ - 3.5], target: [-GATE_RADIUS * 0.5, gateY, gateZ - 0.15], zDir: 1 },
		{ pos: [2.5, 0.1, gateZ - 3.5], target: [GATE_RADIUS * 0.5, gateY, gateZ - 0.15], zDir: 1 },
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
		// BUG-006: call update() synchronously — the old RAF fired on a potentially
		// disposed scene if a rapid scene transition happened before the frame ran.
		helper.update();
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
		color: "#4488ff",
		fontFamily: "'Courier New', monospace",
		fontSize: "16px",
		textAlign: "center",
		textShadow: "0 0 10px #4488ff44",
		pointerEvents: "none",
		userSelect: "none"
	});

	const statusEl = document.createElement("div");
	statusEl.id = "gate-status";
	// Status text is driven by quest progress / cinematic state — no static
	// debug prompt here. Left empty so the HUD strip starts hidden until
	// something meaningful to say.
	statusEl.textContent = "";

	const chevronsEl = document.createElement("div");
	chevronsEl.id = "gate-chevrons";
	Object.assign(chevronsEl.style, {
		marginTop: "8px",
		fontSize: "20px",
		letterSpacing: "4px"
	});

	container.appendChild(statusEl);
	container.appendChild(chevronsEl);
	hud.appendChild(container);
	document.body.appendChild(hud);
	return hud;
}

function updateHUD(gate: GateRuntime): void {
	const status = document.getElementById("gate-status");
	const chevrons = document.getElementById("gate-chevrons");
	if (!status || !chevrons) return;

	let chevronDisplay = "";
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		chevronDisplay += i < gate.lockedChevrons ? "\u25C6" : "\u25C7";
	}
	chevrons.textContent = chevronDisplay;

	switch (gate.state) {
		case "idle":
			status.textContent = "";
			break;
		case "dialing":
			status.textContent = `Dialing... Chevron ${gate.lockedChevrons} of ${CHEVRON_COUNT}`;
			break;
		case "kawoosh":
			status.textContent = "Chevron 9 locked!";
			break;
		case "active":
			status.textContent = "Wormhole established";
			break;
		case "shutdown":
			status.textContent = "Wormhole disengaged";
			break;
	}
}

// ─── Gate activation logic ───────────────────────────────────────────────────

const DIAL_TIME_PER_CHEVRON = 0.6;
const KAWOOSH_DURATION = 1.2;
const SHUTDOWN_DURATION = 0.8;

function updateGate(gate: GateRuntime, delta: number): void {
	switch (gate.state) {
		case "dialing":
			updateDialing(gate, delta);
			break;
		case "kawoosh":
			updateKawoosh(gate, delta);
			break;
		case "active":
			updateActiveWormhole(gate, delta);
			break;
		case "shutdown":
			updateShutdown(gate, delta);
			break;
	}
	updateHUD(gate);
}

function startDial(gate: GateRuntime): void {
	if (gate.state !== "idle") return;
	gate.state = "dialing";
	gate.dialElapsed = 0;
	gate.lockedChevrons = 0;
}

function shutdownGate(gate: GateRuntime): void {
	if (gate.state !== "active") return;
	gate.state = "shutdown";
	gate.kawooshElapsed = 0;
}

function updateDialing(gate: GateRuntime, delta: number): void {
	gate.dialElapsed += delta;

	// Spin the inner ring (SGU-style continuous rotation)
	gate.innerRing.rotation.z += delta * 3.0;

	// Lock chevrons at intervals
	const targetChevrons = Math.min(
		Math.floor(gate.dialElapsed / DIAL_TIME_PER_CHEVRON) + 1,
		CHEVRON_COUNT
	);

	while (gate.lockedChevrons < targetChevrons) {
		lockChevron(gate, gate.lockedChevrons);
		gate.lockedChevrons++;
	}

	// Inner ring glow increases during dial
	const mat = gate.innerRing.material as THREE.MeshStandardMaterial;
	mat.emissive = new THREE.Color(COLOR_ANCIENT_GLOW);
	mat.emissiveIntensity = 0.3 + (gate.lockedChevrons / CHEVRON_COUNT) * 0.5;

	// All chevrons locked — start kawoosh
	if (gate.lockedChevrons >= CHEVRON_COUNT) {
		gate.state = "kawoosh";
		gate.kawooshElapsed = 0;
		gate.eventHorizon.visible = true;
		(gate.eventHorizon.material as THREE.MeshStandardMaterial).opacity = 0;
	}
}

function lockChevron(gate: GateRuntime, index: number): void {
	const chevron = gate.chevronMeshes[index];
	const mat = chevron.material as THREE.MeshStandardMaterial;
	mat.color.set(COLOR_CHEVRON_ON);
	mat.emissive.set(COLOR_CHEVRON_ON);
	mat.emissiveIntensity = 1.2;
}

function updateKawoosh(gate: GateRuntime, delta: number): void {
	gate.kawooshElapsed += delta;
	const progress = gate.kawooshElapsed / KAWOOSH_DURATION;
	const horizonMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;

	if (progress < 0.3) {
		// Phase 1: Burst outward (kawoosh!)
		const burstProgress = progress / 0.3;
		const scale = 0.1 + burstProgress * 1.4;
		gate.eventHorizon.scale.set(scale, scale, 1);
		horizonMat.opacity = burstProgress * 0.95;
		horizonMat.emissiveIntensity = 1.5 + burstProgress * 3.0;
	} else if (progress < 0.6) {
		// Phase 2: Retract to stable size
		const retractProgress = (progress - 0.3) / 0.3;
		const scale = 1.5 - retractProgress * 0.5;
		gate.eventHorizon.scale.set(scale, scale, 1);
		horizonMat.emissiveIntensity = 4.5 - retractProgress * 3.5;
	} else {
		// Phase 3: Settle
		gate.eventHorizon.scale.set(1, 1, 1);
		horizonMat.opacity = 0.8;
		horizonMat.emissiveIntensity = 1.0;
	}

	// Stop inner ring spinning gradually
	gate.innerRing.rotation.z += delta * (3.0 * (1 - progress));

	if (gate.kawooshElapsed >= KAWOOSH_DURATION) {
		gate.state = "active";
		gate.dialElapsed = 0;
		gate.eventHorizon.scale.set(1, 1, 1);
		horizonMat.opacity = 0.8;
		horizonMat.emissiveIntensity = 1.0;
	}
}

let activeWormholeFrame = 0;

function updateActiveWormhole(gate: GateRuntime, delta: number): void {
	gate.dialElapsed += delta;
	activeWormholeFrame++;

	// Only update material every 3rd frame to reduce transparent re-sort cost
	if (activeWormholeFrame % 3 === 0) {
		const horizonMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;
		const pulse = Math.sin(gate.dialElapsed * 2.0) * 0.05;
		horizonMat.opacity = 0.75 + pulse;
		horizonMat.emissiveIntensity = 0.8 + pulse * 2;
	}

	// Subtle rotation (cheap — just a transform, no material change)
	gate.eventHorizon.rotation.z += delta * 0.2;

	// Skip light modulation entirely — static intensity during active wormhole
	// (changing light intensity every frame forces full scene re-light)
}

function updateShutdown(gate: GateRuntime, delta: number): void {
	gate.kawooshElapsed += delta;
	const progress = Math.min(gate.kawooshElapsed / SHUTDOWN_DURATION, 1);
	const horizonMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;

	// Shrink and fade
	const scale = 1 - progress;
	gate.eventHorizon.scale.set(scale, scale, 1);
	horizonMat.opacity = 0.8 * (1 - progress);
	horizonMat.emissiveIntensity = 1.0 * (1 - progress);

	if (progress >= 1) {
		gate.state = "idle";
		gate.eventHorizon.visible = false;
		gate.lockedChevrons = 0;
		gate.dialElapsed = 0;

		// Reset chevrons
		for (const chevron of gate.chevronMeshes) {
			const mat = chevron.material as THREE.MeshStandardMaterial;
			mat.color.set(COLOR_CHEVRON_OFF);
			mat.emissive.set(COLOR_CHEVRON_OFF);
			mat.emissiveIntensity = 0.1;
		}

		// Reset inner ring
		const innerMat = gate.innerRing.material as THREE.MeshStandardMaterial;
		innerMat.emissiveIntensity = 0;

		// Reset lights
		for (const light of gate.pointLights) {
			if (light.color.getHex() === COLOR_ANCIENT_GLOW) {
				light.intensity = 2;
			}
		}
	}
}

// ─── Camera arm pull-in (professional third-person camera technique) ─────────
// Instead of making walls transparent, pull the camera closer to the player
// when geometry is between them. Uses a single raycast from player to desired
// camera position — if it hits something, camera snaps to the hit point.

const CAMERA_MIN_DISTANCE = 1.0;
const CAMERA_PULL_IN_OFFSET = 0.5;
const CAMERA_RECOVER_SPEED = 1.5;
const CAMERA_PULL_IN_SPEED = 15.0;
const cameraRaycaster = new THREE.Raycaster();
const scratchCamDir = new THREE.Vector3();
const occludableMeshes: THREE.Mesh[] = [];
let smoothedCamDistance = -1;
let lastHitDistance = Infinity; // track where the wall actually is

function updateCameraPullIn(camera: THREE.PerspectiveCamera, playerPos: THREE.Vector3, delta: number): void {
	const camDir = scratchCamDir.subVectors(camera.position, playerPos);
	const desiredDistance = camDir.length();
	if (desiredDistance < 0.01) return;
	camDir.normalize();

	// Raycast from player toward desired camera position
	cameraRaycaster.set(playerPos, camDir);
	cameraRaycaster.far = desiredDistance + 1.0;
	const hits = cameraRaycaster.intersectObjects(occludableMeshes, false);

	if (hits.length > 0) {
		lastHitDistance = hits[0].distance;
	} else {
		lastHitDistance = Infinity;
	}

	// Target: pull in if wall is between player and camera
	const wallClearance = lastHitDistance - CAMERA_PULL_IN_OFFSET;
	const targetDistance = lastHitDistance < desiredDistance + 0.5
		? Math.max(CAMERA_MIN_DISTANCE, wallClearance)
		: desiredDistance;

	if (smoothedCamDistance < 0) smoothedCamDistance = desiredDistance;

	// Pull in fast, recover slowly — but ONLY recover if we're safely past the wall
	if (targetDistance < smoothedCamDistance) {
		// Pulling in
		smoothedCamDistance += (targetDistance - smoothedCamDistance) * Math.min(1, delta * CAMERA_PULL_IN_SPEED);
	} else if (smoothedCamDistance < desiredDistance - 0.1) {
		// Recovering — only if the wall is far enough away (dead zone prevents bounce)
		const safeToRecover = lastHitDistance > smoothedCamDistance + 1.0;
		if (safeToRecover) {
			smoothedCamDistance += (desiredDistance - smoothedCamDistance) * Math.min(1, delta * CAMERA_RECOVER_SPEED);
		}
	} else {
		smoothedCamDistance = desiredDistance;
	}

	if (smoothedCamDistance < desiredDistance - 0.05) {
		camera.position.copy(playerPos).addScaledVector(camDir, smoothedCamDistance);
	}
}

// ─── Debug overlay ───────────────────────────────────────────────────────────

function createDebugOverlay(): { element: HTMLDivElement; update: () => void } {
	const el = document.createElement("div");
	el.id = "debug-overlay";
	Object.assign(el.style, {
		position: "fixed",
		top: "8px",
		left: "8px",
		color: "#44ff88",
		fontFamily: "'Courier New', monospace",
		fontSize: "12px",
		lineHeight: "1.6",
		background: "rgba(0, 0, 0, 0.6)",
		padding: "8px 12px",
		borderRadius: "4px",
		pointerEvents: "none",
		userSelect: "none",
		zIndex: "999",
		minWidth: "200px"
	});
	document.body.appendChild(el);

	let frameCount = 0;
	const update = () => {
		frameCount++;
		if (frameCount % 10 !== 0) return; // update text every 10 frames

		const m = perfMetrics;
		const fpsColor = m.fps >= 50 ? "#44ff88" : m.fps >= 30 ? "#ffaa44" : "#ff4444";

		el.textContent = [
			`FPS: ${m.fps}`,
			`Frame: ${m.frameMs.toFixed(1)}ms`,
			`Physics: ${m.physicsMs.toFixed(1)}ms (${m.physicsHz}Hz, ${m.physicsSteps} steps)`,
			`Render: ${m.renderMs.toFixed(1)}ms`,
			`Draw calls: ${m.drawCalls}`,
			`Triangles: ${m.triangles.toLocaleString()}`,
		].join("\n");
		el.style.whiteSpace = "pre";
		el.style.color = fpsColor;
	};

	return { element: el, update };
}

// ─── Escape menu ─────────────────────────────────────────────────────────────

type EscapeMenu = {
	element: HTMLDivElement;
	visible: boolean;
	show: () => void;
	hide: () => void;
	dispose: () => void;
};

function createEscapeMenu(domElement: HTMLCanvasElement): EscapeMenu {
	const overlay = document.createElement("div");
	overlay.id = "escape-menu";
	Object.assign(overlay.style, {
		position: "fixed",
		inset: "0",
		background: "rgba(0, 0, 0, 0.85)",
		display: "none",
		alignItems: "center",
		justifyContent: "center",
		flexDirection: "column",
		gap: "16px",
		zIndex: "1000",
		fontFamily: "'Courier New', monospace"
	});

	const title = document.createElement("div");
	Object.assign(title.style, {
		color: "#4488ff",
		fontSize: "28px",
		fontWeight: "bold",
		textShadow: "0 0 20px #4488ff66",
		marginBottom: "24px"
	});
	title.textContent = "STARGATE UNIVERSE";
	overlay.appendChild(title);

	const buttonStyle = {
		background: "rgba(68, 136, 255, 0.1)",
		border: "1px solid #4488ff44",
		color: "#88bbff",
		padding: "12px 32px",
		fontSize: "16px",
		fontFamily: "'Courier New', monospace",
		cursor: "pointer",
		minWidth: "220px",
		textAlign: "center"
	};

	const resumeBtn = document.createElement("button");
	Object.assign(resumeBtn.style, buttonStyle);
	resumeBtn.textContent = "Resume";
	resumeBtn.addEventListener("click", () => {
		menu.hide();
		void domElement.requestPointerLock();
	});
	overlay.appendChild(resumeBtn);

	const fullscreenBtn = document.createElement("button");
	Object.assign(fullscreenBtn.style, buttonStyle);
	fullscreenBtn.textContent = "Toggle Fullscreen";
	fullscreenBtn.addEventListener("click", () => {
		if (document.fullscreenElement) {
			void document.exitFullscreen();
			fullscreenBtn.textContent = "Enter Fullscreen";
		} else {
			void document.documentElement.requestFullscreen();
			fullscreenBtn.textContent = "Exit Fullscreen";
		}
	});
	overlay.appendChild(fullscreenBtn);

	const hintEl = document.createElement("div");
	Object.assign(hintEl.style, {
		color: "#4488ff66",
		fontSize: "12px",
		marginTop: "24px"
	});
	hintEl.textContent = "Click anywhere or press Resume to continue";
	overlay.appendChild(hintEl);

	document.body.appendChild(overlay);

	const menu: EscapeMenu = {
		element: overlay,
		visible: false,
		show() {
			menu.visible = true;
			overlay.style.display = "flex";
			fullscreenBtn.textContent = document.fullscreenElement
				? "Exit Fullscreen" : "Enter Fullscreen";
		},
		hide() {
			menu.visible = false;
			overlay.style.display = "none";
		},
		dispose() {
			overlay.remove();
		}
	};

	return menu;
}

// ─── Fullscreen + pointer lock integration ───────────────────────────────────

function setupFullscreen(domElement: HTMLCanvasElement, menu: EscapeMenu): () => void {
	const handlePointerLockChange = () => {
		if (document.pointerLockElement === domElement) {
			// Pointer lock acquired — go fullscreen if not already
			if (!document.fullscreenElement) {
				void document.documentElement.requestFullscreen().catch(() => {
					// Fullscreen may fail (user gesture required) — that's okay
				});
			}
			menu.hide();
		} else {
			// Pointer lock lost (ESC pressed) — show escape menu
			menu.show();
		}
	};

	document.addEventListener("pointerlockchange", handlePointerLockChange);

	return () => {
		document.removeEventListener("pointerlockchange", handlePointerLockChange);
	};
}

// ─── Corridor & Storage Room extension ───────────────────────────────────────

const CORRIDOR_Z_START = ROOM_DEPTH / 2;     // starts at the front wall of gate room
const CORRIDOR_WIDTH_EXT = 4;
const CORRIDOR_LENGTH = 12;
const STORAGE_WIDTH = 10;
const STORAGE_DEPTH = 8;
const EXT_ROOM_HEIGHT = 5;
const ANCIENT_GLOW_THRESHOLD = 0.6;

// Shared materials for corridor/storage — reuse, don't recreate
const extWallMat = new THREE.MeshStandardMaterial({
	color: 0x222238, emissive: 0x141428, emissiveIntensity: 1.0,
	roughness: 0.9, metalness: 0.1, side: THREE.DoubleSide
});
const extCeilingMat = new THREE.MeshStandardMaterial({
	color: 0x181828, emissive: 0x0c0c20, emissiveIntensity: 1.0,
	roughness: 0.95, metalness: 0.05
});

function buildCorridor(scene: THREE.Scene): void {
	const cz = CORRIDOR_Z_START + CORRIDOR_LENGTH / 2;

	// Left & right walls
	for (const xSign of [-1, 1]) {
		const wall = new THREE.Mesh(
			new THREE.BoxGeometry(0.3, EXT_ROOM_HEIGHT, CORRIDOR_LENGTH), extWallMat
		);
		wall.position.set(xSign * CORRIDOR_WIDTH_EXT / 2, EXT_ROOM_HEIGHT / 2, cz);
		scene.add(wall);
		occludableMeshes.push(wall);
	}

	// Ceiling
	const ceil = new THREE.Mesh(
		new THREE.BoxGeometry(CORRIDOR_WIDTH_EXT, 0.3, CORRIDOR_LENGTH), extCeilingMat
	);
	ceil.position.set(0, EXT_ROOM_HEIGHT, cz);
	scene.add(ceil);
	occludableMeshes.push(ceil);

	// Floor strip emissives
	const stripMat = new THREE.MeshStandardMaterial({
		color: COLOR_ANCIENT_GLOW, emissive: COLOR_ANCIENT_GLOW, emissiveIntensity: 0.3
	});
	for (const xSign of [-1, 1]) {
		const strip = new THREE.Mesh(
			new THREE.BoxGeometry(0.05, 0.08, CORRIDOR_LENGTH - 1), stripMat
		);
		strip.position.set(xSign * (CORRIDOR_WIDTH_EXT / 2 - 0.2), 0.05, cz);
		scene.add(strip);
	}
}

function buildStorageRoom(scene: THREE.Scene): void {
	const sz = CORRIDOR_Z_START + CORRIDOR_LENGTH + STORAGE_DEPTH / 2;

	// Back wall
	const back = new THREE.Mesh(
		new THREE.BoxGeometry(STORAGE_WIDTH, EXT_ROOM_HEIGHT, 0.3), extWallMat
	);
	back.position.set(0, EXT_ROOM_HEIGHT / 2, sz + STORAGE_DEPTH / 2);
	scene.add(back);
	occludableMeshes.push(back);

	// Side walls with doorway gap
	const sideWidth = (STORAGE_WIDTH - CORRIDOR_WIDTH_EXT) / 2;
	for (const xSign of [-1, 1]) {
		const front = new THREE.Mesh(
			new THREE.BoxGeometry(sideWidth, EXT_ROOM_HEIGHT, 0.3), extWallMat
		);
		front.position.set(
			xSign * (CORRIDOR_WIDTH_EXT / 2 + sideWidth / 2),
			EXT_ROOM_HEIGHT / 2, sz - STORAGE_DEPTH / 2
		);
		scene.add(front);
		occludableMeshes.push(front);

		const side = new THREE.Mesh(
			new THREE.BoxGeometry(0.3, EXT_ROOM_HEIGHT, STORAGE_DEPTH), extWallMat
		);
		side.position.set(xSign * STORAGE_WIDTH / 2, EXT_ROOM_HEIGHT / 2, sz);
		scene.add(side);
		occludableMeshes.push(side);
	}

	// Ceiling
	const ceil = new THREE.Mesh(
		new THREE.BoxGeometry(STORAGE_WIDTH, 0.3, STORAGE_DEPTH), extCeilingMat
	);
	ceil.position.set(0, EXT_ROOM_HEIGHT, sz);
	scene.add(ceil);
	occludableMeshes.push(ceil);
}

// ─── Ship State driven room lighting ─────────────────────────────────────────

interface RoomLighting {
	sectionId: string;
	ancientPanels: THREE.Mesh[];
	emergencyStrips: THREE.Mesh[];
}

function createRoomLighting(
	scene: THREE.Scene, sectionId: string,
	cx: number, cz: number, width: number, depth: number, height: number
): RoomLighting {
	// NO point lights — use emissive-only for perf. One emissive ceiling panel
	// acts as a fake "overhead light" via emissive intensity.
	const ceilingLight = new THREE.Mesh(
		new THREE.BoxGeometry(width * 0.3, 0.05, depth * 0.3),
		new THREE.MeshStandardMaterial({
			color: 0xffeedd, emissive: 0xffeedd, emissiveIntensity: 0,
		})
	);
	ceilingLight.position.set(cx, height - 0.15, cz);
	scene.add(ceilingLight);

	// Ancient glow panels on walls
	const ancientPanels: THREE.Mesh[] = [ceilingLight];
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0x44ddcc, emissive: 0x44ddcc, emissiveIntensity: 0,
	});
	for (const xSign of [-1, 1]) {
		const panel = new THREE.Mesh(
			new THREE.BoxGeometry(0.04, 0.6, depth * 0.5), glowMat.clone()
		);
		panel.position.set(cx + xSign * (width / 2 - 0.25), height * 0.55, cz);
		scene.add(panel);
		ancientPanels.push(panel);
	}

	// Emergency floor strips
	const emergencyStrips: THREE.Mesh[] = [];
	const eMat = new THREE.MeshStandardMaterial({
		color: 0xff2200, emissive: 0xff2200, emissiveIntensity: 0,
	});
	for (const xSign of [-1, 1]) {
		const strip = new THREE.Mesh(
			new THREE.BoxGeometry(0.06, 0.04, depth - 1), eMat.clone()
		);
		strip.position.set(cx + xSign * (width / 2 - 0.25), 0.03, cz);
		scene.add(strip);
		emergencyStrips.push(strip);
	}

	return { sectionId, ancientPanels, emergencyStrips };
}

function updateRoomLighting(rl: RoomLighting, section: Section): void {
	const power = section.powerLevel;

	// Ancient glow panels (first one is the ceiling emissive "light")
	// Ceiling emissive acts as the overhead — scales with power
	for (let i = 0; i < rl.ancientPanels.length; i++) {
		const mat = rl.ancientPanels[i].material as THREE.MeshStandardMaterial;
		if (i === 0) {
			// Ceiling light — emissive intensity scales with power
			const target = power * 1.5;
			mat.emissiveIntensity += (target - mat.emissiveIntensity) * 0.1;
		} else {
			// Wall glow panels — activate above threshold
			const glowTarget = power > ANCIENT_GLOW_THRESHOLD
				? ((power - ANCIENT_GLOW_THRESHOLD) / (1.0 - ANCIENT_GLOW_THRESHOLD)) * 0.8 : 0;
			mat.emissiveIntensity += (glowTarget - mat.emissiveIntensity) * 0.1;
		}
	}

	// Emergency strips — activate below 0.3 power
	const emergTarget = power < 0.3 ? (1 - power / 0.3) * 0.6 : 0;
	for (const strip of rl.emergencyStrips) {
		const mat = strip.material as THREE.MeshStandardMaterial;
		mat.emissiveIntensity += (emergTarget - mat.emissiveIntensity) * 0.1;
	}
}

// ─── Subsystem visual markers ────────────────────────────────────────────────

interface SubsystemVisual {
	id: string;
	mesh: THREE.Mesh;
	indicator: THREE.Mesh;
}

function createSubsystemVisual(scene: THREE.Scene, sub: Subsystem, pos: THREE.Vector3, wallSide: "left" | "right" | "back"): SubsystemVisual {
	const bodyMat = new THREE.MeshStandardMaterial({ color: 0x333348, roughness: 0.5, metalness: 0.6 });
	const indMat = new THREE.MeshStandardMaterial({ color: 0x44ff88, emissive: 0x44ff88, emissiveIntensity: 0.5 });

	// Body: thin against wall, taller than wide
	const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.8, 0.6), bodyMat);
	mesh.position.copy(pos);

	// Indicator: on the face pointing toward room center
	const indicator = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.1, 0.3), indMat);
	indicator.position.copy(pos);
	indicator.position.y += 0.5;

	if (wallSide === "right") {
		// Mounted on right wall — body flush, indicator on left face (toward center)
		mesh.position.x = pos.x - 0.15;
		indicator.position.x = pos.x - 0.18; // flush with body, on the room-facing side
		indicator.position.z = pos.z;
	} else if (wallSide === "left") {
		// Mounted on left wall — indicator faces right
		mesh.position.x = pos.x + 0.15;
		indicator.position.x = pos.x + 0.18;
		indicator.position.z = pos.z;
	} else {
		// Back wall — indicator faces toward player (positive Z)
		mesh.rotation.y = Math.PI / 2;
		indicator.position.z = pos.z + 0.18;
	}

	scene.add(mesh);
	scene.add(indicator);

	return { id: sub.id, mesh, indicator };
}

function updateSubsystemVisual(sv: SubsystemVisual, sub: Subsystem): void {
	const mat = sv.indicator.material as THREE.MeshStandardMaterial;
	if (sub.condition >= 0.8) {
		mat.color.set(0x44ff88); mat.emissive.set(0x44ff88); mat.emissiveIntensity = 0.8;
	} else if (sub.condition >= 0.3) {
		mat.color.set(0xffaa44); mat.emissive.set(0xffaa44); mat.emissiveIntensity = 0.6;
	} else {
		mat.color.set(0xff2200); mat.emissive.set(0xff2200); mat.emissiveIntensity = 0.3;
	}
}

// ─── Supply crates ───────────────────────────────────────────────────────────

interface SupplyCrate {
	mesh: THREE.Group;
	position: THREE.Vector3;
	contents: number;
	looted: boolean;
}

function createSupplyCrate(scene: THREE.Scene, pos: THREE.Vector3, contents: number): SupplyCrate {
	const group = new THREE.Group();
	group.position.copy(pos);

	// Crate body — brighter with emissive so visible in dark rooms
	const crateMat = new THREE.MeshStandardMaterial({
		color: 0x776644, emissive: 0x221100, emissiveIntensity: 1.0,
		roughness: 0.85, metalness: 0.1
	});
	const body = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.5, 0.5), crateMat);
	body.position.y = 0.25;
	group.add(body);

	// Lid (slightly lighter)
	const lidMat = new THREE.MeshStandardMaterial({
		color: 0x887755, emissive: 0x221100, emissiveIntensity: 1.0,
		roughness: 0.8, metalness: 0.1
	});
	const lid = new THREE.Mesh(new THREE.BoxGeometry(0.75, 0.08, 0.55), lidMat);
	lid.position.y = 0.54;
	group.add(lid);

	// Glowing indicator strip on front — shows it's lootable
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0xffaa22, emissive: 0xffaa22, emissiveIntensity: 0.6
	});
	const glow = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.04, 0.02), glowMat);
	glow.position.set(0, 0.35, 0.26);
	group.add(glow);

	scene.add(group);

	return { mesh: group, position: pos, contents, looted: false };
}

function markCrateLooted(crate: SupplyCrate): void {
	crate.looted = true;
	// Dim the glow strip
	const glow = crate.mesh.children[2] as THREE.Mesh;
	if (glow) {
		const mat = glow.material as THREE.MeshStandardMaterial;
		mat.emissive.set(0x222211);
		mat.emissiveIntensity = 0.1;
	}
	// Open the lid slightly
	const lid = crate.mesh.children[1];
	if (lid) {
		lid.rotation.x = -0.4;
		lid.position.z = -0.1;
		lid.position.y = 0.58;
	}
}

// ─── 3D Repair Progress Bar ─────────────────────────────────────────────────

interface RepairProgressBar3D {
	group: THREE.Group;
	/** Set up for a repair with N segments, positioned above a world point. */
	init(partCount: number, worldPos: THREE.Vector3): void;
	/** Update fill (0-1) and billboard toward camera. */
	update(pct: number, camera: THREE.Camera): void;
	/** Hide and reset. */
	hide(): void;
	/** Clean up GPU resources. */
	dispose(): void;
}

function createRepairProgressBar3D(): RepairProgressBar3D {
	const BAR_WIDTH = 0.8;
	const BAR_HEIGHT = 0.06;
	const BAR_Y_OFFSET = 0.0;

	const group = new THREE.Group();
	group.visible = false;

	// Background track
	const trackGeo = new THREE.PlaneGeometry(BAR_WIDTH, BAR_HEIGHT);
	const trackMat = new THREE.MeshBasicMaterial({ color: 0x111118, transparent: true, opacity: 0.85, depthTest: false });
	const track = new THREE.Mesh(trackGeo, trackMat);
	track.renderOrder = 998;
	group.add(track);

	// Border (slightly larger plane behind)
	const borderGeo = new THREE.PlaneGeometry(BAR_WIDTH + 0.02, BAR_HEIGHT + 0.02);
	const borderMat = new THREE.MeshBasicMaterial({ color: 0x44ddcc, transparent: true, opacity: 0.4, depthTest: false });
	const border = new THREE.Mesh(borderGeo, borderMat);
	border.position.z = -0.001;
	border.renderOrder = 997;
	group.add(border);

	// Fill bar — scaled on X axis to show progress
	const fillGeo = new THREE.PlaneGeometry(BAR_WIDTH - 0.02, BAR_HEIGHT - 0.02);
	// Shift geometry origin to left edge so scale works from left-to-right
	fillGeo.translate((BAR_WIDTH - 0.02) / 2, 0, 0);
	const fillMat = new THREE.MeshBasicMaterial({ color: 0x44ddcc, transparent: true, opacity: 0.9, depthTest: false });
	const fill = new THREE.Mesh(fillGeo, fillMat);
	fill.position.x = -(BAR_WIDTH - 0.02) / 2;
	fill.position.z = 0.001;
	fill.scale.x = 0;
	fill.renderOrder = 999;
	group.add(fill);

	// Glow behind fill
	const glowMat = new THREE.MeshBasicMaterial({ color: 0x44ddcc, transparent: true, opacity: 0.3, depthTest: false });
	const glow = new THREE.Mesh(new THREE.PlaneGeometry(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.06), glowMat);
	glow.position.z = -0.002;
	glow.renderOrder = 996;
	group.add(glow);

	// Segment dividers (rebuilt per init)
	const dividers: THREE.Mesh[] = [];
	const dividerMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.9, depthTest: false });

	return {
		group,
		init(partCount, worldPos) {
			// Remove old dividers
			for (const d of dividers) { group.remove(d); d.geometry.dispose(); }
			dividers.length = 0;

			// Create segment dividers
			for (let i = 1; i < partCount; i++) {
				const x = -BAR_WIDTH / 2 + (i / partCount) * BAR_WIDTH;
				const dGeo = new THREE.PlaneGeometry(0.012, BAR_HEIGHT + 0.005);
				const divider = new THREE.Mesh(dGeo, dividerMat);
				divider.position.set(x, 0, 0.002);
				divider.renderOrder = 1000;
				group.add(divider);
				dividers.push(divider);
			}

			fill.scale.x = 0;
			group.position.copy(worldPos);
			group.position.y += BAR_Y_OFFSET;
			group.visible = true;
		},
		update(pct, camera) {
			fill.scale.x = Math.min(1, pct);

			// Pulse glow opacity
			glow.material.opacity = 0.2 + Math.sin(performance.now() * 0.005) * 0.1;

			// Billboard — face camera
			group.quaternion.copy(camera.quaternion);
		},
		hide() {
			group.visible = false;
			fill.scale.x = 0;
		},
		dispose() {
			for (const d of dividers) { d.geometry.dispose(); }
			trackGeo.dispose(); trackMat.dispose();
			borderGeo.dispose(); borderMat.dispose();
			fillGeo.dispose(); fillMat.dispose();
			glow.geometry.dispose(); glowMat.dispose();
			dividerMat.dispose();
		},
	};
}

// ─── Interaction prompt ─────────────────────────────────────────────────────

function createInteractionPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "interact-prompt";
	Object.assign(el.style, {
		position: "fixed", bottom: "100px", left: "50%", transform: "translateX(-50%)",
		color: "#44ddcc", fontFamily: "'Courier New', monospace", fontSize: "14px",
		textAlign: "center", textShadow: "0 0 8px #44ddcc44",
		pointerEvents: "none", userSelect: "none", display: "none"
	});
	document.body.appendChild(el);
	return el;
}

// ─── CO2 HUD readout ─────────────────────────────────────────────────────────

function createCO2Display(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "co2-display";
	Object.assign(el.style, {
		position: "fixed",
		top: "12px",
		left: "12px",
		color: "#ff6644",
		fontFamily: "'Courier New', monospace",
		fontSize: "13px",
		lineHeight: "1.6",
		background: "rgba(0, 0, 0, 0.65)",
		padding: "6px 12px",
		borderRadius: "3px",
		pointerEvents: "none",
		userSelect: "none",
		zIndex: "998",
		textShadow: "0 0 8px #ff664466",
		whiteSpace: "pre",
	});
	el.textContent = "CO\u2082: 0.8%\n\u26a0 Scrubbers: CRITICAL";
	document.body.appendChild(el);
	return el;
}

// ─── Scene mount ─────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, player, renderer } = context;
	camera.rotation.order = 'YXZ';
	const bus = scopedBus();

	wallMeshes.length = 0;
	const debugObjects: THREE.Object3D[] = [];
	let debugMode = false;

	// ─── Build the gate room (existing prototype) ────────────────────────
	buildRoom(scene);

	// Floor is from the runtime JSON — kept dark. Visibility comes from
	// player light, room lights, and the yellow runway strips.
	const gate = buildStargate(scene);
	const lights = buildLighting(scene, debugObjects);
	gate.pointLights = lights;

	// ─── Player-attached ambient light (Eli's subtle glow) ──────────────
	const playerLight = new THREE.PointLight(0xccddff, 2.5, 15, 1.5);
	playerLight.position.set(0, 2, 0);
	if (player) {
		player.object.add(playerLight);
	}

	// ── Neural Locomotion Controller ──────────────────────────────────────
	// Load Network.bin/manifest and use it to compute root-motion offsets at
	// 10 Hz, lerp-applied each frame for weighted movement feel.
	// TODO: full skeletal integration once VRM bone tracking is available.
	const loco = new NeuralLocomotionController();
	void loco.load(
		"/assets/ai/Network.bin",
		"/assets/ai/Network.manifest.json",
	).catch((err: unknown) => {
		console.warn("[NeuralLoco] weight load failed — root motion disabled:", err);
	});

	// Prediction state: 10 Hz accumulator + cached sequence
	const PREDICTION_HZ = 10;
	const PREDICTION_INTERVAL = 1 / PREDICTION_HZ;
	let locoAccum = 0;
	let lastSeq: SequenceOutput | null = null;
	/** Smoothed XZ root-motion offset applied to player each frame (lerped from network output). */
	const locoOffset = new THREE.Vector3();
	/** Scratch arrays reused each prediction tick to avoid allocation. */
	const _zeroVec69  = new Float32Array(BONE_COUNT * 3);
	const _futurePos  = new Float32Array(SEQ_LENGTH * 2);
	const _futureFwd  = new Float32Array(SEQ_LENGTH * 2);
	const _futureVel  = new Float32Array(SEQ_LENGTH * 2);

	// Register gate room walls for camera pull-in collision
	occludableMeshes.length = 0;
	for (const w of wallMeshes) occludableMeshes.push(w);
	smoothedCamDistance = -1;

	// ─── Corridor/storage point lights (created here for direct reference) ─
	const corrLightZ = ROOM_DEPTH / 2 + CORRIDOR_LENGTH / 2;
	const storLightZ = ROOM_DEPTH / 2 + CORRIDOR_LENGTH + STORAGE_DEPTH / 2;

	const corridorPointLight = new THREE.PointLight(0xddccaa, 0.5, 25, 1.5);
	corridorPointLight.position.set(0, EXT_ROOM_HEIGHT - 0.5, corrLightZ);
	scene.add(corridorPointLight);

	const storagePointLight = new THREE.PointLight(0xddccaa, 0.3, 20, 1.5);
	storagePointLight.position.set(0, EXT_ROOM_HEIGHT - 0.5, storLightZ);
	scene.add(storagePointLight);

	// ─── Build corridor + storage room extending from gate room ──────────
	buildCorridor(scene);
	buildStorageRoom(scene);

	const corridorCZ = CORRIDOR_Z_START + CORRIDOR_LENGTH / 2;
	const storageCZ = CORRIDOR_Z_START + CORRIDOR_LENGTH + STORAGE_DEPTH / 2;

	// ─── Initialize Ship State ───────────────────────────────────────────
	const shipState = new ShipState();
	shipState.init();

	// Register sections
	const sections: Section[] = [
		{
			id: "gate-room", discovered: true, accessible: true,
			atmosphere: 0.8, powerLevel: 0.7, structuralIntegrity: 0.95,
			accessState: "explored", subsystems: []
		},
		{
			id: "corridor-a1", discovered: false, accessible: true,
			atmosphere: 0.6, powerLevel: 0.4, structuralIntegrity: 0.85,
			accessState: "unexplored", subsystems: []
		},
		{
			id: "storage-bay", discovered: false, accessible: true,
			atmosphere: 0.5, powerLevel: 0.2, structuralIntegrity: 0.8,
			accessState: "unexplored", subsystems: []
		},
	];
	for (const sec of sections) shipState.addSection(sec);

	// Register subsystems
	const subsystemDefs: Array<{ sub: Subsystem; pos: THREE.Vector3; wall: "left" | "right" | "back" }> = [
		{
			sub: { id: "corridor-conduit-1", type: "conduit", sectionId: "corridor-a1",
				condition: 0.25, repairCost: 1, functionalThreshold: 0.2 },
			pos: new THREE.Vector3(CORRIDOR_WIDTH_EXT / 2, 1.0, corridorCZ),
			wall: "right"
		},
		{
			sub: { id: "storage-lights", type: "lighting-panel", sectionId: "storage-bay",
				condition: 0.1, repairCost: 1, functionalThreshold: 0.2 },
			pos: new THREE.Vector3(STORAGE_WIDTH / 2, 1.0, storageCZ + 1),
			wall: "right"
		},
		{
			sub: { id: "storage-console", type: "console", sectionId: "storage-bay",
				condition: 0.35, repairCost: 1, functionalThreshold: 0.2 },
			pos: new THREE.Vector3(-STORAGE_WIDTH / 2, 0.8, storageCZ + 2),
			wall: "left"
		},
	];

	const subsystemVisuals: SubsystemVisual[] = [];
	for (const { sub, pos, wall } of subsystemDefs) {
		shipState.addSubsystem(sub);
		subsystemVisuals.push(createSubsystemVisual(scene, sub, pos, wall));
	}

	shipState.distributePower();

	// ─── NPC / Dialogue / Quest / Save Managers ───────────────────────────
	const dialogueManager = createDialogueManager();
	const npcManager = createNpcManager(dialogueManager);
	const questManager = createQuestManager();

	npcManager.registerNpc(drRushNpc);
	dialogueManager.registerTree(drRushDialogue);
	registerDestinyPowerCrisis(questManager);
	registerAirCrisis(questManager);
	questManager.startQuest(AIR_CRISIS_QUEST_ID);

	// ─── Dr. Rush real character model ──────────────────────────────────
	// Loads VRM (with GLB fallback) via the unified character loader.
	const rushPos = drRushNpc.position;
	let rushCharacter: CharacterLoadResult | undefined;

	// Glowing indicator dot above Rush — shown while loading, kept as nav aid
	const rushDotGeo = new THREE.SphereGeometry(0.08, 8, 6);
	const rushDotMat = new THREE.MeshStandardMaterial({
		color: 0x4488ff, emissive: 0x4488ff, emissiveIntensity: 1.2,
	});
	const rushDot = new THREE.Mesh(rushDotGeo, rushDotMat);
	rushDot.position.set(rushPos.x, rushPos.y + 2.0, rushPos.z);
	scene.add(rushDot);

	// ─── Ancient consoles (left side workstation row) ───────────────────────
	// Three stepped consoles at x=-6, running along the −X wall side of the
	// gate room between the gate and the player-spawn end. Rush stands at
	// the middle one; the others add environmental read as "this is where
	// the science team works". Each console is a dark-metallic base with a
	// glowing top panel + angled monitor.
	const consoleRoot = new THREE.Group();
	consoleRoot.name = "rush-consoles";
	const consoleBaseMat = new THREE.MeshStandardMaterial({
		color: 0x1a1a24, roughness: 0.35, metalness: 0.85,
	});
	const consolePanelMat = new THREE.MeshStandardMaterial({
		color: 0x2a4a6a, emissive: 0x4488ff, emissiveIntensity: 0.5,
		roughness: 0.3, metalness: 0.7,
	});
	const consoleScreenMat = new THREE.MeshStandardMaterial({
		color: 0x1a2a3a, emissive: 0x66aaff, emissiveIntensity: 0.9,
		roughness: 0.15, metalness: 0.1,
	});
	for (const cz of [40, 48, 56]) {          // 3 consoles, flanking Rush at z=48
		const base = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.9, 0.8), consoleBaseMat);
		base.position.set(-22, 0.45, cz);
		consoleRoot.add(base);
		const topPanel = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.05, 0.8), consolePanelMat);
		topPanel.position.set(-22, 0.92, cz);
		consoleRoot.add(topPanel);
		const monitor = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.55, 0.04), consoleScreenMat);
		monitor.position.set(-22.3, 1.25, cz);
		monitor.rotation.z = -Math.PI / 2;
		monitor.rotation.x = 0.3;
		consoleRoot.add(monitor);
	}
	scene.add(consoleRoot);

	// Load Dr. Rush's character model; fall back to capsule on error.
	// Path matches /assets/characters/manifest.json. The legacy
	// /assets/characters/dr-rush.vrm at the top level is a byte-identical
	// duplicate of eli-wallace.vrm (placeholder) — do not reference it.
	void loadVRMCharacter("/assets/characters/nicholas-rush/nicholas-rush.vrm")
		.then((char) => {
			rushCharacter = char;
			// Position at the middle console and rotate so he faces +X
			// (toward the center aisle / his workstation monitor).
			char.root.position.set(rushPos.x, rushPos.y, rushPos.z);
			char.root.rotation.y = -Math.PI / 2; // face +X (toward aisle)
			scene.add(char.root);
			console.log("[GateRoom] Dr. Rush character loaded (", char.format, ")");
		})
		.catch((err: unknown) => {
			console.warn("[GateRoom] Dr. Rush VRM load failed:", err);
			// Rush's VRM IS the standard — if it fails, there's no further fallback.
			// The scene still works, Rush just won't be visible.
		});

	// Player VRM loaded via scene definition player.vrmUrl (StarterPlayerController handles it)

	// ── Opening cinematic mode ───────────────────────────────────────────────
	// Declared here; constructed AFTER the HUD is built below so we can
	// collect HUD refs for cinematic hide/show.
	let cinematicController: GateRoomCinematicController | undefined;
	const isCinematicBoot = Boolean(sessionStorage.getItem("sgu-new-game"));
	if (isCinematicBoot) {
		sessionStorage.removeItem("sgu-new-game");
		if (player) player.inputEnabled = false;
		rushDot.visible = false;
		if (rushCharacter) rushCharacter.root.visible = false;
	}

	// Elements the cinematic should hide — populated as they're built
	// below. The cinematic walks this list and sets display:none on each.
	const cinematicHide: HTMLElement[] = [];

	// Opening dialogue — "Eli... Eli, can you hear me?" — plays right after the
	// cinematic. Scott appears in front of the player; player clicks through a
	// short intro that ends by pointing them at Dr. Rush to investigate.
	const triggerOpeningDialogue = async () => {
		// Lazy-load so the dialogue module isn't imported unless we need it
		// (keeps the CONTINUE path free of extra cost).
		const [{ scottOpeningDialogue }, { scottOpeningNpc }] = await Promise.all([
			import("../../dialogues/scott-opening"),
			import("../../npcs/scott-opening"),
		]);
		dialogueManager.registerTree(scottOpeningDialogue);
		npcManager.registerNpc(scottOpeningNpc);

		// Spawn a Scott character standing in front of the camera, slightly
		// off to the right. We derive position from the CAMERA direction (not
		// the player yaw) because the post-cinematic player is prone on their
		// back — the camera's forward vector is what "in front of us" means
		// from the player's POV. A capsule fallback ensures Scott renders
		// even when the placeholder VRM has minimal geometry.
		try {
			const pp = player?.object.position ?? new THREE.Vector3(0, 0, 12);
			const forward = new THREE.Vector3();
			camera.getWorldDirection(forward);
			// Project onto XZ plane so Scott stands upright (no vertical tilt).
			forward.y = 0;
			forward.normalize();
			// Right vector perpendicular to forward, in XZ plane.
			const right = new THREE.Vector3(-forward.z, 0, forward.x);
			const scottPos = new THREE.Vector3()
				.copy(pp)
				.addScaledVector(forward, 2.2)    // 2.2 m in front
				.addScaledVector(right, 0.8);     // 0.8 m to the right
			scottPos.y = 0;  // feet on ground regardless of camera pitch

			// Load Scott's VRM — if his placeholder has no geometry, fall
			// back to the standard VRoid (Rush's model) instead of a capsule.
			let scott: Awaited<ReturnType<typeof loadVRMCharacter>> | undefined;
			try {
				scott = await loadVRMCharacter("/assets/characters/matthew-scott/matthew-scott.vrm");
				const meshes = (() => { let n = 0; scott.root.traverse((o) => { if ((o as THREE.Mesh).isMesh) n++; }); return n; })();
				if (meshes === 0) {
					scott.dispose?.();
					scott = await loadVRMCharacter("/assets/characters/nicholas-rush/nicholas-rush.vrm");
				}
			} catch {
				try {
					scott = await loadVRMCharacter("/assets/characters/nicholas-rush/nicholas-rush.vrm");
				} catch (err2) {
					console.warn("[GateRoom] Scott + fallback VRM both failed:", err2);
				}
			}
			const scottRoot = scott?.root ?? new THREE.Group();
			scottRoot.position.copy(scottPos);
			// Face the player — opposite of the camera's forward.
			scottRoot.lookAt(pp.x, scottRoot.position.y, pp.z);
			scene.add(scottRoot);
			gateRoomExtraDisposables.push(() => {
				scene.remove(scottRoot);
				scott?.dispose?.();
			});
		} catch (err) {
			console.warn("[GateRoom] Scott spawn failed for opening dialogue:", err);
		}

		// Start the dialogue (no prior player-input needed).
		dialogueManager.startDialogue("scott-opening");
	};

	// Disposables for ephemeral resources spawned after the cinematic
	// (like the Scott opening NPC). Flushed from the scene dispose() below.
	const gateRoomExtraDisposables: Array<() => void> = [];

	// When Rush ends a dialogue session that accepted the power quest, start it.
	// startQuest() is idempotent so it's safe to call on every conversation end.
	// Dialogue gate — lock player movement while the dialogue panel is up.
	// The camera is still free to look around but WASD/stick is blocked so
	// the player can't wander off mid-conversation.
	bus.on("crew:dialogue:started", () => {
		if (player) player.inputEnabled = false;
		// Release pointer lock so the player can actually click dialogue
		// options with the mouse. Controller / keyboard shortcuts still
		// work, but the cursor was trapped before this.
		if (document.pointerLockElement) {
			document.exitPointerLock();
		}
	});
	bus.on("crew:dialogue:ended", () => {
		if (player && !cinematicController) player.inputEnabled = true;
		currentDialogueOptionIds.length = 0;
	});

	// Track the currently-visible option IDs so gamepad A/B/X/Y and
	// keyboard 1-4 can advance the dialogue without needing the mouse.
	const currentDialogueOptionIds: string[] = [];
	bus.on("crew:dialogue:node", ({ options }) => {
		currentDialogueOptionIds.length = 0;
		for (const o of options) currentDialogueOptionIds.push(o.id);
	});

	bus.on("crew:dialogue:ended", ({ speakerId }) => {
		if (speakerId === "dr-rush") {
			const saved = dialogueManager.serialize();
			if (saved.acceptedQuests.includes("destiny-power-crisis")) {
				questManager.startQuest("destiny-power-crisis");
			}
		}
	});

	// Advance speak-to-rush when player commits to going through the gate.
	// The dialogue fires crew:choice:made with responseId 'commit-to-gate'
	// on any of the "I'll go" options in the CO2 crisis tree.
	bus.on("crew:choice:made", ({ responseId }) => {
		const commitIds = new Set([
			"commit-to-gate",
			"from-lime-to-commit",
			"from-timeline-commit",
			"from-scanning-commit",
		]);
		if (commitIds.has(responseId)) {
			questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "speak-to-rush");
		}
	});

	// Gate blocker — declared here so the quest:completed handler can close over it.
	// Assigned after HUD setup below; removed when the air crisis quest completes.
	let gateBlocker: CrashcatRigidBody | null = null;

	// Air crisis done → scrubbers fixed → gate is now passable.
	// When a real quest-toast HUD is added, also surface quest:started /
	// quest:objective-complete / save:completed via that system.
	bus.on("quest:completed", ({ questId }) => {
		if (questId === AIR_CRISIS_QUEST_ID && gateBlocker !== null) {
			rigidBody.remove(context.physicsWorld, gateBlocker);
			gateBlocker = null;
		}
	});

	let playtimeMs = 0;

	const saveManager = createSaveManager({
		shipState,
		questManager,
		dialogueManager,
		getContext: () => ({
			currentSceneId: "gate-room",
			playerPosition: player
				? { x: player.object.position.x, y: player.object.position.y, z: player.object.position.z }
				: { x: 0, y: 0, z: 0 },
			playtime: playtimeMs,
			unlockedScenes: ["gate-room"],
		}),
		gotoScene: context.gotoScene,
	});

	setSceneManagers({ dialogue: dialogueManager, npc: npcManager, quest: questManager, save: saveManager });

	// ─── Resources + Supply Crates ───────────────────────────────────────
	initResources();

	const crates: SupplyCrate[] = [
		createSupplyCrate(scene, new THREE.Vector3(-2, 0, storageCZ - 1.5), 8),
		createSupplyCrate(scene, new THREE.Vector3(-1, 0, storageCZ + 2.5), 6),
		createSupplyCrate(scene, new THREE.Vector3(2.5, 0, storageCZ + 1), 8),
	];

	// ─── Room lighting (Ship State driven) ───────────────────────────────
	const roomLights: RoomLighting[] = [
		createRoomLighting(scene, "corridor-a1", 0, corridorCZ, CORRIDOR_WIDTH_EXT, CORRIDOR_LENGTH, EXT_ROOM_HEIGHT),
		createRoomLighting(scene, "storage-bay", 0, storageCZ, STORAGE_WIDTH, STORAGE_DEPTH, EXT_ROOM_HEIGHT),
	];

	// ─── UI elements ─────────────────────────────────────────────────────
	const hud = createHUD();
	cinematicHide.push(hud);
	const compassHud = createHud(renderer.domElement.parentElement ?? document.body);
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const compass = createHorizontalCompass() as any;
	compassHud.mount(compass);
	// compassHud has no public DOM ref — it's its own managed HTMLDivElement
	// returned from createHud(). Cast to probe for common element shapes.
	const compassAny = compassHud as unknown as { element?: HTMLElement; container?: HTMLElement };
	const compassRoot = compassAny.element ?? compassAny.container;
	if (compassRoot) cinematicHide.push(compassRoot);

	// ── Gate blocker ───────────────────────────────────────────────────────────
	// Invisible static box covering the Stargate opening. Physically prevents the
	// player walking through before the air crisis is resolved. The blocker is
	// removed in the quest:completed handler above when AIR_CRISIS_QUEST_ID fires.
	// halfExtents slightly larger than GATE_RADIUS so a box covers the circular gap.
	gateBlocker = rigidBody.create(context.physicsWorld, {
		motionType: MotionType.STATIC,
		objectLayer: CRASHCAT_OBJECT_LAYER_STATIC,
		shape: box.create({
			// Vec3 in mathcat is a labeled tuple [x, y, z], not { x, y, z }
			halfExtents: [GATE_RADIUS + 0.3, GATE_RADIUS + 0.3, 0.2],
		}),
		position: [GATE_CENTER.x, GATE_CENTER.y, GATE_CENTER.z],
	});

	// Dev / test support: ?lime=1 URL param pre-sets the lime carry state so that
	// tests can load gate-room with the banner visible without going through the
	// full desert-planet flow. Safe in production — the param is simply ignored.
	if (new URLSearchParams(window.location.search).has('lime')) {
		setLimeCollected(true);
	}

	// Lime delivery banner — shown when player returns from the desert planet
	// with calcium deposits and needs to reach the CO₂ scrubber room.
	let limeBanner: HTMLDivElement | null = null;
	if (isLimeCollected()) {
		limeBanner = document.createElement("div");
		limeBanner.id = "lime-delivery-banner";
		Object.assign(limeBanner.style, {
			position: "fixed", top: "50px", left: "50%",
			transform: "translateX(-50%)", color: "#ffee88",
			fontFamily: "'Courier New', monospace", fontSize: "13px",
			background: "rgba(0,0,0,0.8)", padding: "6px 16px",
			borderRadius: "3px", border: "1px solid #ffee8866",
			pointerEvents: "none", userSelect: "none", zIndex: "998",
			textShadow: "0 0 6px #ffee8844",
		});
		limeBanner.textContent =
			"\u25ba Take the lime to the CO\u2082 scrubber room \u2014 Deck 3, Section 7";
		document.body.appendChild(limeBanner);
	}

	// Wire the dialogue panel — adapter bridges SGU's typed bus to the engine's
	// generic DialoguePanelEventBus interface via safe any-casts at the boundary.
	const dialogueBus: DialoguePanelEventBus = {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		on:   (event, handler) => bus.on(event as any, handler as any),
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		emit: (event, data?)  => emit(event as any, data as any),
	};
	// Pick hint labels that match the player's actual input device: controller
	// buttons (A/B/X/Y) when a gamepad is connected, number keys (1/2/3/4)
	// otherwise. Detected once at mount — a later plug-in is uncommon and the
	// dialogue still accepts both inputs regardless of the hint shown.
	const hasGamepadConnected = typeof navigator.getGamepads === "function"
		&& Array.from(navigator.getGamepads() ?? []).some((gp) => gp && gp.connected);
	const dialoguePanel = createDialoguePanel(dialogueBus, {
		style: 'sci-fi',
		// Gamepad: A/B/X/Y; keyboard: digit keys 1-4. Both input paths are
		// always live — the hint just indicates the primary binding for the
		// current device. Extra options render without a chip.
		optionHints: hasGamepadConnected ? ['A', 'B', 'X', 'Y'] : ['1', '2', '3', '4'],
	});
	compassHud.mount(dialoguePanel);
	const debug = createDebugOverlay();
	debug.element.style.display = "none";
	const menu = createEscapeMenu(renderer.domElement);
	const cleanupFullscreen = setupFullscreen(renderer.domElement, menu);
	const interactPrompt = createInteractionPrompt();
	cinematicHide.push(interactPrompt);
	// CO₂ scrubber status belongs to Episode 2 ("Air") — it shouldn't appear
	// at all during Episode 1. Kept offline until a scrubber-crisis event
	// reveals it (see episode-scripting todo). Construction is deferred so
	// the DOM element doesn't even exist on first boot.
	let co2Display: HTMLDivElement | undefined; // created when Ep-2 scrubber crisis begins
	const repairBar = createRepairProgressBar3D();
	scene.add(repairBar.group);

	renderer.shadowMap.enabled = false;

	// ─── Debug + Ship State overlay ──────────────────────────────────────
	const shipDebugEl = document.createElement("div");
	shipDebugEl.id = "ship-debug";
	Object.assign(shipDebugEl.style, {
		position: "fixed", top: "8px", right: "8px",
		color: "#44ddcc", fontFamily: "'Courier New', monospace", fontSize: "11px",
		lineHeight: "1.5", background: "rgba(0,0,0,0.7)", padding: "8px 12px",
		borderRadius: "4px", pointerEvents: "none", userSelect: "none",
		zIndex: "999", minWidth: "200px", whiteSpace: "pre", display: "none"
	});
	document.body.appendChild(shipDebugEl);

	const toggleDebug = () => {
		debugMode = !debugMode;
		debug.element.style.display = debugMode ? "block" : "none";
		shipDebugEl.style.display = debugMode ? "block" : "none";
		for (const obj of debugObjects) obj.visible = debugMode;
	};

	let lastBackquoteTime = 0;
	let currentSection = "gate-room";

	// ─── Interaction state ───────────────────────────────────────────────
	const SECONDS_PER_REPAIR_PART = 1.0;
	let nearestSub: SubsystemVisual | null = null;
	let nearestCrate: SupplyCrate | null = null;
	let nearestNpc: NpcInstance | null = null;
	let nearGate = false;
	let nearScrubberEntrance = false;
	// Scrubber entrance trigger — front-left corridor mouth (visible when carrying lime)
	const SCRUBBER_ENTRANCE_POS = new THREE.Vector3(0, 0, ROOM_DEPTH / 2 - 3);
	const SCRUBBER_ENTRANCE_RADIUS = 3.0;
	type InteractTarget = "subsystem" | "crate" | "npc" | "gate" | "scrubber-entrance" | null;
	let interactTarget: InteractTarget = null;
	let repairingSubsystemId: string | null = null;
	/** Total segments needed to fully repair this subsystem. */
	let repairTotalSegments = 0;
	/** Segments already completed in this hold. */
	let repairCompletedSegments = 0;
	/** Time elapsed within the current segment (resets each segment). */
	let repairSegmentElapsed = 0;

	const cancelRepair = () => {
		if (repairingSubsystemId) {
			repairingSubsystemId = null;
			repairTotalSegments = 0;
			repairCompletedSegments = 0;
			repairSegmentElapsed = 0;
			player?.setRepairing(false);
			repairBar.hide();
		}
	};

	/** Previous-frame player position used to derive velocity for loco input. */
	const _prevPlayerPos = new THREE.Vector3();
	if (player) _prevPlayerPos.copy(player.object.position);

	// All input is polled from the shared InputManager in update() below.
	// No ad-hoc window listeners — keyboard + gamepad go through the same
	// action system (Action.Interact, SguAction.DialGate, etc.).
	const input = getInput();

	/** Handle the "interact" trigger — keyboard E and gamepad A both fire this. */
	const tryInteract = (): void => {
		if (menu.visible) return;
		if (interactTarget === "gate" && gate.state === "active") {
			questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "gate-to-planet");
			void context.gotoScene("desert-planet");
		} else if (interactTarget === "crate" && nearestCrate && !nearestCrate.looted) {
			addResource("ship-parts", nearestCrate.contents);
			markCrateLooted(nearestCrate);
		} else if (interactTarget === "subsystem" && nearestSub && !repairingSubsystemId) {
			const sub = shipState.getSubsystem(nearestSub.id);
			if (sub && sub.condition < 1.0 && hasResource("ship-parts", sub.repairCost)) {
				const repairPerSegment = SHIP_STATE_CONFIG.BASE_REPAIR_AMOUNT * SHIP_STATE_CONFIG.REPAIR_SKILL_MODIFIER;
				const remaining = 1.0 - sub.condition;
				const segs = Math.ceil(remaining / repairPerSegment);
				repairingSubsystemId = sub.id;
				repairTotalSegments = segs;
				repairCompletedSegments = 0;
				repairSegmentElapsed = 0;
				player?.setRepairing(true);
				repairBar.init(segs, nearestSub.mesh.position);
			}
		} else if (interactTarget === "npc" && nearestNpc && !nearestNpc.inDialogue) {
			emit("player:interact", { targetId: nearestNpc.definition.id, action: "talk" });
		} else if (interactTarget === "scrubber-entrance") {
			void context.gotoScene("scrubber-room");
		}
	};

	// ─── Opening cinematic kick-off ──────────────────────────────────────
	// Constructed here (not earlier) so we have HUD refs to hide for the
	// cinematic duration.
	if (isCinematicBoot) {
		// Hide every registered HUD element for the cinematic's lifetime.
		for (const el of cinematicHide) el.style.display = "none";

		cinematicController = new GateRoomCinematicController(
			scene,
			camera as import("three").PerspectiveCamera,
			(i) => {
				// Gate runtime callback — cinematic asks us to light
				// up chevrons 1..9 during its dial beat. We drive the
				// actual in-scene gate state so the chevrons glow for
				// real instead of the cinematic faking it.
				if (gate) {
					gate.lockedChevrons = Math.min(9, i);
					for (let k = 0; k < gate.chevronMeshes.length; k++) {
						const mat = gate.chevronMeshes[k].material as THREE.MeshStandardMaterial;
						const lit = k < gate.lockedChevrons;
						mat.color.setHex(lit ? COLOR_CHEVRON_ON : COLOR_CHEVRON_OFF);
						mat.emissive.setHex(lit ? COLOR_CHEVRON_ON : COLOR_CHEVRON_OFF);
						mat.emissiveIntensity = lit ? 1.5 : 0.1;
					}
				}
			},
			() => {
				// Cinematic complete — restore HUD, gameplay NPCs, input.
				for (const el of cinematicHide) el.style.display = "";
				if (player) {
					player.inputEnabled = true;
					player.setProne(true);
				}
				if (rushCharacter) rushCharacter.root.visible = true;
				rushDot.visible = true;
				cinematicController = undefined;
				void triggerOpeningDialogue();
			},
			player?.object ?? undefined,
		);

		// If Rush loads AFTER the cinematic starts, keep him hidden.
		const rushHidePoll = setInterval(() => {
			if (rushCharacter && cinematicController) {
				rushCharacter.root.visible = false;
				clearInterval(rushHidePoll);
			} else if (!cinematicController) {
				clearInterval(rushHidePoll);
			}
		}, 100);
	}

	// ─── Test hooks ──────────────────────────────────────────────────────
	// Signal to Playwright that this scene's 3-D setup is complete and
	// DOM/event handlers are live.  Bus exposed so tests can inject events.
	(window as any).__sceneReady = true;
	(window as any).__sguBus = bus;
	// Expose scene + cinematic for browser-based test introspection (checking
	// crew positions, HUD state, etc). Safe to expose — production build has
	// no way to trigger __sceneReady hooks from user input.
	(window as any).__sguScene = scene;
	(window as any).__sguGetCinematic = () => cinematicController;

	let debugFrame = 0;

	return {
		update(delta: number) {
			playtimeMs += delta * 1000;

			// ─── Input (unified: keyboard + gamepad via InputManager) ───────
			// InputManager is polled once per frame in app.ts. We only read
			// state here — both keyboard and gamepad go through the same
			// action bindings defined in src/systems/input.ts.
			if (input.gamepad.isConnected && player) {
				// Left stick → movement. Engine dead-zones and clamps already.
				const move = input.gamepad.getMovement();
				player.setExternalMoveInput(-move.z, move.x);
				// Right stick → camera orbit
				const look = input.gamepad.getLook();
				if (look.x !== 0 || look.y !== 0) {
					player.applyOrbitDelta(look.x * delta * 2.2, look.y * delta * 1.8);
				}
				// Sprint when gamepad Sprint action is held (B/Circle by default)
				player.setSprintOverride(input.isAction(Action.Sprint));
			} else if (player) {
				player.setExternalMoveInput(0, 0);
				player.setSprintOverride(false);
			}

			// Dialogue shortcuts — gamepad A/B/X/Y and keyboard 1-4 pick
			// the 1st/2nd/3rd/4th visible option while the dialogue panel
			// is open. Consume the edge so Action.Jump/MenuConfirm on A
			// don't also fire during dialogue.
			if (currentDialogueOptionIds.length > 0) {
				const pick = input.isActionJustPressed(SguAction.Dialogue0) ? 0
					: input.isActionJustPressed(SguAction.Dialogue1) ? 1
					: input.isActionJustPressed(SguAction.Dialogue2) ? 2
					: input.isActionJustPressed(SguAction.Dialogue3) ? 3
					: -1;
				if (pick >= 0 && pick < currentDialogueOptionIds.length) {
					emit("player:dialogue:choice", { responseId: currentDialogueOptionIds[pick] });
				}
			}

			// Interact (KeyE / Gamepad A) — single fire on leading edge.
			// Skipped while a dialogue is open so A doesn't double-fire.
			if (input.isActionJustPressed(Action.Interact) && currentDialogueOptionIds.length === 0) {
				tryInteract();
			}
			if (input.isActionJustReleased(Action.Interact)) {
				cancelRepair();
			}

			// Manual gate dial was a debug prototype shortcut — gate state is
			// now driven entirely by the cinematic + quest scripts. KeyG /
			// Gamepad Y no longer triggers a dial here.

			// Debug overlay toggle (double-tap Backquote).
			if (input.isActionJustPressed(SguAction.DebugToggle)) {
				const now = performance.now();
				if (now - lastBackquoteTime < 400) { toggleDebug(); lastBackquoteTime = 0; }
				else lastBackquoteTime = now;
			}

			// ─── Neural locomotion (10 Hz predict, 60 fps lerp) ──────────────
			if (player && loco.isLoaded) {
				locoAccum += delta;
				if (locoAccum >= PREDICTION_INTERVAL) {
					locoAccum -= PREDICTION_INTERVAL;

					// Build trajectory from current velocity/facing — bone arrays are zero
					// (no skeletal mesh yet; root motion still emerges from trajectory input).
					// TODO: populate bone arrays from VRM skeleton when available.
					const vel = player.object.position.clone()
						.sub(_prevPlayerPos)
						.divideScalar(delta);
					const vx = vel.x, vz = vel.z;
					const spd = Math.sqrt(vx * vx + vz * vz);
					// Facing from camera yaw (camera looks -Z at yaw=0)
					const fwdX = -Math.sin(camera.rotation.y);
					const fwdZ = -Math.cos(camera.rotation.y);

					for (let i = 0; i < SEQ_LENGTH; i++) {
						const t = (i / (SEQ_LENGTH - 1)) * SEQ_WINDOW;
						_futurePos[i * 2]     = vx * t;
						_futurePos[i * 2 + 1] = vz * t;
						_futureFwd[i * 2]     = fwdX;
						_futureFwd[i * 2 + 1] = fwdZ;
						_futureVel[i * 2]     = vx;
						_futureVel[i * 2 + 1] = vz;
					}

					try {
						const encoded = encodeInput({
							bonePositions:         _zeroVec69,
							boneForwardAxes:       _zeroVec69,
							boneUpAxes:            _zeroVec69,
							boneVelocities:        _zeroVec69,
							futureRootPositionsXZ: _futurePos,
							futureRootForwardsXZ:  _futureFwd,
							futureRootVelocitiesXZ: _futureVel,
							guidancePositions:     _zeroVec69,
						});
						lastSeq = loco.predict(encoded);
					} catch {
						// prediction errors are non-fatal — skip this tick
					}
				}

				// Lerp-apply root motion at 60 fps: sample the cached sequence at
				// the interpolated phase and blend into player position.
				if (lastSeq) {
					const phase = Math.min(locoAccum / PREDICTION_INTERVAL, 1.0);
					const pose = loco.sampleAt(lastSeq, phase * SEQ_WINDOW);
					const [dx, , dz] = pose.rootDelta;  // skip Y-rotation (no skeleton yet)
					// Scale down: the raw delta is for 1/60 s of a biped; treat it as
					// a nudge weight rather than full displacement.
					const LOCO_SCALE = 0.06;
					locoOffset.set(dx * LOCO_SCALE, 0, dz * LOCO_SCALE);
					// Smooth lerp toward target offset so it doesn't stutter
					const LERP_K = 1 - Math.exp(-delta * 12);
					player.object.position.addScaledVector(locoOffset, LERP_K);
				}

				_prevPlayerPos.copy(player.object.position);
			}

			npcManager.update(delta);
			// ─── VRM/GLB character physics + animation ──────────────────────
			if (rushCharacter) rushCharacter.update(delta);
						updateGate(gate, delta);
			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			if (cinematicController) cinematicController.update(delta);
			compassHud.update(camera as any, delta);

			// ─── Ship State driven lighting ──────────────────────────────
			// Recalculate power distribution so section power reflects repairs
			shipState.distributePower();

			for (const rl of roomLights) {
				const sec = shipState.getSection(rl.sectionId);
				if (sec) updateRoomLighting(rl, sec);
			}

			// Drive corridor/storage overhead point light intensity from section power
			const corridorSec = shipState.getSection("corridor-a1");
			if (corridorSec) {
				const target = corridorSec.powerLevel * 4.0;
				corridorPointLight.intensity += (target - corridorPointLight.intensity) * 0.1;
			}
			const storageSec = shipState.getSection("storage-bay");
			if (storageSec) {
				const target = storageSec.powerLevel * 4.0;
				storagePointLight.intensity += (target - storagePointLight.intensity) * 0.1;
			}

			// ─── Subsystem visuals ───────────────────────────────────────
			for (const sv of subsystemVisuals) {
				const sub = shipState.getSubsystem(sv.id);
				if (sub) updateSubsystemVisual(sv, sub);
			}

			// ─── Camera pull-in + Player section tracking ───────────────
			if (player) {
				updateCameraPullIn(camera, player.object.position, delta);
				const pz = player.object.position.z;
				let newSection = "gate-room";
				if (pz > CORRIDOR_Z_START + CORRIDOR_LENGTH) newSection = "storage-bay";
				else if (pz > CORRIDOR_Z_START) newSection = "corridor-a1";

				if (newSection !== currentSection) {
					currentSection = newSection;
					emit("player:entered:section", { sectionId: newSection });
				}

				// Find nearest interactable (crates, subsystems, or NPCs)
				nearestSub = null;
				nearestCrate = null;
				nearestNpc = null;
				interactTarget = null;
				let nearestDist = 2.5;
				const pp = player.object.position;

				// Check crates first (higher priority)
				for (const crate of crates) {
					if (crate.looted) continue;
					const dist = crate.position.distanceTo(pp);
					if (dist < nearestDist) {
						nearestCrate = crate;
						nearestDist = dist;
						interactTarget = "crate";
					}
				}

				// Check subsystems
				for (const sv of subsystemVisuals) {
					const dist = sv.mesh.position.distanceTo(pp);
					if (dist < nearestDist) {
						nearestSub = sv;
						nearestCrate = null;
						nearestDist = dist;
						interactTarget = "subsystem";
					}
				}

				// Check NPCs
				for (const npc of npcManager.getAllNpcs()) {
					const { position, behavior } = npc.definition;
					const npcVec = new THREE.Vector3(position.x, position.y, position.z);
					const dist = npcVec.distanceTo(pp);
					if (dist < behavior.interactionRadius && dist < nearestDist) {
						nearestNpc = npc;
						nearestSub = null;
						nearestCrate = null;
						nearestDist = dist;
						interactTarget = "npc";
					}
				}

				// Check gate entrance — only when wormhole is active
				nearGate = false;
				const gateXZDist = Math.sqrt(
					(pp.x - GATE_CENTER.x) ** 2 + (pp.z - GATE_CENTER.z) ** 2
				);
				if (gate.state === "active" && gateXZDist < 2.0) {
					nearGate = true;
					if (gateXZDist < nearestDist) {
						nearestSub = null;
						nearestCrate = null;
						nearestNpc = null;
						nearestDist = gateXZDist;
						interactTarget = "gate";
					}
				}

				// Scrubber entrance — only visible when player is carrying lime
				nearScrubberEntrance = false;
				if (isLimeCollected()) {
					const entranceDist = pp.distanceTo(SCRUBBER_ENTRANCE_POS);
					if (entranceDist < SCRUBBER_ENTRANCE_RADIUS && entranceDist < nearestDist) {
						nearScrubberEntrance = true;
						nearestSub = null;
						nearestCrate = null;
						nearestNpc = null;
						nearestDist = entranceDist;
						interactTarget = "scrubber-entrance";
					}
				}

				// Cancel repair if player moved away from target
				if (repairingSubsystemId && !nearestSub) {
					cancelRepair();
				}

				// Tick repair progress — each segment = 1 second + 1 repairSubsystem call
				if (repairingSubsystemId) {
					repairSegmentElapsed += delta;

					// Check if current segment completed
					if (repairSegmentElapsed >= SECONDS_PER_REPAIR_PART) {
						repairSegmentElapsed -= SECONDS_PER_REPAIR_PART;
						repairCompletedSegments++;

						const sub = shipState.getSubsystem(repairingSubsystemId);
						if (sub) {
							consumeResource("ship-parts", sub.repairCost);
							shipState.repairSubsystem(sub.id);
							shipState.distributePower();
							console.log(`Repaired ${sub.id} segment ${repairCompletedSegments}/${repairTotalSegments}: ${(sub.condition * 100).toFixed(0)}%`);

							// Check if fully repaired or out of parts
							if (sub.condition >= 1.0 || repairCompletedSegments >= repairTotalSegments || !hasResource("ship-parts", sub.repairCost)) {
								cancelRepair();
							}
						} else {
							cancelRepair();
						}
					}

					// Update 3D progress bar (smooth fill within segment)
					if (repairingSubsystemId) {
						const segmentPct = repairSegmentElapsed / SECONDS_PER_REPAIR_PART;
						const totalPct = (repairCompletedSegments + segmentPct) / repairTotalSegments;
						repairBar.update(totalPct, camera);
					}
				}

				// Update prompt
				const parts = getResource("ship-parts");
				if (repairingSubsystemId) {
					interactPrompt.style.display = "none";
				} else if (interactTarget === "crate" && nearestCrate) {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = `[E] Open crate (+${nearestCrate.contents} Ship Parts)`;
				} else if (interactTarget === "subsystem" && nearestSub) {
					const sub = shipState.getSubsystem(nearestSub.id);
					if (sub && sub.condition < 1.0) {
						interactPrompt.style.display = "block";
						if (parts >= sub.repairCost) {
							interactPrompt.textContent = `[Hold E] Repair ${sub.type} (${(sub.condition * 100).toFixed(0)}%) \u2014 ${sub.repairCost} parts`;
						} else {
							interactPrompt.textContent = `Repair ${sub.type} \u2014 Need ${sub.repairCost} Ship Parts (have ${parts})`;
						}
					} else if (sub) {
						interactPrompt.style.display = "block";
						interactPrompt.textContent = `${sub.type} \u2014 Optimal`;
					}
				} else if (interactTarget === "npc" && nearestNpc) {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = `[E] Talk to ${nearestNpc.definition.name}`;
				} else if (interactTarget === "gate") {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = "[E] Step through the Stargate";
				} else if (interactTarget === "scrubber-entrance") {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = "[E] Take the lime to the CO\u2082 scrubber room \u2014 Deck 3, Section 7";
				} else {
					interactPrompt.style.display = "none";
				}
			}

			// ─── Debug overlays ──────────────────────────────────────────
			if (debugMode) {
				debug.update();
				debugFrame++;
				if (debugFrame % 15 === 0) {
					const lines: string[] = ["=== SHIP STATE ==="];
					for (const sys of shipState.getAllSystems()) {
						const bar = "\u2588".repeat(Math.round(sys.condition * 10)) + "\u2591".repeat(10 - Math.round(sys.condition * 10));
						lines.push(`${sys.powered ? "\u26A1" : "  "} ${sys.id.padEnd(16)} ${bar} ${(sys.condition * 100).toFixed(0)}%`);
					}
					lines.push("", `=== SECTIONS === (current: ${currentSection})`);
					for (const sec of shipState.getAllSections()) {
						const marker = sec.id === currentSection ? ">" : " ";
						lines.push(`${marker} ${sec.id.padEnd(14)} P:${(sec.powerLevel * 100).toFixed(0)}% A:${(sec.atmosphere * 100).toFixed(0)}% [${sec.accessState}]`);
					}
					lines.push("", "=== SUBSYSTEMS ===");
					for (const sec of shipState.getAllSections()) {
						for (const sub of shipState.getSubsystemsInSection(sec.id)) {
							lines.push(`  ${sub.id.padEnd(20)} ${sub.type.padEnd(14)} ${(sub.condition * 100).toFixed(0)}%`);
						}
					}
					lines.push("", "=== RESOURCES ===");
					const res = getAllResources();
					for (const [key, val] of Object.entries(res)) {
						lines.push(`  ${key.padEnd(14)} ${val}`);
					}
					shipDebugEl.textContent = lines.join("\n");
				}
			}
		},
		dispose() {
			limeBanner?.remove();
			cancelRepair();
			repairBar.dispose();
			cleanupFullscreen();
			hud.remove();
			compassHud.unmount(dialoguePanel);
			dialoguePanel.dispose();
			compassHud.dispose();
			debug.element.remove();
			shipDebugEl.remove();
			interactPrompt.remove();
			co2Display?.remove();
			menu.dispose();
			// Rush and player character cleanup
			rushCharacter?.dispose();
						scene.remove(rushDot);
			rushDotGeo.dispose();
			rushDotMat.dispose();

			for (const cleanup of gateRoomExtraDisposables) cleanup();
			gateRoomExtraDisposables.length = 0;
			dialogueManager.dispose();
			npcManager.dispose();
			questManager.dispose();
			saveManager.dispose();
			if (cinematicController) {
				cinematicController.dispose();
				cinematicController = undefined;
				// Restore player input if scene is torn down mid-cinematic
				if (player) player.inputEnabled = true;
			}
		setSceneManagers(null);
			shipState.dispose();
			bus.cleanup();
			wallMeshes.length = 0;
			// BUG-003: dispose all GPU geometry + material objects created during mount()
			// to prevent VRAM accumulation across gate-room → desert-planet round trips.
			// The traversal covers everything added via buildRoom, buildStargate,
			// buildLighting, buildCorridor, buildStorageRoom, and inline mount() code.
			scene.traverse((obj) => {
				if (obj instanceof THREE.Mesh) {
					obj.geometry.dispose();
					if (Array.isArray(obj.material)) {
						obj.material.forEach((m) => m.dispose());
					} else {
						(obj.material as THREE.Material).dispose();
					}
				}
			});
			// Also dispose the module-level shared materials (created once at import time,
			// never otherwise freed — ARCH-003 debt). They are cheap to recreate on remount.
			extWallMat.dispose();
			extCeilingMat.dispose();
		}
	};
}

// ─── Scene definition ────────────────────────────────────────────────────────

export const gateRoomScene = defineGameScene({
	id: "gate-room",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((module) => module.default)
	}),
	title: "Gate Room",
	player: { vrmUrl: "https://pub-c642ba55d4f641de916d72786545c520.r2.dev/characters/eli.vrm" },
	mount
});
