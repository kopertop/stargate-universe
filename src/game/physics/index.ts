/**
 * Physics Systems — Runtime physics session for the game.
 *
 * Wraps Crashcat rigid bodies (static + dynamic) and syncs them to Three.js
 * meshes each frame. Scene code imports from here — never reaches into the
 * crashcat internals directly.
 *
 * @see src/game/physics/session.ts
 */
export { createRuntimePhysicsSession } from "./session";
export type { RuntimePhysicsSession } from "./session";
