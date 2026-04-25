/**
 * Frame-by-frame cinematic validation.
 *
 * Walks the 40-second gate-room arrival cinematic at 2-second intervals
 * by reloading with ?cinstep=N, captures a screenshot at each step, and
 * asserts a small machine-checkable property about the visible state
 * (camera position, subtitle text, HUD visibility, chevron count).
 *
 * Run with: `bunx playwright test tests/visual/cinematic-frame-by-frame.spec.ts`
 *
 * Requires preview server running on :5173.
 */
import { test, expect, type Page } from "@playwright/test";

// ─── Expected timeline markers ────────────────────────────────────────────

type FrameExpect = {
	/** cinstep value in seconds */
	t: number;
	/** short tag for the screenshot filename */
	label: string;
	/** human-readable description of what should be on screen */
	description: string;
	/** optional subtitle substring that should be visible at this step */
	expectedSubtitle?: string;
	/** if true, HUD elements (CO₂, compass, gate prompt) MUST be hidden */
	hudShouldBeHidden?: boolean;
};

// Times are in the gate-room cinematic's local clock (0-40s).
// The full opening is 0-60s absolute: 0-20s opening-cinematic
// (ship reveal), 20-60s gate-room arrival. These frames test
// the gate-room arrival in isolation.
const FRAMES: FrameExpect[] = [
	{ t: 0,  label: "01-establish-start",
		description: "Wide establishing, dormant gate",
		hudShouldBeHidden: true },
	{ t: 3,  label: "02-dial-start",
		description: "Chevrons dialing — chevron 1-2 lit",
		expectedSubtitle: "Chevrons locking",
		hudShouldBeHidden: true },
	{ t: 8,  label: "03-dial-mid",
		description: "Chevrons 5-6 lit, still wide shot",
		hudShouldBeHidden: true },
	{ t: 12, label: "04-kawoosh",
		description: "Kawoosh! Event horizon forming, 9 chevrons lit",
		expectedSubtitle: "Wormhole established",
		hudShouldBeHidden: true },
	{ t: 16, label: "05-scott-emerge",
		description: "Scott emerges through the gate (low angle)",
		expectedSubtitle: "clear",
		hudShouldBeHidden: true },
	{ t: 22, label: "06-overhead-start",
		description: "Overhead wide shot — gate visible, crew landing",
		hudShouldBeHidden: true },
	{ t: 26, label: "07-overhead-chaos",
		description: "Overhead — multiple crew on the floor",
		hudShouldBeHidden: true },
	{ t: 30, label: "08-overhead-end",
		description: "Overhead — Young has hit the wall",
		hudShouldBeHidden: true },
	{ t: 34, label: "09-scott-crouch",
		description: "Descent to Eli on ground, Scott crouching in",
		hudShouldBeHidden: true },
	{ t: 38, label: "10-fade",
		description: "Final beat before cinematic hands off",
		hudShouldBeHidden: true },
];

// ─── Test setup ────────────────────────────────────────────────────────────

const gotoStep = async (page: Page, cinstep: number): Promise<void> => {
	// sessionStorage must be set BEFORE navigation so the gate-room scene
	// boots in cinematic mode. Navigate first to set, then reload.
	await page.goto("http://localhost:5173/");
	await page.evaluate(() => { sessionStorage.setItem("sgu-new-game", "1"); });
	// cinfreeze=1 pins the cinematic clock at cinstep so slow VRM streams
	// (Eli + Rush are ~10 MB each) don't advance past our target beat while
	// we're waiting. Without it, a 12s load-settle would push elapsed to 34+
	// regardless of which cinstep we requested.
	await page.goto(`http://localhost:5173/?scene=gate-room&cinstep=${cinstep}&cinfreeze=1`);
	// Wait for the scene to signal readiness; generous timeout because
	// the VRM fetches from R2 can take a moment.
	await page.waitForFunction(() => (window as unknown as { __sceneReady?: boolean }).__sceneReady === true, { timeout: 15_000 });
	// The loading screen waits for `character:model:loaded` which fires only
	// after the player VRM streams in from R2. During cinematic verification we
	// don't care about the overlay — remove it so screenshots capture the scene.
	await page.evaluate(() => {
		document.querySelectorAll(".loading-screen").forEach((el) => el.remove());
	});
	// Generous settle for the full crew pipeline: 5 crew VRM fetches (Eli/Rush
	// are ~10 MB each from R2) + retarget + one render frame so the
	// cinstep-adjusted camera has drawn. Headless Chromium can be slow here.
	await page.waitForTimeout(12_000);
};

const assertHudHidden = async (page: Page): Promise<void> => {
	// Walk ancestor chain checking display/visibility — this catches the common
	// case where a child HUD element has display:block but its parent container
	// is display:none. We cannot rely on offsetParent because position:fixed
	// elements always have offsetParent=null even when visible.
	const visible = await page.evaluate(() => {
		const ids = ["gate-hud", "gate-chevrons", "gate-status", "co2-display", "compass-hud"];
		const isEffectivelyVisible = (el: HTMLElement): boolean => {
			for (let node: HTMLElement | null = el; node; node = node.parentElement) {
				const cs = window.getComputedStyle(node);
				if (cs.display === "none" || cs.visibility === "hidden" || cs.opacity === "0") {
					return false;
				}
			}
			return true;
		};
		const visibleElements: string[] = [];
		for (const id of ids) {
			const el = document.getElementById(id) as HTMLElement | null;
			if (!el) continue;
			if (isEffectivelyVisible(el)) visibleElements.push(id);
		}
		return visibleElements;
	});
	expect(visible, "HUD elements should be hidden during cinematic").toEqual([]);
};

const assertSubtitleContains = async (page: Page, needle: string): Promise<void> => {
	// The cinematic's subtitle element is a bottom-anchored div appended
	// to body by createSubtitle(). Scan all divs for the text.
	const found = await page.evaluate((n: string) => {
		const divs = Array.from(document.querySelectorAll("div"));
		return divs.some((d) => d.textContent && d.textContent.toLowerCase().includes(n.toLowerCase()) && d.offsetParent !== null);
	}, needle);
	expect(found, `expected subtitle matching "${needle}"`).toBe(true);
};

// ─── Tests ─────────────────────────────────────────────────────────────────

test.describe("Gate-room arrival cinematic — frame-by-frame", () => {
	for (const frame of FRAMES) {
		test(`t=${frame.t}s — ${frame.description}`, async ({ page }) => {
			await gotoStep(page, frame.t);
			await expect(page).toHaveScreenshot(`${frame.label}.png`, { maxDiffPixels: 2000 });
			if (frame.hudShouldBeHidden) {
				await assertHudHidden(page);
			}
			if (frame.expectedSubtitle) {
				await assertSubtitleContains(page, frame.expectedSubtitle);
			}
		});
	}

	test("post-cinematic: scott dialogue appears, eli is prone", async ({ page }) => {
		// Skip cinematic by setting cinstep near end — natural finish
		// triggers the dialogue + prone pose.
		await gotoStep(page, 40);
		// Wait for dialogue panel or timeout
		await page.waitForTimeout(3000);
		// Dialogue panel is created via @kopertop/vibe-game-engine; text
		// should contain "Eli" from the scott-opening tree.
		const hasScottLine = await page.evaluate(() => {
			const divs = Array.from(document.querySelectorAll("div"));
			return divs.some((d) => d.textContent && d.textContent.includes("Eli") && d.offsetParent !== null);
		});
		expect(hasScottLine, "Scott's opening line should be visible post-cinematic").toBe(true);
	});
});
