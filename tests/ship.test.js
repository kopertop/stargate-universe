/**
 * Unit tests for src/ship.js — pure layout functions (roomsFromLayout, doorsFromLayout, elevatorsFromLayout).
 *
 * Run with:  node --test tests/ship.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * These functions take JSON layout data and return computed world coordinates,
 * door definitions, and elevator links. They are pure logic with no DOM side effects.
 * ship.js imports three but the tested functions don't use it — the import resolves
 * from node_modules so the module loads cleanly in Node.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { roomsFromLayout, doorsFromLayout, elevatorsFromLayout, DECK_H } from '../src/ship.js';

const _SCALE = 0.05; // used in comment assertions; kept for documentation

// Minimal layout: two adjacent rooms sharing an x-edge, both on floor 0
const TWO_ROOMS = [
	{ id: 'room_a', name: 'Room A', type: 'generic', startX: 0, startY: 0, endX: 400, endY: 200 },
	{ id: 'room_b', name: 'Room B', type: 'generic', startX: 0, startY: 200, endX: 400, endY: 400 },
];
const TWO_CONNECTIONS = { room_a: [{ to: 'room_b', dir: 'door' }] };

describe('roomsFromLayout', () => {
	test('maps JSON coordinates to world space with SCALE=0.05', () => {
		const rooms = roomsFromLayout(TWO_ROOMS);
		assert.equal(rooms.length, 2);

		const a = rooms[0];
		assert.equal(a.id, 'room_a');
		assert.equal(a.name, 'Room A');
		assert.equal(a.type, 'generic');
		assert.equal(a.key, false);
		// startY * SCALE = 0 * 0.05 = 0
		assert.equal(a.x0, 0);
		// endY * SCALE = 200 * 0.05 = 10
		assert.equal(a.x1, 10);
		// -endX * SCALE = -400 * 0.05 = -20
		assert.equal(a.z0, -20);
		// -startX * SCALE = -0 * 0.05 = -0 (JS -0); normalize with Object.is
		assert.equal(Object.is(a.z1, -0) || a.z1 === 0, true);
	});

	test('defaults floor to 0 and computes y0 = floor * DECK_H', () => {
		const rooms = roomsFromLayout([{ id: 'r', name: 'R', type: 'generic', startX: 0, startY: 0, endX: 100, endY: 100 }]);
		assert.equal(rooms[0].floor, 0);
		assert.equal(rooms[0].y0, 0);
	});

	test('respects explicit floor value', () => {
		const rooms = roomsFromLayout([{ id: 'r', name: 'R', type: 'generic', floor: 2, startX: 0, startY: 0, endX: 100, endY: 100 }]);
		assert.equal(rooms[0].floor, 2);
		assert.equal(rooms[0].y0, 2 * DECK_H);
	});

	test('marks key_room as key=true', () => {
		const rooms = roomsFromLayout([{ id: 'r', name: 'R', type: 'generic', key_room: true, startX: 0, startY: 0, endX: 100, endY: 100 }]);
		assert.equal(rooms[0].key, true);
	});

	test('passes props through unchanged', () => {
		const props = [{ type: 'console', u: 0.5, v: 0.5 }];
		const rooms = roomsFromLayout([{ id: 'r', name: 'R', type: 'generic', props, startX: 0, startY: 0, endX: 100, endY: 100 }]);
		assert.deepEqual(rooms[0].props, props);
	});

	test('returns empty array for empty input', () => {
		assert.deepEqual(roomsFromLayout([]), []);
	});
});

describe('doorsFromLayout', () => {
	test('creates a door between two connected rooms sharing an edge', () => {
		const rooms = roomsFromLayout(TWO_ROOMS);
		const doors = doorsFromLayout(rooms, TWO_CONNECTIONS);
		assert.equal(doors.length, 1);
		const d = doors[0];
		assert.ok(d.id.includes('room_a'));
		assert.ok(d.id.includes('room_b'));
		// axis 'x' because rooms share an x-edge (a.x1 === b.x0)
		assert.equal(d.axis, 'x');
		assert.equal(d.at, 10); // a.x1 = 10
	});

	test('returns no doors for non-adjacent rooms', () => {
		const rooms = roomsFromLayout([
			{ id: 'r1', name: 'R1', type: 'generic', startX: 0, startY: 0, endX: 100, endY: 100 },
			{ id: 'r2', name: 'R2', type: 'generic', startX: 500, startY: 500, endX: 600, endY: 600 },
		]);
		const doors = doorsFromLayout(rooms, { r1: [{ to: 'r2', dir: 'door' }] });
		assert.equal(doors.length, 0);
	});

	test('marks shuttle-dock doors as jammed when breached', () => {
		const rooms = roomsFromLayout([
			{ id: 'room_a', name: 'A', type: 'generic', startX: 0, startY: 0, endX: 400, endY: 200 },
			{ id: 'breached_dock', name: 'Dock', type: 'shuttle-dock', startX: 0, startY: 200, endX: 400, endY: 400 },
		]);
		const doors = doorsFromLayout(rooms, { room_a: [{ to: 'breached_dock', dir: 'door' }] });
		assert.equal(doors.length, 1);
		assert.equal(doors[0].jammed, true);
	});

	test('marks sealed rooms as sealed', () => {
		const rooms = roomsFromLayout([
			{ id: 'room_a', name: 'A', type: 'generic', startX: 0, startY: 0, endX: 400, endY: 200 },
			{ id: 'sealed_vault', name: 'Vault', type: 'generic', startX: 0, startY: 200, endX: 400, endY: 400 },
		]);
		const doors = doorsFromLayout(rooms, { room_a: [{ to: 'sealed_vault', dir: 'door' }] });
		assert.equal(doors.length, 1);
		assert.equal(doors[0].sealed, true);
	});

	test('skips elevator connections', () => {
		const rooms = roomsFromLayout([
			{ id: 'r1', name: 'R1', type: 'generic', floor: 0, startX: 0, startY: 0, endX: 100, endY: 100 },
			{ id: 'r2', name: 'R2', type: 'generic', floor: 1, startX: 0, startY: 0, endX: 100, endY: 100 },
		]);
		const doors = doorsFromLayout(rooms, { r1: [{ to: 'r2', dir: 'elevator' }] });
		assert.equal(doors.length, 0);
	});
});

describe('elevatorsFromLayout', () => {
	test('extracts elevator connections', () => {
		const rooms = roomsFromLayout([
			{ id: 'r1', name: 'R1', type: 'generic', floor: 0, startX: 0, startY: 0, endX: 100, endY: 100 },
			{ id: 'r2', name: 'R2', type: 'generic', floor: 1, startX: 0, startY: 0, endX: 100, endY: 100 },
		]);
		const elevators = elevatorsFromLayout(rooms, { r1: [{ to: 'r2', dir: 'elevator' }] });
		assert.equal(elevators.length, 1);
		assert.equal(elevators[0].elevator, true);
		assert.ok(elevators[0].rooms.includes('r1'));
		assert.ok(elevators[0].rooms.includes('r2'));
	});

	test('ignores non-elevator connections', () => {
		const rooms = roomsFromLayout(TWO_ROOMS);
		const elevators = elevatorsFromLayout(rooms, TWO_CONNECTIONS);
		assert.equal(elevators.length, 0);
	});

	test('handles missing rooms gracefully', () => {
		const rooms = roomsFromLayout(TWO_ROOMS);
		const elevators = elevatorsFromLayout(rooms, { room_a: [{ to: 'nonexistent', dir: 'elevator' }] });
		assert.equal(elevators.length, 0);
	});

	test('returns empty for empty connections', () => {
		const rooms = roomsFromLayout(TWO_ROOMS);
		assert.deepEqual(elevatorsFromLayout(rooms, {}), []);
	});
});