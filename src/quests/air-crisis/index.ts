/**
 * Quest: Air Crisis — Registration & Integration Helpers
 *
 * Provides the register function to wire this quest into a QuestManager.
 *
 * The quest auto-starts when the gate room loads — the CO₂ alarm is already
 * going off. Rush's dialogue advances the speak-to-rush objective.
 * Collect objectives (find-lime) are auto-wired via resource:collected events.
 * Repair objectives (fix-scrubbers) are auto-wired via ship:subsystem:repaired.
 *
 * Usage in scene mount:
 *   registerAirCrisis(questManager);
 *   questManager.startQuest(QUEST_ID);   // auto-start — no dialogue gate
 */
import type { QuestManager } from '../../systems/quest-manager.js';
import { airCrisisDefinition } from './definition.js';

export { airCrisisDefinition };

export const QUEST_ID = 'air-crisis' as const;

/** Register this quest's definition with a QuestManager instance. */
export const registerAirCrisis = (questManager: QuestManager): void => {
	questManager.registerDefinition(airCrisisDefinition);
};
