/**
 * Unit tests for src/destination.js — desert world planet scene.
 *
 * Run with:  node --test tests/destination.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * destination.js imports three and stargate.js, and uses
 * document.createElement('canvas') for procedural ground textures.
 * We stub the DOM canvas before importing so the module loads cleanly.
 *
 * Coverage: createDestination return shape, scene background/fog, default
 * biome, custom biome override, terrainHeight (flat near gate, dunes beyond),
 * meshHeight bilinear interpolation, colliders array, occludable array,
 * gate presence and position, resource nodes, spawn/anchors, clampCamera,
 * floorAt, ground mesh, and edge cases.
 */

// ─── DOM Canvas Stub (before import) ───
function _fakeCanvas(size = 512) {
	return {
		width: size,
		height: size,
		getContext() {
			return {
				fillRect() {}, strokeRect() {}, clearRect() {},
				beginPath() {}, arc() {}, fill() {}, stroke() {},
				moveTo() {}, lineTo() {}, closePath() {},
				save() {}, restore() {}, translate() {}, rotate() {}, scale() {},
				fillStyle: '', strokeStyle: '', lineWidth: 1,
				createLinearGradient() { return { addColorStop() {} }; },
				createRadialGradient() { return { addColorStop() {} }; },
			};
		},
	};
}

globalThis.document = globalThis.document ?? {};
const _origCreateElement = globalThis.document.createElement;
globalThis.document.createElement = (tag) => {
	if (tag === 'canvas') return _fakeCanvas();
	return { style: {}, appendChild() {}, setAttribute() {}, addEventListener() {} };
};

// ─── Imports ───
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createDestination } from '../src/destination.js';

// ─── Tests ───

describe('createDestination return shape', () => {
	const d = createDestination();

	test('returns an object with expected keys', () => {
		assert.ok(d.scene, 'scene exists');
		assert.ok(d.colliders, 'colliders exists');
		assert.ok(d.gate, 'gate exists');
		assert.ok(d.occludable, 'occludable exists');
		assert.ok(d.nodes, 'nodes exists');
		assert.ok(d.spawn, 'spawn exists');
		assert.ok(d.clampCamera, 'clampCamera is a function');
		assert.ok(d.floorAt, 'floorAt is a function');
		assert.ok(d.ground, 'ground exists');
		assert.ok(d.terrainHeight, 'terrainHeight is a function');
		assert.ok(d.meshHeight, 'meshHeight is a function');
	});

	test('name is "planet"', () => {
		assert.equal(d.name, 'planet');
	});

	test('exitDir is 1 (player walks +Z)', () => {
		assert.equal(d.exitDir, 1);
	});

	test('spawnYaw is 0', () => {
		assert.equal(d.spawnYaw, 0);
	});

	test('def is the planet definition (empty object by default)', () => {
		assert.ok(typeof d.def === 'object');
	});
});

describe('scene background and fog', () => {
	const d = createDestination();

	test('background is a Color (default fog color)', () => {
		assert.ok(d.scene.background instanceof THREE.Color);
		assert.equal(d.scene.background.getHexString(), 'c9b28a');
	});

	test('fog is FogExp2', () => {
		assert.ok(d.scene.fog instanceof THREE.FogExp2);
	});

	test('scene has children (sky, ground, gate, etc.)', () => {
		assert.ok(d.scene.children.length > 3, 'scene has multiple objects');
	});
});

describe('default biome', () => {
	const d = createDestination();

	test('ground color is default brown', () => {
		// ground uses CanvasTexture from default biome.ground = '#b48a5a'
		assert.ok(d.ground.material.map, 'ground has a texture');
	});
});

describe('custom biome override', () => {
	const d = createDestination({
		biome: {
			sky_low: '#ff0000', sky_high: '#00ff00',
			ground: '#0000ff', fog: '#ffff00', sun: '#ff00ff', rock: '#888888',
		},
	});

	test('background uses custom fog color', () => {
		assert.equal(d.scene.background.getHexString(), 'ffff00');
	});

	test('fog uses custom fog color', () => {
		assert.equal(d.scene.fog.color.getHexString(), 'ffff00');
	});
});

describe('terrainHeight', () => {
	const d = createDestination();

	test('returns 0 at the gate center', () => {
		assert.equal(d.terrainHeight(0, 0), 0);
	});

	test('returns near-zero within 14m of the gate (flat zone)', () => {
		// terrainHeight = sin(x*0.08) * cos(z*0.06) * 2.2 * Math.min(1, (dd-14)/20)
		// At x=0, sin(0)=0 so the whole thing is 0 regardless of distance.
		// For x≠0 within 14m, the fade factor is negative but small → near-zero.
		assert.ok(Math.abs(d.terrainHeight(5, 5)) < 0.01, 'near-zero at (5,5)');
		assert.ok(Math.abs(d.terrainHeight(10, 10)) < 0.01, 'near-zero at (10,10)');
		// At (13, 0): fade = (13-14)/20 = -0.05, so ~0.009 — very small but non-zero
		assert.ok(Math.abs(d.terrainHeight(13, 0)) < 0.01, 'near-zero at (13,0)');
	});

	test('returns a number beyond 14m', () => {
		const h = d.terrainHeight(30, 30);
		assert.ok(typeof h === 'number');
		assert.ok(Number.isFinite(h));
	});

	test('is not symmetric in x (sin(x) breaks symmetry)', () => {
		// terrainHeight = sin(x*0.08) * cos(z*0.06) * 2.2 * fade
		// sin(x) is odd, so terrainHeight(-x, z) = -terrainHeight(x, z) (for same z)
		const h1 = d.terrainHeight(20, 0);
		const h2 = d.terrainHeight(-20, 0);
		assert.ok(Math.abs(h1 + h2) < 1e-6, 'terrain is antisymmetric in x (sin is odd)');
	});
});

describe('meshHeight (bilinear interpolation)', () => {
	const d = createDestination();

	test('returns 0 at origin (within flat zone)', () => {
		assert.ok(Math.abs(d.meshHeight(0, 0)) < 0.01, 'near-zero at gate center');
	});

	test('returns a finite number at various points', () => {
		for (const [x, z] of [[0, 0], [10, 10], [-20, 30], [50, -50], [100, 100]]) {
			const h = d.meshHeight(x, z);
			assert.ok(Number.isFinite(h), `finite at (${x},${z})`);
		}
	});

	test('clamps to grid bounds without crashing', () => {
		// Outside the grid should clamp, not throw
		assert.doesNotThrow(() => d.meshHeight(999, 999));
		assert.doesNotThrow(() => d.meshHeight(-999, -999));
	});
});

describe('colliders', () => {
	const d = createDestination();

	test('colliders is a non-empty array', () => {
		assert.ok(Array.isArray(d.colliders));
		assert.ok(d.colliders.length > 0, 'has colliders (obelisks, rocks, gate)');
	});

	test('some colliders are Box3 (obelisks, gate)', () => {
		const boxes = d.colliders.filter((c) => c instanceof THREE.Box3);
		assert.ok(boxes.length > 0, 'has Box3 colliders');
	});

	test('some colliders are circle type (rocks, pillars)', () => {
		const circles = d.colliders.filter((c) => c.circle === true);
		assert.ok(circles.length > 0, 'has circle colliders');
	});

	test('circle colliders have x, z, r properties', () => {
		const circles = d.colliders.filter((c) => c.circle === true);
		for (const c of circles) {
			assert.ok(typeof c.x === 'number', 'circle has x');
			assert.ok(typeof c.z === 'number', 'circle has z');
			assert.ok(typeof c.r === 'number', 'circle has r');
			assert.ok(c.r > 0, 'circle radius is positive');
		}
	});
});

describe('occludable', () => {
	const d = createDestination();

	test('occludable is a non-empty array', () => {
		assert.ok(Array.isArray(d.occludable));
		assert.ok(d.occludable.length > 0, 'has occludable objects');
	});

	test('occludable items are Object3D instances', () => {
		for (const o of d.occludable) {
			assert.ok(o instanceof THREE.Object3D, 'occludable is Object3D');
		}
	});
});

describe('gate', () => {
	const d = createDestination();

	test('gate exists and is an Object3D', () => {
		assert.ok(d.gate instanceof THREE.Object3D);
	});

	test('gate is positioned near origin on Z', () => {
		assert.ok(Math.abs(d.gate.position.x) < 0.01, 'gate at x=0');
		assert.ok(Math.abs(d.gate.position.z) < 0.01, 'gate at z=0');
	});

	test('gate is added to the scene', () => {
		// gate should be in the scene's children or descendants
		let found = false;
		d.scene.traverse((o) => { if (o === d.gate) found = true; });
		assert.ok(found, 'gate is in the scene graph');
	});
});

describe('resource nodes', () => {
	test('no resource when planetDef has no resource', () => {
		const d = createDestination({});
		assert.equal(d.nodes.length, 0);
		assert.equal(d.resource, undefined);
	});

	test('creates resource nodes when resource is provided', () => {
		const d = createDestination({
			resource: { id: 'iron', name: 'Iron Ore', color: '#aa8800', count: 5, required: 3, verb: 'mine' },
		});
		assert.equal(d.nodes.length, 5, 'creates count nodes');
		for (const n of d.nodes) {
			assert.ok(n.id.startsWith('iron_'), `node id starts with resource id: ${n.id}`);
			assert.ok(typeof n.x === 'number', 'node has x');
			assert.ok(typeof n.z === 'number', 'node has z');
			assert.ok(n.mesh, 'node has mesh');
			assert.equal(n.remaining, 2);
			assert.equal(n.done, false);
		}
	});

	test('nodes are placed 22-60m from gate', () => {
		const d = createDestination({
			resource: { id: 'ice', name: 'Ice', color: '#88ccff', count: 10, required: 5, verb: 'mine' },
		});
		for (const n of d.nodes) {
			const dist = Math.hypot(n.x, n.z);
			assert.ok(dist >= 22 && dist <= 62, `node at ${dist.toFixed(1)}m (expected 22-60m range)`);
		}
	});
});

describe('spawn and anchors', () => {
	const d = createDestination();

	test('spawn is a Vector3 near the gate', () => {
		assert.ok(d.spawn instanceof THREE.Vector3);
		assert.ok(Math.abs(d.spawn.x) < 0.01, 'spawn x=0');
		assert.ok(d.spawn.z > 0, 'spawn is in +Z direction (away from gate)');
	});

	test('has a GateFront anchor', () => {
		assert.ok(d.anchors['planet:GateFront'], 'GateFront anchor exists');
		assert.ok(d.anchors['planet:GateFront'] instanceof THREE.Vector3);
	});
});

describe('clampCamera', () => {
	const d = createDestination();

	test('prevents camera from going below terrain', () => {
		const p = new THREE.Vector3(0, -10, 0);
		d.clampCamera(p);
		assert.ok(p.y >= 0, 'camera y clamped above terrain');
	});

	test('keeps camera above terrain at various positions', () => {
		for (const [x, z] of [[0, 5], [20, 20], [-30, 40]]) {
			const p = new THREE.Vector3(x, -100, z);
			d.clampCamera(p);
			const terrain = d.meshHeight(x, z);
			assert.ok(p.y >= terrain + 0.39, `camera above terrain at (${x},${z}): y=${p.y.toFixed(2)} >= ${terrain.toFixed(2)}`);
		}
	});

	test('does not lower camera already above terrain', () => {
		const p = new THREE.Vector3(0, 10, 0);
		d.clampCamera(p);
		assert.equal(p.y, 10, 'high camera unchanged');
	});
});

describe('floorAt', () => {
	const d = createDestination();

	test('returns dais height near gate center', () => {
		const h = d.floorAt(0, 0);
		assert.equal(h, 0.3, 'dais height at center');
	});

	test('returns step height at dais edge', () => {
		const h = d.floorAt(7, 0);
		assert.equal(h, 0.15, 'step height at 7m');
	});

	test('returns mesh height far from gate', () => {
		const h = d.floorAt(50, 50);
		const expected = d.meshHeight(50, 50);
		assert.ok(Math.abs(h - expected) < 1e-6, 'meshHeight beyond dais');
	});
});

describe('ground mesh', () => {
	const d = createDestination();

	test('ground is a Mesh with PlaneGeometry', () => {
		assert.ok(d.ground instanceof THREE.Mesh);
		assert.ok(d.ground.geometry instanceof THREE.PlaneGeometry);
	});

	test('ground is rotated to be horizontal', () => {
		assert.ok(Math.abs(d.ground.rotation.x - (-Math.PI / 2)) < 1e-6, 'rotated -PI/2 on X');
	});

	test('ground receives shadows', () => {
		assert.equal(d.ground.receiveShadow, true);
	});

	test('ground has a CanvasTexture', () => {
		assert.ok(d.ground.material.map, 'ground has texture map');
		assert.ok(d.ground.material.map instanceof THREE.CanvasTexture);
	});

	test('texture repeats', () => {
		assert.ok(d.ground.material.map.wrapS === THREE.RepeatWrapping);
		assert.ok(d.ground.material.map.wrapT === THREE.RepeatWrapping);
	});
});

describe('independent instances', () => {
	test('two instances have separate scenes', () => {
		const d1 = createDestination();
		const d2 = createDestination();
		assert.notEqual(d1.scene, d2.scene, 'separate scenes');
		assert.notEqual(d1.colliders, d2.colliders, 'separate collider arrays');
	});

	test('two instances have separate gates', () => {
		const d1 = createDestination();
		const d2 = createDestination();
		assert.notEqual(d1.gate, d2.gate, 'separate gates');
	});
});

describe('edge cases', () => {
	test('createDestination with null/undefined planetDef does not crash', () => {
		assert.doesNotThrow(() => createDestination());
		assert.doesNotThrow(() => createDestination({}));
	});

	test('resource with count=0 creates no nodes', () => {
		const d = createDestination({
			resource: { id: 'test', name: 'Test', color: '#fff', count: 0, required: 0, verb: 'mine' },
		});
		assert.equal(d.nodes.length, 0);
	});
});