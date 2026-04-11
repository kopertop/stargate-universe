// ─── NPC types ────────────────────────────────────────────────────────────────

/** States a crew-member NPC can be in. */
export type NpcState = 'idle' | 'patrol' | 'interact';

export type PatrolWaypoint = {
	x: number;
	y: number;
	z: number;
};

export type NpcBehaviorConfig = {
	/** State to enter when first spawned */
	startingState: NpcState;
	/** Optional loop path for patrol state */
	patrolPath?: PatrolWaypoint[];
	/** Seconds to dwell at each waypoint (or idle) before switching to patrol */
	patrolDwellTime: number;
	/** Radius (world units) within which player:interact events are honored */
	interactionRadius: number;
};

/** Static data for a crew-member NPC — never mutated at runtime. */
export type NpcDefinition = {
	/** Kebab-case unique ID, e.g. 'dr-rush' */
	id: string;
	/** Full display name, e.g. 'Dr. Nicholas Rush' */
	name: string;
	/** Short role label shown in UI */
	role: string;
	/** Dialogue tree ID — must match a registered DialogueTree.id */
	dialogueTreeId?: string;
	/** Default world position */
	position: { x: number; y: number; z: number };
	/** Behavior FSM config */
	behavior: NpcBehaviorConfig;
};

/** Runtime mutable state for one NPC instance. */
export type NpcInstance = {
	definition: NpcDefinition;
	state: NpcState;
	/** Seconds elapsed in current state */
	timer: number;
	/** Current patrol waypoint index */
	patrolIndex: number;
	/** True while the player is in an active dialogue with this NPC */
	inDialogue: boolean;
};
