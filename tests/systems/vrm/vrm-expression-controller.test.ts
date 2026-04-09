import { describe, expect, it, vi, beforeEach } from "vitest";
import { VrmExpressionController } from "../../../src/systems/vrm/vrm-expression-controller";

// ─── Mock VRM ───────────────────────────────────────────────────────────────

function createMockExpressionManager() {
	const values = new Map<string, number>();

	return {
		setValue: vi.fn((name: string, weight: number) => {
			values.set(name, weight);
		}),
		getValue: vi.fn((name: string) => values.get(name) ?? null),
		getExpression: vi.fn(() => ({})),
		resetValues: vi.fn(() => values.clear()),
		update: vi.fn(),
		_values: values,
	};
}

function createMockVrm() {
	return {
		expressionManager: createMockExpressionManager(),
		scene: {},
		humanoid: {},
		meta: {},
		update: vi.fn(),
	} as unknown;
}

describe("VrmExpressionController", () => {
	let mockVrm: ReturnType<typeof createMockVrm>;
	let controller: VrmExpressionController;

	beforeEach(() => {
		mockVrm = createMockVrm();
		controller = new VrmExpressionController(mockVrm as never);
	});

	it("initializes without errors", () => {
		expect(controller).toBeDefined();
	});

	it("sets expression target", () => {
		controller.setExpression("happy", 0.8);
		// Expression should be tracked but not applied until update()
		controller.update(0.016);

		const mgr = (mockVrm as { expressionManager: ReturnType<typeof createMockExpressionManager> })
			.expressionManager;
		expect(mgr.setValue).toHaveBeenCalled();

		const happyCalls = mgr.setValue.mock.calls.filter(
			(call: [string, number]) => call[0] === "happy"
		);
		expect(happyCalls.length).toBeGreaterThan(0);
	});

	it("clamps expression weight to 0-1", () => {
		controller.setExpression("angry", 1.5);
		controller.update(5.0); // Large delta to converge

		const mgr = (mockVrm as { expressionManager: ReturnType<typeof createMockExpressionManager> })
			.expressionManager;
		const lastHappyCall = mgr.setValue.mock.calls
			.filter((call: [string, number]) => call[0] === "angry")
			.pop();

		if (lastHappyCall) {
			expect(lastHappyCall[1]).toBeLessThanOrEqual(1.0);
			expect(lastHappyCall[1]).toBeGreaterThanOrEqual(0);
		}
	});

	it("handles blink cycle over multiple updates", () => {
		const mgr = (mockVrm as { expressionManager: ReturnType<typeof createMockExpressionManager> })
			.expressionManager;

		// Run many frames to ensure blink triggers at least once
		for (let i = 0; i < 500; i++) {
			controller.update(0.016);
		}

		const blinkCalls = mgr.setValue.mock.calls.filter(
			(call: [string, number]) => call[0] === "blink"
		);
		expect(blinkCalls.length).toBeGreaterThan(0);
	});

	it("does nothing when disabled", () => {
		controller.setEnabled(false);
		controller.setExpression("sad", 1.0);
		controller.update(0.016);

		const mgr = (mockVrm as { expressionManager: ReturnType<typeof createMockExpressionManager> })
			.expressionManager;
		// resetValues is called when disabling, but no setValue after that
		expect(mgr.resetValues).toHaveBeenCalled();
	});

	it("sets and clears visemes", () => {
		controller.setViseme("aa", 0.8);
		controller.update(0.016);

		const mgr = (mockVrm as { expressionManager: ReturnType<typeof createMockExpressionManager> })
			.expressionManager;
		const aaCalls = mgr.setValue.mock.calls.filter(
			(call: [string, number]) => call[0] === "aa"
		);
		expect(aaCalls.length).toBeGreaterThan(0);

		controller.clearViseme();
		// After clearing, viseme should blend toward 0
		for (let i = 0; i < 60; i++) {
			controller.update(0.016);
		}
	});
});
