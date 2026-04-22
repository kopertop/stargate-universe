/**
 * Visibility Tab — checkbox toggles for each mesh in the VRM.
 */
import type { VRM } from "@pixiv/three-vrm";
import { discoverMeshes } from "../../../systems/vrm/vrm-customizer";
import type { MeshVisibilityOverride } from "../../../systems/vrm/vrm-customization-types";

export type VisibilityTabState = {
	readonly overrides: Map<string, MeshVisibilityOverride>;
};

export type VisibilityTab = {
	readonly element: HTMLElement;
	readonly state: VisibilityTabState;
	hydrateOverrides(saved: readonly MeshVisibilityOverride[]): void;
	dispose(): void;
};

/**
 * Create the visibility tab content. Each mesh gets a checkbox row.
 */
export function createVisibilityTab(
	vrm: VRM,
	onChanged: () => void,
): VisibilityTab {
	const container = document.createElement("div");
	const meshes = discoverMeshes(vrm);
	const overrides = new Map<string, MeshVisibilityOverride>();

	if (meshes.length === 0) {
		const empty = document.createElement("div");
		empty.className = "vrm-editor-empty";
		empty.textContent = "No named meshes found";
		container.appendChild(empty);
<<<<<<< HEAD
		return {
			element: container,
			state: { overrides },
			hydrateOverrides() {},
			dispose() { container.remove(); },
		};
=======
		return { element: container, state: { overrides }, hydrateOverrides() {}, dispose() {} };
>>>>>>> a58c88e (fix(physics): correct colliderCount — static colliders now get rigid bodies)
	}

	const section = document.createElement("div");
	section.className = "vrm-editor-section";

	const title = document.createElement("div");
	title.className = "vrm-editor-section-title";
	title.textContent = `Meshes (${meshes.length})`;
	section.appendChild(title);

	for (const mesh of meshes) {
		const row = document.createElement("div");
		row.className = "vrm-editor-row";

		const checkbox = document.createElement("input");
		checkbox.type = "checkbox";
		checkbox.checked = mesh.visible;
		checkbox.id = `mesh-vis-${mesh.name}`;

		const label = document.createElement("label");
		label.className = "vrm-editor-label";
		label.htmlFor = checkbox.id;
		label.textContent = mesh.name;
		label.title = `${mesh.vertexCount.toLocaleString()} vertices`;

		const vertCount = document.createElement("span");
		vertCount.className = "vrm-editor-value";
		vertCount.textContent = `${mesh.vertexCount}v`;

		checkbox.addEventListener("change", () => {
			overrides.set(mesh.name, {
				meshName: mesh.name,
				visible: checkbox.checked,
			});
			onChanged();
		});

		row.appendChild(checkbox);
		row.appendChild(label);
		row.appendChild(vertCount);
		section.appendChild(row);
	}

	container.appendChild(section);

	return {
		element: container,
		state: { overrides },
		hydrateOverrides(saved: readonly MeshVisibilityOverride[]) {
			for (const override of saved) {
				overrides.set(override.meshName, override);
				const checkbox = container.querySelector<HTMLInputElement>(
					`#mesh-vis-${CSS.escape(override.meshName)}`,
				);
				if (checkbox) checkbox.checked = override.visible;
			}
		},
		dispose() {
			container.remove();
		},
	};
}
