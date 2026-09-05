// In-page gameplay recorder: composites the WebGL frame + a minimal text HUD onto a canvas, encodes with MediaRecorder,
// and POSTs the result to a local save endpoint (tools/save_server.py style) so it lands on disk without screen-capture permission.
export const createRecorder = (glCanvas, hud, { fps = 30, saveUrl = 'http://127.0.0.1:8091/save' } = {}) => {
	const c = document.createElement('canvas'); const ctx = c.getContext('2d');
	let rec = null, chunks = [], stream = null, active = false, t0 = 0;
	const fit = () => { if (c.width !== glCanvas.width || c.height !== glCanvas.height) { c.width = glCanvas.width; c.height = glCanvas.height; } };
	const box = (x, y, w, h) => { ctx.fillStyle = 'rgba(8,8,12,0.72)'; ctx.fillRect(x, y, w, h); ctx.strokeStyle = 'rgba(212,168,82,0.8)'; ctx.lineWidth = 2; ctx.strokeRect(x, y, w, h); };
	const text = (s, x, y, size = 22, color = '#f5ebcc', weight = '') => { ctx.font = `${weight} ${size}px -apple-system, system-ui, sans-serif`; ctx.fillStyle = '#000'; ctx.fillText(s, x + 2, y + 2); ctx.fillStyle = color; ctx.fillText(s, x, y); };
	const wrap = (s, max) => { const out = []; let line = ''; for (const w of s.split(' ')) { const t = line ? `${line} ${w}` : w; if (ctx.measureText(t).width > max && line) { out.push(line); line = w; } else line = t; } if (line) out.push(line); return out; };
	/** Call once per frame right after renderer.render(). */
	const tick = () => {
		if (!active) return; fit();
		ctx.drawImage(glCanvas, 0, 0, c.width, c.height);
		const s = hud(); const W = c.width, H = c.height, k = W / 1280;
		// top-left: chapter + objective
		box(16 * k, 16 * k, 520 * k, 96 * k); text(s.chapter, 30 * k, 50 * k, 24 * k, '#d4a852', '600'); text(`▸ ${s.label}`, 30 * k, 82 * k, 20 * k); text(s.zone, 30 * k, 104 * k, 16 * k, '#a99');
		// top-right: player frame
		box(W - 336 * k, 16 * k, 320 * k, 62 * k); text(`Eli Wallace · Lv ${s.level}`, W - 322 * k, 42 * k, 20 * k, '#d4a852', '600'); text(`HP ${s.hp}   XP ${s.xp}   Carry ${s.carry}`, W - 322 * k, 66 * k, 16 * k);
		if (s.prompt) { ctx.font = `${20 * k}px sans-serif`; const w = ctx.measureText(s.prompt).width + 40 * k; box(W / 2 - w / 2, H * 0.6, w, 40 * k); text(s.prompt, W / 2 - w / 2 + 20 * k, H * 0.6 + 28 * k, 20 * k, '#d4a852'); }
		if (s.subtitle) { ctx.font = `${22 * k}px sans-serif`; const lines = wrap(s.subtitle, W * 0.6); const h = lines.length * 30 * k + 20 * k; box(W * 0.2, H - 140 * k - h, W * 0.6, h); lines.forEach((l, i) => text(l, W * 0.2 + 16 * k, H - 140 * k - h + 34 * k + i * 30 * k, 22 * k)); }
		text(`REC ${((performance.now() - t0) / 1000).toFixed(0)}s`, 24 * k, H - 24 * k, 14 * k, '#e05040');
	};
	const start = () => {
		fit(); chunks = []; stream = c.captureStream(fps);
		const mime = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'].find((m) => MediaRecorder.isTypeSupported(m));
		rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 7_000_000 });
		rec.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
		rec.start(1000); active = true; t0 = performance.now();
	};
	/** Stop and upload. Resolves with the server's reply. */
	const stop = async (name = 'gameplay.webm') => {
		if (!rec) return 'not recording';
		const done = new Promise((r) => (rec.onstop = r)); rec.stop(); active = false; await done;
		const blob = new Blob(chunks, { type: rec.mimeType }); stream.getTracks().forEach((t) => t.stop());
		const res = await fetch(`${saveUrl}?name=${encodeURIComponent(name)}`, { method: 'POST', body: blob });
		return `${await res.text()} (${(blob.size / 1e6).toFixed(1)} MB)`;
	};
	return { tick, start, stop, isActive: () => active };
};
