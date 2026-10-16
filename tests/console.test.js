/**
 * Unit tests for src/console.js — hidden developer console (backquote toggle).
 *
 * Run with:  node --test tests/console.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * console.js creates a DOM overlay (#devcon) with a command input, output
 * pre, and keydown handlers. It exports { toggle, print, run, isOpen }.
 * We mock the DOM with minimal stubs to test: return shape, isOpen state,
 * toggle behavior, run() command dispatch, print() output, and the help
 * auto-command.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

// ─── DOM Stub ─────────────────────────────────────────────

/** Create a fake DOM element with the methods console.js uses. */
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
		addEventListener() {},
		removeEventListener() {},
		onclick: null,
		focus() {},
		blur() {},
		value: '',
		spellcheck: false,
		scrollTop: 0,
		scrollHeight: 0,
	};
	return el;
}

// Track the root div and its child elements (pre, input) per createConsole call
let _rootDiv = null;

globalThis.window = globalThis.window ?? {
	addEventListener() {},
	exitPointerLock() {},
	pointerLockElement: null,
};
globalThis.document = globalThis.document ?? {};
globalThis.document.head = { appendChild() {} };
globalThis.document.body = {
	appendChild(child) {
		if (child.id === 'devcon') _rootDiv = child;
	},
};
globalThis.document.createElement = (tag) => {
	const el = _fakeEl(tag);
	if (tag === 'div') {
		// console.js sets innerHTML then queries 'pre' and 'input'
		el._pre = _fakeEl('pre');
		el._input = _fakeEl('input');
		el.querySelector = (sel) => {
			if (sel === 'pre') return el._pre;
			if (sel === 'input') return el._input;
			return null;
		};
	}
	return el;
};
globalThis.document.exitPointerLock = () => {};

const { createConsole } = await import('../src/console.js');

// ─── Helpers ───

/** Create a console with a set of commands. Returns { con, pre, input }. */
function _make(commands = {}) {
	const con = createConsole(commands);
	return { con, pre: _rootDiv._pre, input: _rootDiv._input };
}

// ─── Tests ───

describe('createConsole return shape', () => {
	test('returns object with toggle, print, run, isOpen', () => {
		const { con } = _make({ foo: () => 'bar' });
		assert.equal(typeof con.toggle, 'function');
		assert.equal(typeof con.print, 'function');
		assert.equal(typeof con.run, 'function');
		assert.equal(typeof con.isOpen, 'function');
	});

	test('starts closed (hidden)', () => {
		const { con } = _make({});
		assert.equal(con.isOpen(), false, 'console should be hidden initially');
	});
});

describe('toggle behavior', () => {
	test('toggle() opens the console', () => {
		const { con } = _make({});
		con.toggle();
		assert.equal(con.isOpen(), true, 'console should be open after toggle()');
	});

	test('toggle(false) closes the console', () => {
		const { con } = _make({});
		con.toggle(); // open
		con.toggle(false);
		assert.equal(con.isOpen(), false, 'console should be closed after toggle(false)');
	});

	test('toggle(true) opens the console', () => {
		const { con } = _make({});
		con.toggle(true);
		assert.equal(con.isOpen(), true, 'console should be open after toggle(true)');
	});

	test('toggle() is idempotent toggle — open then close', () => {
		const { con } = _make({});
		con.toggle(); // open
		assert.equal(con.isOpen(), true);
		con.toggle(); // close
		assert.equal(con.isOpen(), false);
	});
});

describe('run() command dispatch', () => {
	test('runs a registered command and prints result', () => {
		const { con, pre } = _make({ greet: () => 'hello' });
		con.run('greet');
		assert.ok(pre.textContent.includes('hello'), 'should print command result');
	});

	test('prints the input line before running', () => {
		const { con, pre } = _make({ test: () => 'ok' });
		con.run('test');
		assert.ok(pre.textContent.includes('> test'), 'should echo the command line');
	});

	test('unknown command prints error message', () => {
		const { con, pre } = _make({});
		con.run('nonexistent');
		assert.ok(pre.textContent.includes('unknown command'), 'should print unknown command error');
	});

	test('empty command (just whitespace) does nothing', () => {
		const { con, pre } = _make({});
		const before = pre.textContent;
		con.run('   ');
		assert.equal(pre.textContent, before, 'should not print anything for whitespace-only input');
	});

	test('command that throws prints error message', () => {
		const { con, pre } = _make({ boom: () => { throw new Error('kaboom'); } });
		con.run('boom');
		assert.ok(pre.textContent.includes('error: kaboom'), 'should print error message for thrown exception');
	});

	test('command with arguments passes them through', () => {
		const { con, pre } = _make({ add: (a, b) => String(Number(a) + Number(b)) });
		con.run('add 3 5');
		assert.ok(pre.textContent.includes('8'), 'should pass arguments to command');
	});

	test('command returning null does not print result line', () => {
		const { con, pre } = _make({ silent: () => null });
		con.run('silent');
		assert.ok(pre.textContent.includes('> silent'), 'should echo the command');
		// The result line should not be appended (r != null check)
		const lines = pre.textContent.split('\n');
		const afterEcho = lines.slice(lines.findIndex((l) => l.includes('> silent')) + 1);
		assert.ok(!afterEcho.some((l) => l.includes('null') || l.includes('undefined')),
			'should not print null/undefined result');
	});

	test('command returning undefined does not print result line', () => {
		const { con, pre } = _make({ nothing: () => {} });
		con.run('nothing');
		assert.ok(pre.textContent.includes('> nothing'), 'should echo the command');
		const lines = pre.textContent.split('\n');
		const afterEcho = lines.slice(lines.findIndex((l) => l.includes('> nothing')) + 1);
		assert.ok(!afterEcho.some((l) => l.includes('undefined')),
			'should not print undefined result');
	});
});

describe('print() output', () => {
	test('print() adds text to the output area', () => {
		const { con, pre } = _make({});
		con.print('test line');
		assert.ok(pre.textContent.includes('test line'), 'print should add text to output');
	});

	test('print() appends with newline', () => {
		const { con, pre } = _make({});
		con.print('first');
		con.print('second');
		assert.ok(pre.textContent.includes('first'), 'first line present');
		assert.ok(pre.textContent.includes('second'), 'second line present');
	});

	test('print() keeps last 12 lines (scrollback cap)', () => {
		const { con, pre } = _make({});
		for (let i = 0; i < 15; i++) con.print(`line-${i}`);
		assert.ok(pre.textContent.includes('line-14'), 'latest line present');
		assert.ok(!pre.textContent.includes('line-0'), 'oldest line scrolled off');
		assert.ok(!pre.textContent.includes('line-3'), 'line-3 scrolled off (12-element slice includes trailing empty)');
		assert.ok(pre.textContent.includes('line-4'), 'line-4 is the oldest kept (11 lines + trailing empty = 12 elements)');
	});
});

describe('help auto-command', () => {
	test('help is auto-registered if not provided', () => {
		const { con, pre } = _make({ foo: () => '1', bar: () => '2' });
		con.run('help');
		assert.ok(pre.textContent.includes('foo'), 'help should list foo command');
		assert.ok(pre.textContent.includes('bar'), 'help should list bar command');
	});

	test('custom help command overrides auto-help', () => {
		const { con, pre } = _make({ help: () => 'custom help text' });
		con.run('help');
		assert.ok(pre.textContent.includes('custom help text'), 'should use custom help');
	});
});

describe('isOpen state', () => {
	test('isOpen returns false initially', () => {
		const { con } = _make({});
		assert.equal(con.isOpen(), false);
	});

	test('isOpen returns true after toggle', () => {
		const { con } = _make({});
		con.toggle();
		assert.equal(con.isOpen(), true);
	});

	test('isOpen returns false after toggle twice', () => {
		const { con } = _make({});
		con.toggle();
		con.toggle();
		assert.equal(con.isOpen(), false);
	});
});

describe('multiple instances', () => {
	test('can create multiple console instances independently', () => {
		const { con: con1 } = _make({ cmd1: () => 'one' });
		const { con: con2 } = _make({ cmd2: () => 'two' });
		assert.notEqual(con1, con2, 'instances should be distinct objects');
		assert.equal(typeof con1.run, 'function');
		assert.equal(typeof con2.run, 'function');
	});
});