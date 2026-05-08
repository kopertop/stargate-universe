/**
 * One-off perf-baseline capture for Sprint 4 (S4-01).
 *
 * Loads each scene via `?scene=<id>&webgl=1`, waits for __sceneReady,
 * samples renderer.info, FPS over 5s, and resource bytes, then prints
 * a markdown row per scene to stdout.
 *
 * Usage: bun run scripts/perf-baseline.ts
 */
import { chromium, type Page } from "@playwright/test";

const BASE = "http://localhost:5173";
const SCENES = [
	{ id: "gate-room",         label: "gate-room" },
	{ id: "destiny-corridor",  label: "destiny-corridor" },
	{ id: "opening-cinematic", label: "opening-cinematic" },
];

interface Sample {
	scene: string;
	tti_ms: number;
	fps_median: number;
	fps_min: number;
	fps_max: number;
	frame_ms_median: number;
	draw_calls: number;
	triangles: number;
	geometries: number;
	textures: number;
	programs: number;
	total_bytes: number;
	largest_asset_bytes: number;
	largest_asset_url: string;
	asset_count: number;
}

const captureScene = async (page: Page, sceneId: string): Promise<Sample> => {
	const t0 = Date.now();
	await page.goto(`${BASE}/?scene=${sceneId}&webgl=1`, { waitUntil: "domcontentloaded" });
	await page.waitForFunction(() => (window as { __sceneReady?: boolean }).__sceneReady === true, { timeout: 60_000 });
	const tti_ms = Date.now() - t0;

	// Settle a beat so the first-frame storm doesn't dominate the FPS sample.
	await page.waitForTimeout(1000);

	const sample = await page.evaluate(async () => {
		const w = window as unknown as {
			__sguRenderer?: { info: { render: { calls: number; triangles: number }; memory: { geometries: number; textures: number }; programs?: { length: number } | null } };
		};
		const r = w.__sguRenderer;
		if (!r) throw new Error("__sguRenderer missing");

		// 5s FPS sample via rAF deltas.
		const frames: number[] = [];
		await new Promise<void>((resolve) => {
			let last = performance.now();
			const start = last;
			const tick = (t: number) => {
				frames.push(t - last);
				last = t;
				if (t - start < 5000) requestAnimationFrame(tick);
				else resolve();
			};
			requestAnimationFrame(tick);
		});

		// Per-frame deltas → fps stats. Drop the first frame (rAF priming).
		const deltas = frames.slice(1).filter((d) => d > 0 && d < 1000);
		deltas.sort((a, b) => a - b);
		const median = deltas[Math.floor(deltas.length / 2)] ?? 0;
		const min_ms = deltas[0] ?? 0;
		const max_ms = deltas[deltas.length - 1] ?? 0;

		const info = r.info;

		// Resources: total + largest. transferSize is 0 for cached / cross-origin
		// without Timing-Allow-Origin — fall back to encodedBodySize / decodedBodySize.
		const entries = performance.getEntriesByType("resource") as PerformanceResourceTiming[];
		let total = 0;
		let largest = 0;
		let largestUrl = "";
		for (const e of entries) {
			const size = e.transferSize || e.encodedBodySize || e.decodedBodySize || 0;
			total += size;
			if (size > largest) { largest = size; largestUrl = e.name; }
		}

		return {
			fps_median: 1000 / median,
			fps_min: 1000 / max_ms,
			fps_max: 1000 / min_ms,
			frame_ms_median: median,
			draw_calls: info.render.calls,
			triangles: info.render.triangles,
			geometries: info.memory.geometries,
			textures: info.memory.textures,
			programs: info.programs?.length ?? 0,
			total_bytes: total,
			largest_asset_bytes: largest,
			largest_asset_url: largestUrl,
			asset_count: entries.length,
		};
	});

	return { scene: sceneId, tti_ms, ...sample };
};

const main = async () => {
	const browser = await chromium.launch({
		headless: true,
		args: ["--use-gl=swiftshader", "--disable-gpu-sandbox", "--ignore-gpu-blocklist", "--enable-unsafe-webgpu"],
	});
	const samples: Sample[] = [];
	try {
		for (const s of SCENES) {
			const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
			const page = await ctx.newPage();
			page.on("pageerror", (e) => console.error(`[${s.id}] pageerror:`, e.message));
			try {
				const sample = await captureScene(page, s.id);
				samples.push(sample);
				console.error(`[${s.id}] OK fps=${sample.fps_median.toFixed(1)} calls=${sample.draw_calls} tris=${sample.triangles}`);
			} catch (err) {
				console.error(`[${s.id}] FAILED:`, (err as Error).message);
			} finally {
				await ctx.close();
			}
		}
	} finally {
		await browser.close();
	}
	console.log(JSON.stringify(samples, null, 2));
};

await main();
