// Unified keyboard + mouse + gamepad input. Read `state` each frame after calling poll().
export const input = {
	move: { x: 0, y: 0 },   // -1..1, x = strafe, y = forward
	look: { x: 0, y: 0 },   // per-frame delta (radians-ish)
	run: false,
	jump: false,       // edge-triggered (true for one poll)
	cycleView: false,  // edge-triggered
	redial: false,     // edge-triggered
	lockEnabled: true,
	keys: new Set(),
	mouseDelta: { x: 0, y: 0 },
};

const pending = { jump: false, cycleView: false, redial: false };
let padPrev = {};
const dead = (v, d = 0.15) => (Math.abs(v) < d ? 0 : (v - Math.sign(v) * d) / (1 - d));

export const initInput = (canvas) => {
	window.addEventListener('keydown', (e) => {
		if (!e.repeat) { if (e.code === 'Space') pending.jump = true; if (e.code === 'KeyV') pending.cycleView = true; if (e.code === 'KeyR') pending.redial = true; }
		input.keys.add(e.code); if (e.code === 'Tab' || e.code === 'Space') e.preventDefault();
	});
	window.addEventListener('keyup', (e) => input.keys.delete(e.code));
	window.addEventListener('blur', () => input.keys.clear());
	canvas.addEventListener('click', () => { if (input.lockEnabled && document.pointerLockElement !== canvas) canvas.requestPointerLock()?.catch?.(() => {}); });
	window.addEventListener('mousemove', (e) => {
		if (document.pointerLockElement === canvas) {
			input.mouseDelta.x += e.movementX;
			input.mouseDelta.y += e.movementY;
		}
	});
};

export const poll = (dt) => {
	const k = input.keys;
	let x = (k.has('KeyD') || k.has('ArrowRight') ? 1 : 0) - (k.has('KeyA') || k.has('ArrowLeft') ? 1 : 0);
	let y = (k.has('KeyW') || k.has('ArrowUp') ? 1 : 0) - (k.has('KeyS') || k.has('ArrowDown') ? 1 : 0);
	let run = k.has('ShiftLeft') || k.has('ShiftRight');
	let lx = input.mouseDelta.x * 0.0022;
	let ly = input.mouseDelta.y * 0.0022;
	input.mouseDelta.x = input.mouseDelta.y = 0;

	const pad = navigator.getGamepads?.().find((g) => g && g.connected);
	if (pad) {
		const gx = dead(pad.axes[0]), gy = -dead(pad.axes[1]);
		if (gx || gy) { x = gx; y = gy; }
		lx += dead(pad.axes[2]) * 2.6 * dt;
		ly += dead(pad.axes[3]) * 2.0 * dt;
		run ||= (pad.buttons[7]?.value ?? 0) > 0.4 || pad.buttons[10]?.pressed;
		const edge = (b, key) => { const now = !!pad.buttons[b]?.pressed; if (now && !padPrev[b]) pending[key] = true; padPrev[b] = now; };
		edge(0, 'jump'); edge(3, 'cycleView'); edge(2, 'redial');
	}
	const len = Math.hypot(x, y);
	if (len > 1) { x /= len; y /= len; }
	input.move.x = x; input.move.y = y;
	input.look.x = lx; input.look.y = ly;
	input.run = run;
	input.jump = pending.jump; input.cycleView = pending.cycleView; input.redial = pending.redial;
	pending.jump = pending.cycleView = pending.redial = false;
};
