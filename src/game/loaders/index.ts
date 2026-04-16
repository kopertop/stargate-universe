/**
 * Loaders — Runtime source resolvers for game scenes and animation bundles.
 *
 * Two families, each with four source strategies:
 *   - Scenes:   defineGameScene() + [public|bundled|colocated|module]
 *   - Animations: defineGameAnimationBundle() + [public|bundled|colocated|module]
 *
 * All loaders return a RuntimeSceneSource / RuntimeAnimationSource that the
 * game shell consumes at load time. Scenes export their .runtime.json from ggez
 * World Editor; animations export their .bundle.json from the ggez animation editor.
 *
 * @see src/game/loaders/scene-sources.ts
 * @see src/game/loaders/animation-sources.ts
 */
export {
  defineGameScene,
  createPublicRuntimeSceneSource,
  createBundledRuntimeSceneSource,
  createColocatedRuntimeSceneSource
} from "./scene-sources";
export {
  defineGameAnimationBundle,
  createPublicRuntimeAnimationSource,
  createBundledRuntimeAnimationSource,
  createColocatedRuntimeAnimationSource
} from "./animation-sources";
