/**
 * Integration tests — NpcManager (SGU adapter → engine factory)
 *
 * Verifies the bridge from player:interact → dialogue start, from
 * player:dialogue:choice → dialogue advance, and the FSM reset on
 * crew:dialogue:ended.
 */
import { describe, expect, it, beforeEach, afterEach } from "vitest";
import type { NpcDefinition } from "../../src/types/npc";
import type { DialogueTree } from "../../src/types/dialogue";
import { emit } from "../../src/systems/event-bus";
import { createDialogueManager } from "../../src/systems/dialogue-manager";
import { createNpcManager } from "../../src/systems/npc-manager";

const stationaryNpc: NpcDefinition = {
	id: "test-npc",
	name: "Test NPC",
	role: "merchant",
	dialogueTreeId: "test-npc",
	position: { x: 0, y: 0, z: 0 },
	behavior: { startingState: "idle", patrolDwellTime: 0, interactionRadius: 2 },
};

const testTree: DialogueTree = {
	id: "test-npc",
	startNodeId: "greet",
	nodes: [
		{
			id: "greet",
			speaker: "Test NPC",
			text: "Hello.",
			options: [{ id: "end", label: "Bye.", nextNodeId: null }],
		},
	],
};

describe("NpcManager (SGU → engine adapter)", () => {
	let dialogueManager: ReturnType<typeof createDialogueManager>;
	let npcManager: ReturnType<typeof createNpcManager>;

	beforeEach(() => {
		dialogueManager = createDialogueManager();
		dialogueManager.registerTree(testTree);
		npcManager = createNpcManager(dialogueManager);
		npcManager.registerNpc(stationaryNpc);
	});

	afterEach(() => {
		npcManager.dispose();
		dialogueManager.dispose();
	});

	it("registers NPCs accessible by ID", () => {
		// Assert
		const npc = npcManager.getNpc("test-npc");
		expect(npc?.definition.name).toBe("Test NPC");
		expect(npc?.state).toBe("idle");
		expect(npc?.inDialogue).toBe(false);
	});

	it("starts a dialogue on player:interact with action='talk'", () => {
		// Act
		emit("player:interact", { targetId: "test-npc", action: "talk" });

		// Assert
		expect(dialogueManager.isActive()).toBe(true);
		expect(npcManager.getNpc("test-npc")?.inDialogue).toBe(true);
		expect(npcManager.getNpc("test-npc")?.state).toBe("interact");
	});

	it("ignores non-talk interaction actions", () => {
		// Act
		emit("player:interact", { targetId: "test-npc", action: "attack" });

		// Assert
		expect(dialogueManager.isActive()).toBe(false);
		expect(npcManager.getNpc("test-npc")?.inDialogue).toBe(false);
	});

	it("forwards player:dialogue:choice to dialogueManager.advance()", () => {
		// Arrange
		emit("player:interact", { targetId: "test-npc", action: "talk" });

		// Act — choose "end" option which has nextNodeId: null → ends dialogue
		emit("player:dialogue:choice", { responseId: "end" });

		// Assert
		expect(dialogueManager.isActive()).toBe(false);
	});

	it("returns NPC to starting state after crew:dialogue:ended", () => {
		// Arrange
		emit("player:interact", { targetId: "test-npc", action: "talk" });
		expect(npcManager.getNpc("test-npc")?.state).toBe("interact");

		// Act
		dialogueManager.endDialogue();

		// Assert
		expect(npcManager.getNpc("test-npc")?.inDialogue).toBe(false);
		expect(npcManager.getNpc("test-npc")?.state).toBe("idle");
	});

	it("dispose cleans up subscriptions so later player:interact is ignored", () => {
		// Act
		npcManager.dispose();
		emit("player:interact", { targetId: "test-npc", action: "talk" });

		// Assert — no new dialogue started
		expect(dialogueManager.isActive()).toBe(false);
	});
});
