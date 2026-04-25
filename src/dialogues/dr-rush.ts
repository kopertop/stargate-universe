/**
 * Dr. Nicholas Rush — Dialogue Tree (Air Crisis)
 *
 * Rush is frantic — the CO₂ scrubbers are failing and the crew is going to die.
 * He needs Eli to volunteer to go through the gate to a desert planet and find
 * lime (calcium compounds) to absorb the CO₂.
 *
 * Tone: Urgent, scientific, abrasive. Rush cares about survival but not feelings.
 * Accent: Scottish. Brilliant but condescending. Gets straight to the point.
 *
 * This tree triggers the 'air-crisis' quest objective 'speak-to-rush' when the
 * player commits to going through the gate. The gate-room scene listens for the
 * 'crew:choice:made' event with responseId 'commit-to-gate'.
 *
 * @see src/npcs/dr-rush.ts
 * @see src/quests/air-crisis/
 */
import type { DialogueTree, DialogueState } from '../types/dialogue.js';

export const drRushDialogue: DialogueTree = {
	id: 'dr-rush',
	startNodeId: 'greeting',
	nodes: [
		{
			id: 'greeting',
			speaker: 'Dr. Rush',
			text: "Wallace. Good — I need someone who can move fast. The CO\u2082 scrubbers are failing. " +
				"At current atmospheric levels the crew will be incapacitated in twelve hours. Dead in twenty-four. " +
				"We have one option: someone gates to that planet and finds a calcium source. Lime. Now.",
			options: [
				{
					id: 'ask-what-needed',
					label: "What exactly do we need? Lime like the fruit?",
					nextNodeId: 'rush-explains-lime',
					condition: (state: DialogueState) => !state.flags['rush-co2-committed'],
				},
				{
					id: 'ask-timeline',
					label: "Twelve hours. How certain are you?",
					nextNodeId: 'rush-timeline',
					condition: (state: DialogueState) => !state.flags['rush-co2-committed'],
				},
				{
					id: 'ask-planet',
					label: "What about the planet we just passed?",
					nextNodeId: 'rush-scanning',
					condition: (state: DialogueState) => !state.flags['rush-co2-committed'],
				},
				{
					id: 'commit-to-gate',
					label: "Tell me what I need to know. I'll go through the gate.",
					nextNodeId: 'rush-sends-you-off',
					condition: (state: DialogueState) => !state.flags['rush-co2-committed'],
					onSelect: (state: DialogueState) => {
						state.flags['rush-co2-committed'] = true;
						state.affinityDelta += 4;
					},
				},
				{
					id: 'farewell-early',
					label: "I need a moment to think.",
					nextNodeId: null,
					condition: (state: DialogueState) => !state.flags['rush-co2-committed'],
				},
				{
					id: 'already-committed-check',
					label: "Any update on the CO\u2082 situation?",
					nextNodeId: 'rush-update',
					condition: (state: DialogueState) => state.flags['rush-co2-committed'],
				},
			],
		},

		// ── Lime explanation branch ────────────────────────────────────────
		{
			id: 'rush-explains-lime',
			speaker: 'Dr. Rush',
			text: "Calcium oxide. Quicklime. It reacts with CO\u2082 and removes it from the atmosphere — " +
				"been used in submarines for a century. It's an extraordinarily common mineral. We don't need " +
				"a chemistry lab, we just need the raw material. The planet's sensors show silicate desert — " +
				"limestone, chalk formations, calcium carbonate. Any of it will do.",
			options: [
				{
					id: 'from-lime-to-commit',
					label: "Right. So I find rocks. I can do that. I'll go.",
					nextNodeId: 'rush-sends-you-off',
					onSelect: (state: DialogueState) => {
						state.flags['rush-co2-committed'] = true;
						state.affinityDelta += 4;
					},
				},
				{
					id: 'from-lime-ask-timeline',
					label: "How much time does that actually leave me on the planet?",
					nextNodeId: 'rush-timeline',
				},
				{
					id: 'from-lime-back',
					label: "Let me ask you something else first.",
					nextNodeId: 'greeting',
				},
			],
		},

		// ── Timeline branch ────────────────────────────────────────────────
		{
			id: 'rush-timeline',
			speaker: 'Dr. Rush',
			text: "Current CO\u2082: 0.8%. Crew starts showing impairment around 3%. " +
				"At our scrubber degradation rate — assuming no further failures, which is optimistic — " +
				"you have perhaps eight hours before anyone on this ship can't think straight. " +
				"That includes the people keeping us out of FTL. So I'd suggest you stop asking questions " +
				"and start moving.",
			options: [
				{
					id: 'from-timeline-commit',
					label: "Eight hours. Understood. I'll go.",
					nextNodeId: 'rush-sends-you-off',
					onSelect: (state: DialogueState) => {
						state.flags['rush-co2-committed'] = true;
						state.affinityDelta += 3;
					},
				},
				{
					id: 'from-timeline-ask-planet',
					label: "Tell me about the planet.",
					nextNodeId: 'rush-scanning',
				},
				{
					id: 'from-timeline-back',
					label: "One more question.",
					nextNodeId: 'greeting',
				},
			],
		},

		// ── Planet scanning branch ─────────────────────────────────────────
		{
			id: 'rush-scanning',
			speaker: 'Dr. Rush',
			text: "I've been scanning since we dropped out of FTL. There's a desert planet within " +
				"dialing range — barely. Silicate geology, thin atmosphere, breathable for short periods. " +
				"No life signs, which means no predators, but also means you're on your own. " +
				"Calcium formations should be visible on the surface. The gate should hold for long enough. " +
				"Should.",
			options: [
				{
					id: 'from-scanning-commit',
					label: "That's enough. I'll go.",
					nextNodeId: 'rush-sends-you-off',
					onSelect: (state: DialogueState) => {
						state.flags['rush-co2-committed'] = true;
						state.affinityDelta += 3;
					},
				},
				{
					id: 'from-scanning-ask-what',
					label: "What do the calcium deposits look like? So I know what I'm finding.",
					nextNodeId: 'rush-explains-lime',
				},
				{
					id: 'from-scanning-back',
					label: "Let me ask you something else.",
					nextNodeId: 'greeting',
				},
			],
		},

		// ── Terminal: committed, sending player off ────────────────────────
		{
			id: 'rush-sends-you-off',
			speaker: 'Dr. Rush',
			text: "Dial the gate. Step through. Find the calcium deposits — they'll look like pale " +
				"rock formations, possibly crystalline. Collect as much as you can carry. " +
				"Then get back through the gate before it closes. " +
				"Every minute you spend talking to me is a minute of breathable air we don't get back. " +
				"Quickly, Wallace. Every minute counts.",
			options: [],
		},

		// ── Subsequent conversations after committing ──────────────────────
		{
			id: 'rush-update',
			speaker: 'Dr. Rush',
			text: "CO\u2082 is still climbing. The scrubbers aren't getting any better on their own. " +
				"Whatever you're doing, do it faster.",
			options: [
				{
					id: 'rush-update-leave',
					label: "I'm on it.",
					nextNodeId: null,
				},
			],
		},
	],
};
