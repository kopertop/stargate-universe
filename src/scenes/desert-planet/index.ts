/**
 * Desert Planet Scene — Air Crisis (SGU Episode "Air")
 *
 * The crew gates to a nameless desert world to collect calcium deposits (lime)
 * that will be used to absorb CO₂ from Destiny's failing scrubbers.
 *
 * Scene contains:
 *  - Sandy/rocky desert terrain (placeholder geometry)
 *  - A stargate the player arrived through (return point)
 *  - 3 calcium deposit interaction points scattered across the terrain
 *  - HUD compass + CO₂ timer (the crew is running out of air back on Destiny)
 *
 * Quest objectives advanced here:
 *  - find-lime  → auto-advanced by QuestManager via resource:collected events
 *  - return-to-destiny → advanced when player steps back through the gate
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { emit, scopedBus } from "../../systems/event-bus";
import { Action, getInput } from "../../systems/input";
import { createQuestManager } from "../../systems/quest-manager";
import { registerAirCrisis, QUEST_ID as AIR_CRISIS_QUEST_ID } from "../../quests/air-crisis";
import { createHud, createCompass, createDialoguePanel } from "@kopertop/vibe-game-engine";
import { setLimeCollected } from "../../systems/scene-transition-state";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── Constants ────────────────────────────────────────────────────────────────

const GATE_RADIUS = 2.8;
const GATE_TUBE = 0.22;
const GATE_CENTER = new THREE.Vector3(0, GATE_RADIUS + GATE_TUBE - 0.3, 0);

// Desert color palette
const COLOR_SAND = 0xc2a065;
const COLOR_ROCK = 0x8a6a3a;
const COLOR_ROCK_DARK = 0x5a4020;
const COLOR_CALCIUM = 0xe8e0cc;
const COLOR_CALCIUM_GLOW = 0xfff5cc;
const COLOR_SUN = 0xffcc66;
const COLOR_ANCIENT_METAL = 0x2a2a3a;
const COLOR_GATE_GLOW = 0x4488ff;

// Calcium deposit positions (scattered around the map)
const CALCIUM_POSITIONS: THREE.Vector3[] = [
	new THREE.Vector3(-12, 0, -18),
	new THREE.Vector3(16, 0, -10),
	new THREE.Vector3(-6, 0, 22),
];

const COLLECT_RADIUS = 2.2;

// ─── Stargate ─────────────────────────────────────────────────────────────────

type GateState = "active" | "closing" | "closed";

type GateRuntime = {
	outerRing: THREE.Mesh;
	innerRing: THREE.Mesh;
	eventHorizon: THREE.Mesh;
	chevrons: THREE.Mesh[];
	state: GateState;
	elapsed: number;
};

// ─── Terrain builders ─────────────────────────────────────────────────────────

function buildRocks(scene: THREE.Scene): void {
	const rockMat = new THREE.MeshStandardMaterial({
		color: COLOR_ROCK,
		roughness: 0.95,
		metalness: 0.0,
	});
	const darkRockMat = new THREE.MeshStandardMaterial({
		color: COLOR_ROCK_DARK,
		roughness: 0.98,
		metalness: 0.0,
	});

	// Scattered rocky outcroppings — placeholder BoxGeometry boulders
	const rockDefs: Array<{ pos: [number, number, number]; scale: [number, number, number]; rot: number }> = [
		{ pos: [-18, 0.4, -5],  scale: [2.5, 0.8, 1.8], rot: 0.3 },
		{ pos: [20, 0.6, 8],    scale: [3.0, 1.2, 2.2], rot: -0.6 },
		{ pos: [-8, 0.5, 30],   scale: [1.8, 1.0, 2.5], rot: 0.9 },
		{ pos: [10, 0.3, -25],  scale: [4.0, 0.7, 2.0], rot: 1.2 },
		{ pos: [-25, 0.7, 15],  scale: [2.0, 1.4, 1.5], rot: 0.1 },
		{ pos: [28, 0.4, -15],  scale: [2.8, 0.9, 2.0], rot: -0.4 },
		{ pos: [5, 1.0, -30],   scale: [1.5, 2.0, 1.5], rot: 0.5 },
		{ pos: [-20, 0.8, -22], scale: [3.5, 1.6, 2.5], rot: -1.1 },
	];

	for (const def of rockDefs) {
		const mat = Math.random() > 0.4 ? rockMat : darkRockMat;
		const rock = new THREE.Mesh(new THREE.BoxGeometry(...def.scale), mat);
		rock.position.set(...def.pos);
		rock.position.y += def.scale[1] / 2;
		rock.rotation.y = def.rot;
		scene.add(rock);
	}
}

function buildStargate(scene: THREE.Scene): GateRuntime {
	const outerRingMat = new THREE.MeshStandardMaterial({
		color: COLOR_ANCIENT_METAL,
		roughness: 0.3,
		metalness: 0.85,
	});
	const outerRing = new THREE.Mesh(
		new THREE.TorusGeometry(GATE_RADIUS, GATE_TUBE * 2.2, 8, 64),
		outerRingMat
	);
	outerRing.position.copy(GATE_CENTER);
	scene.add(outerRing);

	const innerRingMat = new THREE.MeshStandardMaterial({
		color: 0x222235,
		roughness: 0.25,
		metalness: 0.9,
	});
	const innerRing = new THREE.Mesh(
		new THREE.TorusGeometry(GATE_RADIUS - 0.05, GATE_TUBE * 1.4, 8, 64),
		innerRingMat
	);
	innerRing.position.copy(GATE_CENTER);
	scene.add(innerRing);

	// Chevrons (simplified — just 9 bright markers)
	const chevrons: THREE.Mesh[] = [];
	const CHEVRON_COUNT = 9;
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		const angle = (i / CHEVRON_COUNT) * Math.PI * 2 - Math.PI / 2;
		const chevMat = new THREE.MeshStandardMaterial({
			color: 0x44aaff,
			emissive: 0x44aaff,
			emissiveIntensity: 1.0,
			roughness: 0.4,
			metalness: 0.7,
		});
		const chev = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.3, 0.15), chevMat);
		chev.position.set(
			GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 0.15),
			GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 0.15),
			GATE_CENTER.z + 0.15
		);
		scene.add(chev);
		chevrons.push(chev);
	}

	// Active event horizon — wormhole is already open when player arrives
	const horizonMat = new THREE.MeshStandardMaterial({
		color: 0x88bbff,
		emissive: 0x88bbff,
		emissiveIntensity: 0.8,
		transparent: true,
		opacity: 0.8,
		side: THREE.DoubleSide,
		roughness: 0.1,
		metalness: 0.0,
	});
	const eventHorizon = new THREE.Mesh(
		new THREE.CircleGeometry(GATE_RADIUS - GATE_TUBE - 0.05, 64),
		horizonMat
	);
	eventHorizon.position.copy(GATE_CENTER);
	scene.add(eventHorizon);

	// Gate glow light
	const gateLight = new THREE.PointLight(COLOR_GATE_GLOW, 4, 12, 1.5);
	gateLight.position.copy(GATE_CENTER).add(new THREE.Vector3(0, 0, 1));
	scene.add(gateLight);

	return { outerRing, innerRing, eventHorizon, chevrons, state: "active", elapsed: 0 };
}

// ─── Calcium deposits ─────────────────────────────────────────────────────────

type CalciumDeposit = {
	group: THREE.Group;
	position: THREE.Vector3;
	collected: boolean;
	glowMesh: THREE.Mesh;
};

function buildCalciumDeposit(scene: THREE.Scene, pos: THREE.Vector3): CalciumDeposit {
	const group = new THREE.Group();
	group.position.copy(pos);

	// Main rock body — pale chalky white
	const bodyMat = new THREE.MeshStandardMaterial({
		color: COLOR_CALCIUM,
		roughness: 0.85,
		metalness: 0.0,
	});
	const body = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.9, 1.0), bodyMat);
	body.position.y = 0.45;
	group.add(body);

	// Crystalline top formations — slightly lighter, glowing
	const crystalMat = new THREE.MeshStandardMaterial({
		color: COLOR_CALCIUM_GLOW,
		emissive: COLOR_CALCIUM_GLOW,
		emissiveIntensity: 0.35,
		roughness: 0.3,
		metalness: 0.1,
	});
	for (let i = 0; i < 3; i++) {
		const h = 0.3 + i * 0.15;
		const crystal = new THREE.Mesh(new THREE.BoxGeometry(0.15, h, 0.12), crystalMat.clone());
		crystal.position.set(-0.3 + i * 0.3, 0.9 + h / 2, 0.1 * (i % 2 === 0 ? 1 : -1));
		crystal.rotation.z = (Math.random() - 0.5) * 0.4;
		group.add(crystal);
	}

	// Interaction glow ring at base — pulses to indicate collectability
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0xffee88,
		emissive: 0xffee88,
		emissiveIntensity: 0.6,
		transparent: true,
		opacity: 0.7,
	});
	const glowMesh = new THREE.Mesh(new THREE.RingGeometry(0.7, 0.9, 24), glowMat);
	glowMesh.rotation.x = -Math.PI / 2;
	glowMesh.position.y = 0.02;
	group.add(glowMesh);

	scene.add(group);
	return { group, position: pos, collected: false, glowMesh };
}

function markDepositCollected(deposit: CalciumDeposit): void {
	deposit.collected = true;
	// Dim the glow and tint the body grey
	deposit.group.children.forEach((child) => {
		const mesh = child as THREE.Mesh;
		if (!mesh.material) return;
		const mat = mesh.material as THREE.MeshStandardMaterial;
		mat.emissiveIntensity = 0;
		mat.color.set(0x888877);
	});
}

// ─── HUD elements ─────────────────────────────────────────────────────────────

function createCO2Timer(startSeconds: number): {
	element: HTMLDivElement;
	update: (delta: number) => void;
	getRemaining: () => number;
} {
	let remaining = startSeconds;

	const el = document.createElement("div");
	el.id = "co2-timer";
	Object.assign(el.style, {
		position: "fixed",
		top: "12px",
		left: "12px",
		color: "#ff4422",
		fontFamily: "'Courier New', monospace",
		fontSize: "13px",
		lineHeight: "1.6",
		background: "rgba(0, 0, 0, 0.7)",
		padding: "6px 12px",
		borderRadius: "3px",
		pointerEvents: "none",
		userSelect: "none",
		zIndex: "998",
		textShadow: "0 0 8px #ff442266",
		whiteSpace: "pre",
	});
	document.body.appendChild(el);

	const update = (delta: number): void => {
		remaining = Math.max(0, remaining - delta);
		const minutes = Math.floor(remaining / 60);
		const seconds = Math.floor(remaining % 60);
		const pad = (n: number): string => String(n).padStart(2, "0");
		const urgency = remaining < 120 ? " \u26a0" : "";
		el.textContent =
			`CO\u2082 Scrubbers: CRITICAL\nCrew time remaining: ${pad(minutes)}:${pad(seconds)}${urgency}`;
		el.style.color = remaining < 120 ? "#ff2200" : "#ff6644";
	};

	return { element: el, update, getRemaining: () => remaining };
}

function createInteractionPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "planet-interact-prompt";
	Object.assign(el.style, {
		position: "fixed",
		bottom: "100px",
		left: "50%",
		transform: "translateX(-50%)",
		color: "#ffee88",
		fontFamily: "'Courier New', monospace",
		fontSize: "14px",
		textAlign: "center",
		textShadow: "0 0 8px #ffee8844",
		pointerEvents: "none",
		userSelect: "none",
		display: "none",
	});
	document.body.appendChild(el);
	return el;
}

function createCollectionHUD(total: number): {
	element: HTMLDivElement;
	setCollected: (n: number) => void;
} {
	const el = document.createElement("div");
	el.id = "collection-hud";
	Object.assign(el.style, {
		position: "fixed",
		bottom: "40px",
		left: "50%",
		transform: "translateX(-50%)",
		color: "#ffee88",
		fontFamily: "'Courier New', monospace",
		fontSize: "15px",
		textAlign: "center",
		textShadow: "0 0 10px #ffee8866",
		pointerEvents: "none",
		userSelect: "none",
	});
	el.textContent = `Calcium deposits: 0 / ${total}`;
	document.body.appendChild(el);

	const setCollected = (n: number): void => {
		el.textContent = `Calcium deposits: ${n} / ${total}`;
		el.style.color = n >= total ? "#44ff88" : "#ffee88";
	};

	return { element: el, setCollected };
}

// ─── Lighting ─────────────────────────────────────────────────────────────────

function buildLighting(scene: THREE.Scene): void {
	// Dim alien sun — far-off, warm but weak
	const sun = new THREE.DirectionalLight(COLOR_SUN, 1.8);
	sun.position.set(30, 60, -20);
	scene.add(sun);

	// Ambient fill from the sandy ground
	const ambient = new THREE.AmbientLight(0xd4a06a, 0.5);
	scene.add(ambient);

	// Fog — sandy haze
	scene.fog = new THREE.Fog(0xc8a05a, 40, 80);
}

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, player, renderer } = context;
	camera.rotation.order = "YXZ";
	const bus = scopedBus();

	// ─── Quest manager ─────────────────────────────────────────────────
	// Deserialise is not wired yet — create a fresh manager scoped to this scene.
	// The gate-room scene owns the canonical QuestManager; here we only need
	// to emit the resource:collected events that the canonical manager handles.
	// Scene-local manager is used purely to track find-lime progress display.
	const questManager = createQuestManager();
	registerAirCrisis(questManager);
	questManager.startQuest(AIR_CRISIS_QUEST_ID);
	// Pre-advance objectives already done in gate-room (speak, locate, gate-to)
	questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "speak-to-rush");
	questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "locate-planet");
	questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "gate-to-planet");

	// ─── World ─────────────────────────────────────────────────────────
	buildLighting(scene);
	buildRocks(scene);

	// Ground (from scene.runtime.json — inherits tan colour from manifest)
	// Additional sand scatter — small flat pebble meshes
	const pebbleMat = new THREE.MeshStandardMaterial({ color: 0xb09050, roughness: 1.0, metalness: 0.0 });
	for (let i = 0; i < 30; i++) {
		const pebble = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.08, 0.3), pebbleMat);
		pebble.position.set(
			(Math.random() - 0.5) * 50,
			0.04,
			(Math.random() - 0.5) * 50
		);
		pebble.rotation.y = Math.random() * Math.PI;
		scene.add(pebble);
	}

	// ─── Stargate (player arrived through it — already active) ──────────
	const gate = buildStargate(scene);

	// ─── Calcium deposits ───────────────────────────────────────────────
	const deposits = CALCIUM_POSITIONS.map((pos) => buildCalciumDeposit(scene, pos));
	let collectedCount = 0;
	const totalDeposits = deposits.length;

	// Deposit marker beams — faint vertical glow to help player locate them
	const beamMat = new THREE.MeshStandardMaterial({
		color: COLOR_CALCIUM_GLOW,
		emissive: COLOR_CALCIUM_GLOW,
		emissiveIntensity: 0.2,
		transparent: true,
		opacity: 0.15,
	});
	for (const dep of deposits) {
		const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.4, 15, 8, 1, true), beamMat);
		beam.position.copy(dep.position).add(new THREE.Vector3(0, 7.5, 0));
		scene.add(beam);
	}

	// ─── HUD ───────────────────────────────────────────────────────────
	// 8 hours remaining (cosmetic — not enforced, adds atmosphere)
	const co2Timer = createCO2Timer(8 * 60 * 60);
	const interactPrompt = createInteractionPrompt();
	const collectionHUD = createCollectionHUD(totalDeposits);

	const compassHud = createHud(renderer.domElement.parentElement ?? document.body);
	const compass = createCompass({ position: "top-right", style: "sci-fi" });
	compassHud.mount(compass);

	// ─── Proximity state ────────────────────────────────────────────────
	let nearestDeposit: CalciumDeposit | null = null;
	let nearGate = false;
	let gateElapsed = 0;

	const input = getInput();
	const tryInteract = (): void => {
		if (nearestDeposit && !nearestDeposit.collected) {
			markDepositCollected(nearestDeposit);
			collectedCount++;
			collectionHUD.setCollected(collectedCount);
			emit("resource:collected", {
				type: "calcium-deposit",
				amount: 1,
				source: "desert-planet",
			});
			questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "find-lime");
		} else if (nearGate) {
			// Guard: block return until all deposits are collected (BUG-002).
			if (collectedCount < totalDeposits) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent =
					`You need all ${totalDeposits} calcium deposits before returning. (${collectedCount}/${totalDeposits})`;
				return;
			}
			setLimeCollected(true);
			questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "return-to-destiny");
			void context.gotoScene("gate-room");
		}
	};

	// ─── Test hooks ──────────────────────────────────────────────────────
	(window as any).__sceneReady = true;
	(window as any).__sguBus = bus;

	return {
		update(delta: number) {
			gateElapsed += delta;

			if (input.isActionJustPressed(Action.Interact)) tryInteract();

			// Pulse event horizon
			const horizonMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;
			const pulse = Math.sin(gateElapsed * 2.0) * 0.05;
			horizonMat.opacity = 0.75 + pulse;
			horizonMat.emissiveIntensity = 0.8 + pulse * 2;
			gate.eventHorizon.rotation.z += delta * 0.15;

			// Pulse collection deposit glows
			for (const dep of deposits) {
				if (dep.collected) continue;
				const gMat = dep.glowMesh.material as THREE.MeshStandardMaterial;
				gMat.emissiveIntensity = 0.4 + Math.sin(gateElapsed * 3 + dep.position.x) * 0.2;
			}

			// CO2 timer tick
			co2Timer.update(delta);

			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			compassHud.update(camera as any, delta);

			if (!player) return;
			const pp = player.object.position;

			// Find nearest uncollected deposit
			nearestDeposit = null;
			nearGate = false;
			let nearestDist = COLLECT_RADIUS;

			for (const dep of deposits) {
				if (dep.collected) continue;
				const dist = dep.position.distanceTo(pp);
				if (dist < nearestDist) {
					nearestDeposit = dep;
					nearestDist = dist;
				}
			}

			// Check gate proximity (XZ only)
			const gateXZDist = Math.sqrt(
				(pp.x - GATE_CENTER.x) ** 2 + (pp.z - GATE_CENTER.z) ** 2
			);
			if (gateXZDist < 2.0) {
				nearGate = true;
			}

			// Update prompt
			if (nearestDeposit) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = "[E] Collect calcium deposit";
			} else if (nearGate && collectedCount >= totalDeposits) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = "[E] Return through the Stargate to Destiny";
			} else if (nearGate) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = `Collect all ${totalDeposits} deposits before returning`;
			} else {
				interactPrompt.style.display = "none";
			}
		},

		dispose() {
			co2Timer.element.remove();
			interactPrompt.remove();
			collectionHUD.element.remove();
			compassHud.unmount(compass);
			compassHud.dispose();
			questManager.dispose();
			bus.cleanup();
			// BUG-003: dispose all GPU geometry + material objects to prevent VRAM leaks.
			// Traversing the scene is safer than maintaining a manual list because it
			// catches everything added via helper functions (buildRocks, buildStargate, etc.).
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
		},
	};
}

// ─── Scene definition ──────────────────────────────────────────────────────────

export const desertPlanetScene = defineGameScene({
	id: "desert-planet",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () =>
			import("./scene.runtime.json?raw").then((module) => module.default),
	}),
	title: "Desert Planet",
	player: {
		vrmUrl: "https://pub-c642ba55d4f641de916d72786545c520.r2.dev/characters/eli.vrm",
	},
	mount,
});
