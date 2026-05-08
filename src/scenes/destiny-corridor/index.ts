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
import { emit, scopedBus } from "../../systems/event-bus";
import { Action, SguAction, getInput } from "../../systems/input";
import { addResource, consumeResource, getResource, hasResource, initResources } from "../../systems/resources";
import { createSupplyCrate, markSupplyCrateLooted, type SupplyCrate } from "../../systems/supply-crates";
import { box } from "crashcat";
import {
	CRASHCAT_OBJECT_LAYER_STATIC,
	MotionType,
	rigidBody,
	type CrashcatPhysicsWorld,
	type CrashcatRigidBody,
} from "@ggez/runtime-physics-crashcat";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url"
}) as Record<string, () => Promise<string>>;

// ─── Constants ───────────────────────────────────────────────────────────────

const ROOM_HEIGHT = 5;
const WALL_COLOR = 0x12121f;
const CORRIDOR_WIDTH = 4;
const ANCIENT_GLOW_COLOR = 0xffaa55;
const EMERGENCY_COLOR = 0xff2200;
const EMERGENCY_BASE_COLOR = 0x180604;
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

type StaticCollider = CrashcatRigidBody;

// Build a panelled-metal wall texture once and reuse across all room walls.
// Horizontal seam lines + a few vertical rib columns give the dark indigo
// surface a sense of fabrication scale at grazing-angle corridor views.
// MeshBasicMaterial keeps darks dark at exposure 3.9 (memory: feedback_large_flat_surfaces_basic_material).
function buildCorridorWallTexture(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 256;
	canvas.height = 256;
	const ctx = canvas.getContext("2d")!;
	// Base — slightly varied dark indigo so it doesn't read as a flat fill
	const base = ctx.createLinearGradient(0, 0, 0, 256);
	base.addColorStop(0, "#16161f");
	base.addColorStop(0.5, "#10101a");
	base.addColorStop(1, "#0c0c14");
	ctx.fillStyle = base;
	ctx.fillRect(0, 0, 256, 256);
	// Horizontal seam lines (panel divisions at human-scale heights)
	ctx.strokeStyle = "rgba(28, 28, 44, 0.9)";
	ctx.lineWidth = 1;
	for (const y of [42, 128, 214]) {
		ctx.beginPath();
		ctx.moveTo(0, y);
		ctx.lineTo(256, y);
		ctx.stroke();
	}
	// Tiny lower-edge highlight on each seam to suggest a recess shadow + rim
	ctx.strokeStyle = "rgba(60, 60, 84, 0.45)";
	for (const y of [43, 129, 215]) {
		ctx.beginPath();
		ctx.moveTo(0, y);
		ctx.lineTo(256, y);
		ctx.stroke();
	}
	// Vertical rib columns at quarter intervals
	ctx.strokeStyle = "rgba(36, 36, 52, 0.7)";
	for (const x of [64, 128, 192]) {
		ctx.beginPath();
		ctx.moveTo(x, 0);
		ctx.lineTo(x, 256);
		ctx.stroke();
	}
	// Subtle warm horizontal strip across the panel midline (Ancient cabling
	// glow) — very dim so it reads as ambient warmth, not a UI element
	ctx.fillStyle = "rgba(120, 80, 40, 0.18)";
	ctx.fillRect(0, 124, 256, 2);
	const tex = new THREE.CanvasTexture(canvas);
	tex.wrapS = THREE.RepeatWrapping;
	tex.wrapT = THREE.RepeatWrapping;
	tex.colorSpace = THREE.SRGBColorSpace;
	return tex;
}

function buildRoomGeometry(room: RoomDef, scene: THREE.Scene): RoomVisuals {
	const hw = room.width / 2;
	const hd = room.depth / 2;
	const wallTex = buildCorridorWallTexture();
	wallTex.repeat.set(room.width / 4, ROOM_HEIGHT / 4);
	const wallMat = new THREE.MeshBasicMaterial({
		map: wallTex, side: THREE.DoubleSide, fog: true,
	});
	const ceilingMat = new THREE.MeshStandardMaterial({
		color: 0x0e0e18, roughness: 0.98, metalness: 0.02, side: THREE.DoubleSide,
		emissive: 0x141422, emissiveIntensity: 0.5,
	});
	// Floor texture — dark navy with subtle panel grid so the floor doesn't
	// read as a pitch-black void. Grid anchors the perspective vanishing
	// point looking down the hallway. CanvasTexture (no ShaderMaterial under
	// WebGPU per project memory).
	const floorCanvas = document.createElement("canvas");
	floorCanvas.width = 256; floorCanvas.height = 256;
	const fctx = floorCanvas.getContext("2d")!;
	fctx.fillStyle = "#12141c";
	fctx.fillRect(0, 0, 256, 256);
	fctx.strokeStyle = "rgba(40, 45, 65, 0.55)";
	fctx.lineWidth = 1;
	// Single panel seam — thin tile divider, not a Tron-style mesh grid.
	for (const t of [0, 256]) {
		fctx.beginPath(); fctx.moveTo(t, 0); fctx.lineTo(t, 256); fctx.stroke();
		fctx.beginPath(); fctx.moveTo(0, t); fctx.lineTo(256, t); fctx.stroke();
	}
	// Sub-panel divider — quarter the panel into four quadrants so the
	// vanishing-point grid reads at corridor walking distance, not just
	// at the room edges.
	fctx.strokeStyle = "rgba(35, 40, 58, 0.35)";
	fctx.beginPath(); fctx.moveTo(128, 0); fctx.lineTo(128, 256); fctx.stroke();
	fctx.beginPath(); fctx.moveTo(0, 128); fctx.lineTo(256, 128); fctx.stroke();
	// Bolt corners at panel intersections — small dots at the four corners
	// of each quadrant. Subtle industrial detail anchoring the grid.
	fctx.fillStyle = "rgba(60, 68, 95, 0.6)";
	for (const x of [4, 124, 132, 252]) {
		for (const y of [4, 124, 132, 252]) {
			fctx.fillRect(x, y, 2, 2);
		}
	}
	const floorTex = new THREE.CanvasTexture(floorCanvas);
	floorTex.wrapS = THREE.RepeatWrapping;
	floorTex.wrapT = THREE.RepeatWrapping;
	floorTex.repeat.set(room.width / 2, room.depth / 2);
	floorTex.colorSpace = THREE.SRGBColorSpace;
	const floorMat = new THREE.MeshBasicMaterial({ map: floorTex, fog: true });

	const walls: THREE.Mesh[] = [];

	// Floor — flat dark plane (MeshBasicMaterial so exposure 3.9 doesn't bleach it)
	const floor = new THREE.Mesh(
		new THREE.PlaneGeometry(room.width, room.depth),
		floorMat,
	);
	floor.rotation.x = -Math.PI / 2;
	floor.position.set(room.x, 0, room.z);
	scene.add(floor);

	// Back wall — split with doorway gap if another room is directly south
	// of this one, otherwise solid (terminus of the corridor chain).
	const hasSouthNeighbor = ROOMS.some(
		(r) => r.id !== room.id && Math.abs((r.z + r.depth / 2) - (room.z - hd)) < 0.01,
	);
	if (hasSouthNeighbor) {
		for (const side of [-1, 1]) {
			const sideWidth = (room.width - CORRIDOR_WIDTH) / 2;
			if (sideWidth <= 0) continue;
			const wallPiece = new THREE.Mesh(
				new THREE.BoxGeometry(sideWidth, ROOM_HEIGHT, 0.3), wallMat.clone()
			);
			wallPiece.position.set(
				room.x + side * (CORRIDOR_WIDTH / 2 + sideWidth / 2),
				ROOM_HEIGHT / 2,
				room.z - hd
			);
			scene.add(wallPiece);
			walls.push(wallPiece);
		}
	} else {
		const backWall = new THREE.Mesh(new THREE.BoxGeometry(room.width, ROOM_HEIGHT, 0.3), wallMat.clone());
		backWall.position.set(room.x, ROOM_HEIGHT / 2, room.z - hd);
		scene.add(backWall);
		walls.push(backWall);
	}

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

	// Ceiling fixtures + wall accents are emitted as InstancedMeshes in
	// buildInstancedFurniture() instead of per-room Meshes — collapses ~32
	// draw calls into 2.

	// Overhead light (dynamic — intensity driven by ship state)
	const overheadLight = new THREE.PointLight(0xffeedd, 1.0, room.width * 2, 2);
	overheadLight.position.set(room.x, ROOM_HEIGHT - 0.5, room.z);
	scene.add(overheadLight);

	// Ancient glow panels on walls (emissive — driven by power level)
	const ancientGlowPanels: THREE.Mesh[] = [];
	// Base colour kept dark; emissive drives the visible glow when ship has power.
	// Bright cyan base saturated to white-cyan blobs at exposure 3.9, dominating
	// the corridor silhouette even when emissive is 0 (off).
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0x101622,
		emissive: ANCIENT_GLOW_COLOR,
		emissiveIntensity: 0,
	});
	for (const side of [-1, 1]) {
		const panel = new THREE.Mesh(
			new THREE.BoxGeometry(0.05, 0.18, room.depth * 0.5),
			glowMat.clone()
		);
		panel.position.set(room.x + side * (hw - 0.2), ROOM_HEIGHT * 0.6, room.z);
		scene.add(panel);
		ancientGlowPanels.push(panel);
	}

	// Emergency floor strips (always present, intensity driven by state)
	const emergencyStrips: THREE.Mesh[] = [];
	const emergencyMat = new THREE.MeshStandardMaterial({
		color: EMERGENCY_BASE_COLOR,
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

function buildRoomColliders(world: CrashcatPhysicsWorld): StaticCollider[] {
	const wallThickness = 0.3;
	const colliders: StaticCollider[] = [];
	const addStaticBox = (
		halfExtents: [number, number, number],
		position: [number, number, number],
	) => {
		colliders.push(rigidBody.create(world, {
			motionType: MotionType.STATIC,
			objectLayer: CRASHCAT_OBJECT_LAYER_STATIC,
			shape: box.create({ halfExtents }),
			position,
		}));
	};

	for (const room of ROOMS) {
		const hw = room.width / 2;
		const hd = room.depth / 2;
		const sideWidth = (room.width - CORRIDOR_WIDTH) / 2;

		addStaticBox([hw, wallThickness / 2, hd], [room.x, -wallThickness / 2, room.z]);
		addStaticBox([hw, wallThickness / 2, hd], [room.x, ROOM_HEIGHT + wallThickness / 2, room.z]);
		addStaticBox(
			[wallThickness / 2, ROOM_HEIGHT / 2, hd],
			[room.x - hw - wallThickness / 2, ROOM_HEIGHT / 2, room.z],
		);
		addStaticBox(
			[wallThickness / 2, ROOM_HEIGHT / 2, hd],
			[room.x + hw + wallThickness / 2, ROOM_HEIGHT / 2, room.z],
		);

		const hasNorthNeighbor = ROOMS.some(
			(r) => r.id !== room.id && Math.abs((r.z + r.depth / 2) - (room.z - hd)) < 0.01,
		);
		const addSplitWall = (z: number) => {
			if (sideWidth <= 0) return;
			for (const side of [-1, 1] as const) {
				addStaticBox(
					[sideWidth / 2, ROOM_HEIGHT / 2, wallThickness / 2],
					[
						room.x + side * (CORRIDOR_WIDTH / 2 + sideWidth / 2),
						ROOM_HEIGHT / 2,
						z,
					],
				);
			}
		};

		if (hasNorthNeighbor) {
			addSplitWall(room.z - hd - wallThickness / 2);
		} else {
			addStaticBox(
				[hw, ROOM_HEIGHT / 2, wallThickness / 2],
				[room.x, ROOM_HEIGHT / 2, room.z - hd - wallThickness / 2],
			);
		}

		addSplitWall(room.z + hd + wallThickness / 2);
	}

	return colliders;
}

// ─── Instanced furniture (S4-05) ─────────────────────────────────────────────
// Ceiling light fixtures and wall accent strips repeat across every room with
// identical geometry and material. Each room previously spawned ~10 individual
// Meshes for these — multiplied by 3 rooms that's ~32 extra draw calls every
// frame. One InstancedMesh per type collapses that to two draw calls regardless
// of room count.

function buildInstancedFurniture(scene: THREE.Scene): THREE.InstancedMesh[] {
	const fixtureMat = new THREE.MeshBasicMaterial({ color: 0xb89968, fog: true });
	const accentMat = new THREE.MeshBasicMaterial({ color: 0xa07840, fog: true });
	const fixtureGeo = new THREE.BoxGeometry(0.35, 0.05, 0.7);
	const accentGeo = new THREE.BoxGeometry(0.05, ROOM_HEIGHT * 0.5, 0.15);

	const fixtureXforms: THREE.Matrix4[] = [];
	const accentXforms: THREE.Matrix4[] = [];
	const tmp = new THREE.Matrix4();

	for (const room of ROOMS) {
		const hw = room.width / 2;
		const hd = room.depth / 2;
		const fixtureCount = Math.max(2, Math.floor(room.depth / 2.5));
		for (let i = 0; i < fixtureCount; i++) {
			const t = (i + 0.5) / fixtureCount;
			const fz = room.z - hd + t * room.depth;
			fixtureXforms.push(tmp.clone().setPosition(room.x, ROOM_HEIGHT - 0.18, fz));
		}
		const accentCount = Math.max(2, Math.floor(room.depth / 2));
		for (let i = 0; i < accentCount; i++) {
			const t = (i + 0.5) / accentCount;
			const az = room.z - hd + t * room.depth;
			for (const side of [-1, 1]) {
				accentXforms.push(
					tmp.clone().setPosition(room.x + side * (hw - 0.18), ROOM_HEIGHT * 0.45, az),
				);
			}
		}
	}

	const fixtures = new THREE.InstancedMesh(fixtureGeo, fixtureMat, fixtureXforms.length);
	fixtures.frustumCulled = false; // tiny meshes scattered across the level — bbox test cost > savings
	for (let i = 0; i < fixtureXforms.length; i++) fixtures.setMatrixAt(i, fixtureXforms[i]);
	fixtures.instanceMatrix.needsUpdate = true;
	scene.add(fixtures);

	const accents = new THREE.InstancedMesh(accentGeo, accentMat, accentXforms.length);
	accents.frustumCulled = false;
	for (let i = 0; i < accentXforms.length; i++) accents.setMatrixAt(i, accentXforms[i]);
	accents.instanceMatrix.needsUpdate = true;
	scene.add(accents);

	return [fixtures, accents];
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
	// Degraded state was reading as flat plywood brown (0x442222) — re-tune
	// to industrial dark gray (matching healthy panels) with the *condition*
	// signaled exclusively by the emissive tint on the warning strip below.
	const bodyColor = sub.condition > 0 ? 0x2a2e3c : 0x1a1620;
	// Faint emissive lift so the panel body reads at the corridor's high
	// exposure even without a direct PointLight on it. Without this, the
	// MeshStandardMaterial body collapses to pure black against the unlit
	// MeshBasicMaterial walls. (memory: feedback_dark_surfaces_at_high_exposure)
	const emissiveColor = sub.condition > 0.5 ? 0x1a1a26 : sub.condition > 0 ? 0x261313 : 0x140404;
	const bodyMat = new THREE.MeshStandardMaterial({
		color: bodyColor, roughness: 0.5, metalness: 0.6,
		emissive: emissiveColor, emissiveIntensity: 0.6,
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
		? ((power - ANCIENT_GLOW_THRESHOLD) / (1.0 - ANCIENT_GLOW_THRESHOLD)) * 0.35
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

/** Duration in seconds per repair segment (one segment = one part consumed). */
const SECONDS_PER_REPAIR_PART = 1.0;

interface InteractionState {
	nearestSubsystem: SubsystemVisual | null;
	nearestCrate: SupplyCrate | null;
	promptElement: HTMLDivElement;
	/** Subsystem currently being repaired (null if not repairing). */
	repairingSubsystemId: string | null;
	/** Total repair duration for the current subsystem (seconds). */
	repairDuration: number;
	/** Elapsed time holding E on the current repair (seconds). */
	repairElapsed: number;
}

function createInteractionPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "interact-prompt";
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
	crates: SupplyCrate[],
	playerPos: THREE.Vector3,
	shipState: ShipState
): void {
	const INTERACT_RANGE = 2.5;
	let nearestSubsystem: SubsystemVisual | null = null;
	let nearestCrate: SupplyCrate | null = null;
	let nearestDist = Infinity;

	for (const crate of crates) {
		if (crate.looted) continue;
		const dist = crate.position.distanceTo(playerPos);
		if (dist < INTERACT_RANGE && dist < nearestDist) {
			nearestCrate = crate;
			nearestSubsystem = null;
			nearestDist = dist;
		}
	}

	for (const sv of subsystemVisuals) {
		const dist = sv.mesh.position.distanceTo(playerPos);
		if (dist < INTERACT_RANGE && dist < nearestDist) {
			nearestSubsystem = sv;
			nearestCrate = null;
			nearestDist = dist;
		}
	}

	state.nearestSubsystem = nearestSubsystem;
	state.nearestCrate = nearestCrate;

	if (state.repairingSubsystemId) {
		// Segmented progress bar — one segment per repair part
		const sub = shipState.getSubsystem(state.repairingSubsystemId);
		const parts = sub?.repairCost ?? SHIP_STATE_CONFIG.REPAIR_COST_SHIP_PARTS;
		const pct = Math.min(1, state.repairElapsed / state.repairDuration);
		const filledParts = Math.floor(pct * parts);
		const partialFill = (pct * parts) - filledParts;

		let bar = "";
		for (let i = 0; i < parts; i++) {
			if (i < filledParts) {
				bar += "◆";
			} else if (i === filledParts && pct < 1) {
				bar += partialFill > 0.5 ? "◇" : "·";
			} else {
				bar += "·";
			}
			if (i < parts - 1) bar += " ";
		}

		state.promptElement.style.display = "block";
		state.promptElement.textContent = `Repairing... [ ${bar} ] ${filledParts}/${parts} parts`;
	} else if (nearestCrate) {
		state.promptElement.style.display = "block";
		state.promptElement.textContent = `[E] Open crate (+${nearestCrate.contents} Ship Parts)`;
	} else if (nearestSubsystem) {
		const sub = shipState.getSubsystem(nearestSubsystem.subsystemId);
		if (sub && sub.condition < 1.0) {
			const parts = getResource("ship-parts");
			state.promptElement.style.display = "block";
			state.promptElement.textContent = parts >= sub.repairCost
				? `[Hold E] Repair ${sub.type} — ${sub.repairCost} Ship Parts (${(sub.condition * 100).toFixed(0)}%)`
				: `Repair ${sub.type} — Need ${sub.repairCost} Ship Parts (have ${parts})`;
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

	// Photo-mode override: when capturing screenshots for visual audit,
	// force full power so emergency lighting wash clears and architecture
	// is visible. URL flag ?photo=1 is set by scripts/capture-screenshots.ts.
	const photoMode = typeof window !== "undefined"
		&& new URLSearchParams(window.location.search).get("photo") === "1";

	// Register sections
	const sectionDefs: Section[] = ROOMS.map(room => ({
		id: room.id,
		discovered: room.id === "gate-room", // start in gate room
		accessible: true,
		atmosphere: 0.8,
		powerLevel: photoMode ? 1.0 : 0.4,
		structuralIntegrity: 0.9,
		accessState: photoMode || room.id === "gate-room" ? "explored" as const : "unexplored" as const,
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

	// Photo-mode override: force all sections to full power AFTER distribution,
	// since distributePower recomputes from subsystem condition (which is
	// intentionally degraded for E1 emergency-state gameplay).
	if (photoMode) {
		for (const sec of shipState.getAllSections()) {
			sec.powerLevel = 1.0;
			sec.atmosphere = 1.0;
		}
		// Cool, restrained fill so the SGU corridor mood reads (dim Ancient ship
		// metal, not bright daylit office). Point lights still drive the
		// dramatic ceiling-fixture pools; ambient just keeps walls from black-out.
		scene.add(new THREE.AmbientLight(0x202838, 0.55));
		scene.add(new THREE.HemisphereLight(0x303848, 0x080810, 0.35));
	}

	// Build room geometry
	const roomVisualsMap = new Map<string, RoomVisuals>();
	for (const room of ROOMS) {
		const visuals = buildRoomGeometry(room, scene);
		roomVisualsMap.set(room.id, visuals);
	}
	const roomColliders = buildRoomColliders(context.physicsWorld);
	// Batch repeating fixture+accent furniture into two InstancedMesh draws.
	buildInstancedFurniture(scene);

	// Build subsystem visuals
	const subsystemVisuals: SubsystemVisual[] = [];
	for (const sub of subsystemDefs) {
		const visual = createSubsystemVisual(sub, scene, sub.position);
		subsystemVisuals.push(visual);
	}

	initResources();
	const crates: SupplyCrate[] = [
		createSupplyCrate(scene, new THREE.Vector3(-2.6, 0, -6.6), 6),
		createSupplyCrate(scene, new THREE.Vector3(2.6, 0, -8.4), 8),
		createSupplyCrate(scene, new THREE.Vector3(-1.0, 0, -10.2), 5),
	];

	// Debug overlay
	const debug = createShipStateDebugOverlay(shipState);
	let debugMode = false;
	let lastBackquoteTime = 0;

	// Interaction state
	const interaction: InteractionState = {
		nearestSubsystem: null,
		nearestCrate: null,
		promptElement: createInteractionPrompt(),
		repairingSubsystemId: null,
		repairDuration: 0,
		repairElapsed: 0,
	};

	// Disable shadows for performance
	renderer.shadowMap.enabled = false;

	// Input via shared InputManager (polled in update below)
	const input = getInput();
	const cancelRepair = () => {
		if (interaction.repairingSubsystemId) {
			interaction.repairingSubsystemId = null;
			interaction.repairDuration = 0;
			interaction.repairElapsed = 0;
			player?.setRepairing(false);
		}
	};
	const tryInteract = () => {
		if (interaction.repairingSubsystemId) return;

		if (interaction.nearestCrate && !interaction.nearestCrate.looted) {
			addResource("ship-parts", interaction.nearestCrate.contents);
			markSupplyCrateLooted(interaction.nearestCrate);
			return;
		}

		if (!interaction.nearestSubsystem) return;

		const sub = shipState.getSubsystem(interaction.nearestSubsystem.subsystemId);
		if (sub && sub.condition < 1.0 && hasResource("ship-parts", sub.repairCost)) {
			interaction.repairingSubsystemId = sub.id;
			interaction.repairDuration = sub.repairCost * SECONDS_PER_REPAIR_PART;
			interaction.repairElapsed = 0;
			player?.setRepairing(true);
		}
	};
	const tryDebugToggle = () => {
		const now = performance.now();
		if (now - lastBackquoteTime < 400) {
			debugMode = !debugMode;
			debug.element.style.display = debugMode ? "block" : "none";
			lastBackquoteTime = 0;
		} else {
			lastBackquoteTime = now;
		}
	};

	// Track which section the player is in
	let currentSection = "gate-room";

	// Capture/test hook — signals that the scene is fully mounted and visible.
	(window as unknown as { __sceneReady?: boolean }).__sceneReady = true;

	return {
		update(delta: number) {
			if (input.isActionJustPressed(Action.Interact)) tryInteract();
			if (input.isActionJustReleased(Action.Interact)) cancelRepair();
			if (input.isActionJustPressed(SguAction.DebugToggle)) tryDebugToggle();

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
				updateInteraction(interaction, subsystemVisuals, crates, player.object.position, shipState);

				// Cancel repair if player moved away from the target subsystem
				if (interaction.repairingSubsystemId && !interaction.nearestSubsystem) {
					cancelRepair();
				}

				// Tick repair progress
				if (interaction.repairingSubsystemId) {
					interaction.repairElapsed += delta;
					if (interaction.repairElapsed >= interaction.repairDuration) {
						const sub = shipState.getSubsystem(interaction.repairingSubsystemId);
						if (sub && consumeResource("ship-parts", sub.repairCost)) {
							shipState.repairSubsystem(sub.id);
							shipState.distributePower();
						}
						cancelRepair();
					}
				}
			}

			// Debug overlay
			if (debugMode) debug.update();
		},
		dispose() {
			cancelRepair();
			debug.element.remove();
			interaction.promptElement.remove();
			for (const body of roomColliders) rigidBody.remove(context.physicsWorld, body);
			roomColliders.length = 0;
			shipState.dispose();
			bus.cleanup();
			// Dispose GPU geometry + material objects to prevent VRAM leaks
			// across scene transitions (matches BUG-003 pattern from other scenes).
			scene.traverse((obj) => {
				if (obj instanceof THREE.InstancedMesh) {
					obj.dispose(); // releases instanceMatrix / instanceColor buffer attributes
				}
				if (obj instanceof THREE.Mesh) {
					obj.geometry.dispose();
					if (Array.isArray(obj.material)) {
						obj.material.forEach((m) => m.dispose());
					} else {
						(obj.material as THREE.Material).dispose();
					}
				}
			});
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
		vrmUrl: "/assets/characters/eli-wallace/eli-wallace.vrm",
	},
	mount
});
