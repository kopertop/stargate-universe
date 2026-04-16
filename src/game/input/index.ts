/**
 * Input Manager — Keyboard/mouse/gamepad event aggregator.
 *
 * input-manager.ts owns the browser event listeners and exposes a clean
 * polling API: call inputManager.poll() every frame to snapshot current key/
 * button states, then read the snapshot from any system that needs it. No
 * game code should directly add event listeners — go through InputManager
 * to keep input sampling unified and deterministic.
 *
 * @see src/game/input/input-manager.ts
 */
export { InputManager } from "./input-manager";
