// Destiny interior beyond the gate room: corridor, control room, kino room, life support, breached shuttle dock.
// Rooms are AABB shells with door gaps; doors slide open when powered + unlocked and the player is near.
import * as THREE from 'three';

const DOOR_W = 2.4, DOOR_H = 3.2, WALL_T = 0.3, H = 5.5;
// World-space rooms (gate room is x ±7, z -16..14 from gate-room.js; its front door is at z = 14)
export const SHIP_ROOMS = [
	{ id: 'corridor_main', name: 'Main Corridor', x0: -1.6, x1: 1.6, z0: 14, z1: 28 },
	{ id: 'control_interface_room', name: 'Control Interface Room', x0: -7, x1: 7, z0: 28, z1: 40 },
	{ id: 'eli_quarters', name: 'Kino Room', x0: 1.6, x1: 9.6, z0: 17, z1: 24.5 },
	{ id: 'life_support', name: 'Life Support', x0: -9.6, x1: -1.6, z0: 17, z1: 24.5 },
	{ id: 'breached_section', name: 'Shuttle Dock (Port)', x0: -17.6, x1: -9.6, z0: 17, z1: 24.5 },
];
// Doors: on a wall between two rooms. axis 'x' = door in a wall of constant x (opening spans z), 'z' = wall of constant z.
export const SHIP_DOORS = [
	{ id: 'd_gate_corridor', axis: 'z', at: 14, center: 0, rooms: ['gate_room', 'corridor_main'] },
	{ id: 'd_corridor_control', axis: 'z', at: 28, center: 0, rooms: ['corridor_main', 'control_interface_room'] },
	{ id: 'd_corridor_kino', axis: 'x', at: 1.6, center: 20.75, rooms: ['corridor_main', 'eli_quarters'] },
	{ id: 'd_corridor_life', axis: 'x', at: -1.6, center: 20.75, rooms: ['corridor_main', 'life_support'] },
	{ id: 'd_life_breach', axis: 'x', at: -9.6, center: 20.75, rooms: ['life_support', 'breached_section'], jammed: true },
];

const panelTex = () => {
	const c = document.createElement('canvas'); c.width = 256; c.height = 256; const g = c.getContext('2d');
	g.fillStyle = '#3a3630'; g.fillRect(0, 0, 256, 256);
	for (let i = 0; i < 300; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.15})`; g.fillRect(Math.random() * 256, Math.random() * 256, 3, 3 + Math.random() * 20); }
	g.strokeStyle = '#22201c'; g.lineWidth = 6; g.strokeRect(6, 6, 244, 244); g.beginPath(); g.moveTo(128, 6); g.lineTo(128, 250); g.stroke();
	g.fillStyle = '#8a7350'; g.fillRect(16, 118, 224, 6);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; return t;
};

export const createShip = (scene, colliders) => {
	const group = new THREE.Group(); group.name = 'shipInterior'; scene.add(group);
	const anchors = {}, interact = [], lights = [], occludable = [];
	const wallMat = new THREE.MeshStandardMaterial({ map: panelTex(), roughness: 0.8, metalness: 0.2 }); wallMat.map.repeat.set(2, 1);
	const floorMat = new THREE.MeshStandardMaterial({ color: 0x3b3128, roughness: 0.5, metalness: 0.3 });
	const ceilMat = new THREE.MeshStandardMaterial({ color: 0x1e1c19, roughness: 0.9 });
	const darkMat = new THREE.MeshStandardMaterial({ color: 0x24262b, roughness: 0.5, metalness: 0.6 });
	const amber = new THREE.MeshStandardMaterial({ color: 0xffc070, emissive: 0xff9a30, emissiveIntensity: 0 });
	const redMat = new THREE.MeshStandardMaterial({ color: 0xff3020, emissive: 0xff2010, emissiveIntensity: 2 });
	const box = (w, h, d, mat, x, y, z, solid = true, ry = 0) => {
		const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); m.rotation.y = ry; m.castShadow = m.receiveShadow = true; group.add(m);
		if (solid) { m.updateMatrixWorld(); colliders.push(new THREE.Box3().setFromObject(m)); occludable.push(m); }
		return m;
	};
	const doorsOnWall = (axis, at, lo, hi) => SHIP_DOORS.filter((d) => d.axis === axis && Math.abs(d.at - at) < 1e-3 && d.center > lo && d.center < hi);
	// wall along a boundary with gaps for doors; inset by WALL_T/2 toward the room interior (dir = +1/-1)
	const wall = (axis, at, lo, hi, dir) => {
		const gaps = doorsOnWall(axis, at, lo, hi).map((d) => [d.center - DOOR_W / 2, d.center + DOOR_W / 2]).sort((a, b) => a[0] - b[0]);
		const segs = []; let cur = lo;
		for (const [g0, g1] of gaps) { if (g0 > cur) segs.push([cur, g0]); cur = g1; }
		if (cur < hi) segs.push([cur, hi]);
		const c = at + dir * WALL_T / 2;
		for (const [a, b] of segs) axis === 'x' ? box(WALL_T, H, b - a, wallMat, c, H / 2, (a + b) / 2) : box(b - a, H, WALL_T, wallMat, (a + b) / 2, H / 2, c);
		for (const [g0, g1] of gaps) { const lint = H - DOOR_H; axis === 'x' ? box(WALL_T, lint, g1 - g0, wallMat, c, DOOR_H + lint / 2, (g0 + g1) / 2) : box(g1 - g0, lint, WALL_T, wallMat, (g0 + g1) / 2, DOOR_H + lint / 2, c); }
	};
	for (const r of SHIP_ROOMS) {
		const cx = (r.x0 + r.x1) / 2, cz = (r.z0 + r.z1) / 2, w = r.x1 - r.x0, d = r.z1 - r.z0;
		const floor = box(w + 0.8, 0.1, d + 0.8, floorMat, cx, -0.05, cz, false); floor.receiveShadow = true; // overlaps wall thickness so doorways have no floor gap
		box(w, 0.1, d, ceilMat, cx, H + 0.05, cz, false);
		wall('x', r.x0, r.z0, r.z1, +1); wall('x', r.x1, r.z0, r.z1, -1); wall('z', r.z0, r.x0, r.x1, +1); wall('z', r.z1, r.x0, r.x1, -1);
		// ceiling light strip (amber when powered) + emergency red
		const strip = box(Math.min(w, 3), 0.08, Math.min(d, 3) * 0.3, amber, cx, H - 0.06, cz, false);
		const l = new THREE.PointLight(0xffc890, 0, 14, 1.6); l.position.set(cx, H - 0.5, cz); l.userData.on = Math.min(26, 5 + w * d * 0.28); group.add(l); // scale by floor area so corridors don't blow out
		const em = new THREE.PointLight(0xff3020, 6, 9, 2); em.position.set(cx, H - 0.6, cz); group.add(em);
		lights.push({ l, em, strip });
		anchors[`${r.id}:RoomCenter`] = new THREE.Vector3(cx, 0, cz);
	}
	anchors['gate_room:RoomCenter'] = new THREE.Vector3(0, 0, 4);
	anchors['gate_room:GateFront'] = new THREE.Vector3(0, 0, -8);

	// --- doors
	const doorMat = new THREE.MeshStandardMaterial({ color: 0x4a4640, roughness: 0.6, metalness: 0.5 });
	const doors = SHIP_DOORS.map((d) => {
		const g = new THREE.Group(); group.add(g);
		const halves = [-1, 1].map((s) => { const m = new THREE.Mesh(new THREE.BoxGeometry(d.axis === 'x' ? 0.18 : DOOR_W / 2, DOOR_H, d.axis === 'x' ? DOOR_W / 2 : 0.18), doorMat); m.castShadow = m.receiveShadow = true; g.add(m); occludable.push(m); return { m, s }; });
		const lamp = new THREE.Mesh(new THREE.BoxGeometry(d.axis === 'x' ? 0.06 : 0.5, 0.12, d.axis === 'x' ? 0.5 : 0.06), redMat.clone()); g.add(lamp);
		if (d.axis === 'x') { g.position.set(d.at, 0, d.center); lamp.position.set(0.14, DOOR_H + 0.15, 0); } else { g.position.set(d.center, 0, d.at); lamp.position.set(0, DOOR_H + 0.15, 0.14); }
		const collider = new THREE.Box3(); colliders.push(collider);
		const state = { ...d, g, halves, lamp, open: 0, locked: true, sealed: false, collider };
		return state;
	});
	const setDoorCollider = (d) => {
		if (d.open > 0.6) { d.collider.min.set(1e6, 1e6, 1e6); d.collider.max.set(1e6, 1e6, 1e6); return; }
		const p = d.g.position;
		if (d.axis === 'x') d.collider.set(new THREE.Vector3(p.x - 0.2, 0, p.z - DOOR_W / 2), new THREE.Vector3(p.x + 0.2, DOOR_H, p.z + DOOR_W / 2));
		else d.collider.set(new THREE.Vector3(p.x - DOOR_W / 2, 0, p.z - 0.2), new THREE.Vector3(p.x + DOOR_W / 2, DOOR_H, p.z + 0.2));
	};
	doors.forEach(setDoorCollider);

	// --- power relay (gate room, beside the corridor door)
	const relay = box(1.2, 1.6, 0.25, darkMat, 3.2, 1.2, 13.6, true);
	const relayLamp = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.12, 0.05), redMat.clone()); relayLamp.position.set(3.2, 1.75, 13.45); group.add(relayLamp);
	anchors['gate_room:PowerRelay'] = new THREE.Vector3(3.2, 0, 12.8);

	// --- control room console (cardinal console facing the door)
	const console_ = box(2.6, 1.0, 1.0, darkMat, 0, 0.5, 35, true);
	const screen = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.05, 0.8), new THREE.MeshStandardMaterial({ color: 0xffe0a0, emissive: 0xffc060, emissiveIntensity: 0 })); screen.position.set(0, 1.03, 35); screen.rotation.x = -0.3; group.add(screen);
	anchors['control_interface_room:ControlConsole'] = new THREE.Vector3(0, 0, 33.6);
	for (const sx of [-1, 1]) box(1.2, 3.5, 1.2, darkMat, sx * 5.5, 1.75, 38.5, true); // pillars
	anchors['control_interface_room:Rush'] = new THREE.Vector3(3, 0, 33);

	// --- kino room: pedestal with orb + remote, locker with a vest
	const pedestal = box(0.7, 1.0, 0.7, darkMat, 7.5, 0.5, 20.75, true);
	const kinoOrb = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 14), new THREE.MeshStandardMaterial({ color: 0x555a60, roughness: 0.35, metalness: 0.8 })); kinoOrb.position.set(7.5, 1.2, 20.75); group.add(kinoOrb);
	const remote = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.3), new THREE.MeshStandardMaterial({ color: 0x8a7a5c, emissive: 0x2ad4ff, emissiveIntensity: 0.6, metalness: 0.7 })); remote.position.set(7.2, 1.03, 20.9); group.add(remote);
	anchors['eli_quarters:KinoPedestal'] = new THREE.Vector3(6.6, 0, 20.75);
	const locker = box(0.9, 2.2, 0.6, darkMat, 8.9, 1.1, 18.2, true);
	anchors['eli_quarters:Locker'] = new THREE.Vector3(8.5, 0, 19.2);
	box(2, 0.5, 1, floorMat, 3.2, 0.25, 23.5, true); // bed
	anchors['eli_quarters:Bed'] = new THREE.Vector3(3.2, 0, 22.5);

	// --- life support: CO2 scrubber panel on the far (west) wall
	const scrubber = box(0.4, 2.4, 2.2, darkMat, -9.1, 1.3, 19.2, true);
	const scrubLamp = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.5, 0.5), redMat.clone()); scrubLamp.position.set(-8.86, 2.2, 19.2); group.add(scrubLamp);
	const scrubBed = new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.2, 1.6), new THREE.MeshStandardMaterial({ color: 0x5a5245, roughness: 1 })); scrubBed.position.set(-8.88, 1.0, 19.2); group.add(scrubBed);
	anchors['life_support:Scrubber'] = new THREE.Vector3(-8.2, 0, 19.2);
	const waterTank = box(1.2, 2.0, 1.2, darkMat, -3.0, 1.0, 23.5, true);
	anchors['life_support:WaterTank'] = new THREE.Vector3(-3, 0, 22.4);

	// --- breached section: seal lever beside the jammed door, sparks + hull tear
	const lever = box(0.25, 0.9, 0.25, darkMat, -9.35, 1.2, 22.7, false); // on the life-support side of the jammed door
	const handle = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.5, 0.08), new THREE.MeshStandardMaterial({ color: 0xffd040, emissive: 0xff8000, emissiveIntensity: 1.5 })); handle.position.set(-9.35, 1.75, 22.7); handle.rotation.x = 0.6; group.add(handle);
	anchors['breached_section:SealLever'] = new THREE.Vector3(-8.6, 0, 22.7);
	const tear = new THREE.Mesh(new THREE.PlaneGeometry(3, 2.2), new THREE.MeshBasicMaterial({ color: 0x02030a })); tear.position.set(-17.4, 2.5, 20.75); tear.rotation.y = Math.PI / 2; group.add(tear);
	const breachLight = new THREE.PointLight(0x88aaff, 5, 10); breachLight.position.set(-14, 3, 20.75); group.add(breachLight);

	// --- gate room extras: supply crate + Brody's spot
	const crate = box(1.4, 0.9, 1.0, new THREE.MeshStandardMaterial({ color: 0x5e6a3a, roughness: 0.9 }), -4.6, 0.45, 10.5, true);
	anchors['gate_room:SupplyCrate'] = new THREE.Vector3(-4.6, 0, 9.3);
	anchors['gate_room:Brody'] = new THREE.Vector3(4.2, 0, 8.5);

	const state = { group, anchors, doors, occludable, powered: false };
	state.setPower = (on) => {
		state.powered = on;
		for (const { l, em, strip } of lights) { l.intensity = on ? l.userData.on : 0; em.intensity = on ? 0 : 6; strip.material.emissiveIntensity = on ? 1.6 : 0; }
		relayLamp.material.color.set(on ? 0x40ff80 : 0xff3020); relayLamp.material.emissive.set(on ? 0x20ff60 : 0xff2010);
		screen.material.emissiveIntensity = on ? 1.4 : 0;
		for (const d of doors) if (!d.jammed) { d.locked = !on; d.lamp.material.color.set(on ? 0x40ff80 : 0xff3020); d.lamp.material.emissive.set(on ? 0x20ff60 : 0xff2010); }
	};
	state.sealBreach = () => { const d = doors.find((x) => x.jammed); d.sealed = true; d.locked = true; d.lamp.material.color.set(0xffa020); d.lamp.material.emissive.set(0xff8000); handle.rotation.x = -0.6; breachLight.intensity = 0; };
	state.repairScrubber = () => { scrubLamp.material.color.set(0x40ff80); scrubLamp.material.emissive.set(0x20ff60); scrubBed.material.color.set(0xe8e2d0); };
	state.takeKino = () => { kinoOrb.visible = false; remote.visible = false; };
	/** Doors slide open when unlocked and the player is within 3 m. */
	state.update = (dt, playerPos) => {
		for (const d of doors) {
			const near = playerPos.distanceTo(d.g.position) < 3.2;
			const target = !d.locked && !d.sealed && near ? 1 : 0;
			const prev = d.open; d.open += (target - d.open) * Math.min(1, dt * 5);
			for (const { m, s } of d.halves) { const off = (DOOR_W / 4) + d.open * (DOOR_W / 2 + 0.05); if (d.axis === 'x') m.position.set(0, DOOR_H / 2, s * off); else m.position.set(s * off, DOOR_H / 2, 0); }
			if ((prev > 0.6) !== (d.open > 0.6)) setDoorCollider(d);
		}
	};
	state.update(0, new THREE.Vector3(0, 0, 100));
	state.roomAt = (p) => SHIP_ROOMS.find((r) => p.x >= r.x0 && p.x <= r.x1 && p.z >= r.z0 && p.z <= r.z1)?.id ?? (Math.abs(p.x) <= 7 && p.z >= -16 && p.z <= 14 ? 'gate_room' : null);
	return state;
};
