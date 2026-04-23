import { defineConfig } from "vitest/config";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
	test: {
		environment: "node",
		include: ["tests/**/*.test.ts"],
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
