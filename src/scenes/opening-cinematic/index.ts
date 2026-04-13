/**
 * Opening Cinematic — SGU Season 1 Episode 1 "Air"
 *
 * 9-beat scripted sequence:
 *   1. Start Screen  — title card + New Game / Continue menu
 *   2. Dormant Gate  — slow push toward dark ring
 *   3. Gate Activates — chevrons light, kawoosh disc
 *   4. Scott Through  — walks out, flashlight, subtitle
 *   5. Evacuation Chaos — direct-camera crew fly-through
 *   6. Overhead Cut  — wide shot from above
 *   7. Rush          — side angle, lands, scans, exits
 *   8. Eli / TJ / Young — gate flicker, Young hits wall
 *   9. Player Wakes  — ground push-up, dialogue, HUD
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── Types ────────────────────────────────────────────────────────────────────

interface CinematicBeat {
	startTime: number;
	duration: number;
	type: "tween" | "cut";
	cameraFrom: THREE.Vector3;
	cameraTo: THREE.Vector3;
	lookAt: THREE.Vector3 | "scott" | "rush" | "young" | "eli";
	easing: "linear" | "ease-in" | "ease-out" | "ease-in-out";
}

interface ThrownNpc {
	body: THREE.Mesh;
	head: THREE.Mesh;
	startPos: THREE.Vector3;
	velocity: THREE.Vector3;
	t0: number;
	flightTime: number;
	landed: boolean;
	landingPos: THREE.Vector3;
}

// ─── Scene palette ────────────────────────────────────────────────────────────

const COLOR_EMERGENCY_RED = 0xff2200;
const COLOR_ANCIENT_GLOW  = 0x4488ff;
const COLOR_GATE_HORIZON  = 0x88bbff;
const COLOR_SKIN          = 0xd4926a;
const COLOR_DARK_WALL     = 0x0d0d1a;
const COLOR_FLOOR         = 0x0a0a14;

// ─── World-space layout ───────────────────────────────────────────────────────

const GATE_CENTER = new THREE.Vector3(0, 3.2, 0);

// ─── Cinematic beats (t=0 = New Game clicked) ─────────────────────────────────

const BEATS: CinematicBeat[] = [
	// Beat 2 — dormant gate, slow push toward dark ring
	{
		startTime: 0, duration: 4, type: "tween",
		cameraFrom: new THREE.Vector3(0, 1.7, 15),
		cameraTo:   new THREE.Vector3(0, 1.7,  5),
		lookAt: GATE_CENTER,
		easing: "ease-in",
	},
	// Beat 3 — gate activates: chevrons light, kawoosh
	{
		startTime: 4, duration: 3, type: "tween",
		cameraFrom: new THREE.Vector3(0, 1.7, 5),
		cameraTo:   new THREE.Vector3(0, 1.7, 3),
		lookAt: GATE_CENTER,
		easing: "ease-in",
	},
	// Beat 4 — Scott comes through, flashlight, subtitle
	{
		startTime: 7, duration: 3, type: "tween",
		cameraFrom: new THREE.Vector3(2, 1.7, 4),
		cameraTo:   new THREE.Vector3(1, 1.5, 2.5),
		lookAt: "scott",
		easing: "ease-out",
	},
	// Beat 5 — evacuation chaos, camera behind gate looking back
	{
		startTime: 10, duration: 5, type: "cut",
		cameraFrom: new THREE.Vector3(0, 1.8, -3.5),
		cameraTo:   new THREE.Vector3(0, 1.8, -3.5),
		lookAt: new THREE.Vector3(0, 2, 2),
		easing: "linear",
	},
	// Beat 6 — overhead cut, red emergency lighting
	{
		startTime: 15, duration: 4, type: "cut",
		cameraFrom: new THREE.Vector3(0, 14, 0),
		cameraTo:   new THREE.Vector3(0, 14, 0),
		lookAt: new THREE.Vector3(0, 0, -1),
		easing: "linear",
	},
	// Beat 7 — Rush: side angle, lands on feet, scans, exits
	{
		startTime: 19, duration: 2, type: "cut",
		cameraFrom: new THREE.Vector3(4.5, 2, 1.5),
		cameraTo:   new THREE.Vector3(4.5, 1.7, 0.5),
		lookAt: "rush",
		easing: "ease-out",
	},
	// Beat 8 — Eli, TJ, Young; gate flicker, Young hits far wall
	{
		startTime: 21, duration: 6, type: "tween",
		cameraFrom: new THREE.Vector3(3.5, 2,   1),
		cameraTo:   new THREE.Vector3(3,   1.8, -2),
		lookAt: "young",
		easing: "ease-in-out",
	},
	// Beat 9 — player wakes: ground-level push up, Scott dialogue
	{
		startTime: 27, duration: 5, type: "tween",
		cameraFrom: new THREE.Vector3(0.2, 0.12, -1.5),
		cameraTo:   new THREE.Vector3(0.2, 1.0,  -0.5),
		lookAt: new THREE.Vector3(0.2, 0.3, -2.5),
		easing: "ease-out",
	},
];

const CINEMATIC_TOTAL_DURATION = 34;
const SKIP_FADE_DURATION       = 0.6;

// ─── Easing ───────────────────────────────────────────────────────────────────

const easeFns: Record<CinematicBeat["easing"], (t: number) => number> = {
	"linear":      (t) => t,
	"ease-in":     (t) => t * t,
	"ease-out":    (t) => 1 - (1 - t) * (1 - t),
	"ease-in-out": (t) => t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2,
};

// ─── Start Screen ─────────────────────────────────────────────────────────────

interface StartScreen {
	el: HTMLDivElement;
	waitForNewGame: () => Promise<void>;
	dispose: () => void;
}

const createStartScreen = (): StartScreen => {
	const el = document.createElement("div");
	el.id = "sgu-start-screen";
	Object.assign(el.style, {
		position: "fixed", inset: "0", background: "#000",
		display: "flex", flexDirection: "column",
		alignItems: "center", justifyContent: "center",
		zIndex: "200", fontFamily: "'Courier New', monospace",
	});

	// Star canvas
	const canvas = document.createElement("canvas");
	canvas.width  = window.innerWidth;
	canvas.height = window.innerHeight;
	Object.assign(canvas.style, { position: "absolute", inset: "0", opacity: "0.7" });
	const ctx = canvas.getContext("2d")!;
	for (let i = 0; i < 320; i++) {
		const x  = Math.random() * canvas.width;
		const y  = Math.random() * canvas.height;
		const r  = Math.random() * 1.4 + 0.2;
		const a  = Math.random() * 0.8 + 0.2;
		ctx.beginPath();
		ctx.arc(x, y, r, 0, Math.PI * 2);
		ctx.fillStyle = `rgba(180,210,255,${a})`;
		ctx.fill();
	}
	el.appendChild(canvas);

	// Title
	const title = document.createElement("div");
	Object.assign(title.style, {
		position: "relative", color: "#ddeeff",
		fontSize: "clamp(22px, 4vw, 42px)", letterSpacing: "0.45em",
		fontWeight: "300", textTransform: "uppercase",
		textShadow: "0 0 18px rgba(100,180,255,0.55), 0 0 40px rgba(80,160,255,0.25)",
		marginBottom: "12px",
	});
	title.textContent = "STARGATE UNIVERSE";
	el.appendChild(title);

	const subtitle = document.createElement("div");
	Object.assign(subtitle.style, {
		position: "relative", color: "rgba(100,160,220,0.5)",
		fontSize: "clamp(9px, 1.2vw, 13px)", letterSpacing: "0.5em",
		fontWeight: "300", marginBottom: "60px",
	});
	subtitle.textContent = "SEASON  I  ·  EPISODE  I  ·  AIR";
	el.appendChild(subtitle);

	const makeBtn = (label: string): HTMLButtonElement => {
		const btn = document.createElement("button");
		Object.assign(btn.style, {
			background: "transparent", border: "1px solid rgba(80,150,255,0.4)",
			color: "rgba(160,210,255,0.85)", fontFamily: "'Courier New', monospace",
			fontSize: "clamp(10px, 1.4vw, 14px)", letterSpacing: "0.35em",
			padding: "10px 36px", cursor: "pointer", marginBottom: "14px",
			textTransform: "uppercase", transition: "border-color 0.2s, color 0.2s",
			width: "220px",
		});
		btn.textContent = label;
		btn.addEventListener("mouseenter", () => {
			btn.style.borderColor = "rgba(100,180,255,0.9)";
			btn.style.color = "#ffffff";
		});
		btn.addEventListener("mouseleave", () => {
			btn.style.borderColor = "rgba(80,150,255,0.4)";
			btn.style.color = "rgba(160,210,255,0.85)";
		});
		return btn;
	};

	const menuWrap = document.createElement("div");
	Object.assign(menuWrap.style, {
		position: "relative", display: "flex",
		flexDirection: "column", alignItems: "center",
	});

	const newGameBtn  = makeBtn("New Game");
	const continueBtn = makeBtn("Continue");
	continueBtn.style.opacity = "0.45";
	continueBtn.style.cursor  = "not-allowed";

	menuWrap.appendChild(newGameBtn);
	menuWrap.appendChild(continueBtn);
	el.appendChild(menuWrap);

	document.body.appendChild(el);

	const waitForNewGame = (): Promise<void> => new Promise((resolve) => {
		const onClick = (): void => {
			newGameBtn.removeEventListener("click", onClick);
			// Fade out
			el.style.transition = "opacity 0.8s ease";
			el.style.opacity = "0";
			setTimeout(() => { el.style.display = "none"; resolve(); }, 820);
		};
		newGameBtn.addEventListener("click", onClick);
	});

	return {
		el,
		waitForNewGame,
		dispose: () => el.remove(),
	};
};

// ─── Subtitle system ──────────────────────────────────────────────────────────

interface SubtitleSystem {
	show: (text: string, duration: number) => void;
	dispose: () => void;
}

const createSubtitleSystem = (): SubtitleSystem => {
	const el = document.createElement("div");
	Object.assign(el.style, {
		position: "fixed", bottom: "60px", left: "50%",
		transform: "translateX(-50%)",
		background: "rgba(0,0,0,0.62)", color: "#f0f4ff",
		fontFamily: "'Courier New', monospace",
		fontSize: "clamp(13px, 1.6vw, 17px)", letterSpacing: "0.06em",
		padding: "8px 22px", borderRadius: "4px",
		opacity: "0", pointerEvents: "none",
		transition: "opacity 0.3s ease", zIndex: "150",
		whiteSpace: "nowrap", maxWidth: "80vw",
		textAlign: "center",
	});
	document.body.appendChild(el);

	let hideTimer: ReturnType<typeof setTimeout> | null = null;

	const show = (text: string, duration: number): void => {
		if (hideTimer !== null) clearTimeout(hideTimer);
		el.textContent = text;
		el.style.opacity = "1";
		hideTimer = setTimeout(() => {
			el.style.opacity = "0";
			hideTimer = null;
		}, duration * 1000);
	};

	return {
		show,
		dispose: () => {
			if (hideTimer !== null) clearTimeout(hideTimer);
			el.remove();
		},
	};
};

// ─── Kawoosh system ───────────────────────────────────────────────────────────

interface KawooshSystem {
	group: THREE.Group;
	disc: THREE.Mesh;
	ring: THREE.Mesh;
	active: boolean;
	phase: "expand" | "snap" | "done";
	elapsed: number;
	dispose: () => void;
}

const createKawoosh = (scene: THREE.Scene): KawooshSystem => {
	const group = new THREE.Group();
	group.position.set(GATE_CENTER.x, GATE_CENTER.y, GATE_CENTER.z + 0.15);
	group.visible = false;

	const discGeo = new THREE.CircleGeometry(2.55, 64);
	const discMat = new THREE.MeshBasicMaterial({
		color: 0x44aaff, transparent: true, opacity: 0.92,
		blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
	});
	const disc = new THREE.Mesh(discGeo, discMat);
	group.add(disc);

	const ringGeo = new THREE.TorusGeometry(2.55, 0.22, 12, 64);
	const ringMat = new THREE.MeshBasicMaterial({
		color: 0x88ddff, transparent: true, opacity: 0.95,
		blending: THREE.AdditiveBlending, depthWrite: false,
	});
	const ring = new THREE.Mesh(ringGeo, ringMat);
	group.add(ring);

	scene.add(group);

	return {
		group, disc, ring,
		active: false, phase: "expand", elapsed: 0,
		dispose: () => {
			scene.remove(group);
			discGeo.dispose(); discMat.dispose();
			ringGeo.dispose(); ringMat.dispose();
		},
	};
};

const updateKawoosh = (k: KawooshSystem, delta: number): void => {
	if (!k.active || k.phase === "done") return;
	k.elapsed += delta;
	const dMat = k.disc.material as THREE.MeshBasicMaterial;
	const rMat = k.ring.material as THREE.MeshBasicMaterial;

	if (k.phase === "expand") {
		// scale 0→3 over 0.4s
		const s = Math.min(3, (k.elapsed / 0.4) * 3);
		k.disc.scale.setScalar(s === 0 ? 0.001 : s);
		dMat.opacity = 0.92 * (1 - k.elapsed / 0.4 * 0.25);
		rMat.opacity = 0.95 * Math.min(1, k.elapsed / 0.15);
		if (k.elapsed >= 0.4) k.phase = "snap";
	} else {
		// scale 3→0.1 over 0.4s, then done
		const snapT = Math.min(1, (k.elapsed - 0.4) / 0.4);
		const s = 3 + (0.1 - 3) * snapT;
		k.disc.scale.setScalar(Math.max(0.001, s));
		dMat.opacity = 0.7 * (1 - snapT);
		rMat.opacity = 0.95 * (1 - snapT * 0.6);
		if (k.elapsed >= 0.8) {
			k.phase = "done";
			k.group.visible = false;
		}
	}
};

// ─── Gate entrance ────────────────────────────────────────────────────────────

interface GateEntrance {
	group: THREE.Group;
	outerRing: THREE.Mesh;
	innerRing: THREE.Mesh;
	innerRingMat: THREE.MeshStandardMaterial;
	eventHorizon: THREE.Mesh;
	horizonMat: THREE.MeshStandardMaterial;
	gateLight: THREE.PointLight;
	dispose: () => void;
}

const buildGateEntrance = (scene: THREE.Scene): GateEntrance => {
	const group = new THREE.Group();
	const mats: THREE.Material[] = [];

	const metalMat = new THREE.MeshStandardMaterial({
		color: 0x2a2a3a, roughness: 0.3, metalness: 0.85,
		emissive: 0x111122, emissiveIntensity: 0.1,
	});
	mats.push(metalMat);

	// Outer ring
	const outerRing = new THREE.Mesh(
		new THREE.TorusGeometry(2.8, 0.28, 20, 80), metalMat,
	);
	outerRing.position.copy(GATE_CENTER);
	group.add(outerRing);

	// Inner spinning ring (emissive — will be animated)
	const innerRingMat = new THREE.MeshStandardMaterial({
		color: 0x1a1a30, roughness: 0.2, metalness: 0.92,
		emissive: new THREE.Color(COLOR_ANCIENT_GLOW),
		emissiveIntensity: 0.0,  // starts dark (dormant)
	});
	mats.push(innerRingMat);
	const innerRing = new THREE.Mesh(
		new THREE.TorusGeometry(2.6, 0.14, 12, 60), innerRingMat,
	);
	innerRing.position.copy(GATE_CENTER);
	group.add(innerRing);

	// Segment bumps around outer ring
	const segMat = new THREE.MeshStandardMaterial({ color: 0x333348, roughness: 0.35, metalness: 0.8 });
	mats.push(segMat);
	for (let i = 0; i < 36; i++) {
		const angle = (i / 36) * Math.PI * 2;
		const seg   = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.1, 0.1), segMat);
		seg.position.set(
			GATE_CENTER.x + Math.cos(angle) * 3.0,
			GATE_CENTER.y + Math.sin(angle) * 3.0,
			GATE_CENTER.z + 0.05,
		);
		seg.lookAt(GATE_CENTER.x + Math.cos(angle) * 5, GATE_CENTER.y + Math.sin(angle) * 5, GATE_CENTER.z + 0.05);
		group.add(seg);
	}

	// Event horizon (starts invisible — gate is dormant)
	const horizonMat = new THREE.MeshStandardMaterial({
		color: COLOR_GATE_HORIZON, emissive: new THREE.Color(COLOR_GATE_HORIZON),
		emissiveIntensity: 1.5, transparent: true, opacity: 0.88,
		side: THREE.DoubleSide, roughness: 0.05, metalness: 0,
	});
	mats.push(horizonMat);
	const eventHorizon = new THREE.Mesh(new THREE.CircleGeometry(2.55, 64), horizonMat);
	eventHorizon.position.set(GATE_CENTER.x, GATE_CENTER.y, GATE_CENTER.z + 0.05);
	eventHorizon.visible = false;  // dormant until Beat 3
	group.add(eventHorizon);

	// Approach corridor
	const wallMat  = new THREE.MeshStandardMaterial({ color: 0x1a1a2e, roughness: 0.9, metalness: 0.1, side: THREE.DoubleSide });
	const floorMat = new THREE.MeshStandardMaterial({ color: 0x12121f, roughness: 0.9, metalness: 0.2 });
	mats.push(wallMat, floorMat);

	const floor = new THREE.Mesh(new THREE.BoxGeometry(12, 0.2, 35), floorMat);
	floor.position.set(0, -0.1, 10); group.add(floor);
	const ceiling = new THREE.Mesh(new THREE.BoxGeometry(12, 0.2, 35), wallMat);
	ceiling.position.set(0, 6, 10); group.add(ceiling);
	for (const side of [-1, 1]) {
		const wall = new THREE.Mesh(new THREE.BoxGeometry(0.2, 6, 35), wallMat.clone());
		wall.position.set(side * 6, 3, 10);
		mats.push(wall.material as THREE.Material); group.add(wall);
	}
	const backWall = new THREE.Mesh(new THREE.BoxGeometry(12, 9, 0.3), wallMat.clone());
	backWall.position.set(0, 4.5, -8);
	mats.push(backWall.material as THREE.Material); group.add(backWall);

	// Arch columns
	const archMat = new THREE.MeshStandardMaterial({ color: 0x15152a, roughness: 0.8, metalness: 0.3 });
	mats.push(archMat);
	for (const side of [-1, 1]) {
		const col = new THREE.Mesh(new THREE.BoxGeometry(0.9, 8, 0.7), archMat);
		col.position.set(side * 4.5, 4, -0.3); group.add(col);
	}
	const topBeam = new THREE.Mesh(new THREE.BoxGeometry(10, 0.7, 0.7), archMat);
	topBeam.position.set(0, 7.5, -0.3); group.add(topBeam);

	// Gate light (off when dormant)
	const gateLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 0, 25, 1.5);
	gateLight.position.set(0, 3.2, 4); group.add(gateLight);

	scene.add(group);
	return { group, outerRing, innerRing, innerRingMat, eventHorizon, horizonMat, gateLight, dispose: () => {
		scene.remove(group); for (const m of mats) m.dispose();
	}};
};

// ─── Arrival corridor ─────────────────────────────────────────────────────────

interface ArrivalCorridor {
	group: THREE.Group;
	emergencyLights: THREE.PointLight[];
	sparkingPanels: THREE.Mesh[];
	crewNpcs: THREE.Mesh[];
	dispose: () => void;
}

const buildArrivalCorridor = (scene: THREE.Scene): ArrivalCorridor => {
	const group = new THREE.Group();
	const mats: THREE.Material[] = [];
	const CORR_W = 5, CORR_H = 4.2, CORR_LEN = 36;

	const wallMat  = new THREE.MeshStandardMaterial({ color: COLOR_DARK_WALL, roughness: 0.95, metalness: 0.05, side: THREE.DoubleSide });
	const floorMat = new THREE.MeshStandardMaterial({ color: COLOR_FLOOR, roughness: 0.9, metalness: 0.2 });
	const ceilMat  = new THREE.MeshStandardMaterial({ color: 0x080810, roughness: 0.98, metalness: 0.02 });
	mats.push(wallMat, floorMat, ceilMat);

	const floor = new THREE.Mesh(new THREE.BoxGeometry(CORR_W, 0.2, CORR_LEN), floorMat);
	floor.position.set(0, -0.1, 0); group.add(floor);
	const ceiling = new THREE.Mesh(new THREE.BoxGeometry(CORR_W, 0.2, CORR_LEN), ceilMat);
	ceiling.position.set(0, CORR_H, 0); group.add(ceiling);

	for (const side of [-1, 1]) {
		const wall = new THREE.Mesh(new THREE.BoxGeometry(0.2, CORR_H, CORR_LEN), wallMat.clone());
		wall.position.set(side * (CORR_W / 2), CORR_H / 2, 0);
		mats.push(wall.material as THREE.Material); group.add(wall);
	}
	const backWall = new THREE.Mesh(new THREE.BoxGeometry(CORR_W, CORR_H, 0.2), wallMat.clone());
	backWall.position.set(0, CORR_H / 2, -CORR_LEN / 2);
	mats.push(backWall.material as THREE.Material); group.add(backWall);

	// Ceiling ribs
	const ribMat = new THREE.MeshStandardMaterial({ color: 0x141428, roughness: 0.7, metalness: 0.5 });
	mats.push(ribMat);
	for (let z = -14; z <= 14; z += 5) {
		const rib = new THREE.Mesh(new THREE.BoxGeometry(CORR_W + 0.1, 0.35, 0.3), ribMat);
		rib.position.set(0, CORR_H - 0.15, z); group.add(rib);
	}

	// Emergency strips + lights
	const emergMat = new THREE.MeshStandardMaterial({
		color: COLOR_EMERGENCY_RED, emissive: new THREE.Color(COLOR_EMERGENCY_RED), emissiveIntensity: 1.8,
	});
	mats.push(emergMat);
	for (let z = -12; z <= 12; z += 4) {
		for (const side of [-1, 1]) {
			const strip = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.1, 0.7), emergMat);
			strip.position.set(side * (CORR_W / 2 - 0.15), 0.28, z); group.add(strip);
		}
	}
	const emergencyLights: THREE.PointLight[] = [];
	for (let z = -10; z <= 10; z += 10) {
		const light = new THREE.PointLight(COLOR_EMERGENCY_RED, 55, 9, 1.5);
		light.position.set(0, 1.2, z); group.add(light);
		emergencyLights.push(light);
	}

	// Sparking panels
	const damagedMat = new THREE.MeshStandardMaterial({
		color: 0x333344, emissive: new THREE.Color(0x334466), emissiveIntensity: 0.3,
		roughness: 0.5, metalness: 0.7,
	});
	mats.push(damagedMat);
	const sparkingPanels: THREE.Mesh[] = [];
	for (const [side, z] of [[-1,1],[1,3],[-1,-2],[1,-5],[-1,6],[1,-8]] as [number,number][]) {
		const panel = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.7, 0.9), damagedMat.clone());
		panel.position.set(side * (CORR_W / 2 - 0.1), 1.5 + Math.random(), z);
		mats.push(panel.material as THREE.Material);
		group.add(panel); sparkingPanels.push(panel);
	}

	// Scattered crew on floor (background)
	const crewBodyMat = new THREE.MeshStandardMaterial({ color: 0x22222e, roughness: 0.7, metalness: 0.1 });
	const crewHeadMat = new THREE.MeshStandardMaterial({ color: COLOR_SKIN, roughness: 0.75, metalness: 0 });
	mats.push(crewBodyMat, crewHeadMat);
	const crewNpcs: THREE.Mesh[] = [];

	const crewDefs: Array<{ pos: THREE.Vector3; rotZ: number; rotY: number }> = [
		{ pos: new THREE.Vector3(-1.2, 0.3,  2.5), rotZ:  1.1, rotY: 0.3 },
		{ pos: new THREE.Vector3( 1.4, 0.3,  0.8), rotZ: -0.8, rotY: 1.2 },
		{ pos: new THREE.Vector3(-0.4, 0.3, -1.5), rotZ:  0.9, rotY: 2.1 },
		{ pos: new THREE.Vector3( 0.9, 0.3,  3.5), rotZ: -1.2, rotY: 0.7 },
		{ pos: new THREE.Vector3(-1.7, 0.3,  1.2), rotZ:  1.0, rotY: 1.8 },
		{ pos: new THREE.Vector3( 0.2, 0.3, -2.5), rotZ: -0.7, rotY: 2.8 },
	];
	for (const def of crewDefs) {
		const body = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 1.15, 8), crewBodyMat);
		body.position.copy(def.pos); body.rotation.z = def.rotZ; body.rotation.y = def.rotY;
		group.add(body); crewNpcs.push(body);
		const headOff = new THREE.Vector3(0.62, 0, 0).applyEuler(body.rotation);
		const head = new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 6), crewHeadMat);
		head.position.copy(def.pos).add(headOff); group.add(head);
	}

	scene.add(group);
	return { group, emergencyLights, sparkingPanels, crewNpcs, dispose: () => {
		scene.remove(group); for (const m of mats) m.dispose();
	}};
};

// ─── Simple NPC mesh factory ──────────────────────────────────────────────────

interface NpcMeshes {
	group: THREE.Group;
	dispose: () => void;
}

const createNpcMesh = (scene: THREE.Scene, bodyColor = 0x22222e): NpcMeshes => {
	const group = new THREE.Group();
	const mats: THREE.Material[] = [];

	const bodyMat = new THREE.MeshStandardMaterial({ color: bodyColor, roughness: 0.7, metalness: 0.1 });
	const headMat = new THREE.MeshStandardMaterial({ color: COLOR_SKIN,  roughness: 0.75, metalness: 0 });
	mats.push(bodyMat, headMat);

	// Legs
	for (const side of [-1, 1]) {
		const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.85, 6), bodyMat);
		leg.position.set(side * 0.14, 0.43, 0); group.add(leg);
	}
	// Torso
	const torso = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.65, 0.28), bodyMat);
	torso.position.set(0, 1.05, 0); group.add(torso);
	// Arms
	for (const side of [-1, 1]) {
		const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.065, 0.6, 6), bodyMat);
		arm.position.set(side * 0.32, 1.0, 0);
		arm.rotation.z = side * (Math.PI / 10); group.add(arm);
	}
	// Head
	const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.07, 0.18, 6), headMat);
	neck.position.set(0, 1.46, 0); group.add(neck);
	const head = new THREE.Mesh(new THREE.SphereGeometry(0.185, 10, 8), headMat);
	head.position.set(0, 1.7, 0); group.add(head);

	scene.add(group);
	return { group, dispose: () => { scene.remove(group); for (const m of mats) m.dispose(); } };
};

// ─── Rush NPC (grey coat, dishevelled hair) ───────────────────────────────────

interface RushNpc {
	group: THREE.Group;
	pos: THREE.Vector3;
	walkCycle: number;
	dispose: () => void;
}

const createRushNpc = (scene: THREE.Scene): RushNpc => {
	const group = new THREE.Group();
	const mats: THREE.Material[] = [];

	const greyMat = new THREE.MeshStandardMaterial({ color: 0x777788, roughness: 0.8, metalness: 0.05 });
	const headMat = new THREE.MeshStandardMaterial({ color: COLOR_SKIN,   roughness: 0.75, metalness: 0 });
	const hairMat = new THREE.MeshStandardMaterial({ color: 0xbbbbbb,    roughness: 0.95, metalness: 0 });
	mats.push(greyMat, headMat, hairMat);

	for (const side of [-1, 1]) {
		const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.85, 6), greyMat);
		leg.position.set(side * 0.14, 0.43, 0); group.add(leg);
	}
	const torso = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.65, 0.28), greyMat);
	torso.position.set(0, 1.05, 0); group.add(torso);
	for (const side of [-1, 1]) {
		const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.065, 0.6, 6), greyMat);
		arm.position.set(side * 0.32, 1.0, 0);
		arm.rotation.z = side * (Math.PI / 10); group.add(arm);
	}
	const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.07, 0.18, 6), headMat);
	neck.position.set(0, 1.46, 0); group.add(neck);
	const head = new THREE.Mesh(new THREE.SphereGeometry(0.185, 10, 8), headMat);
	head.position.set(0, 1.7, 0); group.add(head);
	const hair = new THREE.Mesh(
		new THREE.SphereGeometry(0.21, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.55), hairMat,
	);
	hair.position.set(0, 1.74, 0); group.add(hair);

	group.visible = false;
	scene.add(group);
	const pos = group.position;
	return { group, pos, walkCycle: 0, dispose: () => { scene.remove(group); for (const m of mats) m.dispose(); } };
};

// ─── Thrown NPC system ────────────────────────────────────────────────────────
// Parabolic arc: pos(t) = start + vel*t + 0.5*gravity*t²

const GRAVITY = new THREE.Vector3(0, -9.8, 0);

const createThrownNpc = (
	scene: THREE.Scene,
	startPos: THREE.Vector3,
	velocity: THREE.Vector3,
	t0: number,
	flightTime: number,
	landingPos: THREE.Vector3,
): ThrownNpc => {
	const mats: THREE.Material[] = [];
	const bodyMat = new THREE.MeshStandardMaterial({ color: 0x22222e, roughness: 0.7, metalness: 0.1 });
	const headMat = new THREE.MeshStandardMaterial({ color: COLOR_SKIN, roughness: 0.75, metalness: 0 });
	mats.push(bodyMat, headMat);

	const body = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 1.15, 8), bodyMat);
	const head = new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 6), headMat);
	body.visible = false;
	head.visible = false;
	scene.add(body); scene.add(head);

	// Store dispose on the body mesh userData
	(body as unknown as { _disposeFn: () => void })._disposeFn = () => {
		scene.remove(body); scene.remove(head);
		for (const m of mats) m.dispose();
	};

	return { body, head, startPos: startPos.clone(), velocity: velocity.clone(), t0, flightTime, landed: false, landingPos: landingPos.clone() };
};

const updateThrownNpcs = (
	npcs: ThrownNpc[],
	beatT: number,
	shakeRef: { value: number },
): void => {
	const scratchPos = new THREE.Vector3();
	for (const npc of npcs) {
		const localT = beatT - npc.t0;
		if (localT < 0) continue;
		if (!npc.body.visible) { npc.body.visible = true; npc.head.visible = true; }

		if (!npc.landed && localT < npc.flightTime) {
			// Parabolic arc
			scratchPos.copy(npc.startPos)
				.addScaledVector(npc.velocity, localT)
				.addScaledVector(GRAVITY, 0.5 * localT * localT);
			npc.body.position.copy(scratchPos);
			npc.head.position.set(scratchPos.x, scratchPos.y + 0.65, scratchPos.z);
			// Tumble rotation
			npc.body.rotation.z = localT * 4.5;
			npc.body.rotation.x = localT * 2.8;
		} else if (!npc.landed) {
			npc.landed = true;
			npc.body.position.copy(npc.landingPos).setY(0.25);
			npc.head.position.copy(npc.landingPos).setY(0.5);
			npc.body.rotation.z = 1.2 + Math.random() * 0.5;
			shakeRef.value = Math.max(shakeRef.value, 0.28);
		}
	}
};

// ─── Cinematic UI (skip hint + fade + HUD + quest) ───────────────────────────

interface CinematicUI {
	skipHint:    HTMLDivElement;
	hudOverlay:  HTMLDivElement;
	fadeOverlay: HTMLDivElement;
	questMarker: HTMLDivElement;
	dialogPanel: HTMLDivElement;
	dispose: () => void;
}

const createCinematicUI = (): CinematicUI => {
	const skipHint = document.createElement("div");
	Object.assign(skipHint.style, {
		position: "fixed", bottom: "20px", right: "24px",
		color: "rgba(68,136,255,0.55)", fontFamily: "'Courier New', monospace",
		fontSize: "13px", pointerEvents: "none", userSelect: "none",
		zIndex: "100", transition: "opacity 0.3s ease",
	});
	skipHint.textContent = "[Space]  Skip";
	document.body.appendChild(skipHint);

	const fadeOverlay = document.createElement("div");
	fadeOverlay.id = "cinematic-fade";
	Object.assign(fadeOverlay.style, {
		position: "fixed", inset: "0", background: "black",
		opacity: "0", pointerEvents: "none", zIndex: "50",
	});
	document.body.appendChild(fadeOverlay);

	const hudOverlay = document.createElement("div");
	Object.assign(hudOverlay.style, {
		position: "fixed", inset: "0", opacity: "0",
		pointerEvents: "none", zIndex: "10",
	});

	const topBar = document.createElement("div");
	Object.assign(topBar.style, {
		position: "absolute", top: "14px", left: "50%", transform: "translateX(-50%)",
		color: "#4488ff", fontFamily: "'Courier New', monospace",
		fontSize: "13px", letterSpacing: "4px",
		textShadow: "0 0 12px #4488ff55", whiteSpace: "nowrap",
	});
	topBar.textContent = "DESTINY  ·  FTL TRANSIT  ·  DESTINATION UNKNOWN";
	hudOverlay.appendChild(topBar);

	const bottomBar = document.createElement("div");
	Object.assign(bottomBar.style, {
		position: "absolute", bottom: "18px", left: "50%", transform: "translateX(-50%)",
		color: "rgba(68,136,255,0.5)", fontFamily: "'Courier New', monospace",
		fontSize: "11px", letterSpacing: "2px", whiteSpace: "nowrap",
	});
	bottomBar.textContent = "WASD · MOVE     MOUSE · LOOK     E · INTERACT     ESC · MENU";
	hudOverlay.appendChild(bottomBar);
	document.body.appendChild(hudOverlay);

	const questMarker = document.createElement("div");
	Object.assign(questMarker.style, {
		position: "fixed", top: "50%", right: "28px", transform: "translateY(-50%)",
		color: "#ffaa44", fontFamily: "'Courier New', monospace",
		fontSize: "12px", lineHeight: "1.6", opacity: "0",
		pointerEvents: "none", zIndex: "10", textAlign: "right",
		textShadow: "0 0 8px rgba(255,170,68,0.4)",
		borderRight: "1px solid rgba(255,170,68,0.35)", paddingRight: "12px",
	});
	questMarker.innerHTML =
		`<div style="letter-spacing:2px;margin-bottom:4px;">▸ NEW QUEST</div>` +
		`<div style="font-size:11px;opacity:0.85;">Find Dr. Rush</div>` +
		`<div style="font-size:10px;opacity:0.6;margin-top:2px;">He came through the gate</div>`;
	document.body.appendChild(questMarker);

	// Beat 9: Scott dialogue panel
	const dialogPanel = document.createElement("div");
	Object.assign(dialogPanel.style, {
		position: "fixed", bottom: "100px", left: "50%", transform: "translateX(-50%)",
		background: "rgba(0,0,0,0.7)", border: "1px solid rgba(68,136,255,0.3)",
		color: "#ddeeff", fontFamily: "'Courier New', monospace",
		fontSize: "clamp(13px, 1.6vw, 16px)", letterSpacing: "0.05em",
		padding: "14px 28px", borderRadius: "3px",
		opacity: "0", pointerEvents: "none", zIndex: "150",
		whiteSpace: "nowrap", transition: "opacity 0.4s ease",
	});
	dialogPanel.innerHTML =
		`<span style="color:rgba(100,180,255,0.7);font-size:0.85em;letter-spacing:0.2em;">SCOTT</span><br>` +
		`"Eli — where the hell are we?"`;
	document.body.appendChild(dialogPanel);

	return {
		skipHint, hudOverlay, fadeOverlay, questMarker, dialogPanel,
		dispose: () => {
			skipHint.remove(); hudOverlay.remove(); fadeOverlay.remove();
			questMarker.remove(); dialogPanel.remove();
		},
	};
};

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene, renderer } = context;

	renderer.shadowMap.enabled = false;
	scene.background = new THREE.Color(0x010108);
	scene.fog = new THREE.Fog(0x010108, 22, 90);

	const ambientLight = new THREE.AmbientLight(0x0d1535, 4.0);
	scene.add(ambientLight);

	// ── Build geometry ────────────────────────────────────────────────────────
	const gateEntrance    = buildGateEntrance(scene);
	const arrivalCorridor = buildArrivalCorridor(scene);
	arrivalCorridor.group.visible = false;  // hidden until Beat 4+

	// ── NPC actors ────────────────────────────────────────────────────────────
	const scottNpc = createNpcMesh(scene, 0x1e2a3a);  // military blue
	scottNpc.group.visible = false;
	const scottPos = new THREE.Vector3();

	const rushNpc  = createRushNpc(scene);
	const rushPos  = rushNpc.pos;

	// Eli, TJ, Young as separate actors for Beat 8
	const eliNpc   = createNpcMesh(scene, 0x2a2a1e);  // casual civilian
	const tjNpc    = createNpcMesh(scene, 0x1e2e2a);  // teal-grey uniform
	const youngNpc = createNpcMesh(scene, 0x1e2a3a);  // military
	eliNpc.group.visible = tjNpc.group.visible = youngNpc.group.visible = false;
	const youngPos = new THREE.Vector3();

	// Beat 5: thrown NPCs (3 anonymous crew)
	const beat5Npcs: ThrownNpc[] = [
		createThrownNpc(scene, new THREE.Vector3( 0.3, 3.2, 0.2), new THREE.Vector3(-0.8, 3.5, -13), 0.0, 1.1, new THREE.Vector3(-1.5, 0, -6.5)),
		createThrownNpc(scene, new THREE.Vector3(-0.4, 3.2, 0.2), new THREE.Vector3( 1.5, 4.2, -15), 0.4, 1.0, new THREE.Vector3( 2.0, 0, -8.0)),
		createThrownNpc(scene, new THREE.Vector3( 0.6, 3.2, 0.2), new THREE.Vector3(-2.2, 2.8, -12), 0.8, 0.9, new THREE.Vector3(-2.2, 0, -5.5)),
		createThrownNpc(scene, new THREE.Vector3(-0.2, 3.2, 0.2), new THREE.Vector3( 0.9, 5.0, -17), 1.2, 1.2, new THREE.Vector3( 1.5, 0, -9.5)),
	];

	// Scott flashlight
	const scottLight = new THREE.PointLight(0xfff5e0, 0, 8, 2.0);
	scene.add(scottLight);

	// ── Effects systems ───────────────────────────────────────────────────────
	const kawoosh = createKawoosh(scene);

	// ── UI ────────────────────────────────────────────────────────────────────
	const subtitles = createSubtitleSystem();
	const ui        = createCinematicUI();

	// ── Start screen — wait for New Game ─────────────────────────────────────
	const startScreen = createStartScreen();
	await startScreen.waitForNewGame();
	startScreen.dispose();

	// ── Cinematic state ───────────────────────────────────────────────────────
	const urlParams   = new URLSearchParams(window.location.search);
	const startAt     = parseFloat(urlParams.get("cinematicTime") ?? "0");
	let elapsedTime   = isNaN(startAt) ? 0 : startAt;
	let disposed      = false;
	let skipping      = false;
	let skipProgress  = 0;
	let transitioning = false;

	// Camera shake state
	const shake = { value: 0 };
	const shakeOffset = new THREE.Vector3();

	// Gate flicker state (Beat 8: t≈25-26)
	let flickerActive = false;

	// Beat 8 Young trajectory
	const youngThrownNpc = createThrownNpc(
		scene,
		new THREE.Vector3(0, 3.2, 0.2),
		new THREE.Vector3(-1.2, 2.0, -28),  // max velocity
		4.5,  // t0 within Beat 8 (at t=25.5 absolute)
		0.65,
		new THREE.Vector3(-1.0, 0, -17.5),   // hits far wall
	);

	// Eli / TJ softer throws in Beat 8
	const eliThrow = createThrownNpc(
		scene,
		new THREE.Vector3( 0.5, 3.2, 0.2),
		new THREE.Vector3( 0.8, 1.5, -7),
		0.2,  // t0 within Beat 8
		0.9,
		new THREE.Vector3( 0.8, 0, -5.5),
	);
	const tjThrow = createThrownNpc(
		scene,
		new THREE.Vector3(-0.4, 3.2, 0.2),
		new THREE.Vector3(-0.6, 2.0, -9),
		1.2,
		0.85,
		new THREE.Vector3(-0.6, 0, -7.0),
	);

	// ── Camera setup ──────────────────────────────────────────────────────────
	camera.fov  = 65;
	camera.near = 0.1;
	camera.far  = 400;
	camera.updateProjectionMatrix();
	camera.position.copy(BEATS[0].cameraFrom);
	camera.lookAt(GATE_CENTER);

	// ── Helpers ───────────────────────────────────────────────────────────────

	const applyCameraForTime = (t: number): void => {
		let activeBeat = BEATS[0];
		for (const beat of BEATS) {
			if (t >= beat.startTime) activeBeat = beat;
			else break;
		}

		const raw      = Math.min(1, (t - activeBeat.startTime) / Math.max(0.001, activeBeat.duration));
		const progress = easeFns[activeBeat.easing](raw);
		camera.position.lerpVectors(activeBeat.cameraFrom, activeBeat.cameraTo, progress);

		// Apply camera shake
		if (shake.value > 0.001) {
			shakeOffset.set(
				(Math.random() * 2 - 1) * shake.value,
				(Math.random() * 2 - 1) * shake.value,
				0,
			);
			camera.position.add(shakeOffset);
		}

		// LookAt
		if (activeBeat.lookAt === "scott") {
			camera.lookAt(scottPos.clone().setY(scottPos.y + 1.2));
		} else if (activeBeat.lookAt === "rush") {
			camera.lookAt(rushPos.clone().setY(rushPos.y + 1.65));
		} else if (activeBeat.lookAt === "young") {
			camera.lookAt(youngPos.clone().setY(youngPos.y + 0.6));
		} else if (activeBeat.lookAt === "eli") {
			camera.lookAt(new THREE.Vector3(0.2, 0.3, -2.5));
		} else {
			camera.lookAt(activeBeat.lookAt as THREE.Vector3);
		}
	};

	const finishCinematic = async (): Promise<void> => {
		if (disposed || transitioning) return;
		transitioning = true;
		await gotoScene("gate-room");
	};

	// Key handler
	const handleKeyDown = (e: KeyboardEvent): void => {
		if ((e.code === "Space" || e.code === "Escape") && !skipping) skipping = true;
	};
	window.addEventListener("keydown", handleKeyDown);

	// ── Update loop ───────────────────────────────────────────────────────────
	return {
		update(delta: number): void {
			if (disposed) return;

			// Skip
			if (skipping) {
				skipProgress += delta / SKIP_FADE_DURATION;
				ui.fadeOverlay.style.opacity = String(Math.min(1, skipProgress * 2));
				if (skipProgress >= 1) { skipping = false; void finishCinematic(); }
				return;
			}

			elapsedTime += delta;
			const t = elapsedTime;

			// Decay camera shake
			if (shake.value > 0) shake.value *= Math.pow(0.88, delta * 60);

			// ── Beat 2 (t=0-4): Dormant gate — dark ring, no event horizon ──
			if (t < 4) {
				gateEntrance.innerRingMat.emissiveIntensity = 0.05;
				gateEntrance.gateLight.intensity = 0;
			}

			// ── Beat 3 (t=4-7): Gate activates ───────────────────────────────
			if (t >= 4 && t < 7) {
				const bt = t - 4;
				// Chevrons light up: emissive ramps 0→1.4 over first 1.5s
				gateEntrance.innerRingMat.emissiveIntensity = Math.min(1.4, bt / 1.5 * 1.4);
				// Inner ring spins
				gateEntrance.innerRing.rotation.z += delta * (1.0 + bt * 0.8);
				// Gate light on
				gateEntrance.gateLight.intensity = Math.min(280, bt / 1.5 * 280);

				// Kawoosh fires at t=4.3 (0.3s into beat 3)
				if (bt >= 0.3 && !kawoosh.active && kawoosh.phase !== "done") {
					kawoosh.active       = true;
					kawoosh.group.visible = true;
					kawoosh.disc.scale.setScalar(0.001);
				}
				if (kawoosh.active) updateKawoosh(kawoosh, delta);

				// Event horizon appears after kawoosh (t=5.1 = bt=1.1)
				if (bt >= 1.1) gateEntrance.eventHorizon.visible = true;
				if (bt >= 1.1) {
					const horizonRipple = Math.sin(t * 6.5) * 0.03;
					gateEntrance.eventHorizon.scale.set(1 + horizonRipple, 1 + horizonRipple * 0.8, 1);
					gateEntrance.horizonMat.emissiveIntensity = 1.2 + Math.sin(t * 2.8) * 0.2;
				}
			}

			// Keep event horizon shimmer alive after beat 3
			if (t >= 5.1 && t < 21) {
				const ripple = Math.sin(t * 6.5) * 0.025;
				gateEntrance.eventHorizon.scale.set(1 + ripple, 1 + ripple * 0.8, 1);
				gateEntrance.horizonMat.emissiveIntensity = 1.2 + Math.sin(t * 2.8) * 0.18;
				gateEntrance.gateLight.intensity = 260 + Math.sin(t * 3.5) * 30;
			}

			// ── Beat 4 (t=7-10): Scott comes through ──────────────────────────
			if (t >= 7 && t < 12) {
				if (!scottNpc.group.visible) {
					scottNpc.group.visible = true;
					scottNpc.group.position.set(0, 0, 0.5);
					scottNpc.group.rotation.y = Math.PI;
				}
				arrivalCorridor.group.visible = true;
				// Walk toward -z
				const walkDist = Math.min(2.5, (t - 7) * 1.1);
				scottNpc.group.position.z = 0.5 - walkDist;
				scottPos.copy(scottNpc.group.position);
				scottLight.position.copy(scottPos).setY(scottPos.y + 1.2).setZ(scottPos.z - 0.3);
				scottLight.intensity = 25;

				// Subtitle at t=7.5
				if (t >= 7.5 && t < 7.6) {
					subtitles.show("It's clear — start the evacuation.", 3.0);
				}
			} else {
				scottLight.intensity = 0;
			}

			// ── Beat 5 (t=10-15): evacuation chaos — direct camera ────────────
			if (t >= 10 && t < 15) {
				updateThrownNpcs(beat5Npcs, t - 10, shake);
				// Emergency light flicker
				for (const light of arrivalCorridor.emergencyLights) {
					const dropout = Math.random() < 0.05 ? -20 : 0;
					light.intensity = Math.max(10, 55 + Math.sin(t * 13.3) * 10 + dropout);
				}
			}

			// ── Beat 6 (t=15-19): overhead cut — red emergency only ───────────
			// No extra logic needed; camera is static overhead, corridor already visible.

			// ── Beat 7 (t=19-21): Rush side angle ────────────────────────────
			if (t >= 19 && t < 24) {
				if (!rushNpc.group.visible) {
					rushNpc.group.visible = true;
					rushNpc.group.position.set(0, 0, 0.6);
					rushNpc.group.rotation.y = Math.PI;
				}
				// Walk toward -z at purposeful pace
				const rbt = t - 19;
				const walkDist = Math.min(5, rbt * 1.8);
				rushNpc.group.position.z = 0.6 - walkDist;
				rushPos.copy(rushNpc.group.position);
				// Walk bob
				rushNpc.walkCycle += delta * 4.2;
				rushNpc.group.position.y = Math.abs(Math.sin(rushNpc.walkCycle)) * 0.04;
			}

			// ── Beat 8 (t=21-27): Eli, TJ, Young; gate flicker ───────────────
			if (t >= 21 && t < 27) {
				const bt8 = t - 21;

				// Eli and TJ thrown
				updateThrownNpcs([eliThrow, tjThrow], bt8, shake);

				// Gate flicker: 5-6 rapid opacity pulses at bt8 ≈ 3.8–4.8 (abs t=24.8–25.8)
				if (bt8 >= 3.8 && bt8 < 4.9 && !flickerActive) flickerActive = true;
				if (flickerActive && bt8 < 4.9) {
					const f = Math.sin((bt8 - 3.8) * Math.PI * 11);  // ~11 Hz = ~5.5 cycles/s
					gateEntrance.horizonMat.opacity = 0.88 * Math.max(0, f);
					gateEntrance.horizonMat.emissiveIntensity = 0.5 + Math.max(0, f) * 1.0;
				} else if (flickerActive && bt8 >= 4.9) {
					// Gate off permanently (Young came through last)
					gateEntrance.eventHorizon.visible = false;
					gateEntrance.gateLight.intensity  = 0;
					flickerActive = false;
				}

				// Young thrown at bt8=4.5 (absolute t=25.5)
				updateThrownNpcs([youngThrownNpc], bt8, shake);
				youngPos.copy(youngThrownNpc.body.position);

				// Big impact shake when Young lands
				if (youngThrownNpc.landed && shake.value < 0.05) {
					shake.value = 0.45;
				}
			}

			// ── Beat 9 (t=27-34): player wakes, Scott dialogue, HUD ──────────
			if (t >= 27) {
				// Scott crouches near Eli at t=29
				if (t >= 29 && !scottNpc.group.visible) {
					scottNpc.group.visible = true;
					scottNpc.group.position.set(0.4, 0, -2.0);
					scottNpc.group.rotation.y = -0.6;
					scottPos.copy(scottNpc.group.position);
				}

				// Dialogue panel fades in at t=29.5
				if (t >= 29.5 && t < 30.0) {
					const fadeT = (t - 29.5) / 0.5;
					ui.dialogPanel.style.opacity = String(Math.min(1, fadeT));
				} else if (t >= 30 && t < 32.5) {
					ui.dialogPanel.style.opacity = "1";
				} else if (t >= 32.5 && t < 33.5) {
					ui.dialogPanel.style.opacity = String(Math.max(0, 1 - (t - 32.5)));
				}

				// HUD fade in at t=31
				if (t >= 31) {
					const hudT = Math.min(1, (t - 31) / 2.5);
					ui.hudOverlay.style.opacity  = String(hudT);
					if (hudT > 0.5) ui.questMarker.style.opacity = String((hudT - 0.5) * 2);
				}
			}

			// ── Sparking panels flicker (beats 4-8) ───────────────────────────
			if (t >= 7 && t < 28) {
				for (const panel of arrivalCorridor.sparkingPanels) {
					const mat = panel.material as THREE.MeshStandardMaterial;
					if (Math.random() < 0.025) {
						mat.emissive.set(0xffffff); mat.emissiveIntensity = 2.0 + Math.random() * 2;
					} else {
						mat.emissiveIntensity *= Math.pow(0.6, delta * 60);
						if (mat.emissiveIntensity < 0.4) mat.emissive.set(0x334466);
					}
				}
			}

			// Skip hint fades at end
			if (t >= 26) ui.skipHint.style.opacity = String(Math.max(0, 1 - (t - 26) / 2));

			// Camera beat system
			applyCameraForTime(t);

			// End of cinematic
			if (t >= CINEMATIC_TOTAL_DURATION) void finishCinematic();
		},

		dispose(): void {
			disposed = true;
			window.removeEventListener("keydown", handleKeyDown);
			gateEntrance.dispose();
			arrivalCorridor.dispose();
			scottNpc.dispose();
			rushNpc.dispose();
			eliNpc.dispose();
			tjNpc.dispose();
			youngNpc.dispose();
			kawoosh.dispose();
			subtitles.dispose();
			ui.dispose();
			// Dispose thrown NPC meshes
			for (const npc of [...beat5Npcs, eliThrow, tjThrow, youngThrownNpc]) {
				(npc.body as unknown as { _disposeFn?: () => void })._disposeFn?.();
			}
			scene.remove(scottLight);
			scene.remove(ambientLight);
		},
	};
}

// ─── Scene definition ─────────────────────────────────────────────────────────

export const openingCinematicScene = defineGameScene({
	id: "opening-cinematic",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((m) => m.default),
	}),
	title: "Opening Cinematic",
	player: false,
	mount,
});
