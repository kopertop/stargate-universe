import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
	// E2E tests
	testDir: "tests/e2e",
	outputDir: "tests/results",
	timeout: 30_000,
	expect: { timeout: 10_000 },
	// Visual snapshot config
	snapshotDir: "./tests/visual/__snapshots__",
	updateSnapshots: "missing",
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
			},
		},
	],
	webServer: {
		command: "bun run dev",
		port: 5173,
		reuseExistingServer: true,
		timeout: 15_000,
	},
});
