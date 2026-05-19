/**
 * Fullscreen + Escape behavior.
 *
 * Goal: the game enters fullscreen on first user gesture for an
 * immersive presentation, but Escape always works the way the player
 * expects in a browser game — release pointer lock, exit fullscreen,
 * and notify a host so it can pause the game and show a menu.
 *
 * Browser constraints:
 *  - `document.documentElement.requestFullscreen()` requires a user
 *    gesture, so we wait for the first pointerdown / keydown.
 *  - We previously used Chrome's Keyboard Lock API to capture Escape
 *    so the game stayed fullscreen. That broke devtools / cursor
 *    recovery and confused playtesters — Escape is the universal
 *    "let me out" key. We no longer call `navigator.keyboard.lock`.
 *  - The browser also fires `fullscreenchange` whenever the user uses
 *    the browser chrome to exit fullscreen (F11, system gesture). We
 *    treat that as equivalent to Escape so the game still pauses.
 */

let enabled = true;
let installed = false;

type EscapeListener = () => void;
const escapeListeners = new Set<EscapeListener>();

const isFullscreen = (): boolean => Boolean(document.fullscreenElement);

export const enterFullscreen = async (): Promise<void> => {
	if (!enabled || isFullscreen()) return;
	try {
		await document.documentElement.requestFullscreen({ navigationUI: "hide" });
	} catch {
		// Fullscreen requires a trusted gesture. If the call was made
		// from the wrong context we silently retry on the next gesture.
	}
};

export async function exitFullscreen(): Promise<void> {
	if (!isFullscreen()) return;
	try {
		await document.exitFullscreen();
	} catch {
		// Some embeds (iframes without `allow="fullscreen"`) reject this.
	}
}

export function releasePointerLock(): void {
	if (document.pointerLockElement) {
		document.exitPointerLock?.();
	}
}

export async function requestFullscreenAndPointerLock(target?: HTMLElement): Promise<void> {
	await enterFullscreen();
	target?.requestPointerLock?.();
}

const onFirstGesture = () => {
	void enterFullscreen();
};

const queueFullscreenGesture = (): void => {
	window.addEventListener("pointerdown", onFirstGesture, { once: true });
	window.addEventListener("keydown",     onFirstGesture, { once: true });
};

const fireEscape = (): void => {
	releasePointerLock();
	void exitFullscreen();
	// Don't auto re-enter on the next gesture; the host owns resume.
	window.removeEventListener("pointerdown", onFirstGesture);
	window.removeEventListener("keydown",     onFirstGesture);
	for (const listener of escapeListeners) listener();
};

const onEscape = (e: KeyboardEvent) => {
	if (e.code !== "Escape" && e.key !== "Escape") return;
	fireEscape();
};

const onFullscreenChange = (): void => {
	// User exited fullscreen via browser chrome (F11, system gesture, etc.).
	// Treat as an escape so the host can pause + show the menu.
	if (!isFullscreen()) fireEscape();
};

/**
 * Install fullscreen behavior. After the first user gesture, the game
 * enters fullscreen. Escape (or any fullscreen exit) releases pointer
 * lock, exits fullscreen, and fires registered escape listeners.
 */
export function installFullscreenBehavior(): void {
	if (installed) return;
	installed = true;

	queueFullscreenGesture();
	// Capture phase so in-scene handlers can't preventDefault our escape path.
	window.addEventListener("keydown", onEscape, { capture: true });
	document.addEventListener("fullscreenchange", onFullscreenChange);
}

export function setFullscreenBehaviorEnabled(nextEnabled: boolean): void {
	enabled = nextEnabled;
	if (enabled) {
		installFullscreenBehavior();
		queueFullscreenGesture();
	}
}

/**
 * Subscribe to escape events. The listener fires whenever the player
 * pressed Escape or otherwise left fullscreen — regardless of whether
 * we were in fullscreen at the time. Returns an unsubscribe function.
 */
export function onEscapeRequested(listener: EscapeListener): () => void {
	escapeListeners.add(listener);
	return () => escapeListeners.delete(listener);
}

/**
 * Opt-out — stops auto-entering fullscreen. The current fullscreen
 * session isn't forcibly exited; next time the user leaves fullscreen
 * (or DevTools steals focus), we won't retry.
 */
export function disableFullscreenBehavior(): void {
	enabled = false;
}
