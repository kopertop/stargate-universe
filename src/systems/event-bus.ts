/**
 * Event Bus — Centralized pub/sub for all game system communication.
 *
 * Uses mitt under the hood with added error isolation, re-entry protection,
 * and a scopedBus helper for automatic cleanup on scene unload.
 *
 * @see design/gdd/event-bus.md
 */
import mitt, { type Handler, type WildcardHandler } from "mitt";

// ─── Game Event Types ────────────────────────────────────────────────────────

/** Ship State events */
type ShipEvents = {
	"ship:power:changed": { sectionId?: string };
	"ship:system:condition-changed": { systemId: string; condition: number };
	"ship:section:unlocked": { sectionId: string };
	"ship:section:discovered": { sectionId: string };
	"ship:lifesupport:critical": { level: number };
	"ship:subsystem:repaired": { subsystemId: string; condition: number };
	"ship:subsystem:damaged": { subsystemId: string; condition: number };
};

/** Gate & Planet events */
type GateEvents = {
	"gate:dial:started": { planetId: string };
	"gate:activated": { planetId: string };
	"gate:closed": Record<string, never>;
};

/** Resource events */
type ResourceEvents = {
	"resource:collected": { type: string; amount: number; source: string };
	"resource:consumed": { type: string; amount: number; consumer: string };
	"resource:depleted": { type: string };
	"inventory:story-item:acquired": { itemId: string; itemName: string };
};

/** Quest events */
type QuestEvents = {
	"quest:started": { questId: string };
	"quest:objective-complete": { questId: string; objectiveId: string };
	"quest:completed": { questId: string };
	"quest:failed": { questId: string };
};

/** Crew & Dialogue events */
type CrewEvents = {
	"crew:dialogue:started": { speakerId: string; dialogueId: string };
	"crew:dialogue:node": {
		speakerId: string;
		dialogueId: string;
		nodeId: string;
		/** Displayed speaker name (e.g. "Dr. Nicholas Rush") */
		speaker: string;
		/** The line of dialogue spoken by the NPC */
		text: string;
		/** Player-selectable response options for this node */
		options: ReadonlyArray<{ id: string; label: string }>;
	};
	"crew:dialogue:ended": { speakerId: string; dialogueId: string };
	"crew:choice:made": { dialogueId: string; nodeId: string; responseId: string };
	"crew:morale:changed": { morale: number };
	"crew:relationship:changed": { characterId: string; affinity: number };
	"crew:romance:changed": { characterId: string; level: number };
};

/** Timer events */
type TimerEvents = {
	"timer:created": { id: string; tags: string[] };
	"timer:halted": { id: string };
	"timer:resumed": { id: string };
	"timer:cancelled": { id: string; remaining: number; tags: string[] };
	"timer:planet:warning": { remaining: number };
	"timer:planet:expired": Record<string, never>;
	"timer:ftl:ready": Record<string, never>;
	"timer:timescale:set": { scale: number };
};

/** Player events */
type PlayerEvents = {
	"player:interact": { targetId: string; action: string };
	"player:entered:section": { sectionId: string };
	"player:kino:deployed": Record<string, never>;
	/** Fired by the UI when the player picks a dialogue response option. */
	"player:dialogue:choice": { responseId: string };
};

/** Episode events */
type EpisodeEvents = {
	"episode:started": { episodeId: string };
	"episode:crisis:triggered": { crisisId: string };
	"episode:completed": { episodeId: string };
};

/** Planet events */
type PlanetEvents = {
	"planet:entered": { planetId: string };
	"planet:returned": { planetId: string; timeRemaining: number };
	"planet:resource:gathered": { type: string; amount: number };
	"planet:poi:discovered": { poiId: string };
};

/** Character model events */
type CharacterEvents = {
	"character:model:loaded": { characterId: string };
	"character:model:failed": { characterId: string; error: string };
	"character:expression:changed": { characterId: string; expression: string; weight: number };
	"character:customization:applied": { characterId: string };
	"character:customization:saved": { characterId: string };
	"character:gear:equipped": { characterId: string; slotId: string };
	"character:gear:unequipped": { characterId: string; slotId: string };
};

/** Game lifecycle events */
type GameEvents = {
	"game:paused": Record<string, never>;
	"game:resumed": Record<string, never>;
};

/** Save / Load events */
type SaveEvents = {
	"save:completed": { slotId: string };
	"save:loaded": { slotId: string };
	"save:failed": { slotId: string; error: string };
};

/** All events combined — the master type map for mitt */
export type GameEventMap =
	ShipEvents &
	GateEvents &
	ResourceEvents &
	CrewEvents &
	QuestEvents &
	CharacterEvents &
	TimerEvents &
	PlayerEvents &
	EpisodeEvents &
	PlanetEvents &
	GameEvents &
	SaveEvents;

/** Event name union type */
export type GameEventName = keyof GameEventMap;

// ─── Event Bus Implementation ────────────────────────────────────────────────

const MAX_REENTRY_DEPTH = 8;

const emitter = mitt<GameEventMap>();
let reentryDepth = 0;

/**
 * Publish a typed event to all subscribers.
 * Wraps each handler in try/catch for error isolation.
 * Prevents circular event chains via re-entry depth limit.
 */
export function emit<K extends GameEventName>(event: K, payload: GameEventMap[K]): void {
	reentryDepth++;

	if (reentryDepth > MAX_REENTRY_DEPTH) {
		console.error(
			`[EventBus] Max re-entry depth (${MAX_REENTRY_DEPTH}) exceeded for "${event}". ` +
			`Likely circular event chain. Event dropped.`
		);
		reentryDepth--;
		return;
	}

	// mitt's emit is synchronous — handlers run immediately
	// We wrap in try/catch at the mitt handler level via safeOn
	emitter.emit(event, payload);
	reentryDepth--;
}

/**
 * Subscribe to a typed event with error isolation.
 * Returns an unsubscribe function.
 */
export function on<K extends GameEventName>(
	event: K,
	handler: Handler<GameEventMap[K]>
): () => void {
	const safeHandler: Handler<GameEventMap[K]> = (payload) => {
		try {
			handler(payload);
		} catch (error) {
			console.error(`[EventBus] Handler error for "${event}":`, error instanceof Error ? error.message : String(error));
		}
	};

	emitter.on(event, safeHandler);
	return () => emitter.off(event, safeHandler);
}

/**
 * Subscribe to ALL events (wildcard). Useful for debugging and Save/Load.
 * Returns an unsubscribe function.
 */
export function onAny(
	handler: (event: GameEventName, payload: unknown) => void
): () => void {
	const safeHandler: WildcardHandler<GameEventMap> = (event, payload) => {
		try {
			handler(event as GameEventName, payload);
		} catch (error) {
			console.error(`[EventBus] Wildcard handler error for "${String(event)}":`, error);
		}
	};

	emitter.on("*", safeHandler);
	return () => emitter.off("*", safeHandler);
}

/**
 * Create a scoped bus that tracks all subscriptions and unsubscribes them
 * all at once when cleanup is called. Tied to ggez scene dispose lifecycle.
 *
 * Usage:
 * ```ts
 * const bus = scopedBus();
 * bus.on("ship:power:changed", handlePowerChange);
 * bus.on("resource:collected", handleCollection);
 * // Later, on scene unload:
 * bus.cleanup(); // removes all subscriptions
 * ```
 */
export function scopedBus() {
	const unsubscribers: Array<() => void> = [];

	return {
		on<K extends GameEventName>(event: K, handler: Handler<GameEventMap[K]>): () => void {
			const unsub = on(event, handler);
			unsubscribers.push(unsub);
			return unsub;
		},

		onAny(handler: (event: GameEventName, payload: unknown) => void): void {
			unsubscribers.push(onAny(handler));
		},

		emit,

		cleanup(): void {
			for (const unsub of unsubscribers) {
				unsub();
			}
			unsubscribers.length = 0;
		}
	};
}

/** Get the current re-entry depth (for testing) */
export function getReentryDepth(): number {
	return reentryDepth;
}
