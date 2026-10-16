// Procedural Destiny gate room — code-only, primitives + canvas textures. Returns { group, colliders }.
// Colliders are world-space AABBs ({min,max} THREE.Box3) consumed by player.js.
// Layout (metres, +Z toward the camera/spawn, gate at z=0 facing +Z):
//   hall 14 wide × 30 long, 11 high. Gate stands at z=-11 on a raised dais.
import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { ancientMaterial, ancientFloorMaterial, runwayLights, wallSlit } from './ancient.js';

const box = (w, h, d, mat, x, y, z, colliders, opts = {}) => {
	const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
	m.position.set(x, y, z);
	if (opts.ry) m.rotation.y = opts.ry;
	if (opts.rz) m.rotation.z = opts.rz;
	if (opts.rx) m.rotation.x = opts.rx;
	m.castShadow = opts.shadow ?? true; m.receiveShadow = true;
	if (colliders && !opts.noCollide) { m.updateMatrixWorld(); colliders.push(new THREE.Box3().setFromObject(m)); }
	return m;
};

// Hall footprint = the gate_room rect in data/ship_layout.json (800×400 plan units → 40×20 m, z ∈ [-20, 20]); ship.js
// builds its walls/ceiling/doors from that data, this module dresses the interior. Gate stands 5 m in from the back wall.
export const ROOM = { width: 20, length: 40, height: 11, gateZ: -15, daisH: 0.18 };

export const createGateRoom = (_renderer) => {
	const group = new THREE.Group(); group.name = 'gateRoom';
	const colliders = [];
	const { width, length, height, gateZ, daisH } = ROOM;
	const zBack = gateZ - 5, zFront = zBack + length, zMid = (zBack + zFront) / 2;

	const _wallMat = ancientMaterial({ repeat: [4, 1.6], base: '#171c24', plates: 6 }); // Ancient plates (concept: materials sheet)
	const stoneMat = ancientMaterial({ repeat: [1, 3], base: '#1f242c', plates: 3, roughness: 0.6 });
	const darkMat = ancientMaterial({ repeat: [1, 1], base: '#0f1319', plates: 3, roughness: 0.5, metalness: 0.8 });
	const _ceilMat = ancientMaterial({ repeat: [3, 6], base: '#0c0f14', plates: 5, roughness: 0.7 });
	const cyan = new THREE.MeshStandardMaterial({ color: 0xcfe6ff, emissive: 0xa8ccff, emissiveIntensity: 2.2 }); // cold white-blue slits
	const amberScreen = new THREE.MeshStandardMaterial({ color: 0x9fd8ff, emissive: 0x4fa8ff, emissiveIntensity: 1.6 }); // blue console screens

	// --- Floor: reflector + tinted wood overlay (polished look from the reference)
	const reflector = new Reflector(new THREE.PlaneGeometry(width, length), {
		clipBias: 0.003, textureWidth: Math.floor(innerWidth * 0.5), textureHeight: Math.floor(innerHeight * 0.5), color: 0x2e333b,
	});
	reflector.rotation.x = -Math.PI / 2; reflector.position.set(0, -0.002, zMid); group.add(reflector);
	const floorMat = ancientFloorMaterial([3.5, 7.5]); floorMat.transparent = true; floorMat.opacity = 0.86;
	const floor = new THREE.Mesh(new THREE.PlaneGeometry(width, length), floorMat);
	floor.rotation.x = -Math.PI / 2; floor.position.set(0, 0, zMid); floor.receiveShadow = true; group.add(floor);

	// --- Dais under gate
	group.add(box(8, daisH, 3.2, darkMat, 0, daisH / 2, gateZ + 0.6, null, { noCollide: true }));
	// railings flanking the approach to the dais (thin posts + rail), leaving the centre walkway open
	const railMat = ancientMaterial({ repeat: [1, 1], base: '#23282f', plates: 2, roughness: 0.45, metalness: 0.9 });
	for (const sx of [-1, 1]) {
		group.add(box(3.4, 0.05, 0.05, railMat, sx * 3.0, 1.0, gateZ + 2.4, null, { noCollide: true, shadow: false }));
		for (const dx of [-1.6, 0, 1.6]) group.add(box(0.06, 1.0, 0.06, railMat, sx * 3.0 + dx, 0.5, gateZ + 2.4, null, { noCollide: true, shadow: false }));
	}

	// --- Walls / ceiling / doors come from ship.js (data-driven). Wall inner faces sit at ±(width/2 - 0.3).
	const wx = width / 2 - 0.3;
	// tall vertical light slits in the back wall and along the side walls (concept: gate-room-active)
	for (const sx of [-1, 1]) for (const dx of [3.6, 4.6, 5.6]) wallSlit(group, { x: sx * dx, y: 5.6, z: zBack + 0.36, h: 4.2, intensity: 1.8 });
	for (const sx of [-1, 1]) for (let i = 0; i < 7; i++) { const z = gateZ + 2 + i * 5; wallSlit(group, { x: sx * (wx - 0.05), y: 6.2, z, h: 2.6, rotationY: Math.PI / 2, intensity: 1.6 }); wallSlit(group, { x: sx * (wx - 0.05), y: 2.2, z, h: 1.2, rotationY: Math.PI / 2, color: 0xffb060, intensity: 1.2 }); }
	const ringMat = ancientMaterial({ repeat: [6, 1], base: '#12161c', plates: 4, roughness: 0.5, metalness: 0.85 });
	const ceilRing = new THREE.Mesh(new THREE.TorusGeometry(5.2, 0.35, 8, 48), ringMat); ceilRing.rotation.x = Math.PI / 2; ceilRing.position.set(0, height - 0.6, gateZ + 6); group.add(ceilRing);
	for (let i = 0; i < 3; i++) { const a = (i / 3) * Math.PI * 2 + Math.PI / 2; const sp = new THREE.SpotLight(0xcfe0ff, 45, 18, 0.5, 0.6, 1.4); sp.position.set(Math.cos(a) * 4.2, height - 0.9, gateZ + 6 + Math.sin(a) * 4.2); sp.target.position.set(Math.cos(a) * 2.5, 0, gateZ + 6 + Math.sin(a) * 2.5); group.add(sp, sp.target); }
	runwayLights(group, { from: [-2.4, 0, gateZ + 3.5], to: [-2.4, 0, zFront - 0.6], count: 10, light: false });
	runwayLights(group, { from: [2.4, 0, gateZ + 3.5], to: [2.4, 0, zFront - 0.6], count: 10, light: false });
	for (const z of [gateZ + 8, gateZ + 17]) { const l = new THREE.PointLight(0xffa040, 4, 8, 1.8); l.position.set(0, 0.4, z); group.add(l); }

	// --- Angled stone buttresses (the leaning A-frame pillars around the gate)
	const pillarGeo = new THREE.BoxGeometry(1.1, 12.5, 1.6);
	for (const sx of [-1, 1]) {
		for (const [z, lean] of [[gateZ + 1.5, 0.30], [gateZ + 5.0, 0.36]]) {
			const p = new THREE.Mesh(pillarGeo, stoneMat);
			p.position.set(sx * 4.3, 5.4, z); p.rotation.z = sx * lean; p.castShadow = p.receiveShadow = true; group.add(p);
			// collider: foot block only (player can't climb anyway)
			colliders.push(new THREE.Box3(new THREE.Vector3(sx * 5.4 - 0.9, 0, z - 0.9), new THREE.Vector3(sx * 5.4 + 0.9, 3, z + 0.9)));
		}
	}

	// --- Dark tech columns with cyan light strips along the side walls
	for (const sx of [-1, 1]) for (let i = 0; i < 5; i++) {
		const z = gateZ + 6 + i * 5.5; if (Math.abs(z) < 2.2) continue; // leave the side (north/south connector) doors clear
		group.add(box(0.9, height, 0.9, darkMat, sx * (wx - 0.45), height / 2, z, colliders));
		for (let k = 0; k < 9; k++) group.add(box(0.06, 0.5, 0.06, cyan, sx * (wx - 0.92), 1.5 + k * 1.05, z, null, { noCollide: true, shadow: false }));
		// horizontal segmented wall panel
		const py = 6.2;
		group.add(box(0.25, 0.55, 2.6, darkMat, sx * (wx - 0.15), py, z + 2.7, null, { noCollide: true, shadow: false }));
		for (let s = 0; s < 4; s++) group.add(box(0.1, 0.22, 0.45, cyan, sx * (wx - 0.3), py, z + 1.85 + s * 0.57, null, { noCollide: true, shadow: false }));
	}

	// --- Two angled console pedestals in the foreground
	for (const sx of [-1, 1]) {
		const z = gateZ + 15.5, x = sx * 4.6;
		group.add(box(1.4, 0.9, 2.4, darkMat, x, 0.45, z, colliders, { ry: sx * 0.35 }));
		const top = box(1.5, 0.12, 2.5, stoneMat, x, 0.95, z, null, { noCollide: true, ry: sx * 0.35 });
		group.add(top);
		const screen = box(0.9, 0.04, 1.6, amberScreen, x - sx * 0.05, 1.05, z, null, { noCollide: true, shadow: false, ry: sx * 0.35, rx: -sx * 0.25 });
		group.add(screen);
		const glow = new THREE.PointLight(0x6fb8ff, 6, 6, 2); glow.position.set(x, 1.6, z); group.add(glow);
	}

	// --- Upper-left monitor alcove (from the reference's top-left)
	group.add(box(2.2, 1.6, 0.2, darkMat, -wx + 0.3, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));
	group.add(box(1.9, 1.3, 0.05, new THREE.MeshStandardMaterial({ color: 0x0c1a2a, emissive: 0x18426a, emissiveIntensity: 1.5 }), -wx + 0.45, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));

	// --- Lighting
	const hemi = new THREE.HemisphereLight(0x5d7590, 0x0a0c10, 0.45); group.add(hemi);
	const key = new THREE.DirectionalLight(0xbfd4f0, 1.4);
	key.position.set(-6, 10, gateZ + 6); key.target.position.set(0, 0, gateZ + 6);
	key.castShadow = true; key.shadow.mapSize.set(2048, 2048);
	key.shadow.camera.left = -12; key.shadow.camera.right = 12; key.shadow.camera.top = 24; key.shadow.camera.bottom = -24;
	key.shadow.camera.near = 1; key.shadow.camera.far = 40; key.shadow.bias = -0.0005;
	group.add(key, key.target);
	const backFill = new THREE.PointLight(0x9fc4ff, 10, 24, 1.6);
	group.add(new THREE.AmbientLight(0x30404f, 0.35));
	for (const z of [gateZ + 5, gateZ + 13]) { const l = new THREE.PointLight(0xbfd8ff, 9, 22, 1.7); l.position.set(0, 8.5, z); group.add(l); } backFill.position.set(0, 7, zBack + 1.5); group.add(backFill);

	group.userData.reflector = reflector;
	return { group, colliders };
};
