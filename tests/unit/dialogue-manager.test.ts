/**
 * Integration tests — DialogueManager (SGU adapter → engine factory)
 *
 * Verifies that SGU's `createDialogueManager` correctly forwards the
 * SGU event bus to the engine manager and that typed `emit` flows fire
 * as expected. Since SGU's bus is a module-level singleton, each test
 * installs a small listener via `on(...)` and asserts the payload
 * after driving the manager.
 */
import { describe, expect, it, beforeEach, afterEach } from "vitest";
import type { DialogueTree } from "../../src/types/dialogue";
import { on } from "../../src/systems/event-bus";
import { createDialogueManager } from "../../src/systems/dialogue-manager";

const greeterTree: DialogueTree = {
	id: "greeter",
	startNodeId: "hello",
	nodes: [
		{
			id: "hello",
			speaker: "Greeter",
			text: "Hello, traveller.",
			options: [
				{ id: "respond-kind",  label: "Hi there.",           nextNodeId: "thanks",
					onSelect: (s) => { s.affinityDelta += 1; s.flags["met-greeter"] = true; } },
				{ id: "respond-rude",  label: "Whatever.",            nextNodeId: "farewell",
					onSelect: (s) => { s.affinityDelta -= 2; } },
				{ id: "hidden-option", label: "Secret handshake?",   nextNodeId: null,
					condition: (s) => s.flags["has-secret-info"] === true },
				{ id: "accept-quest",  label: "I'll help you.",       nextNodeId: null,
					onSelect: (s) => { s.acceptedQuests.push("test-help-quest"); } },
			],
		},
		{
			id: "thanks",
			speaker: "Greeter",
			text: "Kind of you.",
			options: [],
		},
		{
			id: "farewell",
			speaker: "Greeter",
			text: "Goodbye.",
			options: [],
		},
	],
};

describe("DialogueManager (SGU → engine adapter)", () => {
	let manager: ReturnType<typeof createDialogueManager>;

	beforeEach(() => {
		manager = createDialogueManager();
		manager.registerTree(greeterTree);
	});

	afterEach(() => {
		manager.dispose();
	});

	it("registers a tree and starts a dialogue session at the start node", () => {
		// Act
		const node = manager.startDialogue("greeter");

		// Assert
		expect(node).not.toBeNull();
		expect(node?.id).toBe("hello");
		expect(node?.speaker).toBe("Greeter");
		expect(manager.isActive()).toBe(true);
	});

	it("emits crew:dialogue:started when a session begins", () => {
		// Arrange
		const events: Array<{ speakerId: string; dialogueId: string }> = [];
		const unsub = on("crew:dialogue:started", (e) => { events.push(e); });

		// Act
		manager.startDialogue("greeter");

		// Assert
		expect(events).toHaveLength(1);
		expect(events[0].speakerId).toBe("greeter");
		expect(events[0].dialogueId).toBe("greeter");
		unsub();
	});

	it("emits crew:dialogue:node with visible options only", () => {
		// Arrange
		const nodes: Array<{ nodeId: string; options: ReadonlyArray<{ id: string }> }> = [];
		const unsub = on("crew:dialogue:node", (e) => {
			nodes.push({ nodeId: e.nodeId, options: e.options });
		});

		// Act
		manager.startDialogue("greeter");

		// Assert — hidden-option should NOT appear (condition returns false)
		expect(nodes).toHaveLength(1);
		const ids = nodes[0].options.map((o) => o.id);
		expect(ids).toContain("respond-kind");
		expect(ids).toContain("respond-rude");
		expect(ids).toContain("accept-quest");
		expect(ids).not.toContain("hidden-option");
		unsub();
	});

	it("advance() transitions through the target node and fires choice:made + dialogue:node", () => {
		// Arrange — "thanks" has empty options so it auto-ends; we verify
		// the crew:dialogue:node event fired for it before the session ended.
		const choices: Array<{ responseId: string }> = [];
		const nodesSeen: string[] = [];
		const unsubChoice = on("crew:choice:made", (e) => { choices.push(e); });
		const unsubNode = on("crew:dialogue:node", (e) => { nodesSeen.push(e.nodeId); });

		// Act
		manager.startDialogue("greeter");
		manager.advance("respond-kind");

		// Assert
		expect(choices).toHaveLength(1);
		expect(choices[0].responseId).toBe("respond-kind");
		expect(nodesSeen).toEqual(["hello", "thanks"]);
		unsubChoice(); unsubNode();
	});

	it("auto-ends on a terminal node and emits crew:dialogue:ended", () => {
		// Arrange
		const ended: string[] = [];
		const unsub = on("crew:dialogue:ended", (e) => { ended.push(e.speakerId); });

		// Act
		manager.startDialogue("greeter");
		manager.advance("respond-kind"); // → "thanks" (empty options → auto-end)

		// Assert
		expect(ended).toEqual(["greeter"]);
		expect(manager.isActive()).toBe(false);
		unsub();
	});

	it("accumulates affinity across sessions and fires relationship:changed", () => {
		// Arrange
		const relationshipChanges: Array<{ characterId: string; affinity: number }> = [];
		const unsub = on("crew:relationship:changed", (e) => { relationshipChanges.push(e); });

		// Act — first session: +1
		manager.startDialogue("greeter");
		manager.advance("respond-kind");
		// Second session: -2
		manager.startDialogue("greeter");
		manager.advance("respond-rude");

		// Assert — total affinity is -1, two events fired
		expect(relationshipChanges).toEqual([
			{ characterId: "greeter", affinity:  1 },
			{ characterId: "greeter", affinity: -2 },
		]);
		expect(manager.getAffinity("greeter")).toBe(-1);
		unsub();
	});

	it("records met NPCs so hasMetNpc reports correctly", () => {
		// Arrange + Act
		expect(manager.hasMetNpc("greeter")).toBe(false);
		manager.startDialogue("greeter");

		// Assert
		expect(manager.hasMetNpc("greeter")).toBe(true);
	});

	it("serialize → deserialize round-trips affinity + met state", () => {
		// Arrange
		manager.startDialogue("greeter");
		manager.advance("respond-kind");
		manager.startDialogue("greeter");
		manager.advance("accept-quest");

		// Act
		const snapshot = manager.serialize();
		const fresh = createDialogueManager();
		fresh.registerTree(greeterTree);
		fresh.deserialize(snapshot);

		// Assert
		expect(fresh.hasMetNpc("greeter")).toBe(true);
		expect(fresh.getAffinity("greeter")).toBe(1);
	});
});
