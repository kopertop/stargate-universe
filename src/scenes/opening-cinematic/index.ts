/**
 * Opening Cinematic — story intro played on NEW GAME.
 *
 * Flow:
 *   start-screen → NEW GAME → opening-cinematic → gate-room (with kawoosh cinematic)
 *
 * This scene shows a starfield + credit beats + a procedural reveal of the
 * Ancient vessel Destiny drifting through deep space. When the beats finish
 * (or the player skips with ESC/Space) it sets the `sgu-new-game` flag so
 * the gate-room's GateRoomCinematicController plays the 9-beat arrival
 * sequence next.
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { AudioManager } from "../../systems/audio";
import { Action, getInput } from "../../systems/input";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── Credit beats ─────────────────────────────────────────────────────────────

interface CreditBeat {
	/** Seconds into the cinematic when this beat begins fading in. */
	start: number;
	/** Seconds into the cinematic when this beat begins fading out. */
	end: number;
	/** Line(s) of text. `\n` renders a line break. */
	text: string;
	/** Font size — bigger for title, smaller for body. */
	fontSize: string;
}

// ─── 60-second opening timeline ─────────────────────────────────────────────
//
// This scene is act one (0-20s). The gate-room arrival cinematic (fired
// via sgu-new-game flag) is act two (20-60s). The sgu-theme-song plays
// once at t=0 and runs the full 60s without a restart — this scene
// starts it and INTENTIONALLY does not stop on dispose so the theme
// carries through the scene swap.
//
// Test any second of this scene in isolation via ?cinstep=N:
//   /?scene=opening-cinematic&cinstep=12   ← jumps to t=12
//
const TOTAL_DURATION = 20;

const BEATS: CreditBeat[] = [
	{ start: 0.5, end: 4.5,  fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "In a distant corner of the universe…" },
	{ start: 5,    end: 9,   fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "the Ancients launched a ship called Destiny —\nseeded before humanity walked the Earth." },
	{ start: 9.5,  end: 13.5, fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "For millions of years it has drifted alone,\nmapping the farthest reaches of space." },
	{ start: 14,   end: 17,   fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "One gate has a nine-symbol address.\nEli figured out how to dial it." },
	{ start: 17,   end: 20,   fontSize: "clamp(2.2rem, 6vw, 4rem)",
		text: "STARGATE\u00A0UNIVERSE" },
];

// ─── Star-field (same look as start-screen for continuity) ────────────────────

function buildStarField(scene: THREE.Scene): THREE.Points {
	const COUNT = 2500;
	const pos = new Float32Array(COUNT * 3);
	const col = new Float32Array(COUNT * 3);
	for (let i = 0; i < COUNT; i++) {
		const theta = Math.random() * Math.PI * 2;
		const phi   = Math.acos(2 * Math.random() - 1);
		const r     = 80 + Math.random() * 140;
		pos[i * 3    ] = r * Math.sin(phi) * Math.cos(theta);
		pos[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
		pos[i * 3 + 2] = r * Math.cos(phi);
		const brightness = 0.5 + Math.random() * 0.5;
		const blueShift  = Math.random() * 0.3;
		col[i * 3    ] = brightness * (1 - blueShift * 0.4);
		col[i * 3 + 1] = brightness * (1 - blueShift * 0.2);
		col[i * 3 + 2] = brightness;
	}
	const geo = new THREE.BufferGeometry();
	geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
	geo.setAttribute("color",    new THREE.BufferAttribute(col, 3));
	const mat = new THREE.PointsMaterial({
		size: 0.55, sizeAttenuation: true, vertexColors: true,
		transparent: true, opacity: 0.88,
	});
	const points = new THREE.Points(geo, mat);
	scene.add(points);
	return points;
}

// ─── Procedural Destiny ─────────────────────────────────────────────────────────
//
// The Destiny silhouette is an elongated wedge: a narrow forward command
// section, a wider central hull, back-swept "wings", and a rear engine bank.
// It's intentionally low-poly — every surface uses the same dark Ancient-metal
// material with blue emissive accents along the trim.

interface Destiny {
	root: THREE.Group;
	disposables: { geo: THREE.BufferGeometry; mat: THREE.Material }[];
}

function buildDestiny(scene: THREE.Scene): Destiny {
	const root = new THREE.Group();
	root.name = "destiny-ship";
	const disposables: Destiny["disposables"] = [];

	const hullMat = new THREE.MeshStandardMaterial({
		color: 0x1d2030, roughness: 0.85, metalness: 0.25,
		emissive: 0x0a0d18, emissiveIntensity: 1.0,
	});
	const trimMat = new THREE.MeshStandardMaterial({
		color: 0x4488ff, emissive: 0x4488ff, emissiveIntensity: 2.0,
	});
	const engineMat = new THREE.MeshBasicMaterial({
		color: 0x66bbff, transparent: true, opacity: 0.95,
		blending: THREE.AdditiveBlending, depthWrite: false,
	});

	// Add a mesh with tracked disposal
	const push = (geo: THREE.BufferGeometry, mat: THREE.Material, setup: (m: THREE.Mesh) => void) => {
		const m = new THREE.Mesh(geo, mat);
		setup(m);
		root.add(m);
		disposables.push({ geo, mat });
		return m;
	};

	// Central hull — long narrow box, tapered toward the front
	const hullLen = 14;
	const hullGeo = new THREE.BoxGeometry(2.2, 1.4, hullLen);
	push(hullGeo, hullMat, (m) => m.position.set(0, 0, 0));

	// Forward command section — narrower, slightly raised
	const cmdGeo = new THREE.BoxGeometry(1.4, 1.0, 3);
	push(cmdGeo, hullMat, (m) => m.position.set(0, 0.6, -hullLen / 2 - 1.2));

	// Nose — small wedge
	const noseGeo = new THREE.ConeGeometry(0.6, 1.6, 4);
	push(noseGeo, hullMat, (m) => {
		m.rotation.x = -Math.PI / 2;
		m.rotation.z = Math.PI / 4;
		m.position.set(0, 0.6, -hullLen / 2 - 3.3);
	});

	// Swept-back wings (port + starboard)
	const wingGeo = new THREE.BoxGeometry(5, 0.3, 4);
	for (const xSign of [-1, 1]) {
		push(wingGeo, hullMat, (m) => {
			m.position.set(xSign * 3, -0.1, hullLen / 2 - 3);
			m.rotation.y = xSign * 0.35; // sweep back
		});
	}

	// Rear engine housing
	const engHouseGeo = new THREE.BoxGeometry(3, 1.6, 2.5);
	push(engHouseGeo, hullMat, (m) => m.position.set(0, 0, hullLen / 2 + 0.5));

	// Engine glows (two blue intakes)
	const engineGlowGeo = new THREE.CircleGeometry(0.55, 24);
	for (const xSign of [-1, 1]) {
		push(engineGlowGeo, engineMat, (m) => {
			m.position.set(xSign * 0.8, 0, hullLen / 2 + 1.8);
			m.rotation.y = Math.PI; // face rearward
		});
	}

	// Hull trim strips — thin glowing lines along the sides
	const trimGeo = new THREE.BoxGeometry(0.06, 0.08, hullLen - 1);
	for (const xSign of [-1, 1]) {
		push(trimGeo, trimMat, (m) => m.position.set(xSign * 1.12, 0.4, 0));
	}

	scene.add(root);
	return { root, disposables };
}

function disposeDestiny(scene: THREE.Scene, destiny: Destiny): void {
	scene.remove(destiny.root);
	for (const { geo, mat } of destiny.disposables) {
		geo.dispose();
		mat.dispose();
	}
}

// ─── Credit overlay (DOM) ─────────────────────────────────────────────────────

interface CreditOverlay {
	setBeat: (beat: CreditBeat | null) => void;
	dispose: () => void;
}

function createCreditOverlay(): CreditOverlay {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;left:0;right:0;bottom:22%;",
		"text-align:center;pointer-events:none;z-index:80;",
		"color:#d4b96a;letter-spacing:0.08em;font-weight:600;",
		"text-shadow:0 0 18px rgba(68,136,255,0.35),0 2px 8px rgba(0,0,0,0.9);",
		"font-family:'Segoe UI',sans-serif;",
		"white-space:pre-line;opacity:0;",
		"transition:opacity 0.8s ease;",
	].join("");
	document.body.appendChild(el);

	let currentBeat: CreditBeat | null = null;

	return {
		setBeat(beat) {
			if (beat === currentBeat) return;
			currentBeat = beat;
			if (beat) {
				el.textContent = beat.text;
				el.style.fontSize = beat.fontSize;
				el.style.opacity = "1";
			} else {
				el.style.opacity = "0";
			}
		},
		dispose() { el.remove(); },
	};
}

// ─── Skip hint overlay ────────────────────────────────────────────────────────

function createSkipHint(): { dispose: () => void } {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;top:2rem;right:2rem;z-index:80;",
		"color:rgba(255,255,255,0.45);font-size:0.75rem;",
		"letter-spacing:0.12em;pointer-events:none;",
		"font-family:'Segoe UI',sans-serif;text-transform:uppercase;",
	].join("");
	el.textContent = "Press ESC to skip";
	document.body.appendChild(el);
	return { dispose: () => el.remove() };
}

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene } = context;

	// Deep space — black with a hint of blue
	scene.background = new THREE.Color(0x000005);
	scene.fog = null;

	// Soft key light so the ship isn't pitch black
	const keyLight = new THREE.DirectionalLight(0xffeecc, 3);
	keyLight.position.set(-20, 12, -8);
	scene.add(keyLight);
	const ambient = new THREE.AmbientLight(0x223344, 1.2);
	scene.add(ambient);

	// Camera framed on the ship's center, slightly offset so we see 3/4 view
	camera.fov = 42;
	camera.near = 0.5;
	camera.far = 800;
	camera.updateProjectionMatrix();

	const stars = buildStarField(scene);
	const destiny = buildDestiny(scene);
	const credits = createCreditOverlay();
	const skipHint = createSkipHint();

	// Play the SGU theme, forced to LOOP so it spans the full 60-second
	// cinematic (the track file itself is ~45s, so it'd run out mid-
	// gate-room arrival without loop:true). It starts here and
	// intentionally keeps playing through the scene transition into
	// gate-room; the arrival cinematic inherits this audio and stops
	// it only when the cinematic ends.
	const audio = AudioManager.getInstance();
	void audio.play("sgu-theme-song", undefined, { loop: true, volume: 0.8 });

	// ?cinstep=N — jump to elapsed = N seconds for testing. Clamped to
	// [0, TOTAL_DURATION - 0.1] so a skip value of 20 doesn't immediately
	// tear the scene down before you can see anything.
	const cinStepRaw = new URLSearchParams(window.location.search).get("cinstep");
	const cinStep = cinStepRaw !== null ? Number.parseFloat(cinStepRaw) : NaN;
	let elapsed = Number.isFinite(cinStep)
		? Math.max(0, Math.min(TOTAL_DURATION - 0.1, cinStep))
		: 0;
	let disposed = false;
	let finished = false;

	// Skip handled via InputManager — Action.MenuConfirm (Enter/Gamepad A)
	// and Action.Pause (Escape/Gamepad Start) both end the cinematic.
	const input = getInput();

	// Ship stationary at origin — camera orbits around it.
	destiny.root.position.set(0, 0, 0);
	destiny.root.rotation.y = 0;           // nose pointing −Z (ship forward)

	const finish = (): void => {
		if (finished) return;
		finished = true;
		// Signal gate-room to boot in arrival-cinematic mode
		sessionStorage.setItem("sgu-new-game", "1");
		void gotoScene("gate-room");
	};

	// ── Camera flight plan (parametric orbit) ─────────────────────────────
	//
	// Phase 1 (0-3s):   Pull-back reveal. Camera starts close on hull,
	//                    rapidly backs out so starfield dominates frame.
	// Phase 2 (3-12s):  Orbit counterclockwise from rear-quarter → side →
	//                    full front view (nose-on). Fixed distance ~30.
	// Phase 3 (12-18s): Push-in toward the nose cone from front view.
	//                    Camera closes from r=30 to r=10.
	// Phase 4 (18-20s): Final close on hull / smash to black.
	//
	// Orbit angle θ:  π (behind ship, engines) → 0 (front, nose)
	// θ = π at t=0, sweeps to 0 at t=12, stays 0 through push-in.

	const smooth = (t: number) => t * t * (3 - 2 * t); // hermite smoothstep

	return {
		update(delta: number): void {
			if (disposed) return;
			elapsed += delta;

			// Skip on any confirm/pause press
			if (input.isActionJustPressed(Action.MenuConfirm) || input.isActionJustPressed(Action.Pause)) {
				finish();
			}

			// Star drift
			stars.rotation.y += delta * 0.008;
			stars.rotation.x  = Math.sin(elapsed * 0.03) * 0.02;

			// Gentle ship roll / drift
			destiny.root.rotation.z = Math.sin(elapsed * 0.12) * 0.015;
			destiny.root.rotation.x = Math.sin(elapsed * 0.08 + 1) * 0.01;

			// ── Camera orbit ─────────────────────────────────────────────
			let camR: number;
			let camTheta: number;
			let camY: number;

			if (elapsed < 3) {
				const t = elapsed / 3;
				camR = 6 + smooth(t) * 44;
				camTheta = Math.PI * 0.85;
				camY = 1 + smooth(t) * 3;
			} else if (elapsed < 12) {
				const t = (elapsed - 3) / 9;
				camR = 30 + Math.sin(t * Math.PI) * 5;
				camTheta = Math.PI * (1 - smooth(t));
				camY = 4 - smooth(t) * 2;
			} else if (elapsed < 18) {
				const t = (elapsed - 12) / 6;
				camR = 30 - smooth(t) * 22;
				camTheta = 0;
				camY = 2 - smooth(t) * 0.8;
			} else {
				const t = (elapsed - 18) / 2;
				camR = 8 - smooth(Math.min(1, t)) * 3;
				camTheta = 0;
				camY = 1.2 - smooth(Math.min(1, t)) * 0.4;
			}

			camera.position.set(
				camR * Math.sin(camTheta),
				camY,
				-camR * Math.cos(camTheta),
			);
			camera.lookAt(destiny.root.position);

			const activeBeat = BEATS.find((b) => elapsed >= b.start && elapsed < b.end) ?? null;
			credits.setBeat(activeBeat);

			if (elapsed >= TOTAL_DURATION) {
				finish();
			}
		},

		dispose(): void {
			disposed = true;
			// DO NOT stop sgu-theme-song here — the gate-room arrival
			// cinematic is the continuation of the same 60-second musical
			// beat. Music is stopped when the gate-room cinematic ends
			// (see cinematic-controller's dispose).
			credits.dispose();
			skipHint.dispose();
			scene.remove(keyLight);
			scene.remove(ambient);
			scene.remove(stars);
			stars.geometry.dispose();
			(stars.material as THREE.PointsMaterial).dispose();
			disposeDestiny(scene, destiny);
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
