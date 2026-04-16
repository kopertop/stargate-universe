/**
 * VRM Character Manager — class-based, per-scene lifecycle.
 *
 * Manages VRM character loading, LOD evaluation, spring bones, expressions,
 * and per-frame updates for all active characters in a scene. Instantiated
 * once per scene and disposed on scene transition.
 *
 * Refactored from the module-singleton pattern in the VRM branch to integrate
 * with ggez's GameSceneLifecycle.
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

import { getVrmConfig, type VrmConfig } from "./vrm-config";
import { VrmExpressionController } from "./vrm-expression-controller";
import { VrmLookAtController } from "./vrm-lookat-controller";
import { loadVrm, type VrmLoadResult } from "./vrm-asset-loader";
import { convertMToonToPBR } from "./vrm-mtoon-converter";

// ─── Types ──────────────────────────────────────────────────────────────────

export type LodTier = "near" | "mid" | "far";

export type VrmCharacterOptions = {
	readonly id: string;
	readonly vrmUrl: string;
	readonly isPlayer?: boolean;
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
	readonly fallbackMesh: Mesh;
};

// ─── Manager ────────────────────────────────────────────────────────────────

export class VrmCharacterManager {
	private readonly characters = new Map<string, VrmCharacterInstance>();
	private readonly camera: PerspectiveCamera;
	private adaptiveQualityActive = false;

	private readonly firstPersonState = {
		isFirstPerson: false,
		transitionProgress: 0,
	};

	private readonly scratchPos = new Vector3();
	private readonly scratchCharPos = new Vector3();

	constructor(camera: PerspectiveCamera) {
		this.camera = camera;
	}

	/** Register and begin loading a VRM character. Returns root Group immediately. */
	addCharacter(options: VrmCharacterOptions): VrmCharacterInstance {
		const existing = this.characters.get(options.id);

		if (existing) return existing;

		const root = new Group();
		root.name = `vrm-character-${options.id}`;

		const fallbackMesh = createFallbackCapsule();
		fallbackMesh.visible = false; // Hidden until load fails — prevents capsule flash
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

		this.characters.set(options.id, instance);

		loadVrm(options.vrmUrl, options.priority ?? (options.isPlayer ? 0 : 1))
			.then((result) => this.onVrmLoaded(instance, result))
			.catch((error) => this.onVrmFailed(instance, error));

		return instance;
	}

	/** Remove and dispose a character. */
	removeCharacter(id: string): void {
		const instance = this.characters.get(id);

		if (!instance) return;

		if (instance.vrm) {
			instance.root.remove(instance.vrm.scene);
		}

		instance.root.remove(instance.fallbackMesh);
		disposeFallbackCapsule(instance.fallbackMesh);
		this.characters.delete(id);
	}

	/** Get a character instance by ID. */
	getCharacter(id: string): VrmCharacterInstance | undefined {
		return this.characters.get(id);
	}

	/** Get all active character instances. */
	getAllCharacters(): ReadonlyMap<string, VrmCharacterInstance> {
		return this.characters;
	}

	/**
	 * Update all VRM characters: LOD, spring bones, expressions.
	 * Call once per frame from the game loop.
	 */
	update(delta: number, fps: number): void {
		const config = getVrmConfig();

		this.adaptiveQualityActive = fps > 0 && fps < config.quality.adaptiveThresholdFps;
		this.updateFirstPersonFade(delta);

		for (const [, instance] of this.characters) {
			if (!instance.vrm) continue;

			this.updateLod(instance, config);
			this.updateSpringBones(instance, delta, config);
			this.updateExpressions(instance, delta);
			this.updateLookAt(instance, delta);
			this.updateVrm(instance, delta, config);
		}
	}

	/** Toggle first-person mode on the player character. */
	setFirstPersonMode(isFirstPerson: boolean): void {
		this.firstPersonState.isFirstPerson = isFirstPerson;

		for (const [, instance] of this.characters) {
			if (!instance.isPlayer || !instance.vrm) continue;

			if (!instance.firstPersonSetup && instance.vrm.firstPerson) {
				instance.vrm.firstPerson.setup();
				instance.firstPersonSetup = true;
			}

			if (!instance.vrm.firstPerson) continue;

			const fpLayer = instance.vrm.firstPerson.firstPersonOnlyLayer;
			const tpLayer = instance.vrm.firstPerson.thirdPersonOnlyLayer;

			if (isFirstPerson) {
				this.camera.layers.enable(fpLayer);
				this.camera.layers.disable(tpLayer);
			} else {
				this.camera.layers.disable(fpLayer);
				this.camera.layers.enable(tpLayer);
			}
		}
	}

	/** Dispose all characters and reset state. */
	dispose(): void {
		for (const [id] of this.characters) {
			this.removeCharacter(id);
		}

		this.characters.clear();
		this.adaptiveQualityActive = false;
	}

	// ─── Internal: Load Handlers ────────────────────────────────────────────

	private onVrmLoaded(instance: VrmCharacterInstance, result: VrmLoadResult): void {
		instance.vrm = result.vrm;
		instance.loading = false;

		const mutableMaterials = result.vrm.materials ? [...result.vrm.materials] : undefined;
		convertMToonToPBR(result.vrm.scene, mutableMaterials);

		result.vrm.scene.traverse((child) => {
			if ((child as Mesh).isMesh) {
				child.castShadow = true;
				child.receiveShadow = true;
			}
		});

		instance.expressionController = new VrmExpressionController(result.vrm);
		instance.lookAtController = new VrmLookAtController(result.vrm);

		instance.root.add(result.vrm.scene);
		instance.fallbackMesh.visible = false;

		// Character loaded successfully.
	}

	private onVrmFailed(instance: VrmCharacterInstance, error: unknown): void {
		instance.loading = false;
		instance.failed = true;
		instance.fallbackMesh.visible = true;

		console.error(`[VrmCharacterManager] Failed "${instance.id}":`, error);
	}

	// ─── Internal: Per-Frame Updates ────────────────────────────────────────

	private updateLod(instance: VrmCharacterInstance, config: VrmConfig): void {
		this.camera.getWorldPosition(this.scratchPos);
		instance.root.getWorldPosition(this.scratchCharPos);
		const distance = this.scratchPos.distanceTo(this.scratchCharPos);

		if (instance.isPlayer) {
			instance.lodTier = "near";
		} else if (distance < config.lod.nearDistance) {
			instance.lodTier = "near";
		} else if (distance < config.lod.midDistance) {
			instance.lodTier = "mid";
		} else {
			instance.lodTier = "far";
		}

		if (this.adaptiveQualityActive && !instance.isPlayer && instance.lodTier === "near") {
			instance.lodTier = "mid";
		}
	}

	private updateSpringBones(instance: VrmCharacterInstance, _delta: number, config: VrmConfig): void {
		instance.springBonesActive =
			config.springBone.enabled &&
			instance.lodTier === "near" &&
			!this.adaptiveQualityActive;
	}

	private updateExpressions(instance: VrmCharacterInstance, delta: number): void {
		if (!instance.expressionController) return;

		const isActive = instance.lodTier === "near";
		instance.expressionController.setEnabled(isActive);

		if (isActive) {
			instance.expressionController.update(delta);
		}
	}

	private updateLookAt(instance: VrmCharacterInstance, delta: number): void {
		if (!instance.lookAtController) return;

		const isActive = instance.lodTier === "near";
		instance.lookAtController.setEnabled(isActive);

		if (isActive) {
			instance.lookAtController.update(delta, this.camera);
		}
	}

	private updateVrm(instance: VrmCharacterInstance, delta: number, config: VrmConfig): void {
		if (!instance.vrm) return;

		const clampedDelta = Math.min(delta, config.springBone.maxDeltaSeconds);

		if (instance.springBonesActive) {
			instance.vrm.update(clampedDelta);
		} else {
			instance.vrm.expressionManager?.update();
		}
	}

	private updateFirstPersonFade(delta: number): void {
		const config = getVrmConfig();
		const fadeSpeed = 1.0 / Math.max(0.01, config.firstPerson.headFadeTransition);
		const target = this.firstPersonState.isFirstPerson ? 1 : 0;

		if (Math.abs(this.firstPersonState.transitionProgress - target) < 0.001) {
			this.firstPersonState.transitionProgress = target;
			return;
		}

		if (target > this.firstPersonState.transitionProgress) {
			this.firstPersonState.transitionProgress = Math.min(
				target,
				this.firstPersonState.transitionProgress + delta * fadeSpeed,
			);
		} else {
			this.firstPersonState.transitionProgress = Math.max(
				target,
				this.firstPersonState.transitionProgress - delta * fadeSpeed,
			);
		}

		for (const [, instance] of this.characters) {
			if (!instance.isPlayer || !instance.vrm?.firstPerson) continue;

			const tpLayer = instance.vrm.firstPerson.thirdPersonOnlyLayer;
			const headOpacity = 1 - this.firstPersonState.transitionProgress;
			const testLayers = new Layers();
			testLayers.set(tpLayer);

			instance.vrm.scene.traverse((child) => {
				const mesh = child as Mesh;
				if (!mesh.isMesh) return;

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
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function createFallbackCapsule(): Mesh {
	const mesh = new Mesh(
		new CapsuleGeometry(0.3, 1.0, 4, 12),
		new MeshStandardMaterial({
			color: "#7dd3fc",
			emissive: "#0f4c81",
			emissiveIntensity: 0.12,
			roughness: 0.62,
		}),
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
