import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createTimerSystem } from "../../src/systems/timer-system";
import { on } from "../../src/systems/event-bus";

describe("TimerSystem", () => {
	let unsubs: Array<() => void>;

	beforeEach(() => {
		unsubs = [];
	});

	afterEach(() => {
		for (const unsub of unsubs) unsub();
	});

	it("ticks running timers and emits threshold warnings once", () => {
		const timers = createTimerSystem();
		const warnings: number[] = [];
		unsubs.push(on("timer:planet:warning", ({ remaining }) => warnings.push(remaining)));

		timers.createTimer({
			id: "air-crisis:co2",
			durationSeconds: 30,
			tags: ["life-support"],
			visible: true,
			warnings: [{ thresholdSeconds: 10, event: "timer:planet:warning" }],
		});

		timers.tick(19);
		expect(warnings).toEqual([]);
		timers.tick(1);
		timers.tick(1);

		expect(warnings).toEqual([10]);
		expect(timers.getTimer("air-crisis:co2")?.remainingSeconds).toBe(9);
	});

	it("emits completion events and serializes state", () => {
		const timers = createTimerSystem();
		let expired = 0;
		unsubs.push(on("timer:planet:expired", () => { expired++; }));

		timers.createTimer({
			id: "gate-window",
			durationSeconds: 2,
			completionEvent: "timer:planet:expired",
		});
		timers.tick(3);

		const snapshot = timers.serialize();
		expect(expired).toBe(1);
		expect(snapshot.timers[0].state).toBe("expired");

		const restored = createTimerSystem();
		restored.deserialize(snapshot);
		expect(restored.getTimer("gate-window")?.state).toBe("expired");
	});

	it("halts, resumes, and cancels timers without losing remaining time", () => {
		const timers = createTimerSystem();
		timers.createTimer({ id: "ftl-cooldown", durationSeconds: 60 });
		timers.tick(10);
		timers.haltTimer("ftl-cooldown");
		timers.tick(10);
		expect(timers.getTimer("ftl-cooldown")?.remainingSeconds).toBe(50);

		timers.resumeTimer("ftl-cooldown");
		timers.tick(5);
		expect(timers.getTimer("ftl-cooldown")?.remainingSeconds).toBe(45);

		timers.cancelTimer("ftl-cooldown");
		expect(timers.getTimer("ftl-cooldown")?.state).toBe("cancelled");
	});
});
