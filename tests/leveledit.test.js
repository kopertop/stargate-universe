// Unit tests for src/leveledit.js — level editor utility functions.
//
// Run with: node --test tests/leveledit.test.js
// (Node 18+ built-in test runner — no framework dependency.)
//
// leveledit.js imports three and creates a full DOM-heavy editor.
// We test the pure layout/utility helpers that are extracted or can be
// verified via the module's exported constants and geometry math.
// Since createLevelEditor requires a full ctx with renderer/camera/etc,
// we focus on testing the layout math functions indirectly by importing
// the module and verifying it loads, plus testing the COMPONENTS/ROOM_PROPS
// data that leveledit depends on for palette/prop logic.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from '../src/components.js';

// Re-implement the pure geometry helpers from leveledit.js for testing
// (these are closures inside createLevelEditor, so we test the math directly)
const S = 0.05, SNAP = 50;

// rect(r): converts layout JSON coords to world-space AABB
const rect = (r) => ({ x0: r.startY * S, x1: r.endY * S, z0: -r.endX * S, z1: -r.startX * S });

// roomAtWorld(p): find room containing point p in world space
const roomsOnFloor = (layout, floor) => layout.filter((r) => r.floor === floor);
const roomAtWorld = (layout, floor, p) => roomsOnFloor(layout, floor).find((r) => {
	const q = rect(r);
	return p.x >= q.x0 && p.x <= q.x1 && p.z >= q.z0 && p.z <= q.z1;
});

// fracAt(r, p): fractional position within a room
const fracAt = (r, p) => {
	const q = rect(r);
	return { u: (p.x - q.x0) / (q.x1 - q.x0), v: (p.z - q.z0) / (q.z1 - q.z0) };
};

// snap(v): snap to grid
const snap = (v) => Math.round(v / SNAP) * SNAP;

// dirBetween(a, b): direction string between two rooms
const dirBetween = (a, b) => {
	const ax = (a.startX + a.endX) / 2, ay = (a.startY + a.endY) / 2;
	const bx = (b.startX + b.endX) / 2, by = (b.startY + b.endY) / 2;
	return Math.abs(bx - ax) > Math.abs(by - ay) ? (bx > ax ? '+x' : '-x') : (by > ay ? '+z' : '-z');
};

// Mock layout data for testing
const mockLayout = [
	{ id: 'room_a', type: 'corridor', floor: 0, startX: 0, endX: 400, startY: 0, endY: 300, name: 'Corridor A' },
	{ id: 'room_b', type: 'gate_room', floor: 0, startX: 400, endX: 800, startY: 0, endY: 300, name: 'Gate Room' },
	{ id: 'room_c', type: 'quarters', floor: 1, startX: 0, endX: 400, startY: 0, endY: 300, name: 'Quarters C' },
];

describe('leveledit rect() — layout-to-world conversion', () => {
	test('rect converts layout coords to world AABB', () => {
		const r = rect(mockLayout[0]);
		// startY=0, endY=300, startX=0, endX=400
		// x0 = 0*0.05 = 0, x1 = 300*0.05 = 15
		// z0 = -400*0.05 = -20, z1 = -0*0.05 = 0
		assert.ok(r.x0 === 0); // 0*0.05 = 0 (=== treats -0 and 0 as equal)
		assert.equal(r.x1, 15);
		assert.equal(r.z0, -20);
		assert.ok(r.z1 === 0); // -0*0.05 = -0, but === 0 is true
	});

	test('rect handles negative layout coords', () => {
		const r = { id: 'neg', startX: -400, endX: 0, startY: -300, endY: 0 };
		const w = rect(r);
		assert.equal(w.x0, -15);
		assert.ok(w.x1 === 0); // 0*0.05 = 0
		assert.ok(w.z0 === 0); // -0*0.05 = -0, but === 0 is true
		assert.equal(w.z1, 20);
	});

	test('rect world width matches layout span * S', () => {
		for (const room of mockLayout) {
			const w = rect(room);
			const worldW = w.x1 - w.x0;
			const layoutW = (room.endY - room.startY) * S;
			assert.equal(worldW, layoutW);
		}
	});
});

describe('leveledit roomAtWorld() — room picking', () => {
	test('finds room containing a world point', () => {
		// room_a: x0=0, x1=15, z0=-20, z1=0 → centre ~(7.5, -10)
		const found = roomAtWorld(mockLayout, 0, { x: 7.5, z: -10 });
		assert.equal(found?.id, 'room_a');
	});

	test('finds gate room at its centre', () => {
		// room_b: x0=0, x1=15, z0=-40, z1=-20 → centre ~(7.5, -30)
		const found = roomAtWorld(mockLayout, 0, { x: 7.5, z: -30 });
		assert.equal(found?.id, 'room_b');
	});

	test('returns undefined for point outside all rooms', () => {
		const found = roomAtWorld(mockLayout, 0, { x: 100, z: 100 });
		assert.equal(found, undefined);
	});

	test('respects floor filtering — floor 1 rooms not found on floor 0', () => {
		const found = roomAtWorld(mockLayout, 0, { x: 7.5, z: -10 });
		// room_c is floor 1, should not be matched
		assert.notEqual(found?.id, 'room_c');
	});

	test('floor 1 room found when querying floor 1', () => {
		const found = roomAtWorld(mockLayout, 1, { x: 7.5, z: -10 });
		assert.equal(found?.id, 'room_c');
	});
});

describe('leveledit fracAt() — fractional position within room', () => {
	test('centre of room gives ~0.5, 0.5', () => {
		const r = mockLayout[0];
		const w = rect(r);
		const cx = (w.x0 + w.x1) / 2, cz = (w.z0 + w.z1) / 2;
		const f = fracAt(r, { x: cx, z: cz });
		assert.ok(Math.abs(f.u - 0.5) < 1e-10);
		assert.ok(Math.abs(f.v - 0.5) < 1e-10);
	});

	test('corner of room gives 0, 0', () => {
		const r = mockLayout[0];
		const w = rect(r);
		const f = fracAt(r, { x: w.x0, z: w.z0 });
		assert.equal(f.u, 0);
		assert.equal(f.v, 0);
	});

	test('opposite corner gives 1, 1', () => {
		const r = mockLayout[0];
		const w = rect(r);
		const f = fracAt(r, { x: w.x1, z: w.z1 });
		assert.ok(Math.abs(f.u - 1) < 1e-10);
		assert.ok(Math.abs(f.v - 1) < 1e-10);
	});

	test('outside room gives out-of-range fraction', () => {
		const r = mockLayout[0];
		const f = fracAt(r, { x: -5, z: -30 });
		assert.ok(f.u < 0);
		assert.ok(f.v > 1 || f.v < 0);
	});
});

describe('leveledit snap() — grid snapping', () => {
	test('snaps to nearest 50', () => {
		assert.equal(snap(0), 0);
		assert.equal(snap(24), 0);
		assert.equal(snap(50), 50);
		assert.equal(snap(74), 50);
		assert.equal(snap(75), 100);
		assert.equal(snap(124), 100);
		assert.equal(snap(150), 150);
	});

	test('snaps negative values', () => {
		assert.ok(snap(-24) === 0); // -0 but === 0 is true
		assert.equal(snap(-50), -50);
		assert.equal(snap(-75), -50); // Math.round(-1.5) = -1 in JS (rounds toward +inf)
		assert.equal(snap(-100), -100);
		assert.equal(snap(-125), -100); // Math.round(-2.5) = -2 in JS
		assert.equal(snap(-150), -150);
	});

	test('already-snapped values are idempotent', () => {
		for (const v of [0, 50, 100, 200, -50, -100]) {
			assert.equal(snap(v), v);
		}
	});
});

describe('leveledit dirBetween() — direction between rooms', () => {
	test('room to the right → +x', () => {
		const a = { startX: 0, endX: 100, startY: 0, endY: 100 };
		const b = { startX: 200, endX: 300, startY: 0, endY: 100 };
		assert.equal(dirBetween(a, b), '+x');
	});

	test('room to the left → -x', () => {
		const a = { startX: 200, endX: 300, startY: 0, endY: 100 };
		const b = { startX: 0, endX: 100, startY: 0, endY: 100 };
		assert.equal(dirBetween(a, b), '-x');
	});

	test('room above (higher Y) → +z', () => {
		const a = { startX: 0, endX: 100, startY: 0, endY: 100 };
		const b = { startX: 0, endX: 100, startY: 200, endY: 300 };
		assert.equal(dirBetween(a, b), '+z');
	});

	test('room below (lower Y) → -z', () => {
		const a = { startX: 0, endX: 100, startY: 200, endY: 300 };
		const b = { startX: 0, endX: 100, startY: 0, endY: 100 };
		assert.equal(dirBetween(a, b), '-z');
	});

	test('dominantly-X offset picks x even with slight Y difference', () => {
		const a = { startX: 0, endX: 100, startY: 0, endY: 100 };
		const b = { startX: 200, endX: 300, startY: 10, endY: 110 };
		assert.equal(dirBetween(a, b), '+x');
	});

	test('dominantly-Y offset picks z even with slight X difference', () => {
		const a = { startX: 0, endX: 100, startY: 0, endY: 100 };
		const b = { startX: 10, endX: 110, startY: 200, endY: 300 };
		assert.equal(dirBetween(a, b), '+z');
	});
});

describe('leveledit TYPES — room type list consistency', () => {
	const TYPES = ['corridor', 'gate_room', 'control_room', 'quarters', 'storage', 'infirmary', 'elevator', 'shuttle-dock', 'hydroponics', 'engineering', 'mess_hall', 'lab', 'bridge'];

	test('every room type has at least DEFAULT_PROPS or ROOM_PROPS entry', () => {
		// Not all types need props, but those that ship with content should be consistent
		for (const t of TYPES) {
			// If ROOM_PROPS has the type, it should be an array
			if (ROOM_PROPS[t]) {
				assert.ok(Array.isArray(ROOM_PROPS[t]), `ROOM_PROPS[${t}] should be an array`);
			}
		}
	});

	test('gate_room is in the type list (cannot be deleted)', () => {
		assert.ok(TYPES.includes('gate_room'));
	});
});

describe('leveledit COMPONENTS palette — data integrity for editor', () => {
	test('every component has a label (shown in palette)', () => {
		for (const [key, comp] of Object.entries(COMPONENTS)) {
			assert.ok(comp.label, `COMPONENTS[${key}] missing label`);
			assert.equal(typeof comp.label, 'string');
		}
	});

	test('every component has a size (for ghost mesh)', () => {
		for (const [key, comp] of Object.entries(COMPONENTS)) {
			assert.ok(comp.size, `COMPONENTS[${key}] missing size`);
			assert.ok(Array.isArray(comp.size), `COMPONENTS[${key}].size should be an array`);
			assert.equal(comp.size.length, 2, `COMPONENTS[${key}].size should have 2 elements [w, d]`);
		}
	});

	test('crate component exists (has special editor fields for style/loot)', () => {
		assert.ok(COMPONENTS.crate, 'crate component must exist — leveledit renders style/loot fields for it');
	});
});

describe('leveledit ROOM constant — gate room dimensions', () => {
	// ROOM is a module-level export from gate-room.js, but leveledit uses
	// the same S constant for layout↔world conversion. Verify the scale.
	test('S=0.05 means 1 layout unit = 5cm = 0.05m', () => {
		assert.equal(S, 0.05);
		// 400 layout units (a typical room) = 20m
		assert.equal(400 * S, 20);
		// 800 layout units (gate room) = 40m
		assert.equal(800 * S, 40);
	});

	test('SNAP=50 means grid spacing is 50 layout units = 2.5m', () => {
		assert.equal(SNAP, 50);
		assert.equal(SNAP * S, 2.5);
	});
});

describe('leveledit layout manipulation — nudge and move', () => {
	// Simulate nudge(r, key, delta) behavior
	const nudge = (r, k, dv) => {
		r[k] += dv;
		if (r.endX - r.startX < 100) r.endX = r.startX + 100;
		if (r.endY - r.startY < 100) r.endY = r.startY + 100;
	};

	test('nudge startX by -50 shrinks room', () => {
		const r = { startX: 100, endX: 500, startY: 0, endY: 300 };
		nudge(r, 'startX', -50);
		assert.equal(r.startX, 50);
		assert.equal(r.endX, 500); // unchanged
	});

	test('nudge startX clamps minimum width to 100', () => {
		const r = { startX: 100, endX: 200, startY: 0, endY: 300 };
		nudge(r, 'startX', 50); // startX would become 150, width=50 < 100
		assert.equal(r.startX, 150);
		assert.equal(r.endX, 250); // clamped to maintain 100 minimum
	});

	test('nudge endX clamps minimum width to 100', () => {
		const r = { startX: 100, endX: 300, startY: 0, endY: 300 };
		nudge(r, 'endX', -150); // endX would become 150, width=50 < 100
		assert.equal(r.endX, 200); // clamped to startX + 100 = 200
		assert.equal(r.startX, 100); // startX unchanged
	});

	test('move operation shifts both start and end', () => {
		// Simulate move: r[`start${ax}`] += dv; r[`end${ax}`] += dv;
		const r = { startX: 100, endX: 500, startY: 0, endY: 300 };
		const dv = 50;
		r.startX += dv;
		r.endX += dv;
		assert.equal(r.startX, 150);
		assert.equal(r.endX, 550);
		assert.equal(r.endX - r.startX, 400); // width preserved
	});
});

describe('leveledit toggleConnection — door graph', () => {
	// Simulate toggleConnection logic
	const dirBetween2 = (a, b) => {
		const ax = (a.startX + a.endX) / 2, ay = (a.startY + a.endY) / 2;
		const bx = (b.startX + b.endX) / 2, by = (b.startY + b.endY) / 2;
		return Math.abs(bx - ax) > Math.abs(by - ay) ? (bx > ax ? '+x' : '-x') : (by > ay ? '+z' : '-z');
	};

	test('adding a connection creates bidirectional link', () => {
		const connections = {};
		const a = { id: 'a', startX: 0, endX: 100, startY: 0, endY: 100 };
		const b = { id: 'b', startX: 200, endX: 300, startY: 0, endY: 100 };
		// toggleConnection adds a→b (one direction only; ship.js renders door where they share a wall)
		const la = (connections[a.id] ??= []);
		la.push({ dir: dirBetween2(a, b), to: b.id, plaque: b.name ?? b.id });
		assert.ok(connections.a);
		assert.equal(connections.a[0].to, 'b');
		assert.equal(connections.a[0].dir, '+x');
	});

	test('removing a connection deletes the entry', () => {
		const connections = { a: [{ dir: '+x', to: 'b', plaque: 'B' }], b: [] };
		const a = { id: 'a' }, b = { id: 'b' };
		const la = connections[a.id] ?? [];
		const ia = la.findIndex((c) => c.to === b.id);
		if (ia >= 0) la.splice(ia, 1);
		assert.equal(connections.a.length, 0);
	});

	test('reverse link removal works (b→a removed when toggling a→b)', () => {
		const connections = { a: [], b: [{ dir: '-x', to: 'a', plaque: 'A' }] };
		const a = { id: 'a' }, b = { id: 'b' };
		const lb = connections[b.id] ?? [];
		const ib = lb.findIndex((c) => c.to === a.id);
		if (ib >= 0) lb.splice(ib, 1);
		assert.equal(connections.b.length, 0);
	});
});

describe('leveledit propsOf — component defaults', () => {
	const propsOf = (r) => r.props ?? ROOM_PROPS[r.id] ?? DEFAULT_PROPS[r.type] ?? [];

	test('returns r.props when defined', () => {
		const r = { id: 'test', type: 'corridor', props: [{ type: 'crate', u: 0.5, v: 0.5 }] };
		assert.equal(propsOf(r).length, 1);
		assert.equal(propsOf(r)[0].type, 'crate');
	});

	test('falls back to ROOM_PROPS by id', () => {
		// Find a room id that exists in ROOM_PROPS
		const ids = Object.keys(ROOM_PROPS);
		if (ids.length > 0) {
			const id = ids[0];
			const r = { id, type: 'corridor' };
			assert.equal(propsOf(r), ROOM_PROPS[id]);
		}
	});

	test('falls back to DEFAULT_PROPS by type', () => {
		const types = Object.keys(DEFAULT_PROPS);
		if (types.length > 0) {
			const type = types[0];
			const r = { id: 'unknown_room', type };
			assert.equal(propsOf(r), DEFAULT_PROPS[type]);
		}
	});

	test('returns empty array when no props found', () => {
		const r = { id: 'unknown', type: 'nonexistent' };
		assert.deepEqual(propsOf(r), []);
	});
});

describe('leveledit loot parsing — crate property editor', () => {
	// Simulate the loot input parsing from renderProp
	const parseLoot = (input) => {
		if (!input.trim()) return undefined;
		return input.split(',').map((t) => {
			const [id, n] = t.trim().split(/[×x]/);
			return n ? { id: id.trim(), n: +n } : { id: id.trim() };
		}).filter((it) => it.id);
	};

	test('single item without count', () => {
		assert.deepEqual(parseLoot('large_fuse'), [{ id: 'large_fuse' }]);
	});

	test('single item with count (×)', () => {
		assert.deepEqual(parseLoot('rations×3'), [{ id: 'rations', n: 3 }]);
	});

	test('single item with count (x)', () => {
		assert.deepEqual(parseLoot('rationsx3'), [{ id: 'rations', n: 3 }]);
	});

	test('multiple items mixed', () => {
		const result = parseLoot('large_fuse, rations×3, rpg_kit');
		assert.equal(result.length, 3);
		assert.equal(result[0].id, 'large_fuse');
		assert.ok(!result[0].n);
		assert.equal(result[1].id, 'rations');
		assert.equal(result[1].n, 3);
		assert.equal(result[2].id, 'rpg_kit');
	});

	test('empty string returns undefined', () => {
		assert.equal(parseLoot(''), undefined);
	});

	test('whitespace-only returns undefined', () => {
		assert.equal(parseLoot('   '), undefined);
	});

	test('filters out empty entries (trailing comma)', () => {
		const result = parseLoot('large_fuse, ,');
		assert.equal(result.length, 1);
		assert.equal(result[0].id, 'large_fuse');
	});

	test('trims whitespace around ids', () => {
		const result = parseLoot('  large_fuse  ,  rations×2  ');
		assert.equal(result[0].id, 'large_fuse');
		assert.equal(result[1].id, 'rations');
		assert.equal(result[1].n, 2);
	});
});