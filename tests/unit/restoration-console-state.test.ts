import { afterEach, describe, expect, it } from "vitest";
import {
	buildConsoleSnapshot,
	requestConsoleRepair,
} from "../../src/systems/restoration-console-state";
import { getGameSession, resetGameSessionForTests } from "../../src/systems/game-session";
import { getResource } from "../../src/systems/resources";

describe("RestorationConsoleState", () => {
	afterEach(() => {
		resetGameSessionForTests();
	});

	it("derives system, resource, crew, and repair rows from the shared session", () => {
		const { shipState } = getGameSession();
		shipState.addSection({
			id: "gate-room",
			discovered: true,
			accessible: true,
			atmosphere: 0.8,
			powerLevel: 0.6,
			structuralIntegrity: 0.9,
			accessState: "explored",
			subsystems: [],
		});
		shipState.addSubsystem({
			id: "gate-room:test-conduit",
			type: "conduit",
			sectionId: "gate-room",
			condition: 0.25,
			repairCost: 2,
			functionalThreshold: 0.2,
		});

		const snapshot = buildConsoleSnapshot("overview");

		expect(snapshot.systems.length).toBeGreaterThan(0);
		expect(snapshot.resources["ship-parts"]).toBe(10);
		expect(snapshot.crew.map((member) => member.id)).toContain("dr-rush");
		expect(snapshot.repairs.some((repair) => repair.subsystemId === "gate-room:test-conduit")).toBe(true);
	});

	it("repairs through the shared ship state and consumes ship parts", () => {
		const { shipState } = getGameSession();
		shipState.addSection({
			id: "gate-room",
			discovered: true,
			accessible: true,
			atmosphere: 0.8,
			powerLevel: 0.6,
			structuralIntegrity: 0.9,
			accessState: "explored",
			subsystems: [],
		});
		shipState.addSubsystem({
			id: "gate-room:test-panel",
			type: "console",
			sectionId: "gate-room",
			condition: 0.5,
			repairCost: 3,
			functionalThreshold: 0.2,
		});

		const repaired = requestConsoleRepair("gate-room:test-panel");

		expect(repaired).toBe(true);
		expect(getResource("ship-parts")).toBe(7);
		expect(shipState.getSubsystem("gate-room:test-panel")?.condition).toBeGreaterThan(0.5);
	});
});
