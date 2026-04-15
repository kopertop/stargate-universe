/**
 * Materials Tab — color pickers and PBR sliders for each VRM material.
 */
import type { VRM } from "@pixiv/three-vrm";
import { discoverMaterials, type DiscoveredMaterial } from "../../../../src/systems/vrm/vrm-customizer";
import type { MaterialOverride } from "../../../../src/systems/vrm/vrm-customization-types";

export type MaterialsTabState = {
	readonly overrides: Map<string, MaterialOverride>;
};

export type MaterialsTab = {
	readonly element: HTMLElement;
	readonly state: MaterialsTabState;
	dispose(): void;
};

/**
 * Create the materials tab content. Each discovered material gets a row with
 * color picker + roughness/metalness sliders.
 */
export function createMaterialsTab(
	vrm: VRM,
	onChanged: () => void,
): MaterialsTab {
	const container = document.createElement("div");
	const materials = discoverMaterials(vrm);
	const overrides = new Map<string, MaterialOverride>();

	if (materials.length === 0) {
		const empty = document.createElement("div");
		empty.className = "vrm-editor-empty";
		empty.textContent = "No editable materials found";
		container.appendChild(empty);
		return { element: container, state: { overrides }, dispose() {} };
	}

	// Group materials by mesh name
	const groups = new Map<string, DiscoveredMaterial[]>();
	for (const mat of materials) {
		const group = groups.get(mat.meshName) ?? [];
		group.push(mat);
		groups.set(mat.meshName, group);
	}

	for (const [meshName, mats] of groups) {
		const section = document.createElement("div");
		section.className = "vrm-editor-section";

		const title = document.createElement("div");
		title.className = "vrm-editor-section-title";
		title.textContent = meshName;
		section.appendChild(title);

		for (const mat of mats) {
			const target = mat.materialName;

			// Color row
			const colorRow = createRow(mat.materialName, () => {
				const input = document.createElement("input");
				input.type = "color";
				input.value = mat.color;
				input.addEventListener("input", () => {
					updateOverride(target, { color: input.value });
					onChanged();
				});
				return input;
			});
			section.appendChild(colorRow);

			// Roughness row
			const roughnessRow = createSliderRow("Roughness", mat.roughness, 0, 1, 0.01, (val) => {
				updateOverride(target, { roughness: val });
				onChanged();
			});
			section.appendChild(roughnessRow);

			// Metalness row
			const metalnessRow = createSliderRow("Metalness", mat.metalness, 0, 1, 0.01, (val) => {
				updateOverride(target, { metalness: val });
				onChanged();
			});
			section.appendChild(metalnessRow);
		}

		container.appendChild(section);
	}

	function updateOverride(target: string, partial: Partial<MaterialOverride>) {
		const existing = overrides.get(target) ?? { target };
		overrides.set(target, { ...existing, ...partial } as MaterialOverride);
	}

	return {
		element: container,
		state: { overrides },
		dispose() {
			container.remove();
		},
	};
}

function createRow(label: string, createInput: () => HTMLElement): HTMLElement {
	const row = document.createElement("div");
	row.className = "vrm-editor-row";

	const labelEl = document.createElement("span");
	labelEl.className = "vrm-editor-label";
	labelEl.textContent = label;
	row.appendChild(labelEl);

	row.appendChild(createInput());
	return row;
}

function createSliderRow(
	label: string,
	value: number,
	min: number,
	max: number,
	step: number,
	onChange: (value: number) => void,
): HTMLElement {
	const row = document.createElement("div");
	row.className = "vrm-editor-row";

	const labelEl = document.createElement("span");
	labelEl.className = "vrm-editor-label";
	labelEl.textContent = label;
	row.appendChild(labelEl);

	const input = document.createElement("input");
	input.type = "range";
	input.min = String(min);
	input.max = String(max);
	input.step = String(step);
	input.value = String(value);
	row.appendChild(input);

	const valueEl = document.createElement("span");
	valueEl.className = "vrm-editor-value";
	valueEl.textContent = value.toFixed(2);
	row.appendChild(valueEl);

	input.addEventListener("input", () => {
		const val = parseFloat(input.value);
		valueEl.textContent = val.toFixed(2);
		onChange(val);
	});

	return row;
}
