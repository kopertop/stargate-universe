// Destiny deck 0, generated from the repo's canonical layout (data/ship_layout.json + data/room_connections.json — the same
// data the Godot build uses). JSON plan units → metres at 0.05 (gate room 800×400 → 40×20 m). JSON X runs along the ship;
// we map X → -Z so the gate sits at the far (-Z) end of the gate room and the East Connector leaves toward +Z. JSON Y → X.
// Rooms are AABB shells with door gaps cut where two rooms share an edge; doors slide open when powered + unlocked + near.
import * as THREE from 'three';
import { ancientMaterial, ancientFloorMaterial } from './ancient.js';

export const DOOR_W = 2.4, DOOR_H = 3.2, WALL_T = 0.3;
const SCALE = 0.05, H_ROOM = 4.6, LIGHT_RANGE = 22, MAX_LIVE = 6;
const ROOM_H = { gate_room: 11, control_room: 6.5, hydroponics: 6, 'shuttle-dock': 6 };

/** JSON rooms (floor 0) → world rects. */
export const roomsFromLayout = (layout) => layout.filter((r) => r.floor === 0).map((r) => ({
	id: r.id, name: r.name, type: r.type, key: !!r.key_room,
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
		const key = [a.id, b.id].sort().join('|'); if (seen.has(key)) return; const e = sharedEdge(a, b); if (!e) return; seen.add(key);
		doors.push({ id: key, axis: e.axis, at: e.at, center: (e.lo + e.hi) / 2, rooms: [a.id, b.id], plaque: { [a.id]: plaque ?? b.name, [b.id]: a.name }, jammed: b.type === 'shuttle-dock' && b.id.startsWith('breached'), sealed: b.id.startsWith('sealed') });
	};
	const linked = new Set();
	for (const [from, list] of Object.entries(connections)) for (const c of list) { if (c.dir === 'elevator' || !byId[from] || !byId[c.to]) continue; linked.add(from); linked.add(c.to); add(byId[from], byId[c.to], c.plaque); }
	for (const r of rooms) if (!linked.has(r.id)) for (const o of rooms) if (o !== r) add(r, o, o.name);
	return doors;
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
	const rooms = roomsFromLayout(layout), doors = doorsFromLayout(rooms, connections), byId = Object.fromEntries(rooms.map((r) => [r.id, r]));
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
	const box = (w, h, d, mat, x, y, z, solid = true, ry = 0) => {
		const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); m.rotation.y = ry; m.castShadow = m.receiveShadow = true; group.add(m);
		if (solid) { m.updateMatrixWorld(); colliders.push(new THREE.Box3().setFromObject(m)); occludable.push(m); }
		return m;
	};
	const roomH = (r) => ROOM_H[r.type] ?? H_ROOM;
	const doorsOnWall = (axis, at, lo, hi) => doors.filter((d) => d.axis === axis && Math.abs(d.at - at) < 1e-3 && d.center > lo && d.center < hi);
	// wall along a boundary with door gaps; inset by WALL_T/2 into the room (dir = ±1)
	const wall = (axis, at, lo, hi, dir, H, mat) => {
		const gaps = doorsOnWall(axis, at, lo, hi).map((d) => [d.center - DOOR_W / 2, d.center + DOOR_W / 2]).sort((a, b) => a[0] - b[0]);
		const segs = []; let cur = lo; for (const [g0, g1] of gaps) { if (g0 > cur) segs.push([cur, g0]); cur = g1; } if (cur < hi) segs.push([cur, hi]);
		const c = at + dir * WALL_T / 2;
		for (const [a, b] of segs) axis === 'x' ? box(WALL_T, H, b - a, mat, c, H / 2, (a + b) / 2) : box(b - a, H, WALL_T, mat, (a + b) / 2, H / 2, c);
		for (const [g0, g1] of gaps) { const lint = H - DOOR_H; axis === 'x' ? box(WALL_T, lint, g1 - g0, mat, c, DOOR_H + lint / 2, (g0 + g1) / 2) : box(g1 - g0, lint, WALL_T, mat, (g0 + g1) / 2, DOOR_H + lint / 2, c); }
	};
	for (const r of rooms) {
		const { x: cx, z: cz, w, d } = center(r), H = roomH(r), gate = r.type === 'gate_room';
		if (!gate) { box(w, 0.1, d, floorMat, cx, -0.05, cz, false).receiveShadow = true; }
		const ceil = box(w, 0.1, d, ceilMat, cx, H + 0.05, cz, false); group.remove(ceil); ceilings.add(ceil);
		const mat = gate ? tallWallMat : wallMat;
		wall('x', r.x0, r.z0, r.z1, +1, H, mat); wall('x', r.x1, r.z0, r.z1, -1, H, mat); wall('z', r.z0, r.x0, r.x1, +1, H, mat); wall('z', r.z1, r.x0, r.x1, -1, H, mat);
		anchors[`${r.id}:RoomCenter`] = new THREE.Vector3(cx, 0, cz);
		// lamps every ~9 m along the long axis: strip + powered point light + emergency red (distance-culled in update)
		const long = Math.max(w, d), n = Math.max(1, Math.round(long / 9)), alongZ = d >= w;
		for (let i = 0; i < n; i++) {
			const t = (i + 0.5) / n, x = alongZ ? cx : r.x0 + w * t, z = alongZ ? r.z0 + d * t : cz;
			const s = box(alongZ ? Math.min(w * 0.5, 2.5) : 0.35, 0.06, alongZ ? 0.35 : Math.min(d * 0.5, 2.5), strip, x, H - 0.05, z, false);
			const l = new THREE.PointLight(0xbfd8ff, gate ? 6 : Math.min(6, 1.5 + Math.min(w, d) * 0.5), gate ? 22 : 14, 1.6); l.visible = false; l.position.set(x, H - 0.6, z); group.add(l);
			const em = new THREE.PointLight(0xff3020, 5, 9, 2); em.position.set(x, H - 0.7, z); group.add(em);
			lights.push({ l, em, s, on: l.intensity });
		}
		if (r.type === 'corridor') { // amber edge lines both sides of the walkway (the video's corridor look)
			const inset = 0.45;
			if (alongZ) for (const sx of [-1, 1]) box(0.08, 0.03, d - 0.6, edge, cx + sx * (w / 2 - inset), 0.02, cz, false);
			else for (const sz of [-1, 1]) box(w - 0.6, 0.03, 0.08, edge, cx, 0.02, cz + sz * (d / 2 - inset), false);
		}
	}
	// ---- doors (SGU style): arched two-leaf door with radial spokes, a sunburst gear hub locking the seam, arched wall console
	// with a dome button per side. Built in a local frame (door in the x/y plane, normal = local z) then rotated for 'x' walls.
	const R = DOOR_W / 2, ARCH_Y = DOOR_H - R;
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
		const geo = new THREE.ExtrudeGeometry(sh, { depth: 0.16, bevelEnabled: false }); geo.translate(0, 0, -0.08); return geo;
	};
	const hubTex = (() => {
		const S = 256, c = document.createElement('canvas'); c.width = c.height = S; const g = c.getContext('2d'), m = S / 2;
		g.fillStyle = '#3a3c40'; g.beginPath(); g.arc(m, m, m, 0, 7); g.fill();
		g.fillStyle = '#b9b3a2'; for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; g.beginPath(); g.arc(m + Math.cos(a) * 104, m + Math.sin(a) * 104, 7, 0, 7); g.fill(); }
		g.fillStyle = '#c9962c'; g.beginPath(); for (let i = 0; i < 32; i++) { const a = (i / 32) * Math.PI * 2, r = i % 2 ? 96 : 60; g.lineTo(m + Math.cos(a) * r, m + Math.sin(a) * r); } g.closePath(); g.fill();
		g.fillStyle = '#2a3346'; g.beginPath(); g.arc(m, m, 34, 0, 7); g.fill(); g.fillStyle = '#3aa8ff'; g.beginPath(); g.arc(m, m, 12, 0, 7); g.fill();
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
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
		const g = new THREE.Group(); group.add(g);
		const pos = d.axis === 'x' ? new THREE.Vector3(d.at, 0, d.center) : new THREE.Vector3(d.center, 0, d.at); g.position.copy(pos); g.rotation.y = d.axis === 'x' ? Math.PI / 2 : 0;
		box(d.axis === 'x' ? 1.0 : DOOR_W, 0.1, d.axis === 'x' ? DOOR_W : 1.0, floorMat, pos.x, -0.05, pos.z, false);
		for (const s of [-1, 1]) { const p = new THREE.Mesh(postGeo, frameMat); p.position.set(s * (R + 0.13), ARCH_Y / 2, 0); p.castShadow = p.receiveShadow = true; g.add(p); occludable.push(p); }
		const arch = new THREE.Mesh(archGeo, frameMat); arch.position.set(0, ARCH_Y, 0); arch.scale.z = 1.3; g.add(arch); occludable.push(arch);
		const halves = [-1, 1].map((s) => { const m = new THREE.Mesh(leafGeo(s), leafMat); m.castShadow = m.receiveShadow = true; g.add(m); occludable.push(m); return { m, s }; });
		const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.14, 32), hubMat); hub.rotation.x = Math.PI / 2; hub.position.set(0, DOOR_H / 2, 0.06); halves[0].m.add(hub); // sits on the spoke-wheel centre (texture v = 0.5)
		const hub2 = hub.clone(); hub2.position.z = -0.06; hub2.rotation.x = -Math.PI / 2; halves[0].m.add(hub2); // gear on both faces of the seam
		const ind = new THREE.MeshStandardMaterial({ color: 0xff3020, emissive: 0xff2010, emissiveIntensity: 2 });
		for (const rid of d.rooms) { // per side: plaque over the arch naming the far room, console with dome button beside the door
			const r = byId[rid], c = center(r), n = d.axis === 'x' ? Math.sign(c.x - d.at) : Math.sign(c.z - d.at), ry = n > 0 ? 0 : Math.PI;
			const p = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 0.37), new THREE.MeshBasicMaterial({ map: textPlaque(d.plaque[rid]), transparent: true })); p.position.set(0, DOOR_H + 0.62, n * 0.42); p.rotation.y = ry; g.add(p);
			const con = new THREE.Group(); con.position.set(n * (R + 0.62), 1.35, n * (WALL_T + 0.07)); con.rotation.y = ry; g.add(con); // on this room's wall face (walls are inset WALL_T into each room)
			const body = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.44, 0.1), consoleMat); const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.1, 16, 1, false, 0, Math.PI), consoleMat); cap.rotation.z = Math.PI / 2; cap.rotation.y = Math.PI / 2; cap.position.y = 0.22; con.add(body, cap);
			const dome = new THREE.Mesh(new THREE.SphereGeometry(0.075, 16, 12), new THREE.MeshStandardMaterial({ color: 0x7a5a30, roughness: 0.35, metalness: 0.9 })); dome.position.set(0, -0.09, 0.06); con.add(dome);
			const lamp = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.02), ind); lamp.position.set(0, 0.0, 0.055); con.add(lamp);
		}
		const collider = new THREE.Box3(); colliders.push(collider);
		return { ...d, g, halves, hub, hub2, lamp: { material: ind }, open: 0, locked: true, collider };
	});
	const setDoorCollider = (d) => {
		if (d.open > 0.6) { d.collider.min.set(1e6, 1e6, 1e6); d.collider.max.set(1e6, 1e6, 1e6); return; }
		const p = d.g.position;
		if (d.axis === 'x') d.collider.set(new THREE.Vector3(p.x - 0.2, 0, p.z - DOOR_W / 2), new THREE.Vector3(p.x + 0.2, DOOR_H, p.z + DOOR_W / 2));
		else d.collider.set(new THREE.Vector3(p.x - DOOR_W / 2, 0, p.z - 0.2), new THREE.Vector3(p.x + DOOR_W / 2, DOOR_H, p.z + 0.2));
	};
	doorObjs.forEach(setDoorCollider);

	// ---- props by room type (positions relative to each room's rect)
	const at = (r, u, v) => { const c = center(r); return [r.x0 + c.w * u, r.z0 + c.d * v]; };
	const lampOf = (x, y, z, ry = 0) => { const m = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.12, 0.05), redMat.clone()); m.position.set(x, y, z); m.rotation.y = ry; group.add(m); return m; };
	let relayLamp, screen, kinoOrb, remote, scrubLamp, scrubBed, handle, breachLight;
	for (const r of rooms) {
		const c = center(r);
		if (r.type === 'gate_room') { // relay by the connector door (+z wall), supply crate, crew spots
			const dz = r.z1 - 0.45;
			box(1.2, 1.6, 0.25, darkMat, 3.6, 1.2, dz, true); relayLamp = lampOf(3.6, 1.75, dz - 0.15);
			anchors['gate_room:PowerRelay'] = new THREE.Vector3(3.6, 0, dz - 0.9);
			box(1.4, 0.9, 1.0, new THREE.MeshStandardMaterial({ color: 0x5e6a3a, roughness: 0.9 }), -5, 0.45, 14.5, true);
			anchors['gate_room:SupplyCrate'] = new THREE.Vector3(-5, 0, 13.3);
			anchors['gate_room:Brody'] = new THREE.Vector3(4.6, 0, 12); anchors['gate_room:Scott'] = new THREE.Vector3(-3.5, 0, 9);
			anchors['gate_room:GateFront'] = new THREE.Vector3(0, 0, gateZ + 3);
		} else if (r.type === 'control_room') { // central console facing the -z door, pillars, Rush
			box(2.6, 1.0, 1.0, darkMat, c.x, 0.5, c.z + 1.2, true);
			screen = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.05, 0.8), new THREE.MeshStandardMaterial({ color: 0x9fd8ff, emissive: 0x4fa8ff, emissiveIntensity: 0 })); screen.position.set(c.x, 1.03, c.z + 1.2); screen.rotation.x = -0.3; group.add(screen);
			anchors['control_interface_room:ControlConsole'] = new THREE.Vector3(c.x, 0, c.z - 0.3);
			for (const [u, v] of [[0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]]) { const [x, z] = at(r, u, v); box(1.2, roomH(r) - 0.2, 1.2, darkMat, x, roomH(r) / 2 - 0.1, z, true); }
			anchors['control_interface_room:Rush'] = new THREE.Vector3(c.x + 3, 0, c.z + 0.6);
		} else if (r.id === 'eli_quarters') { // Kino Room: pedestal with orb + remote, locker with a vest, bed
			const [px, pz] = at(r, 0.5, 0.3);
			box(0.7, 1.0, 0.7, darkMat, px, 0.5, pz, true);
			kinoOrb = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 14), new THREE.MeshStandardMaterial({ color: 0x555a60, roughness: 0.35, metalness: 0.8 })); kinoOrb.position.set(px, 1.2, pz); group.add(kinoOrb);
			remote = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.3), new THREE.MeshStandardMaterial({ color: 0x8a7a5c, emissive: 0x2ad4ff, emissiveIntensity: 0.6, metalness: 0.7 })); remote.position.set(px - 0.3, 1.03, pz + 0.15); group.add(remote);
			anchors['eli_quarters:KinoPedestal'] = new THREE.Vector3(px, 0, pz + 1.0);
			const lx = r.x1 - 0.5, lz = at(r, 0, 0.75)[1]; box(0.9, 2.2, 0.6, darkMat, lx, 1.1, lz, true, Math.PI / 2);
			anchors['eli_quarters:Locker'] = new THREE.Vector3(lx - 0.9, 0, lz);
			box(2, 0.5, 1, floorMat, r.x0 + 1.3, 0.25, at(r, 0, 0.75)[1], true); anchors['eli_quarters:Bed'] = new THREE.Vector3(r.x0 + 1.3, 0, at(r, 0, 0.6)[1]);
		} else if (r.type === 'quarters') { box(2, 0.5, 1, floorMat, r.x0 + 1.3, 0.25, c.z, true); box(0.6, 2.2, 0.9, darkMat, r.x1 - 0.4, 1.1, c.z - 2, true); }
		else if (r.type === 'storage') { for (const [u, v] of [[0.2, 0.25], [0.35, 0.3], [0.75, 0.7], [0.8, 0.3]]) { const [x, z] = at(r, u, v); box(1.4, 0.9, 1.0, new THREE.MeshStandardMaterial({ color: 0x4a5236, roughness: 0.9 }), x, 0.45, z, true, (u + v) * 2); } }
		else if (r.type === 'infirmary') { for (const v of [0.3, 0.5, 0.7]) { const [x, z] = at(r, 0.25, v); box(2.0, 0.6, 0.9, new THREE.MeshStandardMaterial({ color: 0xa8b0b8, roughness: 0.6 }), x, 0.3, z, true); } box(1.8, 2.0, 0.5, darkMat, at(r, 0.8, 0.5)[0], 1.0, c.z, true); anchors['infirmary:Beds'] = new THREE.Vector3(c.x, 0, c.z); }
		else if (r.type === 'elevator') { box(DOOR_W, DOOR_H, 0.2, doorMat, c.x, DOOR_H / 2, r.z0 + 0.3, true); lampOf(c.x, DOOR_H + 0.15, r.z0 + 0.45); anchors['elevator_north:Elevator'] = new THREE.Vector3(c.x, 0, r.z0 + 1.4); }
		else if (r.type === 'shuttle-dock') { // far wall torn open (breached) or dark and dead (sealed)
			const tear = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 2.4), new THREE.MeshBasicMaterial({ color: 0x02030a })); tear.position.set(r.x1 - 0.05, 2.6, c.z); tear.rotation.y = -Math.PI / 2; group.add(tear);
			if (r.id.startsWith('breached')) { breachLight = new THREE.PointLight(0x88aaff, 6, 12); breachLight.position.set(r.x1 - 2.5, 3, c.z); group.add(breachLight); }
		}
		if (r.id === 'south_corridor') { // CO2 scrubber panel on the outer (+x) wall, midway
			const sz = c.z + 6, sx = r.x1 - 0.35;
			box(0.4, 2.4, 2.2, darkMat, sx, 1.3, sz, true); scrubLamp = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.5, 0.5), redMat.clone()); scrubLamp.position.set(sx - 0.24, 2.2, sz); group.add(scrubLamp);
			scrubBed = new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.2, 1.6), new THREE.MeshStandardMaterial({ color: 0x5a5245, roughness: 1 })); scrubBed.position.set(sx - 0.22, 1.0, sz); group.add(scrubBed);
			anchors['south_corridor:Scrubber'] = new THREE.Vector3(sx - 1.0, 0, sz);
		}
	}
	// seal lever: on the spur side of the jammed door, offset along the wall
	const jam = doorObjs.find((d) => d.jammed);
	if (jam) {
		const spur = byId[jam.rooms.find((id) => !id.startsWith('breached'))], c = center(spur), p = jam.g.position;
		const n = jam.axis === 'x' ? new THREE.Vector3(Math.sign(c.x - p.x), 0, 0) : new THREE.Vector3(0, 0, Math.sign(c.z - p.z)), side = jam.axis === 'x' ? new THREE.Vector3(0, 0, 1) : new THREE.Vector3(1, 0, 0);
		const lp = p.clone().addScaledVector(n, 0.35).addScaledVector(side, DOOR_W / 2 + 0.6);
		box(0.25, 0.9, 0.25, darkMat, lp.x, 1.2, lp.z, false);
		handle = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.5, 0.08), new THREE.MeshStandardMaterial({ color: 0xffd040, emissive: 0xff8000, emissiveIntensity: 1.5 })); handle.position.set(lp.x, 1.75, lp.z); handle.rotation.x = 0.6; group.add(handle);
		anchors[`${spur.id}:SealLever`] = lp.clone().addScaledVector(n, 0.9).setY(0);
	}

	const state = { group, rooms, doors: doorObjs, anchors, occludable, ceilings, powered: false };
	state.setPower = (on) => {
		state.powered = on;
		strip.emissiveIntensity = on ? 1.2 : 0; edge.emissiveIntensity = on ? 1.8 : 0.25;
		relayLamp.material.color.set(on ? 0x40ff80 : 0xff3020); relayLamp.material.emissive.set(on ? 0x20ff60 : 0xff2010);
		screen.material.emissiveIntensity = on ? 1.6 : 0;
		for (const d of doorObjs) if (!d.jammed && !d.sealed) { d.locked = !on; d.lamp.material.color.set(on ? 0x40ff80 : 0xff3020); d.lamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); }
	};
	state.sealBreach = () => { const d = jam; d.sealed = true; d.locked = true; d.lamp.material.color.set(0xffa020); d.lamp.material.emissive.set(0xff8000); handle.rotation.x = -0.6; if (breachLight) breachLight.intensity = 0; };
	state.repairScrubber = () => { scrubLamp.material.color.set(0x40ff80); scrubLamp.material.emissive.set(0x20ff60); scrubBed.material.color.set(0xe8e2d0); };
	state.takeKino = () => { kinoOrb.visible = false; remote.visible = false; };
	/** Doors slide open when unlocked and the player is within 3 m; only lights near the player are live (light count drives shader cost). */
	state.update = (dt, playerPos) => {
		for (const d of doorObjs) {
			const near = playerPos.distanceTo(d.g.position) < 3.2;
			const target = !d.locked && !d.sealed && near ? 1 : 0;
			const prev = d.open; d.open += (target - d.open) * Math.min(1, dt * 4);
			const unlock = Math.min(1, d.open * 3), slide = Math.max(0, (d.open - 0.33) / 0.67);
			d.hub.rotation.y = unlock * Math.PI / 2; d.hub.position.z = 0.06 + unlock * 0.05; d.hub2.rotation.y = -unlock * Math.PI / 2; d.hub2.position.z = -0.06 - unlock * 0.05;
			for (const { m, s } of d.halves) m.position.x = s * slide * (R + 0.08);
			if ((prev > 0.6) !== (d.open > 0.6)) setDoorCollider(d);
		}
		// only the nearest few lamps are live: every visible light recompiles into every material's shader cost
		const near = lights.map((L) => [L.l.position.distanceToSquared(playerPos), L]).filter(([d2]) => d2 < LIGHT_RANGE * LIGHT_RANGE).sort((a, b) => a[0] - b[0]).slice(0, MAX_LIVE).map(([, L]) => L);
		for (const L of lights) { const on = near.includes(L); L.l.visible = state.powered && on; L.em.visible = !state.powered && on; }
	};
	state.update(0, new THREE.Vector3(0, 0, 0));
	state.roomAt = (p) => rooms.find((r) => p.x >= r.x0 && p.x <= r.x1 && p.z >= r.z0 && p.z <= r.z1)?.id ?? null;
	/** Shortest door path between rooms (BFS). Returns door objects in walking order, or null. */
	state.route = (from, to) => {
		const prev = new Map([[from, null]]), q = [from];
		while (q.length) { const cur = q.shift(); if (cur === to) break; for (const d of doorObjs) { if (d.sealed && !d.jammed) continue; const nxt = d.rooms[0] === cur ? d.rooms[1] : d.rooms[1] === cur ? d.rooms[0] : null; if (nxt && !prev.has(nxt)) { prev.set(nxt, { room: cur, door: d }); q.push(nxt); } } }
		if (!prev.has(to)) return null;
		const path = []; for (let r = to; prev.get(r); r = prev.get(r).room) path.unshift(prev.get(r).door); return path;
	};
	state.center = (id) => { const c = center(byId[id]); return new THREE.Vector3(c.x, 0, c.z); };
	return state;
};
