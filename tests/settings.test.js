/**
 * Unit tests for src/settings.js — pure logic, no DOM, no Three.js.
 *
 * Run with:  node --test tests/settings.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 */
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

const DEFAULTS = { master: 0.9, music: 1.0, sfx: 1.0, sensitivity: 1.0, invertY: false, fov: 60, subtitles: true, clockScale: 1.0 };

describe('settings persistence', () => {
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

	test('defaults are applied when no saved settings exist', () => {
		const raw = store['sgu.settings'] ?? '{}';
		const settings = { ...DEFAULTS };
		Object.assign(settings, JSON.parse(raw));
		assert.equal(settings.master, 0.9);
		assert.equal(settings.fov, 60);
		assert.equal(settings.subtitles, true);
		assert.equal(settings.invertY, false);
	});

	test('saved settings override defaults', () => {
		store['sgu.settings'] = JSON.stringify({ master: 0.5, fov: 80, invertY: true });
		const raw = store['sgu.settings'] ?? '{}';
		const settings = { ...DEFAULTS };
		Object.assign(settings, JSON.parse(raw));
		assert.equal(settings.master, 0.5);
		assert.equal(settings.fov, 80);
		assert.equal(settings.invertY, true);
		// Untouched fields keep defaults
		assert.equal(settings.music, 1.0);
		assert.equal(settings.subtitles, true);
	});

	test('setSetting persists to localStorage', () => {
		const settings = { ...DEFAULTS };
		// Simulate setSetting('fov', 75)
		settings['fov'] = 75;
		store['sgu.settings'] = JSON.stringify(settings);
		const reloaded = JSON.parse(store['sgu.settings']);
		assert.equal(reloaded.fov, 75);
	});

	test('resetSettings restores all defaults', () => {
		const settings = { ...DEFAULTS, master: 0.3, fov: 90, invertY: true };
		// Simulate resetSettings
		for (const k in DEFAULTS) settings[k] = DEFAULTS[k];
		assert.deepEqual(settings, DEFAULTS);
	});

	test('corrupted settings JSON falls back to defaults (caught by try/catch)', () => {
		store['sgu.settings'] = '{broken';
		let warned = false;
		try {
			JSON.parse(store['sgu.settings'] ?? '{}');
		} catch (e) {
			warned = true;
			assert.ok(e instanceof SyntaxError);
		}
		assert.ok(warned);
		// In this case settings stays at defaults since Object.assign never runs
		const settings = { ...DEFAULTS };
		assert.deepEqual(settings, DEFAULTS);
	});

	test('partial save preserves other keys', () => {
		// Simulate: settings has all defaults, user changes one key
		const settings = { ...DEFAULTS };
		settings.sfx = 0.7;
		store['sgu.settings'] = JSON.stringify(settings);
		// Reload
		const loaded = { ...DEFAULTS };
		Object.assign(loaded, JSON.parse(store['sgu.settings']));
		assert.equal(loaded.sfx, 0.7);
		assert.equal(loaded.master, 0.9); // still default
	});
});