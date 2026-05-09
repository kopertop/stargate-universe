/**
 * Restoration Console State — read/write surface for the restoration console UI.
 *
 * Derives a view model from ShipState, resources, quest state, and loot state.
 * The console UI reads this snapshot and dispatches mutations through the
 * existing state systems (shipState.setPriorities, shipState.repairSubsystem,
 * resources.consumeResource, etc.).
 */
import { getGameSession } from "./game-session";
import { getAllResources, consumeResource, hasResource, type ResourceType } from "./resources";
import { SHIP_STATE_CONFIG, type ShipSystem, type ShipSystemId, type Subsystem } from "./ship-state";

// ─── Tab identifiers ─────────────────────────────────────────────────────────

export type ConsoleTab = "overview" | "power" | "resources" | "repairs" | "crew" | "upgrades";

// ─── View models ──────────────────────────────────────────────────────────────

export interface SystemSummary {
	id: ShipSystemId;
	label: string;
	condition: number;
	powered: boolean;
	priority: number;
	powerDraw: number;
}

export interface RepairEntry {
	subsystemId: string;
	label: string;
	condition: number;
	repairCost: number;
	canAfford: boolean;
	sectionLabel: string;
}

export interface CrewEntry {
	id: string;
	name: string;
	role: string;
	morale: number;
	location: string;
}

export interface DataCacheEntry {
	id: string;
	label: string;
	unlocked: boolean;
	description: string;
}

export interface ConsoleSnapshot {
	currentTab: ConsoleTab;
	systems: SystemSummary[];
	availablePower: number;
	maxPower: number;
	usedPower: number;
	resources: Record<string, number>;
	repairs: RepairEntry[];
	crew: CrewEntry[];
	upgradePoints: number;
	dataCaches: DataCacheEntry[];
	shipSections: number;
	shipSectionsDiscovered: number;
}

// ─── Labels ───────────────────────────────────────────────────────────────────

const SYSTEM_LABEL: Record<ShipSystemId, string> = {
	"power-grid": "Power Grid",
	"life-support": "Life Support",
	"ftl-drive": "FTL Drive",
	shields: "Shields",
	sensors: "Sensors",
	communications: "Communications",
	navigation: "Navigation",
	weapons: "Weapons",
};

const SUBSYSTEM_LABEL: Record<string, string> = {
	"corridor-conduit-1": "Corridor Conduit",
	"storage-lights": "Storage Lighting Panel",
	"storage-console": "Storage Bay Console",
	"gate-room-lights": "Gate Room Lighting Panel",
	"conduit-a1": "Conduit Junction A-1",
	"storage-power": "Storage Power Coupling",
	"co2-scrubbers": "CO\u2082 Scrubber Unit",
};

const SECTION_LABEL: Record<string, string> = {
	"gate-room": "Gate Room",
	"corridor-a1": "Corridor A-1",
	"storage-bay": "Storage Bay",
	"scrubber-room": "Scrubber Bay",
};

const CREW_DEFAULTS: Array<{ id: string; name: string; role: string }> = [
	{ id: "eli", name: "Eli Wallace", role: "Player / Engineer" },
	{ id: "dr-rush", name: "Dr. Nicholas Rush", role: "Lead Scientist" },
	{ id: "lt-scott", name: "Lt. Matthew Scott", role: "Military Leader" },
	{ id: "chloe", name: "Chloe Armstrong", role: "Civilian / Linguist" },
	{ id: "greer", name: "Ronald Greer", role: "Security" },
	{ id: "tj", name: "Tamara Johansen", role: "Medic" },
	{ id: "lisa-park", name: "Dr. Lisa Park", role: "Scientist / Botanist" },
];

// ─── Factory ──────────────────────────────────────────────────────────────────

export const buildConsoleSnapshot = (
	currentTab: ConsoleTab,
	upgradePoints = 0,
	dataCaches: DataCacheEntry[] = [],
): ConsoleSnapshot => {
	const { shipState } = getGameSession();
	const resources = getAllResources();

	const allSystems = shipState.getAllSystems().map((sys: ShipSystem) => ({
		id: sys.id,
		label: SYSTEM_LABEL[sys.id] ?? sys.id,
		condition: Math.round(sys.condition * 100),
		powered: sys.powered,
		priority: sys.priority,
		powerDraw: sys.powerDraw,
	}));

	const grid = shipState.getSystem("power-grid");
	const maxPower = 1000;
	const availablePower = grid ? Math.round(grid.condition * maxPower) : 0;
	const usedPower = allSystems
		.filter((s) => s.id !== "power-grid" && s.powered)
		.reduce((sum, s) => sum + s.powerDraw, 0);

	const allSubsystems = shipState.getAllSections()
		.flatMap((section) => shipState.getSubsystemsInSection(section.id));

	const repairs: RepairEntry[] = allSubsystems
		.filter((sub: Subsystem) => sub.condition < 1.0)
		.map((sub: Subsystem) => ({
			subsystemId: sub.id,
			label: SUBSYSTEM_LABEL[sub.id] ?? sub.id,
			condition: Math.round(sub.condition * 100),
			repairCost: sub.repairCost,
			canAfford: hasResource("ship-parts", sub.repairCost),
			sectionLabel: SECTION_LABEL[sub.sectionId] ?? sub.sectionId,
		}))
		.sort((a, b) => a.condition - b.condition);

	const sections = shipState.getAllSections();
	const sectionsDiscovered = sections.filter((s) => s.discovered).length;

	const crew: CrewEntry[] = CREW_DEFAULTS.map((c) => ({
		...c,
		morale: 50,
		location: "Gate Room",
	}));

	const resourceEntries: Record<string, number> = {};
	for (const type of Object.keys(resources) as ResourceType[]) {
		resourceEntries[type] = resources[type] ?? 0;
	}

	return {
		currentTab,
		systems: allSystems,
		availablePower,
		maxPower,
		usedPower,
		resources: resourceEntries,
		repairs,
		crew,
		upgradePoints,
		dataCaches,
		shipSections: sections.length,
		shipSectionsDiscovered: sectionsDiscovered,
	};
};

// ─── Actions (dispatched from the console UI) ─────────────────────────────────

export const setPowerPriority = (systemId: ShipSystemId, priority: number): void => {
	const { shipState } = getGameSession();
	const allSystems = shipState.getAllSystems().map((s) => s.id);
	const idx = allSystems.indexOf(systemId);
	if (idx === -1) return;

	const ordered = [...allSystems];
	ordered.splice(idx, 1);
	ordered.splice(priority, 0, systemId);
	shipState.setPriorities(ordered);
};

export const toggleSystemPower = (systemId: ShipSystemId): void => {
	const { shipState } = getGameSession();
	const sys = shipState.getSystem(systemId);
	if (!sys || systemId === "power-grid") return;

	const ordered = shipState.getAllSystems()
		.sort((a, b) => a.priority - b.priority)
		.map((s) => s.id);

	if (sys.powered) {
		const idx = ordered.indexOf(systemId);
		if (idx !== -1) {
			ordered.splice(idx, 1);
			ordered.push(systemId);
		}
	} else {
		const idx = ordered.indexOf(systemId);
		if (idx !== -1) {
			ordered.splice(idx, 1);
			ordered.unshift(systemId);
		}
	}
	shipState.setPriorities(ordered);
};

export const requestConsoleRepair = (subsystemId: string): boolean => {
	const { shipState } = getGameSession();
	const sub = shipState.getSubsystem(subsystemId);
	if (!sub || sub.condition >= 1.0) return false;
	if (!hasResource("ship-parts", sub.repairCost)) return false;

	consumeResource("ship-parts", sub.repairCost);
	shipState.repairSubsystem(subsystemId);
	return true;
};

export const requestFullRepair = (subsystemId: string): boolean => {
	const { shipState } = getGameSession();
	const sub = shipState.getSubsystem(subsystemId);
	if (!sub || sub.condition >= 1.0) return false;

	let totalCost = 0;
	let remaining = sub.condition;
	const repairAmount = SHIP_STATE_CONFIG.BASE_REPAIR_AMOUNT * SHIP_STATE_CONFIG.REPAIR_SKILL_MODIFIER;
	while (remaining < 1.0) {
		totalCost += sub.repairCost;
		remaining += repairAmount;
	}

	if (!hasResource("ship-parts", totalCost)) return false;
	consumeResource("ship-parts", totalCost);

	let repairsDone = 0;
	while (sub.condition < 1.0 && repairsDone < 10) {
		shipState.repairSubsystem(subsystemId);
		repairsDone++;
	}
	return true;
};
