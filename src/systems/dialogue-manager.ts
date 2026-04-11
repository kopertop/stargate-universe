/**
 * Dialogue Manager — runs branching dialogue trees and wires into the event bus.
 *
 * Tracks a registry of DialogueTrees by NPC ID. One active session at a time.
 * Emits crew:dialogue:* events throughout the conversation lifecycle.
 *
 * Adapts the vibe-game-engine add-dialogue skill for SGU's @ggez/* stack:
 * uses SGU's own typed event bus instead of @kopertop/vibe-game-engine imports.
 *
 * @see design/gdd/crew-dialogue-choice.md
 * @see src/types/dialogue.ts
 */
import { emit } from './event-bus.js';
import type { DialogueTree, DialogueNode, DialogueOption, DialogueState } from '../types/dialogue.js';
import { getNode, getVisibleOptions, selectOption, createDialogueState } from '../types/dialogue.js';

// ─── Types ────────────────────────────────────────────────────────────────────

type DialogueSession = {
	tree: DialogueTree;
	currentNodeId: string | null;
	state: DialogueState;
};

export type DialogueManager = {
	registerTree: (tree: DialogueTree) => void;
	startDialogue: (npcId: string) => DialogueNode | null;
	advance: (optionId: string) => DialogueNode | null;
	endDialogue: () => void;
	getCurrentNode: () => DialogueNode | null;
	getVisibleOptions: () => DialogueOption[];
	isActive: () => boolean;
	dispose: () => void;
};

// ─── Factory ─────────────────────────────────────────────────────────────────

export const createDialogueManager = (): DialogueManager => {
	const trees = new Map<string, DialogueTree>();
	let session: DialogueSession | null = null;

	const registerTree = (tree: DialogueTree): void => {
		trees.set(tree.id, tree);
	};

	const startDialogue = (npcId: string): DialogueNode | null => {
		if (session) endDialogue();
		const tree = trees.get(npcId);
		if (!tree) {
			console.warn(`[dialogue] No tree registered for "${npcId}"`);
			return null;
		}
		const state = createDialogueState();
		session = { tree, currentNodeId: tree.startNodeId, state };
		const startNode = getNode(tree, tree.startNodeId);
		startNode.onEnter?.(state);
		emit('crew:dialogue:started', { speakerId: npcId, dialogueId: tree.id });
		emit('crew:dialogue:node', { speakerId: npcId, dialogueId: tree.id, nodeId: startNode.id });
		return startNode;
	};

	const advance = (optionId: string): DialogueNode | null => {
		if (!session?.currentNodeId) return null;
		const currentNode = getNode(session.tree, session.currentNodeId);
		const visible = getVisibleOptions(currentNode, session.state);
		const option = visible.find(o => o.id === optionId);
		if (!option) {
			console.warn(`[dialogue] Option "${optionId}" not visible`);
			return null;
		}
		emit('crew:choice:made', {
			dialogueId: session.tree.id,
			nodeId: session.currentNodeId,
			responseId: optionId,
		});
		const nextNodeId = selectOption(option, session.state);
		session.currentNodeId = nextNodeId;
		if (nextNodeId === null) { endDialogue(); return null; }
		const nextNode = getNode(session.tree, nextNodeId);
		nextNode.onEnter?.(session.state);
		emit('crew:dialogue:node', {
			speakerId: session.tree.id,
			dialogueId: session.tree.id,
			nodeId: nextNode.id,
		});
		// Auto-end on terminal nodes (no options)
		if (nextNode.options.length === 0) { endDialogue(); return null; }
		return nextNode;
	};

	const endDialogue = (): void => {
		if (!session) return;
		const { tree, state } = session;
		if (state.affinityDelta !== 0) {
			emit('crew:relationship:changed', { characterId: tree.id, affinity: state.affinityDelta });
		}
		emit('crew:dialogue:ended', { speakerId: tree.id, dialogueId: tree.id });
		session = null;
	};

	const getCurrentNode = (): DialogueNode | null => {
		if (!session?.currentNodeId) return null;
		return getNode(session.tree, session.currentNodeId);
	};

	const getVisibleOptionsForCurrent = (): DialogueOption[] => {
		if (!session?.currentNodeId) return [];
		const node = getNode(session.tree, session.currentNodeId);
		return getVisibleOptions(node, session.state);
	};

	return {
		registerTree,
		startDialogue,
		advance,
		endDialogue,
		getCurrentNode,
		getVisibleOptions: getVisibleOptionsForCurrent,
		isActive: () => session !== null,
		dispose: () => { if (session) endDialogue(); },
	};
};
