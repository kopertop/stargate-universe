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
import { AudioManager } from "../../systems/audio";
import { Action, getInput } from "../../systems/input";

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

// Gate center in world space — MUST match gate-room/index.ts:
//   GATE_RADIUS=2.8, GATE_TUBE=0.22, so y = 2.72
// (Previously hard-coded 3.2 here which put the kawoosh ~0.5 above
// the real event horizon — players saw the portal floating behind
// the gate because the kawoosh geometry didn't align with the ring.)
const GATE_CENTER = new THREE.Vector3(0, 2.72, 0);
const GATE_BACK   = new THREE.Vector3(0, 2.72, 0.5);  // just in front of the horizon
// Overhead shot — camera in FRONT of the gate (+Z, player-side), high
// up, looking down and BACKWARD past the gate into the landing zone
// (z=-7 where crew tumble to). Previous coords had camera behind the
// gate looking the wrong way; players only saw empty runway.
const OVERHEAD    = new THREE.Vector3(0, 20, 8);
// Wide establishing shot — camera far back and elevated so the whole
// gate + room silhouette is visible. Stays static during dial & kawoosh
// so the player actually reads the chevrons locking in.
const ESTABLISH   = new THREE.Vector3(0, 6, 22);

// ─── 40-second gate-room arrival ────────────────────────────────────────────
//
// This is act two of the 60-second opening (act one is opening-cinematic
// 0-20s, this is 0-40s relative = 20-60s absolute). The sgu-theme-song is
// already playing from act one and runs through to the end of act two.
// Each beat is independently testable via ?cinstep=N in the URL.
//
// BEAT TABLE (seconds relative to cinematic start):
//    0 - 2s  establishing, dormant gate
//    2 -12s  chevrons dialing (9 chevron-lock SFX)
//   12 -15s  kawoosh + event horizon forms
//   15 -20s  Scott emerges first, "scott-clear" voice line
//   20 -32s  STATIC OVERHEAD — crew tumble through
//   32 -37s  descent to Eli on the ground, Scott crouches
//   37 -40s  fade to gameplay (player prone)
const BEATS: Beat[] = [
	// Beat 1 — WIDE ESTABLISHING. Dormant gate, massive empty hall.
	{
		start: 0, end: 2,
		camFrom: ESTABLISH.clone(),
		camTo:   ESTABLISH.clone(),
		lookAt:  GATE_CENTER,
		easing:  "linear",
	},
	// Beat 2 — CHEVRONS DIALING. Same wide shot, 9 chevron-lock SFX.
	{
		start: 2, end: 12,
		camFrom: ESTABLISH.clone(),
		camTo:   ESTABLISH.clone(),
		lookAt:  GATE_CENTER,
		easing:  "linear",
	},
	// Beat 3 — KAWOOSH. Push in slightly for the effect reveal.
	{
		start: 12, end: 15,
		camFrom: ESTABLISH.clone(),
		camTo:   new THREE.Vector3(0, 4, 14),
		lookAt:  GATE_CENTER,
		easing:  "ease-out",
	},
	// Beat 4 — SCOTT EMERGES. Low angle tracking his walk through.
	{
		start: 15, end: 20,
		camFrom: new THREE.Vector3(2.5, 1.0, -3),
		camTo:   new THREE.Vector3(3.5, 1.0, -6),
		lookAt:  GATE_BACK,
		easing:  "linear",
	},
	// Beat 5 — OVERHEAD. Static high-angle from IN FRONT of the gate,
	// looking down and back past the gate into the landing zone at z=-5.
	// This frames gate-in-foreground + crew-tumbling-into-background.
	{
		start: 20, end: 32,
		camFrom: OVERHEAD.clone(),
		camTo:   OVERHEAD.clone(),
		lookAt:  new THREE.Vector3(0, 1, -5),
		easing:  "linear",
	},
	// Beat 6 — DESCENT to Eli prone on the ground; Scott crouches in.
	{
		start: 32, end: 37,
		camFrom: new THREE.Vector3(0.4, 6, -4),
		camTo:   new THREE.Vector3(0.4, 0.9, -2.5),
		lookAt:  new THREE.Vector3(0.4, 0.3, -5),
		easing:  "ease-out",
	},
	// Beat 7 — FADE. Stays close on Eli as the cinematic hands off.
	{
		start: 37, end: 40,
		camFrom: new THREE.Vector3(0.4, 0.9, -2.5),
		camTo:   new THREE.Vector3(0.4, 0.9, -2.5),
		lookAt:  new THREE.Vector3(0.4, 0.3, -5),
		easing:  "linear",
	},
];

const TOTAL_DURATION = 40;

// Timing anchors — centralize so the updateAudio/updateCrew/updateSubtitles
// stay in sync with the beat structure above.
const T_DIAL_START = 2;
const T_DIAL_END   = 12;
const T_KAWOOSH    = 12;
const T_SCOTT_EMERGE  = 15;
const T_OVERHEAD      = 20;
const T_CHAOS_START   = 22;
const T_TJ_ELI        = 24.5;
const T_RUSH          = 26.5;
const T_YOUNG_IMPACT  = 28.5;
const T_GATE_SHUTDOWN = 32;

// ─── Named thrown actor (VRM crew) ────────────────────────────────────────────

/**
 * Build a minimal CharacterLoadResult backed by a colored capsule so the
 * cinematic still has visible crew members even when a named VRM asset is
 * missing or fails to load. Shape is a rough humanoid silhouette — good
 * enough for wide / overhead shots; callers should only hit this path when
 * the real VRM is unavailable.
 */
function createCapsuleFallback(color: number): CharacterLoadResult {
	const root = new THREE.Group();
	const geo = new THREE.CapsuleGeometry(0.25, 1.0, 4, 12);
	const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.8 });
	const body = new THREE.Mesh(geo, mat);
	body.position.y = 0.75;
	root.add(body);
	const headGeo = new THREE.SphereGeometry(0.14, 12, 10);
	const head = new THREE.Mesh(headGeo, new THREE.MeshStandardMaterial({ color: 0xf0d2a5, roughness: 0.7 }));
	head.position.y = 1.55;
	root.add(head);
	const mixer = new THREE.AnimationMixer(root);
	return {
		root,
		vrm: undefined,
		mixer,
		format: "glb",
		update: (_delta: number) => { /* static capsule — no animation */ },
		dispose: () => {
			root.parent?.remove(root);
			geo.dispose();
			mat.dispose();
			headGeo.dispose();
			(head.material as THREE.Material).dispose();
		},
	};
}

/**
 * Count renderable meshes inside a loaded character root. Used to detect
 * "successful" VRM loads that actually produced no geometry (e.g. our
 * 24 KB placeholder .vrm files parse fine but contain zero meshes).
 */
function countMeshes(root: THREE.Object3D): number {
	let n = 0;
	root.traverse((o) => { if ((o as THREE.Mesh).isMesh) n++; });
	return n;
}

/**
 * Wrap loadCrewMember so cinematic actors always render. Falls back to a
 * capsule when: (a) the VRM network/parse fails entirely, or (b) the VRM
 * parses but contains no meshes (our placeholder .vrm stubs trip this).
 */
async function loadCrewOrFallback(id: string, fallbackColor: number): Promise<CharacterLoadResult> {
	try {
		const result = await loadCrewMember(id);
		const meshes = countMeshes(result.root);
		console.log(`[cinematic] crew "${id}" loaded (meshes=${meshes})`);
		if (meshes === 0) {
			console.warn(`[cinematic] crew "${id}" has 0 meshes, swapping to capsule fallback`);
			result.dispose?.();
			return createCapsuleFallback(fallbackColor);
		}
		return result;
	} catch (err) {
		console.warn(`[cinematic] crew "${id}" failed to load, using capsule fallback`, err);
		return createCapsuleFallback(fallbackColor);
	}
}

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

// ─── Controller ───────────────────────────────────────────────────────────────

export class GateRoomCinematicController {
	private elapsed = 0;
	private frozen = false;   // ?cinfreeze=1 — don't advance elapsed (dev tool)
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
	private tjNpc: CharacterLoadResult | undefined;
	private eliNpc: CharacterLoadResult | undefined;
	private camera: THREE.PerspectiveCamera;
	private scene: THREE.Scene;
	private readonly onComplete: () => void;

	// Skip mechanism (InputManager: Action.Pause = Escape / Gamepad Start)
	private skipHint = createSkipHint();
	private skipHoldStart: number | null = null;
	private readonly SKIP_HOLD_MS = 1500;
	private skipFadeOverlay: HTMLDivElement | undefined;
	private skipTriggered = false;

	// Player visual hide/restore
	private playerObject: THREE.Object3D | undefined;

	// Audio
	private audioCtx: AudioContext | null = null;
	private droneOsc: OscillatorNode | null = null;
	private audioPlayed = new Set<string>();

	private readonly onChevronLock: (lockedCount: number) => void;

	constructor(
		scene: THREE.Scene,
		camera: THREE.PerspectiveCamera,
		onChevronLock: (lockedCount: number) => void,
		onComplete: () => void,
		playerObject?: THREE.Object3D,
	) {
		this.scene = scene;
		this.camera = camera;
		this.onChevronLock = onChevronLock;
		this.onComplete = onComplete;
		this.playerObject = playerObject;

		// ?cinstep=N — jump to elapsed = N seconds for testing. Pair with
		// the same param on opening-cinematic to step through the whole
		// 60-second opening one second at a time.
		// ?cinfreeze=1 — additionally pin the clock to the cinstep value so
		// frame-by-frame verification tools can inspect a specific beat
		// without elapsed marching forward while crew VRMs stream in.
		const params = new URLSearchParams(window.location.search);
		const cinStepRaw = params.get("cinstep");
		const cinStep = cinStepRaw !== null ? Number.parseFloat(cinStepRaw) : NaN;
		if (Number.isFinite(cinStep)) {
			this.elapsed = Math.max(0, Math.min(TOTAL_DURATION - 0.1, cinStep));
			this.frozen = params.get("cinfreeze") === "1";
		}

		this.buildKawoosh();
		// Chaos actors (capsule placeholders) removed — they clashed
		// visually with the VRM crew. All arrival actors are now the
		// named thrown crew (Scott/Rush/TJ/Eli/Young).
		this.loadCrew();
		this.initAudio();
		this.hidePlayerVisual();

		// If the theme song isn't already playing (e.g. player landed
		// directly on this scene with ?scene=gate-room without going
		// through opening-cinematic), kick it off now so the arrival
		// has its score. Force loop:true because the track is shorter
		// than the 40-second arrival cinematic.
		const audio = AudioManager.getInstance();
		if (!audio.isPlaying("sgu-theme-song")) {
			void audio.play("sgu-theme-song", undefined, { loop: true, volume: 0.8 });
		}
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
		// Real SFX are played via AudioManager (sound-catalog entries on R2).
		// We keep a tiny AudioContext only for the background drone since
		// there isn't a looping ship-hum entry in the catalog yet.
		try {
			this.audioCtx = new AudioContext();
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
		const audio = AudioManager.getInstance();

		// Beat 2 — CHEVRONS DIALING. Play chevron-lock once per chevron,
		// spaced evenly over the 10-second dial window (~1s apart, last
		// lock fires just before kawoosh). Also drives the real gate
		// runtime's chevron lighting via the onChevronLock callback.
		const DIAL_DURATION = T_DIAL_END - T_DIAL_START;
		for (let i = 0; i < 9; i++) {
			const chevronTime = T_DIAL_START + (i + 1) * (DIAL_DURATION / 10);
			const key = `chevron-${i}`;
			if (elapsed >= chevronTime && !this.audioPlayed.has(key)) {
				this.audioPlayed.add(key);
				void audio.play("chevron-lock");
				this.onChevronLock(i + 1);
			}
		}

		// Beat 3 — KAWOOSH. The signature gate activation sound.
		if (elapsed >= T_KAWOOSH && !this.audioPlayed.has("kawoosh")) {
			this.audioPlayed.add("kawoosh");
			void audio.play("stargate-kawoosh");
		}

		// Beat 4 — Scott steps through. The scott-clear / scott-bark-eli
		// voice lines are in the catalog but NOT yet uploaded to R2 —
		// playing them would 404 and poison the AudioContext. Subtitles
		// handle the dialogue for now; wire the voice back in once the
		// files land in /audio/voice/ on the sgu-assets bucket.
		if (elapsed >= T_SCOTT_EMERGE && !this.audioPlayed.has("scott-emerge")) {
			this.audioPlayed.add("scott-emerge");
			void audio.play("wormhole-transit");
		}

		// Beat 5 — crew tumble through (overhead). Staggered transits.
		if (elapsed >= T_CHAOS_START && !this.audioPlayed.has("chaos-emerge")) {
			this.audioPlayed.add("chaos-emerge");
			void audio.play("energy-burst");
		}
		if (elapsed >= T_TJ_ELI && !this.audioPlayed.has("tj-eli-emerge")) {
			this.audioPlayed.add("tj-eli-emerge");
			void audio.play("wormhole-transit");
		}
		if (elapsed >= T_RUSH && !this.audioPlayed.has("rush-emerge")) {
			this.audioPlayed.add("rush-emerge");
			void audio.play("wormhole-transit");
		}
		// Young slams the far wall.
		if (elapsed >= T_YOUNG_IMPACT && !this.audioPlayed.has("young-impact")) {
			this.audioPlayed.add("young-impact");
			void audio.play("debris-impact");
			void audio.play("low-rumble");
		}
		// Gate shutdown energy wind-down.
		if (elapsed >= T_GATE_SHUTDOWN + 2 && !this.audioPlayed.has("gate-shutdown")) {
			this.audioPlayed.add("gate-shutdown");
			void audio.play("power-down");
		}
		// (Beat 6 — Scott checking on Eli) — voice line goes here once
		// scott-bark-eli is uploaded to R2. Subtitle-only for now.
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
			// Flicker during shutdown beat (t≈27-29)
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

		// Kawoosh starts at the top of Beat 3
		if (globalElapsed < T_KAWOOSH) return;

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
		console.log("[cinematic] loadCrew() start");
		// Use fallback-wrapped loader so missing VRM placeholders don't leave
		// the cinematic empty. Colors chosen to visually differentiate the crew
		// in wide/overhead shots when the real models are unavailable.
		const [scott, rush, young, tj, eli] = await Promise.allSettled([
			loadCrewOrFallback("scott", 0x4466aa),  // blue — military uniform
			loadCrewOrFallback("rush",  0x444444),  // dark grey — civilian jacket
			loadCrewOrFallback("young", 0x556677),  // slate — command
			loadCrewOrFallback("tj",    0x88aabb),  // light blue — medic
			loadCrewOrFallback("eli",   0x886644),  // tan — civilian hoodie
		]);

		// If the cinematic was disposed while crew was loading (e.g. player
		// skipped, or the scene was torn down), discard loaded VRM resources
		// instead of attaching them to a dead scene.
		if (this.disposed) {
			for (const result of [scott, rush, young, tj, eli]) {
				if (result.status === "fulfilled") {
					result.value.dispose?.();
				}
			}
			this.crewLoaded = true;
			return;
		}

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

		if (tj.status === "fulfilled") {
			this.tjNpc = tj.value;
			this.scene.add(this.tjNpc.root);
			this.tjNpc.root.visible = false;
		}

		if (eli.status === "fulfilled") {
			this.eliNpc = eli.value;
			this.scene.add(this.eliNpc.root);
			this.eliNpc.root.visible = false;
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
	}

	// ── Camera ────────────────────────────────────────────────────────────────

	private applyCamera(elapsed: number) {
		const beat = BEATS.find(b => elapsed >= b.start && elapsed < b.end) ?? BEATS[BEATS.length - 1];
		const rawT = (elapsed - beat.start) / (beat.end - beat.start);
		const t = applyEasing(Math.min(1, Math.max(0, rawT)), beat.easing);

		const pos = new THREE.Vector3().lerpVectors(beat.camFrom, beat.camTo, t);

		// Force-kill shake during the wide establishing + dial + overhead
		// beats so residual landing shake doesn't wobble the calm shots.
		if (elapsed < T_OVERHEAD || (elapsed >= T_OVERHEAD && elapsed < T_OVERHEAD + 2)) {
			this.shakeIntensity = 0;
		}

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
		// Beat 2 — chevrons locking
		if (elapsed >= T_DIAL_START + 1 && elapsed < T_DIAL_START + 5 && !this.subtitleShown.has("chevrons")) {
			this.subtitleShown.add("chevrons");
			this.subtitle.show("Chevrons locking...", 4);
		}
		// Beat 3 — kawoosh forms
		if (elapsed >= T_KAWOOSH && elapsed < T_KAWOOSH + 2 && !this.subtitleShown.has("wormhole")) {
			this.subtitleShown.add("wormhole");
			this.subtitle.show("Wormhole established.", 2);
		}
		// Beat 4 — Scott's all-clear call (paired with scott-clear voice line)
		if (elapsed >= T_SCOTT_EMERGE + 1.5 && elapsed < T_SCOTT_EMERGE + 5 && !this.subtitleShown.has("scott-clear")) {
			this.subtitleShown.add("scott-clear");
			this.subtitle.show("It's clear — start the evacuation!", 3.5);
		}
		// Beat 5 — chaos surge starts (overhead)
		if (elapsed >= T_CHAOS_START && elapsed < T_CHAOS_START + 3 && !this.subtitleShown.has("evacuate")) {
			this.subtitleShown.add("evacuate");
			this.subtitle.show("Everyone through now — GO!", 3);
		}
		// Beat 5 — Rush observes
		if (elapsed >= T_RUSH && elapsed < T_RUSH + 2 && !this.subtitleShown.has("rush-fascinating")) {
			this.subtitleShown.add("rush-fascinating");
			this.subtitle.show("Fascinating...", 2);
		}
		// Beat 5 — Young hits the wall
		if (elapsed >= T_YOUNG_IMPACT && elapsed < T_YOUNG_IMPACT + 2 && !this.subtitleShown.has("young-down")) {
			this.subtitleShown.add("young-down");
			this.subtitle.show("Get Young — he's not moving!", 2);
		}
		// "Eli... Eli, can you hear me?" is intentionally NOT a cinematic
		// subtitle — it's the first line of the Scott opening dialogue,
		// which starts as soon as the cinematic ends. Duplicating it here
		// would show the line twice in a row.
	}

	// ── Beat-triggered crew visibility ────────────────────────────────────────

	private updateCrew(elapsed: number) {
		if (!this.crewLoaded) return;

		// Crew are invisible during beats 1-3 (wide/dial/kawoosh). Scott
		// is the FIRST to come through at T_SCOTT_EMERGE — his visibility
		// is driven by updateThrown the moment his throw begins.
		if (elapsed < T_SCOTT_EMERGE) {
			return;
		}

		// Named thrown actors — indexed by order set in loadCrew:
		// 0=scott(first through at T_SCOTT_EMERGE)
		// 1=rush  (clean landing at T_RUSH)
		// 2=tj    (T_TJ_ELI)
		// 3=eli   (T_TJ_ELI)
		// 4=young (T_YOUNG_IMPACT — hits wall)
		this.thrownActors.forEach((actor, idx) => {
			const beatE =
				idx === 0 ? Math.max(0, elapsed - T_SCOTT_EMERGE) :
				idx === 1 ? Math.max(0, elapsed - T_RUSH) :
				idx === 2 || idx === 3 ? Math.max(0, elapsed - T_TJ_ELI) :
				Math.max(0, elapsed - T_YOUNG_IMPACT);
			updateThrown(actor, beatE);
		});

		// Chaos actors removed — nothing to update here.

		// Shake on the chaos-arrival surge and again on Young's impact.
		if (elapsed >= T_CHAOS_START + 0.3 && elapsed < T_CHAOS_START + 1 && this.shakeIntensity < 0.05) {
			this.shakeIntensity = 0.22;
		}
		if (elapsed >= T_YOUNG_IMPACT && elapsed < T_YOUNG_IMPACT + 0.5 && this.shakeIntensity < 0.05) {
			this.shakeIntensity = 0.35;
		}
	}

	// ── Skip handling ─────────────────────────────────────────────────────────

	private updateSkip() {
		if (this.skipTriggered) return;

		// Action.Pause is bound to Escape (keyboard) + Start (gamepad) by
		// default — hold either for SKIP_HOLD_MS to skip.
		const held = getInput().isAction(Action.Pause);

		if (held && this.skipHoldStart === null) {
			this.skipHoldStart = performance.now();
		} else if (!held && this.skipHoldStart !== null) {
			this.skipHoldStart = null;
			this.skipHint.setProgress(0);
		}

		if (this.skipHoldStart !== null) {
			const elapsed = performance.now() - this.skipHoldStart;
			this.skipHint.setProgress(Math.min(1, elapsed / this.SKIP_HOLD_MS));
			if (elapsed >= this.SKIP_HOLD_MS) {
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

		// `frozen` is a dev/test flag — keep the clock pinned to the cinstep
		// value so tests can take deterministic screenshots while slow VRM
		// loads finish in the background.
		if (!this.frozen) {
			this.elapsed += delta;
		}
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
		// End the 60-second theme here — it was started in opening-cinematic
		// and played through the whole sequence. Gameplay starts in silence.
		AudioManager.getInstance().stop("sgu-theme-song");

		// Restore player visual before anything else
		this.restorePlayerVisual();

		if (this.kawooshDisc) {
			this.scene.remove(this.kawooshDisc);
			this.kawooshDisc.geometry.dispose();
			(this.kawooshDisc.material as THREE.Material).dispose();
			this.kawooshDisc = undefined;
		}
		if (this.eventHorizon) {
			this.scene.remove(this.eventHorizon);
			this.eventHorizon.geometry.dispose();
			(this.eventHorizon.material as THREE.Material).dispose();
			this.eventHorizon = undefined;
		}

		// Crew NPCs (VRM) — remove from scene and dispose GPU resources.
		for (const c of [this.scottNpc, this.rushNpc, this.youngNpc, this.tjNpc, this.eliNpc]) {
			if (!c) continue;
			this.scene.remove(c.root);
			c.dispose?.();
		}
		this.scottNpc = this.rushNpc = this.youngNpc = this.tjNpc = this.eliNpc = undefined;
		this.thrownActors = [];

		for (const a of this.chaosActors) {
			this.scene.remove(a.mesh);
			a.mesh.geometry.dispose();
			(a.mesh.material as THREE.Material).dispose();
		}
		this.chaosActors = [];
	}
}
