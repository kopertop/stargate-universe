/**
 * VRM Model Loader — queued, cached loading of VRM character models.
 *
 * Loads `.vrm` files via `@pixiv/three-vrm` on top of Three.js `GLTFLoader`.
 * Manages a loading queue (max concurrent loads), caches parsed VRM data,
 * and provides graceful fallback on failure.
 *
 * @see design/gdd/vrm-model-integration.md §Detailed Rules > VRM Loading Pipeline
 */
import { VRM, VRMLoaderPlugin, VRMUtils } from "@pixiv/three-vrm";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { getVrmConfig } from "./vrm-config";

// ─── Types ──────────────────────────────────────────────────────────────────

export type VrmLoadResult = {
	readonly vrm: VRM;
	readonly url: string;
};

type QueueEntry = {
	readonly url: string;
	readonly priority: number;
	resolve: (result: VrmLoadResult) => void;
	reject: (error: Error) => void;
};

// ─── Loader Singleton ───────────────────────────────────────────────────────

let gltfLoader: GLTFLoader | undefined;

function getLoader(): GLTFLoader {
	if (!gltfLoader) {
		gltfLoader = new GLTFLoader();
		gltfLoader.register((parser) => new VRMLoaderPlugin(parser));
	}

	return gltfLoader;
}

// ─── Cache ──────────────────────────────────────────────────────────────────

const vrmCache = new Map<string, VRM>();

/** Check if a VRM is already cached for the given URL. */
export function isVrmCached(url: string): boolean {
	return vrmCache.has(url);
}

/** Get a cached VRM instance (or undefined). */
export function getCachedVrm(url: string): VRM | undefined {
	return vrmCache.get(url);
}

/** Remove a VRM from the cache and dispose its resources. */
export function evictVrm(url: string): void {
	const vrm = vrmCache.get(url);

	if (vrm) {
		VRMUtils.deepDispose(vrm.scene);
		vrmCache.delete(url);
	}
}

/** Clear the entire VRM cache, disposing all resources. */
export function clearVrmCache(): void {
	for (const [url] of vrmCache) {
		evictVrm(url);
	}
}

// ─── Loading Queue ──────────────────────────────────────────────────────────

const queue: QueueEntry[] = [];
let activeLoads = 0;

/**
 * Load a VRM model from a URL. Results are cached — subsequent calls with
 * the same URL return the cached instance immediately.
 *
 * @param url      Path to the `.vrm` file
 * @param priority Lower numbers load first (0 = player, 1+ = crew by distance)
 * @returns        The loaded VRM and its source URL
 */
export function loadVrm(url: string, priority = 1): Promise<VrmLoadResult> {
	const cached = vrmCache.get(url);

	if (cached) {
		return Promise.resolve({ vrm: cached, url });
	}

	return new Promise<VrmLoadResult>((resolve, reject) => {
		queue.push({ url, priority, resolve, reject });
		queue.sort((a, b) => a.priority - b.priority);
		drainQueue();
	});
}

async function drainQueue(): Promise<void> {
	const config = getVrmConfig();

	while (queue.length > 0 && activeLoads < config.loading.maxConcurrentLoads) {
		const entry = queue.shift();

		if (!entry) break;

		// Check cache again in case it loaded while queued
		const cached = vrmCache.get(entry.url);

		if (cached) {
			entry.resolve({ vrm: cached, url: entry.url });
			continue;
		}

		activeLoads++;
		loadVrmInternal(entry).finally(() => {
			activeLoads--;
			drainQueue();
		});
	}
}

async function loadVrmInternal(entry: QueueEntry): Promise<void> {
	const config = getVrmConfig();
	let lastError: Error | undefined;

	for (let attempt = 0; attempt <= config.loading.maxRetries; attempt++) {
		try {
			const gltf = await getLoader().loadAsync(entry.url);
			const vrm = gltf.userData["vrm"] as VRM | undefined;

			if (!vrm) {
				throw new Error(`[VrmLoader] File loaded but contains no VRM data: ${entry.url}`);
			}

			// Optimize the VRM scene graph
			VRMUtils.removeUnnecessaryVertices(vrm.scene);
			VRMUtils.removeUnnecessaryJoints(vrm.scene);
			VRMUtils.combineSkeletons(vrm.scene);

			// Disable frustum culling on the VRM scene so skinned meshes
			// don't disappear when the bounding box is off-screen but
			// bones have moved the visible geometry into view
			vrm.scene.traverse((obj) => {
				obj.frustumCulled = false;
			});

			vrmCache.set(entry.url, vrm);
			entry.resolve({ vrm, url: entry.url });
			return;
		} catch (error) {
			lastError = error instanceof Error ? error : new Error(String(error));

			if (attempt < config.loading.maxRetries) {
				// Retrying — attempt counter handled by loop.
				await sleep(config.loading.retryDelayMs);
			}
		}
	}

	console.error(`[VrmLoader] Failed to load VRM: ${entry.url}`, lastError);
	entry.reject(lastError ?? new Error(`Unknown error loading ${entry.url}`));
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}
