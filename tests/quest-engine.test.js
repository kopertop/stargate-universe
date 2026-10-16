/**
 * Unit tests for src/quest.js — chapter/quest engine.
 *
 * Run with:  node --test tests/quest-engine.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * quest.js exports createQuestEngine, which builds a pure-logic
 * state machine: load chapters, start a chapter, set flags, and
 * auto-advance through steps whose complete_when flag is set.
 * No DOM required.
 */
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createQuestEngine } from '../src/quest.js';

// Minimal chapter fixture
const makeChapters = () => [
	{
		id: 'ch1',
		steps: [
			{ id: 's1', complete_when: 'got_key', on_enter: ['msg:find_key'], on_exit: ['msg:key_found'], xp: 10 },
			{ id: 's2', complete_when: 'opened_door', on_enter: ['msg:open_door'], xp: 20 },
			{ id: 's3', terminal: true, complete_when: 'done', on_enter: ['msg:ch1_complete'] },
		],
	},
	{
		id: 'ch2',
		steps: [
			{ id: 's2a', complete_when: 'found_map', on_enter: ['msg:find_map'], xp: 15 },
			{ id: 's2b', terminal: true, complete_when: 'ch2_done', on_enter: ['msg:ch2_complete'] },
		],
	},
];

describe('quest engine — init', () => {
	test('createQuestEngine returns an engine object with expected shape', () => {
		const eng = createQuestEngine({});
		assert.equal(typeof eng.load, 'function');
		assert.equal(typeof eng.startChapter, 'function');
		assert.equal(typeof eng.setFlag, 'function');
		assert.equal(typeof eng.has, 'function');
		assert.equal(typeof eng.check, 'function');
		assert.equal(typeof eng.step, 'function');
		assert.equal(typeof eng.chapterById, 'function');
		assert.equal(typeof eng.nextChapter, 'function');
		assert.deepEqual(eng.chapters, []);
		assert.equal(eng.chapter, null);
		assert.equal(eng.stepIndex, 0);
		assert.equal(eng.done.length, 0);
	});

	test('chapterById returns undefined for unknown id', () => {
		const eng = createQuestEngine({});
		eng.chapters = makeChapters();
		assert.equal(eng.chapterById('nope'), undefined);
	});

	test('chapterById returns the chapter for a known id', () => {
		const eng = createQuestEngine({});
		eng.chapters = makeChapters();
		assert.equal(eng.chapterById('ch1').id, 'ch1');
		assert.equal(eng.chapterById('ch2').id, 'ch2');
	});
});

describe('quest engine — startChapter', () => {
	let triggers, steps, _xpGranted, eng;

	beforeEach(() => {
		triggers = [];
		steps = [];
		_xpGranted = 0;
		eng = createQuestEngine({
			onTrigger: (t) => triggers.push(t),
			onStep: (s) => steps.push(s?.id),
			onChapterComplete: (ch) => triggers.push(`complete:${ch.id}`),
			grantXp: (n) => { _xpGranted += n; },
		});
		eng.chapters = makeChapters();
	});

	test('startChapter sets chapter and resets stepIndex to 0', () => {
		eng.startChapter('ch1');
		assert.equal(eng.chapter.id, 'ch1');
		assert.equal(eng.stepIndex, 0);
	});

	test('startChapter fires on_enter of first step and calls onStep', () => {
		eng.startChapter('ch1');
		assert.deepEqual(triggers, ['msg:find_key']);
		assert.deepEqual(steps, ['s1']);
	});

	test('startChapter deletes complete_when flags for the chapter steps', () => {
		eng.setFlag('got_key');
		assert.equal(eng.has('got_key'), true);
		eng.startChapter('ch1'); // should delete 'got_key'
		assert.equal(eng.has('got_key'), false);
	});

	test('startChapter on unknown id does not throw', () => {
		assert.doesNotThrow(() => eng.startChapter('nonexistent'));
	});

	test('step() returns current step object', () => {
		eng.startChapter('ch1');
		const s = eng.step();
		assert.equal(s.id, 's1');
		assert.equal(s.complete_when, 'got_key');
	});
});

describe('quest engine — flag / check / advance', () => {
	let triggers, steps, _xpGranted, eng;

	beforeEach(() => {
		triggers = [];
		steps = [];
		_xpGranted = 0;
		eng = createQuestEngine({
			onTrigger: (t) => triggers.push(t),
			onStep: (s) => steps.push(s?.id),
			onChapterComplete: (ch) => triggers.push(`complete:${ch.id}`),
			grantXp: (n) => { _xpGranted += n; },
		});
		eng.chapters = makeChapters();
		eng.startChapter('ch1');
		// Reset after startChapter side-effects
		triggers.length = 0;
		steps.length = 0;
	});

	test('setFlag adds a flag and has() returns true', () => {
		eng.setFlag('arbitrary');
		assert.equal(eng.has('arbitrary'), true);
	});

	test('setFlag with falsy value is a no-op', () => {
		eng.setFlag(null);
		eng.setFlag('');
		eng.setFlag(undefined);
		assert.equal(eng.flags.size, 0);
	});

	test('setFlag with already-set flag does not re-trigger check', () => {
		eng.setFlag('got_key');
		// After advancing, set same flag again — should be no-op
		const triggerCountBefore = triggers.length;
		eng.setFlag('got_key');
		assert.equal(triggers.length, triggerCountBefore);
	});

	test('setFlag triggers check and advances through completed steps', () => {
		eng.setFlag('got_key');
		// Should advance from s1 to s2
		assert.equal(eng.stepIndex, 1);
		assert.equal(eng.step().id, 's2');
		// Should have fired on_exit for s1 and on_enter for s2
		assert.ok(triggers.includes('msg:key_found'));
		assert.ok(triggers.includes('msg:open_door'));
		// Should have granted xp for s1
		assert.equal(_xpGranted, 10);
	});

	test('check does not advance when complete_when flag is not set', () => {
		eng.check();
		assert.equal(eng.stepIndex, 0);
		assert.equal(eng.step().id, 's1');
	});

	test('setting all flags advances to terminal step and marks chapter done', () => {
		eng.setFlag('got_key');   // advance s1 → s2
		eng.setFlag('opened_door'); // advance s2 → s3 (terminal)
		assert.equal(eng.stepIndex, 2);
		assert.equal(eng.step().terminal, true);
		assert.deepEqual(eng.done, ['ch1']);
		assert.ok(triggers.includes('complete:ch1'));
		assert.equal(_xpGranted, 30); // 10 + 20
	});

	test('terminal step stops further advancement', () => {
		eng.setFlag('got_key');
		eng.setFlag('opened_door');
		// Now at terminal step s3. Setting 'done' should NOT advance further.
		const stepIndexBefore = eng.stepIndex;
		eng.setFlag('done');
		assert.equal(eng.stepIndex, stepIndexBefore);
	});
});

describe('quest engine — nextChapter', () => {
	test('nextChapter returns the chapter after the current one', () => {
		const eng = createQuestEngine({});
		eng.chapters = makeChapters();
		eng.startChapter('ch1');
		assert.equal(eng.nextChapter().id, 'ch2');
	});

	test('nextChapter returns null for the last chapter', () => {
		const eng = createQuestEngine({});
		eng.chapters = makeChapters();
		eng.startChapter('ch2');
		assert.equal(eng.nextChapter(), null);
	});

	test('nextChapter returns null when no chapter is active', () => {
		const eng = createQuestEngine({});
		eng.chapters = makeChapters();
		assert.equal(eng.nextChapter(), null);
	});
});

describe('quest engine — guard limit', () => {
	test('check does not loop infinitely (guard limit of 20)', () => {
		// Create a chapter where every step is already completable
		const eng = createQuestEngine({
			onTrigger: () => {},
			onStep: () => {},
			grantXp: () => {},
		});
		eng.chapters = [{
			id: 'loop_test',
			steps: Array.from({ length: 25 }, (_, i) => ({
				id: `s${i}`,
				complete_when: `flag${i}`,
				xp: 1,
			})),
		}];
		// Set all flags before starting
		for (let i = 0; i < 25; i++) eng.setFlag(`flag${i}`);
		eng.startChapter('loop_test');
		// check should have advanced at most 20 steps (guard limit)
		assert.ok(eng.stepIndex <= 20, `stepIndex should be <= 20, got ${eng.stepIndex}`);
	});
});