/**
 * Save Manager — persists and restores all game state across browser sessions.
 *
 * Storage backend: localStorage (key-prefixed under "sgu:save:").
 * A lightweight slot index is kept at "sgu:save:index" for fast UI listing.
 * Full save blobs are stored per-slot at "sgu:save:slot:{id}".
 *
 * Emits save:completed / save:loaded / save:failed on the shared event bus.
 * Auto-saves on quest:completed and quest:objective-complete events.
 * Listens for F5 keydown to trigger a manual save.
 *
 * Usage:
 * ```ts
 * const saveManager = createSaveManager({
 *   shipState,
 *   questManager,
 *   dialogueManager,
 *   getContext: () => ({
 *     currentSceneId: activeSceneId,
 *     playerPosition: player?.getPosition() ?? { x: 0, y: 0, z: 0 },
 *     playtime: totalPlaytimeMs,
 *     unlockedScenes: [...unlockedScenes],
 *   }),
 *   gotoScene: loadScene,
 * });
 * ```
 *
 * @see design/gdd/save-load-interface.md
 * @see src/types/save.ts
 */
import { emit, on } from './event-bus.js';
import type { ShipState } from './ship-state.js';
import type { QuestManager } from './quest-manager.js';
import type { DialogueManager } from './dialogue-manager.js';
import type { DialogueSaveData } from '@kopertop/vibe-game-engine';
import { deserialize as deserializeResources, serialize as serializeResources } from './resources.js';
import { isLimeCollected, setLimeCollected } from './scene-transition-state.js';
import {
	AUTOSAVE_SLOT_ID,
	SAVE_VERSION,
	migrate,
	type ResourceSnapshot,
	type SaveData,
	type SaveSlot,
} from '../types/save.js';

// ─── Storage keys ─────────────────────────────────────────────────────────────

const STORAGE_PREFIX = 'sgu:save:';
const INDEX_KEY = `${STORAGE_PREFIX}index`;

const slotKey = (id: string): string => `${STORAGE_PREFIX}slot:${id}`;

// ─── Context provider ─────────────────────────────────────────────────────────

/** Snapshot of the runtime context captured at save time. */
export type SaveContext = {
	currentSceneId: string;
	playerPosition: { x: number; y: number; z: number };
	playtime: number;
	unlockedScenes: string[];
};

// ─── Public API ───────────────────────────────────────────────────────────────

export type SaveManager = {
	/** Snapshot current state and write to the given slot. Returns the saved blob. */
	save: (slotId: string, label: string) => SaveData;
	/** Restore state from a slot and transition to the saved scene. */
	load: (slotId: string) => Promise<void>;
	/** Return the list of slot metadata sorted by most-recent first. */
	listSlots: () => SaveSlot[];
	/** Remove a slot from storage and the index. */
	deleteSlot: (slotId: string) => void;
	/** Save to the reserved autosave slot. */
	autosave: () => void;
	/** Clean up event subscriptions and DOM listeners. */
	dispose: () => void;
};

// ─── Options ──────────────────────────────────────────────────────────────────

export type SaveManagerOptions = {
	shipState: ShipState;
	questManager: QuestManager;
	dialogueManager: DialogueManager;
	/** Called at save time to capture scene/player context from the host. */
	getContext: () => SaveContext;
	/** Transition the game to the given scene ID (async, matches app.loadScene). */
	gotoScene: (sceneId: string) => Promise<void>;
};

// ─── Factory ──────────────────────────────────────────────────────────────────

export const createSaveManager = (options: SaveManagerOptions): SaveManager => {
	const { shipState, questManager, dialogueManager, getContext, gotoScene } = options;
	const unsubscribers: Array<() => void> = [];

	// ─── Storage helpers ─────────────────────────────────────────────────────

	const readIndex = (): SaveSlot[] => {
		try {
			const raw = localStorage.getItem(INDEX_KEY);
			return raw ? (JSON.parse(raw) as SaveSlot[]) : [];
		} catch {
			return [];
		}
	};

	const writeIndex = (slots: SaveSlot[]): void => {
		try {
			localStorage.setItem(INDEX_KEY, JSON.stringify(slots));
		} catch {
			console.warn('[SaveManager] Failed to write slot index — localStorage may be full');
		}
	};

	const readSlotData = (id: string): SaveData | null => {
		try {
			const raw = localStorage.getItem(slotKey(id));
			return raw ? (JSON.parse(raw) as SaveData) : null;
		} catch {
			return null;
		}
	};

	const writeSlotData = (id: string, data: SaveData): void => {
		try {
			localStorage.setItem(slotKey(id), JSON.stringify(data));
		} catch {
			console.warn(`[SaveManager] Failed to write slot "${id}" — localStorage may be full`);
			throw new Error('localStorage write failed — storage quota exceeded?');
		}
	};

	// ─── Public methods ──────────────────────────────────────────────────────

	const listSlots = (): SaveSlot[] => readIndex();

	const save = (slotId: string, label: string): SaveData => {
		try {
			const ctx = getContext();
			const resourcesRaw = serializeResources();

			const data: SaveData = {
				version: SAVE_VERSION,
				timestamp: Date.now(),
				playtime: ctx.playtime,
				currentSceneId: ctx.currentSceneId,
				playerPosition: ctx.playerPosition,
				shipState: shipState.serialize(),
				resources: resourcesRaw as unknown as ResourceSnapshot,
				questState: questManager.serialize(),
				dialogueState: dialogueManager.serialize() as DialogueSaveData,
				unlockedScenes: [...ctx.unlockedScenes],
				limeCollected: isLimeCollected(),
			};

			writeSlotData(slotId, data);

			// Update the slot index
			const existing = readIndex().filter(s => s.id !== slotId);
			const slot: SaveSlot = {
				id: slotId,
				name: label,
				timestamp: data.timestamp,
				playtime: data.playtime,
				sceneId: data.currentSceneId,
			};
			existing.push(slot);
			// Most recent first
			existing.sort((a, b) => b.timestamp - a.timestamp);
			writeIndex(existing);

			emit('save:completed', { slotId });
			return data;
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			emit('save:failed', { slotId, error: message });
			throw error;
		}
	};

	const load = async (slotId: string): Promise<void> => {
		try {
			const raw = readSlotData(slotId);
			if (!raw) throw new Error(`Save slot "${slotId}" not found`);

			// Migrate if the schema version is older
			const data = raw.version !== SAVE_VERSION ? migrate(raw, raw.version) : raw;

			// Transition to the saved scene before restoring state so that
			// scene-registered quest definitions and other hooks are available.
			await gotoScene(data.currentSceneId);

			// Restore all subsystems
			shipState.deserialize(data.shipState);
			deserializeResources(data.resources as unknown as Record<string, unknown>);
			questManager.deserialize(data.questState);
			dialogueManager.deserialize(data.dialogueState);
			// Restore scene-transition flags (BUG-001: lime flag was lost on reload)
			setLimeCollected(data.limeCollected ?? false);

			emit('save:loaded', { slotId });
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			emit('save:failed', { slotId, error: message });
			throw error;
		}
	};

	const deleteSlot = (slotId: string): void => {
		try {
			localStorage.removeItem(slotKey(slotId));
			writeIndex(readIndex().filter(s => s.id !== slotId));
		} catch {
			console.warn(`[SaveManager] Failed to delete slot "${slotId}"`);
		}
	};

	const autosave = (): void => {
		try {
			save(AUTOSAVE_SLOT_ID, 'Autosave');
		} catch {
			// autosave failures are soft — log but don't rethrow
			console.warn('[SaveManager] Autosave failed');
		}
	};

	// ─── Auto-save triggers ──────────────────────────────────────────────────

	// Autosave whenever a quest objective completes or a full quest completes
	unsubscribers.push(on('quest:objective-complete', () => { autosave(); }));
	unsubscribers.push(on('quest:completed', () => { autosave(); }));

	// F5 manual save — uses the autosave slot for now (a save-slot picker UI
	// can intercept this event in the future and call save() with a chosen slot)
	const handleKeyDown = (e: KeyboardEvent): void => {
		if (e.key === 'F5') {
			e.preventDefault();
			autosave();
		}
	};
	window.addEventListener('keydown', handleKeyDown);

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	const dispose = (): void => {
		for (const unsub of unsubscribers) unsub();
		unsubscribers.length = 0;
		window.removeEventListener('keydown', handleKeyDown);
	};

	return { save, load, listSlots, deleteSlot, autosave, dispose };
};
