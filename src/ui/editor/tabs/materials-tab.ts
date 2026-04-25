/**
 * Materials Tab — color pickers and PBR sliders for each VRM material.
 */
import type { VRM } from "@pixiv/three-vrm";
import { discoverMaterials, type DiscoveredMaterial } from "../../../systems/vrm/vrm-customizer";
import type { MaterialOverride } from "../../../systems/vrm/vrm-customization-types";

export type MaterialsTabState = {
	readonly overrides: Map<string, MaterialOverride>;
};

export type MaterialsTab = {
	readonly element: HTMLElement;
	readonly state: MaterialsTabState;
	hydrateOverrides(saved: readonly MaterialOverride[]): void;
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
		return {
			element: container,
			state: { overrides },
			hydrateOverrides() {},
			dispose() { container.remove(); },
		};
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
		hydrateOverrides(saved: readonly MaterialOverride[]) {
			for (const override of saved) {
				overrides.set(override.target, override);
				// Sync color input
				if (override.color) {
					const colorInput = container.querySelector<HTMLInputElement>(
						`[id="${CSS.escape(override.target)}"] input[type="color"]`,
					);
					if (colorInput) colorInput.value = override.color;
				}
				// Sync roughness and metalness sliders by scanning row labels
				const allRows = container.querySelectorAll<HTMLElement>(".vrm-editor-section");
				for (const sec of allRows) {
					const rows = sec.querySelectorAll<HTMLElement>(".vrm-editor-row");
					for (const row of rows) {
						const lbl = row.querySelector(".vrm-editor-label");
						if (!lbl) continue;
						const slider = row.querySelector<HTMLInputElement>("input[type=range]");
						if (!slider) continue;
						if (override.roughness !== undefined && lbl.textContent === "Roughness") {
							slider.value = String(override.roughness);
							const valEl = row.querySelector(".vrm-editor-value");
							if (valEl) valEl.textContent = override.roughness.toFixed(2);
						}
						if (override.metalness !== undefined && lbl.textContent === "Metalness") {
							slider.value = String(override.metalness);
							const valEl = row.querySelector(".vrm-editor-value");
							if (valEl) valEl.textContent = override.metalness.toFixed(2);
						}
					}
				}
			}
		},
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

	const inputWrap = document.createElement("span");
	inputWrap.id = label;
	inputWrap.appendChild(createInput());
	row.appendChild(inputWrap);

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
