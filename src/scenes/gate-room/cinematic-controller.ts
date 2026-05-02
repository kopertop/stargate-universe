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
import { loadCrewMember, loadVRMCharacter } from "../../characters/character-loader";
import type { CharacterLoadResult } from "../../characters/character-loader";
import { AudioManager } from "../../systems/audio";
import { CinematicCamera } from "../../systems/cinematic-camera";
import { Action, getInput } from "../../systems/input";
import { BodyPart, createRagdoll, type RagdollInstance } from "../../systems/ragdoll";
import { CRASHCAT_OBJECT_LAYER_MOVING, type CrashcatPhysicsWorld } from "@ggez/runtime-physics-crashcat";
import { applyKneelingPose, createStandupSequence, type StandupSequence } from "../../systems/vrm/vrm-standup-sequence";

// ─── Beat definitions ─────────────────────────────────────────────────────────

interface Beat {
	start: number;
	end: number;
	camFrom: THREE.Vector3;
	camTo: THREE.Vector3;
	lookAt: THREE.Vector3;
	easing: "linear" | "ease-in" | "ease-out" | "smooth";
}

// Camera look-at target — intentionally lower than the actual gate center
// (y=4.2) to frame the crew landing area on the floor. Do NOT change to
// match CAMERA_LOOK_TARGET in index.ts — this is a camera framing target.
const CAMERA_LOOK_TARGET = new THREE.Vector3(0, 2.72, 0);
const GATE_BACK = new THREE.Vector3(0, 2.72, 0.5);
// Overhead shot — high angle from behind the landing zone, looking back
// TOWARD the gate. Gate at z=0, crew land at z=8-18, player at z=50.
const OVERHEAD    = new THREE.Vector3(0, 24, 20);
// Establishing shot — LOW and CLOSE like the SGU reference image. Camera
// at roughly human eye-height (y=1.5) about 12 meters from the gate so
// the ring fills most of the frame and the room architecture looms above.
const ESTABLISH   = new THREE.Vector3(0, 1.5, 12);

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
		lookAt:  CAMERA_LOOK_TARGET,
		easing:  "linear",
	},
	// Beat 2 — CHEVRONS DIALING. Same wide shot, 9 chevron-lock SFX.
	{
		start: 2, end: 12,
		camFrom: ESTABLISH.clone(),
		camTo:   ESTABLISH.clone(),
		lookAt:  CAMERA_LOOK_TARGET,
		easing:  "linear",
	},
	// Beat 3 — KAWOOSH. Push in slightly for the effect reveal.
	{
		start: 12, end: 15,
		camFrom: ESTABLISH.clone(),
		camTo:   new THREE.Vector3(0, 4, 14),
		lookAt:  CAMERA_LOOK_TARGET,
		easing:  "ease-out",
	},
	// Beat 4 — SCOTT EMERGES. Camera BEHIND Scott's landing zone (z=14),
	// low angle, looking back at the gate. Scott flies from gate mouth
	// (z=0.8) toward and past the camera. We see him emerge from the
	// event horizon, arc through the air, and crash-land at z=10.
	{
		start: 15, end: 20,
		camFrom: new THREE.Vector3(3, 1.5, 14),
		camTo:   new THREE.Vector3(4, 1.5, 16),
		lookAt:  new THREE.Vector3(0, 2.0, 0),   // look back at gate
		easing:  "linear",
	},
	// Beat 5 — OVERHEAD. Camera elevated behind the landing zone (z=12)
	// looking backward toward the gate (z=0). This frames the gate ring
	// in the top third and the crew landing area (z=4-10) across the
	// center and bottom thirds — the classic overhead chaos shot.
	{
		start: 20, end: 32,
		camFrom: OVERHEAD.clone(),
		camTo:   OVERHEAD.clone(),
		lookAt:  new THREE.Vector3(0, 0, 3),
		easing:  "linear",
	},
	// Beat 6 — DESCENT to Eli prone on the ground; Scott crouches in.
	// Eli lands at z≈14; camera drops from overhead to eye-level beside him.
	{
		start: 32, end: 37,
		camFrom: new THREE.Vector3(1.0, 8, 12),
		camTo:   new THREE.Vector3(1.5, 1.0, 12),
		lookAt:  new THREE.Vector3(0.5, 0.3, 14),
		easing:  "ease-out",
	},
	// Beat 7 — FADE. Stays close on Eli as the cinematic hands off.
	{
		start: 37, end: 40,
		camFrom: new THREE.Vector3(1.5, 1.0, 12),
		camTo:   new THREE.Vector3(1.5, 1.0, 12),
		lookAt:  new THREE.Vector3(0.5, 0.3, 14),
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
 * Count renderable meshes inside a loaded character root. Used to detect
 * "successful" VRM loads that actually produced no geometry (e.g. our
 * 24 KB placeholder .vrm files parse fine but contain zero meshes).
 */
function countMeshes(root: THREE.Object3D): number {
	let n = 0;
	root.traverse((o) => { if ((o as THREE.Mesh).isMesh) n++; });
	return n;
}

// Standard VRoid used for anonymous extras when we don't have a
// per-character VRM. Points to the R2-hosted Rush model (known-good)
// so both dev and prod load the same high-quality geometry.
const STANDARD_VROID_PATH = "https://pub-c642ba55d4f641de916d72786545c520.r2.dev/characters/rush.vrm";

/**
 * Wrap loadCrewMember so cinematic actors always render with a real VRoid
 * body — no more blocky capsule fallbacks. When a crew member's own VRM
 * is missing or has no geometry (24 KB placeholder stubs), we load the
 * standard VRoid model instead. This gives every character a proper
 * humanoid silhouette for the throw/ragdoll sequence.
 */
async function loadCrewOrFallback(id: string, _fallbackColor: number): Promise<CharacterLoadResult> {
	try {
		const result = await loadCrewMember(id);
		const meshes = countMeshes(result.root);
		if (meshes > 0) return result;
		// Placeholder VRM — dispose and fall through to standard VRoid.
		console.warn(`[cinematic] crew "${id}" has 0 meshes, loading standard VRoid`);
		result.dispose?.();
	} catch (err) {
		console.warn(`[cinematic] crew "${id}" failed, loading standard VRoid`, err);
	}
	// Load the standard VRoid as fallback — a real humanoid model.
	return loadVRMCharacter(STANDARD_VROID_PATH);
}

interface ThrownActor {
	char: CharacterLoadResult;
	startPos: THREE.Vector3;
	velocity: THREE.Vector3;
	angularVelocity: THREE.Vector3;
	t0: number;           // delay before throw starts (within beat window)
	flightTime: number;   // seconds until cinematic forces landing at landPos
	landPos: THREE.Vector3;
	landed: boolean;
	landedAt: number;     // beatElapsed when landing occurred
	standUpDelay: number; // seconds after landing before standing up starts (procedural sequence's prone-hold derives from this)
	standUpDur: number;   // uniform pacing factor for the sequence (lower = faster recovery)
	staysDown: boolean;   // true = unconscious (Young), never stands up
	// Ragdoll-driven flight
	ragdoll: RagdollInstance | null;
	launched: boolean;
	// Procedural "natural" stand-up — built once the actor lands.
	standup: StandupSequence | null;
}

function createThrownActor(
	char: CharacterLoadResult,
	startPos: THREE.Vector3,
	velocity: THREE.Vector3,
	t0: number,
	flightTime: number,
	landPos: THREE.Vector3,
	standUpDelay = 1.5,
	standUpDur = 2.0,
	staysDown = false,
	angularVelocity = new THREE.Vector3(5 + Math.random() * 3, (Math.random() - 0.5) * 4, (Math.random() - 0.5) * 2),
): ThrownActor {
	char.root.position.copy(startPos);
	char.root.visible = false;
	return {
		char, startPos: startPos.clone(), velocity: velocity.clone(),
		angularVelocity: angularVelocity.clone(),
		t0, flightTime, landPos: landPos.clone(), landed: false,
		landedAt: 0, standUpDelay, standUpDur, staysDown,
		ragdoll: null, launched: false, standup: null,
	};
}

// ── Ragdoll-driven flight helpers ────────────────────────────────────────────
// The ragdoll's pelvis lives 1.1m above the "feet origin" at scale=1.0 (see
// buildPartConfigs in ragdoll.ts: lowerLeg 0.5 + upperLeg 0.5 + pelvisLen/2 0.1).
// To keep the VRM's feet co-located with the ragdoll's feet region we offset
// the VRM root by −1.1m in the pelvis's LOCAL frame — that way when the ragdoll
// rolls/tumbles in flight the VRM appears to tumble with it instead of orbiting
// at a fixed world-Y offset.
const RAGDOLL_PELVIS_TO_FEET = 1.1;
const _tmpVec = new THREE.Vector3();
const _tmpQuat = new THREE.Quaternion();
const _feetOffset = new THREE.Vector3();

function updateThrown(
	actor: ThrownActor,
	beatElapsed: number,
	_physicsWorld: CrashcatPhysicsWorld,
	deltaSeconds: number,
) {
	const t = beatElapsed - actor.t0;
	if (t < 0) return;

	actor.char.root.visible = true;

	// ── Landed state ─────────────────────────────────────────────────
	if (actor.landed) {
		if (actor.staysDown) {
			// Unconscious (Young) — stays prone permanently.
			actor.char.root.rotation.x = -Math.PI / 2;
			return;
		}

		// Build the natural-recovery sequence on the first post-landing
		// frame.
		//   standUpDelay  → proneHold (seconds face-down before push-up)
		//   standUpDur    → inverse pacing knob; old hand-tuned values
		//                   (1.5-3.0s) map to pacing 0.67-1.33 so faster
		//                   recoverers still finish sooner. Default
		//                   sequence runs ~6.8s at pacing 1.0.
		if (!actor.standup) {
			actor.standup = createStandupSequence(actor.char, {
				proneHold: actor.standUpDelay,
				pacing: 2.0 / Math.max(0.5, actor.standUpDur),
			});
		}
		actor.standup.update(deltaSeconds);
		return;
	}

	// ── Landing snap ─────────────────────────────────────────────────
	if (t >= actor.flightTime) {
		actor.landed = true;
		actor.landedAt = beatElapsed;
		actor.char.root.position.copy(actor.landPos);
		actor.char.root.rotation.set(-Math.PI / 2, 0, 0);
		actor.char.root.quaternion.setFromEuler(actor.char.root.rotation);
		return;
	}

	// ── In-flight parabolic arc (ragdoll disabled in cinematic) ──────
	// Ragdoll physics via Crashcat requires a broadphase listener to
	// disable collisions between constraint-linked bodies — @ggez's
	// runtime-physics-crashcat currently calls updateWorld without a
	// listener, so limb self-collision explodes the simulation. We keep
	// the ragdoll primitive for the character-viewer sandbox and use
	// authored parabolic motion + the procedural stand-up sequence for
	// the cinematic. `actor.ragdoll` / `.launched` stay on the type for
	// the day the engine grows listener support.
	actor.char.root.position.set(
		actor.startPos.x + actor.velocity.x * t,
		actor.startPos.y + actor.velocity.y * t - 4.9 * t * t,
		actor.startPos.z + actor.velocity.z * t,
	);
	actor.char.root.rotation.x = -t * 6;
	actor.char.root.rotation.z = Math.sin(t * 8) * 0.8;
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
	private cinCam: CinematicCamera;
	private flickerActive = false;
	private subtitle = createSubtitle();
	private subtitleShown = new Set<string>();
	private thrownActors: ThrownActor[] = [];
	private crewLoaded = false;
	private rushNpc: CharacterLoadResult | undefined;
	private scottNpc: CharacterLoadResult | undefined;
	private youngNpc: CharacterLoadResult | undefined;
	private tjNpc: CharacterLoadResult | undefined;
	private eliNpc: CharacterLoadResult | undefined;
	/** Anonymous crew extras — no speaking lines, used for Beat-4 chaos */
	private anonymousExtras: CharacterLoadResult[] = [];
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

	private readonly gateControl: import("./index").GateControl;
	private readonly registerDisposable: (cleanup: () => void) => void;
	private readonly physicsWorld: CrashcatPhysicsWorld;

	constructor(
		scene: THREE.Scene,
		camera: THREE.PerspectiveCamera,
		gateControl: import("./index").GateControl,
		onComplete: () => void,
		registerDisposable: (cleanup: () => void) => void,
		physicsWorld: CrashcatPhysicsWorld,
		playerObject?: THREE.Object3D,
	) {
		this.scene = scene;
		this.camera = camera;
		this.cinCam = new CinematicCamera(camera);
		this.gateControl = gateControl;
		this.registerDisposable = registerDisposable;
		this.onComplete = onComplete;
		this.playerObject = playerObject;
		this.physicsWorld = physicsWorld;

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
		// Blanket-restore all children. Fallback capsules no longer exist —
		// the player's visual is VRM-only, and the VRM loader hides itself
		// via parent-remove if anything unexpected shows up.
		this.playerObject.traverse(obj => {
			obj.visible = true;
		});
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

		// Start the real gate dial at T_DIAL_START
		if (elapsed >= T_DIAL_START && !this.audioPlayed.has("dial-start")) {
			this.audioPlayed.add("dial-start");
			this.gateControl.startDial();
		}

		// Beat 2 — CHEVRONS DIALING. Play chevron-lock once per chevron,
		// spaced evenly over the 10-second dial window (~1s apart, last
		// lock fires just before kawoosh). Drives the real gate chevrons.
		const DIAL_DURATION = T_DIAL_END - T_DIAL_START;
		for (let i = 0; i < 9; i++) {
			const chevronTime = T_DIAL_START + (i + 1) * (DIAL_DURATION / 10);
			const key = `chevron-${i}`;
			if (elapsed >= chevronTime && !this.audioPlayed.has(key)) {
				this.audioPlayed.add(key);
				void audio.play("chevron-lock");
				this.gateControl.forceLockedChevrons(i + 1);
			}
		}

		// Beat 3 — KAWOOSH. Trigger real gate kawoosh state + audio.
		if (elapsed >= T_KAWOOSH && !this.audioPlayed.has("kawoosh")) {
			this.audioPlayed.add("kawoosh");
			void audio.play("stargate-kawoosh");
			this.gateControl.forceState("kawoosh");
		}

		// Beat 4 — Scott steps through the gate.
		if (elapsed >= T_SCOTT_EMERGE && !this.audioPlayed.has("scott-emerge")) {
			this.audioPlayed.add("scott-emerge");
			void audio.play("wormhole-transit");
		}
		// Scott's radio call — he gets up (flight 1s + delay 1s + stand 1.5s ≈ t=18.5)
		// then radios "It's clear! Start the evacuation!" with radio clicks.
		if (elapsed >= 18.5 && !this.audioPlayed.has("scott-radio-click-1")) {
			this.audioPlayed.add("scott-radio-click-1");
			void audio.play("radio-click");
		}
		if (elapsed >= 19 && !this.audioPlayed.has("scott-clear-voice")) {
			this.audioPlayed.add("scott-clear-voice");
			void audio.play("scott-clear");
		}
		if (elapsed >= 21.5 && !this.audioPlayed.has("scott-radio-click-2")) {
			this.audioPlayed.add("scott-radio-click-2");
			void audio.play("radio-click");
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
			this.gateControl.shutdownGate();
		}
		// (Beat 6 — Scott checking on Eli) — voice line goes here once
		// scott-bark-eli is uploaded to R2. Subtitle-only for now.
	}

	// ── Gate flicker effect (shutdown beat) ──────────────────────────────────

	private updateGateFlicker(elapsed: number) {
		// Flicker the real event horizon during shutdown beat (t≈27-29)
		if (elapsed >= 27 && elapsed <= 29) {
			const flicker = Math.random() > 0.7;
			this.gateControl.eventHorizon.visible = flicker;
			this.flickerActive = true;
		} else if (this.flickerActive && elapsed > 29) {
			this.flickerActive = false;
			this.gateControl.eventHorizon.visible = true;
		}
	}

	// ── Crew loading ──────────────────────────────────────────────────────────
	// NOTE: anonymous "chaos" capsule actors were removed — all cinematic
	// cast are now VRMs (named crew via loadCrewOrFallback, which falls back
	// to the standard VRoid when a crew member's model is a placeholder).
	// See src/systems/ragdoll.ts for the physics-driven ragdoll primitive
	// that will eventually drive thrown-character arcs in a follow-up pass.

	private async loadCrew() {
		// Load named crew via loadCrewOrFallback so any missing / placeholder
		// VRM falls back to the standard VRoid. Eli is direct-loaded (player
		// model — guaranteed real asset). In addition to the 5 named roles,
		// we stream in 3 anonymous extras (Greer, Chloe, and one VRoid-fallback
		// "crewman") so the overhead shot in Beat 4 shows a real crowd of
		// crew getting flung through the gate instead of just the speaking cast.
		const [scott, rush, young, tj, eli, greer, chloe, extra] = await Promise.allSettled([
			loadCrewOrFallback("scott", 0x4466aa),
			loadCrewOrFallback("rush",  0x444444),
			loadCrewOrFallback("young", 0x556677),
			loadCrewOrFallback("tj",    0x88aabb),
			loadVRMCharacter("https://pub-c642ba55d4f641de916d72786545c520.r2.dev/characters/eli.vrm"),
			loadCrewOrFallback("greer", 0x5a4a3a),
			loadCrewOrFallback("chloe", 0x7a6a88),
			loadVRMCharacter(STANDARD_VROID_PATH), // "unknown crewman" — falls back to Rush model
		]);

		// If the cinematic was disposed while crew was loading (e.g. player
		// skipped, or the scene was torn down), discard loaded VRM resources
		// instead of attaching them to a dead scene.
		if (this.disposed) {
			for (const result of [scott, rush, young, tj, eli, greer, chloe, extra]) {
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
			this.rushNpc.root.position.set(0.3, 0.1, 0.8);
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

		// Anonymous extras — registered here for lifecycle. They get their
		// own thrown-actor entries below; no field needed on the class.
		for (const extraResult of [greer, chloe, extra]) {
			if (extraResult.status === "fulfilled") {
				this.scene.add(extraResult.value.root);
				extraResult.value.root.visible = false;
				this.anonymousExtras.push(extraResult.value);
			}
		}

		// Set up thrown actors once crew is loaded
		const actors: ThrownActor[] = [];

		// ── Named crew throw trajectories ────────────────────────────────
		// Gate is at z=0. Crew emerge from the event horizon and are THROWN
		// into the room (+Z direction, toward the player at z=12). The first
		// gate transit in SGU canon is violent — crew are launched at high
		// speed, tumble, slide, hit things. All land positions are at +Z.
		//
		// createThrownActor params:
		//   (char, startPos, velocity, t0, flightTime, landPos)
		//
		// IMPORTANT GEOMETRY RULES:
		//   - startPos.y ≈ 0.1 (FLOOR level at gate base). Characters walk
		//     through the gate on the FLOOR; the portal is now sunk 0.2m below
		//     floor so there's no ledge. Portal center is at y≈2.35.
		//   - startPos.z ≈ 0.8 (+Z = player side of gate = just emerged).
		//   - velocity.z  >0 = thrown INTO the room (+Z toward player spawn).
		//   - All land positions at +Z, further from the gate for chaos.

		// createThrownActor extra args: standUpDelay, standUpDur, staysDown
		// Scott gets up FIRST (fastest) so he can radio "all clear" while standing.
		// Young NEVER gets up — he's unconscious after hitting the wall.

		if (scott.status === "fulfilled") {
			// Scott — first through, controlled but fast. Gets up quickly.
			actors.push(createThrownActor(
				scott.value,
				new THREE.Vector3(0, 0.1, 0.8),
				new THREE.Vector3(-0.5, 0.3, 14),
				0, 1.0,
				new THREE.Vector3(-1.0, 0.1, 10),
				1.0,   // standUpDelay — gets up 1s after landing
				1.5,   // standUpDur — takes 1.5s to stand
				false,
			));
		}

		if (rush.status === "fulfilled") {
			// Rush — second wave, slower to recover.
			actors.push(createThrownActor(
				rush.value,
				new THREE.Vector3(0.3, 0.1, 0.8),
				new THREE.Vector3(0.6, 0.8, 16),
				0.3, 0.9,
				new THREE.Vector3(2.0, 0.1, 12),
				3.0,   // standUpDelay
				2.5,   // standUpDur — Rush is older, takes longer
				false,
			));
		}

		if (tj.status === "fulfilled") {
			// TJ — third wave, medic, gets up relatively quickly.
			actors.push(createThrownActor(
				tj.value,
				new THREE.Vector3(-0.4, 0.1, 0.8),
				new THREE.Vector3(-2.0, 1.2, 13),
				0.5, 0.8,
				new THREE.Vector3(-3.5, 0.1, 13),
				2.0,   // standUpDelay
				2.0,   // standUpDur
				false,
			));
		}

		if (eli.status === "fulfilled") {
			// Eli (NPC copy) — hard crash, slow to recover.
			actors.push(createThrownActor(
				eli.value,
				new THREE.Vector3(0.2, 0.1, 0.8),
				new THREE.Vector3(1.5, 1.5, 15),
				0.7, 0.9,
				new THREE.Vector3(3.0, 0.1, 14),
				4.0,   // standUpDelay — dazed
				3.0,   // standUpDur — slow
				false,
			));
		}

		if (young.status === "fulfilled") {
			// Young — LAST through, hits wall at max velocity. UNCONSCIOUS.
			actors.push(createThrownActor(
				young.value,
				new THREE.Vector3(-0.2, 0.1, 0.8),
				new THREE.Vector3(-1.2, 0.4, 24),
				0, 0.7,
				new THREE.Vector3(-2.0, 0.1, 18),
				0, 0,
				true,  // staysDown — unconscious, never stands up
			));
		}

		// ── Anonymous extras — fill out the Beat-4 chaos sequence ────────────
		// These get staggered spawns in T_CHAOS_START's time window so the
		// overhead wide shot reads as a real crowd of crew getting flung.
		// Spawn offsets / landings are scattered around the gate mouth to
		// spread the tumble visually. Fast stand-up (no one is significant
		// enough to dwell on) so they're upright and out of frame quickly.
		const extraConfigs = [
			{ side: -1, t0: 0.1, flightTime: 1.0, land: [-3.5, 0.1, 11] as const, sd: 2.5, sdu: 1.8 },
			{ side:  1, t0: 0.6, flightTime: 0.9, land: [ 3.2, 0.1,  9] as const, sd: 2.0, sdu: 1.8 },
			{ side: -1, t0: 1.3, flightTime: 1.1, land: [-4.5, 0.1, 14] as const, sd: 3.2, sdu: 2.2 },
		];
		for (let i = 0; i < this.anonymousExtras.length && i < extraConfigs.length; i++) {
			const extra = this.anonymousExtras[i];
			const cfg = extraConfigs[i];
			actors.push(createThrownActor(
				extra,
				new THREE.Vector3(cfg.side * 0.4, 0.1, 0.8),
				new THREE.Vector3(cfg.side * 2.5, 1.0 + Math.random() * 1.5, 11 + Math.random() * 4),
				cfg.t0, cfg.flightTime,
				new THREE.Vector3(cfg.land[0], cfg.land[1], cfg.land[2]),
				cfg.sd, cfg.sdu,
				false,
			));
		}

		this.thrownActors = actors;
		this.crewLoaded = true;
	}

	// ── Camera ────────────────────────────────────────────────────────────────

	private applyCamera(elapsed: number) {
		const beat = BEATS.find(b => elapsed >= b.start && elapsed < b.end) ?? BEATS[BEATS.length - 1];
		const rawT = (elapsed - beat.start) / (beat.end - beat.start);

		// Kill shake during calm beats (establishing, dial, first second of overhead)
		if (elapsed < T_OVERHEAD || (elapsed >= T_OVERHEAD && elapsed < T_OVERHEAD + 2)) {
			this.cinCam.killShake();
		}
		this.cinCam.updateShake();

		// Use CinematicCamera.lerpTo for the beat transition
		this.cinCam.lerpTo(
			beat.camFrom, beat.camTo, beat.lookAt,
			rawT, beat.easing,
		);
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
		// Scott's radio call subtitle — synced with the TTS voice line at t=19
		// (after he stands up from his landing at ~t=18.5).
		if (elapsed >= 19 && !this.subtitleShown.has("scott-clear")) {
			this.subtitleShown.add("scott-clear");
			this.subtitle.show("[RADIO] It's clear! Start the evacuation!", 3.0);
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
		// "Young's not moving" is the FINAL subtitle — fires just before the
		// cinematic hands off control (~1s before fade starts at t=37).
		if (elapsed >= 36 && !this.subtitleShown.has("young-down")) {
			this.subtitleShown.add("young-down");
			this.subtitle.show("Young's not moving…", 2.5);
		}
		// "Eli... Eli, can you hear me?" is intentionally NOT a cinematic
		// subtitle — it's the first line of the Scott opening dialogue,
		// which starts as soon as the cinematic ends. Duplicating it here
		// would show the line twice in a row.
	}

	// ── Beat-triggered crew visibility ────────────────────────────────────────

	private updateCrew(elapsed: number, deltaSeconds: number) {
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
		//
		// DO NOT clamp to max(0, ...) — a negative beatE means "not yet
		// entered the gate" and updateThrown correctly returns early when
		// t < 0. Clamping to 0 made actors ghost-appear at the gate mouth
		// the moment the first crew throw began.
		this.thrownActors.forEach((actor, idx) => {
			// Named crew indices 0-4 are fixed by the loadCrew() push order:
			// 0=scott, 1=rush, 2=tj, 3=eli, 4=young. Indices 5+ are anonymous
			// Beat-4 extras (greer / chloe / vroid-fallback) that all fire
			// during the chaos window.
			const beatE =
				idx === 0 ? elapsed - T_SCOTT_EMERGE :
				idx === 1 ? elapsed - T_RUSH :
				idx === 2 || idx === 3 ? elapsed - T_TJ_ELI :
				idx === 4 ? elapsed - T_YOUNG_IMPACT :
				elapsed - T_CHAOS_START;
			updateThrown(actor, beatE, this.physicsWorld, deltaSeconds);
		});

		// ── TJ kneels next to Young during the "descent" beat ─────────────
		// Once TJ has finished her own stand-up sequence (she wraps ~31s),
		// move her next to the unconscious Young and force a kneeling pose
		// so the camera zoom reveals her tending to him rather than standing
		// idle across the room. Runs every frame so spring-bone updates
		// don't drift the pose back.
		if (elapsed >= T_GATE_SHUTDOWN && this.tjNpc && this.youngNpc) {
			const young = this.youngNpc.root.position;
			this.tjNpc.root.position.set(young.x + 1.0, 0.1, young.z - 0.4);
			// Face Young — atan2 on the XZ delta from TJ → Young
			const dx = young.x - this.tjNpc.root.position.x;
			const dz = young.z - this.tjNpc.root.position.z;
			this.tjNpc.root.rotation.set(0, Math.atan2(dx, dz) + Math.PI, 0);
			applyKneelingPose(this.tjNpc);
			this.tjNpc.root.visible = true;
		}

		// Chaos actors removed — nothing to update here.

		// Shake on the chaos-arrival surge and again on Young's impact.
		if (elapsed >= T_CHAOS_START + 0.3 && elapsed < T_CHAOS_START + 1 && this.cinCam.currentShakeIntensity < 0.05) {
			this.cinCam.shake(0.22);
		}
		if (elapsed >= T_YOUNG_IMPACT && elapsed < T_YOUNG_IMPACT + 0.5 && this.cinCam.currentShakeIntensity < 0.05) {
			this.cinCam.shake(0.35);
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
		this.updateGateFlicker(this.elapsed);
		this.updateCrew(this.elapsed, delta);
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

		// Crew NPCs — KEEP in scene as gameplay NPCs (except cinematic Eli
		// copy which would duplicate the player). Stand them upright at their
		// landing positions so they're visible in the gameplay world. Any
		// in-flight ragdoll bodies are released back to the physics world
		// so they don't keep simulating after the cinematic ends. Any in-
		// progress stand-up sequences are cleaned up so the VRM bones return
		// to rest pose for normal gameplay idle animations.
		for (const actor of this.thrownActors) {
			actor.ragdoll?.dispose();
			actor.ragdoll = null;
			actor.standup?.dispose();
			actor.standup = null;
			actor.char.root.visible = true;
			actor.char.root.rotation.set(0, 0, 0); // upright
			actor.char.root.quaternion.setFromEuler(actor.char.root.rotation);
		}
		// Remove cinematic Eli (player takes over)
		if (this.eliNpc) {
			this.scene.remove(this.eliNpc.root);
			this.eliNpc.dispose?.();
			this.eliNpc = undefined;
		}
		// Keep Young down (unconscious)
		if (this.youngNpc) {
			this.youngNpc.root.rotation.x = -Math.PI / 2;
		}

		// Register VRM disposal for kept NPCs so scene exit frees
		// spring bone textures, morph targets, and bone textures.
		for (const npc of [this.scottNpc, this.rushNpc, this.youngNpc, this.tjNpc]) {
			if (npc) {
				this.registerDisposable(() => npc.dispose());
			}
		}
		// Anonymous extras are truly transient — dispose immediately rather
		// than keeping them around as gameplay NPCs (no one talks to them).
		for (const extra of this.anonymousExtras) {
			this.scene.remove(extra.root);
			extra.dispose?.();
		}
		this.anonymousExtras = [];
		this.scottNpc = undefined;
		this.rushNpc = undefined;
		this.youngNpc = undefined;
		this.tjNpc = undefined;
		this.thrownActors = [];
	}
}
