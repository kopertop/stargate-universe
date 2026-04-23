/**
 * VRM Character Manager — orchestrates VRM character loading, LOD, spring
 * bones, expressions, and per-frame updates for all active characters.
 *
 * This is the top-level system that the game shell and player controller
 * interact with. It manages both the player VRM and crew NPC VRMs.
 *
 * @see design/gdd/vrm-model-integration.md
 */
import type { VRM } from "@pixiv/three-vrm";
import {
	CapsuleGeometry,
	Group,
	Layers,
	Mesh,
	MeshStandardMaterial,
	PerspectiveCamera,
	Vector3,
} from "three";

import { resolveAssetUrl } from "../asset-resolver";
import { emit } from "../event-bus";
import { getVrmConfig, type VrmConfig } from "./vrm-config";
import { VrmExpressionController } from "./vrm-expression-controller";
import { VrmLookAtController } from "./vrm-lookat-controller";
import { applyCustomization } from "./vrm-customizer";
import { loadCustomization } from "./vrm-customization-persistence";
import { loadVrm, type VrmLoadResult } from "./vrm-loader";
import { convertMToonToPBR, flattenVrmMaterials } from "./vrm-mtoon-converter";

// ─── Types ──────────────────────────────────────────────────────────────────

export type LodTier = "near" | "mid" | "far";

export type VrmCharacterOptions = {
	/** Unique character ID (e.g., "eli-wallace", "nicholas-rush"). */
	readonly id: string;
	/** Path to the `.vrm` file. */
	readonly vrmUrl: string;
	/** Whether this is the player character. */
	readonly isPlayer?: boolean;
	/** Loading priority (0 = highest, player default). */
	readonly priority?: number;
};

export type VrmCharacterInstance = {
	readonly id: string;
	readonly vrmUrl: string;
	readonly isPlayer: boolean;
	readonly root: Group;
	vrm: VRM | undefined;
	expressionController: VrmExpressionController | undefined;
	lookAtController: VrmLookAtController | undefined;
	lodTier: LodTier;
	springBonesActive: boolean;
	firstPersonSetup: boolean;
	loading: boolean;
	failed: boolean;
	/** Capsule fallback mesh, shown until VRM loads (or on failure). */
	readonly fallbackMesh: Mesh;
};

// ─── Manager ────────────────────────────────────────────────────────────────

const characters = new Map<string, VrmCharacterInstance>();
const scratchPos = new Vector3();
const scratchCharPos = new Vector3();

/** The camera used for LOD distance calculations. */
let activeCamera: PerspectiveCamera | undefined;

/** Whether adaptive quality is currently active (low FPS detected). */
let adaptiveQualityActive = false;

/** Current first-person mode state and transition progress. */
let firstPersonState = {
	isFirstPerson: false,
	transitionProgress: 0, // 0 = third-person, 1 = first-person
};

/**
 * Set the camera used for LOD distance calculations.
 * Must be called before `update()` to enable LOD.
 */
/**
 * Sets the active camera for the VRM character system.
 * @param camera The perspective camera to use as the active view.
 */
export function setActiveCamera(camera: PerspectiveCamera): void {
	activeCamera = camera;
}

/**
 * Register and begin loading a VRM character.
 * Returns the character's root Group immediately (may show fallback capsule
 * until the VRM finishes loading).
 */
/**
 * Adds a new VRM character instance to the manager.
 * @param options Character configuration including model URL and initial state.
 * @returns The created VRM character instance.
 */
export function addCharacter(options: VrmCharacterOptions): VrmCharacterInstance {
	const existing = characters.get(options.id);

	if (existing) {
		return existing;
	}

	const root = new Group();
	root.name = `vrm-character-${options.id}`;

	const fallbackMesh = createFallbackCapsule();
	root.add(fallbackMesh);

	const instance: VrmCharacterInstance = {
		id: options.id,
		vrmUrl: options.vrmUrl,
		isPlayer: options.isPlayer ?? false,
		root,
		vrm: undefined,
		expressionController: undefined,
		lookAtController: undefined,
		lodTier: "near",
		springBonesActive: true,
		firstPersonSetup: false,
		loading: true,
		failed: false,
		fallbackMesh,
	};

	characters.set(options.id, instance);

	// Begin async load — resolve asset URL through R2 in production
	loadVrm(resolveAssetUrl(options.vrmUrl), options.priority ?? (options.isPlayer ? 0 : 1))
		.then((result) => onVrmLoaded(instance, result))
		.catch((error) => onVrmFailed(instance, error));

	return instance;
}

/**
 * Remove a character and dispose its VRM resources.
 */
/**
 * Removes a VRM character instance by its ID and cleans up associated resources.
 * @param id The unique identifier of the character to remove.
 */
export function removeCharacter(id: string): void {
	const instance = characters.get(id);

	if (!instance) return;

	if (instance.vrm) {
		instance.root.remove(instance.vrm.scene);
	}

	instance.root.remove(instance.fallbackMesh);
	disposeFallbackCapsule(instance.fallbackMesh);
	characters.delete(id);
}

/**
 * Get a character instance by ID.
 */
/**
 * Retrieves a VRM character instance by its ID.
 * @param id The unique identifier of the character.
 * @returns The character instance if found, otherwise undefined.
 */
export function getCharacter(id: string): VrmCharacterInstance | undefined {
	return characters.get(id);
}

/**
 * Get all active character instances.
 */
export function getAllCharacters(): ReadonlyMap<string, VrmCharacterInstance> {
	return characters;
}

/**
 * Update all VRM characters: LOD evaluation, spring bones, expressions.
 * Call once per frame from the game loop.
 *
 * @param delta Frame delta in seconds
 * @param fps   Current FPS (for adaptive quality)
 */
export function update(delta: number, fps: number): void {
	const config = getVrmConfig();

	// Adaptive quality check
	adaptiveQualityActive = fps > 0 && fps < config.quality.adaptiveThresholdFps;

	// Smooth first-person head fade transition
	updateFirstPersonFade(delta);

	for (const [, instance] of characters) {
		if (!instance.vrm) continue;

		updateLod(instance, config);
		updateSpringBones(instance, delta, config);
		updateExpressions(instance, delta);
		updateLookAt(instance, delta);
		updateVrm(instance, delta);
	}
}

/**
 * Set first-person mode on the player character.
 * Uses VRM first-person layers with a smooth opacity transition on the head
 * mesh to avoid visual jarring when switching camera modes.
 *
 * @param isFirstPerson Whether the camera is in FPS mode
 * @param camera        The active camera to configure layers on
 */
export function setFirstPersonMode(isFirstPerson: boolean, camera: PerspectiveCamera): void {
	firstPersonState.isFirstPerson = isFirstPerson;

	for (const [, instance] of characters) {
		if (!instance.isPlayer || !instance.vrm) continue;

		// Set up first-person layers if not done yet
		if (!instance.firstPersonSetup && instance.vrm.firstPerson) {
			instance.vrm.firstPerson.setup();
			instance.firstPersonSetup = true;
		}

		if (!instance.vrm.firstPerson) continue;

		const fpLayer = instance.vrm.firstPerson.firstPersonOnlyLayer;
		const tpLayer = instance.vrm.firstPerson.thirdPersonOnlyLayer;

		if (isFirstPerson) {
			camera.layers.enable(fpLayer);
			camera.layers.disable(tpLayer);
		} else {
			camera.layers.disable(fpLayer);
			camera.layers.enable(tpLayer);
		}
	}
}

/**
 * Update the first-person head fade transition. Called from the main update loop.
 * Smoothly transitions head mesh opacity over the configured fade duration.
 */
function updateFirstPersonFade(delta: number): void {
	const config = getVrmConfig();
	const fadeSpeed = 1.0 / Math.max(0.01, config.firstPerson.headFadeTransition);
	const target = firstPersonState.isFirstPerson ? 1 : 0;

	if (Math.abs(firstPersonState.transitionProgress - target) < 0.001) {
		firstPersonState.transitionProgress = target;
		return;
	}

	// Move toward target
	if (target > firstPersonState.transitionProgress) {
		firstPersonState.transitionProgress = Math.min(
			target,
			firstPersonState.transitionProgress + delta * fadeSpeed
		);
	} else {
		firstPersonState.transitionProgress = Math.max(
			target,
			firstPersonState.transitionProgress - delta * fadeSpeed
		);
	}

	// Apply opacity to third-person-only head meshes on the player
	for (const [, instance] of characters) {
		if (!instance.isPlayer || !instance.vrm?.firstPerson) continue;

		const tpLayer = instance.vrm.firstPerson.thirdPersonOnlyLayer;
		const headOpacity = 1 - firstPersonState.transitionProgress;
		const testLayers = new Layers();
		testLayers.set(tpLayer);

		instance.vrm.scene.traverse((child) => {
			const mesh = child as Mesh;
			if (!mesh.isMesh) return;

			// Only affect meshes on the third-person-only layer (head/hair/face)
			if (mesh.layers.test(testLayers)) {
				const mat = mesh.material as MeshStandardMaterial;
				if (mat.isMeshStandardMaterial) {
					mat.transparent = headOpacity < 1;
					mat.opacity = headOpacity;
				}
			}
		});
	}
}

/**
 * Spawn crew NPCs from manifest entries. Convenience wrapper around `addCharacter`.
 * Returns all spawned instances (skips already-loaded characters).
 */
export function spawnCrew(
	manifests: readonly import("./vrm-crew-manifest").CrewCharacterManifest[]
): VrmCharacterInstance[] {
	const spawned: VrmCharacterInstance[] = [];

	for (const manifest of manifests) {
		if (manifest.isPlayer) continue; // Player is handled separately

		const instance = addCharacter({
			id: manifest.id,
			vrmUrl: manifest.vrmAsset,
			isPlayer: false,
			priority: 1,
		});

		// Apply expression profile defaults
		if (instance.expressionController && manifest.expressionProfile?.defaultExpression) {
			instance.expressionController.setExpression(
				manifest.expressionProfile.defaultExpression,
				manifest.expressionProfile.expressionIntensity ?? 0.7
			);
		}

		spawned.push(instance);
	}

	return spawned;
}

/**
 * Dispose all characters and reset state.
 */
export function dispose(): void {
	for (const [id] of characters) {
		removeCharacter(id);
	}

	characters.clear();
	activeCamera = undefined;
	adaptiveQualityActive = false;
}

// ─── Internal: Load Handlers ────────────────────────────────────────────────

function onVrmLoaded(instance: VrmCharacterInstance, result: VrmLoadResult): void {
	instance.vrm = result.vrm;
	instance.loading = false;

	// Convert MToon materials to PBR for WebGPU consistency
	const mutableMaterials = result.vrm.materials
		? [...result.vrm.materials]
		: undefined;
	convertMToonToPBR(result.vrm.scene, mutableMaterials);

	// Ensure all materials are matte/non-metallic for the game's aesthetic
	flattenVrmMaterials(result.vrm.scene);

	// Enable shadows on all meshes
	result.vrm.scene.traverse((child) => {
		if ((child as Mesh).isMesh) {
			child.castShadow = true;
			child.receiveShadow = true;
		}
	});

	// Initialize controllers
	instance.expressionController = new VrmExpressionController(result.vrm);
	instance.lookAtController = new VrmLookAtController(result.vrm);

	// Add VRM scene to the character root
	instance.root.add(result.vrm.scene);

	// Hide fallback capsule
	instance.fallbackMesh.visible = false;

	// Emit load event
	emit("character:model:loaded", { characterId: instance.id });

	console.info(`[VrmCharacterManager] Loaded VRM for "${instance.id}" from ${result.url}`);

	// Auto-apply saved customization (async, non-blocking)
	loadCustomization(instance.id).then((customization) => {
		if (customization && instance.vrm) {
			applyCustomization(instance.id, instance.vrm, customization).catch((err) => {
				console.error(`[VrmCharacterManager] Failed to apply customization for "${instance.id}"`, err);
			});
		}
	}).catch(() => {
		// Customization load failed — not critical, character still renders
	});
}

function onVrmFailed(instance: VrmCharacterInstance, error: unknown): void {
	instance.loading = false;
	instance.failed = true;

	// Keep fallback capsule visible
	instance.fallbackMesh.visible = true;

	console.error(
		`[VrmCharacterManager] Failed to load VRM for "${instance.id}". ` +
		`Falling back to capsule.`,
		error
	);
}

// ─── Internal: Per-Frame Updates ────────────────────────────────────────────

function updateLod(instance: VrmCharacterInstance, config: VrmConfig): void {
	if (!activeCamera) {
		instance.lodTier = "near";
		return;
	}

	activeCamera.getWorldPosition(scratchPos);
	instance.root.getWorldPosition(scratchCharPos);
	const distance = scratchPos.distanceTo(scratchCharPos);

	const lodConfig = config.lod;

	if (distance < lodConfig.nearDistance) {
		instance.lodTier = "near";
	} else if (distance < lodConfig.midDistance) {
		instance.lodTier = "mid";
	} else {
		instance.lodTier = "far";
	}

	// Player always stays at near LOD (camera is on them)
	if (instance.isPlayer) {
		instance.lodTier = "near";
	}

	// Adaptive quality override
	if (adaptiveQualityActive && !instance.isPlayer) {
		if (instance.lodTier === "near") {
			instance.lodTier = "mid";
		}
	}
}

function updateSpringBones(instance: VrmCharacterInstance, _delta: number, config: VrmConfig): void {
	const shouldBeActive =
		config.springBone.enabled &&
		instance.lodTier === "near" &&
		!adaptiveQualityActive;

	instance.springBonesActive = shouldBeActive;
}

function updateExpressions(instance: VrmCharacterInstance, delta: number): void {
	if (!instance.expressionController) return;

	const isActive = instance.lodTier === "near";
	instance.expressionController.setEnabled(isActive);

	if (isActive) {
		instance.expressionController.update(delta);
	}
}

function updateLookAt(instance: VrmCharacterInstance, delta: number): void {
	if (!instance.lookAtController) return;

	const isActive = instance.lodTier === "near";
	instance.lookAtController.setEnabled(isActive);

	if (isActive) {
		instance.lookAtController.update(delta, activeCamera);
	}
}

function updateVrm(instance: VrmCharacterInstance, delta: number): void {
	if (!instance.vrm) return;

	const config = getVrmConfig();

	// Clamp delta for spring bone stability (prevents explosion after alt-tab)
	const clampedDelta = Math.min(delta, config.springBone.maxDeltaSeconds);

	// VRM.update() steps spring bones, constraints, materials, and expressions
	// If spring bones should be frozen, we skip the update (they hold position)
	if (instance.springBonesActive) {
		instance.vrm.update(clampedDelta);
	} else {
		// Update expressions and materials only (skip spring bones)
		instance.vrm.expressionManager?.update();
	}
}

// ─── Internal: Fallback Capsule ─────────────────────────────────────────────

function createFallbackCapsule(): Mesh {
	const mesh = new Mesh(
		new CapsuleGeometry(0.3, 1.0, 4, 12),
		new MeshStandardMaterial({
			color: "#7dd3fc",
			emissive: "#0f4c81",
			emissiveIntensity: 0.12,
			roughness: 0.62,
		})
	);

	mesh.castShadow = true;
	mesh.receiveShadow = true;
	mesh.name = "vrm-fallback-capsule";
	return mesh;
}

function disposeFallbackCapsule(mesh: Mesh): void {
	mesh.geometry.dispose();
	(mesh.material as MeshStandardMaterial).dispose();
}
