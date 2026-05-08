/**
 * Player HUD — Hollowlands-inspired overlay layout.
 *
 *   ┌──────────────────────────────────────────────────────┐
 *   │ resources                                       clock│
 *   │ quests                                               │
 *   │                                                      │
 *   │                                                      │
 *   │ keybinds         hotbar                       brand  │
 *   └──────────────────────────────────────────────────────┘
 *
 * Pure DOM overlay — no game state mutation. The HUD subscribes to
 * the event bus for live data and reads from the resource pool / quest
 * manager on demand. Disposed cleanly on app dispose so no zombie
 * listeners survive across hot-module reloads.
 *
 * Display-only: HUD never owns inventory or quest state, just renders
 * snapshots and re-renders on event triggers.
 */
import type { QuestObjective } from "@kopertop/vibe-game-engine";
import { scopedBus } from "../systems/event-bus";
import { getAllResources, type ResourceType } from "../systems/resources";
import { getActiveQuestManager } from "../systems/active-quest-manager";

export interface HudHandle {
	dispose: () => void;
	/** Force a full re-render (e.g. after scene change or save load). */
	refresh: () => void;
}

// ─── Resource icons ────────────────────────────────────────────────────────
// Pictogram glyphs for the four player-pool resources. Using emoji here is
// intentional: the HUD is small, scales cleanly with text-size, and avoids
// shipping additional sprite atlases for what is essentially debug-grade UI
// until the art team delivers final iconography. Swap to <img> elements
// pointing at /assets/icons/* when the icons land.
const RESOURCE_ICON: Record<ResourceType, string> = {
	"ship-parts": "🛠",
	"water":      "💧",
	"food":       "🥖",
	"lime":       "🪨",
};

const RESOURCE_LABEL: Record<ResourceType, string> = {
	"ship-parts": "Parts",
	"water":      "Water",
	"food":       "Food",
	"lime":       "Lime",
};

// ─── DOM helpers ───────────────────────────────────────────────────────────

const el = <K extends keyof HTMLElementTagNameMap>(
	tag: K,
	className?: string,
	text?: string,
): HTMLElementTagNameMap[K] => {
	const node = document.createElement(tag);
	if (className) node.className = className;
	if (text !== undefined) node.textContent = text;
	return node;
};

// ─── Stylesheet ────────────────────────────────────────────────────────────
// Injected once, on first mount. Keeps all HUD CSS in one place rather than
// inlining styles on every node. Deduped via id check.

const STYLE_ID = "sgu-hud-style";

const STYLE = `
.sgu-hud {
	position: fixed;
	inset: 0;
	pointer-events: none;
	z-index: 100;
	font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
	color: #f4f4f4;
	text-shadow: 0 1px 2px rgba(0, 0, 0, 0.85);
	user-select: none;
}
.sgu-hud * { pointer-events: auto; }

/* Top-left cluster: resources strip + quest list */
.sgu-hud-top-left {
	position: absolute;
	top: 16px;
	left: 16px;
	display: flex;
	flex-direction: column;
	gap: 12px;
	max-width: 320px;
}
.sgu-hud-resources {
	display: flex;
	gap: 14px;
	flex-wrap: wrap;
	font-size: 18px;
	font-weight: 600;
}
.sgu-hud-resource {
	display: flex;
	align-items: center;
	gap: 4px;
	background: rgba(0, 0, 0, 0.35);
	border-radius: 6px;
	padding: 3px 8px;
}
.sgu-hud-resource-icon { font-size: 18px; line-height: 1; }
.sgu-hud-resource-count { font-variant-numeric: tabular-nums; }

.sgu-hud-quests {
	display: flex;
	flex-direction: column;
	gap: 6px;
	font-size: 15px;
	line-height: 1.3;
}
.sgu-hud-quest {
	display: flex;
	align-items: flex-start;
	gap: 8px;
}
.sgu-hud-quest-box {
	flex: 0 0 14px;
	width: 14px;
	height: 14px;
	border: 1.5px solid #d8d8d8;
	border-radius: 2px;
	margin-top: 2px;
	background: rgba(0, 0, 0, 0.3);
}
.sgu-hud-quest.is-complete .sgu-hud-quest-box {
	background: #6cd06c;
	border-color: #4eb84e;
}
.sgu-hud-quest.is-complete .sgu-hud-quest-box::after {
	content: "✓";
	display: block;
	color: #062;
	font-size: 12px;
	font-weight: 700;
	line-height: 11px;
	text-align: center;
}
.sgu-hud-quest.is-complete .sgu-hud-quest-text {
	text-decoration: line-through;
	opacity: 0.6;
}

/* Top-right: clock dial */
.sgu-hud-top-right {
	position: absolute;
	top: 16px;
	right: 18px;
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 4px;
}
.sgu-hud-clock-icon { font-size: 22px; line-height: 1; }
.sgu-hud-clock-dial {
	width: 38px;
	height: 38px;
	border-radius: 50%;
	background: rgba(20, 24, 38, 0.55);
	border: 1.5px solid rgba(220, 220, 220, 0.5);
	position: relative;
}
.sgu-hud-clock-hand {
	position: absolute;
	left: 50%;
	top: 50%;
	width: 1.5px;
	height: 14px;
	background: #f0f0f0;
	transform-origin: top center;
	transform: translate(-50%, 0) rotate(0deg);
}

/* Bottom-left: keybind hints */
.sgu-hud-bottom-left {
	position: absolute;
	bottom: 18px;
	left: 18px;
	display: flex;
	flex-direction: column;
	gap: 6px;
	font-size: 13px;
}
.sgu-hud-key-row {
	display: flex;
	align-items: center;
	gap: 8px;
}
.sgu-hud-key {
	display: inline-flex;
	align-items: center;
	justify-content: center;
	min-width: 30px;
	padding: 2px 7px;
	background: rgba(0, 0, 0, 0.55);
	border: 1px solid rgba(255, 255, 255, 0.18);
	border-radius: 4px;
	font-family: ui-monospace, "SF Mono", Menlo, monospace;
	font-size: 11px;
	font-weight: 600;
	letter-spacing: 0.5px;
	text-transform: uppercase;
	color: #d8d8d8;
}
.sgu-hud-key-label { opacity: 0.85; }

/* Bottom-center: hotbar */
.sgu-hud-hotbar {
	position: absolute;
	bottom: 22px;
	left: 50%;
	transform: translateX(-50%);
	display: flex;
	gap: 6px;
}
.sgu-hud-slot {
	width: 56px;
	height: 56px;
	background: rgba(0, 0, 0, 0.45);
	border: 1.5px solid rgba(255, 255, 255, 0.22);
	border-radius: 4px;
	position: relative;
	display: flex;
	align-items: flex-end;
	justify-content: flex-end;
	font-size: 11px;
	font-weight: 700;
	color: #f0f0f0;
}
.sgu-hud-slot-index {
	position: absolute;
	top: 2px;
	left: 4px;
	font-size: 11px;
	color: #cfd5e3;
	opacity: 0.8;
}
.sgu-hud-slot-icon { font-size: 26px; line-height: 1; padding: 14px; }
.sgu-hud-slot-count { padding: 0 4px 2px 0; }

/* Bottom-right: brand tag */
.sgu-hud-brand {
	position: absolute;
	bottom: 12px;
	right: 14px;
	font-size: 11px;
	font-weight: 600;
	letter-spacing: 0.5px;
	text-transform: uppercase;
	background: rgba(0, 0, 0, 0.6);
	padding: 4px 10px;
	border-radius: 3px;
	color: #c8d3e8;
}
`;

const ensureStyle = (): void => {
	if (document.getElementById(STYLE_ID)) return;
	const style = document.createElement("style");
	style.id = STYLE_ID;
	style.textContent = STYLE;
	document.head.appendChild(style);
};

// ─── Build helpers ─────────────────────────────────────────────────────────

const buildResourcesStrip = (): {
	root: HTMLDivElement;
	render: () => void;
} => {
	const root = el("div", "sgu-hud-resources");
	const counts: Record<ResourceType, HTMLSpanElement> = {
		"ship-parts": el("span", "sgu-hud-resource-count", "0"),
		"water":      el("span", "sgu-hud-resource-count", "0"),
		"food":       el("span", "sgu-hud-resource-count", "0"),
		"lime":       el("span", "sgu-hud-resource-count", "0"),
	};
	for (const type of Object.keys(counts) as ResourceType[]) {
		const slot = el("div", "sgu-hud-resource");
		slot.title = RESOURCE_LABEL[type];
		const icon = el("span", "sgu-hud-resource-icon", RESOURCE_ICON[type]);
		slot.appendChild(icon);
		slot.appendChild(counts[type]);
		root.appendChild(slot);
	}
	const render = () => {
		const all = getAllResources();
		for (const type of Object.keys(counts) as ResourceType[]) {
			counts[type].textContent = String(all[type] ?? 0);
		}
	};
	render();
	return { root, render };
};

const buildQuestPanel = (): { root: HTMLDivElement; render: () => void } => {
	const root = el("div", "sgu-hud-quests");
	const render = () => {
		root.replaceChildren();
		const manager = getActiveQuestManager();
		if (!manager) return;
		const log = manager.getQuestLog();
		// Active quests, then up to two recently completed quests for affordance.
		const active = [...log.active.values()];
		for (const state of active) {
			// Show only visible, top-of-stack objectives (≤4 lines per quest).
			const visible = state.objectives.filter((o: QuestObjective) => o.visible);
			for (const obj of visible.slice(0, 4)) {
				const row = el("div", `sgu-hud-quest${obj.completed ? " is-complete" : ""}`);
				row.appendChild(el("span", "sgu-hud-quest-box"));
				row.appendChild(el("span", "sgu-hud-quest-text", obj.description));
				root.appendChild(row);
			}
		}
	};
	render();
	return { root, render };
};

const buildKeybindHints = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-bottom-left");
	const HINTS: ReadonlyArray<readonly [string, string]> = [
		["WASD",  "Move"],
		["Shift", "Run"],
		["Space", "Jump"],
		["E",     "Interact"],
		["G",     "Dial Gate"],
	];
	for (const [key, label] of HINTS) {
		const row = el("div", "sgu-hud-key-row");
		row.appendChild(el("span", "sgu-hud-key", key));
		row.appendChild(el("span", "sgu-hud-key-label", label));
		root.appendChild(row);
	}
	return root;
};

const buildHotbar = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-hotbar");
	for (let i = 1; i <= 5; i++) {
		const slot = el("div", "sgu-hud-slot");
		slot.appendChild(el("span", "sgu-hud-slot-index", String(i)));
		root.appendChild(slot);
	}
	return root;
};

const buildClock = (): { root: HTMLDivElement; tick: () => void } => {
	const root = el("div", "sgu-hud-top-right");
	// Phase glyph — sun for the day half, moon for the night half. We don't
	// have a day/night cycle yet, so just pick one based on real-world hour
	// for now; swap to ship-time-of-day source when that lands.
	const icon = el("div", "sgu-hud-clock-icon", "🌙");
	const dial = el("div", "sgu-hud-clock-dial");
	const hand = el("div", "sgu-hud-clock-hand");
	dial.appendChild(hand);
	root.appendChild(icon);
	root.appendChild(dial);
	const tick = () => {
		const now = new Date();
		const hours = now.getHours() + now.getMinutes() / 60;
		// 0–24h → 0–360°. The 12-hour wrap matches a clock-hand convention.
		const deg = (hours % 12) * 30;
		hand.style.transform = `translate(-50%, 0) rotate(${deg}deg)`;
		icon.textContent = hours >= 6 && hours < 18 ? "☀" : "🌙";
	};
	tick();
	return { root, tick };
};

const buildBrand = (): HTMLDivElement => el("div", "sgu-hud-brand", "Stargate · Destiny");

// ─── Public API ────────────────────────────────────────────────────────────

export const mountHud = (): HudHandle => {
	ensureStyle();

	const root = el("div", "sgu-hud");

	const topLeft = el("div", "sgu-hud-top-left");
	const resources = buildResourcesStrip();
	const quests = buildQuestPanel();
	topLeft.appendChild(resources.root);
	topLeft.appendChild(quests.root);

	const clock = buildClock();
	const keybinds = buildKeybindHints();
	const hotbar = buildHotbar();
	const brand = buildBrand();

	root.appendChild(topLeft);
	root.appendChild(clock.root);
	root.appendChild(keybinds);
	root.appendChild(hotbar);
	root.appendChild(brand);

	document.body.appendChild(root);

	// Live updates via event bus — quest + resource changes trigger re-render.
	// Scoped so a single .cleanup() unwinds them all.
	const bus = scopedBus();
	const refresh = () => {
		resources.render();
		quests.render();
	};
	bus.on("resource:collected", refresh);
	bus.on("resource:consumed",  refresh);
	bus.on("resource:depleted",  refresh);
	bus.on("quest:started",            refresh);
	bus.on("quest:objective-complete", refresh);
	bus.on("quest:completed",          refresh);
	bus.on("quest:failed",             refresh);
	bus.on("save:loaded",              refresh);

	// Tick the clock once a minute. Cheap; no requestAnimationFrame needed.
	const clockTimer = window.setInterval(clock.tick, 60_000);

	return {
		dispose: () => {
			window.clearInterval(clockTimer);
			bus.cleanup();
			root.remove();
		},
		refresh,
	};
};
