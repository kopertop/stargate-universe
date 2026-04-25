/**
 * Quest: Destiny Power Crisis — Registration & Integration Helpers
 *
 * Provides the register function to wire this quest into a QuestManager.
 * The QuestManager auto-wires ship:subsystem:repaired events to repair
 * objectives, so no extra scene-level wiring is needed for conduit repairs.
 *
 * Usage in scene mount:
 *   registerDestinyPowerCrisis(questManager);
 *   // In Rush's dialogue onSelect, call:
 *   //   questManager.startQuest(QUEST_ID);
 */
import type { QuestManager } from '../../systems/quest-manager.js';
import { destinyPowerCrisisDefinition } from './definition.js';

export { destinyPowerCrisisDefinition };

export const QUEST_ID = 'destiny-power-crisis' as const;

/** Subsystem ID → objective ID mapping for this quest. */
export const CONDUIT_OBJECTIVE_MAP: Readonly<Record<string, string>> = {
	'conduit-delta-7':    'repair-delta-7',
	'conduit-delta-9':    'repair-delta-9',
	'conduit-cargo-hold': 'repair-cargo',
};

/** Register this quest's definition with a QuestManager instance. */
export const registerDestinyPowerCrisis = (questManager: QuestManager): void => {
	questManager.registerDefinition(destinyPowerCrisisDefinition);
};
