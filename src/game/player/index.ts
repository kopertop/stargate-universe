/**
 * Player Controllers — All player character implementations.
 *
 * Three flavors cover the full character spectrum:
 *   - StarterPlayerController — capsule-physics stub for prototyping
 *   - VrmPlayerController     — VRM character with live bone retargeting
 *   - GlbPlayerController      — glTF/GLB character with skeletal animation
 *
 * All three share the same update contract and camera interface.
 * Swap at runtime via player.setController().
 *
 * @see src/game/player/controller.ts
 */
export { StarterPlayerController } from "./controller";
export { VrmPlayerController, type VrmPlayerControllerOptions } from "./vrm-player-controller";
export { GlbPlayerController, type GlbPlayerControllerOptions } from "./glb-player-controller";
