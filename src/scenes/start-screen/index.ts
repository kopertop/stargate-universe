/**
 * Start Screen — STARGATE UNIVERSE
 *
 * DOM overlay scene over a rotating Three.js star-field.
 * NEW GAME → opening-cinematic
 * CONTINUE → gate-room
 *
 * Registered as the initial scene via vite.config.ts initialSceneId.
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

// ─── Star-field ───────────────────────────────────────────────────────────────

const buildStarField = (scene: THREE.Scene): THREE.Points => {
	const COUNT = 2500;
	const pos = new Float32Array(COUNT * 3);
	const col = new Float32Array(COUNT * 3);

	for (let i = 0; i < COUNT; i++) {
		const theta = Math.random() * Math.PI * 2;
		const phi   = Math.acos(2 * Math.random() - 1);
		const r     = 60 + Math.random() * 120;

		pos[i * 3 + 0] = r * Math.sin(phi) * Math.cos(theta);
		pos[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
		pos[i * 3 + 2] = r * Math.cos(phi);

		// Blue-white colour variation
		const brightness = 0.5 + Math.random() * 0.5;
		const blueShift  = Math.random() * 0.3;
		col[i * 3 + 0] = brightness * (1 - blueShift * 0.4);
		col[i * 3 + 1] = brightness * (1 - blueShift * 0.2);
		col[i * 3 + 2] = brightness;
	}

	const geo = new THREE.BufferGeometry();
	geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
	geo.setAttribute("color",    new THREE.BufferAttribute(col, 3));

	const mat = new THREE.PointsMaterial({
		size: 0.55,
		sizeAttenuation: true,
		vertexColors: true,
		transparent: true,
		opacity: 0.88,
	});

	const points = new THREE.Points(geo, mat);
	scene.add(points);
	return points;
};

// ─── DOM overlay ──────────────────────────────────────────────────────────────

interface StartUI {
	root: HTMLDivElement;
	dispose: () => void;
}

const createStartUI = (
	onNewGame: () => void,
	onContinue: () => void,
): StartUI => {
	const root = document.createElement("div");
	root.id    = "start-screen";
	Object.assign(root.style, {
		position:        "fixed",
		inset:           "0",
		display:         "flex",
		flexDirection:   "column",
		alignItems:      "center",
		justifyContent:  "center",
		zIndex:          "100",
		fontFamily:      "'Courier New', monospace",
		pointerEvents:   "none",
		userSelect:      "none",
	});

	// ── Title ───────────────────────────────────────────────────────────────
	const titleLine1 = document.createElement("div");
	Object.assign(titleLine1.style, {
		color:       "#a8d4ff",
		fontSize:    "52px",
		fontWeight:  "bold",
		letterSpacing: "10px",
		textShadow:  "0 0 28px #4488ff, 0 0 60px #2244aa66",
		marginBottom: "4px",
		textAlign:   "center",
	});
	titleLine1.textContent = "STARGATE";
	root.appendChild(titleLine1);

	const titleLine2 = document.createElement("div");
	Object.assign(titleLine2.style, {
		color:        "#4488ff",
		fontSize:     "22px",
		letterSpacing: "14px",
		textShadow:   "0 0 18px #4488ff99",
		marginBottom: "72px",
		textAlign:    "center",
	});
	titleLine2.textContent = "UNIVERSE";
	root.appendChild(titleLine2);

	// Thin rule
	const rule = document.createElement("div");
	Object.assign(rule.style, {
		width:        "280px",
		height:       "1px",
		background:   "rgba(68, 136, 255, 0.25)",
		marginBottom: "40px",
	});
	root.appendChild(rule);

	// ── Button factory ────────────────────────────────────────────────────
	const makeButton = (label: string, onClick: () => void): HTMLButtonElement => {
		const btn = document.createElement("button");
		Object.assign(btn.style, {
			pointerEvents:  "auto",
			cursor:         "pointer",
			background:     "rgba(68, 136, 255, 0.07)",
			border:         "1px solid rgba(68, 136, 255, 0.35)",
			color:          "#88bbff",
			padding:        "14px 52px",
			fontSize:       "13px",
			fontFamily:     "'Courier New', monospace",
			letterSpacing:  "4px",
			minWidth:       "240px",
			marginBottom:   "16px",
			transition:     "background 0.18s ease, color 0.18s ease, border-color 0.18s ease",
			outline:        "none",
		});
		btn.textContent = label;

		btn.addEventListener("mouseenter", () => {
			btn.style.background   = "rgba(68, 136, 255, 0.18)";
			btn.style.color        = "#ffffff";
			btn.style.borderColor  = "rgba(68, 136, 255, 0.7)";
			void AudioManager.getInstance().play("hover");
		});
		btn.addEventListener("mouseleave", () => {
			btn.style.background   = "rgba(68, 136, 255, 0.07)";
			btn.style.color        = "#88bbff";
			btn.style.borderColor  = "rgba(68, 136, 255, 0.35)";
		});
		btn.addEventListener("click", () => {
			void AudioManager.getInstance().play("select");
			onClick();
		});
		return btn;
	};

	root.appendChild(makeButton("NEW GAME",  onNewGame));
	root.appendChild(makeButton("CONTINUE",  onContinue));

	// ── Version / hint ───────────────────────────────────────────────────
	const hint = document.createElement("div");
	Object.assign(hint.style, {
		marginTop:    "48px",
		color:        "rgba(68, 136, 255, 0.3)",
		fontSize:     "10px",
		letterSpacing: "2px",
		textAlign:    "center",
	});
	hint.textContent = "DESTINY  ·  ANCIENT VESSEL  ·  LOCATION UNKNOWN";
	root.appendChild(hint);

	document.body.appendChild(root);

	return {
		root,
		dispose: () => root.remove(),
	};
};

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene } = context;

	scene.background = new THREE.Color(0x000810);
	scene.fog        = new THREE.FogExp2(0x000810, 0.003);

	camera.fov  = 55;
	camera.near = 0.5;
	camera.far  = 600;
	camera.position.set(0, 0, 0);
	camera.lookAt(0, 0, -1);
	camera.updateProjectionMatrix();

	const stars = buildStarField(scene);

	let transitioning = false;

	const go = (sceneId: string) => (): void => {
		if (transitioning) return;
		transitioning = true;
		void gotoScene(sceneId);
	};

	const ui = createStartUI(go("opening-cinematic"), go("gate-room"));

	// Iconic SGU theme on the main menu. The catalog marks the theme song
	// as a non-looping one-shot (it's reserved for cinematic stingers),
	// but the menu is exactly where the full theme belongs — force loop+
	// softer volume via the play() override so it plays continuously while
	// the player sits at the NEW GAME / CONTINUE screen.
	void AudioManager.getInstance().play("sgu-theme-song", undefined, {
		loop: true,
		volume: 0.55,
	});

	let elapsed = 0;
	let disposed = false;

	return {
		update(delta: number): void {
			if (disposed) return;
			elapsed += delta;
			// Slow drift rotation of the star sphere
			stars.rotation.y += delta * 0.015;
			stars.rotation.x  = Math.sin(elapsed * 0.08) * 0.04;
		},

		dispose(): void {
			disposed = true;
			// Stop menu theme when we leave the start screen — the opening
			// cinematic uses a different bed so it doesn't duplicate.
			AudioManager.getInstance().stop("sgu-theme-song");
			ui.dispose();
			scene.remove(stars);
			stars.geometry.dispose();
			(stars.material as THREE.PointsMaterial).dispose();
		},
	};
}

// ─── Scene definition ─────────────────────────────────────────────────────────

export const startScreenScene = defineGameScene({
	id:     "start-screen",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((m) => m.default),
	}),
	title:  "Start Screen",
	player: false,
	mount,
});
