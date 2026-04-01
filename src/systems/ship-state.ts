/**
 * Ship State System — Central data authority for Destiny's physical condition.
 *
 * Three-tier model: Ship Systems → Sections → Subsystems.
 * All condition values are 0.0-1.0 (displayed as 0-100%).
 * Power distributes by priority order.
 *
 * @see design/gdd/ship-state-system.md
 */
import { emit, on, scopedBus, type GameEventMap } from "./event-bus";

// ─── Configuration (externalized tuning knobs) ──────────────────────────────

export const SHIP_STATE_CONFIG = {
	MAX_POWER_OUTPUT: 1000,
	MIN_POWER_RATIO: 0.3,
	BASE_DEGRADATION: 0.002,
	DAMAGE_ACCELERATION: 2.0,
	BASE_REPAIR_AMOUNT: 0.15,
	REPAIR_COST_SHIP_PARTS: 5,
	EMERGENCY_BATTERY_DURATION: 1800,
	LIFE_SUPPORT_CRITICAL_THRESHOLD: 0.3,
	LIFE_SUPPORT_FATAL_THRESHOLD: 0.1,
	ATMOSPHERE_DRAIN_RATE: 0.01,
	REPAIR_SKILL_MODIFIER: 0.8,
};

// ─── Type Definitions ────────────────────────────────────────────────────────

export type ShipSystemId =
	| "power-grid"
	| "life-support"
	| "ftl-drive"
	| "shields"
	| "sensors"
	| "communications"
	| "weapons"
	| "navigation";

export type SubsystemType =
	| "door"
	| "conduit"
	| "console"
	| "lighting-panel"
	| "life-support-unit"
	| "vent"
	| "water-recycler"
	| "ancient-console";

export type SectionAccessState =
	| "unexplored"
	| "explored"
	| "accessible"
	| "inaccessible"
	| "compromised";

/** Tier 1: Ship-wide system */
export interface ShipSystem {
	readonly id: ShipSystemId;
	condition: number;
	powered: boolean;
	priority: number;
	powerDraw: number;
	powerDrawOptimal: number;
}

/** Tier 3: Individual interactable subsystem */
export interface Subsystem {
	readonly id: string;
	readonly type: SubsystemType;
	readonly sectionId: string;
	condition: number;
	repairCost: number;
	functionalThreshold: number;
}

/** Tier 2: Physical section of the ship */
export interface Section {
	readonly id: string;
	discovered: boolean;
	accessible: boolean;
	atmosphere: number;
	powerLevel: number;
	structuralIntegrity: number;
	accessState: SectionAccessState;
	subsystems: string[];
}

/** Complete serializable snapshot */
export interface ShipStateSnapshot {
	version: number;
	systems: ShipSystem[];
	sections: Section[];
	subsystems: Subsystem[];
}

// ─── Default Data ────────────────────────────────────────────────────────────

const DEFAULT_SYSTEMS: ShipSystem[] = [
	{ id: "power-grid", condition: 0.4, powered: true, priority: 0, powerDraw: 0, powerDrawOptimal: 0 },
	{ id: "life-support", condition: 0.35, powered: false, priority: 1, powerDraw: 200, powerDrawOptimal: 200 },
	{ id: "shields", condition: 0.2, powered: false, priority: 2, powerDraw: 250, powerDrawOptimal: 250 },
	{ id: "ftl-drive", condition: 0.5, powered: false, priority: 3, powerDraw: 300, powerDrawOptimal: 300 },
	{ id: "sensors", condition: 0.3, powered: false, priority: 4, powerDraw: 100, powerDrawOptimal: 100 },
	{ id: "communications", condition: 0.15, powered: false, priority: 5, powerDraw: 80, powerDrawOptimal: 80 },
	{ id: "navigation", condition: 0.25, powered: false, priority: 6, powerDraw: 60, powerDrawOptimal: 60 },
	{ id: "weapons", condition: 0.1, powered: false, priority: 7, powerDraw: 200, powerDrawOptimal: 200 },
];

// ─── Ship State Class ────────────────────────────────────────────────────────

export class ShipState {
	private systems: Map<ShipSystemId, ShipSystem> = new Map();
	private sections: Map<string, Section> = new Map();
	private subsystems: Map<string, Subsystem> = new Map();
	private bus = scopedBus();

	constructor() {
		for (const sys of DEFAULT_SYSTEMS) {
			this.systems.set(sys.id, { ...sys });
		}
		this.distributePower();
	}

	// ─── System Queries ──────────────────────────────────────────────────────

	getSystem(id: ShipSystemId): ShipSystem | undefined {
		return this.systems.get(id);
	}

	getAllSystems(): ShipSystem[] {
		return [...this.systems.values()];
	}

	getSection(id: string): Section | undefined {
		return this.sections.get(id);
	}

	getAllSections(): Section[] {
		return [...this.sections.values()];
	}

	getSubsystem(id: string): Subsystem | undefined {
		return this.subsystems.get(id);
	}

	getSubsystemsInSection(sectionId: string): Subsystem[] {
		const section = this.sections.get(sectionId);
		if (!section) return [];
		return section.subsystems.map(id => this.subsystems.get(id)).filter(Boolean) as Subsystem[];
	}

	// ─── Section Management ──────────────────────────────────────────────────

	addSection(section: Section): void {
		this.sections.set(section.id, section);
		for (const subId of section.subsystems) {
			const sub = this.subsystems.get(subId);
			if (sub) {
				// subsystem already registered
			}
		}
	}

	addSubsystem(subsystem: Subsystem): void {
		this.subsystems.set(subsystem.id, subsystem);
		const section = this.sections.get(subsystem.sectionId);
		if (section && !section.subsystems.includes(subsystem.id)) {
			section.subsystems.push(subsystem.id);
		}
	}

	discoverSection(sectionId: string): void {
		const section = this.sections.get(sectionId);
		if (!section || section.discovered) return;

		section.discovered = true;
		if (section.accessState === "unexplored") {
			section.accessState = "explored";
		}
		this.bus.emit("ship:section:discovered", { sectionId });
	}

	// ─── Power Distribution ──────────────────────────────────────────────────

	/** Reorder system priorities. Array of system IDs in priority order (index 0 = highest). */
	setPriorities(orderedIds: ShipSystemId[]): void {
		for (let i = 0; i < orderedIds.length; i++) {
			const sys = this.systems.get(orderedIds[i]);
			if (sys) sys.priority = i;
		}
		this.distributePower();
		this.bus.emit("ship:power:changed", {});
	}

	/** Recalculate power distribution based on current grid condition and priorities. */
	distributePower(): void {
		const config = SHIP_STATE_CONFIG;
		const powerGrid = this.systems.get("power-grid");
		if (!powerGrid) return;

		const availablePower = powerGrid.condition * config.MAX_POWER_OUTPUT;
		let remaining = availablePower;

		// Sort by priority (lower number = higher priority)
		const sorted = [...this.systems.values()]
			.filter(s => s.id !== "power-grid")
			.sort((a, b) => a.priority - b.priority);

		for (const sys of sorted) {
			const allocated = Math.min(sys.powerDraw, remaining);
			remaining -= allocated;
			sys.powered = allocated >= sys.powerDraw * config.MIN_POWER_RATIO;
		}

		// Update section power levels based on conduit routing (simplified for MVP)
		for (const section of this.sections.values()) {
			section.powerLevel = this.calculateSectionPower(section);
			section.atmosphere = this.calculateSectionAtmosphere(section);
		}
	}

	/** Simplified power calculation for MVP (no DAG routing yet). */
	private calculateSectionPower(section: Section): number {
		const powerGrid = this.systems.get("power-grid");
		if (!powerGrid || !powerGrid.powered) return 0;

		// Find conduit subsystems in this section
		const conduits = this.getSubsystemsInSection(section.id)
			.filter(s => s.type === "conduit");

		if (conduits.length === 0) {
			// No conduits — section gets base power from grid condition
			return section.accessible ? powerGrid.condition : 0;
		}

		// Average conduit condition determines section power
		const avgConduitCondition = conduits.reduce((sum, c) => sum + c.condition, 0) / conduits.length;
		return powerGrid.condition * avgConduitCondition;
	}

	/** Calculate breathable atmosphere from life support, structural integrity, and power. */
	private calculateSectionAtmosphere(section: Section): number {
		const lifeSupport = this.systems.get("life-support");
		if (!lifeSupport) return 0;

		const lsEffectiveness = lifeSupport.condition * (lifeSupport.powered ? 1.0 : 0.0);
		return lsEffectiveness * section.structuralIntegrity * section.powerLevel;
	}

	// ─── Repairs ─────────────────────────────────────────────────────────────

	/**
	 * Attempt to repair a subsystem. Returns true if repair succeeded.
	 * Caller is responsible for checking/consuming resources.
	 */
	repairSubsystem(subsystemId: string): { success: boolean; conditionRestored: number } {
		const sub = this.subsystems.get(subsystemId);
		if (!sub) return { success: false, conditionRestored: 0 };
		if (sub.condition >= 1.0) return { success: false, conditionRestored: 0 };

		const config = SHIP_STATE_CONFIG;
		const amount = config.BASE_REPAIR_AMOUNT * config.REPAIR_SKILL_MODIFIER;
		const oldCondition = sub.condition;
		sub.condition = Math.min(1.0, sub.condition + amount);
		const restored = sub.condition - oldCondition;

		// Recalculate power after repair (conduit repair affects power routing)
		this.distributePower();

		this.bus.emit("ship:subsystem:repaired", {
			subsystemId,
			condition: sub.condition
		});

		return { success: true, conditionRestored: restored };
	}

	// ─── Degradation ─────────────────────────────────────────────────────────

	/** Apply time-based degradation to all subsystems. Call once per game-minute. */
	applyDegradation(gameHoursElapsed: number): void {
		const config = SHIP_STATE_CONFIG;
		let anyChanged = false;

		for (const sub of this.subsystems.values()) {
			if (sub.condition <= 0) continue;

			const rate = config.BASE_DEGRADATION * (1 + config.DAMAGE_ACCELERATION * (1 - sub.condition));
			const loss = rate * gameHoursElapsed;
			const oldCondition = sub.condition;
			sub.condition = Math.max(0, sub.condition - loss);

			if (oldCondition !== sub.condition) {
				anyChanged = true;
				if (sub.condition === 0) {
					this.bus.emit("ship:subsystem:damaged", { subsystemId: sub.id, condition: 0 });
				}
			}
		}

		if (anyChanged) {
			this.distributePower();

			// Check life support critical threshold
			const lifeSupport = this.systems.get("life-support");
			if (lifeSupport && lifeSupport.condition < config.LIFE_SUPPORT_CRITICAL_THRESHOLD) {
				this.bus.emit("ship:lifesupport:critical", { level: lifeSupport.condition });
			}
		}
	}

	// ─── Narrative Override ──────────────────────────────────────────────────

	/** Set a system's condition directly (for episode events like attacks). */
	setSystemCondition(systemId: ShipSystemId, condition: number): void {
		const sys = this.systems.get(systemId);
		if (!sys) return;

		sys.condition = Math.max(0, Math.min(1, condition));
		this.distributePower();
		this.bus.emit("ship:system:condition-changed", { systemId, condition: sys.condition });
	}

	/** Set a subsystem's condition directly. */
	setSubsystemCondition(subsystemId: string, condition: number): void {
		const sub = this.subsystems.get(subsystemId);
		if (!sub) return;

		const oldCondition = sub.condition;
		sub.condition = Math.max(0, Math.min(1, condition));
		this.distributePower();

		if (sub.condition > oldCondition) {
			this.bus.emit("ship:subsystem:repaired", { subsystemId, condition: sub.condition });
		} else if (sub.condition < oldCondition) {
			this.bus.emit("ship:subsystem:damaged", { subsystemId, condition: sub.condition });
		}
	}

	// ─── Serialization (ISaveableSystem) ─────────────────────────────────────

	readonly saveId = "ship-state";

	serialize(): ShipStateSnapshot {
		return {
			version: 1,
			systems: [...this.systems.values()].map(s => ({ ...s })),
			sections: [...this.sections.values()].map(s => ({ ...s, subsystems: [...s.subsystems] })),
			subsystems: [...this.subsystems.values()].map(s => ({ ...s })),
		};
	}

	deserialize(data: ShipStateSnapshot): void {
		this.systems.clear();
		this.sections.clear();
		this.subsystems.clear();

		for (const sys of data.systems) {
			this.systems.set(sys.id, { ...sys });
		}
		for (const section of data.sections) {
			this.sections.set(section.id, { ...section, subsystems: [...section.subsystems] });
		}
		for (const sub of data.subsystems) {
			this.subsystems.set(sub.id, { ...sub });
		}

		this.distributePower();
	}

	// ─── Lifecycle ───────────────────────────────────────────────────────────

	/** Subscribe to player section entry events. */
	init(): void {
		this.bus.on("player:entered:section", ({ sectionId }) => {
			this.discoverSection(sectionId);
		});
	}

	dispose(): void {
		this.bus.cleanup();
	}
}
