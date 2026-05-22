/**
 * Player HUD — Destiny Restored exploration overlay.
 *
 * Layout matches design/concept-art/ui/destiny-restored-hud-layout.png:
 *   Top center: live compass + location
 *   Top right: objective tracker
 *   Bottom left: player unit frame (portrait + vitals)
 *   Bottom center: multi-tool action bar
 *   Bottom right: bag inventory
 *   Bottom strip: resource/ship status bar
 *
 * Ship telemetry stays on physical consoles until the Kino remote is unlocked.
 */
import type { QuestObjective } from "@kopertop/vibe-game-engine";
import { getActiveQuestManager } from "../systems/active-quest-manager";
import { scopedBus } from "../systems/event-bus";
import { getAllResources, type ResourceType } from "../systems/resources";
import "./styles/hud.scss";

export interface HudHandle {
	dispose: () => void;
	refresh: () => void;
	updateCompass: (cameraYaw: number) => void;
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

const COMPASS_POINTS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as const;

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

const buildCompass = (sceneTitle: string): {
	root: HTMLDivElement;
	locationEl: HTMLDivElement;
	tickEls: HTMLDivElement[];
} => {
	const root = el("div", "sgu-hud-compass");
	const tickEls: HTMLDivElement[] = [];

	for (const heading of COMPASS_POINTS) {
		const tick = el("div", "sgu-hud-compass-tick", heading);
		tickEls.push(tick);
		root.appendChild(tick);
	}

	const locationEl = el("div", "sgu-hud-location", sceneTitle);
	root.appendChild(locationEl);
	return { root, locationEl, tickEls };
};

function updateCompassHeading(tickEls: HTMLDivElement[], cameraYaw: number): void {
	// cameraYaw is in radians; 0 = looking +Z (south in game), PI/2 = looking +X (west)
	// Normalize to 0–360 compass degrees where 0=N (looking -Z)
	let degrees = (((-cameraYaw * 180) / Math.PI) + 360) % 360;
	// Find which compass point is closest to current heading
	const pointIndex = Math.round(degrees / 45) % 8;
	for (let i = 0; i < tickEls.length; i++) {
		tickEls[i].classList.toggle("is-current", i === pointIndex);
	}
}

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

const buildBottomStrip = (): HTMLDivElement => {
	const root = el("div", "sgu-hud-bottom-strip");

	const items: Array<{ label: string; value: string }> = [
		{ label: "Tritanium", value: "540" },
		{ label: "Naquadah", value: "320" },
		{ label: "Silicon", value: "210" },
		{ label: "Power", value: "68%" },
		{ label: "Crew", value: "29/97" },
	];

	for (let i = 0; i < items.length; i++) {
		if (i > 0) root.appendChild(el("div", "sgu-hud-strip-separator"));
		const item = el("div", "sgu-hud-strip-item");
		item.appendChild(el("div", "sgu-hud-strip-icon"));
		item.appendChild(el("span", undefined, items[i].label));
		item.appendChild(el("span", "sgu-hud-strip-value", items[i].value));
		root.appendChild(item);
	}

	root.appendChild(el("div", "sgu-hud-strip-separator"));

	// Destiny integrity bar
	const integrityItem = el("div", "sgu-hud-strip-item");
	integrityItem.appendChild(el("span", undefined, "Integrity"));
	const integrityBar = el("div", "sgu-hud-strip-bar");
	const integrityFill = el("div", "sgu-hud-strip-bar-fill");
	integrityFill.style.width = "61%";
	integrityBar.appendChild(integrityFill);
	integrityItem.appendChild(integrityBar);
	integrityItem.appendChild(el("span", "sgu-hud-strip-value", "61%"));
	root.appendChild(integrityItem);

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

export const mountHud = (sceneTitle?: string): HudHandle => {
	const root = el("div", "sgu-hud");
	const compass = buildCompass(sceneTitle ?? "Gate Room");
	const objectives = buildObjectives();
	const bag = buildBagInventory();
	const feedback = buildFeedback();

	root.appendChild(compass.root);
	root.appendChild(objectives.root);
	root.appendChild(buildPlayerPanel());
	root.appendChild(buildActionBar());
	root.appendChild(bag.root);
	root.appendChild(buildBottomStrip());
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
		updateCompass: (cameraYaw: number) => {
			updateCompassHeading(compass.tickEls, cameraYaw);
		},
	};
};
