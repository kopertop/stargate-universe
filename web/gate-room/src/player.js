// Character: Quaternius Universal Animation Library mannequin (repo asset) driven by BOTH UAL1 + UAL2 clip sets
// (same skeleton). Locomotion blend (idle/fidget/walk/carry/jog/jump) + one-shot / looping action API for interactions.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const MODEL_URL = '../../models/quaternius/anim_lib/UAL1_Standard.glb';
const EXTRA_CLIPS_URL = '../../models/quaternius/anim_lib/UAL2_Standard.glb';
export const PLAYER = { radius: 0.35, height: 1.72, walk: 4.2, run: 10.4, turnLerp: 10, jumpVel: 5.5, gravity: 15 };

// Semantic action names → library clip names. To swap in a Mixamo pack (FBX → GLB, retargeted to this skeleton or its own),
// change MODEL_URL/EXTRA_CLIPS_URL and remap here; gameplay code only ever uses the keys.
export const CLIPS = {
	idle: 'Idle_Loop', fidget: 'Idle_FoldArms_Loop', walk: 'Walk_Loop', carry: 'Walk_Carry_Loop', run: 'Jog_Fwd_Loop', sprint: 'Sprint_Loop', air: 'Jump_Loop',
	interact: 'Interact', pickup: 'PickUp_Table', open: 'Chest_Open', repair: 'Fixing_Kneeling', dig: 'Farm_Harvest', talk: 'Idle_Talking_Loop', nod: 'Yes', device: 'Idle_TalkingPhone_Loop',
};
const loader = new GLTFLoader();
let cache = null;
const loadAssets = async () => {
	cache ??= Promise.all([loader.loadAsync(MODEL_URL), loader.loadAsync(EXTRA_CLIPS_URL)]);
	return cache;
};

/** Load a rigged character. `tint` recolours the body; clips from both libraries are available by name. */
export const loadPlayer = async ({ tint = 0x9d978d } = {}) => {
	const [gltf, extra] = await loadAssets();
	const root = new THREE.Group(); root.name = 'character';
	// clone the scene per character so several can animate independently (SkeletonUtils.clone keeps skinning)
	const { clone } = await import('three/addons/utils/SkeletonUtils.js');
	const model = clone(gltf.scene);
	model.scale.setScalar(PLAYER.height / 1.83); // UAL mannequin is 1.83 m
	const body = new THREE.MeshStandardMaterial({ color: tint, roughness: 0.5, metalness: 0.2 });
	const joints = new THREE.MeshStandardMaterial({ color: new THREE.Color(tint).multiplyScalar(0.55), roughness: 0.6, metalness: 0.3 });
	model.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = false; o.frustumCulled = false; o.material = o.material.name === 'M_Joints' ? joints : body; } });
	root.add(model);

	const clips = new Map();
	for (const a of [...gltf.animations, ...extra.animations]) {
		const c = a.clone(); c.tracks = c.tracks.filter((t) => !t.name.startsWith('root.position') && !t.name.startsWith('Armature.')); clips.set(c.name, c);
	}
	const mixer = new THREE.AnimationMixer(model);
	const act = (key, loop = THREE.LoopRepeat) => { const name = CLIPS[key] ?? key; const c = clips.get(name); if (!c) throw new Error(`missing clip ${name}`); const a = mixer.clipAction(c); a.setLoop(loop, loop === THREE.LoopOnce ? 1 : Infinity); a.clampWhenFinished = loop === THREE.LoopOnce; return a; };
	const loco = Object.fromEntries(['idle', 'fidget', 'walk', 'carry', 'run', 'sprint', 'air'].map((k) => [k, act(CLIPS[k])]));
	for (const a of Object.values(loco)) { a.play(); a.setEffectiveWeight(0); }
	loco.idle.setEffectiveWeight(1);
	const weights = Object.fromEntries(Object.keys(loco).map((k) => [k, k === 'idle' ? 1 : 0]));

	const state = { root, model, mixer, clips, speed: 0, grounded: true, speedMul: 1, carrying: false, action: null };
	let vy = 0, grounded = true, fidgetTimer = 4, fidgetLeft = 0, landT = 0;
	const FIDGET_LEN = clips.get(CLIPS.fidget).duration;

	// ---- action layer: one-shot (Interact, PickUp_Table, Chest_Open, Fixing_Kneeling, Yes …) or looping (Farm_Harvest, Idle_TalkingPhone_Loop)
	/** Play a clip on top of locomotion. Returns a promise resolving when a one-shot finishes. `loop` keeps it until stopAction(). */
	state.clipDuration = (name) => clips.get(CLIPS[name] ?? name).duration;
	state.playAction = (name, { loop = false, timeScale = 1, fade = 0.15 } = {}) => {
		state.stopAction(fade);
		const a = act(name, loop ? THREE.LoopRepeat : THREE.LoopOnce); a.reset(); a.timeScale = timeScale; a.setEffectiveWeight(1); a.fadeIn(fade); a.play();
		state.action = { name, a, loop };
		if (loop) return Promise.resolve();
		const dur = clips.get(CLIPS[name] ?? name).duration / timeScale;
		return new Promise((res) => setTimeout(() => { if (state.action?.a === a) state.stopAction(); res(); }, dur * 1000));
	};
	state.stopAction = (fade = 0.2) => {
		const cur = state.action; if (!cur) return; cur.a.fadeOut(fade); setTimeout(() => cur.a.stop(), fade * 1000 + 20); state.action = null;
		// hand the body straight back to idle so the blend never sums to ~0 (which flashes the bind pose)
		weights.idle = 1; loco.idle.setEffectiveWeight(1);
	};
	state.actionName = () => state.action?.name ?? null;

	/** Attach a prop to a bone (e.g. shovel → hand_r). */
	state.bone = (n) => model.getObjectByName(n);
	state.attach = (obj, boneName) => { const b = state.bone(boneName); if (b) b.add(obj); return b; };

	const skinned = []; model.traverse((o) => { if (o.isSkinnedMesh) skinned.push(o); });
	state.setFade = (f) => { for (const m of [body, joints]) { m.transparent = f > 0; m.opacity = 1 - f; m.depthWrite = f <= 0; } };
	state.samplePoint = (out) => { const mesh = skinned[Math.floor(Math.random() * skinned.length)]; const i = Math.floor(Math.random() * mesh.geometry.attributes.position.count); return mesh.getVertexPosition(i, out).applyMatrix4(mesh.matrixWorld); };

	const vel = new THREE.Vector3();
	/** Move with camera-relative input; slide along colliders; drive the locomotion blend. Movement is frozen during a one-shot action. */
	state.update = (dt, input, camYaw, colliders, floorY = 0) => {
		const { move, run, jump } = input;
		const acting = !!state.action && !state.action.loop; // one-shots root the character
		const mag = acting ? 0 : Math.hypot(move.x, move.y);
		const target = mag > 0 ? (run ? PLAYER.run : PLAYER.walk) * mag * state.speedMul : 0;
		state.speed += (target - state.speed) * Math.min(1, dt * 8);
		if (mag > 0) {
			const fwd = new THREE.Vector3(-Math.sin(camYaw), 0, -Math.cos(camYaw)), right = new THREE.Vector3(-fwd.z, 0, fwd.x);
			vel.copy(fwd).multiplyScalar(move.y).addScaledVector(right, move.x).normalize().multiplyScalar(state.speed);
			const desired = Math.atan2(vel.x, vel.z); let d = desired - root.rotation.y; d = Math.atan2(Math.sin(d), Math.cos(d));
			root.rotation.y += d * Math.min(1, dt * PLAYER.turnLerp);
		} else vel.set(0, 0, 0);

		if (jump && grounded && !acting) { vy = PLAYER.jumpVel; grounded = false; }
		if (!grounded) { vy -= PLAYER.gravity * dt; root.position.y += vy * dt; if (root.position.y <= floorY) { root.position.y = floorY; vy = 0; grounded = true; landT = 0.35; } }
		else root.position.y = floorY;
		state.grounded = grounded;

		const p = root.position, r = PLAYER.radius;
		for (const axis of ['x', 'z']) {
			p[axis] += vel[axis] * dt;
			for (const b of colliders) {
				if (b.circle) continue;
				if (p.x + r > b.min.x && p.x - r < b.max.x && p.z + r > b.min.z && p.z - r < b.max.z && b.min.y < 1.2) {
					if (axis === 'x') p.x = vel.x > 0 ? b.min.x - r : b.max.x + r; else p.z = vel.z > 0 ? b.min.z - r : b.max.z + r;
				}
			}
		}
		for (const c of colliders) { if (!c.circle) continue; const dx = p.x - c.x, dz = p.z - c.z, dist = Math.hypot(dx, dz), minD = c.r + r; if (dist < minD && dist > 1e-4) { p.x = c.x + (dx / dist) * minD; p.z = c.z + (dz / dist) * minD; } }

		// locomotion blend
		const moveT = THREE.MathUtils.smoothstep(state.speed, 0.05, 0.9);
		const runT = THREE.MathUtils.smoothstep(state.speed, PLAYER.walk + 0.6, PLAYER.run - 1.5);
		const sprintT = THREE.MathUtils.smoothstep(state.speed, 8.5, 10);
		if (moveT < 0.05 && !state.action) { if (fidgetLeft > 0) fidgetLeft -= dt; else if ((fidgetTimer -= dt) <= 0) { fidgetLeft = FIDGET_LEN; fidgetTimer = 6 + Math.random() * 5; loco.fidget.reset(); } } else fidgetLeft = 0;
		const fid = fidgetLeft > 0.3 ? 1 : 0, air = grounded ? 0 : 1, actW = state.action ? 1 : 0; // action layer takes over the body
		const walkW = moveT * (1 - runT), carryW = state.carrying ? 1 : 0;
		const tw = {
			idle: (1 - moveT) * (1 - fid) * (1 - air) * (1 - actW), fidget: (1 - moveT) * fid * (1 - air) * (1 - actW),
			walk: walkW * (1 - carryW) * (1 - air) * (1 - actW), carry: walkW * carryW * (1 - air) * (1 - actW),
			run: moveT * runT * (1 - sprintT) * (1 - air) * (1 - actW), sprint: moveT * runT * sprintT * (1 - air) * (1 - actW), air: air * (1 - actW),
		};
		for (const k in tw) weights[k] += (tw[k] - weights[k]) * Math.min(1, dt * (k === 'air' ? 25 : 10));
		if (!state.action) { const sum = Object.values(weights).reduce((a, b) => a + b, 0); if (sum < 1) weights.idle += 1 - sum; }
		for (const k in tw) loco[k].setEffectiveWeight(weights[k]);
		loco.walk.timeScale = loco.carry.timeScale = 0.9 + (state.speed / PLAYER.walk) * 0.45; loco.run.timeScale = 0.9 + (state.speed / PLAYER.run) * 0.5;
		if (landT > 0) landT -= dt;
		mixer.update(dt);
	};
	return state;
};
