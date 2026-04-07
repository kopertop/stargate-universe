/**
 * Destiny Corridor Scene — Sprint 1 playable exploration loop.
 *
 * Three connected spaces: Gate Room entrance → Main Corridor → Storage Room.
 * Ship State drives lighting. Subsystems are repairable. Doors respond to power.
 *
 * @see design/gdd/ship-exploration.md
 * @see design/gdd/ship-atmosphere-lighting.md
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { ShipState, type Section, type Subsystem, SHIP_STATE_CONFIG } from "../../systems/ship-state";
import { emit, on, scopedBus } from "../../systems/event-bus";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url"
}) as Record<string, () => Promise<string>>;

// ─── Constants ───────────────────────────────────────────────────────────────

const ROOM_HEIGHT = 5;
const WALL_COLOR = 0x12121f;
const CORRIDOR_WIDTH = 4;
const ANCIENT_GLOW_COLOR = 0x44ddcc;
const EMERGENCY_COLOR = 0xff2200;
const ANCIENT_GLOW_THRESHOLD = 0.6;

// ─── Room Layout ─────────────────────────────────────────────────────────────
// Gate Room (south) → Corridor (center) → Storage Room (north)

interface RoomDef {
	id: string;
	label: string;
	x: number;
	z: number;
	width: number;
	depth: number;
}

const ROOMS: RoomDef[] = [
	{ id: "gate-room", label: "Gate Room", x: 0, z: 8, width: 10, depth: 8 },
	{ id: "corridor-a1", label: "Corridor A-1", x: 0, z: 0, width: CORRIDOR_WIDTH, depth: 8 },
	{ id: "storage-bay", label: "Storage Bay", x: 0, z: -8, width: 8, depth: 8 },
];

// ─── Room geometry builder ───────────────────────────────────────────────────

interface RoomVisuals {
	walls: THREE.Mesh[];
	ceiling: THREE.Mesh;
	lights: THREE.PointLight[];
	ancientGlowPanels: THREE.Mesh[];
	emergencyStrips: THREE.Mesh[];
}

function buildRoomGeometry(room: RoomDef, scene: THREE.Scene): RoomVisuals {
	const hw = room.width / 2;
	const hd = room.depth / 2;
	const wallMat = new THREE.MeshStandardMaterial({
		color: WALL_COLOR, roughness: 0.95, metalness: 0.05, side: THREE.DoubleSide,
		transparent: true, opacity: 1.0
	});
	const ceilingMat = new THREE.MeshStandardMaterial({
		color: 0x0e0e18, roughness: 0.98, metalness: 0.02, side: THREE.DoubleSide
	});

	const walls: THREE.Mesh[] = [];

	// Back wall
	const backWall = new THREE.Mesh(new THREE.BoxGeometry(room.width, ROOM_HEIGHT, 0.3), wallMat.clone());
	backWall.position.set(room.x, ROOM_HEIGHT / 2, room.z - hd);
	scene.add(backWall);
	walls.push(backWall);

	// Front wall (with doorway gap in center)
	for (const side of [-1, 1]) {
		const sideWidth = (room.width - CORRIDOR_WIDTH) / 2;
		if (sideWidth <= 0) continue;
		const wallPiece = new THREE.Mesh(
			new THREE.BoxGeometry(sideWidth, ROOM_HEIGHT, 0.3), wallMat.clone()
		);
		wallPiece.position.set(
			room.x + side * (CORRIDOR_WIDTH / 2 + sideWidth / 2),
			ROOM_HEIGHT / 2,
			room.z + hd
		);
		scene.add(wallPiece);
		walls.push(wallPiece);
	}

	// Side walls
	for (const side of [-1, 1]) {
		const sideWall = new THREE.Mesh(
			new THREE.BoxGeometry(0.3, ROOM_HEIGHT, room.depth), wallMat.clone()
		);
		sideWall.position.set(room.x + side * hw, ROOM_HEIGHT / 2, room.z);
		scene.add(sideWall);
		walls.push(sideWall);
	}

	// Ceiling
	const ceiling = new THREE.Mesh(
		new THREE.BoxGeometry(room.width, 0.3, room.depth), ceilingMat
	);
	ceiling.position.set(room.x, ROOM_HEIGHT, room.z);
	scene.add(ceiling);

	// Overhead light (dynamic — intensity driven by ship state)
	const overheadLight = new THREE.PointLight(0xffeedd, 1.0, room.width * 2, 2);
	overheadLight.position.set(room.x, ROOM_HEIGHT - 0.5, room.z);
	scene.add(overheadLight);

	// Ancient glow panels on walls (emissive — driven by power level)
	const ancientGlowPanels: THREE.Mesh[] = [];
	const glowMat = new THREE.MeshStandardMaterial({
		color: ANCIENT_GLOW_COLOR,
		emissive: ANCIENT_GLOW_COLOR,
		emissiveIntensity: 0,
	});
	for (const side of [-1, 1]) {
		const panel = new THREE.Mesh(
			new THREE.BoxGeometry(0.05, 0.8, room.depth * 0.6),
			glowMat.clone()
		);
		panel.position.set(room.x + side * (hw - 0.2), ROOM_HEIGHT * 0.6, room.z);
		scene.add(panel);
		ancientGlowPanels.push(panel);
	}

	// Emergency floor strips (always present, intensity driven by state)
	const emergencyStrips: THREE.Mesh[] = [];
	const emergencyMat = new THREE.MeshStandardMaterial({
		color: EMERGENCY_COLOR,
		emissive: EMERGENCY_COLOR,
		emissiveIntensity: 0,
	});
	for (const side of [-1, 1]) {
		const strip = new THREE.Mesh(
			new THREE.BoxGeometry(0.08, 0.05, room.depth - 0.5),
			emergencyMat.clone()
		);
		strip.position.set(room.x + side * (hw - 0.3), 0.03, room.z);
		scene.add(strip);
		emergencyStrips.push(strip);
	}

	return { walls, ceiling, lights: [overheadLight], ancientGlowPanels, emergencyStrips };
}

// ─── Subsystem visual markers ────────────────────────────────────────────────

interface SubsystemVisual {
	subsystemId: string;
	mesh: THREE.Mesh;
	glowMesh: THREE.Mesh;
}

function createSubsystemVisual(
	sub: Subsystem, scene: THREE.Scene, position: THREE.Vector3
): SubsystemVisual {
	// Box representing the subsystem (conduit, console, etc.)
	const bodyColor = sub.condition > 0.5 ? 0x333348 : sub.condition > 0 ? 0x442222 : 0x220000;
	const bodyMat = new THREE.MeshStandardMaterial({
		color: bodyColor, roughness: 0.5, metalness: 0.6
	});
	const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.8, 0.3), bodyMat);
	mesh.position.copy(position);
	mesh.userData = { subsystemId: sub.id, interactable: true };
	scene.add(mesh);

	// Glow indicator (green = healthy, amber = degraded, red = broken)
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0x44ff88,
		emissive: 0x44ff88,
		emissiveIntensity: 0.5,
	});
	const glowMesh = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.1, 0.05), glowMat);
	glowMesh.position.set(position.x, position.y + 0.5, position.z + 0.18);
	scene.add(glowMesh);

	return { subsystemId: sub.id, mesh, glowMesh };
}

function updateSubsystemVisual(visual: SubsystemVisual, sub: Subsystem): void {
	const glowMat = visual.glowMesh.material as THREE.MeshStandardMaterial;
	const bodyMat = visual.mesh.material as THREE.MeshStandardMaterial;

	if (sub.condition >= 0.8) {
		glowMat.color.set(0x44ff88);
		glowMat.emissive.set(0x44ff88);
		glowMat.emissiveIntensity = 0.8;
		bodyMat.color.set(0x333348);
	} else if (sub.condition >= 0.5) {
		glowMat.color.set(0x44ff88);
		glowMat.emissive.set(0x44ff88);
		glowMat.emissiveIntensity = 0.4;
		bodyMat.color.set(0x333348);
	} else if (sub.condition > 0) {
		glowMat.color.set(0xffaa44);
		glowMat.emissive.set(0xffaa44);
		glowMat.emissiveIntensity = 0.6;
		bodyMat.color.set(0x442222);
	} else {
		glowMat.color.set(0xff2200);
		glowMat.emissive.set(0xff2200);
		glowMat.emissiveIntensity = 0.3;
		bodyMat.color.set(0x220000);
	}
}

// ─── Atmosphere visuals (S1-04) ──────────────────────────────────────────────

function updateRoomAtmosphere(room: RoomDef, visuals: RoomVisuals, section: Section): void {
	const power = section.powerLevel;

	// Overhead light intensity scales with power
	for (const light of visuals.lights) {
		const targetIntensity = power * 2.0;
		light.intensity += (targetIntensity - light.intensity) * 0.1;

		// Color blends from emergency red (low power) to warm white (full power)
		const r = 1.0;
		const g = 0.5 + power * 0.5;
		const b = 0.3 + power * 0.6;
		light.color.setRGB(r, g, b);
	}

	// Ancient glow panels — activate above threshold
	const glowIntensity = power > ANCIENT_GLOW_THRESHOLD
		? ((power - ANCIENT_GLOW_THRESHOLD) / (1.0 - ANCIENT_GLOW_THRESHOLD)) * 0.8
		: 0;
	for (const panel of visuals.ancientGlowPanels) {
		const mat = panel.material as THREE.MeshStandardMaterial;
		mat.emissiveIntensity += (glowIntensity - mat.emissiveIntensity) * 0.1;
	}

	// Emergency strips — activate below 0.3 power
	const emergencyIntensity = power < 0.3 ? (1 - power / 0.3) * 0.6 : 0;
	for (const strip of visuals.emergencyStrips) {
		const mat = strip.material as THREE.MeshStandardMaterial;
		mat.emissiveIntensity += (emergencyIntensity - mat.emissiveIntensity) * 0.1;
	}
}

// ─── Debug overlay ───────────────────────────────────────────────────────────

function createShipStateDebugOverlay(shipState: ShipState): { element: HTMLDivElement; update: () => void } {
	const el = document.createElement("div");
	el.id = "ship-state-debug";
	Object.assign(el.style, {
		position: "fixed",
		top: "8px",
		right: "8px",
		color: "#44ddcc",
		fontFamily: "'Courier New', monospace",
		fontSize: "11px",
		lineHeight: "1.5",
		background: "rgba(0, 0, 0, 0.7)",
		padding: "8px 12px",
		borderRadius: "4px",
		pointerEvents: "none",
		userSelect: "none",
		zIndex: "999",
		minWidth: "220px",
		whiteSpace: "pre",
		display: "none"
	});
	document.body.appendChild(el);

	let frame = 0;
	const update = () => {
		frame++;
		if (frame % 15 !== 0) return;

		const lines: string[] = ["=== SHIP STATE ==="];
		const systems = shipState.getAllSystems();
		for (const sys of systems) {
			const bar = "█".repeat(Math.round(sys.condition * 10)) + "░".repeat(10 - Math.round(sys.condition * 10));
			const powered = sys.powered ? "⚡" : "  ";
			lines.push(`${powered} ${sys.id.padEnd(16)} ${bar} ${(sys.condition * 100).toFixed(0)}%`);
		}

		lines.push("");
		lines.push("=== SECTIONS ===");
		const sections = shipState.getAllSections();
		for (const sec of sections) {
			const pwr = `P:${(sec.powerLevel * 100).toFixed(0)}%`;
			const atm = `A:${(sec.atmosphere * 100).toFixed(0)}%`;
			lines.push(`${sec.id.padEnd(16)} ${pwr} ${atm} [${sec.accessState}]`);
		}

		lines.push("");
		lines.push("=== SUBSYSTEMS ===");
		for (const sec of sections) {
			const subs = shipState.getSubsystemsInSection(sec.id);
			for (const sub of subs) {
				const cond = `${(sub.condition * 100).toFixed(0)}%`;
				lines.push(`  ${sub.id.padEnd(22)} ${sub.type.padEnd(14)} ${cond}`);
			}
		}

		el.textContent = lines.join("\n");
	};

	return { element: el, update };
}

// ─── Interaction system (S1-05) ──────────────────────────────────────────────

interface InteractionState {
	nearestSubsystem: SubsystemVisual | null;
	promptElement: HTMLDivElement;
}

function createInteractionPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "interaction-prompt";
	Object.assign(el.style, {
		position: "fixed",
		bottom: "120px",
		left: "50%",
		transform: "translateX(-50%)",
		color: "#44ddcc",
		fontFamily: "'Courier New', monospace",
		fontSize: "14px",
		textAlign: "center",
		textShadow: "0 0 8px #44ddcc44",
		pointerEvents: "none",
		userSelect: "none",
		display: "none"
	});
	document.body.appendChild(el);
	return el;
}

function updateInteraction(
	state: InteractionState,
	subsystemVisuals: SubsystemVisual[],
	playerPos: THREE.Vector3,
	shipState: ShipState
): void {
	const INTERACT_RANGE = 2.5;
	let nearest: SubsystemVisual | null = null;
	let nearestDist = Infinity;

	for (const sv of subsystemVisuals) {
		const dist = sv.mesh.position.distanceTo(playerPos);
		if (dist < INTERACT_RANGE && dist < nearestDist) {
			nearest = sv;
			nearestDist = dist;
		}
	}

	state.nearestSubsystem = nearest;

	if (nearest) {
		const sub = shipState.getSubsystem(nearest.subsystemId);
		if (sub && sub.condition < 1.0) {
			state.promptElement.style.display = "block";
			state.promptElement.textContent = `[E] Repair ${sub.type} (${(sub.condition * 100).toFixed(0)}% → ${(Math.min(1, sub.condition + SHIP_STATE_CONFIG.BASE_REPAIR_AMOUNT * SHIP_STATE_CONFIG.REPAIR_SKILL_MODIFIER) * 100).toFixed(0)}%)`;
		} else if (sub) {
			state.promptElement.style.display = "block";
			state.promptElement.textContent = `${sub.type} — Optimal condition`;
		} else {
			state.promptElement.style.display = "none";
		}
	} else {
		state.promptElement.style.display = "none";
	}
}

// ─── Scene mount ─────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, player, renderer } = context;
	const bus = scopedBus();

	// Initialize Ship State with our 3 rooms
	const shipState = new ShipState();
	shipState.init();

	// Register sections
	const sectionDefs: Section[] = ROOMS.map(room => ({
		id: room.id,
		discovered: room.id === "gate-room", // start in gate room
		accessible: true,
		atmosphere: 0.8,
		powerLevel: 0.4,
		structuralIntegrity: 0.9,
		accessState: room.id === "gate-room" ? "explored" as const : "unexplored" as const,
		subsystems: [],
	}));

	for (const sec of sectionDefs) {
		shipState.addSection(sec);
	}

	// Register subsystems
	const subsystemDefs: Array<Subsystem & { position: THREE.Vector3 }> = [
		// Gate room — lighting panel (working)
		{
			id: "gate-room-lights", type: "lighting-panel", sectionId: "gate-room",
			condition: 0.7, repairCost: 3, functionalThreshold: 0.2,
			position: new THREE.Vector3(-4, 1.5, 9),
		},
		// Corridor — power conduit (damaged)
		{
			id: "corridor-conduit-1", type: "conduit", sectionId: "corridor-a1",
			condition: 0.25, repairCost: 5, functionalThreshold: 0.2,
			position: new THREE.Vector3(1.5, 1.5, 0),
		},
		// Storage bay — lighting panel (broken)
		{
			id: "storage-lights", type: "lighting-panel", sectionId: "storage-bay",
			condition: 0.1, repairCost: 3, functionalThreshold: 0.2,
			position: new THREE.Vector3(3, 1.5, -8),
		},
		// Storage bay — console (damaged)
		{
			id: "storage-console", type: "console", sectionId: "storage-bay",
			condition: 0.35, repairCost: 5, functionalThreshold: 0.2,
			position: new THREE.Vector3(-3, 1.2, -10),
		},
	];

	for (const sub of subsystemDefs) {
		shipState.addSubsystem(sub);
	}

	// Set initial power — the corridor conduit affects storage bay power
	shipState.distributePower();

	// Build room geometry
	const roomVisualsMap = new Map<string, RoomVisuals>();
	for (const room of ROOMS) {
		const visuals = buildRoomGeometry(room, scene);
		roomVisualsMap.set(room.id, visuals);
	}

	// Build subsystem visuals
	const subsystemVisuals: SubsystemVisual[] = [];
	for (const sub of subsystemDefs) {
		const visual = createSubsystemVisual(sub, scene, sub.position);
		subsystemVisuals.push(visual);
	}

	// Debug overlay
	const debug = createShipStateDebugOverlay(shipState);
	let debugMode = false;
	let lastBackquoteTime = 0;

	// Interaction state
	const interaction: InteractionState = {
		nearestSubsystem: null,
		promptElement: createInteractionPrompt(),
	};

	// Disable shadows for performance
	renderer.shadowMap.enabled = false;

	// Key handlers
	const handleKeyDown = (e: KeyboardEvent) => {
		if (e.code === "Backquote") {
			const now = performance.now();
			if (now - lastBackquoteTime < 400) {
				debugMode = !debugMode;
				debug.element.style.display = debugMode ? "block" : "none";
				lastBackquoteTime = 0;
			} else {
				lastBackquoteTime = now;
			}
			return;
		}

		if (e.code === "KeyE" && interaction.nearestSubsystem) {
			const sub = shipState.getSubsystem(interaction.nearestSubsystem.subsystemId);
			if (sub && sub.condition < 1.0) {
				const result = shipState.repairSubsystem(sub.id);
				if (result.success) {
					console.log(`Repaired ${sub.id}: +${(result.conditionRestored * 100).toFixed(0)}% → ${(sub.condition * 100).toFixed(0)}%`);
				}
			}
		}
	};
	window.addEventListener("keydown", handleKeyDown);

	// Track which section the player is in
	let currentSection = "gate-room";

	return {
		update(delta: number) {
			// Update atmosphere visuals for each room
			for (const room of ROOMS) {
				const section = shipState.getSection(room.id);
				const visuals = roomVisualsMap.get(room.id);
				if (section && visuals) {
					updateRoomAtmosphere(room, visuals, section);
				}
			}

			// Update subsystem visuals
			for (const sv of subsystemVisuals) {
				const sub = shipState.getSubsystem(sv.subsystemId);
				if (sub) updateSubsystemVisual(sv, sub);
			}

			// Check player section (simple z-based)
			if (player) {
				const pz = player.object.position.z;
				let newSection = "gate-room";
				if (pz < -4) newSection = "storage-bay";
				else if (pz < 4) newSection = "corridor-a1";

				if (newSection !== currentSection) {
					currentSection = newSection;
					emit("player:entered:section", { sectionId: newSection });
				}

				// Update interaction prompt
				updateInteraction(interaction, subsystemVisuals, player.object.position, shipState);
			}

			// Debug overlay
			if (debugMode) debug.update();
		},
		dispose() {
			window.removeEventListener("keydown", handleKeyDown);
			debug.element.remove();
			interaction.promptElement.remove();
			shipState.dispose();
			bus.cleanup();
		}
	};
}

// ─── Scene definition ────────────────────────────────────────────────────────

export const destinyCorridorScene = defineGameScene({
	id: "destiny-corridor",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((module) => module.default)
	}),
	title: "Destiny Corridor",
	player: {
		vrmUrl: "/characters/avatar-sample-a.vrm",
	},
	mount
});
