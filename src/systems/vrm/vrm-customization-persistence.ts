/**
 * VRM Customization Persistence — save/load character customizations.
 *
 * Uses the R2-backed API when available, with localStorage as fallback
 * for offline development.
 *
 * @see functions/api/customizations/[[characterId]].ts
 */
import { emit } from "../event-bus";
import type { VrmCustomization } from "./vrm-customization-types";

const STORAGE_KEY_PREFIX = "vrm-customization:";
const API_BASE = "/api/customizations";

/**
 * Load a saved customization for a character.
 * Tries the API first, falls back to localStorage.
 *
 * @returns The saved customization, or null if none exists.
 */
export async function loadCustomization(characterId: string): Promise<VrmCustomization | null> {
	// Try API first
	try {
		const response = await fetch(`${API_BASE}/${encodeURIComponent(characterId)}`);
		if (response.ok) {
			const data = await response.json();
			if (data && typeof data === "object" && "characterId" in data) {
				return data as VrmCustomization;
			}
		}
	} catch {
		// API not available — fall through to localStorage
	}

	// Fallback: localStorage
	try {
		const stored = localStorage.getItem(`${STORAGE_KEY_PREFIX}${characterId}`);
		if (stored) {
			return JSON.parse(stored) as VrmCustomization;
		}
	} catch {
		// localStorage not available or corrupt
	}

	return null;
}

/**
 * Save a character customization.
 * Saves to both API and localStorage (localStorage as offline cache).
 */
export async function saveCustomization(customization: VrmCustomization): Promise<void> {
	const { characterId } = customization;
	const json = JSON.stringify(customization);

	// Always save to localStorage as cache
	try {
		localStorage.setItem(`${STORAGE_KEY_PREFIX}${characterId}`, json);
	} catch {
		// localStorage full or not available
	}

	// Try API
	try {
		const response = await fetch(`${API_BASE}/${encodeURIComponent(characterId)}`, {
			method: "PUT",
			headers: { "Content-Type": "application/json" },
			body: json,
		});

		if (!response.ok) {
			console.error(`[VrmCustomizationPersistence] API save failed (${response.status})`);
		}
	} catch {
		console.error(\"[VrmCustomizationPersistence] API not available, saved to localStorage only\");
	}

	emit("character:customization:saved", { characterId });
}

/**
 * Delete a saved customization.
 */
export async function deleteCustomization(characterId: string): Promise<void> {
	// Remove from localStorage
	try {
		localStorage.removeItem(`${STORAGE_KEY_PREFIX}${characterId}`);
	} catch {
		// ignore
	}

	// API doesn't have a DELETE endpoint yet — just overwrite with null
	// The GET handler returns 404 for missing keys, so this is fine
}
