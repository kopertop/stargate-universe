/**
 * Gate Room — Scene Manager Refs
 *
 * Exposes the live manager instances created during mount() so that the
 * future HUD layer (and any other scene-level consumers) can reach them
 * without prop-drilling through the lifecycle return value.
 *
 * Usage:
 *   import { sceneManagers } from './context';
 *   sceneManagers?.dialogue.getCurrentNode();
 */
import type { DialogueManager } from '../../systems/dialogue-manager';
import type { NpcManager } from '../../systems/npc-manager';
import type { QuestManager } from '../../systems/quest-manager';
import type { SaveManager } from '../../systems/save-manager';

export type GateRoomManagers = {
	dialogue: DialogueManager;
	npc: NpcManager;
	quest: QuestManager;
	save: SaveManager;
};

/** Null when the gate room scene is not mounted. */
export let sceneManagers: GateRoomManagers | null = null;

/** Called by mount() to publish the managers; called by dispose() with null. */
export const setSceneManagers = (managers: GateRoomManagers | null): void => {
	sceneManagers = managers;
};
