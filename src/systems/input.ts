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
	Action,
	DEFAULT_GAMEPAD_BINDINGS,
	DEFAULT_KEY_BINDINGS,
	GamepadButton,
	InputManager,
} from "@kopertop/vibe-game-engine";

/**
 * Project-specific action IDs. Engine reserves 0-99; 100+ is ours.
 * These are plain numbers so InputManager can key bindings on them.
 */
export const SguAction = {
	/** G — dial the stargate (or shut it down if already active). */
	DialGate: 100,
	/** F5 — manual save. */
	ManualSave: 101,
	/** Backquote — toggle debug overlay (caller handles double-tap debounce). */
	DebugToggle: 102,
	/** Dialogue options 1-4 — mapped to gamepad A/B/X/Y + keys 1/2/3/4. */
	Dialogue0: 110,
	Dialogue1: 111,
	Dialogue2: 112,
	Dialogue3: 113,
} as const;

const SGU_KEY_BINDINGS: Record<string, number> = {
	...DEFAULT_KEY_BINDINGS,
	KeyG:      SguAction.DialGate,
	F5:        SguAction.ManualSave,
	Backquote: SguAction.DebugToggle,
	// Number keys 1-4 double as dialogue option shortcuts. Keep the engine
	// default bindings for MenuConfirm/Back on Enter/Escape — dialogue
	// shortcuts are additional, not replacements.
	Digit1:    SguAction.Dialogue0,
	Digit2:    SguAction.Dialogue1,
	Digit3:    SguAction.Dialogue2,
	Digit4:    SguAction.Dialogue3,
};

const SGU_GAMEPAD_BINDINGS: Partial<Record<number, number[]>> = {
	// Start from engine defaults but explicitly remap A/B/X/Y so dialogue
	// works without fighting the engine's MenuConfirm/MenuBack/Interact/Jump
	// on those same buttons. Scenes read SguAction.Dialogue0..3 when a
	// dialogue panel is open; otherwise those buttons still fire their
	// engine-default actions via the entries below.
	...(DEFAULT_GAMEPAD_BINDINGS as Record<number, number[]>),
	[GamepadButton.A]: [Action.Jump, Action.MenuConfirm, SguAction.Dialogue0],
	[GamepadButton.B]: [Action.MenuBack,                  SguAction.Dialogue1],
	[GamepadButton.X]: [Action.Interact,                  SguAction.Dialogue2],
	[GamepadButton.Y]: [SguAction.DialGate,               SguAction.Dialogue3],
};

let instance: InputManager | undefined;
let keyboardUnbind: (() => void) | undefined;

/** Get (and lazily construct) the shared InputManager. */
export function getInput(): InputManager {
	if (!instance) {
		instance = new InputManager();
		instance.setKeyBindings(SGU_KEY_BINDINGS);
		instance.setGamepadBindings(SGU_GAMEPAD_BINDINGS);
		keyboardUnbind = instance.bind();
	}
	return instance;
}

/** Re-export Action so scene code doesn't need to also import from the engine. */
export { Action };

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
