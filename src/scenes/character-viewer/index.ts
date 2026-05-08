/**
 * Character Viewer Scene
 *
 * A utility scene for inspecting and tweaking individual VRM characters in
 * isolation. Loads a single VRM, optionally applies an animation, and spins
 * it on a turntable so you can see every angle without the game's scene
 * pressure (no player controller, no gameplay systems, no cinematic).
 *
 * URL parameters:
 *   ?scene=character-viewer
 *   ?character=<id>           crew manifest id (e.g. "rush", "eli", "young"),
 *                             OR a full path starting with "/" or "http".
 *                             Default: "rush".
 *   ?animation=<path>         path to an animation GLB to apply to the mixer.
 *                             Optional — default pose otherwise.
 *   ?autorotate=0             disable the turntable rotation (default: on).
 *   ?ragdoll=1                spawn a ragdoll next to the character for
 *                             physics-testing. Each click re-launches it
 *                             with a random impulse.
 *
 * Example:
 *   /?scene=character-viewer&character=rush&animation=/assets/anim/idle.glb
 *   /?scene=character-viewer&character=/assets/characters/eli/eli.vrm&ragdoll=1
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import {
	getCrewManifestJSON,
	loadAnimationClip,
	loadVRMCharacter,
	type CharacterLoadResult,
} from "../../characters/character-loader";
import { createRagdoll, type RagdollInstance } from "../../systems/ragdoll";
import { CRASHCAT_OBJECT_LAYER_MOVING } from "@ggez/runtime-physics-crashcat";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

// ─── URL param resolution ────────────────────────────────────────────────────

interface ViewerParams {
	character: string;
	animation: string | null;
	autorotate: boolean;
	ragdoll: boolean;
}

function readParams(): ViewerParams {
	const qs = new URLSearchParams(window.location.search);
	return {
		character: qs.get("character") ?? "rush",
		animation: qs.get("animation"),
		autorotate: qs.get("autorotate") !== "0",
		ragdoll: qs.get("ragdoll") === "1",
	};
}

/**
 * Resolve a character param into a VRM URL. Accepts three forms:
 *   - A crew manifest short id ("rush", "eli")  →  manifest.path
 *   - An absolute path ("/assets/characters/...") →  passes through
 *   - A URL ("http(s)://...")                   →  passes through
 */
async function resolveCharacterUrl(input: string): Promise<string> {
	if (input.startsWith("http://") || input.startsWith("https://") || input.startsWith("/")) {
		return input;
	}
	const manifest = await getCrewManifestJSON();
	const entry = manifest.crew.find((c) => c.id === input);
	if (!entry) {
		throw new Error(
			`[character-viewer] unknown crew id "${input}". Known ids: ${manifest.crew.map((c) => c.id).join(", ")}`,
		);
	}
	return entry.path;
}

// ─── HUD overlay ─────────────────────────────────────────────────────────────

function createHud(params: ViewerParams): {
	setStatus: (text: string) => void;
	setCrewList: (ids: string[]) => void;
	dispose: () => void;
} {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;top:1rem;left:1rem;",
		"color:#ddd;font-family:'Segoe UI',sans-serif;",
		"font-size:0.85rem;line-height:1.4;",
		"background:#00000099;padding:0.75rem 1rem;border-radius:6px;",
		"pointer-events:none;z-index:50;max-width:28rem;",
	].join("");

	const title = document.createElement("div");
	title.style.cssText = "font-size:1rem;font-weight:600;color:#d4b96a;margin-bottom:0.25rem;";
	title.textContent = "Character Viewer";

	const body = document.createElement("div");
	const appendField = (label: string, value: string): void => {
		const row = document.createElement("div");
		const b = document.createElement("b");
		b.textContent = `${label}: `;
		row.appendChild(b);
		row.appendChild(document.createTextNode(value));
		body.appendChild(row);
	};
	appendField("character", params.character);
	if (params.animation) appendField("animation", params.animation);
	appendField("autorotate", String(params.autorotate));
	if (params.ragdoll) appendField("ragdoll", "on (click to relaunch)");

	const status = document.createElement("div");
	status.style.cssText = "margin-top:0.35rem;color:#9ca3af;min-height:1.2em;";
	status.textContent = "Loading…";

	const crewHeader = document.createElement("b");
	crewHeader.textContent = "crew ids: ";
	const crewList = document.createElement("span");
	const crewRow = document.createElement("div");
	crewRow.style.cssText = "margin-top:0.5rem;color:#9ca3af;font-size:0.75rem;";
	crewRow.append(crewHeader, crewList);

	el.append(title, body, status, crewRow);
	document.body.appendChild(el);

	return {
		setStatus(text) { status.textContent = text; },
		setCrewList(ids) {
			crewList.textContent = ids.length === 0 ? "" : ids.join(", ");
			crewRow.style.display = ids.length === 0 ? "none" : "";
		},
		dispose() { el.remove(); },
	};
}

// ─── Scene mount ─────────────────────────────────────────────────────────────

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, physicsWorld } = context;
	const params = readParams();
	const hud = createHud(params);

	// Camera — fixed front view at eye level, looking at torso.
	camera.position.set(0, 1.5, 3);
	camera.lookAt(0, 1.1, 0);

	// Key + fill lights — enough to read face and silhouette clearly.
	const key = new THREE.DirectionalLight(0xffffff, 1.4);
	key.position.set(2, 4, 3);
	scene.add(key);
	const fill = new THREE.DirectionalLight(0xaaccff, 0.6);
	fill.position.set(-3, 2, -2);
	scene.add(fill);

	// Turntable pivot — rotating the group instead of the camera keeps any
	// attached ragdoll inspector stable while the character spins.
	const turntable = new THREE.Group();
	turntable.name = "character-viewer:turntable";
	scene.add(turntable);

	// ── Populate crew list in HUD (for discoverability) ──────────────────
	try {
		const manifest = await getCrewManifestJSON();
		hud.setCrewList(manifest.crew.map((c) => c.id));
	} catch (err) {
		console.warn("[character-viewer] manifest fetch failed", err);
	}

	// ── Load the VRM ────────────────────────────────────────────────────
	let character: CharacterLoadResult | null = null;
	try {
		const url = await resolveCharacterUrl(params.character);
		hud.setStatus(`Loading ${url}…`);
		character = await loadVRMCharacter(url);
		character.root.position.set(0, 0, 0);
		turntable.add(character.root);
		hud.setStatus(`Loaded ${url}`);
	} catch (err) {
		hud.setStatus(`❌ ${String(err)}`);
		console.error("[character-viewer] load failed", err);
	}

	// ── Apply animation if requested ────────────────────────────────────
	if (character && params.animation) {
		try {
			await loadAnimationClip(params.animation, character.mixer, THREE.LoopRepeat);
			hud.setStatus(`Playing ${params.animation}`);
		} catch (err) {
			hud.setStatus(`Animation failed: ${String(err)}`);
			console.warn("[character-viewer] animation load failed", err);
		}
	}

	// ── Optional ragdoll for physics smoke-testing ──────────────────────
	let ragdoll: RagdollInstance | null = null;
	let onPointerDown: ((ev: PointerEvent) => void) | undefined;
	if (params.ragdoll) {
		ragdoll = createRagdoll(physicsWorld, {
			objectLayer: CRASHCAT_OBJECT_LAYER_MOVING,
			position: new THREE.Vector3(1.5, 2.5, 0),
			scale: 1.0,
		});
		scene.add(ragdoll.group);
		ragdoll.launch([0, 2, 0], [Math.random() * 4 - 2, 0, Math.random() * 4 - 2]);

		onPointerDown = () => {
			if (!ragdoll) return;
			ragdoll.launch(
				[(Math.random() - 0.5) * 6, 2 + Math.random() * 3, (Math.random() - 0.5) * 6],
				[(Math.random() - 0.5) * 8, (Math.random() - 0.5) * 8, (Math.random() - 0.5) * 8],
			);
		};
		window.addEventListener("pointerdown", onPointerDown);
	}

	return {
		update(delta) {
			character?.update?.(delta);
			if (params.autorotate && character) {
				turntable.rotation.y += delta * 0.4;
			}
			ragdoll?.syncToVisual();
		},
		dispose() {
			if (onPointerDown) window.removeEventListener("pointerdown", onPointerDown);
			ragdoll?.dispose();
			character?.dispose?.();
			scene.remove(turntable);
			scene.remove(key);
			scene.remove(fill);
			hud.dispose();
		},
	};
}

// ─── Scene definition ────────────────────────────────────────────────────────

export const characterViewerScene = defineGameScene({
	id: "character-viewer",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () =>
			import("./scene.runtime.json?raw").then((module) => module.default),
	}),
	title: "Character Viewer",
	player: false,
	mount,
});
