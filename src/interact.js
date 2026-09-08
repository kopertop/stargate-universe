// Proximity interactables: nearest one with a prompt is shown; E / gamepad X triggers (or holds, for `hold` seconds).
import * as THREE from 'three';
const list = [];
const tmp = new THREE.Vector3();
/** @param {{id:string, position:THREE.Vector3|THREE.Object3D, radius?:number, prompt:()=>string|null, action:()=>void, hold?:()=>number}} def */
export const register = (def) => { list.push({ radius: 2.4, ...def, progress: 0 }); return def; };
export const unregister = (id) => { const i = list.findIndex((d) => d.id === id); if (i >= 0) list.splice(i, 1); };
const posOf = (d) => (d.position.isObject3D ? d.position.getWorldPosition(tmp) : tmp.copy(d.position));
export let current = null;
export let holding = false;
/** Call every frame. Returns { prompt, progress } for the HUD, or null. */
export const update = (dt, playerPos, pressed, held, worldName = null) => {
	let best = null, bestD = Infinity;
	for (const d of list) {
		if (d.world && worldName && d.world !== worldName) continue; // interactables live in one world
		const p = d.prompt(); if (!p) continue;
		const dist = posOf(d).distanceTo(playerPos);
		if (dist < d.radius && dist < bestD) { best = d; bestD = dist; }
	}
	if (best !== current) { if (current) current.progress = 0; current = best; }
	if (!current) { holding = false; return null; }
	const holdSec = current.hold?.() ?? 0;
	holding = holdSec > 0 && held;
	if (holdSec > 0) {
		if (held) { current.progress += dt / holdSec; if (current.progress >= 1) { current.progress = 0; current.action(); } }
		else current.progress = Math.max(0, current.progress - dt * 2);
	} else if (pressed) current.action();
	return { prompt: current.prompt(), progress: holdSec > 0 ? current.progress : null, hold: holdSec > 0 };
};
