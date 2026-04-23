/**
 * Scene Registry — Exposes the virtual scene registry for the game.
 *
 * Each scene folder under src/scenes/<scene-id>/ is discovered by @ggez/game-dev
 * at build time and registered in the virtual scene registry.
 *
 * @see src/scenes/main/index.ts
 * @see src/scenes/destiny-corridor/index.ts
 * @see src/scenes/destiny-gate-room/index.ts
 */
// Scene folders under src/scenes/<scene-id>/ are discovered by @ggez/game-dev.
// Each folder can contain index.ts for scene logic, scene.runtime.json, scene.meta.json, and assets/.
export { initialSceneId, scenes } from "virtual:web-hammer-scene-registry";
