// Ancient-metal look shared by the gate room and ship interior. Reference: concept-art/materials/ancient-metal-pbr-sheet.png
// and gate-room/*.png — near-black blue-grey plates, recessed seams, rivets, worn bevel highlights, cold blue-white light,
// sparse amber runway lights. Everything is procedural canvas textures (no runtime art assets).
import * as THREE from 'three';

const rnd = (a, b) => a + Math.random() * (b - a);

/** Panel-plate texture: albedo + a matching bump/roughness canvas. `size` px, `plates` per side. */
export const ancientPlates = ({ size = 1024, plates = 6, base = '#1b2028', seam = '#07090d', rivets = true, seedShift = 0 } = {}) => {
	const c = document.createElement('canvas'); c.width = c.height = size; const g = c.getContext('2d');
	const r = document.createElement('canvas'); r.width = r.height = size; const rg = r.getContext('2d');
	g.fillStyle = base; g.fillRect(0, 0, size, size);
	const dark = base.toLowerCase() < '#101418';
	rg.fillStyle = '#8a8a8a'; rg.fillRect(0, 0, size, size); // mid roughness
	// grime / brushed variation
	for (let i = 0; i < 2600; i++) { g.fillStyle = `rgba(${rnd(120, 200)},${rnd(140, 210)},${rnd(170, 235)},${rnd(0.02, 0.07)})`; g.fillRect(rnd(0, size), rnd(0, size), rnd(1, 3), rnd(6, 60)); }
	for (let i = 0; i < 1400; i++) { g.fillStyle = `rgba(0,0,0,${rnd(0.05, 0.2)})`; g.fillRect(rnd(0, size), rnd(0, size), rnd(1, 4), rnd(2, 30)); }
	// irregular plate grid: split each cell 0–2 times
	const cells = [];
	const cell = size / plates;
	for (let y = 0; y < plates; y++) for (let x = 0; x < plates; x++) {
		const cx = x * cell, cy = y * cell; const splitV = Math.random() < 0.45, splitH = Math.random() < 0.35;
		const sx = splitV ? cx + cell * rnd(0.3, 0.7) : null, sy = splitH ? cy + cell * rnd(0.3, 0.7) : null;
		const boxes = [[cx, cy, sx ? sx - cx : cell, sy ? sy - cy : cell]];
		if (sx) boxes.push([sx, cy, cx + cell - sx, sy ? sy - cy : cell]);
		if (sy) boxes.push([cx, sy, sx ? sx - cx : cell, cy + cell - sy]);
		if (sx && sy) boxes.push([sx, sy, cx + cell - sx, cy + cell - sy]);
		cells.push(...boxes);
	}
	for (const [x, y, w, h] of cells) {
		// plate tint variation
		g.fillStyle = `rgba(${rnd(14, 30)},${rnd(20, 40)},${rnd(30, 56)},${rnd(0.15, 0.4)})`; g.fillRect(x + 3, y + 3, w - 6, h - 6);
		// recessed seam (dark) + bevel highlight on top/left edges
		g.strokeStyle = seam; g.lineWidth = 5; g.strokeRect(x + 2.5, y + 2.5, w - 5, h - 5);
		g.strokeStyle = 'rgba(160,190,230,0.14)'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(x + 6, y + h - 6); g.lineTo(x + 6, y + 6); g.lineTo(x + w - 6, y + 6); g.stroke();
		rg.fillStyle = `rgb(${rnd(110, 160)},${rnd(110, 160)},${rnd(110, 160)})`; rg.fillRect(x + 3, y + 3, w - 6, h - 6);
		rg.strokeStyle = '#f0f0f0'; rg.lineWidth = 5; rg.strokeRect(x + 2.5, y + 2.5, w - 5, h - 5); // seams rough
		// inner detail: a smaller inset panel or a conduit strip
		if (w > cell * 0.5 && Math.random() < 0.5) { const ix = x + w * rnd(0.15, 0.3), iy = y + h * rnd(0.15, 0.3), iw = w * rnd(0.3, 0.5), ih = h * rnd(0.3, 0.5); g.strokeStyle = 'rgba(0,0,0,0.6)'; g.lineWidth = 2; g.strokeRect(ix, iy, iw, ih); }
		if (rivets && w > 40 && h > 40) { g.fillStyle = 'rgba(200,215,235,0.5)'; for (const [px, py] of [[x + 10, y + 10], [x + w - 10, y + 10], [x + 10, y + h - 10], [x + w - 10, y + h - 10]]) { g.beginPath(); g.arc(px, py, 2.2, 0, 7); g.fill(); } }
	}
	const map = new THREE.CanvasTexture(c); map.colorSpace = THREE.SRGBColorSpace; map.wrapS = map.wrapT = THREE.RepeatWrapping; map.anisotropy = 8;
	const rough = new THREE.CanvasTexture(r); rough.wrapS = rough.wrapT = THREE.RepeatWrapping;
	return { map, rough };
};

/** Standard Ancient-metal material. `repeat` tiles the plates per world-unit scale of the surface. */
export const ancientMaterial = ({ repeat = [1, 1], base, plates, roughness = 0.6, metalness = 0.5, tint = 0xffffff } = {}) => {
	const { map, rough } = ancientPlates({ base, plates });
	map.repeat.set(...repeat); rough.repeat.set(...repeat);
	return new THREE.MeshStandardMaterial({ map, roughnessMap: rough, bumpMap: rough, bumpScale: 0.02, roughness, metalness, color: tint });
};

/** Floor grating/plates: darker, wetter (reflection lives in the Reflector under it). */
export const ancientFloorMaterial = (repeat = [4, 8]) => ancientMaterial({ repeat, base: '#070a0d', plates: 5, roughness: 0.45, metalness: 0.3 });

/** Amber runway light: small emissive slab + shared warm point light every few metres. */
export const runwayLights = (group, { from, to, count = 8, offset = 0, color = 0xffa040, y = 0.05, light = true }) => {
	const mat = new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 2.2 });
	const geo = new THREE.BoxGeometry(0.18, 0.04, 0.5);
	const a = new THREE.Vector3(...from), b = new THREE.Vector3(...to), dir = b.clone().sub(a);
	const len = dir.length(); dir.normalize(); const side = new THREE.Vector3(-dir.z, 0, dir.x);
	for (let i = 0; i < count; i++) {
		const t = (i + 0.5) / count; const p = a.clone().addScaledVector(dir, len * t).addScaledVector(side, offset); p.y = y;
		const m = new THREE.Mesh(geo, mat); m.position.copy(p); m.rotation.y = Math.atan2(dir.x, dir.z); group.add(m);
		if (light && i % 2 === 0) { const l = new THREE.PointLight(color, 1.6, 4, 2); l.position.copy(p).add(new THREE.Vector3(0, 0.3, 0)); group.add(l); }
	}
};

/** Octagonal door frame (chamfered corners) around a rectangular opening, Destiny-style. */
export const octagonFrame = (group, { w, h, depth = 0.3, thick = 0.28, mat, position, rotationY = 0 }) => {
	const frame = new THREE.Group(); frame.position.copy(position); frame.rotation.y = rotationY;
	const ch = Math.min(w, h) * 0.22; // chamfer
	const seg = (len, x, y, rz) => { const m = new THREE.Mesh(new THREE.BoxGeometry(len, thick, depth), mat); m.position.set(x, y, 0); m.rotation.z = rz; m.castShadow = m.receiveShadow = true; frame.add(m); };
	seg(w - 2 * ch + thick, 0, h + thick / 2, 0); // top
	seg(h - 2 * ch + thick, -w / 2 - thick / 2, h / 2, Math.PI / 2); seg(h - 2 * ch + thick, w / 2 + thick / 2, h / 2, Math.PI / 2); // sides
	const d = Math.SQRT2 * ch;
	seg(d, -w / 2 + ch / 2 - thick / 3, h - ch / 2 + thick / 3, -Math.PI / 4); seg(d, w / 2 - ch / 2 + thick / 3, h - ch / 2 + thick / 3, Math.PI / 4);
	seg(d, -w / 2 + ch / 2 - thick / 3, ch / 2 - thick / 3, Math.PI / 4); seg(d, w / 2 - ch / 2 + thick / 3, ch / 2 - thick / 3, -Math.PI / 4);
	group.add(frame); return frame;
};

/** Vertical wall light slit (cold white-blue by default). */
export const wallSlit = (group, { x, y, z, h = 1.6, rotationY = 0, color = 0xcfe6ff, intensity = 2.5 }) => {
	const m = new THREE.Mesh(new THREE.BoxGeometry(0.08, h, 0.06), new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: intensity }));
	m.position.set(x, y, z); m.rotation.y = rotationY; group.add(m); return m;
};
