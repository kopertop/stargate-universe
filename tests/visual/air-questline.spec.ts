/**
 * Visual (screenshot) regression tests — Air questline
 *
 * Covers all 3 scenes across 15 meaningful visual states.
 * First run creates baseline PNGs in __snapshots__/; subsequent runs diff.
 *
 * URL conventions:
 *   ?scene=<id>   — navigate directly to a scene (wired in main.ts)
 *   &webgl=1      — force WebGPURenderer into WebGL mode (headless-safe)
 *
 * Pattern: page.screenshot() → expect(buffer).toMatchSnapshot()
 * We intentionally avoid toHaveScreenshot() because its internal JS evaluation
 * (for animation-freeze + stability detection) deadlocks the WebGPU renderer
 * in headless Chromium with SwiftShader.  page.screenshot() always works;
 * toMatchSnapshot() does a pure pixel-buffer comparison with no page eval.
 *
 * Test hooks added to each scene's mount():
 *   window.__sceneReady  — true once 3-D setup is live
 *   window.__sguBus      — scoped event bus for emit injection
 *   window.__sguEmit     — global emit (added to main.ts)
 */

import { test, expect, type Page } from "@playwright/test";

// ─── Helpers ─────────────────────────────────────────────────────────────────

const sceneUrl = (sceneId: string) => `/?scene=${sceneId}&webgl=1`;

/** Navigate to a scene and wait for __sceneReady. */
const gotoScene = async (page: Page, sceneId: string) => {
	await page.goto(sceneUrl(sceneId));
	await page.waitForFunction(() => (window as any).__sceneReady === true, {
		timeout: 30_000,
	});
	await page.waitForTimeout(500);
};

/** Emit via the global bus (wired in main.ts). */
const emitEvent = (page: Page, event: string, payload: Record<string, unknown>) =>
	page.evaluate(
		([ev, data]) => (window as any).__sguEmit(ev, data),
		[event, payload] as const,
	);

/** Emit via the scene-scoped bus. */
const emitBus = (page: Page, event: string, payload: Record<string, unknown>) =>
	page.evaluate(
		([ev, data]) => (window as any).__sguBus?.emit(ev, data),
		[event, payload] as const,
	);

/** Save path for named snapshots (also stored to __snapshots__ via toMatchSnapshot). */
const snap = (name: string) => `tests/visual/__snapshots__/${name}.png`;

/** Take a screenshot, save it to disk, and assert it matches the stored baseline. */
const screenshot = async (page: Page, name: string) => {
	const img = await page.screenshot({ path: snap(name) });
	expect(img).toMatchSnapshot(`${name}.png`);
};

// ─── Gate Room ────────────────────────────────────────────────────────────────

test.describe("Gate Room", () => {
	test("1 – initial load: CO₂ HUD critical, Rush present", async ({ page }) => {
		await gotoScene(page, "gate-room");
		const co2El = page.locator("body").filter({ hasText: "Scrubbers: CRITICAL" });
		await expect(co2El).toBeVisible({ timeout: 5_000 });
		await screenshot(page, "01-gate-room-initial");
	});

	test("2 – dialogue panel opens when Rush is spoken to", async ({ page }) => {
		await gotoScene(page, "gate-room");
		// Use the REAL dialogue tree ID ("dr-rush") and the REAL start node ID ("greeting").
		// Previously used "dr-rush-air-crisis" / "co2-intro" — IDs that don't exist anywhere
		// in the codebase, giving false green on a completely broken dialogue system (BUG-004).
		await emitBus(page, "crew:dialogue:started", {
			speakerId: "dr-rush",
			dialogueId: "dr-rush",
		});
		await emitBus(page, "crew:dialogue:node", {
			speakerId: "dr-rush",
			dialogueId: "dr-rush",
			nodeId: "greeting",
			speaker: "Dr. Rush",
			text: "Wallace. Good — I need someone who can move fast. The CO\u2082 scrubbers are failing.",
			options: [
				{ id: "ask-what-needed", label: "What exactly do we need? Lime like the fruit?" },
				{ id: "ask-timeline",    label: "Twelve hours. How certain are you?" },
				{ id: "ask-planet",      label: "What about the planet we just passed?" },
				{ id: "commit-to-gate",  label: "Tell me what I need to know. I'll go through the gate." },
				{ id: "farewell-early",  label: "I need a moment to think." },
			],
		});
		await page.waitForTimeout(300);
		await screenshot(page, "02-gate-room-dialogue-open");
	});

	test("3 – dialogue shows 3 response branches", async ({ page }) => {
		await gotoScene(page, "gate-room");
		// Real IDs: dialogueId = "dr-rush", nodeId = "greeting" (BUG-004 fix)
		await emitBus(page, "crew:dialogue:started", {
			speakerId: "dr-rush",
			dialogueId: "dr-rush",
		});
		await emitBus(page, "crew:dialogue:node", {
			speakerId: "dr-rush",
			dialogueId: "dr-rush",
			nodeId: "greeting",
			speaker: "Dr. Rush",
			text: "The CO\u2082 scrubbers are failing.",
			options: [
				{ id: "ask-what-needed", label: "What exactly do we need?" },
				{ id: "ask-timeline",    label: "Twelve hours. How certain are you?" },
				{ id: "commit-to-gate",  label: "I'll go through the gate." },
			],
		});
		await page.waitForTimeout(300);
		await screenshot(page, "03-gate-room-dialogue-options");
	});

	test("4 – gate dialing: G key triggers stargate spin-up", async ({ page }) => {
		await gotoScene(page, "gate-room");
		await page.keyboard.press("KeyG");
		await page.waitForTimeout(2_000);
		await screenshot(page, "04-gate-room-dialing");
	});

	test("5 – lime banner shown after returning from desert planet", async ({ page }) => {
		// Navigate with ?lime=1 so gate-room's mount() calls setLimeCollected(true)
		// before creating the banner. This tests the REAL banner element created by
		// the game — the old test injected fake DOM and proved nothing (BUG-004 fix).
		await page.goto(`/?scene=gate-room&lime=1&webgl=1`);
		await page.waitForFunction(() => (window as any).__sceneReady === true, {
			timeout: 30_000,
		});
		await page.waitForTimeout(400);
		// Assert the real game banner (id added to gate-room mount alongside this fix)
		await expect(page.locator("#lime-delivery-banner")).toBeVisible();
		await screenshot(page, "05-gate-room-lime-banner");
	});
});

// ─── Desert Planet ────────────────────────────────────────────────────────────

test.describe("Desert Planet", () => {
	test("6 – initial arrival: desert visible, compass top-right, CO₂ countdown", async ({ page }) => {
		await gotoScene(page, "desert-planet");
		await screenshot(page, "06-desert-planet-initial");
	});

	test("7 – three glowing calcium deposit markers visible", async ({ page }) => {
		await gotoScene(page, "desert-planet");
		await page.waitForTimeout(800);
		await screenshot(page, "07-desert-planet-deposits");
	});

	test("8 – one deposit collected: resource:collected event updates HUD", async ({ page }) => {
		await gotoScene(page, "desert-planet");
		await emitEvent(page, "resource:collected", {
			type: "calcium-deposit",
			amount: 1,
			source: "desert-planet",
		});
		await page.waitForTimeout(400);
		await screenshot(page, "08-desert-planet-one-collected");
	});

	test("9 – all three deposits collected: gate return prompt visible", async ({ page }) => {
		await gotoScene(page, "desert-planet");
		for (let i = 0; i < 3; i++) {
			await emitEvent(page, "resource:collected", {
				type: "calcium-deposit",
				amount: 1,
				source: "desert-planet",
			});
			await page.waitForTimeout(150);
		}
		await page.waitForTimeout(400);
		await screenshot(page, "09-desert-planet-all-collected");
	});

	test("10 – gate return E-key prompt appears when near gate", async ({ page }) => {
		await gotoScene(page, "desert-planet");
		// Teleport player to the gate via window.__sgPlayer if exposed
		await page.evaluate(() => {
			if ((window as any).__sgPlayer) {
				(window as any).__sgPlayer.object.position.set(0, 0, 0);
			}
		});
		// Emit all deposits first so gate prompt isn't blocked by "collect first"
		for (let i = 0; i < 3; i++) {
			await emitEvent(page, "resource:collected", {
				type: "calcium-deposit",
				amount: 1,
				source: "desert-planet",
			});
		}
		await page.waitForTimeout(600);
		await screenshot(page, "10-desert-planet-gate-prompt");
	});
});

// ─── Scrubber Room ────────────────────────────────────────────────────────────

test.describe("Scrubber Room", () => {
	test("11 – initial arrival: red pulsing status lights, repair panel visible", async ({ page }) => {
		await gotoScene(page, "scrubber-room");
		await page.waitForTimeout(600);
		await screenshot(page, "11-scrubber-room-initial");
	});

	test("12 – without lime: blocked interaction message shown", async ({ page }) => {
		await gotoScene(page, "scrubber-room");
		// E key without lime → "You need to find a calcium source first."
		await page.keyboard.press("KeyE");
		await page.waitForTimeout(300);
		await screenshot(page, "12-scrubber-room-no-lime");
	});

	test("13 – repair event: scrubbers transition to green on ship:subsystem:repaired", async ({ page }) => {
		await gotoScene(page, "scrubber-room");
		await emitEvent(page, "ship:subsystem:repaired", {
			subsystemId: "co2-scrubbers",
			condition: 1.0,
		});
		await page.waitForTimeout(300);
		await screenshot(page, "13-scrubber-room-repair-transition");
	});

	test("14 – fully repaired: green lights, Rush dialogue ready", async ({ page }) => {
		await gotoScene(page, "scrubber-room");
		await emitEvent(page, "ship:subsystem:repaired", {
			subsystemId: "co2-scrubbers",
			condition: 1.0,
		});
		await page.waitForTimeout(2_000);
		await screenshot(page, "14-scrubber-room-repaired");
	});

	test("15 – quest complete: CO₂ HUD normalises after repair", async ({ page }) => {
		await gotoScene(page, "scrubber-room");
		await emitEvent(page, "ship:subsystem:repaired", {
			subsystemId: "co2-scrubbers",
			condition: 1.0,
		});
		await emitEvent(page, "quest:objective-complete", {
			questId: "air-crisis",
			objectiveId: "fix-scrubbers",
		});
		await emitEvent(page, "quest:completed", {
			questId: "air-crisis",
		});
		await page.waitForTimeout(2_500);
		await screenshot(page, "15-scrubber-room-quest-complete");
	});
});
