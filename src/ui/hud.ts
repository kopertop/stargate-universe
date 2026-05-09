/**
 * Player HUD — concept-facing exploration overlay.
 *
 * The HUD is display-only. Shared gameplay systems own resources, quests,
 * timers, ship state, and loot; this renderer turns those snapshots into the
 * persistent third-person exploration layer shown in the Destiny Restored
 * concept: compass/location, compact objectives, resource strip, vitals,
 * multi-tool status, countdowns, and pickup feedback.
 */
import type { QuestObjective } from "@kopertop/vibe-game-engine";
import { getActiveQuestManager } from "../systems/active-quest-manager";
import { scopedBus } from "../systems/event-bus";
import { getGameSession } from "../systems/game-session";
import { getAllResources, type ResourceType } from "../systems/resources";

export interface HudHandle {
	dispose: () => void;
	/** Force a full re-render (e.g. after scene change or save load). */
	refresh: () => void;
}

const RESOURCE_LABEL: Record<ResourceType, string> = {
	"ship-parts": "Parts",
	water: "Water",
	food: "Rations",
	lime: "Lime",
};

const RESOURCE_SHORT: Record<ResourceType, string> = {
	"ship-parts": "Ti",
	water: "H2O",
	food: "FD",
	lime: "Ca",
};

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

const STYLE_ID = "sgu-hud-style";

const STYLE = `
.sgu-hud {
	position: fixed;
	inset: 0;
	pointer-events: none;
	z-index: 100;
	font-family: Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
	color: #e8f2ff;
	text-shadow: 0 1px 2px rgba(0, 0, 0, 0.9);
	user-select: none;
}
.sgu-hud * {
	box-sizing: border-box;
	pointer-events: none;
	letter-spacing: 0;
}
.sgu-hud-panel {
	background: linear-gradient(180deg, rgba(10, 16, 24, 0.82), rgba(5, 9, 14, 0.66));
	border: 1px solid rgba(138, 174, 205, 0.26);
	box-shadow: 0 14px 36px rgba(0, 0, 0, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.06);
	backdrop-filter: blur(8px);
	border-radius: 4px;
}
.sgu-hud-kicker {
	color: #c9d9ea;
	font-size: 10px;
	font-weight: 700;
	text-transform: uppercase;
}
.sgu-hud-compass {
	position: absolute;
	top: 16px;
	left: 50%;
	transform: translateX(-50%);
	width: min(460px, calc(100vw - 32px));
	display: grid;
	grid-template-columns: repeat(5, 1fr);
	gap: 10px;
	align-items: end;
	color: #d8e9fb;
	font-size: 11px;
	text-align: center;
}
.sgu-hud-compass::after {
	content: "";
	position: absolute;
	left: 6%;
	right: 6%;
	bottom: 12px;
	height: 1px;
	background: linear-gradient(90deg, transparent, rgba(200, 225, 245, 0.42), transparent);
}
.sgu-hud-heading {
	position: relative;
	padding-bottom: 16px;
	opacity: 0.74;
}
.sgu-hud-heading.is-current {
	opacity: 1;
	color: #ffffff;
}
.sgu-hud-heading.is-current::after {
	content: "";
	position: absolute;
	left: 50%;
	bottom: 4px;
	transform: translateX(-50%);
	width: 8px;
	height: 8px;
	border: 1px solid #ffd36b;
	background: rgba(255, 211, 107, 0.12);
	rotate: 45deg;
}
.sgu-hud-location {
	position: absolute;
	top: 38px;
	left: 50%;
	transform: translateX(-50%);
	color: #d5e8ff;
	font-size: 10px;
	font-weight: 700;
	text-transform: uppercase;
}
.sgu-hud-objectives {
	position: absolute;
	top: 68px;
	right: 22px;
	width: min(310px, calc(100vw - 44px));
	padding: 14px;
}
.sgu-hud-objectives-title {
	margin-bottom: 8px;
}
.sgu-hud-quest-name {
	color: #ffffff;
	font-size: 13px;
	font-weight: 700;
	margin-bottom: 8px;
}
.sgu-hud-objective-list {
	display: flex;
	flex-direction: column;
	gap: 7px;
}
.sgu-hud-objective {
	display: grid;
	grid-template-columns: 14px 1fr;
	gap: 8px;
	align-items: start;
	color: #d9e6f3;
	font-size: 12px;
	line-height: 1.3;
}
.sgu-hud-check {
	width: 12px;
	height: 12px;
	border: 1px solid rgba(235, 245, 255, 0.72);
	border-radius: 50%;
	margin-top: 1px;
}
.sgu-hud-objective.is-complete {
	color: rgba(217, 230, 243, 0.58);
}
.sgu-hud-objective.is-complete .sgu-hud-check {
	background: #8ad6ff;
	border-color: #8ad6ff;
	box-shadow: 0 0 10px rgba(138, 214, 255, 0.5);
}
.sgu-hud-timers {
	position: absolute;
	top: 68px;
	left: 22px;
	width: min(260px, calc(100vw - 44px));
	padding: 12px;
	display: flex;
	flex-direction: column;
	gap: 8px;
}
.sgu-hud-timer {
	display: flex;
	justify-content: space-between;
	gap: 12px;
	color: #f6c5b2;
	font-family: ui-monospace, "SF Mono", Menlo, monospace;
	font-size: 12px;
}
.sgu-hud-timer.is-critical {
	color: #ff7b5d;
}
.sgu-hud-player {
	position: absolute;
	left: 22px;
	bottom: 22px;
	width: min(330px, calc(100vw - 44px));
	padding: 12px;
	display: grid;
	grid-template-columns: 54px 1fr;
	gap: 12px;
	align-items: center;
}
.sgu-hud-portrait {
	width: 54px;
	height: 64px;
	border: 1px solid rgba(168, 202, 232, 0.35);
	border-radius: 3px;
	background:
		radial-gradient(circle at 52% 34%, rgba(210, 224, 238, 0.55) 0 12%, transparent 13%),
		linear-gradient(180deg, #1b2b39, #080d13);
	position: relative;
	overflow: hidden;
}
.sgu-hud-portrait::after {
	content: "";
	position: absolute;
	left: 14px;
	right: 14px;
	bottom: 4px;
	height: 27px;
	border-radius: 50% 50% 0 0;
	background: linear-gradient(180deg, #1f2935, #111820);
}
.sgu-hud-player-name {
	font-size: 11px;
	font-weight: 800;
	text-transform: uppercase;
	margin-bottom: 7px;
	color: #ffffff;
}
.sgu-hud-vital {
	display: grid;
	grid-template-columns: 62px 1fr 42px;
	align-items: center;
	gap: 8px;
	margin-top: 5px;
	font-size: 10px;
	text-transform: uppercase;
	color: #cfdae5;
}
.sgu-hud-bar {
	height: 6px;
	background: rgba(255, 255, 255, 0.11);
	overflow: hidden;
	border-radius: 1px;
}
.sgu-hud-bar-fill {
	height: 100%;
	background: linear-gradient(90deg, #87d8ff, #d7f2ff);
}
.sgu-hud-vital.is-power .sgu-hud-bar-fill {
	background: linear-gradient(90deg, #ffd36b, #fff0a8);
}
.sgu-hud-vital.is-oxygen .sgu-hud-bar-fill {
	background: linear-gradient(90deg, #65baff, #9edcff);
}
.sgu-hud-resources {
	position: absolute;
	left: 50%;
	bottom: 20px;
	transform: translateX(-50%);
	display: flex;
	gap: 8px;
	max-width: calc(100vw - 390px);
	justify-content: center;
	flex-wrap: wrap;
}
.sgu-hud-resource {
	min-width: 86px;
	padding: 8px 10px;
	display: grid;
	grid-template-columns: 24px 1fr;
	gap: 8px;
	align-items: center;
}
.sgu-hud-resource-code {
	width: 24px;
	height: 24px;
	display: grid;
	place-items: center;
	border-radius: 50%;
	border: 1px solid rgba(136, 200, 255, 0.3);
	color: #8cd4ff;
	font-size: 10px;
	font-weight: 800;
}
.sgu-hud-resource-label {
	color: #b8c8d8;
	font-size: 9px;
	text-transform: uppercase;
}
.sgu-hud-resource-count {
	color: #ffffff;
	font-size: 16px;
	font-weight: 800;
	font-variant-numeric: tabular-nums;
	line-height: 1;
}
.sgu-hud-tool {
	position: absolute;
	right: 22px;
	bottom: 22px;
	width: min(285px, calc(100vw - 44px));
	padding: 12px;
}
.sgu-hud-tool-name {
	display: flex;
	justify-content: space-between;
	gap: 12px;
	margin-bottom: 10px;
	color: #ffffff;
	font-size: 12px;
	font-weight: 800;
	text-transform: uppercase;
}
.sgu-hud-tool-visual {
	height: 44px;
	border: 1px solid rgba(154, 204, 244, 0.28);
	background:
		linear-gradient(90deg, transparent 0 25%, rgba(119, 184, 239, 0.18) 26% 72%, transparent 73%),
		linear-gradient(180deg, rgba(30, 49, 68, 0.75), rgba(9, 14, 20, 0.75));
	position: relative;
}
.sgu-hud-tool-visual::before,
.sgu-hud-tool-visual::after {
	content: "";
	position: absolute;
	top: 19px;
	height: 6px;
	background: #a8d9ff;
	box-shadow: 0 0 12px rgba(101, 186, 255, 0.5);
}
.sgu-hud-tool-visual::before {
	left: 36px;
	width: 118px;
}
.sgu-hud-tool-visual::after {
	right: 30px;
	width: 58px;
}
.sgu-hud-feedback {
	position: absolute;
	left: 50%;
	bottom: 112px;
	transform: translateX(-50%);
	min-width: 260px;
	padding: 10px 14px;
	color: #fff0b8;
	font-size: 12px;
	font-weight: 700;
	text-align: center;
	opacity: 0;
	transition: opacity 160ms ease;
}
.sgu-hud-feedback.is-visible {
	opacity: 1;
}
@media (max-width: 900px), (pointer: coarse) {
	.sgu-hud-objectives {
		top: 58px;
		right: 10px;
		width: min(280px, calc(100vw - 20px));
	}
	.sgu-hud-timers {
		top: 58px;
		left: 10px;
		width: 210px;
	}
	.sgu-hud-tool {
		display: none;
	}
	.sgu-hud-player {
		left: 10px;
		bottom: 86px;
		width: 270px;
	}
	.sgu-hud-resources {
		left: 10px;
		right: 10px;
		bottom: 12px;
		transform: none;
		max-width: none;
		justify-content: flex-start;
	}
	.sgu-hud-resource {
		min-width: 72px;
		padding: 7px 8px;
	}
}
`;

const ensureStyle = (): void => {
	if (document.getElementById(STYLE_ID)) return;
	const style = document.createElement("style");
	style.id = STYLE_ID;
	style.textContent = STYLE;
	document.head.appendChild(style);
};

const formatTimer = (seconds: number): string => {
	const remaining = Math.max(0, Math.floor(seconds));
	const hours = Math.floor(remaining / 3600);
	const minutes = Math.floor((remaining % 3600) / 60);
	const secs = remaining % 60;
	if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
	return `${minutes}:${String(secs).padStart(2, "0")}`;
};

const buildCompass = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-compass");
	for (const heading of ["W", "NW", "N", "NE", "E"]) {
		root.appendChild(el("div", `sgu-hud-heading${heading === "N" ? " is-current" : ""}`, heading));
	}
	root.appendChild(el("div", "sgu-hud-location", "Engineering Deck"));
	return root;
};

const buildObjectives = (): { root: HTMLDivElement; render: () => void } => {
	const root = el("div", "sgu-hud-objectives sgu-hud-panel");
	const title = el("div", "sgu-hud-kicker sgu-hud-objectives-title", "Objective");
	const questName = el("div", "sgu-hud-quest-name", "Systems Standby");
	const list = el("div", "sgu-hud-objective-list");
	root.append(title, questName, list);

	const render = () => {
		list.replaceChildren();
		const manager = getActiveQuestManager();
		if (!manager) {
			questName.textContent = "Systems Standby";
			list.appendChild(el("div", "sgu-hud-objective", "Awaiting mission data"));
			return;
		}

		const active = [...manager.getQuestLog().active.values()];
		const current = active[0];
		if (!current) {
			questName.textContent = "Destiny Systems";
			list.appendChild(el("div", "sgu-hud-objective", "No active objectives"));
			return;
		}

		questName.textContent = current.definition.title ?? current.definition.name ?? current.definition.id;
		const visible = current.objectives.filter((objective: QuestObjective) => objective.visible);
		for (const objective of visible.slice(0, 3)) {
			const row = el("div", `sgu-hud-objective${objective.completed ? " is-complete" : ""}`);
			row.appendChild(el("span", "sgu-hud-check"));
			row.appendChild(el("span", undefined, objective.description));
			list.appendChild(row);
		}
	};

	render();
	return { root, render };
};

const buildTimers = (): { root: HTMLDivElement; render: () => void } => {
	const root = el("div", "sgu-hud-timers sgu-hud-panel");
	root.appendChild(el("div", "sgu-hud-kicker", "Ship Alerts"));

	const render = () => {
		root.querySelectorAll(".sgu-hud-timer").forEach((node) => node.remove());
		const timers = getGameSession().timers.getActiveTimers().filter((timer) => timer.visible);
		if (timers.length === 0) {
			root.style.display = "none";
			return;
		}
		root.style.display = "";
		for (const timer of timers) {
			const row = el("div", `sgu-hud-timer${timer.remainingSeconds < 120 ? " is-critical" : ""}`);
			row.appendChild(el("span", undefined, timer.tags.includes("life-support") ? "CO2 SCRUBBERS" : timer.id.toUpperCase()));
			row.appendChild(el("span", undefined, formatTimer(timer.remainingSeconds)));
			root.appendChild(row);
		}
	};

	render();
	return { root, render };
};

const buildPlayerPanel = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-player sgu-hud-panel");
	root.appendChild(el("div", "sgu-hud-portrait"));
	const details = el("div");
	details.appendChild(el("div", "sgu-hud-player-name", "Eli Wallace"));

	const vitals: ReadonlyArray<readonly [string, string, number, string]> = [
		["Health", "", 100, "100"],
		["Power", " is-power", 76, "76"],
		["Oxygen", " is-oxygen", 92, "92"],
	];
	for (const [label, modifier, pct, text] of vitals) {
		const row = el("div", `sgu-hud-vital${modifier}`);
		row.appendChild(el("span", undefined, label));
		const bar = el("div", "sgu-hud-bar");
		const fill = el("div", "sgu-hud-bar-fill");
		fill.style.width = `${pct}%`;
		bar.appendChild(fill);
		row.appendChild(bar);
		row.appendChild(el("span", undefined, `${text}/100`));
		details.appendChild(row);
	}
	root.appendChild(details);
	return root;
};

const buildResourcesStrip = (): { root: HTMLDivElement; render: () => void } => {
	const root = el("div", "sgu-hud-resources");
	const counts = new Map<ResourceType, HTMLDivElement>();

	for (const type of Object.keys(RESOURCE_LABEL) as ResourceType[]) {
		const item = el("div", "sgu-hud-resource sgu-hud-panel");
		item.appendChild(el("div", "sgu-hud-resource-code", RESOURCE_SHORT[type]));
		const meta = el("div");
		meta.appendChild(el("div", "sgu-hud-resource-label", RESOURCE_LABEL[type]));
		const count = el("div", "sgu-hud-resource-count", "0");
		meta.appendChild(count);
		item.appendChild(meta);
		root.appendChild(item);
		counts.set(type, count);
	}

	const render = () => {
		const resources = getAllResources();
		for (const [type, count] of counts) {
			count.textContent = String(resources[type] ?? 0);
		}
	};

	render();
	return { root, render };
};

const buildToolPanel = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-tool sgu-hud-panel");
	root.appendChild(el("div", "sgu-hud-kicker", "Multi-Tool"));
	const name = el("div", "sgu-hud-tool-name");
	name.appendChild(el("span", undefined, "Arc Cutter"));
	name.appendChild(el("span", undefined, "100%"));
	root.appendChild(name);
	root.appendChild(el("div", "sgu-hud-tool-visual"));
	return root;
};

const buildFeedback = (): {
	root: HTMLDivElement;
	show: (message: string) => void;
	dispose: () => void;
} => {
	const root = el("div", "sgu-hud-feedback sgu-hud-panel");
	let timer: number | undefined;

	const show = (message: string): void => {
		root.textContent = message;
		root.classList.add("is-visible");
		if (timer !== undefined) window.clearTimeout(timer);
		timer = window.setTimeout(() => {
			root.classList.remove("is-visible");
			timer = undefined;
		}, 1800);
	};

	return {
		root,
		show,
		dispose: () => {
			if (timer !== undefined) window.clearTimeout(timer);
		},
	};
};

export const mountHud = (): HudHandle => {
	ensureStyle();

	const root = el("div", "sgu-hud");
	const objectives = buildObjectives();
	const timers = buildTimers();
	const resources = buildResourcesStrip();
	const feedback = buildFeedback();

	root.appendChild(buildCompass());
	root.appendChild(objectives.root);
	root.appendChild(timers.root);
	root.appendChild(buildPlayerPanel());
	root.appendChild(resources.root);
	root.appendChild(buildToolPanel());
	root.appendChild(feedback.root);
	document.body.appendChild(root);

	const bus = scopedBus();
	const refresh = () => {
		resources.render();
		objectives.render();
		timers.render();
	};
	bus.on("resource:collected", ({ type, amount }) => {
		refresh();
		feedback.show(`${RESOURCE_LABEL[type as ResourceType] ?? type} +${amount}`);
	});
	bus.on("resource:consumed", refresh);
	bus.on("resource:depleted", refresh);
	bus.on("loot:container:opened", ({ source }) => {
		refresh();
		feedback.show(source === "gate-room" ? "Supply crate opened" : "Loot recovered");
	});
	bus.on("inventory:story-item:acquired", ({ itemName }) => {
		refresh();
		feedback.show(`${itemName} acquired`);
	});
	bus.on("quest:started", refresh);
	bus.on("quest:objective-complete", refresh);
	bus.on("quest:completed", refresh);
	bus.on("quest:failed", refresh);
	bus.on("save:loaded", refresh);
	bus.on("timer:created", refresh);
	bus.on("timer:halted", refresh);
	bus.on("timer:resumed", refresh);
	bus.on("timer:cancelled", refresh);

	const renderTimer = window.setInterval(refresh, 1000);

	return {
		dispose: () => {
			window.clearInterval(renderTimer);
			feedback.dispose();
			bus.cleanup();
			root.remove();
		},
		refresh,
	};
};
