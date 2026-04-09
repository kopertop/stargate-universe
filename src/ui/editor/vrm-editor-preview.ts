/**
 * VRM Editor Preview — small turntable renderer for the character editor.
 *
 * Creates a separate WebGLRenderer (not the game's WebGPU renderer) to show
 * the character spinning on a turntable. This avoids state-sharing issues.
 */
import {
	AmbientLight,
	DirectionalLight,
	PerspectiveCamera,
	Scene,
	WebGLRenderer,
} from "three";
import type { VRM } from "@pixiv/three-vrm";

export type EditorPreview = {
	/** The canvas element to insert into the DOM. */
	readonly canvas: HTMLCanvasElement;
	/** Call per-frame to rotate the turntable. */
	update(delta: number): void;
	/** Set the VRM to preview (call after loading). */
	setVrm(vrm: VRM): void;
	/** Clean up renderer and resources. */
	dispose(): void;
};

const PREVIEW_WIDTH = 260;
const PREVIEW_HEIGHT = 400;
const ROTATION_SPEED = 0.4; // radians per second

/**
 * Create the editor preview renderer.
 */
export function createEditorPreview(): EditorPreview {
	const renderer = new WebGLRenderer({ antialias: true, alpha: true });
	renderer.setSize(PREVIEW_WIDTH, PREVIEW_HEIGHT);
	renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
	renderer.setClearColor(0x111111, 1);

	const scene = new Scene();
	const camera = new PerspectiveCamera(30, PREVIEW_WIDTH / PREVIEW_HEIGHT, 0.1, 20);
	camera.position.set(0, 1.0, 3.5);
	camera.lookAt(0, 0.9, 0);

	// Lighting
	const ambient = new AmbientLight(0xffffff, 1.5);
	scene.add(ambient);

	const directional = new DirectionalLight(0xffffff, 2.0);
	directional.position.set(2, 3, 2);
	scene.add(directional);

	let activeVrm: VRM | undefined;
	let rotation = 0;
	let animationId = 0;
	let lastTime = 0;

	const tick = (time: number) => {
		animationId = requestAnimationFrame(tick);
		const delta = lastTime ? (time - lastTime) / 1000 : 0;
		lastTime = time;

		rotation += ROTATION_SPEED * delta;

		if (activeVrm) {
			activeVrm.scene.rotation.y = rotation;
			activeVrm.update(delta);
		}

		renderer.render(scene, camera);
	};

	// Start render loop
	animationId = requestAnimationFrame(tick);

	return {
		canvas: renderer.domElement,

		update(_delta: number) {
			// Render loop is self-driven via rAF
		},

		setVrm(vrm: VRM) {
			// Remove previous
			if (activeVrm) {
				scene.remove(activeVrm.scene);
			}

			activeVrm = vrm;
			scene.add(vrm.scene);
			vrm.scene.rotation.y = rotation;
		},

		dispose() {
			cancelAnimationFrame(animationId);
			if (activeVrm) {
				scene.remove(activeVrm.scene);
			}
			renderer.dispose();
		},
	};
}
