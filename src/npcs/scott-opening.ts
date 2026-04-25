/**
 * Lt. Matthew Scott — Opening-Scene NPC
 *
 * Spawns immediately after the opening cinematic, kneeling in front of the
 * player. His only purpose is to deliver the "Eli... Eli, can you hear me?"
 * opening dialogue that kicks off the first quest (find Dr. Rush / figure
 * out what's happening). After the dialogue ends this NPC is left in the
 * scene where it spawned but no longer interactable through its own tree —
 * the player is now pointed at Rush.
 *
 * @see src/dialogues/scott-opening.ts
 */
import type { NpcDefinition } from '../types/npc.js';

export const scottOpeningNpc: NpcDefinition = {
	id: 'scott-opening',
	name: 'Lt. Matthew Scott',
	role: 'Military, 2nd in command',
	dialogueTreeId: 'scott-opening',
	// Position is set at spawn time relative to the player — the value here
	// is a placeholder. npc-manager doesn't move this NPC post-registration.
	position: { x: 0, y: 0, z: -2 },
	behavior: {
		startingState: 'idle',
		interactionRadius: 3.0,
		patrolDwellTime: 0,
	},
};
