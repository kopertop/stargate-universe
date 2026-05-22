/**
 * One-shot BVH → VRMA (uses vrm-c/bvh2vrma conversion logic in ./bvh-converter/).
 *
 * Usage: bun scripts/convert-bvh-to-vrma.ts <input.bvh> <output.vrma>
 */
import { writeFileSync } from "node:fs";
import { convertBvhFileToBuffer } from "./bvh-converter/convertBvhFile.ts";

const bvhPath = process.argv[2];
const outPath = process.argv[3];
if (!bvhPath || !outPath) {
	console.error("Usage: bun scripts/convert-bvh-to-vrma.ts <input.bvh> <output.vrma>");
	process.exit(1);
}

const buffer = await convertBvhFileToBuffer(bvhPath);
writeFileSync(outPath, Buffer.from(buffer));
console.log(`Wrote ${outPath} (${buffer.byteLength} bytes)`);
