/**
 * Automated screenshot capture for visual similarity comparison.
 *
 * Launches the game in a headed browser, navigates to each scene,
 * positions the camera at predefined angles matching the reference
 * catalog, and captures screenshots for comparison.
 *
 * Usage:
 *   bunx playwright test scripts/capture-screenshots.ts
 *   # or directly:
 *   bun run scripts/capture-screenshots.ts
 *
 * Output: screenshots saved to scripts/screenshots/ directory
 */

import { chromium, type Page } from "@playwright/test";
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";

const BASE_URL = "http://localhost:5173";
const OUTPUT_DIR = join(import.meta.dirname, "screenshots");
const SETTLE_MS = 2000; // time for scene to fully render after camera move

// ─── Camera presets matching reference-catalog.json ──────────────────────

type CameraPreset = {
	name: string;
	scene: string;
	position: { x: number; y: number; z: number };
	target: { x: number; y: number; z: number };
	description: string;
	/** If true, append ?gate=active to URL so the gate starts fully open. */
	gateActive?: boolean;
};

const CAMERA_PRESETS: CameraPreset[] = [
	{
		name: "gate-room-front",
		scene: "gate-room",
		// Gate is at (0, 6.2, 0), radius 6. At z=14 with FOV 60, the gate
		// fills ~80% of frame height, matching the reference framing.
		position: { x: 0, y: 6.2, z: 14 },
		target: { x: 0, y: 6.2, z: 0 },
		description: "Head-on view of gate room, matching sgu-gateroom.webp reference",
	},
	{
		name: "gate-active",
		scene: "gate-room",
		position: { x: 0, y: 4.5, z: 13 },
		target: { x: 0, y: 6.2, z: 0 },
		description: "Floor-level view looking at gate, matching active stargate reference",
		gateActive: true,
	},
	{
		name: "gate-closeup",
		scene: "gate-room",
		position: { x: 0, y: 6.2, z: 9 },
		target: { x: 0, y: 6.2, z: 0 },
		description: "Close-up of gate ring, matching Stargate.jpeg reference",
		gateActive: true,
	},
	{
		name: "gate-room-wide",
		scene: "gate-room",
		position: { x: -12, y: 8, z: 22 },
		target: { x: 0, y: 5, z: 0 },
		description: "Wide establishing shot showing room architecture and gate",
	},
	{
		name: "gate-room-overhead",
		scene: "gate-room",
		position: { x: 0, y: 20, z: 14 },
		target: { x: 0, y: 0, z: 0 },
		description: "High overhead angle showing floor layout and gate from above",
	},
	{
		name: "gate-room-side",
		scene: "gate-room",
		position: { x: 18, y: 5, z: 10 },
		target: { x: 0, y: 5, z: 0 },
		description: "Side angle showing room depth, wall panels, and gate profile",
	},
];

// ─── Capture logic ──────────────────────────────────────────────────────────

async function waitForSceneReady(page: Page): Promise<void> {
	await page.waitForFunction(
		() => (window as unknown as { __sceneReady?: boolean }).__sceneReady === true,
		{ timeout: 30_000 },
	);
	// Extra settle time for lighting, LOD, and animations to stabilize
	await page.waitForTimeout(SETTLE_MS);
}

async function captureFromPreset(page: Page, preset: CameraPreset): Promise<string> {
	// Position camera via debug API
	await page.evaluate(
		({ pos, target }) => {
			const sgu = (window as unknown as { __sgu?: { setCamera: (p: typeof pos, t: typeof target) => void } }).__sgu;
			if (!sgu) throw new Error("__sgu debug API not available");
			sgu.setCamera(pos, target);
		},
		{ pos: preset.position, target: preset.target },
	);

	// Let the frame settle with new camera position
	await page.waitForTimeout(500);

	// Capture via debug API (renders a fresh frame and returns data URL)
	const dataUrl = await page.evaluate(
		({ pos, target }) => {
			const sgu = (window as unknown as {
				__sgu?: {
					screenshot: (opts?: {
						cameraPos?: typeof pos;
						cameraTarget?: typeof target;
						waitFrames?: number;
					}) => Promise<string>;
				};
			}).__sgu;
			if (!sgu) throw new Error("__sgu debug API not available");
			return sgu.screenshot({ cameraPos: pos, cameraTarget: target, waitFrames: 5 });
		},
		{ pos: preset.position, target: preset.target },
	);

	return dataUrl;
}

function dataUrlToBuffer(dataUrl: string): Buffer {
	const base64 = dataUrl.split(",")[1];
	return Buffer.from(base64, "base64");
}

// ─── Main ──────────────────────────────────────────────────────────────────

async function main() {
	mkdirSync(OUTPUT_DIR, { recursive: true });

	console.log("Launching browser...");
	const browser = await chromium.launch({
		headless: false, // headed so WebGPU is available
		args: ["--enable-unsafe-webgpu"],
	});

	const context = await browser.newContext({
		viewport: { width: 1280, height: 720 },
	});
	const page = await context.newPage();

	// Group presets by (scene + gateActive) so URL params are consistent
	// across all presets in a group and we only reload when params change.
	const byGroup = new Map<string, CameraPreset[]>();
	for (const preset of CAMERA_PRESETS) {
		const key = `${preset.scene}:${preset.gateActive ? "active" : "idle"}`;
		const existing = byGroup.get(key) ?? [];
		existing.push(preset);
		byGroup.set(key, existing);
	}

	const results: Array<{ name: string; path: string; success: boolean; error?: string }> = [];

	for (const [groupKey, presets] of byGroup) {
		const sceneId = presets[0].scene;
		const gateActive = presets[0].gateActive ?? false;
		console.log(`\nLoading scene: ${sceneId} (gate=${gateActive ? "active" : "idle"})`);
		// ?photo=1 hides the player + disables input so the preset camera isn't
		// overridden each frame by third-person follow.
		const gateParam = gateActive ? "&gate=active" : "";
		await page.goto(`${BASE_URL}/?scene=${sceneId}&webgl=1&photo=1${gateParam}`);
		void groupKey;

		try {
			await waitForSceneReady(page);
			console.log(`  Scene ready.`);
		} catch {
			console.error(`  TIMEOUT waiting for scene ${sceneId}`);
			for (const preset of presets) {
				results.push({ name: preset.name, path: "", success: false, error: "Scene load timeout" });
			}
			continue;
		}

		for (const preset of presets) {
			console.log(`  Capturing: ${preset.name} — ${preset.description}`);
			try {
				const dataUrl = await captureFromPreset(page, preset);
				const buffer = dataUrlToBuffer(dataUrl);
				const filePath = join(OUTPUT_DIR, `${preset.name}.png`);
				writeFileSync(filePath, buffer);
				console.log(`    Saved: ${filePath} (${buffer.length} bytes)`);
				results.push({ name: preset.name, path: filePath, success: true });
			} catch (err) {
				const msg = err instanceof Error ? err.message : String(err);
				console.error(`    FAILED: ${msg}`);
				results.push({ name: preset.name, path: "", success: false, error: msg });
			}
		}
	}

	await browser.close();

	// Write results manifest
	const manifest = {
		timestamp: new Date().toISOString(),
		base_url: BASE_URL,
		presets: CAMERA_PRESETS.length,
		captured: results.filter((r) => r.success).length,
		failed: results.filter((r) => !r.success).length,
		results,
	};

	const manifestPath = join(OUTPUT_DIR, "capture-manifest.json");
	writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));

	console.log(`\n${"=".repeat(60)}`);
	console.log(`Captured: ${manifest.captured}/${manifest.presets} screenshots`);
	console.log(`Manifest: ${manifestPath}`);
	console.log(`${"=".repeat(60)}`);
}

main().catch((err) => {
	console.error("Fatal:", err);
	process.exit(1);
});
