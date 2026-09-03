import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { createGateRoom, ROOM } from './gate-room.js';
import { createStargate, GATE } from './stargate.js';
import { createDestination } from './destination.js';
import { createWormhole } from './wormhole.js';
import { loadPlayer } from './player.js';
import { initInput, poll, input } from './input.js';

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.25;
document.body.appendChild(renderer.domElement);
initInput(renderer.domElement);

const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 400);
// soft fill riding with the camera so the player's back reads as mid-grey like the reference
const camFill = new THREE.PointLight(0xdfe8f0, 14, 12, 1.8); camera.add(camFill);

// ---------------------------------------------------------------- worlds
const buildDestiny = () => {
	const scene = new THREE.Scene();
	scene.background = new THREE.Color(0x07080c);
	scene.fog = new THREE.Fog(0x0a0c12, 30, 70);
	const { group: room, colliders } = createGateRoom(renderer);
	scene.add(room);
	const gate = createStargate();
	// puddle bottom sits ~15 cm below the dais top, so the ring's lower arc is buried in the platform
	gate.position.set(0, GATE.rInner + ROOM.daisH - 0.15, ROOM.gateZ);
	scene.add(gate);
	const gz = ROOM.gateZ;
	for (const sx of [-1, 1]) colliders.push(new THREE.Box3(new THREE.Vector3(sx * 2.9 - 0.7, 0, gz - 0.4), new THREE.Vector3(sx * 2.9 + 0.7, 8, gz + 0.4)));
	const occludable = [];
	room.traverse((o) => { if (o.isMesh && o !== room.userData.reflector && o.geometry.type !== 'PlaneGeometry') occludable.push(o); });
	gate.traverse((o) => { if (o.isMesh && o.name !== 'eventHorizon') occludable.push(o); });
	return {
		name: 'destiny', scene, room, colliders, gate, occludable,
		spawn: new THREE.Vector3(0, 0, gz + 14), spawnYaw: Math.PI, // facing the gate (-Z)
		exitDir: 1, // arriving travellers walk +Z out of this gate
		floorAt: (x, z) => (Math.abs(x) < 4 && z > gz - 1 && z < gz + 2.2 ? ROOM.daisH : 0),
		clampCamera: (p) => {
			p.x = THREE.MathUtils.clamp(p.x, -ROOM.width / 2 + 0.4, ROOM.width / 2 - 0.4);
			p.z = Math.min(p.z, gz + ROOM.length - 5 - 0.4);
			p.y = Math.max(p.y, 0.3);
		},
	};
};
const destiny = buildDestiny();
const planet = createDestination();
const wormhole = createWormhole();
let world = destiny;
// neutral env map so metals (gate ring) pick up reflections instead of going black
const envTex = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
destiny.scene.environment = envTex; destiny.scene.environmentIntensity = 0.35;
planet.scene.environment = envTex; planet.scene.environmentIntensity = 0.6;
const otherWorld = () => (world === destiny ? planet : destiny);

const player = await loadPlayer();
const placePlayer = (w, pos, yaw) => {
	player.root.removeFromParent(); w.scene.add(player.root);
	player.root.position.copy(pos); player.root.rotation.y = yaw; player.root.visible = true;
};
const enterWorld = (w) => {
	world = w; camera.removeFromParent(); w.scene.add(camera);
	if (destiny.room.userData.ceiling) destiny.room.userData.ceiling.visible = view !== 'top';
};
placePlayer(destiny, destiny.spawn, destiny.spawnYaw);
const floorUnder = () => world.floorAt(player.root.position.x, player.root.position.z);
document.getElementById('loading').textContent = 'CLICK TO DIAL';

// ---------------------------------------------------------------- audio (repo assets)
const listener = new THREE.AudioListener(); camera.add(listener);
const audioLoader = new THREE.AudioLoader();
const buffers = {};
for (const [k, url] of Object.entries({ chevron: '../../sounds/stargate_chevron_incom.mp3', kawoosh: '../../sounds/gate_kawoosh.wav', hum: '../../sounds/gate_active_hum.wav' })) buffers[k] = await audioLoader.loadAsync(url);
const attachGateAudio = (w) => {
	const mk = (buf, loop, vol) => { const a = new THREE.PositionalAudio(listener); a.setBuffer(buf); a.setLoop(loop); a.setVolume(vol); a.setRefDistance(6); a.setMaxDistance(60); w.gate.add(a); return a; };
	w.sfx = { chevron: mk(buffers.chevron, false, 0.9), kawoosh: mk(buffers.kawoosh, false, 1.0), hum: mk(buffers.hum, true, 0.6) };
};
attachGateAudio(destiny); attachGateAudio(planet);
// Ring-spin rumble + wormhole whoosh: no assets in repo → synthesized filtered noise (ponytail: swap for wavs when they exist)
const noiseBuffer = () => {
	const ctx = listener.context; const len = ctx.sampleRate * 2; const buf = ctx.createBuffer(1, len, ctx.sampleRate);
	const d = buf.getChannelData(0); let l = 0; for (let i = 0; i < len; i++) { l = l * 0.985 + (Math.random() * 2 - 1) * 0.015; d[i] = l * 6; }
	return buf;
};
const makeNoise = (freq, type = 'lowpass') => {
	const a = new THREE.Audio(listener); a.setBuffer(noiseBuffer()); a.setLoop(true); a.setVolume(0);
	const f = listener.context.createBiquadFilter(); f.type = type; f.frequency.value = freq; a.setFilter(f); return a;
};
const sfxRumble = makeNoise(140);
const sfxWhoosh = makeNoise(900, 'bandpass');
const playOnce = (a) => { if (a.isPlaying) a.stop(); a.play(); };
// Gate shutdown "whoomp": no sample in repo → synthesized descending tone sweep + low noise tail (ponytail: swap for a wav)
const shutdownBuffer = () => {
	const ctx = listener.context, sr = ctx.sampleRate, dur = 1.5, len = Math.floor(sr * dur);
	const buf = ctx.createBuffer(1, len, sr), out = buf.getChannelData(0); let ph = 0, lp = 0;
	for (let i = 0; i < len; i++) {
		const t = i / sr, k = t / dur;
		const f = 220 * Math.pow(0.16, k);                      // 220 Hz → ~35 Hz
		ph += (2 * Math.PI * f) / sr;
		const tone = Math.sin(ph) * (0.6 + 0.4 * Math.sin(ph * 2.0)) * Math.pow(1 - k, 1.3);
		lp = lp * 0.93 + (Math.random() * 2 - 1) * 0.07;         // low rumble noise
		const noise = lp * 3.0 * Math.pow(1 - k, 2.2) * Math.min(1, t * 12);
		const swell = Math.min(1, t * 25);                       // avoid a click
		out[i] = (tone * 0.8 + noise) * swell * 0.9;
	}
	return buf;
};
const attachShutdownAudio = (w) => { const a = new THREE.PositionalAudio(listener); a.setBuffer(shutdownBuffer()); a.setVolume(0.9); a.setRefDistance(6); a.setMaxDistance(60); w.gate.add(a); w.sfx.shutdown = a; };
attachShutdownAudio(destiny); attachShutdownAudio(planet);
// Hum fade-out (hard stop sounded like a cut): lerp volume to 0 over ~0.7 s, then stop and restore the default volume.
const humFades = new Set();
const fadeHum = (w) => { if (w.sfx.hum.isPlaying) humFades.add(w); };
const tickHumFades = (dt) => {
	for (const w of humFades) {
		const h = w.sfx.hum, v = h.getVolume() - dt * 0.9;
		if (v <= 0) { h.stop(); h.setVolume(0.6); humFades.delete(w); } else h.setVolume(v);
	}
};
// Footfalls: synthesized per surface (sand = soft low-passed puff, deck = short bright tap). ponytail: swap for samples later.
const footBuffer = (surface) => {
	const ctx = listener.context, sr = ctx.sampleRate, len = Math.floor(sr * (surface === 'sand' ? 0.14 : 0.07));
	const buf = ctx.createBuffer(1, len, sr), out = buf.getChannelData(0); let lp = 0;
	for (let i = 0; i < len; i++) {
		const env = Math.pow(1 - i / len, surface === 'sand' ? 1.6 : 3.5);
		const n = Math.random() * 2 - 1; lp = lp * (surface === 'sand' ? 0.82 : 0.4) + n * (surface === 'sand' ? 0.18 : 0.6);
		out[i] = lp * env * (surface === 'sand' ? 0.9 : 0.5);
	}
	return buf;
};
const footBuffers = { sand: footBuffer('sand'), deck: footBuffer('deck') };
const footPool = Array.from({ length: 4 }, () => new THREE.Audio(listener));
let footIdx = 0, stepDist = 0;
const footstep = (surface, loud) => {
	const a = footPool[footIdx++ % footPool.length]; if (a.isPlaying) a.stop();
	a.setBuffer(footBuffers[surface]); a.setPlaybackRate(0.9 + Math.random() * 0.25); a.setVolume((surface === 'sand' ? 0.35 : 0.22) * (loud ? 1.3 : 1)); a.play();
};
// Sand kick-up: small dust puffs at the feet on each sand footfall (planet scene only)
const DCOUNT = 400;
const dGeo = new THREE.BufferGeometry();
dGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(DCOUNT * 3), 3));
dGeo.setAttribute('aAlpha', new THREE.BufferAttribute(new Float32Array(DCOUNT), 1));
dGeo.setAttribute('aSize', new THREE.BufferAttribute(new Float32Array(DCOUNT), 1));
const dVel = new Float32Array(DCOUNT * 3), dLife = new Float32Array(DCOUNT), dMax = new Float32Array(DCOUNT);
// soft round sprites with per-particle alpha/size (PointsMaterial can't fade alpha per point, and additive on bright sand reads as white blocks)
const dust = new THREE.Points(dGeo, new THREE.ShaderMaterial({
	transparent: true, depthWrite: false,
	uniforms: { uColor: { value: new THREE.Color(0xf1dcb2) } },
	vertexShader: `attribute float aAlpha, aSize; varying float vA;
		void main(){ vA = aAlpha; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_PointSize = aSize * 380.0 / -mv.z; gl_Position = projectionMatrix * mv; }`,
	fragmentShader: `uniform vec3 uColor; varying float vA;
		void main(){ float d = length(gl_PointCoord - 0.5) * 2.0; float soft = smoothstep(1.0, 0.35, d); if (soft <= 0.001) discard; gl_FragColor = vec4(uColor, soft * vA); }`,
}));
dust.frustumCulled = false; planet.scene.add(dust);
let dNext = 0;
const kickSand = (loud) => {
	const p = player.root.position, pos = dGeo.attributes.position.array;
	const back = new THREE.Vector3(Math.sin(player.root.rotation.y), 0, Math.cos(player.root.rotation.y)).multiplyScalar(-1); // behind the model (+Z is its forward)
	const n = loud ? 26 : 14;
	for (let k = 0; k < n; k++) {
		const i = dNext++ % DCOUNT;
		pos[i * 3] = p.x + (Math.random() - 0.5) * 0.35; pos[i * 3 + 1] = p.y + 0.05; pos[i * 3 + 2] = p.z + (Math.random() - 0.5) * 0.35;
		dVel[i * 3] = back.x * (0.8 + Math.random()) + (Math.random() - 0.5) * 0.8; dVel[i * 3 + 1] = 1.1 + Math.random() * 1.3; dVel[i * 3 + 2] = back.z * (0.8 + Math.random()) + (Math.random() - 0.5) * 0.8;
		dLife[i] = dMax[i] = 0.45 + Math.random() * 0.35;
	}
};
const tickDust = (dt) => {
	const pos = dGeo.attributes.position.array, al = dGeo.attributes.aAlpha.array, sz = dGeo.attributes.aSize.array;
	for (let i = 0; i < DCOUNT; i++) {
		if (dLife[i] <= 0) { al[i] = 0; continue; }
		dLife[i] -= dt; dVel[i * 3 + 1] -= 3.5 * dt;
		pos[i * 3] += dVel[i * 3] * dt; pos[i * 3 + 1] += dVel[i * 3 + 1] * dt; pos[i * 3 + 2] += dVel[i * 3 + 2] * dt;
		const k = Math.max(0, dLife[i] / dMax[i]); // 1 → 0
		al[i] = 0.85 * k; sz[i] = 0.22 + (1 - k) * 0.55; // fade out while puffing up
	}
	dGeo.attributes.position.needsUpdate = true; dGeo.attributes.aAlpha.needsUpdate = true; dGeo.attributes.aSize.needsUpdate = true;
};
const tickFootsteps = (dt) => {
	if (!player.grounded || player.speed < 0.6) { stepDist = 0; return; }
	stepDist += player.speed * dt;
	const stride = player.speed > 7 ? 1.55 : 0.85; // run vs walk
	if (stepDist >= stride) { stepDist -= stride; const loud = player.speed > 7; footstep(world === planet ? 'sand' : 'deck', loud); if (world === planet) kickSand(loud); }
};

// ---------------------------------------------------------------- dialing
let dialing = true, rumbleOn = false;
const IDLE_INPUT = { move: { x: 0, y: 0 }, run: false };
const onGateEvent = (w) => (ev, i) => {
	if (ev === 'chevron') { playOnce(w.sfx.chevron); if (i === GATE.chevrons - 1) { rumbleOn = false; sfxRumble.setVolume(0); } }
	if (ev === 'kawoosh') playOnce(w.sfx.kawoosh);
	if (ev === 'active') { w.sfx.hum.play(); if (w === world) dialing = false; }
};
const startDial = () => {
	document.getElementById('loading')?.remove();
	listener.context.resume();
	world.gate.userData.reset(); world.sfx.hum.stop(); dialing = true;
	sfxRumble.setVolume(0); sfxRumble.isPlaying || sfxRumble.play(); rumbleOn = true;
	world.gate.userData.dial(onGateEvent(world));
};
document.getElementById('loading').addEventListener('click', startDial, { once: true });

// ---------------------------------------------------------------- views
const VIEWS = ['follow', 'top', 'orbit'];
let view = 'follow';
const orbit = new OrbitControls(camera, renderer.domElement); orbit.enabled = false; orbit.enableDamping = true;
const viewEl = document.getElementById('view');
const setView = (v) => {
	view = v; input.lockEnabled = v === 'follow'; orbit.enabled = v === 'orbit';
	if (v !== 'follow' && document.pointerLockElement) document.exitPointerLock();
	const g = world.gate.position;
	orbit.target.set(g.x, GATE.rOuter, g.z);
	if (v === 'orbit') camera.position.set(g.x + 9, 7, g.z + 9);
	destiny.room.userData.ceiling.visible = v !== 'top';
	viewEl.textContent = `view: ${v} (V)`;
};
enterWorld(destiny);

// third-person follow camera
const cam = { yaw: 0, pitch: 0.12, dist: 5.0, height: 1.5 };
const camTarget = new THREE.Vector3(), camPos = new THREE.Vector3();
const updateCamera = (dt, snap = false) => {
	cam.yaw -= input.look.x; cam.pitch = THREE.MathUtils.clamp(cam.pitch + input.look.y, -0.35, 0.9);
	camTarget.copy(player.root.position).add(new THREE.Vector3(0, cam.height, 0));
	const off = new THREE.Vector3(Math.sin(cam.yaw) * Math.cos(cam.pitch), Math.sin(cam.pitch), Math.cos(cam.yaw) * Math.cos(cam.pitch)).multiplyScalar(cam.dist);
	camPos.copy(camTarget).add(off);
	world.clampCamera(camPos);
	if (snap) camera.position.copy(camPos); else camera.position.lerp(camPos, Math.min(1, dt * 12));
	camera.up.set(0, 1, 0); camera.lookAt(camTarget);
};
const camUpdate = (dt) => {
	if (view === 'follow') updateCamera(dt);
	else if (view === 'top') { const g = world.gate.position; camera.position.lerp(new THREE.Vector3(g.x + 0.001, 10.6, g.z + 2.4), Math.min(1, dt * 6)); camera.up.set(0, 1, 0); camera.lookAt(g.x, 0, g.z + 2.4); }
	else orbit.update();
};

// ---------------------------------------------------------------- camera occlusion (follow view only)
const raycaster = new THREE.Raycaster();
const faded = new Map(); // mesh → original material
const updateOcclusion = () => {
	const target = player.root.position.clone().add(new THREE.Vector3(0, 1.2, 0));
	const dir = target.clone().sub(camera.position); const dist = dir.length(); dir.normalize();
	raycaster.set(camera.position, dir); raycaster.far = dist - 0.3;
	const hits = new Set(raycaster.intersectObjects(world.occludable, false).map((h) => h.object));
	for (const mesh of hits) {
		if (faded.has(mesh)) continue;
		faded.set(mesh, mesh.material);
		const mat = mesh.material.clone(); mat.transparent = true; mat.opacity = 0.1; mat.depthWrite = false; mesh.material = mat;
	}
	for (const [mesh, orig] of faded) if (!hits.has(mesh)) { mesh.material.dispose(); mesh.material = orig; faded.delete(mesh); }
};

// ---------------------------------------------------------------- disintegration particles
const PCOUNT = 1200;
const pGeo = new THREE.BufferGeometry();
pGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(PCOUNT * 3), 3));
pGeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(PCOUNT * 3), 3));
const pVel = new Float32Array(PCOUNT * 3), pLife = new Float32Array(PCOUNT);
const particles = new THREE.Points(pGeo, new THREE.PointsMaterial({ size: 0.07, vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
particles.frustumCulled = false; particles.visible = false;
let pNext = 0;
const tmpV = new THREE.Vector3();
const emitParticles = (n, dirZ) => {
	const pos = pGeo.attributes.position.array;
	for (let k = 0; k < n; k++) {
		const i = pNext++ % PCOUNT;
		player.samplePoint(tmpV);
		pos[i * 3] = tmpV.x; pos[i * 3 + 1] = tmpV.y; pos[i * 3 + 2] = tmpV.z;
		pVel[i * 3] = (Math.random() - 0.5) * 0.8; pVel[i * 3 + 1] = 0.4 + Math.random() * 0.8; pVel[i * 3 + 2] = dirZ * (2.5 + Math.random() * 2.0);
		pLife[i] = 0.45 + Math.random() * 0.3;
	}
};
const tickParticles = (dt) => {
	const pos = pGeo.attributes.position.array, col = pGeo.attributes.color.array;
	for (let i = 0; i < PCOUNT; i++) {
		if (pLife[i] <= 0) { col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = 0; continue; }
		pLife[i] -= dt;
		pos[i * 3] += pVel[i * 3] * dt; pos[i * 3 + 1] += pVel[i * 3 + 1] * dt; pos[i * 3 + 2] += pVel[i * 3 + 2] * dt;
		const a = Math.max(0, Math.min(1, pLife[i] / 0.35));
		col[i * 3] = 0.55 * a; col[i * 3 + 1] = 0.9 * a; col[i * 3 + 2] = 1.0 * a;
	}
	pGeo.attributes.position.needsUpdate = true; pGeo.attributes.color.needsUpdate = true;
};

// ---------------------------------------------------------------- terrain debug (B): wireframe ground, floor marker, visual-vs-collision delta
const dbgEl = document.getElementById('dbg');
let debugTerrain = false;
const groundWire = new THREE.Mesh(planet.ground.geometry, new THREE.MeshBasicMaterial({ color: 0x00ffcc, wireframe: true, transparent: true, opacity: 0.35 }));
groundWire.rotation.copy(planet.ground.rotation); groundWire.position.copy(planet.ground.position); groundWire.visible = false; planet.scene.add(groundWire);
const floorMarker = new THREE.Mesh(new THREE.SphereGeometry(0.06, 12, 8), new THREE.MeshBasicMaterial({ color: 0xff3366 })); floorMarker.visible = false;
const footMarker = new THREE.Mesh(new THREE.SphereGeometry(0.06, 12, 8), new THREE.MeshBasicMaterial({ color: 0xffee00 })); footMarker.visible = false;
const downRay = new THREE.Raycaster();
/** Returns { feet, floor, mesh, delta } for the player's current XZ: floor = collision query, mesh = raycast onto the drawn ground. */
const terrainReport = () => {
	const p = player.root.position; const floor = world.floorAt(p.x, p.z);
	let mesh = null;
	if (world === planet) { downRay.set(new THREE.Vector3(p.x, 60, p.z), new THREE.Vector3(0, -1, 0)); const h = downRay.intersectObject(planet.ground, false)[0]; mesh = h ? h.point.y : null; }
	return { x: +p.x.toFixed(2), z: +p.z.toFixed(2), feet: +p.y.toFixed(3), floor: +floor.toFixed(3), mesh: mesh === null ? null : +mesh.toFixed(3), delta: mesh === null ? null : +(p.y - mesh).toFixed(3) };
};
const setDebugTerrain = (on) => {
	debugTerrain = on; groundWire.visible = on; floorMarker.visible = footMarker.visible = on; dbgEl.hidden = !on;
	floorMarker.removeFromParent(); footMarker.removeFromParent(); if (on) { world.scene.add(floorMarker, footMarker); }
};
const tickDebugTerrain = () => {
	if (!debugTerrain) return;
	const r = terrainReport(); const p = player.root.position;
	floorMarker.position.set(p.x, r.floor, p.z); footMarker.position.set(p.x + 0.25, p.y, p.z);
	dbgEl.textContent = `feet ${r.feet}  floor ${r.floor}  mesh ${r.mesh ?? '—'}  Δ(feet−mesh) ${r.delta ?? '—'}  @ ${r.x},${r.z}`;
};

// ---------------------------------------------------------------- gate travel
// enter (dive into the puddle) → wormhole ride → arrive (incoming kawoosh on the far gate, walk out) → control
const flash = document.getElementById('flash');
let travel = null;
const PLAYER_CHEST = 1.1;
const gateTravelCheck = () => {
	const g = world.gate; if (!g.userData.active) return;
	const p = player.root.position; const dx = p.x - g.position.x, dz = p.z - g.position.z;
	if (dz > 0 && dz < 1.1 && Math.abs(dx) < GATE.rInner - 0.3) {
		travel = { phase: 'enter', t: 0, from: world, to: otherWorld(), rippled: false };
		pLife.fill(0); particles.removeFromParent(); world.scene.add(particles); particles.visible = true;
	}
};
const WALK_OUT = { move: { x: 0, y: 1 }, run: false };
const updateTravel = (dt, t) => {
	travel.t += dt;
	const { phase } = travel;
	if (phase === 'enter') {
		const g = travel.from.gate.position;
		// keep walking into the puddle while the body dematerialises into particles
		if (travel.t < 0.75) { player.update(dt, WALK_OUT, 0, [], floorUnder()); emitParticles(Math.round(dt * 2600), -1); }
		const fade = THREE.MathUtils.smoothstep(travel.t, 0.1, 0.7);
		player.setFade(fade); player.root.visible = fade < 1;
		const dz = player.root.position.z - g.z;
		if (!travel.rippled && dz < 0.35) { travel.rippled = true; travel.from.gate.userData.ripple(player.root.position.x - g.x, PLAYER_CHEST - g.y); playOnce(travel.from.sfx.kawoosh); }
		if (travel.t < 0.45) updateCamera(dt);
		else {
			const k = Math.min(1, (travel.t - 0.45) / 0.7);
			camera.position.lerp(new THREE.Vector3(g.x, g.y, g.z + 3.5 * (1 - k) + 0.1), Math.min(1, dt * 4));
			camera.up.set(0, 1, 0); camera.lookAt(g.x, g.y, g.z - 5);
		}
		flash.style.opacity = String(THREE.MathUtils.smoothstep(travel.t, 0.75, 1.15));
		if (travel.t >= 1.15) {
			particles.visible = false; player.setFade(0);
			travel.phase = 'wormhole'; travel.t = 0;
			travel.from.gate.userData.shutdown(); travel.from.sfx.hum.stop();
			camera.removeFromParent(); wormhole.scene.add(camera);
			sfxWhoosh.isPlaying || sfxWhoosh.play(); sfxWhoosh.setVolume(0.9);
			// far gate: incoming wormhole forms while we're in transit
			travel.to.gate.userData.reset(); travel.to.gate.userData.incoming(onGateEvent(travel.to));
		}
	} else if (phase === 'wormhole') {
		const k = Math.min(1, travel.t / wormhole.duration);
		wormhole.tick(t, k, camera);
		flash.style.opacity = String(Math.max(1 - THREE.MathUtils.smoothstep(k, 0, 0.15), THREE.MathUtils.smoothstep(k, 0.9, 1)));
		sfxWhoosh.setVolume(0.9 * (1 - THREE.MathUtils.smoothstep(k, 0.85, 1)));
		if (k >= 1) {
			travel.phase = 'arrive'; travel.t = 0; sfxWhoosh.setVolume(0); sfxWhoosh.stop();
			enterWorld(travel.to);
			const g = travel.to.gate.position, d = travel.to.exitDir;
			placePlayer(travel.to, new THREE.Vector3(g.x, travel.to.floorAt(g.x, g.z + 0.35 * d), g.z + 0.35 * d), d > 0 ? 0 : Math.PI);
			travel.to.gate.userData.ripple(0, PLAYER_CHEST - g.y);
			// the far gate's kawoosh happened while we were in transit (inaudible at wormhole distance): play it as we emerge, hum + drone underneath
			playOnce(travel.to.sfx.kawoosh); if (!travel.to.sfx.hum.isPlaying) { travel.to.sfx.hum.setVolume(0.6); travel.to.sfx.hum.play(); }
			// camera in front of the far gate, watching the traveller step out
			camera.position.set(g.x + 2.2 * d, 1.7, g.z + 6.5 * d); camera.up.set(0, 1, 0); camera.lookAt(g.x, 1.2, g.z);
			cam.yaw = d > 0 ? Math.PI : 0; cam.pitch = 0.12;
		}
	} else if (phase === 'arrive') {
		flash.style.opacity = String(1 - THREE.MathUtils.smoothstep(travel.t, 0, 0.5));
		player.update(dt, WALK_OUT, cam.yaw, world.colliders, floorUnder());
		camera.up.set(0, 1, 0); camera.lookAt(player.root.position.x, 1.2, player.root.position.z);
		if (travel.t >= 1.6) { travel = null; flash.style.opacity = '0'; world.gate.userData.shutdown(); fadeHum(world); playOnce(world.sfx.shutdown); } // wormhole closes once we're through
	}
};


addEventListener('resize', () => {
	camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
	renderer.setSize(innerWidth, innerHeight);
	destiny.room.userData.reflector.getRenderTarget().setSize(Math.floor(innerWidth * 0.5), Math.floor(innerHeight * 0.5));
});

window.__dbg = { shutdownPlaying: () => world.sfx.shutdown.isPlaying, kawooshPlaying: () => world.sfx.kawoosh.isPlaying, dustAlive: () => dLife.reduce((n, l) => n + (l > 0 ? 1 : 0), 0), rumblePlaying: () => sfxRumble.isPlaying, humPlaying: () => world.sfx.hum.isPlaying, terrainReport, setDebugTerrain, teleport: (x, z) => { player.root.position.set(x, world.floorAt(x, z), z); }, input, player, camera, get world() { return world; }, destiny, planet, setView, cam: () => cam, faded: () => faded, travel: () => travel };

const fpsEl = document.getElementById('fps');
const clock = new THREE.Clock(); let acc = 0, frames = 0;
renderer.setAnimationLoop(() => {
	const dt = Math.min(clock.getDelta(), 0.05); const t = clock.elapsedTime;
	poll(dt);
	if (input.cycleView) setView(VIEWS[(VIEWS.indexOf(view) + 1) % VIEWS.length]);
	if (input.redial && !dialing && !travel) startDial();
	if (travel) { player.mixer.update(dt); updateTravel(dt, t); }
	else if (dialing) { player.update(dt, IDLE_INPUT, cam.yaw, world.colliders, floorUnder()); camUpdate(dt); }
	else { player.update(dt, input, cam.yaw, world.colliders, floorUnder()); gateTravelCheck(); camUpdate(dt); }
	if (particles.visible) tickParticles(dt);
	if (view === 'follow' && !travel) updateOcclusion();
	// Low rumble drone: rises while the ring spins, dips at the final chevron, then sits under the hum while the gate is active.
	{
		const active = world.gate.userData.active && (!travel || travel.phase === 'arrive');
		const target = active ? 0.7 : dialing && rumbleOn ? Math.min(0.8, sfxRumble.getVolume() + dt * 0.6) : 0;
		const v = sfxRumble.getVolume() + (target - sfxRumble.getVolume()) * Math.min(1, dt * 3);
		sfxRumble.setVolume(v);
		if (v > 0.01 && !sfxRumble.isPlaying) sfxRumble.play(); else if (v <= 0.01 && sfxRumble.isPlaying && !dialing) sfxRumble.stop();
	}
	tickHumFades(dt);
	if (!travel) tickFootsteps(dt);
	if (world === planet) tickDust(dt);
	if (input.debug) setDebugTerrain(!debugTerrain);
	tickDebugTerrain();
	destiny.gate.userData.tick(t, dt); planet.gate.userData.tick(t, dt);
	renderer.render(travel?.phase === 'wormhole' ? wormhole.scene : world.scene, camera);
	acc += dt; frames++; if (acc > 0.5) { fpsEl.textContent = `${Math.round(frames / acc)} fps`; acc = 0; frames = 0; }
});
