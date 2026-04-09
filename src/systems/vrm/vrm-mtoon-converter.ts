/**
 * MToon → PBR Material Converter — converts VRM's MToon toon shader materials
 * to PBR-equivalent `MeshStandardMaterial` for WebGPU render consistency.
 *
 * Destiny's aesthetic is dark and realistic (submarine-like). MToon's toon
 * shading doesn't match. This converter remaps MToon color/texture properties
 * to PBR parameters so characters blend naturally with the ship environment.
 *
 * @see design/gdd/vrm-model-integration.md §Edge Cases > VRM with MToon shader
 * @see docs/architecture/adr-004-vrm-models.md §Consequences > MToon shader
 */
import {
	Color,
	MeshStandardMaterial,
	type Material,
	type Mesh,
	type Object3D,
	type SkinnedMesh,
	type Texture,
} from "three";

// ─── Types ──────────────────────────────────────────────────────────────────

type MToonLikeMaterial = Material & {
	isMToonMaterial?: boolean;
	color?: Color;
	map?: Texture | null;
	normalMap?: Texture | null;
	normalScale?: { x: number; y: number };
	emissive?: Color;
	emissiveMap?: Texture | null;
	emissiveIntensity?: number;
	shadeColorFactor?: Color;
	shadeMultiplyTexture?: Texture | null;
	outlineWidthMode?: string;
	transparent?: boolean;
	opacity?: number;
	alphaTest?: number;
	side?: number;
};

type ConversionResult = {
	readonly converted: number;
	readonly skipped: number;
	readonly errors: string[];
};

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Convert all MToon materials in a VRM scene graph to PBR equivalents.
 * Modifies materials in-place on mesh objects.
 *
 * @param root       The VRM scene root (`vrm.scene`)
 * @param materials  The VRM's materials array (`vrm.materials`)
 * @returns          Conversion result with counts and any errors
 */
export function convertMToonToPBR(
	root: Object3D,
	materials?: Material[]
): ConversionResult {
	const result: ConversionResult = { converted: 0, skipped: 0, errors: [] };
	const converted = new Map<Material, MeshStandardMaterial>();

	root.traverse((child) => {
		const mesh = child as Mesh | SkinnedMesh;

		if (!mesh.isMesh) return;

		if (Array.isArray(mesh.material)) {
			mesh.material = mesh.material.map((mat) =>
				convertSingleMaterial(mat, converted, result)
			);
		} else {
			mesh.material = convertSingleMaterial(mesh.material, converted, result);
		}
	});

	// Also update the VRM materials array if provided
	if (materials) {
		for (let i = 0; i < materials.length; i++) {
			const replacement = converted.get(materials[i]);

			if (replacement) {
				materials[i] = replacement;
			}
		}
	}

	if (result.converted > 0) {
		console.info(
			`[MToonConverter] Converted ${result.converted} MToon materials to PBR ` +
			`(${result.skipped} already PBR)`
		);
	}

	return result;
}

// ─── Internal ───────────────────────────────────────────────────────────────

function convertSingleMaterial(
	material: Material,
	cache: Map<Material, MeshStandardMaterial>,
	result: { converted: number; skipped: number; errors: string[] }
): Material {
	// Already converted
	const cached = cache.get(material);
	if (cached) return cached;

	// Check if it's actually MToon
	const mtoon = material as MToonLikeMaterial;

	if (!isMToonMaterial(mtoon)) {
		result.skipped++;
		return material;
	}

	try {
		const pbr = createPBRFromMToon(mtoon);
		cache.set(material, pbr);
		result.converted++;

		// Dispose original MToon material
		material.dispose();

		return pbr;
	} catch (error) {
		const msg = `Failed to convert material "${material.name}": ${error}`;
		result.errors.push(msg);
		console.warn(`[MToonConverter] ${msg}`);
		return material; // Keep original on failure
	}
}

function isMToonMaterial(material: MToonLikeMaterial): boolean {
	// Check for MToon-specific properties
	return (
		material.isMToonMaterial === true ||
		material.type === "ShaderMaterial" && material.shadeColorFactor !== undefined
	);
}

/**
 * Ensure all MeshStandardMaterial on a VRM look non-metallic and matte.
 * Call after MToon conversion. Fixes VRM models that already use PBR but
 * have overly shiny/metallic settings that don't suit the game's look.
 */
export function flattenVrmMaterials(root: Object3D): void {
	root.traverse((child) => {
		const mesh = child as Mesh | SkinnedMesh;
		if (!mesh.isMesh) return;

		const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
		for (const mat of mats) {
			const std = mat as MeshStandardMaterial & { isMeshStandardMaterial?: boolean };
			if (!std.isMeshStandardMaterial) continue;

			// Force non-metallic, high roughness for character materials
			std.metalness = Math.min(std.metalness, 0.05);
			std.roughness = Math.max(std.roughness, 0.7);
			std.needsUpdate = true;
		}
	});
}

function createPBRFromMToon(mtoon: MToonLikeMaterial): MeshStandardMaterial {
	const pbr = new MeshStandardMaterial();

	// Transfer name
	pbr.name = mtoon.name ? `${mtoon.name}_PBR` : "VRM_PBR";

	// Base color
	if (mtoon.color) {
		pbr.color.copy(mtoon.color);
	}

	// Diffuse texture (albedo map)
	if (mtoon.map) {
		pbr.map = mtoon.map;
	}

	// Normal map
	if (mtoon.normalMap) {
		pbr.normalMap = mtoon.normalMap;

		if (mtoon.normalScale) {
			pbr.normalScale.set(mtoon.normalScale.x, mtoon.normalScale.y);
		}
	}

	// Emissive
	if (mtoon.emissive) {
		pbr.emissive.copy(mtoon.emissive);
	}

	if (mtoon.emissiveMap) {
		pbr.emissiveMap = mtoon.emissiveMap;
	}

	pbr.emissiveIntensity = mtoon.emissiveIntensity ?? 0;

	// Derive roughness from MToon shade color:
	// Darker shade color → more diffuse → higher roughness
	// Lighter shade color → more specular → lower roughness
	if (mtoon.shadeColorFactor) {
		const shadeLuminance =
			mtoon.shadeColorFactor.r * 0.299 +
			mtoon.shadeColorFactor.g * 0.587 +
			mtoon.shadeColorFactor.b * 0.114;

		// Map shade luminance to roughness: darker shade = higher roughness
		pbr.roughness = 0.4 + (1 - shadeLuminance) * 0.4;
	} else {
		pbr.roughness = 0.65;
	}

	// Characters aren't metallic (skin, fabric, hair)
	pbr.metalness = 0.0;

	// Transparency
	if (mtoon.transparent) {
		pbr.transparent = true;
		pbr.opacity = mtoon.opacity ?? 1.0;
	}

	if (mtoon.alphaTest !== undefined && mtoon.alphaTest > 0) {
		pbr.alphaTest = mtoon.alphaTest;
	}

	// Face rendering side
	if (mtoon.side !== undefined) {
		pbr.side = mtoon.side;
	}

	// Shadows
	pbr.shadowSide = pbr.side;

	return pbr;
}
