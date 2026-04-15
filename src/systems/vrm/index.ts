/**
 * VRM Character Model System — public API surface.
 *
 * Integrated with ggez pipeline: entities placed in Trident, animations
 * through ggez animation editor, assets loaded via scene asset pipeline.
 *
 * @see design/gdd/vrm-model-integration.md
 */

// Asset loading
export { loadVrm, isVrmCached, getCachedVrm, evictVrm, clearVrmCache, type VrmLoadResult } from "./vrm-asset-loader";

// Configuration
export { getVrmConfig, loadVrmConfig, type VrmConfig } from "./vrm-config";

// Bone mapping
export {
	VRM_REQUIRED_BONES,
	VRM_OPTIONAL_BONES,
	VRM_TO_GGEZ_BONE_MAP,
	MIXAMO_TO_VRM_BONE_MAP,
	validateRequiredBones,
	type VrmBoneName,
} from "./vrm-bone-map";

// Character management
export {
	VrmCharacterManager,
	type VrmCharacterInstance,
	type VrmCharacterOptions,
	type LodTier,
} from "./vrm-character-instance";

// Animation retargeting
export { createVrmAnimatorBridge, type VrmAnimatorBridge } from "./vrm-retarget-bridge";
export { retargetClipToVrmSkeleton } from "./vrm-clip-retargeter";

// VRM-specific features
export { VrmExpressionController, type VrmExpressionName, type VrmVisemeName, type ExpressionTarget } from "./vrm-expression-controller";
export { VrmLookAtController, type LookAtMode, type LookAtState } from "./vrm-lookat-controller";
export { convertMToonToPBR, flattenVrmMaterials } from "./vrm-mtoon-converter";

// Crew roster
export {
	DEFAULT_CREW_ROSTER,
	getCrewRoster,
	getCrewManifest,
	getPlayerManifest,
	getNpcManifests,
	loadCrewRoster,
	type CrewCharacterManifest,
	type CrewExpressionProfile,
	type SpringBoneProfile,
} from "./vrm-crew-manifest";

// Entity system
export {
	createVrmEntitySystem,
	findPlayerVrmEntity,
	type VrmEntitySystemOptions,
	type VrmEntitySystemResult,
} from "./vrm-entity-system";

// Customization types
export {
	type GearSlot,
	GEAR_SLOTS,
	GEAR_SLOT_BONES,
	type VrmCustomization,
	type MaterialOverride,
	type GearAttachment,
	type MeshVisibilityOverride,
	type GearCatalogItem,
	createEmptyCustomization,
} from "./vrm-customization-types";

// Customization persistence
export { loadCustomization, saveCustomization } from "./vrm-customization-persistence";

// Customizer
export {
	applyCustomization,
	removeCustomization,
	discoverMaterials,
	type DiscoveredMaterial,
	discoverMeshes,
	type DiscoveredMesh,
	disposeCustomizer,
} from "./vrm-customizer";