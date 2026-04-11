/**
 * Dr. Nicholas Rush — Dialogue Tree
 *
 * Rush is brilliant, secretive, and perpetually dismissive — unless he needs
 * something. This tree offers Eli the Destiny Power Crisis quest.
 * Tone: Mysterious, terse, condescending-but-intrigued.
 *
 * @see src/npcs/dr-rush.ts
 * @see src/quests/destiny-power-crisis/
 */
import type { DialogueTree, DialogueState } from '../types/dialogue.js';

export const drRushDialogue: DialogueTree = {
	id: 'dr-rush',
	startNodeId: 'greeting',
	nodes: [
		{
			id: 'greeting',
			speaker: 'Dr. Rush',
			text: "Wallace. I assume you didn't come to discuss Ancient poetry.",
			options: [
				{
					id: 'ask-power',
					label: 'You look like you need help with something.',
					nextNodeId: 'power-situation',
					condition: (state: DialogueState) => !state.flags['power-quest-started'],
				},
				{
					id: 'ask-ship',
					label: "What do you know about Destiny's power grid?",
					nextNodeId: 'ship-lore',
				},
			{
					id: 'farewell',
					label: "Never mind. I'll come back later.",
					nextNodeId: null,
				},
			],
		},
		{
			id: 'ship-lore',
			speaker: 'Dr. Rush',
			text: "More than anyone else on this ship, I assure you. The power grid is Ancient — millions of years old — and degrading faster than I can model. We have weeks, not months.",
			options: [
				{
					id: 'from-ship-lore-to-quest',
					label: 'Sounds like you need someone who can move around the ship quickly.',
					nextNodeId: 'power-situation',
					condition: (state: DialogueState) => !state.flags['power-quest-started'],
				},
				{
					id: 'back-to-greeting',
					label: "What else can you tell me?",
					nextNodeId: 'greeting',
				},
			],
		},
		{
			id: 'power-situation',
			speaker: 'Dr. Rush',
			text: "Three conduits feeding power to life support are at critical failure. I need them repaired before we lose breathable atmosphere in three sections. I've been... unable to leave the control interface.",
			options: [
				{
					id: 'accept-quest',
					label: "Tell me where. I'll handle it.",
					nextNodeId: 'quest-accepted',
					onSelect: (state: DialogueState) => {
						state.flags['power-quest-started'] = true;
						state.acceptedQuests.push('destiny-power-crisis');
						state.affinityDelta += 5;
					},
				},
				{
					id: 'ask-more',
					label: "Why can't you just redistribute power from another system?",
					nextNodeId: 'rush-explains',
				},
				{
					id: 'decline',
					label: "I'll think about it.",
					nextNodeId: 'quest-declined',
				},
			],
		},
		{
			id: 'rush-explains',
			speaker: 'Dr. Rush',
			text: "Because redistributing power kills the sensors. And without sensors we're flying blind into FTL. You want to explain to Colonel Young why we dropped out inside a star? I'm listening.",
			options: [
				{
					id: 'accept-after-explanation',
					label: "Alright. I'll fix the conduits.",
					nextNodeId: 'quest-accepted',
					onSelect: (state: DialogueState) => {
						state.flags['power-quest-started'] = true;
						state.acceptedQuests.push('destiny-power-crisis');
						state.affinityDelta += 3;
					},
				},
				{
					id: 'decline-after-explanation',
					label: "You make a compelling case for someone who's doing nothing.",
					nextNodeId: 'quest-declined',
					onSelect: (state: DialogueState) => { state.affinityDelta -= 2; },
				},
			],
		},
		{
			id: 'quest-accepted',
			speaker: 'Dr. Rush',
			text: "The conduits are in sections Delta-7, Delta-9, and the cargo hold. You'll need ship parts for each repair. And Wallace — don't dawdle.",
			options: [],
		},
		{
			id: 'quest-declined',
			speaker: 'Dr. Rush',
			text: "Fine. When life support goes critical I'll note your contribution in my log.",
			options: [
				{
					id: 'reconsider',
					label: "Wait. Tell me what needs doing.",
					nextNodeId: 'power-situation',
				},
				{ id: 'leave', label: "I said I'll think about it.", nextNodeId: null },
			],
		},
		{
			id: 'already-accepted',
			speaker: 'Dr. Rush',
			text: "The conduits aren't going to repair themselves, Wallace. Delta-7, Delta-9, cargo hold. Ship parts. Go.",
			options: [],
		},
	],
};
