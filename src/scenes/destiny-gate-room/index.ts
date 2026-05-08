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
import { formatInteractPrompt } from "../../ui/interact-prompt-text";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url"
}) as Record<string, () => Promise<string>>;

// ─── Constants ───────────────────────────────────────────────────────────────

// Gate room scaled to match the show's Destiny gate room — a massive
// cavernous Ancient chamber. Gate and characters are NOT scaled — only
// the architectural envelope grows. The room needs to be large enough
// for crew to be thrown 15-20m from the gate during the arrival cinematic.
// Cathedral-scale gate room — concept art shows an enormous Ancient hall
// where the player is dwarfed by the architecture. Width/height bumped to
// emphasize verticality; depth kept reasonable so the back wall still
// frames the gate instead of disappearing into the distance.
const ROOM_WIDTH = 140;
const ROOM_DEPTH = 180;
const ROOM_HEIGHT = 52;
// Gate scaled up to fill the frame like the reference — the SGU gate is
// a massive structure. GATE_RADIUS=6 gives a 12-meter diameter ring.
// Edge comparison showed the reference gate fills ~60% of the frame width
// while R=4 only filled ~5% from the gameplay camera at z=32.
const GATE_RADIUS = 6.0;
// Flat ring cross-section — the SGU gate is a wide, shallow ring, not a donut.
// WIDTH is the radial thickness (inner→outer edge); DEPTH is the thin Z extent.
const GATE_RING_WIDTH = 0.8;
const GATE_RING_DEPTH = 0.175;
// Sink the gate so the PORTAL bottom (event horizon) sits 0.2m below the
// floor — characters walk through without any ledge or step. The outer
// ring naturally dips further below floor (hidden under the platform),
// which is exactly the canonical SGU look: a ring set into a raised dais.
// Inner portal radius = GATE_RADIUS - GATE_RING_WIDTH/2 - 0.05
//                     = 6.0 - 0.4 - 0.05 = 5.55
// Portal bottom y = GATE_CENTER.y - 5.55 = -0.2  →  GATE_CENTER.y = 5.35
const GATE_PORTAL_SINK = 0.2;
const GATE_PORTAL_INNER_RADIUS = GATE_RADIUS - GATE_RING_WIDTH / 2 - 0.05;
const GATE_CENTER = new THREE.Vector3(0, GATE_PORTAL_INNER_RADIUS - GATE_PORTAL_SINK, 0);
const CHEVRON_COUNT = 9;

// SGU color palette — blue-grey Ancient metal, matching the reference
const COLOR_ANCIENT_METAL = 0x1e2030;  // dark blue-grey hull metal
const COLOR_ANCIENT_GLOW = 0x4488ff;   // blue accent glow
const COLOR_CHEVRON_OFF = 0x223355;  // visible dim blue even when unlit
const COLOR_CHEVRON_ON = 0x44aaff;
const COLOR_EVENT_HORIZON = 0x4499dd;
// Wall and ceiling — dark blue-grey to match the SGU reference. The room
// should feel like a dimly-lit Ancient military chamber, not a bright hall.
const COLOR_WALL = 0x1a1a2e;
const COLOR_CEILING = 0x141425;

// Wall transparency — track wall meshes for camera occlusion
const wallMeshes: THREE.Mesh[] = [];

function setHorizonOpacity(eventHorizon: THREE.Mesh, value: number): void {
	(eventHorizon.material as THREE.MeshBasicMaterial).opacity = value;
}
function getHorizonOpacity(eventHorizon: THREE.Mesh): number {
	return (eventHorizon.material as THREE.MeshBasicMaterial).opacity;
}

// ─── Gate activation state ───────────────────────────────────────────────────

type GateState = "idle" | "dialing" | "kawoosh" | "active" | "shutdown";

type GateRuntime = {
	chevronMeshes: THREE.Mesh[];
	dialElapsed: number;
	eventHorizon: THREE.Mesh;
	halo: THREE.Mesh;
	innerRing: THREE.Mesh;
	kawooshElapsed: number;
	lockedChevrons: number;
	outerRing: THREE.Mesh;
	pointLights: THREE.PointLight[];
	state: GateState;
};

// ─── Gate control interface (for cinematic to drive the real gate) ───────────

export interface GateControl {
	startDial(): void;
	shutdownGate(): void;
	forceLockedChevrons(count: number): void;
	forceState(state: GateState): void;
	getState(): GateState;
	readonly eventHorizon: THREE.Mesh;
}

function createGateControl(gate: GateRuntime): GateControl {
	return {
		startDial: () => startDial(gate),
		shutdownGate: () => {
			// Allow shutdown from active OR kawoosh (cinematic may force shutdown early)
			if (gate.state === "active" || gate.state === "kawoosh") {
				gate.state = "shutdown";
				gate.kawooshElapsed = 0;
			}
		},
		forceLockedChevrons: (count: number) => {
			while (gate.lockedChevrons < count) {
				lockChevron(gate, gate.lockedChevrons);
				gate.lockedChevrons++;
			}
		},
		forceState: (state: GateState) => {
			gate.state = state;
			gate.dialElapsed = 0;
			gate.kawooshElapsed = 0;
			if (state === "kawoosh") {
				gate.eventHorizon.visible = true;
				setHorizonOpacity(gate.eventHorizon, 0);
				gate.halo.visible = true;
				(gate.halo.material as THREE.MeshBasicMaterial).opacity = 0;
			}
		},
		getState: () => gate.state,
		get eventHorizon() { return gate.eventHorizon; },
	};
}

// ─── Room construction ───────────────────────────────────────────────────────

function createWallMaterial(): THREE.MeshStandardMaterial {
	// Brighter emissive *color* (cool indigo) at modest intensity rather than
	// near-black emissive at high intensity — multiplying near-zero by intensity
	// is still near-zero. Concept gate-room-dormant shows clear cool-blue cast
	// across the walls, not pure black void. Memory: feedback_dark_surfaces_at_high_exposure.
	return new THREE.MeshStandardMaterial({
		color: 0x100e0a,
		emissive: 0x1a2244,
		emissiveIntensity: 0.5,
		roughness: 0.75,
		metalness: 0.5,
		side: THREE.DoubleSide,
	});
}

function buildRoom(scene: THREE.Scene): void {
	const ceilingMat = new THREE.MeshStandardMaterial({
		color: 0x100e0a,
		emissive: 0x040302,
		emissiveIntensity: 0.2,
		roughness: 0.8,
		metalness: 0.3,
		side: THREE.DoubleSide,
	});

	// Back wall (behind gate) — darker than side walls so the gate ring
	// silhouette stands out. The reference shows the back wall as near-black.
	const backWallMat = new THREE.MeshStandardMaterial({
		color: 0x080604,
		emissive: 0x020101,
		emissiveIntensity: 0.1,
		roughness: 0.8,
		metalness: 0.4,
		side: THREE.DoubleSide,
	});
	const backWall = new THREE.Mesh(
		new THREE.BoxGeometry(ROOM_WIDTH, ROOM_HEIGHT, 0.5),
		backWallMat,
	);
	backWall.position.set(0, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2);
	scene.add(backWall);
	wallMeshes.push(backWall);

	// Front wall — split into two pieces with cathedral-scale doorway gap.
	// Concept-art `gate-room-dormant.png` shows the room framed by a giant
	// arched portal that fills the near plane; player POV looks through.
	// Doorway widened from 4m → 16m and heightened from 3.5m → 26m so a
	// camera positioned outside the front wall (z > ROOM_DEPTH/2) at
	// head-height (y ≈ 16) actually frames the gate through the opening.
	const doorwayWidth = 16;
	const doorwayHeight = 26;
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
	// Door frame top piece — wall above the cathedral arch opening.
	const doorTopHeight = ROOM_HEIGHT - doorwayHeight;
	const doorTop = new THREE.Mesh(
		new THREE.BoxGeometry(doorwayWidth + 0.5, doorTopHeight, 0.5),
		createWallMaterial()
	);
	doorTop.position.set(0, ROOM_HEIGHT - doorTopHeight / 2, ROOM_DEPTH / 2);
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
		color: 0x2a3a55,
		emissive: 0x1a2a44,
		emissiveIntensity: 0.7,
		roughness: 0.4,
		metalness: 0.2,
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
			// Alcove vertical light slit between buttresses — narrow tall
			// strip matching the concept's tall vertical wall apertures.
			const alcove = new THREE.Mesh(
				new THREE.BoxGeometry(0.1, 7.0, 0.6),
				alcoveLightMat,
			);
			alcove.position.set(xBase + xSign * 0.1, ROOM_HEIGHT * 0.45, z + archSpacing / 2);
			scene.add(alcove);
		}
	}

	// Back wall structural frame around gate — heavy Ancient architecture.
	// The SGU reference shows massive structural columns flanking the gate
	// with an arched top beam, giving a cathedral-like framing effect.
	const frameMat = new THREE.MeshStandardMaterial({
		color: 0x14141e,
		roughness: 0.6,
		metalness: 0.4,
		emissive: 0x060610,
		emissiveIntensity: 0.3,
	});
	// Top arch beam — wider than the gate, arched
	const topBeam = new THREE.Mesh(
		new THREE.BoxGeometry(GATE_RADIUS * 3, 1.5, 1.0),
		frameMat,
	);
	topBeam.position.set(0, GATE_CENTER.y + GATE_RADIUS + 2, -ROOM_DEPTH / 2 + 0.8);
	scene.add(topBeam);

	// Triangular scaffold buttresses flanking the gate — concept
	// gate-room-active.png shows two large triangular frames angled inward
	// toward the ring, creating the iconic Destiny gate-room "the gate is
	// held by an industrial cradle" silhouette. Heavier silhouette + a thin
	// emissive accent strip on the inner edge so they read against the dark
	// back wall at the cinematic exposure.
	// Gate room overrides exposure to 1.15 (cinematic-dim), so dark
	// MeshStandardMaterial at low emissive intensity vanishes. Use brighter
	// base color + higher emissive to keep silhouette readable.
	const strutMat = new THREE.MeshStandardMaterial({
		color: 0x44485a,
		roughness: 0.5,
		metalness: 0.6,
		emissive: 0x2a3044,
		emissiveIntensity: 1.4,
	});
	const strutAccentMat = new THREE.MeshBasicMaterial({
		color: 0x88b4ff,
		fog: true,
	});
	const strutLength = Math.hypot(GATE_RADIUS * 2.2, GATE_RADIUS * 2.0);
	for (const xSign of [-1, 1]) {
		const strut = new THREE.Mesh(
			new THREE.BoxGeometry(1.2, strutLength, 1.2),
			strutMat,
		);
		const baseX = xSign * GATE_RADIUS * 2.6;
		const baseY = 0.6;
		const topX = xSign * GATE_RADIUS * 0.5;
		const topY = GATE_CENTER.y + GATE_RADIUS * 0.95;
		const midX = (baseX + topX) / 2;
		const midY = (baseY + topY) / 2;
		const angle = Math.atan2(topX - baseX, topY - baseY);
		strut.position.set(midX, midY, -1.5);
		strut.rotation.z = angle;
		scene.add(strut);

		// Inner-edge accent strip — sits on the gate-facing face of the strut
		// so it reads as a glowing trim line in the silhouette.
		const accent = new THREE.Mesh(
			new THREE.BoxGeometry(0.08, strutLength * 0.92, 0.08),
			strutAccentMat,
		);
		// Offset toward the gate (interior side) along the strut's local +X.
		const accentOffset = -xSign * 0.65;
		accent.position.set(midX + accentOffset * Math.cos(angle), midY + accentOffset * -Math.sin(angle), -ROOM_DEPTH / 2 + 0.6);
		accent.rotation.z = angle;
		scene.add(accent);

		// Foot block — chunky base where the strut meets the floor. Darker
		// material than the strut so it reads as a mounting point, not a
		// glowing slab in the side-camera view.
		const foot = new THREE.Mesh(
			new THREE.BoxGeometry(1.6, 1.0, 1.4),
			new THREE.MeshStandardMaterial({
				color: 0x1a1a26,
				roughness: 0.7,
				metalness: 0.5,
				emissive: 0x080812,
				emissiveIntensity: 0.4,
			}),
		);
		foot.position.set(baseX, 0.5, -1.5);
		scene.add(foot);
	}

	// Cathedral ceiling trusses — running width-wise above the central aisle.
	// Concept gate-room-dormant.png shows a dense lattice of structural beams
	// up high; without these the ceiling reads as featureless black void.
	const trussMat = new THREE.MeshStandardMaterial({
		color: 0x0e0e18,
		roughness: 0.7,
		metalness: 0.5,
		emissive: 0x040408,
		emissiveIntensity: 0.2,
	});
	// Trusses sit at ~55% of ROOM_HEIGHT so they fall inside the front-camera
	// frustum (camera y=14 looking at y=8 with FOV ~50° clips anything above
	// ~y=40 at gate distance). Hanging them low also reads more "industrial
	// rib-cage" than "distant ceiling lattice."
	const trussY = ROOM_HEIGHT * 0.55;
	const trussCount = 7;
	const trussSpacing = (ROOM_DEPTH - 8) / (trussCount + 1);
	const trussGlowMat = new THREE.MeshStandardMaterial({
		color: 0x14141e,
		roughness: 0.6,
		metalness: 0.5,
		emissive: 0x223344,
		emissiveIntensity: 0.35,
	});
	// Cluster of downlight panels concentrated above the gate dais (z=0).
	// Concept gate-room-dormant.png shows a chandelier-like cluster of multiple
	// downlights centered on the gate; this approximates that read with cheap
	// emissive panels rather than actual spotlights.
	const downlightMat = new THREE.MeshBasicMaterial({ color: 0xa8b8d0, fog: true, toneMapped: false });
	for (const [dx, dz, w, d] of [
		[0, -2, 4.0, 1.2],
		[0,  2, 4.0, 1.2],
		[-3, 0, 1.0, 3.5],
		[ 3, 0, 1.0, 3.5],
	] as const) {
		const panel = new THREE.Mesh(
			new THREE.BoxGeometry(w, 0.2, d),
			downlightMat,
		);
		panel.name = "downlight-cluster";
		panel.position.set(dx, ROOM_HEIGHT - 0.3, dz);
		scene.add(panel);
	}
	for (let i = 1; i <= trussCount; i++) {
		const z = -ROOM_DEPTH / 2 + 4 + i * trussSpacing;
		// Arched truss main beam — wide rectangular section
		const truss = new THREE.Mesh(
			new THREE.BoxGeometry(ROOM_WIDTH * 0.85, 1.2, 0.8),
			trussGlowMat,
		);
		truss.position.set(0, trussY, z);
		scene.add(truss);
		// Vertical drops anchoring truss to ceiling
		for (const xSign of [-1, 1]) {
			const drop = new THREE.Mesh(
				new THREE.BoxGeometry(0.6, ROOM_HEIGHT - trussY, 0.6),
				trussMat,
			);
			drop.position.set(
				xSign * ROOM_WIDTH * 0.42,
				(ROOM_HEIGHT + trussY) / 2,
				z,
			);
			scene.add(drop);
		}
	}
	// Staircase structures flanking the gate — the SGU gate room has
	// staircases on both sides leading up to a second-floor catwalk/balcony.
	// These are the large angled structures visible in the reference image.
	const stairMat = new THREE.MeshStandardMaterial({
		color: 0x121220,
		roughness: 0.65,
		metalness: 0.4,
		emissive: 0x040408,
		emissiveIntensity: 0.2,
	});
	for (const xSign of [-1, 1]) {
		// Staircase body — angled box from floor to second level
		const stairHeight = ROOM_HEIGHT * 0.5;
		const stairWidth = 4.0;
		const stairDepth = 8.0;
		const stair = new THREE.Mesh(
			new THREE.BoxGeometry(stairWidth, stairHeight, stairDepth),
			stairMat,
		);
		stair.position.set(
			xSign * (GATE_RADIUS + 4),
			stairHeight / 2,
			-ROOM_DEPTH / 2 + stairDepth / 2 + 0.5,
		);
		scene.add(stair);

		// Railing/wall along stair top
		const railing = new THREE.Mesh(
			new THREE.BoxGeometry(stairWidth, 1.5, stairDepth),
			frameMat,
		);
		railing.position.set(
			xSign * (GATE_RADIUS + 4),
			stairHeight + 0.75,
			-ROOM_DEPTH / 2 + stairDepth / 2 + 0.5,
		);
		scene.add(railing);

		// Second floor platform extending from the staircase
		const platform = new THREE.Mesh(
			new THREE.BoxGeometry(stairWidth + 2, 0.5, ROOM_DEPTH * 0.3),
			stairMat,
		);
		platform.position.set(
			xSign * (GATE_RADIUS + 4),
			stairHeight + 0.25,
			0,
		);
		scene.add(platform);
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

	// Aged metal floor grate panels — single InstancedMesh for all panels
	// to keep draw calls at 1 instead of ~936 individual meshes.
	const grateMat = new THREE.MeshBasicMaterial({
		color: 0x05060a,
		fog: true,
	});
	const grateSpacingX = 4;
	const grateSpacingZ = 4;
	const grateGeo = new THREE.BoxGeometry(grateSpacingX - 0.15, 0.03, grateSpacingZ - 0.15);
	const xSteps = Math.floor((ROOM_WIDTH - 4) / grateSpacingX);
	const zSteps = Math.floor((ROOM_DEPTH - 4) / grateSpacingZ);
	const grateInstanced = new THREE.InstancedMesh(grateGeo, grateMat, xSteps * zSteps);
	const grateMatrix = new THREE.Matrix4();
	let grateIdx = 0;
	for (let xi = 0; xi < xSteps; xi++) {
		for (let zi = 0; zi < zSteps; zi++) {
			const x = -ROOM_WIDTH / 2 + 2 + xi * grateSpacingX + grateSpacingX / 2;
			const z = -ROOM_DEPTH / 2 + 2 + zi * grateSpacingZ + grateSpacingZ / 2;
			grateMatrix.makeTranslation(x, 0.015, z);
			grateInstanced.setMatrixAt(grateIdx++, grateMatrix);
		}
	}
	grateInstanced.instanceMatrix.needsUpdate = true;
	scene.add(grateInstanced);

	// Dark base floor plane — covers whatever bright tile floor the
	// scene.runtime.json contributes. Pure black + max roughness + zero metal
	// so the high (3.9) tone-map exposure doesn't push it back to mid-grey.
	// Sits at y=0.005 (above the JSON floor at y=-0.5, just below grates at
	// y=0.015) so it overdraws the bright JSON floor without z-fighting.
	const baseFloor = new THREE.Mesh(
		new THREE.PlaneGeometry(ROOM_WIDTH - 0.4, ROOM_DEPTH - 0.4),
		new THREE.MeshBasicMaterial({
			color: 0x040408,
			fog: true,
		}),
	);
	baseFloor.rotation.x = -Math.PI / 2;
	baseFloor.position.y = 0.005;
	scene.add(baseFloor);
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
	// ── Raised dais under the gate — concept shows gate sitting on a 2-step
	// platform that the player ascends. Elevates the gate so it dominates the
	// frame and gives the room a proper focal point.
	const daisMat = new THREE.MeshBasicMaterial({
		color: 0x16181e,
		fog: true,
	});
	// Lower tier — wider, shorter
	const daisLow = new THREE.Mesh(
		new THREE.BoxGeometry(GATE_RADIUS * 3, 0.4, GATE_RADIUS * 2.6),
		daisMat,
	);
	daisLow.position.set(0, 0.2, 0);
	scene.add(daisLow);
	// Upper tier — narrower, taller, sits on top
	const daisHigh = new THREE.Mesh(
		new THREE.BoxGeometry(GATE_RADIUS * 2.4, 0.4, GATE_RADIUS * 2.0),
		daisMat,
	);
	daisHigh.position.set(0, 0.6, 0);
	scene.add(daisHigh);

	// Dais front-edge trim light — thin warm emissive strip along the
	// upper tier's player-facing edge, mimicking the recessed accent
	// lighting visible on Ancient platform edges in the concept art.
	// MeshBasicMaterial + toneMapped:false so it survives gate-room
	// exposure 2.2 as a crisp light line, not a dim grey strip.
	const daisTrimMat = new THREE.MeshBasicMaterial({
		color: 0xffd29c, fog: false, toneMapped: false,
	});
	const daisTrim = new THREE.Mesh(
		new THREE.BoxGeometry(GATE_RADIUS * 2.36, 0.06, 0.06),
		daisTrimMat,
	);
	// Sits flush with the front face of daisHigh (z = +GATE_RADIUS) at
	// the top edge (y ≈ 0.78).
	daisTrim.position.set(0, 0.78, GATE_RADIUS * 1.0 - 0.03);
	scene.add(daisTrim);
	// Lower-tier matching trim for the wider step profile.
	const daisTrimLow = new THREE.Mesh(
		new THREE.BoxGeometry(GATE_RADIUS * 2.96, 0.06, 0.06),
		daisTrimMat,
	);
	daisTrimLow.position.set(0, 0.38, GATE_RADIUS * 1.3 - 0.03);
	scene.add(daisTrimLow);

	// ── Console row props along both side walls flanking the gate (per
	// concept gate-room-active.png — banks of lit operator consoles extending
	// from gate-mid toward the back wall). Procedural cluster: dark base box
	// + warm-blue emissive panel top. Placed ~14m off centerline, raised on
	// short bases. MeshBasic for the panels keeps them gate-room-exposure stable.
	const consoleBaseMat = new THREE.MeshStandardMaterial({
		color: 0x101522,
		roughness: 0.6,
		metalness: 0.5,
		emissive: 0x05080f,
		emissiveIntensity: 0.4,
	});
	const consolePanelMat = new THREE.MeshBasicMaterial({
		color: 0x4d8fd9,
		fog: false,
		toneMapped: false,
	});
	const consoleCount = 5;
	const consoleSpacing = 5.2;
	const consoleZStart = -GATE_RADIUS - 2;
	for (const sideX of [-14, 14] as const) {
		for (let i = 0; i < consoleCount; i++) {
			const z = consoleZStart - i * consoleSpacing;
			const base = new THREE.Mesh(
				new THREE.BoxGeometry(2.4, 1.1, 1.6),
				consoleBaseMat,
			);
			base.position.set(sideX, 0.55, z);
			scene.add(base);
			const panel = new THREE.Mesh(
				new THREE.BoxGeometry(2.0, 0.06, 1.0),
				consolePanelMat,
			);
			// tilt panel toward gate centerline
			panel.rotation.x = -0.25;
			panel.rotation.y = sideX < 0 ? -0.18 : 0.18;
			panel.position.set(sideX + (sideX < 0 ? 0.15 : -0.15), 1.18, z);
			scene.add(panel);
		}
	}

	// ── Front-facing stairs descending toward the player approach (+z side).
	// Concept gate-room-dormant.png shows a shallow stepped ramp leading up to
	// the gate dais. Five 0.16m steps spanning ~3m deep give a gentle climb that
	// reads from the doorway-distance camera without dominating the floor plane.
	const stepCount = 5;
	const stepRise = 0.8 / stepCount; // climb top of dais (0.8) over 5 steps
	const stepRun = 0.6;
	const stepWidth = GATE_RADIUS * 2.8;
	for (let i = 0; i < stepCount; i++) {
		const step = new THREE.Mesh(
			new THREE.BoxGeometry(stepWidth, stepRise, stepRun),
			daisMat,
		);
		// step i sits in front of the dais, descending as i increases.
		// y centerline = (stepCount - i - 0.5) * stepRise so top of step i = (stepCount - i) * stepRise
		const stepY = (stepCount - i - 0.5) * stepRise;
		const stepZ = GATE_RADIUS * 1.0 + (i + 0.5) * stepRun;
		step.position.set(0, stepY, stepZ);
		scene.add(step);
	}

	// ── Main ring — FLAT profile (rectangular cross-section), not a donut.
	// The SGU gate is a wide, shallow ring — LatheGeometry with a rectangular
	// profile matches the show's industrial look far better than TorusGeometry.
	// fog:false so the ring punches through atmospheric fog at distance.
	const outerRingMat = new THREE.MeshStandardMaterial({
		color: 0x3a3a44,
		roughness: 0.5,
		metalness: 0.9,
		emissive: 0x0e1520,
		emissiveIntensity: 1.0,
		fog: false,
	});
	const outerRing = new THREE.Mesh(
		createFlatRingGeometry(GATE_RADIUS, GATE_RING_WIDTH, GATE_RING_DEPTH, 64),
		outerRingMat,
	);
	outerRing.position.copy(GATE_CENTER);
	scene.add(outerRing);

	// Inner ring — a narrower inset track sitting just inside the main ring,
	// with a slightly shallower depth so it reads as recessed. Darker and
	// more metallic, matching the show's two-tier ring silhouette.
	const innerRingMat = new THREE.MeshStandardMaterial({
		color: 0x141420,
		roughness: 0.55,
		metalness: 0.9,
		emissive: 0x06090f,
		emissiveIntensity: 0.05,
		fog: false,
	});
	const innerRing = new THREE.Mesh(
		createFlatRingGeometry(GATE_RADIUS - GATE_RING_WIDTH / 2 - 0.2, 0.3, GATE_RING_DEPTH * 0.7, 64),
		innerRingMat,
	);

	// No glow halo — the SGU reference shows the gate as a dark metallic
	// ring against a dark wall, not a glowing blue portal. The halo was
	// creating a spurious oval edge in the similarity comparison.
	innerRing.position.copy(GATE_CENTER);
	scene.add(innerRing);

	// (Ring segments / symbol-wheel dots REMOVED — 36 decorative bumps
	// visually conflicted with the 9 chevrons and made the gate read as
	// "too busy". The clean silhouette matches the show's look better.)

	// Chevrons — 9 raised V-shaped bumps sitting ON the outer ring face.
	// Sized at ~14% of radius — a chunky industrial bump that reads as a
	// "locked glyph" without overwhelming the ring. Apex points outward.
	const CHEVRON_HEIGHT = 0.425;  // radial span
	const CHEVRON_HALF_W = 0.225;  // tangential half-width
	const CHEVRON_DEPTH  = 0.14;   // protrusion forward from ring face
	const chevronShape = new THREE.Shape();
	chevronShape.moveTo( 0,               CHEVRON_HEIGHT / 2);
	chevronShape.lineTo(-CHEVRON_HALF_W, -CHEVRON_HEIGHT / 2);
	chevronShape.lineTo( CHEVRON_HALF_W, -CHEVRON_HEIGHT / 2);
	chevronShape.closePath();
	const chevronGeo = new THREE.ExtrudeGeometry(chevronShape, {
		depth: CHEVRON_DEPTH,
		bevelEnabled: true,
		bevelThickness: 0.02,
		bevelSize: 0.015,
		bevelSegments: 2,
	});
	chevronGeo.translate(0, 0, -CHEVRON_DEPTH / 2);

	// Chevrons sit on the front face of the flat ring. Front face is at
	// z = GATE_RING_DEPTH / 2, and the chevron back needs to just touch it:
	// z = GATE_RING_DEPTH / 2 + CHEVRON_DEPTH / 2 = 0.175 + 0.14 ≈ 0.32
	const chevronZ = GATE_CENTER.z + GATE_RING_DEPTH / 2 + CHEVRON_DEPTH / 2;
	const chevronMeshes: THREE.Mesh[] = [];
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		const angle = Math.PI / 2 + (i / CHEVRON_COUNT) * Math.PI * 2;
		const chevronMat = new THREE.MeshStandardMaterial({
			color: COLOR_CHEVRON_OFF,
			roughness: 0.35,
			metalness: 0.8,
			emissive: COLOR_CHEVRON_OFF,
			emissiveIntensity: 0.3,
			fog: false,
		});
		const chevron = new THREE.Mesh(chevronGeo, chevronMat);
		chevron.position.set(
			GATE_CENTER.x + Math.cos(angle) * GATE_RADIUS,
			GATE_CENTER.y + Math.sin(angle) * GATE_RADIUS,
			chevronZ,
		);
		chevron.rotation.z = angle + Math.PI / 2;
		scene.add(chevron);
		chevronMeshes.push(chevron);
	}

	// Event horizon — plasma vortex texture (hidden until active).
	// Three's WebGPURenderer doesn't accept legacy ShaderMaterial, so we bake
	// the swirl pattern into a CanvasTexture and animate via UV rotation +
	// scale pulse on the mesh transform.
	const HORIZON_TEX_SIZE = 512;
	const horizonCanvas = document.createElement("canvas");
	horizonCanvas.width = HORIZON_TEX_SIZE;
	horizonCanvas.height = HORIZON_TEX_SIZE;
	const hctx = horizonCanvas.getContext("2d");
	if (hctx) {
		const cx = HORIZON_TEX_SIZE / 2;
		const cy = HORIZON_TEX_SIZE / 2;
		// Background radial gradient — deep blue edge to bright cyan core.
		const grad = hctx.createRadialGradient(cx, cy, 0, cx, cy, HORIZON_TEX_SIZE * 0.5);
		grad.addColorStop(0.0, "#dff0ff");
		grad.addColorStop(0.25, "#7cc8ff");
		grad.addColorStop(0.6, "#1e6cb8");
		grad.addColorStop(0.92, "#0a2a55");
		grad.addColorStop(1.0, "rgba(10,20,40,0)");
		hctx.fillStyle = grad;
		hctx.fillRect(0, 0, HORIZON_TEX_SIZE, HORIZON_TEX_SIZE);

		// Spiral wisps — many thin strokes with jittered radii so the swirl reads
		// as turbulent flowing energy, not a clean logo-spiral. Concept shows
		// organic churning wormhole, not 6 thick spiral arms.
		hctx.globalCompositeOperation = "lighter";
		const armCount = 16;
		for (let arm = 0; arm < armCount; arm++) {
			const baseAngle = (arm / armCount) * Math.PI * 2;
			const armTwist = Math.PI * (3 + Math.sin(arm * 1.7) * 0.8);
			hctx.beginPath();
			for (let t = 0; t <= 1; t += 0.01) {
				const jitter = Math.sin(t * 18 + arm * 2.3) * 6;
				const r = t * HORIZON_TEX_SIZE * 0.48 + jitter;
				const a = baseAngle + t * armTwist;
				const x = cx + Math.cos(a) * r;
				const y = cy + Math.sin(a) * r;
				if (t === 0) hctx.moveTo(x, y); else hctx.lineTo(x, y);
			}
			const opacity = 0.25 + (arm % 3) * 0.08;
			hctx.strokeStyle = `rgba(200, 230, 255, ${opacity})`;
			hctx.lineWidth = 2 + (arm % 4) * 0.7;
			hctx.lineCap = "round";
			hctx.stroke();
		}

		// Speckle turbulence — small bright dots scattered through the disc.
		hctx.globalCompositeOperation = "lighter";
		for (let i = 0; i < 1600; i++) {
			const r = Math.sqrt(Math.random()) * HORIZON_TEX_SIZE * 0.48;
			const a = Math.random() * Math.PI * 2;
			const x = cx + Math.cos(a) * r;
			const y = cy + Math.sin(a) * r;
			const sz = Math.random() * 2.5 + 0.5;
			const alpha = (1 - r / (HORIZON_TEX_SIZE * 0.5)) * 0.6;
			hctx.fillStyle = `rgba(220,240,255,${alpha})`;
			hctx.beginPath();
			hctx.arc(x, y, sz, 0, Math.PI * 2);
			hctx.fill();
		}

		// Soft alpha falloff at edge — punch out beyond r=0.96.
		hctx.globalCompositeOperation = "destination-in";
		const alphaGrad = hctx.createRadialGradient(cx, cy, 0, cx, cy, HORIZON_TEX_SIZE * 0.5);
		alphaGrad.addColorStop(0, "rgba(255,255,255,1)");
		alphaGrad.addColorStop(0.85, "rgba(255,255,255,1)");
		alphaGrad.addColorStop(1.0, "rgba(255,255,255,0)");
		hctx.fillStyle = alphaGrad;
		hctx.fillRect(0, 0, HORIZON_TEX_SIZE, HORIZON_TEX_SIZE);
	}
	const horizonTex = new THREE.CanvasTexture(horizonCanvas);
	horizonTex.colorSpace = THREE.SRGBColorSpace;
	const horizonMat = new THREE.MeshBasicMaterial({
		map: horizonTex,
		color: 0xffffff,
		transparent: true,
		opacity: 0,
		side: THREE.DoubleSide,
		depthWrite: false,
		fog: false,
		blending: THREE.AdditiveBlending,
	});
	const eventHorizon = new THREE.Mesh(
		new THREE.CircleGeometry(GATE_RADIUS - GATE_RING_WIDTH / 2 - 0.05, 64),
		horizonMat
	);
	eventHorizon.position.copy(GATE_CENTER);
	eventHorizon.visible = false;
	scene.add(eventHorizon);

	// Halo bloom — soft-edged radial gradient billboarded behind the gate so
	// the active gate appears to spill cyan light outward rather than wear a
	// hard donut sticker. CanvasTexture with annular alpha falloff (transparent
	// at center hole AND outer edge, peak alpha just outside the gate radius).
	const HALO_TEX_SIZE = 256;
	const haloCanvas = document.createElement("canvas");
	haloCanvas.width = HALO_TEX_SIZE;
	haloCanvas.height = HALO_TEX_SIZE;
	const haloCtx = haloCanvas.getContext("2d");
	if (haloCtx) {
		const hcx = HALO_TEX_SIZE / 2;
		const hcy = HALO_TEX_SIZE / 2;
		const grad = haloCtx.createRadialGradient(hcx, hcy, 0, hcx, hcy, HALO_TEX_SIZE * 0.5);
		grad.addColorStop(0.00, "rgba(120, 200, 255, 0)");
		grad.addColorStop(0.28, "rgba(120, 200, 255, 0)");
		grad.addColorStop(0.40, "rgba(220, 245, 255, 0.95)");
		grad.addColorStop(0.50, "rgba(160, 220, 255, 0.65)");
		grad.addColorStop(0.65, "rgba(110, 180, 240, 0.32)");
		grad.addColorStop(0.85, "rgba(70, 140, 220, 0.10)");
		grad.addColorStop(1.00, "rgba(40, 80, 160, 0)");
		haloCtx.fillStyle = grad;
		haloCtx.fillRect(0, 0, HALO_TEX_SIZE, HALO_TEX_SIZE);
	}
	const haloTex = new THREE.CanvasTexture(haloCanvas);
	haloTex.colorSpace = THREE.SRGBColorSpace;
	const haloMat = new THREE.MeshBasicMaterial({
		map: haloTex,
		color: 0xffffff,
		transparent: true,
		opacity: 0,
		blending: THREE.AdditiveBlending,
		depthWrite: false,
		side: THREE.DoubleSide,
		fog: false,
	});
	const haloGeo = new THREE.PlaneGeometry(GATE_RADIUS * 4.6, GATE_RADIUS * 4.6);
	const haloMesh = new THREE.Mesh(haloGeo, haloMat);
	haloMesh.position.copy(GATE_CENTER);
	haloMesh.position.z -= 0.12; // sit slightly behind ring face
	haloMesh.visible = false;
	scene.add(haloMesh);



	return {
		chevronMeshes,
		dialElapsed: 0,
		eventHorizon,
		halo: haloMesh,
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
	// Moody ambient — the SGU gate room is VERY dark with isolated cool pools.
	// Reference shows near-black walls with only gate glow and minimal fills.
	// Concept ref shows near-black walls with only the gate ring + isolated
	// pool lights visible. Ambient/hemisphere kept at the bare minimum so
	// architecture reads but doesn't compete with the gate's blue glow.
	const ambientLight = new THREE.AmbientLight(0x101830, 0.45);
	scene.add(ambientLight);
	const hemisphereLight = new THREE.HemisphereLight(0x182238, 0x080810, 0.6);
	scene.add(hemisphereLight);

	// Directional from above — cold, dim fill to barely reveal ceiling geometry.
	const dirLight = new THREE.DirectionalLight(0x334466, 0.25);
	dirLight.position.set(0, 25, 10);
	dirLight.target.position.set(0, 0, 0);
	scene.add(dirLight);
	scene.add(dirLight.target);

	// ── Gate-area accent lights ──────────────────────────────────────────
	// Idle defaults are deliberately tiny — the dormant concept shows the
	// gate as a dark silhouette, not a glowing portal. The dial/active
	// updates ramp these up via gate.pointLights when the gate engages.
	// Use distance-based falloff (decay 1.5) and finite range so the wash
	// stays local to the gate instead of bleeding across 80+ units of wall.

	// Directly IN FRONT of the gate ring — cool blue wash on the ring face.
	const gateRingLight = new THREE.PointLight(0x3366aa, 0.6, 14, 1.6);
	gateRingLight.position.set(0, GATE_CENTER.y, gateZ + 4);
	scene.add(gateRingLight);
	lights.push(gateRingLight);

	// Wider gate-area blue glow — visible from distance
	const gateFrontLight = new THREE.PointLight(0x2244aa, 0.3, 18, 1.6);
	gateFrontLight.position.set(0, 4, gateZ + 10);
	scene.add(gateFrontLight);
	lights.push(gateFrontLight);

	const gateBackLight = new THREE.PointLight(0x2244aa, 0.4, 14, 1.6);
	gateBackLight.position.set(0, 5, gateZ - 6);
	scene.add(gateBackLight);
	lights.push(gateBackLight);

	const gateTopLight = new THREE.PointLight(0x2244aa, 0.3, 16, 1.6);
	gateTopLight.position.set(0, 12, gateZ);
	scene.add(gateTopLight);
	lights.push(gateTopLight);

	// Overhead room light — cool dim fill, NOT warm.
	const overheadLight = new THREE.PointLight(0x1a2233, 0.15, 22, 1.6);
	overheadLight.position.set(0, ROOM_HEIGHT - 3, ROOM_DEPTH / 4);
	scene.add(overheadLight);
	lights.push(overheadLight);

	// Side accents — isolated cool pools matching the dormant concept's
	// scattered alcove glints. Finite range so each only paints its own wall.
	const COLOR_COOL_ACCENT = 0x1a2244;
	for (const zOff of [0, ROOM_DEPTH / 3, 2 * ROOM_DEPTH / 3]) {
		for (const xSign of [-1, 1]) {
			const side = new THREE.PointLight(COLOR_COOL_ACCENT, 0.18, 12, 1.8);
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
		const spot = new THREE.SpotLight(0xbbddff, 20, 20, Math.PI / 5, 0.5, 1.0);
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

	// Spin the inner ring — alternates direction with each chevron lock.
	// Odd chevrons spin clockwise, even counterclockwise (like a combination lock).
	const spinDir = gate.lockedChevrons % 2 === 0 ? 1 : -1;
	gate.innerRing.rotation.z += delta * 2.5 * spinDir;

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
	mat.emissive.set(COLOR_ANCIENT_GLOW);
	mat.emissiveIntensity = 0.3 + (gate.lockedChevrons / CHEVRON_COUNT) * 0.5;

	// All chevrons locked — start kawoosh
	if (gate.lockedChevrons >= CHEVRON_COUNT) {
		gate.state = "kawoosh";
		gate.kawooshElapsed = 0;
		gate.eventHorizon.visible = true;
		setHorizonOpacity(gate.eventHorizon, 0);
		gate.halo.visible = true;
		(gate.halo.material as THREE.MeshBasicMaterial).opacity = 0;
	}
}

function lockChevron(gate: GateRuntime, index: number): void {
	const chevron = gate.chevronMeshes[index];
	const mat = chevron.material as THREE.MeshStandardMaterial;
	mat.color.set(COLOR_CHEVRON_ON);
	mat.emissive.set(COLOR_CHEVRON_ON);
	mat.emissiveIntensity = 2.0;
}

function updateKawoosh(gate: GateRuntime, delta: number): void {
	gate.kawooshElapsed += delta;
	const progress = gate.kawooshElapsed / KAWOOSH_DURATION;

	if (progress < 0.3) {
		// Phase 1: Burst outward (kawoosh!)
		const burstProgress = progress / 0.3;
		const scale = 0.1 + burstProgress * 1.4;
		gate.eventHorizon.scale.set(scale, scale, 1);
		setHorizonOpacity(gate.eventHorizon, burstProgress * 0.95);
	} else if (progress < 0.6) {
		// Phase 2: Retract to stable size
		const retractProgress = (progress - 0.3) / 0.3;
		const scale = 1.5 - retractProgress * 0.5;
		gate.eventHorizon.scale.set(scale, scale, 1);
	} else {
		// Phase 3: Settle
		gate.eventHorizon.scale.set(1, 1, 1);
		setHorizonOpacity(gate.eventHorizon, 0.9);
	}
	(gate.halo.material as THREE.MeshBasicMaterial).opacity = getHorizonOpacity(gate.eventHorizon) * 0.7;

	// Stop inner ring spinning gradually
	gate.innerRing.rotation.z += delta * (3.0 * (1 - progress));

	if (gate.kawooshElapsed >= KAWOOSH_DURATION) {
		gate.state = "active";
		gate.dialElapsed = 0;
		gate.eventHorizon.scale.set(1, 1, 1);
		setHorizonOpacity(gate.eventHorizon, 0.9);
		(gate.halo.material as THREE.MeshBasicMaterial).opacity = 0.55;
	}
}

let activeWormholeFrame = 0;

function updateActiveWormhole(gate: GateRuntime, delta: number): void {
	gate.dialElapsed += delta;
	activeWormholeFrame++;

	if (activeWormholeFrame % 3 === 0) {
		const pulse = Math.sin(gate.dialElapsed * 2.0) * 0.05;
		setHorizonOpacity(gate.eventHorizon, 0.92 + pulse);
	}

	// Subtle rotation (cheap — just a transform, no material change)
	gate.eventHorizon.rotation.z += delta * 0.2;

	// Skip light modulation entirely — static intensity during active wormhole
	// (changing light intensity every frame forces full scene re-light)
}

function updateShutdown(gate: GateRuntime, delta: number): void {
	gate.kawooshElapsed += delta;
	const progress = Math.min(gate.kawooshElapsed / SHUTDOWN_DURATION, 1);

	// Shrink and fade
	const scale = 1 - progress;
	gate.eventHorizon.scale.set(scale, scale, 1);
	setHorizonOpacity(gate.eventHorizon, 0.9 * (1 - progress));

	(gate.halo.material as THREE.MeshBasicMaterial).opacity = 0.55 * (1 - progress);

	if (progress >= 1) {
		gate.state = "idle";
		gate.eventHorizon.visible = false;
		gate.halo.visible = false;
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

// Shared materials for corridor/storage — reused inside a single mount() pass.
// `let` (not `const`) because dispose() disposes them; mount() must recreate
// fresh instances on every remount or the second mount uses disposed materials.
let extWallMat: THREE.MeshStandardMaterial;
let extCeilingMat: THREE.MeshStandardMaterial;

function createExtMaterials(): void {
	extWallMat = new THREE.MeshStandardMaterial({
		color: 0x222238, emissive: 0x141428, emissiveIntensity: 1.0,
		roughness: 0.9, metalness: 0.1, side: THREE.DoubleSide
	});
	extCeilingMat = new THREE.MeshStandardMaterial({
		color: 0x181828, emissive: 0x0c0c20, emissiveIntensity: 1.0,
		roughness: 0.95, metalness: 0.05
	});
}

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
	// Save original projection to restore on dispose (camera is shared across scenes)
	const origNear = camera.near;
	const origFar = camera.far;
	camera.near = 0.1;
	camera.far = 500;
	camera.updateProjectionMatrix();

	// Force a deep near-black backdrop + atmospheric fog for the gate room.
	// Without this we inherit whatever scene.background the previous scene
	// left set (or the renderer's lavender clear color) — breaking the
	// SGU "very dark with isolated cool pools" look from the concept ref
	// (design/concept-art/gate-room/gate-room-dormant.png).
	scene.background = new THREE.Color(0x02030a);
	scene.fog = new THREE.FogExp2(0x02030a, 0.018);
	// Tone the renderer down for the interior — exposure 3.9 was tuned for
	// the dark-space opening cinematic and over-blasts the closed gate room.
	const origExposure = renderer.toneMappingExposure;
	renderer.toneMappingExposure = 2.2;
	const bus = scopedBus();

	// Reset module-level mutable state — ES modules are singletons, so any value
	// that survives across remounts (scene → other scene → back to gate-room)
	// will leak stale frame counters / camera-distance smoothers / disposed
	// material refs. Recreate or reset everything that mount() owns.
	wallMeshes.length = 0;
	occludableMeshes.length = 0;
	smoothedCamDistance = -1;
	lastHitDistance = Infinity;
	activeWormholeFrame = 0;
	createExtMaterials();
	const debugObjects: THREE.Object3D[] = [];
	let debugMode = false;
	let cinematicDrivingGate = false;

	// ─── Build the gate room (existing prototype) ────────────────────────
	buildRoom(scene);

	// Hide the GLB stargate baked into scene.runtime.json — buildStargate()
	// constructs a procedural ring that the cinematic + dial logic drives,
	// and the GLB version was double-rendering with a galaxy-textured inner
	// disc that doesn't match the dormant concept ref. Re-checked each
	// frame (briefly) because the GLB resolves async after mount() runs.
	const hideGlbStargate = () => {
		// The runtime.json was authored as a stand-alone prototype gate room
		// (8m-tall walls + GLB stargate). buildRoom + buildStargate now own
		// the visible architecture, so suppress everything from the JSON to
		// avoid double-stacking and the small-ceiling occluding the procedural
		// ring at y≈12.
		const hideNames = new Set<string>([
			"Stargate", "Stargate:high",
			"Floor", "Ancient Floor", "Ceiling",
			"Back Wall", "Front Wall Left", "Front Wall Right", "Front Wall Top",
			"Left Wall", "Right Wall",
			"Frame Top", "Frame Left", "Frame Right",
		]);
		// Prefixes covering all sub-mesh variants (e.g. ":high", ":low", ":Ancient Wall").
		// runtime.json is a giant prototype scene; hide all the back-room/storage/corridor
		// extensions so only the procedural geometry plus arches + guide strips render.
		// Only hide the prototype scaffolding that creates the cream-box and
		// off-stage corridor extensions. Wall Strip, Fixture, Lens, Overhead
		// are the architectural light accents we WANT visible (per concept art:
		// vertical wall strips + glowing console rows are the key gate-room
		// silhouette). They're now kept for atmosphere.
		const hidePrefixes = [
			"Chevron ",
			"Storage ",
			"Corridor ",
		];
		scene.traverse((obj) => {
			if (hideNames.has(obj.name) || hidePrefixes.some((p) => obj.name.startsWith(p))) {
				obj.visible = false;
			}
		});
	};
	hideGlbStargate();

	// ─── runtime.json wall accent emissive lift ─────────────────────────
	// The dominant gate-room architecture (Wall Strip, Fixture, Lens,
	// Overhead nodes) comes from runtime.json prefabs, NOT the procedural
	// buildRoom() walls. createWallMaterial() can only tint small back-fill
	// geometry. To propagate the concept-art cool indigo cast across the
	// dominant silhouette, traverse the runtime nodes after they resolve
	// and lift their emissive directly. Idempotent via userData flag.
	const accentPrefixes = ["Wall Strip", "Fixture", "Lens", "Overhead"];
	const lensColor = new THREE.Color(0x4488cc);
	const stripColor = new THREE.Color(0x223344);
	// Guide Strips render as a bright floor grid below the dais that doesn't
	// match concept gate-room-active (concept floor is mostly dark). They're
	// many small brush instances — match by material .name, not mesh node name.
	const guideColor = new THREE.Color(0x1a1208);
	const patchAccentEmissive = () => {
		scene.traverse((obj) => {
			const mesh = obj as THREE.Mesh;
			if (!mesh.isMesh) return;
			const accentMatch = accentPrefixes.some((p) => obj.name.startsWith(p));
			const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
			for (const m of mats) {
				const mat = m as THREE.MeshStandardMaterial;
				if (!mat || !("emissive" in mat)) continue;
				if (mat.userData?.sguEmissivePatched) continue;
				if (mat.name === "Guide Strip") {
					mat.emissive.copy(guideColor);
					mat.emissiveIntensity = 0.12;
					mat.needsUpdate = true;
					mat.userData = { ...(mat.userData ?? {}), sguEmissivePatched: true };
					continue;
				}
				if (!accentMatch || obj.userData.sguEmissivePatched) continue;
				if (obj.name.startsWith("Lens")) {
					mat.emissive.copy(lensColor);
					mat.emissiveIntensity = 1.2;
				} else {
					mat.emissive.copy(stripColor);
					mat.emissiveIntensity = 0.6;
				}
				mat.needsUpdate = true;
			}
			if (accentMatch) obj.userData.sguEmissivePatched = true;
		});
	};
	patchAccentEmissive();

	// Retries — runtime.json GLB resolves async after mount(). The "Stargate"
	// node mounts first, but its inner GLB hierarchy (Sketchfab_model →
	// Root → Cylinder, Cube003..033) finishes loading later. Hide aggressively
	// at 100ms cadence for 8s, then a slower safety net.
	const fastInterval = setInterval(() => {
		hideGlbStargate();
		patchAccentEmissive();
	}, 100);
	const fastIntervalGuard = setTimeout(() => clearInterval(fastInterval), 8000);
	const slowInterval = setInterval(() => {
		hideGlbStargate();
		patchAccentEmissive();
	}, 1000);
	const slowIntervalGuard = setTimeout(() => clearInterval(slowInterval), 30000);

	// Floor is from the runtime JSON — kept dark. Visibility comes from
	// player light, room lights, and the yellow runway strips.
	const gate = buildStargate(scene);
	const lights = buildLighting(scene, debugObjects);
	gate.pointLights = lights;

	// ─── Ancient running lights — pinpoint accent scatter ──────────────────
	// Concept gate-room-dormant.png shows dozens of tiny warm pinpoint lights
	// scattered across the upper architecture (panel indicators, distant
	// alcove glints, ceiling fixture markers). They give the cavernous space
	// scale and life without changing the cool cathedral mood. MeshBasicMaterial
	// with toneMapped:false so each pinpoint reads at its authored brightness
	// regardless of the gate-room's exposure-2.2 setting (memory:
	// feedback_per_scene_exposure). fog:false so distant lights don't fade
	// into the haze — they're light sources, not atmospheric particles.
	const runningLightMat = new THREE.MeshBasicMaterial({
		color: 0xffcc88, fog: false, toneMapped: false,
	});
	const coolLightMat = new THREE.MeshBasicMaterial({
		color: 0x88aacc, fog: false, toneMapped: false,
	});
	const pinpointGeo = new THREE.BoxGeometry(0.25, 0.25, 0.25);
	// Deterministic-ish positions: row scatter on each side wall plus some
	// rear-wall and front-arch placements. Heights cluster in 3 bands so the
	// scatter reads as architectural levels (catwalk, gantry, ceiling).
	const heightBands = [12, 22, 34];
	for (let i = 0; i < 60; i++) {
		const xSign = i % 2 === 0 ? -1 : 1;
		const yBand = heightBands[i % heightBands.length];
		const yJitter = (Math.sin(i * 13.7) * 0.5 + 0.5) * 4 - 2;
		const z = (Math.sin(i * 7.3) * 0.5) * (ROOM_DEPTH * 0.85);
		const xJitter = (Math.cos(i * 11.1) * 0.5 + 0.5) * 4 - 2;
		const useCool = i % 7 === 0;
		const pin = new THREE.Mesh(pinpointGeo, useCool ? coolLightMat : runningLightMat);
		pin.position.set(
			xSign * (ROOM_WIDTH / 2 - 1.5 + xJitter),
			yBand + yJitter,
			z,
		);
		scene.add(pin);
	}
	// Rear-wall scatter — visible from the front-camera framing as distant
	// architectural lights behind the gate. Small cluster at upper third.
	for (let i = 0; i < 18; i++) {
		const x = (Math.sin(i * 5.1) * 0.5) * (ROOM_WIDTH * 0.55);
		const y = 18 + (i % 4) * 6;
		const useCool = i % 5 === 0;
		const pin = new THREE.Mesh(pinpointGeo, useCool ? coolLightMat : runningLightMat);
		pin.position.set(x, y, -ROOM_DEPTH / 2 + 1.0);
		scene.add(pin);
	}

	// ─── Floor reflection pool — fakes wet-floor specular ────────────────
	// concept gate-room-dormant.png + gate-room-active.png both show a
	// reflective floor with the gate's image bleeding onto it. A real planar
	// Reflector would unmask the runtime.json grid (memory:
	// feedback_gate_room_wet_floor_attempt). Instead, lay a soft additive
	// disc on the floor in front of the gate. Reads as the gate's bounced
	// glow without needing a real reflection. Subtle when dormant, brighter
	// during active (additive blending naturally responds to scene exposure).
	const reflectionTexSize = 256;
	const reflectionCanvas = document.createElement("canvas");
	reflectionCanvas.width = reflectionCanvas.height = reflectionTexSize;
	const rCtx = reflectionCanvas.getContext("2d");
	if (rCtx) {
		const cx = reflectionTexSize / 2;
		// Vertical gradient — strongest near gate (top of canvas), fading
		// toward camera. Authored so the disc plane (rotated to lie flat
		// with V running away from gate) reads as bounced light bleeding
		// out from under the gate.
		const grad = rCtx.createLinearGradient(0, 0, 0, reflectionTexSize);
		grad.addColorStop(0.00, "rgba(110, 170, 230, 0.45)");
		grad.addColorStop(0.20, "rgba(80, 140, 210, 0.28)");
		grad.addColorStop(0.55, "rgba(50, 100, 180, 0.10)");
		grad.addColorStop(1.00, "rgba(30, 60, 130, 0)");
		rCtx.fillStyle = grad;
		rCtx.fillRect(0, 0, reflectionTexSize, reflectionTexSize);
		// Horizontal alpha falloff — punch out left/right edges so the disc
		// reads as a soft pool, not a hard rectangle.
		rCtx.globalCompositeOperation = "destination-in";
		const xGrad = rCtx.createLinearGradient(0, 0, reflectionTexSize, 0);
		xGrad.addColorStop(0.0, "rgba(255,255,255,0)");
		xGrad.addColorStop(0.2, "rgba(255,255,255,1)");
		xGrad.addColorStop(0.8, "rgba(255,255,255,1)");
		xGrad.addColorStop(1.0, "rgba(255,255,255,0)");
		rCtx.fillStyle = xGrad;
		rCtx.fillRect(0, 0, reflectionTexSize, reflectionTexSize);
		void cx;
	}
	const reflectionTex = new THREE.CanvasTexture(reflectionCanvas);
	reflectionTex.colorSpace = THREE.SRGBColorSpace;
	const reflectionMat = new THREE.MeshBasicMaterial({
		map: reflectionTex,
		transparent: true,
		opacity: 1.0,
		blending: THREE.AdditiveBlending,
		depthWrite: false,
		fog: true,
		toneMapped: true,
		side: THREE.DoubleSide,
	});
	const reflectionMesh = new THREE.Mesh(
		new THREE.PlaneGeometry(GATE_RADIUS * 2.2, GATE_RADIUS * 4.0),
		reflectionMat,
	);
	reflectionMesh.rotation.x = -Math.PI / 2;
	// Place in front of the gate (camera-facing direction, +Z), with the
	// "near gate" edge of the gradient hugging the gate base.
	reflectionMesh.position.set(0, 0.02, GATE_RADIUS * 2.0);
	scene.add(reflectionMesh);

	// ─── Floor runway runners — leads the eye from camera to gate ────────
	// The vast dark floor between camera and gate has no scale cue. Two
	// parallel rows of inset floor-level pinpoints at ~y=0.05 read as
	// embedded Ancient runway lights, framing the approach to the gate.
	// Tiny (0.18 cube) so they're points-of-light, not visible blocks.
	const runwayLightGeo = new THREE.BoxGeometry(0.32, 0.10, 0.32);
	const runwayLightMat = new THREE.MeshBasicMaterial({
		color: 0xffe2b6, fog: false, toneMapped: false,
	});
	const runwayHalfWidth = 5.5;
	const runwayStart = ROOM_DEPTH / 2 - 4;
	const runwayEnd = -ROOM_DEPTH / 2 + 18;
	const runwayCount = 14;
	for (let i = 0; i < runwayCount; i++) {
		const t = i / (runwayCount - 1);
		const z = runwayStart + (runwayEnd - runwayStart) * t;
		for (const xSign of [-1, 1] as const) {
			const pin = new THREE.Mesh(runwayLightGeo, runwayLightMat);
			pin.position.set(xSign * runwayHalfWidth, 0.05, z);
			scene.add(pin);
		}
	}

	// ─── Photo mode ─────────────────────────────────────────────────────
	// ?photo=1 — disable player character, lock camera at specified position.
	// ?camx=0&camy=2&camz=15&lookx=0&looky=4&lookz=0 — camera placement.
	// ?gate=active — force the gate into fully-active state (all chevrons
	// locked, event horizon visible + glowing) for reference comparison.
	// Designed for visual comparison screenshots without the player character.
	const photoParams = new URLSearchParams(window.location.search);
	const photoMode = photoParams.has("photo");
	if (photoMode && player) {
		player.object.visible = false;
		player.inputEnabled = false;
	}
	if (photoMode && photoParams.get("gate") === "active") {
		// Lock all chevrons + snap to active without running the dial sequence.
		for (let i = 0; i < CHEVRON_COUNT; i++) {
			lockChevron(gate, i);
		}
		gate.lockedChevrons = CHEVRON_COUNT;
		gate.state = "active";
		gate.eventHorizon.visible = true;
		setHorizonOpacity(gate.eventHorizon, 0.95);
		gate.halo.visible = true;
		(gate.halo.material as THREE.MeshBasicMaterial).opacity = 0.6;
	}

	// ─── Player-attached ambient light (Eli's subtle glow) ──────────────
	const playerLight = new THREE.PointLight(0xccddff, 2.5, 15, 1.5);
	playerLight.position.set(0, 2, 0);
	if (player && !photoMode) {
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
	// Left side (Rush's workstations) at x=-22; mirrored right side at x=+22 for
	// symmetry — concept shows console banks flanking the dais on both sides.
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
	for (const cz of [40, 48, 56]) {
		const base = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.9, 0.8), consoleBaseMat);
		base.position.set(22, 0.45, cz);
		consoleRoot.add(base);
		const topPanel = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.05, 0.8), consolePanelMat);
		topPanel.position.set(22, 0.92, cz);
		consoleRoot.add(topPanel);
		const monitor = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.55, 0.04), consoleScreenMat);
		monitor.position.set(22.3, 1.25, cz);
		monitor.rotation.z = Math.PI / 2;   // mirror so screen faces -x (toward gate)
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
	const isCinematicBoot = !photoMode && Boolean(sessionStorage.getItem("sgu-new-game"));
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
	// Arrow-key selection dialogue — the highlighted option follows
	// ↑/↓ (keyboard) or the gamepad D-pad / left stick. Confirm with
	// A (gamepad) or Enter (keyboard). The panel shows the confirm hint
	// next to the highlighted row so the player can see which button to
	// press. Detection is refreshed once per frame in the update loop.
	const confirmHintInitial = getInput().gamepad.isConnected ? "A" : "Enter";
	const dialoguePanel = createDialoguePanel(dialogueBus, {
		style: 'sci-fi',
		navigation: 'select',
		confirmHint: confirmHintInitial,
	});
	// Keyboard nav listener — raw keydown so it feels instant. Only
	// intercepts when a dialogue is open so arrows stay free for other
	// UI elsewhere. Cleanup registered so scene exit detaches it.
	const dialogueKeyHandler = (ev: KeyboardEvent): void => {
		if (!dialoguePanel.isOpen()) return;
		if (ev.code === "ArrowUp") { ev.preventDefault(); dialoguePanel.selectPrev(); }
		else if (ev.code === "ArrowDown") { ev.preventDefault(); dialoguePanel.selectNext(); }
		else if (ev.code === "Enter") { ev.preventDefault(); dialoguePanel.confirmSelection(); }
	};
	window.addEventListener("keydown", dialogueKeyHandler);
	gateRoomExtraDisposables.push(() => window.removeEventListener("keydown", dialogueKeyHandler));
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

		const gateControl = createGateControl(gate);
		cinematicDrivingGate = true;
		cinematicController = new GateRoomCinematicController(
			scene,
			camera as import("three").PerspectiveCamera,
			gateControl,
			() => {
				// Cinematic complete — restore HUD, gameplay NPCs, input.
				cinematicDrivingGate = false;
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
			(cleanup) => gateRoomExtraDisposables.push(cleanup),
			context.physicsWorld,
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

			// Dialogue navigation — gamepad D-pad moves the highlight.
			// Keyboard ↑/↓/Enter are handled by the `dialogueKeyHandler`
			// window listener installed below (raw keydown, not polled)
			// so they don't need per-frame edge detection here.
			// MenuConfirm (Enter + gamepad A) fires the highlighted option.
			if (dialoguePanel.isOpen()) {
				if (input.isActionJustPressed(Action.DPadUp)) {
					dialoguePanel.selectPrev();
				} else if (input.isActionJustPressed(Action.DPadDown)) {
					dialoguePanel.selectNext();
				} else if (input.isActionJustPressed(Action.MenuConfirm)) {
					dialoguePanel.confirmSelection();
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
						// During cinematic, skip auto-dialing — cinematic drives chevron timing.
						// Kawoosh/active/shutdown still auto-advance via the real state machine.
						if (!(cinematicDrivingGate && gate.state === "dialing")) {
							updateGate(gate, delta);
						}
			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			if (cinematicController) cinematicController.update(delta);
			compassHud.update(camera as any, delta);

			// ─── Photo mode camera override ──────────────────────────────
			// Only re-apply URL-param camera if params are explicitly present.
			// Without this guard, __sgu.setCamera() in automated capture gets
			// clobbered each frame by the URL-param defaults.
			if (photoMode && photoParams.has("camx")) {
				const cx = Number(photoParams.get("camx") ?? "0");
				const cy = Number(photoParams.get("camy") ?? "2");
				const cz = Number(photoParams.get("camz") ?? "15");
				const lx = Number(photoParams.get("lookx") ?? "0");
				const ly = Number(photoParams.get("looky") ?? "4");
				const lz = Number(photoParams.get("lookz") ?? "0");
				camera.position.set(cx, cy, cz);
				camera.lookAt(lx, ly, lz);
			}

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
			// Skip pull-in in photo mode AND during the opening cinematic so
			// the cinematic camera shot isn't yanked toward the player every
			// frame (player spawns at z=12, same place as the cinematic
			// camera, which caused severe jitter and hid the gate).
			if (player && !photoMode && !cinematicController) {
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
					if (dist < behavior.interactionRadius! && dist < nearestDist) {
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
					interactPrompt.textContent = formatInteractPrompt(`Open crate (+${nearestCrate.contents} Ship Parts)`);
				} else if (interactTarget === "subsystem" && nearestSub) {
					const sub = shipState.getSubsystem(nearestSub.id);
					if (sub && sub.condition < 1.0) {
						interactPrompt.style.display = "block";
						if (parts >= sub.repairCost) {
							interactPrompt.textContent = formatInteractPrompt(
								`Repair ${sub.type} (${(sub.condition * 100).toFixed(0)}%) \u2014 ${sub.repairCost} parts`,
								"hold",
							);
						} else {
							interactPrompt.textContent = `Repair ${sub.type} \u2014 Need ${sub.repairCost} Ship Parts (have ${parts})`;
						}
					} else if (sub) {
						interactPrompt.style.display = "block";
						interactPrompt.textContent = `${sub.type} \u2014 Optimal`;
					}
				} else if (interactTarget === "npc" && nearestNpc) {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = formatInteractPrompt(`Talk to ${nearestNpc.definition.name}`);
				} else if (interactTarget === "gate") {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = formatInteractPrompt("Step through the Stargate");
				} else if (interactTarget === "scrubber-entrance") {
					interactPrompt.style.display = "block";
					interactPrompt.textContent = formatInteractPrompt("Take the lime to the CO\u2082 scrubber room \u2014 Deck 3, Section 7");
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
			// Clear runtime.json GLB-suppression intervals (and their auto-stop
			// guards) — these can outlive the scene if the player exits the
			// cinematic in <30s, otherwise they'd fire callbacks against a
			// disposed scene graph.
			clearInterval(fastInterval);
			clearInterval(slowInterval);
			clearTimeout(fastIntervalGuard);
			clearTimeout(slowIntervalGuard);
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
			// Restore shared camera projection (modified in mount)
			camera.near = origNear;
			camera.far = origFar;
			camera.updateProjectionMatrix();
			// Restore renderer exposure (we lowered it for the interior).
			renderer.toneMappingExposure = origExposure;
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
