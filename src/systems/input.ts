/**
 * Shared input layer — wraps the vibe-game-engine InputManager as a
 * singleton that every scene and UI layer in Stargate Universe uses.
 *
 * Controller support is a first-class citizen here:
 *   - Gamepad left stick / D-pad → movement + menu navigation
 *   - Gamepad right stick → camera orbit
 *   - A/Cross → confirm / interact / advance dialogue
 *   - B/Circle → cancel / back / sprint (in-world)
 *   - Start → pause / skip cinematic
 *
 * The engine's InputManager already handles:
 *   - W3C "standard" gamepad mapping (4 axes, 17 buttons)
 *   - Dead-zone smoothing on both sticks (default 0.15)
 *   - Edge detection (just-pressed / just-released) via poll()
 *   - Keyboard + gamepad + touch axis merging with unit-length clamping
 *
 * Call `pollInput()` exactly once per frame (done in app.ts). Scenes read
 * the current state via `getInput()`.
 */
import {
	DEFAULT_GAMEPAD_BINDINGS,
	DEFAULT_KEY_BINDINGS,
	InputManager,
} from "@kopertop/vibe-game-engine";

let instance: InputManager | undefined;
let keyboardUnbind: (() => void) | undefined;

/** Get (and lazily construct) the shared InputManager. */
export function getInput(): InputManager {
	if (!instance) {
		instance = new InputManager();
		instance.setKeyBindings(DEFAULT_KEY_BINDINGS);
		instance.setGamepadBindings(DEFAULT_GAMEPAD_BINDINGS);
		keyboardUnbind = instance.bind();
	}
	return instance;
}

/** Poll gamepad + snapshot edge-detection state for this frame. */
export function pollInput(): void {
	getInput().poll();
}

/** Tear down the listeners — only called on full app dispose. */
export function disposeInput(): void {
	keyboardUnbind?.();
	keyboardUnbind = undefined;
	instance = undefined;
}
