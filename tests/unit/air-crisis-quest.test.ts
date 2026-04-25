/**
 * Unit tests — Air Crisis quest definition
 *
 * Verifies structural integrity of the quest definition without loading
 * any Three.js or Vite-specific scene code. Pure data/logic only.
 */
import { describe, expect, it, beforeEach } from "vitest";
import { airCrisisDefinition } from "../../src/quests/air-crisis/definition";
import { QUEST_ID } from "../../src/quests/air-crisis/index";
import { isLimeCollected, setLimeCollected } from "../../src/systems/scene-transition-state";

// ─── Quest-level assertions ───────────────────────────────────────────────────

describe("Air Crisis quest definition", () => {
	it("has the correct quest ID", () => {
		expect(airCrisisDefinition.id).toBe("air-crisis");
	});

	it("QUEST_ID constant matches definition id", () => {
		expect(QUEST_ID).toBe(airCrisisDefinition.id);
	});

	it("is a main-type quest", () => {
		expect(airCrisisDefinition.type).toBe("main");
	});

	it("is given by dr-rush", () => {
		expect(airCrisisDefinition.giverNpcId).toBe("dr-rush");
	});

	it("offers XP as a reward", () => {
		expect(airCrisisDefinition.reward!.xp).toBeGreaterThan(0);
	});
});

// ─── Objective count & IDs ────────────────────────────────────────────────────

describe("Air Crisis objectives", () => {
	const { objectives } = airCrisisDefinition;

	it("has exactly 6 objectives", () => {
		expect(objectives).toHaveLength(6);
	});

	it("contains all required objective IDs", () => {
		const ids = objectives.map((o) => o.id);
		expect(ids).toContain("speak-to-rush");
		expect(ids).toContain("locate-planet");
		expect(ids).toContain("gate-to-planet");
		expect(ids).toContain("find-lime");
		expect(ids).toContain("return-to-destiny");
		expect(ids).toContain("fix-scrubbers");
	});

	it("first objective (speak-to-rush) is initially visible", () => {
		expect(objectives[0]?.id).toBe("speak-to-rush");
		expect(objectives[0]?.visible).toBe(true);
	});

	it("all subsequent objectives start hidden (gated by unlockedBy)", () => {
		for (const obj of objectives.slice(1)) {
			expect(obj.visible).toBe(false);
		}
	});
});

// ─── unlockedBy chain ─────────────────────────────────────────────────────────

describe("Air Crisis objective unlockedBy chain", () => {
	const byId = Object.fromEntries(
		airCrisisDefinition.objectives.map((o) => [o.id, o])
	);

	it("speak-to-rush has no prerequisite (auto-starts)", () => {
		expect(byId["speak-to-rush"]?.unlockedBy).toBeUndefined();
	});

	it("locate-planet is unlocked by speak-to-rush", () => {
		expect(byId["locate-planet"]?.unlockedBy).toBe("speak-to-rush");
	});

	it("gate-to-planet is unlocked by locate-planet", () => {
		expect(byId["gate-to-planet"]?.unlockedBy).toBe("locate-planet");
	});

	it("find-lime is unlocked by gate-to-planet", () => {
		expect(byId["find-lime"]?.unlockedBy).toBe("gate-to-planet");
	});

	it("return-to-destiny is unlocked by find-lime", () => {
		expect(byId["return-to-destiny"]?.unlockedBy).toBe("find-lime");
	});

	it("fix-scrubbers is unlocked by return-to-destiny", () => {
		expect(byId["fix-scrubbers"]?.unlockedBy).toBe("return-to-destiny");
	});
});

// ─── Key objective details ────────────────────────────────────────────────────

describe("Air Crisis collect objective (find-lime)", () => {
	const findLime = airCrisisDefinition.objectives.find((o) => o.id === "find-lime");

	it("exists", () => expect(findLime).toBeDefined());

	it("is type 'collect'", () => {
		expect(findLime?.type).toBe("collect");
	});

	it("requires exactly 3 calcium deposits", () => {
		expect(findLime?.required).toBe(3);
	});

	it("targets calcium-deposit resource type", () => {
		expect(findLime?.targetId).toBe("calcium-deposit");
	});

	it("starts at 0 collected", () => {
		expect(findLime?.current).toBe(0);
	});
});

describe("Air Crisis repair objective (fix-scrubbers)", () => {
	const fixScrubbers = airCrisisDefinition.objectives.find((o) => o.id === "fix-scrubbers");

	it("exists", () => expect(fixScrubbers).toBeDefined());

	it("is type 'repair'", () => {
		expect(fixScrubbers?.type).toBe("repair");
	});

	it("targets the co2-scrubbers subsystem", () => {
		expect(fixScrubbers?.targetId).toBe("co2-scrubbers");
	});

	it("requires exactly 1 repair action", () => {
		expect(fixScrubbers?.required).toBe(1);
	});

	it("is the final objective (index 5)", () => {
		const idx = airCrisisDefinition.objectives.findIndex((o) => o.id === "fix-scrubbers");
		expect(idx).toBe(5);
	});
});

// ─── Cross-scene transition state ─────────────────────────────────────────────

describe("scene-transition-state (lime flag)", () => {
	beforeEach(() => {
		setLimeCollected(false); // reset singleton to clean state before each test
	});

	it("starts as false after reset", () => {
		expect(isLimeCollected()).toBe(false);
	});

	it("setLimeCollected(true) makes isLimeCollected() return true", () => {
		setLimeCollected(true);
		expect(isLimeCollected()).toBe(true);
	});

	it("setLimeCollected(false) clears the flag", () => {
		setLimeCollected(true);
		setLimeCollected(false);
		expect(isLimeCollected()).toBe(false);
	});
});
