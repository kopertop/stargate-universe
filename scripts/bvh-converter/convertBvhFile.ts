/**
 * Shared ACCAD / Mixamo BVH → VRMA buffer conversion (vrm-c/bvh2vrma logic).
 */
import { Window } from "happy-dom";
import { readFileSync } from "node:fs";
import { BVHLoader } from "three/examples/jsm/loaders/BVHLoader.js";
import { convertBVHToVRMAnimation } from "./convertBVHToVRMAnimation.ts";

let domReady = false;

const ensureDom = (): void => {
	if (domReady) return;
	const dom = new Window();
	globalThis.window = dom as unknown as Window & typeof globalThis;
	globalThis.document = dom.document;
	globalThis.FileReader = dom.FileReader;
	globalThis.Blob = dom.Blob;
	domReady = true;
};

/** Parse a `.bvh` file and return encoded VRMA bytes. */
export const convertBvhFileToBuffer = async (bvhPath: string): Promise<ArrayBuffer> => {
	ensureDom();
	const text = readFileSync(bvhPath, "utf8");
	const loader = new BVHLoader();
	const bvh = loader.parse(text);
	return convertBVHToVRMAnimation(bvh);
};
