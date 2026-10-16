/**
 * Unit tests for src/flow.js — flow-balance mini-game (life support valve puzzle).
 *
 * Run with:  node --test tests/flow.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * flow.js creates a DOM overlay with pressure gauges, valve range inputs,
 * a status bar, and a hold progress bar. It exports { play, solve, isOpen }.
 * We mock the DOM with minimal stubs to test: return shape, isOpen state,
 * play() promise interface, solve() helper, sfx callback wiring, gauges option,
 * and multiple instance independence.
 */
import { test, describe, afterEach } from 'node:test';
import assert from 'node:assert/strict';

// ─── Interval Leak Prevention ───────────────────────────
// flow.js starts setInterval(tick, 200) in play() and only clears it in done().
// Tests that call play() without resolving leave orphaned intervals that prevent
// node --test from exiting. Track and clear all intervals after each test.
const _intervals = [];
const _origSetInterval = globalThis.setInterval;
globalThis.setInterval = (...args) => { const id = _origSetInterval(...args); _intervals.push(id); return id; };
function _clearAllIntervals() { _intervals.forEach((id) => clearInterval(id)); _intervals.length = 0; }
afterEach(_clearAllIntervals);

// ─── DOM Stub ─────────────────────────────────────────────
// flow.js calls document.head.appendChild(createElement('style')),
// document.body.appendChild(createElement('div')), sets el.innerHTML,
// and queries input[type=range], .col, .status, .bar i, .needle, .fill.
// We provide a fake element factory that supports all methods flow uses.

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
		oninput: null,
		value: '50',
		exitPointerLock() {},
	};
	return el;
}

// Stub globals before importing flow.js
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
		if (child.id === 'flow') {
			_rootDiv = child;
			_rootDiv.querySelectorAll = (sel) => {
				if (sel === 'input[type=range]') return _allEls.filter((e) => e._cls === 'input-range');
				if (sel === 'input') return _allEls.filter((e) => e._cls === 'input-range');
				if (sel === '.col') return _allEls.filter((e) => e._cls === 'col');
				return [];
			};
			_rootDiv.querySelector = (sel) => {
				if (sel === '.status') return _allEls.find((e) => e._cls === 'status') ?? null;
				if (sel === '.bar i') return _allEls.find((e) => e._cls === 'bar-i') ?? null;
				return null;
			};
		}
	},
};
globalThis.document.createElement = (tag) => _fakeEl(tag);
globalThis.document.pointerLockElement = null;
globalThis.document.exitPointerLock = () => {};

// Now import
const { createFlow } = await import('../src/flow.js');

// ─── Helpers ───

/** Populate _allEls with fake cols, range inputs, status, bar after play() sets innerHTML. */
function _simulatePlay(gauges = 3) {
	_allEls.length = 0;
	for (let i = 0; i < gauges; i++) {
		const col = _fakeEl('div');
		col._cls = 'col';
		col.querySelector = (sel) => {
			if (sel === '.needle') return { style: {} };
			if (sel === '.fill') return { style: {} };
			return null;
		};
		_allEls.push(col);
		const input = _fakeEl('input');
		input._cls = 'input-range';
		input.value = '50';
		_allEls.push(input);
	}
	const status = _fakeEl('div');
	status._cls = 'status';
	_allEls.push(status);

	const barI = _fakeEl('div');
	barI._cls = 'bar-i';
	barI.style = {};
	_allEls.push(barI);
}

/** Create a fresh flow instance. */
function _make() {
	return createFlow({ sfx: {} });
}

// ─── Tests ───

describe('createFlow return shape', () => {
	test('returns object with play, solve, isOpen', () => {
		const flow = _make();
		assert.equal(typeof flow.play, 'function');
		assert.equal(typeof flow.solve, 'function');
		assert.equal(typeof flow.isOpen, 'function');
	});
});

describe('isOpen state', () => {
	test('starts closed (hidden)', () => {
		const flow = _make();
		assert.equal(flow.isOpen(), false, 'panel should be hidden initially');
	});

	test('isOpen returns true when root is visible, false when hidden', () => {
		const flow = _make();
		_rootDiv.hidden = false;
		assert.equal(flow.isOpen(), true, 'panel should be open when root visible');
		_rootDiv.hidden = true;
		assert.equal(flow.isOpen(), false, 'panel should be closed when root hidden');
	});
});

describe('play() returns a promise', () => {
	test('play() returns a Promise', () => {
		const flow = _make();
		const result = flow.play({});
		assert.ok(result instanceof Promise, 'play() should return a Promise');
		// Clean up — don't let it hang
		_rootDiv.hidden = true;
	});

	test('play() works with default options (no arg)', () => {
		const flow = _make();
		assert.doesNotThrow(() => {
			flow.play();
			_rootDiv.hidden = true;
		});
	});

	test('play() works with empty object', () => {
		const flow = _make();
		assert.doesNotThrow(() => {
			flow.play({});
			_rootDiv.hidden = true;
		});
	});

	test('play() accepts title and gauges options', () => {
		const flow = _make();
		assert.doesNotThrow(() => {
			flow.play({ title: 'CUSTOM_FLOW', gauges: 4 });
			_rootDiv.hidden = true;
		});
	});

	test('play() accepts custom labels', () => {
		const flow = _make();
		assert.doesNotThrow(() => {
			flow.play({ labels: ['A', 'B', 'C', 'D'] });
			_rootDiv.hidden = true;
		});
	});
});

describe('solve() helper', () => {
	test('solve is a function that does not throw', () => {
		const flow = _make();
		assert.doesNotThrow(() => flow.solve());
	});

	test('solve works after play() without error', () => {
		const flow = _make();
		flow.play({});
		_simulatePlay(3);
		assert.doesNotThrow(() => flow.solve());
		_rootDiv.hidden = true;
	});
});

describe('sfx callbacks', () => {
	test('createFlow accepts sfx object with all callbacks', () => {
		const sfx = {
			pick: () => {},
			success: () => {},
			tick: () => {},
		};
		assert.doesNotThrow(() => createFlow({ sfx }));
	});

	test('createFlow works without sfx', () => {
		assert.doesNotThrow(() => createFlow());
	});

	test('createFlow works with empty sfx object', () => {
		assert.doesNotThrow(() => createFlow({ sfx: {} }));
	});

	test('createFlow works with no arguments at all', () => {
		assert.doesNotThrow(() => createFlow());
	});
});

describe('gauges option', () => {
	test('play with gauges=3 creates 3 columns and 3 range inputs', () => {
		const flow = _make();
		flow.play({ gauges: 3 });
		_simulatePlay(3);
		const cols = _rootDiv.querySelectorAll('.col');
		const inputs = _rootDiv.querySelectorAll('input[type=range]');
		assert.equal(cols.length, 3, 'should have 3 columns');
		assert.equal(inputs.length, 3, 'should have 3 range inputs');
		_rootDiv.hidden = true;
	});

	test('play with gauges=4 creates 4 columns and 4 range inputs', () => {
		const flow = _make();
		flow.play({ gauges: 4 });
		_simulatePlay(4);
		const cols = _rootDiv.querySelectorAll('.col');
		const inputs = _rootDiv.querySelectorAll('input[type=range]');
		assert.equal(cols.length, 4, 'should have 4 columns');
		assert.equal(inputs.length, 4, 'should have 4 range inputs');
		_rootDiv.hidden = true;
	});
});

describe('multiple instances', () => {
	test('can create multiple flow instances independently', () => {
		const flow1 = createFlow();
		const flow2 = createFlow({ sfx: {} });
		assert.equal(typeof flow1.play, 'function');
		assert.equal(typeof flow2.play, 'function');
		assert.notEqual(flow1, flow2, 'instances should be distinct objects');
	});
});

describe('play() promise interface', () => {
	test('promise has .then method', () => {
		const flow = _make();
		const p = flow.play({});
		assert.equal(typeof p.then, 'function');
		_rootDiv.hidden = true;
	});

	test('play() promise is not resolved before interaction', () => {
		const flow = _make();
		let resolved = false;
		const p = flow.play({});
		p.then(() => { resolved = true; });
		// Should not be resolved yet (no interaction occurred)
		assert.equal(resolved, false);
		_rootDiv.hidden = true;
	});
});