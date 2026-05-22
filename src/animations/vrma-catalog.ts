/**
 * VRMA animation catalog — local clips under public/assets/animations/.
 *
 * Used by the character-viewer debug scene and any tooling that needs a
 * stable list of retargetable VRM Animation clips.
 */
import { resolveAssetUrl } from "../systems/asset-resolver";

export type VrmaCatalogEntry = {
	readonly id: string;
	readonly label: string;
	/** Asset-server-relative path before resolveAssetUrl. */
	readonly file: string;
	/** Optional grouping label for UI. */
	readonly group?: string;
};

const VRMA_BASE = "/assets/animations";

/** ACCAD Female1 wait — shared idle for all female crew VRMs. */
export const FEMALE_IDLE_ANIMATION_ID = "female-idle";

/** Male / default crew idle (tk256 Relax sample). */
export const CREW_IDLE_ANIMATION_ID = "eli-idle";

/** @deprecated Use CREW_IDLE_ANIMATION_ID */
export const MALE_IDLE_ANIMATION_ID = CREW_IDLE_ANIMATION_ID;

/** Player locomotion + gendered idles (see public/assets/animations/ATTRIBUTION.md). */
export const CORE_VRMA_CATALOG: readonly VrmaCatalogEntry[] = [
	{ id: FEMALE_IDLE_ANIMATION_ID, file: "female-idle.vrma", label: "Female Idle", group: "Core" },
	{ id: CREW_IDLE_ANIMATION_ID, file: "eli-idle.vrma", label: "Crew Idle", group: "Core" },
	{ id: "eli-walk", file: "eli-walk.vrma", label: "Eli Walk", group: "Core" },
	{ id: "eli-run", file: "eli-run.vrma", label: "Eli Run", group: "Core" },
	{ id: "eli-jump", file: "eli-jump.vrma", label: "Eli Jump", group: "Core" },
] as const;

/** sashii CC0 Josie retarget pack (BOOTH item 7861818). */
export const CC0_LOCOMOTION_CATALOG: readonly VrmaCatalogEntry[] = [
	{ id: "cc0-walk", file: "cc0-locomotion/CC0-walk.vrma", label: "CC0 Walk", group: "CC0 Locomotion" },
	{ id: "cc0-run", file: "cc0-locomotion/CC0-run.vrma", label: "CC0 Run", group: "CC0 Locomotion" },
	{ id: "cc0-slowrun", file: "cc0-locomotion/CC0-slowrun.vrma", label: "CC0 Slow Run", group: "CC0 Locomotion" },
] as const;

/** VRoid Project free motion pack (BOOTH item 5512385). */
export const VROID_MOTION_PACK_CATALOG: readonly VrmaCatalogEntry[] = [
	{ id: "vroid-01-show-body", file: "vroid-motion-pack/vrma/VRMA_01.vrma", label: "Show Full Body", group: "VRoid Motion Pack" },
	{ id: "vroid-02-greeting", file: "vroid-motion-pack/vrma/VRMA_02.vrma", label: "Greeting", group: "VRoid Motion Pack" },
	{ id: "vroid-03-peace-sign", file: "vroid-motion-pack/vrma/VRMA_03.vrma", label: "Peace Sign", group: "VRoid Motion Pack" },
	{ id: "vroid-04-shoot", file: "vroid-motion-pack/vrma/VRMA_04.vrma", label: "Shoot", group: "VRoid Motion Pack" },
	{ id: "vroid-05-spin", file: "vroid-motion-pack/vrma/VRMA_05.vrma", label: "Spin", group: "VRoid Motion Pack" },
	{ id: "vroid-06-model-pose", file: "vroid-motion-pack/vrma/VRMA_06.vrma", label: "Model Pose", group: "VRoid Motion Pack" },
	{ id: "vroid-07-squat", file: "vroid-motion-pack/vrma/VRMA_07.vrma", label: "Squat", group: "VRoid Motion Pack" },
] as const;

/** Emotion / emote samples from tk256ailab/vrm-viewer (native VRMA). */
export const TK256_EMOTE_CATALOG: readonly VrmaCatalogEntry[] = [
	{ id: "tk256-angry", file: "tk256-emotes/Angry.vrma", label: "Angry", group: "Emotes" },
	{ id: "tk256-blush", file: "tk256-emotes/Blush.vrma", label: "Blush", group: "Emotes" },
	{ id: "tk256-clapping", file: "tk256-emotes/Clapping.vrma", label: "Clapping", group: "Emotes" },
	{ id: "tk256-goodbye", file: "tk256-emotes/Goodbye.vrma", label: "Goodbye", group: "Emotes" },
	{ id: "tk256-jump", file: "tk256-emotes/Jump.vrma", label: "Jump (sample)", group: "Emotes" },
	{ id: "tk256-look-around", file: "tk256-emotes/LookAround.vrma", label: "Look Around", group: "Emotes" },
	{ id: "tk256-relax", file: "tk256-emotes/Relax.vrma", label: "Relax", group: "Emotes" },
	{ id: "tk256-sad", file: "tk256-emotes/Sad.vrma", label: "Sad", group: "Emotes" },
	{ id: "tk256-sleepy", file: "tk256-emotes/Sleepy.vrma", label: "Sleepy", group: "Emotes" },
	{ id: "tk256-surprised", file: "tk256-emotes/Surprised.vrma", label: "Surprised", group: "Emotes" },
	{ id: "tk256-thinking", file: "tk256-emotes/Thinking.vrma", label: "Thinking", group: "Emotes" },
] as const;

const ALL_VRMA_CATALOG = [
	...CORE_VRMA_CATALOG,
	...CC0_LOCOMOTION_CATALOG,
	...VROID_MOTION_PACK_CATALOG,
	...TK256_EMOTE_CATALOG,
] as const;

/** @deprecated Use getResolvedVrmaCatalog() — sync subset for tests. */
export const VRMA_CATALOG = ALL_VRMA_CATALOG;

export type ResolvedVrmaCatalogEntry = VrmaCatalogEntry & {
	readonly path: string;
};

const resolveEntries = (
	entries: readonly VrmaCatalogEntry[],
): readonly ResolvedVrmaCatalogEntry[] =>
	entries.map((entry) => ({
		...entry,
		path: resolveAssetUrl(`${VRMA_BASE}/${entry.file}`),
	}));

/** Full catalog of checked-in native VRMA clips. */
export const getResolvedVrmaCatalog = async (): Promise<readonly ResolvedVrmaCatalogEntry[]> =>
	resolveEntries(ALL_VRMA_CATALOG);

/** Default clip to auto-play in the character viewer by crew gender. */
export const getDefaultViewerAnimationId = (
	gender: "male" | "female" | undefined,
): string | undefined => {
	if (gender === "female") return FEMALE_IDLE_ANIMATION_ID;
	if (gender === "male") return CREW_IDLE_ANIMATION_ID;
	return undefined;
};

export const getVrmaCatalogEntry = async (
	id: string,
): Promise<ResolvedVrmaCatalogEntry | undefined> => {
	const catalog = await getResolvedVrmaCatalog();
	return catalog.find((entry) => entry.id === id);
};
