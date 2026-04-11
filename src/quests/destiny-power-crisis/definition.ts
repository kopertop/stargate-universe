/**
 * Quest: Destiny Power Crisis — Static Definition
 *
 * Eli must repair three conduits feeding life support before critical
 * atmosphere loss hits three sections of the ship.
 *
 * Given by: Dr. Rush (via dialogue)
 * Type: side (tutorial for the repair system)
 * Reward: ship-parts + XP
 */
import type { QuestDefinition } from '../../types/quest.js';

export const destinyPowerCrisisDefinition: QuestDefinition = {
	id: 'destiny-power-crisis',
	name: 'Power Crisis',
	description:
		"Dr. Rush has identified three conduits feeding life support at critical failure. " +
		"Repair them before atmosphere becomes unbreathable in Delta-7, Delta-9, and the cargo hold.",
	type: 'side',
	giverNpcId: 'dr-rush',

	objectives: [
		{
			id: 'repair-delta-7',
			type: 'repair',
			description: 'Repair the power conduit in section Delta-7.',
			targetId: 'conduit-delta-7',
			required: 1,
			current: 0,
			completed: false,
			visible: true,
		},
		{
			id: 'repair-delta-9',
			type: 'repair',
			description: 'Repair the power conduit in section Delta-9.',
			targetId: 'conduit-delta-9',
			required: 1,
			current: 0,
			completed: false,
			visible: true,
		},
		{
			id: 'repair-cargo',
			type: 'repair',
			description: 'Repair the power conduit in the cargo hold.',
			targetId: 'conduit-cargo-hold',
			required: 1,
			current: 0,
			completed: false,
			visible: true,
		},
		{
			id: 'report-back',
			type: 'talk',
			description: 'Report back to Dr. Rush.',
			targetId: 'dr-rush',
			required: 1,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'repair-cargo',
		},
	],

	reward: {
		type: 'multiple',
		xp: 300,
		items: [{ id: 'ship-parts', quantity: 15 }],
	},
};
