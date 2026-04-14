import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
	testDir: "./tests/visual",
	snapshotDir: "./tests/visual/__snapshots__",
	// First run creates baselines; subsequent runs diff against them
	updateSnapshots: "missing",

	// Three.js animates via requestAnimationFrame — CSS animation disabling
	// doesn't stop the rAF loop, so consecutive frames always differ slightly.
	// Allow up to 15% of pixels to differ (handles light flicker, gate spin, etc.)
	// animations:'allow' prevents Playwright injecting CSS that disables animations
	// (the injection causes the rAF-driven game loop to hang on the second frame).
	expect: {
		timeout: 15_000, // give WebGL scenes 15s for assertions
		// toMatchSnapshot is used instead of toHaveScreenshot so that the
		// comparison is pure Buffer diff (no in-page JS evaluation that can
		// deadlock the WebGPU renderer in headless Chromium).
		toMatchSnapshot: {
			maxDiffPixelRatio: 0.15,
			threshold: 0.3, // per-pixel CIEDE2000 color distance 0–1
		},
	},

	use: {
		baseURL: "http://localhost:5173",
		screenshot: "on",
		video: "retain-on-failure",
		// WebGL software renderer — required for headless Chromium (no GPU)
		launchOptions: {
			args: [
				"--use-gl=swiftshader",
				"--disable-gpu-sandbox",
				"--ignore-gpu-blocklist",
			],
		},
	},
	projects: [
		{
			name: "chromium",
			use: {
				...devices["Desktop Chrome"],
				viewport: { width: 1280, height: 720 },
				launchOptions: {
					args: [
						"--use-gl=swiftshader",
						"--disable-gpu-sandbox",
						"--ignore-gpu-blocklist",
					],
				},
			},
		},
	],
	webServer: {
		command: "bun run dev",
		url: "http://localhost:5173",
		// Always start a fresh managed server so a stale pre-existing Vite
		// process can't die mid-run and cause ERR_CONNECTION_REFUSED on test 2+.
		reuseExistingServer: true,
		timeout: 60_000,
	},
});
