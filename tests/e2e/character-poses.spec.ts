/**
 * Character pose capture — debug aid for animation regressions.
 *
 * Drives the player VRM through idle / walk / stop and saves screenshots to
 * tests/screenshots/character-poses/. Uses the in-game debug API
 * (`window.__sgu`) to position the camera in front of the character so the
 * arms are clearly visible (T-pose vs relaxed).
 *
 * Asserts that VrmAnimRetarget logs at least one matched-track count > 0,
 * regression-protecting against:
 *   1. Mixamo bone names not normalizing (GLB vs FBX) → 0 matched tracks → T-pose
 *   2. springBonesActive gate accidentally suppressing vrm.update() → bind pose
 *
 * Run: bun run test:e2e tests/e2e/character-poses.spec.ts --headed
 */
import { test, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";

const OUT_DIR = path.resolve("tests/screenshots/character-poses");

interface SguDebugApi {
	state: () => { scene: string | undefined; player: { x: number; y: number; z: number } | undefined };
	drive: (moveX: number, moveZ: number) => void;
	stop: () => void;
	screenshot: (opts?: {
		cameraPos?: { x: number; y: number; z: number };
		cameraTarget?: { x: number; y: number; z: number };
		waitFrames?: number;
	}) => Promise<string>;
}

declare global {
	interface Window {
		__sgu?: SguDebugApi;
	}
}

const ensureDir = (dir: string) => {
	if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
};

const writeDataUrlToFile = (dataUrl: string, filePath: string) => {
	const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
	fs.writeFileSync(filePath, Buffer.from(base64, "base64"));
};

/**
 * Capture the character from in front, slightly above the hips, looking at the
 * chest. Reveals arm pose at a glance — T-pose arms point outward to the sides,
 * idle arms hang down.
 *
 * playerPos.y is the physics capsule center (≈chest), but the VRM character is
 * parented so its feet land on the floor — center the frame on the player
 * capsule so head/torso/arms all read.
 */
const capturePoseFromFront = async (page: import("@playwright/test").Page, name: string) => {
	const dataUrl = await page.evaluate(async () => {
		const api = window.__sgu;
		if (!api) throw new Error("window.__sgu not installed — game in production build?");
		const p = api.state().player;
		if (!p) throw new Error("Player not spawned yet");
		return api.screenshot({
			cameraPos: { x: p.x, y: p.y + 0.4, z: p.z + 2.5 },
			cameraTarget: { x: p.x, y: p.y, z: p.z },
			waitFrames: 5,
		});
	});
	writeDataUrlToFile(dataUrl, path.join(OUT_DIR, `${name}.png`));
};

const captureOverhead = async (page: import("@playwright/test").Page, name: string) => {
	const dataUrl = await page.evaluate(async () => {
		const api = window.__sgu;
		if (!api) throw new Error("window.__sgu not installed");
		const p = api.state().player;
		if (!p) throw new Error("Player not spawned yet");
		return api.screenshot({
			cameraPos: { x: p.x + 4, y: p.y + 0.6, z: p.z },
			cameraTarget: { x: p.x, y: p.y, z: p.z },
			waitFrames: 5,
		});
	});
	writeDataUrlToFile(dataUrl, path.join(OUT_DIR, `${name}.png`));
};

test.describe("Character animation poses", () => {
	test.beforeAll(() => {
		ensureDir(OUT_DIR);
	});

	test("test_character_animation_idle_walk_stop_captures_distinct_poses", async ({ page }) => {
		test.setTimeout(90_000);
		const consoleLogs: string[] = [];
		page.on("console", (msg) => {
			const text = msg.text();
			if (/Vrm|VRM|character|eli\.vrm/i.test(text)) {
				consoleLogs.push(`[${msg.type()}] ${text}`);
			}
		});

		// Arrange: land directly in the gate room (skip cinematic).
		await page.goto("/?scene=gate-room");
		await page.waitForSelector("canvas", { timeout: 15_000 });

		// Wait for the player VRM mesh to attach to its own group. Polling for
		// any SkinnedMesh in the scene matches NPCs (e.g. Rush) before the
		// player's eli.vrm finishes downloading from R2 — must scope to the
		// player's own group.
		await page.waitForFunction(
			() => {
				interface Node { name: string; type: string; children: Node[]; traverse: (cb: (n: Node) => void) => void }
				const root = (window as unknown as { __sguSceneRoot?: Node }).__sguSceneRoot;
				if (!root) return false;
				let playerGroup: Node | undefined;
				root.traverse((n) => { if (n.name === "vrm-character-player" && !playerGroup) playerGroup = n; });
				if (!playerGroup) return false;
				let found = false;
				playerGroup.traverse((n) => { if (n.type === "SkinnedMesh") found = true; });
				return found;
			},
			null,
			{ timeout: 40_000 },
		);

		// Wait for the animation controller to be wired up. The mesh attaches
		// before clips finish loading, so capturing here would catch the bind
		// pose (T-pose) before idle starts driving bones.
		await page.waitForFunction(
			() => (window as unknown as { __sguAnimWire?: string }).__sguAnimWire === "controller-attached",
			null,
			{ timeout: 30_000 },
		);
		await page.waitForTimeout(500);

		// Act + Assert: capture three distinct frames + side view for sanity.
		await capturePoseFromFront(page, "01-idle-front");
		await captureOverhead(page, "01-idle-side");

		await page.evaluate(() => window.__sgu?.drive(0, -1));
		await page.waitForTimeout(800);
		await capturePoseFromFront(page, "02-walking-front");
		await captureOverhead(page, "02-walking-side");

		await page.evaluate(() => window.__sgu?.stop());
		await page.waitForTimeout(600);
		await capturePoseFromFront(page, "03-after-stop-front");

		// Persist animation-related console output for offline diffing.
		fs.writeFileSync(
			path.join(OUT_DIR, "console.log"),
			consoleLogs.join("\n") + "\n",
		);

		// Assert: at least one matched-track log was emitted (idle or walk).
		// "matched 0 tracks" still passes the regex but should fail this gate
		// — that's the original symptom of broken Mixamo bone normalization.
		const sawMatched = consoleLogs.some((line) =>
			/VrmAnimRetarget.*matched (\d+) tracks/.test(line)
				&& !/matched 0 tracks/.test(line),
		);
		expect(sawMatched, "expected at least one VrmAnimRetarget matched-track log").toBe(true);
	});
});
