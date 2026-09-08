// In-page gameplay recorder: composites the WebGL frame + a text HUD onto a canvas and streams JPEG frames to the dev server,
// which pipes them into ffmpeg at a fixed frame rate (tools/edit_server.py /rec/*). The game loop steps exactly 1/fps per
// frame while recording, so the video is smooth even when the window is occluded or the machine is slow.
export const createRecorder = (glCanvas, hud, { fps = 30, base = '/rec', quality = 0.86 } = {}) => {
	const c = document.createElement('canvas'); const ctx = c.getContext('2d');
	let active = false, frames = 0, name = '', chain = Promise.resolve();
	const fit = () => { const k = Math.min(1, 1024 / glCanvas.width), w = Math.round(glCanvas.width * k) & ~1, h = Math.round(glCanvas.height * k) & ~1; if (c.width !== w || c.height !== h) { c.width = w; c.height = h; } }; // even dims for yuv420p
	const box = (x, y, w, h) => { ctx.fillStyle = 'rgba(8,8,12,0.72)'; ctx.fillRect(x, y, w, h); ctx.strokeStyle = 'rgba(212,168,82,0.8)'; ctx.lineWidth = 2; ctx.strokeRect(x, y, w, h); };
	const text = (s, x, y, size = 22, color = '#f5ebcc', weight = '') => { ctx.font = `${weight} ${size}px -apple-system, system-ui, sans-serif`; ctx.fillStyle = '#000'; ctx.fillText(s, x + 2, y + 2); ctx.fillStyle = color; ctx.fillText(s, x, y); };
	const wrap = (s, max) => { const out = []; let line = ''; for (const w of s.split(' ')) { const t = line ? `${line} ${w}` : w; if (ctx.measureText(t).width > max && line) { out.push(line); line = w; } else line = t; } if (line) out.push(line); return out; };
	const compose = () => {
		fit(); ctx.drawImage(glCanvas, 0, 0, c.width, c.height);
		const s = hud(); const W = c.width, H = c.height, k = W / 1024;
		box(16 * k, 16 * k, 520 * k, 96 * k); text(s.chapter, 30 * k, 50 * k, 24 * k, '#d4a852', '600'); text(`▸ ${s.label}`, 30 * k, 82 * k, 20 * k); text(s.zone, 30 * k, 104 * k, 16 * k, '#a99');
		box(W - 336 * k, 16 * k, 320 * k, 62 * k); text(`Eli Wallace · Lv ${s.level}`, W - 322 * k, 42 * k, 20 * k, '#d4a852', '600'); text(`HP ${s.hp}   O₂ ${s.o2}%   XP ${s.xp}   Carry ${s.carry}`, W - 322 * k, 66 * k, 16 * k);
		if (s.prompt) { ctx.font = `${20 * k}px sans-serif`; const w = ctx.measureText(s.prompt).width + 40 * k; box(W / 2 - w / 2, H * 0.6, w, 40 * k); text(s.prompt, W / 2 - w / 2 + 20 * k, H * 0.6 + 28 * k, 20 * k, '#d4a852'); }
		if (s.subtitle) { ctx.font = `${22 * k}px sans-serif`; const lines = wrap(s.subtitle, W * 0.6); const h = lines.length * 30 * k + 20 * k; box(W * 0.2, H - 140 * k - h, W * 0.6, h); lines.forEach((l, i) => text(l, W * 0.2 + 16 * k, H - 140 * k - h + 34 * k + i * 30 * k, 22 * k)); }
		if (s.overlay) { ctx.font = `600 ${26 * k}px monospace`; const w = ctx.measureText(s.overlay).width + 60 * k; box(W / 2 - w / 2, H * 0.42, w, 50 * k); text(s.overlay, W / 2 - w / 2 + 30 * k, H * 0.42 + 35 * k, 26 * k, '#5ff3ea', '600'); }
		text(`REC ${(frames / fps).toFixed(1)}s`, 24 * k, H - 24 * k, 14 * k, '#e05040');
	};
	const post = (url, body) => fetch(url, { method: 'POST', body });
	/** Call once per simulated frame after render; resolves when the frame has been handed to the encoder (main.js waits on it). */
	const tick = async () => {
		if (!active) return; compose();
		const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', quality)); const i = frames++;
		chain = chain.then(() => post(`${base}/frame?name=${encodeURIComponent(name)}&i=${i}`, blob)).catch(() => {}); // strictly ordered
		await chain;
	};
	const start = async (n = 'gameplay') => { name = n.replace(/\.(mp4|webm)$/, ''); fit(); frames = 0; await post(`${base}/start?name=${encodeURIComponent(name)}&fps=${fps}`); active = true; return `recording ${name}.mp4 at ${fps} fps (${c.width}×${c.height})`; };
	/** Stop and finalise the mp4. Resolves with the server's reply (path + size). */
	const stop = async () => { if (!active) return 'not recording'; active = false; await chain; const r = await post(`${base}/stop?name=${encodeURIComponent(name)}`); return `${await r.text()} (${frames} frames = ${(frames / fps).toFixed(1)}s)`; };
	return { tick, start, stop, isActive: () => active, fps };
};
