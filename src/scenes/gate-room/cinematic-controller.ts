/**
 * GateRoomCinematicController
 *
 * Plugs into the live gate-room scene to play the 9-beat "Air" opening
 * sequence.  It reuses everything already in the scene — the room geometry,
 * lighting, and loads crew members via loadCrewMember().  Includes:
 *  - 9-beat scripted camera with per-beat easing
 *  - Kawoosh gate activation + event horizon flicker
 *  - Named crew thrown actors (Scott, Rush, TJ, Eli, Young)
 *  - Beat-4 anonymous chaos actors (capsule fallback meshes)
 *  - Expanded subtitle cues across all beats
 *  - Web Audio synthesized ambience + SFX (drone, gate tone, whooshes, boom)
 *  - ESC / gamepad-Start skip with hold-to-skip UI + fade-to-black
 *  - Player visual hide during cinematic, restore on complete/dispose
 */

import * as THREE from "three";
import { loadCrewMember } from "../../characters/character-loader";
import type { CharacterLoadResult } from "../../characters/character-loader";

// ─── Beat definitions ─────────────────────────────────────────────────────────

interface Beat {
	start: number;
	end: number;
	camFrom: THREE.Vector3;
	camTo: THREE.Vector3;
	lookAt: THREE.Vector3;
	easing: "linear" | "ease-in" | "ease-out" | "smooth";
}

function smooth(t: number): number {
	return t * t * (3 - 2 * t);
}

function easeIn(t: number): number {
	return t * t;
}

function easeOut(t: number): number {
	return 1 - (1 - t) * (1 - t);
}

function applyEasing(t: number, mode: Beat["easing"]): number {
	switch (mode) {
		case "ease-in":  return easeIn(t);
		case "ease-out": return easeOut(t);
		case "smooth":   return smooth(t);
		default:         return t;
	}
}

// Gate center in world space (matches gate-room buildStargate placement)
const GATE_CENTER = new THREE.Vector3(0, 3.2, 0);
const GATE_BACK   = new THREE.Vector3(0, 3.2, 0.5);  // just behind the horizon
const OVERHEAD    = new THREE.Vector3(0, 14, -4);

const BEATS: Beat[] = [
	// Beat 1 — dormant gate, slow push toward ring
	{
		start: 0, end: 4,
		camFrom: new THREE.Vector3(0, 1.7, 16),
		camTo:   new THREE.Vector3(0, 1.7,  6),
		lookAt:  GATE_CENTER,
		easing:  "ease-in",
	},
	// Beat 2 — gate activates, kawoosh expands
	{
		start: 4, end: 7,
		camFrom: new THREE.Vector3(0, 1.7, 6),
		camTo:   new THREE.Vector3(0, 1.7, 4),
		lookAt:  GATE_CENTER,
		easing:  "ease-out",
	},
	// Beat 3 — Scott through, low angle toward camera
	{
		start: 7, end: 11,
		camFrom: new THREE.Vector3(0.5, 0.6, -2),
		camTo:   new THREE.Vector3(0.5, 0.6, -4),
		lookAt:  GATE_BACK,
		easing:  "linear",
	},
	// Beat 4 — evacuation chaos, anonymous crew flying
	{
		start: 11, end: 16,
		camFrom: new THREE.Vector3(-1.5, 0.4, -5),
		camTo:   new THREE.Vector3(-2.0, 0.4, -8),
		lookAt:  new THREE.Vector3(0, 2, 0),
		easing:  "linear",
	},
	// Beat 5 — overhead wide shot, NPCs sprawled
	{
		start: 16, end: 20,
		camFrom: OVERHEAD.clone(),
		camTo:   OVERHEAD.clone().add(new THREE.Vector3(0, -1, 0)),
		lookAt:  new THREE.Vector3(0, 0, -4),
		easing:  "smooth",
	},
	// Beat 6 — Rush lands clean, walks off
	{
		start: 20, end: 23,
		camFrom: new THREE.Vector3(-3, 1.4, -4),
		camTo:   new THREE.Vector3(-4, 1.4, -8),
		lookAt:  new THREE.Vector3(-2, 1.4, -6),
		easing:  "ease-out",
	},
	// Beat 7 — Eli and TJ tumble through
	{
		start: 23, end: 26,
		camFrom: new THREE.Vector3(1.5, 0.5, -3),
		camTo:   new THREE.Vector3(2.0, 0.5, -6),
		lookAt:  GATE_BACK,
		easing:  "linear",
	},
	// Beat 8 — Young last through at high speed, gate flickers shut
	{
		start: 26, end: 31,
		camFrom: new THREE.Vector3(0, 1.4, -4),
		camTo:   new THREE.Vector3(0, 1.4, -10),
		lookAt:  new THREE.Vector3(0, 1.2, -16),
		easing:  "ease-in",
	},
	// Beat 9 — ground level push up near Eli, Scott crouches in
	{
		start: 31, end: 36,
		camFrom: new THREE.Vector3(0.4, 0.15, -2.5),
		camTo:   new THREE.Vector3(0.4, 0.9,  -2.5),
		lookAt:  new THREE.Vector3(0.4, 1.0,  -5),
		easing:  "ease-out",
	},
];

const TOTAL_DURATION = 36;

// ─── Named thrown actor (VRM crew) ────────────────────────────────────────────

interface ThrownActor {
	char: CharacterLoadResult;
	startPos: THREE.Vector3;
	velocity: THREE.Vector3;
	t0: number;         // time offset within beat window that throw starts
	flightTime: number;
	landPos: THREE.Vector3;
	landed: boolean;
}

function createThrownActor(
	char: CharacterLoadResult,
	startPos: THREE.Vector3,
	velocity: THREE.Vector3,
	t0: number,
	flightTime: number,
	landPos: THREE.Vector3,
): ThrownActor {
	char.root.position.copy(startPos);
	char.root.visible = false;
	return { char, startPos: startPos.clone(), velocity: velocity.clone(), t0, flightTime, landPos: landPos.clone(), landed: false };
}

function updateThrown(actor: ThrownActor, beatElapsed: number) {
	const t = beatElapsed - actor.t0;
	if (t < 0) return;

	actor.char.root.visible = true;

	if (actor.landed) return;

	if (t >= actor.flightTime) {
		actor.landed = true;
		actor.char.root.position.copy(actor.landPos);
		return;
	}

	// Parabolic arc
	actor.char.root.position.set(
		actor.startPos.x + actor.velocity.x * t,
		actor.startPos.y + actor.velocity.y * t - 4.9 * t * t,
		actor.startPos.z + actor.velocity.z * t,
	);
}

// ─── Chaos actor (Beat 4 — anonymous capsule crew) ───────────────────────────

interface ChaosActor {
	mesh: THREE.Mesh;
	startPos: THREE.Vector3;
	velocity: THREE.Vector3;
	t0: number;
	flightTime: number;
	landPos: THREE.Vector3;
	landed: boolean;
}

function createChaosActor(
	scene: THREE.Scene,
	startPos: THREE.Vector3,
	velocity: THREE.Vector3,
	t0: number,
	flightTime: number,
	landPos: THREE.Vector3,
	color: number,
): ChaosActor {
	const geo = new THREE.CapsuleGeometry(0.25, 1.0, 4, 8);
	const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.8 });
	const mesh = new THREE.Mesh(geo, mat);
	mesh.position.copy(startPos);
	mesh.visible = false;
	scene.add(mesh);
	return { mesh, startPos: startPos.clone(), velocity: velocity.clone(), t0, flightTime, landPos: landPos.clone(), landed: false };
}

function updateChaos(actor: ChaosActor, beatElapsed: number) {
	const t = beatElapsed - actor.t0;
	if (t < 0) return;

	actor.mesh.visible = true;

	if (actor.landed) {
		actor.mesh.rotation.x += 0.01; // subtle tumble after landing
		return;
	}

	if (t >= actor.flightTime) {
		actor.landed = true;
		actor.mesh.position.copy(actor.landPos);
		return;
	}

	actor.mesh.position.set(
		actor.startPos.x + actor.velocity.x * t,
		actor.startPos.y + actor.velocity.y * t - 4.9 * t * t,
		actor.startPos.z + actor.velocity.z * t,
	);
	// Spin in flight for visual chaos
	actor.mesh.rotation.x += 0.15;
	actor.mesh.rotation.z += 0.08;
}

// ─── Subtitle overlay ─────────────────────────────────────────────────────────

function createSubtitle(): { show: (text: string, duration: number) => void; dispose: () => void } {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;bottom:10%;left:50%;transform:translateX(-50%);",
		"color:#fff;font-size:1.3rem;text-align:center;",
		"text-shadow:0 2px 6px #000,0 0 20px #000;",
		"font-family:'Segoe UI',sans-serif;pointer-events:none;",
		"max-width:80vw;z-index:50;opacity:0;transition:opacity 0.4s;",
	].join("");
	document.body.appendChild(el);

	let timer: ReturnType<typeof setTimeout> | undefined;

	return {
		show(text, duration) {
			if (timer) clearTimeout(timer);
			el.textContent = text;
			el.style.opacity = "1";
			timer = setTimeout(() => { el.style.opacity = "0"; }, duration * 1000 - 400);
		},
		dispose() {
			if (timer) clearTimeout(timer);
			el.remove();
		},
	};
}

// ─── Skip hint UI ─────────────────────────────────────────────────────────────

function createSkipHint(): { setProgress: (p: number) => void; dispose: () => void } {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;top:2rem;right:2rem;",
		"color:#ffffffaa;font-size:0.85rem;letter-spacing:0.08em;",
		"font-family:'Segoe UI',sans-serif;pointer-events:none;",
		"z-index:60;text-align:right;",
	].join("");

	const label = document.createElement("div");
	label.textContent = "Hold ESC to skip";
	el.appendChild(label);

	const bar = document.createElement("div");
	bar.style.cssText = "height:2px;background:#ffffff22;margin-top:4px;overflow:hidden;";
	const fill = document.createElement("div");
	fill.style.cssText = "height:100%;background:#d4b96a;width:0%;transition:width 0.05s linear;";
	bar.appendChild(fill);
	el.appendChild(bar);
	document.body.appendChild(el);

	return {
		setProgress(p: number) {
			fill.style.width = `${Math.min(100, p * 100)}%`;
			el.style.color = p > 0 ? "#d4b96aee" : "#ffffffaa";
		},
		dispose() { el.remove(); },
	};
}

// ─── Web Audio helpers ────────────────────────────────────────────────────────

function playGateTone(ctx: AudioContext) {
	const osc = ctx.createOscillator();
	const gain = ctx.createGain();
	osc.type = "sine";
	osc.frequency.setValueAtTime(200, ctx.currentTime);
	osc.frequency.exponentialRampToValueAtTime(80, ctx.currentTime + 0.5);
	gain.gain.setValueAtTime(0.3, ctx.currentTime);
	gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 2.0);
	osc.connect(gain);
	gain.connect(ctx.destination);
	osc.start();
	osc.stop(ctx.currentTime + 2.0);
}

function playWhoosh(ctx: AudioContext, intensity = 1.0) {
	const bufSize = Math.floor(ctx.sampleRate * 0.35);
	const buf = ctx.createBuffer(1, bufSize, ctx.sampleRate);
	const data = buf.getChannelData(0);
	for (let i = 0; i < bufSize; i++) data[i] = Math.random() * 2 - 1;

	const src = ctx.createBufferSource();
	src.buffer = buf;

	const filter = ctx.createBiquadFilter();
	filter.type = "highpass";
	filter.frequency.value = 800;

	const gain = ctx.createGain();
	gain.gain.setValueAtTime(0.25 * intensity, ctx.currentTime);
	gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);

	src.connect(filter);
	filter.connect(gain);
	gain.connect(ctx.destination);
	src.start();
}

function playBoom(ctx: AudioContext) {
	const osc = ctx.createOscillator();
	const gain = ctx.createGain();
	osc.type = "sine";
	osc.frequency.setValueAtTime(80, ctx.currentTime);
	osc.frequency.exponentialRampToValueAtTime(18, ctx.currentTime + 0.5);
	gain.gain.setValueAtTime(0.5, ctx.currentTime);
	gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 1.2);
	osc.connect(gain);
	gain.connect(ctx.destination);
	osc.start();
	osc.stop(ctx.currentTime + 1.2);
}

// ─── Controller ───────────────────────────────────────────────────────────────

export class GateRoomCinematicController {
	private elapsed = 0;
	private disposed = false;
	private shakeIntensity = 0;
	private readonly shakeOffset = new THREE.Vector3();
	private flickerActive = false;
	private kawooshDisc: THREE.Mesh | undefined;
	private kawooshElapsed = 0;
	private kawooshDone = false;
	private eventHorizon: THREE.Mesh | undefined;
	private subtitle = createSubtitle();
	private subtitleShown = new Set<string>();
	private thrownActors: ThrownActor[] = [];
	private chaosActors: ChaosActor[] = [];
	private crewLoaded = false;
	private rushNpc: CharacterLoadResult | undefined;
	private scottNpc: CharacterLoadResult | undefined;
	private youngNpc: CharacterLoadResult | undefined;
	private camera: THREE.PerspectiveCamera;
	private scene: THREE.Scene;
	private readonly onComplete: () => void;

	// Skip mechanism
	private skipHint = createSkipHint();
	private skipHoldStart: number | null = null;
	private readonly SKIP_HOLD_MS = 1500;
	private skipFadeOverlay: HTMLDivElement | undefined;
	private skipTriggered = false;
	private readonly boundKeyDown: (e: KeyboardEvent) => void;
	private readonly boundKeyUp: (e: KeyboardEvent) => void;

	// Player visual hide/restore
	private playerObject: THREE.Object3D | undefined;

	// Audio
	private audioCtx: AudioContext | null = null;
	private droneOsc: OscillatorNode | null = null;
	private audioPlayed = new Set<string>();

	constructor(
		scene: THREE.Scene,
		camera: THREE.PerspectiveCamera,
		onComplete: () => void,
		playerObject?: THREE.Object3D,
	) {
		this.scene = scene;
		this.camera = camera;
		this.onComplete = onComplete;
		this.playerObject = playerObject;

		this.buildKawoosh();
		this.buildChaosActors();
		this.loadCrew();
		this.initAudio();
		this.hidePlayerVisual();

		this.boundKeyDown = (e: KeyboardEvent) => {
			if (e.code === "Escape" && this.skipHoldStart === null && !this.skipTriggered) {
				this.skipHoldStart = performance.now();
			}
		};
		this.boundKeyUp = (e: KeyboardEvent) => {
			if (e.code === "Escape") {
				this.skipHoldStart = null;
				this.skipHint.setProgress(0);
			}
		};
		window.addEventListener("keydown", this.boundKeyDown);
		window.addEventListener("keyup", this.boundKeyUp);
	}

	// ── Player visual hide/restore ────────────────────────────────────────────

	private hidePlayerVisual() {
		if (!this.playerObject) return;
		this.playerObject.traverse(obj => {
			if (obj.name !== "physics") obj.visible = false;
		});
	}

	private restorePlayerVisual() {
		if (!this.playerObject) return;
		this.playerObject.traverse(obj => { obj.visible = true; });
	}

	// ── Audio ─────────────────────────────────────────────────────────────────

	private initAudio() {
		try {
			this.audioCtx = new AudioContext();
			// Low background drone — ship ambient hum
			const osc = this.audioCtx.createOscillator();
			const gain = this.audioCtx.createGain();
			osc.type = "sine";
			osc.frequency.value = 60;
			gain.gain.value = 0.04;
			osc.connect(gain);
			gain.connect(this.audioCtx.destination);
			osc.start();
			this.droneOsc = osc;
		} catch (e) {
			console.warn("[Cinematic] Web Audio unavailable:", e);
		}
	}

	private updateAudio(elapsed: number) {
		if (!this.audioCtx) return;

		// Beat 2: gate activation tone sweep (200→80 Hz)
		if (elapsed >= 4 && !this.audioPlayed.has("gate-tone")) {
			this.audioPlayed.add("gate-tone");
			playGateTone(this.audioCtx);
		}
		// Beat 3: Scott lands
		if (elapsed >= 9 && !this.audioPlayed.has("whoosh-scott")) {
			this.audioPlayed.add("whoosh-scott");
			playWhoosh(this.audioCtx, 0.9);
		}
		// Beat 4: chaos landing surge
		if (elapsed >= 13 && !this.audioPlayed.has("whoosh-chaos")) {
			this.audioPlayed.add("whoosh-chaos");
			playWhoosh(this.audioCtx, 1.2);
		}
		// Beat 6: Rush lands (quiet, clean)
		if (elapsed >= 21.2 && !this.audioPlayed.has("whoosh-rush")) {
			this.audioPlayed.add("whoosh-rush");
			playWhoosh(this.audioCtx, 0.5);
		}
		// Beat 7: TJ/Eli tumble in
		if (elapsed >= 24.5 && !this.audioPlayed.has("whoosh-tj")) {
			this.audioPlayed.add("whoosh-tj");
			playWhoosh(this.audioCtx, 0.8);
		}
		// Beat 8: Young hits wall — boom + whoosh
		if (elapsed >= 27 && !this.audioPlayed.has("boom-young")) {
			this.audioPlayed.add("boom-young");
			playBoom(this.audioCtx);
			playWhoosh(this.audioCtx, 1.4);
		}
	}

	// ── Kawoosh effect ────────────────────────────────────────────────────────

	private buildKawoosh() {
		// Expanding disc (additive blue)
		const discGeo  = new THREE.CircleGeometry(1, 64);
		const discMat  = new THREE.MeshBasicMaterial({
			color: 0x2266ff, transparent: true, opacity: 0.85,
			blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
		});
		this.kawooshDisc = new THREE.Mesh(discGeo, discMat);
		this.kawooshDisc.position.copy(GATE_CENTER);
		this.kawooshDisc.scale.setScalar(0);
		this.kawooshDisc.visible = false;
		this.scene.add(this.kawooshDisc);

		// Stable event horizon (shown after kawoosh)
		const horizonGeo = new THREE.CircleGeometry(2.55, 64);
		const horizonMat = new THREE.MeshStandardMaterial({
			color: 0x224488, emissive: 0x112244, emissiveIntensity: 1.5,
			transparent: true, opacity: 0.7, side: THREE.DoubleSide,
		});
		this.eventHorizon = new THREE.Mesh(horizonGeo, horizonMat);
		this.eventHorizon.position.copy(GATE_CENTER);
		this.eventHorizon.visible = false;
		this.scene.add(this.eventHorizon);
	}

	private updateKawoosh(delta: number, globalElapsed: number) {
		if (this.kawooshDone) {
			// Flicker at Beat 8 (t≈27-29)
			if (globalElapsed >= 27 && globalElapsed <= 29) {
				const flicker = Math.random() > 0.7;
				if (this.eventHorizon) this.eventHorizon.visible = flicker;
				this.flickerActive = true;
			} else if (this.flickerActive && globalElapsed > 29) {
				this.flickerActive = false;
				if (this.eventHorizon) this.eventHorizon.visible = false;
			}
			return;
		}

		if (globalElapsed < 4) return;  // Before Beat 2

		this.kawooshElapsed += delta;

		if (!this.kawooshDisc) return;

		if (this.kawooshElapsed <= 0.4) {
			// Expand 0 → 3.5 in 0.4s
			const s = (this.kawooshElapsed / 0.4) * 3.5;
			this.kawooshDisc.visible = true;
			this.kawooshDisc.scale.setScalar(s);
		} else {
			// Snap to stable event horizon
			this.kawooshDisc.visible = false;
			if (this.eventHorizon) this.eventHorizon.visible = true;
			this.kawooshDone = true;
		}
	}

	// ── Beat 4 chaos actors (anonymous crew, capsule meshes) ──────────────────

	private buildChaosActors() {
		// 4 anonymous crew flung through the gate during Beat 4 (t=11-16)
		// Staggered t0 so they don't all come through at once
		const configs = [
			{
				startPos: new THREE.Vector3( 0.6, 3.2, 0.3),
				vel:      new THREE.Vector3( 1.5, 1.2, -9),
				t0: 0.0, flightTime: 0.9,
				landPos:  new THREE.Vector3( 2.0, 0.1, -10),
				color:    0x8888aa,
			},
			{
				startPos: new THREE.Vector3(-0.8, 3.2, 0.3),
				vel:      new THREE.Vector3(-2.0, 2.5, -7),
				t0: 0.8, flightTime: 1.1,
				landPos:  new THREE.Vector3(-2.5, 0.1,  -8),
				color:    0x7a8a99,
			},
			{
				startPos: new THREE.Vector3( 0.2, 3.2, 0.3),
				vel:      new THREE.Vector3( 0.5, 3.5,-11),
				t0: 1.5, flightTime: 0.8,
				landPos:  new THREE.Vector3( 0.8, 0.1, -12),
				color:    0x998877,
			},
			{
				startPos: new THREE.Vector3(-0.3, 3.2, 0.3),
				vel:      new THREE.Vector3(-1.0, 1.8, -8),
				t0: 2.2, flightTime: 1.0,
				landPos:  new THREE.Vector3(-1.5, 0.1,  -9),
				color:    0x6a7a88,
			},
		];

		this.chaosActors = configs.map(cfg =>
			createChaosActor(
				this.scene,
				cfg.startPos, cfg.vel, cfg.t0, cfg.flightTime, cfg.landPos,
				cfg.color,
			),
		);
	}

	// ── Crew loading ──────────────────────────────────────────────────────────

	private async loadCrew() {
		try {
			const [scott, rush, young, tj, eli] = await Promise.allSettled([
				loadCrewMember("scott"),
				loadCrewMember("rush"),
				loadCrewMember("young"),
				loadCrewMember("tj"),
				loadCrewMember("eli"),
			]);

			if (scott.status === "fulfilled") {
				this.scottNpc = scott.value;
				this.scene.add(this.scottNpc.root);
				this.scottNpc.root.visible = false;
			}

			if (rush.status === "fulfilled") {
				// Rush is already in the scene as the main NPC — cinematic version
				// is positioned at the gate mouth for the throw, separately
				this.rushNpc = rush.value;
				this.rushNpc.root.position.set(0.3, 3.2, 0.5);
				this.rushNpc.root.visible = false;
				this.scene.add(this.rushNpc.root);
			}

			if (young.status === "fulfilled") {
				this.youngNpc = young.value;
				this.scene.add(this.youngNpc.root);
				this.youngNpc.root.visible = false;
			}

			// Set up thrown actors once crew is loaded
			const actors: ThrownActor[] = [];

			if (scott.status === "fulfilled") {
				// Beat 3: Scott walks through at t=7, arrives at t=9
				actors.push(createThrownActor(
					scott.value,
					new THREE.Vector3(0, 3.2, 0.3),
					new THREE.Vector3(-0.3, -0.5, -4),
					0, 1.8,
					new THREE.Vector3(-0.5, 0.1, -7),
				));
			}

			if (rush.status === "fulfilled") {
				// Beat 6: Rush lands mostly clean at t=20
				actors.push(createThrownActor(
					rush.value,
					new THREE.Vector3(0.2, 3.2, 0.3),
					new THREE.Vector3(0.2, 0.2, -5),
					0, 1.2,
					new THREE.Vector3(0.3, 0.1, -6),
				));
			}

			if (tj.status === "fulfilled") {
				// Beat 7: TJ tumbles at t=23
				actors.push(createThrownActor(
					tj.value,
					new THREE.Vector3(-0.5, 3.2, 0.3),
					new THREE.Vector3(-1.2, 2.5, -8),
					0.3, 1.0,
					new THREE.Vector3(-1.8, 0.1, -8),
				));
			}

			if (eli.status === "fulfilled") {
				// Beat 7: Eli tumbles (NPC version — player Eli is hidden during cinematic)
				actors.push(createThrownActor(
					eli.value,
					new THREE.Vector3(0.4, 3.2, 0.3),
					new THREE.Vector3(0.9, 3.0, -7),
					0.6, 1.1,
					new THREE.Vector3(1.2, 0.1, -7),
				));
				this.scene.add(eli.value.root);
			}

			if (young.status === "fulfilled") {
				// Beat 8: Young high-speed, hits far wall unconscious
				actors.push(createThrownActor(
					young.value,
					new THREE.Vector3(-0.2, 3.2, 0.3),
					new THREE.Vector3(-1.0, 1.5, -14),
					0, 0.7,
					new THREE.Vector3(-1.2, 0.1, -17),
				));
			}

			this.thrownActors = actors;
			this.crewLoaded = true;
		} catch (err) {
			console.warn("[Cinematic] Crew load error:", err);
			this.crewLoaded = true; // continue without crew
		}
	}

	// ── Camera ────────────────────────────────────────────────────────────────

	private applyCamera(elapsed: number) {
		const beat = BEATS.find(b => elapsed >= b.start && elapsed < b.end) ?? BEATS[BEATS.length - 1];
		const rawT = (elapsed - beat.start) / (beat.end - beat.start);
		const t = applyEasing(Math.min(1, Math.max(0, rawT)), beat.easing);

		const pos = new THREE.Vector3().lerpVectors(beat.camFrom, beat.camTo, t);

		// Camera shake
		if (this.shakeIntensity > 0.001) {
			this.shakeOffset.set(
				(Math.random() - 0.5) * this.shakeIntensity,
				(Math.random() - 0.5) * this.shakeIntensity,
				(Math.random() - 0.5) * this.shakeIntensity,
			);
			pos.add(this.shakeOffset);
			this.shakeIntensity *= Math.pow(0.85, 1 / 60);
		}

		this.camera.position.copy(pos);
		this.camera.lookAt(beat.lookAt);
	}

	// ── Subtitles ─────────────────────────────────────────────────────────────

	private updateSubtitles(elapsed: number) {
		// Beat 2: ambient — chevrons locking
		if (elapsed >= 4 && elapsed < 6 && !this.subtitleShown.has("chevrons")) {
			this.subtitleShown.add("chevrons");
			this.subtitle.show("Chevrons locking...", 2);
		}
		// Beat 3: Scott clears the gate
		if (elapsed >= 7 && elapsed < 9 && !this.subtitleShown.has("scott-clear")) {
			this.subtitleShown.add("scott-clear");
			this.subtitle.show("It's clear — start the evacuation", 3);
		}
		// Beat 4: chaos begins
		if (elapsed >= 11 && elapsed < 13.5 && !this.subtitleShown.has("evacuate")) {
			this.subtitleShown.add("evacuate");
			this.subtitle.show("Evacuate! Everyone through now!", 2.5);
		}
		// Beat 6: Rush observes the ancient ship
		if (elapsed >= 20 && elapsed < 22 && !this.subtitleShown.has("rush-fascinating")) {
			this.subtitleShown.add("rush-fascinating");
			this.subtitle.show("Fascinating...", 2);
		}
		// Beat 8: Young is down
		if (elapsed >= 26 && elapsed < 28 && !this.subtitleShown.has("young-down")) {
			this.subtitleShown.add("young-down");
			this.subtitle.show("Get Young — he's not moving!", 2);
		}
		// Beat 9: Scott checks on Eli
		if (elapsed >= 31 && elapsed < 33 && !this.subtitleShown.has("eli-scott")) {
			this.subtitleShown.add("eli-scott");
			this.subtitle.show("Eli... Eli, can you hear me?", 2);
		}
		// Beat 9 close: Eli wakes
		if (elapsed >= 34 && elapsed < 37 && !this.subtitleShown.has("eli-wake")) {
			this.subtitleShown.add("eli-wake");
			this.subtitle.show("Eli — where the hell are we?", 4);
		}
	}

	// ── Beat-triggered crew visibility ────────────────────────────────────────

	private updateCrew(elapsed: number) {
		if (!this.crewLoaded) return;

		// Scott visible from Beat 3 onwards
		if (this.scottNpc && elapsed >= 7) {
			this.scottNpc.root.visible = true;
		}
		// Rush cinematic NPC visible Beat 6
		if (this.rushNpc && elapsed >= 20 && elapsed < 23) {
			this.rushNpc.root.visible = true;
		}

		// Named thrown actors — indexed by order set in loadCrew:
		// 0=scott(beat3), 1=rush(beat6), 2=tj(beat7), 3=eli(beat7), 4=young(beat8)
		const beat4E  = Math.max(0, elapsed - 11);
		const beat7E  = Math.max(0, elapsed - 23);
		const beat8E  = Math.max(0, elapsed - 26);

		this.thrownActors.forEach((actor, idx) => {
			const beatE =
				idx === 0 ? Math.max(0, elapsed - 7) :
				idx === 1 ? Math.max(0, elapsed - 20) :
				idx === 2 || idx === 3 ? beat7E :
				beat8E;
			updateThrown(actor, beatE);
		});

		// Beat 4 chaos actors
		this.chaosActors.forEach(actor => updateChaos(actor, beat4E));

		// Shake on first landing in Beat 4
		if (elapsed >= 12 && elapsed < 13 && this.shakeIntensity < 0.05) {
			this.shakeIntensity = 0.25;
		}
		// Shake on Young hitting wall in Beat 8
		if (elapsed >= 27 && elapsed < 27.5 && this.shakeIntensity < 0.05) {
			this.shakeIntensity = 0.35;
		}
	}

	// ── Skip handling ─────────────────────────────────────────────────────────

	private updateSkip() {
		if (this.skipTriggered) return;

		// Gamepad Start (standard mapping index 9) as alternative to ESC
		const gamepads = navigator.getGamepads();
		let gpStartHeld = false;
		for (const gp of gamepads) {
			if (gp?.buttons[9]?.pressed) { gpStartHeld = true; break; }
		}

		if (gpStartHeld && this.skipHoldStart === null) {
			this.skipHoldStart = performance.now();
		} else if (!gpStartHeld && this.skipHoldStart !== null) {
			// Only clear if ESC also isn't held (ESC tracking is event-driven)
			// This path handles gamepad-only release — ESC has its own keyup listener
		}

		if (this.skipHoldStart !== null) {
			const held = performance.now() - this.skipHoldStart;
			const progress = Math.min(1, held / this.SKIP_HOLD_MS);
			this.skipHint.setProgress(progress);

			if (held >= this.SKIP_HOLD_MS) {
				this.triggerSkip();
			}
		}
	}

	private triggerSkip() {
		if (this.skipTriggered) return;
		this.skipTriggered = true;
		this.skipHint.dispose();

		// Fade to black
		const overlay = document.createElement("div");
		overlay.style.cssText = [
			"position:fixed;inset:0;background:#000;opacity:0;",
			"transition:opacity 0.4s ease-in;z-index:200;pointer-events:none;",
		].join("");
		document.body.appendChild(overlay);
		this.skipFadeOverlay = overlay;

		// Next frame kicks the CSS transition
		requestAnimationFrame(() => { overlay.style.opacity = "1"; });

		setTimeout(() => {
			this.dispose();
			this.onComplete();
		}, 450);
	}

	// ── Public update — called each frame from gate-room ─────────────────────

	update(delta: number) {
		if (this.disposed) return;

		this.elapsed += delta;
		this.applyCamera(this.elapsed);
		this.updateKawoosh(delta, this.elapsed);
		this.updateCrew(this.elapsed);
		this.updateSubtitles(this.elapsed);
		this.updateAudio(this.elapsed);
		this.updateSkip();

		// VRM spring-bone updates
		this.thrownActors.forEach(a => a.char.update?.(delta));
		this.rushNpc?.update?.(delta);
		this.scottNpc?.update?.(delta);
		this.youngNpc?.update?.(delta);

		if (this.elapsed >= TOTAL_DURATION && !this.disposed) {
			this.dispose();
			this.onComplete();
		}
	}

	// ── Cleanup ───────────────────────────────────────────────────────────────

	dispose() {
		if (this.disposed) return;
		this.disposed = true;

		window.removeEventListener("keydown", this.boundKeyDown);
		window.removeEventListener("keyup", this.boundKeyUp);

		this.subtitle.dispose();
		this.skipHint.dispose();
		if (this.skipFadeOverlay) {
			this.skipFadeOverlay.remove();
			this.skipFadeOverlay = undefined;
		}

		// Audio cleanup
		if (this.droneOsc) {
			try { this.droneOsc.stop(); } catch { /* already stopped */ }
			this.droneOsc = null;
		}
		if (this.audioCtx) {
			void this.audioCtx.close();
			this.audioCtx = null;
		}

		// Restore player visual before anything else
		this.restorePlayerVisual();

		if (this.kawooshDisc) { this.scene.remove(this.kawooshDisc); this.kawooshDisc = undefined; }
		if (this.eventHorizon) { this.scene.remove(this.eventHorizon); this.eventHorizon = undefined; }

		[this.scottNpc, this.rushNpc, this.youngNpc].forEach(c => {
			if (c) this.scene.remove(c.root);
		});
		this.thrownActors.forEach(a => this.scene.remove(a.char.root));
		this.thrownActors = [];

		this.chaosActors.forEach(a => this.scene.remove(a.mesh));
		this.chaosActors = [];
	}
}
