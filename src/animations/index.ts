/**
 * Animation Registry — Exposes the virtual animation registry for the game.
 *
 * Animation bundle folders under src/animations/<bundle-id>/ are discovered
 * automatically by @ggez/game-dev and registered at build time.
 *
 * @see src/animations/<bundle-id>/index.ts
 */
// Animation bundle folders under src/animations/<bundle-id>/ are discovered automatically.
// Generated folders include index.ts, animation.bundle.json, graph.animation.json, animation.meta.json, and assets/.
export { animations } from "virtual:web-hammer-animation-registry";
