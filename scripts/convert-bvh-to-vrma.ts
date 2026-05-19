/**
 * One-shot ACCAD BVH → VRMA (uses vrm-c/bvh2vrma conversion logic in ./bvh-converter/).
 *
 * Usage: bun scripts/convert-bvh-to-vrma.ts <input.bvh> <output.vrma>
 */
import { Window } from "happy-dom";
import { readFileSync, writeFileSync } from "node:fs";

const dom = new Window();
globalThis.window = dom as unknown as Window & typeof globalThis;
globalThis.document = dom.document;
globalThis.FileReader = dom.FileReader;
globalThis.Blob = dom.Blob;
import { BVHLoader } from "three/examples/jsm/loaders/BVHLoader.js";
import { convertBVHToVRMAnimation } from "./bvh-converter/convertBVHToVRMAnimation.ts";

const bvhPath = process.argv[2];
const outPath = process.argv[3];
if (!bvhPath || !outPath) {
	console.error("Usage: bun scripts/convert-bvh-to-vrma.ts <input.bvh> <output.vrma>");
	process.exit(1);
}

const text = readFileSync(bvhPath, "utf8");
const loader = new BVHLoader();
const bvh = loader.parse(text);
const buffer = await convertBVHToVRMAnimation(bvh);
writeFileSync(outPath, Buffer.from(buffer));
console.log(`Wrote ${outPath} (${buffer.byteLength} bytes)`);
