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

// Input — no-ops since this is a type stub; InputManager is provided by the real engine
export const DEFAULT_KEY_BINDINGS = {};
export const DEFAULT_GAMEPAD_BINDINGS = {};

export class InputManager {
	bind() { return () => {}; }
	setKeyBindings() {}
	setGamepadBindings() {}
	poll() {}
	isAction() { return false; }
	isActionJustPressed() { return false; }
	isActionJustReleased() { return false; }
	get gamepad() {
		return {
			get isConnected() { return false; },
			getAxis() { return 0; },
			getMovement() { return { x: 0, z: 0 }; },
			getLook() { return { x: 0, y: 0 }; },
		};
	}
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

// Input enums
export const Action = {
	Jump: 1, Interact: 2, Shoot: 3, Inventory: 4, Map: 5,
	Pause: 6, Menu: 7, Sprint: 8, MenuConfirm: 9, MenuBack: 10,
	DPadUp: 11, DPadDown: 12, MoveForward: 13, MoveBackward: 14,
};

export const GamepadButton = { A: 0, B: 1, X: 2, Y: 3 };
