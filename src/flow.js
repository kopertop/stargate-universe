// Flow-balance mini-game (life support): a bank of coupled valves feeds a row of pressure gauges. Every valve also bleeds
// into its neighbours, so nudging one needle pushes the ones beside it. Bring every needle into its target band and hold
// it there while the system settles. No fail state beyond walking away (Esc) — the tension is the coupling, not a timer.
// Same contract as hotwire.js: play() resolves true on success, false on Esc; main.js pauses the sim while isOpen().
const css = `
	#flow[hidden]{display:none}
	#flow{position:fixed;inset:0;display:grid;place-items:center;background:rgba(2,4,8,.8);z-index:40;font-family:"Trebuchet MS",monospace;color:#8fd0ff;user-select:none}
	#flow .fw{width:min(720px,94vw);background:linear-gradient(#161a20,#0b0d11);border:2px solid #2a3038;box-shadow:0 0 0 6px #14171c,0 0 60px #000,inset 0 0 40px rgba(0,0,0,.6);padding:18px 26px 20px;position:relative;clip-path:polygon(4% 0,96% 0,100% 8%,100% 92%,96% 100%,4% 100%,0 92%,0 8%)}
	#flow h1{margin:0;text-align:center;font:600 24px monospace;letter-spacing:.12em;color:#8fd0ff;text-shadow:0 0 12px rgba(143,208,255,.7)}
	#flow .sub{text-align:center;font:12px monospace;color:#3f7fb0;margin:4px 0 14px;letter-spacing:.08em}
	#flow .bank{display:grid;grid-auto-flow:column;grid-auto-columns:1fr;gap:18px;padding:0 10px}
	#flow .col{display:flex;flex-direction:column;align-items:center;gap:10px}
	#flow .gauge{position:relative;width:46px;height:210px;background:#07090d;border:2px solid #2a3038;border-radius:6px;overflow:hidden}
	#flow .gauge .band{position:absolute;left:0;right:0;background:rgba(87,240,160,.22);border-top:1px solid #57f0a0;border-bottom:1px solid #57f0a0}
	#flow .gauge .fill{position:absolute;left:0;right:0;bottom:0;background:linear-gradient(#3a86c8,#1a3c5c);transition:height .12s}
	#flow .gauge .needle{position:absolute;left:-2px;right:-2px;height:3px;background:#ffb060;box-shadow:0 0 8px #ffb060;transition:top .12s}
	#flow .col.ok .gauge{border-color:#57f0a0;box-shadow:0 0 12px rgba(87,240,160,.5)}#flow .col.ok .needle{background:#57f0a0;box-shadow:0 0 8px #57f0a0}
	#flow .col label{font:700 11px monospace;letter-spacing:.06em;color:#5f9fd0}
	#flow input[type=range]{width:120px;accent-color:#8fd0ff;cursor:pointer}
	#flow .status{margin-top:14px;text-align:center;font:12px monospace;color:#f2b838;letter-spacing:.1em;min-height:16px}#flow .status.ok{color:#57f0a0}
	#flow .bar{height:12px;margin:10px auto 0;width:60%;background:#0a0c10;border:1px solid #2a3038;padding:2px}#flow .bar i{display:block;height:100%;background:repeating-linear-gradient(90deg,#57f0a0 0 8px,transparent 8px 11px);width:0;transition:width .1s linear}
	#flow .esc{position:absolute;right:26px;bottom:10px;font:11px monospace;color:#3f7fb0}
`;
const clamp01 = (v) => Math.min(1, Math.max(0, v));
export const createFlow = ({ sfx = {} } = {}) => {
	document.head.appendChild(Object.assign(document.createElement('style'), { textContent: css }));
	const el = document.createElement('div'); el.id = 'flow'; el.hidden = true; document.body.appendChild(el);
	let resolve = null, M = [], target = [], sol = [], band = 0.06, hold = 0, holdTimer = 0, N = 3;
	const done = (ok) => { clearInterval(holdTimer); el.hidden = true; const r = resolve; resolve = null; r?.(ok); };
	const values = () => [...el.querySelectorAll('input[type=range]')].map((i) => +i.value / 100);
	const reading = (v) => M.map((row, i) => clamp01(row.reduce((acc, m, j) => acc + m * v[j], 0) + 0.15));
	const render = () => {
		const r = reading(values()); let allOk = true;
		el.querySelectorAll('.col').forEach((col, i) => {
			const ok = Math.abs(r[i] - target[i]) <= band; allOk &&= ok; col.classList.toggle('ok', ok);
			col.querySelector('.needle').style.top = `${(1 - r[i]) * 100}%`; col.querySelector('.fill').style.height = `${r[i] * 100}%`;
		});
		return allOk;
	};
	const status = (t, cls = '') => { const s = el.querySelector('.status'); s.textContent = t; s.className = `status ${cls}`; };
	const tick = () => { // hold the balance for ~1.4 s (7 ticks) while the system settles
		if (!render()) { if (hold) { hold = 0; el.querySelector('.bar i').style.width = '0%'; status('BALANCE LOST — RE-TRIM THE VALVES'); } return; }
		hold++; el.querySelector('.bar i').style.width = `${Math.min(100, (hold / 7) * 100)}%`; if (hold === 1) sfx.pick?.();
		if (hold >= 7) { clearInterval(holdTimer); status('FLOW BALANCED — SYSTEM CYCLING', 'ok'); sfx.success?.(); setTimeout(() => done(true), 900); } else status(`HOLDING… ${hold}/7`);
	};
	/** Open the panel. `gauges` is the number of coupled lines (3 = medium, 4 = hard). */
	const play = ({ title = 'SCRUBBER_FLOW_v1.4', gauges = 3, labels = ['INTAKE', 'BED_A', 'BED_B', 'EXHAUST'] } = {}) => new Promise((res) => {
		resolve = res; N = gauges; hold = 0; clearInterval(holdTimer);
		M = Array.from({ length: N }, (_, i) => Array.from({ length: N }, (_, j) => (i === j ? 0.7 : Math.abs(i - j) === 1 ? (Math.random() < 0.5 ? -0.35 : 0.35) : 0)));
		for (let tries = 0; tries < 40; tries++) { sol = Array.from({ length: N }, () => 0.25 + Math.random() * 0.5); target = reading(sol); if (target.every((t) => t > 0.12 && t < 0.88)) break; } // keep every band inside the gauge
		band = N > 3 ? 0.05 : 0.06;
		const start = sol.map((s) => clamp01(s + (Math.random() < 0.5 ? -1 : 1) * (0.25 + Math.random() * 0.3)));
		el.innerHTML = `<div class="fw"><h1>${title}</h1><div class="sub">// TRIM EVERY LINE INTO ITS GREEN BAND — VALVES BLEED INTO THEIR NEIGHBOURS</div>
			<div class="bank">${Array.from({ length: N }, (_, i) => `<div class="col"><div class="gauge"><div class="band" style="top:${(1 - target[i] - band) * 100}%;height:${band * 200}%"></div><div class="fill"></div><div class="needle"></div></div>
			<input type="range" min="0" max="100" value="${Math.round(start[i] * 100)}" data-valve="${i}"><label>${labels[i] ?? `LINE_${i + 1}`}</label></div>`).join('')}</div>
			<div class="status">PRESSURE OUT OF BAND — TRIM THE VALVES</div><div class="bar"><i></i></div><div class="esc">ESC abandons</div></div>`;
		el.hidden = false; el.querySelectorAll('input').forEach((i) => (i.oninput = () => { sfx.tick?.(); render(); }));
		render(); holdTimer = setInterval(tick, 200);
		if (document.pointerLockElement) document.exitPointerLock();
	});
	window.addEventListener('keydown', (e) => { if (!el.hidden && e.code === 'Escape') { e.stopImmediatePropagation(); done(false); } }, true);
	/** Dev/autoplay: set every valve to the generating solution. */
	const solve = () => { el.querySelectorAll('input[type=range]').forEach((i, j) => { i.value = Math.round(sol[j] * 100); }); render(); };
	return { play, solve, isOpen: () => !el.hidden };
};
