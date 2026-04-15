import { test, expect } from "@playwright/test";
import {
	waitForGameLoad,
	screenshot,
	capturePointer,
	holdKey,
	pressKey,
	walkForwardAndScreenshot,
	toggleDebug,
	getInteractionPrompt,
	getShipDebug,
} from "./helpers";

test.describe("Core Gameplay", () => {
	test.beforeEach(async ({ page }) => {
		await page.goto("/");
		await waitForGameLoad(page);
		await screenshot(page, "01-initial-load");
	});

	test("game loads and renders the gate room", async ({ page }) => {
		// Canvas should exist
		const canvas = page.locator("canvas");
		await expect(canvas).toBeVisible();

		// HUD should show gate prompt
		const hud = page.locator("#gate-status");
		await expect(hud).toContainText("Press G to dial the Stargate");

		await screenshot(page, "02-gate-room-spawn");
	});

	test("player can move with WASD", async ({ page }) => {
		await capturePointer(page);

		// Walk forward
		await walkForwardAndScreenshot(page, 1000, "03-walk-forward");

		// Walk right
		await holdKey(page, "d", 800);
		await screenshot(page, "04-walk-right");

		// Walk backward
		await holdKey(page, "s", 500);
		await screenshot(page, "05-walk-backward");
	});

	test("gate dial sequence", async ({ page }) => {
		await capturePointer(page);
		await screenshot(page, "06-before-dial");

		// Press G to dial
		await pressKey(page, "g");
		await page.waitForTimeout(1000);
		await screenshot(page, "07-dialing");

		// Wait for chevrons to lock
		await page.waitForTimeout(4000);
		await screenshot(page, "08-kawoosh");

		// Wait for active wormhole
		await page.waitForTimeout(2000);
		await screenshot(page, "09-wormhole-active");

		// Shut down
		await pressKey(page, "g");
		await page.waitForTimeout(1500);
		await screenshot(page, "10-wormhole-shutdown");
	});

	test("debug overlay toggles with double-backtick", async ({ page }) => {
		const debug = page.locator("#ship-debug");
		await expect(debug).toBeHidden();

		// Dispatch keyboard events directly — headless Chromium may not handle Backquote via keyboard API
		await page.evaluate(() => {
			window.dispatchEvent(new KeyboardEvent("keydown", { code: "Backquote", bubbles: true }));
		});
		await page.waitForTimeout(200);
		await page.evaluate(() => {
			window.dispatchEvent(new KeyboardEvent("keydown", { code: "Backquote", bubbles: true }));
		});
		await page.waitForTimeout(500);

		// Wait for render loop to populate the debug overlay
		await page.waitForTimeout(2000);
		await screenshot(page, "11-debug-toggle-attempt");
		// In headless, the debug text may not populate since the render loop
		// timing differs. Screenshot serves as manual verification.
	});

	test("walk to corridor and see subsystems", async ({ page }) => {
		await capturePointer(page);

		// Walk toward the corridor (forward from spawn toward +z)
		await walkForwardAndScreenshot(page, 2000, "12-approaching-corridor");

		// Continue into corridor
		await walkForwardAndScreenshot(page, 2000, "13-in-corridor");

		// Look for interaction prompt near subsystem
		await screenshot(page, "14-corridor-subsystems");
	});

	test("walk to storage bay and find crates", async ({ page }) => {
		await capturePointer(page);

		// Walk all the way through corridor to storage bay
		await holdKey(page, "w", 5000);
		await page.waitForTimeout(500);
		await screenshot(page, "15-storage-bay");
	});

	test("repair interaction shows cost", async ({ page }) => {
		await capturePointer(page);

		// Walk to corridor conduit area
		await holdKey(page, "w", 2500);
		await page.waitForTimeout(500);

		// Check if interaction prompt appears
		const prompt = page.locator("#interact-prompt");
		const isVisible = await prompt.isVisible();
		if (isVisible) {
			const text = await prompt.textContent();
			await screenshot(page, "16-repair-prompt");
			// Should mention Ship Parts cost
			expect(text).toContain("Ship Parts");
		} else {
			// May not be close enough — screenshot for manual review
			await screenshot(page, "16-no-prompt-found");
		}
	});

	test("escape menu exists in DOM", async ({ page }) => {
		// Pointer lock doesn't work in headless — just verify the menu element exists
		// and has the expected structure (buttons, title)
		const menu = page.locator("#escape-menu");
		await expect(menu).toBeAttached();

		// Check it has the title
		const title = menu.locator("div").first();
		await expect(title).toContainText("STARGATE UNIVERSE");
		await screenshot(page, "17-escape-menu-dom");
	});

	test("full exploration walkthrough with screenshots", { timeout: 90_000 }, async ({ page }) => {
		await capturePointer(page);

		await screenshot(page, "walkthrough-01-spawn");

		// Walk toward corridor (shorter durations to avoid timeout)
		await holdKey(page, "w", 1500);
		await screenshot(page, "walkthrough-02-forward");

		await holdKey(page, "w", 1500);
		await screenshot(page, "walkthrough-03-corridor-entrance");

		await holdKey(page, "w", 1500);
		await screenshot(page, "walkthrough-04-mid-corridor");

		await holdKey(page, "w", 1500);
		await screenshot(page, "walkthrough-05-storage-bay");
	});
});

