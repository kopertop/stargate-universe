import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { getVrmConfig, loadVrmConfig } from "../../../src/systems/vrm/vrm-config";

describe("VRM Config", () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("returns default config before loading", () => {
		const config = getVrmConfig();
		expect(config.maxVisibleCrew).toBe(4);
		expect(config.springBone.enabled).toBe(true);
		expect(config.springBone.budgetMs).toBe(1.0);
		expect(config.expression.blendSpeed).toBe(0.3);
		expect(config.lod.nearDistance).toBe(5.0);
		expect(config.lod.midDistance).toBe(15.0);
		expect(config.loading.maxConcurrentLoads).toBe(2);
		expect(config.firstPerson.headFadeTransition).toBe(0.15);
		expect(config.quality.adaptiveThresholdFps).toBe(30.0);
	});

	it("falls back to defaults on fetch failure", async () => {
		vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network error")));

		const config = await loadVrmConfig("/nonexistent.json");
		expect(config.maxVisibleCrew).toBe(4);
		expect(config.springBone.enabled).toBe(true);
	});

	it("falls back to defaults on non-200 response", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: false,
			status: 404,
		}));

		const config = await loadVrmConfig("/missing.json");
		expect(config.maxVisibleCrew).toBe(4);
	});

	it("merges partial config with defaults", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: true,
			json: () => Promise.resolve({
				maxVisibleCrew: 8,
				springBone: { enabled: false },
			}),
		}));

		const config = await loadVrmConfig("/test.json");
		expect(config.maxVisibleCrew).toBe(8);
		expect(config.springBone.enabled).toBe(false);
		// Non-overridden values should use defaults
		expect(config.springBone.budgetMs).toBe(1.0);
		expect(config.expression.blendSpeed).toBe(0.3);
	});

	it("ignores invalid types in loaded config", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
			ok: true,
			json: () => Promise.resolve({
				maxVisibleCrew: "not a number",
				springBone: { enabled: 42 },
			}),
		}));

		const config = await loadVrmConfig("/test.json");
		expect(config.maxVisibleCrew).toBe(4); // default, because string is invalid
		expect(config.springBone.enabled).toBe(true); // default, because 42 is not boolean
	});
});
