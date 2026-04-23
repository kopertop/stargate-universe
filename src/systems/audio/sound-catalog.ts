/**
 * Sound Catalog — registry of all game sounds with metadata.
 *
 * Sound files are stored on R2 and resolved via the asset resolver.
 * This catalog maps sound IDs to their R2 paths and playback settings.
 */

export type SoundCategory = "sfx" | "ambient" | "music" | "ui" | "voice";

export interface SoundEntry {
	/** R2 asset path (resolved via resolveAssetUrl). */
	readonly path: string;
	/** Default volume (0-1). */
	readonly volume: number;
	/** Sound category. */
	readonly category: SoundCategory;
	/** Whether this sound should loop. */
	readonly loop: boolean;
	/** Whether this is positional (3D) or global (2D). */
	readonly positional: boolean;
}

/**
 * All registered game sounds. Add new entries here when integrating sounds.
 *
 * Sound IDs use kebab-case matching the filename on R2.
 */
export const SOUND_CATALOG = {
	"repair-sparks": {
		path: "/audio/sfx/repair-sparks.mp3",
		volume: 0.6,
		category: "sfx",
		loop: true,
		positional: true,
	},
} as const satisfies Record<string, SoundEntry>;

export type SoundId = keyof typeof SOUND_CATALOG;
