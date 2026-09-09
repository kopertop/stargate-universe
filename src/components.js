// Reusable interior components: each entry builds meshes + colliders at a world position and can expose named `parts`
// that ship state toggles (relay lamp, console screen, scrubber bed…) and an `anchor` point in front of it that quests and
// NPCs reference by name (`${roomId}:${spec.anchor}`). Specs come from the layout data (room.props) or the per-type
// defaults in ship.js; the map editor places the same specs. Positions are room-relative fractions (u, v) resolved by ship.js.
//   spec: { type, u, v, ry?, anchor?, id?, loot?, style? }   ctx: { box, group, mats, parts, roomH }
// Convention: `ry` is the direction the prop's FRONT faces (0 = +z); the anchor (where the player stands) lies along it.
import * as THREE from 'three';

const fwd = (ry) => new THREE.Vector3(Math.sin(ry), 0, Math.cos(ry));
const lamp = (ctx, x, y, z, ry = 0, w = 0.6, h = 0.12) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.05), ctx.mats.red.clone()); m.position.set(x, y, z); m.rotation.y = ry; ctx.group.add(m); return m; };
const emissive = (color, intensity = 0) => new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: intensity });

/** Ancient key panel: a header readout, a grid of backlit stone key-tiles each carrying a glyph, a waveform column.
 *  Blue on near-black with a couple of amber "active" keys; used as map + emissiveMap so it only glows when powered. */
const glyph = (g, x, y, r) => { g.beginPath(); for (let k = 0; k < 3 + Math.floor(Math.random() * 3); k++) { const a = Math.random() * 6.3, b = a + 0.6 + Math.random() * 2; g.moveTo(x + Math.cos(a) * r, y + Math.sin(a) * r); g.lineTo(x + Math.cos(b) * r * (0.3 + Math.random() * 0.7), y + Math.sin(b) * r * (0.3 + Math.random() * 0.7)); } g.stroke(); if (Math.random() < 0.5) { g.beginPath(); g.arc(x, y, r * 0.3, 0, 7); g.stroke(); } };
const glyphScreen = () => {
	const W = 768, H = 320, c = document.createElement('canvas'); c.width = W; c.height = H; const g = c.getContext('2d');
	const bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, '#08131f'); bg.addColorStop(1, '#040a12'); g.fillStyle = bg; g.fillRect(0, 0, W, H);
	g.fillStyle = 'rgba(80,170,255,0.18)'; g.fillRect(0, 0, W, 44); g.fillStyle = 'rgba(80,170,255,0.5)'; g.fillRect(0, 44, W, 2);
	g.strokeStyle = '#9fd8ff'; g.lineWidth = 3; g.lineCap = 'round'; for (let i = 0; i < 12; i++) glyph(g, 26 + i * 34, 22, 9);
	g.fillStyle = 'rgba(255,170,80,0.85)'; for (let i = 0; i < 5; i++) g.fillRect(560 + i * 40, 14, 26, 16); g.fillStyle = 'rgba(255,170,80,0.35)'; g.fillRect(560, 34, 186, 3);
	const cols = 8, rows = 3, tw = 62, th = 70, gap = 6, x0 = 16, y0 = 60, lit = new Set([Math.floor(Math.random() * cols * rows), Math.floor(Math.random() * cols * rows)]);
	for (let r = 0; r < rows; r++) for (let cI = 0; cI < cols; cI++) { // key tiles: dark stone, blue rim glow, glyph; two keys are lit amber
		const x = x0 + cI * (tw + gap), y = y0 + r * (th + gap), on = lit.has(r * cols + cI);
		g.fillStyle = 'rgba(70,150,255,0.10)'; g.beginPath(); g.roundRect(x - 2, y - 2, tw + 4, th + 4, 8); g.fill();
		g.fillStyle = on ? '#4a3418' : '#141d28'; g.beginPath(); g.roundRect(x, y, tw, th, 6); g.fill();
		g.strokeStyle = on ? '#ffb060' : 'rgba(110,190,255,0.7)'; g.lineWidth = 2; g.stroke();
		g.strokeStyle = on ? '#ffd9a0' : '#bfe4ff'; g.lineWidth = 3.5; glyph(g, x + tw / 2, y + th / 2, 15);
	}
	const rx = x0 + cols * (tw + gap) + 8; g.strokeStyle = '#ffb060'; g.lineWidth = 3; g.strokeRect(rx, 60, W - rx - 14, H - 74); // readout column
	g.strokeStyle = '#cfe9ff'; g.lineWidth = 3; g.beginPath(); for (let x = rx + 10; x < W - 24; x += 4) g.lineTo(x, 130 + Math.sin(x * 0.07) * 24 * Math.sin(x * 0.011) + (Math.random() - 0.5) * 4); g.stroke();
	g.fillStyle = 'rgba(159,216,255,0.9)'; for (let i = 0; i < 9; i++) g.fillRect(rx + 12 + i * 20, 210 + Math.random() * 40, 12, 80 - Math.random() * 40);
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

/** Case materials shared by every crate: Earth polymer (Pelican-style) and its hardware, Ancient cavity glow. */
const caseMats = { poly: new THREE.MeshStandardMaterial({ color: 0x4d5538, roughness: 0.8, metalness: 0.05 }), foam: new THREE.MeshStandardMaterial({ color: 0x1e1f1e, roughness: 1 }),
	hw: new THREE.MeshStandardMaterial({ color: 0x9aa0a6, roughness: 0.45, metalness: 0.7 }), cavity: new THREE.MeshStandardMaterial({ color: 0x0a1420, emissive: 0x1a3c5c, emissiveIntensity: 0.6, roughness: 1 }) };
/** Stencilled label decal (transparent canvas, one per label, cached): white military stencil for the Earth cases. */
const stencilCache = {};
const stencil = (label, sub) => {
	if (!stencilCache[label]) {
		const c = document.createElement('canvas'); c.width = 512; c.height = 256; const g = c.getContext('2d');
		g.fillStyle = 'rgba(235,235,225,0.9)'; g.textAlign = 'center'; g.font = '700 74px "Courier New", monospace'; g.fillText(label, 256, 120);
		g.font = '700 30px "Courier New", monospace'; g.fillText(sub, 256, 172); g.fillStyle = 'rgba(220,180,60,0.9)'; g.beginPath(); g.moveTo(60, 226); g.lineTo(96, 226); g.lineTo(78, 196); g.fill();
		g.strokeStyle = 'rgba(235,235,225,0.6)'; g.lineWidth = 4; g.strokeRect(20, 40, 472, 200);
		const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; stencilCache[label] = new THREE.MeshBasicMaterial({ map: t, transparent: true, polygonOffset: true, polygonOffsetFactor: -1 });
	}
	return stencilCache[label];
};
/** Ancient glyph plate: three glyphs on a dark strip (blue emissive, toggled with ship power via parts.trims). */
const glyphPlate = () => {
	const c = document.createElement('canvas'); c.width = 256; c.height = 64; const g = c.getContext('2d');
	g.fillStyle = '#0a1622'; g.fillRect(0, 0, 256, 64); g.strokeStyle = '#8fd0ff'; g.lineWidth = 4; g.lineCap = 'round'; for (let i = 0; i < 3; i++) glyph(g, 60 + i * 68, 32, 18);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return new THREE.MeshStandardMaterial({ map: t, emissiveMap: t, emissive: 0xffffff, emissiveIntensity: 1.0, roughness: 0.4 });
};
/** Hollow open-topped box: floor + four walls, so the cavity reads as a real hole once the lid moves. */
const hollowBox = (g, w, h, d, t, mat, y = 0) => {
	const add = (sx, sy, sz, x, yy, z) => { const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mat); m.position.set(x, yy, z); m.castShadow = m.receiveShadow = true; g.add(m); return m; };
	add(w, t, d, 0, y + t / 2, 0); add(w, h, t, 0, y + h / 2, -d / 2 + t / 2); add(w, h, t, 0, y + h / 2, d / 2 - t / 2); add(t, h, d, -w / 2 + t / 2, y + h / 2, 0); add(t, h, d, w / 2 - t / 2, y + h / 2, 0);
};
const ease = (k) => k * k * (3 - 2 * k);

/** Registry. `size` (w, d in m) is the editor footprint; `build(ctx, p, spec)` places at world p = {x, z}, facing spec.ry. */
export const COMPONENTS = {
	console: {
		label: 'Console', size: [3.0, 1.5], defaultAnchor: 'Console',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			// SGU control console: foot plate, flared four-sided pedestal in engraved Ancient plate, a smooth sloped desk carrying the
			// backlit key panel, angled side wings with amber readouts, a back spine that projects the holo. Operator stands at −z.
			const desk = new THREE.MeshStandardMaterial({ color: 0x1c2229, roughness: 0.35, metalness: 0.65 }), blue = () => emissive(0x3a86c8, 0.8);
			const foot = new THREE.Mesh(new THREE.BoxGeometry(2.3, 0.08, 0.95), ctx.mats.dark); foot.position.y = 0.04; foot.receiveShadow = true; g.add(foot);
			const ped = new THREE.Mesh(new THREE.CylinderGeometry(1, 0.72, 0.72, 4, 1), ctx.mats.dark); ped.rotation.y = Math.PI / 4; ped.scale.set(1.77, 1, 0.72); ped.position.y = 0.44; ped.castShadow = ped.receiveShadow = true; g.add(ped);
			for (const sx of [-1, 1]) { const slit = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.42, 0.03), blue()); slit.position.set(sx * 0.62, 0.46, -0.44); slit.rotation.x = -0.19; g.add(slit); ctx.parts.trims.push(slit); } // pedestal front slits
			const prof = new THREE.Shape(); prof.moveTo(-0.62, 0.78); prof.lineTo(0.62, 0.78); prof.lineTo(0.62, 1.22); prof.lineTo(-0.62, 0.92); prof.lineTo(-0.62, 0.78); // side view (x = depth): low at the front, high at the back
			const top = new THREE.Mesh(new THREE.ExtrudeGeometry(prof, { depth: 2.8, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.02, bevelSegments: 1 }), desk); top.rotation.y = -Math.PI / 2; top.position.set(1.4, 0, 0); top.castShadow = top.receiveShadow = true; g.add(top);
			const slope = Math.atan2(0.30, 1.24), sg = new THREE.Group(); sg.position.set(0, 1.095, 0); sg.rotation.x = -slope; g.add(sg); // everything on the slope lives in this tilted frame
			const screen = new THREE.Mesh(new THREE.PlaneGeometry(2.3, 0.96), new THREE.MeshStandardMaterial({ color: 0x102030, emissive: 0xffffff, emissiveIntensity: 0, roughness: 0.3, metalness: 0.2 })); screen.material.map = screen.material.emissiveMap = glyphScreen();
			screen.rotation.x = -Math.PI / 2; screen.position.set(0, 0.03, 0.02); sg.add(screen); ctx.parts.screens.push(screen);
			for (const [w, d, x, z] of [[2.44, 0.05, 0, -0.485], [2.44, 0.05, 0, 0.525], [0.05, 1.06, -1.195, 0.02], [0.05, 1.06, 1.195, 0.02]]) { const bz = new THREE.Mesh(new THREE.BoxGeometry(w, 0.025, d), blue()); bz.position.set(x, 0.035, z); sg.add(bz); ctx.parts.trims.push(bz); } // lit bezel
			const spine = new THREE.Mesh(new THREE.BoxGeometry(2.9, 0.42, 0.22), desk); spine.position.set(0, 1.36, 0.63); spine.castShadow = true; g.add(spine);
			const emit = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.03, 0.02), blue()); emit.position.set(0, 1.5, 0.515); g.add(emit); ctx.parts.trims.push(emit);
			const holo = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 0.7), new THREE.MeshBasicMaterial({ map: schematicScreen(), transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending })); holo.position.set(0, 2.05, 0.58); holo.rotation.set(0.15, Math.PI, 0); g.add(holo); ctx.parts.holos.push(holo); // faces the operator
			for (const sx of [-1, 1]) { // side wings: drooping facets with an amber readout strip
				const wg = new THREE.Group(); wg.position.set(sx * 1.66, 1.0, 0); wg.rotation.z = -sx * 0.32; g.add(wg);
				const wing = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.12, 1.12), desk); wing.castShadow = true; wg.add(wing);
				const rd = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.84), emissive(0xffa040, 1.2)); rd.position.set(0, 0.065, 0); rd.rotation.x = -Math.PI / 2; wg.add(rd); ctx.parts.trims.push(rd);
			}
			const trim = new THREE.Mesh(new THREE.BoxGeometry(2.5, 0.03, 0.03), emissive(0xffa040, 1.2)); trim.position.set(0, 0.9, -0.64); g.add(trim); ctx.parts.trims.push(trim); // front apron light
			ctx.box(2.9, 1.3, 1.3, ctx.mats.dark, p.x, 0.65, p.z, true, s.ry).visible = false; // collider only
			return { anchor: f.multiplyScalar(-1.5).add(new THREE.Vector3(p.x, 0, p.z)) }; // operator stands at the low front edge
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
		label: 'Supply crate', size: [1.5, 1.0], defaultAnchor: 'SupplyCrate',
		build: (ctx, p, s) => {
			// Two cases share one component. `style` defaults from the loot: Ancient parts (fuses) sit in Destiny's own salvage
			// containers — angular engraved boxes whose lid lifts and slides aside; everything from Earth is a stencilled Pelican-style
			// case whose lid hinges up at the back. Both are hollow so the opening reads. `setOpen(k)` animates 0→1 (ship.update).
			const f = fwd(s.ry), g = new THREE.Group(); g.position.set(p.x, 0, p.z); g.rotation.y = s.ry; ctx.group.add(g);
			const style = s.style ?? (s.loot?.some((it) => /fuse/.test(it.id)) ? 'ancient' : 'pelican');
			let setOpen;
			if (style === 'pelican') {
				const W = 1.3, H = 0.62, D = 0.9, T = 0.05;
				hollowBox(g, W, H, D, T, caseMats.poly);
				const foam = new THREE.Mesh(new THREE.BoxGeometry(W - 2 * T, 0.05, D - 2 * T), caseMats.foam); foam.position.y = T + 0.025; g.add(foam);
				for (const y of [0.16, 0.34, 0.52]) { const rib = new THREE.Mesh(new THREE.BoxGeometry(W + 0.03, 0.04, D + 0.03), caseMats.poly); rib.position.y = y; g.add(rib); } // moulded ridges
				for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { const bump = new THREE.Mesh(new THREE.BoxGeometry(0.1, H + 0.02, 0.1), caseMats.poly); bump.position.set(sx * (W / 2 - 0.03), H / 2, sz * (D / 2 - 0.03)); g.add(bump); } // corner bumpers
				for (const sx of [-0.42, 0.42]) { // press latches: a plate on the body and a raised bar that reads as the pull
					const plate = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.22, 0.03), caseMats.hw); plate.position.set(sx, H - 0.12, D / 2 + 0.015); g.add(plate);
					const bar = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.06, 0.05), caseMats.hw); bar.position.set(sx, H - 0.19, D / 2 + 0.04); g.add(bar);
				}
				const handle = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.05, 0.06), caseMats.hw); handle.position.set(0, 0.13, D / 2 + 0.04); g.add(handle); // fold-down carry handle, below the label
				const label = new THREE.Mesh(new THREE.PlaneGeometry(0.56, 0.28), stencil('SGC', 'ICARUS BASE · LOT 7')); label.position.set(0, 0.36, D / 2 + 0.001); g.add(label);
				const lid = new THREE.Group(); lid.position.set(0, H, -D / 2); g.add(lid); // hinged at the back edge
				const cap = new THREE.Mesh(new THREE.BoxGeometry(W + 0.04, 0.12, D + 0.04), caseMats.poly); cap.position.set(0, 0.06, D / 2); cap.castShadow = true; lid.add(cap);
				const ridge = new THREE.Mesh(new THREE.BoxGeometry(W - 0.3, 0.03, D - 0.3), caseMats.poly); ridge.position.set(0, 0.13, D / 2); lid.add(ridge);
				for (const sx of [-0.42, 0.42]) { const hook = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.1, 0.03), caseMats.hw); hook.position.set(sx, 0.05, D + 0.015); lid.add(hook); }
				const top = new THREE.Mesh(new THREE.PlaneGeometry(0.62, 0.31), stencil('SGC', 'ICARUS BASE · LOT 7')); top.position.set(0, 0.146, D / 2); top.rotation.x = -Math.PI / 2; lid.add(top);
				setOpen = (k) => { lid.rotation.x = -1.95 * ease(k); };
				ctx.box(W + 0.1, H + 0.12, D + 0.1, ctx.mats.dark, p.x, (H + 0.12) / 2, p.z, true, s.ry).visible = false;
			} else {
				const W = 1.5, H = 0.8, D = 1.0, T = 0.07;
				const base = new THREE.Mesh(new THREE.BoxGeometry(W - 0.16, 0.08, D - 0.16), ctx.mats.dark); base.position.y = 0.04; g.add(base); // chamfered foot
				hollowBox(g, W, H, D, T, ctx.mats.dark, 0.08);
				const glow = new THREE.Mesh(new THREE.PlaneGeometry(W - 2 * T - 0.02, D - 2 * T - 0.02), caseMats.cavity); glow.rotation.x = -Math.PI / 2; glow.position.y = 0.08 + T + 0.002; g.add(glow); // lit cavity floor
				for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { const post = new THREE.Mesh(new THREE.BoxGeometry(0.13, H + 0.1, 0.13), ctx.mats.shell); post.position.set(sx * (W / 2 - 0.04), 0.08 + H / 2, sz * (D / 2 - 0.04)); post.castShadow = true; g.add(post); } // corner frame
				for (const [w, d, x, z] of [[W, 0.02, 0, -D / 2 - 0.005], [W, 0.02, 0, D / 2 + 0.005], [0.02, D, -W / 2 - 0.005, 0], [0.02, D, W / 2 + 0.005, 0]]) { const seam = new THREE.Mesh(new THREE.BoxGeometry(w, 0.02, d), emissive(0x3a86c8, 0.8)); seam.position.set(x, 0.08 + H - 0.1, z); g.add(seam); ctx.parts.trims.push(seam); } // blue seam below the rim
				const plate = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.125), glyphPlate()); plate.position.set(0, 0.45, D / 2 + 0.003); g.add(plate); ctx.parts.trims.push(plate);
				const lid = new THREE.Group(); lid.position.set(0, 0.08 + H, 0); g.add(lid); // rises on four corner risers, then splits like the ship's doors
				for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { const riser = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.34, 0.08), ctx.mats.shell); riser.position.set(sx * (W / 2 - 0.04), -0.17 + 0.05, sz * (D / 2 - 0.04)); lid.add(riser); }
				const halves = [-1, 1].map((sx) => {
					const h = new THREE.Group(); lid.add(h);
					const slab = new THREE.Mesh(new THREE.BoxGeometry(W / 2 + 0.01, 0.1, D + 0.02), ctx.mats.dark); slab.position.set(sx * (W / 4 + 0.005), 0.05, 0); slab.castShadow = true; h.add(slab);
					const ridge = new THREE.Mesh(new THREE.BoxGeometry(W * 0.3, 0.07, D * 0.5), ctx.mats.shell); ridge.position.set(sx * W * 0.15, 0.13, 0); h.add(ridge); // faceted centre ridge, split by the seam
					const cap = new THREE.Mesh(new THREE.PlaneGeometry(0.22, 0.11), glyphPlate()); cap.position.set(sx * W * 0.15, 0.166, 0); cap.rotation.x = -Math.PI / 2; h.add(cap); ctx.parts.trims.push(cap);
					return h;
				});
				const seam = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.02, D), emissive(0x3a86c8, 0.8)); seam.position.set(0, 0.1, 0); lid.add(seam); ctx.parts.trims.push(seam);
				const y0 = lid.position.y;
				setOpen = (k) => { const up = ease(Math.min(1, k / 0.4)), over = ease(Math.max(0, (k - 0.4) / 0.6)); lid.position.y = y0 + 0.34 * up; seam.visible = over < 0.02; for (const [i, h] of halves.entries()) h.position.x = (i ? 1 : -1) * (W / 2 + 0.08) * over; };
				ctx.box(W + 0.1, H + 0.2, D + 0.1, ctx.mats.dark, p.x, (H + 0.2) / 2, p.z, true, s.ry).visible = false;
			}
			return { anchor: f.multiplyScalar(1.25).add(new THREE.Vector3(p.x, 0, p.z)), setOpen, loot: s.loot };
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
	storage: [{ type: 'crate', u: 0.2, v: 0.25, ry: 0.3, style: 'ancient' }, { type: 'crate', u: 0.35, v: 0.3, ry: 1.1, style: 'ancient' }, { type: 'crate', u: 0.75, v: 0.7, ry: 2.4 }, { type: 'crate', u: 0.8, v: 0.3, ry: 0.8, style: 'ancient' }],
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
	aft_storage_hall: [{ type: 'crate', u: 0.18, v: 0.2, ry: 0.3, anchor: 'Salvage1', loot: [{ id: 'bus_fuse' }] }, { type: 'crate', u: 0.4, v: 0.25, ry: 1.1, anchor: 'Salvage2', loot: [{ id: 'rations', n: 2 }] }, { type: 'crate', u: 0.75, v: 0.7, ry: 2.4, anchor: 'Salvage3', loot: [{ id: 'bus_fuse' }] }, { type: 'crate', u: 0.82, v: 0.28, ry: 0.8, style: 'ancient' }],
	infirmary: [{ type: 'med_bed', u: 0.25, v: 0.3, anchor: 'Beds' }, { type: 'med_bed', u: 0.25, v: 0.5 }, { type: 'med_bed', u: 0.25, v: 0.7 }, { type: 'cabinet', u: 0.85, v: 0.5, ry: -Math.PI / 2 }, { type: 'crate', u: 0.8, v: 0.85, ry: Math.PI, anchor: 'Salvage1', loot: [{ id: 'large_fuse' }] }],
};
