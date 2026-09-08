// Hotwire mini-game (port of the Godot hotwire_minigame.gd / DOOR_HACK concept): three coloured jacks on the left must be
// patched to their protocol ports on the right; one port is a VOID decoy. The ports flash their colour for a moment at the
// start, then go dark — after that you work from memory. A wrong patch faults the panel and clears every connection.
// play() pauses nothing itself; main.js treats an open panel like the Kino Remote. Resolves true on success, false on Esc.
const WIRES = [{ label: 'PWR_CORE', color: '#f247b8' }, { label: 'DATA_LINK', color: '#33e6e0' }, { label: 'SYS_LOCK', color: '#f2b838' }];
const css = `
	#hotwire[hidden]{display:none}
	#hotwire{position:fixed;inset:0;display:grid;place-items:center;background:rgba(2,4,8,.8);z-index:40;font-family:"Trebuchet MS",monospace;color:#5ff3ea;user-select:none}
	#hotwire .hw{width:min(760px,94vw);background:linear-gradient(#1a1d22,#0c0e12);border:2px solid #2a3038;box-shadow:0 0 0 6px #14171c,0 0 60px #000,inset 0 0 40px rgba(0,0,0,.6);padding:18px 26px 20px;position:relative;clip-path:polygon(4% 0,96% 0,100% 8%,100% 92%,96% 100%,4% 100%,0 92%,0 8%)}
	#hotwire h1{margin:0;text-align:center;font:600 24px monospace;letter-spacing:.12em;color:#5ff3ea;text-shadow:0 0 12px rgba(95,243,234,.7)}
	#hotwire .sub{text-align:center;font:12px monospace;color:#3aa9a3;margin:4px 0 14px;letter-spacing:.08em}
	#hotwire .field{display:grid;grid-template-columns:150px 1fr 190px;gap:0;align-items:stretch;min-height:250px;position:relative}
	#hotwire .jacks,#hotwire .ports{display:flex;flex-direction:column;justify-content:space-around;gap:10px}
	#hotwire .jack{height:52px;border-radius:26px 8px 8px 26px;border:2px solid #333;background:linear-gradient(90deg,var(--c) 0 60%,#8a8f96 60% 78%,#c9ccd0 78%);box-shadow:0 0 14px var(--c),inset 0 0 8px rgba(0,0,0,.5);cursor:pointer;position:relative;transition:transform .12s}
	#hotwire .jack.done::after{content:attr(data-label);position:absolute;left:12px;top:16px;font:700 11px monospace;color:#0a0c10;letter-spacing:.04em}
	#hotwire .jack.sel{transform:translateX(10px) scale(1.04);outline:2px solid #fff}#hotwire .jack.done{opacity:.55;cursor:default}
	#hotwire .port{height:48px;border:2px solid #3a4048;border-radius:10px;background:#0a0c10;display:flex;align-items:center;gap:10px;padding:0 12px;font:700 13px monospace;color:#8a8f96;cursor:pointer;letter-spacing:.05em}
	#hotwire .port i{width:16px;height:16px;border-radius:50%;border:2px solid #2a3038;background:#111;box-shadow:none;transition:background .3s,box-shadow .3s}
	#hotwire .port.lit i{background:var(--c);box-shadow:0 0 12px var(--c)}#hotwire .port.on{border-color:var(--c);color:var(--c)}#hotwire .port.on i{background:var(--c);box-shadow:0 0 12px var(--c)}
	#hotwire .port.void{color:#555}#hotwire .port:hover{border-color:#5ff3ea}
	#hotwire svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}
	#hotwire .status{margin-top:14px;text-align:center;font:12px monospace;color:#f2b838;letter-spacing:.1em;min-height:16px}
	#hotwire .status.bad{color:#ff5050;text-shadow:0 0 10px #f00}#hotwire .status.ok{color:#57f0a0}
	#hotwire .bar{height:12px;margin:10px auto 0;width:60%;background:#0a0c10;border:1px solid #2a3038;padding:2px}#hotwire .bar i{display:block;height:100%;background:repeating-linear-gradient(90deg,#5ff3ea 0 8px,transparent 8px 11px);width:0;transition:width .35s}
	#hotwire .esc{position:absolute;right:26px;bottom:10px;font:11px monospace;color:#3aa9a3}
	#hotwire.fault .hw{animation:hwshake .4s}@keyframes hwshake{0%,100%{transform:none}25%{transform:translate(-6px,2px)}50%{transform:translate(5px,-3px)}75%{transform:translate(-3px,1px)}}
`;
export const createHotwire = ({ sfx = {} } = {}) => {
	document.head.appendChild(Object.assign(document.createElement('style'), { textContent: css }));
	const el = document.createElement('div'); el.id = 'hotwire'; el.hidden = true; document.body.appendChild(el);
	let resolve = null, faults = 0, connected = new Map(), selected = -1, order = [];
	const done = (ok) => { el.hidden = true; const r = resolve; resolve = null; r?.(ok); };
	const draw = () => {
		const svg = el.querySelector('svg'), fr = el.querySelector('.field').getBoundingClientRect();
		svg.innerHTML = [...connected].map(([j, p]) => { const a = el.querySelector(`[data-jack="${j}"]`).getBoundingClientRect(), b = el.querySelector(`[data-port="${p}"]`).getBoundingClientRect(); const x1 = a.right - fr.left, y1 = a.top + a.height / 2 - fr.top, x2 = b.left - fr.left, y2 = b.top + b.height / 2 - fr.top; return `<path d="M${x1},${y1} C${x1 + 80},${y1} ${x2 - 80},${y2} ${x2},${y2}" stroke="${WIRES[j].color}" stroke-width="7" fill="none" stroke-linecap="round" style="filter:drop-shadow(0 0 6px ${WIRES[j].color})"/>`; }).join('');
		el.querySelector('.bar i').style.width = `${(connected.size / WIRES.length) * 100}%`;
	};
	const status = (t, cls = '') => { const s = el.querySelector('.status'); s.textContent = t; s.className = `status ${cls}`; };
	const fault = () => {
		faults++; connected.clear(); selected = -1; el.classList.add('fault'); setTimeout(() => el.classList.remove('fault'), 450); sfx.fault?.();
		el.querySelectorAll('.jack').forEach((j) => j.classList.remove('sel', 'done')); el.querySelectorAll('.port').forEach((p) => p.classList.remove('on'));
		status(`PROTOCOL FAULT — LINES RESET (${faults})`, 'bad'); draw();
	};
	const pick = (j) => { if (connected.has(j)) return; selected = j; el.querySelectorAll('.jack').forEach((b) => b.classList.toggle('sel', +b.dataset.jack === j)); sfx.pick?.(); status(`${WIRES[j].label} SELECTED — PATCH TO ITS PORT`); };
	const patch = (p) => {
		if (selected < 0) { status('SELECT A JACK FIRST'); return; }
		const live = order[p]; if (live !== selected || [...connected.values()].includes(p)) return fault();
		connected.set(selected, p); el.querySelector(`[data-jack="${selected}"]`).classList.replace('sel', 'done'); el.querySelector(`[data-port="${p}"]`).classList.add('on'); selected = -1; sfx.connect?.(); draw();
		if (connected.size === WIRES.length) { status('PROTOCOL MATCHED — ROUTING POWER', 'ok'); sfx.success?.(); setTimeout(() => done(true), 900); } else status(`${connected.size}/${WIRES.length} LINES LIVE`);
	};
	/** Open the panel. `title` names the system being hotwired. */
	const play = ({ title = 'RELAY_HOTWIRE_v2.7', security = 'MEDIUM' } = {}) => new Promise((res) => {
		resolve = res; faults = 0; connected = new Map(); selected = -1;
		order = [0, 1, 2, -1].sort(() => Math.random() - 0.5); // port index → wire index (-1 = VOID)
		el.innerHTML = `<div class="hw"><h1>${title}</h1><div class="sub">// CONNECT WIRES TO MATCH PROTOCOL — SKIP VOID</div>
			<div class="field"><div class="jacks">${WIRES.map((w, i) => `<div class="jack" data-jack="${i}" data-label="${w.label}" style="--c:${w.color}"></div>`).join('')}</div><svg></svg>
			<div class="ports">${order.map((w, p) => `<div class="port ${w < 0 ? 'void' : 'lit'}" data-port="${p}" data-label="${w < 0 ? 'VOID' : WIRES[w].label}" style="--c:${w < 0 ? '#333' : WIRES[w].color}"><i></i>${w < 0 ? 'VOID' : WIRES[w].label}</div>`).join('')}</div></div>
			<div class="status">SECURITY LEVEL: ${security} — PORTS SHOW THEIR LINE FOR A MOMENT</div><div class="bar"><i></i></div><div class="esc">ESC abandons</div></div>`;
		el.hidden = false; el.querySelectorAll('.jack').forEach((b) => (b.onclick = () => pick(+b.dataset.jack))); el.querySelectorAll('.port').forEach((b) => (b.onclick = () => patch(+b.dataset.port)));
		setTimeout(() => { el.querySelectorAll('.port').forEach((p) => p.classList.remove('lit')); if (resolve && !connected.size) status(`SECURITY LEVEL: ${security} — PATCH FROM MEMORY`); }, 2600);
		if (document.pointerLockElement) document.exitPointerLock();
	});
	window.addEventListener('keydown', (e) => { if (!el.hidden && e.code === 'Escape') { e.stopImmediatePropagation(); done(false); } }, true);
	return { play, isOpen: () => !el.hidden, get faults() { return faults; } };
};
