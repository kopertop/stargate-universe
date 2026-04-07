/**
 * VRM Character Model System — public API surface.
 *
 * @see design/gdd/vrm-model-integration.md
 */
export { getVrmConfig, loadVrmConfig, type VrmConfig } from "./vrm-config";
export {
	VRM_REQUIRED_BONES,
	VRM_OPTIONAL_BONES,
	VRM_TO_GGEZ_BONE_MAP,
	MIXAMO_TO_VRM_BONE_MAP,
	validateRequiredBones,
	type VrmBoneName,
} from "./vrm-bone-map";
export {
	loadVrm,
	isVrmCached,
	getCachedVrm,
	evictVrm,
	clearVrmCache,
	type VrmLoadResult,
} from "./vrm-loader";
export {
	VrmExpressionController,
	type VrmExpressionName,
	type VrmVisemeName,
	type ExpressionTarget,
} from "./vrm-expression-controller";
export {
	VrmLookAtController,
	type LookAtMode,
	type LookAtState,
} from "./vrm-lookat-controller";
export {
	convertMToonToPBR,
} from "./vrm-mtoon-converter";
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
export {
	addCharacter,
	removeCharacter,
	getCharacter,
	getAllCharacters,
	setActiveCamera,
	setFirstPersonMode,
	spawnCrew,
	update as updateVrmCharacters,
	dispose as disposeVrmCharacters,
	type VrmCharacterOptions,
	type VrmCharacterInstance,
	type LodTier,
} from "./vrm-character-manager";
export {
	applyCustomization,
	removeCustomization,
	removeGear,
	discoverMeshes,
	discoverMaterials,
	disposeCustomizer,
	type DiscoveredMesh,
	type DiscoveredMaterial,
} from "./vrm-customizer";
export type {
	VrmCustomization,
	MaterialOverride,
	GearAttachment,
	GearSlot,
	GearCatalogItem,
	MeshVisibilityOverride,
} from "./vrm-customization-types";
export {
	GEAR_SLOTS,
	GEAR_SLOT_BONES,
	createEmptyCustomization,
} from "./vrm-customization-types";
export {
	loadCustomization,
	saveCustomization,
	deleteCustomization,
} from "./vrm-customization-persistence";
export { loadAnimation, loadMixamoAnimation, loadVrmaAnimation } from "./vrm-animation-retarget";
export {
	VrmPlayerAnimationController,
	type PlayerAnimationParams,
} from "./vrm-player-animation-controller";
