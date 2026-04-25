import { defineConfig } from "vitest/config";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
	test: {
		environment: "node",
		include: ["tests/**/*.test.ts"],
		exclude: ["**/tests/e2e/**", "**/node_modules/**", "**/dist/**"],
	},
	resolve: {
		alias: {
			"@kopertop/vibe-game-engine": resolve(
				__dirname,
				"tests/mocks/vibe-game-engine.ts",
			),
		},
	},
});
