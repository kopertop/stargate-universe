/**
 * Game Loop — Fixed-step simulation driver for the game shell.
 *
 * GameLoop steps physics at a hard-coded FIXED_STEP_SECONDS interval (Crashcat's
 * preferred cadence) while the browser paint runs at whatever it can manage.
 * Inputs and camera update every frame; physics steps only when the accumulator
 * crosses the fixed-step threshold. Keeps simulation deterministic even at variable
 * frame rates.
 *
 * @see src/game/loop/game-loop.ts
 */
export { GameLoop, FIXED_STEP_SECONDS } from "./game-loop";
export type { GameLoopCallbacks } from "./game-loop";
