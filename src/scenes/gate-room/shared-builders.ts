/**
 * Gate-Room Shared Builders
 *
 * Exports the geometry + lighting builders used by both the gate-room gameplay
 * scene and the opening-cinematic scene.  Both consumers import from here so the
 * visual environment is always identical.
 *
 * Builders return explicit handles (meshes, lights, runtime state) rather than
 * relying on module-level side-effect arrays, so they are safe to call from
 * multiple scene mounts.
 */
import * as THREE from "three";

// ─── Room dimensions & gate geometry constants ────────────────────────────────

export const ROOM_WIDTH    = 26;
export const ROOM_DEPTH    = 40;
export const ROOM_HEIGHT   = 8;
export const GATE_RADIUS   = 2.8;
export const GATE_TUBE     = 0.22;
export const GATE_CENTER   = new THREE.Vector3(0, GATE_RADIUS + GATE_TUBE - 0.3, 0);
export const CHEVRON_COUNT = 9;

// ─── SGU colour palette ───────────────────────────────────────────────────────

export const COLOR_ANCIENT_METAL  = 0x2a2a3a;
export const COLOR_ANCIENT_GLOW   = 0x4488ff;
export const COLOR_CHEVRON_OFF    = 0x111122;
export const COLOR_CHEVRON_ON     = 0x44aaff;
export const COLOR_EVENT_HORIZON  = 0x88bbff;
export const COLOR_WALL           = 0x1a1a2e;
export const COLOR_CEILING        = 0x141425;
export const COLOR_WARM_ACCENT    = 0xffaa44;

// ─── Shared types ─────────────────────────────────────────────────────────────

export type GateState = "idle" | "dialing" | "kawoosh" | "active" | "shutdown";

export type GateRuntime = {
	chevronMeshes: THREE.Mesh[];
	dialElapsed:   number;
	eventHorizon:  THREE.Mesh;
	innerRing:     THREE.Mesh;
	kawooshElapsed: number;
	lockedChevrons: number;
	outerRing:     THREE.Mesh;
	pointLights:   THREE.PointLight[];
	state:         GateState;
};

export type RoomResult = {
	/** All wall / ceiling meshes — useful for camera-occlusion transparency. */
	wallMeshes: THREE.Mesh[];
	/** Floor mesh (y = 0 plane). */
	floorMesh:  THREE.Mesh;
};

// ─── Internal helpers ─────────────────────────────────────────────────────────

function createWallMaterial(): THREE.MeshStandardMaterial {
	return new THREE.MeshStandardMaterial({
		color:             0x222238,
		emissive:          0x141428,
		emissiveIntensity: 1.0,
		roughness:         0.9,
		metalness:         0.1,
		side:              THREE.DoubleSide,
	});
}

/**
 * Create a flat-profiled ring (rectangular cross-section) using LatheGeometry.
 * LatheGeometry rotates a 2-D profile around Y; we then rotate 90° so it faces +Z.
 */
function createFlatRingGeometry(
	radius:   number,
	width:    number,
	depth:    number,
	segments: number = 64,
): THREE.BufferGeometry {
	const halfW  = width / 2;
	const halfD  = depth / 2;
	const outerR = radius + halfW;
	const innerR = radius - halfW;

	const points = [
		new THREE.Vector2(innerR, -halfD),
		new THREE.Vector2(outerR, -halfD),
		new THREE.Vector2(outerR,  halfD),
		new THREE.Vector2(innerR,  halfD),
	];

	const geo = new THREE.LatheGeometry(points, segments);
	geo.rotateX(Math.PI / 2);
	return geo;
}

// ─── Public builders ──────────────────────────────────────────────────────────

/**
 * Build the Destiny gate-room enclosure: walls, floor, ceiling, arch supports,
 * structural frame around the gate alcove, and amber guide strips.
 * Returns handles to all created meshes.
 */
export function buildRoom(scene: THREE.Scene): RoomResult {
	const wallMeshes: THREE.Mesh[] = [];
	const wallMat = createWallMaterial();

	const ceilingMat = new THREE.MeshStandardMaterial({
		color:             0x181828,
		emissive:          0x060612,
		emissiveIntensity: 1.0,
		roughness:         0.95,
		metalness:         0.05,
		side:              THREE.DoubleSide,
	});

	// ── Floor ────────────────────────────────────────────────────────────────
	const floorMat  = new THREE.MeshStandardMaterial({
		color:     0x101018,
		roughness: 0.92,
		metalness: 0.15,
	});
	const floorMesh = new THREE.Mesh(
		new THREE.BoxGeometry(ROOM_WIDTH, 0.2, ROOM_DEPTH),
		floorMat,
	);
	floorMesh.position.set(0, -0.1, 0);
	scene.add(floorMesh);

	// ── Back wall (behind gate, -Z side) ─────────────────────────────────────
	const backWall = new THREE.Mesh(
		new THREE.BoxGeometry(ROOM_WIDTH, ROOM_HEIGHT, 0.5),
		createWallMaterial(),
	);
	backWall.position.set(0, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2);
	scene.add(backWall);
	wallMeshes.push(backWall);

	// ── Front wall — split with doorway gap (4 m wide) ────────────────────────
	const doorwayWidth   = 4;
	const frontPieceW    = (ROOM_WIDTH - doorwayWidth) / 2;
	for (const xSign of [-1, 1]) {
		const piece = new THREE.Mesh(
			new THREE.BoxGeometry(frontPieceW, ROOM_HEIGHT, 0.5),
			createWallMaterial(),
		);
		piece.position.set(
			xSign * (doorwayWidth / 2 + frontPieceW / 2),
			ROOM_HEIGHT / 2,
			ROOM_DEPTH / 2,
		);
		scene.add(piece);
		wallMeshes.push(piece);
	}
	// Door frame top piece
	const doorTop = new THREE.Mesh(
		new THREE.BoxGeometry(doorwayWidth + 0.5, ROOM_HEIGHT - 3.5, 0.5),
		createWallMaterial(),
	);
	doorTop.position.set(0, ROOM_HEIGHT - (ROOM_HEIGHT - 3.5) / 2, ROOM_DEPTH / 2);
	scene.add(doorTop);
	wallMeshes.push(doorTop);

	// ── Side walls ───────────────────────────────────────────────────────────
	const leftWall = new THREE.Mesh(
		new THREE.BoxGeometry(0.5, ROOM_HEIGHT, ROOM_DEPTH),
		createWallMaterial(),
	);
	leftWall.position.set(-ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 0);
	scene.add(leftWall);
	wallMeshes.push(leftWall);

	const rightWall = new THREE.Mesh(
		new THREE.BoxGeometry(0.5, ROOM_HEIGHT, ROOM_DEPTH),
		createWallMaterial(),
	);
	rightWall.position.set(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 0);
	scene.add(rightWall);
	wallMeshes.push(rightWall);

	// ── Ceiling ───────────────────────────────────────────────────────────────
	const ceiling = new THREE.Mesh(
		new THREE.BoxGeometry(ROOM_WIDTH, 0.5, ROOM_DEPTH),
		ceilingMat,
	);
	ceiling.position.set(0, ROOM_HEIGHT, 0);
	scene.add(ceiling);
	wallMeshes.push(ceiling);

	// ── Structural arch supports ──────────────────────────────────────────────
	const archMat = new THREE.MeshStandardMaterial({
		color:     0x15152a,
		roughness: 0.8,
		metalness: 0.2,
	});
	for (let i = -2; i <= 2; i++) {
		if (i === 0) continue;
		for (const xSign of [-1, 1]) {
			const arch = new THREE.Mesh(
				new THREE.BoxGeometry(0.4, ROOM_HEIGHT, 0.6),
				archMat,
			);
			arch.position.set(
				xSign * (ROOM_WIDTH / 2 - (xSign < 0 ? -0.4 : 0.4)),
				ROOM_HEIGHT / 2,
				i * 4,
			);
			scene.add(arch);
		}
	}

	// ── Structural frame around gate alcove ───────────────────────────────────
	const frameMat = new THREE.MeshStandardMaterial({
		color:     0x1a1a30,
		roughness: 0.75,
		metalness: 0.25,
	});
	const topBeam = new THREE.Mesh(
		new THREE.BoxGeometry(10, 0.8, 0.6),
		frameMat,
	);
	topBeam.position.set(0, ROOM_HEIGHT - 1, -ROOM_DEPTH / 2 + 0.5);
	scene.add(topBeam);

	for (const xSign of [-1, 1]) {
		const column = new THREE.Mesh(
			new THREE.BoxGeometry(0.8, ROOM_HEIGHT, 0.6),
			frameMat,
		);
		column.position.set(xSign * 4.5, ROOM_HEIGHT / 2, -ROOM_DEPTH / 2 + 0.5);
		scene.add(column);
	}

	// ── Amber floor guide strips ──────────────────────────────────────────────
	const stripMat = new THREE.MeshStandardMaterial({
		color:             0xddaa33,
		emissive:          0xddaa33,
		emissiveIntensity: 0.4,
		roughness:         0.6,
		metalness:         0.3,
	});
	const stripStartZ  = ROOM_DEPTH / 2 - 2;
	const stripEndZ    = -ROOM_DEPTH / 2 + 2;
	const stripSpacing = 1.4;
	for (let z = stripStartZ; z >= stripEndZ; z -= stripSpacing) {
		for (const x of [-1.2, 1.2]) {
			const strip = new THREE.Mesh(
				new THREE.BoxGeometry(0.12, 0.02, 0.5),
				stripMat,
			);
			strip.position.set(x, 0.01, z);
			scene.add(strip);
		}
	}

	return { wallMeshes, floorMesh };
}

/**
 * Build the Stargate ring, chevrons, and event horizon disc.
 * Returns a GateRuntime handle; state starts at "idle".
 */
export function buildStargate(scene: THREE.Scene): GateRuntime {
	// ── Outer ring ────────────────────────────────────────────────────────────
	const outerRingMat = new THREE.MeshStandardMaterial({
		color:     COLOR_ANCIENT_METAL,
		roughness: 0.3,
		metalness: 0.85,
	});
	const outerRing = new THREE.Mesh(
		createFlatRingGeometry(GATE_RADIUS, GATE_TUBE * 2.2, GATE_TUBE * 1.4),
		outerRingMat,
	);
	outerRing.position.copy(GATE_CENTER);
	scene.add(outerRing);

	// ── Inner ring (spins during dialing) ─────────────────────────────────────
	const innerRingMat = new THREE.MeshStandardMaterial({
		color:     0x222235,
		roughness: 0.25,
		metalness: 0.9,
	});
	const innerRing = new THREE.Mesh(
		createFlatRingGeometry(GATE_RADIUS - 0.05, GATE_TUBE * 1.4, GATE_TUBE * 1.0),
		innerRingMat,
	);
	innerRing.position.copy(GATE_CENTER);
	scene.add(innerRing);

	// ── Decorative ring segments ──────────────────────────────────────────────
	const segmentMat = new THREE.MeshStandardMaterial({
		color:     0x333348,
		roughness: 0.35,
		metalness: 0.8,
	});
	const SEGMENT_COUNT = 36;
	for (let i = 0; i < SEGMENT_COUNT; i++) {
		const angle   = (i / SEGMENT_COUNT) * Math.PI * 2;
		const segment = new THREE.Mesh(
			new THREE.BoxGeometry(0.22, 0.12, 0.12),
			segmentMat,
		);
		segment.position.set(
			GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 0.08),
			GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 0.08),
			GATE_CENTER.z + 0.08,
		);
		segment.lookAt(
			GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 2),
			GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 2),
			GATE_CENTER.z + 0.08,
		);
		scene.add(segment);
	}

	// ── Chevrons ──────────────────────────────────────────────────────────────
	const chevronMeshes: THREE.Mesh[] = [];
	for (let i = 0; i < CHEVRON_COUNT; i++) {
		const angle      = (i / CHEVRON_COUNT) * Math.PI * 2 - Math.PI / 2;
		const chevronMat = new THREE.MeshStandardMaterial({
			color:             COLOR_CHEVRON_OFF,
			roughness:         0.4,
			metalness:         0.7,
			emissive:          new THREE.Color(COLOR_CHEVRON_OFF),
			emissiveIntensity: 0.1,
		});
		const chevron = new THREE.Mesh(
			new THREE.BoxGeometry(0.18, 0.3, 0.15),
			chevronMat,
		);
		chevron.position.set(
			GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 0.15),
			GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 0.15),
			GATE_CENTER.z + 0.15,
		);
		chevron.lookAt(
			GATE_CENTER.x + Math.cos(angle) * (GATE_RADIUS + 2),
			GATE_CENTER.y + Math.sin(angle) * (GATE_RADIUS + 2),
			GATE_CENTER.z + 0.15,
		);
		scene.add(chevron);
		chevronMeshes.push(chevron);
	}

	// ── Event horizon disc ────────────────────────────────────────────────────
	const horizonMat = new THREE.MeshStandardMaterial({
		color:             COLOR_EVENT_HORIZON,
		emissive:          new THREE.Color(COLOR_EVENT_HORIZON),
		emissiveIntensity: 0.8,
		transparent:       true,
		opacity:           0,
		side:              THREE.DoubleSide,
		roughness:         0.1,
		metalness:         0.0,
	});
	const eventHorizon = new THREE.Mesh(
		new THREE.CircleGeometry(GATE_RADIUS - GATE_TUBE - 0.05, 64),
		horizonMat,
	);
	eventHorizon.position.copy(GATE_CENTER);
	eventHorizon.visible = false;
	scene.add(eventHorizon);

	return {
		chevronMeshes,
		dialElapsed:    0,
		eventHorizon,
		innerRing,
		kawooshElapsed: 0,
		lockedChevrons: 0,
		outerRing,
		pointLights:    [],
		state:          "idle",
	};
}

/**
 * Build atmospheric lighting for the gate room.
 * `debugObjects` receives SpotLightHelper meshes (hidden by default) so the
 * caller can include them in scene-level debug toggles.
 */
export function buildLighting(
	scene:        THREE.Scene,
	debugObjects: THREE.Object3D[],
): THREE.PointLight[] {
	const lights: THREE.PointLight[] = [];
	const gateZ  = GATE_CENTER.z;

	// Hemisphere fill (sky + ground bounce)
	const hemisphereLight = new THREE.HemisphereLight(0x4466aa, 0x111122, 2.0);
	scene.add(hemisphereLight);

	// 1. Overhead general fill
	const overheadLight = new THREE.PointLight(0xffeedd, 80, 40, 1.5);
	overheadLight.position.set(0, 7.5, 2);
	scene.add(overheadLight);
	lights.push(overheadLight);

	// 2. Gate front — Ancient blue glow
	const gateFrontLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 200, 15, 1.5);
	gateFrontLight.position.set(0, 2, gateZ + 2);
	scene.add(gateFrontLight);
	lights.push(gateFrontLight);

	// 3. Gate back — rim light
	const gateBackLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 150, 12, 1.5);
	gateBackLight.position.set(0, 3.5, gateZ - 3);
	scene.add(gateBackLight);
	lights.push(gateBackLight);

	// 4. Gate top — highlights upper ring
	const gateTopLight = new THREE.PointLight(COLOR_ANCIENT_GLOW, 100, 10, 2);
	gateTopLight.position.set(0, 7, gateZ);
	scene.add(gateTopLight);
	lights.push(gateTopLight);

	// 5-6. Warm amber side fills
	const leftSide = new THREE.PointLight(COLOR_WARM_ACCENT, 60, 18, 1.5);
	leftSide.position.set(-ROOM_WIDTH / 2 + 2, 3, 0);
	scene.add(leftSide);
	lights.push(leftSide);

	const rightSide = new THREE.PointLight(COLOR_WARM_ACCENT, 60, 18, 1.5);
	rightSide.position.set(ROOM_WIDTH / 2 - 2, 3, 0);
	scene.add(rightSide);
	lights.push(rightSide);

	// 7-10. Floor spotlights aimed at gate faces
	const gateY        = GATE_CENTER.y;
	const spotPositions = [
		{ pos: [-2.5, 0.1, gateZ + 3.5] as const, target: [-GATE_RADIUS * 0.5, gateY, gateZ + 0.15] as const, zDir: -1 },
		{ pos: [ 2.5, 0.1, gateZ + 3.5] as const, target: [ GATE_RADIUS * 0.5, gateY, gateZ + 0.15] as const, zDir: -1 },
		{ pos: [-2.5, 0.1, gateZ - 3.5] as const, target: [-GATE_RADIUS * 0.5, gateY, gateZ - 0.15] as const, zDir:  1 },
		{ pos: [ 2.5, 0.1, gateZ - 3.5] as const, target: [ GATE_RADIUS * 0.5, gateY, gateZ - 0.15] as const, zDir:  1 },
	];

	const housingMat = new THREE.MeshStandardMaterial({ color: 0x222233, roughness: 0.6, metalness: 0.4 });
	const lensMat    = new THREE.MeshStandardMaterial({ color: 0xccddff, emissive: 0xbbddff, emissiveIntensity: 1.5 });

	for (const sp of spotPositions) {
		const spot = new THREE.SpotLight(0xbbddff, 30, 20, Math.PI / 5, 0.5, 1.0);
		spot.position.set(sp.pos[0], sp.pos[1], sp.pos[2]);
		spot.target.position.set(sp.target[0], sp.target[1], sp.target[2]);
		scene.add(spot);
		scene.add(spot.target);

		const helper = new THREE.SpotLightHelper(spot, 0xffff00);
		helper.visible = false;
		scene.add(helper);
		helper.update();
		debugObjects.push(helper);

		const dx  = sp.target[0] - sp.pos[0];
		const dy  = sp.target[1] - sp.pos[1];
		const dz  = sp.target[2] - sp.pos[2];
		const hDist    = Math.sqrt(dx * dx + dz * dz);
		const tiltAngle = Math.atan2(dy, hDist);

		const fixtureGroup = new THREE.Group();
		fixtureGroup.position.set(sp.pos[0], 0.18, sp.pos[2]);
		fixtureGroup.rotation.x = sp.zDir * -tiltAngle;

		const housing = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.35, 0.6), housingMat);
		fixtureGroup.add(housing);
		const lens = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.25, 0.05), lensMat);
		lens.position.set(0, 0, sp.zDir * 0.33);
		fixtureGroup.add(lens);
		scene.add(fixtureGroup);
	}

	// Emissive Ancient glow strips along floor edges
	const glowStripMat = new THREE.MeshStandardMaterial({
		color:             COLOR_ANCIENT_GLOW,
		emissive:          new THREE.Color(COLOR_ANCIENT_GLOW),
		emissiveIntensity: 0.5,
	});
	for (const xSign of [-1, 1]) {
		const strip = new THREE.Mesh(
			new THREE.BoxGeometry(0.06, 0.12, ROOM_DEPTH - 2),
			glowStripMat,
		);
		strip.position.set(xSign * (ROOM_WIDTH / 2 - 0.3), 0.1, 0);
		scene.add(strip);
	}

	// Emissive panels behind gate (cheaper than extra point lights)
	const backGlowMat = new THREE.MeshStandardMaterial({
		color:             0x2244aa,
		emissive:          new THREE.Color(0x2244aa),
		emissiveIntensity: 0.6,
	});
	for (const xSign of [-1, 1]) {
		const panel = new THREE.Mesh(
			new THREE.BoxGeometry(0.1, 4, 2),
			backGlowMat,
		);
		panel.position.set(xSign * 3, 2.5, gateZ - 2);
		scene.add(panel);
	}

	return lights;
}

/**
 * Kawoosh animation constants — exported so the cinematic can drive the same
 * burst/retract/settle curve independently of the gameplay GateState machine.
 */
export const KAWOOSH_DURATION           = 1.2;
export const KAWOOSH_BURST_PHASE        = 0.3;   // fraction: burst
export const KAWOOSH_RETRACT_PHASE      = 0.3;   // fraction: retract
export const KAWOOSH_BURST_MAX_SCALE    = 1.5;
