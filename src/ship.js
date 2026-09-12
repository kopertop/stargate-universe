// Destiny deck 0, generated from the repo's canonical layout (data/ship_layout.json + data/room_connections.json — the same
// data the Godot build uses). JSON plan units → metres at 0.05 (gate room 800×400 → 40×20 m). JSON X runs along the ship;
// we map X → -Z so the gate sits at the far (-Z) end of the gate room and the East Connector leaves toward +Z. JSON Y → X.
// Rooms are AABB shells with door gaps cut where two rooms share an edge; doors slide open when powered + unlocked + near.
import * as THREE from 'three';
import { ancientMaterial, ancientFloorMaterial } from './ancient.js';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from './components.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export const DOOR_W = 2.4, DOOR_H = 3.2, WALL_T = 0.3, DECK_H = 12; // decks stack DECK_H apart (gate hall is 11 m tall)
const R = DOOR_W / 2, ARCH_Y = DOOR_H - R, BULGE = 0.1, HUB_R = 0.42, GEAR_R = 0.2; // arched opening: straight to ARCH_Y, semicircle to DOOR_H
const SCALE = 0.05, H_ROOM = 4.6, LIGHT_RANGE = 22, MAX_LIVE = 6;
const ROOM_H = { gate_room: 11, control_room: 6.5, hydroponics: 6, 'shuttle-dock': 6 };

/** JSON rooms (every floor) → world rects; `y0` is the deck's floor height. */
export const roomsFromLayout = (layout) => layout.map((r) => ({
	id: r.id, name: r.name, type: r.type, key: !!r.key_room, props: r.props, floor: r.floor ?? 0, y0: (r.floor ?? 0) * DECK_H,
	x0: r.startY * SCALE, x1: r.endY * SCALE, z0: -r.endX * SCALE, z1: -r.startX * SCALE,
}));
const center = (r) => ({ x: (r.x0 + r.x1) / 2, z: (r.z0 + r.z1) / 2, w: r.x1 - r.x0, d: r.z1 - r.z0 });
/** Shared wall between two rects (long enough for a door), or null. axis 'x' = wall of constant x. */
const sharedEdge = (a, b) => {
	const eps = 0.01;
	for (const [at, ok] of [[a.x1, Math.abs(a.x1 - b.x0) < eps], [a.x0, Math.abs(a.x0 - b.x1) < eps]]) if (ok) { const lo = Math.max(a.z0, b.z0), hi = Math.min(a.z1, b.z1); if (hi - lo >= DOOR_W + 0.4) return { axis: 'x', at, lo, hi }; }
	for (const [at, ok] of [[a.z1, Math.abs(a.z1 - b.z0) < eps], [a.z0, Math.abs(a.z0 - b.z1) < eps]]) if (ok) { const lo = Math.max(a.x0, b.x0), hi = Math.min(a.x1, b.x1); if (hi - lo >= DOOR_W + 0.4) return { axis: 'z', at, lo, hi }; }
	return null;
};
/** Doors: one per declared connection (same floor), plus every shared edge of rooms the JSON leaves unconnected (the ring corridors). */
export const doorsFromLayout = (rooms, connections) => {
	const byId = Object.fromEntries(rooms.map((r) => [r.id, r])), doors = [], seen = new Set();
	const add = (a, b, plaque) => {
		if (a.floor !== b.floor) return; const key = [a.id, b.id].sort().join('|'); if (seen.has(key)) return; const e = sharedEdge(a, b); if (!e) return; seen.add(key);
		doors.push({ id: key, axis: e.axis, at: e.at, center: (e.lo + e.hi) / 2, rooms: [a.id, b.id], plaque: { [a.id]: plaque ?? b.name, [b.id]: a.name }, jammed: b.type === 'shuttle-dock' && b.id.startsWith('breached'), sealed: b.id.startsWith('sealed') });
	};
	const linked = new Set();
	for (const [from, list] of Object.entries(connections)) for (const c of list) { if (c.dir === 'elevator' || !byId[from] || !byId[c.to]) continue; linked.add(from); linked.add(c.to); add(byId[from], byId[c.to], c.plaque); }
	for (const r of rooms) if (!linked.has(r.id)) for (const o of rooms) if (o !== r) add(r, o, o.name);
	return doors;
};
/** Elevator links between decks (routing edges, not doors): [{ rooms: [from, to], elevator: true }]. */
export const elevatorsFromLayout = (rooms, connections) => {
	const byId = Object.fromEntries(rooms.map((r) => [r.id, r]));
	return Object.entries(connections).flatMap(([from, list]) => list.filter((c) => c.dir === 'elevator' && byId[from] && byId[c.to]).map((c) => ({ id: `${from}|${c.to}`, rooms: [from, c.to], elevator: true })));
};

const textPlaque = (text, { w = 512, h = 112, color = '#d4a852' } = {}) => {
	const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d');
	g.fillStyle = '#0a0d12'; g.fillRect(0, 0, w, h); g.strokeStyle = 'rgba(212,168,82,0.6)'; g.lineWidth = 4; g.strokeRect(6, 6, w - 12, h - 12);
	g.fillStyle = color; g.font = '600 46px "Trebuchet MS", sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(text.toUpperCase(), w / 2, h / 2 + 2, w - 40);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
};

/**
 * Build the deck. `gateZ` is where the gate stands (gate-room.js draws the gate hall's interior; we draw its walls/ceiling
 * like every other room so its doors come from the same data). Returns { group, rooms, doors, anchors, ceilings, … }.
 */
export const createShip = (scene, colliders, { layout, connections, gateZ }) => {
	const group = new THREE.Group(); group.name = 'shipInterior'; scene.add(group);
	const rooms = roomsFromLayout(layout), doors = doorsFromLayout(rooms, connections), elevators = elevatorsFromLayout(rooms, connections), byId = Object.fromEntries(rooms.map((r) => [r.id, r]));
	// one group per deck, offset by y0: everything is built in deck-local coordinates (floor at y = 0) and colliders/anchors read world space
	const decks = {}; for (const r of rooms) if (!decks[r.floor]) { const fg = new THREE.Group(); fg.name = `deck${r.floor}`; fg.position.y = r.y0; group.add(fg); fg.updateMatrixWorld(true); decks[r.floor] = fg; }
	let cur = group; // the deck group new meshes go into
	const anchors = {}, lights = [], occludable = [], ceilings = new THREE.Group(); group.add(ceilings);
	const wallMat = ancientMaterial({ repeat: [2, 1.2], base: '#151a21', plates: 5 });
	const tallWallMat = ancientMaterial({ repeat: [4, 1.6], base: '#171c24', plates: 6 });
	const floorMat = ancientFloorMaterial([2, 3]);
	const ceilMat = ancientMaterial({ repeat: [2, 3], base: '#0b0e13', plates: 4, roughness: 0.75 });
	const darkMat = ancientMaterial({ repeat: [1, 1], base: '#0f1319', plates: 3, roughness: 0.5, metalness: 0.8 });
	const doorMat = ancientMaterial({ repeat: [1, 2], base: '#1a2028', plates: 2, roughness: 0.4, metalness: 0.85 });
	const strip = new THREE.MeshStandardMaterial({ color: 0xcfe6ff, emissive: 0xa8ccff, emissiveIntensity: 0 }); // cold ceiling strips (on = powered)
	const edge = new THREE.MeshStandardMaterial({ color: 0xffa040, emissive: 0xffa040, emissiveIntensity: 0 }); // amber corridor edge lines
	const redMat = new THREE.MeshStandardMaterial({ color: 0xff3020, emissive: 0xff2010, emissiveIntensity: 2 });
	const box = (w, h, d, mat, x, y, z, solid = true, ry = 0, mergeKey = null) => {
		const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); m.rotation.y = ry; m.castShadow = m.receiveShadow = true; cur.add(m);
		if (solid) { m.updateMatrixWorld(); colliders.push(new THREE.Box3().setFromObject(m)); if (!mergeKey) occludable.push(m); }
		if (mergeKey) (staticParts.get(mergeKey) ?? staticParts.set(mergeKey, []).get(mergeKey)).push(m);
		return m;
	};
	// static wall pieces are merged per room + material after the build (one draw call instead of dozens); colliders stay per piece
	const staticParts = new Map();
	const mergeStatic = () => {
		for (const [key, parts] of staticParts) {
			const mat = parts[0].material, geo = mergeGeometries(parts.map((m) => { m.updateMatrixWorld(); return (m.geometry.index ? m.geometry.toNonIndexed() : m.geometry.clone()).applyMatrix4(m.matrixWorld); })); // boxes are indexed, extruded arches are not
			for (const m of parts) { m.removeFromParent(); m.geometry.dispose(); }
			const merged = new THREE.Mesh(geo, mat); merged.castShadow = merged.receiveShadow = true; merged.userData.roomKey = key; group.add(merged); occludable.push(merged);
		}
		staticParts.clear();
	};
	const roomH = (r) => ROOM_H[r.type] ?? H_ROOM;
	const doorsOnWall = (axis, at, lo, hi) => doors.filter((d) => d.axis === axis && Math.abs(d.at - at) < 1e-3 && d.center > lo && d.center < hi);
	// wall along a boundary with door gaps; inset by WALL_T/2 into the room (dir = ±1)
	const wall = (axis, at, lo, hi, dir, H, mat, key) => {
		const gaps = doorsOnWall(axis, at, lo, hi).map((d) => [d.center - DOOR_W / 2, d.center + DOOR_W / 2]).sort((a, b) => a[0] - b[0]);
		const segs = []; let cur = lo; for (const [g0, g1] of gaps) { if (g0 > cur) segs.push([cur, g0]); cur = g1; } if (cur < hi) segs.push([cur, hi]);
		const c = at + dir * WALL_T / 2;
		for (const [a, b] of segs) axis === 'x' ? box(WALL_T, H, b - a, mat, c, H / 2, (a + b) / 2, true, 0, key) : box(b - a, H, WALL_T, mat, (a + b) / 2, H / 2, c, true, 0, key);
		for (const [g0, g1] of gaps) archLintel(axis, c, (g0 + g1) / 2, H, mat, key);
	};
	// wall infill above a doorway with the arch cut out of it (the opening matches the door leaves' shape)
	const archLintel = (axis, c, mid, H, mat, key) => {
		const sh = new THREE.Shape(); sh.moveTo(-R, ARCH_Y); sh.lineTo(-R, H); sh.lineTo(R, H); sh.lineTo(R, ARCH_Y); sh.absarc(0, ARCH_Y, R, 0, Math.PI, false); // straight sides + arch hole
		const geo = new THREE.ExtrudeGeometry(sh, { depth: WALL_T, bevelEnabled: false }); geo.translate(0, 0, -WALL_T / 2);
		const m = new THREE.Mesh(geo, mat); m.castShadow = m.receiveShadow = true;
		if (axis === 'x') { m.position.set(c, 0, mid); m.rotation.y = Math.PI / 2; } else m.position.set(mid, 0, c);
		cur.add(m); (staticParts.get(key) ?? staticParts.set(key, []).get(key)).push(m);
	};
	for (const r of rooms) {
		cur = decks[r.floor];
		const { x: cx, z: cz, w, d } = center(r), H = roomH(r), gate = r.type === 'gate_room';
		const floor = box(w, 0.1, d, floorMat, cx, -0.05, cz, false); floor.receiveShadow = true; floor.userData.roomId = r.id; if (gate) floor.visible = false; // gate hall floor is gate-room.js's reflector; keep an invisible pick target
		const ceil = box(w, 0.1, d, ceilMat, cx, H + 0.05, cz, false); ceil.removeFromParent(); ceil.position.y += r.y0; ceilings.add(ceil);
		const mat = gate ? tallWallMat : wallMat;
		const key = `${r.id}|walls`; wall('x', r.x0, r.z0, r.z1, +1, H, mat, key); wall('x', r.x1, r.z0, r.z1, -1, H, mat, key); wall('z', r.z0, r.x0, r.x1, +1, H, mat, key); wall('z', r.z1, r.x0, r.x1, -1, H, mat, key);
		anchors[`${r.id}:RoomCenter`] = new THREE.Vector3(cx, r.y0, cz);
		// lamps every ~9 m along the long axis: strip + powered point light + emergency red (distance-culled in update)
		const long = Math.max(w, d), n = Math.max(1, Math.round(long / 9)), alongZ = d >= w;
		for (let i = 0; i < n; i++) {
			const t = (i + 0.5) / n, x = alongZ ? cx : r.x0 + w * t, z = alongZ ? r.z0 + d * t : cz;
			const s = box(alongZ ? Math.min(w * 0.5, 2.5) : 0.35, 0.06, alongZ ? 0.35 : Math.min(d * 0.5, 2.5), strip, x, H - 0.05, z, false);
			const l = new THREE.PointLight(0xbfd8ff, gate ? 6 : Math.min(8, 3 + Math.min(w, d) * 0.5), gate ? 22 : 16, 1.5); l.visible = false; l.position.set(x, H - 0.6, z); cur.add(l);
			const em = new THREE.PointLight(0xff3020, 5, 9, 2); em.position.set(x, H - 0.7, z); cur.add(em);
			lights.push({ l, em, s, on: l.intensity, wp: new THREE.Vector3(x, r.y0 + H - 0.6, z) });
		}
		if (r.type === 'corridor') { // amber edge lines both sides of the walkway (the video's corridor look)
			const inset = 0.45;
			if (alongZ) for (const sx of [-1, 1]) box(0.08, 0.03, d - 0.6, edge, cx + sx * (w / 2 - inset), 0.02, cz, false);
			else for (const sz of [-1, 1]) box(w - 0.6, 0.03, 0.08, edge, cx, 0.02, cz + sz * (d / 2 - inset), false);
		}
	}
	// ---- doors (SGU style): arched two-leaf door with radial spokes, a sunburst gear hub locking the seam, arched wall console
	// with a dome button per side. Built in a local frame (door in the x/y plane, normal = local z) then rotated for 'x' walls.
		const leafTex = (() => {
		const W = 480, Hc = 640, c = document.createElement('canvas'); c.width = W; c.height = Hc; const g = c.getContext('2d');
		g.fillStyle = '#2b2d30'; g.fillRect(0, 0, W, Hc);
		for (let i = 0; i < 2500; i++) { g.fillStyle = `rgba(${Math.random() < 0.5 ? '0,0,0' : '160,170,180'},${Math.random() * 0.08})`; g.fillRect(Math.random() * W, Math.random() * Hc, 2, 2 + Math.random() * 14); }
		const cx = W / 2, cy = Hc / 2, spokes = 8; // rounded slots between spokes, radiating from the hub
		g.fillStyle = '#0d0f12';
		for (let i = 0; i < spokes; i++) { const a0 = (i / spokes) * Math.PI * 2 + 0.16, a1 = ((i + 1) / spokes) * Math.PI * 2 - 0.16; g.beginPath(); g.arc(cx, cy, 120, a0, a1); g.arc(cx, cy, 250, a1, a0, true); g.closePath(); g.fill(); }
		g.strokeStyle = '#3a3d42'; g.lineWidth = 10; g.beginPath(); g.arc(cx, cy, 262, 0, 7); g.stroke(); g.beginPath(); g.arc(cx, cy, 108, 0, 7); g.stroke();
		g.fillStyle = '#4a4d52'; for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; g.beginPath(); g.arc(cx + Math.cos(a) * 285, cy + Math.sin(a) * 285, 5, 0, 7); g.fill(); }
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.repeat.set(1 / DOOR_W, 1 / DOOR_H); t.offset.set(0.5, 0); return t;
	})();
	const leafMat = new THREE.MeshStandardMaterial({ map: leafTex, roughness: 0.55, metalness: 0.7 });
	const leafGeo = (s) => { // half arch: inner edge at x = 0, outer at s·R, semicircular top
		const sh = new THREE.Shape(); sh.moveTo(0, 0); sh.lineTo(s * R, 0); sh.lineTo(s * R, ARCH_Y); sh.absarc(0, ARCH_Y, R, s > 0 ? 0 : Math.PI, Math.PI / 2, s < 0); sh.lineTo(0, 0); // aClockwise: left leaf sweeps π→π/2 clockwise
		const geo = new THREE.ExtrudeGeometry(sh, { depth: 0.16, bevelEnabled: false }); geo.translate(0, 0, -0.08);
		// slight convex curve across the leaf (SGU doors bow outward): push the seam edge forward, outer edge back
		const P = geo.attributes.position; for (let i = 0; i < P.count; i++) { const x = P.getX(i) / R; P.setZ(i, P.getZ(i) + BULGE * (0.5 - x * x)); }
		geo.computeVertexNormals(); return geo;
	};
	/** Half of the locking gear (split on the seam) so each leaf carries its half apart. Centred at the origin, radius HUB_R. */
	const hubHalfGeo = (s) => {
		const sh = new THREE.Shape(); sh.moveTo(0, -HUB_R); sh.absarc(0, 0, HUB_R, s > 0 ? -Math.PI / 2 : Math.PI / 2, s > 0 ? Math.PI / 2 : Math.PI * 1.5, false); sh.lineTo(0, -HUB_R);
		const geo = new THREE.ExtrudeGeometry(sh, { depth: 0.22, bevelEnabled: true, bevelThickness: 0.04, bevelSize: 0.03, bevelSegments: 2 }); geo.translate(0, 0, -0.11); return geo;
	};
	/** Toothed centre gear: the part that visibly spins, sitting proud of the split halves. */
	const gearGeo = (() => {
		const sh = new THREE.Shape(), teeth = 14; for (let i = 0; i < teeth * 2; i++) { const a = (i / (teeth * 2)) * Math.PI * 2, r = i % 2 ? GEAR_R : GEAR_R * 0.82; const a2 = a + Math.PI / (teeth * 2) * 0.9; if (i === 0) sh.moveTo(Math.cos(a) * r, Math.sin(a) * r); else sh.lineTo(Math.cos(a) * r, Math.sin(a) * r); sh.lineTo(Math.cos(a2) * r, Math.sin(a2) * r); }
		sh.closePath(); const geo = new THREE.ExtrudeGeometry(sh, { depth: 0.1, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.015, bevelSegments: 1 }); geo.translate(0, 0, -0.05); return geo;
	})();
	const gearMat = new THREE.MeshStandardMaterial({ color: 0xc9962c, roughness: 0.35, metalness: 0.9 }), gearCapMat = new THREE.MeshStandardMaterial({ color: 0x2a3346, roughness: 0.3, metalness: 0.6, emissive: 0x1a6cff, emissiveIntensity: 0.6 });
	const hubTex = (() => {
		const S = 256, c = document.createElement('canvas'); c.width = c.height = S; const g = c.getContext('2d'), m = S / 2;
		g.fillStyle = '#3a3c40'; g.beginPath(); g.arc(m, m, m, 0, 7); g.fill();
		g.fillStyle = '#b9b3a2'; for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; g.beginPath(); g.arc(m + Math.cos(a) * 104, m + Math.sin(a) * 104, 7, 0, 7); g.fill(); }
		g.fillStyle = '#c9962c'; g.beginPath(); for (let i = 0; i < 32; i++) { const a = (i / 32) * Math.PI * 2, r = i % 2 ? 96 : 60; g.lineTo(m + Math.cos(a) * r, m + Math.sin(a) * r); } g.closePath(); g.fill();
		g.fillStyle = '#2a3346'; g.beginPath(); g.arc(m, m, 34, 0, 7); g.fill(); g.fillStyle = '#3aa8ff'; g.beginPath(); g.arc(m, m, 12, 0, 7); g.fill();
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.repeat.set(1 / (2 * HUB_R), 1 / (2 * HUB_R)); t.offset.set(0.5, 0.5); return t;
	})();
	const hubMat = new THREE.MeshStandardMaterial({ map: hubTex, roughness: 0.4, metalness: 0.8 });
	const consoleTex = (() => {
		const c = document.createElement('canvas'); c.width = 128; c.height = 192; const g = c.getContext('2d');
		g.fillStyle = '#23262a'; g.fillRect(0, 0, 128, 192); g.strokeStyle = '#111'; g.lineWidth = 3; for (let y = 14; y < 70; y += 9) { g.beginPath(); g.moveTo(18, y); g.lineTo(110, y); g.stroke(); }
		g.fillStyle = '#7a1d1d'; g.fillRect(24, 84, 36, 22); g.fillStyle = '#b8781c'; g.fillRect(66, 84, 36, 22);
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
	})();
	const consoleMat = new THREE.MeshStandardMaterial({ map: consoleTex, roughness: 0.6, metalness: 0.6 });
	const frameMat = darkMat, postGeo = new THREE.BoxGeometry(0.26, ARCH_Y, 0.34), archGeo = new THREE.TorusGeometry(R + 0.13, 0.13, 8, 32, Math.PI);
	const doorObjs = doors.map((d) => {
		const y0 = byId[d.rooms[0]].y0; cur = decks[byId[d.rooms[0]].floor];
		const g = new THREE.Group(); cur.add(g);
		const pos = d.axis === 'x' ? new THREE.Vector3(d.at, 0, d.center) : new THREE.Vector3(d.center, 0, d.at); g.position.copy(pos); g.rotation.y = d.axis === 'x' ? Math.PI / 2 : 0;
		box(d.axis === 'x' ? 1.0 : DOOR_W, 0.1, d.axis === 'x' ? DOOR_W : 1.0, floorMat, pos.x, -0.05, pos.z, false);
		for (const s of [-1, 1]) { const p = new THREE.Mesh(postGeo, frameMat); p.position.set(s * (R + 0.13), ARCH_Y / 2, 0); p.castShadow = p.receiveShadow = true; g.add(p); occludable.push(p); }
		const arch = new THREE.Mesh(archGeo, frameMat); arch.position.set(0, ARCH_Y, 0); arch.scale.z = 1.3; g.add(arch); occludable.push(arch);
		const halves = [-1, 1].map((s) => { const m = new THREE.Mesh(leafGeo(s), leafMat); m.castShadow = m.receiveShadow = true; g.add(m); occludable.push(m); return { m, s }; });
		// one central locking gear, split on the seam: each half is parented to its leaf, sits on the spoke-wheel centre
		const hubs = halves.map(({ m, s }) => { const h = new THREE.Mesh(hubHalfGeo(s), hubMat); h.position.set(0, DOOR_H / 2, BULGE / 2); h.castShadow = true; m.add(h); return h; });
		// centre gears (one per face) ride the left leaf, proud of the halves; they spin fast while the lock releases
		const gears = [1, -1].map((side) => { const gz = side * (BULGE / 2 + 0.11 + 0.07); const gear = new THREE.Mesh(gearGeo, gearMat); gear.position.set(0, DOOR_H / 2, gz); gear.castShadow = true; const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.06, 16), gearCapMat); cap.rotation.x = Math.PI / 2; cap.position.z = side * 0.06; gear.add(cap); halves[0].m.add(gear); gear.userData.z0 = gz; return gear; });
		for (const s of [-1, 1]) { const bar = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.06, 0.06), edge); bar.position.set(0, DOOR_H + 0.3, s * (WALL_T + 0.03)); g.add(bar); } // lintel lamp per side
		const ind = new THREE.MeshStandardMaterial({ color: 0xff3020, emissive: 0xff2010, emissiveIntensity: 2 });
		for (const rid of d.rooms) { // per side: plaque over the arch naming the far room, console with dome button beside the door
			const r = byId[rid], c = center(r), n = d.axis === 'x' ? Math.sign(c.x - d.at) : Math.sign(c.z - d.at), ry = n > 0 ? 0 : Math.PI;
			const p = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 0.37), new THREE.MeshBasicMaterial({ map: textPlaque(d.plaque[rid]), transparent: true })); p.position.set(0, DOOR_H + 0.78, n * 0.42); p.rotation.y = ry; g.add(p);
			const con = new THREE.Group(); con.position.set(n * (R + 0.62), 1.35, n * (WALL_T + 0.07)); con.rotation.y = ry; g.add(con); // on this room's wall face (walls are inset WALL_T into each room)
			const body = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.44, 0.1), consoleMat); const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.1, 16, 1, false, 0, Math.PI), consoleMat); cap.rotation.z = Math.PI / 2; cap.rotation.y = Math.PI / 2; cap.position.y = 0.22; con.add(body, cap);
			const dome = new THREE.Mesh(new THREE.SphereGeometry(0.075, 16, 12), new THREE.MeshStandardMaterial({ color: 0x7a5a30, roughness: 0.35, metalness: 0.9 })); dome.position.set(0, -0.09, 0.06); con.add(dome);
			const lamp = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.02), ind); lamp.position.set(0, 0.0, 0.055); con.add(lamp);
		}
		const collider = new THREE.Box3(); colliders.push(collider);
		return { ...d, g, wp: pos.clone().setY(y0), y0, halves, hubs, gears, lamp: { material: ind }, open: 0, locked: true, collider };
	});
	const setDoorCollider = (d) => {
		if (d.open > 0.6) { d.collider.min.set(1e6, 1e6, 1e6); d.collider.max.set(1e6, 1e6, 1e6); return; }
		const p = d.g.position, y = d.y0;
		if (d.axis === 'x') d.collider.set(new THREE.Vector3(p.x - 0.2, y, p.z - DOOR_W / 2), new THREE.Vector3(p.x + 0.2, y + DOOR_H, p.z + DOOR_W / 2));
		else d.collider.set(new THREE.Vector3(p.x - DOOR_W / 2, y, p.z - 0.2), new THREE.Vector3(p.x + DOOR_W / 2, y + DOOR_H, p.z + 0.2));
	};
	doorObjs.forEach(setDoorCollider);

	// ---- props: reusable components placed from room.props (layout data / editor) or the per-type defaults
	const parts = { screens: [], holos: [], trims: [], kino: [], elevators: [], growLamps: [], sprouts: [], conduits: [] }, propMeshes = [], lootables = [];
	const mats = { dark: darkMat, floor: floorMat, door: doorMat, red: redMat, shell: new THREE.MeshStandardMaterial({ color: 0x2b3139, roughness: 0.45, metalness: 0.7 }), slit: new THREE.MeshStandardMaterial({ color: 0xcfe6ff, emissive: 0xcfe6ff, emissiveIntensity: 1.6 }), crate: new THREE.MeshStandardMaterial({ color: 0x5e6a3a, roughness: 0.9 }), steel: new THREE.MeshStandardMaterial({ color: 0xa8b0b8, roughness: 0.6 }) };
	for (const r of rooms) {
		cur = decks[r.floor];
		const c = center(r), specs = r.props ?? ROOM_PROPS[r.id] ?? DEFAULT_PROPS[r.type] ?? [];
		const ctx = { box, group: cur, mats, parts, roomH: roomH(r) };
		for (const s of specs) {
			const comp = COMPONENTS[s.type]; if (!comp) continue;
			const p = { x: r.x0 + c.w * s.u, z: r.z0 + c.d * s.v }, spec = { ry: 0, ...s };
			const n0 = cur.children.length, c0 = colliders.length;
			const out = comp.build(ctx, p, spec) ?? {}; if (out.anchor) out.anchor.y += r.y0;
			for (const m of cur.children.slice(n0)) { m.userData.prop = { roomId: r.id, spec: s }; propMeshes.push(m); }
			for (let i = c0; i < colliders.length; i++) colliders[i].prop = { roomId: r.id, spec: s };
			if (out.anchor && (spec.anchor || comp.defaultAnchor)) anchors[`${r.id}:${spec.anchor ?? comp.defaultAnchor}`] = out.anchor;
			if (out.loot) lootables.push({ key: `${r.id}:${spec.anchor ?? `${s.type}${lootables.length}`}`, roomId: r.id, anchor: out.anchor, setOpen: out.setOpen, items: out.items, loot: out.loot, spec: s });
		}
		if (r.type === 'gate_room') anchors['gate_room:GateFront'] = new THREE.Vector3(0, 0, gateZ + 3);
	}
	const { relayLamp, relayFuse, relayCover, scrubLamp, scrubBed, breachLight } = parts; let handle;
	// seal lever: on the spur side of the jammed door, offset along the wall
	cur = group;
	const jam = doorObjs.find((d) => d.jammed);
	if (jam) { cur = decks[byId[jam.rooms[0]].floor];
		const spur = byId[jam.rooms.find((id) => !id.startsWith('breached'))], c = center(spur), p = jam.g.position;
		const n = jam.axis === 'x' ? new THREE.Vector3(Math.sign(c.x - p.x), 0, 0) : new THREE.Vector3(0, 0, Math.sign(c.z - p.z)), side = jam.axis === 'x' ? new THREE.Vector3(0, 0, 1) : new THREE.Vector3(1, 0, 0);
		const lp = p.clone().addScaledVector(n, 0.35).addScaledVector(side, DOOR_W / 2 + 0.6);
		box(0.25, 0.9, 0.25, darkMat, lp.x, 1.2, lp.z, false);
		handle = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.5, 0.08), new THREE.MeshStandardMaterial({ color: 0xffd040, emissive: 0xff8000, emissiveIntensity: 1.5 })); handle.position.set(lp.x, 1.75, lp.z); handle.rotation.x = 0.6; group.add(handle);
		anchors[`${spur.id}:SealLever`] = lp.clone().addScaledVector(n, 0.9).setY(0);
	}

	mergeStatic();
	const state = { group, rooms, doors: doorObjs, elevators, anchors, occludable, ceilings, propMeshes, lootables, powered: false, doorSpeed: 1, onDoor: null }; // onDoor(ev, door): 'unlock' | 'closed' | 'denied'
	state.setPower = (on) => {
		state.powered = on;
		strip.emissiveIntensity = on ? 1.2 : 0; edge.emissiveIntensity = on ? 1.8 : 0.25;
		if (relayLamp) { relayLamp.material.color.set(on ? 0x40ff80 : 0xff3020); relayLamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); }
		for (const sc of parts.screens) sc.material.emissiveIntensity = on ? 1.6 : 0;
		for (const h of parts.holos) h.visible = on; for (const t of parts.trims) t.material.emissiveIntensity = on ? 1.2 : 0.1;
		for (const d of doorObjs) if (!d.jammed && !d.sealed) { d.locked = !on; d.lamp.material.color.set(on ? 0x40ff80 : 0xff3020); d.lamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); }
	};
	/** Fuse seated in the relay bay (cover swings open, fuse visible, lamp amber = ready to hotwire). */
	state.installFuse = () => { if (relayFuse) relayFuse.visible = true; if (relayCover) relayCover.rotation.x = -1.9; if (relayLamp && !state.powered) { relayLamp.material.color.set(0xffa020); relayLamp.material.emissive.set(0xff8000); } };
	/** Elevator bus: fuses seated (visible) → powered (lamp green, doors part). */
	state.seatElevatorFuses = () => { for (const e of parts.elevators) for (const f of e.fuses) f.visible = true; };
	state.setElevatorPower = (on) => { state.elevatorPowered = on; for (const e of parts.elevators) { e.lamp.material.color.set(on ? 0x40ff80 : 0xff3020); e.lamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); for (const [i, m] of e.leaves.entries()) m.position.x = (i ? 1 : -1) * (on ? 1.05 : 0.58); } };
	state.installConduit = () => { for (const c of parts.conduits) { c.segment.visible = true; if (!state.quartersPowered) { c.lamp.material.color.set(0xffa020); c.lamp.material.emissive.set(0xff8000); } } };
	state.setQuartersPower = (on) => { state.quartersPowered = on; for (const c of parts.conduits) { c.lamp.material.color.set(on ? 0x40ff80 : 0xff3020); c.lamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); } };
	state.setGrowLights = (on) => { for (const l of parts.growLamps) l.material.emissiveIntensity = on ? 1.8 : 0; for (const s of parts.sprouts) s.visible = on; };
	state.takeLoot = (l) => { if (l.items) l.items.visible = false; l.taken = true; };
	state.openCrate = (l, instant = false) => { l.opened = true; if (instant) { l.openK = 1; l.setOpen?.(1); } else l.openK ??= 0; }; // lid animates in update()
	state.sealBreach = () => { const d = jam; d.sealed = true; d.locked = true; d.lamp.material.color.set(0xffa020); d.lamp.material.emissive.set(0xff8000); handle.rotation.x = -0.6; if (breachLight) breachLight.intensity = 0; };
	state.repairScrubber = () => { if (!scrubLamp) return; scrubLamp.material.color.set(0x40ff80); scrubLamp.material.emissive.set(0x20ff60); scrubBed.material.color.set(0xe8e2d0); };
	state.takeKino = () => { for (const m of parts.kino) m.visible = false; };
	/** Doors slide open when unlocked and the player is within 3 m; only lights near the player are live (light count drives shader cost). */
	state.update = (dt, playerPos) => {
		for (const l of lootables) if (l.opened && l.openK < 1) { l.openK = Math.min(1, l.openK + dt / 0.9); l.setOpen?.(l.openK); }
		for (const d of doorObjs) {
			const near = playerPos.distanceTo(d.wp) < 3.2;
			const target = !d.locked && !d.sealed && near ? 1 : 0;
			if (near && !d.wasNear && target === 0) state.onDoor?.('denied', d); d.wasNear = near;
			const prev = d.open; d.open += (target - d.open) * Math.min(1, dt * 4 * state.doorSpeed);
			const unlock = Math.min(1, d.open * 3), slide = Math.max(0, (d.open - 0.33) / 0.67);
			for (const h of d.hubs) { h.rotation.z = unlock * Math.PI * 2; h.position.z = BULGE / 2 + Math.sin(unlock * Math.PI) * 0.06; } // one full turn, pops out, then splits with the leaves
			for (const gr of d.gears) { gr.rotation.z = -unlock * Math.PI * 4; gr.position.z = gr.userData.z0 * (1 - unlock * 0.55); } // centre gear spins two turns and sinks flush as the lock releases
			for (const { m, s } of d.halves) m.position.x = s * slide * (R + HUB_R + 0.12); // far enough that the gear halves vanish into the wall
			if ((prev > 0.6) !== (d.open > 0.6)) setDoorCollider(d);
			if (prev < 0.01 && d.open >= 0.01) state.onDoor?.('unlock', d); if (prev > 0.08 && d.open <= 0.08 && target === 0) state.onDoor?.('closed', d);
		}
		// only the nearest few lamps are live: every visible light recompiles into every material's shader cost
		const near = lights.map((L) => [L.wp.distanceToSquared(playerPos), L]).filter(([d2]) => d2 < LIGHT_RANGE * LIGHT_RANGE).sort((a, b) => a[0] - b[0]).slice(0, MAX_LIVE).map(([, L]) => L);
		for (const L of lights) { const on = near.includes(L); L.l.visible = state.powered && on; L.em.visible = !state.powered && on; }
	};
	for (const h of parts.holos) h.visible = false; for (const t of parts.trims) t.material.emissiveIntensity = 0.1;
	state.update(0, new THREE.Vector3(0, 0, 0));
	state.roomAt = (p) => rooms.find((r) => Math.abs(p.y - r.y0) < DECK_H / 2 && p.x >= r.x0 && p.x <= r.x1 && p.z >= r.z0 && p.z <= r.z1)?.id ?? null;
	state.deckOf = (id) => byId[id]?.floor ?? 0;
	/** Shortest door path between rooms (BFS). Returns door objects in walking order, or null. */
	state.route = (from, to) => {
		const prev = new Map([[from, null]]), q = [from];
		while (q.length) { const cur = q.shift(); if (cur === to) break; for (const d of [...doorObjs, ...elevators]) { if (d.sealed && !d.jammed) continue; const nxt = d.rooms[0] === cur ? d.rooms[1] : d.rooms[1] === cur ? d.rooms[0] : null; if (nxt && !prev.has(nxt)) { prev.set(nxt, { room: cur, door: d }); q.push(nxt); } } }
		if (!prev.has(to)) return null;
		const path = []; for (let r = to; prev.get(r); r = prev.get(r).room) path.unshift(prev.get(r).door); return path;
	};
	state.center = (id) => { const c = center(byId[id]); return new THREE.Vector3(c.x, byId[id].y0, c.z); };
	return state;
};
