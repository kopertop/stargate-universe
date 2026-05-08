/**
 * Level editor — prop catalog.
 *
 * A prop is a self-contained piece of world content that the editor can
 * place. Each catalog entry exposes a `create()` factory that builds the
 * Three.js geometry (and optional physics) for one instance.
 *
 * See design/gdd/level-editor.md for the full design vocabulary.
 */
import * as THREE from "three";
import type { CrashcatPhysicsWorld } from "@ggez/runtime-physics-crashcat";

export type PropId = string;

export interface PropBuildContext {
	scene: THREE.Scene;
	physicsWorld: CrashcatPhysicsWorld;
}

export interface PropInstance {
	id: PropId;
	root: THREE.Object3D;
	/** Remove from scene + dispose GPU/physics resources. */
	dispose(): void;
}

export interface PropCatalogEntry {
	id: PropId;
	name: string;
	/** Approximate bounding size for the placement preview ghost. */
	previewSize: [number, number, number];
	create(
		ctx: PropBuildContext,
		position: THREE.Vector3,
		rotation: THREE.Euler,
		instanceProps?: Record<string, unknown>,
	): PropInstance;
}

/** Serialized placement of a prop — persisted to localStorage. */
export interface PlacedProp {
	id: PropId;
	position: [number, number, number];
	rotation: [number, number, number];
	props?: Record<string, unknown>;
}

export interface EditorSceneDocument {
	sceneId: string;
	version: 1;
	placed: PlacedProp[];
}

// ─── Registry ────────────────────────────────────────────────────────────────

const registry = new Map<PropId, PropCatalogEntry>();

export function registerProp(entry: PropCatalogEntry): void {
	registry.set(entry.id, entry);
}

export function getProp(id: PropId): PropCatalogEntry | undefined {
	return registry.get(id);
}

export function listProps(): PropCatalogEntry[] {
	return [...registry.values()];
}
