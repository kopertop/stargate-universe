/**
 * Restoration Console UI — full-page overlay matching the Destiny Restored
 * concept image's dense data panels.
 *
 * Mounted/unmounted on demand (Tab key or interaction with a restoration
 * console in the scene). Reads from RestorationConsoleState for live data
 * and dispatches mutations (repair, power priority, etc.) through the
 * existing ShipState / Resources systems.
 */
import {
	buildConsoleSnapshot,
	requestConsoleRepair,
	requestFullRepair,
	setPowerPriority,
	toggleSystemPower,
	type ConsoleSnapshot,
	type ConsoleTab,
	type RepairEntry,
	type SystemSummary,
} from "../systems/restoration-console-state";

// ─── Stylesheet ID ────────────────────────────────────────────────────────────

const STYLE_ID = "sgu-console-style";
const STYLE = `
.sgu-console-overlay {
	position: fixed;
	inset: 0;
	z-index: 200;
	background: rgba(4, 6, 12, 0.92);
	backdrop-filter: blur(12px);
	display: flex;
	flex-direction: column;
	color: #d0def0;
	font-family: Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
	font-size: 13px;
	line-height: 1.4;
	user-select: none;
	overflow-y: auto;
}
.sgu-console-header {
	display: flex;
	align-items: center;
	justify-content: space-between;
	padding: 14px 24px;
	border-bottom: 1px solid rgba(100, 140, 200, 0.18);
	flex-shrink: 0;
}
.sgu-console-title {
	font-size: 16px;
	font-weight: 800;
	text-transform: uppercase;
	color: #f0f6ff;
	letter-spacing: 1.5px;
}
.sgu-console-close {
	background: rgba(180, 60, 60, 0.3);
	border: 1px solid rgba(200, 80, 80, 0.4);
	color: #f0b0b0;
	padding: 6px 16px;
	border-radius: 3px;
	cursor: pointer;
	font-size: 12px;
	font-family: inherit;
}
.sgu-console-close:hover {
	background: rgba(200, 60, 60, 0.5);
}
.sgu-console-tabs {
	display: flex;
	gap: 2px;
	padding: 0 24px;
	border-bottom: 1px solid rgba(100, 140, 200, 0.12);
	flex-shrink: 0;
}
.sgu-console-tab {
	padding: 10px 18px;
	font-size: 11px;
	font-weight: 700;
	text-transform: uppercase;
	color: #7a8aa0;
	cursor: pointer;
	border-bottom: 2px solid transparent;
	letter-spacing: 0.5px;
	background: none;
	border-top: none;
	border-left: none;
	border-right: none;
	font-family: inherit;
}
.sgu-console-tab:hover {
	color: #b0c8e0;
}
.sgu-console-tab.is-active {
	color: #b8d8ff;
	border-bottom-color: #5a9cff;
}
.sgu-console-body {
	flex: 1;
	padding: 20px 24px 40px;
	display: grid;
	grid-template-columns: 1fr 1fr;
	gap: 20px;
	align-content: start;
}
.sgu-console-panel {
	background: rgba(10, 16, 28, 0.6);
	border: 1px solid rgba(100, 140, 200, 0.12);
	border-radius: 4px;
	padding: 16px;
}
.sgu-console-panel-title {
	font-size: 10px;
	font-weight: 800;
	text-transform: uppercase;
	color: #7894b0;
	margin-bottom: 12px;
	letter-spacing: 1px;
}
.sgu-console-panel-full {
	grid-column: 1 / -1;
}
.sgu-console-system-row {
	display: grid;
	grid-template-columns: 140px 1fr 50px 80px;
	gap: 10px;
	align-items: center;
	padding: 6px 0;
	border-bottom: 1px solid rgba(100, 140, 200, 0.06);
}
.sgu-console-system-name {
	font-size: 12px;
	color: #b8cce0;
}
.sgu-console-bar {
	height: 6px;
	background: rgba(255, 255, 255, 0.08);
	border-radius: 2px;
	overflow: hidden;
}
.sgu-console-bar-fill {
	height: 100%;
	border-radius: 2px;
	transition: width 240ms ease;
}
.sgu-console-bar-fill.is-good {
	background: linear-gradient(90deg, #4a9eff, #7abcff);
}
.sgu-console-bar-fill.is-warn {
	background: linear-gradient(90deg, #d4a040, #f0c860);
}
.sgu-console-bar-fill.is-critical {
	background: linear-gradient(90deg, #cc4040, #ff6060);
}
.sgu-console-pct {
	font-size: 11px;
	font-weight: 700;
	font-variant-numeric: tabular-nums;
	text-align: right;
}
.sgu-console-status {
	font-size: 10px;
	text-align: right;
}
.sgu-console-status.is-on {
	color: #60c080;
}
.sgu-console-status.is-off {
	color: #7a7a8a;
}
.sgu-console-repair-row {
	display: grid;
	grid-template-columns: 1fr 60px 70px 80px;
	gap: 10px;
	align-items: center;
	padding: 8px 0;
	border-bottom: 1px solid rgba(100, 140, 200, 0.06);
}
.sgu-console-repair-label {
	font-size: 12px;
	color: #b8cce0;
}
.sgu-console-repair-section {
	font-size: 10px;
	color: #6a7a90;
}
.sgu-console-repair-btn {
	padding: 4px 10px;
	border-radius: 3px;
	font-size: 10px;
	font-weight: 700;
	text-transform: uppercase;
	cursor: pointer;
	border: 1px solid rgba(100, 140, 200, 0.3);
	font-family: inherit;
	text-align: center;
}
.sgu-console-repair-btn.can-afford {
	background: rgba(60, 140, 80, 0.3);
	color: #80dc90;
	border-color: rgba(80, 180, 100, 0.4);
}
.sgu-console-repair-btn.can-afford:hover {
	background: rgba(60, 180, 80, 0.45);
}
.sgu-console-repair-btn.cannot-afford {
	background: rgba(80, 80, 80, 0.2);
	color: #6a6a7a;
	border-color: rgba(80, 80, 80, 0.2);
	cursor: default;
}
.sgu-console-resource-grid {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
	gap: 10px;
}
.sgu-console-resource-card {
	background: rgba(20, 30, 48, 0.5);
	border: 1px solid rgba(100, 140, 200, 0.1);
	border-radius: 3px;
	padding: 12px;
	text-align: center;
}
.sgu-console-resource-count {
	font-size: 28px;
	font-weight: 800;
	color: #f0f6ff;
	font-variant-numeric: tabular-nums;
}
.sgu-console-resource-label {
	font-size: 10px;
	text-transform: uppercase;
	color: #7894b0;
	margin-top: 4px;
}
.sgu-console-crew-grid {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
	gap: 10px;
}
.sgu-console-crew-card {
	background: rgba(20, 30, 48, 0.5);
	border: 1px solid rgba(100, 140, 200, 0.1);
	border-radius: 3px;
	padding: 12px;
}
.sgu-console-crew-name {
	font-size: 13px;
	font-weight: 700;
	color: #e0ecff;
}
.sgu-console-crew-role {
	font-size: 10px;
	color: #6a8aa8;
	margin-top: 2px;
}
.sgu-console-crew-location {
	font-size: 10px;
	color: #7894b0;
	margin-top: 4px;
}
.sgu-console-crew-morale {
	margin-top: 6px;
}
.sgu-console-power-summary {
	font-size: 24px;
	font-weight: 800;
	color: #f0f6ff;
	font-variant-numeric: tabular-nums;
}
.sgu-console-power-unit {
	font-size: 12px;
	font-weight: 400;
	color: #7894b0;
}
.sgu-console-power-bar {
	height: 8px;
	background: rgba(255, 255, 255, 0.08);
	border-radius: 3px;
	overflow: hidden;
	margin: 8px 0;
}
.sgu-console-power-fill {
	height: 100%;
	background: linear-gradient(90deg, #4a9eff, #7abcff);
	border-radius: 3px;
	transition: width 240ms ease;
}
.sgu-console-power-fill.is-over {
	background: linear-gradient(90deg, #cc4040, #ff6060);
}
@media (max-width: 800px) {
	.sgu-console-body {
		grid-template-columns: 1fr;
	}
	.sgu-console-tabs {
		overflow-x: auto;
	}
}
`;

// ─── DOM helper ──────────────────────────────────────────────────────────────

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

const ensureStyle = (): void => {
	if (document.getElementById(STYLE_ID)) return;
	const style = document.createElement("style");
	style.id = STYLE_ID;
	style.textContent = STYLE;
	document.head.appendChild(style);
};

// ─── Bar helpers ──────────────────────────────────────────────────────────────

const conditionClass = (pct: number): string => {
	if (pct >= 60) return "is-good";
	if (pct >= 30) return "is-warn";
	return "is-critical";
};

const formatPct = (pct: number): string => `${Math.round(pct)}%`;

const barHtml = (pct: number, extra = ""): string =>
	`<div class="sgu-console-bar"><div class="sgu-console-bar-fill ${conditionClass(pct)} ${extra}" style="width:${Math.round(pct)}%"></div></div>`;

// ─── Tab builders ─────────────────────────────────────────────────────────────

const buildTabBar = (current: ConsoleTab, onTab: (tab: ConsoleTab) => void): HTMLDivElement => {
	const bar = el("div", "sgu-console-tabs");
	const tabs: Array<{ id: ConsoleTab; label: string }> = [
		{ id: "overview", label: "Overview" },
		{ id: "power", label: "Power" },
		{ id: "resources", label: "Resources" },
		{ id: "repairs", label: "Repairs" },
		{ id: "crew", label: "Crew" },
		{ id: "upgrades", label: "Upgrades" },
	];
	for (const tab of tabs) {
		const btn = el("button", `sgu-console-tab${tab.id === current ? " is-active" : ""}`, tab.label);
		btn.addEventListener("click", () => onTab(tab.id));
		btn.type = "button";
		bar.appendChild(btn);
	}
	return bar;
};

// ─── Panel builders ───────────────────────────────────────────────────────────

const buildOverviewPanels = (snap: ConsoleSnapshot): HTMLDivElement[] => {
	const panels: HTMLDivElement[] = [];

	// System health
	const sysPanel = el("div", "sgu-console-panel sgu-console-panel-full");
	sysPanel.appendChild(el("div", "sgu-console-panel-title", "Ship System Status"));
	for (const sys of snap.systems) {
		if (sys.id === "power-grid") continue;
		const row = el("div", "sgu-console-system-row");
		row.appendChild(el("div", "sgu-console-system-name", sys.label));
		const barC = el("div");
		barC.innerHTML = barHtml(sys.condition);
		row.appendChild(barC);
		row.appendChild(el("div", "sgu-console-pct", formatPct(sys.condition)));
		row.appendChild(el("div", `sgu-console-status ${sys.powered ? "is-on" : "is-off"}`, sys.powered ? "POWERED" : "OFF"));
		sysPanel.appendChild(row);
	}
	panels.push(sysPanel);

	// Power summary
	const pwPanel = el("div", "sgu-console-panel");
	pwPanel.appendChild(el("div", "sgu-console-panel-title", "Power Grid"));
	const pwRow = el("div");
	pwRow.innerHTML = `
		<div class="sgu-console-power-summary">${snap.availablePower} <span class="sgu-console-power-unit">/ ${snap.maxPower} MW</span></div>
		<div class="sgu-console-power-bar"><div class="sgu-console-power-fill ${snap.usedPower > snap.availablePower ? "is-over" : ""}" style="width:${Math.round((snap.usedPower / snap.maxPower) * 100)}%"></div></div>
		<div style="font-size:11px; color:#7894b0; margin-top:4px">Used: ${snap.usedPower} MW &middot; Available: ${snap.availablePower} MW</div>
	`;
	pwPanel.appendChild(pwRow);
	panels.push(pwPanel);

	// Resources summary
	const resPanel = el("div", "sgu-console-panel");
	resPanel.appendChild(el("div", "sgu-console-panel-title", "Resources"));
	const resGrid = el("div", "sgu-console-resource-grid");
	for (const [type, count] of Object.entries(snap.resources)) {
		const card = el("div", "sgu-console-resource-card");
		card.appendChild(el("div", "sgu-console-resource-count", String(count)));
		card.appendChild(el("div", "sgu-console-resource-label", type.replace("-", " ")));
		resGrid.appendChild(card);
	}
	resPanel.appendChild(resGrid);
	panels.push(resPanel);

	return panels;
};

const buildPowerPanel = (snap: ConsoleSnapshot, onRepaint: () => void): HTMLDivElement[] => {
	const panel = el("div", "sgu-console-panel sgu-console-panel-full");
	panel.appendChild(el("div", "sgu-console-panel-title", "Power Priority"));

	const pwRow = el("div");
	pwRow.innerHTML = `
		<div class="sgu-console-power-summary">${snap.availablePower} <span class="sgu-console-power-unit">/ ${snap.maxPower} MW</span></div>
		<div class="sgu-console-power-bar"><div class="sgu-console-power-fill ${snap.usedPower > snap.availablePower ? "is-over" : ""}" style="width:${Math.round((snap.usedPower / snap.maxPower) * 100)}%"></div></div>
		<div style="font-size:11px; color:#7894b0; margin-top:4px; margin-bottom:12px">Allocated: ${snap.usedPower} MW &middot; Free: ${snap.availablePower - snap.usedPower} MW</div>
	`;
	panel.appendChild(pwRow);

	const sorted = [...snap.systems]
		.filter((s) => s.id !== "power-grid")
		.sort((a, b) => a.priority - b.priority);

	for (const sys of sorted) {
		const row = el("div", "sgu-console-system-row");
		row.appendChild(el("div", "sgu-console-system-name", sys.label));
		const barC = el("div");
		barC.innerHTML = barHtml(sys.condition);
		row.appendChild(barC);
		row.appendChild(el("div", "sgu-console-pct", `${sys.powerDraw} MW`));
		const toggleBtn = el("button", `sgu-console-repair-btn can-afford`, sys.powered ? "ON" : "OFF");
		toggleBtn.addEventListener("click", () => {
			toggleSystemPower(sys.id);
			onRepaint();
		});
		row.appendChild(toggleBtn);
		panel.appendChild(row);
	}

	return [panel];
};

const buildResourcesPanel = (snap: ConsoleSnapshot): HTMLDivElement[] => {
	const panel = el("div", "sgu-console-panel sgu-console-panel-full");
	panel.appendChild(el("div", "sgu-console-panel-title", "Ship Supplies"));
	const grid = el("div", "sgu-console-resource-grid");
	for (const [type, count] of Object.entries(snap.resources)) {
		const card = el("div", "sgu-console-resource-card");
		card.appendChild(el("div", "sgu-console-resource-count", String(count)));
		card.appendChild(el("div", "sgu-console-resource-label", type.replace("-", " ")));
		grid.appendChild(card);
	}
	panel.appendChild(grid);
	return [panel];
};

const buildRepairsPanel = (snap: ConsoleSnapshot, onRepaint: () => void): HTMLDivElement[] => {
	const panel = el("div", "sgu-console-panel sgu-console-panel-full");
	panel.appendChild(el("div", "sgu-console-panel-title", "Available Repairs"));

	if (snap.repairs.length === 0) {
		panel.appendChild(el("div", undefined, "All ship subsystems are in working order."));
		return [panel];
	}

	for (const repair of snap.repairs) {
		const row = el("div", "sgu-console-repair-row");
		const labelGroup = el("div");
		labelGroup.appendChild(el("div", "sgu-console-repair-label", repair.label));
		labelGroup.appendChild(el("div", "sgu-console-repair-section", repair.sectionLabel));
		row.appendChild(labelGroup);

		const barC = el("div");
		barC.innerHTML = barHtml(repair.condition, repair.condition < 30 ? "is-critical" : "is-warn");
		row.appendChild(barC);

		row.appendChild(el("div", "sgu-console-pct", `${repair.repairCost} Parts`));

		const repairBtn = el("button", `sgu-console-repair-btn ${repair.canAfford ? "can-afford" : "cannot-afford"}`, "Repair");
		if (repair.canAfford) {
			repairBtn.addEventListener("click", () => {
				requestConsoleRepair(repair.subsystemId);
				onRepaint();
			});
		}
		row.appendChild(repairBtn);

		panel.appendChild(row);
	}
	return [panel];
};

const buildCrewPanel = (snap: ConsoleSnapshot): HTMLDivElement[] => {
	const panel = el("div", "sgu-console-panel sgu-console-panel-full");
	panel.appendChild(el("div", "sgu-console-panel-title", "Crew Status"));
	const grid = el("div", "sgu-console-crew-grid");
	for (const member of snap.crew) {
		const card = el("div", "sgu-console-crew-card");
		card.appendChild(el("div", "sgu-console-crew-name", member.name));
		card.appendChild(el("div", "sgu-console-crew-role", member.role));
		card.appendChild(el("div", "sgu-console-crew-location", member.location));
		const moraleBar = el("div", "sgu-console-crew-morale");
		moraleBar.innerHTML = `<div style="font-size:9px;color:#6a8aa8;margin-bottom:2px">MORALE</div>${barHtml(member.morale)}`;
		card.appendChild(moraleBar);
		grid.appendChild(card);
	}
	panel.appendChild(grid);
	return [panel];
};

const buildUpgradesPanel = (snap: ConsoleSnapshot): HTMLDivElement[] => {
	const panel = el("div", "sgu-console-panel sgu-console-panel-full");
	panel.appendChild(el("div", "sgu-console-panel-title", "Engineering Upgrades"));
	panel.appendChild(el("div", undefined, `Upgrade Points: ${snap.upgradePoints}`));

	const upgrades = [
		{ name: "Reinforced Conduits", desc: "Reduce subsystem degradation rate by 20%", cost: 3, unlocked: false },
		{ name: "Emergency Batteries", desc: "Systems remain powered 30s longer during grid failure", cost: 5, unlocked: false },
		{ name: "Ancient Database Access", desc: "Unlock additional data caches across the ship", cost: 2, unlocked: false },
		{ name: "Automated Diagnostics", desc: "Highlight new damage on the repair screen", cost: 4, unlocked: false },
	];

	for (const upgrade of upgrades) {
		const row = el("div", "sgu-console-system-row");
		row.innerHTML = `
			<div style="font-size:12px;color:#b8cce0">${upgrade.name}</div>
			<div style="font-size:10px;color:#6a8aa8">${upgrade.desc}</div>
			<div style="font-size:11px;font-weight:700;text-align:right">${upgrade.cost} pts</div>
			<div style="font-size:10px;text-align:right;color:#6a7a90">${upgrade.unlocked ? "UNLOCKED" : "LOCKED"}</div>
		`;
		panel.appendChild(row);
	}
	return [panel];
};

// ─── Tab -> panel router ──────────────────────────────────────────────────────

const PANEL_BUILDERS: Record<ConsoleTab, (snap: ConsoleSnapshot, repaint: () => void) => HTMLDivElement[]> = {
	overview: (s) => buildOverviewPanels(s),
	power: (s, r) => buildPowerPanel(s, r),
	resources: (s) => buildResourcesPanel(s),
	repairs: (s, r) => buildRepairsPanel(s, r),
	crew: (s) => buildCrewPanel(s),
	upgrades: (s) => buildUpgradesPanel(s),
};

// ─── Mount / Unmount ──────────────────────────────────────────────────────────

export interface ConsoleHandle {
	dispose: () => void;
}

export const mountConsole = (options?: { initialTab?: ConsoleTab; onClose?: () => void }): ConsoleHandle => {
	ensureStyle();

	const { initialTab = "overview", onClose } = options ?? {};
	let currentTab: ConsoleTab = initialTab;
	let disposed = false;
	const overlay = el("div", "sgu-console-overlay");

	// Header
	const header = el("div", "sgu-console-header");
	const title = el("div", "sgu-console-title", "Restoration Console");
	const closeBtn = el("button", "sgu-console-close", "Close");
	closeBtn.addEventListener("click", () => dispose());
	closeBtn.type = "button";
	header.append(title, closeBtn);
	overlay.appendChild(header);

	// Tab bar
	let tabBar: HTMLDivElement;
	const switchTab = (tab: ConsoleTab) => {
		currentTab = tab;
		tabBar.remove();
		bodyEl.innerHTML = "";
		tabBar = buildTabBar(currentTab, switchTab);
		overlay.insertBefore(tabBar, bodyEl);
		repaint();
	};
	tabBar = buildTabBar(currentTab, switchTab);
	overlay.appendChild(tabBar);

	// Body
	const bodyEl = el("div", "sgu-console-body");
	overlay.appendChild(bodyEl);

	const repaint = () => {
		bodyEl.innerHTML = "";
		const snap = buildConsoleSnapshot(currentTab);
		const panels = PANEL_BUILDERS[currentTab](snap, repaint);
		for (const panel of panels) bodyEl.appendChild(panel);
	};

	repaint();

	document.body.appendChild(overlay);

	const dispose = () => {
		if (disposed) return;
		disposed = true;
		overlay.remove();
		onClose?.();
	};

	return { dispose };
};
