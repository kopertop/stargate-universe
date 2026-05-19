/**
 * @file Runtime stub for @kopertop/vibe-game-engine.
 * Provides no-op values so Rollup can resolve the imports at build time.
 * Type information lives in index.d.ts (sibling file).
 */

// PWA / service worker
export const DEFAULT_SW_SOURCE = "";

export function createInstallPrompt() {
	return {
		prompt: async () => {},
		userChoice: Promise.resolve({ outcome: "dismissed" }),
	};
}

export function registerServiceWorker() {
	return Promise.resolve();
}

// Manifest generation — returns empty string (gen-manifest.ts generates real manifest)
export function generateManifest() { return ""; }

// Input
export const Action = {
	Jump: 1, Interact: 2, Shoot: 3, Inventory: 4, Map: 5,
	Pause: 6, Menu: 7, Sprint: 8, MenuConfirm: 9, MenuBack: 10,
	DPadUp: 11, DPadDown: 12, MoveForward: 13, MoveBackward: 14,
};

export const GamepadButton = { A: 0, B: 1, X: 2, Y: 3 };

export const DEFAULT_KEY_BINDINGS = {
	Space: Action.Jump,
	KeyE: Action.Interact,
	KeyR: Action.Inventory,
	KeyM: Action.Map,
	Escape: Action.MenuBack,
	Enter: Action.MenuConfirm,
	ShiftLeft: Action.Sprint,
	ShiftRight: Action.Sprint,
	ArrowUp: Action.DPadUp,
	ArrowDown: Action.DPadDown,
	KeyW: Action.MoveForward,
	KeyS: Action.MoveBackward,
};

export const DEFAULT_GAMEPAD_BINDINGS = {
	[GamepadButton.A]: [Action.Jump, Action.MenuConfirm],
	[GamepadButton.B]: [Action.MenuBack],
	[GamepadButton.X]: [Action.Interact],
};

export class InputManager {
	#keyBindings = { ...DEFAULT_KEY_BINDINGS };
	#gamepadBindings = { ...DEFAULT_GAMEPAD_BINDINGS };
	#keys = new Set();
	#actions = new Set();
	#previousActions = new Set();
	#touchMovement = { x: 0, z: 0 };
	#bound = false;
	#onKeyDown = (event) => {
		if (isTextInputTarget(event.target)) return;
		this.#keys.add(event.code);
		if (event.code === "Space") event.preventDefault();
	};
	#onKeyUp = (event) => {
		this.#keys.delete(event.code);
	};
	#onBlur = () => {
		this.#keys.clear();
		this.#touchMovement = { x: 0, z: 0 };
	};

	bind() {
		if (this.#bound) return () => {};
		if (typeof window === "undefined") return () => {};
		this.#bound = true;
		window.addEventListener("keydown", this.#onKeyDown);
		window.addEventListener("keyup", this.#onKeyUp);
		window.addEventListener("blur", this.#onBlur);
		return () => {
			if (!this.#bound) return;
			this.#bound = false;
			window.removeEventListener("keydown", this.#onKeyDown);
			window.removeEventListener("keyup", this.#onKeyUp);
			window.removeEventListener("blur", this.#onBlur);
			this.#keys.clear();
			this.#actions.clear();
			this.#previousActions.clear();
		};
	}
	setKeyBindings(bindings) {
		this.#keyBindings = { ...bindings };
	}
	setGamepadBindings(bindings) {
		this.#gamepadBindings = { ...bindings };
	}
	setTouchMovement(x, z) {
		this.#touchMovement = {
			x: Math.max(-1, Math.min(1, x)),
			z: Math.max(-1, Math.min(1, z)),
		};
	}
	poll() {
		this.#previousActions = new Set(this.#actions);
		this.#actions.clear();

		for (const key of this.#keys) {
			const action = this.#keyBindings[key];
			if (action !== undefined) this.#actions.add(action);
		}

		for (const gamepad of getGamepads()) {
			if (!gamepad) continue;
			gamepad.buttons.forEach((button, index) => {
				if (!button.pressed) return;
				for (const action of this.#gamepadBindings[index] ?? []) {
					this.#actions.add(action);
				}
			});
		}
	}
	isAction(action) { return this.#actions.has(action); }
	isActionJustPressed(action) { return this.#actions.has(action) && !this.#previousActions.has(action); }
	isActionJustReleased(action) { return !this.#actions.has(action) && this.#previousActions.has(action); }
	get gamepad() {
		const first = getGamepads().find(Boolean);
		const axis = (index) => first?.axes[index] ?? 0;
		const touch = this.#touchMovement;
		return {
			get isConnected() { return first !== undefined || Math.abs(touch.x) > 0 || Math.abs(touch.z) > 0; },
			getAxis(index) { return axis(index); },
			getMovement() {
				return {
					x: Math.abs(touch.x) > 0 ? touch.x : axis(0),
					z: Math.abs(touch.z) > 0 ? touch.z : -axis(1),
				};
			},
			getLook() { return { x: axis(2), y: axis(3) }; },
		};
	}
}

function isTextInputTarget(target) {
	return (
		typeof HTMLElement !== "undefined" &&
		target instanceof HTMLElement &&
		(target.isContentEditable || target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT")
	);
}

function getGamepads() {
	if (typeof navigator === "undefined") return [];
	return Array.from(navigator.getGamepads?.() ?? []);
}

// Cross-cutting event bus
export function on() { return () => {}; }
export function emit() {}

// Dialogue + quest + NPC — functional dev runtime (vitest uses the same module).
export {
	createDialogueManager,
	createNpcManager,
	createQuestManager,
	createQuestLog,
	createDialogueState,
	getNode,
	getVisibleOptions,
	checkQuestComplete as isQuestComplete,
	getObjective,
} from "../../../tests/mocks/vibe-game-engine.ts";

export function selectOption() {}

// HUD / Dialogue panel
export function createHud() {
	return {
		mount() {},
		unmount() {},
		update() {},
		dispose() {},
	};
}

export function createDialoguePanel(bus, options = {}) {
	const root = document.createElement("div");
	root.id = "dialogue-panel";
	root.hidden = true;
	Object.assign(root.style, {
		position: "fixed",
		left: "50%",
		bottom: "18%",
		transform: "translateX(-50%)",
		width: "min(720px, 92vw)",
		padding: "16px 18px",
		borderRadius: "6px",
		border: "1px solid rgba(120, 171, 215, 0.35)",
		background: "rgba(1, 10, 17, 0.92)",
		color: "#e8f4ff",
		fontFamily: "'Courier New', monospace",
		zIndex: "1200",
		boxShadow: "0 12px 40px rgba(0, 0, 0, 0.55)",
	});

	const speakerEl = document.createElement("div");
	speakerEl.style.cssText = "font-size:11px;letter-spacing:0.12em;text-transform:uppercase;color:#8fd0ff;margin-bottom:8px;";
	const textEl = document.createElement("div");
	textEl.style.cssText = "font-size:15px;line-height:1.55;margin-bottom:12px;white-space:pre-wrap;";
	const optionsEl = document.createElement("div");
	optionsEl.style.cssText = "display:flex;flex-direction:column;gap:8px;";
	root.append(speakerEl, textEl, optionsEl);
	document.body.appendChild(root);

	const hints = options.optionHints ?? ["1", "2", "3", "4"];

	const renderNode = (data) => {
		root.hidden = false;
		speakerEl.textContent = data?.speaker ?? "";
		textEl.textContent = data?.text ?? "";
		optionsEl.replaceChildren();
		for (const [index, opt] of (data?.options ?? []).entries()) {
			const btn = document.createElement("button");
			btn.type = "button";
			const hint = hints[index] ? `[${hints[index]}] ` : "";
			btn.textContent = `${hint}${opt.label ?? opt.id}`;
			Object.assign(btn.style, {
				textAlign: "left",
				padding: "10px 12px",
				borderRadius: "4px",
				border: "1px solid rgba(120, 171, 215, 0.25)",
				background: "rgba(8, 28, 44, 0.88)",
				color: "#e8f4ff",
				cursor: "pointer",
				fontFamily: "inherit",
				fontSize: "13px",
			});
			btn.addEventListener("click", () => {
				bus.emit("player:dialogue:choice", { responseId: opt.id });
			});
			optionsEl.appendChild(btn);
		}
	};

	const hide = () => {
		root.hidden = true;
		optionsEl.replaceChildren();
	};

	bus.on("crew:dialogue:started", () => {
		root.hidden = false;
	});
	bus.on("crew:dialogue:node", renderNode);
	bus.on("crew:dialogue:ended", hide);

	return Object.assign(root, {
		dispose() {
			root.remove();
		},
	});
}

// Compass
export function createCompass() {
	return document.createElement("div");
}

// Neural locomotion
export const SEQ_LENGTH = 0;
export const SEQ_WINDOW = 0;
export const BONE_COUNT = 0;
export function encodeInput() { return new Float32Array(0); }

export class NeuralLocomotionController {
	get isLoaded() { return false; }
	async load() {}
	predict() { return { rootDelta: [0,0,0], rotations: new Float32Array(0) }; }
	sampleAt() { return { rootDelta: [0,0,0], rotations: new Float32Array(0) }; }
}
