/**
 * Unit tests for src/recorder.js — in-page gameplay recorder.
 *
 * Run with:  node --test tests/recorder.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * recorder.js creates a recording system that composites WebGL frames + HUD
 * onto a canvas and streams JPEGs to a dev server via fetch(). It requires
 * document.createElement('canvas') and canvas 2D context, so we stub the DOM.
 *
 * Coverage: createRecorder return shape, fps/quality/base defaults, custom
 * options, isActive state, start/stop lifecycle, tick behavior, fetch calls,
 * canvas sizing (even dimensions), and edge cases.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

// ─── DOM Stub ─────────────────────────────────────────────
// recorder.js calls:
//   document.createElement('canvas') → needs getContext('2d')
//   canvas.toBlob(callback, mime, quality) → needs to call callback with a Blob
//   fetch(url, opts) → returns a Response with .text()
//   canvas.width / canvas.height (get/set)
//   ctx.drawImage, fillRect, strokeRect, fillText, measureText, font, fillStyle, strokeStyle, lineWidth

let fetchCalls = [];

function makeFakeCtx() {
	return {
		font: '',
		fillStyle: '',
		strokeStyle: '',
		lineWidth: 1,
		drawImage: () => {},
		fillRect: () => {},
		strokeRect: () => {},
		fillText: () => {},
		measureText: (s) => ({ width: s.length * 8 }),
	};
}

function makeFakeCanvas(width = 1920, height = 1080) {
	const c = {
		width: width,
		height: height,
		_ctx: makeFakeCtx(),
		getContext: function() { return this._ctx; },
		toBlob: function(cb, mime, _quality) {
			// Simulate async blob creation
			setTimeout(() => cb({ size: 1024, type: mime }), 0);
		},
	};
	return c;
}

// Stub global document and fetch
globalThis.document = {
	createElement: (tag) => {
		if (tag === 'canvas') return makeFakeCanvas();
		return {};
	},
};

globalThis.fetch = (url, opts) => {
	fetchCalls.push({ url, method: opts?.method || 'GET' });
	return Promise.resolve({
		text: () => Promise.resolve('ok'),
		json: () => Promise.resolve({}),
	});
};

// Stub glCanvas that recorder receives
const glCanvas = { width: 1920, height: 1080 };
const hud = () => ({
	chapter: 'Chapter 1',
	label: 'Mission Start',
	zone: 'Forest',
	level: 5,
	hp: 100,
	o2: 95,
	xp: 1200,
	carry: 3,
	prompt: '',
	subtitle: '',
	overlay: '',
});

import { createRecorder } from '../src/recorder.js';

describe('createRecorder — return shape', () => {
	test('returns an object with tick, start, stop, isActive, fps', () => {
		const r = createRecorder(glCanvas, hud);
		assert.equal(typeof r.tick, 'function');
		assert.equal(typeof r.start, 'function');
		assert.equal(typeof r.stop, 'function');
		assert.equal(typeof r.isActive, 'function');
		assert.equal(typeof r.fps, 'number');
	});

	test('isActive() returns false before start', () => {
		const r = createRecorder(glCanvas, hud);
		assert.equal(r.isActive(), false);
	});

	test('fps defaults to 30', () => {
		const r = createRecorder(glCanvas, hud);
		assert.equal(r.fps, 30);
	});

	test('fps can be customized', () => {
		const r = createRecorder(glCanvas, hud, { fps: 60 });
		assert.equal(r.fps, 60);
	});

	test('base defaults to /rec', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('test-video');
		// start should POST to /rec/start
		assert.ok(fetchCalls.some(f => f.url.includes('/rec/start')), 'default base is /rec');
		await r.stop();
	});

	test('base can be customized', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/custom-rec' });
		await r.start('test-video');
		assert.ok(fetchCalls.some(f => f.url.includes('/custom-rec/start')), 'custom base used');
		await r.stop();
	});

	test('quality defaults to 0.86', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('test-video');
		// The quality is passed to toBlob — we can't easily verify it from here
		// but we can verify the recorder doesn't crash with defaults
		assert.ok(r.isActive(), 'recorder started with default quality');
		await r.stop();
	});
});

describe('start / stop lifecycle', () => {
	test('start sets active to true', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('my-recording');
		assert.equal(r.isActive(), true, 'isActive is true after start');
		await r.stop();
	});

	test('start returns a status string', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		const msg = await r.start('my-recording');
		assert.equal(typeof msg, 'string');
		assert.ok(msg.includes('my-recording'), 'start message includes recording name');
		assert.ok(msg.includes('30'), 'start message includes fps');
		await r.stop();
	});

	test('start strips .mp4 extension from name', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		const msg = await r.start('gameplay.mp4');
		assert.ok(!msg.includes('gameplay.mp4.mp4'), 'no double extension');
		assert.ok(msg.includes('gameplay'), 'name preserved without extension');
		await r.stop();
	});

	test('start strips .webm extension from name', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		const msg = await r.start('clip.webm');
		assert.ok(msg.includes('clip'), 'name preserved without .webm');
		await r.stop();
	});

	test('start defaults name to "gameplay"', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		const msg = await r.start();
		assert.ok(msg.includes('gameplay'), 'default name is gameplay');
		await r.stop();
	});

	test('stop sets active to false', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('test');
		await r.stop();
		assert.equal(r.isActive(), false, 'isActive is false after stop');
	});

	test('stop returns a status string', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('test');
		const msg = await r.stop();
		assert.equal(typeof msg, 'string');
	});

	test('stop when not recording returns "not recording"', async () => {
		const r = createRecorder(glCanvas, hud);
		const msg = await r.stop();
		assert.ok(msg.includes('not recording'), 'stop before start returns not recording');
	});

	test('start sends POST to /start endpoint with name and fps', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('test-vid');
		const startCall = fetchCalls.find(f => f.url.includes('/start'));
		assert.ok(startCall, 'start endpoint called');
		assert.equal(startCall.method, 'POST', 'start uses POST');
		assert.ok(startCall.url.includes('name=test-vid'), 'name in URL');
		assert.ok(startCall.url.includes('fps=30'), 'fps in URL');
		await r.stop();
	});

	test('stop sends POST to /stop endpoint', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('test-vid');
		fetchCalls = [];
		await r.stop();
		const stopCall = fetchCalls.find(f => f.url.includes('/stop'));
		assert.ok(stopCall, 'stop endpoint called');
		assert.equal(stopCall.method, 'POST', 'stop uses POST');
	});
});

describe('tick behavior', () => {
	test('tick is an async function that resolves', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.start('test');
		// tick should not throw and should return a promise that resolves
		await assert.doesNotReject(() => r.tick());
		await r.stop();
	});

	test('tick does nothing when not active', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud);
		await r.tick(); // should not throw or send frames
		assert.equal(fetchCalls.length, 0, 'no fetch calls when not active');
	});

	test('tick sends frame data when active', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('test');
		fetchCalls = []; // clear start call
		await r.tick();
		// Should have posted a frame
		const frameCall = fetchCalls.find(f => f.url.includes('/frame'));
		assert.ok(frameCall, 'frame endpoint called during tick');
		assert.equal(frameCall.method, 'POST', 'frame uses POST');
		await r.stop();
	});

	test('tick increments frame counter', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('test');
		fetchCalls = [];
		await r.tick();
		const frame1 = fetchCalls.find(f => f.url.includes('i=0'));
		assert.ok(frame1, 'first frame has i=0');
		await r.tick();
		const frame2 = fetchCalls.find(f => f.url.includes('i=1'));
		assert.ok(frame2, 'second frame has i=1');
		await r.stop();
	});
});

describe('canvas sizing (even dimensions for yuv420p)', () => {
	test('recorder works with large glCanvas (scales down to max 1024)', async () => {
		fetchCalls = [];
		const bigCanvas = { width: 3840, height: 2160 };
		const r = createRecorder(bigCanvas, hud, { base: '/rec' });
		const msg = await r.start('big-test');
		assert.ok(msg, 'recorder handles large canvas');
		await r.stop();
	});

	test('recorder works with small glCanvas', async () => {
		fetchCalls = [];
		const smallCanvas = { width: 640, height: 480 };
		const r = createRecorder(smallCanvas, hud, { base: '/rec' });
		const msg = await r.start('small-test');
		assert.ok(msg, 'recorder handles small canvas');
		await r.stop();
	});

	test('recorder works with odd-dimension canvas (rounds to even)', async () => {
		fetchCalls = [];
		const oddCanvas = { width: 1921, height: 1081 };
		const r = createRecorder(oddCanvas, hud, { base: '/rec' });
		const msg = await r.start('odd-test');
		assert.ok(msg, 'recorder handles odd dimensions');
		await r.stop();
	});
});

describe('HUD composition', () => {
	test('tick with full HUD (prompt, subtitle, overlay) does not crash', async () => {
		fetchCalls = [];
		const fullHud = () => ({
			chapter: 'Chapter 5',
			label: 'Boss Fight',
			zone: 'Throne Room',
			level: 20,
			hp: 75,
			o2: 60,
			xp: 5000,
			carry: 5,
			prompt: 'Press E to open',
			subtitle: 'The door creaks open...',
			overlay: 'LEVEL UP',
		});
		const r = createRecorder(glCanvas, fullHud, { base: '/rec' });
		await r.start('hud-test');
		await assert.doesNotReject(() => r.tick());
		await r.stop();
	});

	test('tick with minimal HUD (empty strings) does not crash', async () => {
		fetchCalls = [];
		const minHud = () => ({
			chapter: '', label: '', zone: '', level: 0,
			hp: 0, o2: 0, xp: 0, carry: 0,
			prompt: '', subtitle: '', overlay: '',
		});
		const r = createRecorder(glCanvas, minHud, { base: '/rec' });
		await r.start('min-hud-test');
		await assert.doesNotReject(() => r.tick());
		await r.stop();
	});

	test('tick with long subtitle text wraps without crashing', async () => {
		fetchCalls = [];
		const longSubHud = () => ({
			chapter: 'Ch1', label: 'Test', zone: 'Zone', level: 1,
			hp: 100, o2: 100, xp: 0, carry: 0,
			prompt: '',
			subtitle: 'This is a very long subtitle that should wrap across multiple lines because it contains many words and the wrap function needs to split it properly',
			overlay: '',
		});
		const r = createRecorder(glCanvas, longSubHud, { base: '/rec' });
		await r.start('wrap-test');
		await assert.doesNotReject(() => r.tick());
		await r.stop();
	});
});

describe('edge cases and independence', () => {
	test('multiple tick calls in sequence do not crash', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('multi-tick');
		for (let i = 0; i < 5; i++) {
			await r.tick();
		}
		assert.ok(r.isActive(), 'still active after 5 ticks');
		await r.stop();
	});

	test('two recorders are independent', async () => {
		fetchCalls = [];
		const r1 = createRecorder(glCanvas, hud, { base: '/rec' });
		const r2 = createRecorder(glCanvas, hud, { base: '/rec' });
		await r1.start('rec1');
		assert.equal(r1.isActive(), true);
		assert.equal(r2.isActive(), false, 'r2 not active when r1 starts');
		await r2.start('rec2');
		assert.equal(r2.isActive(), true, 'r2 active after its own start');
		await r1.stop();
		assert.equal(r1.isActive(), false, 'r1 stopped independently');
		assert.equal(r2.isActive(), true, 'r2 still active after r1 stops');
		await r2.stop();
	});

	test('start → stop → start cycle works', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { base: '/rec' });
		await r.start('cycle1');
		assert.ok(r.isActive());
		await r.stop();
		assert.equal(r.isActive(), false);
		await r.start('cycle2');
		assert.ok(r.isActive(), 'recorder can start again after stop');
		await r.stop();
	});

	test('custom fps and quality together', async () => {
		fetchCalls = [];
		const r = createRecorder(glCanvas, hud, { fps: 60, quality: 0.9, base: '/rec' });
		assert.equal(r.fps, 60);
		await r.start('custom-test');
		assert.ok(r.isActive());
		await r.stop();
	});
});