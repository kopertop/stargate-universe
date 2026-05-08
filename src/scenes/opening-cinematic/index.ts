/**
 * Opening Cinematic — story intro played on NEW GAME.
 *
 * Flow:
 *   start-screen → NEW GAME → opening-cinematic → gate-room (with kawoosh cinematic)
 *
 * This scene shows a starfield + credit beats + a GLB reveal of the Ancient
 * vessel Destiny drifting through deep space. When the beats finish
 * (or the player skips with ESC/Space) it sets the `sgu-new-game` flag so
 * the gate-room's GateRoomCinematicController plays the 9-beat arrival
 * sequence next.
 */
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import { AudioManager } from "../../systems/audio";
import destinyShipModelUrl from "./assets/destiny-ship.glb?url";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── Credit beats ─────────────────────────────────────────────────────────────

interface CreditBeat {
	/** Seconds into the cinematic when this beat begins fading in. */
	start: number;
	/** Seconds into the cinematic when this beat begins fading out. */
	end: number;
	/** Line(s) of text. `\n` renders a line break. */
	text: string;
	/** Font size — bigger for title, smaller for body. */
	fontSize: string;
}

// ─── 60-second opening timeline ─────────────────────────────────────────────
//
// This scene is act one (0-20s). The gate-room arrival cinematic (fired
// via sgu-new-game flag) is act two (20-60s). The sgu-theme-song plays
// once at t=0 and runs the full 60s without a restart — this scene
// starts it and INTENTIONALLY does not stop on dispose so the theme
// carries through the scene swap.
//
// Test any second of this scene in isolation via ?cinstep=N&cinfreeze=1:
//   /?scene=opening-cinematic&cinstep=12&cinfreeze=1   ← jumps to t=12
//
const TOTAL_DURATION = 24;
const TUNNEL_START = 17;
const TUNNEL_END   = 21;

const BEATS: CreditBeat[] = [
	{ start: 0.5, end: 4.5,  fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "In a distant corner of the universe…" },
	{ start: 5,    end: 9,   fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "the Ancients launched a ship called Destiny —\nseeded before humanity walked the Earth." },
	{ start: 9.5,  end: 13.5, fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "For millions of years it has drifted alone,\nmapping the farthest reaches of space." },
	{ start: 14,   end: 17,   fontSize: "clamp(1rem, 2vw, 1.2rem)",
		text: "One gate has a nine-symbol address.\nEli figured out how to dial it." },
	{ start: 17.4, end: 20.6, fontSize: "clamp(2.2rem, 6vw, 4rem)",
		text: "STARGATE\u00A0UNIVERSE" },
];

// ─── Star-field (same look as start-screen for continuity) ────────────────────

function buildStarField(scene: THREE.Scene): THREE.Points {
	const COUNT = 2500;
	const pos = new Float32Array(COUNT * 3);
	const col = new Float32Array(COUNT * 3);
	for (let i = 0; i < COUNT; i++) {
		const theta = Math.random() * Math.PI * 2;
		const phi   = Math.acos(2 * Math.random() - 1);
		const r     = 80 + Math.random() * 140;
		pos[i * 3    ] = r * Math.sin(phi) * Math.cos(theta);
		pos[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
		pos[i * 3 + 2] = r * Math.cos(phi);
		const brightness = 0.5 + Math.random() * 0.5;
		const blueShift  = Math.random() * 0.3;
		col[i * 3    ] = brightness * (1 - blueShift * 0.4);
		col[i * 3 + 1] = brightness * (1 - blueShift * 0.2);
		col[i * 3 + 2] = brightness;
	}
	const geo = new THREE.BufferGeometry();
	geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
	geo.setAttribute("color",    new THREE.BufferAttribute(col, 3));
	const mat = new THREE.PointsMaterial({
		size: 0.55, sizeAttenuation: true, vertexColors: true,
		transparent: true, opacity: 0.88,
	});
	const points = new THREE.Points(geo, mat);
	scene.add(points);
	return points;
}

// ─── Procedural Destiny ─────────────────────────────────────────────────────────
//
// Destiny's exterior is a long Ancient wedge: a knife-like prow, broad crescent
// aft rim, high dorsal tower, and dense plated surface detail. The cinematic uses
// a procedural approximation so the opening can keep animating without a heavy
// ship asset.

interface Destiny {
	root: THREE.Group;
	geometries: Set<THREE.BufferGeometry>;
	materials: Set<THREE.Material>;
	textures?: Set<THREE.Texture>;
}

const DESTINY_MODEL_TARGET_LENGTH = 24;
const DESTINY_MODEL_FORWARD_ROTATION_Y = Math.PI / 2;

const collectMaterialTextures = (material: THREE.Material): THREE.Texture[] =>
	Object.values(material as unknown as Record<string, unknown>)
		.filter((value): value is THREE.Texture => value instanceof THREE.Texture);

const tuneModelMaterial = (material: THREE.Material): void => {
	material.side = THREE.FrontSide;

	if ("roughness" in material && typeof material.roughness === "number") {
		material.roughness = Math.max(material.roughness, 0.84);
	}
	if ("metalness" in material && typeof material.metalness === "number") {
		material.metalness = Math.max(material.metalness, 0.22);
	}
	// Preserve interior window/accent glow — concept (exterior-hero-shot.png)
	// shows the ship reading as alive against the void via blue running lights
	// and warm interior windows. Previous clamp at 0.18 was killing those.
	// Allow up to 1.5 emissive intensity, and only slightly reduce baked
	// emissive colors (was multiplying by 0.18 — far too aggressive).
	if ("emissiveIntensity" in material && typeof material.emissiveIntensity === "number") {
		material.emissiveIntensity = Math.min(material.emissiveIntensity, 1.5);
	}
	if ("emissive" in material && material.emissive instanceof THREE.Color) {
		material.emissive.multiplyScalar(0.85);
	}
};

async function loadDestinyModel(scene: THREE.Scene): Promise<Destiny | null> {
	try {
		const loader = new GLTFLoader();
		const gltf = await loader.loadAsync(destinyShipModelUrl);
		const model = gltf.scene;
		const root = new THREE.Group();
		const geometries = new Set<THREE.BufferGeometry>();
		const materials = new Set<THREE.Material>();
		const textures = new Set<THREE.Texture>();

		root.name = "destiny-ship";
		model.name = "destiny-ship-glb";

		model.updateMatrixWorld(true);
		const box = new THREE.Box3().setFromObject(model);
		const size = box.getSize(new THREE.Vector3());
		const center = box.getCenter(new THREE.Vector3());
		const scale = DESTINY_MODEL_TARGET_LENGTH / Math.max(size.x, size.y, size.z);

		model.position.sub(center);
		root.scale.setScalar(scale);
		root.rotation.y = DESTINY_MODEL_FORWARD_ROTATION_Y;

		model.traverse((node) => {
			if (!(node instanceof THREE.Mesh)) return;
			node.castShadow = true;
			node.receiveShadow = true;
			geometries.add(node.geometry);

			const materialList = Array.isArray(node.material) ? node.material : [node.material];
			for (const material of materialList) {
				materials.add(material);
				tuneModelMaterial(material);
				for (const texture of collectMaterialTextures(material)) textures.add(texture);
			}
		});

		root.add(model);
		scene.add(root);

		// Interior glow accents — concept exterior-hero-shot.png shows the ship
		// reading as alive against the void via window banks + engine glow.
		// The GLB has no emissive windows of its own, so we layer two effects:
		// (1) interior point lights bleeding warm/cool onto nearby plating, and
		// (2) additive sprite quads acting as visible window strips along the
		//     hull. Both attached to the scene in WORLD space (post-scale ship
		//     is ~24 units along its long axis; ship forward = -Z).
		const accentDefs: Array<{ pos: [number, number, number]; color: number; intensity: number; range: number }> = [
			{ pos: [0, 1.0, -8], color: 0x88bbff, intensity: 25, range: 6 },   // bridge
			{ pos: [0, 0.0, 9],  color: 0x66ddff, intensity: 60, range: 10 }, // engine bell
		];
		for (const def of accentDefs) {
			const light = new THREE.PointLight(def.color, def.intensity, def.range, 1.6);
			light.position.set(...def.pos);
			scene.add(light);
		}

		// Visible engine glare sprites — concept exterior-hero-shot.png shows
		// the engines as a bright blue underbelly emissive disc readable from
		// long camera distances. PointLights alone don't contribute a visible
		// halo because the hull is dark and the engine bay is recessed; add an
		// additive Sprite that reads as the engine bell glow itself.
		// (memory: feedback_distant_emitters_use_sprite)
		const engineGlowCanvas = document.createElement("canvas");
		engineGlowCanvas.width = engineGlowCanvas.height = 256;
		const egCtx = engineGlowCanvas.getContext("2d");
		if (egCtx) {
			const gradient = egCtx.createRadialGradient(128, 128, 0, 128, 128, 128);
			gradient.addColorStop(0, "rgba(200, 240, 255, 1.0)");
			gradient.addColorStop(0.15, "rgba(120, 200, 255, 0.95)");
			gradient.addColorStop(0.45, "rgba(60, 140, 220, 0.55)");
			gradient.addColorStop(1, "rgba(40, 90, 180, 0)");
			egCtx.fillStyle = gradient;
			egCtx.fillRect(0, 0, 256, 256);
		}
		const engineGlowTex = new THREE.CanvasTexture(engineGlowCanvas);
		engineGlowTex.colorSpace = THREE.SRGBColorSpace;
		const engineSpriteMat = new THREE.SpriteMaterial({
			map: engineGlowTex,
			transparent: true,
			blending: THREE.AdditiveBlending,
			depthWrite: false,
			toneMapped: false,
			fog: false,
		});
		const engineSprite = new THREE.Sprite(engineSpriteMat);
		engineSprite.position.set(0, 0.2, 9.4);
		engineSprite.scale.set(3.2, 3.2, 1);
		scene.add(engineSprite);

		// Bridge / forward window-bank pinpoint to give the silhouette a
		// readable "this end is the bow" cue at long range.
		const bridgeSprite = new THREE.Sprite(engineSpriteMat.clone());
		(bridgeSprite.material as THREE.SpriteMaterial).map = engineGlowTex;
		(bridgeSprite.material as THREE.SpriteMaterial).needsUpdate = true;
		bridgeSprite.position.set(0, 1.0, -7.6);
		bridgeSprite.scale.set(0.9, 0.9, 1);
		scene.add(bridgeSprite);

		// Hull window-bank pinpoints — concept hero shows hundreds of warm
		// interior windows reading as life along the silhouette. The GLB has
		// no emissive windows, so layer additive Sprites along the long axis.
		// Two parallel rows just offset from centerline read as port/starboard
		// window banks at this distance. (memory: feedback_distant_emitters_use_sprite)
		const winCanvas = document.createElement("canvas");
		winCanvas.width = winCanvas.height = 64;
		const winCtx = winCanvas.getContext("2d");
		if (winCtx) {
			const wg = winCtx.createRadialGradient(32, 32, 0, 32, 32, 32);
			wg.addColorStop(0.00, "rgba(255, 240, 200, 1.0)");
			wg.addColorStop(0.35, "rgba(255, 210, 140, 0.6)");
			wg.addColorStop(1.00, "rgba(255, 180, 100, 0)");
			winCtx.fillStyle = wg;
			winCtx.fillRect(0, 0, 64, 64);
		}
		const winTex = new THREE.CanvasTexture(winCanvas);
		winTex.colorSpace = THREE.SRGBColorSpace;
		const winMat = new THREE.SpriteMaterial({
			map: winTex,
			transparent: true,
			blending: THREE.AdditiveBlending,
			depthWrite: false,
			toneMapped: false,
			fog: false,
			opacity: 0.85,
		});
		const winRowZ = [-7, -5.5, -4, -2.5, -1, 0.5, 2, 3.5, 5, 6.5, 8];
		for (const z of winRowZ) {
			for (const xOff of [-0.55, 0.55] as const) {
				const w = new THREE.Sprite(winMat);
				w.position.set(xOff, 0.55, z);
				w.scale.set(0.32, 0.18, 1);
				scene.add(w);
			}
		}

		return { root, geometries, materials, textures };
	} catch (error) {
		console.warn("[OpeningCinematic] Failed to load Destiny GLB, using procedural fallback.", error);
		return null;
	}
}

type Vec2Tuple = readonly [number, number];
type Vec3Tuple = readonly [number, number, number];

const makeAftArc = (segments = 20): THREE.Vector2[] =>
	Array.from({ length: segments + 1 }, (_, index) => {
		const t = index / segments;
		const x = 7.65 - t * 15.3;
		const z = 8.15 - Math.sin(t * Math.PI) * 1.18;
		return new THREE.Vector2(x, z);
	});

const makeDestinyPlanform = (): THREE.Vector2[] => {
	const starboard = [
		new THREE.Vector2(0, -15.8),
		new THREE.Vector2(0.55, -15.25),
		new THREE.Vector2(1.15, -13.6),
		new THREE.Vector2(1.85, -10.8),
		new THREE.Vector2(2.55, -7.2),
		new THREE.Vector2(3.2, -3.4),
		new THREE.Vector2(4.15, 0.6),
		new THREE.Vector2(5.75, 4.2),
		new THREE.Vector2(7.65, 8.15),
	];
	const port = starboard
		.slice(1, -1)
		.reverse()
		.map((point) => new THREE.Vector2(-point.x, point.y));

	return [...starboard, ...makeAftArc().slice(1), ...port];
};

const createDeckGeometry = (
	points: readonly THREE.Vector2[],
	topY: number,
	bottomY: number,
): THREE.BufferGeometry => {
	const vertices = [
		...points.flatMap((point) => [point.x, topY, point.y]),
		...points.flatMap((point) => [point.x, bottomY, point.y]),
	];
	const count = points.length;
	const contour = points.map((point) => new THREE.Vector2(point.x, point.y));
	const triangles = THREE.ShapeUtils.triangulateShape(contour, []);
	const indices: number[] = [];

	for (const [a, b, c] of triangles) {
		indices.push(c, b, a);
		indices.push(a + count, b + count, c + count);
	}

	for (let index = 0; index < count; index++) {
		const next = (index + 1) % count;
		indices.push(index, next, next + count);
		indices.push(index, next + count, index + count);
	}

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
	geometry.setIndex(indices);
	geometry.computeVertexNormals();
	return geometry;
};

const createTaperedBoxGeometry = (
	bottomWidth: number,
	topWidth: number,
	bottomDepth: number,
	topDepth: number,
	height: number,
): THREE.BufferGeometry => {
	const bw = bottomWidth / 2;
	const tw = topWidth / 2;
	const bd = bottomDepth / 2;
	const td = topDepth / 2;
	const vertices = [
		-bw, 0, -bd, bw, 0, -bd, bw, 0, bd, -bw, 0, bd,
		-tw, height, -td, tw, height, -td, tw, height, td, -tw, height, td,
	];
	const indices = [
		0, 2, 1, 0, 3, 2,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		1, 2, 6, 1, 6, 5,
		2, 3, 7, 2, 7, 6,
		3, 0, 4, 3, 4, 7,
	];
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
	geometry.setIndex(indices);
	geometry.computeVertexNormals();
	return geometry;
};

const hullHalfWidthAtZ = (z: number): number => {
	const samples: Vec2Tuple[] = [
		[-15.8, 0.16],
		[-13.6, 1.15],
		[-10.8, 1.85],
		[-7.2, 2.55],
		[-3.4, 3.2],
		[0.6, 4.15],
		[4.2, 5.75],
		[8.15, 7.65],
	];

	if (z <= samples[0][0]) return samples[0][1];
	for (let index = 1; index < samples.length; index++) {
		const [nextZ, nextWidth] = samples[index];
		const [prevZ, prevWidth] = samples[index - 1];
		if (z <= nextZ) {
			const t = (z - prevZ) / (nextZ - prevZ);
			return prevWidth + (nextWidth - prevWidth) * t;
		}
	}
	return samples[samples.length - 1][1];
};

function buildDestiny(scene: THREE.Scene): Destiny {
	const root = new THREE.Group();
	root.name = "destiny-ship";
	const geometries = new Set<THREE.BufferGeometry>();
	const materials = new Set<THREE.Material>();

	const hullMat = new THREE.MeshStandardMaterial({
		color: 0x191b1b,
		roughness: 0.88,
		metalness: 0.32,
		emissive: 0x030405,
		emissiveIntensity: 0.35,
	});
	const plateMat = new THREE.MeshStandardMaterial({
		color: 0x272a27,
		roughness: 0.93,
		metalness: 0.18,
		emissive: 0x020303,
		emissiveIntensity: 0.28,
	});
	const shadowMat = new THREE.MeshStandardMaterial({
		color: 0x0b0d0e,
		roughness: 0.96,
		metalness: 0.26,
	});
	const trimMat = new THREE.MeshStandardMaterial({
		color: 0x3e4645,
		roughness: 0.82,
		metalness: 0.35,
	});
	const windowMat = new THREE.MeshBasicMaterial({
		color: 0xcfeeff,
		transparent: true,
		opacity: 0.92,
		blending: THREE.AdditiveBlending, depthWrite: false,
	});

	const trackMaterial = (material: THREE.Material | THREE.Material[]): void => {
		const list = Array.isArray(material) ? material : [material];
		for (const entry of list) materials.add(entry);
	};

	const addMesh = (
		geometry: THREE.BufferGeometry,
		material: THREE.Material | THREE.Material[],
		setup: (mesh: THREE.Mesh) => void,
	): THREE.Mesh => {
		const mesh = new THREE.Mesh(geometry, material);
		setup(mesh);
		root.add(mesh);
		geometries.add(geometry);
		trackMaterial(material);
		return mesh;
	};

	const addBox = (
		size: Vec3Tuple,
		position: Vec3Tuple,
		material: THREE.Material,
		rotationY = 0,
	): THREE.Mesh => addMesh(
		new THREE.BoxGeometry(size[0], size[1], size[2]),
		material,
		(mesh) => {
			mesh.position.set(position[0], position[1], position[2]);
			mesh.rotation.y = rotationY;
		},
	);

	const addMirroredBox = (
		size: Vec3Tuple,
		position: Vec3Tuple,
		material: THREE.Material,
		rotationY = 0,
	): void => {
		for (const xSign of [-1, 1]) {
			addBox(
				size,
				[position[0] * xSign, position[1], position[2]],
				material,
				rotationY * xSign,
			);
		}
	};

	const addSegment = (
		from: Vec2Tuple,
		to: Vec2Tuple,
		width: number,
		height: number,
		y: number,
		material: THREE.Material,
	): void => {
		const dx = to[0] - from[0];
		const dz = to[1] - from[1];
		const length = Math.hypot(dx, dz);
		addBox(
			[width, height, length],
			[(from[0] + to[0]) / 2, y, (from[1] + to[1]) / 2],
			material,
			Math.atan2(dx, dz),
		);
	};

	const deckPoints = makeDestinyPlanform();
	addMesh(createDeckGeometry(deckPoints, 0.22, -0.34), hullMat, (mesh) => {
		mesh.castShadow = true;
		mesh.receiveShadow = true;
	});

	const insetDeck = deckPoints.map((point) => new THREE.Vector2(point.x * 0.82, point.y * 0.96 - 0.12));
	addMesh(createDeckGeometry(insetDeck, 0.34, 0.2), plateMat, (mesh) => {
		mesh.receiveShadow = true;
	});

	addMesh(createTaperedBoxGeometry(3.35, 1.25, 23.2, 16.4, 0.44), shadowMat, (mesh) => {
		mesh.position.set(0, -0.82, -3.55);
	});
	addMesh(createTaperedBoxGeometry(3.1, 1.4, 12.8, 8.6, 0.58), plateMat, (mesh) => {
		mesh.position.set(0, 0.42, -5.2);
	});
	addMesh(createTaperedBoxGeometry(4.3, 2.2, 4.9, 3.05, 2.35), plateMat, (mesh) => {
		mesh.position.set(0, 0.35, 3.75);
	});
	addMesh(createTaperedBoxGeometry(2.25, 1.25, 3.0, 1.9, 1.05), shadowMat, (mesh) => {
		mesh.position.set(0, 2.65, 3.82);
	});
	addMesh(createTaperedBoxGeometry(2.6, 1.2, 5.0, 2.5, 0.76), hullMat, (mesh) => {
		mesh.position.set(0, 0.5, -0.45);
	});

	for (const z of [-13.6, -12, -10.3, -8.7, -7.2, -5.7, -4.1, -2.5, -0.8, 0.9, 2.8, 4.6, 6.2]) {
		const halfWidth = hullHalfWidthAtZ(z);
		addBox([Math.max(0.9, halfWidth * 1.35), 0.055, 0.08], [0, 0.47, z], trimMat);
	}

	for (const z of [-12.8, -10.9, -9, -6.4, -4.7, -2.9, -0.9, 1.5, 3.4]) {
		const halfWidth = hullHalfWidthAtZ(z);
		const laneX = Math.min(halfWidth * 0.45, 1.9);
		addMirroredBox([0.12, 0.075, 1.2], [laneX, 0.5, z], trimMat);
		addMirroredBox([Math.max(0.45, halfWidth * 0.36), 0.07, 0.34], [halfWidth * 0.53, 0.51, z + 0.45], plateMat);
	}

	const sideRails: readonly [Vec2Tuple, Vec2Tuple][] = [
		[[0.22, -15.1], [1.65, -10.7]],
		[[1.75, -10.5], [3.05, -3.6]],
		[[3.12, -3.25], [5.52, 4.15]],
		[[5.65, 4.18], [7.2, 7.52]],
	];
	for (const [from, to] of sideRails) {
		addSegment(from, to, 0.12, 0.12, 0.55, trimMat);
		addSegment([-from[0], from[1]], [-to[0], to[1]], 0.12, 0.12, 0.55, trimMat);
	}

	addMirroredBox([0.55, 0.24, 4.6], [2.95, 0.75, 1.45], trimMat, -0.35);
	addMirroredBox([0.42, 0.24, 4.0], [4.65, 0.68, 4.85], trimMat, -0.52);
	addMirroredBox([0.7, 0.22, 2.65], [2.05, 0.78, -3.25], shadowMat, -0.18);
	addMirroredBox([0.9, 0.18, 1.35], [1.2, 0.82, -8.2], plateMat, -0.08);
	addMirroredBox([0.8, 0.2, 1.1], [1.75, 0.78, -6.2], plateMat, -0.12);
	addBox([1.1, 0.18, 2.8], [0, 0.82, -10.2], shadowMat);
	addBox([0.75, 0.18, 1.5], [0, 0.85, -13.2], trimMat);

	const aftArc = makeAftArc(28);
	for (let index = 0; index < aftArc.length - 1; index++) {
		const from = aftArc[index];
		const to = aftArc[index + 1];
		addSegment([from.x, from.y + 0.06], [to.x, to.y + 0.06], 0.24, 0.24, 0.46, shadowMat);
		if (index % 2 === 0) {
			const midX = (from.x + to.x) / 2;
			const midZ = (from.y + to.y) / 2 + 0.21;
			const dx = to.x - from.x;
			const dz = to.y - from.y;
			addBox([0.28, 0.08, 0.055], [midX, 0.58, midZ], windowMat, Math.atan2(dx, dz) + Math.PI / 2);
		}
	}

	for (const x of [-4.9, -3.25, -1.55, 1.55, 3.25, 4.9]) {
		addBox([0.7, 0.08, 0.12], [x, 0.63, 6.55], windowMat);
	}

	scene.add(root);
	return { root, geometries, materials };
}

function disposeDestiny(scene: THREE.Scene, destiny: Destiny): void {
	scene.remove(destiny.root);
	for (const geometry of destiny.geometries) geometry.dispose();
	for (const material of destiny.materials) material.dispose();
	if (destiny.textures) {
		for (const texture of destiny.textures) texture.dispose();
	}
}

// ─── Credit overlay (DOM) ─────────────────────────────────────────────────────

interface CreditOverlay {
	setBeat: (beat: CreditBeat | null) => void;
	dispose: () => void;
}

function createCreditOverlay(): CreditOverlay {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;left:0;right:0;bottom:22%;",
		"text-align:center;pointer-events:none;z-index:80;",
		"color:#d4b96a;letter-spacing:0.08em;font-weight:600;",
		"text-shadow:0 0 18px rgba(68,136,255,0.35),0 2px 8px rgba(0,0,0,0.9);",
		"font-family:'Segoe UI',sans-serif;",
		"white-space:pre-line;opacity:0;",
		"transition:opacity 0.8s ease;",
	].join("");
	document.body.appendChild(el);

	let currentBeat: CreditBeat | null = null;

	return {
		setBeat(beat) {
			if (beat === currentBeat) return;
			currentBeat = beat;
			if (beat) {
				el.textContent = beat.text;
				el.style.fontSize = beat.fontSize;
				el.style.opacity = "1";
			} else {
				el.style.opacity = "0";
			}
		},
		dispose() { el.remove(); },
	};
}

// ─── Tunnel overlay — radial vignette + blue rim that intensifies during the
// warp/jump phase. Frames the smash-cut into the gate-room (Image #1 ref:
// `design/concept-art/gate-room/gate-room-dormant.png`) so the next scene
// reads as the same circular corridor opening seen here.

interface TunnelOverlay {
	/** progress 0..1 — 0 = no tunnel, 1 = full circular vignette + black smash. */
	setProgress: (progress: number) => void;
	dispose: () => void;
}

function createTunnelOverlay(): TunnelOverlay {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;inset:0;pointer-events:none;z-index:78;",
		"background:radial-gradient(circle at 50% 50%,",
		"  transparent 28%,",
		"  rgba(8,18,32,0.0) 38%,",
		"  rgba(4,10,20,0.55) 60%,",
		"  rgba(0,0,0,0.95) 82%);",
		"opacity:0;transition:opacity 0.18s linear;",
		"mix-blend-mode:multiply;",
	].join("");
	const flash = document.createElement("div");
	flash.style.cssText = [
		"position:fixed;inset:0;pointer-events:none;z-index:79;",
		"background:#000;opacity:0;",
	].join("");
	document.body.appendChild(el);
	document.body.appendChild(flash);
	return {
		setProgress(progress) {
			const p = Math.max(0, Math.min(1, progress));
			el.style.opacity = String(p);
			// Final 18% punches to full black so the gate-room dormant shot
			// loads behind a black frame, not mid-warp.
			const blackPunch = p < 0.82 ? 0 : (p - 0.82) / 0.18;
			flash.style.opacity = String(blackPunch);
		},
		dispose() { el.remove(); flash.remove(); },
	};
}

// ─── Skip hint overlay ────────────────────────────────────────────────────────

function createSkipHint(): { setProgress: (p: number) => void; dispose: () => void } {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;bottom:2rem;right:2rem;z-index:80;",
		"color:rgba(255,255,255,0.65);font-size:0.85rem;letter-spacing:0.08em;",
		"font-family:'Segoe UI',sans-serif;pointer-events:none;text-align:right;",
	].join("");

	const label = document.createElement("div");
	label.textContent = "Hold SPACE to skip";
	el.appendChild(label);

	const bar = document.createElement("div");
	bar.style.cssText = "height:2px;background:#ffffff22;margin-top:4px;overflow:hidden;";
	const fill = document.createElement("div");
	fill.style.cssText = "height:100%;background:#d4b96a;width:0%;transition:width 0.05s linear;";
	bar.appendChild(fill);
	el.appendChild(bar);

	document.body.appendChild(el);
	return {
		setProgress(p: number) {
			fill.style.width = `${Math.min(100, p * 100)}%`;
			el.style.color = p > 0 ? "#d4b96aee" : "rgba(255,255,255,0.65)";
		},
		dispose: () => el.remove(),
	};
}

// ─── Scene mount ──────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, gotoScene } = context;

	// Deep space backdrop — equirect CanvasTexture with soft nebula clouds +
	// dense star sparkle, so the cinematic frame reads as galactic space
	// rather than an empty void. Concept hero shot shows visible nebulae
	// and dust lanes; pure-black backdrop killed the sense of scale and
	// scifi grandeur. Texture is procedural (no asset load required).
	const bgCanvas = document.createElement("canvas");
	bgCanvas.width = 2048;
	bgCanvas.height = 1024;
	const bgctx = bgCanvas.getContext("2d")!;
	// Base — very dark blue-black, slightly lifted at horizontal band so a
	// galactic plane reads
	const baseGrad = bgctx.createLinearGradient(0, 0, 0, 1024);
	baseGrad.addColorStop(0.0, "#020308");
	baseGrad.addColorStop(0.45, "#040612");
	baseGrad.addColorStop(0.55, "#06081a");
	baseGrad.addColorStop(1.0, "#020308");
	bgctx.fillStyle = baseGrad;
	bgctx.fillRect(0, 0, 2048, 1024);
	// Diffuse nebula blobs — multiple large soft radial gradients in cool
	// blue/violet/cyan, additively layered. Concentrated near the horizontal
	// midband to sell the galactic-plane look.
	bgctx.globalCompositeOperation = "lighter";
	// Toned WAY down — exposure 3.9 multiplies these in tone-mapping. Source
	// alphas need to be ~0.05–0.10 with low RGB values so the result reads
	// as a dim galactic glow, not a washed-out blue sky.
	const nebulaColors = [
		[14, 22, 42, 0.10],    // cool blue
		[22, 12, 32, 0.09],    // violet
		[10, 26, 32, 0.08],    // teal
		[32, 16, 26, 0.07],    // dusty magenta
		[12, 18, 36, 0.09],    // deep blue
	];
	for (let i = 0; i < 8; i++) {
		const x = Math.random() * 2048;
		const y = 380 + Math.random() * 280;
		const r = 280 + Math.random() * 420;
		const [nr, ng, nb, na] = nebulaColors[i % nebulaColors.length];
		const grad = bgctx.createRadialGradient(x, y, 0, x, y, r);
		grad.addColorStop(0, `rgba(${nr}, ${ng}, ${nb}, ${na})`);
		grad.addColorStop(0.5, `rgba(${nr}, ${ng}, ${nb}, ${na * 0.3})`);
		grad.addColorStop(1, `rgba(${nr}, ${ng}, ${nb}, 0)`);
		bgctx.fillStyle = grad;
		bgctx.fillRect(0, 0, 2048, 1024);
	}
	// Dust-lane dark streaks across the galactic plane (subtractive look —
	// emulated by drawing slightly darker low-opacity bands)
	bgctx.globalCompositeOperation = "source-over";
	for (let i = 0; i < 5; i++) {
		const y = 460 + (i - 2) * 18;
		bgctx.fillStyle = `rgba(2, 2, 6, ${0.12 + Math.random() * 0.08})`;
		bgctx.fillRect(0, y, 2048, 6);
	}
	// Star sparkle — varying brightness + color tint so it doesn't read as
	// uniform white pepper
	for (let i = 0; i < 1800; i++) {
		const x = Math.random() * 2048;
		const y = Math.random() * 1024;
		const brightness = Math.random();
		const size = brightness > 0.95 ? 2.0 : brightness > 0.7 ? 1.2 : 0.8;
		const tint = Math.random();
		let r = 255, g = 255, b = 255;
		if (tint > 0.85) { r = 200; g = 220; b = 255; }       // blue star
		else if (tint > 0.75) { r = 255; g = 230; b = 200; }  // warm star
		bgctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${0.4 + brightness * 0.6})`;
		bgctx.fillRect(x, y, size, size);
	}
	const bgTex = new THREE.CanvasTexture(bgCanvas);
	bgTex.mapping = THREE.EquirectangularReflectionMapping;
	bgTex.colorSpace = THREE.SRGBColorSpace;
	scene.background = bgTex;
	scene.fog = null;

	// Soft key light so the ship isn't pitch black
	const keyLight = new THREE.DirectionalLight(0xdde8ff, 1.55);
	keyLight.position.set(-20, 12, -8);
	scene.add(keyLight);
	const rimLight = new THREE.DirectionalLight(0x9fd6ff, 1.35);
	rimLight.position.set(24, 8, 22);
	scene.add(rimLight);
	const ambient = new THREE.AmbientLight(0x1b2630, 0.65);
	scene.add(ambient);

	// Distant sun — radial-gradient sprite billboard so the sun reads as a
	// glaring pinpoint with smooth falloff rather than a flat sphere disc.
	// CanvasTexture with a multi-stop radial gradient: pure-white core,
	// warm-cream mid, transparent edges — additively blended.
	const sunCanvas = document.createElement("canvas");
	sunCanvas.width = 256;
	sunCanvas.height = 256;
	const sctx = sunCanvas.getContext("2d")!;
	const sgrad = sctx.createRadialGradient(128, 128, 0, 128, 128, 128);
	sgrad.addColorStop(0.0, "rgba(255, 255, 255, 1.0)");
	sgrad.addColorStop(0.05, "rgba(255, 252, 240, 0.95)");
	sgrad.addColorStop(0.18, "rgba(255, 230, 180, 0.55)");
	sgrad.addColorStop(0.45, "rgba(255, 200, 130, 0.18)");
	sgrad.addColorStop(0.75, "rgba(220, 160, 100, 0.05)");
	sgrad.addColorStop(1.0, "rgba(180, 120, 80, 0)");
	sctx.fillStyle = sgrad;
	sctx.fillRect(0, 0, 256, 256);
	const sunTex = new THREE.CanvasTexture(sunCanvas);
	sunTex.colorSpace = THREE.SRGBColorSpace;
	const sunSprite = new THREE.Sprite(
		new THREE.SpriteMaterial({
			map: sunTex,
			color: 0xffffff,
			transparent: true,
			blending: THREE.AdditiveBlending,
			depthWrite: false,
			fog: false,
			toneMapped: false,
		}),
	);
	// Position chosen so the sprite lands in the upper-right of the
	// hero-shot frame (camera at (-25,6,35) looking at origin).
	sunSprite.position.set(60, 22, -5);
	// Sprite scale ~ visual diameter in world units. Slightly larger than
	// the previous corona radius so the soft falloff has room to fade.
	sunSprite.scale.set(8, 8, 1);
	scene.add(sunSprite);

	// Outer bloom — larger, dimmer sprite layered on top to extend the
	// soft halo into the surrounding void. Two-sprite corona gives a
	// readable hot core with a wide bleed without making the core too big.
	const sunBloomCanvas = document.createElement("canvas");
	sunBloomCanvas.width = sunBloomCanvas.height = 256;
	const sbCtx = sunBloomCanvas.getContext("2d");
	if (sbCtx) {
		const sbg = sbCtx.createRadialGradient(128, 128, 0, 128, 128, 128);
		sbg.addColorStop(0.00, "rgba(255, 250, 230, 0.45)");
		sbg.addColorStop(0.25, "rgba(255, 220, 170, 0.22)");
		sbg.addColorStop(0.55, "rgba(220, 170, 120, 0.08)");
		sbg.addColorStop(1.00, "rgba(180, 120, 80, 0)");
		sbCtx.fillStyle = sbg;
		sbCtx.fillRect(0, 0, 256, 256);
	}
	const sunBloomTex = new THREE.CanvasTexture(sunBloomCanvas);
	sunBloomTex.colorSpace = THREE.SRGBColorSpace;
	const sunBloomSprite = new THREE.Sprite(
		new THREE.SpriteMaterial({
			map: sunBloomTex,
			color: 0xffffff,
			transparent: true,
			blending: THREE.AdditiveBlending,
			depthWrite: false,
			fog: false,
			toneMapped: false,
		}),
	);
	sunBloomSprite.position.copy(sunSprite.position);
	sunBloomSprite.scale.set(28, 28, 1);
	scene.add(sunBloomSprite);

	// Distant planet — slate-grey body in the lower-mid frame for scale.
	// CanvasTexture adds subtle surface variation (continent/cloud blobs +
	// crater speckle) so the sphere doesn't read as a flat painted ball.
	// Lit by the sun direction (matches keyLight orientation) so the
	// terminator line points sun-ward.
	const planetCanvas = document.createElement("canvas");
	planetCanvas.width = 512;
	planetCanvas.height = 256;
	const pctx = planetCanvas.getContext("2d")!;
	pctx.fillStyle = "#4a4a52";
	pctx.fillRect(0, 0, 512, 256);
	// Continent-style darker blobs
	for (let i = 0; i < 24; i++) {
		const x = Math.random() * 512;
		const y = Math.random() * 256;
		const r = 20 + Math.random() * 40;
		const g = pctx.createRadialGradient(x, y, 0, x, y, r);
		const shade = 0.15 + Math.random() * 0.25;
		g.addColorStop(0, `rgba(40, 42, 54, ${shade})`);
		g.addColorStop(1, "rgba(40, 42, 54, 0)");
		pctx.fillStyle = g;
		pctx.beginPath();
		pctx.arc(x, y, r, 0, Math.PI * 2);
		pctx.fill();
	}
	// Lighter highland blobs
	for (let i = 0; i < 18; i++) {
		const x = Math.random() * 512;
		const y = Math.random() * 256;
		const r = 12 + Math.random() * 25;
		const g = pctx.createRadialGradient(x, y, 0, x, y, r);
		g.addColorStop(0, `rgba(100, 105, 120, ${0.1 + Math.random() * 0.15})`);
		g.addColorStop(1, "rgba(100, 105, 120, 0)");
		pctx.fillStyle = g;
		pctx.beginPath();
		pctx.arc(x, y, r, 0, Math.PI * 2);
		pctx.fill();
	}
	// Crater speckle
	for (let i = 0; i < 200; i++) {
		const x = Math.random() * 512;
		const y = Math.random() * 256;
		pctx.fillStyle = `rgba(20, 22, 30, ${0.15 + Math.random() * 0.25})`;
		pctx.beginPath();
		pctx.arc(x, y, Math.random() * 1.5 + 0.4, 0, Math.PI * 2);
		pctx.fill();
	}
	const planetTex = new THREE.CanvasTexture(planetCanvas);
	planetTex.colorSpace = THREE.SRGBColorSpace;
	const planet = new THREE.Mesh(
		new THREE.SphereGeometry(5, 32, 32),
		new THREE.MeshStandardMaterial({
			map: planetTex,
			color: 0xffffff,
			roughness: 1.0,
			metalness: 0.0,
			emissive: 0x06070a,
			emissiveIntensity: 0.4,
		}),
	);
	// Position to lower-left of frame, well clear of the ship silhouette so it
	// reads as a distant world rather than something the ship is parked on.
	// Position to lower-left as a distant body for scale. Pulled away from
	// the frame edge so it reads as a sphere, not a cropped half-circle.
	planet.position.set(-22, -10, -38);
	scene.add(planet);

	// Camera framed on the ship's center, slightly offset so we see 3/4 view
	camera.fov = 42;
	camera.near = 0.5;
	camera.far = 800;
	camera.updateProjectionMatrix();

	const stars = buildStarField(scene);
	const starsBaseSize = (stars.material as THREE.PointsMaterial).size;
	// Try the high-quality GLB first; fall back to the procedural wedge if
	// it fails to load (offline, asset moved, etc.).
	const destiny = (await loadDestinyModel(scene)) ?? buildDestiny(scene);
	const credits = createCreditOverlay();
	const skipHint = createSkipHint();
	const tunnelOverlay = createTunnelOverlay();

	// Play the SGU theme, forced to LOOP so it spans the full 60-second
	// cinematic (the track file itself is ~45s, so it'd run out mid-
	// gate-room arrival without loop:true). It starts here and
	// intentionally keeps playing through the scene transition into
	// gate-room; the arrival cinematic inherits this audio and stops
	// it only when the cinematic ends.
	const audio = AudioManager.getInstance();
	void audio.play("sgu-theme-song", undefined, { loop: true, volume: 0.8 });

	// ?cinstep=N — jump to elapsed = N seconds for testing. Clamped to
	// [0, TOTAL_DURATION - 0.1] so a skip value of 20 doesn't immediately
	// tear the scene down before you can see anything.
	const cinStepRaw = new URLSearchParams(window.location.search).get("cinstep");
	const cinStep = cinStepRaw !== null ? Number.parseFloat(cinStepRaw) : NaN;
	const frozen = new URLSearchParams(window.location.search).has("cinfreeze");
	let elapsed = Number.isFinite(cinStep)
		? Math.max(0, Math.min(TOTAL_DURATION - 0.1, cinStep))
		: 0;
	let disposed = false;
	let finished = false;

	// Hold-SPACE skip via direct keyboard listener. The engine's
	// InputManager is a Vite-aliased no-op stub, so isAction() never fires
	// at runtime. We track Space-held state manually here.
	const SKIP_HOLD_MS = 1500;
	let spaceHeld = false;
	let skipHoldStart: number | null = null;
	let skipTriggered = false;
	const onSkipKeyDown = (event: KeyboardEvent) => {
		if (event.code === "Space") spaceHeld = true;
	};
	const onSkipKeyUp = (event: KeyboardEvent) => {
		if (event.code === "Space") spaceHeld = false;
	};
	window.addEventListener("keydown", onSkipKeyDown);
	window.addEventListener("keyup", onSkipKeyUp);

	// Ship stationary at origin — camera orbits around it.
	destiny.root.position.set(0, 0, 0);
	destiny.root.rotation.y = 0;           // nose pointing −Z (ship forward)
	const destinyFocus = new THREE.Vector3(0, 0.55, -2.3);

	const finish = (): void => {
		if (finished) return;
		finished = true;
		// Signal gate-room to boot in arrival-cinematic mode
		sessionStorage.setItem("sgu-new-game", "1");
		void gotoScene("gate-room");
	};

	// ── Camera flight plan (parametric orbit) ─────────────────────────────
	//
	// Phase 1 (0-3s):    Pull-back reveal. Camera starts close on aft hull,
	//                     rapidly backs out so starfield dominates frame.
	// Phase 2 (3-12s):   Orbit counterclockwise from rear-quarter → side →
	//                     full front view (nose-on). Fixed distance ~30.
	// Phase 3 (12-17s):  Push-in toward the nose cone from front view.
	// Phase 4 (17-21s):  WARP TUNNEL. Star-field stretches into streaks, a
	//                     circular vignette closes on the prow — the camera
	//                     dives THROUGH the ship's silhouette toward black.
	// Phase 5 (21-24s):  Smash to black. Hand off to gate-room (which boots
	//                     in arrival-cinematic mode and opens on the dormant
	//                     gate — concept-art/gate-room/gate-room-dormant.png).

	const smooth = (t: number) => t * t * (3 - 2 * t); // hermite smoothstep

	// Capture/test hook — opening cinematic is fully mounted (Destiny, stars, beats).
	(window as unknown as { __sceneReady?: boolean }).__sceneReady = true;

	return {
		update(delta: number): void {
			if (disposed) return;
			const step = frozen ? 0 : delta;
			elapsed += step;

			// Hold-SPACE skip with progress bar
			if (!skipTriggered) {
				if (spaceHeld && skipHoldStart === null) {
					skipHoldStart = performance.now();
				} else if (!spaceHeld && skipHoldStart !== null) {
					skipHoldStart = null;
					skipHint.setProgress(0);
				}
				if (skipHoldStart !== null) {
					const heldFor = performance.now() - skipHoldStart;
					skipHint.setProgress(Math.min(1, heldFor / SKIP_HOLD_MS));
					if (heldFor >= SKIP_HOLD_MS) {
						skipTriggered = true;
						finish();
					}
				}
			}

			// Star drift (additional warp acceleration applied below)
			stars.rotation.x  = Math.sin(elapsed * 0.03) * 0.02;

			// Gentle ship roll / drift
			destiny.root.rotation.z = Math.sin(elapsed * 0.12) * 0.015;
			destiny.root.rotation.x = Math.sin(elapsed * 0.08 + 1) * 0.01;

			// ── Camera orbit ─────────────────────────────────────────────
			let camR: number;
			let camTheta: number;
			let camY: number;

			if (elapsed < 3) {
				const t = elapsed / 3;
				camR = 10 + smooth(t) * 44;
				camTheta = Math.PI * 0.86;
				camY = 1.5 + smooth(t) * 4.2;
			} else if (elapsed < 12) {
				const t = (elapsed - 3) / 9;
				camR = 40 + Math.sin(t * Math.PI) * 6;
				camTheta = Math.PI * 0.86 * (1 - smooth(t));
				camY = 5.6 - smooth(t) * 2.6;
			} else if (elapsed < TUNNEL_START) {
				const t = (elapsed - 12) / (TUNNEL_START - 12);
				camR = 38 - smooth(t) * 17;
				camTheta = 0;
				camY = 3 - smooth(t) * 1.2;
			} else if (elapsed < TUNNEL_END) {
				// Warp / FTL drop — accelerate through the prow toward black.
				const t = (elapsed - TUNNEL_START) / (TUNNEL_END - TUNNEL_START);
				camR = 21 - smooth(t) * 22;          // closes through the ship
				camTheta = 0;
				camY = 1.8 - smooth(t) * 1.4;
			} else {
				camR = -1.2;                           // past the prow — black
				camTheta = 0;
				camY = 0.4;
			}

			// ── Warp / tunnel effect ─────────────────────────────────────
			const tunnelPhase = elapsed < TUNNEL_START
				? 0
				: elapsed < TUNNEL_END
					? smooth((elapsed - TUNNEL_START) / (TUNNEL_END - TUNNEL_START))
					: 1;
			tunnelOverlay.setProgress(tunnelPhase);
			// Stretch & accelerate the star-field during warp. PointsMaterial
			// can't draw lines, so we cheat: balloon the point size and ramp
			// rotation to give a streak-out impression that smash-cuts to black.
			(stars.material as THREE.PointsMaterial).size = starsBaseSize * (1 + tunnelPhase * 6);
			stars.rotation.y += step * (0.008 + tunnelPhase * 1.4);

			camera.position.set(
				camR * Math.sin(camTheta),
				camY,
				-camR * Math.cos(camTheta),
			);
			camera.lookAt(destinyFocus);

			const activeBeat = BEATS.find((b) => elapsed >= b.start && elapsed < b.end) ?? null;
			credits.setBeat(activeBeat);

			if (elapsed >= TOTAL_DURATION) {
				finish();
			}
		},

		dispose(): void {
			disposed = true;
			window.removeEventListener("keydown", onSkipKeyDown);
			window.removeEventListener("keyup", onSkipKeyUp);
			// DO NOT stop sgu-theme-song here — the gate-room arrival
			// cinematic is the continuation of the same 60-second musical
			// beat. Music is stopped when the gate-room cinematic ends
			// (see cinematic-controller's dispose).
			credits.dispose();
			skipHint.dispose();
			tunnelOverlay.dispose();
			scene.remove(keyLight);
			scene.remove(rimLight);
			scene.remove(ambient);
			scene.remove(stars);
			stars.geometry.dispose();
			(stars.material as THREE.PointsMaterial).dispose();
			disposeDestiny(scene, destiny);
		},
	};
}

// ─── Scene definition ─────────────────────────────────────────────────────────

export const openingCinematicScene = defineGameScene({
	id: "opening-cinematic",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((m) => m.default),
	}),
	title: "Opening Cinematic",
	player: false,
	hud: false,
	mount,
});
