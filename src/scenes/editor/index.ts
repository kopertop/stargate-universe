/**
 * Editor Scene — prototype level editor with click-to-place props.
 *
 * Usage: navigate to `/?scene=editor` (or `/?scene=editor&editor=1` for
 * symmetry with the design doc). The scene spawns a 40×40 m floor grid
 * and lets you click to place the currently-selected prop at the raycast
 * hit point. Right click removes the clicked prop. Changes
 * are saved to localStorage under `sgu:editor:editor`.
 *
 * Keys:
 *   1 / 2    — select prop (crate / simple-stargate)
 *   G        — toggle grid-snap (default on)
 *   Esc      — clear selection (ghost hidden)
 *   Delete   — wipe all placements
 *
 * This is the prototype pass described in design/gdd/level-editor.md.
 */
import * as THREE from "three";
import {
	createColocatedRuntimeSceneSource,
	defineGameScene,
} from "../../game/runtime-scene-sources";
import type { GameSceneModuleContext, GameSceneLifecycle } from "../../game/scene-types";
import {
	getProp,
	listProps,
	registerProp,
	type PropCatalogEntry,
	type PropInstance,
	type PlacedProp,
} from "../../editor/prop-catalog";
import { crateProp } from "../../editor/props/crate";
import { simpleStargateProp } from "../../editor/props/simple-stargate";
import {
	addPlaced,
	clearSceneDoc,
	loadSceneDoc,
	removePlaced,
	saveSceneDoc,
} from "../../editor/editor-persistence";

const assetUrlLoaders = import.meta.glob("./assets/**/*", {
	import: "default",
	query: "?url",
}) as Record<string, () => Promise<string>>;

const SCENE_ID = "editor";
const GRID_STEP = 1.0;

// Register the prototype catalog entries once, at module load.
registerProp(crateProp);
registerProp(simpleStargateProp);

// ─── HUD ─────────────────────────────────────────────────────────────────────

function createEditorHud(allProps: PropCatalogEntry[]): {
	setActive: (id: string) => void;
	setSnap: (on: boolean) => void;
	setStatus: (text: string) => void;
	dispose: () => void;
} {
	const el = document.createElement("div");
	el.style.cssText = [
		"position:fixed;top:1rem;left:1rem;z-index:50;",
		"color:#ddd;font-family:'Segoe UI',sans-serif;",
		"font-size:0.85rem;line-height:1.4;",
		"background:#00000099;padding:0.75rem 1rem;border-radius:6px;",
		"pointer-events:none;max-width:28rem;",
	].join("");

	const title = document.createElement("div");
	title.style.cssText = "font-size:1rem;font-weight:600;color:#d4b96a;margin-bottom:0.25rem;";
	title.textContent = "Level Editor";
	el.appendChild(title);

	const help = document.createElement("div");
	help.style.cssText = "color:#9ca3af;";
	help.textContent = "Click floor: place. Right-click prop: remove. G: snap. 1-2: prop. Del: clear all.";
	el.appendChild(help);

	const propsRow = document.createElement("div");
	propsRow.style.marginTop = "0.5rem";
	const propSpans: Record<string, HTMLSpanElement> = {};
	allProps.forEach((p, idx) => {
		const span = document.createElement("span");
		span.style.cssText = "margin-right:0.75rem;";
		span.textContent = `${idx + 1}. ${p.name}`;
		propsRow.appendChild(span);
		propSpans[p.id] = span;
	});
	el.appendChild(propsRow);

	const statusRow = document.createElement("div");
	statusRow.style.cssText = "margin-top:0.5rem;color:#9ca3af;min-height:1.2em;";
	el.appendChild(statusRow);

	const snapRow = document.createElement("div");
	snapRow.style.cssText = "margin-top:0.25rem;color:#9ca3af;";
	el.appendChild(snapRow);

	document.body.appendChild(el);

	return {
		setActive(id) {
			for (const [k, span] of Object.entries(propSpans)) {
				span.style.color = k === id ? "#d4b96a" : "";
				span.style.fontWeight = k === id ? "600" : "";
			}
		},
		setSnap(on) { snapRow.textContent = `snap: ${on ? `${GRID_STEP}m` : "off"}`; },
		setStatus(text) { statusRow.textContent = text; },
		dispose() { el.remove(); },
	};
}

// ─── Scene mount ─────────────────────────────────────────────────────────────

function snap(v: number): number {
	return Math.round(v / GRID_STEP) * GRID_STEP;
}

async function mount(context: GameSceneModuleContext): Promise<GameSceneLifecycle> {
	const { scene, camera, physicsWorld, renderer } = context;
	const allProps = listProps();
	const hud = createEditorHud(allProps);

	// ── Camera: top-down-ish for placement ───────────────────────────────
	camera.position.set(10, 12, 10);
	camera.lookAt(0, 0, 0);

	// ── Lighting + floor grid ────────────────────────────────────────────
	const key = new THREE.DirectionalLight(0xffffff, 1.1);
	key.position.set(5, 10, 5);
	scene.add(key);
	const ambient = new THREE.AmbientLight(0x5566aa, 0.5);
	scene.add(ambient);

	const grid = new THREE.GridHelper(40, 40, 0x555577, 0x303040);
	(grid.material as THREE.Material).transparent = true;
	(grid.material as THREE.Material).opacity = 0.6;
	scene.add(grid);

	// Invisible floor plane for raycasting.
	const floor = new THREE.Mesh(
		new THREE.PlaneGeometry(200, 200),
		new THREE.MeshBasicMaterial({ visible: false }),
	);
	floor.rotation.x = -Math.PI / 2;
	floor.name = "editor:floor";
	scene.add(floor);

	// ── State ────────────────────────────────────────────────────────────
	let doc = loadSceneDoc(SCENE_ID);
	let activePropId: string = allProps[0]?.id ?? "crate";
	let snapEnabled = true;
	let ghostMesh: THREE.Mesh | null = null;
	const placedInstances: { placed: PlacedProp; instance: PropInstance }[] = [];

	const buildCtx = { scene, physicsWorld };

	const spawnPlaced = (placed: PlacedProp): void => {
		const entry = getProp(placed.id);
		if (!entry) {
			console.warn(`[editor] unknown prop "${placed.id}" — skipping`);
			return;
		}
		const pos = new THREE.Vector3(...placed.position);
		const rot = new THREE.Euler(...placed.rotation);
		const instance = entry.create(buildCtx, pos, rot, placed.props);
		placedInstances.push({ placed, instance });
	};

	// Restore persisted placements
	for (const p of doc.placed) spawnPlaced(p);
	hud.setStatus(`Restored ${doc.placed.length} prop${doc.placed.length === 1 ? "" : "s"}.`);

	// ── Ghost preview (currently selected prop) ──────────────────────────
	const ensureGhost = (): void => {
		if (ghostMesh) {
			scene.remove(ghostMesh);
			ghostMesh.geometry.dispose();
			(ghostMesh.material as THREE.Material).dispose();
			ghostMesh = null;
		}
		const entry = getProp(activePropId);
		if (!entry) return;
		const [sx, sy, sz] = entry.previewSize;
		const geo = new THREE.BoxGeometry(sx, sy, sz);
		const mat = new THREE.MeshBasicMaterial({ color: 0xd4b96a, transparent: true, opacity: 0.35, wireframe: true });
		ghostMesh = new THREE.Mesh(geo, mat);
		ghostMesh.name = "editor:ghost";
		scene.add(ghostMesh);
		hud.setActive(activePropId);
	};
	ensureGhost();
	hud.setSnap(snapEnabled);

	// ── Pointer + keyboard handlers ──────────────────────────────────────
	const raycaster = new THREE.Raycaster();
	const ndc = new THREE.Vector2();
	const worldHit = new THREE.Vector3();

	const updateGhostFromPointer = (clientX: number, clientY: number): boolean => {
		const rect = renderer.domElement.getBoundingClientRect();
		ndc.x = ((clientX - rect.left) / rect.width) * 2 - 1;
		ndc.y = -((clientY - rect.top) / rect.height) * 2 + 1;
		raycaster.setFromCamera(ndc, camera);
		const hits = raycaster.intersectObject(floor, false);
		if (hits.length === 0) {
			if (ghostMesh) ghostMesh.visible = false;
			return false;
		}
		worldHit.copy(hits[0].point);
		if (snapEnabled) {
			worldHit.x = snap(worldHit.x);
			worldHit.z = snap(worldHit.z);
		}
		if (ghostMesh) {
			ghostMesh.visible = true;
			const entry = getProp(activePropId);
			const yOffset = entry ? entry.previewSize[1] / 2 : 0.5;
			ghostMesh.position.set(worldHit.x, worldHit.y + yOffset, worldHit.z);
		}
		return true;
	};

	const findPlacedIndexAtPointer = (): number => {
		const roots = placedInstances.map(({ instance }) => instance.root);
		const hits = raycaster.intersectObjects(roots, true);
		if (hits.length === 0) return -1;
		return placedInstances.findIndex(({ instance }) => {
			let node: THREE.Object3D | null = hits[0].object;
			while (node) {
				if (node === instance.root) return true;
				node = node.parent;
			}
			return false;
		});
	};

	const onPointerMove = (ev: PointerEvent): void => {
		updateGhostFromPointer(ev.clientX, ev.clientY);
	};

	const onPointerDown = (ev: PointerEvent): void => {
		if (ev.target !== renderer.domElement) return;
		if (!updateGhostFromPointer(ev.clientX, ev.clientY)) return;

		if (ev.button === 2) {
			// Right click → remove the prop under the cursor.
			ev.preventDefault();
			const placedIndex = findPlacedIndexAtPointer();
			if (placedIndex < 0) return;
			const [entry] = placedInstances.splice(placedIndex, 1);
			entry.instance.dispose();
			doc = removePlaced(doc, placedIndex);
			saveSceneDoc(doc);
			hud.setStatus(`Removed ${entry.placed.id}. (${doc.placed.length} placed)`);
			return;
		}

		if (ev.button !== 0) return;

		const placed: PlacedProp = {
			id: activePropId,
			position: [worldHit.x, worldHit.y, worldHit.z],
			rotation: [0, 0, 0],
		};
		spawnPlaced(placed);
		doc = addPlaced(doc, placed);
		saveSceneDoc(doc);
		hud.setStatus(`Placed ${placed.id} at ${worldHit.x.toFixed(1)}, ${worldHit.z.toFixed(1)}. (${doc.placed.length} placed)`);
	};

	const onContextMenu = (ev: MouseEvent): void => { ev.preventDefault(); };

	const onKey = (ev: KeyboardEvent): void => {
		// Digit1..9 → pick prop
		if (/^Digit[1-9]$/.test(ev.code)) {
			const idx = Number(ev.code.slice(-1)) - 1;
			const entry = allProps[idx];
			if (entry) {
				activePropId = entry.id;
				ensureGhost();
				hud.setStatus(`Selected ${entry.name}.`);
			}
			return;
		}
		if (ev.code === "KeyG") {
			snapEnabled = !snapEnabled;
			hud.setSnap(snapEnabled);
			return;
		}
		if (ev.code === "Escape") {
			if (ghostMesh) ghostMesh.visible = false;
			return;
		}
		if (ev.code === "Delete") {
			for (const { instance } of placedInstances) instance.dispose();
			placedInstances.length = 0;
			doc = { sceneId: SCENE_ID, version: 1, placed: [] };
			clearSceneDoc(SCENE_ID);
			hud.setStatus("All placements cleared.");
			return;
		}
	};

	window.addEventListener("pointermove", onPointerMove);
	window.addEventListener("pointerdown", onPointerDown);
	window.addEventListener("keydown", onKey);
	window.addEventListener("contextmenu", onContextMenu);

	return {
		dispose() {
			window.removeEventListener("pointermove", onPointerMove);
			window.removeEventListener("pointerdown", onPointerDown);
			window.removeEventListener("keydown", onKey);
			window.removeEventListener("contextmenu", onContextMenu);

			for (const { instance } of placedInstances) instance.dispose();
			placedInstances.length = 0;

			if (ghostMesh) {
				scene.remove(ghostMesh);
				ghostMesh.geometry.dispose();
				(ghostMesh.material as THREE.Material).dispose();
			}
			scene.remove(grid);
			scene.remove(floor);
			floor.geometry.dispose();
			scene.remove(key);
			scene.remove(ambient);
			hud.dispose();
		},
	};
}

// ─── Scene definition ────────────────────────────────────────────────────────

export const editorScene = defineGameScene({
	id: SCENE_ID,
	source: createColocatedRuntimeSceneSource({
		assetUrlLoaders,
		manifestLoader: () =>
			import("./scene.runtime.json?raw").then((module) => module.default),
	}),
	title: "Level Editor",
	player: false,
	mount,
});
