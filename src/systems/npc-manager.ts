/**
 * SGU → engine adapter for NpcManager.
 * @see dialogue-manager.ts for the same pattern.
 */
import {
	createNpcManager as createEngineNpcManager,
	type DialogueManager,
	type ManagerEvents,
	type NpcManager,
} from '@kopertop/vibe-game-engine';

import { on } from './event-bus.js';

export type { NpcManager };

export const createNpcManager = (dialogueManager: DialogueManager): NpcManager =>
	createEngineNpcManager({
		dialogueManager,
		on: on as unknown as <K extends keyof ManagerEvents>(
			event: K,
			handler: (payload: ManagerEvents[K]) => void,
		) => () => void,
	});
