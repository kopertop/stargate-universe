// Kino drone mode: the camera becomes a floating reconnaissance orb. Fly it through an active gate to scan the far side.
import * as THREE from 'three';
export const createKino = () => {
	const orb = new THREE.Group();
	const body = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 14), new THREE.MeshStandardMaterial({ color: 0x555a60, roughness: 0.35, metalness: 0.8 }));
	const lens = new THREE.Mesh(new THREE.SphereGeometry(0.05, 10, 8), new THREE.MeshStandardMaterial({ color: 0x66f0ff, emissive: 0x33d0ff, emissiveIntensity: 3 }));
	lens.position.set(0, 0, 0.15); orb.add(body, lens);
	const light = new THREE.PointLight(0x66e0ff, 4, 6); orb.add(light);
	const state = { orb, active: false, yaw: 0, pitch: 0, vel: new THREE.Vector3(), scanT: 0 };
	state.launch = (pos, yaw) => { orb.position.copy(pos); state.yaw = yaw; state.pitch = 0; state.vel.set(0, 0, 0); state.active = true; state.scanT = 0; orb.visible = true; };
	state.recall = () => { state.active = false; orb.visible = false; };
	/** Fly: input.move (x strafe, y fwd), input.look, Space/jump up, run = descend. Returns nothing; caller handles gate crossing. */
	state.update = (dt, input, camera) => {
		state.yaw -= input.look.x; state.pitch = THREE.MathUtils.clamp(state.pitch + input.look.y, -1.2, 1.2);
		const fwd = new THREE.Vector3(-Math.sin(state.yaw), 0, -Math.cos(state.yaw)), right = new THREE.Vector3(-fwd.z, 0, fwd.x);
		const want = fwd.multiplyScalar(input.move.y).addScaledVector(right, input.move.x);
		want.y = (input.jump || input.keys?.has('Space') ? 1 : 0) - (input.run ? 1 : 0);
		want.multiplyScalar(5.5);
		state.vel.lerp(want, Math.min(1, dt * 4));
		orb.position.addScaledVector(state.vel, dt);
		orb.rotation.y = state.yaw;
		// camera rides just behind/above the orb, looking where it looks
		const camOff = new THREE.Vector3(Math.sin(state.yaw) * 1.7, 0.55, Math.cos(state.yaw) * 1.7);
		camera.position.copy(orb.position).add(camOff);
		const look = orb.position.clone().add(new THREE.Vector3(-Math.sin(state.yaw) * Math.cos(state.pitch), Math.sin(state.pitch), -Math.cos(state.yaw) * Math.cos(state.pitch)));
		camera.up.set(0, 1, 0); camera.lookAt(look);
	};
	orb.visible = false;
	return state;
};
