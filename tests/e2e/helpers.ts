import { type Page } from "@playwright/test";
import * as path from "path";

const SCREENSHOT_DIR = path.resolve("tests/screenshots");

/** Wait for the game canvas to be present and WebGPU to initialize */
export async function waitForGameLoad(page: Page): Promise<void> {
	// Wait for the canvas element to appear
	await page.waitForSelector("canvas", { timeout: 10_000 });
	// Give the renderer a moment to draw the first frame
	await page.waitForTimeout(2000);
}

/** Take a named screenshot and save to tests/screenshots/ */
export async function screenshot(page: Page, name: string): Promise<void> {
	await page.screenshot({
		path: path.join(SCREENSHOT_DIR, `${name}.png`),
		fullPage: false,
	});
}

/** Click the canvas to capture pointer lock */
export async function capturePointer(page: Page): Promise<void> {
	const canvas = page.locator("canvas");
	await canvas.click();
	await page.waitForTimeout(500);
}

/** Press and hold a key for a duration (simulates walking) */
export async function holdKey(page: Page, key: string, durationMs: number): Promise<void> {
	await page.keyboard.down(key);
	await page.waitForTimeout(durationMs);
	await page.keyboard.up(key);
}

/** Press a key once */
export async function pressKey(page: Page, key: string): Promise<void> {
	await page.keyboard.press(key);
}

/** Simulate mouse movement (for camera rotation) */
export async function moveMouse(page: Page, deltaX: number, deltaY: number): Promise<void> {
	// Move relative to center of viewport
	const viewport = page.viewportSize();
	if (!viewport) return;
	const cx = viewport.width / 2;
	const cy = viewport.height / 2;
	await page.mouse.move(cx + deltaX, cy + deltaY);
}

/** Walk forward for a duration and take a screenshot */
export async function walkForwardAndScreenshot(
	page: Page, durationMs: number, name: string
): Promise<void> {
	await holdKey(page, "w", durationMs);
	await page.waitForTimeout(300); // let the scene settle
	await screenshot(page, name);
}

/** Toggle debug overlay (double backtick) */
export async function toggleDebug(page: Page): Promise<void> {
	await pressKey(page, "`");
	await page.waitForTimeout(100);
	await pressKey(page, "`");
	await page.waitForTimeout(300);
}

/** Get text content of the interaction prompt */
export async function getInteractionPrompt(page: Page): Promise<string | null> {
	const el = page.locator("#interact-prompt");
	const visible = await el.isVisible();
	if (!visible) return null;
	return el.textContent();
}

/** Get text content of the debug overlay */
export async function getShipDebug(page: Page): Promise<string | null> {
	const el = page.locator("#ship-debug");
	const visible = await el.isVisible();
	if (!visible) return null;
	return el.textContent();
}
