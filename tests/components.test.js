/**
 * Unit tests for src/components.js — COMPONENTS registry, DEFAULT_PROPS, and ROOM_PROPS.
 *
 * Run with:  node --test tests/components.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * These are pure data-structure tests: the COMPONENTS registry is a lookup table
 * mapping type keys to { label, size, defaultAnchor?, build }, and DEFAULT_PROPS /
 * ROOM_PROPS are room-type → spec[] mappings. No DOM or Three.js rendering needed —
 * we validate the schema and consistency of the static data.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from '../src/components.js';

// ── COMPONENTS registry ──────────────────────────────────────────────────────

describe('COMPONENTS registry', () => {
	test('has the expected set of component types', () => {
		const keys = Object.keys(COMPONENTS).sort();
		assert.deepEqual(keys, [
			'bed', 'breach', 'cabinet', 'conduit', 'console', 'crate',
			'elevator_door', 'grow_bed', 'kino_pedestal', 'locker',
			'marker', 'med_bed', 'pillar', 'relay', 'scrubber',
			'tank', 'wall_light',
		]);
	});

	test('every entry has label, size, and build', () => {
		for (const [type, def] of Object.entries(COMPONENTS)) {
			assert.equal(typeof def.label, 'string', `${type}: label must be a string`);
			assert.ok(def.label.length > 0, `${type}: label must not be empty`);
			assert.ok(Array.isArray(def.size), `${type}: size must be an array`);
			assert.equal(def.size.length, 2, `${type}: size must be [w, d]`);
			assert.equal(typeof def.build, 'function', `${type}: build must be a function`);
		}
	});

	test('size values are positive numbers (editor footprint in metres)', () => {
		for (const [type, def] of Object.entries(COMPONENTS)) {
			const [w, d] = def.size;
			assert.ok(typeof w === 'number' && w > 0, `${type}: size[0] must be a positive number`);
			assert.ok(typeof d === 'number' && d > 0, `${type}: size[1] must be a positive number`);
		}
	});

	test('entries with defaultAnchor have a string anchor name', () => {
		for (const [type, def] of Object.entries(COMPONENTS)) {
			if (def.defaultAnchor !== undefined) {
				assert.equal(typeof def.defaultAnchor, 'string', `${type}: defaultAnchor must be a string`);
				assert.ok(def.defaultAnchor.length > 0, `${type}: defaultAnchor must not be empty`);
			}
		}
	});

	test('build function takes 2-3 parameters (ctx, p, spec?)', () => {
		for (const [type, def] of Object.entries(COMPONENTS)) {
			assert.ok(def.build.length >= 2, `${type}: build() must accept at least (ctx, p)`);
			assert.ok(def.build.length <= 3, `${type}: build() must accept at most (ctx, p, spec)`);
		}
	});
});

// ── DEFAULT_PROPS ────────────────────────────────────────────────────────────

describe('DEFAULT_PROPS', () => {
	test('has entries for expected room types', () => {
		const keys = Object.keys(DEFAULT_PROPS).sort();
		assert.deepEqual(keys, [
			'control_room', 'elevator', 'gate_room',
			'hydroponics', 'infirmary', 'quarters',
			'shuttle-dock', 'storage',
		]);
	});

	test('every spec references a component type that exists in COMPONENTS', () => {
		for (const [roomType, specs] of Object.entries(DEFAULT_PROPS)) {
			assert.ok(Array.isArray(specs), `${roomType}: DEFAULT_PROPS value must be an array`);
			for (const spec of specs) {
				assert.ok(typeof spec.type === 'string', `${roomType}: spec.type must be a string`);
				assert.ok(COMPONENTS[spec.type], `${roomType}: spec.type "${spec.type}" must exist in COMPONENTS`);
			}
		}
	});

	test('u and v are numbers in [0, 1] range (room-relative fractions)', () => {
		for (const [roomType, specs] of Object.entries(DEFAULT_PROPS)) {
			for (const spec of specs) {
				assert.ok(typeof spec.u === 'number', `${roomType}: spec.u must be a number`);
				assert.ok(typeof spec.v === 'number', `${roomType}: spec.v must be a number`);
				assert.ok(spec.u >= 0 && spec.u <= 1, `${roomType}: spec.u must be in [0,1], got ${spec.u}`);
				assert.ok(spec.v >= 0 && spec.v <= 1, `${roomType}: spec.v must be in [0,1], got ${spec.v}`);
			}
		}
	});

	test('ry (rotation) when present is a number', () => {
		for (const [roomType, specs] of Object.entries(DEFAULT_PROPS)) {
			for (const spec of specs) {
				if (spec.ry !== undefined) {
					assert.ok(typeof spec.ry === 'number', `${roomType}: spec.ry must be a number`);
				}
			}
		}
	});

	test('anchor when present is a non-empty string', () => {
		for (const [roomType, specs] of Object.entries(DEFAULT_PROPS)) {
			for (const spec of specs) {
				if (spec.anchor !== undefined) {
					assert.equal(typeof spec.anchor, 'string', `${roomType}: spec.anchor must be a string`);
					assert.ok(spec.anchor.length > 0, `${roomType}: spec.anchor must not be empty`);
				}
			}
		}
	});

	test('loot when present is an array of {id, n?} objects', () => {
		for (const [roomType, specs] of Object.entries(DEFAULT_PROPS)) {
			for (const spec of specs) {
				if (spec.loot !== undefined) {
					assert.ok(Array.isArray(spec.loot), `${roomType}: spec.loot must be an array`);
					for (const item of spec.loot) {
						assert.ok(typeof item.id === 'string', `${roomType}: loot item.id must be a string`);
						if (item.n !== undefined) {
							assert.ok(typeof item.n === 'number' && item.n > 0, `${roomType}: loot item.n must be a positive number`);
						}
					}
				}
			}
		}
	});

	test('gate_room has a relay component (power relay is the key prop)', () => {
		const gateRoom = DEFAULT_PROPS.gate_room;
		assert.ok(gateRoom.some(s => s.type === 'relay'), 'gate_room must have a relay component');
	});

	test('control_room has a console component', () => {
		const controlRoom = DEFAULT_PROPS.control_room;
		assert.ok(controlRoom.some(s => s.type === 'console'), 'control_room must have a console component');
	});

	test('hydroponics has grow_bed components', () => {
		const hydro = DEFAULT_PROPS.hydroponics;
		const growBeds = hydro.filter(s => s.type === 'grow_bed');
		assert.ok(growBeds.length >= 4, 'hydroponics must have at least 4 grow beds');
	});

	test('infirmary has med_bed components', () => {
		const infirmary = DEFAULT_PROPS.infirmary;
		const medBeds = infirmary.filter(s => s.type === 'med_bed');
		assert.ok(medBeds.length >= 3, 'infirmary must have at least 3 med beds');
	});
});

// ── ROOM_PROPS (room-specific overrides) ─────────────────────────────────────

describe('ROOM_PROPS', () => {
	test('has entries for specific room IDs', () => {
		const keys = Object.keys(ROOM_PROPS);
		assert.ok(keys.length > 0, 'ROOM_PROPS must have at least one entry');
		// Room IDs are not room types — they are specific layout JSON IDs
		for (const key of keys) {
			assert.equal(typeof key, 'string', 'ROOM_PROPS keys must be strings');
			assert.ok(key.length > 0, 'ROOM_PROPS keys must not be empty');
		}
	});

	test('every spec references a component type that exists in COMPONENTS', () => {
		for (const [roomId, specs] of Object.entries(ROOM_PROPS)) {
			assert.ok(Array.isArray(specs), `${roomId}: ROOM_PROPS value must be an array`);
			for (const spec of specs) {
				assert.ok(typeof spec.type === 'string', `${roomId}: spec.type must be a string`);
				assert.ok(COMPONENTS[spec.type], `${roomId}: spec.type "${spec.type}" must exist in COMPONENTS`);
			}
		}
	});

	test('u and v are numbers in [0, 1] range', () => {
		for (const [roomId, specs] of Object.entries(ROOM_PROPS)) {
			for (const spec of specs) {
				assert.ok(typeof spec.u === 'number', `${roomId}: spec.u must be a number`);
				assert.ok(typeof spec.v === 'number', `${roomId}: spec.v must be a number`);
				assert.ok(spec.u >= 0 && spec.u <= 1, `${roomId}: spec.u must be in [0,1], got ${spec.u}`);
				assert.ok(spec.v >= 0 && spec.v <= 1, `${roomId}: spec.v must be in [0,1], got ${spec.v}`);
			}
		}
	});

	test('eli_quarters has a kino_pedestal (Kino room)', () => {
		const eli = ROOM_PROPS.eli_quarters;
		assert.ok(eli, 'eli_quarters must exist in ROOM_PROPS');
		assert.ok(eli.some(s => s.type === 'kino_pedestal'), 'eli_quarters must have a kino_pedestal');
	});

	test('south_corridor has a scrubber (CO2 scrubber)', () => {
		const south = ROOM_PROPS.south_corridor;
		assert.ok(south, 'south_corridor must exist in ROOM_PROPS');
		assert.ok(south.some(s => s.type === 'scrubber'), 'south_corridor must have a scrubber');
	});

	test('room_1753576770763 has a conduit (crew-deck power junction)', () => {
		const junction = ROOM_PROPS.room_1753576770763;
		assert.ok(junction, 'room_1753576770763 must exist in ROOM_PROPS');
		assert.ok(junction.some(s => s.type === 'conduit'), 'room_1753576770763 must have a conduit');
	});
});

// ── Cross-references: DEFAULT_PROPS vs ROOM_PROPS ───────────────────────────

describe('DEFAULT_PROPS and ROOM_PROPS consistency', () => {
	test('ROOM_PROPS infirmary overrides DEFAULT_PROPS infirmary (same room type)', () => {
		// Both have infirmary entries — ROOM_PROPS is the room-specific override
		assert.ok(DEFAULT_PROPS.infirmary, 'DEFAULT_PROPS.infirmary must exist');
		assert.ok(ROOM_PROPS.infirmary, 'ROOM_PROPS.infirmary must exist');
		// ROOM_PROPS version should have the med_beds + cabinet from default plus a crate
		const roomPropsInfirmary = ROOM_PROPS.infirmary;
		assert.ok(roomPropsInfirmary.some(s => s.type === 'med_bed'), 'ROOM_PROPS infirmary must have med_beds');
		assert.ok(roomPropsInfirmary.some(s => s.type === 'crate'), 'ROOM_PROPS infirmary must have a crate (override adds salvage)');
	});

	test('no spec uses a style value that is not "ancient" or "pelican"', () => {
		const validStyles = ['ancient', 'pelican', undefined];
		for (const specs of Object.values(DEFAULT_PROPS)) {
			for (const spec of specs) {
				if (spec.style !== undefined) {
					assert.ok(validStyles.includes(spec.style), `Invalid style "${spec.style}" — must be "ancient" or "pelican"`);
				}
			}
		}
		for (const specs of Object.values(ROOM_PROPS)) {
			for (const spec of specs) {
				if (spec.style !== undefined) {
					assert.ok(validStyles.includes(spec.style), `Invalid style "${spec.style}" in ROOM_PROPS — must be "ancient" or "pelican"`);
				}
			}
		}
	});
});