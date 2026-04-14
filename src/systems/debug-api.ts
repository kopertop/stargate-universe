/**
 * Debug + test automation API.
 *
 * Exposes a scriptable game-control surface on window.__sgu so that
 * Playwright/MCP/manual browser-console sessions can navigate menus,
 * move the character, trigger interactions, and inspect game state
 * without needing synthetic mouse/keyboard events.
 *
 * Also renders a small on-screen dev overlay (toggled with Backquote)
 * with buttons for the most common actions so a human testing by hand
 * can click through the game flow.
 */
import type * as THREE from "three";
import { emit } from "./event-bus";
import { AudioManager } from "./audio";
import { getInput, Action, SguAction } from "./input";

// ─── API shape ─────────────────────────────────────────────────────────────

export interface SguDebugApi {
	/** Current scene id + coarse player position. */
	readonly state: () => {
		scene: string | undefined;
		player: { x: number; y: number; z: number } | undefined;
	};
	/** Navigate to a scene (calls the app's loadScene via the global hook). */
	readonly gotoScene: (sceneId: string) => Promise<void>;
	/** Inject a named action press for one frame (keyboard/gamepad-style). */
	readonly press: (action: "interact" | "dial-gate" | "confirm" | "back" | "pause" | "jump" | "sprint" | "debug-toggle") => void;
	/** Release a held action. */
	readonly release: (action: "interact" | "sprint") => void;
	/** Drive the player with analog move + look axes for the NEXT frame. */
	readonly drive: (moveX: number, moveZ: number, lookX?: number, lookY?: number) => void;
	/** Stop driving the player (zero all external axes). */
	readonly stop: () => void;
	/** Trigger a player:interact event targeting a named entity (NPC / crate / gate). */
	readonly interact: (targetId: string, action?: string) => void;
	/** Start a specific dialogue tree (bypasses proximity). */
	readonly startDialogue: (dialogueId: string) => void;
	/** Pick a dialogue response by option id. */
	readonly chooseDialogue: (responseId: string) => void;
	/** AudioContext/listener state — useful when debugging silent audio. */
	readonly audioState: () => { contextState: AudioContextState };
	/**
	 * Capture a screenshot on the next rendered frame.
	 * Returns a data URL (image/png) of the canvas contents.
	 * Optionally set camera position/target before capture.
	 */
	readonly screenshot: (opts?: {
		cameraPos?: { x: number; y: number; z: number };
		cameraTarget?: { x: number; y: number; z: number };
		waitFrames?: number;
	}) => Promise<string>;
	/** Set camera position and look-at target directly. */
	readonly setCamera: (pos: { x: number; y: number; z: number }, target: { x: number; y: number; z: number }) => void;
}

// ─── Implementation ─────────────────────────────────────────────────────────

interface HostHooks {
	getCurrentSceneId: () => string | undefined;
	getPlayerPosition: () => { x: number; y: number; z: number } | undefined;
	setExternalMove: ((forward: number, strafe: number) => void) | undefined;
	gotoScene: (sceneId: string) => Promise<void>;
	getCanvas: () => HTMLCanvasElement | undefined;
	getCamera: () => THREE.PerspectiveCamera | undefined;
	getRenderer: () => { render: (scene: THREE.Scene, camera: THREE.Camera) => void } | undefined;
	getScene: () => THREE.Scene | undefined;
}

const actionMap = {
	"interact":      Action.Interact,
	"dial-gate":     SguAction.DialGate,
	"confirm":       Action.MenuConfirm,
	"back":          Action.MenuBack,
	"pause":         Action.Pause,
	"jump":          Action.Jump,
	"sprint":        Action.Sprint,
	"debug-toggle":  SguAction.DebugToggle,
} as const;

/**
 * Install the debug API on window. Call once from app.ts after the
 * game app is constructed.
 */
export function installDebugApi(hooks: HostHooks): void {
	// Pulse an action by synthesising the keyboard path the InputManager
	// already watches: dispatch a KeyboardEvent matching the default binding.
	const pulseKey = (code: string): void => {
		window.dispatchEvent(new KeyboardEvent("keydown", { code }));
		// Release on next microtask so InputManager's next poll sees a pressed-
		// then-released edge and isActionJustPressed returns true exactly once.
		queueMicrotask(() => {
			window.dispatchEvent(new KeyboardEvent("keyup", { code }));
		});
	};

	// Inverse mapping: action → a default key code. Picks the most common binding.
	const actionToKey: Record<keyof typeof actionMap, string> = {
		"interact":     "KeyE",
		"dial-gate":    "KeyG",
		"confirm":      "Enter",
		"back":         "Escape",
		"pause":        "Escape",
		"jump":         "Space",
		"sprint":       "ShiftLeft",
		"debug-toggle": "Backquote",
	};

	const api: SguDebugApi = {
		state: () => ({
			scene: hooks.getCurrentSceneId(),
			player: hooks.getPlayerPosition(),
		}),
		gotoScene: (sceneId) => hooks.gotoScene(sceneId),
		press: (action) => pulseKey(actionToKey[action]),
		release: (action) => {
			window.dispatchEvent(new KeyboardEvent("keyup", { code: actionToKey[action] }));
		},
		drive: (moveX, moveZ, _lookX, _lookY) => {
			hooks.setExternalMove?.(moveZ, moveX);
		},
		stop: () => {
			hooks.setExternalMove?.(0, 0);
		},
		interact: (targetId, action = "talk") => {
			emit("player:interact", { targetId, action });
		},
		startDialogue: (dialogueId) => {
			// The dialogue tree id matches the NPC id in SGU's registry.
			emit("player:interact", { targetId: dialogueId, action: "talk" });
		},
		chooseDialogue: (responseId) => {
			emit("player:dialogue:choice", { responseId });
		},
		audioState: () => ({
			contextState: AudioManager.getInstance().getContextState(),
		}),
		screenshot: (opts) => {
			return new Promise<string>((resolve, reject) => {
				const cam = hooks.getCamera();
				const rndr = hooks.getRenderer();
				const scn = hooks.getScene();
				const canvas = hooks.getCanvas();

				if (!cam || !rndr || !scn || !canvas) {
					reject(new Error("Game not ready — no renderer/camera/scene"));
					return;
				}

				if (opts?.cameraPos) {
					cam.position.set(opts.cameraPos.x, opts.cameraPos.y, opts.cameraPos.z);
				}
				if (opts?.cameraTarget) {
					cam.lookAt(opts.cameraTarget.x, opts.cameraTarget.y, opts.cameraTarget.z);
				}

				const framesToWait = opts?.waitFrames ?? 3;
				let waited = 0;

				const captureOnFrame = () => {
					waited++;
					if (waited < framesToWait) {
						requestAnimationFrame(captureOnFrame);
						return;
					}

					rndr.render(scn, cam);
					try {
						const dataUrl = canvas.toDataURL("image/png");
						resolve(dataUrl);
					} catch (err) {
						reject(err);
					}
				};

				requestAnimationFrame(captureOnFrame);
			});
		},
		setCamera: (pos, target) => {
			const cam = hooks.getCamera();
			if (!cam) return;
			cam.position.set(pos.x, pos.y, pos.z);
			cam.lookAt(target.x, target.y, target.z);
		},
	};

	(window as unknown as { __sgu?: SguDebugApi }).__sgu = api;

	// Silence unused-import warning from getInput — we don't need it here
	// but keeping the import clarifies that the action map aligns with the
	// binding in src/systems/input.ts.
	void getInput;
}

// ─── On-screen overlay (Backquote toggles) ─────────────────────────────────

let overlay: HTMLDivElement | undefined;

export function toggleDebugOverlay(hooks: HostHooks): void {
	if (overlay) {
		overlay.remove();
		overlay = undefined;
		return;
	}

	const el = document.createElement("div");
	el.id = "sgu-debug-overlay";
	Object.assign(el.style, {
		position:      "fixed",
		top:           "12px",
		right:         "12px",
		zIndex:        "5000",
		background:    "rgba(10, 14, 26, 0.88)",
		color:         "#88bbff",
		fontFamily:    "'Courier New', monospace",
		fontSize:      "11px",
		padding:       "10px 12px",
		border:        "1px solid rgba(68, 136, 255, 0.45)",
		maxWidth:      "220px",
		pointerEvents: "auto",
	} as Partial<CSSStyleDeclaration>);

	const title = document.createElement("div");
	title.textContent = "DEV — press ` to close";
	Object.assign(title.style, { fontWeight: "bold", marginBottom: "6px", color: "#d4b96a" });
	el.appendChild(title);

	const status = document.createElement("div");
	status.style.marginBottom = "8px";
	status.style.whiteSpace = "pre";
	el.appendChild(status);

	const row = (buttons: Array<[string, () => void]>): void => {
		const r = document.createElement("div");
		r.style.display = "flex";
		r.style.gap = "4px";
		r.style.marginBottom = "4px";
		r.style.flexWrap = "wrap";
		for (const [label, fn] of buttons) {
			const b = document.createElement("button");
			b.textContent = label;
			Object.assign(b.style, {
				flex:           "1 1 auto",
				background:     "rgba(68, 136, 255, 0.14)",
				border:         "1px solid rgba(68, 136, 255, 0.35)",
				color:          "#88bbff",
				padding:        "4px 6px",
				fontFamily:     "inherit",
				fontSize:       "10px",
				cursor:         "pointer",
			} as Partial<CSSStyleDeclaration>);
			b.addEventListener("click", (e) => {
				e.stopPropagation();
				fn();
			});
			r.appendChild(b);
		}
		el.appendChild(r);
	};

	// Scene jump
	row([
		["▶ Start",         () => void hooks.gotoScene("start-screen")],
		["▶ Gate Room",     () => void hooks.gotoScene("gate-room")],
	]);
	row([
		["▶ Desert Planet", () => void hooks.gotoScene("desert-planet")],
		["▶ Scrubber Room", () => void hooks.gotoScene("scrubber-room")],
	]);
	row([
		["▶ Cinematic",     () => {
			sessionStorage.setItem("sgu-new-game", "1");
			void hooks.gotoScene("gate-room");
		}],
	]);

	// Inputs
	row([
		["↑ Forward",   () => hooks.setExternalMove?.(-1, 0)],
		["↓ Back",      () => hooks.setExternalMove?.(1, 0)],
		["⏹ Stop",      () => hooks.setExternalMove?.(0, 0)],
	]);
	row([
		["← Left",      () => hooks.setExternalMove?.(0, -1)],
		["→ Right",     () => hooks.setExternalMove?.(0, 1)],
	]);
	row([
		["E Interact",  () => {
			window.dispatchEvent(new KeyboardEvent("keydown", { code: "KeyE" }));
			queueMicrotask(() => window.dispatchEvent(new KeyboardEvent("keyup", { code: "KeyE" })));
		}],
		["G Dial",      () => {
			window.dispatchEvent(new KeyboardEvent("keydown", { code: "KeyG" }));
			queueMicrotask(() => window.dispatchEvent(new KeyboardEvent("keyup", { code: "KeyG" })));
		}],
	]);
	row([
		["Talk Rush", () => emit("player:interact", { targetId: "dr-rush",       action: "talk" })],
		["Talk Scott", () => emit("player:interact", { targetId: "scott-opening", action: "talk" })],
	]);

	document.body.appendChild(el);
	overlay = el;

	// Live status updater
	const tick = () => {
		if (!overlay) return;
		const s = hooks.getCurrentSceneId() ?? "?";
		const p = hooks.getPlayerPosition();
		const pos = p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : "—";
		status.textContent = `scene: ${s}\nplayer: ${pos}`;
		requestAnimationFrame(tick);
	};
	requestAnimationFrame(tick);
}
