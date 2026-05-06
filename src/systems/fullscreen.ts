/**
 * Fullscreen + Escape-key capture.
 *
 * Goal: the game behaves like a native app — always fullscreen, with
 * Escape routed to the in-game menu instead of exiting fullscreen.
 *
 * Browser constraints:
 *  - `document.documentElement.requestFullscreen()` requires a user
 *    gesture. It cannot be called from main-module code at load time —
 *    the browser rejects it. We wait for the first pointerdown / key
 *    press and enter fullscreen from that handler.
 *  - Chrome's Keyboard Lock API (`navigator.keyboard.lock(["Escape"])`)
 *    prevents Escape from exiting fullscreen and instead delivers it as
 *    a normal keydown event — which our InputManager picks up as
 *    Action.Pause, routing it to the in-game menu or cinematic skip.
 *
 * Both APIs are available in Chrome / Edge / Electron; Firefox + Safari
 * don't support keyboard lock (Escape exits fullscreen there). The app
 * targets Chrome + eventual Electron wrapper, so this is a non-issue
 * for our shipping platform.
 *
 * Disable the whole thing by calling `disableFullscreenBehavior()` —
 * useful for dev (sometimes you want Escape to drop fullscreen so you
 * can see DevTools).
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
	await lockEscape();
};

const lockEscape = async (): Promise<void> => {
	// Keyboard Lock API — only present in Chrome/Edge/Electron. Ignored
	// elsewhere. With Escape locked, pressing it fires a normal keydown
	// event; without it, Escape exits fullscreen and consumes the event.
	const keyboard = (navigator as unknown as {
		keyboard?: { lock: (keys: string[]) => Promise<void> };
	}).keyboard;
	if (!keyboard) return;
	try {
		await keyboard.lock(["Escape"]);
	} catch {
		// User agent can refuse (e.g. not in fullscreen yet); safe to ignore.
	}
};

const onFirstGesture = () => {
	void enterFullscreen();
};

const queueFullscreenGesture = (): void => {
	window.addEventListener("pointerdown", onFirstGesture, { once: true });
	window.addEventListener("keydown",     onFirstGesture, { once: true });
};

const unlockEscape = (): void => {
	const keyboard = (navigator as unknown as {
		keyboard?: { unlock: () => void };
	}).keyboard;
	keyboard?.unlock?.();
};

/**
 * Install fullscreen behavior. After the first user gesture, the game
 * enters fullscreen and locks the Escape key so the browser doesn't
 * consume it for fullscreen exit.
 */
export function installFullscreenBehavior(): void {
	if (installed) return;
	installed = true;

	queueFullscreenGesture();

	// If the user somehow leaves fullscreen (alt-tab, OS-level switcher,
	// F11, focused DevTools), re-request on the next interaction instead
	// of fighting the user mid-flight.
	const onFullscreenChange = () => {
		if (isFullscreen()) {
			void lockEscape();
		} else {
			unlockEscape();
			if (enabled) {
				// Queue a re-entry on the next user gesture.
				queueFullscreenGesture();
			}
		}
	};
	document.addEventListener("fullscreenchange", onFullscreenChange);
}

export function setFullscreenBehaviorEnabled(nextEnabled: boolean): void {
	enabled = nextEnabled;

	if (enabled) {
		installFullscreenBehavior();
		queueFullscreenGesture();
	} else {
		unlockEscape();
	}
}

/**
 * Opt-out — stops auto-entering fullscreen. The current fullscreen
 * session isn't forcibly exited; next time the user leaves fullscreen
 * (or DevTools steals focus), we won't retry.
 */
export function disableFullscreenBehavior(): void {
	enabled = false;
	unlockEscape();
}
