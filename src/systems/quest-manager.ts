/**
 * Quest Manager — tracks active/completed quests, evaluates objectives,
 * and fires quest:* events via the event bus.
 *
 * Adapts the vibe-game-engine add-quest skill for SGU's @ggez/* stack.
 * Auto-wires to ship:subsystem:repaired and resource:collected events
 * so quest objectives advance without manual wiring in scene code.
 *
 * @see src/types/quest.ts
 */
import { emit, on } from './event-bus.js';
import type { QuestDefinition, QuestLog, QuestState } from '../types/quest.js';
import { createQuestLog, isQuestComplete } from '../types/quest.js';

// ─── Types ────────────────────────────────────────────────────────────────────

export type QuestManager = {
	registerDefinition: (definition: QuestDefinition) => void;
	startQuest: (questId: string) => QuestState | null;
	/** Manually advance an objective (use for custom/zone/escort types). */
	advanceObjective: (questId: string, objectiveId: string, delta?: number) => void;
	failQuest: (questId: string) => void;
	getQuestLog: () => QuestLog;
	isActive: (questId: string) => boolean;
	isCompleted: (questId: string) => boolean;
	dispose: () => void;
};

// ─── Factory ─────────────────────────────────────────────────────────────────

export const createQuestManager = (): QuestManager => {
	const definitions = new Map<string, QuestDefinition>();
	const questLog = createQuestLog();
	const unsubscribers: Array<() => void> = [];

	const registerDefinition = (definition: QuestDefinition): void => {
		definitions.set(definition.id, definition);
	};

	const startQuest = (questId: string): QuestState | null => {
		if (questLog.active.has(questId) || questLog.completed.has(questId)) return null;
		const definition = definitions.get(questId);
		if (!definition) {
			console.warn(`[quest] No definition for "${questId}"`);
			return null;
		}
		if (definition.prerequisiteId && !questLog.completed.has(definition.prerequisiteId)) {
			console.warn(`[quest] Prerequisite "${definition.prerequisiteId}" incomplete`);
			return null;
		}
		const state: QuestState = {
			definition,
			status: 'in-progress',
			objectives: definition.objectives.map(o => ({ ...o })),
			startedAt: Date.now(),
		};
		questLog.active.set(questId, state);
		emit('quest:started', { questId });
		console.log(`[quest] Started: ${definition.name}`);
		return state;
	};

	const advanceObjective = (questId: string, objectiveId: string, delta = 1): void => {
		const state = questLog.active.get(questId);
		if (!state || state.status !== 'in-progress') return;
		const obj = state.objectives.find(o => o.id === objectiveId);
		if (!obj || obj.completed) return;
		obj.current = Math.min(obj.current + delta, obj.required);
		if (obj.current >= obj.required) {
			obj.completed = true;
			emit('quest:objective-complete', { questId, objectiveId });
			console.log(`[quest] Objective complete: ${objectiveId}`);
			for (const other of state.objectives) {
				if (other.unlockedBy === objectiveId) other.visible = true;
			}
			if (isQuestComplete(state)) completeQuestInternal(questLog, state);
		}
	};

	const failQuest = (questId: string): void => {
		const state = questLog.active.get(questId);
		if (!state) return;
		state.status = 'failed';
		questLog.active.delete(questId);
		questLog.failed.set(questId, state);
		emit('quest:failed', { questId });
		console.log(`[quest] Failed: ${state.definition.name}`);
	};

	// Auto-advance repair objectives when ship subsystems are repaired
	unsubscribers.push(on('ship:subsystem:repaired', ({ subsystemId }) => {
		for (const state of questLog.active.values()) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'repair' && obj.targetId === subsystemId) {
					advanceObjective(state.definition.id, obj.id);
				}
			}
		}
	}));

	// Auto-advance collect objectives when resources are gathered
	unsubscribers.push(on('resource:collected', ({ type }) => {
		for (const state of questLog.active.values()) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'collect' && obj.targetId === type) {
					advanceObjective(state.definition.id, obj.id);
				}
			}
		}
	}));

	return {
		registerDefinition,
		startQuest,
		advanceObjective,
		failQuest,
		getQuestLog: () => questLog,
		isActive: (questId) => questLog.active.has(questId),
		isCompleted: (questId) => questLog.completed.has(questId),
		dispose: () => {
			for (const unsub of unsubscribers) unsub();
			unsubscribers.length = 0;
		},
	};
};

// ─── Internal helpers ─────────────────────────────────────────────────────────

const completeQuestInternal = (log: QuestLog, state: QuestState): void => {
	state.status = 'completed';
	state.completedAt = Date.now();
	log.active.delete(state.definition.id);
	log.completed.set(state.definition.id, state);

	const { reward } = state.definition;
	if (reward.xp)        console.log(`[quest] +${reward.xp} XP`);
	if (reward.currency)  console.log(`[quest] +${reward.currency} currency`);
	for (const item of reward.items ?? []) console.log(`[quest] Reward: ${item.quantity}x ${item.id}`);
	if (reward.abilityId) console.log(`[quest] Unlocked ability: ${reward.abilityId}`);

	emit('quest:completed', { questId: state.definition.id });
	console.log(`[quest] Completed: ${state.definition.name}`);
};
