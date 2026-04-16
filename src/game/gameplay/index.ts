/**
 * Gameplay Systems — Default game systems and host creation.
 *
 * Provides createDefaultGameplaySystems() for the common case (physics, input,
 * camera) and mergeGameplaySystems() for extending with custom game logic.
 * createStarterGameplayHost() bundles everything into a ready-to-use runtime.
 *
 * @see src/game/gameplay/systems.ts
 * @see src/game/gameplay/host.ts
 */
export { createDefaultGameplaySystems, mergeGameplaySystems } from "./systems";
export { createStarterGameplayHost } from "./host";
