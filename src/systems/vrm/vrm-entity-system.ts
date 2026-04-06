/**
 * VRM Entity System — processes "vrm-character" entities from scene.runtime.json.
 *
 * Registered as a gameplay system, this module reads VRM character entities
 * at scene load, spawns NPC characters via the VrmCharacterManager, and
 * positions them at their editor-placed transforms.
 *
 * Player VRM characters are handled separately by VrmPlayerController.
 *
 * @see design/gdd/vrm-model-integration.md
 */
import type { ThreeRuntimeSceneInstance } from "@ggez/three-runtime";
import { Group, Scene } from "three";
import { VrmCharacterManager, type VrmCharacterInstance } from "./vrm-character-instance";

// ─── Types ──────────────────────────────────────────────────────────────────

export type VrmEntitySystemOptions = {
	/** The character manager for this scene. */
	characterManager: VrmCharacterManager;
	/** The loaded runtime scene instance. */
	runtimeScene: ThreeRuntimeSceneInstance;
	/** The root Three.js scene (to add NPC groups). */
	scene: Scene;
	/** Resolve an asset path to a URL. */
	resolveAssetUrl: (path: string) => string;
};

export type VrmEntitySystemResult = {
	/** All spawned NPC instances (excluding player). */
	readonly npcInstances: readonly VrmCharacterInstance[];
	/** Dispose the entity system and remove NPCs from scene. */
	dispose(): void;
};

// ─── System ─────────────────────────────────────────────────────────────────

/**
 * Process all "vrm-character" entities in the scene.
 * Non-player entities are immediately spawned as NPC characters.
 *
 * @returns Handles for spawned NPCs and a dispose function.
 */
export function createVrmEntitySystem(options: VrmEntitySystemOptions): VrmEntitySystemResult {
	const { characterManager, runtimeScene, scene, resolveAssetUrl } = options;
	const npcInstances: VrmCharacterInstance[] = [];
	const npcRoots: Group[] = [];

	for (const entity of runtimeScene.entities) {
		if (entity.type !== "vrm-character") continue;

		const isPlayer = entity.properties["isPlayer"] === true;

		// Player VRM is handled by VrmPlayerController, skip here
		if (isPlayer) continue;

		const vrmUrl = entity.properties["vrmUrl"] as string | undefined;

		if (!vrmUrl) {
			console.warn(`[VrmEntitySystem] Entity "${entity.id}" has no vrmUrl property, skipping`);
			continue;
		}

		const characterId = (entity.properties["characterId"] as string) || entity.id;
		const resolvedUrl = resolveAssetUrl(vrmUrl);

		const instance = characterManager.addCharacter({
			id: characterId,
			vrmUrl: resolvedUrl,
			isPlayer: false,
			priority: 1,
		});

		// Position at entity transform
		instance.root.position.set(
			entity.transform.position.x,
			entity.transform.position.y,
			entity.transform.position.z,
		);
		instance.root.rotation.set(
			entity.transform.rotation.x,
			entity.transform.rotation.y,
			entity.transform.rotation.z,
		);

		scene.add(instance.root);
		npcInstances.push(instance);
		npcRoots.push(instance.root);
	}

	if (npcInstances.length > 0) {
		console.info(`[VrmEntitySystem] Spawned ${npcInstances.length} NPC character(s)`);
	}

	return {
		npcInstances,
		dispose() {
			for (const root of npcRoots) {
				scene.remove(root);
			}

			for (const instance of npcInstances) {
				characterManager.removeCharacter(instance.id);
			}
		},
	};
}

/**
 * Find the player VRM entity from a scene's entities list.
 * Returns entity data for use by VrmPlayerController setup.
 */
export function findPlayerVrmEntity(
	runtimeScene: ThreeRuntimeSceneInstance,
): { vrmUrl: string; animationBundle: string; characterId: string } | undefined {
	for (const entity of runtimeScene.entities) {
		if (entity.type !== "vrm-character") continue;
		if (entity.properties["isPlayer"] !== true) continue;

		const vrmUrl = entity.properties["vrmUrl"] as string | undefined;

		if (!vrmUrl) return undefined;

		return {
			vrmUrl,
			animationBundle: (entity.properties["animationBundle"] as string) || "",
			characterId: (entity.properties["characterId"] as string) || "player",
		};
	}

	return undefined;
}
