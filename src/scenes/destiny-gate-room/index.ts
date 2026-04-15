/**
 * Gate Room Scene — Stargate arrival zone and ship entry point.
 *
 * Features the iconic Stargate with 9 chevrons, event horizon, and theDestiny's
 * distinctive ring wall. Ships dock here; players emerge into the corridor beyond.
 *
 * @see design/gdd/ship-exploration.md
 * @see design/gdd/destiny-gate-room.md
 */
import * as THREE from "three";
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

/**
 * Constructs the physical room geometry for the Gate Room, including walls, ceiling,
 * structural arches, and amber floor guide strips.
 * @param scene The Three.js scene to add geometry to.
 */
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
	const archMat = new THREE.MeshStandardMaterial({
		color: 0x15152a,
		roughness: 0.8,
		metalness: 0.2
	});
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

/**
 * Creates a flat-profiled ring (rectangular cross-section) using LatheGeometry.
 * @param radius The distance from the center to the mid-point of the ring profile.
 * @param width The width of the ring (thickness along the radius).
 * @param depth The depth of the ring (thickness along the axis of rotation).
 * @param segments The number of segments used to approximate the circle. Defaults to 64.
 * @returns A BufferGeometry representing the ring.
 */
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
		console.info("[GateRoom] Loaded stargate GLB model");
	} catch (error) {
		console.error("[GateRoom] Failed to load stargate GLB, using fallback ring:", error);
		// Fallback: simple torus
		const fallbackMat = new THREE.MeshStandardMaterial({
			color: COLOR_ANCIENT_METAL, roughness: 0.3, metalness: 0.85
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
		color: 0x222235, roughness: 0.25, metalness: 0.9
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
	statusEl.textContent = "Press G to dial the Stargate";

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
			status.textContent = "Press G to dial the Stargate";
			break;
		case "dialing":
			status.textContent = `Dialing... Chevron ${gate.lockedChevrons} of ${CHEVRON_COUNT}`;
			break;
		case "kawoosh":
			status.textContent = "Chevron 9 locked!";
			break;
		case "active":
			status.textContent = "Wormhole established \u2014 Press G to shut down";
			break;
		case "shutdown":
			status.textContent = "Wormhole disengaged";
			break;
	}
}

// ─── Gate activation logic ───────────────────────────────────────────────────

const DIAL_TIME_PER_CHEVRON = 1.0; // 1 second per chevron for dramatic pacing
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

function createDebugOverlay(renderer: any): { element: HTMLDivElement; update: (delta: number) => void } {
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
	let fps = 60;
	let lastTime = performance.now();

	const update = (_delta: number) => {
		frameCount++;
		if (frameCount % 10 !== 0) return;

		const now = performance.now();
		fps = Math.round(1000 / (now - lastTime) * 10) / 10;
		lastTime = now;

		const info = renderer.info as any;
		const fpsColor = fps >= 50 ? "#44ff88" : fps >= 30 ? "#ffaa44" : "#ff4444";

		el.textContent = [
			`FPS: ${fps}`,
			`Draw calls: ${info.render.calls}`,
			`Triangles: ${info.render.triangles.toLocaleString()}`,
			`Geometries: ${info.memory.geometries}`,
			`Textures: ${info.memory.textures}`,
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

// ─── Scene mount ─────────────────────────────────────────────────────────────

async function mount(context: GameSceneContext): Promise<GameSceneLifecycle> {
	const { scene, camera, player, renderer } = context;
	const bus = scopedBus();

	wallMeshes.length = 0;
	const debugObjects: THREE.Object3D[] = [];
	let debugMode = false;

	// ─── Static geometry is in scene.runtime.json ──────────────────────
	// Room walls, floor, ceiling, arches, corridor, storage, lights, and
	// accent strips are all in the runtime JSON. Only DYNAMIC objects
	// (stargate, supply crates, subsystem visuals) are built here.
	// buildRoom(scene);        // DISABLED — in runtime JSON
	// buildLighting(scene);    // DISABLED — lights in runtime JSON
	// buildCorridor(scene);    // DISABLED — in runtime JSON
	// buildStorageRoom(scene); // DISABLED — walls in runtime JSON (crates built below)

	const gate = await buildStargate(scene);
	gate.pointLights = []; // Lights are in runtime JSON now

	// ─── Player-attached ambient light (Eli's subtle glow) ──────────────
	const playerLight = new THREE.PointLight(0xccddff, 2.5, 15, 1.5);
	playerLight.position.set(0, 2, 0);
	if (player) {
		player.object.add(playerLight);
	}

	// Camera pull-in: no programmatic walls to track anymore
	occludableMeshes.length = 0;
	smoothedCamDistance = -1;

	// ─── Dynamic corridor/storage lights (intensity varies with ship power) ─
	const corrLightZ = ROOM_DEPTH / 2 + CORRIDOR_LENGTH / 2;
	const storLightZ = ROOM_DEPTH / 2 + CORRIDOR_LENGTH + STORAGE_DEPTH / 2;

	const corridorPointLight = new THREE.PointLight(0xddccaa, 0.5, 25, 1.5);
	corridorPointLight.position.set(0, EXT_ROOM_HEIGHT - 0.5, corrLightZ);
	scene.add(corridorPointLight);

	const storagePointLight = new THREE.PointLight(0xddccaa, 0.3, 20, 1.5);
	storagePointLight.position.set(0, EXT_ROOM_HEIGHT - 0.5, storLightZ);
	scene.add(storagePointLight);

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
	const debug = createDebugOverlay(renderer);
	debug.element.style.display = "none";
	const menu = createEscapeMenu(renderer.domElement);
	const cleanupFullscreen = setupFullscreen(renderer.domElement, menu);
	const interactPrompt = createInteractionPrompt();
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
	type InteractTarget = "subsystem" | "crate" | null;
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

	const handleKeyDown = (e: KeyboardEvent) => {
		if (e.code === "Backquote") {
			const now = performance.now();
			if (now - lastBackquoteTime < 400) { toggleDebug(); lastBackquoteTime = 0; }
			else lastBackquoteTime = now;
			return;
		}
		if (e.code === "KeyG" && !menu.visible) {
			if (gate.state === "idle") startDial(gate);
			else if (gate.state === "active") shutdownGate(gate);
		}
		if (e.code === "KeyE" && !e.repeat && !menu.visible) {
			if (interactTarget === "crate" && nearestCrate && !nearestCrate.looted) {
				// Loot the crate (instant)
				addResource("ship-parts", nearestCrate.contents);
				markCrateLooted(nearestCrate);
			} else if (interactTarget === "subsystem" && nearestSub && !repairingSubsystemId) {
				const sub = shipState.getSubsystem(nearestSub.id);
				if (sub && sub.condition < 1.0) {
					const cost = sub.repairCost;
					if (hasResource("ship-parts", cost)) {
						// Calculate how many segments needed to reach 100%
						const repairPerSegment = SHIP_STATE_CONFIG.BASE_REPAIR_AMOUNT * SHIP_STATE_CONFIG.REPAIR_SKILL_MODIFIER;
						const remaining = 1.0 - sub.condition;
						const segmentsToFull = Math.ceil(remaining / repairPerSegment);

						repairingSubsystemId = sub.id;
						repairTotalSegments = segmentsToFull;
						repairCompletedSegments = 0;
						repairSegmentElapsed = 0;
						player?.setRepairing(true);
						repairBar.init(segmentsToFull, nearestSub.mesh.position);
					}
				}
			}
		}
	};
	const handleKeyUp = (e: KeyboardEvent) => {
		if (e.code === "KeyE") {
			cancelRepair();
		}
	};
	window.addEventListener("keydown", handleKeyDown);
	window.addEventListener("keyup", handleKeyUp);

	let debugFrame = 0;

	return {
		update(delta: number) {
			updateGate(gate, delta);

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

				// Find nearest interactable (crates or subsystems)
				nearestSub = null;
				nearestCrate = null;
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
				} else {
					interactPrompt.style.display = "none";
				}
			}

			// ─── Debug overlays ──────────────────────────────────────────
			if (debugMode) {
			debug.update(0);
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
			window.removeEventListener("keydown", handleKeyDown);
			window.removeEventListener("keyup", handleKeyUp);
			cancelRepair();
			repairBar.dispose();
			cleanupFullscreen();
			hud.remove();
			debug.element.remove();
			shipDebugEl.remove();
			interactPrompt.remove();
			menu.dispose();
			shipState.dispose();
			bus.cleanup();
			wallMeshes.length = 0;
		}
	};
}

// ─── Scene definition ────────────────────────────────────────────────────────

export const destinyGateRoomScene = defineGameScene({
	id: "destiny-gate-room",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((module) => module.default)
	}),
	title: "Destiny Gate Room",
	player: {
		vrmUrl: "/characters/eli.vrm",
	},
	mount
});
