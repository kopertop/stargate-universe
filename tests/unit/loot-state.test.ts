import { beforeEach, describe, expect, it } from "vitest";
import {
	deserializeLootState,
	isLootContainerOpened,
	openLootContainer,
	registerLootContainer,
	resetLootState,
	serializeLootState,
} from "../../src/systems/loot-state";
import { deserialize as deserializeResources, getResource } from "../../src/systems/resources";

describe("LootState", () => {
	beforeEach(() => {
		resetLootState();
		deserializeResources({
			resources: {
				"ship-parts": 0,
				water: 0,
				food: 0,
				lime: 0,
			},
		});
	});

	it("opens a registered container once and grants its resources", () => {
		registerLootContainer({
			id: "gate-room:crate-1",
			source: "gate-room",
			contents: { "ship-parts": 8, water: 2 },
		});

		const first = openLootContainer({
			id: "gate-room:crate-1",
			source: "gate-room",
			contents: { "ship-parts": 8, water: 2 },
		});
		const second = openLootContainer({
			id: "gate-room:crate-1",
			source: "gate-room",
			contents: { "ship-parts": 8, water: 2 },
		});

		expect(first.status).toBe("opened");
		expect(second.status).toBe("already-opened");
		expect(getResource("ship-parts")).toBe(8);
		expect(getResource("water")).toBe(2);
	});

	it("round-trips opened state through save data", () => {
		openLootContainer({
			id: "corridor:crate-2",
			source: "corridor",
			contents: { "ship-parts": 5 },
		});
		const snapshot = serializeLootState();

		resetLootState();
		expect(isLootContainerOpened("corridor:crate-2")).toBe(false);

		deserializeLootState(snapshot);
		expect(isLootContainerOpened("corridor:crate-2")).toBe(true);
	});
});
