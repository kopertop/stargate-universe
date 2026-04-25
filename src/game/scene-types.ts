/**
 * @file Re-export shim — moved to src/game/scene/types
 */
export type { GameSceneDefinition, GameSceneLifecycle, RuntimeSceneSource } from "./scene/types";
/** @deprecated Use GameSceneContext instead. */
export type { GameSceneContext as GameSceneModuleContext } from "./scene/types";
