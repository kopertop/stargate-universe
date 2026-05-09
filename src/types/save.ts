/**
 * Save / Load type definitions for Stargate Universe.
 *
 * All types are plain JSON-serializable. No classes, no functions.
 * Bump SAVE_VERSION when the schema changes and add a migration branch in `migrate()`.
 *
 * @see design/gdd/save-load-interface.md
 * @see src/systems/save-manager.ts
 */
import type { ShipStateSnapshot } from '../systems/ship-state';
import type { LootStateSnapshot } from '../systems/loot-state';
import type { SceneTransitionStateSnapshot } from '../systems/scene-transition-state';
import type { TimerSystemSnapshot } from '../systems/timer-system';
// Quest + dialogue save shapes are defined in the engine so every consumer
// shares one schema. We re-export them here for SGU's existing imports.
export type {
	QuestObjectiveSave,
	QuestStateSave,
	QuestSaveData,
	DialogueSaveData,
} from '@kopertop/vibe-game-engine';

// ─── Versioning ───────────────────────────────────────────────────────────────

export const SAVE_VERSION = 2;

export const AUTOSAVE_SLOT_ID = '__autosave__';

// ─── Slot index (lightweight — stored separately for fast listing) ─────────────

/** Metadata for a single save slot shown in the save/load UI. */
export type SaveSlot = {
	id: string;
	name: string;
	timestamp: number;
	playtime: number;
	sceneId: string;
	thumbnail?: string;
};

// ─── Sub-snapshots ────────────────────────────────────────────────────────────

/** Serialized output of resources.serialize() */
export type ResourceSnapshot = {
	version: number;
	resources: Record<string, number>;
};

import type { QuestSaveData, DialogueSaveData } from '@kopertop/vibe-game-engine';

// ─── Top-level save blob ──────────────────────────────────────────────────────

/** Complete game state snapshot persisted to localStorage. */
export type SaveData = {
	version: number;
	timestamp: number;
	playtime: number;
	currentSceneId: string;
	playerPosition: { x: number; y: number; z: number };
	shipState: ShipStateSnapshot;
	resources: ResourceSnapshot;
	questState: QuestSaveData;
	dialogueState: DialogueSaveData;
	unlockedScenes: string[];
	/** Whether the player is currently carrying lime from the desert planet. */
	limeCollected?: boolean;
	sceneTransitionState?: SceneTransitionStateSnapshot;
	timers?: TimerSystemSnapshot;
	lootState?: LootStateSnapshot;
};

// ─── Migration ────────────────────────────────────────────────────────────────

/**
 * Migrate a save blob from an older schema version to SAVE_VERSION.
 * Add a new conditional block here for each version bump.
 *
 * @param data        - Raw data as loaded from storage
 * @param fromVersion - The version number recorded in the blob
 * @returns           - Data conforming to the current schema
 */
export const migrate = (data: SaveData, fromVersion: number): SaveData => {
	if (fromVersion < 2) {
		data = {
			...data,
			version: 2,
			sceneTransitionState: {
				version: 1,
				limeCollected: data.limeCollected ?? false,
			},
			timers: {
				version: 1,
				timers: [],
			},
			lootState: {
				version: 1,
				containers: [],
			},
		};
	}
	if (fromVersion === SAVE_VERSION) return data;

	console.warn(`[SaveManager] Migrating save from v${fromVersion} → v${SAVE_VERSION}`);
	return data;
};
