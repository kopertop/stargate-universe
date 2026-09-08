// Reusable interior components: each entry builds meshes + colliders at a world position and can expose named `parts`
// that ship state toggles (relay lamp, console screen, scrubber bed…) and an `anchor` point in front of it that quests and
// NPCs reference by name (`${roomId}:${spec.anchor}`). Specs come from the layout data (room.props) or the per-type
// defaults in ship.js; the map editor places the same specs. Positions are room-relative fractions (u, v) resolved by ship.js.
//   spec: { type, u, v, ry?, anchor?, id? }   ctx: { box, group, mats, parts, roomH }
// Convention: `ry` is the direction the prop's FRONT faces (0 = +z); the anchor (where the player stands) lies along it.
import * as THREE from 'three';

const fwd = (ry) => new THREE.Vector3(Math.sin(ry), 0, Math.cos(ry));
const lamp = (ctx, x, y, z, ry = 0, w = 0.6, h = 0.12) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.05), ctx.mats.red.clone()); m.position.set(x, y, z); m.rotation.y = ry; ctx.group.add(m); return m; };
const emissive = (color, intensity = 0) => new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: intensity });

/** Ancient glyph readout: header bar, columns of glyph clusters, a waveform. Blue on near-black; used as map + emissiveMap. */
const glyphScreen = () => {
	const W = 512, H = 224, c = document.createElement('canvas'); c.width = W; c.height = H; const g = c.getContext('2d');
	const bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, '#0b1b33'); bg.addColorStop(1, '#061020'); g.fillStyle = bg; g.fillRect(0, 0, W, H);
	g.fillStyle = 'rgba(80,170,255,0.35)'; g.fillRect(0, 0, W, 30); g.fillRect(0, H - 8, W, 8); g.fillStyle = 'rgba(80,170,255,0.12)'; g.fillRect(12, 42, 196, 164); g.fillRect(222, 42, 278, 164);
	g.strokeStyle = '#9fd8ff'; g.lineWidth = 4; g.lineCap = 'round';
	const glyph = (x, y, r) => { g.beginPath(); for (let k = 0; k < 3 + Math.floor(Math.random() * 3); k++) { const a = Math.random() * 6.3, b = a + 0.6 + Math.random() * 2; g.moveTo(x + Math.cos(a) * r, y + Math.sin(a) * r); g.lineTo(x + Math.cos(b) * r * (0.3 + Math.random() * 0.7), y + Math.sin(b) * r * (0.3 + Math.random() * 0.7)); } g.stroke(); if (Math.random() < 0.5) { g.beginPath(); g.arc(x, y, r * 0.3, 0, 7); g.stroke(); } };
	g.lineWidth = 3; for (let i = 0; i < 10; i++) glyph(28 + i * 30, 15, 9);
	g.lineWidth = 4; for (let col = 0; col < 3; col++) for (let row = 0; row < 4; row++) glyph(46 + col * 64 + (Math.random() - 0.5) * 6, 64 + row * 38, 13);
	g.strokeStyle = '#cfe9ff'; g.lineWidth = 3; g.beginPath(); for (let x = 232; x < W - 20; x += 4) g.lineTo(x, 100 + Math.sin(x * 0.07) * 20 * Math.sin(x * 0.011) + (Math.random() - 0.5) * 4); g.stroke();
	g.fillStyle = 'rgba(159,216,255,0.9)'; for (let i = 0; i < 16; i++) g.fillRect(236 + i * 16, 156 + Math.random() * 30, 10, 44 - Math.random() * 30);
	g.strokeStyle = '#ffb060'; g.lineWidth = 3; g.strokeRect(226, 46, W - 244, 156);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
};
/** Floating schematic: ship outline + a few blinking nodes (additive holo pane). */
const schematicScreen = () => {
	const W = 512, H = 212, c = document.createElement('canvas'); c.width = W; c.height = H; const g = c.getContext('2d');
	g.strokeStyle = 'rgba(120,200,255,0.9)'; g.lineWidth = 2; g.beginPath(); g.moveTo(30, 106); g.lineTo(120, 60); g.lineTo(420, 50); g.lineTo(490, 106); g.lineTo(420, 162); g.lineTo(120, 152); g.closePath(); g.stroke();
	g.strokeStyle = 'rgba(120,200,255,0.4)'; for (let x = 120; x < 420; x += 40) { g.beginPath(); g.moveTo(x, 58); g.lineTo(x, 155); g.stroke(); }
	g.fillStyle = 'rgba(255,170,80,0.9)'; for (let i = 0; i < 6; i++) { g.beginPath(); g.arc(140 + i * 55, 80 + (i % 2) * 50, 5, 0, 7); g.fill(); }
	g.fillStyle = 'rgba(120,200,255,0.8)'; g.font = '600 18px monospace'; g.fillText('DESTINY · DECK 0', 200, 30); g.fillText('FTL ▸ ▸ ▸', 380, 195);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
};

/** Olive supply-crate material with a stencilled label (one canvas per label, cached). */
const crateTexCache = {};
const crateMat = (ctx, label) => {
	if (!crateTexCache[label]) {
		const c = document.createElement('canvas'); c.width = 512; c.height = 256; const g = c.getContext('2d');
		g.fillStyle = '#5e6a3a'; g.fillRect(0, 0, 512, 256); for (let i = 0; i < 1800; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.12})`; g.fillRect(Math.random() * 512, Math.random() * 256, 2, 2 + Math.random() * 10); }
		g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 6; g.strokeRect(20, 20, 472, 216);
		g.fillStyle = 'rgba(20,24,16,0.85)'; g.font = '700 54px "Courier New", monospace'; g.textAlign = 'center'; g.fillText(label, 256, 120); g.font = '700 26px "Courier New", monospace'; g.fillText(label === 'SALVAGE' ? 'ICARUS BASE · LOT 7' : 'STARGATE COMMAND', 256, 170);
		g.fillStyle = 'rgba(220,180,60,0.8)'; g.beginPath(); g.moveTo(60, 220); g.lineTo(90, 220); g.lineTo(75, 196); g.fill();
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; crateTexCache[label] = new THREE.MeshStandardMaterial({ map: t, roughness: 0.9 });
	}
	return crateTexCache[label];
};

/** Registry. `size` (w, d in m) is the editor footprint; `build(ctx, p, spec)` places at world p = {x, z}, facing spec.ry. */
export const COMPONENTS = {
	console: {
		label: 'Console', size: [2.8, 1.4], defaultAnchor: 'Console',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			// plinth + sloped desk (trapezoid profile extruded across the width): dark Ancient stone-metal with a lit glyph face
			const shell = ctx.mats.shell;
			const plinth = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.72, 0.7), ctx.mats.dark); plinth.position.set(0, 0.36, 0.05); plinth.castShadow = plinth.receiveShadow = true; g.add(plinth);
			const prof = new THREE.Shape(); prof.moveTo(-0.6, 0.66); prof.lineTo(0.6, 0.66); prof.lineTo(0.6, 1.2); prof.lineTo(-0.6, 0.92); prof.lineTo(-0.6, 0.66); // side view (x = depth): low at the front (−z), high at the back
			const desk = new THREE.Mesh(new THREE.ExtrudeGeometry(prof, { depth: 2.6, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.02, bevelSegments: 1 }), shell); desk.rotation.y = -Math.PI / 2; desk.position.set(1.3, 0, 0); desk.castShadow = desk.receiveShadow = true; g.add(desk); // extrusion runs along -x from +1.3
			// glyph screen laid on the slope (tilted toward the operator), plus a floating holo pane above the back edge
			const slope = Math.atan2(0.30, 1.24);
			const screen = new THREE.Mesh(new THREE.PlaneGeometry(2.3, 1.0), new THREE.MeshStandardMaterial({ color: 0x102030, emissive: 0xffffff, emissiveIntensity: 0, roughness: 0.3, metalness: 0.2 })); screen.material.map = screen.material.emissiveMap = glyphScreen();
			screen.position.set(0, 1.13, 0.0); screen.rotation.set(-Math.PI / 2 - slope, 0, 0); g.add(screen); ctx.parts.screens.push(screen); // 4 cm proud of the bevelled slope
			const holo = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 0.7), new THREE.MeshBasicMaterial({ map: schematicScreen(), transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending })); holo.position.set(0, 1.8, 0.5); holo.rotation.set(0.15, Math.PI, 0); g.add(holo); // faces the operator at the low edge ctx.parts.holos.push(holo);
			for (const sx of [-1, 1]) { // side wings: angled panels with a small amber readout each
				const wing = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.14, 1.0), shell); wing.position.set(sx * 1.52, 0.98, 0.05); wing.rotation.z = sx * 0.3; wing.castShadow = true; g.add(wing);
				const rd = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.6), emissive(0xffa040, 1.2)); rd.position.set(sx * 1.55, 1.06, 0.05); rd.rotation.set(-Math.PI / 2, 0, 0); rd.rotateY(sx * 0.3); g.add(rd); ctx.parts.trims.push(rd);
			}
			const trim = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.03, 0.03), emissive(0xffa040, 1.2)); trim.position.set(0, 0.68, -0.6); g.add(trim); ctx.parts.trims.push(trim);
			ctx.box(2.6, 1.2, 1.0, ctx.mats.dark, p.x, 0.6, p.z, true, s.ry).visible = false; // collider only
			return { anchor: f.multiplyScalar(-1.4).add(new THREE.Vector3(p.x, 0, p.z)) }; // operator stands at the low front edge
		},
	},
	relay: {
		label: 'Power relay', size: [1.2, 0.3], defaultAnchor: 'PowerRelay',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			ctx.box(1.2, 1.7, 0.3, ctx.mats.shell, p.x, 1.2, p.z, true, s.ry);
			for (const [w, h, x, y] of [[1.1, 0.04, 0, 2.0], [1.1, 0.04, 0, 0.4], [0.04, 1.6, -0.53, 1.2], [0.04, 1.6, 0.53, 1.2]]) { const t = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.02), emissive(0xffa040, 0.5)); t.position.set(x, y, 0.16); g.add(t); ctx.parts.trims.push(t); } // panel frame lines
			const plate = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.3, 0.03), ctx.mats.dark); plate.position.set(0, 0.62, 0.16); g.add(plate); // lower blanking plate
			const bay = new THREE.Mesh(new THREE.BoxGeometry(0.62, 0.5, 0.12), new THREE.MeshStandardMaterial({ color: 0x06080c, roughness: 0.9 })); bay.position.set(0, 1.05, 0.12); g.add(bay); // recessed fuse bay
			for (const [i, c] of [0xff48b8, 0x33e6e0, 0xf2b838].entries()) { const w = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.34, 6), emissive(c, 0.9)); w.position.set(-0.2 + i * 0.2, 1.05, 0.2); w.rotation.z = Math.PI / 2; w.scale.z = 0.6; w.rotation.y = 0.9 - i * 0.9; g.add(w); } // jumper stubs
			const fuse = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.3, 12), new THREE.MeshStandardMaterial({ color: 0xd8b060, emissive: 0x6a4010, emissiveIntensity: 0.6, roughness: 0.35, metalness: 0.6 })); fuse.rotation.z = Math.PI / 2; fuse.position.set(0, 1.05, 0.15); fuse.visible = false; g.add(fuse);
			for (const sx of [-1, 1]) { const clip = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.14, 0.1), ctx.mats.steel); clip.position.set(sx * 0.17, 1.05, 0.15); g.add(clip); }
			const cover = new THREE.Group(); cover.position.set(0, 1.32, 0.19); g.add(cover); const cm = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.58, 0.03), ctx.mats.door); cm.position.y = -0.29; cover.add(cm); // hinged at the top edge
			ctx.parts.relayLamp = lamp(ctx, p.x + f.x * 0.17, 1.82, p.z + f.z * 0.17, s.ry, 0.5, 0.1);
			ctx.parts.relayFuse = fuse; ctx.parts.relayCover = cover;
			return { anchor: f.multiplyScalar(1.0).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	crate: {
		label: 'Supply crate', size: [1.4, 1.0], defaultAnchor: 'SupplyCrate',
		build: (ctx, p, s) => {
			const body = ctx.box(1.4, 0.78, 1.0, ctx.mats.crate, p.x, 0.39, p.z, true, s.ry); body.material = crateMat(ctx, s.loot ? 'SALVAGE' : 'SGC SUPPLY');
			for (const sx of [-0.45, 0.45]) { const strap = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.8, 1.02), ctx.mats.steel); strap.position.set(p.x, 0.39, p.z); strap.rotation.y = s.ry; strap.translateX(sx); ctx.group.add(strap); }
			const lid = new THREE.Group(); lid.position.set(p.x, 0.78, p.z); lid.rotation.y = s.ry; ctx.group.add(lid); // hinge on the back edge
			const top = new THREE.Mesh(new THREE.BoxGeometry(1.44, 0.12, 1.04), ctx.mats.crate); top.position.set(0, 0.06, 0.52); top.castShadow = true; lid.add(top); lid.position.add(fwd(s.ry).multiplyScalar(-0.52));
			for (const sx of [-1, 1]) { const strap = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.13, 1.06), ctx.mats.steel); strap.position.set(sx * 0.45, 0.06, 0.52); lid.add(strap); }
			return { anchor: fwd(s.ry).multiplyScalar(1.2).add(new THREE.Vector3(p.x, 0, p.z)), lid, loot: s.loot };
		},
	},
	bed: {
		label: 'Bed', size: [2.0, 1.0], defaultAnchor: 'Bed',
		build: (ctx, p, s) => { ctx.box(2, 0.5, 1, ctx.mats.floor, p.x, 0.25, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	med_bed: {
		label: 'Med bed', size: [2.0, 0.9], defaultAnchor: 'Beds',
		build: (ctx, p, s) => { ctx.box(2.0, 0.6, 0.9, ctx.mats.steel, p.x, 0.3, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	locker: {
		label: 'Locker', size: [0.9, 0.6], defaultAnchor: 'Locker',
		build: (ctx, p, s) => { ctx.box(0.9, 2.2, 0.6, ctx.mats.dark, p.x, 1.1, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(0.9).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	cabinet: {
		label: 'Cabinet', size: [1.8, 0.5],
		build: (ctx, p, s) => { ctx.box(1.8, 2.0, 0.5, ctx.mats.dark, p.x, 1.0, p.z, true, s.ry); return {}; },
	},
	pillar: {
		label: 'Pillar', size: [1.2, 1.2],
		build: (ctx, p, s) => { const H = ctx.roomH - 0.2; ctx.box(1.2, H, 1.2, ctx.mats.dark, p.x, H / 2, p.z, true, s.ry); return {}; },
	},
	kino_pedestal: {
		label: 'Kino pedestal', size: [0.7, 0.7], defaultAnchor: 'KinoPedestal',
		build: (ctx, p, s) => {
			ctx.box(0.7, 1.0, 0.7, ctx.mats.dark, p.x, 0.5, p.z, true, s.ry);
			const orb = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 14), new THREE.MeshStandardMaterial({ color: 0x555a60, roughness: 0.35, metalness: 0.8 })); orb.position.set(p.x, 1.2, p.z); ctx.group.add(orb);
			const remote = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.3), new THREE.MeshStandardMaterial({ color: 0x8a7a5c, emissive: 0x2ad4ff, emissiveIntensity: 0.6, metalness: 0.7 })); remote.position.set(p.x - 0.3, 1.03, p.z + 0.15); ctx.group.add(remote);
			ctx.parts.kino = [orb, remote];
			return { anchor: fwd(s.ry).multiplyScalar(1.0).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	scrubber: {
		label: 'CO2 scrubber', size: [2.2, 0.4], defaultAnchor: 'Scrubber',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), side = new THREE.Vector3(-f.z, 0, f.x);
			ctx.box(2.2, 2.4, 0.4, ctx.mats.dark, p.x, 1.3, p.z, true, s.ry);
			const sl = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.06), ctx.mats.red.clone()); sl.position.set(p.x + f.x * 0.24, 2.2, p.z + f.z * 0.24); sl.rotation.y = s.ry; ctx.group.add(sl);
			const bed = new THREE.Mesh(new THREE.BoxGeometry(1.6, 1.2, 0.1), new THREE.MeshStandardMaterial({ color: 0x5a5245, roughness: 1 })); bed.position.set(p.x + f.x * 0.22, 1.0, p.z + f.z * 0.22); bed.rotation.y = s.ry; ctx.group.add(bed);
			ctx.parts.scrubLamp = sl; ctx.parts.scrubBed = bed; void side;
			return { anchor: f.multiplyScalar(1.0).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	tank: {
		label: 'Water tank', size: [1.2, 1.2], defaultAnchor: 'WaterTank',
		build: (ctx, p, s) => { ctx.box(1.2, 2.0, 1.2, ctx.mats.dark, p.x, 1.0, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	elevator_door: {
		label: 'Elevator door', size: [2.6, 0.3], defaultAnchor: 'Elevator',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			ctx.box(2.6, 3.4, 0.3, ctx.mats.shell, p.x, 1.7, p.z, true, s.ry); // frame block (collider)
			for (const sx of [-1, 1]) { const leaf = new THREE.Mesh(new THREE.BoxGeometry(1.1, 3.0, 0.08), ctx.mats.door); leaf.position.set(sx * 0.58, 1.5, 0.19); g.add(leaf); }
			const seam = new THREE.Mesh(new THREE.BoxGeometry(0.04, 3.0, 0.02), emissive(0xffa040, 0.5)); seam.position.set(0, 1.5, 0.24); g.add(seam); ctx.parts.trims.push(seam);
			const header = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.18, 0.04), emissive(0xffa040, 0.5)); header.position.set(0, 3.15, 0.22); g.add(header); ctx.parts.trims.push(header);
			const panel = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.7, 0.08), ctx.mats.dark); panel.position.set(1.6, 1.3, 0.19); g.add(panel); // call panel + fuse bay beside the doors
			const ind = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.04, 0.02), ctx.mats.red.clone()); ind.position.set(1.6, 1.6, 0.24); g.add(ind);
			const fuses = [-0.09, 0, 0.09].map((dx, i) => { const f = new THREE.Mesh(new THREE.CylinderGeometry(i === 1 ? 0.035 : 0.025, i === 1 ? 0.035 : 0.025, 0.2, 10), new THREE.MeshStandardMaterial({ color: 0xd8b060, emissive: 0x6a4010, emissiveIntensity: 0.6, roughness: 0.35, metalness: 0.6 })); f.position.set(1.6 + dx, 1.15, 0.24); f.visible = false; g.add(f); return f; });
			ctx.parts.elevators.push({ lamp: ind, fuses, leaves: g.children.filter((m) => m.geometry?.parameters?.width === 1.1) });
			return { anchor: f.multiplyScalar(1.2).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	breach: {
		label: 'Hull breach', size: [3.2, 0.1],
		build: (ctx, p, s) => {
			const tear = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 2.4), new THREE.MeshBasicMaterial({ color: 0x02030a })); tear.position.set(p.x, 2.6, p.z); tear.rotation.y = s.ry; ctx.group.add(tear);
			if (s.active !== false) { const l = new THREE.PointLight(0x88aaff, 6, 12); const f = fwd(s.ry); l.position.set(p.x + f.x * 2.5, 3, p.z + f.z * 2.5); ctx.group.add(l); ctx.parts.breachLight = l; }
			return {};
		},
	},
	wall_light: {
		label: 'Wall light', size: [0.1, 0.6],
		build: (ctx, p, s) => { const m = new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.6, 0.06), ctx.mats.slit); m.position.set(p.x, 2.0, p.z); m.rotation.y = s.ry; ctx.group.add(m); return {}; },
	},
	grow_bed: {
		label: 'Grow bed', size: [3.0, 1.2], defaultAnchor: 'GrowBed',
		build: (ctx, p, s) => { // raised planter with dark soil and a lamp bar above it; the lamp lights up when hydroponics is restored
			const g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			ctx.box(3.0, 0.7, 1.2, ctx.mats.shell, p.x, 0.35, p.z, true, s.ry);
			const soil = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.08, 1.0), new THREE.MeshStandardMaterial({ color: 0x2a2018, roughness: 1 })); soil.position.set(0, 0.72, 0); g.add(soil);
			for (let i = 0; i < 7; i++) { const sprout = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.18, 5), new THREE.MeshStandardMaterial({ color: 0x4f7a3a, roughness: 0.9 })); sprout.position.set(-1.2 + i * 0.4, 0.85, (i % 2 ? 0.2 : -0.2)); sprout.visible = false; g.add(sprout); ctx.parts.sprouts.push(sprout); }
			for (const sx of [-1.35, 1.35]) { const post = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.3, 0.06), ctx.mats.dark); post.position.set(sx, 1.35, 0); g.add(post); }
			const lampBar = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.06, 0.3), new THREE.MeshStandardMaterial({ color: 0xd8ffd0, emissive: 0xa8ff9a, emissiveIntensity: 0 })); lampBar.position.set(0, 2.0, 0); g.add(lampBar); ctx.parts.growLamps.push(lampBar);
			return { anchor: fwd(s.ry).multiplyScalar(1.3).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	marker: {
		label: 'Anchor marker', size: [0.6, 0.6], defaultAnchor: 'Spot',
		build: (ctx, p) => ({ anchor: new THREE.Vector3(p.x, 0, p.z) }), // invisible: NPC stand spot / waypoint
	},
};

/** Default furniture per room type, as room-relative specs (used when the layout row has no `props`). */
export const DEFAULT_PROPS = {
	gate_room: [{ type: 'relay', u: 0.68, v: 0.989, ry: Math.PI }, { type: 'crate', u: 0.25, v: 0.86, ry: Math.PI },
		{ type: 'crate', u: 0.84, v: 0.95, ry: Math.PI, anchor: 'Salvage1', loot: [{ id: 'large_fuse' }] }, { type: 'crate', u: 0.93, v: 0.95, ry: Math.PI, anchor: 'Salvage2', loot: [{ id: 'rations', n: 3 }] }, { type: 'crate', u: 0.955, v: 0.78, ry: -Math.PI / 2, anchor: 'Salvage3', loot: [{ id: 'small_fuse' }] }, { type: 'marker', u: 0.73, v: 0.8, anchor: 'Brody' }, { type: 'marker', u: 0.325, v: 0.725, anchor: 'Scott' }],
	control_room: [{ type: 'console', u: 0.5, v: 0.53, ry: Math.PI, anchor: 'ControlConsole' }, { type: 'marker', u: 0.6, v: 0.52, anchor: 'Rush' }, { type: 'pillar', u: 0.2, v: 0.2 }, { type: 'pillar', u: 0.8, v: 0.2 }, { type: 'pillar', u: 0.2, v: 0.8 }, { type: 'pillar', u: 0.8, v: 0.8 }],
	quarters: [{ type: 'bed', u: 0.15, v: 0.5, ry: Math.PI / 2 }, { type: 'locker', u: 0.92, v: 0.3, ry: -Math.PI / 2 }],
	storage: [{ type: 'crate', u: 0.2, v: 0.25, ry: 0.3 }, { type: 'crate', u: 0.35, v: 0.3, ry: 1.1 }, { type: 'crate', u: 0.75, v: 0.7, ry: 2.4 }, { type: 'crate', u: 0.8, v: 0.3, ry: 0.8 }],
	infirmary: [{ type: 'med_bed', u: 0.25, v: 0.3, anchor: 'Beds' }, { type: 'med_bed', u: 0.25, v: 0.5 }, { type: 'med_bed', u: 0.25, v: 0.7 }, { type: 'cabinet', u: 0.85, v: 0.5, ry: -Math.PI / 2 }],
	elevator: [{ type: 'elevator_door', u: 0.5, v: 0.04, ry: 0, anchor: 'Elevator' }],
	'shuttle-dock': [{ type: 'breach', u: 0.99, v: 0.5, ry: -Math.PI / 2 }],
	hydroponics: [{ type: 'console', u: 0.5, v: 0.12, ry: Math.PI, anchor: 'GrowConsole' }, { type: 'tank', u: 0.08, v: 0.9 }, { type: 'tank', u: 0.92, v: 0.9 }, { type: 'grow_bed', u: 0.25, v: 0.4, ry: Math.PI / 2 }, { type: 'grow_bed', u: 0.25, v: 0.62, ry: Math.PI / 2 }, { type: 'grow_bed', u: 0.75, v: 0.4, ry: Math.PI / 2 }, { type: 'grow_bed', u: 0.75, v: 0.62, ry: Math.PI / 2 }, { type: 'grow_bed', u: 0.5, v: 0.5, ry: Math.PI / 2 }],
};
/** Room-specific overrides by id (the Kino Room, the scrubber's corridor). */
export const ROOM_PROPS = {
	eli_quarters: [{ type: 'kino_pedestal', u: 0.5, v: 0.3, ry: 0, anchor: 'KinoPedestal' }, { type: 'locker', u: 0.955, v: 0.75, ry: -Math.PI / 2, anchor: 'Locker' }, { type: 'bed', u: 0.11, v: 0.75, ry: Math.PI / 2, anchor: 'Bed' }],
	south_corridor: [{ type: 'scrubber', u: 0.953, v: 0.5585, ry: -Math.PI / 2, anchor: 'Scrubber' }],
	sealed_section_north: [{ type: 'breach', u: 0.99, v: 0.5, ry: -Math.PI / 2, active: false }],
	elevator_room_floor_1: [{ type: 'elevator_door', u: 0.96, v: 0.5, ry: -Math.PI / 2, anchor: 'Elevator' }], // the room's only doorway is on the −z wall
	aft_storage_hall: [{ type: 'crate', u: 0.18, v: 0.2, ry: 0.3, anchor: 'Salvage1', loot: [{ id: 'bus_fuse' }] }, { type: 'crate', u: 0.4, v: 0.25, ry: 1.1, anchor: 'Salvage2', loot: [{ id: 'rations', n: 2 }] }, { type: 'crate', u: 0.75, v: 0.7, ry: 2.4, anchor: 'Salvage3', loot: [{ id: 'bus_fuse' }] }, { type: 'crate', u: 0.82, v: 0.28, ry: 0.8 }],
	infirmary: [{ type: 'med_bed', u: 0.25, v: 0.3, anchor: 'Beds' }, { type: 'med_bed', u: 0.25, v: 0.5 }, { type: 'med_bed', u: 0.25, v: 0.7 }, { type: 'cabinet', u: 0.85, v: 0.5, ry: -Math.PI / 2 }, { type: 'crate', u: 0.8, v: 0.85, ry: Math.PI, anchor: 'Salvage1', loot: [{ id: 'large_fuse' }] }],
};
