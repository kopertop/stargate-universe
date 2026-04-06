/**
 * Build Animation Bundle — CLI script
 *
 * Loads Mixamo FBX files, extracts skeleton + animation clips, and writes
 * the animation bundle files that the Vite plugin expects.
 *
 * This does programmatically what the Animation Studio UI does:
 * FBX → Three.js → ggez clip assets → compiled graph → bundle JSON
 *
 * Usage: bun run scripts/build-animation-bundle.ts
 */
// Polyfill browser globals that Three.js FBXLoader needs in Node/Bun
if (typeof globalThis.window === "undefined") {
	(globalThis as any).window = globalThis;
}
if (typeof globalThis.document === "undefined") {
	(globalThis as any).document = { createElementNS: () => ({}) };
}
if (typeof URL.createObjectURL === "undefined") {
	(URL as any).createObjectURL = (blob: Blob) => `blob:mock/${Math.random().toString(36).slice(2)}`;
}
if (typeof URL.revokeObjectURL === "undefined") {
	(URL as any).revokeObjectURL = () => {};
}
if (typeof globalThis.Blob === "undefined") {
	(globalThis as any).Blob = class MockBlob { constructor(public parts: any[], public options?: any) {} };
}
if (typeof globalThis.self === "undefined") {
	(globalThis as any).self = globalThis;
}
// Mock Image for texture loading (we don't need textures, just skeleton + animation)
if (typeof globalThis.Image === "undefined") {
	(globalThis as any).Image = class MockImage {
		width = 1; height = 1; src = "";
		addEventListener(event: string, fn: Function) { if (event === "load") setTimeout(() => fn(), 0); }
		removeEventListener() {}
	};
}
// Mock document.createElementNS more completely
(globalThis as any).document = {
	createElementNS(_ns: string, tag: string) {
		if (tag === "img") return new (globalThis as any).Image();
		if (tag === "canvas") return {
			width: 1, height: 1, style: {},
			getContext: () => ({
				drawImage() {}, getImageData: () => ({ data: new Uint8Array(4) }),
				fillRect() {}, canvas: { width: 1, height: 1, toDataURL: () => "data:" },
			}),
			toDataURL: () => "data:",
			addEventListener() {}, removeEventListener() {},
		};
		return {};
	},
	createElement(tag: string) {
		return this.createElementNS("", tag);
	},
};
if (typeof globalThis.atob === "undefined") {
	(globalThis as any).atob = (b64: string) => Buffer.from(b64, "base64").toString("binary");
}

import { createRigDefinition, type AnimationClipAsset } from "@ggez/anim-core";
import { createAnimationArtifact, serializeAnimationArtifact } from "@ggez/anim-exporter";
import { createClipAssetFromThreeClip, createRigFromSkeleton } from "@ggez/anim-three";
import { writeFileSync, mkdirSync } from "fs";
import { resolve } from "path";
import {
	AnimationClip,
	Bone,
	BufferGeometry,
	Loader,
	Matrix4,
	Quaternion,
	Skeleton,
	SkinnedMesh,
	Vector3,
} from "three";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";

// ─── Config ─────────────────────────────────────────────────────────────────

const BUNDLE_DIR = resolve(import.meta.dir, "../src/animations/player-locomotion");
const CLIPS = [
	{ id: "idle", name: "Idle", file: resolve(BUNDLE_DIR, "assets/idle.fbx") },
	{ id: "breathing-idle", name: "Breathing Idle", file: resolve(BUNDLE_DIR, "assets/breathing-idle.fbx") },
	{ id: "walking", name: "Walking", file: resolve(BUNDLE_DIR, "assets/walking.fbx") },
];

// ─── FBX Loading (Node.js) ──────────────────────────────────────────────────

async function loadFbxFile(filePath: string): Promise<{ root: any; animations: AnimationClip[] }> {
	const buffer = await Bun.file(filePath).arrayBuffer();

	// FBXLoader expects a path for texture resolution, but we only need animations
	const loader = new FBXLoader();

	// In Node/Bun, we need to parse the buffer directly
	const root = loader.parse(buffer, "");
	const animations = root.animations as AnimationClip[] ?? [];

	return { root, animations };
}

function findSkeleton(root: any): Skeleton | undefined {
	// Collect ALL bones from the hierarchy to get the complete skeleton
	const bones: Bone[] = [];

	root.traverse?.((child: any) => {
		if (child.isBone) {
			bones.push(child);
		}
	});

	if (bones.length > 0) {
		// Sort bones: root first (the one whose parent is not a bone)
		const rootBones = bones.filter((b) => !b.parent || !(b.parent as any).isBone);

		// Use DFS ordering from root bones for consistent bone indices.
		// Deduplicate by bone name — FBXLoader can create multiple bone objects
		// for the same logical bone (one per transform component).
		const ordered: Bone[] = [];
		const visited = new Set<Bone>();
		const seenNames = new Set<string>();

		function dfs(bone: Bone) {
			if (visited.has(bone)) return;
			visited.add(bone);

			// Only add if this bone name hasn't been seen yet
			if (!seenNames.has(bone.name)) {
				seenNames.add(bone.name);
				ordered.push(bone);
			}

			for (const child of bone.children) {
				if ((child as any).isBone) dfs(child as Bone);
			}
		}

		for (const root of rootBones) dfs(root);
		// Add any orphans
		for (const bone of bones) {
			if (!visited.has(bone) && !seenNames.has(bone.name)) {
				seenNames.add(bone.name);
				ordered.push(bone);
			}
		}

		root.updateMatrixWorld?.(true);

		const boneInverses = ordered.map((bone: Bone) => {
			const m = new Matrix4();
			bone.updateWorldMatrix(true, false);
			m.copy(bone.matrixWorld).invert();
			return m;
		});

		return new Skeleton(ordered, boneInverses);
	}

	// Fallback: try SkinnedMesh skeleton
	let skeleton: Skeleton | undefined;
	root.traverse?.((child: any) => {
		if (skeleton) return;
		if (child.isSkinnedMesh && child.skeleton) {
			skeleton = child.skeleton;
		}
	});

	return skeleton;
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
	console.log("🎬 Building animation bundle...\n");

	// Load all FBX files
	const loaded: Array<{
		id: string;
		name: string;
		clip: AnimationClip;
		skeleton: Skeleton;
	}> = [];

	for (const clipDef of CLIPS) {
		console.log(`  Loading ${clipDef.name} from ${clipDef.file}...`);

		try {
			const { root, animations } = await loadFbxFile(clipDef.file);

			if (animations.length === 0) {
				console.warn(`  ⚠ No animations found in ${clipDef.file}`);
				continue;
			}

			const skeleton = findSkeleton(root);

			if (!skeleton) {
				console.warn(`  ⚠ No skeleton found in ${clipDef.file}`);
				continue;
			}

			const clip = animations[0];
			clip.name = clipDef.name;

			console.log(`  ✓ ${clipDef.name}: ${clip.duration.toFixed(2)}s, ${clip.tracks.length} tracks, ${skeleton.bones.length} bones`);
			console.log(`    Bone names: ${skeleton.bones.slice(0, 5).map(b => b.name).join(", ")}...`);

			if (clip.tracks.length === 0) {
				console.warn(`  ⚠ Skipping "${clipDef.name}" — no animation tracks`);
				continue;
			}

			loaded.push({ id: clipDef.id, name: clipDef.name, clip, skeleton });
		} catch (error) {
			console.error(`  ✗ Failed to load ${clipDef.file}:`, error);
		}
	}

	if (loaded.length === 0) {
		console.error("\n✗ No clips loaded. Aborting.");
		process.exit(1);
	}

	// Use the first clip's skeleton as reference
	const refSkeleton = loaded[0].skeleton;
	const rig = createRigFromSkeleton(refSkeleton);

	console.log(`\n  Rig: ${rig.boneNames.length} bones, root: "${rig.boneNames[rig.rootBoneIndex]}"`);
	console.log(`  All bones: ${rig.boneNames.join(", ")}`);

	// Convert clips to ggez format
	const clipAssets: AnimationClipAsset[] = [];
	const clipSlots: Array<{ id: string; name: string; duration: number }> = [];

	for (const entry of loaded) {
		const clipAsset = createClipAssetFromThreeClip(entry.clip, refSkeleton);
		clipAssets.push(clipAsset);
		clipSlots.push({
			id: entry.id,
			name: entry.name,
			duration: entry.clip.duration,
		});

		console.log(`  Converted "${entry.name}" → ${clipAsset.tracks.length} bone tracks`);
	}

	// Build the compiled graph
	const compiledGraph = {
		version: 1 as const,
		name: "PlayerLocomotion",
		parameters: [
			{ name: "speed", type: "float" as const, defaultValue: 0 },
			{ name: "isGrounded", type: "bool" as const, defaultValue: true },
			{ name: "isRunning", type: "bool" as const, defaultValue: false },
			{ name: "isJumping", type: "bool" as const, defaultValue: false },
		],
		clipSlots,
		masks: [],
		graphs: [
			{
				name: "Main",
				rootNodeIndex: loaded.length, // The blend1d node index
				nodes: [
					// One clip node per loaded clip
					...loaded.map((_, i) => ({
						type: "clip" as const,
						clipIndex: i,
						speed: 1,
						loop: true,
					})),
					// blend1d node
					{
						type: "blend1d" as const,
						parameterIndex: 0, // "speed"
						children: loaded.map((entry, i) => ({
							nodeIndex: i,
							threshold: entry.id === "idle" ? 0 :
								entry.id === "breathing-idle" ? 0.3 :
								2.0, // walking
						})),
					},
				],
			},
		],
		layers: [
			{
				name: "Base",
				graphIndex: 0,
				weight: 1,
				blendMode: "override" as const,
				rootMotionMode: "none" as const,
				enabled: true,
			},
		],
		entryGraphIndex: 0,
	};

	// Create the artifact with embedded clips
	const artifact = createAnimationArtifact({
		graph: compiledGraph,
		rig,
		clips: clipAssets,
	});

	const artifactJson = serializeAnimationArtifact(artifact);

	// Write the artifact
	const artifactPath = resolve(BUNDLE_DIR, "graph.animation.json");
	writeFileSync(artifactPath, artifactJson);
	console.log(`\n  ✓ Wrote ${artifactPath}`);

	// Write the bundle manifest
	const bundle = {
		format: "ggez.animation.bundle",
		version: 1,
		name: "player-locomotion",
		artifact: "graph.animation.json",
		characterAsset: null,
		clips: loaded.map((entry) => ({
			id: entry.id,
			name: entry.name,
			duration: entry.clip.duration,
			source: "mixamo",
			asset: `assets/${entry.id === "breathing-idle" ? "breathing-idle" : entry.id}.fbx`,
		})),
		clipAssets: Object.fromEntries(
			loaded.map((entry) => [
				entry.name,
				`assets/${entry.id === "breathing-idle" ? "breathing-idle" : entry.id}.fbx`,
			]),
		),
	};

	const bundlePath = resolve(BUNDLE_DIR, "animation.bundle.json");
	writeFileSync(bundlePath, JSON.stringify(bundle, null, 2));
	console.log(`  ✓ Wrote ${bundlePath}`);

	console.log("\n🎬 Animation bundle built successfully!");
	console.log(`   Clips: ${clipSlots.map((c) => `${c.name} (${c.duration.toFixed(2)}s)`).join(", ")}`);
	console.log(`   Bones: ${rig.boneNames.length}`);
	console.log(`   Graph: blend1d with ${loaded.length} children`);
}

main().catch((error) => {
	console.error("Fatal error:", error);
	process.exit(1);
});
