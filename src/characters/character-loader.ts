/**
 * Character Loader — unified entry point for loading VRM or GLB character models.
 *
 * Wraps the VRM system for `.vrm` files and falls back to plain GLTFLoader for
 * `.glb` / generic glTF. Returns a consistent `CharacterLoadResult` regardless
 * of the underlying format.
 *
 * Usage:
 *   const result = await loadVRMCharacter('/assets/characters/player.vrm');
 *   scene.add(result.root);
 *   // In game loop:
 *   result.update(delta);
 *   // On cleanup:
 *   result.dispose();
 *
 * Crew manifest shorthand:
 *   const result = await loadCrewMember('rush');
 *   // Reads /assets/characters/manifest.json, resolves path, and loads.
 */

import type { VRM } from "@pixiv/three-vrm";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "@pixiv/three-vrm";

// ─── Types ───────────────────────────────────────────────────────────────────

export type CharacterFormat = "vrm" | "glb";

export type CharacterLoadResult = {
	/** The root Group — add to scene or re-parent as needed. */
	readonly root: THREE.Group;
	/** VRM instance if loaded from a .vrm file, undefined for GLB. */
	readonly vrm: VRM | undefined;
	/** THREE.AnimationMixer pre-connected to root. */
	readonly mixer: THREE.AnimationMixer;
	/** Detected file format. */
	readonly format: CharacterFormat;
	/**
	 * Call once per frame with the elapsed time delta (seconds).
	 * For VRM: advances spring-bone physics + animation mixer.
	 * For GLB: advances animation mixer only.
	 */
	readonly update: (delta: number) => void;
	/** Dispose all GPU resources and remove root from its parent. */
	readonly dispose: () => void;
};

// ─── Shared GLTF loader (singleton) ──────────────────────────────────────────

let _sharedLoader: GLTFLoader | undefined;

const getSharedLoader = (): GLTFLoader => {
	if (!_sharedLoader) {
		_sharedLoader = new GLTFLoader();
		_sharedLoader.register((parser) => new VRMLoaderPlugin(parser));
	}
	return _sharedLoader;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Enable shadow casting on every Mesh in the loaded scene. */
const setupShadows = (root: THREE.Object3D): void => {
	root.traverse((obj) => {
		if ((obj as THREE.Mesh).isMesh) {
			obj.castShadow = true;
			obj.receiveShadow = false;
			// Disable frustum culling so skinned meshes don't vanish at screen edges
			obj.frustumCulled = false;
		}
	});
};

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Load a character model (`.vrm` or `.glb`) and return a unified handle.
 *
 * The returned `root` is NOT added to any scene automatically — the caller
 * controls placement and parenting (scene.add, player.object.add, etc.).
 *
 * @param path  Public URL path to the model file.
 */
export const loadVRMCharacter = async (
	path: string,
): Promise<CharacterLoadResult> => {
	const isVRM = path.toLowerCase().endsWith(".vrm");
	const loader = getSharedLoader();

	const gltf = await loader.loadAsync(path);

	const root = new THREE.Group();
	root.name = isVRM ? "vrm-character" : "glb-character";

	setupShadows(gltf.scene);
	root.add(gltf.scene);

	const mixer = new THREE.AnimationMixer(root);

	if (isVRM) {
		const vrm = gltf.userData["vrm"] as VRM | undefined;
		if (!vrm) {
			throw new Error(`[CharacterLoader] File parsed but no VRM data found: ${path}`);
		}

		// Optimise VRM scene graph. combineSkeletons supersedes the deprecated
		// removeUnnecessaryJoints and handles the joint pruning + skeleton
		// merge in a single pass.
		VRMUtils.removeUnnecessaryVertices(vrm.scene);
		VRMUtils.combineSkeletons(vrm.scene);

		// VRM models face -Z by default; rotate 180° so they face +Z (toward camera)
		vrm.scene.rotation.y = Math.PI;

		const update = (delta: number): void => {
			vrm.update(delta);
			mixer.update(delta);
		};

		const dispose = (): void => {
			mixer.stopAllAction();
			root.parent?.remove(root);
			VRMUtils.deepDispose(vrm.scene);
		};

		return { root, vrm, mixer, format: "vrm", update, dispose };
	} else {
		// GLB path — no VRM spring bones, just AnimationMixer
		const update = (delta: number): void => {
			mixer.update(delta);
		};

		const dispose = (): void => {
			mixer.stopAllAction();
			root.parent?.remove(root);
			gltf.scene.traverse((obj) => {
				const mesh = obj as THREE.Mesh;
				if (mesh.isMesh) {
					mesh.geometry?.dispose();
					if (Array.isArray(mesh.material)) {
						mesh.material.forEach((m) => m.dispose());
					} else {
						mesh.material?.dispose();
					}
				}
			});
		};

		// Auto-play any embedded animations (e.g. Mixamo retargeted GLBs)
		if (gltf.animations.length > 0) {
			const action = mixer.clipAction(gltf.animations[0]);
			action.play();
		}

		return { root, vrm: undefined, mixer, format: "glb", update, dispose };
	}
};

/**
 * Load an external animation GLB (e.g. Mixamo retargeted clip) and apply it
 * to an existing character mixer, replacing any currently playing actions.
 */
export const loadAnimationClip = async (
	animPath: string,
	mixer: THREE.AnimationMixer,
	loop = THREE.LoopRepeat,
): Promise<THREE.AnimationAction> => {
	const loader = getSharedLoader();
	const gltf = await loader.loadAsync(animPath);
	if (gltf.animations.length === 0) {
		throw new Error(`[CharacterLoader] No animations found in: ${animPath}`);
	}
	mixer.stopAllAction();
	const action = mixer.clipAction(gltf.animations[0]);
	action.setLoop(loop, Infinity);
	action.play();
	return action;
};

// ─── Crew Manifest ────────────────────────────────────────────────────────────

/**
 * A single entry from `/assets/characters/manifest.json`.
 * Short `id` fields (e.g. "rush", "eli") are the public API surface;
 * `path` is the asset-server-relative URL for the VRM file.
 */
export type CrewManifestEntry = {
	readonly id: string;
	readonly name: string;
	readonly path: string;
	readonly role: string;
	readonly gender: "male" | "female";
	readonly isPlayer?: boolean;
	readonly expressionIntensity?: number;
	readonly notes?: string;
};

type CrewManifestJSON = {
	readonly version: string;
	readonly crew: readonly CrewManifestEntry[];
};

/** Cached manifest — fetched once on first call to `loadCrewMember`. */
let _cachedManifest: CrewManifestJSON | undefined;
const MANIFEST_URL = "/assets/characters/manifest.json";

/**
 * Fetch (and cache) the crew manifest JSON.
 * Subsequent calls return the cached value without re-fetching.
 */
export const getCrewManifestJSON = async (): Promise<CrewManifestJSON> => {
	if (_cachedManifest) return _cachedManifest;

	const response = await fetch(MANIFEST_URL);
	if (!response.ok) {
		throw new Error(
			`[CharacterLoader] Failed to fetch crew manifest: ${response.status} ${response.statusText}`,
		);
	}

	_cachedManifest = (await response.json()) as CrewManifestJSON;
	return _cachedManifest;
};

/**
 * Look up a crew member's manifest entry by short ID (e.g. "rush", "eli").
 * Returns `undefined` if the ID is not found.
 */
export const getCrewEntry = async (
	id: string,
): Promise<CrewManifestEntry | undefined> => {
	const manifest = await getCrewManifestJSON();
	return manifest.crew.find((entry) => entry.id === id);
};

/**
 * Load a crew member by their short manifest ID (e.g. `"rush"`, `"young"`).
 *
 * Reads `/assets/characters/manifest.json`, resolves the character's VRM path,
 * and returns a `CharacterLoadResult` identical to `loadVRMCharacter`.
 *
 * @throws If the ID is not found in the manifest or the VRM fails to load.
 *
 * @example
 *   const rush = await loadCrewMember('rush');
 *   scene.add(rush.root);
 *   // game loop:
 *   rush.update(delta);
 */
export const loadCrewMember = async (id: string): Promise<CharacterLoadResult> => {
	const entry = await getCrewEntry(id);

	if (!entry) {
		const manifest = await getCrewManifestJSON();
		const knownIds = manifest.crew.map((e) => e.id).join(", ");
		throw new Error(
			`[CharacterLoader] Unknown crew member: "${id}". Known IDs: ${knownIds}`,
		);
	}

	return loadVRMCharacter(entry.path);
};
