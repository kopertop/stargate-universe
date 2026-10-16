/**
 * Unit tests for src/save.js — tests the extracted save/load system (TD-101).
 *
 * Tests cover: migrateSave, hasSave, clear, saveGame (serialization),
 * gameStarted getter/setter, SAVE_KEY/SAVE_VERSION constants.
 *
 * loadGame/newGame/startFrom require heavy dependency injection (quest, destiny,
 * ui, etc.) and are integration-tested via rpg-integration.test.js instead.
 *
 * Run with:  node --test tests/save.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 */
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createSaveSystem } from '../src/save.js';

/** Build a minimal mock ctx for createSaveSystem. */
function makeCtx(overrides = {}) {
	const quest = {
		chapter: { id: 'e1_wake', title: 'Wake', subtitle: '...', steps: [{ id: 'scout_kino', label: 'Scout' }] },
		stepIndex: 0,
		flags: new Set(['power_restored']),
		step: () => ({ id: 'scout_kino', label: 'Scout' }),
		has: (_f) => false,
		...overrides.quest,
	};
	const ftl = { window: 300, cooldown: 0, warned: new Set() };
	const destiny = {
		deck: 0,
		ship: {
			growBeds: [{ growth: 0.5 }, { growth: 0.8 }],
			...overrides.ship,
		},
		...overrides.destiny,
	};
	return {
		quest,
		ftl,
		destiny,
		DECK_H: 4,
		ui: { refreshTracker: () => {}, refreshPlayer: () => {}, toast: () => {}, showChapter: () => {}, subtitle: () => {}, isRemoteOpen: () => false, renderRemote: () => {} },
		enterWorld: () => {},
		arriveAt: () => {},
		placePlayer: () => {},
		loadRpg: () => {},
		saveRpg: () => {},
		listener: { context: { resume: () => {} } },
		beacon: {},
		startChapter: () => {},
		lastScan: null,
		cam: { yaw: 0 },
		onGateEvent: () => {},
		count: () => 0,
		addItem: () => {},
		equip: () => {},
		countdown: null,
		...overrides,
	};
}

describe('save system constants', () => {
	test('SAVE_KEY is sgu.save', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		assert.equal(save.SAVE_KEY, 'sgu.save');
	});

	test('SAVE_VERSION is 1', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		assert.equal(save.SAVE_VERSION, 1);
	});
});

describe('migrateSave', () => {
	test('adds version field to versionless saves (v0)', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		const s = { chapter: 'e1_wake', stepIndex: 0 };
		const result = save.migrateSave(s);
		assert.equal(result.version, 1);
	});

	test('upgrades v0 to current version', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		const s = { version: 0, chapter: 'e1_wake' };
		const result = save.migrateSave(s);
		assert.equal(result.version, save.SAVE_VERSION);
	});

	test('preserves existing data during migration', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		const s = { version: 0, chapter: 'e1_wake', stepIndex: 3, flags: ['a', 'b'] };
		const result = save.migrateSave(s);
		assert.equal(result.chapter, 'e1_wake');
		assert.equal(result.stepIndex, 3);
		assert.deepEqual(result.flags, ['a', 'b']);
		assert.equal(result.version, save.SAVE_VERSION);
	});

	test('already-current version is a no-op (still sets version)', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		const s = { version: 1, chapter: 'e1_wake' };
		const result = save.migrateSave(s);
		assert.equal(result.version, 1);
		assert.equal(result.chapter, 'e1_wake');
	});
});

describe('hasSave', () => {
	let store;
	beforeEach(() => {
		store = {};
		globalThis.localStorage = {
			getItem: (k) => store[k] ?? null,
			setItem: (k, v) => { store[k] = String(v); },
			removeItem: (k) => { delete store[k]; },
		};
	});
	afterEach(() => { delete globalThis.localStorage; });

	test('returns false when no save exists', () => {
		const save = createSaveSystem(makeCtx());
		assert.equal(save.hasSave(), false);
	});

	test('returns true when save exists', () => {
		store['sgu.save'] = JSON.stringify({ version: 1, chapter: 'e1_wake' });
		const save = createSaveSystem(makeCtx());
		assert.equal(save.hasSave(), true);
	});

	test('returns false when localStorage throws (private mode)', () => {
		delete globalThis.localStorage;
		globalThis.localStorage = { getItem: () => { throw new Error('Security'); } };
		const save = createSaveSystem(makeCtx());
		assert.equal(save.hasSave(), false);
	});
});

describe('clear', () => {
	let store;
	beforeEach(() => {
		store = {};
		globalThis.localStorage = {
			getItem: (k) => store[k] ?? null,
			setItem: (k, v) => { store[k] = String(v); },
			removeItem: (k) => { delete store[k]; },
		};
	});
	afterEach(() => { delete globalThis.localStorage; });

	test('removes the save key from localStorage', () => {
		store['sgu.save'] = JSON.stringify({ version: 1 });
		store['sgu.rpg'] = '{"hp":100}';
		const save = createSaveSystem(makeCtx());
		save.clear();
		assert.equal(store['sgu.save'], undefined);
		// clear should NOT remove RPG save — only the main save
		assert.equal(store['sgu.rpg'], '{"hp":100}');
	});
});

describe('saveGame serialization', () => {
	let store;
	beforeEach(() => {
		store = {};
		globalThis.localStorage = {
			getItem: (k) => store[k] ?? null,
			setItem: (k, v) => { store[k] = String(v); },
			removeItem: (k) => { delete store[k]; },
		};
	});
	afterEach(() => { delete globalThis.localStorage; });

	test('writes version, chapter, stepIndex, flags to localStorage', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		save.gameStarted = true;

		save.saveGame();

		const stored = JSON.parse(store['sgu.save']);
		assert.equal(stored.version, 1);
		assert.equal(stored.chapter, 'e1_wake');
		assert.equal(stored.stepIndex, 0);
		assert.deepEqual(stored.flags, ['power_restored']);
	});

	test('includes ftl window and cooldown in save', () => {
		const ctx = makeCtx();
		ctx.ftl.window = 450;
		ctx.ftl.cooldown = 30;
		const save = createSaveSystem(ctx);
		save.gameStarted = true;
		save.saveGame();

		const stored = JSON.parse(store['sgu.save']);
		assert.equal(stored.ftl.window, 450);
		assert.equal(stored.ftl.cooldown, 30);
	});

	test('includes grow bed growth values', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		save.gameStarted = true;
		save.saveGame();

		const stored = JSON.parse(store['sgu.save']);
		assert.deepEqual(stored.growth, [0.5, 0.8]);
	});

	test('includes savedAt timestamp', () => {
		const ctx = makeCtx();
		const save = createSaveSystem(ctx);
		save.gameStarted = true;
		save.saveGame();

		const stored = JSON.parse(store['sgu.save']);
		assert.equal(typeof stored.savedAt, 'number');
		assert.ok(stored.savedAt > 0, 'savedAt should be a positive timestamp');
	});

	test('does nothing when game not started', () => {
		const save = createSaveSystem(makeCtx());
		save.saveGame();
		assert.equal(store['sgu.save'], undefined);
	});

	test('does nothing when no chapter loaded', () => {
		const ctx = makeCtx();
		ctx.quest.chapter = null;
		const save = createSaveSystem(ctx);
		save.gameStarted = true;
		save.saveGame();
		assert.equal(store['sgu.save'], undefined);
	});

	test('handles localStorage quota error gracefully (warn, no throw)', () => {
		globalThis.localStorage = {
			getItem: () => null,
			setItem: () => { throw new Error('QuotaExceeded'); },
			removeItem: () => {},
		};
		const save = createSaveSystem(makeCtx());
		save.gameStarted = true;
		// Should not throw
		assert.doesNotThrow(() => save.saveGame());
	});
});

describe('gameStarted getter/setter', () => {
	test('defaults to false', () => {
		const save = createSaveSystem(makeCtx());
		assert.equal(save.gameStarted, false);
	});

	test('setter updates getter', () => {
		const save = createSaveSystem(makeCtx());
		save.gameStarted = true;
		assert.equal(save.gameStarted, true);
	});

	test('setter is independent per save system instance', () => {
		const save1 = createSaveSystem(makeCtx());
		const save2 = createSaveSystem(makeCtx());
		save1.gameStarted = true;
		assert.equal(save1.gameStarted, true);
		assert.equal(save2.gameStarted, false);
	});
});

describe('PREREQ_STAGES', () => {
	test('has entries for e2_water, e3_darkness, e4_parts, e5_light', () => {
		const save = createSaveSystem(makeCtx());
		assert.equal(typeof save.PREREQ_STAGES.e2_water, 'function');
		assert.equal(typeof save.PREREQ_STAGES.e3_darkness, 'function');
		assert.equal(typeof save.PREREQ_STAGES.e4_parts, 'function');
		assert.equal(typeof save.PREREQ_STAGES.e5_light, 'function');
	});

	test('e3_darkness is a no-op (empty function)', () => {
		const save = createSaveSystem(makeCtx());
		// Should not throw, should return undefined
		assert.equal(save.PREREQ_STAGES.e3_darkness(), undefined);
	});
});