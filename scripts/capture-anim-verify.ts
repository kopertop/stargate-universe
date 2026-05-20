/**
 * Capture player animation frames (jump, strafe) for visual verification.
 *
 * Usage: bun run scripts/capture-anim-verify.ts
 * Output: scripts/screenshots/anim-verify/*.png
 */
import { chromium } from "playwright";
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";

const BASE_URL = "http://localhost:5173";
const OUT = join(import.meta.dirname, "screenshots", "anim-verify");

async function waitReady(page: import("playwright").Page): Promise<void> {
	await page.waitForFunction(
		() => (window as unknown as { __sceneReady?: boolean }).__sceneReady === true,
		{ timeout: 45_000 },
	);
	await page.waitForTimeout(4000);
}

async function shot(
	page: import("playwright").Page,
	name: string,
	cam: { pos: { x: number; y: number; z: number }; target: { x: number; y: number; z: number } },
): Promise<void> {
	const dataUrl = await page.evaluate(
		({ pos, target }) => {
			const sgu = (window as unknown as {
				__sgu?: {
					screenshot: (o?: {
						cameraPos?: typeof pos;
						cameraTarget?: typeof target;
						waitFrames?: number;
					}) => Promise<string>;
				};
			}).__sgu;
			if (!sgu) throw new Error("__sgu missing");
			return sgu.screenshot({ cameraPos: pos, cameraTarget: target, waitFrames: 8 });
		},
		cam,
	);
	const base64 = dataUrl.split(",")[1];
	const buf = Buffer.from(base64, "base64");
	const path = join(OUT, `${name}.png`);
	writeFileSync(path, buf);
	console.log(`  saved ${path} (${buf.length} bytes)`);
}

async function main(): Promise<void> {
	mkdirSync(OUT, { recursive: true });

	const browser = await chromium.launch({
		headless: false,
		args: ["--enable-unsafe-webgpu"],
	});
	const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });

	// Side view of player in gate room (jump enabled)
	await page.goto(`${BASE_URL}/?scene=gate-room&webgl=1`);
	await waitReady(page);

	const player = await page.evaluate(() => {
		const sgu = (window as unknown as {
			__sgu?: { state: () => { player?: { x: number; y: number; z: number } } };
		}).__sgu;
		return sgu?.state().player ?? { x: 0, y: 0, z: 0 };
	});
	console.log("  player at", player);

	// Third-person side + front views — offset from live player position
	const sideCam = {
		pos: { x: player.x + 3.5, y: player.y + 1.35, z: player.z + 0.2 },
		target: { x: player.x, y: player.y + 1.05, z: player.z },
	};
	const frontCam = {
		pos: { x: player.x, y: player.y + 1.35, z: player.z + 3.5 },
		target: { x: player.x, y: player.y + 1.05, z: player.z },
	};

	await shot(page, "01-idle", sideCam);

	// Strafe left (hold A)
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { drive: (x: number, z: number) => void } }).__sgu;
		sgu?.drive(-1, 0);
	});
	await page.waitForTimeout(1800);
	await shot(page, "02-strafe-left-side", sideCam);
	await shot(page, "02b-strafe-left-front", frontCam);
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { stop: () => void } }).__sgu;
		sgu?.stop();
	});
	await page.waitForTimeout(800);

	// Strafe right
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { drive: (x: number, z: number) => void } }).__sgu;
		sgu?.drive(1, 0);
	});
	await page.waitForTimeout(1800);
	await shot(page, "03-strafe-right-side", sideCam);
	await shot(page, "03b-strafe-right-front", frontCam);
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { stop: () => void } }).__sgu;
		sgu?.stop();
	});
	await page.waitForTimeout(800);

	// Jump — capture a few frames after Space
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { press: (a: string) => void } }).__sgu;
		sgu?.press("jump");
	});
	const jumpFrames: Array<{ waitMs: number; tag: string }> = [
		{ waitMs: 100, tag: "04-jump-t100ms" },
		{ waitMs: 150, tag: "05-jump-t250ms" },
		{ waitMs: 200, tag: "06-jump-t450ms" },
		{ waitMs: 300, tag: "07-jump-t750ms" },
	];
	for (const frame of jumpFrames) {
		await page.waitForTimeout(frame.waitMs);
		await shot(page, frame.tag, sideCam);
	}

	// Forward run for locomotion baseline
	await page.evaluate(() => {
		const sgu = (window as unknown as { __sgu?: { drive: (x: number, z: number) => void } }).__sgu;
		sgu?.drive(0, 1);
	});
	await page.waitForTimeout(1500);
	await shot(page, "08-run-forward", sideCam);

	await browser.close();
	console.log("\nDone — review scripts/screenshots/anim-verify/");
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
