/**
 * Unit tests for src/ui.js — WoW-style HUD + Kino Remote full-screen menu.
 *
 * Run with:  node --test tests/ui.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * ui.js imports rpg.js and settings.js (which import assets.js), so we stub
 * window.__ASSET_ROOT, localStorage, and the DOM before importing.
 *
 * Strategy: We provide a global document.createElement that returns fake
 * elements with a "smart" querySelector — it returns pre-made child elements
 * for known CSS selectors used by ui.js and settings.js. All elements share
 * the same child lookup, so querySelector works regardless of which element
 * it's called on.
 *
 * Coverage: createUI return shape, isRemoteOpen, setPrompt, subtitle,
 * toast, setClock, zone, showChapter, showTitle, refreshPlayer,
 * refreshTracker, drawMinimap, renderRemote, openRemote tab switching.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

// ─── Global Stubs ─────────────────────────────────────────

globalThis.window = globalThis.window ?? {};
globalThis.window.__ASSET_ROOT = './';

const _store = new Map();
globalThis.localStorage = {
	getItem(k) { return _store.get(k) ?? null; },
	setItem(k, v) { _store.set(k, String(v)); },
	removeItem(k) { _store.delete(k); },
};
globalThis.window.localStorage = globalThis.localStorage;

globalThis.performance = globalThis.performance ?? { now: () => Date.now() };
globalThis.window.performance = globalThis.performance;

// ─── DOM Stub ─────────────────────────────────────────────

function _fakeCtx() {
	return {
		clearRect() {}, save() {}, restore() {}, translate() {}, rotate() {},
		scale() {}, fillRect() {}, strokeRect() {}, beginPath() {}, arc() {},
		fill() {}, stroke() {}, moveTo() {}, lineTo() {}, closePath() {},
		fillStyle: '', strokeStyle: '', lineWidth: 1,
		createLinearGradient() { return { addColorStop() {} }; },
		createRadialGradient() { return { addColorStop() {} }; },
	};
}

/**
 * Create a fake DOM element with synced className/classList.
 * querySelector and querySelectorAll use a shared global child registry.
 */
function _fakeEl(tag = 'div') {
	const _list = new Set();
	const el = {
		tag, id: '', hidden: false, innerHTML: '', textContent: '',
		dataset: {}, style: {},
		children: [], childNodes: [],
		appendChild(child) { this.children.push(child); return child; },
		removeChild(child) { const i = this.children.indexOf(child); if (i >= 0) this.children.splice(i, 1); return child; },
		remove() {},
		getBoundingClientRect() { return { left: 0, top: 0, right: 100, bottom: 100, width: 100, height: 100 }; },
		addEventListener() {}, removeEventListener() {},
		onclick: null, oninput: null, value: '50', checked: false,
		exitPointerLock() {},
		getContext() { return _fakeCtx(); },
		firstElementChild: null, lastElementChild: null, nextElementSibling: null,
	};
	// querySelector uses the shared child registry
	el.querySelector = (sel) => _childRegistry[sel] ?? _makeOnDemand(sel);
	el.querySelectorAll = (sel) => {
		if (sel === '#pf .bar i' && _childRegistry['#pf .bar i']) return [_childRegistry['#pf .bar i'], _childRegistry['#pf .bar i'], _childRegistry['#pf .bar i']];
		if (sel === '#menu button') return _childRegistry['#menu button'] ? [_childRegistry['#menu button']] : [];
		if (sel === '#ab') return _childRegistry['#ab'] ? [_childRegistry['#ab']] : [];
		if (sel === '#log') return _childRegistry['#log'] ? [_childRegistry['#log']] : [];
		if (sel === '[data-tab]') return [];
		if (sel === '[data-chapter]') return [];
		if (sel === '[data-s]') return [];
		if (sel === '[data-equip]') return [];
		if (sel === '[data-use]') return [];
		if (sel === '[data-item]') return [];
		if (sel === '[data-unequip]') return [];
		if (sel === '[data-talent]') return [];
		if (sel === '[data-dial]') return [];
		if (sel === '[data-launch]') return [];
		return [];
	};
	// Synced classList + className
	el.classList = {
		_list,
		add(...c) { c.forEach((x) => { _list.add(x); }); },
		remove(...c) { c.forEach((x) => { _list.delete(x); }); },
		replace(old, nw) { _list.delete(old); _list.add(nw); },
		toggle(c, force) {
			if (force === true) _list.add(c);
			else if (force === false) _list.delete(c);
			else if (_list.has(c)) _list.delete(c);
			else _list.add(c);
		},
		contains(c) { return _list.has(c); },
	};
	let _className = '';
	Object.defineProperty(el, 'className', {
		get() { return _className; },
		set(v) {
			_className = String(v);
			_list.clear();
			_className.split(/\s+/).filter(Boolean).forEach((c) => _list.add(c));
		},
	});
	return el;
}

/** Make a fake element on demand for selectors we haven't pre-registered. */
function _makeOnDemand(sel) {
	const el = _fakeEl('div');
	// For settings-related selectors, ensure onclick can be set
	if (sel === '[data-reset]' || sel.startsWith('[data-action')) {
		el.onclick = null;
	}
	return el;
}

// ─── Shared child registry ─────────────────────────────────
// All querySelector calls look up here first. _makeUI() populates it before
// calling createUI(), so the closures inside createUI capture working lookups.

let _childRegistry = {};

function _makeHudChildren() {
	const barI = _fakeEl('i'); barI.style = {};
	const lvlEl = _fakeEl('span');
	const hpvEl = _fakeEl('b');
	const o2vEl = _fakeEl('b');
	const logEl = _fakeEl('div');
	const abEl = _fakeEl('div');
	const qtEl = _fakeEl('div');
	const mmCanvas = _fakeEl('canvas'); mmCanvas.getContext = () => _fakeCtx();
	const zoneEl = _fakeEl('div');
	const promptEl = _fakeEl('div'); promptEl.classList.add('hidden');
	const subEl = _fakeEl('div'); subEl.classList.add('hidden');
	const toastEl = _fakeEl('div'); toastEl.classList.add('hidden');
	const clockEl = _fakeEl('div'); clockEl.classList.add('hidden');
	const menuBtn = _fakeEl('button'); menuBtn.dataset = { tab: 'character' };

	// Extra elements for settings, chapter card, remote
	const resetBtn = _fakeEl('button'); resetBtn.onclick = null;
	const newBtn = _fakeEl('button'); newBtn.onclick = null;
	const continueBtn = _fakeEl('button'); continueBtn.addEventListener = () => {};
	const controlsBtn = _fakeEl('button'); controlsBtn.onclick = null;
	const chaptersBtn = _fakeEl('button'); chaptersBtn.addEventListener = () => {};
	const settingsBtn = _fakeEl('button'); settingsBtn.onclick = null;
	const settingsBody = _fakeEl('div');
	const ctlDiv = _fakeEl('div'); ctlDiv.classList.add('hidden');
	const chaptersDiv = _fakeEl('div'); chaptersDiv.classList.add('hidden');

	return {
		'.lvl': lvlEl, '.hpv': hpvEl, '.o2v': o2vEl,
		'#pf .bar i': barI, '#log': logEl, '#ab': abEl,
		'#qt': qtEl, '#mm canvas': mmCanvas, '#zone': zoneEl,
		'#prompt': promptEl, '#sub': subEl, '#toast': toastEl,
		'#clock': clockEl, '#menu button': menuBtn,
		// settings.js selectors
		'[data-reset]': resetBtn,
		'#settings-body': settingsBody,
		// showTitle selectors
		'[data-action="new"]': newBtn,
		'[data-action="continue"]': continueBtn,
		'[data-action="controls"]': controlsBtn,
		'[data-action="chapters"]': chaptersBtn,
		'[data-action="settings"]': settingsBtn,
		'.ctl': ctlDiv,
		'.chapters': chaptersDiv,
		// generic button fallback
		'button': newBtn,
	};
}

// ─── Document setup ────────────────────────────────────────

let _createdHud = null;
let _createdRemote = null;
let _createdChapter = null;

globalThis.document = globalThis.document ?? {};
globalThis.document.head = { appendChild() {} };
globalThis.document.body = {
	appendChild(child) {
		if (child.id === 'remote') _createdRemote = child;
		else if (child.id === 'chapter') _createdChapter = child;
		else _createdHud = child;
	},
};
globalThis.document.exitPointerLock = () => {};
globalThis.document.pointerLockElement = null;

// Global createElement: always returns elements using the shared child registry
globalThis.document.createElement = (tag) => {
	const el = _fakeEl(tag);
	if (tag === 'canvas') el.getContext = () => _fakeCtx();
	return el;
};

globalThis.window.addEventListener = () => {};
globalThis.window.exitPointerLock = () => {};
globalThis.window.pointerLockElement = null;

globalThis.clearTimeout = () => {};
globalThis.setTimeout = () => 0;

// Now import
const { createUI } = await import('../src/ui.js');

// ─── Helper ───

function _makeUI(overrides = {}) {
	_createdHud = null;
	_createdRemote = null;
	_createdChapter = null;
	_childRegistry = _makeHudChildren();

	const ctx = {
		getWorldName: () => 'destiny',
		onDial: () => {}, onLaunchKino: () => {},
		canLaunchKino: () => false, planets: () => [],
		chapterTitle: () => 'Test Chapter',
		steps: () => [{ label: 'Step 1', objective: 'Do thing' }],
		stepIndex: () => 0, flags: new Set(),
		onResume: () => {}, onOpen: () => {},
		deckMap: () => ({ rooms: [], deck: 0, player: { x: 0, z: 0 }, current: null, discovered: [], waypoint: null }),
		shipStatus: () => [], clocks: () => [], lastScan: () => null,
		...overrides,
	};

	const ui = createUI(ctx);

	// Patch the created chapter card's firstElementChild for showTitle
	if (_createdChapter) {
		_createdChapter.firstElementChild = _fakeEl('div');
	}

	return { ui, ctx, children: _childRegistry, hud: _createdHud, remote: _createdRemote, chapter: _createdChapter };
}

// ─── Tests ───

describe('createUI return shape', () => {
	test('returns object with all expected methods', () => {
		const { ui } = _makeUI();
		for (const m of ['refreshPlayer', 'refreshTracker', 'drawMinimap', 'setPrompt',
			'subtitle', 'toast', 'setClock', 'zone', 'showChapter', 'showTitle',
			'openRemote', 'closeRemote', 'isRemoteOpen', 'renderRemote']) {
			assert.equal(typeof ui[m], 'function', `${m} should be a function`);
		}
	});
});

describe('isRemoteOpen state', () => {
	test('starts closed', () => {
		const { ui } = _makeUI();
		assert.equal(ui.isRemoteOpen(), false);
	});

	test('openRemote opens the remote', () => {
		const { ui } = _makeUI();
		ui.openRemote();
		assert.equal(ui.isRemoteOpen(), true);
	});

	test('closeRemote closes the remote', () => {
		const { ui } = _makeUI();
		ui.openRemote();
		ui.closeRemote();
		assert.equal(ui.isRemoteOpen(), false);
	});

	test('openRemote calls onOpen callback', () => {
		let opened = false;
		const { ui } = _makeUI({ onOpen: () => { opened = true; } });
		ui.openRemote();
		assert.equal(opened, true);
	});

	test('openRemote calls onOpen each time it opens from closed', () => {
		let count = 0;
		const { ui } = _makeUI({ onOpen: () => { count++; } });
		ui.openRemote();
		ui.closeRemote();
		ui.openRemote();
		assert.ok(count >= 1, 'onOpen should fire at least once');
	});

	test('closeRemote calls onResume callback', () => {
		let resumed = false;
		const { ui } = _makeUI({ onResume: () => { resumed = true; } });
		ui.openRemote();
		ui.closeRemote();
		assert.equal(resumed, true);
	});
});

describe('setPrompt', () => {
	test('with null hides the prompt', () => {
		const { ui, children } = _makeUI();
		ui.setPrompt(null);
		assert.ok(children['#prompt'].classList.contains('hidden'));
	});

	test('with a prompt object shows the prompt', () => {
		const { ui, children } = _makeUI();
		ui.setPrompt({ prompt: 'Open the door' });
		assert.ok(!children['#prompt'].classList.contains('hidden'));
	});

	test('with hold shows hold indicator', () => {
		const { ui, children } = _makeUI();
		ui.setPrompt({ prompt: 'Dig', hold: true, progress: 0.5 });
		assert.ok(!children['#prompt'].classList.contains('hidden'));
	});

	test('does not crash with undefined', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.setPrompt(undefined));
	});

	test('does not crash with empty string prompt', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.setPrompt({ prompt: '' }));
	});
});

describe('subtitle', () => {
	test('shows subtitle text with speaker name', () => {
		const { ui, children } = _makeUI();
		ui.subtitle('Rush', 'We need to move!');
		assert.ok(!children['#sub'].classList.contains('hidden'));
	});

	test('radio flag adds radio class', () => {
		const { ui, children } = _makeUI();
		ui.subtitle('Young', 'Copy that', { radio: true });
		assert.ok(!children['#sub'].classList.contains('hidden'));
		assert.ok(children['#sub'].classList.contains('radio'));
	});

	test('without radio flag does not add radio class', () => {
		const { ui, children } = _makeUI();
		ui.subtitle('Rush', 'Hello');
		assert.ok(!children['#sub'].classList.contains('radio'));
	});

	test('custom duration does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.subtitle('Rush', 'Test', { dur: 2.0 }));
	});
});

describe('toast', () => {
	test('shows toast text and unhides element', () => {
		const { ui, children } = _makeUI();
		ui.toast('Achievement unlocked!');
		assert.ok(!children['#toast'].classList.contains('hidden'));
		assert.equal(children['#toast'].textContent, 'Achievement unlocked!');
	});

	test('does not crash with no args', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.toast());
	});

	test('does not crash with custom duration', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.toast('Test', 1.5));
	});
});

describe('setClock', () => {
	test('with empty text hides the clock', () => {
		const { ui, children } = _makeUI();
		ui.setClock('');
		assert.ok(children['#clock'].classList.contains('hidden'));
	});

	test('with text shows the clock', () => {
		const { ui, children } = _makeUI();
		ui.setClock('04:32', 'urgent');
		assert.ok(!children['#clock'].classList.contains('hidden'));
		assert.equal(children['#clock'].textContent, '04:32');
	});

	test('urgent class is applied', () => {
		const { ui, children } = _makeUI();
		ui.setClock('01:00', 'urgent');
		assert.ok(children['#clock'].classList.contains('urgent'));
	});

	test('cool class is applied', () => {
		const { ui, children } = _makeUI();
		ui.setClock('05:00', 'cool');
		assert.ok(children['#clock'].classList.contains('cool'));
	});

	test('default class is empty (no urgent or cool)', () => {
		const { ui, children } = _makeUI();
		ui.setClock('03:00');
		assert.ok(!children['#clock'].classList.contains('urgent'));
		assert.ok(!children['#clock'].classList.contains('cool'));
	});
});

describe('zone', () => {
	test('sets zone text', () => {
		const { ui, children } = _makeUI();
		ui.zone('GATE_ROOM');
		assert.equal(children['#zone'].textContent, 'GATE_ROOM');
	});

	test('with null clears zone text', () => {
		const { ui, children } = _makeUI();
		ui.zone('GATE_ROOM');
		ui.zone(null);
		assert.equal(children['#zone'].textContent, '');
	});

	test('with undefined clears zone text', () => {
		const { ui, children } = _makeUI();
		ui.zone(undefined);
		assert.equal(children['#zone'].textContent, '');
	});
});

describe('showChapter', () => {
	test('does not crash with valid args', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.showChapter('Chapter 1', 'The Beginning', 'Start', () => {});
		});
	});

	test('does not crash with no callback', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.showChapter('Test', 'Sub', 'Btn');
		});
	});
});

describe('showTitle', () => {
	test('does not crash with save and chapters', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.showTitle({
				hasSave: true,
				onNew: () => {},
				onContinue: () => {},
				chapters: [{ id: 'ch1', title: 'Chapter 1' }],
				onChapter: () => {},
			});
		});
	});

	test('does not crash with no save', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.showTitle({ hasSave: false, onNew: () => {} });
		});
	});

	test('does not crash with no chapters', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.showTitle({ hasSave: false, onNew: () => {}, chapters: [] });
		});
	});
});

describe('refreshPlayer', () => {
	test('updates level display from rpg state', () => {
		const { ui, children } = _makeUI();
		ui.refreshPlayer();
		assert.equal(String(children['.lvl'].textContent), '1');
	});

	test('does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.refreshPlayer());
	});
});

describe('refreshTracker', () => {
	test('renders quest tracker with chapter title and steps', () => {
		const { ui, children } = _makeUI();
		ui.refreshTracker();
		assert.ok(children['#qt'].innerHTML.includes('Test Chapter'));
	});

	test('handles empty steps', () => {
		const { ui, children, ctx } = _makeUI();
		ctx.steps = () => [];
		ctx.stepIndex = () => 0;
		ui.refreshTracker();
		assert.ok(children['#qt'].innerHTML.includes('Test Chapter'));
	});
});

describe('drawMinimap', () => {
	test('does not crash with rooms data', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.drawMinimap({ rooms: [{ x0: 0, z0: 0, x1: 10, z1: 10 }], player: { x: 5, z: 5 }, yaw: 0 });
		});
	});

	test('does not crash with nodes data', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.drawMinimap({ nodes: [{ x: 3, z: 4, done: false }, { x: 6, z: 8, done: true }], player: { x: 0, z: 0 }, yaw: 0 });
		});
	});

	test('does not crash with gate and waypoint', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.drawMinimap({ rooms: [], gate: { x: 10, z: 10 }, waypoint: { x: 5, z: 5 }, player: { x: 0, z: 0 }, yaw: Math.PI });
		});
	});

	test('does not crash with empty data', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => {
			ui.drawMinimap({ player: { x: 0, z: 0 }, yaw: 0 });
		});
	});
});

describe('renderRemote', () => {
	test('does not crash when called directly', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.renderRemote());
	});

	test('does not crash after openRemote', () => {
		const { ui } = _makeUI();
		ui.openRemote();
		assert.doesNotThrow(() => ui.renderRemote());
	});
});

describe('openRemote tab selection', () => {
	test('openRemote with no arg does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote());
		assert.equal(ui.isRemoteOpen(), true);
	});

	test('openRemote with "ship" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('ship'));
		assert.equal(ui.isRemoteOpen(), true);
	});

	test('openRemote with "gate" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('gate'));
	});

	test('openRemote with "settings" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('settings'));
	});

	test('openRemote with "inventory" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('inventory'));
	});

	test('openRemote with "kino" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('kino'));
	});

	test('openRemote with "clocks" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('clocks'));
	});

	test('openRemote with "character" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('character'));
	});

	test('openRemote with "talents" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('talents'));
	});

	test('openRemote with "quest" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('quest'));
	});

	test('openRemote with "log" tab does not crash', () => {
		const { ui } = _makeUI();
		assert.doesNotThrow(() => ui.openRemote('log'));
	});
});

describe('multiple UI instances', () => {
	test('two UI instances are independent', () => {
		const a = _makeUI();
		const b = _makeUI();
		a.ui.openRemote();
		assert.equal(a.ui.isRemoteOpen(), true);
		assert.equal(b.ui.isRemoteOpen(), false, 'second UI should be independent');
	});
});