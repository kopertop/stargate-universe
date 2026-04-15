/**
 * Runtime discovery helpers for VRM editor tabs.
 * Stubs — full implementation pending VRM editor integration.
 */

import type { VRM } from "@pixiv/three-vrm";

export interface DiscoveredMesh {
	name: string;
	materialName: string;
}

export interface DiscoveredMaterial {
	name: string;
	color?: string;
}

/**
 * Enumerate all skinned meshes in a VRM that could be shown/hidden in the visibility tab.
 */
export function discoverMeshes(_vrm: VRM): DiscoveredMesh[] {
	// TODO: traverse VRM for Mesh nodes with SkinnedMesh.renderer
	return [];
}

/**
 * Enumerate all materials in a VRM that could be edited in the materials tab.
 */
export function discoverMaterials(_vrm: VRM): DiscoveredMaterial[] {
	// TODO: extract material names and initial PBR values from VRM.materials
	return [];
}