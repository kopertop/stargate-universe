import { defineConfig, searchForWorkspaceRoot } from "vite";
import { createWebHammerGamePlugin } from "@ggez/game-dev";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  plugins: [createWebHammerGamePlugin({ initialSceneId: "destiny-gate-room", projectName: "stargate-universe" })],
  resolve: {
    alias: {
      "@kopertop/vibe-game-engine": resolve(__dirname, "src/types/vibe-game-engine/index"),
    },
  },
  server: {
    fs: {
      allow: [searchForWorkspaceRoot(process.cwd())]
    }
  }
});
