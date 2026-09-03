// Player: CC0 OpenBot mannequin (repo asset) with idle/walk/run blending, capsule-vs-AABB sliding collision.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const MODEL_URL = '../../models/mixamo_openbot/OpenBot.glb';
export const PLAYER = { radius: 0.35, height: 1.72, walk: 4.2, run: 10.4, turnLerp: 10, jumpVel: 5.5, gravity: 15 };

export const loadPlayer = async () => {
	const gltf = await new GLTFLoader().loadAsync(MODEL_URL);
	const root = new THREE.Group(); root.name = 'player';
	const model = gltf.scene;
	// OpenBot is ~1.58m; scale to a 1.72m human-ish silhouette like the reference mannequin
	const s = PLAYER.height / 1.58; model.scale.setScalar(s);
	const grey = new THREE.MeshStandardMaterial({ color: 0xb9b1a3, roughness: 0.5, metalness: 0.2 });
	const seam = new THREE.MeshStandardMaterial({ color: 0x6b645a, roughness: 0.6, metalness: 0.3 });
	model.traverse((o) => {
		if (o.isMesh) { o.castShadow = true; o.receiveShadow = false; o.frustumCulled = false; o.material = o.material.name === 'Orange' ? seam : grey; }
	});
	root.add(model);

	const mixer = new THREE.AnimationMixer(model);
	const clip = (n) => gltf.animations.find((a) => a.name === n);
	// Strip hips root-motion translation so the loop stays in place (we drive world position ourselves)
	for (const a of gltf.animations) a.tracks = a.tracks.filter((t) => !(t.name.endsWith('hips.position')));
	const actions = {
		idle: mixer.clipAction(clip('idle1-loop')),
		walk: mixer.clipAction(clip('walk-loop')),
		run: mixer.clipAction(clip('run-loop')),
		fidget: mixer.clipAction(clip('idle2-loop')),
		jump: mixer.clipAction(clip('jump')),
	};
	actions.jump.setLoop(THREE.LoopOnce, 1); actions.jump.clampWhenFinished = true;
	for (const a of Object.values(actions)) { a.play(); a.setEffectiveWeight(0); }
	actions.idle.setEffectiveWeight(1);

	const vel = new THREE.Vector3();
	const weights = { idle: 1, walk: 0, run: 0, fidget: 0, jump: 0 };
	let vy = 0, grounded = true;
	// idle fidget: every 5–9 s of standing still, blend the second idle clip in for one pass
	let fidgetTimer = 4, fidgetLeft = 0;
	const FIDGET_LEN = actions.fidget.getClip().duration;

	const state = { root, mixer, actions, speed: 0, heading: 0 };
	const skinned = []; model.traverse((o) => { if (o.isSkinnedMesh) skinned.push(o); });
	/** 0 = solid, 1 = fully dematerialised (materials go transparent only while fading). */
	state.setFade = (f) => { for (const m of [grey, seam]) { m.transparent = f > 0; m.opacity = 1 - f; m.depthWrite = f <= 0; } };
	/** Random world-space point on the posed skin surface (for disintegration particles). */
	state.samplePoint = (out) => {
		const mesh = skinned[Math.floor(Math.random() * skinned.length)];
		const i = Math.floor(Math.random() * mesh.geometry.attributes.position.count);
		return mesh.getVertexPosition(i, out).applyMatrix4(mesh.matrixWorld);
	};

	/** Move with camera-relative input; slide along AABB colliders. */
	state.update = (dt, input, camYaw, colliders, floorY = 0) => {
		const { move, run, jump } = input;
		const mag = Math.hypot(move.x, move.y);
		const target = mag > 0 ? (run ? PLAYER.run : PLAYER.walk) * mag : 0;
		state.speed += (target - state.speed) * Math.min(1, dt * 8);
		if (mag > 0) {
			// camera yaw: 0 looks toward -Z. forward = (-sin yaw, -cos yaw)
			const fwd = new THREE.Vector3(-Math.sin(camYaw), 0, -Math.cos(camYaw));
			const right = new THREE.Vector3(-fwd.z, 0, fwd.x);
			vel.copy(fwd).multiplyScalar(move.y).addScaledVector(right, move.x).normalize().multiplyScalar(state.speed);
			const desired = Math.atan2(vel.x, vel.z);
			let d = desired - root.rotation.y; d = Math.atan2(Math.sin(d), Math.cos(d));
			root.rotation.y += d * Math.min(1, dt * PLAYER.turnLerp);
		} else vel.set(0, 0, 0);

		// jump / gravity (flat floor at y=0)
		if (jump && grounded) { vy = PLAYER.jumpVel; grounded = false; actions.jump.reset().play(); }
		if (!grounded) { vy -= PLAYER.gravity * dt; root.position.y += vy * dt; if (root.position.y <= floorY) { root.position.y = floorY; vy = 0; grounded = true; } }
		else root.position.y += (floorY - root.position.y) * Math.min(1, dt * 20); // step up/down onto daises
		state.grounded = grounded;
		// axis-separated slide against boxes (ponytail: XZ only, floor is flat)
		const p = root.position; const r = PLAYER.radius;
		for (const axis of ['x', 'z']) {
			p[axis] += vel[axis] * dt;
			for (const b of colliders) {
				if (p.x + r > b.min.x && p.x - r < b.max.x && p.z + r > b.min.z && p.z - r < b.max.z && b.min.y < 1.2) {
					if (axis === 'x') p.x = vel.x > 0 ? b.min.x - r : b.max.x + r;
					else p.z = vel.z > 0 ? b.min.z - r : b.max.z + r;
				}
			}
		}

		// animation blend by speed
		const runT = THREE.MathUtils.smoothstep(state.speed, PLAYER.walk + 0.4, PLAYER.run - 0.6);
		const moveT = THREE.MathUtils.smoothstep(state.speed, 0.05, 0.9);
		if (moveT < 0.05) {
			if (fidgetLeft > 0) fidgetLeft -= dt;
			else if ((fidgetTimer -= dt) <= 0) { fidgetLeft = FIDGET_LEN; fidgetTimer = 5 + Math.random() * 4; actions.fidget.reset(); }
		} else fidgetLeft = 0;
		const fid = fidgetLeft > 0.3 ? 1 : 0;
		const air = grounded ? 0 : 1;
		const tw = { idle: (1 - moveT) * (1 - fid) * (1 - air), fidget: (1 - moveT) * fid * (1 - air), walk: moveT * (1 - runT) * (1 - air), run: moveT * runT * (1 - air), jump: air };
		for (const k in tw) { weights[k] += (tw[k] - weights[k]) * Math.min(1, dt * (k === 'jump' ? 25 : 10)); actions[k].setEffectiveWeight(weights[k]); }
		actions.walk.timeScale = 0.9 + (state.speed / PLAYER.walk) * 0.35;
		mixer.update(dt);
	};
	return state;
};
