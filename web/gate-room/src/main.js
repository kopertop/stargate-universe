import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { createGateRoom, ROOM } from './gate-room.js';
import { createStargate, GATE } from './stargate.js';
import { createDestination } from './destination.js';
import { createWormhole } from './wormhole.js';
import { createShip } from './ship.js';
import { loadPlayer } from './player.js';
import { initInput, poll, input } from './input.js';
import { createQuestEngine } from './quest.js';
import { createKino } from './kino.js';
import { createUI } from './ui.js';
import * as interact from './interact.js';
import { rpg, loadItems, addItem, removeItem, count, equip, stats, carried, grantXp, addLog, onRpgChange, save as saveRpg, load as loadRpg } from './rpg.js';
import { ASSETS } from './assets.js';

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 0.95;
document.body.appendChild(renderer.domElement);
initInput(renderer.domElement);

const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 400);
const camFill = new THREE.PointLight(0xbfd4f0, 2.5, 10, 1.8); camera.add(camFill);
const envTex = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;

// ---------------------------------------------------------------- worlds
const buildDestiny = async () => {
	const [layout, connections] = await Promise.all([`${ASSETS}data/ship_layout.json`, `${ASSETS}data/room_connections.json`].map((u) => fetch(u).then((r) => r.json())));
	const scene = new THREE.Scene();
	scene.background = new THREE.Color(0x04060a); scene.fog = new THREE.Fog(0x05070c, 26, 70);
	scene.environment = envTex; scene.environmentIntensity = 0.15;
	const { group: room, colliders } = createGateRoom(renderer); scene.add(room);
	const gate = createStargate(); gate.position.set(0, GATE.rInner + ROOM.daisH - 0.15, ROOM.gateZ); scene.add(gate);
	const gz = ROOM.gateZ;
	for (const sx of [-1, 1]) colliders.push(new THREE.Box3(new THREE.Vector3(sx * 2.9 - 0.7, 0, gz - 0.4), new THREE.Vector3(sx * 2.9 + 0.7, 8, gz + 0.4)));
	const ship = createShip(scene, colliders, { layout, connections, gateZ: gz });
	const occludable = [...ship.occludable];
	room.traverse((o) => { if (o.isMesh && o !== room.userData.reflector && o.geometry.type !== 'PlaneGeometry') occludable.push(o); });
	gate.traverse((o) => { if (o.isMesh && o.name !== 'eventHorizon') occludable.push(o); });
	return {
		name: 'destiny', scene, room, ship, colliders, gate, occludable, rooms: ship.rooms, anchors: ship.anchors,
		spawn: new THREE.Vector3(0, 0, gz + 14), spawnYaw: Math.PI, exitDir: 1,
		floorAt: (x, z) => (Math.abs(x) < 4 && z > gz - 1 && z < gz + 2.2 ? ROOM.daisH : 0),
		clampCamera: (p) => { p.y = Math.max(p.y, 0.3); if (Math.abs(p.z) < ROOM.length / 2 && Math.abs(p.x) < ROOM.width / 2 + 0.2) p.x = THREE.MathUtils.clamp(p.x, -ROOM.width / 2 + 0.7, ROOM.width / 2 - 0.7); },
	};
};
const destiny = await buildDestiny();
const wormhole = createWormhole();
let planet = null;
let world = destiny;
const otherWorld = () => (world === destiny ? planet : destiny);

// ---------------------------------------------------------------- player + NPCs
const player = await loadPlayer();
/** Play a one-shot on the player, run `effect` at `at` fraction of the clip (so the result lands on the gesture). */
const withAnim = (name, effect, { at = 0.45, timeScale = 1 } = {}) => { const dur = player.clipDuration(name) / timeScale; player.playAction(name, { timeScale }); setTimeout(effect, dur * at * 1000); };
const npcTalk = (n, seconds = 3) => { n.playAction('talk', { loop: true }); setTimeout(() => n.stopAction(), seconds * 1000); };
let view = 'follow';
const placePlayer = (w, pos, yaw) => { player.root.removeFromParent(); w.scene.add(player.root); player.root.position.copy(pos); player.root.rotation.y = yaw; player.root.visible = true; };
const enterWorld = (w) => { world = w; camera.removeFromParent(); w.scene.add(camera); destiny.ship.ceilings.visible = view !== 'top'; };
const floorUnder = () => world.floorAt(player.root.position.x, player.root.position.z);
placePlayer(destiny, destiny.spawn, destiny.spawnYaw);
const IDLE_INPUT = { move: { x: 0, y: 0 }, run: false };
const WALK_OUT = { move: { x: 0, y: 1 }, run: false };

const nameplate = (text, color = '#f5ebcc') => {
	const c = document.createElement('canvas'); c.width = 256; c.height = 64; const g = c.getContext('2d');
	g.font = 'bold 30px sans-serif'; g.textAlign = 'center'; g.lineWidth = 6; g.strokeStyle = '#000'; g.strokeText(text, 128, 44); g.fillStyle = color; g.fillText(text, 128, 44);
	const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
	const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false })); s.scale.set(1.6, 0.4, 1); s.position.y = 2.15; return s;
};
const npcs = [];
const spawnNpc = async (name, tint, w, pos, yaw) => {
	const n = await loadPlayer({ tint });
	n.root.add(nameplate(name, '#ffd24a')); w.scene.add(n.root); n.root.position.copy(pos); n.root.rotation.y = yaw; n.name = name; npcs.push(n); return n;
};
const A = destiny.anchors;
const brody = await spawnNpc('Brody', 0x8a9a7a, destiny, A['gate_room:Brody'], Math.PI * 0.9);
const rush = await spawnNpc('Rush', 0x7a7a8a, destiny, A['control_interface_room:Rush'], -Math.PI / 2);
const scott = await spawnNpc('Lt. Scott', 0x7a8a6a, destiny, A['gate_room:Scott'], Math.PI * 0.6);

// ---------------------------------------------------------------- audio
const listener = new THREE.AudioListener(); camera.add(listener);
const audioLoader = new THREE.AudioLoader();
const buffers = {};
for (const [k, url] of Object.entries({ chevron: `${ASSETS}sounds/stargate_chevron_incom.mp3`, kawoosh: `${ASSETS}sounds/gate_kawoosh.wav`, hum: `${ASSETS}sounds/gate_active_hum.wav` })) buffers[k] = await audioLoader.loadAsync(url);
const noiseBuffer = (len = 2, smooth = 0.985, gain = 6) => { const ctx = listener.context, n = ctx.sampleRate * len, buf = ctx.createBuffer(1, n, ctx.sampleRate), d = buf.getChannelData(0); let l = 0; for (let i = 0; i < n; i++) { l = l * smooth + (Math.random() * 2 - 1) * (1 - smooth); d[i] = l * gain; } return buf; };
const makeNoise = (freq, type = 'lowpass') => { const a = new THREE.Audio(listener); a.setBuffer(noiseBuffer()); a.setLoop(true); a.setVolume(0); const f = listener.context.createBiquadFilter(); f.type = type; f.frequency.value = freq; a.setFilter(f); return a; };
const sfxRumble = makeNoise(140), sfxWhoosh = makeNoise(900, 'bandpass');
const shutdownBuffer = () => {
	const ctx = listener.context, sr = ctx.sampleRate, dur = 1.5, len = Math.floor(sr * dur), buf = ctx.createBuffer(1, len, sr), out = buf.getChannelData(0); let ph = 0, lp = 0;
	for (let i = 0; i < len; i++) { const t = i / sr, k = t / dur, f = 220 * Math.pow(0.16, k); ph += (2 * Math.PI * f) / sr; const tone = Math.sin(ph) * (0.6 + 0.4 * Math.sin(ph * 2)) * Math.pow(1 - k, 1.3); lp = lp * 0.93 + (Math.random() * 2 - 1) * 0.07; out[i] = (tone * 0.8 + lp * 3 * Math.pow(1 - k, 2.2) * Math.min(1, t * 12)) * Math.min(1, t * 25) * 0.9; }
	return buf;
};
const shutdownBuf = shutdownBuffer();
const attachGateAudio = (w) => {
	const mk = (buf, loop, vol) => { const a = new THREE.PositionalAudio(listener); a.setBuffer(buf); a.setLoop(loop); a.setVolume(vol); a.setRefDistance(6); a.setMaxDistance(60); w.gate.add(a); return a; };
	w.sfx = { chevron: mk(buffers.chevron, false, 0.9), kawoosh: mk(buffers.kawoosh, false, 1.0), hum: mk(buffers.hum, true, 0.6), shutdown: mk(shutdownBuf, false, 0.9) };
};
attachGateAudio(destiny);
const playOnce = (a) => { if (a.isPlaying) a.stop(); a.play(); };
const oneShot = (buf, vol = 0.6, rate = 1) => { const a = new THREE.Audio(listener); a.setBuffer(buf); a.setVolume(vol); a.setPlaybackRate(rate); a.play(); };
const footBuffer = (surface) => { const ctx = listener.context, sr = ctx.sampleRate, len = Math.floor(sr * (surface === 'sand' ? 0.14 : 0.07)), buf = ctx.createBuffer(1, len, sr), out = buf.getChannelData(0); let lp = 0; for (let i = 0; i < len; i++) { const env = Math.pow(1 - i / len, surface === 'sand' ? 1.6 : 3.5); const n = Math.random() * 2 - 1; lp = lp * (surface === 'sand' ? 0.82 : 0.4) + n * (surface === 'sand' ? 0.18 : 0.6); out[i] = lp * env * (surface === 'sand' ? 0.9 : 0.5); } return buf; };
const footBuffers = { sand: footBuffer('sand'), deck: footBuffer('deck') };
const footPool = Array.from({ length: 4 }, () => new THREE.Audio(listener)); let footIdx = 0, stepDist = 0;
const footstep = (surface, loud) => { const a = footPool[footIdx++ % footPool.length]; if (a.isPlaying) a.stop(); a.setBuffer(footBuffers[surface]); a.setPlaybackRate(0.9 + Math.random() * 0.25); a.setVolume((surface === 'sand' ? 0.35 : 0.22) * (loud ? 1.3 : 1)); a.play(); };
const humFades = new Set();
const fadeHum = (w) => { if (w.sfx.hum.isPlaying) humFades.add(w); };
const tickHumFades = (dt) => { for (const w of humFades) { const h = w.sfx.hum, v = h.getVolume() - dt * 0.9; if (v <= 0) { h.stop(); h.setVolume(0.6); humFades.delete(w); } else h.setVolume(v); } };

// ---------------------------------------------------------------- dialing
let dialingWorld = null, rumbleOn = false;
const onGateEvent = (w) => (ev, i) => {
	if (ev === 'chevron') { playOnce(w.sfx.chevron); if (i === (w.dialCount ?? 7) - 1) { rumbleOn = false; sfxRumble.setVolume(0); } }
	if (ev === 'kawoosh') playOnce(w.sfx.kawoosh);
	if (ev === 'active') { w.sfx.hum.setVolume(0.6); w.sfx.hum.play(); if (w === dialingWorld) dialingWorld = null; }
};
const dialGate = (w, chevronCount = 7) => { if (w.gate.userData.active) return; w.gate.userData.reset(); w.sfx.hum.stop(); dialingWorld = w; w.dialCount = chevronCount; sfxRumble.setVolume(0); sfxRumble.isPlaying || sfxRumble.play(); rumbleOn = true; w.gate.userData.dial(onGateEvent(w), { chevronCount }); addLog(`${w === destiny ? 'Destiny' : planet.def.name}: gate dialing`); };
const shutdownGate = (w) => { if (!w.gate.userData.active) return; w.gate.userData.shutdown(); fadeHum(w); playOnce(w.sfx.shutdown); };

// ---------------------------------------------------------------- RPG + UI + quest engine
await loadItems();
let lastScan = null;
let quest = null;
const ui = createUI({
	flags: { has: (f) => quest?.flags.has(f) ?? false },
	chapterTitle: () => quest?.chapter?.title ?? '', steps: () => quest?.chapter?.steps ?? [], stepIndex: () => quest?.stepIndex ?? 0,
	deckMap: () => ({ rooms: destiny.rooms, player: player.root.position, current: currentRoom, discovered: [...discovered], waypoint: world === destiny ? waypointPos() : null }),
	shipStatus: () => [['Power', destiny.ship.powered ? 'ONLINE' : 'OFFLINE', destiny.ship.powered], ['Hull (port dock)', quest.has('any_breach_sealed') ? 'SEALED' : quest.has('life_support_diagnosed') ? 'BREACH' : 'unknown', quest.has('any_breach_sealed')], ['CO2 scrubbers', quest.has('scrubber_repaired') ? 'NOMINAL' : quest.has('scrubber_diagnosed') ? 'FAILED — lime bed exhausted' : 'unknown', quest.has('scrubber_repaired')], ['FTL', quest.has('ftl_dropped') && !quest.has('scrubber_repaired') ? 'DROPPED — gate window open' : 'CRUISING', true]],
	planets: () => [
		...(planet ? [{ id: planet.def.id, name: planet.def.name, scan: lastScan?.id === planet.def.id ? lastScan.atmosphere.composition : null, canDial: world === destiny && !destiny.gate.userData.active && !dialingWorld && quest.has('ftl_dropped') }] : []),
		{ id: 'destiny', name: 'Destiny', scan: 'Home. Ancient seed ship.', canDial: world === planet && !planet.gate.userData.active && !dialingWorld },
	],
	onDial: (id) => dialGate(id === 'destiny' ? planet : destiny),
	canLaunchKino: () => count('kino_orb') > 0 && world === destiny && destiny.gate.userData.active && !travel,
	onLaunchKino: () => launchKino(), lastScan: () => lastScan,
	onResume: () => {},
});
onRpgChange(() => { ui.refreshPlayer(); player.speedMul = stats().speed; if (ui.isRemoteOpen()) ui.renderRemote(); });

const flash = document.getElementById('flash');
let shake = 0;
quest = createQuestEngine({
	grantXp: (n) => grantXp(n),
	onStep: (step) => { ui.refreshTracker(); if (step && !step.terminal) ui.toast(`New objective: ${step.label}`, 3); saveGame(); },
	onTrigger: (t) => {
		if (t.type === 'subtitle') ui.subtitle(t.who, t.text);
		if (t.type === 'radio') ui.subtitle(t.who, t.text, { radio: true });
		if (t.type === 'toast') ui.toast(t.text, 6);
		if (t.type === 'ftl_drop') { shake = 1.4; oneShot(shutdownBuf, 0.8, 0.55); addLog('Destiny dropped out of FTL'); }
		if (t.type === 'dial') setTimeout(() => dialGate(destiny), 900);
	},
	onChapterComplete: (ch) => {
		grantXp(300); addLog(`${ch.title} — complete`); saveGame();
		const next = quest.nextChapter();
		setTimeout(() => ui.showChapter(`${ch.title} — Complete`, ch.steps.at(-1).objective + (next ? `<br><br>Next: <b>${next.title}</b> — ${next.subtitle}` : ''), next ? `Continue to ${next.title}` : 'The End (for now)', () => next && startChapter(next.id)), 1200);
	},
});
await quest.load('./data/chapters.json');

// ---------------------------------------------------------------- chapter start: build the chapter's planet, reset gates
const startChapter = (id) => {
	const ch = quest.chapterById(id);
	planet = createDestination(ch.planet); planet.scene.environment = envTex; planet.scene.environmentIntensity = 0.6; attachGateAudio(planet); planet.scene.add(dust);
	registerPlanetInteractables();
	shutdownGate(destiny); destiny.gate.userData.reset();
	quest.startChapter(id); ui.refreshTracker(); ui.refreshPlayer();
};

// ---------------------------------------------------------------- interactables (Destiny)
const S = destiny.ship;
const stepIs = (id) => quest.step()?.id === id;
interact.register({ world: 'destiny', id: 'relay', position: A['gate_room:PowerRelay'], prompt: () => (!S.powered ? 'Restore power' : null), action: () => withAnim('interact', () => { S.setPower(true); quest.setFlag('power_restored'); ui.subtitle('Eli', 'Power relay engaged... lights are coming up. Doors should unlock.'); oneShot(shutdownBuf, 0.5, 1.6); }) });
interact.register({ world: 'destiny', id: 'console', position: A['control_interface_room:ControlConsole'], prompt: () => (S.powered && !quest.has('life_support_diagnosed') ? 'Access control terminal' : null), action: () => withAnim('interact', () => { quest.setFlag('life_support_diagnosed'); ui.subtitle('Eli', 'Hull breach — port shuttle dock. And life support is flagged red across the board.'); ui.openRemote('ship'); }, { at: 0.6 }) });
interact.register({ world: 'destiny', id: 'elevator', position: A['elevator_north:Elevator'], prompt: () => 'Call elevator — upper deck', action: () => { ui.toast(S.powered ? 'Elevator offline — no power routed to the upper deck yet.' : 'No power.'); } });
interact.register({ world: 'destiny', id: 'lever', position: A['south_spur:SealLever'], prompt: () => (quest.has('life_support_diagnosed') && !quest.has('any_breach_sealed') ? 'Pull emergency seal' : null), action: () => withAnim('interact', () => { S.sealBreach(); quest.setFlag('any_breach_sealed'); oneShot(shutdownBuf, 0.9, 0.8); ui.subtitle('Rush', 'Pressure is holding. Good. Now go make yourself useful somewhere else.'); }) });
interact.register({ world: 'destiny', id: 'kino', position: A['eli_quarters:KinoPedestal'], prompt: () => (!quest.has('kino_acquired') ? 'Take the Kino and its remote' : null), action: () => withAnim('pickup', () => { S.takeKino(); addItem('kino_remote'); addItem('kino_orb', 2); quest.setFlag('kino_acquired'); }, { at: 0.55 }) });
interact.register({ world: 'destiny', id: 'locker', position: A['eli_quarters:Locker'], prompt: () => (!quest.has('locker_opened') ? 'Open locker' : null), action: () => withAnim('open', () => { quest.setFlag('locker_opened'); addItem('tac_vest'); ui.toast('Found: Tactical Vest (+20 health) — equip it from Character', 5); }, { at: 0.6 }) });
interact.register({ world: 'destiny', id: 'scrubber', position: A['south_corridor:Scrubber'], prompt: () => (quest.has('kino_acquired') && !quest.has('scrubber_diagnosed') ? 'Inspect CO2 scrubber' : (stepIs('repair_scrubber') || stepIs('repair_water')) && count('refined_lime') > 0 ? `Load refined ${planet?.resource?.name?.toLowerCase() ?? 'lime'}` : null),
	action: () => {
		if (!quest.has('scrubber_diagnosed')) { withAnim('interact', () => { quest.setFlag('scrubber_diagnosed'); ui.subtitle('Rush', 'The scrubber bed is spent — the lime is inert. We need more, and there is none on this ship.'); }); return; }
		withAnim('repair', () => { removeItem('refined_lime', count('refined_lime')); S.repairScrubber(); quest.setFlag('scrubber_repaired'); ui.subtitle('Eli', 'Scrubber is cycling. CO2 is dropping. We can breathe.'); oneShot(shutdownBuf, 0.5, 1.8); }, { at: 0.8, timeScale: 1.4 });
	} });
interact.register({ world: 'destiny', id: 'crate', position: A['gate_room:SupplyCrate'], prompt: () => (stepIs('gear_up') ? 'Take shovel and field backpack' : null), action: () => withAnim('open', () => { addItem('shovel'); addItem('field_backpack'); equip('shovel'); equip('field_backpack'); quest.setFlag('geared_up'); ui.toast('Equipped: Field Shovel, Field Backpack (+6 carry)', 5); }, { at: 0.6 }) });
let brodyBusy = 0;
interact.register({ world: 'destiny', id: 'brody', position: brody.root, radius: 2.6, prompt: () => { const r = planet?.resource; if (!r) return null; if (stepIs('give_brody') && count(r.id) >= r.required) return `Give ${r.name.toLowerCase()} to Brody`; if (brodyBusy > 0) return null; return 'Talk to Brody'; },
	action: () => { const r = planet.resource; if (stepIs('give_brody') && count(r.id) >= r.required) { const n = count(r.id); withAnim('pickup', () => removeItem(r.id, n), { at: 0.5 }); brodyBusy = 4; ui.subtitle('Brody', `Give me a minute with this ${r.name.toLowerCase()}...`, { dur: 4 }); brody.playAction('repair', { timeScale: 1.3 }); setTimeout(() => { addItem('refined_lime', n); quest.setFlag('lime_refined'); }, 4000); } else { npcTalk(brody); player.playAction('nod'); ui.subtitle('Brody', 'If you find anything we can burn, breathe, or drink — bring it to me.'); } } });
interact.register({ world: 'destiny', id: 'rush', position: rush.root, radius: 2.6, prompt: () => 'Talk to Rush', action: () => { npcTalk(rush, 4); player.playAction('nod'); if (stepIs('talk_rush')) { quest.setFlag('water_briefed'); ui.subtitle('Rush', 'Reserves are at eleven percent. The next drop is a frozen world. Bring back ice — as much as you can carry.'); } else ui.subtitle('Rush', 'I am busy, Eli.'); } });
interact.register({ world: 'destiny', id: 'scott', position: scott.root, radius: 2.6, prompt: () => 'Talk to Scott', action: () => { npcTalk(scott); player.playAction('nod'); ui.subtitle('Scott', quest.has('power_restored') ? 'Good work on the power. Keep moving.' : 'See if you can find a way to get those doors open.'); } });

// shovel prop (procedural) mounted in the right hand while digging
const shovel = new THREE.Group();
{ const wood = new THREE.MeshStandardMaterial({ color: 0x6b4a2a, roughness: 0.9 }), steel = new THREE.MeshStandardMaterial({ color: 0x8a8f96, roughness: 0.4, metalness: 0.9 });
	const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 1.1, 8), wood); shaft.position.y = -0.35; shovel.add(shaft);
	const blade = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.28, 0.02), steel); blade.position.y = -1.0; shovel.add(blade);
	shovel.rotation.set(Math.PI / 2, 0, 0); shovel.scale.setScalar(1 / (1.72 / 1.83)); shovel.visible = false; }
player.attach(shovel, 'hand_r');
let digging = false;
const tickDigAnim = () => {
	const want = interact.holding && world === planet && stats().canMine;
	if (want && !digging) { digging = true; shovel.visible = true; player.playAction('dig', { loop: true, timeScale: 1.1 }); }
	else if (!want && digging) { digging = false; shovel.visible = false; player.stopAction(); }
};
// planet interactables: resource nodes (hold E to dig)
let planetRegs = [];
const registerPlanetInteractables = () => {
	for (const id of planetRegs) interact.unregister(id); planetRegs = [];
	const r = planet.resource; if (!r) return;
	for (const n of planet.nodes) {
		const pos = new THREE.Vector3(n.x, planet.floorAt(n.x, n.z), n.z);
		interact.register({ world: 'planet', id: n.id, position: pos, radius: 2.6, hold: () => 2.2 / Math.max(0.2, stats().mineSpeed),
			prompt: () => (world !== planet || n.done ? null : !stats().canMine ? 'Needs a shovel' : carried() >= stats().carry ? 'Backpack full' : `${r.verb} (${n.remaining} left)`),
			action: () => { addItem(r.id); n.remaining--; kickSand(true); footstep('sand', true); if (n.remaining <= 0) { n.done = true; n.mesh.material = n.mesh.material.clone(); n.mesh.material.color.multiplyScalar(0.6); } if (count(r.id) >= r.required) quest.setFlag('has_required_resource'); } });
		planetRegs.push(n.id);
	}
};

// ---------------------------------------------------------------- views + camera
const VIEWS = ['follow', 'top', 'orbit'];
const orbit = new OrbitControls(camera, renderer.domElement); orbit.enabled = false; orbit.enableDamping = true;
const viewEl = document.getElementById('view');
const setView = (v) => { view = v; input.lockEnabled = v === 'follow'; orbit.enabled = v === 'orbit'; if (v !== 'follow' && document.pointerLockElement) document.exitPointerLock(); const g = world.gate.position; orbit.target.set(g.x, GATE.rOuter, g.z); if (v === 'orbit') camera.position.set(g.x + 9, 7, g.z + 9); destiny.ship.ceilings.visible = v !== 'top'; viewEl.textContent = `view: ${v} (V)`; };
enterWorld(destiny);
const cam = { yaw: 0, pitch: 0.12, dist: 5.0, height: 1.5 };
const camTarget = new THREE.Vector3(), camPos = new THREE.Vector3();
const raycaster = new THREE.Raycaster();
const updateCamera = (dt) => {
	cam.yaw -= input.look.x; cam.pitch = THREE.MathUtils.clamp(cam.pitch + input.look.y, -0.35, 0.9);
	camTarget.copy(player.root.position).add(new THREE.Vector3(0, cam.height, 0));
	const off = new THREE.Vector3(Math.sin(cam.yaw) * Math.cos(cam.pitch), Math.sin(cam.pitch), Math.cos(cam.yaw) * Math.cos(cam.pitch)).multiplyScalar(cam.dist);
	camPos.copy(camTarget).add(off); world.clampCamera(camPos);
	// pull the camera in when a wall sits between it and the player (interior rooms are tight)
	const dir = camPos.clone().sub(camTarget).normalize();
	raycaster.set(camTarget, dir); raycaster.far = cam.dist;
	const hit = raycaster.intersectObjects(world.occludable, false)[0];
	if (hit && hit.distance < cam.dist) camPos.copy(camTarget).addScaledVector(dir, Math.max(0.8, hit.distance - 0.3));
	if (shake > 0) camPos.add(new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).multiplyScalar(0.18 * shake));
	camera.position.lerp(camPos, Math.min(1, dt * 12)); camera.up.set(0, 1, 0); camera.lookAt(camTarget);
};
const camUpdate = (dt) => { if (view === 'follow') updateCamera(dt); else if (view === 'top') { const g = world.gate.position; camera.position.lerp(new THREE.Vector3(g.x + 0.001, 10.6, g.z + 2.4), Math.min(1, dt * 6)); camera.up.set(0, 1, 0); camera.lookAt(g.x, 0, g.z + 2.4); } else orbit.update(); };
const faded = new Map();
const updateOcclusion = () => {
	const target = player.root.position.clone().add(new THREE.Vector3(0, 1.2, 0));
	const dir = target.clone().sub(camera.position); const dist = dir.length(); dir.normalize();
	raycaster.set(camera.position, dir); raycaster.far = dist - 0.3;
	const hits = new Set(raycaster.intersectObjects(world.occludable, false).map((h) => h.object));
	for (const mesh of hits) { if (faded.has(mesh)) continue; faded.set(mesh, mesh.material); const mat = mesh.material.clone(); mat.transparent = true; mat.opacity = 0.1; mat.depthWrite = false; mesh.material = mat; }
	for (const [mesh, orig] of faded) if (!hits.has(mesh)) { mesh.material.dispose(); mesh.material = orig; faded.delete(mesh); }
};

// ---------------------------------------------------------------- waypoint beacon
const beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 6, 16, 1, true), new THREE.MeshBasicMaterial({ color: 0xffd24a, transparent: true, opacity: 0.25, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending }));
beacon.visible = false;
const waypointPos = () => {
	const s = quest.step(); if (!s || s.terminal || !s.target?.room) return null;
	const inPlanet = s.target.room === 'planet';
	if ((world === planet) !== inPlanet) return world === planet ? planet.anchors['planet:GateFront'] : null;
	if (s.target.anchor === 'NearestResource') { let best = null, bd = Infinity; for (const n of planet.nodes) if (!n.done) { const d = Math.hypot(n.x - player.root.position.x, n.z - player.root.position.z); if (d < bd) { bd = d; best = n; } } return best ? new THREE.Vector3(best.x, planet.floorAt(best.x, best.z), best.z) : null; }
	return world.anchors[`${s.target.room}:${s.target.anchor}`] ?? null;
};

// ---------------------------------------------------------------- particles (disintegration + sand dust)
const PCOUNT = 1200, pGeo = new THREE.BufferGeometry();
pGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(PCOUNT * 3), 3)); pGeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(PCOUNT * 3), 3));
const pVel = new Float32Array(PCOUNT * 3), pLife = new Float32Array(PCOUNT);
const particles = new THREE.Points(pGeo, new THREE.PointsMaterial({ size: 0.07, vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false })); particles.frustumCulled = false; particles.visible = false;
let pNext = 0; const tmpV = new THREE.Vector3();
const emitParticles = (n, dirZ) => { const pos = pGeo.attributes.position.array; for (let k = 0; k < n; k++) { const i = pNext++ % PCOUNT; player.samplePoint(tmpV); pos[i * 3] = tmpV.x; pos[i * 3 + 1] = tmpV.y; pos[i * 3 + 2] = tmpV.z; pVel[i * 3] = (Math.random() - 0.5) * 0.8; pVel[i * 3 + 1] = 0.4 + Math.random() * 0.8; pVel[i * 3 + 2] = dirZ * (2.5 + Math.random() * 2); pLife[i] = 0.45 + Math.random() * 0.3; } };
const tickParticles = (dt) => { const pos = pGeo.attributes.position.array, col = pGeo.attributes.color.array; for (let i = 0; i < PCOUNT; i++) { if (pLife[i] <= 0) { col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = 0; continue; } pLife[i] -= dt; pos[i * 3] += pVel[i * 3] * dt; pos[i * 3 + 1] += pVel[i * 3 + 1] * dt; pos[i * 3 + 2] += pVel[i * 3 + 2] * dt; const a = Math.max(0, Math.min(1, pLife[i] / 0.35)); col[i * 3] = 0.55 * a; col[i * 3 + 1] = 0.9 * a; col[i * 3 + 2] = a; } pGeo.attributes.position.needsUpdate = true; pGeo.attributes.color.needsUpdate = true; };
const DCOUNT = 400, dGeo = new THREE.BufferGeometry();
dGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(DCOUNT * 3), 3)); dGeo.setAttribute('aAlpha', new THREE.BufferAttribute(new Float32Array(DCOUNT), 1)); dGeo.setAttribute('aSize', new THREE.BufferAttribute(new Float32Array(DCOUNT), 1));
const dVel = new Float32Array(DCOUNT * 3), dLife = new Float32Array(DCOUNT), dMax = new Float32Array(DCOUNT);
const dust = new THREE.Points(dGeo, new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: { uColor: { value: new THREE.Color(0xf1dcb2) } },
	vertexShader: `attribute float aAlpha, aSize; varying float vA; void main(){ vA = aAlpha; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_PointSize = aSize * 380.0 / -mv.z; gl_Position = projectionMatrix * mv; }`,
	fragmentShader: `uniform vec3 uColor; varying float vA; void main(){ float d = length(gl_PointCoord - 0.5) * 2.0; float soft = smoothstep(1.0, 0.35, d); if (soft <= 0.001) discard; gl_FragColor = vec4(uColor, soft * vA); }` }));
dust.frustumCulled = false; let dNext = 0;
const kickSand = (loud) => { const p = player.root.position, pos = dGeo.attributes.position.array; const back = new THREE.Vector3(Math.sin(player.root.rotation.y), 0, Math.cos(player.root.rotation.y)).multiplyScalar(-1); const n = loud ? 26 : 14; for (let k = 0; k < n; k++) { const i = dNext++ % DCOUNT; pos[i * 3] = p.x + (Math.random() - 0.5) * 0.35; pos[i * 3 + 1] = p.y + 0.05; pos[i * 3 + 2] = p.z + (Math.random() - 0.5) * 0.35; dVel[i * 3] = back.x * (0.8 + Math.random()) + (Math.random() - 0.5) * 0.8; dVel[i * 3 + 1] = 1.1 + Math.random() * 1.3; dVel[i * 3 + 2] = back.z * (0.8 + Math.random()) + (Math.random() - 0.5) * 0.8; dLife[i] = dMax[i] = 0.45 + Math.random() * 0.35; } };
const tickDust = (dt) => { const pos = dGeo.attributes.position.array, al = dGeo.attributes.aAlpha.array, sz = dGeo.attributes.aSize.array; for (let i = 0; i < DCOUNT; i++) { if (dLife[i] <= 0) { al[i] = 0; continue; } dLife[i] -= dt; dVel[i * 3 + 1] -= 3.5 * dt; pos[i * 3] += dVel[i * 3] * dt; pos[i * 3 + 1] += dVel[i * 3 + 1] * dt; pos[i * 3 + 2] += dVel[i * 3 + 2] * dt; const k = Math.max(0, dLife[i] / dMax[i]); al[i] = 0.85 * k; sz[i] = 0.22 + (1 - k) * 0.55; } dGeo.attributes.position.needsUpdate = true; dGeo.attributes.aAlpha.needsUpdate = true; dGeo.attributes.aSize.needsUpdate = true; };
const tickFootsteps = (dt) => { if (!player.grounded || player.speed < 0.6) { stepDist = 0; return; } stepDist += player.speed * dt; const stride = player.speed > 7 ? 1.55 : 0.85; if (stepDist >= stride) { stepDist -= stride; const loud = player.speed > 7; footstep(world === planet ? 'sand' : 'deck', loud); if (world === planet) kickSand(loud); } };

// ---------------------------------------------------------------- gate travel + arrival
let travel = null; const PLAYER_CHEST = 1.1;
const gateTravelCheck = () => {
	const g = world.gate; if (!g.userData.active) return;
	const p = player.root.position, dx = p.x - g.position.x, dz = p.z - g.position.z;
	if (dz > 0 && dz < 1.1 && Math.abs(dx) < GATE.rInner - 0.3) { travel = { phase: 'enter', t: 0, from: world, to: otherWorld(), rippled: false }; pLife.fill(0); particles.removeFromParent(); world.scene.add(particles); particles.visible = true; }
};
/** Place the player at a world's gate and start the step-out phase (used for travel arrival AND the chapter cold open). */
const arriveAt = (w) => {
	enterWorld(w);
	const g = w.gate.position, d = w.exitDir;
	placePlayer(w, new THREE.Vector3(g.x, w.floorAt(g.x, g.z + 0.35 * d), g.z + 0.35 * d), d > 0 ? 0 : Math.PI);
	if (!w.gate.userData.active) { w.gate.userData.reset(); w.gate.userData.incoming(onGateEvent(w)); }
	w.gate.userData.ripple(0, PLAYER_CHEST - g.y);
	playOnce(w.sfx.kawoosh); if (!w.sfx.hum.isPlaying) { w.sfx.hum.setVolume(0.6); w.sfx.hum.play(); }
	camera.position.set(g.x + 2.2 * d, 1.7, g.z + 6.5 * d); camera.up.set(0, 1, 0); camera.lookAt(g.x, 1.2, g.z);
	cam.yaw = d > 0 ? Math.PI : 0; cam.pitch = 0.12;
	travel = { phase: 'arrive', t: 0, from: null, to: w };
};
const updateTravel = (dt, t) => {
	travel.t += dt; const { phase } = travel;
	if (phase === 'enter') {
		const g = travel.from.gate.position;
		if (travel.t < 0.75) { player.update(dt, WALK_OUT, 0, [], floorUnder()); emitParticles(Math.round(dt * 2600), -1); }
		const fade = THREE.MathUtils.smoothstep(travel.t, 0.1, 0.7); player.setFade(fade); player.root.visible = fade < 1;
		if (!travel.rippled && player.root.position.z - g.z < 0.35) { travel.rippled = true; travel.from.gate.userData.ripple(player.root.position.x - g.x, PLAYER_CHEST - g.y); playOnce(travel.from.sfx.kawoosh); }
		if (travel.t < 0.45) updateCamera(dt); else { const k = Math.min(1, (travel.t - 0.45) / 0.7); camera.position.lerp(new THREE.Vector3(g.x, g.y, g.z + 3.5 * (1 - k) + 0.1), Math.min(1, dt * 4)); camera.up.set(0, 1, 0); camera.lookAt(g.x, g.y, g.z - 5); }
		flash.style.opacity = String(THREE.MathUtils.smoothstep(travel.t, 0.75, 1.15));
		if (travel.t >= 1.15) {
			particles.visible = false; player.setFade(0); travel.phase = 'wormhole'; travel.t = 0;
			shutdownGate(travel.from); camera.removeFromParent(); wormhole.scene.add(camera);
			sfxWhoosh.isPlaying || sfxWhoosh.play(); sfxWhoosh.setVolume(0.9);
			travel.to.gate.userData.reset(); travel.to.gate.userData.incoming(onGateEvent(travel.to));
		}
	} else if (phase === 'wormhole') {
		const k = Math.min(1, travel.t / wormhole.duration); wormhole.tick(t, k, camera);
		flash.style.opacity = String(Math.max(1 - THREE.MathUtils.smoothstep(k, 0, 0.15), THREE.MathUtils.smoothstep(k, 0.9, 1)));
		sfxWhoosh.setVolume(0.9 * (1 - THREE.MathUtils.smoothstep(k, 0.85, 1)));
		if (k >= 1) { sfxWhoosh.setVolume(0); sfxWhoosh.stop(); const to = travel.to; arriveAt(to); quest.setFlag(to === planet ? 'on_planet' : 'returned_from_planet'); }
	} else if (phase === 'arrive') {
		flash.style.opacity = String(1 - THREE.MathUtils.smoothstep(travel.t, 0, 0.5));
		player.update(dt, WALK_OUT, cam.yaw, world.colliders, floorUnder());
		camera.up.set(0, 1, 0); camera.lookAt(player.root.position.x, 1.2, player.root.position.z);
		if (travel.t >= 1.6) { travel = null; flash.style.opacity = '0'; shutdownGate(world); if (world === destiny) quest.setFlag('arrived'); }
	}
};

// ---------------------------------------------------------------- Kino drone mode
const kino = createKino(); let kinoWorld = null, kinoScanT = 0;
const launchKino = () => {
	if (count('kino_orb') <= 0 || !destiny.gate.userData.active || world !== destiny) { ui.toast('Kino needs an active gate and a Kino in inventory'); return; }
	// launch ahead of the player, heading where they face (kino yaw 0 = -Z; player rotation.y = π when facing -Z)
	const ry = player.root.rotation.y, fwd = new THREE.Vector3(Math.sin(ry), 0, Math.cos(ry));
	kinoWorld = destiny; destiny.scene.add(kino.orb); kino.launch(player.root.position.clone().addScaledVector(fwd, 1).add(new THREE.Vector3(0, 1.4, 0)), ry + Math.PI);
	camera.removeFromParent(); destiny.scene.add(camera); kinoScanT = 0; addLog('Kino launched');
};
const recallKino = () => { kino.recall(); kino.orb.removeFromParent(); kinoWorld = null; enterWorld(world); camera.position.copy(player.root.position).add(new THREE.Vector3(0, 2, 5)); };
const updateKino = (dt) => {
	kino.update(dt, input, camera);
	const g = kinoWorld.gate.position, o = kino.orb.position;
	if (kinoWorld === destiny && o.z < g.z && Math.hypot(o.x - g.x, o.y - g.y) < GATE.rInner) {
		kinoWorld = planet; kino.orb.removeFromParent(); planet.scene.add(kino.orb); camera.removeFromParent(); planet.scene.add(camera);
		if (!planet.gate.userData.active) { planet.gate.userData.reset(); planet.gate.userData.incoming(onGateEvent(planet)); }
		const pg = planet.gate.position; o.set(pg.x, pg.y, pg.z + 1.5); kino.yaw = Math.PI; kino.vel.set(0, 0, 3); flash.style.opacity = '1'; setTimeout(() => (flash.style.opacity = '0'), 250);
	}
	if (kinoWorld === planet) { kinoScanT += dt; if (kinoScanT > 3.5 && !quest.has('kino_scout_done')) { lastScan = { id: planet.def.id, name: planet.def.name, atmosphere: planet.def.atmosphere }; quest.setFlag('kino_scout_done'); const at = planet.def.atmosphere; ui.subtitle('Kino', `${planet.def.name}: ${at.composition}. ${at.temperature_c}°C, radiation ${at.radiation}, toxins ${at.toxins}.`, { radio: true, dur: 7 }); addLog(`Kino scan — ${planet.def.name}: ${at.composition}`); } }
	if (input.remote || input.interact) { if (kinoWorld === planet && planet.gate.userData.active) shutdownGate(planet); recallKino(); }
};

// ---------------------------------------------------------------- rooms / zones
let currentRoom = null; const discovered = new Set(['gate_room']);
const tickRooms = () => {
	const id = world === destiny ? destiny.ship.roomAt(player.root.position) : 'planet';
	if (id !== currentRoom) {
		currentRoom = id; const r = destiny.rooms.find((x) => x.id === id); ui.zone(world === planet ? planet.def.name : r?.name ?? '');
		if (r && !discovered.has(id)) { discovered.add(id); ui.toast(`Discovered: ${r.name}`, 3); addLog(`Discovered ${r.name}`); grantXp(r.key ? 15 : 5); }
		const s = quest.step(); if (s && !s.terminal && s.target?.room === id && s.target.anchor === 'RoomCenter') quest.setFlag(s.complete_when);
	}
};
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); destiny.room.userData.reflector.getRenderTarget().setSize(Math.floor(innerWidth * 0.5), Math.floor(innerHeight * 0.5)); });
window.__dbg = { input, player, camera, quest, rpg, get world() { return world; }, destiny, get planet() { return planet; }, setView, cam: () => cam, travel: () => travel, teleport: (x, z) => { player.root.position.set(x, world.floorAt(x, z), z); }, dialGate: () => dialGate(world), launchKino, interact: () => interact.current?.id, ui, startChapter, kino: () => kinoWorld?.name };

// ---------------------------------------------------------------- start: chapter card → cold open (arrive through the gate)
// ---------------------------------------------------------------- save / load (localStorage) + title screen
const SAVE_KEY = 'sgu.save';
let gameStarted = false; // saves only once a game is running (startChapter fires onStep during boot/load)
const saveGame = () => { if (!quest.chapter || !gameStarted) return; try { localStorage.setItem(SAVE_KEY, JSON.stringify({ chapter: quest.chapter.id, stepIndex: quest.stepIndex, flags: [...quest.flags], lastScan, savedAt: Date.now() })); saveRpg(); } catch {} };
const hasSave = () => { try { return !!localStorage.getItem(SAVE_KEY); } catch { return false; } };
/** Restore chapter/step/flags + RPG, rebuild Destiny state from flags, and put the player in the gate room. Planet-side steps rewind to the gate. */
const loadGame = () => {
	let s; try { s = JSON.parse(localStorage.getItem(SAVE_KEY)); } catch { s = null; }
	if (!s) return false;
	startChapter(s.chapter); loadRpg(); lastScan = s.lastScan ?? null;
	for (const f of s.flags) quest.flags.add(f);
	const steps = quest.chapter.steps, idx = (id) => steps.findIndex((x) => x.id === id);
	let si = Math.min(s.stepIndex, steps.length - 1);
	const travelIdx = idx('travel'), brodyIdx = idx('give_brody');
	if (travelIdx >= 0 && brodyIdx >= 0 && si > travelIdx && si < brodyIdx) { si = travelIdx; for (const f of ['on_planet', 'returned_from_planet']) quest.flags.delete(f); }
	quest.stepIndex = si;
	const S2 = destiny.ship;
	if (quest.has('power_restored')) S2.setPower(true); if (quest.has('any_breach_sealed')) S2.sealBreach(); if (quest.has('kino_acquired')) S2.takeKino(); if (quest.has('scrubber_repaired')) S2.repairScrubber();
	const step = quest.step();
	if (quest.has('ftl_dropped') && ['scout_kino', 'gear_up', 'travel'].includes(step?.id)) { destiny.gate.userData.reset(); destiny.gate.userData.incoming(onGateEvent(destiny)); }
	enterWorld(destiny); placePlayer(destiny, destiny.spawn, destiny.spawnYaw); cam.yaw = 0;
	gameStarted = true; saveGame();
	ui.refreshTracker(); ui.refreshPlayer(); ui.toast(`Loaded: ${quest.chapter.title} — ${step?.label ?? ''}`, 4);
	return true;
};
window.__save = { saveGame, loadGame, hasSave, clear: () => localStorage.removeItem(SAVE_KEY) };
startChapter('e1_air');
document.getElementById('loading')?.remove();
const newGame = () => { listener.context.resume(); destiny.scene.add(beacon); localStorage.removeItem(SAVE_KEY); localStorage.removeItem('sgu.rpg'); ui.showChapter(quest.chapter.title, quest.chapter.subtitle, 'Begin', () => { gameStarted = true; arriveAt(destiny); }); };
ui.showTitle({ hasSave: hasSave(), onNew: newGame, onContinue: () => { listener.context.resume(); destiny.scene.add(beacon); if (!loadGame()) newGame(); } });
// ?autoplay → hands-free demo driver (recordings / smoke runs); start it with window.__auto.run()
if (location.search.includes('autoplay')) { const { createAutoplay } = await import('./autoplay.js'); window.__auto = createAutoplay(window.__dbg); }
// ?record → in-page recorder (WebGL + text HUD) → local save endpoint; control with window.__rec.start()/stop(name)
let recorder = null;
if (location.search.includes('record')) {
	const { createRecorder } = await import('./recorder.js');
	recorder = createRecorder(renderer.domElement, () => { const s = quest.step(); const p = document.getElementById('prompt'), sub = document.getElementById('sub'); return {
		chapter: quest.chapter?.title ?? '', label: s?.label ?? '', zone: document.getElementById('zone').textContent, level: rpg.level, hp: Math.round(rpg.hp), xp: rpg.xp, carry: `${carried()}/${stats().carry}`,
		prompt: p.classList.contains('hidden') ? '' : p.textContent.replace(/\s+/g, ' ').trim(), subtitle: sub.classList.contains('hidden') ? '' : sub.textContent.trim() }; });
	window.__rec = recorder;
}

const fpsEl = document.getElementById('fps');
const clock = new THREE.Clock(); let acc = 0, frames = 0;
renderer.setAnimationLoop(() => {
	const rawDt = Math.min(clock.getDelta(), 0.05); const t = clock.elapsedTime;
	poll(rawDt);
	const paused = ui.isRemoteOpen();
	if (input.remote && !kino.active) { if (paused) { ui.closeRemote(); player.stopAction(); } else if (quest.has('kino_acquired')) { ui.openRemote(); player.playAction('device', { loop: true }); } else ui.toast('You have no device to open yet'); }
	if (input.launchKino && !paused && !travel && !kino.active) launchKino();
	if (input.cycleView) setView(VIEWS[(VIEWS.indexOf(view) + 1) % VIEWS.length]);
	if (input.fullscreen) { if (document.fullscreenElement) document.exitFullscreen?.(); else document.documentElement.requestFullscreen?.().catch?.(() => {}); }
	const dt = paused ? 0 : rawDt;
	if (shake > 0) shake = Math.max(0, shake - dt);
	if (dt > 0) {
		for (const n of npcs) n.update(dt, IDLE_INPUT, 0, [], 0);
		if (kino.active) { player.mixer.update(dt); updateKino(dt); }
		else if (travel) { player.mixer.update(dt); updateTravel(dt, t); }
		else {
			player.update(dt, input, cam.yaw, world.colliders, floorUnder());
			gateTravelCheck(); camUpdate(dt); tickRooms();
			ui.setPrompt(interact.update(dt, player.root.position, input.interact, input.interactHeld, world.name)); tickDigAnim();
			player.carrying = carried() >= 3;
			if (view === 'follow') updateOcclusion();
			tickFootsteps(dt);
		}
		destiny.ship.update(dt, player.root.position);
		destiny.gate.userData.tick(t, dt); planet.gate.userData.tick(t, dt);
		if (particles.visible) tickParticles(dt); if (world === planet) tickDust(dt);
		tickHumFades(dt);
		{ // low rumble drone: rises while the ring spins, dips at the final chevron, then sits under the hum while the gate is active
			const active = world.gate.userData.active && (!travel || travel.phase === 'arrive');
			const target = active ? 0.7 : dialingWorld && rumbleOn ? Math.min(0.8, sfxRumble.getVolume() + dt * 0.6) : 0;
			const v = sfxRumble.getVolume() + (target - sfxRumble.getVolume()) * Math.min(1, dt * 3); sfxRumble.setVolume(v);
			if (v > 0.01 && !sfxRumble.isPlaying) sfxRumble.play(); else if (v <= 0.01 && sfxRumble.isPlaying && !dialingWorld) sfxRumble.stop();
		}
		brodyBusy = Math.max(0, brodyBusy - dt);
		const wp = waypointPos(); beacon.visible = !!wp && !kino.active;
		if (wp) { if (beacon.parent !== world.scene) { beacon.removeFromParent(); world.scene.add(beacon); } beacon.position.set(wp.x, wp.y + 3, wp.z); beacon.material.opacity = 0.18 + 0.1 * Math.sin(t * 3); }
		ui.drawMinimap({ rooms: world === destiny ? destiny.rooms : null, nodes: world === planet ? planet.nodes : null, player: player.root.position, yaw: player.root.rotation.y, waypoint: wp, gate: world.gate.position });
		if (quest.step()?.counter) ui.refreshTracker();
	}
	renderer.render(travel?.phase === 'wormhole' ? wormhole.scene : kino.active ? kinoWorld.scene : world.scene, camera);
	recorder?.tick();
	acc += rawDt; frames++; if (acc > 0.5) { fpsEl.textContent = `${Math.round(frames / acc)} fps`; acc = 0; frames = 0; }
});
