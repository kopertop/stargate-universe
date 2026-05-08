/**
 * Patches three.js's GLTFLoader prototype so every `new GLTFLoader()` —
 * including the ones constructed inside `@ggez/three-runtime` and other
 * dependencies that don't expose hooks — automatically delegates DRACO,
 * KTX2, and Meshopt-compressed payloads to the right decoders.
 *
 * Also patches VRMLoaderPlugin's underlying GLTFLoader the same way (the
 * VRM library uses three's GLTFLoader internally; the prototype patch
 * covers it transparently).
 *
 * Call once at startup (from src/game/app.ts) AFTER the renderer is
 * constructed — KTX2Loader needs `renderer.capabilities` for transcoder
 * format selection.
 *
 * Decoder asset paths point at `/decoders/draco/` and `/decoders/basis/`
 * served from `public/decoders/` (same origin, no CORS, cacheable).
 */
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { KTX2Loader } from "three/examples/jsm/loaders/KTX2Loader.js";
import { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";

const DRACO_PATH = "/decoders/draco/";
const BASIS_PATH = "/decoders/basis/";

let installed = false;

export const installAssetDecoders = (renderer: unknown): void => {
	if (installed) return;
	installed = true;

	const dracoLoader = new DRACOLoader().setDecoderPath(DRACO_PATH);
	const ktx2Loader = new KTX2Loader()
		.setTranscoderPath(BASIS_PATH)
		// detectSupport reads renderer.capabilities to pick the best transcoder
		// target (BC7/ASTC/ETC/etc). It's typed against WebGLRenderer but works
		// against the WebGPURenderer wrapper too — the shape we care about is
		// the same.
		.detectSupport(renderer as never);

	const proto = GLTFLoader.prototype as unknown as {
		dracoLoader?: DRACOLoader;
		ktx2Loader?: KTX2Loader;
		meshoptDecoder?: typeof MeshoptDecoder;
		setDRACOLoader: (loader: DRACOLoader) => GLTFLoader;
		setKTX2Loader: (loader: KTX2Loader) => GLTFLoader;
		setMeshoptDecoder: (decoder: typeof MeshoptDecoder) => GLTFLoader;
		parse: (...args: unknown[]) => unknown;
	};

	const origParse = proto.parse;
	proto.parse = function patchedParse(this: typeof proto, ...args: unknown[]) {
		if (!this.dracoLoader)     this.setDRACOLoader(dracoLoader);
		if (!this.ktx2Loader)      this.setKTX2Loader(ktx2Loader);
		if (!this.meshoptDecoder)  this.setMeshoptDecoder(MeshoptDecoder);
		return origParse.apply(this, args);
	};
};
