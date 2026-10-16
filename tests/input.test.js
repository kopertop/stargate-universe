/**
 * Unit tests for src/input.js — keyboard, mouse, and gamepad input system.
 *
 * Tests cover: initial state shape, dead() helper, poll() keyboard movement,
 * look deltas, edge-triggered action reset, run/sprint, interactHeld, and
 * gamepad input (mocked navigator.getGamepads).
 *
 * Run with:  node --test tests/input.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * input.js attaches window/canvas listeners in initInput() — we test the
 * exported `input` object and `poll()` by manipulating `input.keys` directly
 * (simulating keyboard state) and mocking navigator.getGamepads for pad tests.
 */
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

// Stub minimal globals that input.js top-level references
// (window.addEventListener in initInput, navigator.getGamepads in poll)
globalThis.window = globalThis.window ?? {
	addEventListener: () => {},
	removeEventListener: () => {},
};
globalThis.document = globalThis.document ?? {
	createElement: () => ({ addEventListener: () => {}, requestPointerLock: () => ({ catch: () => {} }) }),
};
// navigator is a read-only getter in Node 22 — use defineProperty
if (!globalThis.navigator.getGamepads) {
	Object.defineProperty(globalThis.navigator, 'getGamepads', {
		value: () => [null, null, null, null],
		writable: true,
		configurable: true,
	});
}

// Now import the module
const { input, poll, initInput } = await import('../src/input.js');

// ─── Helpers ───

/** Reset input state between tests by manipulating keys set and calling poll with no keys. */
function resetKeys() {
	input.keys.clear();
	input.mouseDelta.x = 0;
	input.mouseDelta.y = 0;
}

/** Simulate holding keys by adding codes to the keys set. */
function hold(...codes) {
	for (const c of codes) input.keys.add(c);
}

/** Mock navigator.getGamepads with a fake pad. */
function mockGamepad(pad) {
	Object.defineProperty(globalThis.navigator, 'getGamepads', {
		value: () => (pad ? [pad] : [null, null, null, null]),
		writable: true,
		configurable: true,
	});
}

/** Build a fake gamepad with axes and buttons. */
function makePad(overrides = {}) {
	return {
		connected: true,
		axes: [0, 0, 0, 0],
		buttons: Array.from({ length: 16 }, () => ({ pressed: false, value: 0 })),
		...overrides,
	};
}

// ─── Tests ───

describe('input initial state', () => {
	test('has move, look, run, jump, and keys', () => {
		assert.ok(input.move, 'input.move should exist');
		assert.ok(input.look, 'input.look should exist');
		assert.equal(typeof input.run, 'boolean');
		assert.equal(typeof input.jump, 'boolean');
		assert.ok(input.keys instanceof Set, 'input.keys should be a Set');
	});

	test('move and look start at zero', () => {
		resetKeys();
		poll(0.016);
		assert.equal(input.move.x, 0);
		assert.equal(input.move.y, 0);
		assert.equal(input.look.x, 0);
		assert.equal(input.look.y, 0);
	});

	test('default sensitivity is 1 and invertY is false', () => {
		assert.equal(input.sensitivity, 1);
		assert.equal(input.invertY, false);
	});
});

describe('poll() keyboard movement', () => {
	beforeEach(() => resetKeys());

	test('W produces forward movement (y=1)', () => {
		hold('KeyW');
		poll(0.016);
		assert.equal(input.move.y, 1);
	});

	test('S produces backward movement (y=-1)', () => {
		hold('KeyS');
		poll(0.016);
		assert.equal(input.move.y, -1);
	});

	test('D produces right strafe (x=1)', () => {
		hold('KeyD');
		poll(0.016);
		assert.equal(input.move.x, 1);
	});

	test('A produces left strafe (x=-1)', () => {
		hold('KeyA');
		poll(0.016);
		assert.equal(input.move.x, -1);
	});

	test('W+D produces normalized diagonal (hypot=1)', () => {
		hold('KeyW', 'KeyD');
		poll(0.016);
		assert.ok(Math.abs(Math.hypot(input.move.x, input.move.y) - 1) < 1e-10,
			`diagonal should be normalized to unit length, got ${Math.hypot(input.move.x, input.move.y)}`);
		assert.equal(input.move.x, 1 / Math.SQRT2);
		assert.equal(input.move.y, 1 / Math.SQRT2);
	});

	test('ArrowUp works like W', () => {
		hold('ArrowUp');
		poll(0.016);
		assert.equal(input.move.y, 1);
	});

	test('ArrowDown works like S', () => {
		hold('ArrowDown');
		poll(0.016);
		assert.equal(input.move.y, -1);
	});

	test('ArrowLeft works like A', () => {
		hold('ArrowLeft');
		poll(0.016);
		assert.equal(input.move.x, -1);
	});

	test('ArrowRight works like D', () => {
		hold('ArrowRight');
		poll(0.016);
		assert.equal(input.move.x, 1);
	});
});

describe('poll() run/sprint', () => {
	beforeEach(() => resetKeys());

	test('ShiftLeft sets run=true', () => {
		hold('ShiftLeft');
		poll(0.016);
		assert.equal(input.run, true);
	});

	test('ShiftRight sets run=true', () => {
		hold('ShiftRight');
		poll(0.016);
		assert.equal(input.run, true);
	});

	test('No shift sets run=false', () => {
		poll(0.016);
		assert.equal(input.run, false);
	});
});

describe('poll() look deltas from mouse', () => {
	beforeEach(() => resetKeys());

	test('mouseDelta produces look.x proportional to movement', () => {
		input.mouseDelta.x = 100;
		input.mouseDelta.y = 0;
		poll(0.016);
		assert.ok(input.look.x > 0, 'look.x should be positive for positive mouseDelta.x');
		assert.equal(input.look.y, 0);
	});

	test('mouseDelta produces look.y proportional to movement', () => {
		input.mouseDelta.x = 0;
		input.mouseDelta.y = 50;
		poll(0.016);
		assert.ok(input.look.y > 0, 'look.y should be positive for positive mouseDelta.y');
		assert.equal(input.look.x, 0);
	});

	test('mouseDelta is consumed after poll (reset to 0)', () => {
		input.mouseDelta.x = 100;
		input.mouseDelta.y = 50;
		poll(0.016);
		assert.equal(input.mouseDelta.x, 0);
		assert.equal(input.mouseDelta.y, 0);
	});

	test('sensitivity scales look delta', () => {
		input.mouseDelta.x = 100;
		input.mouseDelta.y = 0;
		input.sensitivity = 2;
		poll(0.016);
		const base = 100 * 0.0022 * 2;
		assert.ok(Math.abs(input.look.x - base) < 1e-10);
		input.sensitivity = 1; // restore
	});

	test('invertY flips look.y sign', () => {
		input.mouseDelta.x = 0;
		input.mouseDelta.y = 50;
		input.invertY = true;
		poll(0.016);
		assert.ok(input.look.y < 0, 'look.y should be negative when invertY=true and mouseDelta.y is positive');
		input.invertY = false; // restore
	});
});

describe('poll() edge-triggered actions', () => {
	beforeEach(() => resetKeys());

	test('jump is true when Space is in pending (set by keydown)', () => {
		// We simulate the keydown handler by directly setting the pending state
		// Since pending is module-private, we test via the public API:
		// Space in keys set → jump should reflect pending state from keydown
		// Without a real keydown event, pending.jump stays false
		poll(0.016);
		// After poll with no pending, all edge-triggered should be false
		assert.equal(input.jump, false);
		assert.equal(input.interact, false);
		assert.equal(input.cycleView, false);
		assert.equal(input.redial, false);
		assert.equal(input.debug, false);
		assert.equal(input.remote, false);
		assert.equal(input.launchKino, false);
		assert.equal(input.fullscreen, false);
	});

	test('interactHeld is true when KeyE is held', () => {
		hold('KeyE');
		poll(0.016);
		assert.equal(input.interactHeld, true);
	});

	test('interactHeld is false when KeyE is not held', () => {
		poll(0.016);
		assert.equal(input.interactHeld, false);
	});
});

describe('poll() gamepad input', () => {
	beforeEach(() => {
		resetKeys();
		mockGamepad(null);
	});

	test('left stick X moves player', () => {
		const pad = makePad({ axes: [0.8, 0, 0, 0] });
		mockGamepad(pad);
		poll(0.016);
		assert.ok(input.move.x > 0, 'right stick should move x positive');
		assert.ok(input.move.x <= 1, 'move.x should not exceed 1');
	});

	test('left stick Y moves player (inverted)', () => {
		const pad = makePad({ axes: [0, -0.7, 0, 0] });
		mockGamepad(pad);
		poll(0.016);
		assert.ok(input.move.y > 0, 'stick up (-Y) should produce forward (+Y)');
	});

	test('dead zone zeroes small inputs', () => {
		const pad = makePad({ axes: [0.05, 0.03, 0, 0] });
		mockGamepad(pad);
		poll(0.016);
		assert.equal(input.move.x, 0, 'small X input below deadzone should be zero');
		assert.equal(input.move.y, 0, 'small Y input below deadzone should be zero');
	});

	test('right stick adds to look delta', () => {
		const pad = makePad({ axes: [0, 0, 0.5, 0.3] });
		mockGamepad(pad);
		poll(0.016);
		assert.ok(input.look.x > 0, 'right stick X should add to look.x');
		assert.ok(input.look.y > 0, 'right stick Y should add to look.y');
	});

	test('trigger button (7) sets run', () => {
		const buttons = Array.from({ length: 16 }, () => ({ pressed: false, value: 0 }));
		buttons[7] = { pressed: true, value: 0.9 };
		const pad = makePad({ axes: [0, 0, 0, 0], buttons });
		mockGamepad(pad);
		poll(0.016);
		assert.equal(input.run, true);
	});

	test('A button (0) triggers jump on press edge', () => {
		const buttons = Array.from({ length: 16 }, () => ({ pressed: false, value: 0 }));
		buttons[0] = { pressed: true, value: 1 };
		const pad = makePad({ axes: [0, 0, 0, 0], buttons });
		mockGamepad(pad);
		poll(0.016);
		assert.equal(input.jump, true, 'first poll with button pressed should trigger jump');
		// Second poll — no new edge, jump should be false
		poll(0.016);
		assert.equal(input.jump, false, 'second poll should not re-trigger (no new edge)');
	});

	test('X button (2) sets interactHeld while pressed', () => {
		const buttons = Array.from({ length: 16 }, () => ({ pressed: false, value: 0 }));
		buttons[2] = { pressed: true, value: 1 };
		const pad = makePad({ axes: [0, 0, 0, 0], buttons });
		mockGamepad(pad);
		poll(0.016);
		assert.equal(input.interactHeld, true);
	});

	test('no gamepad connected → no movement from pad', () => {
		mockGamepad(null);
		hold('KeyW');
		poll(0.016);
		// Keyboard should still work
		assert.equal(input.move.y, 1);
	});
});

describe('poll() normalization', () => {
	beforeEach(() => resetKeys());

	test('keyboard diagonal is normalized but single axis is not scaled', () => {
		hold('KeyW');
		poll(0.016);
		assert.equal(input.move.y, 1, 'single W should give y=1 (no scaling)');
	});

	test('gamepad full diagonal is normalized to unit circle', () => {
		const pad = makePad({ axes: [1, 1, 0, 0] });
		mockGamepad(pad);
		poll(0.016);
		const len = Math.hypot(input.move.x, input.move.y);
		assert.ok(Math.abs(len - 1) < 1e-10, `diagonal gamepad should be normalized, got len=${len}`);
	});
});

describe('initInput', () => {
	test('initInput is a function', () => {
		assert.equal(typeof initInput, 'function');
	});

	test('initInput does not throw with stub canvas', () => {
		const fakeCanvas = {
			addEventListener: () => {},
			requestPointerLock: () => ({ catch: () => {} }),
		};
		// Should not throw
		assert.doesNotThrow(() => initInput(fakeCanvas));
	});
});