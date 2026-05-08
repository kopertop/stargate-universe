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

// Dialogue helpers
export function getNode() { return undefined; }
export function getVisibleOptions(state) { return state.options ?? []; }
export function selectOption() {}
export function createDialogueState() { return {}; }

// Dialogue manager
export function createDialogueManager() {
	return {
		registerTree() {},
		startDialogue() { return null; },
		isActive() { return false; },
		advance() {},
		endDialogue() {},
		getAffinity() { return 0; },
		hasMetNpc() { return false; },
		serialize() { return {}; },
		deserialize() {},
		dispose() {},
	};
}

// HUD / Dialogue panel
export function createHud() {
	return {
		mount() {},
		unmount() {},
		update() {},
		dispose() {},
	};
}

export function createDialoguePanel() {
	const el = document.createElement("div");
	return {
		...el,
		dispose() {},
	};
}

// Compass
export function createCompass() {
	return document.createElement("div");
}

// Quest system
export function createQuestLog() {
	return { active: new Map(), completed: new Map() };
}
export function createQuestManager() {
	return {
		getQuestLog() { return createQuestLog(); },
		startQuest() { return { status: "active" }; },
		advanceObjective() {},
		completeQuest() {},
		failQuest() {},
		registerDefinition() {},
		getQuestStatus() { return "active"; },
		isActive() { return false; },
		isCompleted() { return false; },
		serialize() { return {}; },
		deserialize() {},
		dispose() {},
	};
}
export function isQuestComplete() { return false; }
export function getObjective() { return undefined; }

// NPC system
export function createNpcManager() {
	return {
		registerNpc() { return {}; },
		getAllNpcs() { return []; },
		get() { return undefined; },
		getNpc() { return undefined; },
		update() {},
		dispose() {},
	};
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
