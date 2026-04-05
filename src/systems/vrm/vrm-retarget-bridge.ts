/**
 * VRM Retarget Bridge — connects VRM skeletons to ggez's animation pipeline.
 *
 * Creates an AnimatorInstance from a loaded VRM model and an ggez animation
 * bundle, bridging VRM bone names to ggez RigDefinition so Mixamo-sourced
 * clips play correctly on VRM characters.
 *
 * @see design/gdd/vrm-model-integration.md §Retargeting
 */
import type { AnimatorInstance } from "@ggez/anim-runtime";
import { createAnimatorInstance } from "@ggez/anim-runtime";
import { createRigFromSkeleton, createThreeAnimatorBridge } from "@ggez/anim-three";
import type { VRM } from "@pixiv/three-vrm";
import { Skeleton, SkinnedMesh } from "three";
import type { RuntimeAnimationBundle } from "../../game/loaders/animation-sources";

// ─── Types ──────────────────────────────────────────────────────────────────

export type VrmAnimatorBridge = {
	/** The ggez AnimatorInstance — set parameters (speed, isGrounded, etc.) on this. */
	readonly animator: AnimatorInstance;
	/** Call once per frame to evaluate the animation graph and apply pose to skeleton. */
	update(deltaTime: number): void;
	/** Clean up. */
	dispose(): void;
};

// ─── Bridge Factory ─────────────────────────────────────────────────────────

/**
 * Create an animation bridge for a VRM character.
 *
 * This extracts the VRM's skeleton, builds an ggez RigDefinition from it,
 * loads animation clips against that skeleton (handling name remapping),
 * and returns a bridge that evaluates the state machine each frame.
 *
 * @param vrm              Loaded VRM instance
 * @param animationBundle  ggez animation bundle (from animation editor)
 */
export async function createVrmAnimatorBridge(
	vrm: VRM,
	animationBundle: RuntimeAnimationBundle,
): Promise<VrmAnimatorBridge> {
	const skeleton = findPrimarySkeleton(vrm);

	if (!skeleton) {
		throw new Error("[VrmRetargetBridge] No skeleton found in VRM scene graph");
	}

	// Build rig from the VRM skeleton bone names
	const rig = createRigFromSkeleton(skeleton);

	// Load clips from the animation bundle, mapped to the VRM skeleton.
	// loadGraphClipAssets uses createClipAssetFromThreeClip internally,
	// which maps clip tracks to skeleton bone indices by name.
	const clips = await animationBundle.loadGraphClipAssets(skeleton);

	// Create the animator from the compiled graph
	const animator = createAnimatorInstance({
		rig,
		graph: animationBundle.artifact.graph,
		clips,
	});

	// Three.js bridge that applies computed pose to skeleton bones each frame
	const bridge = createThreeAnimatorBridge(animator, skeleton);

	return {
		animator,
		update(deltaTime: number) {
			animator.update(deltaTime);
			bridge.update(deltaTime);
		},
		dispose() {
			// AnimatorInstance and bridge don't hold GPU resources — no-op dispose
		},
	};
}

// ─── Internal ───────────────────────────────────────────────────────────────

/**
 * Find the primary skeleton in a VRM scene graph.
 * Searches for the first SkinnedMesh and returns its skeleton.
 */
function findPrimarySkeleton(vrm: VRM): Skeleton | undefined {
	let skeleton: Skeleton | undefined;

	vrm.scene.traverse((child) => {
		if (skeleton) return;

		if (child instanceof SkinnedMesh && child.skeleton) {
			skeleton = child.skeleton;
		}
	});

	return skeleton;
}
