// ─── Dialogue types ────────────────────────────────────────────────────────────

/** Mutable state passed through a dialogue session. */
export type DialogueState = {
	/** Map of flag name → boolean (e.g. 'rush-trust-gained': true) */
	flags: Record<string, boolean>;
	/** Quest IDs accepted via dialogue onSelect callbacks */
	acceptedQuests: string[];
	/** Net relationship change to apply when conversation ends (positive = warmer) */
	affinityDelta: number;
};

/** A single player-selectable response option (spoken as Eli). */
export type DialogueOption = {
	/** Unique ID for this option within its node */
	id: string;
	/** Text displayed to the player */
	label: string;
	/** Node to transition to, or null to end the conversation */
	nextNodeId: string | null;
	/** Optional condition — return false to hide this option */
	condition?: (state: DialogueState) => boolean;
	/** Optional effect — runs immediately when this option is chosen */
	onSelect?: (state: DialogueState) => void;
};

/** A single beat of dialogue — what the crew member says plus player reply options. */
export type DialogueNode = {
	/** Unique ID within the tree */
	id: string;
	/** Name of the speaking character */
	speaker: string;
	/** What they say */
	text: string;
	/** Player (Eli) response options. Empty = auto-close conversation. */
	options: DialogueOption[];
	/** Runs on entry — use for animations, SFX, event emissions */
	onEnter?: (state: DialogueState) => void;
};

/** The top-level dialogue tree for a single NPC or world interaction. */
export type DialogueTree = {
	/** Matches the NPC/context ID (e.g. 'dr-rush') */
	id: string;
	/** Node ID to start from */
	startNodeId: string;
	/** All nodes in the tree */
	nodes: DialogueNode[];
};

// ─── Pure helpers ──────────────────────────────────────────────────────────────

/** Find a node by ID — throws if missing (trees must be internally consistent). */
export const getNode = (tree: DialogueTree, nodeId: string): DialogueNode => {
	const node = tree.nodes.find(n => n.id === nodeId);
	if (!node) throw new Error(`[dialogue] Node "${nodeId}" not found in tree "${tree.id}"`);
	return node;
};

/** Filter to options whose condition passes (or have no condition). */
export const getVisibleOptions = (node: DialogueNode, state: DialogueState): DialogueOption[] =>
	node.options.filter(opt => opt.condition === undefined || opt.condition(state));

/** Run option's side effect and return next node ID (null = conversation ends). */
export const selectOption = (option: DialogueOption, state: DialogueState): string | null => {
	option.onSelect?.(state);
	return option.nextNodeId;
};

/** Create a fresh dialogue state for a new conversation session. */
export const createDialogueState = (): DialogueState => ({
	flags: {},
	acceptedQuests: [],
	affinityDelta: 0,
});
