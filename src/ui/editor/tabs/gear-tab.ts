/**
 * Gear Tab — browse and equip gear items from the catalog.
 *
 * Fetches the gear manifest from R2 and displays items grouped by slot.
 * Click to equip/unequip (one item per slot).
 */
import { resolveAssetUrl } from "../../../systems/asset-resolver";
import type { GearAttachment, GearCatalogItem, GearSlot } from "../../../systems/vrm/vrm-customization-types";
import { GEAR_SLOTS } from "../../../systems/vrm/vrm-customization-types";

export type GearTabState = {
	readonly equipped: Map<GearSlot, GearAttachment>;
};

export type GearTab = {
	readonly element: HTMLElement;
	readonly state: GearTabState;
	hydrateOverrides(saved: readonly GearAttachment[]): void;
	dispose(): void;
};

const GEAR_MANIFEST_PATH = "/gear/gear-manifest.json";

/**
 * Create the gear tab content. Loads the gear catalog and displays items
 * grouped by slot.
 */
export function createGearTab(
	onChanged: () => void,
): GearTab {
	const container = document.createElement("div");
	const equipped = new Map<GearSlot, GearAttachment>();

	// Show loading state initially
	const loading = document.createElement("div");
	loading.className = "vrm-editor-empty";
	loading.textContent = "Loading gear catalog...";
	container.appendChild(loading);

	// Start loading the gear catalog
	loadGearCatalog().then((catalog) => {
		container.removeChild(loading);
		renderCatalog(container, catalog, equipped, onChanged);
	}).catch(() => {
		loading.textContent = "No gear catalog available yet. Upload gear-manifest.json to R2.";
	});

	return {
		element: container,
		state: { equipped },
		hydrateOverrides(saved: readonly GearAttachment[]) {
			for (const attachment of saved) {
				equipped.set(attachment.slotId, attachment);
			}
		},
		dispose() {
			container.remove();
		},
	};
}

async function loadGearCatalog(): Promise<GearCatalogItem[]> {
	const url = resolveAssetUrl(GEAR_MANIFEST_PATH);
	const response = await fetch(url);
	if (!response.ok) {
		throw new Error(`Failed to load gear manifest: ${response.status}`);
	}
	return response.json();
}

function renderCatalog(
	container: HTMLElement,
	catalog: GearCatalogItem[],
	equipped: Map<GearSlot, GearAttachment>,
	onChanged: () => void,
): void {
	// Clear existing children safely
	while (container.firstChild) {
		container.removeChild(container.firstChild);
	}

	if (catalog.length === 0) {
		const empty = document.createElement("div");
		empty.className = "vrm-editor-empty";
		empty.textContent = "No gear items in catalog";
		container.appendChild(empty);
		return;
	}

	// Group by slot
	const bySlot = new Map<GearSlot, GearCatalogItem[]>();
	for (const item of catalog) {
		const group = bySlot.get(item.slot) ?? [];
		group.push(item);
		bySlot.set(item.slot, group);
	}

	for (const slot of GEAR_SLOTS) {
		const items = bySlot.get(slot);
		if (!items?.length) continue;

		const section = document.createElement("div");
		section.className = "vrm-editor-section";

		const title = document.createElement("div");
		title.className = "vrm-editor-section-title";
		title.textContent = formatSlotName(slot);
		section.appendChild(title);

		const grid = document.createElement("div");
		grid.className = "vrm-editor-gear-grid";

		for (const item of items) {
			const card = document.createElement("div");
			card.className = "vrm-editor-gear-item";

			const isEquipped = equipped.get(slot)?.assetUrl === item.assetUrl;
			if (isEquipped) card.classList.add("equipped");

			if (item.thumbnailUrl) {
				const img = document.createElement("img");
				img.src = resolveAssetUrl(item.thumbnailUrl);
				img.alt = item.displayName;
				card.appendChild(img);
			}

			const label = document.createElement("span");
			label.textContent = item.displayName;
			card.appendChild(label);

			card.addEventListener("click", () => {
				const wasEquipped = equipped.get(slot)?.assetUrl === item.assetUrl;
				if (wasEquipped) {
					equipped.delete(slot);
				} else {
					equipped.set(slot, {
						slotId: slot,
						assetUrl: item.assetUrl,
						boneName: item.boneName,
						offset: item.offset ? [...item.offset] : undefined,
						rotation: item.rotation ? [...item.rotation] : undefined,
						scale: item.scale ? [...item.scale] : undefined,
					});
				}

				// Re-render to update equipped state
				renderCatalog(container, catalog, equipped, onChanged);
				onChanged();
			});

			grid.appendChild(card);
		}

		section.appendChild(grid);
		container.appendChild(section);
	}
}

function formatSlotName(slot: GearSlot): string {
	const names: Record<GearSlot, string> = {
		head: "Head",
		torso: "Torso",
		leftHand: "Left Hand",
		rightHand: "Right Hand",
		back: "Back",
		belt: "Belt",
	};
	return names[slot] ?? slot;
}
