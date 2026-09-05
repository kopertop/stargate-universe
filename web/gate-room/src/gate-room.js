// Procedural Destiny gate room — code-only, primitives + canvas textures. Returns { group, colliders }.
// Colliders are world-space AABBs ({min,max} THREE.Box3) consumed by player.js.
// Layout (metres, +Z toward the camera/spawn, gate at z=0 facing +Z):
//   hall 14 wide × 30 long, 11 high. Gate stands at z=-11 on a raised dais.
import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { ancientMaterial, ancientFloorMaterial, runwayLights, octagonFrame, wallSlit } from './ancient.js';

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

// Canvas texture: window lattice (warm amber panes behind dark mullions)
const latticeTexture = (cols, rows) => {
	const c = document.createElement('canvas'); c.width = 512; c.height = 512;
	const ctx = c.getContext('2d');
	const grd = ctx.createRadialGradient(256, 256, 40, 256, 256, 380);
	grd.addColorStop(0, '#f7e3b5'); grd.addColorStop(1, '#c9a86a');
	ctx.fillStyle = grd; ctx.fillRect(0, 0, 512, 512);
	ctx.fillStyle = '#1b1a17';
	const cw = 512 / cols, rh = 512 / rows;
	for (let i = 0; i <= cols; i++) ctx.fillRect(i * cw - 5, 0, 10, 512);
	for (let j = 0; j <= rows; j++) ctx.fillRect(0, j * rh - 5, 512, 10);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
};

// Canvas texture: floor inlay — dark polished wood with concentric arc seams around the gate
const floorTexture = () => {
	const c = document.createElement('canvas'); c.width = 1024; c.height = 2048;
	const ctx = c.getContext('2d');
	ctx.fillStyle = '#5a2b1c'; ctx.fillRect(0, 0, 1024, 2048);
	// grain streaks
	for (let i = 0; i < 350; i++) {
		ctx.fillStyle = `rgba(${90 + Math.random() * 40},${40 + Math.random() * 20},${25 + Math.random() * 15},${0.08 + Math.random() * 0.12})`;
		ctx.fillRect(Math.random() * 1024, Math.random() * 2048, 2 + Math.random() * 6, 40 + Math.random() * 260);
	}
	ctx.strokeStyle = '#1c0d08'; ctx.lineWidth = 7;
	// arcs centred on gate (top of texture = gate end)
	for (const r of [260, 420, 600, 800, 1050]) { ctx.beginPath(); ctx.arc(512, 60, r, 0, Math.PI); ctx.stroke(); }
	// radial seams
	for (let k = -3; k <= 3; k++) { ctx.beginPath(); ctx.moveTo(512, 60); ctx.lineTo(512 + k * 300, 2048); ctx.stroke(); }
	// centre runway edges
	ctx.lineWidth = 10; ctx.beginPath(); ctx.moveTo(300, 2048); ctx.lineTo(300, 400); ctx.moveTo(724, 2048); ctx.lineTo(724, 400); ctx.stroke();
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t;
};

const wallTexture = () => {
	const c = document.createElement('canvas'); c.width = 256; c.height = 1024;
	const ctx = c.getContext('2d');
	ctx.fillStyle = '#4b5433'; ctx.fillRect(0, 0, 256, 1024);
	for (let i = 0; i < 400; i++) { ctx.fillStyle = `rgba(0,0,0,${Math.random() * 0.12})`; ctx.fillRect(Math.random() * 256, Math.random() * 1024, 3, 3 + Math.random() * 30); }
	ctx.fillStyle = '#d8cf9c'; ctx.fillRect(28, 0, 10, 1024); ctx.fillRect(218, 0, 10, 1024); // beige trim strips
	ctx.fillStyle = '#2e3324'; ctx.fillRect(0, 0, 8, 1024); ctx.fillRect(248, 0, 8, 1024);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; return t;
};

export const ROOM = { width: 14, length: 30, height: 11, gateZ: -11, daisH: 0.18 };

export const createGateRoom = (renderer) => {
	const group = new THREE.Group(); group.name = 'gateRoom';
	const colliders = [];
	const { width, length, height, gateZ, daisH } = ROOM;
	const zMid = gateZ + 4; // hall centre
	const zBack = gateZ - 5, zFront = gateZ + length - 5;

	const wallMat = ancientMaterial({ repeat: [4, 1.6], base: '#171c24', plates: 6 }); // Ancient plates (concept: materials sheet)
	const stoneMat = ancientMaterial({ repeat: [1, 3], base: '#1f242c', plates: 3, roughness: 0.6 });
	const darkMat = ancientMaterial({ repeat: [1, 1], base: '#0f1319', plates: 3, roughness: 0.5, metalness: 0.8 });
	const ceilMat = ancientMaterial({ repeat: [3, 6], base: '#0c0f14', plates: 5, roughness: 0.7 });
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

	// --- Walls / ceiling
	group.add(box(0.4, height, length, wallMat, -width / 2 - 0.2, height / 2, zMid, colliders));
	group.add(box(0.4, height, length, wallMat, width / 2 + 0.2, height / 2, zMid, colliders));
	group.add(box(width + 1, height, 0.4, wallMat, 0, height / 2, zBack - 0.2, colliders));
	// front wall with a door gap (door itself lives in ship.js)
	const DW = 2.4, DH = 3.2, sideW = (width + 1 - DW) / 2;
	group.add(box(sideW, height, 0.4, wallMat, -(DW / 2 + sideW / 2), height / 2, zFront + 0.2, colliders));
	group.add(box(sideW, height, 0.4, wallMat, DW / 2 + sideW / 2, height / 2, zFront + 0.2, colliders));
	group.add(box(DW, height - DH, 0.4, wallMat, 0, DH + (height - DH) / 2, zFront + 0.2, colliders));
	octagonFrame(group, { w: DW + 0.2, h: DH + 0.1, mat: darkMat, position: new THREE.Vector3(0, 0, zFront - 0.15) });
	const ceiling = box(width + 1, 0.4, length, ceilMat, 0, height + 0.2, zMid, null, { noCollide: true, shadow: false });
	group.add(ceiling); group.userData.ceiling = ceiling;

	// --- Back wall windows (lattice, warm glow) flanking the gate
	// tall vertical light slits in the back wall and along the side walls (concept: gate-room-active)
	for (const sx of [-1, 1]) for (const dx of [3.6, 4.6, 5.6]) wallSlit(group, { x: sx * dx, y: 5.6, z: zBack + 0.06, h: 4.2, intensity: 1.8 });
	for (const sx of [-1, 1]) for (let i = 0; i < 5; i++) { const z = gateZ + 2 + i * 5; wallSlit(group, { x: sx * (width / 2 - 0.05), y: 6.2, z, h: 2.6, rotationY: Math.PI / 2, intensity: 1.6 }); wallSlit(group, { x: sx * (width / 2 - 0.05), y: 2.2, z, h: 1.2, rotationY: Math.PI / 2, color: 0xffb060, intensity: 1.2 }); }
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
	for (const sx of [-1, 1]) for (let i = 0; i < 4; i++) {
		const z = gateZ + 6 + i * 5.5;
		group.add(box(0.9, height, 0.9, darkMat, sx * (width / 2 - 0.45), height / 2, z, colliders));
		for (let k = 0; k < 9; k++) group.add(box(0.06, 0.5, 0.06, cyan, sx * (width / 2 - 0.92), 1.5 + k * 1.05, z, null, { noCollide: true, shadow: false }));
		// horizontal segmented wall panel
		const py = 6.2;
		group.add(box(0.25, 0.55, 2.6, darkMat, sx * (width / 2 - 0.15), py, z + 2.7, null, { noCollide: true, shadow: false }));
		for (let s = 0; s < 4; s++) group.add(box(0.1, 0.22, 0.45, cyan, sx * (width / 2 - 0.3), py, z + 1.85 + s * 0.57, null, { noCollide: true, shadow: false }));
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
	group.add(box(2.2, 1.6, 0.2, darkMat, -width / 2 + 0.6, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));
	group.add(box(1.9, 1.3, 0.05, new THREE.MeshStandardMaterial({ color: 0x0c1a2a, emissive: 0x18426a, emissiveIntensity: 1.5 }), -width / 2 + 0.75, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));

	// --- Lighting
	const hemi = new THREE.HemisphereLight(0x5d7590, 0x0a0c10, 0.45); group.add(hemi);
	const key = new THREE.DirectionalLight(0xbfd4f0, 1.4);
	key.position.set(-6, 10, gateZ + 6); key.target.position.set(0, 0, gateZ + 6);
	key.castShadow = true; key.shadow.mapSize.set(2048, 2048);
	key.shadow.camera.left = -12; key.shadow.camera.right = 12; key.shadow.camera.top = 16; key.shadow.camera.bottom = -16;
	key.shadow.camera.near = 1; key.shadow.camera.far = 40; key.shadow.bias = -0.0005;
	group.add(key, key.target);
	const backFill = new THREE.PointLight(0x9fc4ff, 10, 24, 1.6);
	group.add(new THREE.AmbientLight(0x30404f, 0.35));
	for (const z of [gateZ + 5, gateZ + 13]) { const l = new THREE.PointLight(0xbfd8ff, 9, 22, 1.7); l.position.set(0, 8.5, z); group.add(l); } backFill.position.set(0, 7, zBack + 1.5); group.add(backFill);

	group.userData.reflector = reflector;
	return { group, colliders };
};
