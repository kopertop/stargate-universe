/**
 * Unit tests for src/autoplay.js — demo driver / smoke test module.
 *
 * Run with:  node --test tests/autoplay.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * autoplay.js depends on a browser environment (window, KeyboardEvent,
 * document, location, performance, sessionStorage) and a game instance
 * passed to createAutoplay(d). We can't load the full module in Node
 * without extensive stubs. Instead we test:
 *   1. Source structure — exports, handler vocabulary, key patterns
 *   2. handlerFor routing logic (extracted and eval'd in isolation)
 *   3. Step handler coverage — every step id in chapters.json has a handler
 *   4. RESUME_KEY constant and sessionStorage usage patterns
 *   5. Autoplay state shape (idle/log/running/abort/report)
 *
 * The regex-based extractor reads the source file and evaluates the
 * handlerFor function in a sandboxed context (no imports needed).
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(__dirname, '..', 'src', 'autoplay.js'), 'utf-8');

// ─── Source Structure Tests ───────────────────────────────

describe('autoplay.js source structure', () => {
	test('exports createAutoplay as a named export', () => {
		assert.ok(src.includes('export const createAutoplay'),
			'createAutoplay should be a named export');
	});

	test('module has no default export', () => {
		assert.ok(!src.includes('export default'),
			'autoplay.js should not have a default export');
	});

	test('creates auto state object with expected fields', () => {
		assert.ok(src.includes("status: 'idle'"),
			'auto state should initialize with status: idle');
		assert.ok(src.includes('log: []'),
			'auto state should initialize with log: []');
		assert.ok(src.includes('running: false'),
			'auto state should initialize with running: false');
		assert.ok(src.includes('abort: false'),
			'auto state should initialize with abort: false');
		assert.ok(src.includes('report: []'),
			'auto state should initialize with report: []');
	});

	test('exposes runChapter and run methods on auto object', () => {
		assert.ok(src.includes('auto.runChapter'),
			'should expose runChapter method');
		assert.ok(src.includes('auto.run'),
			'should expose run method');
	});

	test('uses simNow for simulated time tracking', () => {
		assert.ok(src.includes('simNow'),
			'should use simNow for time tracking');
		assert.ok(src.includes('performance.now()'),
			'simNow should initially use performance.now()');
	});

	test('uses keyboard events via press() helper', () => {
		assert.ok(src.includes("const press = (code)"),
			'should define press() helper for keyboard events');
		assert.ok(src.includes('KeyboardEvent'),
			'press should dispatch KeyboardEvent');
	});

	test('defines sleep helper using simNow', () => {
		assert.ok(src.includes('const sleep ='),
			'should define sleep helper');
		assert.ok(src.includes('simNow()'),
			'sleep should use simNow for timing');
	});
});

// ─── Handler Vocabulary Tests ─────────────────────────────

describe('step handler vocabulary', () => {
	// Extract all handler names from the H object
	const handlerMatches = [...src.matchAll(/^\t\t(\w+):\s*async/gm)];
	const handlerNames = handlerMatches.map((m) => m[1]);

	test('defines handlers for all core step types', () => {
		const expected = [
			'arrive', 'inspect_relay', 'find', 'ride_up', 'restore_power',
			'reach_control', 'diagnose', 'seal_breach', 'explore',
			'find_kino', 'find_scrubber', 'talk_rush', 'ftl_drop',
			'scout_kino', 'gear_up', 'travel', 'mine', 'dial_home',
			'give_brody', 'balance', 'repair',
		];
		for (const name of expected) {
			assert.ok(handlerNames.includes(name),
				`should define handler: ${name}`);
		}
	});

	test('does not define a handler for "talk_" prefix (uses fallback)', () => {
		// talk_ is handled by handlerFor fallback to talk_rush
		assert.ok(!handlerNames.includes('talk_'),
			'talk_ is a prefix pattern, not a direct handler');
	});

	test('handler count is between 18 and 25', () => {
		assert.ok(handlerNames.length >= 18 && handlerNames.length <= 25,
			`handler count should be 18-25, got ${handlerNames.length}`);
	});
});

// ─── handlerFor Routing Logic Tests ───────────────────────

describe('handlerFor routing logic', () => {
	// Extract the handlerFor function from source and eval it in isolation
	const fnMatch = src.match(/const handlerFor = (\([^)]*\) => [\s\S]*?);\s*\n/);
	assert.ok(fnMatch, 'handlerFor should be defined in source');

	// Reconstruct: the H object maps ids to functions. For routing tests,
	// we only need the id → handler-name resolution, not the actual functions.
	// We build a mock H where each key maps to its own name as a string.
	const handlerIds = [...src.matchAll(/^\t\t(\w+):\s*async/gm)].map((m) => m[1]);
	const mockH = {};
	for (const id of handlerIds) mockH[id] = id; // value = id string for identification

	// Eval handlerFor with our mockH
	const handlerFor = eval('(function(H) { return ' + fnMatch[1] + ' })')(mockH);

	test('routes exact match ids correctly', () => {
		assert.equal(handlerFor('arrive'), 'arrive');
		assert.equal(handlerFor('mine'), 'mine');
		assert.equal(handlerFor('travel'), 'travel');
		assert.equal(handlerFor('dial_home'), 'dial_home');
		assert.equal(handlerFor('scout_kino'), 'scout_kino');
		assert.equal(handlerFor('gear_up'), 'gear_up');
		assert.equal(handlerFor('balance'), 'balance');
		assert.equal(handlerFor('repair'), 'repair');
	});

	test('routes repair_ prefix to repair handler', () => {
		assert.equal(handlerFor('repair_conduit'), 'repair');
		assert.equal(handlerFor('repair_shields'), 'repair');
		assert.equal(handlerFor('repair_anything'), 'repair');
	});

	test('routes balance_ prefix to balance handler', () => {
		assert.equal(handlerFor('balance_primary'), 'balance');
		assert.equal(handlerFor('balance_secondary'), 'balance');
		assert.equal(handlerFor('balance_emitters'), 'balance');
	});

	test('routes talk_ prefix to talk_rush handler', () => {
		assert.equal(handlerFor('talk_rush'), 'talk_rush');
		assert.equal(handlerFor('talk_chloe'), 'talk_rush');
		assert.equal(handlerFor('talk_scott'), 'talk_rush');
		assert.equal(handlerFor('talk_anything'), 'talk_rush');
	});

	test('routes find_ prefix to find handler', () => {
		assert.equal(handlerFor('find_fuse'), 'find');
		assert.equal(handlerFor('find_toolkit'), 'find');
		assert.equal(handlerFor('find_anything'), 'find');
	});

	test('routes restore_ prefix to restore_power handler', () => {
		assert.equal(handlerFor('restore_power'), 'restore_power');
		assert.equal(handlerFor('restore_gravity'), 'restore_power');
		assert.equal(handlerFor('restore_anything'), 'restore_power');
	});

	test('routes reach_ prefix to reach_control handler', () => {
		assert.equal(handlerFor('reach_control'), 'reach_control');
		assert.equal(handlerFor('reach_bridge'), 'reach_control');
		assert.equal(handlerFor('reach_anything'), 'reach_control');
	});

	test('returns null for unknown id with no matching prefix', () => {
		assert.equal(handlerFor('unknown_step'), null);
		assert.equal(handlerFor('xyz'), null);
		assert.equal(handlerFor(''), null);
	});

	test('exact match takes priority over prefix match', () => {
		// 'find' is both an exact match AND matches the find_ prefix pattern
		// but handlerFor checks exact first (H[id]) before prefix fallbacks
		assert.equal(handlerFor('find'), 'find');
		assert.equal(handlerFor('repair'), 'repair');
		assert.equal(handlerFor('balance'), 'balance');
	});
});

// ─── Step Coverage: chapters.json vs handler vocabulary ───

describe('step id coverage in chapters.json', () => {
	// Load chapters.json and extract all step ids
	let chapters;
	try {
		chapters = JSON.parse(readFileSync(join(__dirname, '..', 'data', 'chapters.json'), 'utf-8'));
	} catch {
		chapters = null;
	}

	test('chapters.json is valid JSON', () => {
		assert.ok(chapters, 'chapters.json should be parseable');
	});

	if (chapters) {
		// Extract all step ids from all chapters
		const allStepIds = new Set();
		const chaptersArr = Array.isArray(chapters) ? chapters : (chapters.chapters ?? []);
		for (const ch of chaptersArr) {
			if (ch.steps) {
				for (const s of ch.steps) {
					if (s.id) allStepIds.add(s.id);
				}
			}
		}

		// Extract handler ids and prefix patterns from source
		const handlerIds = [...src.matchAll(/^\t\t(\w+):\s*async/gm)].map((m) => m[1]);
		const fnMatch = src.match(/const handlerFor = (\([^)]*\) => [\s\S]*?);\s*\n/);
		const mockH = {};
		for (const id of handlerIds) mockH[id] = id;
		const handlerFor = eval('(function(H) { return ' + fnMatch[1] + ' })')(mockH);

		test('every non-terminal step id has a handler, prefix match, or target fallback', () => {
			// Terminal steps (complete) cause runChapter to break before
			// needing a handler, so they're intentionally uncovered.
			// Steps with target.room are handled by the generic fallback:
			//   goTo(s.target.room, s.target.anchor) + interact()
			const uncovered = [];
			for (const ch of chaptersArr) {
				if (!ch.steps) continue;
				for (const s of ch.steps) {
					if (s.terminal) continue;
					if (handlerFor(s.id) !== null) continue;
					if (s.target && s.target.room) continue; // generic fallback
					uncovered.push(s.id);
				}
			}
			const unique = [...new Set(uncovered)];
			assert.equal(unique.length, 0,
				`Uncovered non-terminal step ids (no handler, no prefix, no target): ${unique.join(', ')}`);
		});

		test('chapters.json has at least 20 unique step ids', () => {
			assert.ok(allStepIds.size >= 20,
				`expected >= 20 step ids, got ${allStepIds.size}`);
		});
	}
});

// ─── Resume/Reload Pattern Tests ──────────────────────────

describe('resume and reload pattern', () => {
	test('uses RESUME_KEY constant for sessionStorage', () => {
		assert.ok(src.includes("const RESUME_KEY = 'sgu.autoresume'"),
			'should define RESUME_KEY as sgu.autoresume');
	});

	test('stores report in sessionStorage on reload', () => {
		assert.ok(src.includes('sessionStorage.setItem(RESUME_KEY'),
			'should store resume data in sessionStorage');
	});

	test('cleans up RESUME_KEY on completion', () => {
		assert.ok(src.includes('sessionStorage.removeItem(RESUME_KEY)'),
			'should remove RESUME_KEY after successful run or on failure');
	});

	test('reads RESUME_KEY at module load for auto-resume', () => {
		assert.ok(src.includes("sessionStorage.getItem(RESUME_KEY)"),
			'should check for resume data at module load time');
	});

	test('polls for Continue button with 80 retries at 250ms', () => {
		// 80 * 250ms = 20 seconds max wait for Continue button
		assert.ok(src.includes('i < 80'),
			'should poll up to 80 times for Continue button');
		assert.ok(src.includes('250'),
			'should wait 250ms between polls');
	});

	test('checks location.search for reload parameter', () => {
		assert.ok(src.includes("location.search.includes('reload')"),
			'should detect ?reload in URL query string');
	});
});

// ─── Autoplay State and Safety Tests ──────────────────────

describe('autoplay safety and state management', () => {
	test('run() guards against re-entry', () => {
		assert.ok(src.includes('if (auto.running) return'),
			'run() should guard against double-entry');
	});

	test('sets running=true at start and false in finally', () => {
		assert.ok(src.includes('auto.running = true'),
			'should set running=true at start');
		assert.ok(src.includes('auto.running = false'),
			'should set running=false in finally block');
	});

	test('clears input keys in finally block', () => {
		assert.ok(src.includes('d.input.keys.clear()'),
			'should clear input keys on exit');
	});

	test('respects abort flag in runChapter loop', () => {
		assert.ok(src.includes('!auto.abort'),
			'runChapter should check abort flag in loop');
	});

	test('has guard limit of 60 iterations in runChapter', () => {
		assert.ok(src.includes('guard++ < 60'),
			'runChapter should have a 60-iteration guard limit');
	});

	test('detects stuck state after 2 retries on same step', () => {
		assert.ok(src.includes('tries > 2'),
			'should detect stuck after 2 retries');
		assert.ok(src.includes('STUCK'),
			'should log STUCK status');
	});

	test('returns result object with ok, chapter, seconds fields', () => {
		assert.ok(src.includes('ok:'),
			'result should have ok field');
		assert.ok(src.includes('chapter:'),
			'result should have chapter field');
		assert.ok(src.includes('seconds:'),
			'result should have seconds field');
	});

	test('walkTo cleans up all movement keys on exit', () => {
		// Should delete KeyW, ShiftLeft, KeyA, KeyD, KeyS
		const cleanupMatch = src.match(/for \(const k of \[([^\]]+)\]\) d\.input\.keys\.delete\(k\)/);
		assert.ok(cleanupMatch, 'should have a key cleanup loop');
		const keys = cleanupMatch[1].split(',').map((s) => s.trim().replace(/['"]/g, ''));
		assert.ok(keys.includes('KeyW'), 'should clean KeyW');
		assert.ok(keys.includes('KeyA'), 'should clean KeyA');
		assert.ok(keys.includes('KeyD'), 'should clean KeyD');
		assert.ok(keys.includes('KeyS'), 'should clean KeyS');
		assert.ok(keys.includes('ShiftLeft'), 'should clean ShiftLeft');
	});

	test('unstick logic uses escalating sidestep duration', () => {
		assert.ok(src.includes('Math.min(2400, 600 * stalls)'),
			'sidestep duration should escalate with stall count, capped at 2400ms');
	});

	test('unstick alternates sidestep direction', () => {
		assert.ok(src.includes("side === 'KeyD' ? 'KeyA' : 'KeyD'"),
			'should alternate between KeyD and KeyA for sidestep direction');
	});

	test('closes stray open remote before each step', () => {
		assert.ok(src.includes('d.ui.isRemoteOpen()'),
			'should check if remote is open');
		assert.ok(src.includes('d.ui.closeRemote()'),
			'should close remote to prevent sim pause');
	});
});

// ─── Timeout/Interval Cleanup Tests ───────────────────────

describe('timer and interval cleanup', () => {
	test('does not create unmanaged setInterval', () => {
		// autoplay.js uses setTimeout via sleep(), not setInterval
		// This is important to prevent test hangs (see flow.test.js fix)
		assert.ok(!src.includes('setInterval'),
			'autoplay.js should not use setInterval (uses setTimeout via sleep)');
	});

	test('all async operations use sleep() which is timeout-bounded', () => {
		// Every sleep call has a finite duration (no infinite loops)
		const sleepCalls = src.match(/sleep\(\d+\)/g);
		assert.ok(sleepCalls && sleepCalls.length > 10,
			'should have multiple bounded sleep() calls');
	});

	test('waitFor has default timeout of 20000ms', () => {
		assert.ok(src.includes('timeout = 20000'),
			'waitFor should default to 20s timeout');
	});

	test('walkTo calculates timeout from distance', () => {
		assert.ok(src.includes('dist0 / (run ? 8 : 3.5)'),
			'walkTo should calculate timeout from distance and speed');
	});
});