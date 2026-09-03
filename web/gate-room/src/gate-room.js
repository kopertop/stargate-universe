// Procedural Destiny gate room — code-only, primitives + canvas textures. Returns { group, colliders }.
// Colliders are world-space AABBs ({min,max} THREE.Box3) consumed by player.js.
// Layout (metres, +Z toward the camera/spawn, gate at z=0 facing +Z):
//   hall 14 wide × 30 long, 11 high. Gate stands at z=-11 on a raised dais.
import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';

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

	const wallMat = new THREE.MeshStandardMaterial({ map: wallTexture(), roughness: 0.85, metalness: 0.05 });
	wallMat.map.repeat.set(6, 1);
	const stoneMat = new THREE.MeshStandardMaterial({ color: 0x5e5a4e, roughness: 0.9 });
	const darkMat = new THREE.MeshStandardMaterial({ color: 0x1f2026, roughness: 0.6, metalness: 0.5 });
	const ceilMat = new THREE.MeshStandardMaterial({ color: 0x22251f, roughness: 0.95 });
	const cyan = new THREE.MeshStandardMaterial({ color: 0x5ff5ff, emissive: 0x2fd8ff, emissiveIntensity: 2.4 });
	const amberScreen = new THREE.MeshStandardMaterial({ color: 0xfff1cf, emissive: 0xffe0a0, emissiveIntensity: 2.0 });

	// --- Floor: reflector + tinted wood overlay (polished look from the reference)
	const reflector = new Reflector(new THREE.PlaneGeometry(width, length), {
		clipBias: 0.003, textureWidth: Math.floor(innerWidth * 0.5), textureHeight: Math.floor(innerHeight * 0.5), color: 0x3e3e3e,
	});
	reflector.rotation.x = -Math.PI / 2; reflector.position.set(0, -0.002, zMid); group.add(reflector);
	const floorMat = new THREE.MeshStandardMaterial({ map: floorTexture(), roughness: 0.35, metalness: 0.1, transparent: true, opacity: 0.9 });
	const floor = new THREE.Mesh(new THREE.PlaneGeometry(width, length), floorMat);
	floor.rotation.x = -Math.PI / 2; floor.position.set(0, 0, zMid); floor.receiveShadow = true; group.add(floor);

	// --- Dais under gate
	group.add(box(8, daisH, 3.2, new THREE.MeshStandardMaterial({ color: 0x3b2e28, roughness: 0.6, metalness: 0.2 }), 0, daisH / 2, gateZ + 0.6, null, { noCollide: true }));

	// --- Walls / ceiling
	group.add(box(0.4, height, length, wallMat, -width / 2 - 0.2, height / 2, zMid, colliders));
	group.add(box(0.4, height, length, wallMat, width / 2 + 0.2, height / 2, zMid, colliders));
	group.add(box(width + 1, height, 0.4, wallMat, 0, height / 2, zBack - 0.2, colliders));
	group.add(box(width + 1, height, 0.4, wallMat, 0, height / 2, zFront + 0.2, colliders));
	const ceiling = box(width + 1, 0.4, length, ceilMat, 0, height + 0.2, zMid, null, { noCollide: true, shadow: false });
	group.add(ceiling); group.userData.ceiling = ceiling;

	// --- Back wall windows (lattice, warm glow) flanking the gate
	const lattice = latticeTexture(6, 7);
	const winMat = new THREE.MeshStandardMaterial({ map: lattice, emissive: 0xffffff, emissiveMap: lattice, emissiveIntensity: 0.55, roughness: 1 });
	for (const sx of [-1, 1]) {
		const w = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 7.5), winMat);
		w.position.set(sx * 4.9, 5.2, zBack + 0.03); group.add(w);
			}
	// side-wall high windows
	for (const sx of [-1, 1]) for (const z of [gateZ + 4, gateZ + 12]) {
		const w = new THREE.Mesh(new THREE.PlaneGeometry(4.5, 3.4), winMat);
		w.position.set(sx * (width / 2 - 0.03), 7.6, z); w.rotation.y = -sx * Math.PI / 2; group.add(w);
	}

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
		const glow = new THREE.PointLight(0xffe2a8, 8, 6, 2); glow.position.set(x, 1.6, z); group.add(glow);
	}

	// --- Upper-left monitor alcove (from the reference's top-left)
	group.add(box(2.2, 1.6, 0.2, darkMat, -width / 2 + 0.6, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));
	group.add(box(1.9, 1.3, 0.05, new THREE.MeshStandardMaterial({ color: 0x0c1a2a, emissive: 0x18426a, emissiveIntensity: 1.5 }), -width / 2 + 0.75, 8.6, gateZ + 15, null, { noCollide: true, shadow: false }));

	// --- Lighting
	const hemi = new THREE.HemisphereLight(0x9fc3dd, 0x5a3a26, 1.1); group.add(hemi);
	const key = new THREE.DirectionalLight(0xfff0d8, 3.2);
	key.position.set(-6, 10, gateZ + 6); key.target.position.set(0, 0, gateZ + 6);
	key.castShadow = true; key.shadow.mapSize.set(2048, 2048);
	key.shadow.camera.left = -12; key.shadow.camera.right = 12; key.shadow.camera.top = 16; key.shadow.camera.bottom = -16;
	key.shadow.camera.near = 1; key.shadow.camera.far = 40; key.shadow.bias = -0.0005;
	group.add(key, key.target);
	const backFill = new THREE.PointLight(0xffd9a0, 60, 24, 1.6);
	group.add(new THREE.AmbientLight(0x6a7480, 0.45));
	for (const sx of [-1, 1]) for (const z of [gateZ + 5, gateZ + 13]) { const l = new THREE.PointLight(0xffe6c0, 32, 20, 1.7); l.position.set(sx * 5.5, 8.5, z); group.add(l); } backFill.position.set(0, 7, zBack + 1.5); group.add(backFill);

	group.userData.reflector = reflector;
	return { group, colliders };
};
