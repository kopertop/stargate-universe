/**
 * Shared helper for interact prompt labels.
 *
 * Returns the correct key hint based on the currently active input device:
 *   - Gamepad connected → "A"
 *   - Otherwise → "E"
 *
 * Scenes typically format their own prompt strings like `[E] Pick up this`.
 * Use {@link formatInteractPrompt} to get `[A] Pick up this` when a gamepad
 * is connected. The check is cheap (reads the already-polled InputManager),
 * so it's safe to call every frame — scenes that rebuild their prompt text
 * in `update(delta)` will see the label flip the moment the gamepad
 * connects or disconnects.
 */
import { getInput } from "../systems/input";

export type InteractVerb = "press" | "hold";

/** Return "A" (gamepad) or "E" (keyboard). */
export function getInteractKeyLabel(): string {
	return getInput().gamepad.isConnected ? "A" : "E";
}

/**
 * Build a bracketed prompt like `[E] ...` or `[Hold A] ...`.
 * `verb` defaults to "press". Rest is the action, e.g. `"Pick up the lime"`.
 */
export function formatInteractPrompt(action: string, verb: InteractVerb = "press"): string {
	const key = getInteractKeyLabel();
	return verb === "hold" ? `[Hold ${key}] ${action}` : `[${key}] ${action}`;
}
