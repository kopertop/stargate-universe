/**
 * Player HUD — concept-facing exploration overlay.
 *
 * The HUD is display-only. Shared gameplay systems own resources, quests,
 * ship state, and loot; this renderer turns those snapshots into the
 * persistent third-person exploration layer shown in the Destiny Restored
 * concept: compass/location, compact objectives, a WoW-like unit frame, tool
 * slots, bag inventory, and pickup feedback.
 *
 * Ship telemetry stays on physical consoles until the Kino remote is unlocked.
 */
import type { QuestObjective } from "@kopertop/vibe-game-engine";
import { getActiveQuestManager } from "../systems/active-quest-manager";
import { scopedBus } from "../systems/event-bus";
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

const BAG_SLOTS: ReadonlyArray<{
	type?: ResourceType;
	code: string;
	label: string;
}> = [
	{ type: "ship-parts", code: "SP", label: "Ship Parts" },
	{ type: "lime", code: "Ca", label: "Lime" },
	{ code: "", label: "Empty Slot" },
	{ code: "", label: "Empty Slot" },
	{ code: "", label: "Empty Slot" },
	{ code: "", label: "Empty Slot" },
];

const ACTION_SLOTS: ReadonlyArray<{
	key: string;
	code: string;
	label: string;
}> = [
	{ key: "1", code: "AC", label: "Arc Cutter" },
	{ key: "2", code: "SC", label: "Scanner" },
	{ key: "3", code: "RP", label: "Repair" },
	{ key: "4", code: "--", label: "Locked" },
];

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
.sgu-hud-player {
	position: absolute;
	left: 16px;
	top: 16px;
	width: min(300px, calc(100vw - 32px));
	padding: 10px;
	display: grid;
	grid-template-columns: 52px 1fr;
	gap: 10px;
	align-items: center;
}
.sgu-hud-portrait {
	width: 52px;
	height: 52px;
	border: 1px solid rgba(168, 202, 232, 0.35);
	border-radius: 50%;
	background:
		radial-gradient(circle at 52% 34%, rgba(210, 224, 238, 0.55) 0 12%, transparent 13%),
		linear-gradient(180deg, #1b2b39, #080d13);
	position: relative;
	overflow: hidden;
}
.sgu-hud-portrait::after {
	content: "";
	position: absolute;
	left: 12px;
	right: 12px;
	bottom: 2px;
	height: 22px;
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
	grid-template-columns: 50px 1fr 40px;
	align-items: center;
	gap: 7px;
	margin-top: 4px;
	font-size: 9px;
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
.sgu-hud-actionbar {
	position: absolute;
	left: 50%;
	bottom: 18px;
	transform: translateX(-50%);
	display: flex;
	gap: 6px;
	justify-content: center;
}
.sgu-hud-action-slot {
	position: relative;
	width: 54px;
	height: 54px;
	display: grid;
	place-items: center;
	background:
		linear-gradient(180deg, rgba(32, 50, 67, 0.92), rgba(6, 10, 15, 0.92)),
		radial-gradient(circle at 50% 45%, rgba(122, 199, 255, 0.26), transparent 58%);
	border: 1px solid rgba(166, 204, 236, 0.3);
	box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.04), 0 8px 22px rgba(0, 0, 0, 0.38);
	border-radius: 4px;
	color: #dff3ff;
	font-weight: 800;
	font-size: 13px;
}
.sgu-hud-action-slot.is-locked {
	color: rgba(208, 224, 238, 0.46);
	background: linear-gradient(180deg, rgba(18, 25, 34, 0.88), rgba(5, 8, 12, 0.88));
}
.sgu-hud-action-key {
	position: absolute;
	left: 5px;
	top: 3px;
	color: #93b7d5;
	font-family: ui-monospace, "SF Mono", Menlo, monospace;
	font-size: 10px;
	font-weight: 800;
}
.sgu-hud-action-label {
	position: absolute;
	left: 4px;
	right: 4px;
	bottom: 4px;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
	color: rgba(224, 238, 249, 0.72);
	font-size: 8px;
	font-weight: 700;
	text-align: center;
	text-transform: uppercase;
}
.sgu-hud-bag {
	position: absolute;
	right: 18px;
	bottom: 18px;
	display: grid;
	grid-template-columns: 54px auto;
	align-items: end;
	gap: 8px;
}
.sgu-hud-bag-button {
	position: relative;
	width: 54px;
	height: 54px;
	display: grid;
	place-items: center;
	border-radius: 4px;
	border: 1px solid rgba(210, 180, 112, 0.46);
	background:
		linear-gradient(180deg, rgba(58, 46, 26, 0.92), rgba(18, 13, 8, 0.94)),
		radial-gradient(circle at 48% 42%, rgba(255, 207, 119, 0.24), transparent 58%);
	color: #ffe4a3;
	box-shadow: inset 0 0 0 1px rgba(255, 244, 205, 0.08), 0 8px 22px rgba(0, 0, 0, 0.38);
	font-size: 12px;
	font-weight: 800;
	text-transform: uppercase;
}
.sgu-hud-bag-count {
	position: absolute;
	right: 4px;
	bottom: 3px;
	color: #ffffff;
	font-family: ui-monospace, "SF Mono", Menlo, monospace;
	font-size: 10px;
	font-weight: 800;
}
.sgu-hud-bag-grid {
	display: grid;
	grid-template-columns: repeat(3, 38px);
	gap: 4px;
}
.sgu-hud-bag-slot {
	position: relative;
	width: 38px;
	height: 38px;
	display: grid;
	place-items: center;
	border-radius: 3px;
	border: 1px solid rgba(142, 168, 190, 0.24);
	background: linear-gradient(180deg, rgba(20, 29, 39, 0.9), rgba(4, 7, 11, 0.88));
	color: #d9efff;
	font-size: 11px;
	font-weight: 800;
}
.sgu-hud-bag-slot.is-empty {
	color: transparent;
	background: rgba(4, 7, 11, 0.55);
}
.sgu-hud-bag-stack {
	position: absolute;
	right: 3px;
	bottom: 1px;
	color: #ffffff;
	font-family: ui-monospace, "SF Mono", Menlo, monospace;
	font-size: 10px;
	font-weight: 800;
	text-shadow: 0 1px 2px #000;
}
.sgu-hud-feedback {
	position: absolute;
	left: 50%;
	bottom: 86px;
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
	.sgu-hud-player {
		left: 10px;
		top: 10px;
		width: 252px;
	}
	.sgu-hud-actionbar {
		bottom: 10px;
	}
	.sgu-hud-action-slot,
	.sgu-hud-bag-button {
		width: 46px;
		height: 46px;
	}
	.sgu-hud-bag {
		right: 10px;
		bottom: 10px;
		grid-template-columns: 46px;
	}
	.sgu-hud-bag-grid {
		display: none;
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

const buildActionBar = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-actionbar");
	for (const slot of ACTION_SLOTS) {
		const button = el("div", `sgu-hud-action-slot${slot.code === "--" ? " is-locked" : ""}`);
		button.title = slot.label;
		button.appendChild(el("span", "sgu-hud-action-key", slot.key));
		button.appendChild(el("span", "sgu-hud-action-code", slot.code));
		button.appendChild(el("span", "sgu-hud-action-label", slot.label));
		root.appendChild(button);
	}
	return root;
};

const buildBagInventory = (): { root: HTMLDivElement; render: () => void } => {
	const root = el("div", "sgu-hud-bag");
	const button = el("div", "sgu-hud-bag-button", "Bag");
	const total = el("span", "sgu-hud-bag-count", "0");
	button.title = "Personal Bag";
	button.appendChild(total);
	const grid = el("div", "sgu-hud-bag-grid");
	const stacks = new Map<ResourceType, HTMLSpanElement>();

	for (const slot of BAG_SLOTS) {
		const item = el("div", `sgu-hud-bag-slot${slot.type ? "" : " is-empty"}`, slot.code);
		item.title = slot.label;
		if (slot.type) {
			const stack = el("span", "sgu-hud-bag-stack", "0");
			item.appendChild(stack);
			stacks.set(slot.type, stack);
		}
		grid.appendChild(item);
	}

	root.append(button, grid);

	const render = () => {
		const resources = getAllResources();
		let totalItems = 0;
		for (const [type, stack] of stacks) {
			const count = resources[type] ?? 0;
			totalItems += count;
			stack.textContent = String(count);
		}
		total.textContent = String(totalItems);
	};

	render();
	return { root, render };
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
	const bag = buildBagInventory();
	const feedback = buildFeedback();

	root.appendChild(buildCompass());
	root.appendChild(objectives.root);
	root.appendChild(buildPlayerPanel());
	root.appendChild(buildActionBar());
	root.appendChild(bag.root);
	root.appendChild(feedback.root);
	document.body.appendChild(root);

	const bus = scopedBus();
	const refresh = () => {
		bag.render();
		objectives.render();
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

	return {
		dispose: () => {
			feedback.dispose();
			bus.cleanup();
			root.remove();
		},
		refresh,
	};
};
