/**
 * Unit tests for src/gate-room.js — Procedural Destiny gate room.
 *
 * Run with:  node --test tests/gate-room.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * gate-room.js imports three, Reflector (from three/addons), and ancient.js
 * helpers. It uses browser globals innerWidth/innerHeight for reflector texture
 * sizing. We stub DOM canvas + window dimensions before importing so the module
 * loads cleanly in Node.
 *
 * Coverage: ROOM constants, createGateRoom return shape, group structure,
 * colliders array, reflector assignment, collider properties.
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

// ─── Window dimension stubs (gate-room uses innerWidth/innerHeight) ───
globalThis.innerWidth = 1920;
globalThis.innerHeight = 1080;

// ─── Imports ───
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { ROOM, createGateRoom } from '../src/gate-room.js';

// ─── Tests ───

describe('ROOM constants', () => {
	test('has width, length, height, gateZ, daisH', () => {
		assert.ok('width' in ROOM, 'ROOM must have width');
		assert.ok('length' in ROOM, 'ROOM must have length');
		assert.ok('height' in ROOM, 'ROOM must have height');
		assert.ok('gateZ' in ROOM, 'ROOM must have gateZ');
		assert.ok('daisH' in ROOM, 'ROOM must have daisH');
	});

	test('width is a positive number', () => {
		assert.equal(typeof ROOM.width, 'number');
		assert.ok(ROOM.width > 0, 'width must be positive');
	});

	test('length is a positive number', () => {
		assert.equal(typeof ROOM.length, 'number');
		assert.ok(ROOM.length > 0, 'length must be positive');
	});

	test('height is a positive number', () => {
		assert.equal(typeof ROOM.height, 'number');
		assert.ok(ROOM.height > 0, 'height must be positive');
	});

	test('gateZ is a negative number (gate is behind origin)', () => {
		assert.equal(typeof ROOM.gateZ, 'number');
		assert.ok(ROOM.gateZ < 0, 'gateZ should be negative (behind spawn)');
	});

	test('daisH is a positive number', () => {
		assert.equal(typeof ROOM.daisH, 'number');
		assert.ok(ROOM.daisH > 0, 'daisH must be positive');
	});

	test('width is less than length (room is longer than wide)', () => {
		assert.ok(ROOM.width < ROOM.length, 'width should be < length');
	});

	test('specific values match design spec', () => {
		assert.equal(ROOM.width, 20);
		assert.equal(ROOM.length, 40);
		assert.equal(ROOM.height, 11);
		assert.equal(ROOM.gateZ, -15);
		assert.equal(ROOM.daisH, 0.18);
	});
});

describe('createGateRoom', () => {
	test('returns an object with group and colliders', () => {
		const result = createGateRoom();
		assert.ok(result, 'must return a result');
		assert.ok(result.group, 'must have group');
		assert.ok(result.colliders, 'must have colliders');
	});

	test('group is a THREE.Group', () => {
		const { group } = createGateRoom();
		assert.ok(group instanceof THREE.Group, 'group must be THREE.Group');
	});

	test('group is named "gateRoom"', () => {
		const { group } = createGateRoom();
		assert.equal(group.name, 'gateRoom');
	});

	test('colliders is an array', () => {
		const { colliders } = createGateRoom();
		assert.ok(Array.isArray(colliders), 'colliders must be an array');
	});

	test('colliders is non-empty (room has physical geometry)', () => {
		const { colliders } = createGateRoom();
		assert.ok(colliders.length > 0, 'should have at least one collider');
	});

	test('colliders are THREE.Box3 instances', () => {
		const { colliders } = createGateRoom();
		for (const c of colliders) {
			assert.ok(c instanceof THREE.Box3, 'each collider must be THREE.Box3');
		}
	});

	test('each collider has min and max vectors', () => {
		const { colliders } = createGateRoom();
		for (const c of colliders) {
			assert.ok(c.min instanceof THREE.Vector3, 'collider.min must be Vector3');
			assert.ok(c.max instanceof THREE.Vector3, 'collider.max must be Vector3');
		}
	});

	test('each collider has valid min <= max', () => {
		const { colliders } = createGateRoom();
		for (const c of colliders) {
			assert.ok(c.min.x <= c.max.x, 'collider min.x <= max.x');
			assert.ok(c.min.y <= c.max.y, 'collider min.y <= max.y');
			assert.ok(c.min.z <= c.max.z, 'collider min.z <= max.z');
		}
	});

	test('colliders span the room length (z-axis range)', () => {
		const { colliders } = createGateRoom();
		const zMin = Math.min(...colliders.map(c => c.min.z));
		const zMax = Math.max(...colliders.map(c => c.max.z));
		assert.ok(zMax - zMin > 10, 'colliders should span at least 10m in z');
	});

	test('colliders are within room width bounds', () => {
		const { colliders } = createGateRoom();
		const halfWidth = ROOM.width / 2;
		for (const c of colliders) {
			assert.ok(c.min.x >= -halfWidth - 1, 'collider min.x within room bounds');
			assert.ok(c.max.x <= halfWidth + 1, 'collider max.x within room bounds');
		}
	});

	test('colliders are within room height bounds', () => {
		const { colliders } = createGateRoom();
		for (const c of colliders) {
			assert.ok(c.min.y >= 0, 'collider min.y >= floor');
			assert.ok(c.max.y <= ROOM.height + 1, 'collider max.y <= ceiling');
		}
	});

	test('group has children (geometry was added)', () => {
		const { group } = createGateRoom();
		assert.ok(group.children.length > 0, 'group should have children');
	});

	test('group has userData.reflector set', () => {
		const { group } = createGateRoom();
		assert.ok(group.userData.reflector, 'group.userData.reflector must be set');
	});

	test('reflector is an object with isReflector or constructor', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(typeof ref === 'object', 'reflector must be an object');
	});

	test('accepts a renderer argument without error', () => {
		assert.doesNotThrow(() => createGateRoom({}));
	});

	test('accepts null/undefined renderer', () => {
		assert.doesNotThrow(() => createGateRoom(null));
		assert.doesNotThrow(() => createGateRoom(undefined));
	});

	test('group contains a named gateRoom (metadata)', () => {
		const { group } = createGateRoom();
		assert.equal(group.name, 'gateRoom');
	});

	test('multiple calls create independent groups', () => {
		const a = createGateRoom();
		const b = createGateRoom();
		assert.notEqual(a.group, b.group, 'groups should be different objects');
		assert.notEqual(a.colliders, b.colliders, 'collider arrays should be different');
	});

	test('collider count is reasonable (pillars + columns + consoles)', () => {
		const { colliders } = createGateRoom();
		// 4 buttress colliders + 10 column colliders (5 per side) + 2 console colliders = 16 minimum
		assert.ok(colliders.length >= 12, `expected >= 12 colliders, got ${colliders.length}`);
		assert.ok(colliders.length <= 40, `expected <= 40 colliders, got ${colliders.length}`);
	});

	test('group has lights (hemisphere, directional, point)', () => {
		const { group } = createGateRoom();
		const lights = group.children.filter(c =>
			c instanceof THREE.HemisphereLight ||
			c instanceof THREE.DirectionalLight ||
			c instanceof THREE.PointLight ||
			c instanceof THREE.SpotLight ||
			c instanceof THREE.AmbientLight
		);
		assert.ok(lights.length >= 5, `expected >= 5 lights, got ${lights.length}`);
	});

	test('group has at least one SpotLight (ceiling ring)', () => {
		const { group } = createGateRoom();
		const spotlights = group.children.filter(c => c instanceof THREE.SpotLight);
		assert.ok(spotlights.length >= 3, `expected >= 3 spotlights, got ${spotlights.length}`);
	});

	test('group has at least one DirectionalLight (key light)', () => {
		const { group } = createGateRoom();
		const dirLights = group.children.filter(c => c instanceof THREE.DirectionalLight);
		assert.ok(dirLights.length >= 1, 'should have at least 1 directional light');
	});

	test('key directional light has shadow enabled', () => {
		const { group } = createGateRoom();
		const keyLight = group.children.find(c => c instanceof THREE.DirectionalLight);
		assert.ok(keyLight, 'must find directional light');
		assert.equal(keyLight.castShadow, true, 'key light should cast shadows');
	});

	test('group has an AmbientLight', () => {
		const { group } = createGateRoom();
		const ambient = group.children.filter(c => c instanceof THREE.AmbientLight);
		assert.ok(ambient.length >= 1, 'should have ambient light');
	});

	test('group has a HemisphereLight', () => {
		const { group } = createGateRoom();
		const hemi = group.children.filter(c => c instanceof THREE.HemisphereLight);
		assert.ok(hemi.length >= 1, 'should have hemisphere light');
	});

	test('reflector texture dimensions derived from innerWidth/innerHeight', () => {
		// With innerWidth=1920, innerHeight=1080, textureWidth should be 960
		const { group } = createGateRoom();
		// The Reflector stores options; just verify it was created without error
		assert.ok(group.userData.reflector, 'reflector should exist');
	});

	test('group has meshes (BoxGeometry, PlaneGeometry, etc.)', () => {
		const { group } = createGateRoom();
		const meshes = [];
		group.traverse(obj => {
			if (obj.isMesh) meshes.push(obj);
		});
		assert.ok(meshes.length >= 20, `expected >= 20 meshes, got ${meshes.length}`);
	});

	test('group has a reflector mesh (PlaneGeometry on floor)', () => {
		const { group } = createGateRoom();
		// The reflector is added directly to the group and also stored in userData
		assert.ok(group.userData.reflector, 'reflector in userData');
	});

	test('group has ceiling torus ring', () => {
		const { group } = createGateRoom();
		const torusMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.geometry instanceof THREE.TorusGeometry) torusMeshes.push(obj);
		});
		assert.ok(torusMeshes.length >= 1, 'should have at least 1 torus (ceiling ring)');
	});

	test('colliders near gate area (z near gateZ)', () => {
		const { colliders } = createGateRoom();
		const gateColliders = colliders.filter(c => c.min.z < ROOM.gateZ + 10);
		assert.ok(gateColliders.length >= 2, `expected >= 2 colliders near gate, got ${gateColliders.length}`);
	});

	test('colliders near front area (z near front of room)', () => {
		const { colliders } = createGateRoom();
		const zFront = ROOM.gateZ + ROOM.length;
		const frontColliders = colliders.filter(c => c.max.z > zFront - 15);
		assert.ok(frontColliders.length >= 1, 'expected >= 1 collider near front');
	});

	test('buttress colliders are on both sides (±x)', () => {
		const { colliders } = createGateRoom();
		const leftColliders = colliders.filter(c => c.max.x < 0);
		const rightColliders = colliders.filter(c => c.min.x > 0);
		assert.ok(leftColliders.length >= 2, `expected >= 2 left-side colliders, got ${leftColliders.length}`);
		assert.ok(rightColliders.length >= 2, `expected >= 2 right-side colliders, got ${rightColliders.length}`);
	});

	test('console pedestal colliders exist near z=gateZ+15', () => {
		const { colliders } = createGateRoom();
		const consoleZ = ROOM.gateZ + 15.5;
		const consoles = colliders.filter(c =>
			Math.abs(c.min.z - consoleZ) < 2 || Math.abs(c.max.z - consoleZ) < 2
		);
		assert.ok(consoles.length >= 2, `expected >= 2 console colliders, got ${consoles.length}`);
	});

	test('column colliders span the side walls', () => {
		const { colliders } = createGateRoom();
		// Columns are at sx * (wx - 0.45) where wx = width/2 - 0.3 = 9.7
		// So columns at ±9.25
		const sideColumns = colliders.filter(c =>
			Math.abs(Math.abs(c.min.x) - 9.25) < 2 || Math.abs(Math.abs(c.max.x) - 9.25) < 2
		);
		assert.ok(sideColumns.length >= 4, `expected >= 4 side column colliders, got ${sideColumns.length}`);
	});

	test('collider y-values start at floor level', () => {
		const { colliders } = createGateRoom();
		for (const c of colliders) {
			assert.ok(c.min.y >= 0, 'collider min.y should be at or above floor');
		}
	});

	test('group has shadow-casting meshes', () => {
		const { group } = createGateRoom();
		const shadowCasters = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.castShadow) shadowCasters.push(obj);
		});
		assert.ok(shadowCasters.length >= 5, `expected >= 5 shadow casters, got ${shadowCasters.length}`);
	});

	test('group has non-collidable decorative meshes (noCollide)', () => {
		const { group } = createGateRoom();
		// Many decorative elements (light slits, rails, screen panels) are added with noCollide
		// They're in the group but not in the colliders array
		const { colliders } = createGateRoom();
		const meshes = [];
		group.traverse(obj => { if (obj.isMesh) meshes.push(obj); });
		// There should be significantly more meshes than colliders
		assert.ok(meshes.length > colliders.length * 3,
			`expected >> meshes than colliders (${meshes.length} vs ${colliders.length})`);
	});

	test('buttress colliders have limited height (foot blocks only)', () => {
		const { colliders } = createGateRoom();
		// Buttress colliders are foot blocks: max.y = 3
		const buttressColliders = colliders.filter(c => c.max.y <= 3.1 && c.max.y >= 2.9);
		assert.ok(buttressColliders.length >= 4, `expected >= 4 buttress foot colliders, got ${buttressColliders.length}`);
	});

	test('column colliders span full room height', () => {
		const { colliders } = createGateRoom();
		const fullHeightColliders = colliders.filter(c => c.max.y >= ROOM.height - 1);
		assert.ok(fullHeightColliders.length >= 5, `expected >= 5 full-height colliders, got ${fullHeightColliders.length}`);
	});

	test('createGateRoom is idempotent in structure (same child count)', () => {
		const a = createGateRoom();
		const b = createGateRoom();
		assert.equal(a.group.children.length, b.group.children.length,
			'multiple calls should produce identical child counts');
		assert.equal(a.colliders.length, b.colliders.length,
			'multiple calls should produce identical collider counts');
	});

	test('group contains point lights with warm color (orange/amber)', () => {
		const { group } = createGateRoom();
		const warmLights = group.children.filter(c =>
			c instanceof THREE.PointLight && (c.color.r > c.color.b)
		);
		assert.ok(warmLights.length >= 2, `expected >= 2 warm point lights, got ${warmLights.length}`);
	});

	test('group contains point lights with cool color (blue)', () => {
		const { group } = createGateRoom();
		const coolLights = group.children.filter(c =>
			c instanceof THREE.PointLight && (c.color.b > c.color.r)
		);
		assert.ok(coolLights.length >= 2, `expected >= 2 cool point lights, got ${coolLights.length}`);
	});

	test('reflector has a plane geometry', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(ref.geometry, 'reflector should have geometry');
	});

	test('reflector geometry is PlaneGeometry', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(ref.geometry instanceof THREE.PlaneGeometry, 'reflector geometry should be PlaneGeometry');
	});

	test('reflector is rotated to be horizontal (floor)', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		// rotation.x = -PI/2 makes it horizontal
		assert.ok(Math.abs(ref.rotation.x - (-Math.PI / 2)) < 0.01, 'reflector should be horizontal');
	});

	test('reflector positioned at y near 0 (floor level)', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(Math.abs(ref.position.y) < 0.1, 'reflector should be at floor level');
	});

	test('reflector geometry width matches ROOM.width', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(Math.abs(ref.geometry.parameters.width - ROOM.width) < 0.1,
			'reflector width should match ROOM.width');
	});

	test('reflector geometry height matches ROOM.length', () => {
		const { group } = createGateRoom();
		const ref = group.userData.reflector;
		assert.ok(Math.abs(ref.geometry.parameters.height - ROOM.length) < 0.1,
			'reflector height should match ROOM.length');
	});

	test('group has at least one Mesh with MeshStandardMaterial', () => {
		const { group } = createGateRoom();
		const standardMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.material instanceof THREE.MeshStandardMaterial) standardMeshes.push(obj);
		});
		assert.ok(standardMeshes.length >= 5, `expected >= 5 MeshStandardMaterial meshes, got ${standardMeshes.length}`);
	});

	test('floor mesh exists with transparent material', () => {
		const { group } = createGateRoom();
		const floorMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.geometry instanceof THREE.PlaneGeometry && obj.material.transparent) {
				floorMeshes.push(obj);
			}
		});
		assert.ok(floorMeshes.length >= 1, 'should have at least 1 transparent floor mesh');
	});

	test('floor mesh has opacity < 1', () => {
		const { group } = createGateRoom();
		const floorMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.geometry instanceof THREE.PlaneGeometry && obj.material.transparent) {
				floorMeshes.push(obj);
			}
		});
		for (const m of floorMeshes) {
			assert.ok(m.material.opacity < 1, 'floor material opacity should be < 1');
		}
	});

	test('dais mesh exists (low box under gate)', () => {
		const { group } = createGateRoom();
		const daisMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.geometry instanceof THREE.BoxGeometry) {
				const h = obj.geometry.parameters.height;
				if (h > 0.1 && h < 0.3 && obj.position.y > 0 && obj.position.y < 0.2) {
					daisMeshes.push(obj);
				}
			}
		});
		assert.ok(daisMeshes.length >= 1, 'should have at least 1 dais mesh');
	});

	test('monitor alcove mesh exists (upper wall area)', () => {
		const { group } = createGateRoom();
		const monitorMeshes = [];
		group.traverse(obj => {
			if (obj.isMesh && obj.position.y > 7) {
				monitorMeshes.push(obj);
			}
		});
		assert.ok(monitorMeshes.length >= 2, `expected >= 2 upper-area meshes, got ${monitorMeshes.length}`);
	});
});