/**
 * Unit tests for src/ancient.js — Ancient-metal procedural textures and materials.
 *
 * Run with:  node --test tests/ancient.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * ancient.js imports three and uses document.createElement('canvas') for
 * procedural textures. We stub the DOM canvas before importing so the module
 * loads cleanly in Node.
 *
 * Coverage: ancientPlates, ancientGrating, ancientMaterial,
 * ancientFloorMaterial, runwayLights, octagonFrame, wallSlit.
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
globalThis.document.createElement = (tag) => {
	if (tag === 'canvas') return _fakeCanvas();
	return { style: {}, appendChild() {}, setAttribute() {}, addEventListener() {} };
};

// ─── Imports ───
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {
	ancientPlates,
	ancientGrating,
	ancientMaterial,
	ancientFloorMaterial,
	runwayLights,
	octagonFrame,
	wallSlit,
} from '../src/ancient.js';

// ─── Tests ───

describe('ancientPlates', () => {
	test('returns { map, rough } object', () => {
		const r = ancientPlates();
		assert.ok(r.map, 'must have map');
		assert.ok(r.rough, 'must have rough');
	});

	test('map is a CanvasTexture', () => {
		const r = ancientPlates();
		assert.equal(r.map.isCanvasTexture, true);
	});

	test('rough is a CanvasTexture', () => {
		const r = ancientPlates();
		assert.equal(r.rough.isCanvasTexture, true);
	});

	test('map colorSpace is SRGB', () => {
		const r = ancientPlates();
		assert.equal(r.map.colorSpace, THREE.SRGBColorSpace);
	});

	test('rough colorSpace is NOT SRGB (linear)', () => {
		const r = ancientPlates();
		assert.notEqual(r.rough.colorSpace, THREE.SRGBColorSpace);
	});

	test('map has RepeatWrapping on S and T', () => {
		const r = ancientPlates();
		assert.equal(r.map.wrapS, THREE.RepeatWrapping);
		assert.equal(r.map.wrapT, THREE.RepeatWrapping);
	});

	test('accepts custom size option', () => {
		const r = ancientPlates({ size: 256 });
		assert.equal(r.map.image.width, 256);
		assert.equal(r.map.image.height, 256);
	});

	test('accepts custom base color', () => {
		const r = ancientPlates({ base: '#ff0000' });
		assert.ok(r.map);
	});

	test('accepts plates option', () => {
		const r = ancientPlates({ plates: 3 });
		assert.ok(r.map);
	});

	test('ribs=false disables vent ribs', () => {
		const r = ancientPlates({ ribs: false });
		assert.ok(r.map);
	});

	test('rivets=false disables rivets', () => {
		const r = ancientPlates({ rivets: false });
		assert.ok(r.map);
	});

	test('default size is 1024', () => {
		const r = ancientPlates();
		assert.equal(r.map.image.width, 1024);
		assert.equal(r.map.image.height, 1024);
	});

	test('anisotropy is set to 8', () => {
		const r = ancientPlates();
		assert.equal(r.map.anisotropy, 8);
	});

	test('multiple calls produce independent textures', () => {
		const a = ancientPlates();
		const b = ancientPlates();
		assert.notEqual(a.map, b.map);
		assert.notEqual(a.rough, b.rough);
	});
});

describe('ancientGrating', () => {
	test('returns { map, rough } object', () => {
		const r = ancientGrating();
		assert.ok(r.map, 'must have map');
		assert.ok(r.rough, 'must have rough');
	});

	test('map is a CanvasTexture', () => {
		const r = ancientGrating();
		assert.equal(r.map.isCanvasTexture, true);
	});

	test('default size is 1024', () => {
		const r = ancientGrating();
		assert.equal(r.map.image.width, 1024);
		assert.equal(r.map.image.height, 1024);
	});

	test('accepts custom size', () => {
		const r = ancientGrating({ size: 512 });
		assert.equal(r.map.image.width, 512);
		assert.equal(r.map.image.height, 512);
	});

	test('accepts custom panels count', () => {
		const r = ancientGrating({ panels: 6 });
		assert.ok(r.map);
	});

	test('accepts custom base color', () => {
		const r = ancientGrating({ base: '#222222' });
		assert.ok(r.map);
	});

	test('map has RepeatWrapping', () => {
		const r = ancientGrating();
		assert.equal(r.map.wrapS, THREE.RepeatWrapping);
		assert.equal(r.map.wrapT, THREE.RepeatWrapping);
	});

	test('rough is linear colorSpace', () => {
		const r = ancientGrating();
		assert.notEqual(r.rough.colorSpace, THREE.SRGBColorSpace);
	});

	test('multiple calls produce independent textures', () => {
		const a = ancientGrating();
		const b = ancientGrating();
		assert.notEqual(a.map, b.map);
	});
});

describe('ancientMaterial', () => {
	test('returns a MeshStandardMaterial', () => {
		const m = ancientMaterial();
		assert.equal(m.isMeshStandardMaterial, true);
	});

	test('has map (albedo) set', () => {
		const m = ancientMaterial();
		assert.ok(m.map, 'material must have a map');
	});

	test('has roughnessMap set', () => {
		const m = ancientMaterial();
		assert.ok(m.roughnessMap, 'material must have a roughnessMap');
	});

	test('has bumpMap set (from rough canvas)', () => {
		const m = ancientMaterial();
		assert.ok(m.bumpMap, 'material must have a bumpMap');
	});

	test('default roughness is 0.6', () => {
		const m = ancientMaterial();
		assert.equal(m.roughness, 0.6);
	});

	test('default metalness is 0.5', () => {
		const m = ancientMaterial();
		assert.equal(m.metalness, 0.5);
	});

	test('accepts custom roughness', () => {
		const m = ancientMaterial({ roughness: 0.3 });
		assert.equal(m.roughness, 0.3);
	});

	test('accepts custom metalness', () => {
		const m = ancientMaterial({ metalness: 0.9 });
		assert.equal(m.metalness, 0.9);
	});

	test('accepts custom repeat [x, y]', () => {
		const m = ancientMaterial({ repeat: [3, 5] });
		assert.equal(m.map.repeat.x, 3);
		assert.equal(m.map.repeat.y, 5);
	});

	test('accepts custom tint color', () => {
		const m = ancientMaterial({ tint: 0xff8800 });
		assert.equal(m.color.getHex(), 0xff8800);
	});

	test('default tint is white', () => {
		const m = ancientMaterial();
		assert.equal(m.color.getHex(), 0xffffff);
	});

	test('bumpScale is 0.025', () => {
		const m = ancientMaterial();
		assert.equal(m.bumpScale, 0.025);
	});

	test('map repeat matches rough repeat', () => {
		const m = ancientMaterial({ repeat: [2, 7] });
		assert.equal(m.map.repeat.x, m.roughnessMap.repeat.x);
		assert.equal(m.map.repeat.y, m.roughnessMap.repeat.y);
	});

	test('multiple calls produce independent materials', () => {
		const a = ancientMaterial();
		const b = ancientMaterial();
		assert.notEqual(a, b);
		assert.notEqual(a.map, b.map);
	});
});

describe('ancientFloorMaterial', () => {
	test('returns a MeshStandardMaterial', () => {
		const m = ancientFloorMaterial();
		assert.equal(m.isMeshStandardMaterial, true);
	});

	test('has map set', () => {
		const m = ancientFloorMaterial();
		assert.ok(m.map);
	});

	test('has roughnessMap set', () => {
		const m = ancientFloorMaterial();
		assert.ok(m.roughnessMap);
	});

	test('has bumpMap set', () => {
		const m = ancientFloorMaterial();
		assert.ok(m.bumpMap);
	});

	test('default repeat is [4, 8]', () => {
		const m = ancientFloorMaterial();
		assert.equal(m.map.repeat.x, 4);
		assert.equal(m.map.repeat.y, 8);
	});

	test('accepts custom repeat', () => {
		const m = ancientFloorMaterial([2, 3]);
		assert.equal(m.map.repeat.x, 2);
		assert.equal(m.map.repeat.y, 3);
	});

	test('bumpScale is 0.04 (higher than wall material)', () => {
		const m = ancientFloorMaterial();
		assert.equal(m.bumpScale, 0.04);
	});

	test('roughness is 0.5', () => {
		const m = ancientFloorMaterial();
		assert.equal(m.roughness, 0.5);
	});

	test('metalness is 0.45', () => {
		const m = ancientFloorMaterial();
		assert.equal(m.metalness, 0.45);
	});

	test('multiple calls produce independent materials', () => {
		const a = ancientFloorMaterial();
		const b = ancientFloorMaterial();
		assert.notEqual(a, b);
		assert.notEqual(a.map, b.map);
	});
});

describe('runwayLights', () => {
	test('adds meshes to a group', () => {
		const group = new THREE.Group();
		const before = group.children.length;
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 4 });
		assert.ok(group.children.length > before, 'group must have new children');
	});

	test('adds exactly count meshes (plus optional lights)', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 6, light: false });
		// Without lights, only the mesh slabs are added
		assert.equal(group.children.length, 6);
	});

	test('with light=true adds point lights every 2nd position', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 6, light: true });
		// 6 meshes + 3 point lights (i % 2 === 0 for i=0,2,4)
		assert.equal(group.children.length, 9);
	});

	test('default count is 8', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], light: false });
		assert.equal(group.children.length, 8);
	});

	test('default color is amber (0xffa040)', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false });
		const mesh = group.children[0];
		assert.equal(mesh.material.color.getHex(), 0xffa040);
	});

	test('emissive color matches material color', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false });
		const mesh = group.children[0];
		assert.equal(mesh.material.emissive.getHex(), 0xffa040);
	});

	test('emissiveIntensity is 2.2', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false });
		const mesh = group.children[0];
		assert.equal(mesh.material.emissiveIntensity, 2.2);
	});

	test('accepts custom color', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false, color: 0x00ff00 });
		assert.equal(group.children[0].material.color.getHex(), 0x00ff00);
	});

	test('meshes are positioned along the from→to line', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 2, light: false });
		// First mesh at t=0.25, second at t=0.75
		const z0 = group.children[0].position.z;
		const z1 = group.children[1].position.z;
		assert.ok(z0 > 0 && z0 < 5, `first mesh z=${z0} should be in first half`);
		assert.ok(z1 > 5 && z1 < 10, `second mesh z=${z1} should be in second half`);
	});

	test('offset shifts meshes perpendicular to the line', () => {
		const g1 = new THREE.Group();
		const g2 = new THREE.Group();
		runwayLights(g1, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false, offset: 0 });
		runwayLights(g2, { from: [0, 0, 0], to: [0, 0, 10], count: 1, light: false, offset: 2 });
		assert.notEqual(g1.children[0].position.x, g2.children[0].position.x);
	});

	test('point lights have correct color', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 2, light: true, color: 0x0000ff });
		const light = group.children.find(c => c.type === 'PointLight');
		assert.ok(light, 'must have a point light');
		assert.equal(light.color.getHex(), 0x0000ff);
	});

	test('point light intensity is 1.6', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 2, light: true });
		const light = group.children.find(c => c.type === 'PointLight');
		assert.equal(light.intensity, 1.6);
	});

	test('point light distance is 4', () => {
		const group = new THREE.Group();
		runwayLights(group, { from: [0, 0, 0], to: [0, 0, 10], count: 2, light: true });
		const light = group.children.find(c => c.type === 'PointLight');
		assert.equal(light.distance, 4);
	});
});

describe('octagonFrame', () => {
	const POS = new THREE.Vector3(0, 0, 0);
	const MAT = new THREE.MeshStandardMaterial();

	test('adds a frame group to the parent group', () => {
		const group = new THREE.Group();
		const before = group.children.length;
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		assert.ok(group.children.length > before, 'parent group must have new child');
	});

	test('frame child is a Group', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		assert.equal(frame.type, 'Group');
	});

	test('frame contains 7 segments (top, 2 sides, 4 chamfers)', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		assert.equal(frame.children.length, 7);
	});

	test('all segments are Meshes', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		for (const child of frame.children) {
			assert.equal(child.type, 'Mesh');
		}
	});

	test('all segments have castShadow=true', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		for (const child of frame.children) {
			assert.equal(child.castShadow, true);
		}
	});

	test('accepts position parameter', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: new THREE.Vector3(1, 2, 3) });
		const frame = group.children[group.children.length - 1];
		assert.equal(frame.position.x, 1);
		assert.equal(frame.position.y, 2);
		assert.equal(frame.position.z, 3);
	});

	test('accepts rotationY parameter', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS, rotationY: Math.PI / 2 });
		const frame = group.children[group.children.length - 1];
		assert.equal(frame.rotation.y, Math.PI / 2);
	});

	test('default rotationY is 0', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		assert.equal(frame.rotation.y, 0);
	});

	test('default depth is 0.3', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		// Check geometry depth of first segment
		assert.ok(frame.children[0].geometry.parameters.depth >= 0.3);
	});

	test('accepts custom depth', () => {
		const group = new THREE.Group();
		octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS, depth: 0.5 });
		const frame = group.children[group.children.length - 1];
		assert.ok(frame.children[0].geometry.parameters.depth >= 0.5);
	});

	test('returns the frame group', () => {
		const group = new THREE.Group();
		const frame = octagonFrame(group, { w: 3, h: 4, mat: MAT, position: POS });
		assert.equal(frame.type, 'Group');
		assert.ok(group.children.includes(frame));
	});

	test('chamfer is 22% of min(w,h)', () => {
		// Verify the chamfer segments exist and are positioned at 45° angles
		const group = new THREE.Group();
		octagonFrame(group, { w: 4, h: 6, mat: MAT, position: POS });
		const frame = group.children[group.children.length - 1];
		// 7 segments: top(0), left-side(1), right-side(2), then 4 chamfers(3-6)
		const chamferRots = [3, 4, 5, 6].map(i => frame.children[i].rotation.z);
		// Chamfers should have ±PI/4 rotations
		const hasPI4 = chamferRots.some(r => Math.abs(Math.abs(r) - Math.PI / 4) < 0.01);
		assert.ok(hasPI4, 'at least one chamfer should have ±PI/4 rotation');
	});
});

describe('wallSlit', () => {
	test('adds a mesh to the group', () => {
		const group = new THREE.Group();
		const before = group.children.length;
		wallSlit(group, { x: 0, y: 5, z: 0 });
		assert.equal(group.children.length, before + 1);
	});

	test('returns the mesh', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 5, z: 0 });
		assert.equal(m.type, 'Mesh');
		assert.ok(group.children.includes(m));
	});

	test('mesh is positioned at (x, y, z)', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 1, y: 2, z: 3 });
		assert.equal(m.position.x, 1);
		assert.equal(m.position.y, 2);
		assert.equal(m.position.z, 3);
	});

	test('default color is cold white-blue (0xcfe6ff)', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.material.color.getHex(), 0xcfe6ff);
	});

	test('emissive matches color', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.material.emissive.getHex(), 0xcfe6ff);
	});

	test('default intensity is 2.5', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.material.emissiveIntensity, 2.5);
	});

	test('accepts custom intensity', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0, intensity: 5 });
		assert.equal(m.material.emissiveIntensity, 5);
	});

	test('accepts custom color', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0, color: 0xff0000 });
		assert.equal(m.material.color.getHex(), 0xff0000);
		assert.equal(m.material.emissive.getHex(), 0xff0000);
	});

	test('default height is 1.6', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.geometry.parameters.height, 1.6);
	});

	test('accepts custom height', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0, h: 3.2 });
		assert.equal(m.geometry.parameters.height, 3.2);
	});

	test('default rotationY is 0', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.rotation.y, 0);
	});

	test('accepts custom rotationY', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0, rotationY: Math.PI });
		assert.equal(m.rotation.y, Math.PI);
	});

	test('geometry width is thin (0.08)', () => {
		const group = new THREE.Group();
		const m = wallSlit(group, { x: 0, y: 0, z: 0 });
		assert.equal(m.geometry.parameters.width, 0.08);
	});

	test('multiple calls add multiple meshes', () => {
		const group = new THREE.Group();
		wallSlit(group, { x: 0, y: 0, z: 0 });
		wallSlit(group, { x: 1, y: 0, z: 0 });
		wallSlit(group, { x: 2, y: 0, z: 0 });
		assert.equal(group.children.length, 3);
	});
});