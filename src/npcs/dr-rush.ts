/**
 * Dr. Nicholas Rush — NPC Definition
 *
 * Chief scientist. Permanently stationed at the ship's primary interface consoles.
 * Quest-giver type: idle at his station, interactable, has full dialogue tree.
 *
 * @see src/dialogues/dr-rush.ts
 * @see src/quests/destiny-power-crisis/
 */
import type { NpcDefinition } from '../types/npc.js';

export const drRushNpc: NpcDefinition = {
	id: 'dr-rush',
	name: 'Dr. Nicholas Rush',
	role: 'Chief Science Officer',
	dialogueTreeId: 'dr-rush',
	// Near Destiny's main console — tune to actual scene node positions
	position: { x: 0, y: 0, z: -8 },
	behavior: {
		startingState: 'idle',
		interactionRadius: 2.5,
		patrolDwellTime: 0,          // Rush never patrols — he stays at the console
		// No patrolPath — undefined keeps him stationary
	},
};
