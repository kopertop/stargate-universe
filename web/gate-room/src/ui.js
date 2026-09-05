// WoW-style HUD (gold-on-dark, per docs/hud-redesign/HANDOFF.md) + the diegetic Kino Remote full-screen menu.
import { rpg, ITEMS, TALENTS, stats, xpToNext, count, equip, unequip, spendTalent, carried } from './rpg.js';

const css = `
	:root{--gold:#d4a852;--gold-dim:#8c7038;--panel:rgba(9,9,12,.82);--text:#f5ebcc;--hp:#57bd42;--o2:#59b8eb;--xp:#a98cf0}
	.hud{position:fixed;inset:0;pointer-events:none;font-family:-apple-system,system-ui,sans-serif;color:var(--text);text-shadow:0 1px 2px #000}
	.panel{background:var(--panel);border:1px solid var(--gold-dim);box-shadow:0 0 0 2px #000 inset,0 0 0 1px #000;border-radius:4px}
	#pf{position:absolute;left:14px;top:12px;display:flex;gap:10px;align-items:center;padding:8px 12px 8px 8px}
	#pf .portrait{width:56px;height:56px;border-radius:50%;border:2px solid var(--gold);background:radial-gradient(circle at 40% 35%,#c8c0b0,#4a4640);position:relative}
	#pf .lvl{position:absolute;right:-6px;bottom:-4px;background:#000;border:1px solid var(--gold);border-radius:50%;width:20px;height:20px;font:bold 11px sans-serif;display:grid;place-items:center;color:var(--gold)}
	.bar{position:relative;width:170px;height:14px;background:#111;border:1px solid #000;margin-top:3px}
	.bar i{position:absolute;inset:0;transform-origin:left;display:block}
	.bar b{position:absolute;inset:0;font:10px/14px monospace;text-align:center;font-weight:600}
	#pf .name{font:600 13px sans-serif;color:var(--gold)}
	#qt{position:absolute;right:14px;top:210px;width:270px;padding:8px 10px;font-size:12px}
	#qt h4{margin:0 0 4px;color:var(--gold);font:700 13px sans-serif;letter-spacing:.02em}
	#qt .step{margin:2px 0 0 8px}#qt .step.done{opacity:.5;text-decoration:line-through}#qt .obj{opacity:.85;margin-left:8px;font-size:11px}
	#mm{position:absolute;right:14px;top:12px;width:180px;height:180px;border-radius:50%;border:2px solid var(--gold);background:var(--panel);overflow:hidden}
	#mm canvas{width:100%;height:100%}#zone{position:absolute;right:14px;top:196px;width:184px;text-align:center;font:600 11px sans-serif;color:var(--gold)}
	#ab{position:absolute;left:50%;bottom:14px;transform:translateX(-50%);display:flex;gap:6px;padding:6px}
	#ab .slot{width:52px;height:52px;border:1px solid var(--gold-dim);background:#111;position:relative;display:grid;place-items:center;font-size:22px}
	#ab .slot.off{opacity:.35;filter:grayscale(1)}#ab .slot kbd{position:absolute;left:3px;top:2px;font:10px monospace;color:var(--gold)}#ab .slot small{position:absolute;right:3px;bottom:2px;font:10px monospace}
	#menu{position:absolute;right:14px;bottom:14px;display:flex;flex-direction:column;gap:4px;pointer-events:auto}
	#menu button{background:var(--panel);border:1px solid var(--gold-dim);color:var(--gold);font:11px monospace;padding:4px 8px;cursor:pointer;text-align:left}
	#menu button:hover{border-color:var(--gold)}
	#log{position:absolute;left:14px;bottom:14px;width:320px;height:120px;padding:6px 8px;font:11px monospace;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end}
	#log div{color:#e6d6a8;white-space:nowrap;text-overflow:ellipsis;overflow:hidden}
	#prompt{position:absolute;left:50%;top:58%;transform:translateX(-50%);padding:6px 14px;font-size:14px}
	#prompt kbd{color:var(--gold);font-weight:700}#prompt .pb{height:4px;background:#222;margin-top:5px}#prompt .pb i{display:block;height:100%;background:var(--gold)}
	#sub{position:absolute;left:50%;bottom:150px;transform:translateX(-50%);max-width:640px;padding:8px 16px;font-size:15px;text-align:center}
	#sub b{color:var(--gold)}#sub.radio b::before{content:'📻 '}
	#toast{position:absolute;left:50%;top:22%;transform:translateX(-50%);padding:10px 22px;font:600 16px sans-serif;color:var(--gold);letter-spacing:.04em;text-align:center}
	#chapter{position:fixed;inset:0;display:grid;place-items:center;background:rgba(0,0,0,.86);pointer-events:auto;text-align:center}
	#chapter h1{font:300 34px/1.2 Georgia,serif;letter-spacing:.2em;color:var(--gold);margin:0}#chapter p{max-width:560px;opacity:.85}
	#chapter button{margin-top:18px;background:transparent;border:1px solid var(--gold);color:var(--gold);padding:8px 22px;font:14px monospace;cursor:pointer}
	#remote{position:fixed;inset:0;display:grid;place-items:center;background:rgba(4,6,10,.78);pointer-events:auto}
	#remote .dev{width:min(960px,92vw);height:min(600px,86vh);background:linear-gradient(#141a22,#0b0e14);border:2px solid var(--gold-dim);box-shadow:0 0 40px #000,0 0 0 1px #000 inset;display:grid;grid-template-columns:170px 1fr;font-size:13px}
	#remote nav{border-right:1px solid var(--gold-dim);padding:10px 0;display:flex;flex-direction:column}
	#remote nav button{background:none;border:0;border-left:3px solid transparent;color:#bba;padding:9px 14px;text-align:left;font:13px monospace;cursor:pointer}
	#remote nav button.on{color:var(--gold);border-left-color:var(--gold);background:rgba(212,168,82,.08)}
	#remote section{padding:16px 20px;overflow:auto}#remote h2{margin:0 0 10px;font:600 16px monospace;color:var(--gold);letter-spacing:.1em}
	#remote table{border-collapse:collapse;width:100%}#remote td,#remote th{padding:4px 6px;border-bottom:1px solid #222;text-align:left}
	#remote .btn{background:#181c24;border:1px solid var(--gold-dim);color:var(--gold);padding:4px 10px;font:12px monospace;cursor:pointer}#remote .btn:disabled{opacity:.4;cursor:default}
	#remote .slots{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}#remote .gslot{border:1px solid var(--gold-dim);padding:8px;min-height:54px;background:#0d1016}#remote .gslot small{color:#887;display:block}
	#remote .tal{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}#remote .tal>div{border:1px solid var(--gold-dim);padding:10px;background:#0d1016}
	#remote .hint{color:#887;font-size:11px;margin-top:8px}
	.hidden{display:none!important}
`;
const el = (tag, attrs = {}, html = '') => { const e = document.createElement(tag); Object.assign(e, attrs); e.innerHTML = html; return e; };

export const createUI = (ctx) => {
	// ctx: { getWorldName, onDial(planetId|'destiny'), onLaunchKino, canLaunchKino, planets(), chapterTitle(), steps(), stepIndex(), flags, onResume }
	document.head.appendChild(el('style', {}, css));
	const hud = el('div', { className: 'hud' }); document.body.appendChild(hud);
	hud.innerHTML = `
		<div id="pf" class="panel"><div class="portrait"><span class="lvl">1</span></div><div>
			<div class="name">Eli Wallace <span style="color:#aaa;font-weight:400">· Engineer</span></div>
			<div class="bar"><i style="background:var(--hp)"></i><b class="hpv"></b></div>
			<div class="bar"><i style="background:var(--o2)"></i><b class="o2v"></b></div>
			<div class="bar" style="height:6px"><i style="background:var(--xp)"></i></div></div></div>
		<div id="mm"><canvas width="360" height="360"></canvas></div><div id="zone"></div>
		<div id="qt" class="panel"></div>
		<div id="ab" class="panel"></div>
		<div id="menu"><button data-tab="character">C  Character</button><button data-tab="quest">Q  Quests</button><button data-tab="map">M  Ship</button><button data-tab="inventory">B  Bags</button></div>
		<div id="log" class="panel"></div>
		<div id="prompt" class="panel hidden"></div>
		<div id="sub" class="panel hidden"></div>
		<div id="toast" class="panel hidden"></div>`;
	const q = (s) => hud.querySelector(s);
	const remote = el('div', { id: 'remote', className: 'hidden' }); document.body.appendChild(remote);
	const chapterCard = el('div', { id: 'chapter', className: 'hidden' }); document.body.appendChild(chapterCard);

	// ---- player frame
	const refreshPlayer = () => {
		const s = stats();
		q('.lvl').textContent = rpg.level;
		const bars = hud.querySelectorAll('#pf .bar i');
		bars[0].style.transform = `scaleX(${rpg.hp / s.maxHp})`; q('.hpv').textContent = `${Math.round(rpg.hp)} / ${s.maxHp}`;
		bars[1].style.transform = `scaleX(${rpg.o2 / 100})`; q('.o2v').textContent = `O₂ ${Math.round(rpg.o2)}%`;
		bars[2].style.transform = `scaleX(${rpg.xp / xpToNext(rpg.level)})`;
		q('#log').innerHTML = rpg.log.slice(-7).map((t) => `<div>${t}</div>`).join('');
		refreshActionBar();
	};
	// ---- action bar (4 slots, controller-first)
	const SLOTS = [
		{ key: 'TAB', pad: '☰', icon: '📟', name: 'Kino Remote', has: () => count('kino_remote') > 0 || rpg.equipment.tool === 'kino_remote' || ctx.flags.has('kino_acquired') },
		{ key: 'E', pad: 'X', icon: '⛏', name: 'Shovel', has: () => rpg.equipment.tool === 'shovel' },
		{ key: 'K', pad: 'Y', icon: '🛰', name: 'Launch Kino', has: () => count('kino_orb') > 0 },
		{ key: 'SPC', pad: 'A', icon: '⤒', name: 'Jump', has: () => true },
	];
	const refreshActionBar = () => { q('#ab').innerHTML = SLOTS.map((s) => `<div class="slot ${s.has() ? '' : 'off'}" title="${s.name}"><kbd>${s.key}</kbd>${s.icon}<small>${s.pad}</small></div>`).join(''); };

	// ---- quest tracker
	const refreshTracker = () => {
		const steps = ctx.steps(), idx = ctx.stepIndex();
		const visible = steps.slice(Math.max(0, idx - 2), idx + 1);
		q('#qt').innerHTML = `<h4>${ctx.chapterTitle()}</h4>` + visible.map((s, i) => {
			const done = Math.max(0, idx - 2) + i < idx;
			const counter = s.counter ? ` <span style="color:var(--gold)">${Math.min(count(s.counter.item), s.counter.required)}/${s.counter.required}</span>` : '';
			return `<div class="step ${done ? 'done' : ''}">${done ? '✓' : '▸'} ${s.label}${done ? '' : counter}</div>${done ? '' : `<div class="obj">${s.objective}</div>`}`;
		}).join('');
	};

	// ---- minimap (2D canvas): rooms or planet nodes, player, waypoint
	const mmc = q('#mm canvas').getContext('2d');
	const drawMinimap = ({ rooms, nodes, player, yaw, waypoint, gate }) => {
		const W = 360, R = W / 2, scale = 4.2; mmc.clearRect(0, 0, W, W);
		mmc.save(); mmc.translate(R, R); mmc.rotate(-yaw + Math.PI); // heading-up... keep north-up: comment out rotate for stability
		mmc.rotate(yaw - Math.PI); // net: north-up
		const tx = (x, z) => [(x - player.x) * scale, (z - player.z) * scale];
		mmc.fillStyle = 'rgba(212,168,82,.10)'; mmc.strokeStyle = 'rgba(212,168,82,.55)'; mmc.lineWidth = 2;
		for (const r of rooms ?? []) { const [x, y] = tx(r.x0, r.z0); mmc.fillRect(x, y, (r.x1 - r.x0) * scale, (r.z1 - r.z0) * scale); mmc.strokeRect(x, y, (r.x1 - r.x0) * scale, (r.z1 - r.z0) * scale); }
		for (const n of nodes ?? []) { const [x, y] = tx(n.x, n.z); mmc.fillStyle = n.done ? '#555' : '#c48a3a'; mmc.beginPath(); mmc.arc(x, y, 5, 0, 7); mmc.fill(); }
		if (gate) { const [x, y] = tx(gate.x, gate.z); mmc.strokeStyle = '#59b8eb'; mmc.lineWidth = 3; mmc.beginPath(); mmc.arc(x, y, 10, 0, 7); mmc.stroke(); }
		if (waypoint) { const [x, y] = tx(waypoint.x, waypoint.z); const d = Math.hypot(x, y); const k = d > R - 14 ? (R - 14) / d : 1; mmc.fillStyle = '#ffd24a'; mmc.beginPath(); mmc.arc(x * k, y * k, 6, 0, 7); mmc.fill(); }
		mmc.fillStyle = '#fff'; mmc.beginPath(); mmc.moveTo(0, -9); mmc.lineTo(6, 7); mmc.lineTo(-6, 7); mmc.closePath();
		mmc.save(); mmc.rotate(-yaw + Math.PI); mmc.fill(); mmc.restore();
		mmc.restore();
	};

	// ---- prompt / subtitle / toast
	let subT = null, toastT = null;
	const setPrompt = (r) => { const p = q('#prompt'); if (!r) { p.classList.add('hidden'); return; } p.classList.remove('hidden'); p.innerHTML = `<kbd>[E]</kbd> ${r.prompt}${r.hold ? ` <span style="opacity:.6">(hold)</span><div class="pb"><i style="width:${Math.round((r.progress ?? 0) * 100)}%"></i></div>` : ''}`; };
	const subtitle = (who, text, { radio = false, dur = 4.5 } = {}) => { const s = q('#sub'); s.className = `panel${radio ? ' radio' : ''}`; s.innerHTML = `<b>${who}:</b> ${text}`; clearTimeout(subT); subT = setTimeout(() => s.classList.add('hidden'), dur * 1000); };
	const toast = (text, dur = 3.5) => { const t = q('#toast'); t.textContent = text; t.classList.remove('hidden'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.add('hidden'), dur * 1000); };
	const zone = (name) => { q('#zone').textContent = name ?? ''; };

	// ---- chapter card
	const showChapter = (title, subtitleText, buttonText, onClick) => {
		chapterCard.innerHTML = `<div><div style="font:12px monospace;letter-spacing:.3em;color:#887">STARGATE UNIVERSE</div><h1>${title}</h1><p>${subtitleText}</p><button>${buttonText}</button></div>`;
		chapterCard.classList.remove('hidden'); chapterCard.querySelector('button').onclick = () => { chapterCard.classList.add('hidden'); onClick?.(); };
	};

	// ---- Kino Remote (full mode, pauses the game)
	const TABS = ['quest', 'character', 'inventory', 'talents', 'ship', 'gate', 'kino', 'log'];
	let tab = 'quest', open = false;
	const renderRemote = () => {
		const s = stats();
		const body = {
			quest: () => `<h2>QUEST LOG</h2><h3 style="color:var(--gold);margin:6px 0">${ctx.chapterTitle()}</h3>` + ctx.steps().map((st, i) => `<div style="opacity:${i < ctx.stepIndex() ? .5 : i === ctx.stepIndex() ? 1 : .35}">${i < ctx.stepIndex() ? '✓' : i === ctx.stepIndex() ? '▸' : '·'} <b>${st.label}</b>${i === ctx.stepIndex() ? `<div style="margin:2px 0 6px 16px;color:#cbb">${st.objective}</div>` : ''}</div>`).join(''),
			character: () => `<h2>CHARACTER</h2><table><tr><td>Level</td><td>${rpg.level}</td><td>XP</td><td>${rpg.xp} / ${xpToNext(rpg.level)}</td></tr>
				<tr><td>Health</td><td>${Math.round(rpg.hp)} / ${s.maxHp}</td><td>Carry</td><td>${carried()} / ${s.carry}</td></tr>
				<tr><td>Move speed</td><td>${Math.round(s.speed * 100)}%</td><td>Dig speed</td><td>${s.canMine ? Math.round(s.mineSpeed * 100) + '%' : '— (no tool)'}</td></tr></table>
				<h2 style="margin-top:14px">EQUIPMENT</h2><div class="slots">${Object.entries(rpg.equipment).map(([slot, id]) => `<div class="gslot"><small>${slot}</small>${id ? `${ITEMS[id]?.name ?? id}<br><button class="btn" data-unequip="${slot}">unequip</button>` : '<span style="color:#554">empty</span>'}</div>`).join('')}</div>`,
			inventory: () => `<h2>INVENTORY</h2><div class="hint">Carry ${carried()} / ${s.carry} — resources are stackable; gear can be equipped.</div><table>${Object.entries(rpg.inventory).map(([id, c]) => `<tr><td><b>${ITEMS[id]?.name ?? id}</b>${c > 1 ? ` ×${c}` : ''}</td><td style="color:#998">${ITEMS[id]?.description ?? ''}</td><td>${ITEMS[id]?.slot ? `<button class="btn" data-equip="${id}">equip</button>` : ''}</td></tr>`).join('') || '<tr><td>Empty</td></tr>'}</table>`,
			talents: () => `<h2>TALENTS</h2><div class="hint">Points available: <b style="color:var(--gold)">${rpg.talentPoints}</b> — one per level.</div><div class="tal" style="margin-top:10px">${TALENTS.map((t) => `<div><b>${t.name}</b> <span style="color:var(--gold)">${rpg.talents[t.id]}/${t.max}</span><div style="color:#aa9;margin:6px 0">${t.desc}</div><button class="btn" data-talent="${t.id}" ${rpg.talentPoints <= 0 || rpg.talents[t.id] >= t.max ? 'disabled' : ''}>Train</button></div>`).join('')}</div>`,
			ship: () => `<h2>SHIP SYSTEMS</h2><table>${ctx.shipStatus().map(([k, v, ok]) => `<tr><td>${k}</td><td style="color:${ok ? '#57bd42' : '#e05040'}">${v}</td></tr>`).join('')}</table>`,
			gate: () => `<h2>GATE CONTROL</h2><div class="hint">Dial a destination. The gate must be idle. Destiny's address is always available from a planet.</div><table>${ctx.planets().map((p) => `<tr><td><b>${p.name}</b></td><td style="color:#998">${p.scan ? p.scan : 'no scan data'}</td><td><button class="btn" data-dial="${p.id}" ${p.canDial ? '' : 'disabled'}>Dial</button></td></tr>`).join('')}</table>`,
			kino: () => `<h2>KINO CONTROL</h2><div class="hint">Kinos: ${count('kino_orb')}. Launch one to fly it through an active gate; the Kino reports the atmosphere on the far side. Fly with WASD, mouse to look, Space up / Shift down. TAB or E recalls it.</div><p><button class="btn" data-launch="1" ${ctx.canLaunchKino() ? '' : 'disabled'}>Launch Kino</button></p>${ctx.lastScan() ? `<h2 style="margin-top:14px">LAST SCAN — ${ctx.lastScan().name}</h2><table>${Object.entries(ctx.lastScan().atmosphere).map(([k, v]) => `<tr><td>${k}</td><td>${v}</td></tr>`).join('')}</table>` : ''}`,
			log: () => `<h2>LOG</h2>${rpg.log.slice().reverse().map((t) => `<div style="color:#dcb">${t}</div>`).join('')}`,
		}[tab]();
		remote.innerHTML = `<div class="dev"><nav>${TABS.map((t) => `<button class="${t === tab ? 'on' : ''}" data-tab="${t}">${t.toUpperCase()}</button>`).join('')}<div style="flex:1"></div><div class="hint" style="padding:10px 14px">TAB / Esc closes</div></nav><section>${body}</section></div>`;
		remote.querySelectorAll('[data-tab]').forEach((b) => (b.onclick = () => { tab = b.dataset.tab; renderRemote(); }));
		remote.querySelectorAll('[data-equip]').forEach((b) => (b.onclick = () => { equip(b.dataset.equip); renderRemote(); }));
		remote.querySelectorAll('[data-unequip]').forEach((b) => (b.onclick = () => { unequip(b.dataset.unequip); renderRemote(); }));
		remote.querySelectorAll('[data-talent]').forEach((b) => (b.onclick = () => { spendTalent(b.dataset.talent); renderRemote(); }));
		remote.querySelectorAll('[data-dial]').forEach((b) => (b.onclick = () => { closeRemote(); ctx.onDial(b.dataset.dial); }));
		remote.querySelectorAll('[data-launch]').forEach((b) => (b.onclick = () => { closeRemote(); ctx.onLaunchKino(); }));
	};
	const openRemote = (t) => { if (t) tab = t; open = true; remote.classList.remove('hidden'); renderRemote(); if (document.pointerLockElement) document.exitPointerLock(); };
	const closeRemote = () => { open = false; remote.classList.add('hidden'); ctx.onResume?.(); };
	hud.querySelectorAll('#menu button').forEach((b) => (b.onclick = () => openRemote(b.dataset.tab === 'map' ? 'ship' : b.dataset.tab)));

	return { refreshPlayer, refreshTracker, drawMinimap, setPrompt, subtitle, toast, zone, showChapter, openRemote, closeRemote, isRemoteOpen: () => open, renderRemote };
};
