/**
 * Unit tests for src/stargate.js — procedural Stargate factory and dialing sequence.
 *
 * Run with:  node --test tests/stargate.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * stargate.js imports three but the tested functions are on the returned Group's
 * userData — the import resolves from node_modules so the module loads cleanly in Node.
 *
 * Coverage: GATE constants, createStargate structure, dial(), incoming(), shutdown(),
 * reset(), tick() animation phases, ripple(), and edge cases.
 */
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { GATE, createStargate } from '../src/stargate.js';

const DT = 0.016; // ~60fps frame delta
const CHEV_INTERVAL = 0.55;

// Helper: advance the simulation by N seconds
function advance(g, seconds) {
	const ticks = Math.ceil(seconds / DT);
	for (let i = 0; i < ticks; i++) g.userData.tick(i * DT, DT);
	return ticks;
}

// Helper: collect events from onEvent callback
function makeCollector() {
	const events = [];
	const cb = (name, idx) => events.push({ name, idx });
	return { events, cb };
}

describe('GATE constants', () => {
	test('has rOuter, rInner, and chevrons', () => {
		assert.equal(typeof GATE.rOuter, 'number');
		assert.equal(typeof GATE.rInner, 'number');
		assert.equal(typeof GATE.chevrons, 'number');
	});

	test('rOuter > rInner (ring has width)', () => {
		assert.ok(GATE.rOuter > GATE.rInner, 'rOuter must exceed rInner');
	});

	test('chevrons is 9 (canonical Stargate)', () => {
		assert.equal(GATE.chevrons, 9);
	});
});

describe('createStargate', () => {
	let g;

	beforeEach(() => {
		g = createStargate();
	});

	test('returns a named Group', () => {
		assert.equal(g.name, 'stargate');
		assert.ok(g.children.length > 0, 'group must have children');
	});

	test('userData has all expected keys', () => {
		const expected = ['sockets', 'active', 'dial', 'incoming', 'shutdown', 'reset', 'colliders', 'tick', 'ripple'];
		for (const key of expected) {
			assert.ok(key in g.userData, `userData must have "${key}"`);
		}
	});

	test('starts inactive', () => {
		assert.equal(g.userData.active, false);
	});

	test('colliders initialized as empty array', () => {
		assert.deepEqual(g.userData.colliders, []);
	});

	test('sockets has all expected sub-objects', () => {
		const s = g.userData.sockets;
		assert.ok(s.horizon, 'must have horizon mesh');
		assert.ok(s.spill, 'must have spill light');
		assert.ok(s.chevronPivots, 'must have chevronPivots array');
		assert.ok(s.ringGroup, 'must have ringGroup');
		assert.ok(s.plumePivot, 'must have plumePivot');
	});

	test('horizon mesh is initially hidden', () => {
		assert.equal(g.userData.sockets.horizon.visible, false);
	});

	test('plumePivot is initially hidden', () => {
		assert.equal(g.userData.sockets.plumePivot.visible, false);
	});

	test('chevronPivots has 9 entries (one per chevron)', () => {
		assert.equal(g.userData.sockets.chevronPivots.length, GATE.chevrons);
	});

	test('horizon mesh is named eventHorizon', () => {
		assert.equal(g.userData.sockets.horizon.name, 'eventHorizon');
	});

	test('ringGroup is named ringGroup', () => {
		assert.equal(g.userData.sockets.ringGroup.name, 'ringGroup');
	});

	test('spill is a PointLight', () => {
		assert.equal(g.userData.sockets.spill.type, 'PointLight');
	});

	test('spill starts with intensity 0', () => {
		assert.equal(g.userData.sockets.spill.intensity, 0);
	});
});

describe('dial() — standard 7-chevron dialing sequence', () => {
	let g, col;

	beforeEach(() => {
		g = createStargate();
		col = makeCollector();
	});

	test('fires 7 chevron events in order', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		const chevs = col.events.filter(e => e.name === 'chevron');
		assert.equal(chevs.length, 7);
		assert.deepEqual(chevs.map(e => e.idx), [0, 1, 2, 3, 4, 5, 6]);
	});

	test('fires kawoosh event after all chevrons lock', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.ok(col.events.some(e => e.name === 'kawoosh'), 'must fire kawoosh');
	});

	test('fires active event after kawoosh animation completes', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.ok(col.events.some(e => e.name === 'active'), 'must fire active');
	});

	test('gate becomes active after full dial sequence', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.equal(g.userData.active, true);
	});

	test('no events fire before the first chevron threshold (0.4s)', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		advance(g, 0.35);
		assert.equal(col.events.length, 0, 'no events should fire before 0.4s');
	});

	test('event order is chevrons → kawoosh → active', () => {
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		const names = col.events.map(e => e.name);
		const chevronIdx = names.lastIndexOf('chevron');
		const kawooshIdx = names.indexOf('kawoosh');
		const activeIdx = names.indexOf('active');
		assert.ok(chevronIdx < kawooshIdx, 'all chevrons before kawoosh');
		assert.ok(kawooshIdx < activeIdx, 'kawoosh before active');
	});
});

describe('dial() — variable chevron counts', () => {
	let g, col;

	beforeEach(() => {
		g = createStargate();
		col = makeCollector();
	});

	test('3-chevron address fires exactly 3 chevron events', () => {
		g.userData.dial(col.cb, { chevronCount: 3 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 3 + 0.35;
		advance(g, kawooshAt + 2.0);
		const chevs = col.events.filter(e => e.name === 'chevron');
		assert.equal(chevs.length, 3);
	});

	test('9-chevron address fires all 9 chevrons', () => {
		g.userData.dial(col.cb, { chevronCount: 9 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 9 + 0.35;
		advance(g, kawooshAt + 2.0);
		const chevs = col.events.filter(e => e.name === 'chevron');
		assert.equal(chevs.length, 9);
	});

	test('default chevronCount (omitted) does not crash', () => {
		g.userData.dial(col.cb);
		advance(g, 10.0);
		assert.ok(col.events.length > 0, 'should fire some events');
	});
});

describe('incoming() — incoming wormhole (pre-locked chevrons)', () => {
	let g, col;

	beforeEach(() => {
		g = createStargate();
		col = makeCollector();
	});

	test('skips chevron locking and goes straight to kawoosh', () => {
		g.userData.incoming(col.cb, { chevronCount: 7 });
		const _kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		// incoming starts at _kawooshAt - 0.05, so only ~0.05s before kawoosh
		advance(g, 2.0);
		const chevs = col.events.filter(e => e.name === 'chevron');
		assert.equal(chevs.length, 0, 'incoming should not fire chevron events');
		assert.ok(col.events.some(e => e.name === 'kawoosh'), 'must fire kawoosh');
	});

	test('gate becomes active after incoming kawoosh', () => {
		g.userData.incoming(col.cb, { chevronCount: 7 });
		advance(g, 3.0);
		assert.equal(g.userData.active, true);
	});

	test('incoming with 3 chevrons works', () => {
		g.userData.incoming(col.cb, { chevronCount: 3 });
		advance(g, 3.0);
		assert.equal(g.userData.active, true);
	});
});

describe('shutdown() and reset()', () => {
	let g;

	beforeEach(() => {
		g = createStargate();
	});

	test('shutdown on inactive gate is a no-op', () => {
		g.userData.shutdown();
		assert.equal(g.userData.active, false);
	});

	test('shutdown on active gate deactivates it', () => {
		const col = makeCollector();
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.equal(g.userData.active, true);
		g.userData.shutdown();
		assert.equal(g.userData.active, false);
	});

	test('reset clears all visual state', () => {
		const col = makeCollector();
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.equal(g.userData.active, true);
		assert.equal(g.userData.sockets.horizon.visible, true);

		g.userData.reset();
		assert.equal(g.userData.active, false);
		assert.equal(g.userData.sockets.horizon.visible, false);
		assert.equal(g.userData.sockets.plumePivot.visible, false);
	});

	test('reset is idempotent (can be called multiple times)', () => {
		g.userData.reset();
		g.userData.reset();
		assert.equal(g.userData.active, false);
	});

	test('reset after shutdown works', () => {
		const col = makeCollector();
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		g.userData.shutdown();
		g.userData.reset();
		assert.equal(g.userData.active, false);
		assert.equal(g.userData.sockets.horizon.visible, false);
	});
});

describe('ripple()', () => {
	let g;

	beforeEach(() => {
		g = createStargate();
	});

	test('sets uRipple uniform to 1', () => {
		g.userData.ripple(1.0, 0.5);
		const u = g.userData.sockets.horizon.material.uniforms;
		assert.equal(u.uRipple.value, 1);
	});

	test('resets uRippleT to 0', () => {
		g.userData.ripple(1.0, 0.5);
		const u = g.userData.sockets.horizon.material.uniforms;
		assert.equal(u.uRippleT.value, 0);
	});

	test('normalizes position by rInner', () => {
		const lx = 1.2, ly = 0.6;
		g.userData.ripple(lx, ly);
		const u = g.userData.sockets.horizon.material.uniforms;
		assert.ok(Math.abs(u.uRipplePos.value.x - lx / GATE.rInner) < 1e-10);
		assert.ok(Math.abs(u.uRipplePos.value.y - ly / GATE.rInner) < 1e-10);
	});

	test('uRippleT accumulates during tick after ripple', () => {
		g.userData.ripple(1.0, 0.5);
		g.userData.tick(0.0, DT);
		g.userData.tick(DT, DT);
		const u = g.userData.sockets.horizon.material.uniforms;
		assert.ok(u.uRippleT.value > 0, 'uRippleT should increase over time');
		assert.ok(Math.abs(u.uRippleT.value - 2 * DT) < 1e-6);
	});
});

describe('tick() — animation state', () => {
	let g;

	beforeEach(() => {
		g = createStargate();
	});

	test('updates uTime uniform on every tick', () => {
		const u = g.userData.sockets.horizon.material.uniforms;
		const before = u.uTime.value;
		g.userData.tick(99.0, DT);
		assert.equal(u.uTime.value, 99.0);
		assert.notEqual(u.uTime.value, before);
	});

	test('spill intensity increases when gate is active', () => {
		const col = makeCollector();
		g.userData.dial(col.cb, { chevronCount: 7 });
		const kawooshAt = 0.4 + CHEV_INTERVAL * 7 + 0.35;
		advance(g, kawooshAt + 2.0);
		assert.equal(g.userData.active, true);
		// Now tick once more and check spill is non-zero
		g.userData.tick(10.0, DT);
		assert.ok(g.userData.sockets.spill.intensity > 0, 'spill should be lit when active');
	});

	test('spill intensity stays 0 when gate is inactive', () => {
		g.userData.tick(0.0, DT);
		g.userData.tick(DT, DT);
		assert.equal(g.userData.sockets.spill.intensity, 0);
	});

	test('ringGroup rotates during dialing', () => {
		const col = makeCollector();
		const before = g.userData.sockets.ringGroup.rotation.z;
		g.userData.dial(col.cb, { chevronCount: 7 });
		advance(g, 0.5); // during spin phase
		const after = g.userData.sockets.ringGroup.rotation.z;
		assert.notEqual(after, before, 'ring should have rotated during dial');
	});
});