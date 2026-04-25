/**
 * SGU → engine adapter for DialogueManager.
 *
 * The implementation now lives in @kopertop/vibe-game-engine. This module
 * creates the engine factory with SGU's typed event bus (mitt-backed) so
 * the rest of the game code keeps importing from this path and doesn't
 * need to know about the engine move.
 */
import {
	createDialogueManager as createEngineDialogueManager,
	type DialogueManager,
	type ManagerEvents,
} from '@kopertop/vibe-game-engine';

import { emit } from './event-bus.js';

export type { DialogueManager };

export const createDialogueManager = (): DialogueManager =>
	createEngineDialogueManager({
		// SGU's GameEventMap is a superset of ManagerEvents — safe to pass
		// the bound emit through. Cast narrows the generic to the
		// manager-required keys so TypeScript is happy.
		emit: emit as unknown as <K extends keyof ManagerEvents>(event: K, payload: ManagerEvents[K]) => void,
	});
