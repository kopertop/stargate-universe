/**
 * CO₂ Scrubber Room Scene — Air Crisis Completion (SGU Episode "Air")
 *
 * The cramped, dimly-lit mechanical room deep in Destiny where the CO₂
 * scrubbers are located. The player arrives here after returning from the
 * desert planet with calcium deposits (lime).
 *
 * Quest objectives completed here:
 *  - fix-scrubbers → auto-advanced via ship:subsystem:repaired event
 *
 * Navigation:
 *  - Entered from gate-room after returning with lime
 *  - Returns to gate-room after quest completion
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { emit, scopedBus } from "../../systems/event-bus";
import { Action, getInput } from "../../systems/input";
import { setActiveQuestManager } from "../../systems/active-quest-manager";
import { QUEST_ID as AIR_CRISIS_QUEST_ID } from "../../quests/air-crisis";
import { isLimeCollected, setLimeCollected } from "../../systems/scene-transition-state";
import { createHud } from "@kopertop/vibe-game-engine";
import { getGameSession } from "../../systems/game-session";
import { consumeResource } from "../../systems/resources";
import { applyPostProfile } from "../../post/profiles";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── Constants ────────────────────────────────────────────────────────────────

const ROOM_WIDTH = 14;
const ROOM_DEPTH = 22;
const ROOM_HEIGHT = 4.5;

const COLOR_FLOOR = 0x0d0d1a;
const COLOR_WALL = 0x111120;
const COLOR_METAL = 0x1a1a2a;
const COLOR_METAL_DARK = 0x0f0f1a;
const COLOR_PIPE = 0x1e1e30;
const COLOR_SCRUBBER = 0x1a2030;
const COLOR_STATUS_RED = 0xff3300;
const COLOR_STATUS_GREEN = 0x00ff66;
const COLOR_EMERGENCY_RED = 0xff2200;

// Three scrubber units arranged in a tight cluster
const SCRUBBER_POSITIONS: THREE.Vector3[] = [
	new THREE.Vector3(-3.5, 0, -5),
	new THREE.Vector3(3.5, 0, -5),
	new THREE.Vector3(0, 0, -9),
];

// Repair panel — player must stand near this to interact
const REPAIR_PANEL_POS = new THREE.Vector3(0, 0, -2);
const REPAIR_RADIUS = 2.2;

// ─── Room construction ────────────────────────────────────────────────────────

function buildRoom(scene: THREE.Scene): void {
	// MeshBasicMaterial keeps walls/floor genuinely dark at exposure 3.9 —
	// MeshStandardMaterial here baked out to saturated cyan/red as the
	// hemisphere + emergency strobes were exposure-multiplied. Lighting still
	// reads on the scrubbers, panels, and pipes which keep PBR.
	// Industrial grated floor texture — orthogonal seam lines at half-meter
	// scale catch the emergency light pools and read as a metal deck plate
	// rather than a uniform painted slab.
	const floorCanvas = document.createElement("canvas");
	floorCanvas.width = 256; floorCanvas.height = 256;
	const fctx = floorCanvas.getContext("2d")!;
	fctx.fillStyle = "#0d0d1a";
	fctx.fillRect(0, 0, 256, 256);
	// Heavy grid seams (panel boundary)
	fctx.strokeStyle = "rgba(28, 28, 44, 0.85)";
	fctx.lineWidth = 2;
	for (const t of [0, 128, 256]) {
		fctx.beginPath(); fctx.moveTo(t, 0); fctx.lineTo(t, 256); fctx.stroke();
		fctx.beginPath(); fctx.moveTo(0, t); fctx.lineTo(256, t); fctx.stroke();
	}
	// Inner cross-hatch ribs (smaller diamond plate pattern)
	fctx.strokeStyle = "rgba(40, 40, 60, 0.5)";
	fctx.lineWidth = 1;
	for (let i = 32; i < 256; i += 32) {
		if (i === 128) continue;
		fctx.beginPath(); fctx.moveTo(i, 0); fctx.lineTo(i, 256); fctx.stroke();
		fctx.beginPath(); fctx.moveTo(0, i); fctx.lineTo(256, i); fctx.stroke();
	}
	// Bolt corners on each large panel quadrant
	fctx.fillStyle = "rgba(60, 60, 84, 0.7)";
	for (const x of [12, 116, 140, 244]) {
		for (const y of [12, 116, 140, 244]) {
			fctx.fillRect(x, y, 3, 3);
		}
	}
	const floorTex = new THREE.CanvasTexture(floorCanvas);
	floorTex.wrapS = THREE.RepeatWrapping;
	floorTex.wrapT = THREE.RepeatWrapping;
	floorTex.repeat.set(ROOM_WIDTH / 4, ROOM_DEPTH / 4);
	floorTex.colorSpace = THREE.SRGBColorSpace;
	const floorMat = new THREE.MeshBasicMaterial({ map: floorTex, fog: true });
	const floor = new THREE.Mesh(new THREE.BoxGeometry(ROOM_WIDTH, 0.3, ROOM_DEPTH), floorMat);
	floor.position.set(0, -0.15, 0);
	scene.add(floor);

	// Industrial wall texture — vertical ribs + horizontal seam, slightly
	// red-tinted base so emergency light wash blends naturally rather than
	// reading as flat color × red flood.
	const wallCanvas = document.createElement("canvas");
	wallCanvas.width = 256; wallCanvas.height = 256;
	const wctx = wallCanvas.getContext("2d")!;
	const wallGrad = wctx.createLinearGradient(0, 0, 0, 256);
	wallGrad.addColorStop(0, "#15151f");
	wallGrad.addColorStop(0.5, "#10101a");
	wallGrad.addColorStop(1, "#0a0a14");
	wctx.fillStyle = wallGrad;
	wctx.fillRect(0, 0, 256, 256);
	// Horizontal panel seam mid-height
	wctx.strokeStyle = "rgba(30, 30, 46, 0.9)";
	wctx.lineWidth = 1;
	wctx.beginPath(); wctx.moveTo(0, 128); wctx.lineTo(256, 128); wctx.stroke();
	// Rib columns
	wctx.strokeStyle = "rgba(38, 38, 56, 0.7)";
	for (const x of [42, 86, 170, 214]) {
		wctx.beginPath(); wctx.moveTo(x, 0); wctx.lineTo(x, 256); wctx.stroke();
	}
	// Faint vertical recess shadows next to ribs
	wctx.strokeStyle = "rgba(6, 6, 12, 0.5)";
	for (const x of [43, 87, 171, 215]) {
		wctx.beginPath(); wctx.moveTo(x, 0); wctx.lineTo(x, 256); wctx.stroke();
	}
	const wallTex = new THREE.CanvasTexture(wallCanvas);
	wallTex.wrapS = THREE.RepeatWrapping;
	wallTex.wrapT = THREE.RepeatWrapping;
	wallTex.repeat.set(ROOM_WIDTH / 4, ROOM_HEIGHT / 4);
	wallTex.colorSpace = THREE.SRGBColorSpace;
	const wallMat = new THREE.MeshBasicMaterial({
		map: wallTex,
		side: THREE.DoubleSide,
		fog: true,
	});

	// Back wall
	const backWall = new THREE.Mesh(new THREE.BoxGeometry(ROOM_WIDTH, ROOM_HEIGHT, 0.3), wallMat);
	backWall.position.set(0, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2);
	scene.add(backWall);

	// Left and right walls
	for (const xSign of [-1, 1]) {
		const wall = new THREE.Mesh(new THREE.BoxGeometry(0.3, ROOM_HEIGHT, ROOM_DEPTH), wallMat);
		wall.position.set(xSign * ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 0);
		scene.add(wall);
	}

	// Ceiling
	const ceiling = new THREE.Mesh(new THREE.BoxGeometry(ROOM_WIDTH, 0.3, ROOM_DEPTH), wallMat);
	ceiling.position.set(0, ROOM_HEIGHT, 0);
	scene.add(ceiling);

	// Overhead pipes running across the ceiling
	const pipeMat = new THREE.MeshStandardMaterial({ color: COLOR_PIPE, roughness: 0.7, metalness: 0.5 });
	for (let i = -2; i <= 2; i++) {
		const pipe = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, ROOM_WIDTH, 8), pipeMat);
		pipe.rotation.z = Math.PI / 2;
		pipe.position.set(0, ROOM_HEIGHT - 0.3, i * 3.5);
		scene.add(pipe);
	}

	// Wall-mounted console panels
	const panelMat = new THREE.MeshStandardMaterial({ color: COLOR_METAL, roughness: 0.6, metalness: 0.4 });
	const screenMat = new THREE.MeshStandardMaterial({
		color: 0x001122,
		emissive: 0x003344,
		emissiveIntensity: 0.8,
		roughness: 0.3,
	});
	for (const xSign of [-1, 1]) {
		const x = xSign * (ROOM_WIDTH / 2 - 0.2);
		for (let z = -6; z <= 4; z += 4) {
			const panel = new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.2, 2.0), panelMat);
			panel.position.set(x, 1.5, z);
			scene.add(panel);
			const screen = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.6, 0.8), screenMat);
			screen.position.set(xSign > 0 ? x - 0.08 : x + 0.08, 1.7, z);
			scene.add(screen);
		}
	}
}

// ─── Scrubber units ───────────────────────────────────────────────────────────

type ScrubberUnit = {
	group: THREE.Group;
	statusLightMat: THREE.MeshStandardMaterial;
	pointLight: THREE.PointLight;
	repaired: boolean;
};

function buildScrubberUnit(scene: THREE.Scene, pos: THREE.Vector3): ScrubberUnit {
	const group = new THREE.Group();
	group.position.copy(pos);

	// Main cylindrical body
	const bodyMat = new THREE.MeshStandardMaterial({ color: COLOR_SCRUBBER, roughness: 0.7, metalness: 0.5 });
	const body = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.9, 3.0, 12), bodyMat);
	body.position.y = 1.5;
	group.add(body);

	// Top dome cap
	const capMat = new THREE.MeshStandardMaterial({ color: COLOR_METAL_DARK, roughness: 0.5, metalness: 0.7 });
	const cap = new THREE.Mesh(new THREE.SphereGeometry(0.82, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), capMat);
	cap.position.y = 3.0;
	group.add(cap);

	// Base flange
	const flange = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.1, 0.25, 12), capMat);
	flange.position.y = 0.125;
	group.add(flange);

	// Mid-body band (detail ring)
	const band = new THREE.Mesh(new THREE.TorusGeometry(0.85, 0.06, 6, 20), capMat);
	band.rotation.x = Math.PI / 2;
	band.position.y = 1.5;
	group.add(band);

	// Status indicator light (red = failing)
	const statusLightMat = new THREE.MeshStandardMaterial({
		color: COLOR_STATUS_RED,
		emissive: COLOR_STATUS_RED,
		emissiveIntensity: 1.5,
		roughness: 0.2,
		metalness: 0.1,
	});
	const statusLight = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 8), statusLightMat);
	statusLight.position.set(0.85, 2.2, 0);
	group.add(statusLight);

	// Coloured point light cast from status indicator
	const pointLight = new THREE.PointLight(COLOR_STATUS_RED, 60, 3.5, 2.0);
	pointLight.position.copy(statusLight.position);
	group.add(pointLight);

	// Vent slots
	const ventMat = new THREE.MeshStandardMaterial({ color: 0x080810, roughness: 0.9, metalness: 0.2 });
	for (let i = 0; i < 4; i++) {
		const angle = (i / 4) * Math.PI * 2;
		const vent = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.08, 0.05), ventMat);
		vent.position.set(Math.cos(angle) * 0.78, 1.0, Math.sin(angle) * 0.78);
		vent.rotation.y = -angle;
		group.add(vent);
	}

	scene.add(group);
	return { group, statusLightMat, pointLight, repaired: false };
}

const repairScrubberVisual = (unit: ScrubberUnit): void => {
	unit.repaired = true;
	unit.statusLightMat.color.set(COLOR_STATUS_GREEN);
	unit.statusLightMat.emissive.set(COLOR_STATUS_GREEN);
	unit.pointLight.color.set(COLOR_STATUS_GREEN);
};

// ─── Repair panel ─────────────────────────────────────────────────────────────

type RepairPanel = { glowMat: THREE.MeshStandardMaterial };

function buildRepairPanel(scene: THREE.Scene, pos: THREE.Vector3): RepairPanel {
	const frameMat = new THREE.MeshStandardMaterial({ color: COLOR_METAL, roughness: 0.6, metalness: 0.5 });
	const frame = new THREE.Mesh(new THREE.BoxGeometry(1.5, 1.8, 0.15), frameMat);
	frame.position.set(pos.x, 1.2, pos.z);
	scene.add(frame);

	const glowMat = new THREE.MeshStandardMaterial({
		color: 0x220000,
		emissive: COLOR_EMERGENCY_RED,
		emissiveIntensity: 0.25,
		roughness: 0.2,
	});
	const screen = new THREE.Mesh(new THREE.BoxGeometry(1.1, 1.2, 0.06), glowMat);
	screen.position.set(pos.x, 1.25, pos.z + 0.11);
	scene.add(screen);

	// Amber "E" interaction indicator at floor level — small and dim so it reads
	// as a glowing button, not a bright block (exposure 3.9 bleaches anything ≥0.5).
	const eMat = new THREE.MeshStandardMaterial({
		color: 0x886600,
		emissive: 0xffaa00,
		emissiveIntensity: 0.4,
		roughness: 0.2,
	});
	const eIndicator = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.18, 0.05), eMat);
	eIndicator.position.set(pos.x, 0.5, pos.z + 0.11);
	scene.add(eIndicator);

	return { glowMat };
}

// ─── Lighting ─────────────────────────────────────────────────────────────────

function buildLighting(scene: THREE.Scene): THREE.PointLight[] {
	// Cool Ancient base lighting — the room is *Ancient*, not "everything-on-fire".
	// The red emergency tint flickers through this baseline, doesn't replace it.
	scene.add(new THREE.HemisphereLight(0x4a6890, 0x101820, 0.45));
	// Subtle red emergency wash — present but no longer the dominant tone.
	scene.add(new THREE.HemisphereLight(0x2a0808, 0x080202, 0.2));

	// Sporadic overhead emergency strip lights — significantly toned down so
	// they read as red strobes punching through cool ambient, not a saturated bath.
	const positions: [number, number, number][] = [
		[-4, 4.0, -8], [4, 4.0, -8],
		[-4, 4.0, 0],  [4, 4.0, 0],
		[0,  4.0, 6],
	];

	const lights: THREE.PointLight[] = [];
	const housingMat = new THREE.MeshStandardMaterial({ color: 0x220000, roughness: 0.5 });
	for (const [x, y, z] of positions) {
		const light = new THREE.PointLight(COLOR_EMERGENCY_RED, 28, 6, 1.8);
		light.position.set(x, y, z);
		scene.add(light);
		lights.push(light);
		const housing = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.15, 0.3), housingMat);
		housing.position.set(x, ROOM_HEIGHT - 0.1, z);
		scene.add(housing);
	}

	// Cool ancient floor accents — boost so they actually fight the red flicker.
	const accentPositions: [number, number, number][] = [
		[-5, 0.3, -8], [5, 0.3, -8],
		[-5, 0.3, 6],  [5, 0.3, 6],
		[0,  2.5, -2],
	];
	for (const [x, y, z] of accentPositions) {
		const accent = new THREE.PointLight(0x4488cc, 22, 8, 1.8);
		accent.position.set(x, y, z);
		scene.add(accent);
	}

	// Thinner haze — let the back wall show, no fog-saturation eating the depth.
	scene.fog = new THREE.FogExp2(0x06080c, 0.025);
	return lights;
}

// ─── HUD helpers ──────────────────────────────────────────────────────────────

function createCO2Display(): {
	element: HTMLDivElement;
	setNormalizing: () => void;
	setNormal: () => void;
} {
	const el = document.createElement("div");
	el.id = "scrubber-co2-hud";
	Object.assign(el.style, {
		position: "fixed", top: "12px", left: "12px",
		color: "#ff2200", fontFamily: "'Courier New', monospace",
		fontSize: "13px", lineHeight: "1.6",
		background: "rgba(0,0,0,0.75)", padding: "6px 12px",
		borderRadius: "3px", pointerEvents: "none",
		userSelect: "none", zIndex: "998",
		textShadow: "0 0 8px #ff220066", whiteSpace: "pre",
	});
	el.textContent = "CO\u2082 Scrubbers: CRITICAL\nAtmosphere: TOXIC \u2014 EVACUATE";
	document.body.appendChild(el);
	return {
		element: el,
		setNormalizing: () => {
			el.textContent = "CO\u2082 Scrubbers: REPAIRING\u2026\nAtmosphere: Normalizing\u2026";
			el.style.color = "#ff9900";
		},
		setNormal: () => {
			el.textContent = "CO\u2082 Scrubbers: NOMINAL\nAtmosphere: Safe \u2713";
			el.style.color = "#00ff66";
		},
	};
}

function createInteractPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "scrubber-interact-prompt";
	Object.assign(el.style, {
		position: "fixed", bottom: "100px", left: "50%",
		transform: "translateX(-50%)", color: "#ffee88",
		fontFamily: "'Courier New', monospace", fontSize: "14px",
		textAlign: "center", textShadow: "0 0 8px #ffee8844",
		pointerEvents: "none", userSelect: "none", display: "none",
	});
	document.body.appendChild(el);
	return el;
}

function createRushDialogue(text: string): { element: HTMLDivElement; dismiss: () => void } {
	const el = document.createElement("div");
	el.id = "scrubber-rush-dialogue";
	Object.assign(el.style, {
		position: "fixed", bottom: "160px", left: "50%",
		transform: "translateX(-50%)", color: "#00ff88",
		fontFamily: "'Courier New', monospace", fontSize: "14px",
		textAlign: "center", background: "rgba(0,0,0,0.85)",
		padding: "10px 22px", borderRadius: "4px", maxWidth: "600px",
		border: "1px solid #00ff8844", textShadow: "0 0 8px #00ff8844",
		pointerEvents: "none", userSelect: "none",
		opacity: "1", transition: "opacity 1.5s ease",
	});
	el.textContent = `Rush: "${text}"`;
	document.body.appendChild(el);
	return {
		element: el,
		dismiss: () => {
			el.style.opacity = "0";
			setTimeout(() => el.remove(), 1500);
		},
	};
}

function createReturnPrompt(): HTMLDivElement {
	const el = document.createElement("div");
	el.id = "scrubber-return-prompt";
	Object.assign(el.style, {
		position: "fixed", bottom: "60px", left: "50%",
		transform: "translateX(-50%)", color: "#44aaff",
		fontFamily: "'Courier New', monospace", fontSize: "14px",
		textAlign: "center", background: "rgba(0,0,0,0.7)",
		padding: "8px 18px", borderRadius: "4px",
		border: "1px solid #44aaff66", textShadow: "0 0 8px #44aaff44",
		pointerEvents: "none", userSelect: "none", display: "none",
	});
	el.textContent = "[E] Return to the Gate Room";
	document.body.appendChild(el);
	return el;
}

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, player, renderer } = context;
	const restorePostProfile = applyPostProfile(renderer, "interior");
	camera.rotation.order = "YXZ";
	const bus = scopedBus();

	// ─── Shared gameplay state ────────────────────────────────────────
	const { questManager, timers } = getGameSession();
	if (!questManager.isActive(AIR_CRISIS_QUEST_ID) && !questManager.isCompleted(AIR_CRISIS_QUEST_ID)) {
		questManager.startQuest(AIR_CRISIS_QUEST_ID);
	}
	setActiveQuestManager(questManager);

	// ─── World ────────────────────────────────────────────────────────
	const emergencyLights = buildLighting(scene);
	buildRoom(scene);

	// ─── Scrubber units ───────────────────────────────────────────────
	const scrubberUnits = SCRUBBER_POSITIONS.map((pos) => buildScrubberUnit(scene, pos));

	// ─── Repair panel ─────────────────────────────────────────────────
	const repairPanel = buildRepairPanel(scene, REPAIR_PANEL_POS);

	// ─── HUD ──────────────────────────────────────────────────────────
	const co2Display = createCO2Display();
	const interactPrompt = createInteractPrompt();
	const returnPrompt = createReturnPrompt();

	const compassHud = createHud(renderer.domElement.parentElement ?? document.body);

	// ─── State ────────────────────────────────────────────────────────
	let elapsed = 0;
	let repaired = false;
	let returnReady = false;
	let nearPanel = false;

	// Pending timers from the repair sequence — cleared on dispose so callbacks
	// don't fire on a removed DOM or stale scene state after a scene transition.
	const repairTimers = new Set<ReturnType<typeof setTimeout>>();
	const schedule = (fn: () => void, ms: number): void => {
		const id = setTimeout(() => {
			repairTimers.delete(id);
			fn();
		}, ms);
		repairTimers.add(id);
	};

	const doRepair = (): void => {
		if (repaired) return;
		repaired = true;

		// Emit repair event — quest manager auto-advances fix-scrubbers objective
		// (repair objectives keyed on subsystemId === targetId = "co2-scrubbers")
		emit("ship:subsystem:repaired", { subsystemId: "co2-scrubbers", condition: 1.0 });
		timers.cancelTimer("air-crisis:co2");
		consumeResource("lime", 3);

		// Clear lime carry state — delivery complete
		setLimeCollected(false);

		// Scrubber status lights → green
		for (const unit of scrubberUnits) repairScrubberVisual(unit);

		// Repair panel screen → green
		repairPanel.glowMat.emissive.set(0x00ff66);
		repairPanel.glowMat.color.set(0x002200);

		// HUD: normalizing phase
		co2Display.setNormalizing();

		// Rush dialogue fires after a beat
		schedule(() => {
			const dialogue = createRushDialogue("Remarkable. You actually pulled it off.");
			// Atmosphere fully normal ~4s after dialogue
			schedule(() => co2Display.setNormal(), 4000);
			// Return prompt appears as dialogue fades
			schedule(() => {
				dialogue.dismiss();
				returnPrompt.style.display = "block";
				returnReady = true;
			}, 6000);
		}, 1500);
	};

	// ─── Input (shared InputManager) ──────────────────────────────────
	const input = getInput();
	const tryInteract = (): void => {
		if (nearPanel && !repaired) {
			if (!isLimeCollected()) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = "You need to find a calcium source first.";
				return;
			}
			doRepair();
		} else if (returnReady) {
			void context.gotoScene("gate-room");
		}
	};

	// ─── Test hooks ──────────────────────────────────────────────────────
	(window as any).__sceneReady = true;
	(window as any).__sguBus = bus;

	return {
		update(delta: number) {
			elapsed += delta;
			timers.tick(delta);

			if (input.isActionJustPressed(Action.Interact)) tryInteract();

			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			compassHud.update(camera as any, delta);

			// Emergency lights — flicker on failing power; dim to ambient after repair.
			// Scale factor raised to 6.0 (was 1.2) so the room is visually readable.
			for (const light of emergencyLights) {
				const flicker =
					0.8 + Math.sin(elapsed * 8.3 + light.position.x) * 0.2
					+ Math.sin(elapsed * 13.7 + light.position.z) * 0.1;
				light.intensity = repaired ? flicker * 8 : flicker * 200;
			}

			// Scrubber status light pulse
			for (const unit of scrubberUnits) {
				const pulse = repaired
					? 0.8 + Math.sin(elapsed * 2.5) * 0.2
					: 0.7 + Math.sin(elapsed * 4.0 + unit.group.position.x) * 0.3;
				unit.statusLightMat.emissiveIntensity = pulse * (repaired ? 1.0 : 1.5);
				unit.pointLight.intensity = pulse * (repaired ? 30 : 60);
			}

			if (!player) return;
			const pp = player.object.position;

			// Panel proximity
			const panelDist = Math.sqrt(
				(pp.x - REPAIR_PANEL_POS.x) ** 2 + (pp.z - REPAIR_PANEL_POS.z) ** 2
			);
			nearPanel = panelDist < REPAIR_RADIUS;

			// Update interaction prompt
			if (nearPanel && !repaired) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = isLimeCollected()
					? "[E] Apply calcium compound to scrubber system"
					: "You need to find a calcium source first.";
			} else if (returnReady) {
				interactPrompt.style.display = "block";
				interactPrompt.textContent = "[E] Return to the Gate Room";
			} else {
				interactPrompt.style.display = "none";
			}
		},

		dispose() {
			restorePostProfile();
			for (const id of repairTimers) clearTimeout(id);
			repairTimers.clear();
			co2Display.element.remove();
			interactPrompt.remove();
			returnPrompt.remove();
			compassHud.dispose();
			setActiveQuestManager(null);
			bus.cleanup();
			// BUG-003: dispose all GPU geometry + material objects to prevent VRAM leaks.
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

// ─── Scene definition ─────────────────────────────────────────────────────────

export const scrubberRoomScene = defineGameScene({
	id: "scrubber-room",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () =>
			import("./scene.runtime.json?raw").then((module) => module.default),
	}),
	title: "CO\u2082 Scrubber Room",
	player: {
		vrmUrl: "/assets/characters/eli-wallace/eli-wallace.vrm",
	},
	mount,
});
