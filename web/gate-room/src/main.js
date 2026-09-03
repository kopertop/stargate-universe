import * as THREE from 'three';
import { createGateRoom, ROOM } from './gate-room.js';
import { createStargate, GATE } from './stargate.js';
import { loadPlayer } from './player.js';
import { initInput, poll, input } from './input.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.25;
document.body.appendChild(renderer.domElement);
initInput(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x07080c);
scene.fog = new THREE.Fog(0x0a0c12, 30, 70);
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 120);
// soft fill riding with the camera so the player's back reads as mid-grey like the reference
const camFill = new THREE.PointLight(0xdfe8f0, 14, 12, 1.8); camera.add(camFill); scene.add(camera);

const { group: room, colliders } = createGateRoom(renderer);
scene.add(room);

const gate = createStargate();
// puddle bottom sits ~15 cm below the dais top, so the ring's lower arc is buried in the platform
gate.position.set(0, GATE.rInner + ROOM.daisH - 0.15, ROOM.gateZ);
scene.add(gate);
// ring colliders: two side blocks + top bar (leave the opening walkable)
const gz = ROOM.gateZ;
for (const sx of [-1, 1]) colliders.push(new THREE.Box3(new THREE.Vector3(sx * 2.9 - 0.7, 0, gz - 0.4), new THREE.Vector3(sx * 2.9 + 0.7, 8, gz + 0.4)));

const player = await loadPlayer();
const SPAWN = new THREE.Vector3(0, ROOM.daisH * 0, gz + 14);
player.root.position.copy(SPAWN); player.root.rotation.y = Math.PI; // face the gate (-Z)
scene.add(player.root);
document.getElementById('loading').textContent = 'CLICK TO DIAL';

// --- Audio (repo assets) — listener on the camera, positional sources on the gate
const listener = new THREE.AudioListener(); camera.add(listener);
const audioLoader = new THREE.AudioLoader();
const loadSound = async (url, { loop = false, volume = 1, positional = true } = {}) => {
	const buf = await audioLoader.loadAsync(url);
	const a = positional ? new THREE.PositionalAudio(listener) : new THREE.Audio(listener);
	a.setBuffer(buf); a.setLoop(loop); a.setVolume(volume);
	if (positional) { a.setRefDistance(6); a.setMaxDistance(60); gate.add(a); }
	return a;
};
const [sfxChevron, sfxKawoosh, sfxHum] = await Promise.all([
	loadSound('../../sounds/stargate_chevron_incom.mp3', { volume: 0.9 }),
	loadSound('../../sounds/gate_kawoosh.wav', { volume: 1.0 }),
	loadSound('../../sounds/gate_active_hum.wav', { loop: true, volume: 0.6 }),
]);
// Ring-spin rumble: no asset in repo → synthesized low filtered noise (ponytail: swap for a wav when one exists)
const makeRumble = () => {
	const ctx = listener.context; const len = ctx.sampleRate * 2; const buf = ctx.createBuffer(1, len, ctx.sampleRate);
	const d = buf.getChannelData(0); let l = 0; for (let i = 0; i < len; i++) { l = l * 0.985 + (Math.random() * 2 - 1) * 0.015; d[i] = l * 6; }
	const a = new THREE.PositionalAudio(listener); a.setBuffer(buf); a.setLoop(true); a.setVolume(0); a.setRefDistance(6); gate.add(a);
	const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 140; a.setFilter(f);
	return a;
};
const sfxRumble = makeRumble();

let dialing = true;
const IDLE_INPUT = { move: { x: 0, y: 0 }, run: false };
const startDial = () => {
	document.getElementById('loading')?.remove();
	gate.userData.reset(); dialing = true; sfxHum.stop();
	listener.context.resume();
	sfxRumble.play();
	gate.userData.dial((ev, i) => {
		if (ev === 'chevron') { if (sfxChevron.isPlaying) sfxChevron.stop(); sfxChevron.play(); if (i === GATE.chevrons - 1) sfxRumble.setVolume(0); }
		if (ev === 'kawoosh') { sfxKawoosh.play(); }
		if (ev === 'active') { sfxHum.play(); dialing = false; }
	});
};
document.getElementById('loading').addEventListener('click', startDial, { once: true });
window.__startDial = startDial;
window.__dbg = { input, player, camera, colliders, gate, setView: (v) => setView(v), cam: () => cam, faded: () => faded };

// --- View modes: follow (3rd person) → top (down onto the gate, for kawoosh validation) → orbit (free)
const VIEWS = ['follow', 'top', 'orbit'];
let view = 'follow';
const orbit = new OrbitControls(camera, renderer.domElement); orbit.enabled = false; orbit.enableDamping = true;
orbit.target.set(0, GATE.rOuter, gz);
const viewEl = document.getElementById('view');
const setView = (v) => {
	view = v; input.lockEnabled = v === 'follow'; orbit.enabled = v === 'orbit';
	if (v !== 'follow' && document.pointerLockElement) document.exitPointerLock();
	if (v === 'orbit') camera.position.set(9, 7, gz + 9);
	room.userData.ceiling.visible = v !== 'top';
	viewEl.textContent = `view: ${v} (V)`;
};


// --- Third-person follow camera (behind + above, like the reference framing)
const cam = { yaw: 0, pitch: 0.12, dist: 5.0, height: 1.5 };
const camTarget = new THREE.Vector3(), camPos = new THREE.Vector3();
const updateCamera = (dt) => {
	cam.yaw -= input.look.x; cam.pitch = THREE.MathUtils.clamp(cam.pitch + input.look.y, -0.35, 0.9);
	camTarget.copy(player.root.position).add(new THREE.Vector3(0, cam.height, 0));
	const off = new THREE.Vector3(Math.sin(cam.yaw) * Math.cos(cam.pitch), Math.sin(cam.pitch), Math.cos(cam.yaw) * Math.cos(cam.pitch)).multiplyScalar(cam.dist);
	camPos.copy(camTarget).add(off);
	// keep the camera inside the walls / above the floor
	camPos.x = THREE.MathUtils.clamp(camPos.x, -ROOM.width / 2 + 0.4, ROOM.width / 2 - 0.4);
	camPos.z = Math.min(camPos.z, gz + ROOM.length - 5 - 0.4);
	camPos.y = Math.max(camPos.y, 0.3);
	camera.position.lerp(camPos, Math.min(1, dt * 12));
	camera.lookAt(camTarget);
};

// --- Camera occlusion: anything between camera and player goes ~90% transparent (per-mesh material clone, restored when clear)
const raycaster = new THREE.Raycaster();
const occludable = [];
room.traverse((o) => { if (o.isMesh && o !== room.userData.reflector && o.geometry.type !== 'PlaneGeometry') occludable.push(o); });
gate.traverse((o) => { if (o.isMesh && o.name !== 'eventHorizon') occludable.push(o); });
const faded = new Map(); // mesh → original material
const updateOcclusion = () => {
	const target = player.root.position.clone().add(new THREE.Vector3(0, 1.2, 0));
	const dir = target.clone().sub(camera.position); const dist = dir.length(); dir.normalize();
	raycaster.set(camera.position, dir); raycaster.far = dist - 0.3;
	const hits = new Set(raycaster.intersectObjects(occludable, false).map((h) => h.object));
	for (const mesh of hits) {
		if (faded.has(mesh)) continue;
		faded.set(mesh, mesh.material);
		const mat = mesh.material.clone(); mat.transparent = true; mat.opacity = 0.1; mat.depthWrite = false; mesh.material = mat;
	}
	for (const [mesh, orig] of faded) if (!hits.has(mesh)) { mesh.material.dispose(); mesh.material = orig; faded.delete(mesh); }
};

// --- Gate travel: walk into the puddle → ripple, dive, whiteout, respawn
const flash = document.getElementById('flash');
let travel = null; // { t }
const gateTravelCheck = () => {
	const p = player.root.position;
	const dx = p.x - gate.position.x, dz = p.z - gz;
	if (!travel && gate.userData.active && Math.abs(dz) < 0.25 && Math.hypot(dx, 0) < GATE.rInner - 0.3) {
		travel = { t: 0 };
		gate.userData.ripple(dx, PLAYER_CHEST - gate.position.y);
	}
};
const PLAYER_CHEST = 1.1;
const updateTravel = (dt) => {
	if (!travel) return;
	travel.t += dt;
	// dive camera into the horizon
	const k = Math.min(1, travel.t / 1.1);
	const dive = new THREE.Vector3(0, gate.position.y, gz + 3.5 * (1 - k) + 0.1);
	camera.position.lerp(dive, Math.min(1, dt * 4));
	camera.lookAt(0, gate.position.y, gz - 5);
	flash.style.opacity = String(THREE.MathUtils.smoothstep(travel.t, 0.7, 1.15));
	player.root.visible = travel.t < 0.55;
	if (travel.t > 1.5) {
		player.root.position.copy(SPAWN); player.root.rotation.y = Math.PI; player.root.visible = true;
		cam.yaw = 0; camera.position.set(0, 2, SPAWN.z + 4.2);
		travel = null; flash.style.opacity = '0';
	}
};

addEventListener('resize', () => {
	camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
	renderer.setSize(innerWidth, innerHeight);
	room.userData.reflector.getRenderTarget().setSize(Math.floor(innerWidth * 0.5), Math.floor(innerHeight * 0.5));
});

const fpsEl = document.getElementById('fps');
const clock = new THREE.Clock(); let acc = 0, frames = 0;
renderer.setAnimationLoop(() => {
	const dt = Math.min(clock.getDelta(), 0.05); const t = clock.elapsedTime;
	poll(dt);
	if (input.cycleView) setView(VIEWS[(VIEWS.indexOf(view) + 1) % VIEWS.length]);
	if (input.redial && !dialing && !travel) { sfxRumble.setVolume(0); sfxRumble.isPlaying || sfxRumble.play(); startDial(); }
	const camUpdate = (d) => {
		if (view === 'follow') updateCamera(d);
		else if (view === 'top') { camera.position.lerp(new THREE.Vector3(0.001, 10.6, gz + 2.4), Math.min(1, d * 6)); camera.lookAt(0, 0, gz + 2.4); }
		else orbit.update();
	};
	if (dialing) { sfxRumble.setVolume(Math.min(0.8, sfxRumble.getVolume() + dt * 0.6)); player.update(dt, IDLE_INPUT, cam.yaw, colliders); camUpdate(dt); }
	else if (!travel) { player.update(dt, input, cam.yaw, colliders); gateTravelCheck(); camUpdate(dt); }
	if (view === 'follow') updateOcclusion();
	else { player.mixer.update(dt); updateTravel(dt); }
	gate.userData.tick(t, dt);
	renderer.render(scene, camera);
	acc += dt; frames++; if (acc > 0.5) { fpsEl.textContent = `${Math.round(frames / acc)} fps`; acc = 0; frames = 0; }
});
