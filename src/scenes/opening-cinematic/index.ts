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

const BEATS: CreditBeat[] = [
	{ start: 1,    end: 5,  fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "In a distant corner of the universe…" },
	{ start: 5.5,  end: 9.5, fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "the Ancients launched a ship called Destiny —\nseeded before humanity walked the Earth." },
	{ start: 10,   end: 14, fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "For millions of years it has drifted alone,\nmapping the farthest reaches of space." },
	{ start: 14.5, end: 18, fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "Today, nine stranded souls dial a nine-chevron address…" },
	{ start: 18.5, end: 22, fontSize: "clamp(2.2rem, 6vw, 4rem)",
		text: "STARGATE\u00A0UNIVERSE" },
];

const TOTAL_DURATION = 23;

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

	// Quiet score bed under the credits so the iconic theme stays owned
	// by the main menu. sgu-soundtrack is a looping exploration bed —
	// perfect for under-dialogue ambience and the Destiny reveal.
	const audio = AudioManager.getInstance();
	void audio.play("sgu-soundtrack", undefined, { volume: 0.45 });

	let elapsed = 0;
	let disposed = false;
	let finished = false;

	const finish = (): void => {
		if (finished) return;
		finished = true;
		// Signal gate-room to boot in arrival-cinematic mode
		sessionStorage.setItem("sgu-new-game", "1");
		void gotoScene("gate-room");
	};

	const handleKey = (e: KeyboardEvent): void => {
		if (e.code === "Escape" || e.code === "Space" || e.code === "Enter") {
			finish();
		}
	};
	window.addEventListener("keydown", handleKey);

	// Position the ship far back so the opening frames are just stars
	destiny.root.position.set(4, -0.5, 40);
	destiny.root.rotation.y = Math.PI * 0.9; // showing 3/4 rear quarter first

	return {
		update(delta: number): void {
			if (disposed) return;
			elapsed += delta;

			// Star drift
			stars.rotation.y += delta * 0.01;
			stars.rotation.x  = Math.sin(elapsed * 0.04) * 0.03;

			// Destiny drifts slowly toward the camera, then past the right
			// side of frame — classic "reveal" move. Progress runs 0→1 across
			// the cinematic.
			const p = Math.min(1, elapsed / TOTAL_DURATION);
			// Pull from z=40 to z=-4 in an ease-out curve so the ship
			// decelerates as it gets close.
			const ez = 1 - Math.pow(1 - p, 2);
			destiny.root.position.z = 40 - ez * 44;
			// Slight lateral drift so we see more of the hull
			destiny.root.position.x = 4 - ez * 3;
			// Slow yaw — reveals the forward hull by the end
			destiny.root.rotation.y = Math.PI * 0.9 + ez * 0.35;
			// Gentle roll for a "drifting" feel
			destiny.root.rotation.z = Math.sin(elapsed * 0.15) * 0.02;

			// Camera: mostly still with subtle breathing so it feels cinematic
			camera.position.set(
				Math.sin(elapsed * 0.08) * 0.6,
				0.3 + Math.cos(elapsed * 0.06) * 0.2,
				0,
			);
			camera.lookAt(destiny.root.position);

			// Update current credit beat
			const activeBeat = BEATS.find((b) => elapsed >= b.start && elapsed < b.end) ?? null;
			credits.setBeat(activeBeat);

			// Auto-finish at TOTAL_DURATION
			if (elapsed >= TOTAL_DURATION) {
				finish();
			}
		},

		dispose(): void {
			disposed = true;
			window.removeEventListener("keydown", handleKey);
			// Stop the score bed so the gate-room cinematic owns the audio
			// mix (SFX-driven with no background music).
			audio.stop("sgu-soundtrack");
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
