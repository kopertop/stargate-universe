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
import { Action } from "@kopertop/vibe-game-engine";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { AudioManager } from "../../systems/audio";
import { getInput } from "../../systems/input";
import { hasStoredSaveGame } from "../../systems/save-manager";
import packageJson from "../../../package.json";
import startBackdropUrl from "./assets/destiny-restored-start.png?url";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

const BUILD_VERSION = packageJson.version;

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
	/** Move focus indicator by ±1 (wraps). Plays hover SFX. */
	moveFocus: (delta: number) => void;
	/** Activate the currently focused button. Plays select SFX. */
	confirm: () => void;
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
		display:         "grid",
		gridTemplateRows: "1fr auto",
		zIndex:          "100",
		fontFamily:      "'IBM Plex Sans', 'Segoe UI', sans-serif",
		pointerEvents:   "auto",
		userSelect:      "none",
		overflow:        "hidden",
		backgroundImage: `linear-gradient(90deg, rgba(0, 3, 8, 1) 0%, rgba(0, 4, 9, 1) 22%, rgba(0, 5, 10, 0.94) 34%, rgba(0, 6, 12, 0.28) 53%, rgba(0, 0, 0, 0.05) 100%), url(${startBackdropUrl})`,
		backgroundPosition: "center",
		backgroundSize:  "cover",
	});

	const vignette = document.createElement("div");
	Object.assign(vignette.style, {
		position: "absolute",
		inset: "0",
		background: "radial-gradient(circle at 78% 19%, rgba(180, 215, 255, 0.18), transparent 16%), linear-gradient(180deg, rgba(0, 0, 0, 0.2), rgba(0, 0, 0, 0.58))",
		pointerEvents: "none",
	});
	root.appendChild(vignette);

	const panel = document.createElement("div");
	Object.assign(panel.style, {
		position: "relative",
		zIndex: "1",
		alignSelf: "center",
		marginLeft: "clamp(28px, 5.25vw, 82px)",
		width: "min(410px, calc(100vw - 48px))",
	});
	root.appendChild(panel);

	// ── Title ───────────────────────────────────────────────────────────────
	const title = document.createElement("div");
	Object.assign(title.style, {
		marginBottom: "clamp(34px, 4vw, 48px)",
	});
	panel.appendChild(title);

	const titleLine1 = document.createElement("div");
	Object.assign(titleLine1.style, {
		color:       "rgba(255, 255, 255, 0.96)",
		fontSize:    "clamp(40px, 4.2vw, 64px)",
		fontWeight:  "300",
		lineHeight:  "0.92",
		letterSpacing: "0.24em",
		textShadow:  "0 0 28px rgba(115, 169, 222, 0.22)",
		textTransform: "uppercase",
	});
	titleLine1.textContent = "STARGATE";
	title.appendChild(titleLine1);

	const titleLine2 = document.createElement("div");
	Object.assign(titleLine2.style, {
		color:        "rgba(255, 255, 255, 0.96)",
		fontSize:     "clamp(40px, 4.2vw, 64px)",
		fontWeight:  "300",
		lineHeight:  "0.92",
		letterSpacing: "0.19em",
		textShadow:   "0 0 28px rgba(115, 169, 222, 0.22)",
		textTransform: "uppercase",
	});
	titleLine2.textContent = "UNIVERSE";
	title.appendChild(titleLine2);

	// Thin rule
	const rule = document.createElement("div");
	Object.assign(rule.style, {
		width:        "min(360px, 100%)",
		height:       "1px",
		background:   "rgba(255, 255, 255, 0.44)",
		marginTop: "22px",
		marginBottom: "14px",
	});
	title.appendChild(rule);

	const subtitle = document.createElement("div");
	Object.assign(subtitle.style, {
		color: "rgba(255, 255, 255, 0.84)",
		fontSize: "clamp(20px, 1.65vw, 25px)",
		fontWeight: "300",
		letterSpacing: "0.39em",
		textTransform: "uppercase",
	});
	subtitle.textContent = "DESTINY RESTORED";
	title.appendChild(subtitle);

	const menu = document.createElement("div");
	Object.assign(menu.style, {
		width: "min(390px, 100%)",
		borderTop: "1px solid rgba(120, 171, 215, 0.14)",
	});
	panel.appendChild(menu);

	// ── Button factory ────────────────────────────────────────────────────
	const makeButton = (label: string, onClick: () => void): HTMLButtonElement => {
		const btn = document.createElement("button");
		Object.assign(btn.style, {
			display: "block",
			width: "100%",
			height: "56px",
			textAlign: "left",
			cursor:         "pointer",
			background:     "rgba(1, 10, 17, 0.44)",
			border:         "0",
			borderBottom:   "1px solid rgba(120, 171, 215, 0.14)",
			color:          "rgba(255, 255, 255, 0.78)",
			padding:        "0 28px",
			fontSize:       "clamp(17px, 1.3vw, 21px)",
			fontFamily:     "inherit",
			fontWeight:     "300",
			letterSpacing:  "0.07em",
			textTransform:  "uppercase",
			transition:     "background 0.18s ease, color 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease",
			outline:        "none",
		});
		btn.textContent = label;

		btn.addEventListener("mouseenter", () => {
			if (btn.disabled) return;
			btn.style.background   = "linear-gradient(90deg, rgba(13, 46, 68, 0.82), rgba(3, 20, 34, 0.62))";
			btn.style.color        = "#ffffff";
			btn.style.borderColor  = "rgba(140, 210, 255, 0.58)";
			btn.style.boxShadow    = "inset 0 0 0 1px rgba(150, 216, 255, 0.72), 0 0 26px rgba(60, 145, 205, 0.18)";
			void AudioManager.getInstance().play("hover");
		});
		btn.addEventListener("mouseleave", () => {
			if (btn.disabled) return;
			btn.style.background   = "rgba(1, 10, 17, 0.44)";
			btn.style.color        = "rgba(255, 255, 255, 0.78)";
			btn.style.borderColor  = "rgba(120, 171, 215, 0.14)";
			btn.style.boxShadow    = "none";
		});
		btn.addEventListener("click", () => {
			if (btn.disabled) return;
			void AudioManager.getInstance().play("select");
			onClick();
		});
		return btn;
	};

	const canContinue = hasStoredSaveGame();
	const continueBtn = makeButton("CONTINUE GAME", onContinue);
	const newGameBtn = makeButton("NEW GAME", onNewGame);
	const settingsBtn = makeButton("SETTINGS", () => undefined);
	const exitBtn = makeButton("EXIT", () => undefined);
	continueBtn.disabled = !canContinue;
	menu.appendChild(continueBtn);
	menu.appendChild(newGameBtn);
	menu.appendChild(settingsBtn);
	menu.appendChild(exitBtn);

	// Focus state for controller/keyboard nav.
	const buttons: HTMLButtonElement[] = [continueBtn, newGameBtn, settingsBtn, exitBtn];
	const handlers: Array<() => void> = [onContinue, onNewGame, () => undefined, () => undefined];
	let focusIndex = canContinue ? 0 : 1;

	const paintFocus = (): void => {
		for (let i = 0; i < buttons.length; i++) {
			if (buttons[i].disabled) {
				buttons[i].style.background = "rgba(1, 10, 17, 0.24)";
				buttons[i].style.color = "rgba(255, 255, 255, 0.32)";
				buttons[i].style.borderColor = "rgba(120, 171, 215, 0.08)";
				buttons[i].style.boxShadow = "none";
				buttons[i].style.cursor = "not-allowed";
				continue;
			}

			buttons[i].style.cursor = "pointer";
			const focused = i === focusIndex;
			buttons[i].style.background = focused
				? "linear-gradient(90deg, rgba(13, 46, 68, 0.82), rgba(3, 20, 34, 0.62))"
				: "rgba(1, 10, 17, 0.44)";
			buttons[i].style.color = focused ? "#ffffff" : "rgba(255, 255, 255, 0.78)";
			buttons[i].style.borderColor = focused ? "rgba(140, 210, 255, 0.58)" : "rgba(120, 171, 215, 0.14)";
			buttons[i].style.boxShadow = focused
				? "inset 0 0 0 1px rgba(150, 216, 255, 0.72), 0 0 26px rgba(60, 145, 205, 0.18)"
				: "none";
		}
	};
	paintFocus();

	const moveFocus = (delta: number): void => {
		let next = focusIndex;
		for (let i = 0; i < buttons.length; i++) {
			next = (next + delta + buttons.length) % buttons.length;
			if (!buttons[next].disabled) break;
		}
		if (next === focusIndex) return;
		focusIndex = next;
		paintFocus();
		void AudioManager.getInstance().play("hover");
	};

	const confirm = (): void => {
		if (buttons[focusIndex].disabled) return;
		void AudioManager.getInstance().play("select");
		handlers[focusIndex]();
	};

	// Mouse hover also updates the focused index so keyboard/controller focus
	// matches whatever the player is pointing at.
	buttons.forEach((btn, i) => {
		btn.addEventListener("mouseenter", () => {
			if (btn.disabled) return;
			if (focusIndex !== i) {
				focusIndex = i;
				paintFocus();
			}
		});
	});

	// ── Version / hint ───────────────────────────────────────────────────
	const footer = document.createElement("div");
	Object.assign(footer.style, {
		position: "relative",
		zIndex: "1",
		marginLeft: "clamp(28px, 5.25vw, 82px)",
		marginBottom: "clamp(32px, 5vw, 78px)",
		color:        "rgba(125, 143, 157, 0.62)",
		fontSize:     "12px",
		letterSpacing: "0.06em",
		textTransform: "uppercase",
	});
	footer.textContent = `BUILD ${BUILD_VERSION}`;
	root.appendChild(footer);

	document.body.appendChild(root);

	return {
		root,
		moveFocus,
		confirm,
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

	// Looping exploration bed for the main menu at 0.3 vol — quiet enough
	// that the hover/click SFX and the player's decision-making breathe.
	void AudioManager.getInstance().play("sgu-soundtrack", undefined, { volume: 0.3 });

	// ── Controller + keyboard navigation ───────────────────────────────────
	// InputManager is polled once per frame in app.ts. We watch for the
	// just-pressed edges of D-pad / stick-Y and MenuConfirm to move focus
	// and activate. This is repeated each frame in update() below.
	const input = getInput();
	// Analog-stick nav needs a small debounce — snap-up/down on threshold.
	let stickFired = false;
	const STICK_THRESHOLD = 0.6;

	let elapsed = 0;
	let disposed = false;

	return {
		update(delta: number): void {
			if (disposed) return;
			elapsed += delta;
			// Slow drift rotation of the star sphere
			stars.rotation.y += delta * 0.015;
			stars.rotation.x  = Math.sin(elapsed * 0.08) * 0.04;

			if (transitioning) return;

			// D-pad / arrow-keys — edge-detected single step per press
			if (input.isActionJustPressed(Action.DPadUp) || input.isActionJustPressed(Action.MoveForward)) {
				ui.moveFocus(-1);
			}
			if (input.isActionJustPressed(Action.DPadDown) || input.isActionJustPressed(Action.MoveBackward)) {
				ui.moveFocus(1);
			}
			// Left stick up/down — debounced past the threshold.
			const stickY = input.gamepad.getAxis(/* LeftStickY */ 1);
			if (!stickFired && stickY < -STICK_THRESHOLD) { ui.moveFocus(-1); stickFired = true; }
			else if (!stickFired && stickY > STICK_THRESHOLD) { ui.moveFocus(1); stickFired = true; }
			else if (Math.abs(stickY) < STICK_THRESHOLD * 0.5) { stickFired = false; }

			// A/Enter confirm
			if (input.isActionJustPressed(Action.MenuConfirm)) {
				ui.confirm();
			}
		},

		dispose(): void {
			disposed = true;
			// Stop menu bed when we leave — the opening cinematic owns its
			// own music from there.
			AudioManager.getInstance().stop("sgu-soundtrack");
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
