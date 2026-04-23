/**
 * VRM Customizer — applies and removes character customizations at runtime.
 *
 * Handles material overrides, gear attachments, and mesh visibility changes
 * on loaded VRM character instances.
 *
 * @see src/systems/vrm/vrm-customization-types.ts
 */
import type { VRM, VRMHumanBoneName } from "@pixiv/three-vrm";
import {
	Color,
	Euler,
	Group,
	Mesh,
	MeshStandardMaterial,
	Object3D,
	TextureLoader,
	Vector3,
} from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

import { resolveAssetUrl } from "../asset-resolver";
import { emit } from "../event-bus";
import type {
	GearAttachment,
	MaterialOverride,
	MeshVisibilityOverride,
	VrmCustomization,
} from "./vrm-customization-types";

// ─── Types ─────────────────────────────────────────────────────────────────────

/** Snapshot of original material properties for reset. */
type MaterialSnapshot = {
	readonly color: string;
	readonly roughness: number;
	readonly metalness: number;
	readonly emissive: string;
	readonly emissiveIntensity: number;
};

/** Discovered mesh info for the editor UI. */
export type DiscoveredMesh = {
	readonly name: string;
	readonly visible: boolean;
	readonly vertexCount: number;
};

/** Discovered material info for the editor UI. */
export type DiscoveredMaterial = {
	readonly meshName: string;
	readonly materialName: string;
	readonly color: string;
	readonly roughness: number;
	readonly metalness: number;
	readonly emissive: string;
	readonly emissiveIntensity: number;
};

// ─── Internal State ────────────────────────────────────────────────────────────

/** Original material snapshots keyed by `meshName:materialName`. */
const materialSnapshots = new Map<string, Map<string, MaterialSnapshot>>();

/** Gear groups keyed by `characterId:slotId`. */
const gearGroups = new Map<string, Object3D>();

/** Shared loaders. */
const textureLoader = new TextureLoader();
const gltfLoader = new GLTFLoader();

// ─── Discovery ─────────────────────────────────────────────────────────────────

/**
 * Discover all named meshes in a VRM scene. Used by the editor UI to populate
 * the visibility tab.
 */
export function discoverMeshes(vrm: VRM): DiscoveredMesh[] {
	const meshes: DiscoveredMesh[] = [];

	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (!mesh.isMesh || !mesh.name) return;

		meshes.push({
			name: mesh.name,
			visible: mesh.visible,
			vertexCount: mesh.geometry?.attributes?.position?.count ?? 0,
		});
	});

	return meshes;
}

/**
 * Discover all materials on meshes in a VRM scene. Used by the editor UI
 * to populate the materials tab with current values.
 */
export function discoverMaterials(vrm: VRM): DiscoveredMaterial[] {
	const materials: DiscoveredMaterial[] = [];

	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (!mesh.isMesh || !mesh.name) return;

		const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
		for (const mat of mats) {
			const std = mat as MeshStandardMaterial;
			if (!std.isMeshStandardMaterial) continue;

			materials.push({
				meshName: mesh.name,
				materialName: std.name ?? mesh.name,
				color: `#${std.color.getHexString()}`,
				roughness: std.roughness,
				metalness: std.metalness,
				emissive: `#${std.emissive.getHexString()}`,
				emissiveIntensity: std.emissiveIntensity,
			});
		}
	});

	return materials;
}

// ─── Apply Customization ───────────────────────────────────────────────────────

/**
 * Apply a full customization to a loaded VRM instance.
 * Snapshots original material state on first call for clean reset.
 */
export async function applyCustomization(
	characterId: string,
	vrm: VRM,
	customization: VrmCustomization,
): Promise<void> {
	// Snapshot originals if not already done
	snapshotMaterials(characterId, vrm);

	// Apply each customization type
	for (const override of customization.materials) {
		applyMaterialOverride(vrm, override);
	}

	for (const override of customization.meshVisibility) {
		applyMeshVisibility(vrm, override);
	}

	// Gear attachments are async (GLB loading)
	const gearPromises = customization.gear.map((attachment) =>
		applyGearAttachment(characterId, vrm, attachment)
	);
	await Promise.all(gearPromises);

	emit("character:customization:applied", { characterId });
}

/**
 * Remove all customizations from a VRM instance, restoring original state.
 */
export function removeCustomization(characterId: string, vrm: VRM): void {
	// Restore material snapshots
	const snapshots = materialSnapshots.get(characterId);
	if (snapshots) {
		vrm.scene.traverse((child) => {
			const mesh = child as Mesh;
			if (!mesh.isMesh || !mesh.name) return;

			const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
			for (const mat of mats) {
				const std = mat as MeshStandardMaterial;
				if (!std.isMeshStandardMaterial) continue;

				const key = `${mesh.name}:${std.name ?? mesh.name}`;
				const snapshot = snapshots.get(key);
				if (snapshot) {
					std.color.set(snapshot.color);
					std.roughness = snapshot.roughness;
					std.metalness = snapshot.metalness;
					std.emissive.set(snapshot.emissive);
					std.emissiveIntensity = snapshot.emissiveIntensity;
					std.needsUpdate = true;
				}
			}
		});
	}

	// Restore mesh visibility
	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (mesh.isMesh) {
			mesh.visible = true;
		}
	});

	// Remove all gear
	removeAllGear(characterId, vrm);
}

// ─── Material Overrides ────────────────────────────────────────────────────────

function applyMaterialOverride(vrm: VRM, override: MaterialOverride): void {
	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (!mesh.isMesh) return;

		const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
		for (const mat of mats) {
			const std = mat as MeshStandardMaterial;
			if (!std.isMeshStandardMaterial) continue;

			// Match by mesh name or material name
			if (mesh.name !== override.target && std.name !== override.target) continue;

			if (override.color !== undefined) std.color.set(override.color);
			if (override.roughness !== undefined) std.roughness = override.roughness;
			if (override.metalness !== undefined) std.metalness = override.metalness;
			if (override.emissive !== undefined) std.emissive.set(override.emissive);
			if (override.emissiveIntensity !== undefined) std.emissiveIntensity = override.emissiveIntensity;

			if (override.textureUrl) {
				textureLoader.load(resolveAssetUrl(override.textureUrl), (texture) => {
					std.map = texture;
					std.needsUpdate = true;
				});
			}

			std.needsUpdate = true;
		}
	});
}

// ─── Mesh Visibility ───────────────────────────────────────────────────────────

function applyMeshVisibility(vrm: VRM, override: MeshVisibilityOverride): void {
	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (mesh.isMesh && mesh.name === override.meshName) {
			mesh.visible = override.visible;
		}
	});
}

// ─── Gear Attachments ──────────────────────────────────────────────────────────

async function applyGearAttachment(
	characterId: string,
	vrm: VRM,
	attachment: GearAttachment,
): Promise<void> {
	const boneNode = vrm.humanoid?.getNormalizedBoneNode(attachment.boneName as VRMHumanBoneName);
	if (!boneNode) {
		console.error(
			`[VrmCustomizer] Bone "${attachment.boneName}" not found for gear slot "${attachment.slotId}"`
		);
		return;
	}

	// Remove existing gear in this slot
	const slotKey = `${characterId}:${attachment.slotId}`;
	const existingGear = gearGroups.get(slotKey);
	if (existingGear) {
		existingGear.parent?.remove(existingGear);
		gearGroups.delete(slotKey);
	}

	try {
		const gltf = await gltfLoader.loadAsync(resolveAssetUrl(attachment.assetUrl));
		const gearRoot = new Group();
		gearRoot.name = `gear-${attachment.slotId}`;
		gearRoot.userData.isGear = true;
		gearRoot.userData.slotId = attachment.slotId;
		gearRoot.userData.characterId = characterId;

		// Add all loaded meshes to the gear group
		gearRoot.add(gltf.scene);

		// Apply transforms
		if (attachment.offset) {
			gearRoot.position.copy(new Vector3(...attachment.offset));
		}
		if (attachment.rotation) {
			gearRoot.rotation.copy(new Euler(...attachment.rotation));
		}
		if (attachment.scale) {
			gearRoot.scale.copy(new Vector3(...attachment.scale));
		}

		// Enable shadows on gear meshes
		gearRoot.traverse((child) => {
			if ((child as Mesh).isMesh) {
				child.castShadow = true;
				child.receiveShadow = true;
			}
		});

		boneNode.add(gearRoot);
		gearGroups.set(slotKey, gearRoot);

		emit("character:gear:equipped", { characterId, slotId: attachment.slotId });
	} catch (err) {
		console.error(
			`[VrmCustomizer] Failed to load gear "${attachment.assetUrl}" for slot "${attachment.slotId}"`,
			err
		);
	}
}

/** Remove a single gear piece by slot. */
export function removeGear(characterId: string, slotId: string): void {
	const slotKey = `${characterId}:${slotId}`;
	const gear = gearGroups.get(slotKey);
	if (gear) {
		gear.parent?.remove(gear);
		gearGroups.delete(slotKey);
		emit("character:gear:unequipped", { characterId, slotId });
	}
}

/** Remove all gear from a character. */
function removeAllGear(characterId: string, vrm: VRM): void {
	// Traverse scene to find and remove all gear groups
	const toRemove: Object3D[] = [];
	vrm.scene.traverse((child) => {
		if (child.userData.isGear && child.userData.characterId === characterId) {
			toRemove.push(child);
		}
	});

	for (const gear of toRemove) {
		gear.parent?.remove(gear);
		const slotKey = `${characterId}:${gear.userData.slotId}`;
		gearGroups.delete(slotKey);
	}
}

// ─── Material Snapshots ────────────────────────────────────────────────────────

function snapshotMaterials(characterId: string, vrm: VRM): void {
	if (materialSnapshots.has(characterId)) return;

	const snapshots = new Map<string, MaterialSnapshot>();

	vrm.scene.traverse((child) => {
		const mesh = child as Mesh;
		if (!mesh.isMesh || !mesh.name) return;

		const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
		for (const mat of mats) {
			const std = mat as MeshStandardMaterial;
			if (!std.isMeshStandardMaterial) continue;

			const key = `${mesh.name}:${std.name ?? mesh.name}`;
			snapshots.set(key, {
				color: `#${std.color.getHexString()}`,
				roughness: std.roughness,
				metalness: std.metalness,
				emissive: `#${std.emissive.getHexString()}`,
				emissiveIntensity: std.emissiveIntensity,
			});
		}
	});

	materialSnapshots.set(characterId, snapshots);
}

/**
 * Clean up all customizer state for a character (call on character disposal).
 */
export function disposeCustomizer(characterId: string): void {
	materialSnapshots.delete(characterId);

	// Remove gear group entries for this character
	for (const [key] of gearGroups) {
		if (key.startsWith(`${characterId}:`)) {
			gearGroups.delete(key);
		}
	}
}
