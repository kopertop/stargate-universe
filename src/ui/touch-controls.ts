/**
 * S4-09 — Mobile virtual joystick + primary action button.
 *
 * Activates on coarse pointers (touch screens). The joystick feeds the
 * shared InputManager via `setTouchMovement(x, z)` once per frame; the
 * action button dispatches a synthetic `KeyE` keyboard event so the
 * engine's existing keybind path (Interact → E) handles it without a
 * separate code path.
 *
 * Stays out of the way on desktop — the matchMedia gate means the DOM
 * nodes are never created when the user has a fine pointer.
 *
 * Returns a `{ tickAxis(), dispose() }` handle. Call `tickAxis()` once
 * per frame from the game loop to push the current stick value into
 * the InputManager (the manager polls per frame, so we re-push every
 * frame to keep the value live).
 */
import type { InputManager } from "@kopertop/vibe-game-engine";

const PAD_RADIUS = 60;     // px — thumb travel radius
const ACTION_KEY = "KeyE"; // mirrors keyboard Interact binding

interface TouchControlsHandle {
	tickAxis: () => void;
	dispose: () => void;
}

const isCoarsePointer = (): boolean => {
	if (typeof window === "undefined" || !window.matchMedia) return false;
	return window.matchMedia("(pointer: coarse)").matches;
};

interface PadState {
	pointerId: number | null;
	originX: number;
	originY: number;
	dx: number;
	dy: number;
}

const buildPad = (): { root: HTMLDivElement; thumb: HTMLDivElement; state: PadState } => {
	const root = document.createElement("div");
	Object.assign(root.style, {
		position: "fixed",
		left: "20px",
		bottom: "20px",
		width: `${PAD_RADIUS * 2}px`,
		height: `${PAD_RADIUS * 2}px`,
		borderRadius: "50%",
		background: "rgba(20, 30, 50, 0.35)",
		border: "2px solid rgba(120, 180, 255, 0.4)",
		touchAction: "none",
		userSelect: "none",
		zIndex: "200",
	});
	const thumb = document.createElement("div");
	Object.assign(thumb.style, {
		position: "absolute",
		left: "50%",
		top: "50%",
		width: `${PAD_RADIUS}px`,
		height: `${PAD_RADIUS}px`,
		marginLeft: `-${PAD_RADIUS / 2}px`,
		marginTop: `-${PAD_RADIUS / 2}px`,
		borderRadius: "50%",
		background: "rgba(120, 180, 255, 0.5)",
		pointerEvents: "none",
		transform: "translate(0, 0)",
	});
	root.appendChild(thumb);
	const state: PadState = { pointerId: null, originX: 0, originY: 0, dx: 0, dy: 0 };
	return { root, thumb, state };
};

const buildActionButton = (): HTMLDivElement => {
	const btn = document.createElement("div");
	Object.assign(btn.style, {
		position: "fixed",
		right: "30px",
		bottom: "40px",
		width: "84px",
		height: "84px",
		borderRadius: "50%",
		background: "rgba(80, 200, 160, 0.45)",
		border: "2px solid rgba(140, 255, 220, 0.6)",
		display: "flex",
		alignItems: "center",
		justifyContent: "center",
		fontFamily: "'Courier New', monospace",
		fontSize: "16px",
		color: "#e0fff7",
		textShadow: "0 0 6px #44ddccaa",
		touchAction: "none",
		userSelect: "none",
		zIndex: "200",
	});
	btn.textContent = "E";
	return btn;
};

export const mountTouchControls = (input: InputManager): TouchControlsHandle | null => {
	if (!isCoarsePointer()) return null;

	const { root: pad, thumb, state } = buildPad();
	const action = buildActionButton();
	document.body.appendChild(pad);
	document.body.appendChild(action);

	const fireKey = (type: "keydown" | "keyup") => {
		window.dispatchEvent(new KeyboardEvent(type, { code: ACTION_KEY, key: "e", bubbles: true }));
	};

	const onPadDown = (e: PointerEvent) => {
		if (state.pointerId !== null) return;
		state.pointerId = e.pointerId;
		const rect = pad.getBoundingClientRect();
		state.originX = rect.left + rect.width / 2;
		state.originY = rect.top + rect.height / 2;
		pad.setPointerCapture(e.pointerId);
		e.preventDefault();
	};
	const onPadMove = (e: PointerEvent) => {
		if (e.pointerId !== state.pointerId) return;
		let dx = e.clientX - state.originX;
		let dy = e.clientY - state.originY;
		const len = Math.hypot(dx, dy);
		if (len > PAD_RADIUS) {
			dx = (dx / len) * PAD_RADIUS;
			dy = (dy / len) * PAD_RADIUS;
		}
		state.dx = dx;
		state.dy = dy;
		thumb.style.transform = `translate(${dx}px, ${dy}px)`;
	};
	const resetPad = () => {
		state.pointerId = null;
		state.dx = 0;
		state.dy = 0;
		thumb.style.transform = "translate(0, 0)";
	};
	const onPadUp = (e: PointerEvent) => {
		if (e.pointerId !== state.pointerId) return;
		// Browser auto-releases capture on pointercancel; only release on real up.
		try { pad.releasePointerCapture?.(e.pointerId); } catch { /* already released */ }
		resetPad();
	};
	const onPadCancel = (e: PointerEvent) => {
		if (e.pointerId !== state.pointerId) return;
		resetPad();
	};
	pad.addEventListener("pointerdown", onPadDown);
	pad.addEventListener("pointermove", onPadMove);
	pad.addEventListener("pointerup", onPadUp);
	pad.addEventListener("pointercancel", onPadCancel);

	let actionPointerId: number | null = null;
	const onActionDown = (e: PointerEvent) => {
		if (actionPointerId !== null) return;
		actionPointerId = e.pointerId;
		action.style.background = "rgba(120, 240, 200, 0.7)";
		fireKey("keydown");
		action.setPointerCapture(e.pointerId);
		e.preventDefault();
	};
	const onActionUp = (e: PointerEvent) => {
		if (e.pointerId !== actionPointerId) return;
		actionPointerId = null;
		action.style.background = "rgba(80, 200, 160, 0.45)";
		fireKey("keyup");
		try { action.releasePointerCapture?.(e.pointerId); } catch { /* already released */ }
	};
	const onActionCancel = (e: PointerEvent) => {
		if (e.pointerId !== actionPointerId) return;
		actionPointerId = null;
		action.style.background = "rgba(80, 200, 160, 0.45)";
		fireKey("keyup");
	};
	action.addEventListener("pointerdown", onActionDown);
	action.addEventListener("pointerup", onActionUp);
	action.addEventListener("pointercancel", onActionCancel);

	const tickAxis = () => {
		// Engine convention: x = strafe (right positive), z = forward (UP positive).
		// Joystick screen-y down is positive, so invert for forward motion.
		input.setTouchMovement(state.dx / PAD_RADIUS, -state.dy / PAD_RADIUS);
	};
	const dispose = () => {
		pad.remove();
		action.remove();
	};
	return { tickAxis, dispose };
};
