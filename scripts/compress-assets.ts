/**
 * S4-02 + S4-03 — Asset compression pass.
 *
 * Walks every `.glb`/`.vrm` under `assets/`, `public/`, `src/` and
 * shells out to `gltf-transform optimize` with:
 *   - DRACO geometry compression
 *   - KTX2 (basis/UASTC) texture compression
 *   - Texture resize cap at 2048
 *   - Mesh joining / instancing / dedup
 *
 * Originals are stashed alongside as `<name>.glb.orig` on the first run
 * so a re-run is idempotent (we read from `.orig` if it exists). To
 * restore: `find . -name '*.orig' -exec sh -c 'mv "$0" "${0%.orig}"' {} \;`
 *
 * Usage:
 *   bun run scripts/compress-assets.ts            # compress everything
 *   bun run scripts/compress-assets.ts --restore  # restore .orig files
 *   bun run scripts/compress-assets.ts <substr>   # restrict to substring match
 */
import { readdir, stat, copyFile, access, rename, mkdir } from "node:fs/promises";
import { join, extname, relative } from "node:path";
import { spawn } from "node:child_process";

const ROOT = process.cwd();
const TARGET_DIRS = ["assets", "public", "src"];
// Stash uncompressed originals OUTSIDE the asset roots — Vite/rollup picks
// up `*.orig` siblings as static assets and ships them in `dist/`. Keeping
// originals here makes restore possible without bloating the build.
const ORIG_STASH_DIR = ".asset-originals";
const origPathFor = (file: string): string =>
	join(ROOT, ORIG_STASH_DIR, relative(ROOT, file).replace(/[\\/]/g, "__") + ".orig");
// .vrm intentionally excluded — gltf-transform's optimize pass strips the
// VRMC_* extensions (springBone, vrm, materials_mtoon, node_constraint),
// which breaks character spring physics and MToon shading. VRM compression
// needs a VRM-aware tool (e.g. vrm-validator + manual mesh-only DRACO);
// flag for Sprint 5 follow-up.
const TARGET_EXTS = new Set([".glb"]);
const SKIP_BELOW_BYTES = 100 * 1024;
const args = process.argv.slice(2);
const restore = args.includes("--restore");
const restrict = args.find((a) => !a.startsWith("--"));

const fileExists = async (p: string): Promise<boolean> => {
	try { await access(p); return true; } catch { return false; }
};

const walk = async (dir: string, out: string[] = []): Promise<string[]> => {
	let entries;
	try { entries = await readdir(dir, { withFileTypes: true }); } catch { return out; }
	for (const e of entries) {
		const full = join(dir, e.name);
		if (e.isDirectory()) {
			if (e.name === "node_modules" || e.name.startsWith(".")) continue;
			await walk(full, out);
		} else if (TARGET_EXTS.has(extname(e.name).toLowerCase()) && !e.name.endsWith(".orig")) {
			out.push(full);
		}
	}
	return out;
};

const formatBytes = (n: number): string =>
	n > 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(2)} MB` : `${(n / 1024).toFixed(1)} kB`;

const runOptimize = (input: string, output: string): Promise<void> =>
	new Promise((resolve, reject) => {
		// `gltf-transform optimize` is the all-in-one pass: DRACO geometry,
		// KTX2 textures, mesh joining, dedup, prune. We disable `--flatten`
		// because some VRM rigs depend on intermediate transforms; flattening
		// breaks bone hierarchy / spring chains.
		const child = spawn("bunx", [
			"gltf-transform", "optimize", input, output,
			"--compress", "draco",
			"--texture-compress", "webp",
			"--texture-size", "2048",
			"--flatten", "false",
			"--join", "false",
		], { stdio: ["ignore", "pipe", "pipe"] });
		let stderr = "";
		child.stderr.on("data", (d) => { stderr += d.toString(); });
		child.on("close", (code) => {
			if (code === 0) resolve();
			else reject(new Error(`exit ${code}: ${stderr.split("\n").slice(-5).join("\n")}`));
		});
	});

const main = async () => {
	const all: string[] = [];
	for (const d of TARGET_DIRS) await walk(join(ROOT, d), all);
	const files = restrict
		? all.filter((f) => f.includes(restrict))
		: all;

	if (restore) {
		console.log("Restoring .orig files…");
		for (const f of files) {
			const orig = origPathFor(f);
			if (await fileExists(orig)) {
				await rename(orig, f);
				console.log(`  restored ${relative(ROOT, f)}`);
			}
		}
		return;
	}

	await mkdir(join(ROOT, ORIG_STASH_DIR), { recursive: true });

	console.log(`Found ${files.length} compressible files (glb/vrm)\n`);

	let totalBefore = 0;
	let totalAfter = 0;

	for (const file of files) {
		const rel = relative(ROOT, file);
		const orig = origPathFor(file);
		const sourceFile = (await fileExists(orig)) ? orig : file;
		const before = (await stat(sourceFile)).size;
		totalBefore += before;

		if (before < SKIP_BELOW_BYTES) {
			totalAfter += before;
			console.log(`  ${rel}: ${formatBytes(before)} (skipped — below 100 kB)`);
			continue;
		}

		try {
			if (sourceFile === file && !(await fileExists(orig))) {
				await copyFile(file, orig);
			}
			await runOptimize(orig, file);
			const after = (await stat(file)).size;
			totalAfter += after;
			console.log(`  ${rel}: ${formatBytes(before)} → ${formatBytes(after)} (${((1 - after / before) * 100).toFixed(1)}% smaller)`);
		} catch (err) {
			console.error(`  ${rel}: FAILED — ${(err as Error).message}`);
			totalAfter += before;
		}
	}

	console.log(`\nTotal: ${formatBytes(totalBefore)} → ${formatBytes(totalAfter)} (${((1 - totalAfter / totalBefore) * 100).toFixed(1)}% reduction)`);
};

await main();
