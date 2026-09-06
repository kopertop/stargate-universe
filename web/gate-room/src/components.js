// Reusable interior components: each entry builds meshes + colliders at a world position and can expose named `parts`
// that ship state toggles (relay lamp, console screen, scrubber bed…) and an `anchor` point in front of it that quests and
// NPCs reference by name (`${roomId}:${spec.anchor}`). Specs come from the layout data (room.props) or the per-type
// defaults in ship.js; the map editor places the same specs. Positions are room-relative fractions (u, v) resolved by ship.js.
//   spec: { type, u, v, ry?, anchor?, id? }   ctx: { box, group, mats, parts, roomH }
import * as THREE from 'three';

const fwd = (ry) => new THREE.Vector3(Math.sin(ry), 0, Math.cos(ry));
const lamp = (ctx, x, y, z, ry = 0, w = 0.6, h = 0.12) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.05), ctx.mats.red.clone()); m.position.set(x, y, z); m.rotation.y = ry; ctx.group.add(m); return m; };
const emissive = (color, intensity = 0) => new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: intensity });

/** Registry. `size` (w, d in m) is the editor footprint; `build(ctx, p, spec)` places at world p = {x, z}, facing spec.ry. */
export const COMPONENTS = {
	console: {
		label: 'Console', size: [2.6, 1.0], defaultAnchor: 'Console',
		build: (ctx, p, s) => {
			ctx.box(2.6, 1.0, 1.0, ctx.mats.dark, p.x, 0.5, p.z, true, s.ry);
			const screen = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.05, 0.8), emissive(0x9fd8ff)); screen.material.emissive.set(0x4fa8ff); screen.position.set(p.x, 1.03, p.z); screen.rotation.set(-0.3, s.ry, 0, 'YXZ'); ctx.group.add(screen);
			ctx.parts.screens.push(screen);
			return { anchor: fwd(s.ry).multiplyScalar(-1.5).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	relay: {
		label: 'Power relay', size: [1.2, 0.25], defaultAnchor: 'PowerRelay',
		build: (ctx, p, s) => {
			ctx.box(1.2, 1.6, 0.25, ctx.mats.dark, p.x, 1.2, p.z, true, s.ry);
			const f = fwd(s.ry); ctx.parts.relayLamp = lamp(ctx, p.x - f.x * 0.15, 1.75, p.z - f.z * 0.15, s.ry);
			return { anchor: f.multiplyScalar(-0.9).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	crate: {
		label: 'Supply crate', size: [1.4, 1.0], defaultAnchor: 'SupplyCrate',
		build: (ctx, p, s) => { ctx.box(1.4, 0.9, 1.0, ctx.mats.crate, p.x, 0.45, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(-1.2).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	bed: {
		label: 'Bed', size: [2.0, 1.0], defaultAnchor: 'Bed',
		build: (ctx, p, s) => { ctx.box(2, 0.5, 1, ctx.mats.floor, p.x, 0.25, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(-1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	med_bed: {
		label: 'Med bed', size: [2.0, 0.9], defaultAnchor: 'Beds',
		build: (ctx, p, s) => { ctx.box(2.0, 0.6, 0.9, ctx.mats.steel, p.x, 0.3, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(-1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	locker: {
		label: 'Locker', size: [0.9, 0.6], defaultAnchor: 'Locker',
		build: (ctx, p, s) => { ctx.box(0.9, 2.2, 0.6, ctx.mats.dark, p.x, 1.1, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(-0.9).add(new THREE.Vector3(p.x, 0, p.z)) }; },
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
			return { anchor: fwd(s.ry).multiplyScalar(-1.0).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	scrubber: {
		label: 'CO2 scrubber', size: [2.2, 0.4], defaultAnchor: 'Scrubber',
		build: (ctx, p, s) => {
			const f = fwd(s.ry), side = new THREE.Vector3(-f.z, 0, f.x);
			ctx.box(2.2, 2.4, 0.4, ctx.mats.dark, p.x, 1.3, p.z, true, s.ry);
			const sl = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.06), ctx.mats.red.clone()); sl.position.set(p.x - f.x * 0.24, 2.2, p.z - f.z * 0.24); sl.rotation.y = s.ry; ctx.group.add(sl);
			const bed = new THREE.Mesh(new THREE.BoxGeometry(1.6, 1.2, 0.1), new THREE.MeshStandardMaterial({ color: 0x5a5245, roughness: 1 })); bed.position.set(p.x - f.x * 0.22, 1.0, p.z - f.z * 0.22); bed.rotation.y = s.ry; ctx.group.add(bed);
			ctx.parts.scrubLamp = sl; ctx.parts.scrubBed = bed; void side;
			return { anchor: f.multiplyScalar(-1.0).add(new THREE.Vector3(p.x, 0, p.z)) };
		},
	},
	tank: {
		label: 'Water tank', size: [1.2, 1.2], defaultAnchor: 'WaterTank',
		build: (ctx, p, s) => { ctx.box(1.2, 2.0, 1.2, ctx.mats.dark, p.x, 1.0, p.z, true, s.ry); return { anchor: fwd(s.ry).multiplyScalar(-1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	elevator_door: {
		label: 'Elevator door', size: [2.4, 0.2], defaultAnchor: 'Elevator',
		build: (ctx, p, s) => { ctx.box(2.4, 3.2, 0.2, ctx.mats.door, p.x, 1.6, p.z, true, s.ry); const f = fwd(s.ry); lamp(ctx, p.x - f.x * 0.15, 3.35, p.z - f.z * 0.15, s.ry); return { anchor: f.multiplyScalar(-1.1).add(new THREE.Vector3(p.x, 0, p.z)) }; },
	},
	breach: {
		label: 'Hull breach', size: [3.2, 0.1],
		build: (ctx, p, s) => {
			const tear = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 2.4), new THREE.MeshBasicMaterial({ color: 0x02030a })); tear.position.set(p.x, 2.6, p.z); tear.rotation.y = s.ry; ctx.group.add(tear);
			if (s.active !== false) { const l = new THREE.PointLight(0x88aaff, 6, 12); const f = fwd(s.ry); l.position.set(p.x - f.x * 2.5, 3, p.z - f.z * 2.5); ctx.group.add(l); ctx.parts.breachLight = l; }
			return {};
		},
	},
	wall_light: {
		label: 'Wall light', size: [0.1, 0.6],
		build: (ctx, p, s) => { const m = new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.6, 0.06), ctx.mats.slit); m.position.set(p.x, 2.0, p.z); m.rotation.y = s.ry; ctx.group.add(m); return {}; },
	},
	marker: {
		label: 'Anchor marker', size: [0.6, 0.6], defaultAnchor: 'Spot',
		build: (ctx, p) => ({ anchor: new THREE.Vector3(p.x, 0, p.z) }), // invisible: NPC stand spot / waypoint
	},
};

/** Default furniture per room type, as room-relative specs (used when the layout row has no `props`). */
export const DEFAULT_PROPS = {
	gate_room: [{ type: 'relay', u: 0.68, v: 0.989, ry: Math.PI }, { type: 'crate', u: 0.25, v: 0.86, ry: Math.PI }, { type: 'marker', u: 0.73, v: 0.8, anchor: 'Brody' }, { type: 'marker', u: 0.325, v: 0.725, anchor: 'Scott' }],
	control_room: [{ type: 'console', u: 0.5, v: 0.53, ry: Math.PI, anchor: 'ControlConsole' }, { type: 'marker', u: 0.6, v: 0.52, anchor: 'Rush' }, { type: 'pillar', u: 0.2, v: 0.2 }, { type: 'pillar', u: 0.8, v: 0.2 }, { type: 'pillar', u: 0.2, v: 0.8 }, { type: 'pillar', u: 0.8, v: 0.8 }],
	quarters: [{ type: 'bed', u: 0.15, v: 0.5, ry: Math.PI / 2 }, { type: 'locker', u: 0.92, v: 0.3, ry: -Math.PI / 2 }],
	storage: [{ type: 'crate', u: 0.2, v: 0.25, ry: 0.3 }, { type: 'crate', u: 0.35, v: 0.3, ry: 1.1 }, { type: 'crate', u: 0.75, v: 0.7, ry: 2.4 }, { type: 'crate', u: 0.8, v: 0.3, ry: 0.8 }],
	infirmary: [{ type: 'med_bed', u: 0.25, v: 0.3, anchor: 'Beds' }, { type: 'med_bed', u: 0.25, v: 0.5 }, { type: 'med_bed', u: 0.25, v: 0.7 }, { type: 'cabinet', u: 0.85, v: 0.5, ry: -Math.PI / 2 }],
	elevator: [{ type: 'elevator_door', u: 0.5, v: 0.04, ry: Math.PI, anchor: 'Elevator' }],
	'shuttle-dock': [{ type: 'breach', u: 0.99, v: 0.5, ry: -Math.PI / 2 }],
};
/** Room-specific overrides by id (the Kino Room, the scrubber's corridor). */
export const ROOM_PROPS = {
	eli_quarters: [{ type: 'kino_pedestal', u: 0.5, v: 0.3, ry: Math.PI, anchor: 'KinoPedestal' }, { type: 'locker', u: 0.955, v: 0.75, ry: -Math.PI / 2, anchor: 'Locker' }, { type: 'bed', u: 0.11, v: 0.75, ry: Math.PI / 2, anchor: 'Bed' }],
	south_corridor: [{ type: 'scrubber', u: 0.953, v: 0.5585, ry: -Math.PI / 2, anchor: 'Scrubber' }],
	sealed_section_north: [{ type: 'breach', u: 0.99, v: 0.5, ry: -Math.PI / 2, active: false }],
};
