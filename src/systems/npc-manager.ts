/**
 * NPC Manager — registers crew-member NPCs, runs their FSM each tick,
 * and bridges player:interact events to the dialogue system.
 *
 * Adapts the vibe-game-engine add-npc skill for SGU's @ggez/* stack:
 * no bitECS — NPCs are plain typed objects tracked in a Map, registered
 * with SGU's own event bus (mitt-based) instead of an ECS world.
 *
 * @see src/types/npc.ts
 * @see src/systems/dialogue-manager.ts
 */
import { on } from './event-bus.js';
import type { NpcDefinition, NpcInstance, NpcState } from '../types/npc.js';
import type { DialogueManager } from './dialogue-manager.js';

// ─── Types ────────────────────────────────────────────────────────────────────

export type NpcManager = {
	registerNpc: (definition: NpcDefinition) => void;
	unregisterNpc: (id: string) => void;
	/** Call from scene fixedUpdate to tick all NPC behavior FSMs. */
	update: (dt: number) => void;
	getNpc: (id: string) => NpcInstance | undefined;
	getAllNpcs: () => NpcInstance[];
	dispose: () => void;
};

// ─── FSM helpers ──────────────────────────────────────────────────────────────

const transitionTo = (npc: NpcInstance, next: NpcState): void => {
	npc.state = next;
	npc.timer = 0;
};

const tickNpc = (npc: NpcInstance, dt: number): void => {
	if (npc.inDialogue) return;
	npc.timer += dt;
	switch (npc.state) {
		case 'idle': {
			const path = npc.definition.behavior.patrolPath;
			if (path && path.length > 1 && npc.timer >= npc.definition.behavior.patrolDwellTime) {
				transitionTo(npc, 'patrol');
			}
			break;
		}
		case 'patrol': {
			if (npc.timer >= npc.definition.behavior.patrolDwellTime) {
				const path = npc.definition.behavior.patrolPath ?? [];
				npc.patrolIndex = (npc.patrolIndex + 1) % Math.max(path.length, 1);
				transitionTo(npc, 'idle');
			}
			break;
		}
		case 'interact':
			// Held in interact until crew:dialogue:ended fires
			break;
	}
};

// ─── Factory ─────────────────────────────────────────────────────────────────

export const createNpcManager = (dialogueManager: DialogueManager): NpcManager => {
	const npcs = new Map<string, NpcInstance>();
	const unsubscribers: Array<() => void> = [];

	// Player initiates conversation
	unsubscribers.push(on('player:interact', ({ targetId, action }) => {
		if (action !== 'talk') return;
		const npc = npcs.get(targetId);
		if (!npc || npc.inDialogue) return;
		npc.inDialogue = true;
		transitionTo(npc, 'interact');
		dialogueManager.startDialogue(npc.definition.dialogueTreeId ?? npc.definition.id);
	}));

	// Player selected a dialogue response option — advance the dialogue tree
	unsubscribers.push(on('player:dialogue:choice', ({ responseId }) => {
		dialogueManager.advance(responseId);
	}));

	// Dialogue ended — return NPC to its starting state
	unsubscribers.push(on('crew:dialogue:ended', ({ speakerId }) => {
		const npc = npcs.get(speakerId);
		if (!npc) return;
		npc.inDialogue = false;
		transitionTo(npc, npc.definition.behavior.startingState);
	}));

	const registerNpc = (definition: NpcDefinition): void => {
		npcs.set(definition.id, {
			definition,
			state: definition.behavior.startingState,
			timer: 0,
			patrolIndex: 0,
			inDialogue: false,
		});
	};

	return {
		registerNpc,
		unregisterNpc: (id) => { npcs.delete(id); },
		update: (dt) => { for (const npc of npcs.values()) tickNpc(npc, dt); },
		getNpc: (id) => npcs.get(id),
		getAllNpcs: () => [...npcs.values()],
		dispose: () => {
			for (const unsub of unsubscribers) unsub();
			unsubscribers.length = 0;
			npcs.clear();
		},
	};
};
