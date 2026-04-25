// ─── Skyrim-style horizontal compass bar ──────────────────────────────────────
// Renders a thin strip at top of screen. Cardinal/intercardinal labels scroll
// left/right as the camera yaws. A fixed center notch marks current heading.

const CARDINALS = [
	{ angle: 0,   text: "N",  major: true },
	{ angle: 45,  text: "NE", major: false },
	{ angle: 90,  text: "E",  major: true },
	{ angle: 135, text: "SE", major: false },
	{ angle: 180, text: "S",  major: true },
	{ angle: 225, text: "SW", major: false },
	{ angle: 270, text: "W",  major: true },
	{ angle: 315, text: "NW", major: false },
] as const;

/** Degrees of heading visible across the full width of the bar. */
const VISIBLE_RANGE = 160;

// Use a structural camera type to avoid dual @types/three version conflicts.
// THREE.Camera satisfies { rotation: { y: number } } so this is compatible.
type CameraLike = { rotation: { y: number } };

export type HorizontalCompassComponent = {
	element: HTMLElement;
	update(camera: CameraLike, _delta: number): void;
	dispose(): void;
};

export function createHorizontalCompass(): HorizontalCompassComponent {
	// ── Container strip ────────────────────────────────────────────────────────
	const bar = document.createElement("div");
	bar.style.cssText = [
		"position:absolute",
		"top:0",
		"left:0",
		"right:0",
		"height:30px",
		"pointer-events:none",
		"overflow:hidden",
		"background:linear-gradient(to bottom,rgba(0,0,0,0.6) 0%,rgba(0,0,0,0) 100%)",
		"z-index:10",
	].join(";");

	// ── Center notch (downward triangle) ──────────────────────────────────────
	const notch = document.createElement("div");
	notch.style.cssText = [
		"position:absolute",
		"top:0",
		"left:50%",
		"transform:translateX(-50%)",
		"width:0",
		"height:0",
		"border-left:5px solid transparent",
		"border-right:5px solid transparent",
		"border-top:8px solid rgba(100,200,255,0.95)",
		"z-index:12",
	].join(";");
	bar.appendChild(notch);

	// ── Cardinal label spans — repositioned every frame ────────────────────────
	const labelEls = CARDINALS.map(({ text, major }) => {
		const el = document.createElement("span");
		el.textContent = text;
		el.style.cssText = [
			"position:absolute",
			"top:50%",
			"transform:translate(-50%,-50%)",
			`font-family:'Courier New',monospace`,
			`font-size:${major ? "12px" : "9px"}`,
			`font-weight:${major ? "bold" : "normal"}`,
			"color:rgba(180,220,255,0.9)",
			"text-shadow:0 0 5px rgba(80,160,255,0.55)",
			"letter-spacing:0.04em",
			"white-space:nowrap",
		].join(";");
		bar.appendChild(el);
		return el;
	});

	// ── Degree readout ─────────────────────────────────────────────────────────
	const degEl = document.createElement("span");
	degEl.style.cssText = [
		"position:absolute",
		"bottom:1px",
		"left:50%",
		"transform:translateX(-50%)",
		"font-family:'Courier New',monospace",
		"font-size:8px",
		"color:rgba(80,150,210,0.7)",
		"letter-spacing:0.06em",
	].join(";");
	bar.appendChild(degEl);

	// ── Update ─────────────────────────────────────────────────────────────────
	function update(camera: CameraLike): void {
		// Convert camera yaw to a 0–360 heading (0=North, 90=East, etc.)
		const yaw = camera.rotation.y;
		const heading = ((-yaw * 180 / Math.PI) % 360 + 360) % 360;

		const W = bar.clientWidth || window.innerWidth;
		const cx = W / 2;
		const pxPerDeg = W / VISIBLE_RANGE;

		CARDINALS.forEach(({ angle }, i) => {
			// Shortest angular distance from heading to this label, -180..180.
			const diff = ((angle - heading + 540) % 360) - 180;
			const x = cx + diff * pxPerDeg;
			const el = labelEls[i];

			if (x < -40 || x > W + 40) {
				el.style.display = "none";
				return;
			}
			el.style.display = "block";
			el.style.left = `${x}px`;
			// Fade toward edges
			const distRatio = Math.abs(diff) / (VISIBLE_RANGE / 2);
			el.style.opacity = String(Math.max(0, 1 - distRatio * 1.3).toFixed(2));
		});

		degEl.textContent = `${Math.round(heading)}°`;
	}

	return {
		element: bar,
		update,
		dispose() { /* element removal handled by compassHud.unmount */ },
	};
}
