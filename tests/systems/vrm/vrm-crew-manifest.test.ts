import { describe, expect, it, vi, beforeEach } from "vitest";
import {
	DEFAULT_CREW_ROSTER,
	getCrewManifest,
	getCrewRoster,
	getNpcManifests,
	getPlayerManifest,
	loadCrewRoster,
} from "../../../src/systems/vrm/vrm-crew-manifest";

describe("Crew Manifest", () => {
	it("default roster has 8 crew members", () => {
		expect(DEFAULT_CREW_ROSTER).toHaveLength(8);
	});

	it("default roster includes the main cast", () => {
		const ids = DEFAULT_CREW_ROSTER.map((c) => c.id);
		expect(ids).toContain("eli-wallace");
		expect(ids).toContain("nicholas-rush");
		expect(ids).toContain("everett-young");
		expect(ids).toContain("chloe-armstrong");
		expect(ids).toContain("matthew-scott");
		expect(ids).toContain("ronald-greer");
		expect(ids).toContain("tamara-johansen");
		expect(ids).toContain("camile-wray");
	});

	it("only Eli is marked as player", () => {
		const players = DEFAULT_CREW_ROSTER.filter((c) => c.isPlayer);
		expect(players).toHaveLength(1);
		expect(players[0].id).toBe("eli-wallace");
	});

	it("all characters have VRM asset paths", () => {
		for (const character of DEFAULT_CREW_ROSTER) {
			expect(character.vrmAsset).toMatch(/\.vrm$/);
			expect(character.vrmAsset.length).toBeGreaterThan(10);
		}
	});

	it("getPlayerManifest returns Eli", () => {
		expect(getPlayerManifest()?.id).toBe("eli-wallace");
	});

	it("getNpcManifests excludes Eli", () => {
		const npcs = getNpcManifests();
		expect(npcs.every((c) => !c.isPlayer)).toBe(true);
		expect(npcs).toHaveLength(7);
	});

	it("getCrewManifest retrieves by ID", () => {
		const rush = getCrewManifest("nicholas-rush");
		expect(rush).toBeDefined();
		expect(rush?.displayName).toBe("Dr. Nicholas Rush");
	});

	it("getCrewManifest returns undefined for unknown ID", () => {
		expect(getCrewManifest("daniel-jackson")).toBeUndefined();
	});

	it("expression profiles have valid intensity ranges", () => {
		for (const character of DEFAULT_CREW_ROSTER) {
			if (character.expressionProfile?.expressionIntensity !== undefined) {
				const intensity = character.expressionProfile.expressionIntensity;
				expect(intensity).toBeGreaterThanOrEqual(0);
				expect(intensity).toBeLessThanOrEqual(1);
			}
		}
	});

	it("Rush has lower expression intensity than Chloe", () => {
		const rush = getCrewManifest("nicholas-rush");
		const chloe = getCrewManifest("chloe-armstrong");
		expect(rush?.expressionProfile?.expressionIntensity).toBeLessThan(
			chloe?.expressionProfile?.expressionIntensity ?? 1
		);
	});
});

describe("Crew Roster Loading", () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it("falls back to defaults on fetch failure", async () => {
		vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network error")));
		const roster = await loadCrewRoster("/missing.json");
		expect(roster.length).toBeGreaterThan(0);
		expect(roster[0].id).toBe("eli-wallace");
	});

	it("falls back to defaults on non-array JSON", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: true,
			json: () => Promise.resolve({ notAnArray: true }),
		}));
		const roster = await loadCrewRoster("/bad.json");
		expect(roster.length).toBeGreaterThan(0);
	});

	it("parses valid roster JSON", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: true,
			json: () => Promise.resolve([
				{
					id: "test-char",
					displayName: "Test Character",
					vrmAsset: "/assets/characters/test/test.vrm",
					expressionProfile: {
						defaultExpression: "happy",
						expressionIntensity: 0.5,
					},
				},
			]),
		}));

		const roster = await loadCrewRoster("/test-roster.json");
		expect(roster).toHaveLength(1);
		expect(roster[0].id).toBe("test-char");
		expect(roster[0].expressionProfile?.defaultExpression).toBe("happy");
	});

	it("skips invalid entries in roster", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: true,
			json: () => Promise.resolve([
				{ id: "valid", vrmAsset: "/valid.vrm" },
				{ noId: true },
				"not an object",
				null,
				{ id: "also-valid", vrmAsset: "/also-valid.vrm" },
			]),
		}));

		const roster = await loadCrewRoster("/mixed.json");
		expect(roster).toHaveLength(2);
		expect(roster[0].id).toBe("valid");
		expect(roster[1].id).toBe("also-valid");
	});
});
