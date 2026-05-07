import { chromium } from "@playwright/test";

const browser = await chromium.launch({ headless: false, args: ["--enable-unsafe-webgpu"] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await ctx.newPage();
page.on("console", (msg) => console.log(`[${msg.type()}]`, msg.text()));
page.on("pageerror", (err) => console.log("[pageerror]", err.message, err.stack));
await page.goto("http://localhost:5173/?scene=gate-room&webgl=1&photo=1");
await page.waitForFunction(() => (window as { __sceneReady?: boolean }).__sceneReady, { timeout: 30000 });
const inventory = await page.evaluate(() => {
	const s = (window as { __sguScene?: { traverse: (cb: (o: unknown) => void) => void } }).__sguScene;
	if (!s) return null;
	const named: Array<{ name: string; type: string; visible: boolean; x: number; y: number; z: number }> = [];
	s.traverse((o: unknown) => {
		const obj = o as { name: string; type: string; visible: boolean; position?: { x: number; y: number; z: number } };
		if (obj.name && obj.position) {
			named.push({ name: obj.name, type: obj.type, visible: obj.visible, x: +obj.position.x.toFixed(1), y: +obj.position.y.toFixed(1), z: +obj.position.z.toFixed(1) });
		}
	});
	return named.filter((n) => /[Ss]targate|[Gg]ate|[Rr]ing|[Cc]hevron|[Hh]orizon/.test(n.name)).slice(0, 30);
});
console.log("scene children:", JSON.stringify(inventory, null, 2));
await page.waitForTimeout(20000);
const ready = await page.evaluate(() => ({
	sceneReady: (window as { __sceneReady?: boolean }).__sceneReady,
	sceneId: (window as { __sgu?: { state: () => unknown } }).__sgu?.state(),
}));
console.log("status:", JSON.stringify(ready));
await browser.close();
