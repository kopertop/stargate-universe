#!/usr/bin/env node
/**
 * generate-crew-vrm.mjs
 * Creates minimal-but-valid VRM 1.0 GLB placeholder files for the SGU crew.
 * Each file has a proper VRM 1.0 humanoid skeleton + box-mesh body parts
 * with character-specific materials (skin tone, hair, clothing).
 *
 * Usage: node scripts/generate-crew-vrm.mjs
 *
 * Generated files go to: public/assets/characters/{id}/{id}.vrm
 * Only generates files that don't already exist.
 */

import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CHARS_DIR = join(__dirname, '..', 'public', 'assets', 'characters');

// ─────────────────────────────────────────────────────────────────────────────
//  Character Definitions
// ─────────────────────────────────────────────────────────────────────────────

const CHARACTERS = [
	{
		id: 'everett-young',
		name: 'Colonel Everett Young',
		gender: 'male',
		skinTone:      [0.80, 0.65, 0.53],
		hairColor:     [0.15, 0.10, 0.06],
		clothingColor: [0.14, 0.16, 0.18],  // SGU dark-grey uniform
	},
	{
		id: 'matthew-scott',
		name: 'Lt. Matthew Scott',
		gender: 'male',
		skinTone:      [0.82, 0.67, 0.52],
		hairColor:     [0.10, 0.07, 0.04],
		clothingColor: [0.14, 0.16, 0.18],
	},
	{
		id: 'chloe-armstrong',
		name: 'Chloe Armstrong',
		gender: 'female',
		skinTone:      [0.94, 0.80, 0.66],
		hairColor:     [0.05, 0.03, 0.02],
		clothingColor: [0.38, 0.32, 0.27],  // civilian warm-brown
	},
	{
		id: 'ronald-greer',
		name: 'MSgt. Ronald Greer',
		gender: 'male',
		skinTone:      [0.33, 0.24, 0.18],
		hairColor:     [0.07, 0.05, 0.03],  // very dark (close-cropped)
		clothingColor: [0.14, 0.16, 0.18],
	},
	{
		id: 'tamara-johansen',
		name: 'TJ (Tamara Johansen)',
		gender: 'female',
		skinTone:      [0.88, 0.74, 0.60],
		hairColor:     [0.48, 0.33, 0.18],  // auburn-brown
		clothingColor: [0.14, 0.16, 0.18],
	},
];

// ─────────────────────────────────────────────────────────────────────────────
//  Geometry Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Build a box mesh from world-space AABB bounds.
 * Uses 24 unique vertices (4 per face) so face normals are correct.
 * Returns { positions: Float32Array, normals: Float32Array, indices: Uint16Array }
 */
function makeBox(minX, maxX, minY, maxY, minZ, maxZ) {
	const cx = (minX + maxX) / 2;
	const cy = (minY + maxY) / 2;
	const cz = (minZ + maxZ) / 2;
	const hx = (maxX - minX) / 2;
	const hy = (maxY - minY) / 2;
	const hz = (maxZ - minZ) / 2;

	// 6 faces × 4 vertices = 24 vertices
	const p = [cx, cy, cz];
	const positions = new Float32Array([
		// +Z (front)
		cx-hx, cy-hy, cz+hz,  cx+hx, cy-hy, cz+hz,  cx+hx, cy+hy, cz+hz,  cx-hx, cy+hy, cz+hz,
		// -Z (back)
		cx+hx, cy-hy, cz-hz,  cx-hx, cy-hy, cz-hz,  cx-hx, cy+hy, cz-hz,  cx+hx, cy+hy, cz-hz,
		// +X (right / char's right, world +X)
		cx+hx, cy-hy, cz+hz,  cx+hx, cy-hy, cz-hz,  cx+hx, cy+hy, cz-hz,  cx+hx, cy+hy, cz+hz,
		// -X (left)
		cx-hx, cy-hy, cz-hz,  cx-hx, cy-hy, cz+hz,  cx-hx, cy+hy, cz+hz,  cx-hx, cy+hy, cz-hz,
		// +Y (top)
		cx-hx, cy+hy, cz+hz,  cx+hx, cy+hy, cz+hz,  cx+hx, cy+hy, cz-hz,  cx-hx, cy+hy, cz-hz,
		// -Y (bottom)
		cx-hx, cy-hy, cz-hz,  cx+hx, cy-hy, cz-hz,  cx+hx, cy-hy, cz+hz,  cx-hx, cy-hy, cz+hz,
	]);

	const normals = new Float32Array([
		 0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1,
		 0, 0,-1,  0, 0,-1,  0, 0,-1,  0, 0,-1,
		 1, 0, 0,  1, 0, 0,  1, 0, 0,  1, 0, 0,
		-1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0,
		 0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0,
		 0,-1, 0,  0,-1, 0,  0,-1, 0,  0,-1, 0,
	]);

	// 6 faces × 2 triangles × 3 indices = 36
	const indices = new Uint16Array([
		 0, 1, 2,  0, 2, 3,   // +Z
		 4, 5, 6,  4, 6, 7,   // -Z
		 8, 9,10,  8,10,11,   // +X
		12,13,14, 12,14,15,   // -X
		16,17,18, 16,18,19,   // +Y
		20,21,22, 20,22,23,   // -Y
	]);

	return { positions, normals, indices };
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLB Binary Encoding
// ─────────────────────────────────────────────────────────────────────────────

const pad4 = (n) => (n + 3) & ~3;

/**
 * Encode a glTF JSON + optional binary chunk into a GLB buffer.
 */
function encodeGLB(gltfJson, binBuffer) {
	// JSON chunk — padded to 4-byte boundary with spaces
	let jsonStr = JSON.stringify(gltfJson);
	while (jsonStr.length % 4 !== 0) jsonStr += ' ';
	const jsonBytes = Buffer.from(jsonStr, 'utf8');

	const JSON_MAGIC = 0x4E4F534A; // "JSON"
	const BIN_MAGIC  = 0x004E4942; // "BIN\0"

	const jsonHeader = Buffer.alloc(8);
	jsonHeader.writeUInt32LE(jsonBytes.length, 0);
	jsonHeader.writeUInt32LE(JSON_MAGIC, 4);

	const parts = [jsonHeader, jsonBytes];
	let totalLen = 12 + 8 + jsonBytes.length;

	if (binBuffer && binBuffer.length > 0) {
		const binLen = binBuffer.length;
		const binPadded = pad4(binLen);
		const binData = binPadded > binLen
			? Buffer.concat([binBuffer, Buffer.alloc(binPadded - binLen, 0x00)])
			: binBuffer;

		const binHeader = Buffer.alloc(8);
		binHeader.writeUInt32LE(binPadded, 0);
		binHeader.writeUInt32LE(BIN_MAGIC, 4);

		parts.push(binHeader, binData);
		totalLen += 8 + binPadded;
	}

	const glbHeader = Buffer.alloc(12);
	glbHeader.writeUInt32LE(0x46546C67, 0); // magic "glTF"
	glbHeader.writeUInt32LE(2, 4);           // version 2
	glbHeader.writeUInt32LE(totalLen, 8);

	return Buffer.concat([glbHeader, ...parts]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  VRM Character Builder
// ─────────────────────────────────────────────────────────────────────────────

function buildCharacterVRM(char) {
	const isFemale = char.gender === 'female';

	// ── Body Part Geometry (world-space T-pose) ──────────────────────────────
	// Material indices: 0=skin, 1=clothing, 2=hair
	const tw = isFemale ? 0.13 : 0.155; // torso half-width
	const td = 0.105;                    // torso half-depth
	const sw = isFemale ? 0.15 : 0.19;  // shoulder half-width

	const SKIN = 0, CLOTH = 1, HAIR = 2;

	const parts = [
		// Torso / pelvis
		{ mat: CLOTH, geom: makeBox(-tw,       tw,       1.05, 1.42, -td,      td) },
		{ mat: CLOTH, geom: makeBox(-tw*1.08,  tw*1.08,  0.86, 1.05, -td*0.9,  td*0.9) },
		// Left arm: upper (sleeve) + lower (skin) + hand
		{ mat: CLOTH, geom: makeBox( tw,        tw+sw*0.72, 1.13, 1.38, -0.063, 0.063) },
		{ mat: SKIN,  geom: makeBox( tw+sw*0.2, tw+sw*0.80, 0.83, 1.13, -0.053, 0.053) },
		{ mat: SKIN,  geom: makeBox( tw+sw*0.18,tw+sw*0.72, 0.66, 0.83, -0.042, 0.042) },
		// Right arm: upper + lower + hand
		{ mat: CLOTH, geom: makeBox(-(tw+sw*0.72), -tw,        1.13, 1.38, -0.063, 0.063) },
		{ mat: SKIN,  geom: makeBox(-(tw+sw*0.80), -(tw+sw*0.2), 0.83, 1.13, -0.053, 0.053) },
		{ mat: SKIN,  geom: makeBox(-(tw+sw*0.72), -(tw+sw*0.18),0.66, 0.83, -0.042, 0.042) },
		// Left leg: upper + lower + foot
		{ mat: CLOTH, geom: makeBox( 0.018, 0.175, 0.45, 0.87, -0.088, 0.088) },
		{ mat: CLOTH, geom: makeBox( 0.020, 0.158, 0.07, 0.45, -0.072, 0.072) },
		{ mat: CLOTH, geom: makeBox( 0.015, 0.162, 0.00, 0.07, -0.040, 0.138) },
		// Right leg: upper + lower + foot
		{ mat: CLOTH, geom: makeBox(-0.175, -0.018, 0.45, 0.87, -0.088, 0.088) },
		{ mat: CLOTH, geom: makeBox(-0.158, -0.020, 0.07, 0.45, -0.072, 0.072) },
		{ mat: CLOTH, geom: makeBox(-0.162, -0.015, 0.00, 0.07, -0.040, 0.138) },
		// Neck
		{ mat: SKIN,  geom: makeBox(-0.040,  0.040, 1.42, 1.55, -0.038, 0.038) },
		// Head
		{ mat: SKIN,  geom: makeBox(-0.090,  0.090, 1.55, 1.74, -0.088, 0.088) },
		// Hair cap (slightly oversized on top / sides)
		{ mat: HAIR,  geom: makeBox(-0.095,  0.095, 1.70, 1.77, -0.092, 0.092) },
	];

	// ── Bone Hierarchy (VRM 1.0 required humanoid bones) ────────────────────
	// Node indices 0–16 = bones, 17 = meshNode.
	// All translations are LOCAL (parent-relative).
	//
	//   Hierarchy:
	//     0: hips → [1, 11, 14]
	//       1: spine → [2]
	//         2: chest → [3, 5, 8]
	//           3: neck → [4]
	//             4: head
	//           5: leftUpperArm → [6]
	//             6: leftLowerArm → [7]
	//               7: leftHand
	//           8: rightUpperArm → [9]
	//             9: rightLowerArm → [10]
	//              10: rightHand
	//      11: leftUpperLeg → [12]
	//           12: leftLowerLeg → [13]
	//             13: leftFoot
	//      14: rightUpperLeg → [15]
	//           15: rightLowerLeg → [16]
	//             16: rightFoot

	const boneNodes = [
		// 0  hips (root of skeleton, world Y≈0.97)
		{ name: 'hips',          translation: [0,      0.97,  0], children: [1, 11, 14] },
		// 1  spine
		{ name: 'spine',         translation: [0,      0.08,  0], children: [2] },
		// 2  chest
		{ name: 'chest',         translation: [0,      0.22,  0], children: [3, 5, 8] },
		// 3  neck
		{ name: 'neck',          translation: [0,      0.18,  0], children: [4] },
		// 4  head
		{ name: 'head',          translation: [0,      0.13,  0] },
		// 5  leftUpperArm  — +X is character's left in VRM convention
		{ name: 'leftUpperArm',  translation: [ 0.19,  0.00,  0], children: [6] },
		// 6  leftLowerArm
		{ name: 'leftLowerArm',  translation: [ 0.29,  0.00,  0], children: [7] },
		// 7  leftHand
		{ name: 'leftHand',      translation: [ 0.25,  0.00,  0] },
		// 8  rightUpperArm  — -X is character's right
		{ name: 'rightUpperArm', translation: [-0.19,  0.00,  0], children: [9] },
		// 9  rightLowerArm
		{ name: 'rightLowerArm', translation: [-0.29,  0.00,  0], children: [10] },
		// 10 rightHand
		{ name: 'rightHand',     translation: [-0.25,  0.00,  0] },
		// 11 leftUpperLeg
		{ name: 'leftUpperLeg',  translation: [ 0.10, -0.10,  0], children: [12] },
		// 12 leftLowerLeg
		{ name: 'leftLowerLeg',  translation: [ 0,    -0.42,  0], children: [13] },
		// 13 leftFoot
		{ name: 'leftFoot',      translation: [ 0,    -0.38,  0] },
		// 14 rightUpperLeg
		{ name: 'rightUpperLeg', translation: [-0.10, -0.10,  0], children: [15] },
		// 15 rightLowerLeg
		{ name: 'rightLowerLeg', translation: [ 0,    -0.42,  0], children: [16] },
		// 16 rightFoot
		{ name: 'rightFoot',     translation: [ 0,    -0.38,  0] },
	];

	// 17: visual mesh node (separate from skeleton, both are top-level in scene)
	const meshNode = { name: `${char.id}-mesh`, mesh: 0 };

	const allNodes = [...boneNodes, meshNode];

	// ── Materials ────────────────────────────────────────────────────────────
	const [sr, sg, sb] = char.skinTone;
	const [cr, cg, cb] = char.clothingColor;
	const [hr, hg, hb] = char.hairColor;

	const materials = [
		{ name: 'skin',     pbrMetallicRoughness: { baseColorFactor: [sr, sg, sb, 1], metallicFactor: 0, roughnessFactor: 0.85 } },
		{ name: 'clothing', pbrMetallicRoughness: { baseColorFactor: [cr, cg, cb, 1], metallicFactor: 0, roughnessFactor: 0.95 } },
		{ name: 'hair',     pbrMetallicRoughness: { baseColorFactor: [hr, hg, hb, 1], metallicFactor: 0, roughnessFactor: 0.80 } },
	];

	// ── Pack Binary Buffer ────────────────────────────────────────────────────
	// Layout per primitive: [positions][normals][indices_padded]
	const geomLayout = [];
	let byteOffset = 0;

	for (const part of parts) {
		const { positions, normals, indices } = part.geom;
		const posBytes  = positions.byteLength; // 24 * 3 * 4 = 288
		const normBytes = normals.byteLength;   // 288
		const idxBytes  = indices.byteLength;   // 36 * 2 = 72
		const idxBytesP = pad4(idxBytes);       // 72 (already aligned)

		geomLayout.push({
			part,
			posBytes, normBytes, idxBytes, idxBytesP,
			posOff:  byteOffset,
			normOff: byteOffset + posBytes,
			idxOff:  byteOffset + posBytes + normBytes,
		});
		byteOffset += posBytes + normBytes + idxBytesP;
	}

	const binBuffer = Buffer.alloc(byteOffset);

	for (const info of geomLayout) {
		const { positions, normals, indices } = info.part.geom;
		Buffer.from(positions.buffer, positions.byteOffset, positions.byteLength).copy(binBuffer, info.posOff);
		Buffer.from(normals.buffer,   normals.byteOffset,   normals.byteLength  ).copy(binBuffer, info.normOff);
		Buffer.from(indices.buffer,   indices.byteOffset,   indices.byteLength  ).copy(binBuffer, info.idxOff);
	}

	// ── Accessors & BufferViews ───────────────────────────────────────────────
	const bufferViews = [];
	const accessors   = [];
	const primitives  = [];

	for (const info of geomLayout) {
		// POSITION
		const bvPos = bufferViews.length;
		bufferViews.push({ buffer: 0, byteOffset: info.posOff, byteLength: info.posBytes, target: 34962 });

		const pos = info.part.geom.positions;
		let minP = [Infinity, Infinity, Infinity];
		let maxP = [-Infinity, -Infinity, -Infinity];
		for (let i = 0; i < pos.length; i += 3) {
			if (pos[i]   < minP[0]) minP[0] = pos[i];
			if (pos[i+1] < minP[1]) minP[1] = pos[i+1];
			if (pos[i+2] < minP[2]) minP[2] = pos[i+2];
			if (pos[i]   > maxP[0]) maxP[0] = pos[i];
			if (pos[i+1] > maxP[1]) maxP[1] = pos[i+1];
			if (pos[i+2] > maxP[2]) maxP[2] = pos[i+2];
		}
		const accPos = accessors.length;
		accessors.push({ bufferView: bvPos, byteOffset: 0, componentType: 5126, count: 24, type: 'VEC3', min: minP, max: maxP });

		// NORMAL
		const bvNorm = bufferViews.length;
		bufferViews.push({ buffer: 0, byteOffset: info.normOff, byteLength: info.normBytes, target: 34962 });
		const accNorm = accessors.length;
		accessors.push({ bufferView: bvNorm, byteOffset: 0, componentType: 5126, count: 24, type: 'VEC3' });

		// INDEX
		const bvIdx = bufferViews.length;
		bufferViews.push({ buffer: 0, byteOffset: info.idxOff, byteLength: info.idxBytes, target: 34963 });
		const accIdx = accessors.length;
		accessors.push({ bufferView: bvIdx, byteOffset: 0, componentType: 5123, count: 36, type: 'SCALAR' });

		primitives.push({
			attributes: { POSITION: accPos, NORMAL: accNorm },
			indices: accIdx,
			material: info.part.mat,
		});
	}

	// ── glTF JSON ─────────────────────────────────────────────────────────────
	const gltf = {
		asset: {
			version: '2.0',
			generator: `SGU Crew Generator — ${char.name}`,
		},
		extensionsUsed: ['VRMC_vrm'],
		extensions: {
			VRMC_vrm: {
				specVersion: '1.0',
				meta: {
					name:    char.name,
					version: '1.0',
					authors: ['SGU Game — Auto-Generated Placeholder'],
					licenseUrl: 'https://vrm.dev/licenses/1.0/',
					avatarPermission:             'onlyAuthor',
					allowExcessivelySexualUsage:  false,
					allowExcessivelyViolentUsage: false,
					allowPoliticalOrReligiousUsage: false,
					allowAntisocialOrHateUsage:   false,
					creditNotation:               'unnecessary',
					allowRedistribution:          false,
					modification:                 'prohibited',
				},
				humanoid: {
					humanBones: {
						hips:          { node:  0 },
						spine:         { node:  1 },
						chest:         { node:  2 },
						neck:          { node:  3 },
						head:          { node:  4 },
						leftUpperArm:  { node:  5 },
						leftLowerArm:  { node:  6 },
						leftHand:      { node:  7 },
						rightUpperArm: { node:  8 },
						rightLowerArm: { node:  9 },
						rightHand:     { node: 10 },
						leftUpperLeg:  { node: 11 },
						leftLowerLeg:  { node: 12 },
						leftFoot:      { node: 13 },
						rightUpperLeg: { node: 14 },
						rightLowerLeg: { node: 15 },
						rightFoot:     { node: 16 },
					},
				},
			},
		},
		scene: 0,
		// Both the skeleton root (hips, node 0) and the visual mesh node (17) are
		// top-level scene nodes. The VRM loader traverses nodes for bone queries;
		// the mesh node provides the visible geometry independently.
		scenes: [{ name: 'Scene', nodes: [0, 17] }],
		nodes: allNodes,
		meshes: [{ name: `${char.id}-body`, primitives }],
		materials,
		accessors,
		bufferViews,
		buffers: [{ byteLength: byteOffset }],
	};

	return encodeGLB(gltf, binBuffer);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────

console.log('SGU Crew VRM Generator\n' + '─'.repeat(40));

let generated = 0;
let skipped   = 0;

for (const char of CHARACTERS) {
	const charDir = join(CHARS_DIR, char.id);
	const outPath = join(charDir, `${char.id}.vrm`);

	if (existsSync(outPath)) {
		console.log(`  ⚠  skip  ${char.name}  (already exists)`);
		skipped++;
		continue;
	}

	mkdirSync(charDir, { recursive: true });

	try {
		const glb = buildCharacterVRM(char);
		writeFileSync(outPath, glb);
		const sizeKB = (glb.length / 1024).toFixed(1);
		console.log(`  ✓  wrote ${char.name}  →  ${char.id}.vrm  (${sizeKB} KB)`);
		generated++;
	} catch (err) {
		console.error(`  ✗  ERROR ${char.name}: ${err.message}`);
		console.error(err.stack);
	}
}

console.log(`\nDone: ${generated} generated, ${skipped} skipped.`);
