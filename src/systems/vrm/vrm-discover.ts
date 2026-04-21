/**
 * Runtime discovery helpers for VRM editor tabs.
 *
 * At edit-time the Trident editor needs to enumerate the meshes and materials
 * present in a VRM file so the editor can offer per-mesh visibility toggles
 * and per-material colour overrides without loading the full VRM pipeline.
 * These functions are called by the editor's VRM asset tab.
 */

import { Mesh, SkinnedMesh, type Material, type Object3D } from "three";

// ─── Types ───────────────────────────────────────────────────────────────────

/**
 * Subset of Three.js Material properties that are relevant for VRM editor
 * discovery.  Covers both standard PBR materials and MToon toon materials.
 */
interface MaterialDescriptor {
	name?: string;
	transparent?: boolean;
	opacity?: number;
	alphaTest?: number;
	color?: { r: number; g: number; b: number };
	map?: unknown;
	emissiveMap?: unknown;
}

export interface DiscoveredMesh {
	/** Unique name derived from the Three.js mesh object. */
	name: string;
	/** Name of the material applied to this mesh. */
	materialName: string;
	/** True when this mesh is a SkinnedMesh (skeleton-driven). */
	isSkinned: boolean;
}

export interface DiscoveredMaterial {
	/** Material slot name from the VRM. */
	name: string;
	/** RGBA hex string of the primary colour, e.g. "#a1b2c3ff". */
	color?: string;
	/** True when the material has a diffuse texture map. */
	hasMap: boolean;
	/** True when the material is transparent. */
	transparent: boolean;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/**
 * Pack a colour triplet into a 6-digit lower-case hex string.
 * Alpha is omitted — call sites can append "ff" for full opacity.
 */
function colorToHex(c: { r: number; g: number; b: number }): string {
	const r = Math.round(c.r * 255).toString(16).padStart(2, "0");
	const g = Math.round(c.g * 255).toString(16).padStart(2, "0");
	const b = Math.round(c.b * 255).toString(16).padStart(2, "0");
	return (r + g + b).toLowerCase();
}

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Enumerate all meshes in a VRM that could be shown/hidden in the visibility tab.
 *
 * Traversal is shallow (direct children of the VRM scene group) to keep
 * the editor tab fast.  Nested intermediate Groups without mesh children
 * are skipped.
 */
export function discoverMeshes(
	vrm: { scene: { children: Object3D[] } },
): DiscoveredMesh[] {
	const meshes: DiscoveredMesh[] = [];

	vrm.scene.children.forEach((child) => {
		if (child instanceof Mesh || child instanceof SkinnedMesh) {
			meshes.push({
				name: child.name || "(unnamed)",
				materialName: Array.isArray(child.material)
					? child.material.map((m) => m.name || "(unnamed)").join(" + ")
					: (child.material?.name || "(unnamed)"),
				isSkinned: child instanceof SkinnedMesh,
			});
		}
	});

	return meshes;
}

/**
 * Enumerate all materials in a VRM that could be edited in the materials tab.
 *
 * Collects unique materials from the VRM's material array and reads the
 * primary colour, texture presence, and transparency flag so the editor
 * can offer quick overrides without instantiating the full render pipeline.
 */
export function discoverMaterials(
	vrm: { materials?: Material[] },
): DiscoveredMaterial[] {
	if (!vrm.materials || vrm.materials.length === 0) return [];

	return vrm.materials.map((mat) => {
		const mtoon = mat as unknown as MaterialDescriptor;
		const color = mtoon.color ? "#" + colorToHex(mtoon.color) : undefined;
		return {
			name: mat.name || "(unnamed)",
			color,
			hasMap: !!(mtoon.map || mtoon.emissiveMap),
			transparent: !!(mat.transparent || mtoon.opacity! < 1 || mtoon.alphaTest! > 0),
		};
	});
}
