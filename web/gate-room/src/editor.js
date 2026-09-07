// Map builder: first-person free-fly through the real game scene (same builders as the game: gate hall, ship.js rooms/doors,
// components.js props, destination.js planets) with a build menu. Edits the same JSON the game and Godot read
// (data/ship_layout.json, data/room_connections.json, web/gate-room/data/chapters.json); any change rebuilds the scene.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { createGateRoom, ROOM } from './gate-room.js';
import { createStargate, GATE } from './stargate.js';
import { createShip } from './ship.js';
import { createDestination } from './destination.js';
import { COMPONENTS, DEFAULT_PROPS, ROOM_PROPS } from './components.js';

const $ = (s) => document.querySelector(s);
const S = 0.05, SNAP = 50; // layout JSON units (1 u = 5 cm); world x = Y·S, world z = −X·S
const state = { layout: [], connections: {}, chapters: null, floor: 0, sel: null, selProp: null, placing: null, dirty: false, mode: 'ship', powered: true };
const status = (t) => { $('#status').textContent = t; };

// ---------------------------------------------------------------- data
const load = async () => {
	[state.layout, state.connections, state.chapters] = await Promise.all(['/data/ship_layout.json', '/data/room_connections.json', '/web/gate-room/data/chapters.json'].map((u) => fetch(u, { cache: 'reload' }).then((r) => r.json())));
	fillFloors(); fillChapters();
};
const live = () => { try { localStorage.setItem('sgu.layout.live', JSON.stringify({ layout: state.layout, connections: state.connections, chapters: state.chapters })); } catch {} };
const touch = (rebuildScene = true) => { state.dirty = true; live(); if (rebuildScene) rebuild(); renderRoom(); renderProp(); };
const put = async (path, data) => { const r = await fetch(path, { method: 'PUT', body: JSON.stringify(data) }); if (!r.ok) throw new Error(`${path}: ${await r.text()}`); return r.text(); };
$('#save').onclick = async () => {
	for (const r of state.layout) { r.width = r.endX - r.startX; r.height = r.endY - r.startY; }
	try { await put('/data/ship_layout.json', state.layout); await put('/data/room_connections.json', state.connections); await put('/web/gate-room/data/chapters.json', state.chapters); state.dirty = false; status('saved to repo'); }
	catch (e) { status(`save failed (${e.message}) — use Download, or serve with tools/edit_server.py`); }
};
$('#download').onclick = () => { for (const [n, d] of [['ship_layout.json', state.layout], ['room_connections.json', state.connections], ['chapters.json', state.chapters]]) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(d, null, '\t')], { type: 'application/json' })); a.download = n; a.click(); } };
$('#play').onclick = () => { live(); open(`./index.html?layout=live&t=${Date.now()}`, '_blank'); };
document.querySelectorAll('.tabs button').forEach((b) => (b.onclick = () => { document.querySelectorAll('.tabs button').forEach((x) => x.classList.toggle('on', x === b)); $('#tab-ship').hidden = b.dataset.tab !== 'ship'; $('#tab-planets').hidden = b.dataset.tab !== 'planets'; }));

// ---------------------------------------------------------------- helpers (layout ↔ world)
const roomsOnFloor = () => state.layout.filter((r) => r.floor === state.floor);
const rect = (r) => ({ x0: r.startY * S, x1: r.endY * S, z0: -r.endX * S, z1: -r.startX * S });
const roomAtWorld = (p) => roomsOnFloor().find((r) => { const q = rect(r); return p.x >= q.x0 && p.x <= q.x1 && p.z >= q.z0 && p.z <= q.z1; });
const fracAt = (r, p) => { const q = rect(r); return { u: (p.x - q.x0) / (q.x1 - q.x0), v: (p.z - q.z0) / (q.z1 - q.z0) }; };
const propsOf = (r) => r.props ?? ROOM_PROPS[r.id] ?? DEFAULT_PROPS[r.type] ?? [];
const ownProps = (r) => { if (!r.props) r.props = propsOf(r).map((p) => ({ ...p })); return r.props; };
const snap = (v) => Math.round(v / SNAP) * SNAP;

// ---------------------------------------------------------------- scene
const view = $('#view');
const renderer = new THREE.WebGLRenderer({ antialias: true }); renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5)); renderer.shadowMap.enabled = true; renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 0.95; view.appendChild(renderer.domElement);
const camera = new THREE.PerspectiveCamera(65, 1, 0.1, 500); camera.position.set(0, 1.7, 12); camera.add(new THREE.PointLight(0xbfd4f0, 2.5, 10, 1.8));
const envTex = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
let scene, ship, planetWorld = null, propHits = [], floorHits = [];
const shipScene = new THREE.Scene(); shipScene.background = new THREE.Color(0x04060a); shipScene.fog = new THREE.Fog(0x05070c, 26, 90); shipScene.environment = envTex; shipScene.environmentIntensity = 0.28;
const { group: hall } = createGateRoom(renderer); shipScene.add(hall);
const gate = createStargate(); gate.position.set(0, GATE.rInner + ROOM.daisH - 0.15, ROOM.gateZ); shipScene.add(gate);
const selBox = new THREE.Box3Helper(new THREE.Box3(), 0xd4a852); selBox.visible = false; shipScene.add(selBox);
const propBox = new THREE.Box3Helper(new THREE.Box3(), 0xffd24a); propBox.visible = false; shipScene.add(propBox);
const ghost = new THREE.Mesh(new THREE.BoxGeometry(1, 0.6, 1), new THREE.MeshBasicMaterial({ color: 0xffd24a, transparent: true, opacity: 0.35, depthWrite: false })); ghost.visible = false; shipScene.add(ghost);
const rebuild = () => {
	if (ship) { shipScene.remove(ship.group); ship.group.traverse((o) => { o.geometry?.dispose?.(); }); }
	const floorRooms = state.layout.filter((r) => r.floor === state.floor).map((r) => ({ ...r, floor: 0 }));
	ship = createShip(shipScene, [], { layout: floorRooms, connections: state.connections, gateZ: ROOM.gateZ });
	ship.setPower(state.powered); ship.doorSpeed = 1;
	propHits = ship.propMeshes; floorHits = []; ship.group.traverse((o) => { if (o.userData.roomId) floorHits.push(o); });
	shipScene.add(selBox, propBox, ghost); refreshSelection(); $('#power').textContent = `Power: ${state.powered ? 'on' : 'off'}`;
};
const refreshSelection = () => {
	selBox.visible = !!state.sel && state.mode === 'ship'; if (state.sel) { const q = rect(state.sel); selBox.box.set(new THREE.Vector3(q.x0, 0, q.z0), new THREE.Vector3(q.x1, 4.6, q.z1)); }
	const mesh = state.selProp && propHits.find((m) => m.userData.prop.spec === state.selProp); propBox.visible = !!mesh; if (mesh) propBox.box.setFromObject(mesh);
};
$('#power').onclick = () => { state.powered = !state.powered; ship.setPower(state.powered); $('#power').textContent = `Power: ${state.powered ? 'on' : 'off'}`; };

// ---------------------------------------------------------------- fly camera
const keys = new Set(); let yaw = Math.PI, pitch = 0, speed = 8, looking = false, downAt = null;
addEventListener('keydown', (e) => { if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return; keys.add(e.code); if (e.code === 'Escape') { state.placing = null; renderPalette(); ghost.visible = false; } if ((e.code === 'KeyR' || e.key === 'r') && state.selProp && state.sel) { const p = ownProps(state.sel).find((q) => q === state.selProp) ?? state.selProp; p.ry = ((p.ry ?? 0) + Math.PI / 4) % (Math.PI * 2); touch(); } if ((e.code === 'Delete' || e.code === 'Backspace') && state.sel) { if (state.selProp) { const ps = ownProps(state.sel); ps.splice(ps.indexOf(state.selProp), 1); state.selProp = null; touch(); } else deleteRoom(); } });
addEventListener('keyup', (e) => keys.delete(e.code));
const cv = renderer.domElement;
cv.addEventListener('contextmenu', (e) => e.preventDefault());
cv.addEventListener('mousedown', (e) => { if (e.button === 2) looking = true; if (e.button === 0) downAt = [e.clientX, e.clientY]; });
addEventListener('mouseup', (e) => { if (e.button === 2) looking = false; if (e.button === 0 && downAt) { const moved = Math.hypot(e.clientX - downAt[0], e.clientY - downAt[1]); downAt = null; if (moved < 4) click(e); } });
addEventListener('mousemove', (e) => { if (looking || document.pointerLockElement === cv) { yaw -= e.movementX * 0.0025; pitch = THREE.MathUtils.clamp(pitch - e.movementY * 0.0025, -1.5, 1.5); } });
cv.addEventListener('dblclick', () => cv.requestPointerLock?.().catch?.(() => {}));
cv.addEventListener('wheel', (e) => { speed = THREE.MathUtils.clamp(speed * Math.exp(-e.deltaY * 0.001), 1, 60); }, { passive: true });
const fly = (dt) => {
	const f = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw)), r = new THREE.Vector3(-f.z, 0, f.x), v = new THREE.Vector3();
	if (keys.has('KeyW')) v.add(f); if (keys.has('KeyS')) v.sub(f); if (keys.has('KeyD')) v.add(r); if (keys.has('KeyA')) v.sub(r); if (keys.has('KeyE') || keys.has('Space')) v.y += 1; if (keys.has('KeyQ')) v.y -= 1;
	if (v.lengthSq()) camera.position.addScaledVector(v.normalize(), speed * (keys.has('ShiftLeft') ? 3 : 1) * dt);
	camera.rotation.set(0, 0, 0); camera.rotateY(yaw); camera.rotateX(pitch);
};

// ---------------------------------------------------------------- picking / placing
const ray = new THREE.Raycaster();
let mouse = { x: 0, y: 0 }; // NDC of the last mouse position over the canvas (crosshair when pointer-locked)
cv.addEventListener('mousemove', (e) => { const r = cv.getBoundingClientRect(); mouse = { x: ((e.clientX - r.left) / r.width) * 2 - 1, y: -((e.clientY - r.top) / r.height) * 2 + 1 }; });
const aim = (ndc = document.pointerLockElement === cv ? { x: 0, y: 0 } : mouse) => { ray.setFromCamera(ndc, camera); const targets = state.mode === 'ship' ? [...floorHits, ...propHits, ...(ship?.occludable ?? [])] : planetWorld ? planetWorld.scene.children : []; return ray.intersectObjects(targets, false)[0] ?? null; };
const click = () => {
	if (state.mode !== 'ship') return;
	const hit = aim(); if (!hit) return;
	const propMesh = hit.object.userData.prop ? hit.object : null;
	if (state.placing && state.sel) {
		const room = roomAtWorld(hit.point); if (room !== state.sel) { status('aim inside the selected room'); return; }
		const comp = COMPONENTS[state.placing], f = fracAt(room, hit.point), p = { type: state.placing, u: +THREE.MathUtils.clamp(f.u, 0.03, 0.97).toFixed(3), v: +THREE.MathUtils.clamp(f.v, 0.03, 0.97).toFixed(3), ry: Math.round((yaw + Math.PI) / (Math.PI / 4)) * (Math.PI / 4) % (Math.PI * 2) };
		if (comp.defaultAnchor) p.anchor = comp.defaultAnchor; ownProps(room).push(p); state.selProp = p; state.placing = null; ghost.visible = false; touch(); status(`placed ${comp.label} in ${room.name}`); return;
	}
	if (propMesh) { const { roomId, spec } = propMesh.userData.prop; const room = state.layout.find((r) => r.id === roomId); state.sel = room; state.selProp = (room.props ?? []).find((q) => q === spec) ?? ownProps(room).find((q) => q.type === spec.type && Math.abs(q.u - spec.u) < 1e-6 && Math.abs(q.v - spec.v) < 1e-6) ?? null; }
	else { const room = roomAtWorld(hit.point); state.sel = room ?? null; state.selProp = null; }
	renderRoom(); renderProp(); refreshSelection();
};
const tickGhost = () => {
	ghost.visible = false; if (!state.placing || !state.sel || state.mode !== 'ship') return;
	const hit = aim(); if (!hit) return; const room = roomAtWorld(hit.point); if (room !== state.sel) return;
	const [w, d] = COMPONENTS[state.placing].size; ghost.scale.set(w, 1, d); ghost.position.set(hit.point.x, 0.3, hit.point.z); ghost.rotation.y = Math.round((yaw + Math.PI) / (Math.PI / 4)) * (Math.PI / 4); ghost.visible = true;
};

// ---------------------------------------------------------------- rooms / connections
const TYPES = ['corridor', 'gate_room', 'control_room', 'quarters', 'storage', 'infirmary', 'elevator', 'shuttle-dock', 'hydroponics', 'engineering', 'mess_hall', 'lab', 'bridge'];
const fillFloors = () => { const fl = [...new Set(state.layout.map((r) => r.floor))].sort(); $('#floor').innerHTML = fl.map((f) => `<option value="${f}">Floor ${f}</option>`).join('') + '<option value="new">+ new floor</option>'; $('#floor').value = String(state.floor); };
$('#floor').onchange = (e) => { if (e.target.value === 'new') { state.floor = Math.max(...state.layout.map((r) => r.floor)) + 1; addRoom(); fillFloors(); } else state.floor = +e.target.value; state.sel = null; state.selProp = null; touch(); };
const addRoom = () => {
	const hit = aim(); const p = hit?.point ?? camera.position.clone().addScaledVector(new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw)), 8);
	const X = snap(-p.z / S), Y = snap(p.x / S), id = `room_${Date.now().toString(36)}`;
	const r = { id, template_id: 'corridor-template', layout_id: 'destiny', type: 'corridor', name: 'New Room', startX: X - 200, endX: X + 200, startY: Y - 150, endY: Y + 150, floor: state.floor, width: 400, height: 300, found: false, locked: false, explored: false, status: 'unexplored', key_room: false };
	state.layout.push(r); state.sel = r; state.selProp = null; touch(); status(`added ${id} — connect it with "link" in the room panel`);
};
$('#add-room').onclick = addRoom;
const deleteRoom = () => { const r = state.sel; if (!r || r.type === 'gate_room') { status('the gate room is anchored to the gate hall and cannot be deleted'); return; } state.layout.splice(state.layout.indexOf(r), 1); delete state.connections[r.id]; for (const k in state.connections) state.connections[k] = state.connections[k].filter((c) => c.to !== r.id); state.sel = null; state.selProp = null; touch(); };
$('#del-room').onclick = deleteRoom;
const dirBetween = (a, b) => { const ax = (a.startX + a.endX) / 2, ay = (a.startY + a.endY) / 2, bx = (b.startX + b.endX) / 2, by = (b.startY + b.endY) / 2; return Math.abs(bx - ax) > Math.abs(by - ay) ? (bx > ax ? '+x' : '-x') : (by > ay ? '+z' : '-z'); };
const toggleConnection = (a, b) => {
	const la = (state.connections[a.id] ??= []), ia = la.findIndex((c) => c.to === b.id), lb = state.connections[b.id] ?? [], ib = lb.findIndex((c) => c.to === a.id);
	if (ia >= 0) la.splice(ia, 1); else if (ib >= 0) lb.splice(ib, 1); else la.push({ dir: dirBetween(a, b), to: b.id, plaque: b.name });
	status(ia >= 0 || ib >= 0 ? `removed link ${a.id} ↔ ${b.id}` : `linked ${a.id} → ${b.id} (a door appears where they share a wall ≥ 2.8 m)`); touch();
};
const nudge = (r, k, dv) => { r[k] += dv; if (r.endX - r.startX < 100) r.endX = r.startX + 100; if (r.endY - r.startY < 100) r.endY = r.startY + 100; r.width = r.endX - r.startX; r.height = r.endY - r.startY; touch(); };
const renderRoom = () => {
	const r = state.sel; $('#del-room').disabled = !r; if (!r) { $('#room-form').innerHTML = '<span class="hint">Click a floor to select a room.</span>'; return; }
	const linked = new Set([...(state.connections[r.id] ?? []).map((c) => c.to), ...Object.entries(state.connections).filter(([, l]) => l.some((c) => c.to === r.id)).map(([k]) => k)]);
	const others = roomsOnFloor().filter((o) => o !== r);
	$('#room-form').innerHTML = `
		<div class="row"><label>id</label><input data-k="id" value="${r.id}"></div>
		<div class="row"><label>name</label><input data-k="name" value="${r.name}"></div>
		<div class="row"><label>type</label><select data-k="type">${TYPES.map((t) => `<option ${t === r.type ? 'selected' : ''}>${t}</option>`).join('')}</select></div>
		<div class="row"><label>key room</label><input type="checkbox" data-k="key_room" ${r.key_room ? 'checked' : ''}></div>
		<div class="row"><label>along ship (X)</label><div class="bar"><button data-n="startX,-50">◀ start</button><button data-n="startX,50">start ▶</button><button data-n="endX,-50">◀ end</button><button data-n="endX,50">end ▶</button></div></div>
		<div class="row"><label>across (Y)</label><div class="bar"><button data-n="startY,-50">◀ start</button><button data-n="startY,50">start ▶</button><button data-n="endY,-50">◀ end</button><button data-n="endY,50">end ▶</button></div></div>
		<div class="row"><label>move</label><div class="bar"><button data-m="X,-50">−X</button><button data-m="X,50">+X</button><button data-m="Y,-50">−Y</button><button data-m="Y,50">+Y</button></div></div>
		<div class="hint">${((r.endX - r.startX) * S).toFixed(1)} × ${((r.endY - r.startY) * S).toFixed(1)} m · X ${r.startX}…${r.endX} · Y ${r.startY}…${r.endY}</div>
		<div class="row"><label>link</label><select data-link><option value="">toggle door to…</option>${others.map((o) => `<option value="${o.id}">${linked.has(o.id) ? '✓ ' : ''}${o.name} (${o.id})</option>`).join('')}</select></div>
		<div class="hint">${r.props ? `${r.props.length} placed components <button data-reset="1">reset to defaults</button>` : `using ${propsOf(r).length} default components (placing one makes them editable)`}</div>`;
	$('#room-form').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const k = inp.dataset.k, v = inp.type === 'checkbox' ? inp.checked : inp.value; if (k === 'id') { for (const l of Object.values(state.connections)) for (const c of l) if (c.to === r.id) c.to = v; if (state.connections[r.id]) { state.connections[v] = state.connections[r.id]; delete state.connections[r.id]; } } r[k] = v; touch(); }));
	$('#room-form').querySelectorAll('[data-n]').forEach((b) => (b.onclick = () => { const [k, dv] = b.dataset.n.split(','); nudge(r, k, +dv); }));
	$('#room-form').querySelectorAll('[data-m]').forEach((b) => (b.onclick = () => { const [ax, dv] = b.dataset.m.split(','); r[`start${ax}`] += +dv; r[`end${ax}`] += +dv; touch(); }));
	$('#room-form').querySelector('[data-link]').onchange = (e) => { const o = state.layout.find((x) => x.id === e.target.value); if (o) toggleConnection(r, o); };
	$('#room-form').querySelector('[data-reset]')?.addEventListener('click', () => { delete r.props; state.selProp = null; touch(); });
};
const renderPalette = () => { $('#palette').innerHTML = Object.entries(COMPONENTS).map(([k, c]) => `<button data-c="${k}" class="${state.placing === k ? 'on' : ''}" ${state.sel ? '' : 'disabled'}>${c.label}</button>`).join(''); $('#palette').querySelectorAll('[data-c]').forEach((b) => (b.onclick = () => { state.placing = state.placing === b.dataset.c ? null : b.dataset.c; renderPalette(); })); };
const renderProp = () => {
	renderPalette(); const p = state.selProp; if (!p) { $('#prop-form').innerHTML = ''; return; }
	$('#prop-form').innerHTML = `<h2>${COMPONENTS[p.type]?.label ?? p.type}</h2><div class="row"><label>anchor</label><input data-pk="anchor" value="${p.anchor ?? ''}" placeholder="(none)"></div><div class="row"><label>rotation</label><input data-pk="ry" type="range" min="0" max="6.283" step="0.0873" value="${p.ry ?? 0}"></div><div class="row"><label>u / v</label><div style="display:flex;gap:4px"><input data-pk="u" type="number" step="0.01" value="${(+p.u).toFixed(3)}"><input data-pk="v" type="number" step="0.01" value="${(+p.v).toFixed(3)}"></div></div><div class="hint">Quests reference this as <code>${state.sel?.id}:${p.anchor || '…'}</code>.</div>`;
	$('#prop-form').querySelectorAll('[data-pk]').forEach((inp) => (inp.onchange = () => { const q = ownProps(state.sel).find((x) => x === p) ?? p; const k = inp.dataset.pk; q[k] = k === 'anchor' ? inp.value || undefined : +inp.value; state.selProp = q; touch(); }));
};

// ---------------------------------------------------------------- planets
const fillChapters = () => { $('#chapter').innerHTML = state.chapters.chapters.map((c, i) => `<option value="${i}">${c.title}</option>`).join(''); renderPlanet(); };
$('#chapter').onchange = () => { renderPlanet(); if (state.mode === 'planet') visitPlanet(true); };
const COLOR_KEYS = ['sky_low', 'sky_high', 'ground', 'fog', 'sun', 'rock'];
const currentPlanet = () => { const ch = state.chapters.chapters[+$('#chapter').value || 0]; return (ch.planet ??= { id: `${ch.id}_world`, name: 'New World', biome: {}, atmosphere: {}, resource: {} }); };
function renderPlanet() {
	const pl = currentPlanet();
	const field = (obj, k, type = 'text', label = k) => `<div class="row"><label>${label}</label><input data-obj="${obj}" data-k="${k}" type="${type}" value="${(obj ? pl[obj]?.[k] : pl[k]) ?? ''}"></div>`;
	$('#planet-form').innerHTML = `<h2>PLANET</h2>${field('', 'id')}${field('', 'name')}
		<h2>BIOME</h2>${COLOR_KEYS.map((k) => field('biome', k, 'color')).join('')}
		<h2>ATMOSPHERE</h2>${field('atmosphere', 'composition')}${field('atmosphere', 'temperature_c', 'number', 'temp °C')}${field('atmosphere', 'radiation')}${field('atmosphere', 'toxins')}<div class="row"><label>breathable</label><input type="checkbox" data-obj="atmosphere" data-k="breathable" ${pl.atmosphere?.breathable ? 'checked' : ''}></div>
		<h2>RESOURCE</h2>${field('resource', 'id')}${field('resource', 'name')}${field('resource', 'color', 'color')}${field('resource', 'count', 'number')}${field('resource', 'required', 'number')}${field('resource', 'verb')}
		<div class="hint">Resource nodes scatter 22–60 m from the gate at runtime; count/required drive the mining step.</div>`;
	$('#planet-form').querySelectorAll('[data-k]').forEach((inp) => (inp.onchange = () => { const tgt = inp.dataset.obj ? (pl[inp.dataset.obj] ??= {}) : pl; tgt[inp.dataset.k] = inp.type === 'checkbox' ? inp.checked : inp.type === 'number' ? +inp.value : inp.value; state.dirty = true; live(); if (state.mode === 'planet') visitPlanet(true); }));
}
const visitPlanet = (force = false) => {
	if (state.mode === 'planet' && !force) { state.mode = 'ship'; planetWorld = null; $('#visit').textContent = 'Fly the planet'; camera.position.set(0, 1.7, 12); yaw = Math.PI; pitch = 0; return; }
	planetWorld = createDestination(currentPlanet()); planetWorld.scene.environment = envTex; planetWorld.scene.environmentIntensity = 0.6; state.mode = 'planet'; $('#visit').textContent = 'Back to the ship';
	if (!force) { camera.position.set(0, 3, 14); yaw = Math.PI; pitch = -0.1; }
};
$('#visit').onclick = () => visitPlanet(false);

// ---------------------------------------------------------------- loop
const resize = () => { const w = view.clientWidth, h = view.clientHeight; renderer.setSize(w, h); camera.aspect = w / h; camera.updateProjectionMatrix(); };
addEventListener('resize', resize);
let last = performance.now();
const loop = () => {
	const now = performance.now(), dt = Math.min(0.1, (now - last) / 1000); last = now;
	fly(dt); tickGhost();
	const sc = state.mode === 'planet' && planetWorld ? planetWorld.scene : shipScene;
	if (camera.parent !== sc) { camera.removeFromParent(); sc.add(camera); }
	if (state.mode === 'ship') { ship.update(dt, camera.position); gate.userData.update?.(dt); }
	const hit = state.mode === 'ship' ? aim() : null; const room = hit ? roomAtWorld(hit.point) : null;
	$('#hud').textContent = `${state.mode === 'ship' ? `floor ${state.floor} · ${roomsOnFloor().length} rooms · ${ship?.doors.length ?? 0} doors` : `planet: ${currentPlanet().name}`} · speed ${speed.toFixed(0)} m/s${state.dirty ? ' · unsaved' : ''}\n${room ? `aim: ${room.name}` : ''}${state.placing ? ` · placing ${COMPONENTS[state.placing].label}` : ''}`;
	renderer.render(sc, camera); requestAnimationFrame(loop);
};
window.__ed = { state, get ship() { return ship; }, camera, rebuild };
await load(); resize(); rebuild(); renderRoom(); renderProp(); status(`loaded ${state.layout.length} rooms — fly with WASD, right-drag to look`); loop();
