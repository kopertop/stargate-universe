/**
 * Cross-scene transition state — minimal module-level singleton
 * for passing ephemeral gameplay flags between scene mounts in a
 * single browser session (no page reloads between scenes).
 *
 * Deliberately kept small — not a general-purpose store. Each flag
 * should document its lifecycle (set-by / cleared-by).
 */

// ─── Lime-collected flag ──────────────────────────────────────────────────────
// Set by:     desert-planet scene when all 3 deposits are collected & player
//             steps back through the gate.
// Cleared by: scrubber-room scene after the repair is applied.

let _limeCollected = false;

/** Mark that the player collected all calcium deposits and is carrying them. */
export const setLimeCollected = (value: boolean): void => {
	_limeCollected = value;
};

/** True when the player is currently carrying lime from the desert planet. */
export const isLimeCollected = (): boolean => _limeCollected;
