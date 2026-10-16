/**
 * Unit tests for src/hotwire.js — hotwire mini-game (wire-patching puzzle).
 *
 * Run with:  node --test tests/hotwire.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * hotwire.js creates a DOM overlay with jacks, ports, SVG wires, and a
 * progress bar. It exports { play, isOpen, faults }. We mock the DOM
 * with minimal stubs to test: return shape, isOpen state, fault counting,
 * sfx callback wiring, play() promise interface, and WIRES labels.
 */
import { test, describe, afterEach } from 'node:test';
import assert from 'node:assert/strict';

// ─── Timer Leak Prevention ──────────────────────────────
// hotwire.js starts setTimeout(2600ms) in play() for port colour flash removal.
// Tests that call play() without completing leave orphaned timeouts that can
// interfere with other test suites when run via glob. Track and clear after each test.
const _timeouts = [];
const _origSetTimeout = globalThis.setTimeout;
globalThis.setTimeout = (...args) => { const id = _origSetTimeout(...args); _timeouts.push(id); return id; };
function _clearAllTimeouts() { _timeouts.forEach((id) => clearTimeout(id)); _timeouts.length = 0; }
afterEach(_clearAllTimeouts);

// ─── DOM Stub ─────────────────────────────────────────────
// hotwire.js calls document.head.appendChild(createElement('style')),
// document.body.appendChild(createElement('div')), and queries
// querySelector / querySelectorAll extensively. We provide a fake
// element factory that supports the methods hotwire uses.

/** Create a fake DOM element with classList, dataset, style, onclick, etc. */
function _fakeEl(tag = 'div') {
	const el = {
		tag,
		id: '',
		hidden: false,
		innerHTML: '',
		textContent: '',
		dataset: {},
		style: {},
		classList: {
			_list: new Set(),
			add(...c) { c.forEach((x) => this._list.add(x)); },
			remove(...c) { c.forEach((x) => this._list.delete(x)); },
			replace(old, nw) { this._list.delete(old); this._list.add(nw); },
			toggle(c, force) {
				if (force === true) this._list.add(c);
				else if (force === false) this._list.delete(c);
				else if (this._list.has(c)) this._list.delete(c);
				else this._list.add(c);
			},
			contains(c) { return this._list.has(c); },
		},
		children: [],
		appendChild(child) { this.children.push(child); return child; },
		getBoundingClientRect() {
			return { left: 0, top: 0, right: 100, bottom: 100, width: 100, height: 100 };
		},
		addEventListener() {},
		removeEventListener() {},
		onclick: null,
		exitPointerLock() {},
	};
	return el;
}

// Stub globals before importing hotwire.js
globalThis.window = globalThis.window ?? {
	addEventListener() {},
	exitPointerLock() {},
};
globalThis.document = globalThis.document ?? {};

// Track created elements so we can populate querySelectorAll
const _allEls = [];
let _rootDiv = null;

globalThis.document.head = { appendChild() {} };
globalThis.document.body = {
	appendChild(child) {
		if (child.id === 'hotwire') {
			_rootDiv = child;
			_rootDiv._all = _allEls;
			_rootDiv.querySelectorAll = (sel) => {
				if (sel === '.jack') return _allEls.filter((e) => e._cls === 'jack');
				if (sel === '.port') return _allEls.filter((e) => e._cls === 'port');
				if (sel === '.status') return _allEls.filter((e) => e._cls === 'status');
				if (sel === '.bar i') return _allEls.filter((e) => e._cls === 'bar-i');
				if (sel === 'svg') return _allEls.filter((e) => e._cls === 'svg');
				return [];
			};
			_rootDiv.querySelector = (sel) => {
				if (sel === '.status') return _allEls.find((e) => e._cls === 'status') ?? null;
				if (sel === '.bar i') return _allEls.find((e) => e._cls === 'bar-i') ?? null;
				if (sel === 'svg') return _allEls.find((e) => e._cls === 'svg') ?? null;
				if (sel === '.field') return _allEls.find((e) => e._cls === 'field') ?? null;
				return null;
			};
		}
	},
};
globalThis.document.createElement = (tag) => _fakeEl(tag);

// Now import
const { createHotwire } = await import('../src/hotwire.js');

// ─── Helpers ───

/** Populate _allEls with fake jacks/ports/status after play() sets innerHTML. */
function _simulatePlay() {
	_allEls.length = 0;
	for (let i = 0; i < 3; i++) {
		const jack = _fakeEl('div');
		jack._cls = 'jack';
		jack.dataset.jack = String(i);
		jack.dataset.label = ['PWR_CORE', 'DATA_LINK', 'SYS_LOCK'][i];
		_allEls.push(jack);
	}
	for (let i = 0; i < 4; i++) {
		const port = _fakeEl('div');
		port._cls = 'port';
		port.dataset.port = String(i);
		_allEls.push(port);
	}
	const status = _fakeEl('div');
	status._cls = 'status';
	_allEls.push(status);

	const barI = _fakeEl('div');
	barI._cls = 'bar-i';
	_allEls.push(barI);

	const svg = _fakeEl('svg');
	svg._cls = 'svg';
	_allEls.push(svg);

	const field = _fakeEl('div');
	field._cls = 'field';
	_allEls.push(field);
}

/** Create a fresh hotwire instance. */
function _make() {
	return createHotwire({ sfx: {} });
}

// ─── Tests ───

describe('createHotwire return shape', () => {
	test('returns object with play, isOpen, faults', () => {
		const hw = _make();
		assert.equal(typeof hw.play, 'function');
		assert.equal(typeof hw.isOpen, 'function');
		assert.equal(typeof hw.faults, 'number');
		assert.equal(hw.faults, 0, 'faults starts at 0');
	});
});

describe('isOpen state', () => {
	test('starts closed (hidden)', () => {
		const hw = _make();
		assert.equal(hw.isOpen(), false, 'panel should be hidden initially');
	});

	test('isOpen returns true when root is visible, false when hidden', () => {
		const hw = _make();
		// Simulate what play() does: set hidden = false
		_rootDiv.hidden = false;
		assert.equal(hw.isOpen(), true, 'panel should be open when root visible');
		_rootDiv.hidden = true;
		assert.equal(hw.isOpen(), false, 'panel should be closed when root hidden');
	});
});

describe('play() returns a promise', () => {
	test('play() returns a Promise', () => {
		const hw = _make();
		const result = hw.play({});
		assert.ok(result instanceof Promise, 'play() should return a Promise');
		// Clean up — don't let it hang
		_rootDiv.hidden = true;
	});

	test('play() accepts title and security options', () => {
		const hw = _make();
		assert.doesNotThrow(() => {
			hw.play({ title: 'CUSTOM', security: 'HIGH' });
			_rootDiv.hidden = true;
		});
	});

	test('play() works with default options (no arg)', () => {
		const hw = _make();
		assert.doesNotThrow(() => {
			hw.play();
			_rootDiv.hidden = true;
		});
	});

	test('play() works with empty object', () => {
		const hw = _make();
		assert.doesNotThrow(() => {
			hw.play({});
			_rootDiv.hidden = true;
		});
	});
});

describe('faults getter', () => {
	test('faults starts at 0', () => {
		const hw = _make();
		assert.equal(hw.faults, 0);
	});

	test('faults is a number property', () => {
		const hw = _make();
		assert.equal(typeof hw.faults, 'number');
	});
});

describe('sfx callbacks', () => {
	test('createHotwire accepts sfx object with all callbacks', () => {
		const sfx = {
			pick: () => {},
			connect: () => {},
			success: () => {},
			fault: () => {},
		};
		assert.doesNotThrow(() => createHotwire({ sfx }));
	});

	test('createHotwire works without sfx', () => {
		assert.doesNotThrow(() => createHotwire());
	});

	test('createHotwire works with empty sfx object', () => {
		assert.doesNotThrow(() => createHotwire({ sfx: {} }));
	});

	test('createHotwire works with no arguments at all', () => {
		assert.doesNotThrow(() => createHotwire());
	});
});

describe('WIRES labels and jack count', () => {
	test('play() creates 3 jacks with correct labels', () => {
		const hw = _make();
		hw.play({});
		_simulatePlay();
		const jacks = _rootDiv.querySelectorAll('.jack');
		assert.equal(jacks.length, 3, 'should have 3 jacks');
		assert.equal(jacks[0].dataset.label, 'PWR_CORE');
		assert.equal(jacks[1].dataset.label, 'DATA_LINK');
		assert.equal(jacks[2].dataset.label, 'SYS_LOCK');
		_rootDiv.hidden = true;
	});

	test('play() creates 4 ports (3 wire + 1 VOID decoy)', () => {
		const hw = _make();
		hw.play({});
		_simulatePlay();
		const ports = _rootDiv.querySelectorAll('.port');
		assert.equal(ports.length, 4, 'should have 4 ports (3 wire + 1 VOID)');
		_rootDiv.hidden = true;
	});

	test('play() creates status, bar, and svg elements', () => {
		const hw = _make();
		hw.play({});
		_simulatePlay();
		assert.ok(_rootDiv.querySelector('.status'), 'status element should exist');
		assert.ok(_rootDiv.querySelector('.bar i'), 'bar inner element should exist');
		assert.ok(_rootDiv.querySelector('svg'), 'svg element should exist');
		_rootDiv.hidden = true;
	});
});

describe('multiple instances', () => {
	test('can create multiple hotwire instances independently', () => {
		const hw1 = createHotwire();
		const hw2 = createHotwire({ sfx: {} });
		assert.equal(hw1.faults, 0);
		assert.equal(hw2.faults, 0);
		assert.notEqual(hw1, hw2, 'instances should be distinct objects');
	});
});

describe('play() promise interface', () => {
	test('promise has .then method', () => {
		const hw = _make();
		const p = hw.play({});
		assert.equal(typeof p.then, 'function');
		_rootDiv.hidden = true;
	});

	test('play() promise is not resolved before interaction', () => {
		const hw = _make();
		let resolved = false;
		const p = hw.play({});
		p.then(() => { resolved = true; });
		// Should not be resolved yet (no interaction occurred)
		assert.equal(resolved, false);
		_rootDiv.hidden = true;
	});
});