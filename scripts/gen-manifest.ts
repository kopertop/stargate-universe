/**
 * Build script — generates public/manifest.webmanifest.
 * Run as part of `bun run build` or manually with `bun run scripts/gen-manifest.ts`.
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputPath = `${__dirname}/../public/manifest.webmanifest`;

const manifest = {
	name: "Stargate Universe",
	short_name: "SGU",
	description: "Survive aboard the Ancient vessel Destiny — a browser-native sci-fi RPG.",
	start_url: "/?pwa=1",
	scope: "/",
	display: "fullscreen",
	orientation: "landscape",
	background_color: "#000005",
	theme_color: "#4488ff",
	categories: ["games", "entertainment"],
	lang: "en-US",
	icons: [
		{ src: "/icons/icon-192.svg",          sizes: "192x192", type: "image/svg+xml", purpose: "any" },
		{ src: "/icons/icon-512.svg",          sizes: "512x512", type: "image/svg+xml", purpose: "any" },
		{ src: "/icons/icon-maskable-512.svg", sizes: "512x512", type: "image/svg+xml", purpose: "maskable" },
	],
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`✓ wrote ${outputPath}`);
