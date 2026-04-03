import { describe, expect, it } from "vitest";
import {
	Color,
	Group,
	Mesh,
	MeshBasicMaterial,
	MeshStandardMaterial,
	PlaneGeometry,
} from "three";
import { convertMToonToPBR } from "../../../src/systems/vrm/vrm-mtoon-converter";

function createMockMToonMaterial(overrides: Record<string, unknown> = {}) {
	const mat = new MeshBasicMaterial() as unknown as Record<string, unknown>;
	mat["isMToonMaterial"] = true;
	mat["type"] = "ShaderMaterial";
	mat["color"] = new Color(0.8, 0.6, 0.4);
	mat["shadeColorFactor"] = new Color(0.3, 0.2, 0.1);
	mat["emissive"] = new Color(0, 0, 0);
	mat["emissiveIntensity"] = 0;
	mat["name"] = "TestMToon";
	Object.assign(mat, overrides);
	return mat as unknown as MeshStandardMaterial;
}

describe("MToon to PBR Converter", () => {
	it("converts MToon materials on meshes", () => {
		const root = new Group();
		const mesh = new Mesh(
			new PlaneGeometry(1, 1),
			createMockMToonMaterial()
		);
		root.add(mesh);

		const result = convertMToonToPBR(root);
		expect(result.converted).toBe(1);
		expect(result.skipped).toBe(0);
		expect(result.errors).toHaveLength(0);

		const newMat = mesh.material as MeshStandardMaterial;
		expect(newMat.isMeshStandardMaterial).toBe(true);
		expect(newMat.name).toBe("TestMToon_PBR");
	});

	it("skips non-MToon materials", () => {
		const root = new Group();
		const mesh = new Mesh(
			new PlaneGeometry(1, 1),
			new MeshStandardMaterial({ color: "red" })
		);
		root.add(mesh);

		const result = convertMToonToPBR(root);
		expect(result.converted).toBe(0);
		expect(result.skipped).toBe(1);
	});

	it("handles mixed material array on a mesh", () => {
		const root = new Group();
		const mesh = new Mesh(new PlaneGeometry(1, 1), [
			createMockMToonMaterial({ name: "Hair" }),
			new MeshStandardMaterial({ color: "blue", name: "Eye" }),
		]);
		root.add(mesh);

		const result = convertMToonToPBR(root);
		expect(result.converted).toBe(1);
		expect(result.skipped).toBe(1);
	});

	it("derives roughness from shade color", () => {
		const root = new Group();
		// Dark shade → higher roughness (more diffuse)
		const darkShade = new Mesh(
			new PlaneGeometry(1, 1),
			createMockMToonMaterial({ shadeColorFactor: new Color(0.1, 0.1, 0.1) })
		);
		root.add(darkShade);

		convertMToonToPBR(root);
		const mat = darkShade.material as MeshStandardMaterial;
		expect(mat.roughness).toBeGreaterThan(0.7);
	});

	it("sets metalness to 0 (characters are non-metallic)", () => {
		const root = new Group();
		const mesh = new Mesh(new PlaneGeometry(1, 1), createMockMToonMaterial());
		root.add(mesh);

		convertMToonToPBR(root);
		const mat = mesh.material as MeshStandardMaterial;
		expect(mat.metalness).toBe(0);
	});

	it("handles empty scene graph", () => {
		const root = new Group();
		const result = convertMToonToPBR(root);
		expect(result.converted).toBe(0);
		expect(result.skipped).toBe(0);
	});

	it("caches converted materials for reuse", () => {
		const root = new Group();
		const sharedMaterial = createMockMToonMaterial();
		root.add(new Mesh(new PlaneGeometry(1, 1), sharedMaterial));
		root.add(new Mesh(new PlaneGeometry(1, 1), sharedMaterial));

		const result = convertMToonToPBR(root);
		// Only counted once even though two meshes share the material
		expect(result.converted).toBe(1);

		// Both meshes should now have the same PBR material instance
		const mat1 = (root.children[0] as Mesh).material;
		const mat2 = (root.children[1] as Mesh).material;
		expect(mat1).toBe(mat2);
	});

	it("updates materials array when provided", () => {
		const root = new Group();
		const mtoonMat = createMockMToonMaterial();
		const pbrMat = new MeshStandardMaterial();
		root.add(new Mesh(new PlaneGeometry(1, 1), mtoonMat));

		const materials = [mtoonMat as unknown as MeshStandardMaterial, pbrMat];
		convertMToonToPBR(root, materials);

		expect((materials[0] as MeshStandardMaterial).isMeshStandardMaterial).toBe(true);
		expect(materials[1]).toBe(pbrMat); // Unchanged
	});
});
