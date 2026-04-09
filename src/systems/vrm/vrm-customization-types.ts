/**
 * VRM Character Customization — data model for character appearance overrides.
 *
 * Customizations are serialized as JSON, stored in R2 (or localStorage as fallback),
 * and applied to VRM instances at load time or in the editor.
 *
 * @see design/gdd/vrm-model-integration.md
 */

// ─── Gear Slots ────────────────────────────────────────────────────────────────

/** Named attachment points on the character skeleton. */
export type GearSlot = "head" | "torso" | "leftHand" | "rightHand" | "back" | "belt";

/** All valid gear slots. */
export const GEAR_SLOTS: readonly GearSlot[] = [
	"head", "torso", "leftHand", "rightHand", "back", "belt",
] as const;

/** Maps gear slots to VRM humanoid bone names for attachment. */
export const GEAR_SLOT_BONES: Record<GearSlot, string> = {
	head: "head",
	torso: "chest",
	leftHand: "leftHand",
	rightHand: "rightHand",
	back: "spine",
	belt: "hips",
};

// ─── Customization Data ────────────────────────────────────────────────────────

/** Root customization document for a single character. */
export type VrmCustomization = {
	readonly characterId: string;
	readonly version: 1;
	readonly materials: readonly MaterialOverride[];
	readonly gear: readonly GearAttachment[];
	readonly meshVisibility: readonly MeshVisibilityOverride[];
};

/** Override material properties on a specific mesh or material by name. */
export type MaterialOverride = {
	/** Mesh name or material name to target (matched against `mesh.name` or `material.name`). */
	readonly target: string;
	/** Base color as hex string (e.g., "#ff0000"). */
	readonly color?: string;
	/** PBR roughness (0 = mirror, 1 = matte). */
	readonly roughness?: number;
	/** PBR metalness (0 = dielectric, 1 = metallic). */
	readonly metalness?: number;
	/** Emissive color as hex string. */
	readonly emissive?: string;
	/** Emissive intensity multiplier. */
	readonly emissiveIntensity?: number;
	/** URL to a replacement diffuse texture (stored in R2). */
	readonly textureUrl?: string;
};

/** Attach a gear GLB model to a bone on the character. */
export type GearAttachment = {
	/** Which slot this gear occupies (one item per slot). */
	readonly slotId: GearSlot;
	/** URL or R2 path to the `.glb` gear model. */
	readonly assetUrl: string;
	/** VRM humanoid bone name to parent the gear mesh to. */
	readonly boneName: string;
	/** Position offset relative to the bone (meters). */
	readonly offset?: readonly [number, number, number];
	/** Euler rotation offset (radians). */
	readonly rotation?: readonly [number, number, number];
	/** Scale multiplier. */
	readonly scale?: readonly [number, number, number];
};

/** Show or hide a mesh by name. Used to toggle hair styles, clothing layers, etc. */
export type MeshVisibilityOverride = {
	/** Mesh name to target (exact match on `mesh.name`). */
	readonly meshName: string;
	/** Whether the mesh should be visible. */
	readonly visible: boolean;
};

// ─── Gear Catalog ──────────────────────────────────────────────────────────────

/** A single item in the gear catalog (loaded from R2 gear-manifest.json). */
export type GearCatalogItem = {
	readonly id: string;
	readonly displayName: string;
	readonly slot: GearSlot;
	readonly assetUrl: string;
	readonly boneName: string;
	readonly thumbnailUrl?: string;
	readonly offset?: readonly [number, number, number];
	readonly rotation?: readonly [number, number, number];
	readonly scale?: readonly [number, number, number];
};

// ─── Defaults ──────────────────────────────────────────────────────────────────

/** Empty customization — no changes applied. */
export function createEmptyCustomization(characterId: string): VrmCustomization {
	return {
		characterId,
		version: 1,
		materials: [],
		gear: [],
		meshVisibility: [],
	};
}
