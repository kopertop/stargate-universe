/**
 * Fullscreen + Escape behavior.
 *
 * Goal: the game enters fullscreen on first user gesture for an
 * immersive presentation, but Escape always works the way the player
 * expects in a browser game — release pointer lock, then exit
 * fullscreen — instead of being trapped by the in-game pause menu.
 *
 * Browser constraints:
 *  - `document.documentElement.requestFullscreen()` requires a user
 *    gesture, so we wait for the first pointerdown / keydown.
 *  - We previously used Chrome's Keyboard Lock API to capture Escape
 *    so the game stayed fullscreen. That broke devtools / cursor
 *    recovery and confused playtesters — Escape is the universal
 *    "let me out" key. We no longer call `navigator.keyboard.lock`.
 *
 * Disable auto-fullscreen entirely with `disableFullscreenBehavior()`.
 */

let enabled = true;
let installed = false;

const isFullscreen = (): boolean => Boolean(document.fullscreenElement);

const enterFullscreen = async (): Promise<void> => {
	if (!enabled || isFullscreen()) return;
	try {
		await document.documentElement.requestFullscreen({ navigationUI: "hide" });
	} catch {
		// Fullscreen requires a trusted gesture. If the call was made
		// from the wrong context we silently retry on the next gesture.
	}
};

const exitFullscreen = async (): Promise<void> => {
	if (!isFullscreen()) return;
	try {
		await document.exitFullscreen();
	} catch {
		// Some embeds (iframes without `allow="fullscreen"`) reject this.
	}
};

const releasePointerLock = (): void => {
	if (document.pointerLockElement) {
		document.exitPointerLock?.();
	}
};

const onFirstGesture = () => {
	void enterFullscreen();
};

const queueFullscreenGesture = (): void => {
	window.addEventListener("pointerdown", onFirstGesture, { once: true });
	window.addEventListener("keydown",     onFirstGesture, { once: true });
};

/**
 * Escape key handler — always release the pointer lock first, then
 * exit fullscreen. Listening in the *capture* phase so we run before
 * any in-scene pause-menu handler that might call `preventDefault()`
 * — the player's expectation that Escape "lets me out of the game"
 * outranks any in-game pause UI.
 *
 * We also clear the queued first-gesture listeners so pressing Escape
 * before any other key doesn't immediately re-enter fullscreen.
 */
const onEscape = (e: KeyboardEvent) => {
	if (e.code !== "Escape" && e.key !== "Escape") return;
	releasePointerLock();
	void exitFullscreen();
	// Don't re-enter fullscreen on the very next gesture — only on a
	// new dedicated user action (mountFullscreenGesture call site).
	window.removeEventListener("pointerdown", onFirstGesture);
	window.removeEventListener("keydown",     onFirstGesture);
};

/**
 * Install fullscreen behavior. After the first user gesture, the game
 * enters fullscreen. Pressing Escape exits both pointer lock and
 * fullscreen and does NOT auto re-enter.
 */
export function installFullscreenBehavior(): void {
	if (installed) return;
	installed = true;

	queueFullscreenGesture();
	window.addEventListener("keydown", onEscape, { capture: true });
}

export function setFullscreenBehaviorEnabled(nextEnabled: boolean): void {
	enabled = nextEnabled;

	if (enabled) {
		installFullscreenBehavior();
		queueFullscreenGesture();
	}
}

/**
 * Opt-out — stops auto-entering fullscreen. The current fullscreen
 * session isn't forcibly exited; next time the user leaves fullscreen
 * (or DevTools steals focus), we won't retry.
 */
export function disableFullscreenBehavior(): void {
	enabled = false;
}
