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
} as const;

const SGU_KEY_BINDINGS: Record<string, number> = {
	...DEFAULT_KEY_BINDINGS,
	KeyG:      SguAction.DialGate,
	F5:        SguAction.ManualSave,
	Backquote: SguAction.DebugToggle,
};

const SGU_GAMEPAD_BINDINGS: Partial<Record<number, number[]>> = {
	// A doubles as Interact so controller players can "press A" to talk to
	// NPCs / pick things up / dial — matches modern-console convention and
	// the interact-prompt helper ("[A] Talk to Rush" shows this button).
	// X keeps Interact too so the legacy binding still works if the player
	// is coming from an older build.
	...(DEFAULT_GAMEPAD_BINDINGS as Record<number, number[]>),
	[GamepadButton.A]: [Action.Jump, Action.MenuConfirm, Action.Interact],
	[GamepadButton.Y]: [SguAction.DialGate],
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
