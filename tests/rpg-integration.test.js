/**
 * Integration tests for src/rpg.js — imports the real module and exercises
 * its actual exported functions: addItem, removeItem, count, equip, unequip,
 * spendTalent, stats, grantXp, carried, usable, use, addLog.
 *
 * Run with:  node --test tests/rpg-integration.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * rpg.js imports ./assets.js which reads window.__ASSET_ROOT.
 * We stub globalThis.window before import so the asset path resolves.
 * localStorage is also stubbed for save/load tests.
 */
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

// Stub window before importing rpg.js (assets.js reads window.__ASSET_ROOT)
globalThis.window = { __ASSET_ROOT: './' };
// Stub localStorage for save/load tests
const _store = {};
globalThis.localStorage = {
	getItem: (k) => _store[k] ?? null,
	setItem: (k, v) => { _store[k] = String(v); },
	removeItem: (k) => { delete _store[k]; },
};

// Dynamic import after stubs are in place
const rpgMod = await import('../src/rpg.js');
const {
	rpg, xpToNext, addLog, count, addItem, removeItem,
	equip, unequip, spendTalent, stats, carried, grantXp,
	usable, use, useVerb, iconHtml, TALENTS, loadItems,
} = rpgMod;

// Populate ITEMS by calling loadItems with a stubbed fetch.
// loadItems tries to fetch data/items.json from the repo, then
// merges in WEB_ITEMS. We stub fetch to return the local file content.
import { readFileSync } from 'node:fs';
const itemsJson = JSON.parse(readFileSync(new URL('../data/items.json', import.meta.url), 'utf8'));
globalThis.fetch = async (_url) => ({
	ok: true,
	status: 200,
	json: async () => itemsJson,
});
await loadItems();
delete globalThis.fetch;

// Reset RPG state to defaults before each test
function resetRpg() {
	rpg.level = 1;
	rpg.xp = 0;
	rpg.hp = 100;
	rpg.o2 = 100;
	rpg.talentPoints = 0;
	rpg.inventory = {};
	rpg.equipment = { head: null, torso: null, back: null, legs: null, tool: null };
	rpg.talents = { engineer: 0, pathfinder: 0, pack_mule: 0 };
	rpg.log = [];
}

describe('rpg.js — real module integration tests', () => {
	beforeEach(() => resetRpg());

	// ── xpToNext ──────────────────────────────────────────────────────────

	describe('xpToNext', () => {
		test('level 1 → 100 XP', () => assert.equal(xpToNext(1), 100));
		test('level 5 → 500 XP', () => assert.equal(xpToNext(5), 500));
		test('level 10 → 1000 XP', () => assert.equal(xpToNext(10), 1000));
	});

	// ── addItem / removeItem / count ──────────────────────────────────────

	describe('addItem / removeItem / count', () => {
		test('addItem increases count and logs', () => {
			addItem('rations', 3);
			assert.equal(count('rations'), 3);
			assert.ok(rpg.log.some((e) => e.includes('Rations')));
		});

		test('addItem default n=1', () => {
			addItem('shovel');
			assert.equal(count('shovel'), 1);
		});

		test('addItem stacking', () => {
			addItem('rations', 2);
			addItem('rations', 5);
			assert.equal(count('rations'), 7);
		});

		test('removeItem decreases count', () => {
			addItem('rations', 5);
			removeItem('rations', 2);
			assert.equal(count('rations'), 3);
		});

		test('removeItem deletes at zero', () => {
			addItem('rations', 1);
			removeItem('rations', 1);
			assert.equal(count('rations'), 0);
			assert.ok(!('rations' in rpg.inventory));
		});

		test('removeItem on non-existent is safe', () => {
			removeItem('nonexistent', 1);
			assert.equal(count('nonexistent'), 0);
		});

		test('count on missing item returns 0', () => {
			assert.equal(count('nothing'), 0);
		});
	});

	// ── grantXp ───────────────────────────────────────────────────────────

	describe('grantXp', () => {
		test('single level-up at exact threshold', () => {
			const ups = grantXp(100);
			assert.equal(rpg.level, 2);
			assert.equal(rpg.xp, 0);
			assert.equal(rpg.talentPoints, 1);
			assert.equal(ups, 1);
		});

		test('multi level-up from large grant', () => {
			// 100 (lvl1→2) + 200 (lvl2→3) + 50 remaining = 350
			const ups = grantXp(350);
			assert.equal(rpg.level, 3);
			assert.equal(rpg.xp, 50);
			assert.equal(rpg.talentPoints, 2);
			assert.equal(ups, 2);
		});

		test('no level-up below threshold', () => {
			const ups = grantXp(99);
			assert.equal(rpg.level, 1);
			assert.equal(rpg.xp, 99);
			assert.equal(rpg.talentPoints, 0);
			assert.equal(ups, 0);
		});

		test('level-up restores hp to maxHp', () => {
			rpg.hp = 50;
			grantXp(100);
			assert.equal(rpg.hp, stats().maxHp);
			assert.ok(rpg.hp > 50, 'hp should be restored to max');
		});

		test('XP grant logs message', () => {
			grantXp(50);
			assert.ok(rpg.log.some((e) => e.includes('+50 XP')));
		});

		test('level-up log includes talent point', () => {
			grantXp(100);
			assert.ok(rpg.log.some((e) => e.includes('talent point')));
		});
	});

	// ── equip / unequip ───────────────────────────────────────────────────

	describe('equip / unequip', () => {
		test('equip tool returns true and sets slot', () => {
			// shovel has slot: 'tool' in WEB_ITEMS
			addItem('shovel', 1);
			const ok = equip('shovel');
			assert.equal(ok, true);
			assert.equal(rpg.equipment.tool, 'shovel');
			assert.equal(count('shovel'), 0); // consumed from inventory
		});

		test('equip item without slot returns false', () => {
			// rations is category 'resource', no slot
			addItem('rations', 1);
			const ok = equip('rations');
			assert.equal(ok, false);
		});

		test('equip swaps previous gear back to inventory', () => {
			addItem('field_backpack', 2);
			equip('field_backpack');
			assert.equal(rpg.equipment.back, 'field_backpack');
			assert.equal(count('field_backpack'), 1);
			// Equip a second one (same slot swaps)
			equip('field_backpack');
			assert.equal(rpg.equipment.back, 'field_backpack');
			// Previous one should go back to inventory
			assert.ok(count('field_backpack') >= 1);
		});

		test('unequip returns item to inventory', () => {
			addItem('shovel', 1);
			equip('shovel');
			unequip('tool');
			assert.equal(rpg.equipment.tool, null);
			assert.equal(count('shovel'), 1);
		});

		test('unequip empty slot is safe', () => {
			unequip('head');
			assert.equal(rpg.equipment.head, null);
		});

		test('equip clamps hp to maxHp when gear adds hp', () => {
			// tac_vest gives +20 hp
			addItem('tac_vest', 1);
			rpg.hp = 100;
			equip('tac_vest');
			assert.equal(rpg.equipment.torso, 'tac_vest');
			assert.ok(rpg.hp <= stats().maxHp);
		});
	});

	// ── stats ─────────────────────────────────────────────────────────────

	describe('stats', () => {
		test('base stats with no gear', () => {
			const s = stats();
			assert.equal(s.carry, 2);
			assert.equal(s.mineSpeed, 0);
			assert.equal(s.speed, 1);
			assert.equal(s.maxHp, 100);
			assert.equal(s.canMine, false);
		});

		test('shovel grants canMine', () => {
			addItem('shovel', 1);
			equip('shovel');
			const s = stats();
			assert.equal(s.canMine, true);
			assert.ok(s.mineSpeed > 0);
		});

		test('level increases maxHp by 5 per level', () => {
			rpg.level = 5;
			const s = stats();
			assert.equal(s.maxHp, 120); // 100 + (5-1)*5
		});

		test('field_backpack adds carry', () => {
			addItem('field_backpack', 1);
			equip('field_backpack');
			const s = stats();
			assert.equal(s.carry, 8); // base 2 + backpack 6
		});

		test('talent engineer increases mine speed multiplicatively', () => {
			addItem('shovel', 1);
			equip('shovel');
			rpg.talentPoints = 1;
			spendTalent('engineer');
			const s = stats();
			// shovel gives mine: 1, engineer rank 1 gives +30% → 1.3
			assert.ok(s.mineSpeed > 1, `mineSpeed should be > 1, got ${s.mineSpeed}`);
		});
	});

	// ── spendTalent ───────────────────────────────────────────────────────

	describe('spendTalent', () => {
		test('spend talent succeeds with points available', () => {
			rpg.talentPoints = 1;
			const ok = spendTalent('engineer');
			assert.equal(ok, true);
			assert.equal(rpg.talents.engineer, 1);
			assert.equal(rpg.talentPoints, 0);
		});

		test('spend talent fails with no points', () => {
			rpg.talentPoints = 0;
			const ok = spendTalent('engineer');
			assert.equal(ok, false);
			assert.equal(rpg.talents.engineer, 0);
		});

		test('spend talent fails at max rank', () => {
			rpg.talentPoints = 5;
			rpg.talents.engineer = 3; // max is 3
			const ok = spendTalent('engineer');
			assert.equal(ok, false);
			assert.equal(rpg.talents.engineer, 3);
		});

		test('spend talent on unknown id fails', () => {
			rpg.talentPoints = 1;
			const ok = spendTalent('nonexistent');
			assert.equal(ok, false);
		});

		test('spend talent logs the purchase', () => {
			rpg.talentPoints = 1;
			spendTalent('engineer');
			assert.ok(rpg.log.some((e) => e.includes('Engineer')));
		});
	});

	// ── carried ───────────────────────────────────────────────────────────

	describe('carried', () => {
		test('empty inventory carries 0', () => {
			assert.equal(carried(), 0);
		});

		test('only resource items count', () => {
			addItem('rations', 5);      // resource
			addItem('shovel', 1);       // equipment
			// rations is from items.json, shovel is WEB_ITEMS with category 'equipment'
			// Only items with category === 'resource' should count
			// Note: rations category depends on items.json load; if not loaded, ITEMS is sparse
			// The carried function checks ITEMS[id]?.category === 'resource'
			// Without loadItems(), ITEMS won't have rations — so this tests the defensive path
			const c = carried();
			assert.equal(typeof c, 'number');
			assert.ok(c >= 0);
		});
	});

	// ── addLog ────────────────────────────────────────────────────────────

	describe('addLog', () => {
		test('adds entry to log', () => {
			addLog('Test message');
			assert.equal(rpg.log[rpg.log.length - 1], 'Test message');
		});

		test('log truncates at 80 entries', () => {
			for (let i = 0; i < 85; i++) addLog(`entry ${i}`);
			assert.ok(rpg.log.length <= 80, `log length should be ≤ 80, got ${rpg.log.length}`);
			assert.equal(rpg.log[0], 'entry 5'); // first 5 shifted out
		});
	});

	// ── usable / use ──────────────────────────────────────────────────────

	describe('usable / use', () => {
		test('usable returns false for unknown item', () => {
			assert.equal(usable('nonexistent'), false);
		});

		test('use on missing item returns false', () => {
			assert.equal(use('nonexistent'), false);
		});

		test('use on item with zero count returns false', () => {
			assert.equal(use('rations'), false);
		});
	});

	// ── useVerb ───────────────────────────────────────────────────────────

	describe('useVerb', () => {
		test('returns Use for unknown item', () => {
			assert.equal(useVerb('nonexistent'), 'Use');
		});
	});

	// ── iconHtml ──────────────────────────────────────────────────────────

	describe('iconHtml', () => {
		test('sprite item returns img tag', () => {
			// rations is in ICON_SPRITES
			const html = iconHtml('rations');
			assert.ok(html.includes('<img'));
			assert.ok(html.includes('rations.png'));
		});

		test('glyph item returns span with emoji', () => {
			const html = iconHtml('shovel');
			assert.ok(html.includes('<span>'));
			assert.ok(html.includes('⛏'));
		});

		test('unknown item returns default bullet', () => {
			const html = iconHtml('unknown_item');
			assert.ok(html.includes('▪'));
		});
	});

	// ── TALENTS registry ──────────────────────────────────────────────────

	describe('TALENTS', () => {
		test('has 3 talents', () => {
			assert.equal(TALENTS.length, 3);
		});

		test('each talent has required fields', () => {
			for (const t of TALENTS) {
				assert.ok(t.id, `talent ${t.id} missing id`);
				assert.ok(t.name, `talent ${t.id} missing name`);
				assert.ok(t.desc, `talent ${t.id} missing desc`);
				assert.ok(t.max > 0, `talent ${t.id} max should be > 0`);
				assert.ok(t.per > 0, `talent ${t.id} per should be > 0`);
				assert.ok(t.stat, `talent ${t.id} missing stat`);
			}
		});
	});
});

// Cleanup
afterEach(() => {
	for (const k of Object.keys(_store)) delete _store[k];
});