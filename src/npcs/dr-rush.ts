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
	// Left-side gate-room console, on the player's side of the gate. Player
	// spawns at (0, 0.5, 12) facing the gate (−Z); this puts Rush off to
	// the player's left, slightly behind them so they have to turn to find
	// him — consistent with the "Dr. Rush is already here, working" beat.
	position: { x: -20, y: 0, z: 48 },
	behavior: {
		startingState: 'idle',
		interactionRadius: 2.5,
		patrolDwellTime: 0,          // Rush never patrols — he stays at the console
		// No patrolPath — undefined keeps him stationary
	},
};
