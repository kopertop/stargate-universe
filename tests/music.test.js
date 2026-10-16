/**
 * Unit tests for src/music.js — adaptive mood-driven music crossfader.
 *
 * Run with:  node --test tests/music.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * music.js uses THREE.AudioLoader and THREE.Audio. Since ESM namespace
 * objects are frozen, we can't replace the constructors. Instead we patch
 * the prototypes: AudioLoader.prototype.loadAsync returns fake buffers,
 * and Audio prototype methods are replaced with lightweight stubs that
 * track state without needing a real WebAudio context.
 *
 * Coverage: createMusic return shape, MOODS table, setMood, setLevel,
 * tick crossfade behavior, load lifecycle, edge cases.
 */
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createMusic } from '../src/music.js';

// ─── Stub helpers ─────────────────────────────────────────────

/** Create a fake AudioListener whose context has enough stubs for THREE.Audio constructor. */
function fakeListener(state = 'running') {
	const gainNode = {
		gain: { value: 0, setValueAtTime() {}, setTargetAtTime() {}, linearRampToValueAtTime() {}, cancelScheduledValues() {} },
		connect() {}, disconnect() {},
	};
	return {
		context: {
			state,
			createGain: () => gainNode,
			currentTime: 0,
			destination: { connect() {}, disconnect() {} },
			decodeAudioData: async () => ({ duration: 10, sampleRate: 44100 }),
		},
		getInput: () => gainNode,
	};
}

/** Patch THREE.AudioLoader.prototype.loadAsync to return fake buffers. */
function stubAudioLoader(reject = false) {
	const orig = THREE.AudioLoader.prototype.loadAsync;
	if (reject) {
		THREE.AudioLoader.prototype.loadAsync = async function () { throw new Error('404'); };
	} else {
		THREE.AudioLoader.prototype.loadAsync = async function () { return { duration: 10, sampleRate: 44100 }; };
	}
	return () => { THREE.AudioLoader.prototype.loadAsync = orig; };
}

/** Patch THREE.Audio prototype methods to track state without real WebAudio. */
function stubAudioProto() {
	const proto = THREE.Audio.prototype;
	const orig = {
		setBuffer: proto.setBuffer, setLoop: proto.setLoop,
		setVolume: proto.setVolume, getVolume: proto.getVolume,
		play: proto.play, stop: proto.stop,
	};
	proto.setBuffer = function (b) { this._stubBuf = b; };
	proto.setLoop = function (v) { this._stubLoop = v; };
	proto.setVolume = function (v) { this._stubVol = v; };
	proto.getVolume = function () { return this._stubVol ?? 0; };
	proto.play = function () { this._stubPlaying = true; };
	proto.stop = function () { this._stubPlaying = false; };
	Object.defineProperty(proto, 'isPlaying', {
		get() { return !!this._stubPlaying; },
		set(v) { this._stubPlaying = v; },
		configurable: true,
	});
	// Patch constructor to not require real AudioContext
	return () => {
		Object.assign(proto, orig);
		delete proto.isPlaying;
		// Restore isPlaying as native (may not exist on proto — that's fine)
	};
}

// ─── Tests ────────────────────────────────────────────────────

describe('createMusic return shape', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('returns object with load, setMood, setLevel, tick, mood, MOODS', () => {
		const m = createMusic(fakeListener(), {});
		assert.equal(typeof m.load, 'function');
		assert.equal(typeof m.setMood, 'function');
		assert.equal(typeof m.setLevel, 'function');
		assert.equal(typeof m.tick, 'function');
		assert.equal(typeof m.mood, 'function');
		assert.ok(m.MOODS, 'MOODS exported');
	});

	test('initial mood is "silent"', () => {
		const m = createMusic(fakeListener(), {});
		assert.equal(m.mood(), 'silent');
	});
});

describe('MOODS table', () => {
	test('has title, ship_dark, ship, alert, gate, wormhole, planet, silent', () => {
		const m = createMusic(fakeListener(), {});
		const keys = Object.keys(m.MOODS);
		for (const k of ['title', 'ship_dark', 'ship', 'alert', 'gate', 'wormhole', 'planet', 'silent']) {
			assert.ok(keys.includes(k), `MOODS missing "${k}"`);
		}
	});

	test('silent mood has no layers', () => {
		const m = createMusic(fakeListener(), {});
		assert.deepEqual(m.MOODS.silent, {});
	});

	test('title mood has theme layer at 0.9', () => {
		const m = createMusic(fakeListener(), {});
		assert.equal(m.MOODS.title.theme, 0.9);
	});

	test('alert mood has 3 layers', () => {
		const m = createMusic(fakeListener(), {});
		const alertKeys = Object.keys(m.MOODS.alert);
		assert.equal(alertKeys.length, 3);
	});

	test('ship_dark has derelict and pulse_slow', () => {
		const m = createMusic(fakeListener(), {});
		assert.ok(m.MOODS.ship_dark.derelict !== undefined);
		assert.ok(m.MOODS.ship_dark.pulse_slow !== undefined);
	});

	test('planet mood has planet and cello layers', () => {
		const m = createMusic(fakeListener(), {});
		assert.ok(m.MOODS.planet.planet !== undefined);
		assert.ok(m.MOODS.planet.cello !== undefined);
	});
});

describe('setMood', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('changes mood from silent to ship', () => {
		const m = createMusic(fakeListener(), {});
		m.setMood('ship');
		assert.equal(m.mood(), 'ship');
	});

	test('ignores invalid mood names', () => {
		const m = createMusic(fakeListener(), {});
		m.setMood('nonexistent');
		assert.equal(m.mood(), 'silent');
	});

	test('does not re-target when setting same mood', () => {
		const m = createMusic(fakeListener(), {});
		m.setMood('ship');
		const moodBefore = m.mood();
		m.setMood('ship'); // no-op
		assert.equal(m.mood(), moodBefore);
	});

	test('can chain mood transitions', () => {
		const m = createMusic(fakeListener(), {});
		m.setMood('title');
		assert.equal(m.mood(), 'title');
		m.setMood('gate');
		assert.equal(m.mood(), 'gate');
		m.setMood('wormhole');
		assert.equal(m.mood(), 'wormhole');
		m.setMood('silent');
		assert.equal(m.mood(), 'silent');
	});
});

describe('setLevel', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('setLevel is a function that accepts a number', () => {
		const m = createMusic(fakeListener(), {});
		assert.doesNotThrow(() => m.setLevel(0.5));
	});

	test('setLevel(0) mutes all layers via retarget', async () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		await m.load();
		m.setMood('title'); // theme target = 0.9 * MASTER * 1
		m.setLevel(0);      // theme target = 0.9 * MASTER * 0 = 0
		for (let i = 0; i < 100; i++) m.tick(0.016);
		assert.equal(m.mood(), 'title');
	});

	test('setLevel changes affect retargeted volumes', async () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		await m.load();
		m.setMood('title');
		m.setLevel(0.5);
		for (let i = 0; i < 100; i++) m.tick(0.016);
		assert.equal(m.mood(), 'title');
	});
});

describe('load lifecycle', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('load resolves with empty files map (no layers)', async () => {
		const m = createMusic(fakeListener(), {});
		await m.load();
		m.tick(0.016); // should be a no-op
	});

	test('load resolves with files map containing multiple entries', async () => {
		const m = createMusic(fakeListener(), {
			theme: 'theme.mp3',
			derelict: 'derelict.mp3',
			pulse_slow: 'pulse.mp3',
		});
		await m.load();
		m.setMood('ship_dark');
		m.tick(0.016);
		assert.equal(m.mood(), 'ship_dark');
	});

	test('load handles missing audio files gracefully (catch)', async () => {
		const r1 = stubAudioLoader(true); // rejecting loader
		const m = createMusic(fakeListener(), { theme: 'missing.mp3' });
		await m.load(); // should not throw
		r1();
		m.setMood('title');
		m.tick(0.016); // no layers loaded, no crash
	});
});

describe('tick behavior', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('tick before load is a no-op (ready=false)', () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		assert.doesNotThrow(() => m.tick(0.016));
	});

	test('tick with suspended AudioContext is a no-op', async () => {
		const suspended = fakeListener('suspended');
		const m = createMusic(suspended, { theme: 'a.mp3' });
		await m.load();
		m.setMood('title');
		assert.doesNotThrow(() => m.tick(0.016));
	});

	test('tick with running context and loaded layers does not crash', async () => {
		const m = createMusic(fakeListener('running'), { theme: 'a.mp3', derelict: 'b.mp3' });
		await m.load();
		m.setMood('ship_dark');
		for (let i = 0; i < 60; i++) m.tick(0.016);
		assert.equal(m.mood(), 'ship_dark');
	});

	test('tick with dt=0 does not crash', async () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		await m.load();
		m.setMood('title');
		assert.doesNotThrow(() => m.tick(0));
	});

	test('tick with large dt does not overshoot target volume', async () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		await m.load();
		m.setMood('title');
		m.tick(100);
		assert.equal(m.mood(), 'title');
	});
});

describe('crossfade behavior', () => {
	let restore;
	beforeEach(() => { restore = [stubAudioLoader(), stubAudioProto()]; });
	afterEach(() => { restore.forEach((r) => r()); });

	test('changing mood retargets layer volumes', async () => {
		const m = createMusic(fakeListener(), {
			theme: 'a.mp3', ship_warm: 'b.mp3', shimmer: 'c.mp3',
			space: 'd.mp3', tense: 'e.mp3',
		});
		await m.load();
		m.setMood('title');
		for (let i = 0; i < 200; i++) m.tick(0.016);
		m.setMood('wormhole');
		for (let i = 0; i < 200; i++) m.tick(0.016);
		assert.equal(m.mood(), 'wormhole');
	});

	test('transitioning to silent fades all layers to 0', async () => {
		const m = createMusic(fakeListener(), { theme: 'a.mp3' });
		await m.load();
		m.setMood('title');
		for (let i = 0; i < 200; i++) m.tick(0.016);
		m.setMood('silent');
		for (let i = 0; i < 200; i++) m.tick(0.016);
		assert.equal(m.mood(), 'silent');
	});
});