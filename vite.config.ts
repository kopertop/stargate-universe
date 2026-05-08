import { defineConfig, searchForWorkspaceRoot } from "vite";
import { createWebHammerGamePlugin } from "@ggez/game-dev";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
	plugins: [createWebHammerGamePlugin({ initialSceneId: "start-screen", projectName: "stargate-universe" })],
	resolve: {
		alias: {
			"@kopertop/vibe-game-engine": resolve(__dirname, "src/types/vibe-game-engine/index"),
		},
	},
	server: {
		fs: {
			allow: [searchForWorkspaceRoot(process.cwd())]
		}
	},
	build: {
		// S4-10: split each scene into its own chunk so the start menu doesn't
		// pull every scene's geometry/JSON. Three.js + ggez get their own
		// "vendor" chunk to keep the per-scene chunks small and cacheable.
		rollupOptions: {
			output: {
				manualChunks: (id: string) => {
					if (id.includes("node_modules")) {
						if (id.includes("/three/") || id.includes("three-vrm")) return "vendor-three";
						if (id.includes("@ggez/")) return "vendor-ggez";
						return "vendor";
					}
					// Only chunk source files that physically live under a scene
					// directory. Strip Vite query suffixes (e.g. `?raw`) before
					// matching so JSON-as-raw imports still chunk correctly.
					const normalized = id.split("?")[0];
					const sceneMatch = normalized.match(/\/src\/scenes\/([^/]+)\/.+\.(ts|tsx|js|jsx|json)$/);
					if (sceneMatch) return `scene-${sceneMatch[1]}`;
					return undefined;
				},
			},
		},
		chunkSizeWarningLimit: 1500,
	},
});
