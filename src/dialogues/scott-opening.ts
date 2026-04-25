/**
 * Lt. Matthew Scott — Opening Dialogue
 *
 * Plays immediately after the opening arrival cinematic. Scott is crouched
 * in front of the player, checking on Eli. The player just came through a
 * nine-chevron stargate address to an Ancient vessel (Destiny) and has
 * taken a hard landing.
 *
 * This dialogue's purpose:
 *   - Set the tone ("we don't know where we are")
 *   - Re-orient the player inside the gate room
 *   - Point them at Dr. Rush to figure out what's happening
 *
 * It does NOT start a quest of its own — the air-crisis quest is already
 * active, and this dialogue simply nudges the player toward the "speak to
 * Rush" objective that triggers the rest of the questline.
 *
 * Tone: Scott is calm-professional under fire. Military cadence. He's
 * relieved Eli is awake but there's no time for sentiment.
 *
 * @see src/npcs/scott-opening.ts
 * @see src/quests/air-crisis/
 */
import type { DialogueTree, DialogueState } from '../types/dialogue.js';

export const scottOpeningDialogue: DialogueTree = {
	id: 'scott-opening',
	startNodeId: 'intro',
	nodes: [
		{
			id: 'intro',
			speaker: 'Lt. Scott',
			text: "Eli... Eli, can you hear me? Come on, man — look at me.",
			options: [
				{
					id: 'im-awake',
					label: "Yeah... yeah, I'm here. Where — where the hell are we?",
					nextNodeId: 'scott-explains',
				},
				{
					id: 'head-hurts',
					label: "My head. What happened?",
					nextNodeId: 'scott-explains',
				},
			],
		},
		{
			id: 'scott-explains',
			speaker: 'Lt. Scott',
			text: "We don't know. Nine-chevron address. Icarus went up and we came through — " +
				"some kind of Ancient ship. That's all I've got. Rush is over by the console " +
				"trying to figure out where 'here' is. You need to talk to him.",
			options: [
				{
					id: 'who-else',
					label: "Who else came through? Is everyone okay?",
					nextNodeId: 'scott-crew',
				},
				{
					id: 'ancient-ship',
					label: "Ancient ship. Like, THE Ancients?",
					nextNodeId: 'scott-ancient',
				},
				{
					id: 'go-find-rush',
					label: "Rush. Right. I'll go find him.",
					nextNodeId: 'scott-sends-player',
					onSelect: (state: DialogueState) => {
						state.flags['scott-met'] = true;
						state.affinityDelta += 2;
					},
				},
			],
		},
		{
			id: 'scott-crew',
			speaker: 'Lt. Scott',
			text: "Most of us made it. Young took a bad hit — TJ's with him. Everyone else is up. " +
				"We're short on time, Eli. Rush is the one who can tell us how short. Go.",
			options: [
				{
					id: 'from-crew-go-find-rush',
					label: "Got it. I'm on it.",
					nextNodeId: 'scott-sends-player',
					onSelect: (state: DialogueState) => {
						state.flags['scott-met'] = true;
						state.affinityDelta += 2;
					},
				},
			],
		},
		{
			id: 'scott-ancient',
			speaker: 'Lt. Scott',
			text: "I don't know. I don't know anything yet. That's Rush's department — and right " +
				"now he's the only one who does. Just… go talk to him. Please.",
			options: [
				{
					id: 'from-ancient-go-find-rush',
					label: "On my way.",
					nextNodeId: 'scott-sends-player',
					onSelect: (state: DialogueState) => {
						state.flags['scott-met'] = true;
						state.affinityDelta += 1;
					},
				},
			],
		},
		{
			id: 'scott-sends-player',
			speaker: 'Lt. Scott',
			text: "Good. I'll check on the others. Find Rush — he's by the main console.",
			options: [],
		},
	],
};
