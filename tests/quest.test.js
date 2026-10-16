/**
 * Unit tests for src/quest.js — chapter/quest engine logic.
 *
 * Run with:  node --test tests/quest.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * quest.js exports a factory function `createQuestEngine` that returns
 * an engine object. It has no external imports, so we can import it
 * directly with ESM.
 */
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createQuestEngine } from '../src/quest.js';

// Build a minimal chapter set for testing
const TEST_CHAPTERS = {
	chapters: [
		{
			id: 'ch1',
			steps: [
				{ id: 's1', complete_when: 'flag_a', xp: 50, on_enter: ['say:Welcome'] },
				{ id: 's2', complete_when: 'flag_b', xp: 100, on_exit: ['give:shovel'] },
				{ id: 's3', terminal: true, complete_when: 'flag_end' },
			],
		},
		{
			id: 'ch2',
			steps: [
				{ id: 's1b', complete_when: 'flag_c', xp: 75 },
				{ id: 's2b', terminal: true, complete_when: 'flag_end2' },
			],
		},
	],
};

describe('quest engine', () => {
	let eng, triggers, steps, xpGrants, chapterCompletes;

	beforeEach(() => {
		triggers = [];
		steps = [];
		xpGrants = [];
		chapterCompletes = [];
		eng = createQuestEngine({
			onTrigger: (t) => triggers.push(t),
			onStep: (s, ch) => steps.push({ step: s, chapter: ch }),
			onChapterComplete: (ch) => chapterCompletes.push(ch.id),
			grantXp: (n) => xpGrants.push(n),
		});
	});

	test('load populates chapters from fetch', async () => {
		// Stub fetch
		globalThis.fetch = async () => ({
			ok: true,
			status: 200,
			json: async () => TEST_CHAPTERS,
		});
		await eng.load('test://chapters');
		assert.equal(eng.chapters.length, 2);
		assert.equal(eng.chapters[0].id, 'ch1');
		assert.equal(eng.chapters[1].id, 'ch2');
		delete globalThis.fetch;
	});

	test('load throws on HTTP error', async () => {
		globalThis.fetch = async () => ({ ok: false, status: 404, json: async () => ({}) });
		await assert.rejects(() => eng.load('test://missing'), /HTTP 404/);
		delete globalThis.fetch;
	});

	test('startChapter sets current chapter and fires on_enter for first step', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		assert.equal(eng.chapter.id, 'ch1');
		assert.equal(eng.stepIndex, 0);
		assert.equal(eng.step().id, 's1');
		assert.deepEqual(triggers, ['say:Welcome']);
		assert.equal(steps.length, 1);
		assert.equal(steps[0].step.id, 's1');
	});

	test('setFlag advances through completed steps', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		// Set flag_a → s1 completes, advance to s2
		eng.setFlag('flag_a');
		assert.equal(eng.stepIndex, 1);
		assert.equal(eng.step().id, 's2');
		assert.deepEqual(xpGrants, [50]); // s1 had xp: 50
		// on_exit of s1 has no triggers, on_enter of s2 has none
	});

	test('setFlag with multiple flags set advances through all', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		eng.setFlag('flag_a');
		eng.setFlag('flag_b');
		// s1 done (flag_a), s2 done (flag_b) → advance to s3 (terminal)
		// Landing on a terminal step fires onChapterComplete immediately
		assert.equal(eng.stepIndex, 2);
		assert.equal(eng.step().id, 's3');
		assert.equal(eng.step().terminal, true);
		assert.deepEqual(xpGrants, [50, 100]);
		assert.deepEqual(chapterCompletes, ['ch1']);
		assert.equal(eng.done[0], 'ch1');
	});

	test('terminal step completion fires onChapterComplete', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		eng.setFlag('flag_a');
		eng.setFlag('flag_b');
		eng.setFlag('flag_end');
		// s3 is terminal → onChapterComplete fires
		assert.deepEqual(chapterCompletes, ['ch1']);
		assert.equal(eng.done.length, 1);
		assert.equal(eng.done[0], 'ch1');
	});

	test('setFlag with unknown flag is ignored', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		eng.setFlag('nonexistent');
		assert.equal(eng.stepIndex, 0);
		assert.equal(triggers.length, 1); // only the initial on_enter
	});

	test('setFlag with already-set flag is a no-op', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		eng.setFlag('flag_a');
		assert.equal(eng.stepIndex, 1);
		eng.setFlag('flag_a'); // should not double-advance
		assert.equal(eng.stepIndex, 1);
	});

	test('has checks flag presence', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		assert.equal(eng.has('flag_a'), false);
		eng.setFlag('flag_a');
		assert.equal(eng.has('flag_a'), true);
	});

	test('nextChapter returns the following chapter', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		assert.equal(eng.nextChapter().id, 'ch2');
		eng.startChapter('ch2');
		assert.equal(eng.nextChapter(), null);
	});

	test('startChapter clears only current chapter flags', () => {
		eng.chapters = TEST_CHAPTERS.chapters;
		eng.startChapter('ch1');
		eng.setFlag('flag_a');
		eng.setFlag('power_on'); // world-state flag, not a step flag
		assert.equal(eng.has('power_on'), true);
		eng.startChapter('ch2');
		// flag_c is ch2's step flag — should be cleared. power_on should persist.
		assert.equal(eng.has('power_on'), true);
		assert.equal(eng.has('flag_c'), false);
		assert.equal(eng.has('flag_a'), true); // ch1 flag persists too
	});

	test('check has a guard limit of 20 iterations', () => {
		// Create a chapter with circular-looking steps (all complete_when same flag)
		eng.chapters = [{
			id: 'loop',
			steps: Array.from({ length: 25 }, (_, i) => ({
				id: `s${i}`,
				complete_when: 'loop_flag',
				terminal: i === 24,
			})),
		}];
		eng.startChapter('loop');
		eng.setFlag('loop_flag');
		// Guard prevents infinite loop — stepIndex should be at most 20
		assert.ok(eng.stepIndex <= 20, `stepIndex should be ≤ 20, got ${eng.stepIndex}`);
	});
});