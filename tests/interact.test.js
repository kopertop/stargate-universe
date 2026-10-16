/**
 * Unit tests for src/interact.js — proximity interactable system.
 *
 * Run with:  node --test tests/interact.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * interact.js imports three but the functions we test
 * (register, unregister, update) work in Node without a DOM.
 * THREE.Vector3.copy() accepts any {x,y,z} object, and
 * distanceTo() reads .x/.y/.z from the argument, so plain
 * objects work as positions.
 */
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as interact from '../src/interact.js';

describe('interact — register / unregister', () => {
	beforeEach(() => {
		// Clear the internal list by unregistering everything we can
		// The list is module-private, so we unregister known IDs
		interact.unregister('__test_a');
		interact.unregister('__test_b');
	});

	test('register adds an interactable and returns the def', () => {
		const def = { id: '__test_a', position: { x: 0, y: 0, z: 0 }, prompt: () => 'hello' };
		const ret = interact.register(def);
		assert.equal(ret, def);
		interact.unregister('__test_a');
	});

	test('unregister removes an interactable', () => {
		interact.register({ id: '__test_a', position: { x: 0, y: 0, z: 0 }, prompt: () => 'hi' });
		interact.unregister('__test_a');
		// After unregister, update should not find it
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r, null);
	});

	test('unregister with unknown id is a no-op', () => {
		interact.unregister('__nonexistent__');
		// Should not throw
		assert.ok(true);
	});
});

describe('interact — update proximity detection', () => {
	beforeEach(() => {
		interact.unregister('__test_near');
		interact.unregister('__test_far');
		interact.unregister('__test_world');
	});

	afterEach(() => {
		interact.unregister('__test_near');
		interact.unregister('__test_far');
		interact.unregister('__test_world');
	});

	test('update returns null when no interactables registered', () => {
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r, null);
	});

	test('update finds nearest interactable within radius', () => {
		interact.register({
			id: '__test_near',
			position: { x: 1, y: 0, z: 0 },
			prompt: () => 'press E',
			radius: 3,
		});
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.ok(r);
		assert.equal(r.prompt, 'press E');
		interact.unregister('__test_near');
	});

	test('update ignores interactables outside radius', () => {
		interact.register({
			id: '__test_far',
			position: { x: 10, y: 0, z: 0 },
			prompt: () => 'too far',
			radius: 2,
		});
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r, null);
		interact.unregister('__test_far');
	});

	test('update ignores interactables with falsy prompt', () => {
		interact.register({
			id: '__test_near',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => '',
			radius: 3,
		});
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r, null);
		interact.unregister('__test_near');
	});

	test('update picks closest when multiple are in range', () => {
		interact.register({
			id: '__test_near',
			position: { x: 1, y: 0, z: 0 },
			prompt: () => 'near',
			radius: 5,
		});
		interact.register({
			id: '__test_far',
			position: { x: 3, y: 0, z: 0 },
			prompt: () => 'far',
			radius: 5,
		});
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r.prompt, 'near');
		interact.unregister('__test_near');
		interact.unregister('__test_far');
	});

	test('update skips interactables in a different world', () => {
		interact.register({
			id: '__test_world',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => 'other world',
			radius: 3,
			world: 'planet',
		});
		// Player is in 'ship' world — should not see planet interactable
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false, 'ship');
		assert.equal(r, null);
		// Player is in 'planet' world — should see it
		const r2 = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false, 'planet');
		assert.ok(r2);
		assert.equal(r2.prompt, 'other world');
		interact.unregister('__test_world');
	});
});

describe('interact — action triggering', () => {
	beforeEach(() => {
		interact.unregister('__test_act');
	});

	afterEach(() => {
		interact.unregister('__test_act');
	});

	test('pressed triggers action on instant interactable', () => {
		let fired = 0;
		interact.register({
			id: '__test_act',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => 'do thing',
			radius: 3,
			action: () => { fired++; },
		});
		// First update to set current
		interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		// Pressed → action fires
		interact.update(0.016, { x: 0, y: 0, z: 0 }, true, false);
		assert.equal(fired, 1);
	});

	test('pressed does NOT trigger when no interactable in range', () => {
		let fired = 0;
		interact.register({
			id: '__test_act',
			position: { x: 100, y: 0, z: 0 },
			prompt: () => 'far',
			radius: 2,
			action: () => { fired++; },
		});
		interact.update(0.016, { x: 0, y: 0, z: 0 }, true, false);
		assert.equal(fired, 0);
		interact.unregister('__test_act');
	});
});

describe('interact — hold-to-act', () => {
	beforeEach(() => {
		interact.unregister('__test_hold');
	});

	afterEach(() => {
		interact.unregister('__test_hold');
	});

	test('hold accumulates progress and fires at 1.0', () => {
		let fired = 0;
		interact.register({
			id: '__test_hold',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => 'hold E',
			radius: 3,
			hold: () => 2, // 2 seconds to complete
			action: () => { fired++; },
		});
		// Set current
		interact.update(0, { x: 0, y: 0, z: 0 }, false, false);
		// Hold for 1s (dt=1, held=true) → progress = 0.5
		let r = interact.update(1, { x: 0, y: 0, z: 0 }, false, true);
		assert.equal(r.progress, 0.5);
		assert.equal(r.hold, true);
		assert.equal(fired, 0);
		// Hold for another 1s → progress = 1.0 → action fires, progress resets
		r = interact.update(1, { x: 0, y: 0, z: 0 }, false, true);
		assert.equal(fired, 1);
		assert.equal(r.progress, 0); // reset after firing
	});

	test('progress decays when not held', () => {
		interact.register({
			id: '__test_hold',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => 'hold E',
			radius: 3,
			hold: () => 2,
			action: () => {},
		});
		// Set current + build some progress
		interact.update(0, { x: 0, y: 0, z: 0 }, false, false);
		interact.update(1, { x: 0, y: 0, z: 0 }, false, true); // progress = 0.5
		// Not held → progress decays by dt*2 = 0.2
		const r = interact.update(0.1, { x: 0, y: 0, z: 0 }, false, false);
		assert.ok(r.progress < 0.5, `progress should decay, got ${r.progress}`);
	});

	test('hold returns null progress for instant interactables', () => {
		interact.register({
			id: '__test_hold',
			position: { x: 0, y: 0, z: 0 },
			prompt: () => 'instant',
			radius: 3,
			action: () => {},
		});
		interact.update(0, { x: 0, y: 0, z: 0 }, false, false);
		const r = interact.update(0.016, { x: 0, y: 0, z: 0 }, false, false);
		assert.equal(r.progress, null);
		assert.equal(r.hold, false);
	});
});

