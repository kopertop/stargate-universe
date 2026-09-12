// In-game level editor ("leveledit" console command). Takes over the running game: free-fly camera with no collision or
// gravity, HUD/quests/interactables off, and a build menu that edits the same JSON the game and Godot read
// (data/ship_layout.json, data/room_connections.json, data/chapters.json). Every change rebuilds the ship in
// place through ctx.rebuildShip; leaving the editor reloads the game on the edited layout (?layout=live).
import * as THREE from 'three';
import { createDestination } from './destination.js';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from './components.js';

const S = 0.05, SNAP = 50; // layout JSON units (1 u = 5 cm); world x = Y·S, world z = −X·S
const CSS = `
	#le{position:fixed;right:0;top:0;bottom:0;width:340px;z-index:40;background:#0d1219;border-left:1px solid #223;padding:10px 12px;overflow:auto;font:13px -apple-system,system-ui,sans-serif;color:#e8dfc8}
	#le h2{font:600 12px monospace;letter-spacing:.14em;color:#d4a852;margin:12px 0 6px}#le .tabs{display:flex;gap:4px;margin-bottom:8px}#le .tabs button{flex:1}
	#le button{background:#141a24;border:1px solid #8c7038;color:#d4a852;font:12px monospace;padding:5px 8px;cursor:pointer;border-radius:3px}#le button:hover{border-color:#d4a852}#le button.on{background:rgba(212,168,82,.16)}#le button:disabled{opacity:.4}
	#le .row{display:grid;grid-template-columns:96px 1fr;gap:6px;align-items:center;margin:4px 0}#le input,#le select{background:#0a0e14;border:1px solid #334;color:#e8dfc8;padding:4px 6px;font:12px monospace;border-radius:3px;width:100%;box-sizing:border-box}
	#le input[type=color]{padding:0;height:26px}#le input[type=checkbox]{width:auto}#le .palette{display:grid;grid-template-columns:1fr 1fr;gap:4px}#le .hint{color:#887;font-size:11px;line-height:1.4}#le .lebar{display:flex;gap:4px;flex-wrap:wrap}#le kbd{color:#d4a852}
	#le-hud{position:fixed;left:12px;top:12px;z-index:40;font:12px monospace;color:#d4a852;text-shadow:0 1px 2px #000;white-space:pre;pointer-events:none}
	#le-cross{position:fixed;left:50%;top:50%;width:14px;height:14px;margin:-7px;border:1px solid rgba(212,168,82,.8);border-radius:50%;z-index:40;pointer-events:none}
	#le-status{position:fixed;left:12px;bottom:12px;z-index:40;background:rgba(0,0,0,.7);color:#d4a852;padding:4px 10px;font:12px monospace;border:1px solid #8c7038;border-radius:3px;pointer-events:none}`;
const PANEL = `
	<div class="tabs"><button data-tab="ship" class="on">SHIP</button><button data-tab="planets">PLANETS</button></div>
	<div class="lebar"><button id="le-save">Save to repo</button><button id="le-download">Download</button><button id="le-exit">Exit → play map</button></div>
	<div class="hint" style="margin-top:6px"><kbd>WASD</kbd> fly · <kbd>Q</kbd>/<kbd>E</kbd> down/up · <kbd>Shift</kbd> fast · hold <kbd>right mouse</kbd> to look · <kbd>wheel</kbd> speed<br><kbd>left click</kbd> select room / component, or place the chosen component · <kbd>R</kbd> rotate · <kbd>Delete</kbd> remove · <kbd>Esc</kbd> cancel · <kbd>\`</kbd> console</div>
	<div id="le-tab-ship">
		<h2>DECK</h2><div class="row"><label>Floor</label><select id="le-floor"></select></div>
		<div class="lebar"><button id="le-add-room">+ Room at aim</button><button id="le-del-room" disabled>Delete room</button><button id="le-power">Power: on</button></div>
		<h2>ROOM</h2><div id="le-room" class="hint">Click a floor to select a room.</div>
		<h2>COMPONENTS</h2><div class="hint">Pick one, aim at the selected room's floor, click to place.</div><div id="le-palette" class="palette"></div><div id="le-prop"></div>
	</div>
	<div id="le-tab-planets" hidden>
		<h2>CHAPTER</h2><div class="row"><label>Chapter</label><select id="le-chapter"></select></div><div class="lebar"><button id="le-visit">Fly the planet</button></div><div id="le-planet"></div>
	</div>`;

/**
 * @param ctx { renderer, camera, destiny, chapters (mutable array ref holder: {chapters}), rebuildShip(layout, connections),
 *              envTex, input, onEnter(), onExit() }
 */
export const createLevelEditor = (ctx) => {
	const { renderer, camera, destiny, input } = ctx;
	const state = { active: false, layout: null, connections: null, floor: 0, sel: null, selProp: null, placing: null, dirty: false, mode: 'ship', planetWorld: null };
	let root, $, yaw = Math.PI, pitch = 0, speed = 8, looking = false, downAt = null, mouse = { x: 0, y: 0 };
	const cv = renderer.domElement;
	const status = (t) => { const s = document.getElementById('le-status'); if (s) s.textContent = t; };

	// ---- data
	const live = () => { try { localStorage.setItem('sgu.layout.live', JSON.stringify({ layout: state.layout, connections: state.connections, chapters: { chapters: ctx.chapters() } })); } catch {} };
	const put = async (path, data) => { const r = await fetch(path, { method: 'PUT', body: JSON.stringify(data) }); if (!r.ok) throw new Error(`${path}: ${await r.text()}`); return r.text(); };
	const save = async () => {
		for (const r of state.layout) { r.width = r.endX - r.startX; r.height = r.endY - r.startY; }
		try { await put('/data/ship_layout.json', state.layout); await put('/data/room_connections.json', state.connections); await put('/data/chapters.json', { chapters: ctx.chapters() }); state.dirty = false; status('saved to repo'); }
		catch (e) { status(`save failed (${e.message}) — use Download, or serve with tools/edit_server.py`); }
	};
	const download = () => { for (const [n, d] of [['ship_layout.json', state.layout], ['room_connections.json', state.connections], ['chapters.json', { chapters: ctx.chapters() }]]) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(d, null, '\t')], { type: 'application/json' })); a.download = n; a.click(); } };
	const touch = (rebuildScene = true) => { state.dirty = true; live(); if (rebuildScene) rebuild(); renderRoom(); renderProp(); };

	// ---- layout ↔ world
	const roomsOnFloor = () => state.layout.filter((r) => r.floor === state.floor);
	const rect = (r) => ({ x0: r.startY * S, x1: r.endY * S, z0: -r.endX * S, z1: -r.startX * S });
	const roomAtWorld = (p) => roomsOnFloor().find((r) => { const q = rect(r); return p.x >= q.x0 && p.x <= q.x1 && p.z >= q.z0 && p.z <= q.z1; });
	const fracAt = (r, p) => { const q = rect(r); return { u: (p.x - q.x0) / (q.x1 - q.x0), v: (p.z - q.z0) / (q.z1 - q.z0) }; };
	const propsOf = (r) => r.props ?? ROOM_PROPS[r.id] ?? DEFAULT_PROPS[r.type] ?? [];
	const ownProps = (r) => { if (!r.props) r.props = propsOf(r).map((p) => ({ ...p })); return r.props; };
	const snap = (v) => Math.round(v / SNAP) * SNAP;

	// ---- scene helpers (live in the game's Destiny scene)
	const selBox = new THREE.Box3Helper(new THREE.Box3(), 0xd4a852), propBox = new THREE.Box3Helper(new THREE.Box3(), 0xffd24a);
	const ghost = new THREE.Mesh(new THREE.BoxGeometry(1, 0.6, 1), new THREE.MeshBasicMaterial({ color: 0xffd24a, transparent: true, opacity: 0.35, depthWrite: false }));
	selBox.visible = propBox.visible = ghost.visible = false;
	const ship = () => destiny.ship;
	const rebuild = () => { ctx.rebuildShip(state.layout.filter((r) => r.floor === state.floor).map((r) => ({ ...r, floor: 0 })), state.connections); refreshSelection(); const b = document.getElementById('le-power'); if (b) b.textContent = `Power: ${ship().powered ? 'on' : 'off'}`; };
	const refreshSelection = () => {
		selBox.visible = !!state.sel && state.mode === 'ship'; if (state.sel) { const q = rect(state.sel); selBox.box.set(new THREE.Vector3(q.x0, 0, q.z0), new THREE.Vector3(q.x1, 4.6, q.z1)); }
		const mesh = state.selProp && ship().propMeshes.find((m) => m.userData.prop.spec === state.selProp); propBox.visible = !!mesh; if (mesh) propBox.box.setFromObject(mesh);
	};

	// ---- fly camera (right-drag or pointer lock to look)
	const onKey = (e) => {
		if (!state.active || e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
		if (e.code === 'Escape') { state.placing = null; renderPalette(); ghost.visible = false; }
		if ((e.code === 'KeyR' || e.key === 'r') && state.selProp && state.sel) { const p = ownProps(state.sel).find((q) => q === state.selProp) ?? state.selProp; p.ry = ((p.ry ?? 0) + Math.PI / 4) % (Math.PI * 2); state.selProp = p; touch(); }
		if ((e.code === 'Delete' || e.code === 'Backspace') && state.sel) { if (state.selProp) { const ps = ownProps(state.sel); ps.splice(ps.indexOf(state.selProp), 1); state.selProp = null; touch(); } else deleteRoom(); }
	};
	const onDown = (e) => { if (!state.active) return; if (e.button === 2) looking = true; if (e.button === 0) downAt = [e.clientX, e.clientY]; };
	const onUp = (e) => { if (!state.active) return; if (e.button === 2) looking = false; if (e.button === 0 && downAt) { const moved = Math.hypot(e.clientX - downAt[0], e.clientY - downAt[1]); downAt = null; if (moved < 4 && e.target === cv) click(); } };
	const onMove = (e) => { if (!state.active) return; const r = cv.getBoundingClientRect(); mouse = { x: ((e.clientX - r.left) / r.width) * 2 - 1, y: -((e.clientY - r.top) / r.height) * 2 + 1 }; if (looking || document.pointerLockElement === cv) { yaw -= e.movementX * 0.0025; pitch = THREE.MathUtils.clamp(pitch - e.movementY * 0.0025, -1.5, 1.5); } };
	const onWheel = (e) => { if (state.active) speed = THREE.MathUtils.clamp(speed * Math.exp(-e.deltaY * 0.001), 1, 60); };
	const onCtx = (e) => { if (state.active) e.preventDefault(); };
	const fly = (dt) => {
		const k = input.keys, f = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw)), r = new THREE.Vector3(-f.z, 0, f.x), v = new THREE.Vector3();
		if (k.has('KeyW')) v.add(f); if (k.has('KeyS')) v.sub(f); if (k.has('KeyD')) v.add(r); if (k.has('KeyA')) v.sub(r); if (k.has('KeyE') || k.has('Space')) v.y += 1; if (k.has('KeyQ')) v.y -= 1;
		if (v.lengthSq()) camera.position.addScaledVector(v.normalize(), speed * (k.has('ShiftLeft') ? 3 : 1) * dt);
		camera.rotation.set(0, 0, 0); camera.rotateY(yaw); camera.rotateX(pitch);
	};

	// ---- picking / placing (at the mouse; crosshair when pointer-locked)
	const ray = new THREE.Raycaster();
	const aim = () => { ray.setFromCamera(document.pointerLockElement === cv ? { x: 0, y: 0 } : mouse, camera); const floors = []; ship().group.traverse((o) => { if (o.userData.roomId) floors.push(o); }); return ray.intersectObjects([...floors, ...ship().propMeshes, ...ship().occludable], false)[0] ?? null; };
	const click = () => {
		if (state.mode !== 'ship') return; const hit = aim(); if (!hit) return;
		if (state.placing && state.sel) {
			const room = roomAtWorld(hit.point); if (room !== state.sel) { status('aim inside the selected room'); return; }
			const comp = COMPONENTS[state.placing], f = fracAt(room, hit.point), p = { type: state.placing, u: +THREE.MathUtils.clamp(f.u, 0.03, 0.97).toFixed(3), v: +THREE.MathUtils.clamp(f.v, 0.03, 0.97).toFixed(3), ry: Math.round((yaw + Math.PI) / (Math.PI / 4)) * (Math.PI / 4) % (Math.PI * 2) };
			if (comp.defaultAnchor) p.anchor = comp.defaultAnchor; ownProps(room).push(p); state.selProp = p; state.placing = null; ghost.visible = false; touch(); status(`placed ${comp.label} in ${room.name}`); return;
		}
		if (hit.object.userData.prop) { const { roomId, spec } = hit.object.userData.prop; const room = state.layout.find((r) => r.id === roomId); state.sel = room; state.selProp = (room.props ?? []).find((q) => q === spec) ?? ownProps(room).find((q) => q.type === spec.type && Math.abs(q.u - spec.u) < 1e-6 && Math.abs(q.v - spec.v) < 1e-6) ?? null; }
		else { state.sel = roomAtWorld(hit.point) ?? null; state.selProp = null; }
		renderRoom(); renderProp(); refreshSelection();
	};
	const tickGhost = () => {
		ghost.visible = false; if (!state.placing || !state.sel || state.mode !== 'ship') return;
		const hit = aim(); if (!hit) return; const room = roomAtWorld(hit.point); if (room !== state.sel) return;
		const [w, d] = COMPONENTS[state.placing].size; ghost.scale.set(w, 1, d); ghost.position.set(hit.point.x, 0.3, hit.point.z); ghost.rotation.y = Math.round((yaw + Math.PI) / (Math.PI / 4)) * (Math.PI / 4); ghost.visible = true;
	};

	// ---- rooms / connections
	const TYPES = ['corridor', 'gate_room', 'control_room', 'quarters', 'storage', 'infirmary', 'elevator', 'shuttle-dock', 'hydroponics', 'engineering', 'mess_hall', 'lab', 'bridge'];
	const fillFloors = () => { const fl = [...new Set(state.layout.map((r) => r.floor))].sort(); $('#le-floor').innerHTML = fl.map((f) => `<option value="${f}">Floor ${f}</option>`).join('') + '<option value="new">+ new floor</option>'; $('#le-floor').value = String(state.floor); };
	const addRoom = () => {
		const hit = aim(); const p = hit?.point ?? camera.position.clone().addScaledVector(new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw)), 8);
		const X = snap(-p.z / S), Y = snap(p.x / S), id = `room_${Date.now().toString(36)}`;
		state.layout.push({ id, template_id: 'corridor-template', layout_id: 'destiny', type: 'corridor', name: 'New Room', startX: X - 200, endX: X + 200, startY: Y - 150, endY: Y + 150, floor: state.floor, width: 400, height: 300, found: false, locked: false, explored: false, status: 'unexplored', key_room: false });
		state.sel = state.layout.at(-1); state.selProp = null; touch(); status(`added ${id} — link it with "toggle door to…" in the room panel`);
	};
	const deleteRoom = () => { const r = state.sel; if (!r || r.type === 'gate_room') { status('the gate room is anchored to the gate hall and cannot be deleted'); return; } state.layout.splice(state.layout.indexOf(r), 1); delete state.connections[r.id]; for (const k in state.connections) state.connections[k] = state.connections[k].filter((c) => c.to !== r.id); state.sel = null; state.selProp = null; touch(); };
	const dirBetween = (a, b) => { const ax = (a.startX + a.endX) / 2, ay = (a.startY + a.endY) / 2, bx = (b.startX + b.endX) / 2, by = (b.startY + b.endY) / 2; return Math.abs(bx - ax) > Math.abs(by - ay) ? (bx > ax ? '+x' : '-x') : (by > ay ? '+z' : '-z'); };
	const toggleConnection = (a, b) => {
		const la = (state.connections[a.id] ??= []), ia = la.findIndex((c) => c.to === b.id), lb = state.connections[b.id] ?? [], ib = lb.findIndex((c) => c.to === a.id);
		if (ia >= 0) la.splice(ia, 1); else if (ib >= 0) lb.splice(ib, 1); else la.push({ dir: dirBetween(a, b), to: b.id, plaque: b.name });
		status(ia >= 0 || ib >= 0 ? `removed link ${a.id} ↔ ${b.id}` : `linked ${a.id} → ${b.id} (a door appears where they share a wall ≥ 2.8 m)`); touch();
	};
	const nudge = (r, k, dv) => { r[k] += dv; if (r.endX - r.startX < 100) r.endX = r.startX + 100; if (r.endY - r.startY < 100) r.endY = r.startY + 100; touch(); };
	const renderRoom = () => {
		if (!root) return; const r = state.sel; $('#le-del-room').disabled = !r; if (!r) { $('#le-room').innerHTML = '<span class="hint">Click a floor to select a room.</span>'; return; }
		const linked = new Set([...(state.connections[r.id] ?? []).map((c) => c.to), ...Object.entries(state.connections).filter(([, l]) => l.some((c) => c.to === r.id)).map(([k]) => k)]);
		$('#le-room').innerHTML = `
			<div class="row"><label>id</label><input data-k="id" value="${r.id}"></div><div class="row"><label>name</label><input data-k="name" value="${r.name}"></div>
			<div class="row"><label>type</label><select data-k="type">${TYPES.map((t) => `<option ${t === r.type ? 'selected' : ''}>${t}</option>`).join('')}</select></div>
			<div class="row"><label>key room</label><input type="checkbox" data-k="key_room" ${r.key_room ? 'checked' : ''}></div>
			<div class="row"><label>along ship (X)</label><div class="lebar"><button data-n="startX,-50">◀ start</button><button data-n="startX,50">start ▶</button><button data-n="endX,-50">◀ end</button><button data-n="endX,50">end ▶</button></div></div>
			<div class="row"><label>across (Y)</label><div class="lebar"><button data-n="startY,-50">◀ start</button><button data-n="startY,50">start ▶</button><button data-n="endY,-50">◀ end</button><button data-n="endY,50">end ▶</button></div></div>
			<div class="row"><label>move</label><div class="lebar"><button data-m="X,-50">−X</button><button data-m="X,50">+X</button><button data-m="Y,-50">−Y</button><button data-m="Y,50">+Y</button></div></div>
			<div class="hint">${((r.endX - r.startX) * S).toFixed(1)} × ${((r.endY - r.startY) * S).toFixed(1)} m · X ${r.startX}…${r.endX} · Y ${r.startY}…${r.endY}</div>
			<div class="row"><label>link</label><select data-link><option value="">toggle door to…</option>${roomsOnFloor().filter((o) => o !== r).map((o) => `<option value="${o.id}">${linked.has(o.id) ? '✓ ' : ''}${o.name} (${o.id})</option>`).join('')}</select></div>
			<div class="hint">${r.props ? `${r.props.length} placed components <button data-reset="1">reset to defaults</button>` : `using ${propsOf(r).length} default components (placing one makes them editable)`}</div>`;
		$('#le-room').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const k = inp.dataset.k, v = inp.type === 'checkbox' ? inp.checked : inp.value; if (k === 'id') { for (const l of Object.values(state.connections)) for (const c of l) if (c.to === r.id) c.to = v; if (state.connections[r.id]) { state.connections[v] = state.connections[r.id]; delete state.connections[r.id]; } } r[k] = v; touch(); }));
		$('#le-room').querySelectorAll('[data-n]').forEach((b) => (b.onclick = () => { const [k, dv] = b.dataset.n.split(','); nudge(r, k, +dv); }));
		$('#le-room').querySelectorAll('[data-m]').forEach((b) => (b.onclick = () => { const [ax, dv] = b.dataset.m.split(','); r[`start${ax}`] += +dv; r[`end${ax}`] += +dv; touch(); }));
		$('#le-room').querySelector('[data-link]').onchange = (e) => { const o = state.layout.find((x) => x.id === e.target.value); if (o) toggleConnection(r, o); };
		$('#le-room').querySelector('[data-reset]')?.addEventListener('click', () => { delete r.props; state.selProp = null; touch(); });
	};
	const renderPalette = () => { if (!root) return; $('#le-palette').innerHTML = Object.entries(COMPONENTS).map(([k, c]) => `<button data-c="${k}" class="${state.placing === k ? 'on' : ''}" ${state.sel ? '' : 'disabled'}>${c.label}</button>`).join(''); $('#le-palette').querySelectorAll('[data-c]').forEach((b) => (b.onclick = () => { state.placing = state.placing === b.dataset.c ? null : b.dataset.c; renderPalette(); })); };
	const renderProp = () => {
		if (!root) return; renderPalette(); const p = state.selProp; if (!p) { $('#le-prop').innerHTML = ''; return; }
		$('#le-prop').innerHTML = `<h2>${COMPONENTS[p.type]?.label ?? p.type}</h2><div class="row"><label>anchor</label><input data-pk="anchor" value="${p.anchor ?? ''}" placeholder="(none)"></div><div class="row"><label>rotation</label><input data-pk="ry" type="range" min="0" max="6.283" step="0.0873" value="${p.ry ?? 0}"></div><div class="row"><label>u / v</label><div style="display:flex;gap:4px"><input data-pk="u" type="number" step="0.01" value="${(+p.u).toFixed(3)}"><input data-pk="v" type="number" step="0.01" value="${(+p.v).toFixed(3)}"></div></div>${p.type === 'crate' ? `<div class="row"><label>style</label><select data-pk="style"><option value="" ${!p.style ? 'selected' : ''}>auto (fuse → ancient)</option><option ${p.style === 'ancient' ? 'selected' : ''}>ancient</option><option ${p.style === 'pelican' ? 'selected' : ''}>pelican</option></select></div><div class="row"><label>loot</label><input data-pk="loot" value="${(p.loot ?? []).map((it) => `${it.id}${(it.n ?? 1) > 1 ? `×${it.n}` : ''}`).join(', ')}" placeholder="large_fuse, rations×3"></div>` : ''}<div class="hint">Quests reference this as <code>${state.sel?.id}:${p.anchor || '…'}</code>.</div>`;
		$('#le-prop').querySelectorAll('[data-pk]').forEach((inp) => (inp.onchange = () => { const q = ownProps(state.sel).find((x) => x === p) ?? p; const k = inp.dataset.pk; q[k] = k === 'anchor' || k === 'style' ? inp.value || undefined : k === 'loot' ? (inp.value.trim() ? inp.value.split(',').map((t) => { const [id, n] = t.trim().split(/[×x]/); return n ? { id: id.trim(), n: +n } : { id: id.trim() }; }).filter((it) => it.id) : undefined) : +inp.value; state.selProp = q; touch(); })); // loot: "id×n, id" → [{ id, n }]
	};

	// ---- planets (chapter planet defs; fly-through uses destination.js like the game)
	const COLOR_KEYS = ['sky_low', 'sky_high', 'ground', 'fog', 'sun', 'rock'];
	const currentPlanet = () => { const ch = ctx.chapters()[+$('#le-chapter').value || 0]; return (ch.planet ??= { id: `${ch.id}_world`, name: 'New World', biome: {}, atmosphere: {}, resource: {} }); };
	const fillChapters = () => { $('#le-chapter').innerHTML = ctx.chapters().map((c, i) => `<option value="${i}">${c.title}</option>`).join(''); renderPlanet(); };
	const renderPlanet = () => {
		const pl = currentPlanet();
		const field = (obj, k, type = 'text', label = k) => `<div class="row"><label>${label}</label><input data-obj="${obj}" data-k="${k}" type="${type}" value="${(obj ? pl[obj]?.[k] : pl[k]) ?? ''}"></div>`;
		$('#le-planet').innerHTML = `<h2>PLANET</h2>${field('', 'id')}${field('', 'name')}<h2>BIOME</h2>${COLOR_KEYS.map((k) => field('biome', k, 'color')).join('')}
			<h2>ATMOSPHERE</h2>${field('atmosphere', 'composition')}${field('atmosphere', 'temperature_c', 'number', 'temp °C')}${field('atmosphere', 'radiation')}${field('atmosphere', 'toxins')}<div class="row"><label>breathable</label><input type="checkbox" data-obj="atmosphere" data-k="breathable" ${pl.atmosphere?.breathable ? 'checked' : ''}></div>
			<h2>RESOURCE</h2>${field('resource', 'id')}${field('resource', 'name')}${field('resource', 'color', 'color')}${field('resource', 'count', 'number')}${field('resource', 'required', 'number')}${field('resource', 'verb')}
			<div class="hint">Resource nodes scatter 22–60 m from the gate at runtime; count/required drive the mining step.</div>`;
		$('#le-planet').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const tgt = inp.dataset.obj ? (pl[inp.dataset.obj] ??= {}) : pl; tgt[inp.dataset.k] = inp.type === 'checkbox' ? inp.checked : inp.type === 'number' ? +inp.value : inp.value; state.dirty = true; live(); if (state.mode === 'planet') visitPlanet(true); }));
	};
	const visitPlanet = (force = false) => {
		if (state.mode === 'planet' && !force) { state.mode = 'ship'; state.planetWorld = null; $('#le-visit').textContent = 'Fly the planet'; camera.position.set(0, 1.7, 12); yaw = Math.PI; pitch = 0; return; }
		state.planetWorld = createDestination(currentPlanet()); state.planetWorld.scene.environment = ctx.envTex; state.planetWorld.scene.environmentIntensity = 0.6; state.mode = 'planet'; $('#le-visit').textContent = 'Back to the ship';
		if (!force) { camera.position.set(0, 3, 14); yaw = Math.PI; pitch = -0.1; }
	};

	// ---- enter / exit
	const enter = () => {
		if (state.active) return; state.active = true;
		state.layout = destiny.data.layout; state.connections = destiny.data.connections;
		root = document.createElement('div'); root.innerHTML = `<style>${CSS}</style><aside id="le">${PANEL}</aside><div id="le-hud"></div><div id="le-cross"></div><div id="le-status">level editor — fly with WASD, right-drag to look</div>`; document.body.appendChild(root);
		$ = (s) => root.querySelector(s);
		root.querySelectorAll('.tabs button').forEach((b) => (b.onclick = () => { root.querySelectorAll('.tabs button').forEach((x) => x.classList.toggle('on', x === b)); $('#le-tab-ship').hidden = b.dataset.tab !== 'ship'; $('#le-tab-planets').hidden = b.dataset.tab !== 'planets'; }));
		$('#le-save').onclick = save; $('#le-download').onclick = download; $('#le-exit').onclick = exit;
		$('#le-floor').onchange = (e) => { if (e.target.value === 'new') { state.floor = Math.max(...state.layout.map((r) => r.floor)) + 1; addRoom(); fillFloors(); } else state.floor = +e.target.value; state.sel = null; state.selProp = null; touch(); };
		$('#le-add-room').onclick = addRoom; $('#le-del-room').onclick = deleteRoom; $('#le-power').onclick = () => { ship().setPower(!ship().powered); $('#le-power').textContent = `Power: ${ship().powered ? 'on' : 'off'}`; };
		$('#le-chapter').onchange = () => { renderPlanet(); if (state.mode === 'planet') visitPlanet(true); }; $('#le-visit').onclick = () => visitPlanet(false);
		destiny.scene.add(selBox, propBox, ghost);
		yaw = Math.PI; pitch = 0; camera.position.y = Math.max(camera.position.y, 1.7);
		addEventListener('keydown', onKey); cv.addEventListener('mousedown', onDown); addEventListener('mouseup', onUp); addEventListener('mousemove', onMove); cv.addEventListener('wheel', onWheel, { passive: true }); cv.addEventListener('contextmenu', onCtx);
		fillFloors(); fillChapters(); renderRoom(); renderProp(); refreshSelection(); ctx.onEnter?.();
	};
	const exit = () => {
		if (!state.active) return; state.active = false; live();
		removeEventListener('keydown', onKey); cv.removeEventListener('mousedown', onDown); removeEventListener('mouseup', onUp); removeEventListener('mousemove', onMove); cv.removeEventListener('wheel', onWheel); cv.removeEventListener('contextmenu', onCtx);
		destiny.scene.remove(selBox, propBox, ghost); root.remove(); root = null; ctx.onExit?.();
	};
	/** Per frame while active. Returns the scene to render (planet fly-through or the ship). */
	const update = (dt) => {
		fly(dt); tickGhost();
		if (state.mode === 'ship') ship().update(dt, camera.position);
		const hud = document.getElementById('le-hud'); if (hud) { const hit = state.mode === 'ship' ? aim() : null, room = hit ? roomAtWorld(hit.point) : null; hud.textContent = `${state.mode === 'ship' ? `floor ${state.floor} · ${roomsOnFloor().length} rooms · ${ship().doors.length} doors` : `planet: ${currentPlanet().name}`} · speed ${speed.toFixed(0)} m/s${state.dirty ? ' · unsaved' : ''}\n${room ? `aim: ${room.name}` : ''}${state.placing ? ` · placing ${COMPONENTS[state.placing].label}` : ''}`; }
		return state.mode === 'planet' && state.planetWorld ? state.planetWorld.scene : destiny.scene;
	};
	return { state, enter, exit, update, get active() { return state.active; } };
};
