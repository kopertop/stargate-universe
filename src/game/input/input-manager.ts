/**
 * InputManager
 *
 * Single source of truth for keyboard and mouse input. Mount it once against
 * the renderer's canvas and pass it down to anything that needs input.
 *
 * Desktop (fine pointer): WoW-style controls — cursor stays visible; hold
 * right mouse button and drag to orbit the camera.
 *
 * Touch / pointer-lock fallback: optional click-to-capture (legacy).
 */

type PointerLockState = "locked" | "pending" | "unlocked";
type ControlScheme = "wow-desktop" | "pointer-lock";

const isFinePointerDevice = (): boolean => {
	if (typeof window === "undefined" || !window.matchMedia) return true;
	return window.matchMedia("(pointer: fine)").matches;
};

export class InputManager {
	private readonly keyState = new Set<string>();
	private accumulatedMouseX = 0;
	private accumulatedMouseY = 0;
	private pointerLockState: PointerLockState = "unlocked";
	private controlScheme: ControlScheme = "wow-desktop";
	private rightMouseDown = false;
	private lastPointerX = 0;
	private lastPointerY = 0;
	private mountedElement: HTMLElement | null = null;

	// ------------------------------------------------------------------ mount

	mount(element: HTMLElement, options?: { controlScheme?: ControlScheme }): void {
		if (this.mountedElement) {
			this.dispose();
		}

		this.controlScheme =
			options?.controlScheme ??
			(isFinePointerDevice() ? "wow-desktop" : "pointer-lock");

		this.mountedElement = element;
		element.addEventListener("contextmenu", this.handleContextMenu);

		if (this.controlScheme === "pointer-lock") {
			element.addEventListener("click", this.handleClick);
		} else {
			element.addEventListener("mousedown", this.handleMouseDown);
		}

		window.addEventListener("mouseup", this.handleMouseUp);
		document.addEventListener("pointerlockchange", this.handlePointerLockChange);
		window.addEventListener("blur", this.handleBlur);
		window.addEventListener("keydown", this.handleKeyDown);
		window.addEventListener("keyup", this.handleKeyUp);
		window.addEventListener("mousemove", this.handleMouseMove);
	}

	dispose(): void {
		if (this.mountedElement) {
			this.mountedElement.removeEventListener("click", this.handleClick);
			this.mountedElement.removeEventListener("contextmenu", this.handleContextMenu);
			this.mountedElement.removeEventListener("mousedown", this.handleMouseDown);
			this.mountedElement.classList.remove("sgu-orbit-drag");
			this.mountedElement = null;
		}

		window.removeEventListener("mouseup", this.handleMouseUp);
		document.removeEventListener("pointerlockchange", this.handlePointerLockChange);
		window.removeEventListener("blur", this.handleBlur);
		window.removeEventListener("keydown", this.handleKeyDown);
		window.removeEventListener("keyup", this.handleKeyUp);
		window.removeEventListener("mousemove", this.handleMouseMove);

		this.keyState.clear();
		this.accumulatedMouseX = 0;
		this.accumulatedMouseY = 0;
		this.rightMouseDown = false;

		if (this.pointerLockState === "locked" && document.pointerLockElement) {
			document.exitPointerLock();
		}

		this.pointerLockState = "unlocked";
	}

	// ---------------------------------------------------------------- keyboard

	isKeyDown(code: string): boolean {
		return this.keyState.has(code);
	}

	axis(positive: string, negative: string): number {
		return (this.keyState.has(positive) ? 1 : 0) - (this.keyState.has(negative) ? 1 : 0);
	}

	// ------------------------------------------------------------------ mouse

	isPointerLocked(): boolean {
		return this.pointerLockState === "locked";
	}

	/** True while the player is holding RMB to orbit (WoW-style desktop). */
	isOrbitActive(): boolean {
		return this.rightMouseDown || this.pointerLockState === "locked";
	}

	consumeMouseDelta(): { x: number; y: number } {
		const delta = { x: this.accumulatedMouseX, y: this.accumulatedMouseY };
		this.accumulatedMouseX = 0;
		this.accumulatedMouseY = 0;
		return delta;
	}

	requestPointerLock(): void {
		if (!this.mountedElement || this.pointerLockState !== "unlocked") {
			return;
		}

		this.pointerLockState = "pending";
		void this.mountedElement.requestPointerLock();
	}

	releasePointerLock(): void {
		if (this.pointerLockState === "locked" && document.pointerLockElement) {
			document.exitPointerLock();
		}

		this.pointerLockState = "unlocked";
	}

	// -------------------------------------------------------- private handlers

	private readonly handleClick = () => {
		if (this.pointerLockState === "unlocked") {
			this.requestPointerLock();
		}
	};

	private readonly handleContextMenu = (event: MouseEvent) => {
		if (this.controlScheme !== "wow-desktop") return;
		const target = event.target;
		if (
			target === this.mountedElement ||
			(target instanceof Node && this.mountedElement?.contains(target))
		) {
			event.preventDefault();
		}
	};

	private readonly handleMouseDown = (event: MouseEvent) => {
		if (this.controlScheme !== "wow-desktop" || event.button !== 2) return;
		event.preventDefault();
		this.rightMouseDown = true;
		this.lastPointerX = event.clientX;
		this.lastPointerY = event.clientY;
		this.mountedElement?.classList.add("sgu-orbit-drag");
	};

	private readonly handleMouseUp = (event: MouseEvent) => {
		if (event.button !== 2) return;
		this.rightMouseDown = false;
		this.mountedElement?.classList.remove("sgu-orbit-drag");
	};

	private readonly handlePointerLockChange = () => {
		const isLocked = document.pointerLockElement === this.mountedElement;
		this.pointerLockState = isLocked ? "locked" : "unlocked";
	};

	private readonly handleBlur = () => {
		this.keyState.clear();
		this.rightMouseDown = false;
		this.mountedElement?.classList.remove("sgu-orbit-drag");
		this.releasePointerLock();
	};

	private readonly handleKeyDown = (event: KeyboardEvent) => {
		if (isTextInputTarget(event.target)) {
			return;
		}

		this.keyState.add(event.code);

		if (event.code === "Space") {
			event.preventDefault();
		}
	};

	private readonly handleKeyUp = (event: KeyboardEvent) => {
		this.keyState.delete(event.code);
	};

	private readonly handleMouseMove = (event: MouseEvent) => {
		if (this.pointerLockState === "locked") {
			this.accumulatedMouseX += event.movementX;
			this.accumulatedMouseY += event.movementY;
			return;
		}

		if (this.controlScheme === "wow-desktop" && this.rightMouseDown) {
			this.accumulatedMouseX += event.clientX - this.lastPointerX;
			this.accumulatedMouseY += event.clientY - this.lastPointerY;
			this.lastPointerX = event.clientX;
			this.lastPointerY = event.clientY;
		}
	};
}

function isTextInputTarget(target: EventTarget | null): boolean {
	return (
		target instanceof HTMLElement &&
		(target.isContentEditable || target.tagName === "INPUT" || target.tagName === "TEXTAREA")
	);
}
