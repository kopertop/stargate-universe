// Destination: desert world with a stone gate dais. Returns { scene, colliders, gate, spawn, occludable, clampCamera }.
import * as THREE from 'three';
import { createStargate, GATE } from './stargate.js';

export const createDestination = () => {
	const scene = new THREE.Scene();
	scene.background = new THREE.Color(0xc9b28a);
	scene.fog = new THREE.FogExp2(0xc9b28a, 0.012);
	const colliders = [], occludable = [];
	const GZ = 0; // gate at origin facing +Z; player exits toward +Z
	// ONE terrain function drives both the ground mesh and collision (floorAt). Flat within 14 m of the gate.
	const terrainHeight = (x, z) => {
		const dd = Math.hypot(x, z - GZ);
		return dd < 14 ? 0 : Math.sin(x * 0.08) * Math.cos(z * 0.06) * 2.2 * Math.min(1, (dd - 14) / 20);
	};

	// sky dome (gradient)
	const sky = new THREE.Mesh(new THREE.SphereGeometry(180, 24, 12), new THREE.ShaderMaterial({
		side: THREE.BackSide, depthWrite: false,
		vertexShader: `varying vec3 vP; void main(){ vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
		fragmentShader: `varying vec3 vP; void main(){ float h = clamp(vP.y / 180.0, 0.0, 1.0); gl_FragColor = vec4(mix(vec3(0.85,0.72,0.55), vec3(0.45,0.62,0.85), pow(h, 0.6)), 1.0); }`,
	}));
	scene.add(sky);

	// ground
	const gc = document.createElement('canvas'); gc.width = gc.height = 512; const g = gc.getContext('2d');
	g.fillStyle = '#b48a5a'; g.fillRect(0, 0, 512, 512);
	for (let i = 0; i < 4000; i++) { g.fillStyle = `rgba(${60 + Math.random() * 60},${40 + Math.random() * 40},${20 + Math.random() * 20},${Math.random() * 0.35})`; g.fillRect(Math.random() * 512, Math.random() * 512, 1 + Math.random() * 3, 1 + Math.random() * 3); }
	const gt = new THREE.CanvasTexture(gc); gt.colorSpace = THREE.SRGBColorSpace; gt.wrapS = gt.wrapT = THREE.RepeatWrapping; gt.repeat.set(40, 40); gt.anisotropy = 8;
	const SIZE = 400, SEG = 96, CELL = SIZE / SEG;
	const ground = new THREE.Mesh(new THREE.PlaneGeometry(SIZE, SIZE, SEG, SEG), new THREE.MeshStandardMaterial({ map: gt, roughness: 1 }));
	// gentle dunes away from the dais
	const pos = ground.geometry.attributes.position;
	// plane is rotated -90° about X, so local (x, y) → world (x, -y). Vertex index = iy * (SEG + 1) + ix with world z
	// increasing along iy. Heights are kept in a grid so collision can interpolate the SAME triangles the GPU draws.
	const H = new Float32Array(pos.count);
	for (let i = 0; i < pos.count; i++) { H[i] = terrainHeight(pos.getX(i), -pos.getY(i)); pos.setZ(i, H[i]); }
	/** Height of the rendered surface at world (x, z): bilinear on PlaneGeometry's (a,b,d)/(b,c,d) triangle split. */
	const meshHeight = (x, z) => {
		const fx = THREE.MathUtils.clamp((x + SIZE / 2) / CELL, 0, SEG - 1e-6), fz = THREE.MathUtils.clamp((z - GZ + SIZE / 2) / CELL, 0, SEG - 1e-6);
		const ix = Math.floor(fx), iy = Math.floor(fz), u = fx - ix, v = fz - iy, W = SEG + 1;
		const ha = H[iy * W + ix], hb = H[(iy + 1) * W + ix], hc = H[(iy + 1) * W + ix + 1], hd = H[iy * W + ix + 1];
		return u + v <= 1 ? ha + (hb - ha) * v + (hd - ha) * u : hc + (hb - hc) * (1 - u) + (hd - hc) * (1 - v);
	};
	ground.geometry.computeVertexNormals();
	ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; scene.add(ground);

	// dais + steps
	const stone = new THREE.MeshStandardMaterial({ color: 0x8a7a62, roughness: 0.95 });
	const dais = new THREE.Mesh(new THREE.CylinderGeometry(6.5, 7, 0.3, 24), stone); dais.position.set(0, 0.15, GZ); dais.receiveShadow = true; scene.add(dais);
	const step = new THREE.Mesh(new THREE.CylinderGeometry(7.5, 8, 0.15, 24), stone); step.position.set(0, 0.075, GZ); step.receiveShadow = true; scene.add(step);
	// obelisks flanking the approach (colliders)
	for (const sx of [-1, 1]) for (const z of [8, 14]) {
		const o = new THREE.Mesh(new THREE.BoxGeometry(0.8, 3.5 + Math.random(), 0.8), stone);
		o.position.set(sx * 3.8, 1.75 + meshHeight(sx * 3.8, GZ + z), GZ + z); o.castShadow = o.receiveShadow = true; scene.add(o);
		colliders.push(new THREE.Box3().setFromObject(o)); occludable.push(o);
	}
	// rocks
	const rockMat = new THREE.MeshStandardMaterial({ color: 0x7a6a56, roughness: 1, flatShading: true });
	for (let i = 0; i < 40; i++) {
		const a = Math.random() * Math.PI * 2, d = 14 + Math.random() * 60;
		const s = 0.6 + Math.random() * 2.4;
		const r = new THREE.Mesh(new THREE.DodecahedronGeometry(s, 0), rockMat);
		const rx = Math.cos(a) * d, rz = GZ + Math.sin(a) * d;
		r.position.set(rx, meshHeight(rx, rz) + s * 0.4, rz); r.rotation.set(Math.random(), Math.random(), Math.random());
		r.castShadow = r.receiveShadow = true; scene.add(r);
		// circle collider hugging the visible rock (a Box3 of a rotated dodecahedron is up to 1.7× too wide → invisible walls)
		colliders.push({ circle: true, x: rx, z: rz, r: s * 0.85 }); occludable.push(r);
	}

	// gate
	const gate = createStargate();
	gate.position.set(0, GATE.rInner + 0.3 - 0.15, GZ); scene.add(gate);
	for (const sx of [-1, 1]) colliders.push(new THREE.Box3(new THREE.Vector3(sx * 2.9 - 0.7, 0, GZ - 0.4), new THREE.Vector3(sx * 2.9 + 0.7, 8, GZ + 0.4)));
	gate.traverse((o) => { if (o.isMesh && o.name !== 'eventHorizon') occludable.push(o); });

	// lighting: low sun
	const sun = new THREE.DirectionalLight(0xffe6c4, 3.2); sun.position.set(-30, 25, 20); sun.castShadow = true;
	sun.shadow.mapSize.set(2048, 2048); sun.shadow.camera.left = sun.shadow.camera.bottom = -30; sun.shadow.camera.right = sun.shadow.camera.top = 30; sun.shadow.camera.far = 120; sun.shadow.bias = -0.0005;
	scene.add(sun, new THREE.HemisphereLight(0x9fb8d8, 0x8a6a48, 1.2));

	return {
		name: 'planet', scene, colliders, gate, occludable,
		spawn: new THREE.Vector3(0, 0, GZ + 1.2), spawnYaw: 0, // facing +Z (away from the gate)
		exitDir: 1, // player walks +Z out of this gate
		clampCamera: (p) => { p.y = Math.max(p.y, meshHeight(p.x, p.z) + 0.4); },
		floorAt: (x, z) => { const r = Math.hypot(x, z - GZ); return r < 6.5 ? 0.3 : r < 7.5 ? 0.15 : meshHeight(x, z); },
		ground, terrainHeight, meshHeight,
	};
};
