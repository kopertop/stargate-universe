// Ancient-metal look shared by the gate room and ship interior. Reference: concept-art/materials/ancient-metal-pbr-sheet.png
// and gate-room/*.png — near-black blue-grey plates, fine engraved seams (thin double lines), nested inset rectangles,
// vertical vent-slot ribs, rivets, worn bevel highlights, cold blue-white light, sparse amber runway lights.
// Everything is procedural canvas textures (no runtime art assets): albedo + a matching roughness/bump canvas.
import * as THREE from 'three';

const rnd = (a, b) => a + Math.random() * (b - a);
const tex = (c, srgb = true) => { const t = new THREE.CanvasTexture(c); if (srgb) t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; return t; };
const canvas = (size) => { const c = document.createElement('canvas'); c.width = c.height = size; return [c, c.getContext('2d')]; };
/** Brushed grime pass: cool streaks + dark scuffs. */
const grime = (g, size, n = 1) => {
	for (let i = 0; i < 2600 * n; i++) { g.fillStyle = `rgba(${rnd(120, 200)},${rnd(140, 210)},${rnd(170, 235)},${rnd(0.02, 0.06)})`; g.fillRect(rnd(0, size), rnd(0, size), rnd(1, 3), rnd(6, 60)); }
	for (let i = 0; i < 1400 * n; i++) { g.fillStyle = `rgba(0,0,0,${rnd(0.05, 0.2)})`; g.fillRect(rnd(0, size), rnd(0, size), rnd(1, 4), rnd(2, 30)); }
	for (let i = 0; i < 40 * n; i++) { g.strokeStyle = `rgba(180,200,225,${rnd(0.03, 0.08)})`; g.lineWidth = 1; g.beginPath(); const x = rnd(0, size), y = rnd(0, size); g.moveTo(x, y); g.lineTo(x + rnd(-80, 80), y + rnd(-20, 20)); g.stroke(); } // scratches
};
/** Irregular plate split: each grid cell splits 0–2 times. Returns [x, y, w, h] boxes. */
const splitCells = (size, plates) => {
	const cells = [], cell = size / plates;
	for (let y = 0; y < plates; y++) for (let x = 0; x < plates; x++) {
		const cx = x * cell, cy = y * cell; const sx = Math.random() < 0.45 ? cx + cell * rnd(0.3, 0.7) : null, sy = Math.random() < 0.35 ? cy + cell * rnd(0.3, 0.7) : null;
		cells.push([cx, cy, sx ? sx - cx : cell, sy ? sy - cy : cell]);
		if (sx) cells.push([sx, cy, cx + cell - sx, sy ? sy - cy : cell]);
		if (sy) cells.push([cx, sy, sx ? sx - cx : cell, cy + cell - sy]);
		if (sx && sy) cells.push([sx, sy, cx + cell - sx, cy + cell - sy]);
	}
	return cells;
};
/** Vertical vent-slot rib (the ladder-like strips on the reference walls). */
const ventRib = (g, rg, x, y, w, h) => {
	g.fillStyle = 'rgba(0,0,0,0.55)'; g.fillRect(x, y, w, h); rg.fillStyle = '#e8e8e8'; rg.fillRect(x, y, w, h);
	const slot = Math.max(4, w * 0.5), gap = slot * 0.9; g.fillStyle = '#05070a';
	for (let sy = y + gap; sy + slot < y + h; sy += slot + gap) g.fillRect(x + w * 0.2, sy, w * 0.6, slot);
	g.strokeStyle = 'rgba(160,190,230,0.18)'; g.lineWidth = 1; g.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
};

/** Panel-plate texture: albedo + matching roughness/bump canvas. `size` px, `plates` per side. */
export const ancientPlates = ({ size = 1024, plates = 6, base = '#1b2028', seam = '#07090d', rivets = true, ribs = true } = {}) => {
	const [c, g] = canvas(size), [r, rg] = canvas(size);
	g.fillStyle = base; g.fillRect(0, 0, size, size); rg.fillStyle = '#8a8a8a'; rg.fillRect(0, 0, size, size);
	grime(g, size);
	const cell = size / plates;
	for (const [x, y, w, h] of splitCells(size, plates)) {
		g.fillStyle = `rgba(${rnd(14, 30)},${rnd(20, 40)},${rnd(30, 56)},${rnd(0.15, 0.4)})`; g.fillRect(x + 3, y + 3, w - 6, h - 6); // plate tint
		// engraved seam: thin dark groove with a lighter line beside it (the reference's fine double lines)
		g.strokeStyle = seam; g.lineWidth = 3; g.strokeRect(x + 1.5, y + 1.5, w - 3, h - 3);
		g.strokeStyle = 'rgba(150,180,220,0.16)'; g.lineWidth = 1; g.strokeRect(x + 4.5, y + 4.5, w - 9, h - 9);
		rg.fillStyle = `rgb(${rnd(110, 160)},${rnd(110, 160)},${rnd(110, 160)})`; rg.fillRect(x + 3, y + 3, w - 6, h - 6);
		rg.strokeStyle = '#f0f0f0'; rg.lineWidth = 3; rg.strokeRect(x + 1.5, y + 1.5, w - 3, h - 3);
		// nested insets: one or two smaller engraved rectangles, sometimes a tiny "chip" square
		if (w > cell * 0.45 && h > cell * 0.45) {
			const n = Math.random() < 0.6 ? 1 : 2;
			for (let k = 0; k < n; k++) { const iw = w * rnd(0.25, 0.55), ih = h * rnd(0.2, 0.5), ix = x + rnd(8, w - iw - 8), iy = y + rnd(8, h - ih - 8); g.strokeStyle = 'rgba(0,0,0,0.7)'; g.lineWidth = 2; g.strokeRect(ix, iy, iw, ih); g.strokeStyle = 'rgba(150,180,220,0.1)'; g.lineWidth = 1; g.strokeRect(ix + 2.5, iy + 2.5, iw - 5, ih - 5); }
			if (Math.random() < 0.3) { const s = rnd(8, 16); g.fillStyle = 'rgba(0,0,0,0.6)'; g.fillRect(x + w - s - 10, y + h - s - 10, s, s); }
		}
		if (ribs && h > cell * 0.7 && w > 40 && Math.random() < 0.18) ventRib(g, rg, x + rnd(8, w * 0.5), y + 10, Math.min(22, w * 0.25), h - 20);
		if (rivets && w > 40 && h > 40) { g.fillStyle = 'rgba(200,215,235,0.45)'; for (const [px, py] of [[x + 9, y + 9], [x + w - 9, y + 9], [x + 9, y + h - 9], [x + w - 9, y + h - 9]]) { g.beginPath(); g.arc(px, py, 2, 0, 7); g.fill(); } }
	}
	return { map: tex(c), rough: tex(r, false) };
};

/** Floor grating: panel grid, each panel carrying rows of dark slots, heavy rivets at panel corners (reference bottom-right). */
export const ancientGrating = ({ size = 1024, panels = 4, base = '#0d1116' } = {}) => {
	const [c, g] = canvas(size), [r, rg] = canvas(size);
	g.fillStyle = base; g.fillRect(0, 0, size, size); rg.fillStyle = '#9a9a9a'; rg.fillRect(0, 0, size, size);
	grime(g, size, 0.6);
	const p = size / panels;
	for (let y = 0; y < panels; y++) for (let x = 0; x < panels; x++) {
		const px = x * p, py = y * p, m = p * 0.06;
		g.fillStyle = `rgba(${rnd(20, 34)},${rnd(26, 42)},${rnd(34, 56)},0.5)`; g.fillRect(px + m, py + m, p - 2 * m, p - 2 * m);
		g.strokeStyle = '#05070a'; g.lineWidth = 5; g.strokeRect(px + m / 2, py + m / 2, p - m, p - m); // deep frame groove
		rg.strokeStyle = '#ffffff'; rg.lineWidth = 5; rg.strokeRect(px + m / 2, py + m / 2, p - m, p - m);
		g.strokeStyle = 'rgba(170,195,230,0.14)'; g.lineWidth = 1.5; g.strokeRect(px + m + 2, py + m + 2, p - 2 * m - 4, p - 2 * m - 4); // bevel
		const rows = Math.random() < 0.7 ? 5 : 0, slotH = (p - 2 * m) / (rows * 2 + 1); // some panels are solid tread plates
		for (let i = 0; i < rows; i++) { const sy = py + m + slotH * (2 * i + 1); g.fillStyle = '#03040a'; g.fillRect(px + m * 2.2, sy, p - 4.4 * m, slotH * 0.85); rg.fillStyle = '#f4f4f4'; rg.fillRect(px + m * 2.2, sy, p - 4.4 * m, slotH * 0.85); }
		g.fillStyle = 'rgba(190,205,225,0.6)'; for (const [rx, ry] of [[px + m * 1.3, py + m * 1.3], [px + p - m * 1.3, py + m * 1.3], [px + m * 1.3, py + p - m * 1.3], [px + p - m * 1.3, py + p - m * 1.3]]) { g.beginPath(); g.arc(rx, ry, 4, 0, 7); g.fill(); }
	}
	return { map: tex(c), rough: tex(r, false) };
};

/** Standard Ancient-metal material. `repeat` tiles the plates per world-unit scale of the surface. */
export const ancientMaterial = ({ repeat = [1, 1], base, plates, roughness = 0.6, metalness = 0.5, tint = 0xffffff, ribs } = {}) => {
	const { map, rough } = ancientPlates({ base, plates, ribs });
	map.repeat.set(...repeat); rough.repeat.set(...repeat);
	return new THREE.MeshStandardMaterial({ map, roughnessMap: rough, bumpMap: rough, bumpScale: 0.025, roughness, metalness, color: tint });
};

/** Floor: slotted grating panels, darker and wetter (reflection lives in the Reflector under the gate hall). */
export const ancientFloorMaterial = (repeat = [4, 8]) => {
	const { map, rough } = ancientGrating({});
	map.repeat.set(...repeat); rough.repeat.set(...repeat);
	return new THREE.MeshStandardMaterial({ map, roughnessMap: rough, bumpMap: rough, bumpScale: 0.04, roughness: 0.5, metalness: 0.45 });
};

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
