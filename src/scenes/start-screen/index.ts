/**
 * Start Screen — SGU title + menu overlay.
 *
 * Renders a subtle Three.js star field behind a full-screen DOM overlay.
 * No player controller, no physics.  Navigation:
 *   NEW GAME  → opening-cinematic
 *   CONTINUE  → gate-room  (save-game resume)
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

// ─── Star-field ───────────────────────────────────────────────────────────────

const STAR_COUNT = 2400;

const createStarField = (scene: THREE.Scene): { dispose: () => void } => {
	const positions = new Float32Array(STAR_COUNT * 3);
	for (let i = 0; i < STAR_COUNT; i++) {
		// Distribute on a large sphere
		const theta = Math.random() * Math.PI * 2;
		const phi   = Math.acos(2 * Math.random() - 1);
		const r     = 80 + Math.random() * 60;
		positions[i * 3]     = r * Math.sin(phi) * Math.cos(theta);
		positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
		positions[i * 3 + 2] = r * Math.cos(phi);
	}

	const geo = new THREE.BufferGeometry();
	geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));

	const mat  = new THREE.PointsMaterial({ color: 0xffffff, size: 0.45, sizeAttenuation: true });
	const stars = new THREE.Points(geo, mat);
	scene.add(stars);

	return {
		dispose: () => {
			scene.remove(stars);
			geo.dispose();
			mat.dispose();
		},
	};
};

// ─── DOM overlay ─────────────────────────────────────────────────────────────

interface StartScreenUI {
	root: HTMLDivElement;
	dispose: () => void;
}

const createUI = (
	onNewGame:  () => void,
	onContinue: () => void,
): StartScreenUI => {
	const root = document.createElement("div");
	Object.assign(root.style, {
		position:       "fixed",
		inset:          "0",
		display:        "flex",
		flexDirection:  "column",
		alignItems:     "center",
		justifyContent: "center",
		zIndex:         "200",
		pointerEvents:  "none",
		userSelect:     "none",
	});

	// Title
	const title = document.createElement("div");
	Object.assign(title.style, {
		color:          "#ffffff",
		fontFamily:     "'Courier New', monospace",
		fontSize:       "clamp(28px, 5vw, 60px)",
		fontWeight:     "300",
		letterSpacing:  "0.35em",
		textTransform:  "uppercase",
		textShadow:     "0 0 40px rgba(68,136,255,0.5), 0 0 80px rgba(68,136,255,0.2)",
		marginBottom:   "8px",
	});
	title.textContent = "STARGATE UNIVERSE";
	root.appendChild(title);

	// Subtitle line
	const sub = document.createElement("div");
	Object.assign(sub.style, {
		color:         "rgba(68,136,255,0.55)",
		fontFamily:    "'Courier New', monospace",
		fontSize:      "clamp(10px, 1.5vw, 14px)",
		letterSpacing: "0.5em",
		textTransform: "uppercase",
		marginBottom:  "64px",
	});
	sub.textContent = "DESTINY  ·  UNCHARTED GALAXIES";
	root.appendChild(sub);

	// Button container
	const buttons = document.createElement("div");
	Object.assign(buttons.style, {
		display:       "flex",
		flexDirection: "column",
		gap:           "16px",
		pointerEvents: "auto",
	});

	const makeButton = (label: string, onClick: () => void, primary: boolean): HTMLButtonElement => {
		const btn = document.createElement("button");
		btn.textContent = label;
		Object.assign(btn.style, {
			background:    primary ? "rgba(68,136,255,0.12)" : "transparent",
			border:        `1px solid ${primary ? "rgba(68,136,255,0.6)" : "rgba(255,255,255,0.2)"}`,
			color:         primary ? "#ffffff" : "rgba(255,255,255,0.5)",
			fontFamily:    "'Courier New', monospace",
			fontSize:      "clamp(12px, 1.8vw, 16px)",
			letterSpacing: "0.3em",
			textTransform: "uppercase",
			padding:       "14px 48px",
			cursor:        "pointer",
			transition:    "all 0.2s ease",
			outline:       "none",
			minWidth:      "280px",
		});
		btn.addEventListener("mouseenter", () => {
			btn.style.background    = "rgba(68,136,255,0.22)";
			btn.style.borderColor   = "rgba(68,136,255,0.9)";
			btn.style.color         = "#ffffff";
			btn.style.textShadow    = "0 0 12px rgba(68,136,255,0.6)";
		});
		btn.addEventListener("mouseleave", () => {
			btn.style.background    = primary ? "rgba(68,136,255,0.12)" : "transparent";
			btn.style.borderColor   = primary ? "rgba(68,136,255,0.6)" : "rgba(255,255,255,0.2)";
			btn.style.color         = primary ? "#ffffff" : "rgba(255,255,255,0.5)";
			btn.style.textShadow    = "";
		});
		btn.addEventListener("click", onClick);
		return btn;
	};

	buttons.appendChild(makeButton("New Game",  onNewGame,  true));
	buttons.appendChild(makeButton("Continue",  onContinue, false));

	root.appendChild(buttons);
	document.body.appendChild(root);

	return {
		root,
		dispose: () => root.remove(),
	};
};

// ─── Mount ────────────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene } = context;

	scene.background = new THREE.Color(0x000005);

	// Camera: static, looking along +Z into star field
	camera.fov  = 60;
	camera.near = 0.1;
	camera.far  = 300;
	camera.updateProjectionMatrix();
	camera.position.set(0, 0, 0);
	camera.lookAt(0, 0, 1);

	const starField = createStarField(scene);

	let disposed    = false;
	let transitioning = false;

	const navigate = async (sceneId: string): Promise<void> => {
		if (disposed || transitioning) return;
		transitioning = true;
		// Fade to black before transition
		ui.root.style.transition = "opacity 0.5s ease";
		ui.root.style.opacity    = "0";
		await new Promise<void>((r) => setTimeout(r, 500));
		await gotoScene(sceneId);
	};

	const ui = createUI(
		() => void navigate("opening-cinematic"),
		() => void navigate("gate-room"),
	);

	// Slow camera drift through the star field
	let driftAngle = 0;

	return {
		update(delta: number): void {
			if (disposed) return;
			driftAngle += delta * 0.018;
			camera.position.set(
				Math.sin(driftAngle) * 0.6,
				Math.sin(driftAngle * 0.7) * 0.3,
				Math.cos(driftAngle) * 0.6,
			);
			camera.lookAt(
				Math.sin(driftAngle + 0.4) * 0.2,
				0,
				Math.cos(driftAngle + 0.4) * 0.2,
			);
		},

		dispose(): void {
			disposed = true;
			starField.dispose();
			ui.dispose();
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
