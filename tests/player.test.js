/**
 * Unit tests for src/player.js — character constants, CLIPS mapping, and export structure.
 *
 * Run with:  node --test tests/player.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * player.js depends on THREE.js (GLTFLoader, AnimationMixer, etc.) and a browser
 * environment (import maps, `innerWidth`/`innerHeight`). We can't load the full module
 * in Node without a DOM/Three stub. Instead we test the exported constants (PLAYER, CLIPS)
 * which are pure data and don't require Three.js.
 *
 * To get the constants without running the full module, we use a regex-based extractor
 * that reads the source file and evaluates the exported object literals in a sandboxed
 * context (no `import` needed).
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(__dirname, '..', 'src', 'player.js'), 'utf-8');

// Extract PLAYER constant (pure data, no imports needed)
function extractConst(name, src) {
	const marker = `export const ${name} = `;
	const start = src.indexOf(marker);
	if (start === -1) throw new Error(`${name} not found in source`);
	const after = src.slice(start + marker.length);
	// Find the matching closing brace for the object literal
	let depth = 0, end = 0;
	for (let i = 0; i < after.length; i++) {
		if (after[i] === '{') depth++;
		if (after[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
	}
	return after.slice(0, end);
}

const PLAYER_SRC = extractConst('PLAYER', src);
const PLAYER = eval(`(${PLAYER_SRC})`);

// Extract CLIPS constant
const CLIPS_SRC = extractConst('CLIPS', src);
const CLIPS = eval(`(${CLIPS_SRC})`);

// ─── Tests ─────────────────────────────────────────────────

describe('PLAYER constants', () => {
	test('PLAYER has expected keys', () => {
		assert.ok(PLAYER.radius, 'radius should exist');
		assert.ok(PLAYER.height, 'height should exist');
		assert.ok(PLAYER.walk, 'walk should exist');
		assert.ok(PLAYER.run, 'run should exist');
		assert.ok(PLAYER.turnLerp, 'turnLerp should exist');
		assert.ok(PLAYER.jumpVel, 'jumpVel should exist');
		assert.ok(PLAYER.gravity, 'gravity should exist');
	});

	test('PLAYER radius is a positive number', () => {
		assert.ok(typeof PLAYER.radius === 'number');
		assert.ok(PLAYER.radius > 0);
		assert.ok(PLAYER.radius < 1, 'radius should be < 1m for a character');
	});

	test('PLAYER height is a positive number', () => {
		assert.ok(typeof PLAYER.height === 'number');
		assert.ok(PLAYER.height > 1, 'height should be > 1m');
		assert.ok(PLAYER.height < 3, 'height should be < 3m');
	});

	test('PLAYER walk speed is slower than run speed', () => {
		assert.ok(PLAYER.walk < PLAYER.run, 'walk should be slower than run');
		assert.ok(PLAYER.walk > 0, 'walk should be positive');
		assert.ok(PLAYER.run > 0, 'run should be positive');
	});

	test('PLAYER turnLerp is positive', () => {
		assert.ok(PLAYER.turnLerp > 0, 'turnLerp should be positive for smoothing');
	});

	test('PLAYER jumpVel is positive (upward)', () => {
		assert.ok(PLAYER.jumpVel > 0, 'jumpVel should be positive');
	});

	test('PLAYER gravity is positive (magnitude)', () => {
		assert.ok(PLAYER.gravity > 0, 'gravity should be positive');
	});

	test('PLAYER values are physically reasonable', () => {
		// Walk ~4.2 m/s is a brisk walk (~15 km/h jog), reasonable for game character
		assert.ok(PLAYER.walk >= 2 && PLAYER.walk <= 8, 'walk speed in reasonable game range');
		// Run ~10.4 m/s (~37 km/h) is fast but ok for a game sprint
		assert.ok(PLAYER.run >= 5 && PLAYER.run <= 20, 'run speed in reasonable game range');
		// Height 1.72m is average human height
		assert.ok(PLAYER.height >= 1.4 && PLAYER.height <= 2.2, 'height in human range');
	});
});

describe('CLIPS mapping', () => {
	test('CLIPS has expected semantic action keys', () => {
		const expectedKeys = ['idle', 'fidget', 'walk', 'carry', 'run', 'sprint', 'air',
			'interact', 'pickup', 'open', 'repair', 'dig', 'talk', 'nod', 'device'];
		for (const key of expectedKeys) {
			assert.ok(key in CLIPS, `CLIPS should have key: ${key}`);
		}
	});

	test('CLIPS values are non-empty strings', () => {
		for (const [key, val] of Object.entries(CLIPS)) {
			assert.ok(typeof val === 'string', `CLIPS[${key}] should be a string`);
			assert.ok(val.length > 0, `CLIPS[${key}] should be non-empty`);
		}
	});

	test('CLIPS locomotion keys map to distinct clip names', () => {
		const locoKeys = ['idle', 'fidget', 'walk', 'carry', 'run', 'sprint', 'air'];
		const names = locoKeys.map((k) => CLIPS[k]);
		const unique = new Set(names);
		assert.equal(unique.size, names.length, 'locomotion clips should all be distinct');
	});

	test('CLIPS action keys map to distinct clip names', () => {
		const actionKeys = ['interact', 'pickup', 'open', 'repair', 'dig', 'talk', 'nod', 'device'];
		const names = actionKeys.map((k) => CLIPS[k]);
		const unique = new Set(names);
		assert.equal(unique.size, names.length, 'action clips should all be distinct');
	});

	test('CLIPS idle clip is named Idle_Loop', () => {
		assert.equal(CLIPS.idle, 'Idle_Loop');
	});

	test('CLIPS walk clip is named Walk_Loop', () => {
		assert.equal(CLIPS.walk, 'Walk_Loop');
	});

	test('CLIPS run clip is named Jog_Fwd_Loop', () => {
		assert.equal(CLIPS.run, 'Jog_Fwd_Loop');
	});
});

describe('Source file structure', () => {
	test('player.js exports PLAYER', () => {
		assert.ok(src.includes('export const PLAYER'), 'should export PLAYER');
	});

	test('player.js exports CLIPS', () => {
		assert.ok(src.includes('export const CLIPS'), 'should export CLIPS');
	});

	test('player.js exports loadPlayer function', () => {
		assert.ok(src.includes('export const loadPlayer'), 'should export loadPlayer');
	});

	test('player.js imports THREE', () => {
		assert.ok(src.includes("import * as THREE from 'three'"), 'should import three');
	});

	test('player.js imports GLTFLoader', () => {
		assert.ok(src.includes('GLTFLoader'), 'should import GLTFLoader');
	});

	test('player.js has collision handling with nearest-face ejection', () => {
		// The fix for standing-still-inside-a-box: nearest-face ejection instead of velocity-sign
		assert.ok(src.includes('nearest') || src.includes('b.min[axis] + b.max[axis]) / 2'),
			'should have nearest-face logic for standing-still collision');
	});

	test('player.js has error handling on model load', () => {
		assert.ok(src.includes('.catch') && src.includes('Player model load failed'),
			'should catch and log model load errors');
	});
});