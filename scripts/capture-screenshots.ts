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
const SETTLE_MS = 6000; // time for scene to fully render after camera move (incl. async GLB load)

// ─── Camera presets matching reference-catalog.json ──────────────────────

type CameraPreset = {
	name: string;
	scene: string;
	position: { x: number; y: number; z: number };
	target: { x: number; y: number; z: number };
	description: string;
	/** If true, append ?gate=active to URL so the gate starts fully open. */
	gateActive?: boolean;
	/**
	 * If true, capture via Playwright `page.screenshot()` (full viewport including
	 * DOM overlays) instead of `__sgu.screenshot()` (WebGL canvas only).
	 * Required for scenes whose visuals are primarily DOM (e.g. start-screen menu).
	 */
	domCapture?: boolean;
};

const CAMERA_PRESETS: CameraPreset[] = [
	{
		name: "start-screen",
		scene: "start-screen",
		// Camera position is irrelevant — start-screen is a DOM overlay menu;
		// the camera just renders the starfield behind it.
		position: { x: 0, y: 0, z: 0 },
		target: { x: 0, y: 0, z: -1 },
		description: "Main menu overlay (Destiny Restored title, Begin Awakening, Continue, Settings)",
		domCapture: true,
	},
	{
		name: "cinematic-ship-reveal",
		scene: "opening-cinematic",
		// Hero-shot framing matching design/concept-art/destiny-ship/exterior-hero-shot.png:
		// 3/4 angle, ship occupies center-frame with starfield + dark void around it.
		position: { x: -25, y: 6, z: 35 },
		target: { x: 0, y: 0, z: 0 },
		description: "Ship-reveal hero shot matching exterior-hero-shot.png",
	},
	{
		name: "corridor-entry",
		scene: "destiny-corridor",
		// Inside corridor-a1 section (z=0, depth=8) looking south toward
		// storage-bay back wall — captures ceiling fixtures + wall accents.
		// Each room's doorway is on its +z (north) face only, so south-facing
		// shots from a non-corridor section just hit a solid back wall.
		position: { x: 0, y: 1.7, z: 3 },
		target: { x: 0, y: 1.6, z: -4 },
		description: "Player POV inside corridor-a1 looking down hall toward storage",
	},
	{
		name: "corridor-overhead",
		scene: "destiny-corridor",
		// Long-hallway perspective from inside storage-bay (south terminus,
		// solid back wall behind camera) looking north through the chain
		// of doorways toward the gate room. Captures the whole connected
		// 3-section corridor in a single hero shot.
		position: { x: 0, y: 1.7, z: -11.5 },
		target: { x: 0, y: 1.5, z: 12 },
		description: "Long-hallway perspective looking north through full 3-section chain",
	},
	{
		name: "scrubber-entry",
		scene: "scrubber-room",
		position: { x: 0, y: 1.7, z: 8 },
		target: { x: 0, y: 1.5, z: 0 },
		description: "Entry view of CO2 scrubber room",
	},
	{
		name: "scrubber-wide",
		scene: "scrubber-room",
		position: { x: -6, y: 4, z: 10 },
		target: { x: 0, y: 1.5, z: 0 },
		description: "Wide angle showing scrubber units + room layout",
	},
	{
		name: "desert-arrival",
		scene: "desert-planet",
		position: { x: 0, y: 1.7, z: 12 },
		target: { x: 0, y: 1.7, z: 0 },
		description: "Player POV stepping out of gate onto desert (Air ep)",
	},
	{
		name: "desert-wide",
		scene: "desert-planet",
		position: { x: 25, y: 8, z: 25 },
		target: { x: 0, y: 1, z: 0 },
		description: "Wide vista of desert + gate + horizon",
	},
	{
		name: "gate-room-front",
		scene: "gate-room",
		// Concept dormant view: looking THROUGH the cathedral doorway from
		// just inside. Camera at z=80 (10 units inside the front wall at z=90)
		// at mid-height frames the gate prominently, matching concept proportion
		// where gate fills ~25% of frame width.
		position: { x: 0, y: 10, z: 80 },
		target: { x: 0, y: 8, z: 0 },
		description: "Doorway-distance view of gate room cathedral, matching gate-room-dormant.png",
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
		position: { x: -25, y: 12, z: 50 },
		target: { x: 0, y: 6, z: 0 },
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
		name: "gate-room-active-wide",
		scene: "gate-room",
		// Cathedral-establishing shot with the gate ACTIVE — matches
		// gate-room-active.png concept: symmetric framing, gate centered,
		// architecture visible on both sides. Y lifted to catch ceiling beams.
		position: { x: 0, y: 10, z: 38 },
		target: { x: 0, y: 6, z: 0 },
		description: "Wide active-gate establishing shot, matching gate-room-active.png",
		gateActive: true,
	},
	{
		name: "gate-room-side",
		scene: "gate-room",
		// Room is 140 wide × 180 deep × 52 tall. Earlier x=38 placement put a
		// balcony/console structure between camera and gate. Pulled fully back
		// past the intervening geometry; gate now reads in 3/4 profile.
		position: { x: 28, y: 22, z: 28 },
		target: { x: 0, y: 7, z: 0 },
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

async function captureFromPreset(page: Page, preset: CameraPreset): Promise<string | Buffer> {
	if (preset.domCapture) {
		// DOM-overlay scenes: full viewport capture so HTML menu/UI is visible.
		await page.waitForTimeout(500);
		return await page.screenshot({ type: "png" });
	}

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

	// Optional CLI filter: `bun run scripts/capture-screenshots.ts start-screen gate-active`
	const filter = process.argv.slice(2).filter((a) => !a.startsWith("-"));
	const activePresets = filter.length > 0
		? CAMERA_PRESETS.filter((p) => filter.includes(p.name))
		: CAMERA_PRESETS;
	if (filter.length > 0) {
		console.log(`Filtering to: ${activePresets.map((p) => p.name).join(", ")}`);
	}

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
	for (const preset of activePresets) {
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
				const result = await captureFromPreset(page, preset);
				const buffer = typeof result === "string" ? dataUrlToBuffer(result) : result;
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
