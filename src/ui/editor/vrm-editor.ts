/**
 * VRM Character Editor — main controller.
 *
 * Opens a full-screen overlay with a 3D turntable preview and tabs for
 * material editing, gear attachment, and mesh visibility toggles.
 *
 * Usage:
 *   import { openVrmEditor } from "./ui/editor/vrm-editor";
 *   openVrmEditor("player", vrm);
 *
 * @see src/ui/editor/vrm-editor-styles.css
 */
import type { VRM } from "@pixiv/three-vrm";

import {
	applyCustomization,
	removeCustomization,
	type VrmCustomization,
} from "../../systems/vrm";
import { saveCustomization, loadCustomization } from "../../systems/vrm/vrm-customization-persistence";
import { createEmptyCustomization } from "../../systems/vrm/vrm-customization-types";
import type { MaterialOverride, GearAttachment, MeshVisibilityOverride } from "../../systems/vrm/vrm-customization-types";
import { createEditorPreview, type EditorPreview } from "./vrm-editor-preview";
import { createMaterialsTab, type MaterialsTab } from "./tabs/materials-tab";
import { createVisibilityTab, type VisibilityTab } from "./tabs/visibility-tab";
import { createGearTab, type GearTab } from "./tabs/gear-tab";
import "./vrm-editor-styles.css";

// ─── State ─────────────────────────────────────────────────────────────────────

let activeEditor: EditorInstance | null = null;

type EditorInstance = {
	characterId: string;
	vrm: VRM;
	overlay: HTMLElement;
	preview: EditorPreview;
	materialsTab: MaterialsTab;
	visibilityTab: VisibilityTab;
	gearTab: GearTab;
	activeTabId: string;
};

type TabDef = {
	id: string;
	label: string;
};

const TABS: readonly TabDef[] = [
	{ id: "materials", label: "Materials" },
	{ id: "gear", label: "Gear" },
	{ id: "visibility", label: "Visibility" },
];

// ─── Public API ────────────────────────────────────────────────────────────────

/**
 * Open the VRM editor for a character.
 * Only one editor can be open at a time.
 */
export function openVrmEditor(characterId: string, vrm: VRM): void {
	if (activeEditor) {
		closeVrmEditor();
	}

	const preview = createEditorPreview();
	preview.setVrm(vrm);

	const onChanged = () => {
		// Real-time preview: collect state and apply to VRM
		applyCurrentState();
	};

	const materialsTab = createMaterialsTab(vrm, onChanged);
	const visibilityTab = createVisibilityTab(vrm, onChanged);
	const gearTab = createGearTab(onChanged);

	const overlay = buildOverlay(preview, materialsTab, visibilityTab, gearTab);
	document.body.appendChild(overlay);

	activeEditor = {
		characterId,
		vrm,
		overlay,
		preview,
		materialsTab,
		visibilityTab,
		gearTab,
		activeTabId: "materials",
	};

	// Load existing customization
	loadCustomization(characterId).then((saved) => {
		if (saved && activeEditor) {
			// Apply saved customization to the VRM immediately
			applyCustomization(activeEditor.characterId, activeEditor.vrm, saved).catch((err) => {
				console.info(\"[VrmEditor] Saved customization not applied on load (using defaults)\", err);
			});

			// Populate tab UI state from saved customization
			if (saved.materials) {
				saved.materials.forEach((ov) => {
					activeEditor.materialsTab.state.overrides.set(ov.target, ov);
					// Note: We can't easily update the DOM elements of the tab without a re-render 
					// or a set-state mechanism, but the internal state is now synced.
				});
			}
			if (saved.gear) {
				saved.gear.forEach((att) => {
					activeEditor.gearTab.state.equipped.set(att.id, att);
				});
			}
			if (saved.meshVisibility) {
				saved.meshVisibility.forEach((ov) => {
					activeEditor.visibilityTab.state.overrides.set(ov.target, ov);
				});
			}
		}
	}).catch(() => {
		// No saved customization — start fresh
	});
}

/**
 * Close the VRM editor and clean up.
 */
export function closeVrmEditor(): void {
	if (!activeEditor) return;

	activeEditor.preview.dispose();
	activeEditor.materialsTab.dispose();
	activeEditor.visibilityTab.dispose();
	activeEditor.gearTab.dispose();
	activeEditor.overlay.remove();
	activeEditor = null;
}

/**
 * Check if the editor is currently open.
 */
export function isVrmEditorOpen(): boolean {
	return activeEditor !== null;
}

// ─── Internal: DOM Construction ────────────────────────────────────────────────

function buildOverlay(
	preview: EditorPreview,
	materialsTab: MaterialsTab,
	visibilityTab: VisibilityTab,
	gearTab: GearTab,
): HTMLElement {
	const overlay = document.createElement("div");
	overlay.className = "vrm-editor-overlay";

	const panel = document.createElement("div");
	panel.className = "vrm-editor-panel";

	// Header
	const header = document.createElement("div");
	header.className = "vrm-editor-header";

	const title = document.createElement("span");
	title.className = "vrm-editor-title";
	title.textContent = "Character Editor";
	header.appendChild(title);

	const closeBtn = document.createElement("button");
	closeBtn.className = "vrm-editor-close";
	closeBtn.textContent = "Close";
	closeBtn.addEventListener("click", closeVrmEditor);
	header.appendChild(closeBtn);

	panel.appendChild(header);

	// Tab bar
	const tabBar = document.createElement("div");
	tabBar.className = "vrm-editor-tabs";

	const tabContents = new Map<string, HTMLElement>();
	tabContents.set("materials", materialsTab.element);
	tabContents.set("gear", gearTab.element);
	tabContents.set("visibility", visibilityTab.element);

	for (const tab of TABS) {
		const tabBtn = document.createElement("button");
		tabBtn.className = "vrm-editor-tab";
		tabBtn.textContent = tab.label;
		tabBtn.dataset.tabId = tab.id;

		if (tab.id === "materials") {
			tabBtn.classList.add("active");
		}

		tabBtn.addEventListener("click", () => {
			// Update active tab button
			tabBar.querySelectorAll(".vrm-editor-tab").forEach((btn) => {
				btn.classList.toggle("active", (btn as HTMLElement).dataset.tabId === tab.id);
			});

			// Show/hide tab content
			for (const [id, element] of tabContents) {
				element.style.display = id === tab.id ? "" : "none";
			}

			if (activeEditor) {
				activeEditor.activeTabId = tab.id;
			}
		});

		tabBar.appendChild(tabBtn);
	}

	panel.appendChild(tabBar);

	// Body: preview + content
	const body = document.createElement("div");
	body.className = "vrm-editor-body";

	const previewContainer = document.createElement("div");
	previewContainer.className = "vrm-editor-preview";
	previewContainer.appendChild(preview.canvas);
	body.appendChild(previewContainer);

	const content = document.createElement("div");
	content.className = "vrm-editor-content";

	// Add all tab contents, hide non-active
	for (const [id, element] of tabContents) {
		element.style.display = id === "materials" ? "" : "none";
		content.appendChild(element);
	}

	body.appendChild(content);
	panel.appendChild(body);

	// Footer
	const footer = document.createElement("div");
	footer.className = "vrm-editor-footer";

	const resetBtn = document.createElement("button");
	resetBtn.className = "vrm-editor-btn";
	resetBtn.textContent = "Reset";
	resetBtn.addEventListener("click", handleReset);
	footer.appendChild(resetBtn);

	const saveBtn = document.createElement("button");
	saveBtn.className = "vrm-editor-btn primary";
	saveBtn.textContent = "Save";
	saveBtn.addEventListener("click", handleSave);
	footer.appendChild(saveBtn);

	panel.appendChild(footer);

	// Click outside panel to close
	overlay.addEventListener("click", (e) => {
		if (e.target === overlay) {
			closeVrmEditor();
		}
	});

	// Escape key to close
	const handleEscape = (e: KeyboardEvent) => {
		if (e.key === "Escape") {
			closeVrmEditor();
			window.removeEventListener("keydown", handleEscape);
		}
	};
	window.addEventListener("keydown", handleEscape);

	overlay.appendChild(panel);
	return overlay;
}

// ─── Internal: Actions ─────────────────────────────────────────────────────────

function collectCustomization(): VrmCustomization {
	if (!activeEditor) return createEmptyCustomization("unknown");

	const materials: MaterialOverride[] = Array.from(
		activeEditor.materialsTab.state.overrides.values()
	);

	const gear: GearAttachment[] = Array.from(
		activeEditor.gearTab.state.equipped.values()
	);

	const meshVisibility: MeshVisibilityOverride[] = Array.from(
		activeEditor.visibilityTab.state.overrides.values()
	);

	return {
		characterId: activeEditor.characterId,
		version: 1,
		materials,
		gear,
		meshVisibility,
	};
}

function applyCurrentState(): void {
	if (!activeEditor) return;

	const customization = collectCustomization();
	applyCustomization(activeEditor.characterId, activeEditor.vrm, customization).catch((err) => {
		console.info(\"[VrmEditor] Preview customization failed to apply\", err);
	});
}

async function handleSave(): Promise<void> {
	if (!activeEditor) return;

	const customization = collectCustomization();
	try {
		await saveCustomization(customization);
		console.info(`[VrmEditor] Saved customization for "${activeEditor.characterId}"`);
	} catch (err) {
		console.error("[VrmEditor] Failed to save customization", err);
	}
}

function handleReset(): void {
	if (!activeEditor) return;
	removeCustomization(activeEditor.characterId, activeEditor.vrm);
}
