/**
 * SGU → engine adapter for QuestManager.
 *
 * The engine's QuestManager handles the generic quest lifecycle. Game-
 * specific auto-advance wiring (ship:subsystem:repaired → repair objectives,
 * resource:collected → collect objectives) lives here so the engine stays
 * agnostic to SGU-only events.
 */
import {
	createQuestManager as createEngineQuestManager,
	type ManagerEvents,
	type QuestManager,
} from '@kopertop/vibe-game-engine';

import { emit, on } from './event-bus.js';

export type { QuestManager };

export const createQuestManager = (): QuestManager => {
	const manager = createEngineQuestManager({
		emit: emit as unknown as <K extends keyof ManagerEvents>(event: K, payload: ManagerEvents[K]) => void,
	});

	// Bridge SGU-specific events into generic objective advancement.
	const unsubRepaired = on('ship:subsystem:repaired', ({ subsystemId }) => {
		const log = manager.getQuestLog();
		for (const state of log.active.values()) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'repair' && obj.targetId === subsystemId) {
					manager.advanceObjective(state.definition.id, obj.id);
				}
			}
		}
	});
	// Snapshot to avoid iterator-invalidation when quest completion deletes from log.active mid-iteration.
	const unsubCollected = on('resource:collected', ({ type }) => {
		const log = manager.getQuestLog();
		const states = [...log.active.values()];
		for (const state of states) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'collect' && obj.targetId === type) {
					manager.advanceObjective(state.definition.id, obj.id);
				}
			}
		}
	});

	const baseDispose = manager.dispose;
	manager.dispose = () => {
		unsubRepaired();
		unsubCollected();
		baseDispose();
	};

	return manager;
};
