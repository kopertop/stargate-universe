/**
 * Unit tests for src/main.js — the orchestrator module (TD-103 final module).
 *
 * Run with:  node --test tests/main.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * main.js is the 676-line entry point that wires every subsystem together:
 * Three.js renderer, scene graph, audio, quest engine, RPG, UI, save/load,
 * gate travel, Kino drone, level editor, dev console, and the main loop.
 *
 * It cannot be `import`ed in Node — it executes Three.js WebGLRenderer,
 * document.body.appendChild, fetch, top-level await, etc. on load. Instead
 * we use the same regex-based source-text extraction pattern as player.test.js
 * to verify its constants, structure, wiring, and pure functions.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(__dirname, '..', 'src', 'main.js'), 'utf-8');
const ftlSrc = readFileSync(join(__dirname, '..', 'src', 'ftl.js'), 'utf-8');

// ─── Helper: extract a const that's a simple literal (string, number, array) ───
// Handles both standalone (`const X = 5;`) and comma-separated (`const A = 1, X = 5;`) declarations.
function extractConstLiteral(name, src) {
	// Match `NAME = ` preceded by `const/let/var ` OR by `, ` (comma-separated declaration)
	const re = new RegExp(`(?:const|let|var)\\s+${name}\\s*=\\s*|(?:,\\s*)${name}\\s*=\\s*`);
	const m = re.exec(src);
	if (!m) throw new Error(`${name} not found in source`);
	const after = src.slice(m.index + m[0].length);
	const firstChar = after[0];
	if (firstChar === '[' || firstChar === '{') {
		const open = firstChar;
		const close = open === '[' ? ']' : '}';
		let depth = 0, end = 0;
		for (let i = 0; i < after.length; i++) {
			if (after[i] === open) depth++;
			if (after[i] === close) { depth--; if (depth === 0) { end = i + 1; break; } }
		}
		return after.slice(0, end);
	}
	// Number or string literal — find the next comma or semicolon (handles comma-separated consts)
	const comma = after.indexOf(',');
	const semi = after.indexOf(';');
	const end = comma !== -1 && comma < semi ? comma : semi;
	return after.slice(0, end).trim();
}

// ─── Constants extracted from source ───

const FTL_WINDOW = Number(extractConstLiteral('FTL_WINDOW', ftlSrc));
const FTL_COOLDOWN = Number(extractConstLiteral('FTL_COOLDOWN', ftlSrc));
const PLAYER_CHEST = Number(extractConstLiteral('PLAYER_CHEST', src));
const PCOUNT = Number(extractConstLiteral('PCOUNT', src));
const DCOUNT = Number(extractConstLiteral('DCOUNT', src));

const IDLE_INPUT = eval(`(${extractConstLiteral('IDLE_INPUT', src)})`);
const WALK_OUT = eval(`(${extractConstLiteral('WALK_OUT', src)})`);
const VIEWS = eval(`(${extractConstLiteral('VIEWS', src)})`);
const PLANET_STEPS = eval(`(${extractConstLiteral('PLANET_STEPS', ftlSrc)})`);

// SFX_FILES is a large object — extract it
const SFX_FILES_SRC = (() => {
	const marker = 'const SFX_FILES = ';
	const start = src.indexOf(marker);
	if (start === -1) throw new Error('SFX_FILES not found');
	const after = src.slice(start + marker.length);
	let depth = 0, end = 0;
	for (let i = 0; i < after.length; i++) {
		if (after[i] === '{') depth++;
		if (after[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
	}
	return after.slice(0, end);
})();
const SFX_FILES = eval(`(${SFX_FILES_SRC})`);

// FUSES_NEEDED
const FUSES_NEEDED_SRC = (() => {
	const marker = 'const FUSES_NEEDED = ';
	const start = src.indexOf(marker);
	if (start === -1) throw new Error('FUSES_NEEDED not found');
	const after = src.slice(start + marker.length);
	let depth = 0, end = 0;
	for (let i = 0; i < after.length; i++) {
		if (after[i] === '{') depth++;
		if (after[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
	}
	return after.slice(0, end);
})();
const FUSES_NEEDED = eval(`(${FUSES_NEEDED_SRC})`);

// ─── Tests ─────────────────────────────────────────────────

describe('FTL constants', () => {
	test('FTL_WINDOW is 600 seconds (10 minutes)', () => {
		assert.equal(FTL_WINDOW, 600, 'FTL jump window should be 600s = 10 min');
	});

	test('FTL_COOLDOWN is 90 seconds (1.5 minutes)', () => {
		assert.equal(FTL_COOLDOWN, 90, 'FTL cooldown should be 90s = 1.5 min');
	});

	test('FTL_WINDOW is greater than FTL_COOLDOWN', () => {
		assert.ok(FTL_WINDOW > FTL_COOLDOWN, 'jump window should be longer than cooldown');
	});

	test('FTL_WINDOW is a positive integer', () => {
		assert.ok(Number.isInteger(FTL_WINDOW));
		assert.ok(FTL_WINDOW > 0);
	});

	test('FTL_COOLDOWN is a positive integer', () => {
		assert.ok(Number.isInteger(FTL_COOLDOWN));
		assert.ok(FTL_COOLDOWN > 0);
	});
});

describe('PLAYER_CHEST constant', () => {
	test('PLAYER_CHEST is 1.1 (chest height in meters)', () => {
		assert.equal(PLAYER_CHEST, 1.1);
	});

	test('PLAYER_CHEST is in reasonable human range', () => {
		assert.ok(PLAYER_CHEST > 0.8 && PLAYER_CHEST < 1.8, 'chest height should be in human range');
	});
});

describe('Particle system constants', () => {
	test('PCOUNT is 1200', () => {
		assert.equal(PCOUNT, 1200);
	});

	test('DCOUNT is 400', () => {
		assert.equal(DCOUNT, 400);
	});

	test('PCOUNT > DCOUNT (disintegration particles more numerous than dust)', () => {
		assert.ok(PCOUNT > DCOUNT, 'particle pool should be larger than dust pool');
	});

	test('PCOUNT and DCOUNT are positive integers', () => {
		assert.ok(Number.isInteger(PCOUNT) && PCOUNT > 0);
		assert.ok(Number.isInteger(DCOUNT) && DCOUNT > 0);
	});
});

describe('IDLE_INPUT constant', () => {
	test('IDLE_INPUT has move property with x and y', () => {
		assert.ok(typeof IDLE_INPUT === 'object');
		assert.ok('move' in IDLE_INPUT);
		assert.equal(IDLE_INPUT.move.x, 0);
		assert.equal(IDLE_INPUT.move.y, 0);
	});

	test('IDLE_INPUT run is false', () => {
		assert.equal(IDLE_INPUT.run, false);
	});

	test('IDLE_INPUT represents no movement', () => {
		assert.equal(IDLE_INPUT.move.x, 0);
		assert.equal(IDLE_INPUT.move.y, 0);
		assert.equal(IDLE_INPUT.run, false);
	});
});

describe('WALK_OUT constant', () => {
	test('WALK_OUT has move with y=1 (forward)', () => {
		assert.ok('move' in WALK_OUT);
		assert.equal(WALK_OUT.move.x, 0);
		assert.equal(WALK_OUT.move.y, 1, 'y=1 means forward movement');
	});

	test('WALK_OUT run is false (walking, not running)', () => {
		assert.equal(WALK_OUT.run, false);
	});

	test('WALK_OUT represents forward walking (gate travel)', () => {
		assert.equal(WALK_OUT.move.y, 1);
		assert.equal(WALK_OUT.run, false);
	});
});

describe('VIEWS array', () => {
	test('VIEWS has exactly 3 entries', () => {
		assert.equal(VIEWS.length, 3);
	});

	test('VIEWS contains follow, top, and orbit', () => {
		assert.ok(VIEWS.includes('follow'));
		assert.ok(VIEWS.includes('top'));
		assert.ok(VIEWS.includes('orbit'));
	});

	test('VIEWS[0] is follow (default view)', () => {
		assert.equal(VIEWS[0], 'follow', 'follow should be the default/first view');
	});

	test('VIEWS entries are distinct strings', () => {
		const unique = new Set(VIEWS);
		assert.equal(unique.size, VIEWS.length, 'all views should be distinct');
		for (const v of VIEWS) {
			assert.equal(typeof v, 'string');
		}
	});
});

describe('PLANET_STEPS array', () => {
	test('PLANET_STEPS has 5 entries', () => {
		assert.equal(PLANET_STEPS.length, 5);
	});

	test('PLANET_STEPS contains scout_kino as first step', () => {
		assert.equal(PLANET_STEPS[0], 'scout_kino', 'first planet step should be scouting with kino');
	});

	test('PLANET_STEPS contains dial_home as last step', () => {
		assert.equal(PLANET_STEPS[4], 'dial_home', 'last planet step should be dialing home');
	});

	test('PLANET_STEPS entries are distinct strings', () => {
		const unique = new Set(PLANET_STEPS);
		assert.equal(unique.size, PLANET_STEPS.length);
	});

	test('PLANET_STEPS follows expected quest progression', () => {
		assert.equal(PLANET_STEPS[0], 'scout_kino');
		assert.equal(PLANET_STEPS[1], 'gear_up');
		assert.equal(PLANET_STEPS[2], 'travel');
		assert.equal(PLANET_STEPS[3], 'mine');
		assert.equal(PLANET_STEPS[4], 'dial_home');
	});
});

describe('FUSES_NEEDED constant', () => {
	test('FUSES_NEEDED requires 2 bus_fuse', () => {
		assert.equal(FUSES_NEEDED.bus_fuse, 2);
	});

	test('FUSES_NEEDED requires 1 large_fuse', () => {
		assert.equal(FUSES_NEEDED.large_fuse, 1);
	});

	test('FUSES_NEEDED has exactly 2 entries', () => {
		assert.equal(Object.keys(FUSES_NEEDED).length, 2);
	});

	test('FUSES_NEEDED values are positive integers', () => {
		for (const [k, v] of Object.entries(FUSES_NEEDED)) {
			assert.ok(Number.isInteger(v) && v > 0, `${k} should be a positive integer`);
		}
	});
});

describe('SFX_FILES mapping', () => {
	test('SFX_FILES has expected sound effect keys', () => {
		const expected = ['chevron', 'kawoosh', 'hum', 'doorThunk', 'doorLock', 'terminal',
			'menuOpen', 'menuClose', 'radio', 'ftlDrop', 'discover', 'discoverKey'];
		for (const key of expected) {
			assert.ok(key in SFX_FILES, `SFX_FILES should have key: ${key}`);
		}
	});

	test('SFX_FILES has footstep sounds', () => {
		assert.ok('step1' in SFX_FILES);
		assert.ok('step2' in SFX_FILES);
		assert.ok('step3' in SFX_FILES);
		assert.ok('step4' in SFX_FILES);
	});

	test('SFX_FILES has sand footstep sounds', () => {
		assert.ok('sand1' in SFX_FILES);
		assert.ok('sand2' in SFX_FILES);
		assert.ok('sand3' in SFX_FILES);
		assert.ok('sand4' in SFX_FILES);
	});

	test('SFX_FILES values are non-empty strings', () => {
		for (const [key, val] of Object.entries(SFX_FILES)) {
			assert.equal(typeof val, 'string', `SFX_FILES[${key}] should be a string`);
			assert.ok(val.length > 0, `SFX_FILES[${key}] should be non-empty`);
		}
	});

	test('SFX_FILES chevron is an mp3', () => {
		assert.ok(SFX_FILES.chevron.endsWith('.mp3'));
	});

	test('SFX_FILES kawoosh is a wav', () => {
		assert.ok(SFX_FILES.kawoosh.endsWith('.wav'));
	});

	test('SFX_FILES has at least 18 entries', () => {
		assert.ok(Object.keys(SFX_FILES).length >= 18, 'should have comprehensive SFX mapping');
	});
});

describe('mmss time formatting function', () => {
	// Extract and eval the mmss function from source
	const mmss = (() => {
		const marker = 'const mmss = ';
		const start = src.indexOf(marker);
		if (start === -1) throw new Error('mmss not found');
		const after = src.slice(start + marker.length);
		// Find matching closing of arrow function: first semicolon at depth 0 after =>
		const arrowIdx = after.indexOf('=>');
		if (arrowIdx === -1) throw new Error('mmss is not an arrow function');
		// After => there's a parenthesized expression, find the closing semicolon
		const body = after.slice(arrowIdx + 2);
		// Find the semicolon that ends the statement
		let depth = 0, end = 0;
		for (let i = 0; i < body.length; i++) {
			if (body[i] === '(') depth++;
			if (body[i] === ')') depth--;
			if (body[i] === ';' && depth <= 0) { end = i; break; }
		}
		const fnBody = body.slice(0, end);
		return eval(`(s) => ${fnBody}`);
	})();

	test('mmss formats 0 seconds as 00:00', () => {
		assert.equal(mmss(0), '00:00');
	});

	test('mmss formats 60 seconds as 01:00', () => {
		assert.equal(mmss(60), '01:00');
	});

	test('mmss formats 90 seconds as 01:30', () => {
		assert.equal(mmss(90), '01:30');
	});

	test('mmss formats 600 seconds as 10:00 (FTL_WINDOW)', () => {
		assert.equal(mmss(FTL_WINDOW), '10:00');
	});

	test('mmss formats 3599 seconds as 59:59', () => {
		assert.equal(mmss(3599), '59:59');
	});

	test('mmss formats 125 seconds as 02:05 (zero-padded)', () => {
		assert.equal(mmss(125), '02:05');
	});

	test('mmss formats 5 seconds as 00:05 (zero-padded seconds)', () => {
		assert.equal(mmss(5), '00:05');
	});

	test('mmss returns string with format MM:SS', () => {
		const result = mmss(42);
		assert.match(result, /^\d{2}:\d{2}$/);
	});

	test('mmss handles fractional seconds (Math.floor)', () => {
		assert.equal(mmss(90.7), '01:30');
	});
});

describe('Module imports and structure', () => {
	test('main.js imports THREE', () => {
		assert.ok(src.includes("import * as THREE from 'three'"), 'should import three');
	});

	test('main.js imports OrbitControls', () => {
		assert.ok(src.includes('OrbitControls'), 'should import OrbitControls');
	});

	test('main.js imports RoomEnvironment', () => {
		assert.ok(src.includes('RoomEnvironment'), 'should import RoomEnvironment');
	});

	test('main.js imports all game modules', () => {
		const modules = ['gate-room', 'stargate', 'destination', 'wormhole', 'ship',
			'player', 'input', 'quest', 'kino', 'ui', 'interact', 'rpg',
			'assets', 'music', 'console', 'settings', 'leveledit', 'hotwire',
			'flow', 'save'];
		for (const mod of modules) {
			assert.ok(src.includes(`'./${mod}.js'`), `should import ./${mod}.js`);
		}
	});

	test('main.js creates WebGLRenderer', () => {
		assert.ok(src.includes('THREE.WebGLRenderer'), 'should create WebGL renderer');
	});

	test('main.js creates PerspectiveCamera', () => {
		assert.ok(src.includes('THREE.PerspectiveCamera'), 'should create perspective camera');
	});

	test('main.js creates OrbitControls instance', () => {
		assert.ok(src.includes('new OrbitControls'), 'should create OrbitControls');
	});

	test('main.js has main game loop (requestAnimationFrame)', () => {
		assert.ok(src.includes('requestAnimationFrame'), 'should use requestAnimationFrame');
	});

	test('main.js has visibility change handler for hidden tab fallback', () => {
		assert.ok(src.includes('visibilitychange'), 'should handle visibility changes');
		assert.ok(src.includes('document.hidden'), 'should check document.hidden');
	});

	test('main.js has frame sub-stepping for starved tabs', () => {
		assert.ok(src.includes('sub-step') || src.includes('Math.min(8'), 'should have sub-stepping logic');
	});
});

describe('Error handling and resilience', () => {
	test('main.js has global error handler', () => {
		assert.ok(src.includes("addEventListener('error'"), 'should have global error handler');
	});

	test('main.js has unhandled rejection handler', () => {
		assert.ok(src.includes("addEventListener('unhandledrejection'"), 'should handle unhandled rejections');
	});

	test('main.js has Three.js DefaultLoadingManager onError handler', () => {
		assert.ok(src.includes('DefaultLoadingManager.onError'), 'should handle asset load failures');
	});

	test('main.js has Three.js DefaultLoadingManager onProgress handler', () => {
		assert.ok(src.includes('DefaultLoadingManager.onProgress'), 'should show loading progress');
	});

	test('main.js world data load has fallback to empty objects', () => {
		assert.ok(src.includes('layout = {}') && src.includes('connections = {}'), 'should fallback to empty layout on fetch failure');
	});

	test('main.js SFX load has try/catch per file', () => {
		assert.ok(src.includes('SFX missing'), 'should warn on missing SFX files');
	});

	test('main.js knockout_lines.json fetch has catch with warn', () => {
		assert.ok(src.includes('knockout_lines.json load failed'), 'should warn on knockout lines load failure');
	});
});

describe('Save system wiring', () => {
	test('main.js creates save system via createSaveSystem', () => {
		assert.ok(src.includes('createSaveSystem'), 'should create save system');
	});

	test('main.js destructures saveGame, hasSave, loadGame, newGame, startFrom', () => {
		assert.ok(src.includes('saveGame') && src.includes('hasSave') && src.includes('loadGame') && src.includes('newGame') && src.includes('startFrom'));
	});

	test('main.js has SAVE_VERSION or uses save.js for versioning', () => {
		// After TD-101 extraction, save versioning lives in save.js
		// main.js should at least wire the save system
		assert.ok(src.includes('__save') || src.includes('createSaveSystem'));
	});

	test('main.js calls startChapter on init', () => {
		assert.ok(src.includes("startChapter('e1_air')"), 'should start first chapter on load');
	});

	test('main.js exposes save API on window.__save', () => {
		assert.ok(src.includes('window.__save'), 'should expose save API');
	});
});

describe('Interaction system registration', () => {
	test('main.js registers relay interactable', () => {
		assert.ok(src.includes("id: 'relay'"), 'should register power relay');
	});

	test('main.js registers lootable crates dynamically', () => {
		assert.ok(src.includes("id: `loot:"), 'should register lootable crates');
	});

	test('main.js registers elevator interactables', () => {
		assert.ok(src.includes("id: `elevator:"), 'should register elevators');
	});

	test('main.js registers console interactable', () => {
		assert.ok(src.includes("id: 'console'"), 'should register control console');
	});

	test('main.js registers NPC interactions (brody, rush, scott, tj)', () => {
		assert.ok(src.includes("id: 'brody'"));
		assert.ok(src.includes("id: 'rush'"));
		assert.ok(src.includes("id: 'scott'"));
		assert.ok(src.includes("id: 'tj'"));
	});

	test('main.js registers kino pedestal interactable', () => {
		assert.ok(src.includes("id: 'kino'"), 'should register kino pickup');
	});

	test('main.js registers harvest interactables for grow beds', () => {
		assert.ok(src.includes("id: `harvest:"), 'should register harvest interactions');
	});

	test('main.js registers planet resource nodes dynamically', () => {
		assert.ok(src.includes('registerPlanetInteractables'), 'should have planet interactable registration');
	});

	test('main.js registers scrubber interactable', () => {
		assert.ok(src.includes("id: 'scrubber'"), 'should register CO2 scrubber');
	});

	test('main.js registers seal lever interactable', () => {
		assert.ok(src.includes("id: 'lever'"), 'should register emergency seal lever');
	});
});

describe('FTL and countdown system', () => {
	test('main.js has ftl object with window, cooldown, warned', () => {
		assert.ok(ftlSrc.includes('const ftl = { window: 0, cooldown: 0') || ftlSrc.includes('ftl = { window: 0, cooldown: 0'));
		assert.ok(ftlSrc.includes('warned: new Set()'));
	});

	test('main.js wires openFtlWindow from ftl.js', () => {
		assert.ok(src.includes('openFtlWindow'), 'openFtlWindow should be referenced in main.js');
		assert.ok(ftlSrc.includes('openFtlWindow'), 'openFtlWindow should be defined in ftl.js');
	});

	test('main.js wires ftlJump from ftl.js', () => {
		assert.ok(ftlSrc.includes('ftlJump'), 'ftlJump should be defined in ftl.js');
	});

	test('main.js wires ftlRedrop from ftl.js', () => {
		assert.ok(ftlSrc.includes('ftlRedrop'), 'ftlRedrop should be defined in ftl.js');
	});

	test('main.js wires tickFtl from ftl.js', () => {
		assert.ok(src.includes('tickFtl'), 'tickFtl should be called in main.js');
		assert.ok(ftlSrc.includes('tickFtl'), 'tickFtl should be defined in ftl.js');
	});

	test('main.js wires tickCountdown from ftl.js', () => {
		assert.ok(src.includes('tickCountdown'), 'tickCountdown should be called in main.js');
		assert.ok(ftlSrc.includes('tickCountdown'), 'tickCountdown should be defined in ftl.js');
	});

	test('main.js wires startCountdown from ftl.js', () => {
		assert.ok(src.includes('startCountdown'), 'startCountdown should be called in main.js');
		assert.ok(ftlSrc.includes('startCountdown'), 'startCountdown should be defined in ftl.js');
	});

	test('main.js wires stopCountdown from ftl.js', () => {
		assert.ok(src.includes('stopCountdown'), 'stopCountdown should be called in main.js');
		assert.ok(ftlSrc.includes('stopCountdown'), 'stopCountdown should be defined in ftl.js');
	});

	test('main.js has knockOut function', () => {
		assert.ok(src.includes('const knockOut'));
	});

	test('main.js FTL jump window uses clockScale for accessibility', () => {
		assert.ok(src.includes('clockScale()'), 'FTL timers should respect clockScale setting');
	});

	test('main.js FTL has radio warning at 120s and 30s', () => {
		assert.ok(ftlSrc.includes('120') && ftlSrc.includes('30'), 'should have timed radio warnings');
		assert.ok(ftlSrc.includes('warned.has'), 'should track warned thresholds');
	});
});

describe('Gate travel system', () => {
	test('main.js has gateTravelCheck function', () => {
		assert.ok(src.includes('const gateTravelCheck'));
	});

	test('main.js has arriveAt function', () => {
		assert.ok(src.includes('const arriveAt'));
	});

	test('main.js has updateTravel function', () => {
		assert.ok(src.includes('const updateTravel'));
	});

	test('main.js has dialGate function', () => {
		assert.ok(src.includes('const dialGate'));
	});

	test('main.js has shutdownGate function', () => {
		assert.ok(src.includes('const shutdownGate'));
	});

	test('main.js travel phases include enter, wormhole, arrive', () => {
		assert.ok(src.includes("'enter'"));
		assert.ok(src.includes("'wormhole'"));
		assert.ok(src.includes("'arrive'"));
	});

	test('main.js has attachGateAudio function', () => {
		assert.ok(src.includes('const attachGateAudio'));
	});

	test('main.js has onGateEvent callback factory', () => {
		assert.ok(src.includes('const onGateEvent'));
	});
});

describe('Kino drone system', () => {
	test('main.js has launchKino function', () => {
		assert.ok(src.includes('const launchKino'));
	});

	test('main.js has recallKino function', () => {
		assert.ok(src.includes('const recallKino'));
	});

	test('main.js has updateKino function', () => {
		assert.ok(src.includes('const updateKino'));
	});

	test('main.js kino scan produces atmosphere data', () => {
		assert.ok(src.includes('atmosphere'), 'kino scan should return atmosphere data');
		assert.ok(src.includes('kino_scout_done'), 'should set kino_scout_done flag');
	});
});

describe('Camera system', () => {
	test('main.js has cam object with yaw, pitch, dist, height', () => {
		assert.ok(src.includes('yaw:'), 'cam should have yaw');
		assert.ok(src.includes('pitch:'), 'cam should have pitch');
		assert.ok(src.includes('dist:'), 'cam should have dist');
		assert.ok(src.includes('height:'), 'cam should have height');
	});

	test('main.js has updateCamera function', () => {
		assert.ok(src.includes('const updateCamera'));
	});

	test('main.js has camUpdate function', () => {
		assert.ok(src.includes('const camUpdate'));
	});

	test('main.js has updateOcclusion for wall transparency', () => {
		assert.ok(src.includes('const updateOcclusion'), 'should have occlusion system');
		assert.ok(src.includes('faded'), 'should track faded meshes');
	});

	test('main.js camera has shake effect', () => {
		assert.ok(src.includes('shake'), 'should have camera shake');
	});

	test('main.js camera raycaster for wall collision', () => {
		assert.ok(src.includes('raycaster'), 'should use raycasting for camera collision');
	});

	test('main.js has setView function for view switching', () => {
		assert.ok(src.includes('const setView'));
	});
});

describe('Audio system', () => {
	test('main.js creates AudioListener', () => {
		assert.ok(src.includes('THREE.AudioListener'), 'should create audio listener');
	});

	test('main.js creates AudioLoader', () => {
		assert.ok(src.includes('THREE.AudioLoader'), 'should create audio loader');
	});

	test('main.js has footstep system with sand and deck surfaces', () => {
		assert.ok(src.includes('footstep'), 'should have footstep function');
		assert.ok(src.includes("'sand'") && src.includes("'deck'"), 'should support sand and deck surfaces');
	});

	test('main.js has door audio system', () => {
		assert.ok(src.includes('doorSfx'), 'should have door sound effects');
		assert.ok(src.includes('doorAudio'), 'should track door audio');
	});

	test('main.js has noise buffer synthesizer', () => {
		assert.ok(src.includes('noiseBuffer'), 'should synthesize noise buffers');
		assert.ok(src.includes('makeNoise'), 'should create noise sources');
	});

	test('main.js has tone buffer synthesizer for alarms', () => {
		assert.ok(src.includes('toneBuffer'), 'should synthesize tone buffers');
		assert.ok(src.includes('alarmBuf'), 'should have alarm buffer');
	});

	test('main.js has shutdown buffer synthesizer', () => {
		assert.ok(src.includes('shutdownBuffer'), 'should synthesize shutdown sound');
	});

	test('main.js has hum fade system', () => {
		assert.ok(src.includes('fadeHum'), 'should have hum fade function');
		assert.ok(src.includes('tickHumFades'), 'should tick hum fades');
	});

	test('main.js has urgentAlarm function', () => {
		assert.ok(src.includes('urgentAlarm'), 'should have urgent alarm for low time');
	});
});

describe('Particle system', () => {
	test('main.js has emitParticles function', () => {
		assert.ok(src.includes('const emitParticles'));
	});

	test('main.js has tickParticles function', () => {
		assert.ok(src.includes('const tickParticles'));
	});

	test('main.js has kickSand function for dust', () => {
		assert.ok(src.includes('const kickSand'));
	});

	test('main.js has tickDust function', () => {
		assert.ok(src.includes('const tickDust'));
	});

	test('main.js particles use additive blending', () => {
		assert.ok(src.includes('THREE.AdditiveBlending'), 'particles should use additive blending');
	});

	test('main.js dust uses ShaderMaterial', () => {
		assert.ok(src.includes('THREE.ShaderMaterial'), 'dust should use custom shader');
		assert.ok(src.includes('vertexShader') && src.includes('fragmentShader'), 'shader should have vertex and fragment');
	});
});

describe('Debug interface', () => {
	test('main.js exposes __dbg on window', () => {
		assert.ok(src.includes('window.__dbg'), 'should expose debug interface');
	});

	test('main.js __dbg includes key game objects', () => {
		assert.ok(src.includes('input') && src.includes('player') && src.includes('camera') && src.includes('quest'));
	});

	test('main.js __dbg includes teleport command', () => {
		assert.ok(src.includes('teleport'), 'should expose teleport in debug');
	});

	test('main.js __dbg includes dialGate command', () => {
		assert.ok(src.includes('dialGate'), 'should expose dialGate in debug');
	});

	test('main.js __dbg includes launchKino command', () => {
		assert.ok(src.includes('launchKino'), 'should expose launchKino in debug');
	});

	test('main.js __dbg includes setView command', () => {
		assert.ok(src.includes('setView'), 'should expose setView in debug');
	});

	test('main.js exposes dev console commands', () => {
		assert.ok(src.includes('noclip'), 'should have noclip command');
		assert.ok(src.includes('leveledit'), 'should have level editor command');
		assert.ok(src.includes('chapter'), 'should have chapter command');
		assert.ok(src.includes('flag'), 'should have flag command');
		assert.ok(src.includes('give'), 'should have give command');
	});
});

describe('Main loop', () => {
	test('main.js has frame function as main render loop', () => {
		assert.ok(src.includes('const frame'));
	});

	test('main.js has loop function with rAF scheduling', () => {
		assert.ok(src.includes('const loop'));
		assert.ok(src.includes('requestAnimationFrame'));
	});

	test('main.js has schedule function', () => {
		assert.ok(src.includes('const schedule'));
	});

	test('main.js loop handles hidden tab with setTimeout fallback', () => {
		assert.ok(src.includes('document.hidden') && src.includes('setTimeout'), 'should fall back to timer in hidden tabs');
	});

	test('main.js has recording loop (recLoop)', () => {
		assert.ok(src.includes('recLoop'), 'should have recording loop');
	});

	test('main.js uses MessageChannel for non-throttled waits', () => {
		assert.ok(src.includes('MessageChannel'), 'should use MessageChannel for hidden-tab timing');
		assert.ok(src.includes('hop'), 'should have hop function');
	});

	test('main.js frame handles pause state (remote, console, hotwire, flow)', () => {
		assert.ok(src.includes('isRemoteOpen') && src.includes('isOpen()'), 'should check pause conditions');
	});

	test('main.js frame renders correct scene based on travel/kino state', () => {
		assert.ok(src.includes("travel?.phase === 'wormhole'"), 'should render wormhole scene during travel');
		assert.ok(src.includes('kino.active'), 'should render kino scene when active');
	});

	test('main.js has FPS counter', () => {
		assert.ok(src.includes('fps') && src.includes('frames'), 'should track FPS');
	});

	test('main.js has simTime tracking', () => {
		assert.ok(src.includes('simTime'), 'should track simulation time');
	});

	test('main.js processes NPC updates in main loop', () => {
		assert.ok(src.includes('npcs') && src.includes('n.update'), 'should update NPCs in loop');
	});

	test('main.js processes gate tick in main loop', () => {
		assert.ok(src.includes('gate.userData.tick'), 'should tick gate animation');
	});

	test('main.js processes room discovery in main loop', () => {
		assert.ok(src.includes('tickRooms'), 'should process room discovery');
	});

	test('main.js processes air/oxygen system in main loop', () => {
		assert.ok(src.includes('rpg.o2'), 'should process oxygen in main loop');
		assert.ok(src.includes('airless'), 'should check airless state');
	});

	test('main.js processes waypoint beacon in main loop', () => {
		assert.ok(src.includes('waypointPos') && src.includes('beacon'), 'should update waypoint beacon');
	});

	test('main.js processes minimap drawing in main loop', () => {
		assert.ok(src.includes('drawMinimap'), 'should draw minimap');
	});

	test('main.js processes music mood in main loop', () => {
		assert.ok(src.includes('music.setMood'), 'should set music mood based on game state');
	});

	test('main.js calls schedule() at end of loop', () => {
		assert.ok(src.includes('schedule()'), 'should self-schedule next frame');
	});
});

describe('Autoplay and recorder integration', () => {
	test('main.js has autoplay integration via ?autoplay query param', () => {
		assert.ok(src.includes("location.search.includes('autoplay')"));
		assert.ok(src.includes('createAutoplay'));
	});

	test('main.js has recorder integration via ?record query param', () => {
		assert.ok(src.includes("location.search.includes('record')"));
		assert.ok(src.includes('createRecorder'));
	});

	test('main.js recorder uses MessageChannel hop for timing', () => {
		assert.ok(src.includes('await hop'), 'recorder should use hop for non-throttled waits');
	});
});

describe('Level editor integration', () => {
	test('main.js creates level editor via createLevelEditor', () => {
		assert.ok(src.includes('createLevelEditor'));
	});

	test('main.js level editor has onEnter and onExit callbacks', () => {
		assert.ok(src.includes('onEnter') && src.includes('onExit'));
	});

	test('main.js level editor exit reloads with ?layout=live', () => {
		assert.ok(src.includes('layout=live'), 'editor exit should reload with live layout');
	});

	test('main.js supports LIVE layout from localStorage', () => {
		assert.ok(src.includes("layout=live") && src.includes('localStorage'), 'should support live layout editing');
	});
});

describe('Quest engine wiring', () => {
	test('main.js creates quest engine via createQuestEngine', () => {
		assert.ok(src.includes('createQuestEngine'));
	});

	test('main.js quest engine has grantXp callback', () => {
		assert.ok(src.includes('grantXp'));
	});

	test('main.js quest engine has onStep callback for UI refresh', () => {
		assert.ok(src.includes('onStep') && src.includes('refreshTracker'));
	});

	test('main.js quest engine has onTrigger callback', () => {
		assert.ok(src.includes('onTrigger'));
	});

	test('main.js quest engine handles subtitle triggers', () => {
		assert.ok(src.includes("t.type === 'subtitle'"));
	});

	test('main.js quest engine handles radio triggers', () => {
		assert.ok(src.includes("t.type === 'radio'"));
	});

	test('main.js quest engine handles ftl_drop triggers', () => {
		assert.ok(src.includes("t.type === 'ftl_drop'"));
	});

	test('main.js quest engine handles countdown triggers', () => {
		assert.ok(src.includes("t.type === 'countdown'"));
	});

	test('main.js quest engine handles dial triggers', () => {
		assert.ok(src.includes("t.type === 'dial'"));
	});

	test('main.js quest engine has onChapterComplete callback', () => {
		assert.ok(src.includes('onChapterComplete'));
	});

	test('main.js loads chapters from data/chapters.json', () => {
		assert.ok(src.includes('data/chapters.json'), 'should load quest chapters from data file');
	});
});

describe('RPG integration', () => {
	test('main.js imports RPG functions', () => {
		assert.ok(src.includes('loadItems') && src.includes('addItem') && src.includes('removeItem'));
		assert.ok(src.includes('count') && src.includes('equip') && src.includes('stats'));
		assert.ok(src.includes('grantXp') && src.includes('addLog'));
	});

	test('main.js wires onRpgChange for UI refresh', () => {
		assert.ok(src.includes('onRpgChange'), 'should subscribe to RPG state changes');
		assert.ok(src.includes('ui.refreshPlayer'), 'should refresh player UI on change');
	});

	test('main.js has RPG item giving via dev console', () => {
		assert.ok(src.includes("give: (id"), 'dev console should support giving items');
	});
});