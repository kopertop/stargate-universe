// Map editor: hand-author the Destiny deck (rooms, door connections, placed components) and chapter planets, in the same
// JSON the game and the Godot build read: data/ship_layout.json, data/room_connections.json, web/gate-room/data/chapters.json.
// Doors are derived from shared edges exactly as the game does (ship.js), so what you see is what gets built.
import { roomsFromLayout, doorsFromLayout } from './ship.js';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from './components.js';

const $ = (s) => document.querySelector(s);
const S = 0.05, SNAP = 50; // JSON units (1 u = 5 cm) — the editor works in JSON space
const state = { layout: [], connections: {}, chapters: null, floor: 0, sel: null, selProp: null, placing: null, view: { x: 0, y: 0, k: 0.28 }, dirty: false };
const status = (t) => { $('#status').textContent = t; };

// ---------------------------------------------------------------- data
const load = async () => {
	[state.layout, state.connections, state.chapters] = await Promise.all(['/data/ship_layout.json', '/data/room_connections.json', '/web/gate-room/data/chapters.json'].map((u) => fetch(u, { cache: 'reload' }).then((r) => r.json())));
	for (const r of state.layout) { r.width = r.endX - r.startX; r.height = r.endY - r.startY; }
	fillFloors(); fillChapters(); fit(); status(`loaded ${state.layout.length} rooms`);
};
const touch = () => { state.dirty = true; try { localStorage.setItem('sgu.layout.live', JSON.stringify({ layout: state.layout, connections: state.connections, chapters: state.chapters })); } catch {} draw(); };
const put = async (path, data) => { const r = await fetch(path, { method: 'PUT', body: JSON.stringify(data) }); if (!r.ok) throw new Error(`${path}: ${await r.text()}`); return r.text(); };
$('#save').onclick = async () => {
	try { await put('/data/ship_layout.json', state.layout); await put('/data/room_connections.json', state.connections); await put('/web/gate-room/data/chapters.json', state.chapters); state.dirty = false; status('saved to repo'); }
	catch (e) { status(`save failed (${e.message}) — use Download, or run tools/edit_server.py`); }
};
$('#download').onclick = () => { for (const [n, d] of [['ship_layout.json', state.layout], ['room_connections.json', state.connections], ['chapters.json', state.chapters]]) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(d, null, '\t')], { type: 'application/json' })); a.download = n; a.click(); } };
$('#preview-toggle').onclick = () => { const p = $('#preview'); p.classList.toggle('open'); if (p.classList.contains('open') && !$('#frame').src) reloadPreview(); resize(); };
const reloadPreview = () => { touch(); $('#frame').src = `./index.html?layout=live&t=${Date.now()}`; };
$('#preview-reload').onclick = reloadPreview;
document.querySelectorAll('.tabs button').forEach((b) => (b.onclick = () => { document.querySelectorAll('.tabs button').forEach((x) => x.classList.toggle('on', x === b)); $('#tab-ship').hidden = b.dataset.tab !== 'ship'; $('#tab-planets').hidden = b.dataset.tab !== 'planets'; }));

// ---------------------------------------------------------------- geometry helpers (JSON space ↔ room fractions ↔ world)
const rooms = () => state.layout.filter((r) => r.floor === state.floor);
const propJson = (r, p) => ({ X: r.endX - p.v * (r.endX - r.startX), Y: r.startY + p.u * (r.endY - r.startY) }); // world z = -X·S, x = Y·S
const propFrac = (r, X, Y) => ({ u: (Y - r.startY) / (r.endY - r.startY), v: (r.endX - X) / (r.endX - r.startX) });
const propsOf = (r) => r.props ?? ROOM_PROPS[r.id] ?? DEFAULT_PROPS[r.type] ?? [];
const ownProps = (r) => { if (!r.props) r.props = propsOf(r).map((p) => ({ ...p })); return r.props; }; // materialise defaults before editing
const doorsNow = () => doorsFromLayout(roomsFromLayout(state.layout.filter((r) => r.floor === state.floor).map((r) => ({ ...r, floor: 0 }))), state.connections);
const snap = (v) => Math.round(v / SNAP) * SNAP;

// ---------------------------------------------------------------- canvas
const cv = $('#map'), g = cv.getContext('2d');
const toScreen = (X, Y) => [(X - state.view.x) * state.view.k + cv.width / 2, (Y - state.view.y) * state.view.k + cv.height / 2];
const toJson = (sx, sy) => [(sx - cv.width / 2) / state.view.k + state.view.x, (sy - cv.height / 2) / state.view.k + state.view.y];
const resize = () => { const r = cv.getBoundingClientRect(); cv.width = r.width * devicePixelRatio; cv.height = r.height * devicePixelRatio; draw(); };
const fit = () => { const rs = rooms(); if (!rs.length) return; const x0 = Math.min(...rs.map((r) => r.startX)), x1 = Math.max(...rs.map((r) => r.endX)), y0 = Math.min(...rs.map((r) => r.startY)), y1 = Math.max(...rs.map((r) => r.endY)); state.view.x = (x0 + x1) / 2; state.view.y = (y0 + y1) / 2; state.view.k = Math.min(cv.width / (x1 - x0 + 400), cv.height / (y1 - y0 + 400)); draw(); };
$('#fit').onclick = fit;
const draw = () => {
	const k = state.view.k; g.clearRect(0, 0, cv.width, cv.height);
	// grid (100 u = 5 m)
	g.strokeStyle = 'rgba(111,179,232,.07)'; g.lineWidth = 1; const [gx0, gy0] = toJson(0, 0), [gx1, gy1] = toJson(cv.width, cv.height);
	for (let X = Math.floor(gx0 / 100) * 100; X < gx1; X += 100) { const [sx] = toScreen(X, 0); g.beginPath(); g.moveTo(sx, 0); g.lineTo(sx, cv.height); g.stroke(); }
	for (let Y = Math.floor(gy0 / 100) * 100; Y < gy1; Y += 100) { const [, sy] = toScreen(0, Y); g.beginPath(); g.moveTo(0, sy); g.lineTo(cv.width, sy); g.stroke(); }
	for (const r of rooms()) {
		const [sx, sy] = toScreen(r.startX, r.startY), w = (r.endX - r.startX) * k, h = (r.endY - r.startY) * k, sel = r === state.sel;
		g.fillStyle = sel ? 'rgba(212,168,82,.28)' : r.key_room ? 'rgba(80,140,200,.3)' : 'rgba(80,140,200,.16)'; g.fillRect(sx, sy, w, h);
		g.strokeStyle = sel ? '#d4a852' : '#6fb3e8'; g.lineWidth = sel ? 2 : 1; g.strokeRect(sx, sy, w, h);
		if (w > 60) { g.fillStyle = '#cfe4f5'; g.font = `${Math.max(9, Math.min(14, 11 * devicePixelRatio))}px sans-serif`; g.textAlign = 'center'; g.fillText(r.name, sx + w / 2, sy + h / 2 + 4, w - 8); }
		for (const p of propsOf(r)) { // component footprints
			const { X, Y } = propJson(r, p), [px, py] = toScreen(X, Y), c = COMPONENTS[p.type]; if (!c) continue;
			const [cw, cd] = c.size, ry = p.ry ?? 0; g.save(); g.translate(px, py); g.rotate(-ry);
			const psel = state.sel === r && state.selProp === p; g.fillStyle = psel ? '#ffd24a' : p.type === 'marker' ? 'rgba(255,210,74,.35)' : 'rgba(230,214,168,.75)';
			g.fillRect(-cd / S / 2 * k, -cw / S / 2 * k, cd / S * k, cw / S * k); g.restore();
			if (p.anchor && k > 0.3) { g.fillStyle = '#ffd24a'; g.font = '10px monospace'; g.textAlign = 'left'; g.fillText(p.anchor, px + 6, py - 4); }
		}
		if (sel) { g.fillStyle = '#d4a852'; for (const [hx, hy] of [[sx + w, sy + h], [sx, sy], [sx + w, sy], [sx, sy + h]]) g.fillRect(hx - 5, hy - 5, 10, 10); }
	}
	for (const d of doorsNow()) { // world → JSON: X = -z/S, Y = x/S
		const wx = d.axis === 'x' ? d.at : d.center, wz = d.axis === 'x' ? d.center : d.at, [sx, sy] = toScreen(-wz / S, wx / S);
		g.fillStyle = d.jammed ? '#e05040' : d.sealed ? '#888' : '#59e0a0'; g.beginPath(); g.arc(sx, sy, 4.5, 0, 7); g.fill();
	}
	g.fillStyle = '#887'; g.font = '11px monospace'; g.textAlign = 'left'; g.fillText(`floor ${state.floor} · ${rooms().length} rooms · ${doorsNow().length} doors · ${(1 / k).toFixed(1)} u/px${state.dirty ? ' · unsaved' : ''}`, 10, cv.height - 10);
};

// ---------------------------------------------------------------- interaction
let drag = null;
const hitRoom = (X, Y) => rooms().slice().reverse().find((r) => X >= r.startX && X <= r.endX && Y >= r.startY && Y <= r.endY);
const hitProp = (r, X, Y) => propsOf(r).find((p) => { const j = propJson(r, p); return Math.hypot(j.X - X, j.Y - Y) < 30; });
cv.onmousedown = (e) => {
	const [X, Y] = toJson(e.offsetX * devicePixelRatio, e.offsetY * devicePixelRatio); const r = hitRoom(X, Y);
	if (state.placing && state.sel && r === state.sel) { const comp = COMPONENTS[state.placing]; const p = { type: state.placing, ...propFrac(r, X, Y), ry: 0 }; if (comp.defaultAnchor) p.anchor = comp.defaultAnchor; ownProps(r).push(p); state.selProp = p; state.placing = null; renderPalette(); renderProp(); touch(); return; }
	if (e.shiftKey && state.sel && r && r !== state.sel) { toggleConnection(state.sel, r); return; }
	if (r) {
		if (state.sel === r) { const nearCorner = Math.abs(X - r.endX) < 25 / state.view.k && Math.abs(Y - r.endY) < 25 / state.view.k; if (nearCorner) { drag = { kind: 'resize', r }; return; } const p = hitProp(r, X, Y); if (p) { state.selProp = p; drag = { kind: 'prop', r, p }; renderProp(); draw(); return; } }
		state.sel = r; state.selProp = null; drag = { kind: 'move', r, dx: X - r.startX, dy: Y - r.startY, w: r.endX - r.startX, h: r.endY - r.startY }; renderRoom(); renderProp(); draw(); return;
	}
	state.sel = null; state.selProp = null; renderRoom(); renderProp(); drag = { kind: 'pan', sx: e.clientX, sy: e.clientY, vx: state.view.x, vy: state.view.y }; draw();
};
cv.onmousemove = (e) => {
	if (!drag) return; const [X, Y] = toJson(e.offsetX * devicePixelRatio, e.offsetY * devicePixelRatio);
	if (drag.kind === 'pan') { state.view.x = drag.vx - (e.clientX - drag.sx) * devicePixelRatio / state.view.k; state.view.y = drag.vy - (e.clientY - drag.sy) * devicePixelRatio / state.view.k; draw(); }
	else if (drag.kind === 'move') { const r = drag.r; r.startX = snap(X - drag.dx); r.startY = snap(Y - drag.dy); r.endX = r.startX + drag.w; r.endY = r.startY + drag.h; touch(); }
	else if (drag.kind === 'resize') { const r = drag.r; r.endX = Math.max(r.startX + 100, snap(X)); r.endY = Math.max(r.startY + 100, snap(Y)); r.width = r.endX - r.startX; r.height = r.endY - r.startY; touch(); renderRoom(); }
	else if (drag.kind === 'prop') { const f = propFrac(drag.r, X, Y); const p = ownProps(drag.r).find((q) => q === drag.p) ?? drag.p; p.u = Math.min(0.99, Math.max(0.01, f.u)); p.v = Math.min(0.99, Math.max(0.01, f.v)); touch(); }
};
cv.onmouseup = () => { if (drag?.kind === 'move') renderRoom(); drag = null; };
cv.onwheel = (e) => { e.preventDefault(); const f = Math.exp(-e.deltaY * 0.0015); state.view.k = Math.min(3, Math.max(0.04, state.view.k * f)); draw(); };
addEventListener('keydown', (e) => {
	if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
	if (e.key === 'Escape') { state.placing = null; renderPalette(); }
	if ((e.key === 'Delete' || e.key === 'Backspace') && state.sel) { if (state.selProp) { const ps = ownProps(state.sel); ps.splice(ps.indexOf(state.selProp), 1); state.selProp = null; renderProp(); touch(); } else deleteRoom(); }
	if (e.key === 'r' && state.selProp) { const p = ownProps(state.sel).find((q) => q === state.selProp) ?? state.selProp; p.ry = ((p.ry ?? 0) + Math.PI / 4) % (Math.PI * 2); renderProp(); touch(); }
});
addEventListener('resize', resize);

// ---------------------------------------------------------------- rooms / connections
const TYPES = ['corridor', 'gate_room', 'control_room', 'quarters', 'storage', 'infirmary', 'elevator', 'shuttle-dock', 'hydroponics', 'engineering', 'mess_hall', 'lab', 'bridge'];
const fillFloors = () => { const fl = [...new Set(state.layout.map((r) => r.floor))].sort(); $('#floor').innerHTML = fl.map((f) => `<option value="${f}">Floor ${f}</option>`).join('') + '<option value="new">+ new floor</option>'; $('#floor').value = String(state.floor); };
$('#floor').onchange = (e) => { if (e.target.value === 'new') { state.floor = Math.max(...state.layout.map((r) => r.floor)) + 1; addRoom(); fillFloors(); } else state.floor = +e.target.value; state.sel = null; renderRoom(); fit(); };
const addRoom = () => { const id = `room_${Date.now().toString(36)}`; const r = { id, template_id: 'corridor-template', layout_id: 'destiny', type: 'corridor', name: 'New Room', startX: snap(state.view.x - 200), endX: snap(state.view.x + 200), startY: snap(state.view.y - 150), endY: snap(state.view.y + 150), floor: state.floor, width: 400, height: 300, found: false, locked: false, explored: false, status: 'unexplored', key_room: false }; state.layout.push(r); state.sel = r; renderRoom(); touch(); };
$('#add-room').onclick = addRoom;
const deleteRoom = () => { const r = state.sel; if (!r) return; state.layout.splice(state.layout.indexOf(r), 1); delete state.connections[r.id]; for (const k in state.connections) state.connections[k] = state.connections[k].filter((c) => c.to !== r.id); state.sel = null; renderRoom(); touch(); };
$('#del-room').onclick = deleteRoom;
const dirBetween = (a, b) => { const ax = (a.startX + a.endX) / 2, ay = (a.startY + a.endY) / 2, bx = (b.startX + b.endX) / 2, by = (b.startY + b.endY) / 2; return Math.abs(bx - ax) > Math.abs(by - ay) ? (bx > ax ? '+x' : '-x') : (by > ay ? '+z' : '-z'); };
const toggleConnection = (a, b) => {
	const la = (state.connections[a.id] ??= []), ia = la.findIndex((c) => c.to === b.id), lb = state.connections[b.id] ?? [], ib = lb.findIndex((c) => c.to === a.id);
	if (ia >= 0) la.splice(ia, 1); else if (ib >= 0) lb.splice(ib, 1); else la.push({ dir: dirBetween(a, b), to: b.id, plaque: b.name });
	status(ia >= 0 || ib >= 0 ? `removed connection ${a.id} ↔ ${b.id}` : `connected ${a.id} → ${b.id} (needs a shared wall ≥ 2.8 m to get a door)`); touch();
};
const renderRoom = () => {
	const r = state.sel; $('#del-room').disabled = !r; if (!r) { $('#room-form').innerHTML = '<span class="hint">Select a room.</span>'; return; }
	const links = (state.connections[r.id] ?? []).map((c) => c.to).concat(Object.entries(state.connections).filter(([, l]) => l.some((c) => c.to === r.id)).map(([k]) => k));
	$('#room-form').innerHTML = `
		<div class="row"><label>id</label><input data-k="id" value="${r.id}"></div>
		<div class="row"><label>name</label><input data-k="name" value="${r.name}"></div>
		<div class="row"><label>type</label><select data-k="type">${TYPES.map((t) => `<option ${t === r.type ? 'selected' : ''}>${t}</option>`).join('')}</select></div>
		<div class="row"><label>key room</label><input type="checkbox" data-k="key_room" ${r.key_room ? 'checked' : ''}></div>
		<div class="row"><label>startX / endX</label><div style="display:flex;gap:4px"><input data-k="startX" type="number" step="50" value="${r.startX}"><input data-k="endX" type="number" step="50" value="${r.endX}"></div></div>
		<div class="row"><label>startY / endY</label><div style="display:flex;gap:4px"><input data-k="startY" type="number" step="50" value="${r.startY}"><input data-k="endY" type="number" step="50" value="${r.endY}"></div></div>
		<div class="hint">${((r.endX - r.startX) * S).toFixed(1)} × ${((r.endY - r.startY) * S).toFixed(1)} m · doors to: ${links.join(', ') || 'none (shift-click a neighbour)'}</div>
		<div class="hint">${r.props ? `${r.props.length} placed components <button data-reset="1">reset to defaults</button>` : `using ${propsOf(r).length} default components (edit to customise)`}</div>`;
	$('#room-form').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const k = inp.dataset.k, v = inp.type === 'checkbox' ? inp.checked : inp.type === 'number' ? +inp.value : inp.value; if (k === 'id') { for (const l of Object.values(state.connections)) for (const c of l) if (c.to === r.id) c.to = v; if (state.connections[r.id]) { state.connections[v] = state.connections[r.id]; delete state.connections[r.id]; } } r[k] = v; r.width = r.endX - r.startX; r.height = r.endY - r.startY; touch(); renderRoom(); }));
	$('#room-form').querySelector('[data-reset]')?.addEventListener('click', () => { delete r.props; state.selProp = null; renderRoom(); renderProp(); touch(); });
};
const renderPalette = () => { $('#palette').innerHTML = Object.entries(COMPONENTS).map(([k, c]) => `<button data-c="${k}" class="${state.placing === k ? 'on' : ''}" ${state.sel ? '' : 'disabled'}>${c.label}</button>`).join(''); $('#palette').querySelectorAll('[data-c]').forEach((b) => (b.onclick = () => { state.placing = state.placing === b.dataset.c ? null : b.dataset.c; renderPalette(); })); };
const renderProp = () => {
	renderPalette(); const p = state.selProp; if (!p) { $('#prop-form').innerHTML = ''; return; }
	$('#prop-form').innerHTML = `<h2>${COMPONENTS[p.type]?.label ?? p.type}</h2><div class="row"><label>anchor</label><input data-pk="anchor" value="${p.anchor ?? ''}" placeholder="(none)"></div><div class="row"><label>rotation</label><input data-pk="ry" type="range" min="0" max="6.283" step="0.0873" value="${p.ry ?? 0}"></div><div class="row"><label>u / v</label><div style="display:flex;gap:4px"><input data-pk="u" type="number" step="0.01" value="${(+p.u).toFixed(3)}"><input data-pk="v" type="number" step="0.01" value="${(+p.v).toFixed(3)}"></div></div><div class="hint">Anchors are referenced by quests as <code>${state.sel.id}:${p.anchor || '…'}</code>.</div>`;
	$('#prop-form').querySelectorAll('[data-pk]').forEach((inp) => (inp.oninput = () => { const q = ownProps(state.sel).find((x) => x === p) ?? p; const k = inp.dataset.pk; q[k] = k === 'anchor' ? inp.value || undefined : +inp.value; touch(); }));
};

// ---------------------------------------------------------------- planets
const fillChapters = () => { $('#chapter').innerHTML = state.chapters.chapters.map((c, i) => `<option value="${i}">${c.title}</option>`).join(''); renderPlanet(); };
$('#chapter').onchange = renderPlanet;
const COLOR_KEYS = ['sky_low', 'sky_high', 'ground', 'fog', 'sun', 'rock'];
function renderPlanet() {
	const ch = state.chapters.chapters[+$('#chapter').value || 0]; const pl = (ch.planet ??= { id: `${ch.id}_world`, name: 'New World', biome: {}, atmosphere: {}, resource: {} });
	const field = (obj, k, type = 'text', label = k) => `<div class="row"><label>${label}</label><input data-obj="${obj}" data-k="${k}" type="${type}" value="${pl[obj]?.[k] ?? ''}"></div>`;
	$('#planet-form').innerHTML = `<h2>PLANET</h2><div class="row"><label>id</label><input data-obj="" data-k="id" value="${pl.id}"></div><div class="row"><label>name</label><input data-obj="" data-k="name" value="${pl.name}"></div>
		<h2>BIOME</h2>${COLOR_KEYS.map((k) => field('biome', k, 'color')).join('')}
		<h2>ATMOSPHERE</h2>${field('atmosphere', 'composition')}${field('atmosphere', 'temperature_c', 'number', 'temp °C')}${field('atmosphere', 'radiation')}${field('atmosphere', 'toxins')}<div class="row"><label>breathable</label><input type="checkbox" data-obj="atmosphere" data-k="breathable" ${pl.atmosphere?.breathable ? 'checked' : ''}></div>
		<h2>RESOURCE</h2>${field('resource', 'id')}${field('resource', 'name')}${field('resource', 'color', 'color')}${field('resource', 'count', 'number')}${field('resource', 'required', 'number')}${field('resource', 'verb')}
		<div class="hint">Nodes are scattered 22–60 m from the gate at runtime; count/required drive the mining step. Reload the preview and dial out to see it.</div>`;
	$('#planet-form').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const tgt = inp.dataset.obj ? (pl[inp.dataset.obj] ??= {}) : pl; tgt[inp.dataset.k] = inp.type === 'checkbox' ? inp.checked : inp.type === 'number' ? +inp.value : inp.value; touch(); }));
}

await load(); resize(); fit(); renderPalette();
