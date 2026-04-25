/**
 * Mock implementation of @kopertop/vibe-game-engine for vitest.
 *
 * The real engine lives in a sibling workspace that isn't linked in the
 * test environment. This mock provides the factory functions that the
 * SGU adapter modules (dialogue-manager, npc-manager, quest-manager)
 * call at runtime — allowing tests to run without a full engine checkout.
 */

import type {
	DialogueTree,
	DialogueNode,
	DialogueOption,
	DialogueState,
	DialogueManager,
	DialogueManagerSnapshot,
	NpcDefinition,
	NpcInstance,
	NpcInstanceState,
	NpcManager,
	QuestDefinition,
	QuestManager,
	QuestLog,
	QuestState,
} from '../../src/types/vibe-game-engine/index';

// ── Bus helpers ─────────────────────────────────────────────────────────────

type EmitFn = <K extends string>(event: K, data?: unknown) => void;
type Bus = { emit: EmitFn };

function toBus(raw: unknown): Bus {
	if (typeof raw === 'function') return { emit: raw as EmitFn };
	return raw as Bus;
}

// ── Dialogue helpers ─────────────────────────────────────────────────────────

export function getNode(tree: DialogueTree, id: string): DialogueNode | undefined {
	return tree.nodes.find((n) => n.id === id);
}

export function getVisibleOptions(state: DialogueState): DialogueOption[] {
	return (state.options ?? []).filter((opt) => !opt.condition || opt.condition(state));
}

export function createDialogueState(tree: DialogueTree): DialogueState {
	const startNode = getNode(tree, tree.startNodeId)!;
	const initState: DialogueState = {
		current: startNode,
		options: startNode.options ?? [],
		history: [],
		flags: {},
		affinityDelta: 0,
		acceptedQuests: [],
	};
	initState.options = getVisibleOptions(initState);
	initState.history.push(startNode.id);
	return initState;
}

// ── DialogueManager mock ─────────────────────────────────────────────────────

interface DialogueSession {
	tree: DialogueTree;
	state: DialogueState;
	active: boolean;
}

function makeDialogueManager(opts?: { emit?: unknown }): DialogueManager {
	const raw = opts?.emit as unknown;
	const bus = toBus(raw);
	const trees = new Map<string, DialogueTree>();
	const sessions = new Map<string, DialogueSession>();
	const metNpcs = new Set<string>();
	// Track affinity at session start to compute per-session delta.
	const affinitySessionStart: Record<string, number> = {};
	const affinity: Record<string, number> = {};

	function resolveOptionId(session: DialogueSession, optionId: string): DialogueOption | undefined {
		return session.state.options.find((o) => o.id === optionId);
	}

	function checkAutoEnd(session: DialogueSession) {
		const opts = getVisibleOptions(session.state);
		// Only mark inactive — do NOT emit ended here. The advance() caller
		// is responsible for emitting ended so it can emit affinity delta first.
		if (opts.length === 0 && session.active) {
			session.active = false;
		}
	}

	return {
		registerTree(tree: DialogueTree) {
			trees.set(tree.id, tree);
		},

		startDialogue(id: string): DialogueNode | null {
			const tree = trees.get(id);
			// Snapshot affinity at session start so we can emit per-session delta later.
			affinitySessionStart[id] = affinity[id] ?? 0;
			if (!tree) return null;
			const state = createDialogueState(tree);
			sessions.set(id, { tree, state, active: true });
			metNpcs.add(id);
			bus.emit('crew:dialogue:started', { speakerId: id, dialogueId: id });
			bus.emit('crew:dialogue:node', { nodeId: state.current.id, options: getVisibleOptions(state) });
			checkAutoEnd(sessions.get(id)!);
			return state.current;
		},

		isActive(): boolean {
			for (const s of sessions.values()) {
				if (s.active) return true;
			}
			return false;
		},

		advance(optionId: string) {
			for (const session of sessions.values()) {
				if (!session.active) continue;
				const opt = resolveOptionId(session, optionId);
				if (!opt) continue;
				bus.emit('crew:choice:made', { responseId: optionId });
				if (opt.onSelect) opt.onSelect(session.state);

				// Accumulate affinity delta into running total. After each choice, if the
				// session is ending (no next node OR auto-end after advancing), emit the
				// per-session delta. Otherwise the delta stays in state for next advance.
				const delta = session.state.affinityDelta;
				if (delta !== 0) {
					affinity[session.tree.id] = (affinity[session.tree.id] ?? 0) + delta;
					session.state.affinityDelta = 0;
				}

				if (opt.nextNodeId) {
					// Non-terminal: advance, check auto-end, emit ended only if session ended.
					const next = getNode(session.tree, opt.nextNodeId);
					if (next) {
						session.state.current = next;
						session.state.options = next.options ?? [];
						session.state.history.push(next.id);
						bus.emit('crew:dialogue:node', {
							nodeId: next.id,
							options: getVisibleOptions(session.state),
						});
						const wasActive = session.active;
						checkAutoEnd(session);
						if (wasActive && !session.active) {
							// Session auto-ended after advancing to a node with no options.
							// Emit ended, then relationship delta.
							bus.emit('crew:dialogue:ended', { speakerId: session.tree.id });
							if (delta !== 0) {
								bus.emit('crew:relationship:changed', {
									characterId: session.tree.id,
									affinity: delta,
								});
							}
							affinitySessionStart[session.tree.id] = affinity[session.tree.id] ?? 0;
						}
					}
				} else {
					// Terminal node: explicit end.
					session.active = false;
					session.state.options = [];
					bus.emit('crew:dialogue:ended', { speakerId: session.tree.id });
					if (delta !== 0) {
						bus.emit('crew:relationship:changed', {
							characterId: session.tree.id,
							affinity: delta,
						});
					}
					affinitySessionStart[session.tree.id] = affinity[session.tree.id] ?? 0;
				}
				return;
			}
		},

		endDialogue() {
			for (const session of sessions.values()) {
				if (session.active) {
					session.active = false;
					session.state.options = [];
					bus.emit('crew:dialogue:ended', { speakerId: session.tree.id });
				}
			}
		},

		getAffinity(characterId: string): number {
			return affinity[characterId] ?? 0;
		},

		hasMetNpc(npcId: string): boolean {
			return metNpcs.has(npcId);
		},

		serialize(): DialogueManagerSnapshot {
			const seen = new Set<string>();
			const allAccepted: string[] = [];
			for (const s of sessions.values()) {
				for (const q of s.state.acceptedQuests) {
					if (!seen.has(q)) { seen.add(q); allAccepted.push(q); }
				}
			}
			return {
				acceptedQuests: allAccepted,
				metNpcs: [...metNpcs],
				affinity,
				dialogues: Object.fromEntries(
				[...sessions.entries()].map(([id, s]) => [id, {
					id,
					started: s.active || s.state.history.length > 0,
				}]),
			),
			};
		},

		deserialize(data: unknown) {
			const d = data as DialogueManagerSnapshot;
			metNpcs.clear();
			d.metNpcs.forEach((n) => metNpcs.add(n));
			Object.assign(affinity, d.affinity ?? {});
		},

		dispose() {
			sessions.clear();
		},
	};
}

// ── NpcManager mock ─────────────────────────────────────────────────────────

function makeNpcManager(opts: { dialogueManager: DialogueManager; on: unknown }): NpcManager {
	const npcs = new Map<string, NpcInstance>();
	const dialogueManager = opts.dialogueManager;

	const onFn = opts.on as (event: string, handler: (data: unknown) => void) => () => void;

	const unsubStart = onFn('crew:dialogue:started', (data) => {
		const { speakerId } = data as { speakerId: string };
		const npc = npcs.get(speakerId);
		if (npc) {
			npc.inDialogue = true;
			npc.state = 'interact';
		}
	});
	const unsubEnd = onFn('crew:dialogue:ended', (data) => {
		const { speakerId } = data as { speakerId: string };
		const npc = npcs.get(speakerId);
		if (npc) {
			npc.inDialogue = false;
			npc.state = 'idle';
		}
	});
	const unsubInteract = onFn('player:interact', (data) => {
		const { targetId, action } = data as { targetId: string; action: string };
		if (action !== 'talk') return;
		const npc = npcs.get(targetId);
		if (!npc) return;
		dialogueManager.startDialogue(npc.defId);
	});
	const unsubChoice = onFn('player:dialogue:choice', (data) => {
		const { responseId } = data as { responseId: string };
		dialogueManager.advance(responseId);
	});

	return {
		registerNpc(def: NpcDefinition): NpcInstance {
			const instance: NpcInstance = {
				id: def.id,
				defId: def.id,
				state: (def.behavior.startingState ?? 'idle') as NpcInstanceState,
				definition: def,
				inDialogue: false,
			};
			npcs.set(def.id, instance);
			return instance;
		},

		getAllNpcs(): NpcInstance[] {
			return [...npcs.values()];
		},

		get(id: string): NpcInstance | undefined {
			return npcs.get(id);
		},

		getNpc(id: string): NpcInstance | undefined {
			return npcs.get(id);
		},

		update(_delta: number) {
			// no-op in mock
		},

		dispose() {
			unsubStart();
			unsubEnd();
			unsubInteract();
			unsubChoice();
			npcs.clear();
		},
	};
}

// ── QuestManager mock ────────────────────────────────────────────────────────

function makeQuestLog(): QuestLog {
	return {
		active: new Map<string, QuestState>(),
		completed: new Map<string, QuestState>(),
	};
}

function isQuestComplete(def: QuestDefinition, state: QuestState): boolean {
	return def.objectives.every((o) => {
		const s = state.objectives.find((x) => x.id === o.id);
		return s?.completed ?? o.completed;
	});
}

function makeQuestManager(opts?: { emit?: unknown }): QuestManager {
	const raw = opts?.emit as unknown;
	const bus = toBus(raw);
	const definitions = new Map<string, QuestDefinition>();
	const log = makeQuestLog();

	let unsubRepaired: (() => void) | null = null;
	let unsubCollected: (() => void) | null = null;

	function advanceFromRepair(subsystemId: string) {
		// Snapshot active quests before iteration in case quest completion
		// deletes the quest mid-iteration.
		const states = [...log.active.values()];
		for (const state of states) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'repair' && obj.targetId === subsystemId) {
					obj.current = (obj.current ?? 0) + 1;
					if (obj.required && obj.current >= obj.required) obj.completed = true;
					bus.emit('quest:objective-complete', { questId: state.definition.id, objectiveId: obj.id });
					if (isQuestComplete(state.definition, state)) {
						log.active.delete(state.definition.id);
						log.completed.set(state.definition.id, state);
						bus.emit('quest:completed', { questId: state.definition.id });
					}
				}
			}
		}
	}

	function advanceFromCollect(type: string) {
		// Snapshot to avoid iterator-invalidation when quest completion deletes from log.active mid-iteration.
		const states = [...log.active.values()];
		for (const state of states) {
			for (const obj of state.objectives) {
				if (!obj.completed && obj.visible && obj.type === 'collect' && obj.targetId === type) {
					obj.current = (obj.current ?? 0) + 1;
					if (obj.required && obj.current >= obj.required) {
						obj.completed = true;
						bus.emit('quest:objective-complete', { questId: state.definition.id, objectiveId: obj.id });
						if (isQuestComplete(state.definition, state)) {
							log.active.delete(state.definition.id);
							log.completed.set(state.definition.id, state);
							bus.emit('quest:completed', { questId: state.definition.id });
						}
					}
				}
			}
		}
	}

	return {
		getQuestLog(): QuestLog {
			return log;
		},

		startQuest(id: string) {
			const def = definitions.get(id);
			if (!def) return { status: 'unknown' } as unknown as { status: string };
			const state: QuestState = {
				definition: def,
				objectives: def.objectives.map((o) => ({ ...o })),
			};
			log.active.set(id, state);
			bus.emit('quest:started', { questId: id });
			return { status: 'in-progress' };
		},

		advanceObjective(questId: string, objectiveId: string, current?: number) {
			const state = log.active.get(questId);
			if (!state) return;
			const obj = state.objectives.find((o) => o.id === objectiveId);
			if (!obj) return;
			if (current !== undefined) {
				obj.current = current;
				obj.progress = obj.required ? current / obj.required : 0;
				const wasCompleted = obj.completed;
				if (obj.required && current >= obj.required) obj.completed = true;
				if (!wasCompleted && obj.completed) bus.emit('quest:objective-complete', { questId, objectiveId });
			} else {
				obj.current = (obj.current ?? 0) + 1;
				obj.progress = obj.required ? obj.current / obj.required : 0;
				const wasCompleted = obj.completed;
				if (obj.required && obj.current >= obj.required) obj.completed = true;
				if (!wasCompleted && obj.completed) bus.emit('quest:objective-complete', { questId, objectiveId });
			}
			if (isQuestComplete(state.definition, state)) {
				log.active.delete(questId);
				log.completed.set(questId, state);
				bus.emit('quest:completed', { questId });
			}
		},

		completeQuest(id: string) {
			const state = log.active.get(id);
			if (state) {
				log.active.delete(id);
				log.completed.set(id, state);
				bus.emit('quest:completed', { questId: id });
			}
		},

		failQuest(id: string) {
			log.active.delete(id);
		},

		registerDefinition(def: QuestDefinition) {
			definitions.set(def.id, def);
		},

		getQuestStatus(id: string) {
			if (log.completed.has(id)) return 'complete';
			if (log.active.has(id)) return 'active';
			return 'active';
		},

		isActive(id: string): boolean {
			return log.active.has(id);
		},

		isCompleted(id: string): boolean {
			return log.completed.has(id);
		},

		serialize() {
			return {
				id: 'quest-save',
				stage: 0,
				objectives: [...log.active.values()].flatMap((s) =>
					s.objectives.map((o) => ({ id: o.id, completed: o.completed, current: o.current })),
				),
			};
		},

		deserialize(data: unknown) {
			// Rehydrate quest state from serialized save data.
			const d = data as { objectives: Array<{ id: string; completed: boolean; current?: number }> };
			if (!d.objectives) return;
			for (const obj of d.objectives) {
				// Find which quest owns this objective
				for (const [qid, def] of definitions.entries()) {
					const has = def.objectives.some((o) => o.id === obj.id);
					if (has) {
						// Start the quest if not already active or completed
						if (!log.active.has(qid) && !log.completed.has(qid)) {
							this.startQuest(qid);
						}
						// Restore objective state
						const state = log.active.get(qid);
						if (state) {
							const o = state.objectives.find((x) => x.id === obj.id);
							if (o) {
						// Restore current progress if serialized (partial completion)
							if (obj.current !== undefined && obj.current < (o.required ?? 1)) {
								o.current = obj.current;
								o.progress = o.required ? obj.current / o.required : 0;
								o.completed = obj.completed;
							} else {
								// For fully-completed objectives, directly set completed=true without calling
								// advanceObjective (which fires quest:completed and moves quest to log.completed).
								if (obj.completed && o.required) {
									o.current = o.required;
									o.completed = true;
									o.progress = 1;
								}
							}
							}
						}
						break;
					}
				}
			}
		},

		dispose() {
			if (unsubRepaired) { unsubRepaired(); unsubRepaired = null; }
			if (unsubCollected) { unsubCollected(); unsubCollected = null; }
			// NOTE: do NOT clear definitions, log.active, or log.completed — dispose()
			// only unsubscribes bridge listeners. Quest state must remain inspectable
			// after dispose for tests that verify post-dispose quest state.
		},
	};
}

// ── Exports matching the vibe-game-engine index.d.ts ────────────────────────

export { makeDialogueManager as createDialogueManager };
export { makeNpcManager as createNpcManager };
export { makeQuestManager as createQuestManager };
export { makeQuestLog as createQuestLog };

export function checkQuestComplete(quest: QuestDefinition): boolean {
	return quest.objectives.every((o) => o.completed);
}
export function getObjective(quest: QuestDefinition, id: string) {
	return quest.objectives.find((o) => o.id === id);
}
