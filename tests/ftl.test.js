// Unit tests for src/ftl.js — FTL rhythm + story countdown system (TD-101).
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Since ftl.js uses ES export syntax, we eval it in a module context.
// We'll use a dynamic import via a data URL for isolated testing.
const src = readFileSync(new URL('../src/ftl.js', import.meta.url), 'utf-8');

// Create a mock ctx for testing
function createMockCtx(overrides = {}) {
	const calls = { shake: [], alertUntil: [], oneShot: [], subtitle: [], setClock: [], addLog: [], knockOut: [], dialGate: [], recallKino: [], shutdownGate: [], urgentAlarm: [] };
	return {
		ctx: {
			mmss: (s) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(Math.floor(s % 60)).padStart(2, '0')}`,
			clockScale: () => 1,
			quest: { chapter: null, step: () => ({ id: 'mine' }), setFlag: () => {} },
			ui: {
				setClock: (label, cls) => calls.setClock.push({ label, cls }),
				subtitle: (who, text, opts) => calls.subtitle.push({ who, text, opts }),
			},
			oneShot: (buf, vol, rate) => calls.oneShot.push({ buf, vol, rate }),
			buffers: { ftlDrop: 'ftlDrop', radio: 'radio' },
			shutdownBuf: 'shutdownBuf',
			setShake: (n) => calls.shake.push(n),
			setAlertUntil: (t) => calls.alertUntil.push(t),
			knockOut: (cause) => calls.knockOut.push(cause),
			recallKino: () => calls.recallKino.push(true),
			shutdownGate: (w) => calls.shutdownGate.push(w),
			dialGate: (w) => calls.dialGate.push(w),
			addLog: (msg) => calls.addLog.push(msg),
			urgentAlarm: (dt) => calls.urgentAlarm.push(dt),
			getWorld: () => overrides.world ?? { gate: { userData: { active: false } } },
			getDestiny: () => overrides.destiny ?? { gate: { userData: { active: false } } },
			getPlanet: () => overrides.planet ?? null,
			getTravel: () => overrides.travel ?? null,
			getKino: () => overrides.kino ?? { active: false },
			knockedOut: () => overrides.knockedOut ?? false,
			...overrides.ctxOverrides,
		},
		calls,
	};
}

// Import the module dynamically
let createFtlSystem;
try {
	const mod = await import('../src/ftl.js');
	createFtlSystem = mod.createFtlSystem;
} catch {
	// Fallback: eval the source to extract createFtlSystem
	const moduleCode = src.replace(/^export /gm, '');
	const fakeModule = { exports: {} };
	new Function('module', moduleCode)(fakeModule);
	createFtlSystem = fakeModule.exports.createFtlSystem;
}

describe('ftl.js — createFtlSystem', () => {
	let mockCtx, calls, ftl;

	beforeEach(() => {
		const setup = createMockCtx();
		mockCtx = setup.ctx;
		calls = setup.calls;
		ftl = createFtlSystem(mockCtx);
	});

	test('initial state — ftl window and cooldown are 0', () => {
		assert.equal(ftl.ftl.window, 0);
		assert.equal(ftl.ftl.cooldown, 0);
		assert.equal(ftl.ftl.warned.size, 0);
		assert.equal(ftl.countdown, null);
	});

	test('exposes FTL_WINDOW and FTL_COOLDOWN constants', () => {
		assert.equal(ftl.FTL_WINDOW, 600);
		assert.equal(ftl.FTL_COOLDOWN, 90);
	});

	test('exposes PLANET_STEPS', () => {
		assert.deepEqual(ftl.PLANET_STEPS, ['scout_kino', 'gear_up', 'travel', 'mine', 'dial_home']);
	});

	test('needsPlanet returns true for planet steps', () => {
		assert.equal(ftl.needsPlanet(), true); // default mock step is 'mine'
	});

	test('needsPlanet returns false for non-planet steps', () => {
		const setup = createMockCtx({ ctxOverrides: { quest: { chapter: null, step: () => ({ id: 'return' }), setFlag: () => {} } } });
		const f = createFtlSystem(setup.ctx);
		assert.equal(f.needsPlanet(), false);
	});

	test('openFtlWindow sets window from default FTL_WINDOW', () => {
		ftl.openFtlWindow();
		assert.equal(ftl.ftl.window, 600);
		assert.equal(ftl.ftl.cooldown, 0);
		assert.equal(ftl.ftl.warned.size, 0);
	});

	test('openFtlWindow uses chapter planet window_seconds when available', () => {
		const setup = createMockCtx({ ctxOverrides: { quest: { chapter: { planet: { window_seconds: 300 } }, step: () => ({ id: 'mine' }), setFlag: () => {} } } });
		const f = createFtlSystem(setup.ctx);
		f.openFtlWindow();
		assert.equal(f.ftl.window, 300);
	});

	test('openFtlWindow applies clockScale', () => {
		const setup = createMockCtx({ ctxOverrides: { clockScale: () => 0.5 } });
		const f = createFtlSystem(setup.ctx);
		f.openFtlWindow();
		assert.equal(f.ftl.window, 300); // 600 * 0.5
	});

	test('ftlJump when on planet knocks out player', () => {
		const planet = { gate: { userData: { active: false } } };
		const destiny = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ world: planet, planet, destiny, ctxOverrides: { getKino: () => ({ active: true }) } });
		const f = createFtlSystem(setup.ctx);
		f.openFtlWindow();
		f.ftlJump();
		assert.deepEqual(setup.calls.knockOut, ['window_closed']);
		assert.deepEqual(setup.calls.recallKino, [true]); // kino was active
		assert.equal(f.ftl.window, 0);
		assert.equal(f.ftl.cooldown, FTL_COOLDOWN_REF);
		assert.deepEqual(setup.calls.shake, [1.2]);
	});

	test('ftlJump when on destiny with active gate shuts it down', () => {
		const destiny = { gate: { userData: { active: true } } };
		const setup = createMockCtx({ world: destiny, destiny });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.deepEqual(setup.calls.shutdownGate, [destiny]);
		assert.equal(f.ftl.window, 0);
	});

	test('ftlJump sets ftl_jumped flag', () => {
		let flagSet = null;
		const setup = createMockCtx({ ctxOverrides: { quest: { chapter: null, step: () => ({ id: 'mine' }), setFlag: (f) => flagSet = f } } });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.equal(flagSet, 'ftl_jumped');
	});

	test('ftlJump logs the jump', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.deepEqual(setup.calls.addLog, ['Destiny jumped to FTL']);
	});

	test('ftlRedrop opens a new window and dials gate', () => {
		const destiny = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ destiny });
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		assert.equal(f.ftl.window, 600);
		assert.deepEqual(setup.calls.shake, [1.4]);
		// dialGate is called via setTimeout(900ms) — verify the callback is queued
		assert.equal(setup.calls.dialGate.length, 0); // not called synchronously
	});

	test('ftlRedrop logs the drop', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		assert.deepEqual(setup.calls.addLog, ['Destiny dropped out of FTL']);
	});

	test('ftlRedrop plays ftlDrop and shutdownBuf', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		assert.deepEqual(setup.calls.oneShot[0], { buf: 'ftlDrop', vol: 0.9, rate: undefined });
		assert.deepEqual(setup.calls.oneShot[1], { buf: 'shutdownBuf', vol: 0.5, rate: 0.55 });
	});

	test('ftlRedrop shows Brody subtitle', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		assert.equal(setup.calls.subtitle[0].who, 'Brody');
		assert.ok(setup.calls.subtitle[0].text.includes('dropped out again'));
		assert.deepEqual(setup.calls.subtitle[0].opts, { radio: true });
	});

	test('startCountdown sets countdown state with defaults', () => {
		ftl.startCountdown({});
		assert.equal(ftl.countdown.label, 'DEADLINE');
		assert.equal(ftl.countdown.cause, 'generic');
		assert.equal(ftl.countdown.t, 300);
		assert.equal(ftl.countdown.total, 300);
		assert.equal(ftl.countdown.warned.size, 0);
	});

	test('startCountdown accepts custom params', () => {
		ftl.startCountdown({ seconds: 120, label: 'SHIELDS', cause: 'shields' });
		assert.equal(ftl.countdown.label, 'SHIELDS');
		assert.equal(ftl.countdown.cause, 'shields');
		assert.equal(ftl.countdown.t, 120);
	});

	test('startCountdown applies clockScale', () => {
		const setup = createMockCtx({ ctxOverrides: { clockScale: () => 2 } });
		const f = createFtlSystem(setup.ctx);
		f.startCountdown({ seconds: 100 });
		assert.equal(f.countdown.t, 200);
	});

	test('startCountdown sets alertUntil', () => {
		ftl.startCountdown({});
		assert.equal(calls.alertUntil.length, 1);
		assert.ok(calls.alertUntil[0] > 0);
	});

	test('stopCountdown clears countdown and clock', () => {
		ftl.startCountdown({});
		ftl.stopCountdown();
		assert.equal(ftl.countdown, null);
		assert.deepEqual(calls.setClock, [{ label: '', cls: undefined }]);
	});

	test('tickCountdown does nothing when no countdown is active', () => {
		ftl.tickCountdown(0.1);
		assert.equal(calls.setClock.length, 0);
	});

	test('tickCountdown decrements time when not knocked out', () => {
		ftl.startCountdown({ seconds: 100 });
		ftl.tickCountdown(10);
		assert.equal(ftl.countdown.t, 90);
	});

	test('tickCountdown does not decrement when knocked out', () => {
		const setup = createMockCtx({ knockedOut: true });
		const f = createFtlSystem(setup.ctx);
		f.startCountdown({ seconds: 100 });
		f.tickCountdown(10);
		assert.equal(f.countdown.t, 100);
	});

	test('tickCountdown sets HUD clock with label and time', () => {
		ftl.startCountdown({ seconds: 100, label: 'EVAC' });
		calls.setClock.length = 0;
		ftl.tickCountdown(1);
		assert.equal(calls.setClock.length, 1);
		assert.ok(calls.setClock[0].label.includes('EVAC'));
		assert.ok(calls.setClock[0].label.includes('01:39')); // 100-1=99 → 01:39
	});

	test('tickCountdown uses urgent class under 60 seconds', () => {
		ftl.startCountdown({ seconds: 50 });
		calls.setClock.length = 0;
		ftl.tickCountdown(1);
		assert.equal(calls.setClock[0].cls, 'urgent');
	});

	test('tickCountdown uses normal class over 60 seconds', () => {
		ftl.startCountdown({ seconds: 120 });
		calls.setClock.length = 0;
		ftl.tickCountdown(1);
		assert.equal(calls.setClock[0].cls, '');
	});

	test('tickCountdown triggers Rush warning at 120 seconds', () => {
		ftl.startCountdown({ seconds: 120 });
		calls.subtitle.length = 0;
		ftl.tickCountdown(1); // 120 → 119, triggers 120 threshold
		assert.equal(calls.subtitle.length, 1);
		assert.equal(calls.subtitle[0].who, 'Rush');
		assert.ok(calls.subtitle[0].text.includes('Two minutes'));
	});

	test('tickCountdown triggers Scott warning at 30 seconds', () => {
		ftl.startCountdown({ seconds: 31 });
		calls.subtitle.length = 0;
		// First tick crosses 120 threshold (31→30 is not below 120)
		// Actually 31-1=30, which triggers both 120 (already passed?) and 30
		// Let's start at 31 and tick to 30
		ftl.tickCountdown(1);
		// 31→30: triggers 30s warning (30 <= 30), but 120 is not triggered (30 <= 120 is true but 30 was not <= 120 before)
		// Actually: at 30, both 120 and 30 thresholds are <= current. 120 wasn't warned yet so both fire.
		const scottLine = calls.subtitle.find(s => s.who === 'Scott');
		assert.ok(scottLine, 'Scott warning should fire');
		assert.ok(scottLine.text.includes('Thirty seconds'));
	});

	test('tickCountdown does not repeat warnings', () => {
		ftl.startCountdown({ seconds: 120 });
		ftl.tickCountdown(1); // triggers 120 warning
		calls.subtitle.length = 0;
		ftl.tickCountdown(1); // 119 → should not re-trigger 120
		// 119 is still <= 120 but warned already has 120
		assert.equal(calls.subtitle.filter(s => s.who === 'Rush').length, 0);
	});

	test('tickCountdown calls urgentAlarm under 60 seconds', () => {
		ftl.startCountdown({ seconds: 50 });
		calls.urgentAlarm.length = 0;
		ftl.tickCountdown(1);
		assert.equal(calls.urgentAlarm.length, 1);
	});

	test('tickCountdown does not call urgentAlarm at or above 60 seconds', () => {
		ftl.startCountdown({ seconds: 70 });
		calls.urgentAlarm.length = 0;
		ftl.tickCountdown(1); // 70→69
		assert.equal(calls.urgentAlarm.length, 0);
	});

	test('tickCountdown does not call urgentAlarm when knocked out', () => {
		const setup = createMockCtx({ knockedOut: true });
		const f = createFtlSystem(setup.ctx);
		f.startCountdown({ seconds: 30 });
		f.tickCountdown(1);
		assert.equal(setup.calls.urgentAlarm.length, 0);
	});

	test('tickCountdown calls knockOut and re-arms when time reaches 0', () => {
		ftl.startCountdown({ seconds: 1 });
		calls.knockOut.length = 0;
		ftl.tickCountdown(1); // 1→0
		assert.deepEqual(calls.knockOut, ['generic']);
		assert.equal(ftl.countdown.t, 1); // re-armed to total
		assert.deepEqual(calls.shake, [1.2]);
	});

	test('tickCountdown clamps time to 0 and re-arms', () => {
		ftl.startCountdown({ seconds: 0.5 });
		ftl.tickCountdown(10); // 0.5-10 → clamped to 0, then re-armed to total (0.5)
		assert.equal(ftl.countdown.t, 0.5); // re-armed to total
		assert.deepEqual(calls.knockOut, ['generic']); // knockOut called
	});

	test('tickFtl does nothing when window and cooldown are 0', () => {
		ftl.tickFtl(0.1);
		// When no countdown and no ftl, should set clock to ''
		assert.deepEqual(calls.setClock, [{ label: '', cls: undefined }]);
	});

	test('tickFtl decrements window timer', () => {
		ftl.openFtlWindow();
		calls.setClock.length = 0;
		ftl.tickFtl(10);
		assert.equal(ftl.ftl.window, 590);
	});

	test('tickFtl calls ftlJump when window reaches 0', () => {
		ftl.openFtlWindow();
		calls.knockOut.length = 0;
		// Tick the entire window down to 0
		ftl.tickFtl(600);
		assert.equal(ftl.ftl.window, 0);
		// ftlJump should have been called — sets cooldown
		assert.equal(ftl.ftl.cooldown, 90);
	});

	test('tickFtl sets FTL JUMP clock when window is active', () => {
		ftl.openFtlWindow();
		calls.setClock.length = 0;
		ftl.tickFtl(1);
		assert.ok(calls.setClock[0].label.includes('FTL JUMP'));
		assert.ok(calls.setClock[0].label.includes('09:59'));
	});

	test('tickFtl uses urgent class for FTL window under 60 seconds', () => {
		ftl.openFtlWindow();
		// Burn down to under 60
		ftl.tickFtl(541); // 600-541=59
		calls.setClock.length = 0;
		ftl.tickFtl(1); // 59→58
		assert.equal(calls.setClock[0].cls, 'urgent');
	});

	test('tickFtl decrements cooldown timer', () => {
		// Set cooldown manually
		ftl.ftl.cooldown = 90;
		calls.setClock.length = 0;
		ftl.tickFtl(10);
		assert.equal(ftl.ftl.cooldown, 80);
	});

	test('tickFtl cooldown shows IN FTL with next drop time when planet needed', () => {
		ftl.ftl.cooldown = 90;
		calls.setClock.length = 0;
		ftl.tickFtl(1);
		assert.ok(calls.setClock[0].label.includes('IN FTL'));
		assert.ok(calls.setClock[0].label.includes('NEXT DROP'));
	});

	test('tickFtl cooldown shows IN FTL without drop when planet not needed', () => {
		const setup = createMockCtx({ ctxOverrides: { quest: { chapter: null, step: () => ({ id: 'return' }), setFlag: () => {} } } });
		const f = createFtlSystem(setup.ctx);
		f.ftl.cooldown = 90;
		f.tickFtl(1);
		assert.ok(setup.calls.setClock[0].label === 'IN FTL');
		assert.equal(setup.calls.setClock[0].cls, 'cool');
	});

	test('tickFtl cooldown expiry triggers ftlRedrop when planet needed', () => {
		const destiny = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ world: destiny, destiny });
		const f = createFtlSystem(setup.ctx);
		f.ftl.cooldown = 1;
		f.tickFtl(1); // cooldown reaches 0, ftlRedrop called
		// ftlRedrop should have been called — opens window
		assert.equal(f.ftl.window, 600);
		// dialGate is async (setTimeout) so not called synchronously
		assert.equal(setup.calls.dialGate.length, 0);
	});

	test('tickFtl cooldown expiry clears clock when planet not needed', () => {
		const setup = createMockCtx({ ctxOverrides: { quest: { chapter: null, step: () => ({ id: 'return' }), setFlag: () => {} } } });
		const f = createFtlSystem(setup.ctx);
		f.ftl.cooldown = 1;
		setup.calls.setClock.length = 0;
		f.tickFtl(1);
		assert.deepEqual(setup.calls.setClock, [{ label: '', cls: undefined }]);
	});

	test('tickFtl does not show FTL clock when countdown is active', () => {
		ftl.openFtlWindow();
		ftl.startCountdown({ seconds: 100 });
		calls.setClock.length = 0;
		ftl.tickFtl(1);
		// tickFtl does NOT call setClock when countdown is active (priority: countdown > FTL)
		// The clock is managed by tickCountdown, not tickFtl, when both are active
		assert.equal(calls.setClock.length, 0);
	});

	test('tickFtl still decrements window even when countdown is active', () => {
		ftl.openFtlWindow();
		ftl.startCountdown({ seconds: 100 });
		const initialWindow = ftl.ftl.window;
		ftl.tickFtl(10);
		assert.equal(ftl.ftl.window, initialWindow - 10);
	});

	test('tickFtl triggers Rush warning for FTL window at 120 seconds', () => {
		ftl.openFtlWindow();
		calls.subtitle.length = 0;
		// Burn down to 120: 600 - 480 = 120 → triggers 120 threshold on this tick
		ftl.tickFtl(480);
		const rushLine = calls.subtitle.find(s => s.who === 'Rush');
		assert.ok(rushLine, 'Rush FTL warning should fire at 120s');
		assert.ok(rushLine.text.includes('FTL clock'));
	});

	test('tickFtl triggers Scott warning for FTL window at 30 seconds', () => {
		ftl.openFtlWindow();
		// Burn down to 31
		ftl.tickFtl(569); // 600-569=31
		calls.subtitle.length = 0;
		ftl.tickFtl(1); // 31→30
		const scottLine = calls.subtitle.find(s => s.who === 'Scott');
		assert.ok(scottLine, 'Scott FTL warning should fire');
		assert.ok(scottLine.text.includes('Thirty seconds'));
	});

	test('tickFtl calls urgentAlarm for FTL window under 60 seconds', () => {
		ftl.openFtlWindow();
		ftl.tickFtl(541); // 600-541=59
		calls.urgentAlarm.length = 0;
		ftl.tickFtl(1); // 59→58
		assert.equal(calls.urgentAlarm.length, 1);
	});

	test('tickFtl does not call urgentAlarm when countdown is active', () => {
		ftl.openFtlWindow();
		ftl.tickFtl(541); // 59 seconds left
		ftl.startCountdown({ seconds: 100 });
		calls.urgentAlarm.length = 0;
		ftl.tickFtl(1);
		// urgentAlarm should NOT fire for FTL when countdown is active
		assert.equal(calls.urgentAlarm.length, 0);
	});

	test('countdown getter/setter works', () => {
		ftl.countdown = { t: 50, label: 'TEST', cause: 'test', total: 50, warned: new Set() };
		assert.equal(ftl.countdown.label, 'TEST');
		ftl.countdown = null;
		assert.equal(ftl.countdown, null);
	});

	test('clockScale affects FTL window duration', () => {
		const setup = createMockCtx({ ctxOverrides: { clockScale: () => 0.5 } });
		const f = createFtlSystem(setup.ctx);
		f.openFtlWindow();
		assert.equal(f.ftl.window, 300);
	});

	test('clockScale affects countdown duration', () => {
		const setup = createMockCtx({ ctxOverrides: { clockScale: () => 0.5 } });
		const f = createFtlSystem(setup.ctx);
		f.startCountdown({ seconds: 200 });
		assert.equal(f.countdown.t, 100);
	});

	test('ftlJump does not recall kino when kino is inactive', () => {
		const setup = createMockCtx({ ctxOverrides: { getKino: () => ({ active: false }) } });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.equal(setup.calls.recallKino.length, 0);
	});

	test('ftlJump does not shut down gate when not active', () => {
		const destiny = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ world: destiny, destiny });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.equal(setup.calls.shutdownGate.length, 0);
	});

	test('mmss is used for clock display', () => {
		ftl.openFtlWindow();
		calls.setClock.length = 0;
		ftl.tickFtl(1); // 599 seconds = 09:59
		assert.ok(calls.setClock[0].label.includes('09:59'));
	});

	test('multiple openFtlWindow calls reset warned set', () => {
		ftl.openFtlWindow();
		ftl.ftl.warned.add(120);
		assert.equal(ftl.ftl.warned.size, 1);
		ftl.openFtlWindow();
		assert.equal(ftl.ftl.warned.size, 0);
	});

	test('tickFtl with window and cooldown both 0 clears clock when no countdown', () => {
		ftl.tickFtl(0.1);
		assert.deepEqual(calls.setClock, [{ label: '', cls: undefined }]);
	});

	test('tickFtl with window and cooldown both 0 does nothing when countdown active', () => {
		ftl.startCountdown({ seconds: 100 });
		calls.setClock.length = 0;
		ftl.tickFtl(0.1);
		// tickFtl's else-if branch: !countdown is false, so setClock is NOT called by tickFtl
		// But tickCountdown should handle the clock
		assert.equal(calls.setClock.length, 0); // tickFtl doesn't set clock when countdown is active and no ftl
	});

	test('ftlJump when world is planet and travel destination is planet knocks out', () => {
		const planet = { gate: { userData: { active: false } } };
		const destiny = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ world: destiny, planet, destiny, travel: { to: planet }, ctxOverrides: { getKino: () => ({ active: false }) } });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.deepEqual(setup.calls.knockOut, ['window_closed']);
	});

	test('ftlJump when world is not planet and travel is not to planet does not knock out', () => {
		const destiny = { gate: { userData: { active: false } } };
		const planet = { gate: { userData: { active: false } } };
		const setup = createMockCtx({ world: destiny, planet, destiny, travel: null });
		const f = createFtlSystem(setup.ctx);
		f.ftlJump();
		assert.equal(setup.calls.knockOut.length, 0);
	});

	test('ftlRedrop sets alertUntil', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		assert.equal(setup.calls.alertUntil.length, 1);
	});

	test('ftlRedrop plays radio click', () => {
		const setup = createMockCtx();
		const f = createFtlSystem(setup.ctx);
		f.ftlRedrop();
		const radioShot = setup.calls.oneShot.find(o => o.buf === 'radio');
		assert.ok(radioShot, 'radio oneShot should fire');
		assert.equal(radioShot.vol, 0.6);
	});
});

// Reference constant for comparison
const FTL_COOLDOWN_REF = 90;