import { describe, expect, it } from "vitest";
import { resolveNearestInteractionTarget } from "../../src/systems/interaction-targets";

describe("resolveNearestInteractionTarget", () => {
	it("returns the nearest target inside radius", () => {
		const result = resolveNearestInteractionTarget([
			{ id: "crate-far", type: "crate", position: { x: 4, y: 0, z: 0 }, radius: 5 },
			{ id: "crate-near", type: "crate", position: { x: 1, y: 0, z: 0 }, radius: 5 },
		], { x: 0, y: 0, z: 0 });

		expect(result?.target.id).toBe("crate-near");
		expect(result?.distance).toBe(1);
	});

	it("uses priority to break interaction conflicts", () => {
		const result = resolveNearestInteractionTarget([
			{ id: "crate", type: "crate", position: { x: 1, y: 0, z: 0 }, radius: 3, priority: 1 },
			{ id: "rush", type: "npc", position: { x: 1.5, y: 0, z: 0 }, radius: 3, priority: 5 },
		], { x: 0, y: 0, z: 0 });

		expect(result?.target.id).toBe("rush");
	});

	it("ignores disabled and out-of-range targets", () => {
		const result = resolveNearestInteractionTarget([
			{ id: "disabled", type: "crate", position: { x: 0.5, y: 0, z: 0 }, disabled: true },
			{ id: "far", type: "console", position: { x: 8, y: 0, z: 0 }, radius: 2 },
		], { x: 0, y: 0, z: 0 });

		expect(result).toBeNull();
	});
});
