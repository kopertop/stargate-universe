/**
 * S4-07 — Dev-only post profile panel.
 *
 * Mounts a `lil-gui` panel (dev builds only — `import.meta.env.DEV`)
 * exposing renderer tone mapping + exposure live, plus reserved sliders
 * for bloom/vignette once the EffectComposer pipeline lands.
 *
 * The whole module is tree-shaken out of production builds: every
 * call site is wrapped in `if (import.meta.env.DEV) ...`, and the
 * `lil-gui` import is dynamic so production rollup doesn't pull it.
 *
 * Toggle: backtick (`) — same key as the existing debug overlay so
 * dev tooling clusters under one keybind. Press once to show, again
 * to hide.
 */
import * as THREE from "three";

interface DevPanelHandle {
	dispose: () => void;
}

interface DevPanelTargets {
	renderer: { toneMapping: THREE.ToneMapping; toneMappingExposure: number };
}

let active: DevPanelHandle | null = null;

const TONE_MAPPING_OPTIONS: Record<string, THREE.ToneMapping> = {
	None: THREE.NoToneMapping,
	Linear: THREE.LinearToneMapping,
	Reinhard: THREE.ReinhardToneMapping,
	Cineon: THREE.CineonToneMapping,
	ACESFilmic: THREE.ACESFilmicToneMapping,
	AgX: THREE.AgXToneMapping,
	Neutral: THREE.NeutralToneMapping,
};

export const mountDevPanel = async (targets: DevPanelTargets): Promise<DevPanelHandle | null> => {
	if (!import.meta.env.DEV) return null;
	if (active) return active;

	// Dynamic import so prod build never bundles lil-gui.
	const { default: GUI } = await import("lil-gui");
	const gui = new GUI({ title: "SGU Dev (` to toggle)", width: 280 });
	gui.domElement.style.zIndex = "9999";

	const post = gui.addFolder("Post");
	post.add(targets.renderer, "toneMappingExposure", 0.1, 6.0, 0.05).name("exposure");
	const toneState = {
		toneMapping: Object.keys(TONE_MAPPING_OPTIONS).find(
			(k) => TONE_MAPPING_OPTIONS[k] === targets.renderer.toneMapping,
		) ?? "ACESFilmic",
	};
	post.add(toneState, "toneMapping", Object.keys(TONE_MAPPING_OPTIONS)).onChange((v: string) => {
		targets.renderer.toneMapping = TONE_MAPPING_OPTIONS[v];
	});

	// Bloom/vignette stubs — passive until EffectComposer lands; controls
	// need something to mutate so the sliders aren't disabled.
	const reserved = { bloom: 0.4, vignette: 0.25 };
	post.add(reserved, "bloom", 0, 2.0, 0.05).name("bloom (stub)");
	post.add(reserved, "vignette", 0, 1.0, 0.05).name("vignette (stub)");

	let visible = true;
	const onKey = (e: KeyboardEvent) => {
		if (e.code !== "Backquote") return;
		visible = !visible;
		gui.domElement.style.display = visible ? "" : "none";
	};
	window.addEventListener("keydown", onKey);

	const handle: DevPanelHandle = {
		dispose: () => {
			window.removeEventListener("keydown", onKey);
			gui.destroy();
			active = null;
		},
	};
	active = handle;
	return handle;
};
