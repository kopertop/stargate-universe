import { defineConfig } from "@playwright/test";

export default defineConfig({
	testDir: "tests/e2e",
	outputDir: "tests/results",
	timeout: 30_000,
	expect: { timeout: 10_000 },
	use: {
		baseURL: "http://localhost:5173",
		screenshot: "off", // we take manual screenshots in tests
		video: "off",
		trace: "off",
	},
	projects: [
		{
			name: "chromium",
			use: {
				browserName: "chromium",
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
