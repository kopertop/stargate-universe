/**
 * Standalone crew idle playback for NPC VRMs loaded via character-loader.
 *
 * Uses gender-default idle from the VRMA catalog plus optional variant cycling
 * (male: Look Around ↔ Thinking; female: occasional Model Pose).
 */
import type { CharacterLoadResult } from "../../characters/character-loader";
import { LoopRepeat } from "three";
import {
	getDefaultViewerAnimationId,
	getVrmaCatalogEntry,
} from "../../animations/vrma-catalog";
import { loadAnimation } from "./vrm-animation-retarget";
import { VrmIdleVariantCycle } from "./vrm-idle-variant-cycle";

export type CrewIdleAnimationOptions = {
	readonly gender?: "male" | "female";
	/** When false, only the base idle loop plays (no look-around / emote beats). */
	readonly enableVariants?: boolean;
};

export type CrewIdleAnimationHandle = {
	readonly update: (delta: number) => void;
	readonly dispose: () => void;
};

export async function startCrewIdleAnimation(
	character: CharacterLoadResult,
	options: CrewIdleAnimationOptions = {},
): Promise<CrewIdleAnimationHandle | undefined> {
	const { vrm, mixer } = character;
	if (!vrm) return undefined;

	const idleId = getDefaultViewerAnimationId(options.gender);
	if (!idleId) return undefined;

	const entry = await getVrmaCatalogEntry(idleId);
	if (!entry) return undefined;

	try {
		const clip = await loadAnimation(entry.path, vrm, entry.label);
		mixer.stopAllAction();
		const baseAction = mixer.clipAction(clip);
		baseAction.reset();
		baseAction.setLoop(LoopRepeat, Infinity);
		baseAction.setEffectiveWeight(1);
		baseAction.play();

		let variantCycle: VrmIdleVariantCycle | undefined;
		if (options.enableVariants !== false && options.gender) {
			variantCycle = new VrmIdleVariantCycle({
				gender: options.gender,
				vrm,
				baseIdleAction: baseAction,
				getBaseIdleWeight: () => 1,
			});
			await variantCycle.load();
			if (variantCycle.hasVariants) {
				variantCycle.enterIdle();
			} else {
				variantCycle.dispose();
				variantCycle = undefined;
			}
		}

		return {
			update(delta: number) {
				variantCycle?.update(delta);
			},
			dispose() {
				variantCycle?.dispose();
				mixer.stopAllAction();
			},
		};
	} catch (err) {
		console.warn(
			`[CrewIdleAnim] Failed to start idle "${idleId}":`,
			err,
		);
		return undefined;
	}
}
