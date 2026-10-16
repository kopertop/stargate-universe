/**
 * Unit tests for src/assets.js — asset root resolution.
 *
 * Run with:  node --test tests/assets.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * assets.js reads window.__ASSET_ROOT at import time and exports ASSETS.
 * We stub globalThis.window before importing to test the override path
 * and the default fallback when __ASSET_ROOT is unset.
 *
 * Note: assets.js uses bare `window` (not globalThis.window), so window
 * must exist on the global scope for the module to evaluate at all.
 */
import { test, describe, afterEach } from 'node:test';
import assert from 'node:assert/strict';

// Helper: dynamically import assets.js with a fresh window stub.
// Since assets.js reads window.__ASSET_ROOT at module-evaluation time,
// we must set up window BEFORE importing. We use a unique query string
// to bust the module cache so each test gets a fresh evaluation.
async function importAssets(assetRoot) {
	globalThis.window = { __ASSET_ROOT: assetRoot };
	const mod = await import(`../src/assets.js?test=${Date.now()}_${Math.random()}`);
	return mod.ASSETS;
}

describe('ASSETS default path', () => {
	afterEach(() => { delete globalThis.window; });

	test('falls back to "./" when window.__ASSET_ROOT is undefined', async () => {
		globalThis.window = {};
		const mod = await import(`../src/assets.js?test=${Date.now()}_${Math.random()}`);
		assert.equal(mod.ASSETS, './');
	});

	test('falls back to "./" when window.__ASSET_ROOT is null', async () => {
		const ASSETS = await importAssets(null);
		assert.equal(ASSETS, './');
	});
});

describe('ASSETS override path', () => {
	afterEach(() => { delete globalThis.window; });

	test('uses window.__ASSET_ROOT when set to "./assets/"', async () => {
		const ASSETS = await importAssets('./assets/');
		assert.equal(ASSETS, './assets/');
	});

	test('uses window.__ASSET_ROOT when set to an absolute URL', async () => {
		const ASSETS = await importAssets('https://cdn.example.com/sgu/');
		assert.equal(ASSETS, 'https://cdn.example.com/sgu/');
	});

	test('uses window.__ASSET_ROOT when set to a relative path', async () => {
		const ASSETS = await importAssets('../shared/');
		assert.equal(ASSETS, '../shared/');
	});
});

describe('ASSETS export type', () => {
	afterEach(() => { delete globalThis.window; });

	test('ASSETS is a string', async () => {
		const ASSETS = await importAssets('./assets/');
		assert.equal(typeof ASSETS, 'string');
	});

	test('ASSETS is not an empty string', async () => {
		const ASSETS = await importAssets('./');
		assert.ok(ASSETS.length > 0, 'ASSETS must not be empty');
	});
});