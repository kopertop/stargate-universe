/**
 * Opening Cinematic — SGU S1E1 "Air Part 1"
 *
 * Rebuilt from scratch.  Uses the SAME room geometry and lighting as the
 * gate-room gameplay scene (imported from shared-builders) and loads real
 * VRM crew characters via loadCrewMember().  Only camera + input differ —
 * StarterPlayerController is disabled (player: false) for the full sequence.
 *
 * Beat timeline:
 *   Beat 2  (0  – 4 s)  Dormant gate push-in
 *   Beat 3  (4  – 7 s)  Chevrons light + Kawoosh burst
 *   Beat 4  (7  –10 s)  Scott steps through (VRM, flashlight, subtitle)
 *   Beat 5  (10 –15 s)  Direct-camera flythrough — 4 crew shoot out
 *   Beat 6  (15 –19 s)  Hard-cut overhead — bodies scatter, sparks
 *   Beat 7  (19 –21 s)  Rush lands clean, walks off purposefully
 *   Beat 8  (21 –27 s)  Eli tumbles / TJ / gate flickers / Young slumps
 *   Beat 9  (27 –35 s)  Low angle, Eli wakes, Scott line, HUD + quest in
 *
 * Beat 1 (start screen) is handled by src/scenes/start-screen.
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import {
	GATE_CENTER, CHEVRON_COUNT,
	COLOR_CHEVRON_ON,
	buildRoom, buildStargate, buildLighting,
	type GateRuntime,
} from "../gate-room/shared-builders";
import { loadCrewMember, type CharacterLoadResult } from "../../characters/character-loader";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// Suppress "unused import" for GateRuntime — referenced only as a type guard
const _gateRuntimeRef: GateRuntime | undefined = undefined;
void _gateRuntimeRef;

// ─── Beat timing (seconds from cinematic start) ───────────────────────────────

const T_CHEVRON_START   =  4.0;
const T_KAWOOSH_BURST   =  4.8;  // disc expands 0 → 3.5 × over 0.4 s
const T_KAWOOSH_SETTLE  =  5.2;  // disc snaps to 0.05 × (stable event horizon)
const T_SCOTT_ENTER     =  7.0;  // Scott walks through gate
const T_SUBTITLE_SCOTT  =  9.0;  // "It's clear — start the evacuation."
const T_FLYTHROUGH      = 10.0;  // camera inside gate; 4 crew shoot out
const T_OVERHEAD        = 15.0;  // hard cut straight down
const T_RUSH_LAND       = 19.0;  // Rush slides through, lands on feet
const T_ELI_ENTER       = 21.0;  // Eli tumbles through
const T_TJ_ENTER        = 22.5;  // TJ comes through
const T_FLICKER_START   = 24.0;  // gate begins flickering (8 × over 1.2 s)
const T_YOUNG_ENTER     = 25.2;  // Young shoots through at maximum speed
const T_GATE_CLOSE      = 25.4;  // event horizon permanently closes
const T_WAKE_START      = 27.0;  // camera at ground level, Eli prone
const T_HUD_START       = 30.0;  // HUD fades in
const T_QUEST_START     = 31.5;  // quest marker appears
const T_TOTAL           = 35.0;

// ─── Easing + progress helpers ────────────────────────────────────────────────

const easeIn    = (t: number) => t * t;
const easeOut   = (t: number) => 1 - (1 - t) * (1 - t);

const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
const beatProgress = (start: number, end: number, t: number) =>
	clamp01((t - start) / (end - start));

// ─── Kawoosh disc ─────────────────────────────────────────────────────────────
//
// Separate CircleGeometry using AdditiveBlending so it composites cleanly on
// top of the event horizon disc without depth-write conflicts.

type KawooshDisc = { mesh: THREE.Mesh; dispose: () => void };

const createKawooshDisc = (scene: THREE.Scene): KawooshDisc => {
	const mat = new THREE.MeshBasicMaterial({
		color:       0x44aaff,
		transparent: true,
		opacity:     0.9,
		side:        THREE.DoubleSide,
		blending:    THREE.AdditiveBlending,
		depthWrite:  false,
	});
	const mesh = new THREE.Mesh(new THREE.CircleGeometry(1.95, 64), mat);
	mesh.position.set(GATE_CENTER.x, GATE_CENTER.y, GATE_CENTER.z + 0.04);
	mesh.scale.setScalar(0);
	scene.add(mesh);
	return {
		mesh,
		dispose: () => { scene.remove(mesh); mat.dispose(); mesh.geometry.dispose(); },
	};
};

// ─── Spark particle emitters ──────────────────────────────────────────────────

const SPARK_COUNT = 50;

type SparkEmitter = {
	mesh:       THREE.Points;
	positions:  Float32Array;
	velocities: Float32Array;
	lifetimes:  Float32Array;
	origin:     THREE.Vector3;
	active:     boolean;
	dispose:    () => void;
};

const createSparkEmitter = (scene: THREE.Scene, origin: THREE.Vector3): SparkEmitter => {
	const positions  = new Float32Array(SPARK_COUNT * 3);
	const velocities = new Float32Array(SPARK_COUNT * 3);
	const lifetimes  = new Float32Array(SPARK_COUNT);

	for (let i = 0; i < SPARK_COUNT; i++) {
		positions[i * 3]     = origin.x;
		positions[i * 3 + 1] = origin.y;
		positions[i * 3 + 2] = origin.z;
		lifetimes[i]         = -Math.random() * 1.5; // staggered starts
	}

	const geo = new THREE.BufferGeometry();
	geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));

	const mat = new THREE.PointsMaterial({
		color:       0xffcc44,
		size:        0.07,
		transparent: true,
		opacity:     0.95,
		depthWrite:  false,
	});
	const mesh = new THREE.Points(geo, mat);
	scene.add(mesh);

	return {
		mesh, positions, velocities, lifetimes, origin,
		active:  false,
		dispose: () => { scene.remove(mesh); geo.dispose(); mat.dispose(); },
	};
};

const updateSparkEmitter = (em: SparkEmitter, delta: number): void => {
	if (!em.active) return;
	for (let i = 0; i < SPARK_COUNT; i++) {
		em.lifetimes[i] += delta;
		if (em.lifetimes[i] < 0) continue;

		if (em.lifetimes[i] > 1.0 || em.positions[i * 3 + 1] < -0.5) {
			em.positions[i * 3]     = em.origin.x + (Math.random() - 0.5) * 0.15;
			em.positions[i * 3 + 1] = em.origin.y;
			em.positions[i * 3 + 2] = em.origin.z + (Math.random() - 0.5) * 0.15;
			em.velocities[i * 3]     = (Math.random() - 0.5) * 1.8;
			em.velocities[i * 3 + 1] = 1.8 + Math.random() * 2.2;
			em.velocities[i * 3 + 2] = (Math.random() - 0.5) * 1.8;
			em.lifetimes[i]          = 0;
		}
		em.positions[i * 3]     += em.velocities[i * 3]     * delta;
		em.positions[i * 3 + 1] += em.velocities[i * 3 + 1] * delta;
		em.positions[i * 3 + 2] += em.velocities[i * 3 + 2] * delta;
		em.velocities[i * 3 + 1] -= 6.0 * delta;
	}
	(em.mesh.geometry.getAttribute("position") as THREE.BufferAttribute).needsUpdate = true;
};

// ─── Cinematic UI ─────────────────────────────────────────────────────────────

type CinUI = {
	subtitle:    HTMLDivElement;
	fadeOverlay: HTMLDivElement;
	impactFlash: HTMLDivElement;
	hud:         HTMLDivElement;
	questMarker: HTMLDivElement;
	skipHint:    HTMLDivElement;
	dispose:     () => void;
};

const createCinUI = (): CinUI => {
	const subtitle = document.createElement("div");
	Object.assign(subtitle.style, {
		position:     "fixed",
		bottom:       "64px",
		left:         "50%",
		transform:    "translateX(-50%)",
		color:        "#ffffff",
		background:   "rgba(0,0,0,0.60)",
		fontFamily:   "'Courier New', monospace",
		fontSize:     "22px",
		fontStyle:    "italic",
		padding:      "8px 24px",
		borderRadius: "999px",
		pointerEvents:"none",
		userSelect:   "none",
		zIndex:       "80",
		opacity:      "0",
		transition:   "opacity 0.4s ease",
		whiteSpace:   "nowrap",
	});
	document.body.appendChild(subtitle);

	const fadeOverlay = document.createElement("div");
	Object.assign(fadeOverlay.style, {
		position:     "fixed",
		inset:        "0",
		background:   "black",
		opacity:      "0",
		pointerEvents:"none",
		zIndex:       "50",
	});
	document.body.appendChild(fadeOverlay);

	const impactFlash = document.createElement("div");
	Object.assign(impactFlash.style, {
		position:     "fixed",
		inset:        "0",
		background:   "white",
		opacity:      "0",
		pointerEvents:"none",
		zIndex:       "60",
	});
	document.body.appendChild(impactFlash);

	// HUD
	const hud = document.createElement("div");
	Object.assign(hud.style, {
		position:     "fixed",
		inset:        "0",
		opacity:      "0",
		pointerEvents:"none",
		zIndex:       "10",
		transition:   "opacity 1.2s ease",
	});
	const topBar = document.createElement("div");
	Object.assign(topBar.style, {
		position:     "absolute",
		top:          "14px",
		left:         "50%",
		transform:    "translateX(-50%)",
		color:        "#4488ff",
		fontFamily:   "'Courier New', monospace",
		fontSize:     "13px",
		letterSpacing:"4px",
		textShadow:   "0 0 12px #4488ff55",
		whiteSpace:   "nowrap",
	});
	topBar.textContent = "DESTINY  \u00b7  LOCATION UNKNOWN";
	hud.appendChild(topBar);
	const bottomBar = document.createElement("div");
	Object.assign(bottomBar.style, {
		position:     "absolute",
		bottom:       "22px",
		left:         "50%",
		transform:    "translateX(-50%)",
		color:        "rgba(68,136,255,0.5)",
		fontFamily:   "'Courier New', monospace",
		fontSize:     "11px",
		letterSpacing:"2px",
		whiteSpace:   "nowrap",
	});
	bottomBar.textContent = "CO\u2082: CRITICAL   \u00b7   WASD \u00b7 MOVE   \u00b7   E \u00b7 INTERACT";
	hud.appendChild(bottomBar);
	document.body.appendChild(hud);

	// Quest marker — built with safe DOM methods (no innerHTML)
	const questMarker = document.createElement("div");
	Object.assign(questMarker.style, {
		position:     "fixed",
		top:          "50%",
		right:        "28px",
		transform:    "translateY(-50%)",
		color:        "#ffaa44",
		fontFamily:   "'Courier New', monospace",
		fontSize:     "12px",
		lineHeight:   "1.6",
		opacity:      "0",
		pointerEvents:"none",
		zIndex:       "10",
		textAlign:    "right",
		borderRight:  "1px solid rgba(255,170,68,0.35)",
		paddingRight: "12px",
		transition:   "opacity 1s ease",
	});
	const qLabel = document.createElement("div");
	qLabel.style.letterSpacing = "2px";
	qLabel.style.marginBottom  = "4px";
	qLabel.textContent = "\u25b8 NEW QUEST";
	const qTitle = document.createElement("div");
	qTitle.style.fontSize = "11px";
	qTitle.style.opacity  = "0.85";
	qTitle.textContent = "Find Dr. Rush";
	const qDesc = document.createElement("div");
	qDesc.style.fontSize  = "10px";
	qDesc.style.opacity   = "0.6";
	qDesc.style.marginTop = "2px";
	qDesc.textContent = "Locate Dr. Nicholas Rush";
	questMarker.appendChild(qLabel);
	questMarker.appendChild(qTitle);
	questMarker.appendChild(qDesc);
	document.body.appendChild(questMarker);

	const skipHint = document.createElement("div");
	Object.assign(skipHint.style, {
		position:     "fixed",
		bottom:       "20px",
		right:        "24px",
		color:        "rgba(68,136,255,0.5)",
		fontFamily:   "'Courier New', monospace",
		fontSize:     "13px",
		pointerEvents:"none",
		userSelect:   "none",
		zIndex:       "100",
	});
	skipHint.textContent = "[Space]  Skip";
	document.body.appendChild(skipHint);

	return {
		subtitle, fadeOverlay, impactFlash, hud, questMarker, skipHint,
		dispose: () => {
			subtitle.remove();
			fadeOverlay.remove();
			impactFlash.remove();
			hud.remove();
			questMarker.remove();
			skipHint.remove();
		},
	};
};

const showSubtitle = (ui: CinUI, text: string) => {
	ui.subtitle.textContent = text;
	ui.subtitle.style.opacity = "1";
};
const hideSubtitle = (ui: CinUI) => { ui.subtitle.style.opacity = "0"; };

// ─── VRM crew loading with primitive fallback ─────────────────────────────────

type CrewHandle = {
	root:    THREE.Group;
	update:  (delta: number) => void;
	dispose: () => void;
};

const createFallbackMesh = (): CrewHandle => {
	const group   = new THREE.Group();
	const bodyMat = new THREE.MeshStandardMaterial({ color: 0x222230, roughness: 0.8, metalness: 0.1 });
	const headMat = new THREE.MeshStandardMaterial({ color: 0xd4926a, roughness: 0.75, metalness: 0 });
	const bodyGeo = new THREE.CylinderGeometry(0.2, 0.2, 1.0, 8);
	const headGeo = new THREE.SphereGeometry(0.16, 8, 6);
	const torso   = new THREE.Mesh(bodyGeo, bodyMat);
	torso.position.y = 0.6;
	group.add(torso);
	const head = new THREE.Mesh(headGeo, headMat);
	head.position.y = 1.25;
	group.add(head);
	return {
		root:    group,
		update:  () => { /* no VRM spring-bones */ },
		dispose: () => {
			bodyGeo.dispose(); headGeo.dispose();
			bodyMat.dispose(); headMat.dispose();
		},
	};
};

const loadCrew = async (scene: THREE.Scene, id: string): Promise<CrewHandle> => {
	try {
		const result: CharacterLoadResult = await loadCrewMember(id);
		result.root.visible = false;
		scene.add(result.root);
		return { root: result.root, update: result.update, dispose: result.dispose };
	} catch {
		console.warn(`[Cinematic] VRM load failed for "${id}" — using fallback`);
		const fb = createFallbackMesh();
		fb.root.visible = false;
		scene.add(fb.root);
		return fb;
	}
};

// ─── Flying NPC state (Beat 5) ────────────────────────────────────────────────

type FlyingNpc = {
	handle:    CrewHandle;
	startTime: number;
	startPos:  THREE.Vector3;
	vx: number; vy: number; vz: number;
	landPos:   THREE.Vector3;
	landed:    boolean;
	impacted:  boolean;
};

// ─── Mount ────────────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene, renderer } = context;

	renderer.shadowMap.enabled = false;
	scene.background = new THREE.Color(0x020208);
	scene.fog = new THREE.Fog(0x020208, 22, 65);

	const ambient = new THREE.AmbientLight(0x06091a, 3.0);
	scene.add(ambient);

	// ── SHARED gate-room geometry (identical to gameplay) ─────────────────────
	const debugObjects: THREE.Object3D[] = [];
	buildRoom(scene);
	const gate    = buildStargate(scene);
	const lights  = buildLighting(scene, debugObjects);

	// ── Kawoosh disc ───────────────────────────────────────────────────────────
	const kawoosh = createKawooshDisc(scene);

	// ── Scott's flashlight (PointLight attached to hand position) ─────────────
	const scottFlashlight = new THREE.PointLight(0xfff8e8, 0, 14, 1.8);
	scene.add(scottFlashlight);

	// ── Emergency red overhead lights ─────────────────────────────────────────
	const redLights: THREE.PointLight[] = [];
	for (let z = -8; z <= 16; z += 6) {
		const rl = new THREE.PointLight(0xff2200, 50, 10, 1.5);
		rl.position.set(0, 7.2, z);
		scene.add(rl);
		redLights.push(rl);
	}

	// ── Spark emitters for damaged wall panels (Beat 6 overhead) ──────────────
	const sparks: SparkEmitter[] = [
		createSparkEmitter(scene, new THREE.Vector3(-10, 4.5,  3)),
		createSparkEmitter(scene, new THREE.Vector3( 11, 5.0,  9)),
		createSparkEmitter(scene, new THREE.Vector3( -9, 3.5, 14)),
	];

	// ── UI ────────────────────────────────────────────────────────────────────
	const ui = createCinUI();

	// ── Load VRM crew (non-blocking; fallback mesh used if VRM missing) ────────
	const [scottH, rushH, eliH, tjH, youngH, greerH, crewAH, crewBH] = await Promise.all([
		loadCrew(scene, "matthew-scott"),
		loadCrew(scene, "nicholas-rush"),
		loadCrew(scene, "eli-wallace"),
		loadCrew(scene, "tamara-johansen"),
		loadCrew(scene, "everett-young"),
		loadCrew(scene, "ronald-greer"),
		loadCrew(scene, "chloe-armstrong"),
		loadCrew(scene, "camile-wray"),
	]);

	// Beat-5 flythrough NPCs: Young, Greer, CrewA, CrewB — staggered 0.8 s
	const flyNpcs: FlyingNpc[] = [
		{ handle: youngH, startTime: T_FLYTHROUGH,       startPos: new THREE.Vector3(-0.3, GATE_CENTER.y, GATE_CENTER.z - 1.5), vx:  0.3, vy: 2.5, vz:  9.0, landPos: new THREE.Vector3(-8, 0.5, 16), landed: false, impacted: false },
		{ handle: greerH, startTime: T_FLYTHROUGH + 0.8, startPos: new THREE.Vector3( 0.4, GATE_CENTER.y, GATE_CENTER.z - 1.5), vx: -0.2, vy: 3.0, vz: 10.5, landPos: new THREE.Vector3( 9, 0.5, 18), landed: false, impacted: false },
		{ handle: crewAH, startTime: T_FLYTHROUGH + 1.6, startPos: new THREE.Vector3(-0.2, GATE_CENTER.y, GATE_CENTER.z - 1.5), vx:  0.1, vy: 2.0, vz:  9.5, landPos: new THREE.Vector3(-5, 0.5, 20), landed: false, impacted: false },
		{ handle: crewBH, startTime: T_FLYTHROUGH + 2.4, startPos: new THREE.Vector3( 0.5, GATE_CENTER.y, GATE_CENTER.z - 1.5), vx: -0.4, vy: 2.8, vz: 11.0, landPos: new THREE.Vector3( 7, 0.5, 15), landed: false, impacted: false },
	];

	// ── State ─────────────────────────────────────────────────────────────────
	const urlParams = new URLSearchParams(window.location.search);
	let elapsed     = parseFloat(urlParams.get("cinematicTime") ?? "0") || 0;
	let disposed    = false;
	let transitioning = false;

	const shake = { intensity: 0 };
	const camLookAt = new THREE.Vector3().copy(GATE_CENTER);

	let gatePermClosed = false;
	let flickerClock   = 0;
	let flickerCount   = 0;
	let youngSlumped   = false;
	let scottWalkPhase = 0;
	let rushWalkPhase  = 0;
	let scottSubShown  = false;
	let wakeSubShown   = false;

	camera.fov  = 65;
	camera.near = 0.1;
	camera.far  = 200;
	camera.updateProjectionMatrix();
	camera.position.set(0, 2.5, 12);

	let skipping     = false;
	let skipProgress = 0;
	const onKeyDown  = (e: KeyboardEvent) => {
		if ((e.code === "Space" || e.code === "Escape") && !skipping) skipping = true;
	};
	window.addEventListener("keydown", onKeyDown);

	const finish = async () => {
		if (disposed || transitioning) return;
		transitioning = true;
		await gotoScene("gate-room");
	};

	// ─── Update loop ──────────────────────────────────────────────────────────
	return {
		update(delta: number): void {
			if (disposed) return;

			if (skipping) {
				skipProgress += delta / 0.6;
				ui.fadeOverlay.style.background = "black";
				ui.fadeOverlay.style.opacity    = String(Math.min(1, skipProgress * 2));
				if (skipProgress >= 1) { skipping = false; void finish(); }
				return;
			}

			elapsed += delta;
			const t = elapsed;

			// Advance VRM spring-bone physics for all crew
			for (const h of [scottH, rushH, eliH, tjH, youngH, greerH, crewAH, crewBH]) {
				h.update(delta);
			}

			// ══ BEAT 2: DORMANT GATE (0 – 4 s) ══════════════════════════════
			if (t < T_CHEVRON_START) {
				const p = easeIn(beatProgress(0, 4, t));
				camera.position.lerpVectors(
					new THREE.Vector3(0, 2.5, 12),
					new THREE.Vector3(0, 2.5, 5.0),
					p,
				);
				camera.up.set(0, 1, 0);
				camLookAt.copy(GATE_CENTER);
			}

			// ══ BEAT 3: KAWOOSH (4 – 7 s) ════════════════════════════════════

			// Chevrons light up sequentially 4.0 → 4.8 s
			if (t >= T_CHEVRON_START && t < T_KAWOOSH_BURST) {
				const litCount = Math.floor(beatProgress(T_CHEVRON_START, T_KAWOOSH_BURST, t) * CHEVRON_COUNT);
				for (let i = 0; i < CHEVRON_COUNT; i++) {
					if (i < litCount) {
						const mat = gate.chevronMeshes[i].material as THREE.MeshStandardMaterial;
						mat.color.set(COLOR_CHEVRON_ON);
						mat.emissive.set(COLOR_CHEVRON_ON);
						mat.emissiveIntensity = 2.0;
					}
				}
				camera.position.lerpVectors(
					new THREE.Vector3(0, 2.5, 5.0),
					new THREE.Vector3(0, 2.5, 3.2),
					beatProgress(T_CHEVRON_START, T_KAWOOSH_BURST, t),
				);
				camera.up.set(0, 1, 0);
				camLookAt.copy(GATE_CENTER);
			}

			// All chevrons ON once burst starts
			if (t >= T_KAWOOSH_BURST) {
				for (const ch of gate.chevronMeshes) {
					const mat = ch.material as THREE.MeshStandardMaterial;
					mat.color.set(COLOR_CHEVRON_ON);
					mat.emissive.set(COLOR_CHEVRON_ON);
					mat.emissiveIntensity = 2.0;
				}
			}

			// Kawoosh disc: scales 0 → 3.5 × in 0.4 s
			if (t >= T_KAWOOSH_BURST && t < T_KAWOOSH_SETTLE) {
				const kp = beatProgress(T_KAWOOSH_BURST, T_KAWOOSH_SETTLE, t);
				kawoosh.mesh.scale.setScalar(kp * 3.5);
				ui.impactFlash.style.opacity = String(Math.max(0, 0.6 - kp * 0.6));
				camera.position.set(0, 2.5, 3.2);
				camera.up.set(0, 1, 0);
				camLookAt.copy(GATE_CENTER);
			}

			// Settle: disc → 0.05 ×, event horizon appears
			if (t >= T_KAWOOSH_SETTLE && t < T_SCOTT_ENTER) {
				kawoosh.mesh.scale.setScalar(0.05);
				gate.eventHorizon.visible = true;
				const hMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;
				hMat.opacity = Math.min(0.88, beatProgress(T_KAWOOSH_SETTLE, T_SCOTT_ENTER, t) * 1.3);
				camera.position.lerpVectors(
					new THREE.Vector3(0, 2.5, 3.2),
					new THREE.Vector3(0, 2.5, 2.0),
					easeOut(beatProgress(T_KAWOOSH_SETTLE, T_SCOTT_ENTER, t)),
				);
				camera.up.set(0, 1, 0);
				camLookAt.copy(GATE_CENTER);
			}

			// Event horizon ripple while active
			if (t >= T_KAWOOSH_SETTLE && !gatePermClosed) {
				const ripple = 1 + Math.sin(t * 7.5) * 0.015;
				gate.eventHorizon.scale.set(ripple, ripple * 0.98, 1);
				const hMat = gate.eventHorizon.material as THREE.MeshStandardMaterial;
				hMat.emissiveIntensity = 0.8 + Math.sin(t * 3.2) * 0.2;
			}

			// ══ BEAT 4: SCOTT (7 – 10 s) ══════════════════════════════════════
			if (t >= T_SCOTT_ENTER && t < T_FLYTHROUGH) {
				scottH.root.visible = true;
				scottWalkPhase += delta;
				scottH.root.position.set(0.3, 0, GATE_CENTER.z + scottWalkPhase * 1.8);
				scottH.root.rotation.set(0, Math.PI, 0);

				scottFlashlight.intensity = 20 + Math.sin(t * 4.8) * 1.5;
				scottFlashlight.position.copy(scottH.root.position)
					.add(new THREE.Vector3(0.35, 1.0, 0.3));

				camera.position.lerpVectors(
					new THREE.Vector3(5, 2.0, GATE_CENTER.z),
					new THREE.Vector3(6, 1.8, GATE_CENTER.z + 6),
					easeOut(beatProgress(T_SCOTT_ENTER, T_FLYTHROUGH, t)),
				);
				camera.up.set(0, 1, 0);
				camLookAt.set(
					scottH.root.position.x,
					scottH.root.position.y + 1.0,
					scottH.root.position.z,
				);

				if (t >= T_SUBTITLE_SCOTT && !scottSubShown) {
					scottSubShown = true;
					showSubtitle(ui, "\u201cIt\u2019s clear \u2014 start the evacuation.\u201d");
				}
				if (t >= T_SUBTITLE_SCOTT + 2.2) hideSubtitle(ui);
			}

			// ══ BEAT 5: FLYTHROUGH (10 – 15 s) ════════════════════════════════
			// Camera inside gate ring, looking OUTWARD toward room.
			// NPCs emerge from wormhole side (z < GATE_CENTER.z) and fly outward.
			if (t >= T_FLYTHROUGH && t < T_OVERHEAD) {
				camera.position.set(GATE_CENTER.x, GATE_CENTER.y, GATE_CENTER.z + 0.5);
				camera.up.set(0, 1, 0);
				camLookAt.set(GATE_CENTER.x, GATE_CENTER.y - 0.4, GATE_CENTER.z + 14);

				for (const npc of flyNpcs) {
					if (t < npc.startTime) continue;
					const ft = t - npc.startTime;
					if (npc.landed) continue;

					npc.handle.root.visible = true;
					// Parabolic arc: pos.y = startY + vy·t − 4.9·t²
					const nx = npc.startPos.x + npc.vx * ft;
					const ny = npc.startPos.y + npc.vy * ft - 4.9 * ft * ft;
					const nz = npc.startPos.z + npc.vz * ft;
					npc.handle.root.position.set(nx, Math.max(0.5, ny), nz);
					npc.handle.root.rotation.x = ft * 2.8;
					npc.handle.root.rotation.z = ft * 1.2;

					// NPC passes through camera plane → impact flash + shake
					if (!npc.impacted && nz > GATE_CENTER.z + 0.4) {
						npc.impacted = true;
						shake.intensity = 0.15;
						ui.impactFlash.style.opacity = "0.7";
						const flashTimeout = setTimeout(
							() => { if (!disposed) ui.impactFlash.style.opacity = "0"; },
							140,
						);
						void flashTimeout;
					}

					if (ny < 0.5 || nz > 19) {
						npc.landed = true;
						npc.handle.root.position.copy(npc.landPos);
						npc.handle.root.rotation.set(Math.PI / 2, Math.random() * Math.PI, 0.3);
					}
				}
			}

			// ══ BEAT 6: OVERHEAD (15 – 19 s) — hard cut ═══════════════════════
			if (t >= T_OVERHEAD && t < T_RUSH_LAND) {
				camera.position.set(0, 12, 5);
				camera.up.set(0, 0, -1);
				camLookAt.set(0, 0, 5);

				for (const s of sparks) s.active = true;

				for (const rl of redLights) {
					rl.intensity = Math.max(18,
						50 + Math.sin(t * 14.2 + rl.position.z) * 20
						+ (Math.random() < 0.04 ? -25 : 0));
				}
			}

			if (t >= T_OVERHEAD) {
				for (const s of sparks) updateSparkEmitter(s, delta);
			}

			// ══ BEAT 7: RUSH (19 – 21 s) ══════════════════════════════════════
			if (t >= T_RUSH_LAND && t < T_ELI_ENTER) {
				camera.up.set(0, 1, 0);
				rushH.root.visible = true;
				rushWalkPhase += delta;

				if (rushWalkPhase < 1.0) {
					// Lands on feet
					rushH.root.position.set(0.2, 0, GATE_CENTER.z + rushWalkPhase * 3);
					rushH.root.rotation.set(0, Math.PI, 0);
				} else {
					// Walks purposefully off-frame (-X toward corridor)
					const wt = rushWalkPhase - 1.0;
					rushH.root.position.set(-wt * 1.6, Math.abs(Math.sin(wt * 4.5)) * 0.04, GATE_CENTER.z + 3);
					rushH.root.rotation.set(0, -Math.PI / 2, 0);
				}

				camera.position.lerpVectors(
					new THREE.Vector3(5.5, 1.6, GATE_CENTER.z + 1),
					new THREE.Vector3(5.5, 1.6, GATE_CENTER.z + 5),
					beatProgress(T_RUSH_LAND, T_ELI_ENTER, t),
				);
				camLookAt.set(
					rushH.root.position.x,
					rushH.root.position.y + 1.2,
					rushH.root.position.z,
				);
			}

			// ══ BEAT 8: ELI / TJ / YOUNG (21 – 27 s) ════════════════════════
			if (t >= T_ELI_ENTER) {
				camera.up.set(0, 1, 0);
				eliH.root.visible = true;
				tjH.root.visible  = t >= T_TJ_ENTER;
				youngH.root.visible = t >= T_YOUNG_ENTER;

				// Eli tumbles and lands hard
				const eliT = Math.max(0, t - T_ELI_ENTER);
				if (eliT < 0.9) {
					const ny = GATE_CENTER.y + 2.0 * eliT - 4.9 * eliT * eliT;
					eliH.root.position.set(0.5, Math.max(0.5, ny), GATE_CENTER.z + eliT * 4.5);
					eliH.root.rotation.x = eliT * 5;
				} else {
					eliH.root.position.set(0.5, 0.3, GATE_CENTER.z + 4);
					eliH.root.rotation.set(Math.PI / 2, 0.3, 0);
				}

				// TJ
				if (t >= T_TJ_ENTER) {
					const tjT = t - T_TJ_ENTER;
					if (tjT < 0.7) {
						const ny = GATE_CENTER.y + 1.5 * tjT - 4.9 * tjT * tjT;
						tjH.root.position.set(-0.4, Math.max(0.5, ny), GATE_CENTER.z + tjT * 5);
						tjH.root.rotation.x = tjT * 4;
					} else {
						tjH.root.position.set(-0.4, 0.3, GATE_CENTER.z + 3.5);
						tjH.root.rotation.set(Math.PI / 2, -0.2, 0);
					}
				}

				// Gate flickers: 8 × over 1.2 s
				if (t >= T_FLICKER_START && t < T_GATE_CLOSE && !gatePermClosed) {
					flickerClock += delta;
					const interval = 1.2 / 8;
					while (flickerClock > interval) {
						flickerClock -= interval;
						flickerCount++;
						const on = flickerCount % 2 === 0;
						(gate.eventHorizon.material as THREE.MeshStandardMaterial).opacity = on ? 0.88 : 0;
						kawoosh.mesh.scale.setScalar(on ? 0.05 : 0);
					}
				}

				// Young shoots through at maximum speed
				if (t >= T_YOUNG_ENTER && !youngSlumped) {
					const yT = t - T_YOUNG_ENTER;
					const ny = GATE_CENTER.y + 0.4 * yT - 4.9 * yT * yT;
					youngH.root.position.set(-0.2, Math.max(0, ny), GATE_CENTER.z + yT * 14);
					youngH.root.rotation.x = yT * 9;
				}

				// Gate permanently closes as Young enters
				if (t >= T_GATE_CLOSE && !gatePermClosed) {
					gatePermClosed = true;
					gate.eventHorizon.visible = false;
					kawoosh.mesh.scale.setScalar(0);
				}

				// Young slumps at far wall after crossing room
				if (t >= T_YOUNG_ENTER + 1.4 && !youngSlumped) {
					youngSlumped = true;
					youngH.root.position.set(-0.2, 0, 18);
					youngH.root.rotation.set(Math.PI * 0.45, 0, Math.PI * 0.1);
				}

				// Camera side angle, settling on slumped Young
				camera.position.lerpVectors(
					new THREE.Vector3(6, 1.5, GATE_CENTER.z + 2),
					new THREE.Vector3(7, 1.2, 16),
					easeOut(beatProgress(T_ELI_ENTER, T_WAKE_START, t)),
				);
				const youngPos = youngH.root.position;
				camLookAt.set(
					youngSlumped ? youngPos.x    : -0.2,
					youngSlumped ? 0.8           : GATE_CENTER.y,
					youngSlumped ? youngPos.z    : GATE_CENTER.z + 8,
				);
			}

			// ══ BEAT 9: PLAYER WAKES (27 – 35 s) ════════════════════════════
			if (t >= T_WAKE_START) {
				camera.up.set(0, 1, 0);

				// Low angle rises: ground → standing height
				camera.position.lerpVectors(
					new THREE.Vector3(0.5, 0.08, GATE_CENTER.z + 2.5),
					new THREE.Vector3(0.5, 1.55, GATE_CENTER.z + 2.0),
					easeOut(beatProgress(T_WAKE_START, T_WAKE_START + 4.5, t)),
				);

				// Scott crouches next to Eli
				scottH.root.visible = true;
				scottH.root.position.set(1.0, 0, GATE_CENTER.z + 3.5);
				scottH.root.rotation.set(0, -Math.PI * 0.65, 0);
				scottFlashlight.intensity = 18;
				scottFlashlight.position.copy(scottH.root.position)
					.add(new THREE.Vector3(0.4, 1.0, 0.3));

				camLookAt.set(
					scottH.root.position.x,
					scottH.root.position.y + 1.0,
					scottH.root.position.z,
				);

				// "Eli — where the hell are we?"
				if (t >= T_WAKE_START + 0.6 && !wakeSubShown) {
					wakeSubShown = true;
					showSubtitle(ui, "\u201cEli \u2014 where the hell are we?\u201d");
				}
				if (t >= T_WAKE_START + 3.8) hideSubtitle(ui);

				if (t >= T_HUD_START) {
					ui.hud.style.opacity = String(
						Math.min(1, beatProgress(T_HUD_START, T_HUD_START + 2.5, t)),
					);
				}
				if (t >= T_QUEST_START) {
					ui.questMarker.style.opacity = "1";
				}
			}

			// Skip hint fades at 30 s
			if (t >= 30) {
				ui.skipHint.style.opacity = String(Math.max(0, 1 - beatProgress(30, 32, t)));
			}

			// ── Camera shake (additive, after all beat positioning) ───────────
			if (shake.intensity > 0.001) {
				camera.position.x += shake.intensity * (Math.random() - 0.5);
				camera.position.y += shake.intensity * (Math.random() - 0.5);
				shake.intensity   *= Math.pow(0.85, delta * 60);
			}

			camera.lookAt(camLookAt);
			camera.updateProjectionMatrix();

			// Gate front-light pulse while wormhole is active
			if (!gatePermClosed && t >= T_KAWOOSH_SETTLE) {
				const frontLight = lights[1]; // gateFrontLight — index 1 from buildLighting
				if (frontLight) frontLight.intensity = 200 + Math.sin(t * 3.5) * 30;
			}

			if (t >= T_TOTAL) void finish();
		},

		dispose(): void {
			disposed = true;
			window.removeEventListener("keydown", onKeyDown);
			kawoosh.dispose();
			for (const s of sparks) s.dispose();
			for (const rl of redLights) scene.remove(rl);
			scene.remove(scottFlashlight);
			scene.remove(ambient);
			for (const h of [scottH, rushH, eliH, tjH, youngH, greerH, crewAH, crewBH]) h.dispose();
			for (const o of debugObjects) scene.remove(o);
			ui.dispose();
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

export const openingCinematicScene = defineGameScene({
	id:     "opening-cinematic",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((m) => m.default),
	}),
	title:  "Opening Cinematic",
	player: false,
	mount,
});
