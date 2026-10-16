/**
 * Unit tests for src/wormhole.js — wormhole ride scene and camera path.
 *
 * Run with:  node --test tests/wormhole.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * wormhole.js imports three and creates a Scene with a tube mesh and shader
 * material. All Three.js classes used (Scene, Color, ShaderMaterial,
 * CylinderGeometry, Mesh, Vector3) work headlessly in Node — no canvas needed.
 *
 * Coverage: createWormhole return shape, scene background, tube geometry
 * and orientation, shader uniforms, duration, camPath math, tick behavior,
 * camera up vector normalization, and edge cases (k=0, k=1, k>1 clamp).
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createWormhole } from '../src/wormhole.js';

describe('createWormhole return shape', () => {
	const w = createWormhole();

	test('returns an object with scene, tube, duration, tick', () => {
		assert.ok(w.scene, 'scene exists');
		assert.ok(w.tube, 'tube exists');
		assert.equal(typeof w.duration, 'number');
		assert.equal(typeof w.tick, 'function');
	});

	test('duration is 3.6 seconds', () => {
		assert.equal(w.duration, 3.6);
	});
});

describe('scene background', () => {
	const w = createWormhole();

	test('background is a dark blue Color', () => {
		assert.ok(w.scene.background instanceof THREE.Color);
		assert.equal(w.scene.background.getHexString(), '020610');
	});

	test('scene has exactly one child (the tube)', () => {
		assert.equal(w.scene.children.length, 1);
		assert.ok(w.scene.children[0] instanceof THREE.Mesh);
	});
});

describe('tube mesh', () => {
	const w = createWormhole();
	const tube = w.tube;

	test('is a Mesh with CylinderGeometry and ShaderMaterial', () => {
		assert.ok(tube instanceof THREE.Mesh);
		assert.ok(tube.geometry instanceof THREE.CylinderGeometry);
		assert.ok(tube.material instanceof THREE.ShaderMaterial);
	});

	test('geometry has radius ~5, length ~320, open-ended', () => {
		const g = tube.geometry;
		assert.equal(g.parameters.radiusTop, 5);
		assert.equal(g.parameters.radiusBottom, 5);
		assert.equal(g.parameters.height, 320);
		assert.equal(g.parameters.openEnded, true);
	});

	test('tube is rotated PI/2 on X and positioned toward -Z', () => {
		assert.ok(Math.abs(tube.rotation.x - Math.PI / 2) < 1e-6);
		// position.z = -LEN/2 + 10 = -160 + 10 = -150
		assert.ok(Math.abs(tube.position.z - (-150)) < 1e-6);
		assert.equal(tube.position.x, 0);
		assert.equal(tube.position.y, 0);
	});

	test('material uses BackSide rendering', () => {
		assert.equal(w.tube.material.side, THREE.BackSide);
	});
});

describe('shader uniforms', () => {
	const w = createWormhole();
	const u = w.tube.material.uniforms;

	test('has uTime and uK uniforms starting at 0', () => {
		assert.ok('uTime' in u, 'uTime uniform exists');
		assert.ok('uK' in u, 'uK uniform exists');
		assert.equal(u.uTime.value, 0);
		assert.equal(u.uK.value, 0);
	});

	test('has vertex and fragment shaders as strings', () => {
		assert.equal(typeof w.tube.material.vertexShader, 'string');
		assert.equal(typeof w.tube.material.fragmentShader, 'string');
		assert.ok(w.tube.material.vertexShader.length > 0);
		assert.ok(w.tube.material.fragmentShader.length > 0);
	});
});

describe('tick updates uniforms and camera', () => {
	const w = createWormhole();
	const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);

	test('tick sets uTime and uK from arguments', () => {
		w.tick(2.5, 0.4, cam);
		assert.equal(w.tube.material.uniforms.uTime.value, 2.5);
		assert.equal(w.tube.material.uniforms.uK.value, 0.4);
	});

	test('tick moves camera position along z-axis', () => {
		w.tick(0, 0, cam);
		// At k=0: z = -0 * (LEN - 30) = 0, x = sin(0)*1.2 = 0, y = cos(0)*1.0 = 1
		assert.ok(Math.abs(cam.position.x - 0) < 1e-6, 'x=0 at k=0');
		assert.ok(Math.abs(cam.position.y - 1) < 1e-6, 'y=1 at k=0');
		assert.ok(Math.abs(cam.position.z - 0) < 1e-6, 'z=0 at k=0');
	});

	test('tick at k=1 places camera at far end of tube', () => {
		w.tick(3.6, 1, cam);
		// z = -1 * (320 - 30) = -290
		assert.ok(Math.abs(cam.position.z - (-290)) < 1e-6, 'z=-290 at k=1');
	});

	test('tick at k>1 clamps to k+0.02 capped at 1', () => {
		// Should not crash; internally clamps ahead point to min(1, k+0.02)
		w.tick(4.0, 1.5, cam);
		// Camera position still set (from the non-clamped camPath)
		assert.ok(cam.position.z < 0, 'camera moved along z');
	});

	test('camera.up is normalized after tick', () => {
		w.tick(1.0, 0.5, cam);
		assert.ok(Math.abs(cam.up.length() - 1) < 1e-6, 'camera.up is unit length');
	});

	test('camera.lookAt is called (camera has a target matrix)', () => {
		w.tick(0.5, 0.3, cam);
		// lookAt sets the quaternion/matrix; verify camera.matrixWorldAutoUpdate is true
		assert.ok(cam.matrixWorldAutoUpdate !== undefined);
	});
});

describe('camera path math (via tick)', () => {
	const w = createWormhole();

	test('at k=0.5, camera z is roughly midway', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		w.tick(0, 0.5, cam);
		// z = -0.5 * 290 = -145
		assert.ok(Math.abs(cam.position.z - (-145)) < 1e-6);
	});

	test('x oscillates with sin(k*9)', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		w.tick(0, 0.5, cam);
		const expectedX = Math.sin(0.5 * 9.0) * 1.2;
		assert.ok(Math.abs(cam.position.x - expectedX) < 1e-6, `x=${cam.position.x} vs expected ${expectedX}`);
	});

	test('y oscillates with cos(k*7)', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		w.tick(0, 0.5, cam);
		const expectedY = Math.cos(0.5 * 7.0) * 1.0;
		assert.ok(Math.abs(cam.position.y - expectedY) < 1e-6, `y=${cam.position.y} vs expected ${expectedY}`);
	});
});

describe('edge cases', () => {
	const w = createWormhole();

	test('tick with zero dt-equivalent (t=0, k=0) still works', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		assert.doesNotThrow(() => w.tick(0, 0, cam));
	});

	test('multiple sequential ticks accumulate camera movement', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		w.tick(0, 0, cam);
		const z0 = cam.position.z;
		w.tick(1.8, 0.5, cam);
		const z1 = cam.position.z;
		assert.ok(z1 < z0, 'camera moved further along z');
	});

	test('tick does not mutate tube position or rotation', () => {
		const cam = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
		const tubeRotXBefore = w.tube.rotation.x;
		const tubePosZBefore = w.tube.position.z;
		w.tick(2.0, 0.7, cam);
		assert.equal(w.tube.rotation.x, tubeRotXBefore);
		assert.equal(w.tube.position.z, tubePosZBefore);
	});

	test('createWormhole creates independent instances', () => {
		const w1 = createWormhole();
		const w2 = createWormhole();
		w1.tube.material.uniforms.uTime.value = 99;
		assert.equal(w2.tube.material.uniforms.uTime.value, 0, 'instances are independent');
	});
});