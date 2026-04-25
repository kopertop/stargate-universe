/**
 * Quest: Air Crisis — Static Definition
 *
 * The CO₂ scrubbers are failing. Eli must gate to a desert planet,
 * find calcium deposits (lime), and return before the crew suffocates.
 *
 * Based on SGU episode "Air" (parts 1-3) — the first crisis of the series.
 *
 * Given by: Auto-starts on gate room load (Rush explains situation)
 * Type: main
 * Reward: XP + ship parts
 */
import type { QuestDefinition } from '../../types/quest.js';

export const airCrisisDefinition: QuestDefinition = {
	id: 'air-crisis',
	name: 'Air',
	description:
		"CO\u2082 levels are rising. The scrubbers are failing. The crew has only hours before " +
		"the atmosphere becomes unbreathable. Someone needs to gate to a planet and find a source " +
		"of calcium compounds \u2014 lime \u2014 to save everyone aboard.",
	type: 'main',
	giverNpcId: 'dr-rush',

	objectives: [
		{
			id: 'speak-to-rush',
			type: 'talk',
			description: 'Speak with Dr. Rush about the CO\u2082 problem.',
			targetId: 'dr-rush',
			required: 1,
			current: 0,
			completed: false,
			visible: true,
		},
		{
			id: 'locate-planet',
			type: 'interact',
			description: "Use Destiny's sensors to find a planet within dialing range.",
			targetId: 'gate-console',
			required: 1,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'speak-to-rush',
		},
		{
			id: 'gate-to-planet',
			type: 'reach',
			description: 'Step through the stargate to the desert planet. [Press E near active gate]',
			targetId: 'desert-planet',
			required: 1,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'locate-planet',
		},
		{
			id: 'find-lime',
			type: 'collect',
			description: 'Find calcium deposits on the planet surface (0 / 3).',
			targetId: 'calcium-deposit',
			required: 3,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'gate-to-planet',
		},
		{
			id: 'return-to-destiny',
			type: 'reach',
			description: 'Return through the stargate with the lime.',
			targetId: 'gate-room',
			required: 1,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'find-lime',
		},
		{
			id: 'fix-scrubbers',
			type: 'repair',
			description: 'Deliver the lime to the CO\u2082 scrubber room and repair the scrubbers.',
			targetId: 'co2-scrubbers',
			required: 1,
			current: 0,
			completed: false,
			visible: false,
			unlockedBy: 'return-to-destiny',
		},
	],

	reward: {
		type: 'multiple',
		xp: 500,
		items: [{ id: 'ship-parts', quantity: 10 }],
	},
};
