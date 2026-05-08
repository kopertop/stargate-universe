/**
 * Editor persistence — localStorage I/O for placed props.
 *
 * Prototype storage layer. Production flow (see level-editor.md GDD) will
 * serialize into `scene.runtime.json` diffs.
 */
import type { EditorSceneDocument, PlacedProp } from "./prop-catalog";

const STORAGE_PREFIX = "sgu:editor:";

export function storageKey(sceneId: string): string {
	return `${STORAGE_PREFIX}${sceneId}`;
}

export function loadSceneDoc(sceneId: string): EditorSceneDocument {
	const raw = typeof localStorage !== "undefined" ? localStorage.getItem(storageKey(sceneId)) : null;
	if (!raw) return { sceneId, version: 1, placed: [] };
	try {
		const parsed = JSON.parse(raw) as EditorSceneDocument;
		if (parsed.version !== 1) {
			console.warn(`[editor] storage version ${parsed.version} != 1 — ignoring`);
			return { sceneId, version: 1, placed: [] };
		}
		return parsed;
	} catch (err) {
		console.warn("[editor] storage parse failed — starting empty", err);
		return { sceneId, version: 1, placed: [] };
	}
}

export function saveSceneDoc(doc: EditorSceneDocument): void {
	if (typeof localStorage === "undefined") return;
	localStorage.setItem(storageKey(doc.sceneId), JSON.stringify(doc));
}

export function clearSceneDoc(sceneId: string): void {
	if (typeof localStorage === "undefined") return;
	localStorage.removeItem(storageKey(sceneId));
}

export function addPlaced(doc: EditorSceneDocument, placed: PlacedProp): EditorSceneDocument {
	return { ...doc, placed: [...doc.placed, placed] };
}

export function removePlaced(doc: EditorSceneDocument, index: number): EditorSceneDocument {
	return { ...doc, placed: doc.placed.filter((_, i) => i !== index) };
}
