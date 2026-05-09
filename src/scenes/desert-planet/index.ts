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
import { setActiveQuestManager } from "../../systems/active-quest-manager";
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
		// Faceted polyhedron reads as a weathered boulder; deterministic
		// seed-free deform via vertex displacement gives variation without
		// loading external assets.
		const geo = new THREE.DodecahedronGeometry(0.5, 1);
		const pos = geo.attributes.position;
		for (let i = 0; i < pos.count; i++) {
			const jitter = 0.85 + ((i * 31 + def.rot * 17) % 1) * 0.3;
			pos.setX(i, pos.getX(i) * jitter);
			pos.setY(i, pos.getY(i) * jitter);
			pos.setZ(i, pos.getZ(i) * jitter);
		}
		geo.computeVertexNormals();
		const rock = new THREE.Mesh(geo, mat);
		rock.scale.set(def.scale[0], def.scale[1] * 1.2, def.scale[2]);
		rock.position.set(...def.pos);
		// Sink rocks ~10% of their scale into the sand so they ground visually
		// instead of floating like flung debris.
		rock.position.y += (def.scale[1] * 1.2) * -0.1;
		rock.rotation.set(def.rot * 0.4, def.rot, def.rot * 0.2);
		scene.add(rock);
		// Contact shadow: dark elliptical decal flat on the sand at rock base.
		// Larger than rock footprint so the soft edge sells the grounding.
		const shadowGeo = new THREE.CircleGeometry(0.5, 16);
		const shadowMat = new THREE.MeshBasicMaterial({
			color: 0x2a1d10,
			transparent: true,
			opacity: 0.35,
			depthWrite: false,
			fog: false,
		});
		const shadow = new THREE.Mesh(shadowGeo, shadowMat);
		shadow.rotation.x = -Math.PI / 2;
		shadow.scale.set(def.scale[0] * 1.4, def.scale[2] * 1.4, 1);
		shadow.position.set(def.pos[0], 0.02, def.pos[2]);
		scene.add(shadow);
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

	// Chevrons — bright markers around the ring perimeter. Sized large
	// enough to read as iconic SGU triangular indicators; positioned just
	// outside the outer ring tube (radius extent ~3.28) plus pushed forward
	// so they sit on the ring face rather than embedded inside it.
	const chevrons: THREE.Mesh[] = [];
	const CHEVRON_COUNT = 9;
	const chevronRadius = GATE_RADIUS + GATE_TUBE * 2.4;
	// Trapezoidal keystone profile: wider at outer edge, narrow at inner edge —
	// matches canonical stargate chevron silhouette rather than a flat box.
	const chevShape = new THREE.Shape();
	chevShape.moveTo(-0.18, 0.0);   // outer-left corner
	chevShape.lineTo(0.18, 0.0);    // outer-right corner
	chevShape.lineTo(0.10, 0.34);   // inner-right corner
	chevShape.lineTo(-0.10, 0.34);  // inner-left corner
	chevShape.lineTo(-0.18, 0.0);
	const chevGeom = new THREE.ExtrudeGeometry(chevShape, {
		depth: 0.18, bevelEnabled: true, bevelThickness: 0.04,
		bevelSize: 0.03, bevelSegments: 2,
	});
	chevGeom.translate(0, 0, -0.09);  // recenter on z so face protrudes evenly
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		const angle = (i / CHEVRON_COUNT) * Math.PI * 2 - Math.PI / 2;
		const housingMat = new THREE.MeshStandardMaterial({
			color: 0x14243a, roughness: 0.55, metalness: 0.7,
			emissive: 0x080814, emissiveIntensity: 0.2,
		});
		const chev = new THREE.Mesh(chevGeom, housingMat);
		chev.position.set(
			GATE_CENTER.x + Math.cos(angle) * chevronRadius,
			GATE_CENTER.y + Math.sin(angle) * chevronRadius,
			GATE_CENTER.z + GATE_TUBE * 1.5,
		);
		chev.rotation.z = angle - Math.PI / 2;
		scene.add(chev);
		chevrons.push(chev);
		// Inset glow strip: chevron extrudes inward (radius range
		// [chevronRadius - 0.34, chevronRadius]). Place glow at mid-radius on the
		// front face so it reads as a lit-up chevron rather than floating off.
		// Narrow vertical slot reads as a lit chevron blade rather than a square
		// window — preserves the keystone silhouette at viewing distance.
		const glowMat = new THREE.MeshBasicMaterial({ color: 0x88ccff, fog: false, toneMapped: false });
		const glow = new THREE.Mesh(new THREE.BoxGeometry(0.10, 0.20, 0.04), glowMat);
		const glowRadius = chevronRadius - 0.16;
		glow.position.set(
			GATE_CENTER.x + Math.cos(angle) * glowRadius,
			GATE_CENTER.y + Math.sin(angle) * glowRadius,
			GATE_CENTER.z + GATE_TUBE * 1.5 + 0.18,
		);
		glow.rotation.z = angle - Math.PI / 2;
		scene.add(glow);
	}

	// Active event horizon — wormhole is already open when player arrives.
	// CanvasTexture gives the event horizon procedural texture without a
	// ShaderMaterial (WebGPURenderer rejects legacy ShaderMaterial).
	// Radial gradient + concentric ripple bands read as the iconic shimmering
	// wormhole pool, far more cinematic than a flat cyan disc.
	const horizonCanvas = document.createElement("canvas");
	horizonCanvas.width = 512;
	horizonCanvas.height = 512;
	const hctx = horizonCanvas.getContext("2d")!;
	const grad = hctx.createRadialGradient(256, 256, 20, 256, 256, 256);
	grad.addColorStop(0.0, "#88ccff");
	grad.addColorStop(0.25, "#3a7ad8");
	grad.addColorStop(0.55, "#163a78");
	grad.addColorStop(0.85, "#0a2a55");
	grad.addColorStop(1.0, "#06173a");
	hctx.fillStyle = grad;
	hctx.fillRect(0, 0, 512, 512);
	// Turbulent spiral wisps — many thin jittered strokes give the swirl
	// organic churning energy rather than a logo-spiral. Mirrors the
	// gate-room horizon approach.
	hctx.globalCompositeOperation = "lighter";
	const armCount = 16;
	for (let arm = 0; arm < armCount; arm++) {
		const baseAngle = (arm / armCount) * Math.PI * 2;
		const armTwist = Math.PI * (3 + Math.sin(arm * 1.7) * 0.8);
		hctx.beginPath();
		for (let t = 0; t <= 1; t += 0.01) {
			const jitter = Math.sin(t * 18 + arm * 2.3) * 6;
			const r = t * 256 * 0.95 + jitter;
			const a = baseAngle + t * armTwist;
			const x = 256 + Math.cos(a) * r;
			const y = 256 + Math.sin(a) * r;
			if (t === 0) hctx.moveTo(x, y); else hctx.lineTo(x, y);
		}
		const opacity = 0.22 + (arm % 3) * 0.07;
		hctx.strokeStyle = `rgba(180, 220, 255, ${opacity})`;
		hctx.lineWidth = 2 + (arm % 4) * 0.6;
		hctx.lineCap = "round";
		hctx.stroke();
	}
	// Bright speckle turbulence
	for (let i = 0; i < 1400; i++) {
		const r = Math.sqrt(Math.random()) * 240;
		const a = Math.random() * Math.PI * 2;
		const x = 256 + Math.cos(a) * r;
		const y = 256 + Math.sin(a) * r;
		const sz = Math.random() * 2 + 0.4;
		const alpha = (1 - r / 250) * 0.55;
		hctx.fillStyle = `rgba(220, 240, 255, ${alpha})`;
		hctx.beginPath();
		hctx.arc(x, y, sz, 0, Math.PI * 2);
		hctx.fill();
	}
	// Off-center bright spot for asymmetric "swirl" hint
	const swirl = hctx.createRadialGradient(220, 240, 5, 220, 240, 140);
	swirl.addColorStop(0.0, "rgba(220, 240, 255, 0.55)");
	swirl.addColorStop(1.0, "rgba(80, 140, 220, 0)");
	hctx.fillStyle = swirl;
	hctx.fillRect(0, 0, 512, 512);
	const horizonTex = new THREE.CanvasTexture(horizonCanvas);
	horizonTex.colorSpace = THREE.SRGBColorSpace;
	const horizonMat = new THREE.MeshBasicMaterial({
		map: horizonTex,
		transparent: true,
		opacity: 1.0,
		side: THREE.DoubleSide,
		fog: false,
		toneMapped: false,
	});
	const eventHorizon = new THREE.Mesh(
		new THREE.CircleGeometry(GATE_RADIUS - GATE_TUBE - 0.05, 64),
		horizonMat
	);
	eventHorizon.position.copy(GATE_CENTER);
	scene.add(eventHorizon);

	// Additive cyan halo around the open gate — matches gate-room treatment
	// so an active gate reads as glowing rather than as a grey disc.
	// Halo intentionally omitted on desert — additive blending against the
	// bright sky-haze backplate just blooms to white. Gate-room (dark walls)
	// uses an additive halo because the dark backdrop preserves the cyan tint.

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
	// Faceted polyhedron rock body — chalky boulder rather than cardboard box.
	const bodyGeo = new THREE.DodecahedronGeometry(0.6, 1);
	const bodyPos = bodyGeo.attributes.position;
	for (let i = 0; i < bodyPos.count; i++) {
		const j = 0.85 + ((i * 17) % 7) / 20;
		bodyPos.setX(i, bodyPos.getX(i) * j);
		bodyPos.setY(i, bodyPos.getY(i) * j);
		bodyPos.setZ(i, bodyPos.getZ(i) * j);
	}
	bodyGeo.computeVertexNormals();
	const body = new THREE.Mesh(bodyGeo, bodyMat);
	body.scale.set(1.0, 0.85, 0.9);
	body.position.y = 0.5;
	group.add(body);

	// Crystalline top formations — slightly lighter, glowing
	const crystalMat = new THREE.MeshStandardMaterial({
		color: COLOR_CALCIUM_GLOW,
		emissive: COLOR_CALCIUM_GLOW,
		emissiveIntensity: 0.35,
		roughness: 0.3,
		metalness: 0.1,
	});
	// Calcium-carbonate (lime) chunks atop the deposit — chunky pale shards,
	// NOT spiky ice-crystals. Calcium in the SGU "Air" episode reads as
	// chalky, opaque, slightly luminous rock formations roughly fist-sized.
	for (let i = 0; i < 4; i++) {
		const h = 0.12 + (i % 2) * 0.06;
		const chunk = new THREE.Mesh(
			new THREE.DodecahedronGeometry(0.12 + (i % 3) * 0.03, 0),
			crystalMat.clone(),
		);
		// Slight vertical squish so chunks feel like rocks, not gems
		chunk.scale.set(1.0, h * 4.0, 1.0);
		const angle = (i / 4) * Math.PI * 2 + 0.4;
		chunk.position.set(
			Math.cos(angle) * 0.22,
			0.85 + h * 1.5,
			Math.sin(angle) * 0.22,
		);
		chunk.rotation.set(
			(Math.random() - 0.5) * 0.6,
			Math.random() * Math.PI,
			(Math.random() - 0.5) * 0.6,
		);
		group.add(chunk);
	}

	// Interaction glow ring at base — pulses to indicate collectability.
	// Tuned subtle so it reads as a soft ground-glow hint rather than a hard
	// white outline at distance; the pulse animation in updateDesertPlanet
	// brings it forward when the player approaches.
	const glowMat = new THREE.MeshStandardMaterial({
		color: 0xffd066,
		emissive: 0xffaa44,
		emissiveIntensity: 0.35,
		transparent: true,
		opacity: 0.35,
	});
	const glowMesh = new THREE.Mesh(new THREE.RingGeometry(0.7, 0.85, 24), glowMat);
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
	// Dim alien sun — far-off, warm but weak. Reduced for high (3.9) tone-map
	// exposure so the scene doesn't blow out to pure white.
	const sun = new THREE.DirectionalLight(COLOR_SUN, 0.6);
	sun.position.set(30, 60, -20);
	scene.add(sun);

	// Ambient fill from the sandy ground — kept low so the sun reads as
	// directional rather than the whole world being uniformly lit.
	const ambient = new THREE.AmbientLight(0x8a6a3a, 0.18);
	scene.add(ambient);

	// Fog — sandy haze; pulled in to ~25 so distant dunes fade into the
	// horizon rather than reading as a flat backdrop. Color picked low-luma
	// so it doesn't blow out at exposure 3.9.
	scene.fog = new THREE.Fog(0x4a3018, 30, 90);

	// Sky dome — vertex-coloured inverted sphere that gives a horizon
	// gradient. Colors chosen to survive ACES tone-map at exposure 3.9
	// (which pushes mid-tones toward white): use very low-luma source so
	// the visible result is the desired warm desert sky rather than
	// uniformly bleached cream.
	const skyGeo = new THREE.SphereGeometry(220, 32, 16);
	const skyTopColor = new THREE.Color(0x1f2848);    // deep desert-dusk blue zenith
	const skyHorizonColor = new THREE.Color(0xb88560); // warm sand-haze at horizon
	// Mid-band reduces the harsh dark-sky-over-bright-sand edge by introducing
	// a smooth dusty-rust transition between zenith and ground haze.
	const skyMidColor = new THREE.Color(0x6a3a28);
	const colors = new Float32Array(skyGeo.attributes.position.count * 3);
	const pos = skyGeo.attributes.position;
	const tmp = new THREE.Color();
	for (let i = 0; i < pos.count; i++) {
		const y = pos.getY(i);
		// Normalise y from sphere radius range to 0..1 (horizon to zenith).
		const t = Math.max(0, Math.min(1, (y / 220 + 0.05) / 0.95));
		// Three-stop gradient: horizon (sand haze) → mid (rust) → zenith (blue).
		// Smoothly blend through the mid stop at t=0.45 so the horizon doesn't
		// jump straight to deep blue.
		if (t < 0.45) {
			tmp.copy(skyHorizonColor).lerp(skyMidColor, t / 0.45);
		} else {
			tmp.copy(skyMidColor).lerp(skyTopColor, (t - 0.45) / 0.55);
		}
		colors[i * 3] = tmp.r;
		colors[i * 3 + 1] = tmp.g;
		colors[i * 3 + 2] = tmp.b;
	}
	skyGeo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
	const skyMat = new THREE.MeshBasicMaterial({
		vertexColors: true,
		side: THREE.BackSide,
		fog: false,
		depthWrite: false,
	});
	const sky = new THREE.Mesh(skyGeo, skyMat);
	scene.add(sky);

	// Horizon dust haze — soft horizontal billboard sitting at the far
	// horizon, breaking up the hard sand/sky cut that the SG-U "Air"
	// reference softens with dust storms. Camera is at y=1.7 looking
	// roughly horizontal, so a wide thin band at y≈3 reads as ground-level
	// dust suspended in the distance.
	const hazeCanvas = document.createElement("canvas");
	hazeCanvas.width = 1024;
	hazeCanvas.height = 128;
	const hCtx = hazeCanvas.getContext("2d");
	if (hCtx) {
		// Vertical alpha falloff — peak in middle, fade top + bottom.
		const vGrad = hCtx.createLinearGradient(0, 0, 0, 128);
		vGrad.addColorStop(0.0, "rgba(184, 133, 96, 0)");
		vGrad.addColorStop(0.5, "rgba(200, 150, 110, 0.45)");
		vGrad.addColorStop(1.0, "rgba(184, 133, 96, 0)");
		hCtx.fillStyle = vGrad;
		hCtx.fillRect(0, 0, 1024, 128);
		// Random horizontal density variation — breaks up the otherwise
		// uniform band so it reads as plumes of dust, not a flat strip.
		hCtx.globalCompositeOperation = "destination-out";
		for (let i = 0; i < 18; i++) {
			const x = Math.random() * 1024;
			const r = 30 + Math.random() * 120;
			const grad = hCtx.createRadialGradient(x, 64, 0, x, 64, r);
			grad.addColorStop(0, `rgba(0,0,0,${0.15 + Math.random() * 0.25})`);
			grad.addColorStop(1, "rgba(0,0,0,0)");
			hCtx.fillStyle = grad;
			hCtx.fillRect(x - r, 0, r * 2, 128);
		}
	}
	const hazeTex = new THREE.CanvasTexture(hazeCanvas);
	hazeTex.colorSpace = THREE.SRGBColorSpace;
	const hazeMat = new THREE.SpriteMaterial({
		map: hazeTex,
		transparent: true,
		opacity: 0.85,
		depthWrite: false,
		fog: false,
	});
	const haze = new THREE.Sprite(hazeMat);
	haze.position.set(0, 2.5, -75);
	haze.scale.set(220, 9, 1);
	scene.add(haze);
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
	setActiveQuestManager(questManager);

	// ─── World ─────────────────────────────────────────────────────────
	buildLighting(scene);
	buildRocks(scene);

	// Ground tone overlay — large CanvasTexture plane sits just above the
	// runtime.json ground brush and adds dune-scale hue variation. Without
	// it, the ground reads as a flat painted disc at horizon distance because
	// the runtime brush is a single uniform sand color. The pebbles below
	// add micro-detail but can't break up a 120m flat fill at camera height.
	const sandCanvas = document.createElement("canvas");
	sandCanvas.width = 512; sandCanvas.height = 512;
	const sctx = sandCanvas.getContext("2d")!;
	// Base — uses a soft gradient between two warm sand tones so even at
	// uniform-fill scale there's hue motion across the frame.
	sctx.fillStyle = "#c2a065";
	sctx.fillRect(0, 0, 512, 512);
	// Large dune blobs — radial gradients in lighter/darker sand tones,
	// alpha low so they read as patches not stains. Composite source-over
	// for clean tinting (not lighter — tone mapping at exposure 3.9 would
	// blow out additive accumulation per the scene.background memory).
	const sandTones: Array<[number, number, number, number]> = [
		[210, 175, 110, 0.32],  // pale highlight (sun-lit dune crest)
		[155, 115, 60, 0.28],   // shadow band (dune trough)
		[200, 150, 80, 0.22],   // mid warm
		[178, 130, 70, 0.20],   // mid cool sand
	];
	for (let i = 0; i < 36; i++) {
		const x = Math.random() * 512;
		const y = Math.random() * 512;
		const r = 60 + Math.random() * 130;
		const [tr, tg, tb, ta] = sandTones[i % sandTones.length];
		const grad = sctx.createRadialGradient(x, y, 0, x, y, r);
		grad.addColorStop(0, `rgba(${tr},${tg},${tb},${ta})`);
		grad.addColorStop(0.6, `rgba(${tr},${tg},${tb},${ta * 0.4})`);
		grad.addColorStop(1, `rgba(${tr},${tg},${tb},0)`);
		sctx.fillStyle = grad;
		sctx.fillRect(0, 0, 512, 512);
	}
	// Fine sand grain speckle — tiny dark/light dots simulate grains visible
	// near the camera. Sparse enough not to read as a noise pattern.
	for (let i = 0; i < 400; i++) {
		const x = Math.random() * 512;
		const y = Math.random() * 512;
		const dark = Math.random() > 0.55;
		sctx.fillStyle = dark ? "rgba(80,55,28,0.45)" : "rgba(230,200,150,0.4)";
		sctx.fillRect(x, y, 1, 1);
	}
	const sandTex = new THREE.CanvasTexture(sandCanvas);
	sandTex.wrapS = THREE.RepeatWrapping;
	sandTex.wrapT = THREE.RepeatWrapping;
	sandTex.repeat.set(6, 6);
	sandTex.colorSpace = THREE.SRGBColorSpace;
	const sandOverlay = new THREE.Mesh(
		new THREE.PlaneGeometry(120, 120),
		new THREE.MeshBasicMaterial({
			map: sandTex, transparent: true, opacity: 0.9, fog: true,
		}),
	);
	sandOverlay.rotation.x = -Math.PI / 2;
	sandOverlay.position.y = 0.01; // just above runtime ground brush top face (y=0)
	scene.add(sandOverlay);

	// Ground (from scene.runtime.json — inherits tan colour from manifest)
	// Sand-grain scatter with color variation — many tiny flat pebbles in
	// 4 tonal bands break up the flat sand color when seen from camera height.
	const pebbleGeo = new THREE.DodecahedronGeometry(0.18, 0);
	const pebbleColors = [0xb09050, 0xa68545, 0xc2a572, 0x8e6d3a];
	const pebbleMats = pebbleColors.map(
		(c) => new THREE.MeshStandardMaterial({ color: c, roughness: 1.0, metalness: 0.0 })
	);
	for (let i = 0; i < 220; i++) {
		const pebble = new THREE.Mesh(pebbleGeo, pebbleMats[i % pebbleMats.length]);
		const sx = 0.45 + Math.random() * 0.9;
		const sz = 0.45 + Math.random() * 0.9;
		const sy = 0.25 + Math.random() * 0.35;
		pebble.scale.set(sx, sy, sz);
		pebble.position.set(
			(Math.random() - 0.5) * 80,
			0.04,
			(Math.random() - 0.5) * 80
		);
		pebble.rotation.set(Math.random() * 0.5, Math.random() * Math.PI, Math.random() * 0.5);
		scene.add(pebble);
	}

	// ─── Stargate (player arrived through it — already active) ──────────
	const gate = buildStargate(scene);

	// ─── Calcium deposits ───────────────────────────────────────────────
	const deposits = CALCIUM_POSITIONS.map((pos) => buildCalciumDeposit(scene, pos));
	let collectedCount = 0;
	const totalDeposits = deposits.length;

	// Deposit marker beams — faint vertical glow to help player locate them.
	// Kept short (1.4m) and very low emissive so they read as a soft ground
	// halo near each deposit rather than as ice-spike pillars dotting the
	// horizon. The interaction ring at the deposit base is the primary
	// visual cue — these beams just add a subtle glow rim.
	const beamMat = new THREE.MeshBasicMaterial({
		color: COLOR_CALCIUM_GLOW,
		transparent: true,
		opacity: 0.18,
		depthWrite: false,
		fog: true,
	});
	for (const dep of deposits) {
		const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.32, 1.4, 8, 1, true), beamMat);
		beam.position.copy(dep.position).add(new THREE.Vector3(0, 0.7, 0));
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

			// Pulse event horizon — opaque cyan with subtle breathing.
			const horizonMat = gate.eventHorizon.material as THREE.MeshBasicMaterial;
			const pulse = Math.sin(gateElapsed * 2.0) * 0.04;
			horizonMat.opacity = 0.96 + pulse;
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
			setActiveQuestManager(null);
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
		vrmUrl: "/assets/characters/eli-wallace/eli-wallace.vrm",
	},
	mount,
});
