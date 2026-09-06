// Adaptive music: a few looping beds/pads from sounds/music/loops mixed by "mood". Layers crossfade toward per-mood targets,
// so a mood change is a slow blend rather than a cut. Everything stays quiet (MASTER) — it's a bed, not a score.
import * as THREE from 'three';

const MASTER = 0.32;
// mood → { layer: volume }. Layers not listed fade to 0.
const MOODS = {
	title: { theme: 0.9 },
	ship_dark: { derelict: 0.9, pulse_slow: 0.35 },
	ship: { ship_warm: 0.9, shimmer: 0.3 },
	alert: { ship_warm: 0.5, tense: 0.7, pulse_slow: 0.4 },
	gate: { ship_warm: 0.6, shimmer: 0.4, pulse_drive: 0.3 },
	wormhole: { space: 0.8, tense: 0.5 },
	planet: { planet: 0.9, cello: 0.25 },
	silent: {},
};

/** @param listener THREE.AudioListener  @param files {layer: url} */
export const createMusic = (listener, files) => {
	const loader = new THREE.AudioLoader(), layers = {}, target = {};
	let mood = 'silent', ready = false;
	const load = async () => {
		await Promise.all(Object.entries(files).map(async ([k, url]) => {
			const buf = await loader.loadAsync(url); const a = new THREE.Audio(listener); a.setBuffer(buf); a.setLoop(true); a.setVolume(0); layers[k] = a; target[k] = 0;
		}));
		ready = true;
	};
	const setMood = (m) => { if (!MOODS[m] || m === mood) return; mood = m; for (const k in layers) target[k] = (MOODS[m][k] ?? 0) * MASTER; };
	/** Per frame: fade volumes toward targets; start/stop layers as they cross zero. Needs a running AudioContext. */
	const tick = (dt) => {
		if (!ready || listener.context.state !== 'running') return;
		for (const k in layers) {
			const a = layers[k], v = a.getVolume(), t = target[k], nv = v + Math.sign(t - v) * Math.min(Math.abs(t - v), dt * 0.12);
			if (nv > 0.001 && !a.isPlaying) a.play(); a.setVolume(Math.max(0, nv));
			if (nv <= 0.001 && a.isPlaying && t === 0) { a.stop(); a.setVolume(0); }
		}
	};
	return { load, setMood, tick, mood: () => mood, MOODS };
};
