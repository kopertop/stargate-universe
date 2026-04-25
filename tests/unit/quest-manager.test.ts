/**
 * Integration tests — QuestManager (SGU adapter → engine factory)
 *
 * Verifies both the engine lifecycle (start → objective complete →
 * quest complete) and the SGU-specific auto-advance bridges
 * (ship:subsystem:repaired, resource:collected).
 */
import { describe, expect, it, beforeEach, afterEach } from "vitest";
import type { QuestDefinition } from "../../src/types/quest";
import { emit, on } from "../../src/systems/event-bus";
import { createQuestManager } from "../../src/systems/quest-manager";

const fixQuest: QuestDefinition = {
	id: "test-fix-stuff",
	name: "Fix Stuff",
	description: "Fix a subsystem and gather a resource.",
	type: "side",
	objectives: [
		{
			id: "repair-widget",
			type: "repair",
			description: "Repair the widget.",
			targetId: "widget-subsystem",
			required: 1, current: 0, completed: false, visible: true,
		},
		{
			id: "collect-gears",
			type: "collect",
			description: "Collect 3 gears.",
			targetId: "gear",
			required: 3, current: 0, completed: false, visible: true,
		},
	],
	reward: { type: "xp", xp: 10 },
};

describe("QuestManager (SGU → engine adapter)", () => {
	let manager: ReturnType<typeof createQuestManager>;

	beforeEach(() => {
		manager = createQuestManager();
		manager.registerDefinition(fixQuest);
	});

	afterEach(() => {
		// SGU's event-bus is a module singleton — if we don't dispose the
		// manager, its listeners leak across tests and double-advance
		// objectives for subsequent cases.
		manager.dispose();
	});

	it("starts a quest and emits quest:started", () => {
		// Arrange
		const started: string[] = [];
		const unsub = on("quest:started", (e) => { started.push(e.questId); });

		// Act
		const state = manager.startQuest("test-fix-stuff");

		// Assert
		expect(state?.status).toBe("in-progress");
		expect(manager.isActive("test-fix-stuff")).toBe(true);
		expect(started).toEqual(["test-fix-stuff"]);
		unsub();
	});

	it("advanceObjective completes an objective and fires the event", () => {
		// Arrange
		manager.startQuest("test-fix-stuff");
		const events: string[] = [];
		const unsub = on("quest:objective-complete", (e) => {
			events.push(`${e.questId}/${e.objectiveId}`);
		});

		// Act
		manager.advanceObjective("test-fix-stuff", "repair-widget");

		// Assert
		expect(events).toEqual(["test-fix-stuff/repair-widget"]);
		unsub();
	});

	it("auto-advances repair objectives on ship:subsystem:repaired", () => {
		// Arrange
		manager.startQuest("test-fix-stuff");
		const completed: string[] = [];
		const unsub = on("quest:objective-complete", (e) => { completed.push(e.objectiveId); });

		// Act — emit the SGU-specific bridge event
		emit("ship:subsystem:repaired", { subsystemId: "widget-subsystem", condition: 1 });

		// Assert
		expect(completed).toContain("repair-widget");
		unsub();
	});

	it("auto-advances collect objectives on resource:collected and completes the quest", () => {
		// Arrange
		manager.startQuest("test-fix-stuff");
		const completed: string[] = [];
		const questDone: string[] = [];
		const unsubObj  = on("quest:objective-complete", (e) => { completed.push(e.objectiveId); });
		const unsubQuest = on("quest:completed",         (e) => { questDone.push(e.questId); });

		// Act — complete the repair first, then collect 3 gears (one per event)
		emit("ship:subsystem:repaired", { subsystemId: "widget-subsystem", condition: 1 });
		emit("resource:collected", { type: "gear", amount: 1, source: "test" });
		emit("resource:collected", { type: "gear", amount: 1, source: "test" });
		emit("resource:collected", { type: "gear", amount: 1, source: "test" });

		// Assert
		expect(completed).toEqual(["repair-widget", "collect-gears"]);
		expect(questDone).toEqual(["test-fix-stuff"]);
		expect(manager.isCompleted("test-fix-stuff")).toBe(true);
		unsubObj(); unsubQuest();
	});

	it("serialize → deserialize round-trips objective progress", () => {
		// Arrange
		manager.startQuest("test-fix-stuff");
		manager.advanceObjective("test-fix-stuff", "collect-gears", 2); // 2 of 3

		// Act
		const snapshot = manager.serialize();
		const fresh = createQuestManager();
		fresh.registerDefinition(fixQuest);
		fresh.deserialize(snapshot);

		// Assert
		const restoredLog = fresh.getQuestLog();
		const restored = restoredLog.active.get("test-fix-stuff");
		expect(restored).toBeDefined();
		const collectObj = restored?.objectives.find((o) => o.id === "collect-gears");
		expect(collectObj?.current).toBe(2);
		expect(collectObj?.completed).toBe(false);
	});

	it("dispose unsubscribes from the SGU bridge events", () => {
		// Arrange — start quest, then dispose (which should unsub bridges)
		manager.startQuest("test-fix-stuff");
		manager.dispose();

		// Act — bridge event after dispose should NOT advance the objective
		emit("ship:subsystem:repaired", { subsystemId: "widget-subsystem", condition: 1 });

		// Assert — inspect the manager's quest log directly (no reliance on
		// another `on(quest:objective-complete)` listener to avoid false
		// positives from residual subscribers across the test file).
		const log = manager.getQuestLog();
		const state = log.active.get("test-fix-stuff") ?? log.completed.get("test-fix-stuff");
		const repairObj = state?.objectives.find((o) => o.id === "repair-widget");
		expect(repairObj?.completed).toBe(false);
		expect(repairObj?.current).toBe(0);
	});
});
