// ─── Quest types ───────────────────────────────────────────────────────────────

export type QuestType = 'main' | 'side' | 'repeatable';

export type QuestStatus =
	| 'not-started'
	| 'in-progress'
	| 'completed'
	| 'failed'
	| 'abandoned';

export type ObjectiveType =
	| 'collect'    // collect N items or resources
	| 'kill'       // defeat N enemies
	| 'talk'       // speak to an NPC
	| 'reach'      // reach a location/zone
	| 'escort'     // keep an NPC alive to a location
	| 'interact'   // use an object/terminal
	| 'repair'     // repair a ship subsystem (SGU-specific)
	| 'custom';

export type QuestObjective = {
	id: string;
	type: ObjectiveType;
	description: string;
	/** Target entity/item/NPC/subsystem/zone ID */
	targetId: string;
	/** Required amount */
	required: number;
	/** Current progress */
	current: number;
	completed: boolean;
	/** Whether visible in the quest log */
	visible: boolean;
	/** This objective only becomes active after another completes */
	unlockedBy?: string;
};

export type RewardType = 'items' | 'xp' | 'currency' | 'ability' | 'multiple' | 'none';

export type QuestReward = {
	type: RewardType;
	xp?: number;
	currency?: number;
	items?: Array<{ id: string; quantity: number }>;
	abilityId?: string;
};

/** Static quest definition — structure only, never mutated at runtime. */
export type QuestDefinition = {
	id: string;
	name: string;
	description: string;
	type: QuestType;
	giverNpcId?: string;
	objectives: QuestObjective[];
	reward: QuestReward;
	/** Quest that must be completed before this one unlocks */
	prerequisiteId?: string;
};

/** Runtime quest state — one per active/completed/failed quest. */
export type QuestState = {
	definition: QuestDefinition;
	status: QuestStatus;
	/** Mutable copy of objectives — progress tracked here */
	objectives: QuestObjective[];
	startedAt?: number;
	completedAt?: number;
};

/** The player's full quest log. */
export type QuestLog = {
	active: Map<string, QuestState>;
	completed: Map<string, QuestState>;
	failed: Map<string, QuestState>;
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

export const createQuestLog = (): QuestLog => ({
	active: new Map(),
	completed: new Map(),
	failed: new Map(),
});

export const isQuestComplete = (state: QuestState): boolean =>
	state.objectives.every(o => o.completed);

export const getObjective = (state: QuestState, objectiveId: string): QuestObjective | undefined =>
	state.objectives.find(o => o.id === objectiveId);
