/**
 * Character Viewer — debug scene for inspecting VRM crew models and VRMA clips.
 *
 * Navigate directly: /?scene=character-viewer
 *
 * No player controller, no HUD — just a studio turntable with side panels.
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import {
	getCrewManifestJSON,
	loadVRMCharacter,
	type CharacterLoadResult,
	type CrewManifestEntry,
} from "../../characters/character-loader";
import { loadAnimation } from "../../systems/vrm/vrm-animation-retarget";
import { VrmIdleVariantCycle } from "../../systems/vrm/vrm-idle-variant-cycle";
import {
	getDefaultViewerAnimationId,
	getResolvedVrmaCatalog,
	getVrmaCatalogEntry,
} from "../../animations/vrma-catalog";
import {
	mountCharacterViewerPanel,
	type CharacterViewerPanelHandle,
} from "../../ui/character-viewer-panel";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

const STUDIO_TARGET = new THREE.Vector3(0, 0.95, 0);
const ORBIT_MIN_DISTANCE = 1.4;
const ORBIT_MAX_DISTANCE = 4.5;
const ORBIT_DEFAULT_DISTANCE = 2.6;
const ORBIT_DEFAULT_YAW = Math.PI;
const ORBIT_DEFAULT_PITCH = 0.12;

function buildStudio(scene: THREE.Scene): void {
	scene.background = new THREE.Color(0x0c1018);
	scene.fog = new THREE.FogExp2(0x0c1018, 0.045);

	const floor = new THREE.Mesh(
		new THREE.CircleGeometry(2.4, 64),
		new THREE.MeshStandardMaterial({
			color: 0x141820,
			roughness: 0.85,
			metalness: 0.25,
		}),
	);
	floor.rotation.x = -Math.PI / 2;
	floor.position.y = 0;
	floor.receiveShadow = true;
	scene.add(floor);

	const grid = new THREE.GridHelper(6, 24, 0x334466, 0x1a2233);
	grid.position.y = 0.002;
	scene.add(grid);

	const key = new THREE.DirectionalLight(0xffffff, 2.2);
	key.position.set(2.5, 4, 3);
	key.castShadow = true;
	scene.add(key);

	const fill = new THREE.DirectionalLight(0x88aacc, 0.8);
	fill.position.set(-3, 2.5, 2);
	scene.add(fill);

	const rim = new THREE.DirectionalLight(0x6688bb, 0.6);
	rim.position.set(0, 2, -3);
	scene.add(rim);

	scene.add(new THREE.AmbientLight(0x223344, 0.9));
	scene.add(new THREE.HemisphereLight(0x8899bb, 0x101018, 0.7));
}

function applyOrbitCamera(
	camera: THREE.PerspectiveCamera,
	yaw: number,
	pitch: number,
	distance: number,
): void {
	const cosPitch = Math.cos(pitch);
	camera.position.set(
		STUDIO_TARGET.x + Math.sin(yaw) * cosPitch * distance,
		STUDIO_TARGET.y + Math.sin(pitch) * distance,
		STUDIO_TARGET.z + Math.cos(yaw) * cosPitch * distance,
	);
	camera.lookAt(STUDIO_TARGET);
}

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, renderer } = context;
	camera.rotation.order = "YXZ";
	camera.near = 0.05;
	camera.far = 50;
	camera.updateProjectionMatrix();

	buildStudio(scene);

	let animationCatalog: Awaited<ReturnType<typeof getResolvedVrmaCatalog>>;
	try {
		animationCatalog = await getResolvedVrmaCatalog();
	} catch (err) {
		const message = err instanceof Error ? err.message : String(err);
		console.error("[character-viewer] Failed to load animation catalog:", message);
		animationCatalog = [];
	}

	let orbitYaw = ORBIT_DEFAULT_YAW;
	let orbitPitch = ORBIT_DEFAULT_PITCH;
	let orbitDistance = ORBIT_DEFAULT_DISTANCE;
	let dragging = false;
	let lastPointerX = 0;
	let lastPointerY = 0;

	applyOrbitCamera(camera, orbitYaw, orbitPitch, orbitDistance);

	let activeCharacter: CharacterLoadResult | undefined;
	let activeCharacterEntry: CrewManifestEntry | undefined;
	let activeAnimationId: string | null = null;
	let idleVariantCycle: VrmIdleVariantCycle | undefined;
	let loadToken = 0;

	const manifest = await getCrewManifestJSON();
	const panel: CharacterViewerPanelHandle = mountCharacterViewerPanel({
		characters: manifest.crew,
		animations: animationCatalog,
		onSelectCharacter: (entry) => {
			void selectCharacter(entry);
		},
		onSelectAnimation: (entry) => {
			void playAnimation(entry);
		},
	});

	const disposeCharacter = (): void => {
		idleVariantCycle?.dispose();
		idleVariantCycle = undefined;
		if (!activeCharacter) return;
		scene.remove(activeCharacter.root);
		activeCharacter.dispose();
		activeCharacter = undefined;
		activeCharacterEntry = undefined;
		activeAnimationId = null;
		panel.setActiveAnimation(null);
	};

	const selectCharacter = async (entry: CrewManifestEntry): Promise<void> => {
		const token = ++loadToken;
		panel.setActiveCharacter(entry.id);
		panel.setCharacterLoading(entry.id, true);
		panel.setStatus(`Loading ${entry.name}…`);

		disposeCharacter();

		try {
			const loaded = await loadVRMCharacter(entry.path, { facePositiveZ: false });
			if (token !== loadToken) {
				loaded.dispose();
				return;
			}

			activeCharacter = loaded;
			activeCharacterEntry = entry;
			loaded.root.position.set(0, 0, 0);
			scene.add(loaded.root);

			panel.setStatus(`${entry.name} loaded — pick an animation.`);
			panel.setCharacterLoading(entry.id, false);

			// Auto-play gender-appropriate idle (female-idle for female crew, eli-idle for male)
			const defaultAnimId = getDefaultViewerAnimationId(entry.gender);
			const idle = defaultAnimId ? await getVrmaCatalogEntry(defaultAnimId) : undefined;
			if (idle && loaded.vrm) {
				await playAnimation(idle);
			}
		} catch (err) {
			if (token !== loadToken) return;
			const message = err instanceof Error ? err.message : String(err);
			panel.setCharacterLoading(entry.id, false);
			panel.setCharacterError(entry.id, message);
			panel.setStatus(`Failed to load ${entry.name}: ${message}`, true);
		}
	};

	const playAnimation = async (
		entry: Awaited<ReturnType<typeof getResolvedVrmaCatalog>>[number],
	): Promise<void> => {
		if (!activeCharacter?.vrm) {
			panel.setStatus("Load a character before playing an animation.", true);
			return;
		}

		panel.setStatus(`Loading animation ${entry.label}…`);
		try {
			idleVariantCycle?.dispose();
			idleVariantCycle = undefined;

			const clip = await loadAnimation(entry.path, activeCharacter.vrm, entry.label);
			activeCharacter.mixer.stopAllAction();
			const action = activeCharacter.mixer.clipAction(clip);
			action.reset();
			action.setLoop(THREE.LoopRepeat, Infinity);
			action.fadeIn(0.2);
			action.play();
			activeAnimationId = entry.id;
			panel.setActiveAnimation(entry.id);
			panel.setStatus(
				`${activeCharacterEntry?.name ?? "Character"} · ${entry.label}`,
			);

			const gender = activeCharacterEntry?.gender;
			const defaultAnimId = getDefaultViewerAnimationId(gender);
			if (
				gender &&
				defaultAnimId &&
				entry.id === defaultAnimId &&
				activeCharacter.vrm
			) {
				idleVariantCycle = new VrmIdleVariantCycle({
					gender,
					vrm: activeCharacter.vrm,
					baseIdleAction: action,
					getBaseIdleWeight: () => 1,
				});
				await idleVariantCycle.load();
				idleVariantCycle.enterIdle();
			}
		} catch (err) {
			const message = err instanceof Error ? err.message : String(err);
			panel.setStatus(`Animation failed: ${message}`, true);
		}
	};

	// Default to player character (Eli)
	const defaultEntry = manifest.crew.find((c) => c.isPlayer) ?? manifest.crew[0];
	if (defaultEntry) {
		void selectCharacter(defaultEntry);
	}

	const canvas = renderer.domElement;
	const onPointerDown = (event: PointerEvent): void => {
		if (event.button !== 0) return;
		dragging = true;
		lastPointerX = event.clientX;
		lastPointerY = event.clientY;
		canvas.setPointerCapture(event.pointerId);
	};
	const onPointerMove = (event: PointerEvent): void => {
		if (!dragging) return;
		const dx = event.clientX - lastPointerX;
		const dy = event.clientY - lastPointerY;
		lastPointerX = event.clientX;
		lastPointerY = event.clientY;
		orbitYaw -= dx * 0.008;
		orbitPitch = THREE.MathUtils.clamp(orbitPitch - dy * 0.006, -0.4, 0.85);
		applyOrbitCamera(camera, orbitYaw, orbitPitch, orbitDistance);
	};
	const onPointerUp = (event: PointerEvent): void => {
		dragging = false;
		if (canvas.hasPointerCapture(event.pointerId)) {
			canvas.releasePointerCapture(event.pointerId);
		}
	};
	const onWheel = (event: WheelEvent): void => {
		event.preventDefault();
		orbitDistance = THREE.MathUtils.clamp(
			orbitDistance + event.deltaY * 0.002,
			ORBIT_MIN_DISTANCE,
			ORBIT_MAX_DISTANCE,
		);
		applyOrbitCamera(camera, orbitYaw, orbitPitch, orbitDistance);
	};

	canvas.addEventListener("pointerdown", onPointerDown);
	canvas.addEventListener("pointermove", onPointerMove);
	canvas.addEventListener("pointerup", onPointerUp);
	canvas.addEventListener("pointercancel", onPointerUp);
	canvas.addEventListener("wheel", onWheel, { passive: false });

	(window as unknown as { __sceneReady?: boolean }).__sceneReady = true;

	return {
		update: (delta: number) => {
			idleVariantCycle?.update(delta);
			activeCharacter?.update(delta);
		},
		dispose: () => {
			loadToken++;
			canvas.removeEventListener("pointerdown", onPointerDown);
			canvas.removeEventListener("pointermove", onPointerMove);
			canvas.removeEventListener("pointerup", onPointerUp);
			canvas.removeEventListener("pointercancel", onPointerUp);
			canvas.removeEventListener("wheel", onWheel);
			disposeCharacter();
			panel.dispose();
		},
	};
}

export const characterViewerScene = defineGameScene({
	id: "character-viewer",
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () => import("./scene.runtime.json?raw").then((m) => m.default),
	}),
	title: "Character Viewer",
	player: false,
	hud: false,
	mount,
});
