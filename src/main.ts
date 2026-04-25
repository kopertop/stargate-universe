/**
 * Stargate Universe Entry Point
 * Initializes the loading screen, handles the initial app boot flow, 
 * and orchestrates the transition from loading to the main game world.
 */
import "./style.css";
import { createGameApp } from "./game/app";
import { initialSceneId, scenes } from "./scenes";
import { on, emit } from "./systems/event-bus";
import { AudioManager } from "./systems/audio";
import { installFullscreenBehavior } from "./systems/fullscreen";
import { createInstallPrompt, registerServiceWorker } from "@kopertop/vibe-game-engine";

// Chrome autoplay policy: audio contexts created before a user gesture
// start in "suspended" state. Resume on the first click/key so menu music
// and hover/select SFX actually play. Listener is added once, then removed.
const unlockAudio = () => {
	void AudioManager.getInstance().resumeContext();
	window.removeEventListener("pointerdown", unlockAudio);
	window.removeEventListener("keydown", unlockAudio);
};
window.addEventListener("pointerdown", unlockAudio, { once: false });
window.addEventListener("keydown", unlockAudio, { once: false });

// Pause ALL audio when the player backgrounds the tab / switches apps.
// We suspend the underlying AudioContext rather than stopping individual
// sounds so looping tracks resume cleanly at the same position on return.
// Also mirror visibility state back to a flag other systems can read.
(window as unknown as { __sguBackgrounded?: boolean }).__sguBackgrounded = false;

const handleVisibility = () => {
	const audio = AudioManager.getInstance();
	if (document.hidden) {
		(window as unknown as { __sguBackgrounded?: boolean }).__sguBackgrounded = true;
		void audio.suspendContext();
	} else {
		(window as unknown as { __sguBackgrounded?: boolean }).__sguBackgrounded = false;
		// Only resume if the user has actually interacted — otherwise the
		// browser autoplay policy will reject resume() anyway.
		void audio.resumeContext();
	}
};
document.addEventListener("visibilitychange", handleVisibility);
// Some environments fire blur but not visibilitychange (e.g. another
// window pops in front). Treat blur the same way.
window.addEventListener("blur",  handleVisibility);
window.addEventListener("focus", handleVisibility);

// ─── Test hooks ───────────────────────────────────────────────────────────────
// Expose the global emit function so Playwright tests can inject game events
// via: await page.evaluate((ev, d) => window.__sguEmit(ev, d), event, data)
(window as any).__sguEmit = emit;

// Enter fullscreen on the first user gesture and capture Escape so the
// browser doesn't steal it for "exit fullscreen". Escape is routed to
// the in-game menu via InputManager's Action.Pause instead.
installFullscreenBehavior();

// ─── PWA — service worker + installability ────────────────────────────────────
// Skipped entirely on localhost dev (no need to cache the dev server).
// The SW is generated from @kopertop/vibe-game-engine's DEFAULT_SW_SOURCE
// via scripts/gen-sw.ts into public/sw.js and picked up by Vite.
const installPrompt = createInstallPrompt();
(window as any).__sguInstallPrompt = installPrompt;

if (import.meta.env.PROD && "serviceWorker" in navigator) {
		void registerServiceWorker({
			url:   "/sw.js",
			scope: "/",
			onUpdateReady: (registration: any) => {
				// New build available in the background. For now, auto-apply
				// after a short delay so returning players get fresh content
				// without a "Reload?" prompt. Swap to a UI prompt when we have
				// a HUD toast system.
				console.info("[SW] New version ready — applying in 5s");
				setTimeout(() => {
					registration.waiting?.postMessage({ type: "SKIP_WAITING" });
				}, 5000);
			},
			onError: (err: any) => console.warn("[SW] registration failed:", err.message),
		});
}

const root = document.querySelector<HTMLDivElement>("#app");

if (!root) {
	throw new Error("Missing #app root.");
}

// Create loading screen
const loading = document.createElement("div");
loading.className = "loading-screen";

const title = document.createElement("div");
title.className = "loading-title";
title.textContent = "Stargate Universe";
loading.appendChild(title);

const subtitle = document.createElement("div");
subtitle.className = "loading-subtitle";
subtitle.textContent = "Boarding Destiny";
loading.appendChild(subtitle);

const barTrack = document.createElement("div");
barTrack.className = "loading-bar-track";
const barFill = document.createElement("div");
barFill.className = "loading-bar-fill";
barTrack.appendChild(barFill);
loading.appendChild(barTrack);

document.body.appendChild(loading);

// Dismiss loading screen when the player character model loads
/**
 * Smoothly removes the loading screen from the DOM after a fade-out animation.
 * Triggered when the player character model is successfully loaded or as a 10s fallback.
 */
function dismissLoading() {
	if (!loading.parentElement) return;
	loading.classList.add("fade-out");
	setTimeout(() => loading.remove(), 700);
}

const unsubLoaded = on("character:model:loaded", () => {
	unsubLoaded();
	unsubFailed();
	dismissLoading();
});

// If VRM load fails, surface the error to the playtester (who may not have
// DevTools open) rather than silently timing out. The game still drops into
// the scene with a capsule fallback, so this is informational.
const unsubFailed = on("character:model:failed", ({ characterId, error }) => {
	unsubFailed();
	subtitle.textContent = `Character "${characterId}" failed — running with fallback`;
	subtitle.title = error;
	(barFill.style as CSSStyleDeclaration).background = "#ff6644";
	// Give the player a moment to see the message, then drop into the scene.
	setTimeout(() => {
		unsubLoaded();
		dismissLoading();
	}, 2500);
});

// Fallback: dismiss after 10s even if neither event fires
setTimeout(() => {
	unsubLoaded();
	unsubFailed();
	dismissLoading();
}, 10000);

// ─── Scene URL routing ────────────────────────────────────────────────────────
// ?scene=<id> lets Playwright navigate directly to any scene without playing
// through the prior scenes. Example: /?scene=desert-planet&webgl=1
const urlScene = new URLSearchParams(window.location.search).get("scene");
const startSceneId =
	urlScene !== null && (scenes as Record<string, unknown>)[urlScene] !== undefined
		? urlScene
		: initialSceneId;

const app = await createGameApp({
	initialSceneId: startSceneId,
	root,
	scenes
});

void app.start();
