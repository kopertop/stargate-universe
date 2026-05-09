import { emit, type GameEventName } from "./event-bus";

export type TimerState = "running" | "halted" | "expired" | "cancelled";

export type TimerWarningEvent = "timer:planet:warning";

export interface TimerWarningConfig {
	thresholdSeconds: number;
	event: TimerWarningEvent;
	payload?: Record<string, unknown>;
}

export interface TimerWarningSnapshot extends TimerWarningConfig {
	fired: boolean;
}

export interface TimerConfig {
	id: string;
	durationSeconds: number;
	tags?: string[];
	visible?: boolean;
	autoStart?: boolean;
	completionEvent?: GameEventName;
	completionPayload?: Record<string, unknown>;
	warnings?: TimerWarningConfig[];
}

export interface TimerSnapshot {
	id: string;
	durationSeconds: number;
	remainingSeconds: number;
	state: TimerState;
	tags: string[];
	visible: boolean;
	completionEvent?: GameEventName;
	completionPayload?: Record<string, unknown>;
	warnings: TimerWarningSnapshot[];
}

export interface TimerSystemSnapshot {
	version: 1;
	timers: TimerSnapshot[];
}

export interface TimerSystem {
	createTimer: (config: TimerConfig) => TimerSnapshot;
	tick: (deltaSeconds: number) => void;
	haltTimer: (id: string) => TimerSnapshot | undefined;
	resumeTimer: (id: string) => TimerSnapshot | undefined;
	cancelTimer: (id: string) => TimerSnapshot | undefined;
	getTimer: (id: string) => TimerSnapshot | undefined;
	getActiveTimers: () => TimerSnapshot[];
	serialize: () => TimerSystemSnapshot;
	deserialize: (snapshot?: TimerSystemSnapshot) => void;
	clear: () => void;
}

type TimerRuntime = Omit<TimerSnapshot, "warnings"> & {
	warnings: TimerWarningSnapshot[];
};

const toSnapshot = (timer: TimerRuntime): TimerSnapshot => ({
	id: timer.id,
	durationSeconds: timer.durationSeconds,
	remainingSeconds: timer.remainingSeconds,
	state: timer.state,
	tags: [...timer.tags],
	visible: timer.visible,
	completionEvent: timer.completionEvent,
	completionPayload: timer.completionPayload ? { ...timer.completionPayload } : undefined,
	warnings: timer.warnings.map((warning) => ({
		thresholdSeconds: warning.thresholdSeconds,
		event: warning.event,
		payload: warning.payload ? { ...warning.payload } : undefined,
		fired: warning.fired,
	})),
});

const emitDynamic = (event: GameEventName, payload: unknown): void => {
	(emit as (event: GameEventName, payload: unknown) => void)(event, payload);
};

const createRuntime = (config: TimerConfig): TimerRuntime => ({
	id: config.id,
	durationSeconds: Math.max(0, config.durationSeconds),
	remainingSeconds: Math.max(0, config.durationSeconds),
	state: config.autoStart === false ? "halted" : "running",
	tags: [...(config.tags ?? [])],
	visible: config.visible ?? false,
	completionEvent: config.completionEvent,
	completionPayload: config.completionPayload ? { ...config.completionPayload } : undefined,
	warnings: (config.warnings ?? [])
		.map((warning) => ({
			thresholdSeconds: Math.max(0, warning.thresholdSeconds),
			event: warning.event,
			payload: warning.payload ? { ...warning.payload } : undefined,
			fired: false,
		}))
		.sort((a, b) => b.thresholdSeconds - a.thresholdSeconds),
});

const restoreRuntime = (snapshot: TimerSnapshot): TimerRuntime => ({
	id: snapshot.id,
	durationSeconds: Math.max(0, snapshot.durationSeconds),
	remainingSeconds: Math.max(0, snapshot.remainingSeconds),
	state: snapshot.state,
	tags: [...snapshot.tags],
	visible: snapshot.visible,
	completionEvent: snapshot.completionEvent,
	completionPayload: snapshot.completionPayload ? { ...snapshot.completionPayload } : undefined,
	warnings: snapshot.warnings.map((warning) => ({
		thresholdSeconds: Math.max(0, warning.thresholdSeconds),
		event: warning.event,
		payload: warning.payload ? { ...warning.payload } : undefined,
		fired: warning.fired,
	})),
});

export const createTimerSystem = (): TimerSystem => {
	const timers = new Map<string, TimerRuntime>();

	const createTimer = (config: TimerConfig): TimerSnapshot => {
		const timer = createRuntime(config);
		timers.set(timer.id, timer);
		emit("timer:created", { id: timer.id, tags: [...timer.tags] });
		return toSnapshot(timer);
	};

	const tick = (deltaSeconds: number): void => {
		if (deltaSeconds <= 0) return;

		for (const timer of timers.values()) {
			if (timer.state !== "running") continue;

			timer.remainingSeconds = Math.max(0, timer.remainingSeconds - deltaSeconds);

			for (const warning of timer.warnings) {
				if (warning.fired || timer.remainingSeconds > warning.thresholdSeconds) continue;
				warning.fired = true;
				emit(warning.event, {
					remaining: timer.remainingSeconds,
					...(warning.payload ?? {}),
				});
			}

			if (timer.remainingSeconds > 0) continue;

			timer.state = "expired";
			if (timer.completionEvent) {
				emitDynamic(timer.completionEvent, timer.completionPayload ?? {});
			}
		}
	};

	const haltTimer = (id: string): TimerSnapshot | undefined => {
		const timer = timers.get(id);
		if (!timer || timer.state !== "running") return timer ? toSnapshot(timer) : undefined;
		timer.state = "halted";
		emit("timer:halted", { id });
		return toSnapshot(timer);
	};

	const resumeTimer = (id: string): TimerSnapshot | undefined => {
		const timer = timers.get(id);
		if (!timer || timer.state !== "halted") return timer ? toSnapshot(timer) : undefined;
		timer.state = "running";
		emit("timer:resumed", { id });
		return toSnapshot(timer);
	};

	const cancelTimer = (id: string): TimerSnapshot | undefined => {
		const timer = timers.get(id);
		if (!timer) return undefined;
		timer.state = "cancelled";
		emit("timer:cancelled", {
			id,
			remaining: timer.remainingSeconds,
			tags: [...timer.tags],
		});
		return toSnapshot(timer);
	};

	const getTimer = (id: string): TimerSnapshot | undefined => {
		const timer = timers.get(id);
		return timer ? toSnapshot(timer) : undefined;
	};

	const getActiveTimers = (): TimerSnapshot[] =>
		[...timers.values()]
			.filter((timer) => timer.state === "running" || timer.state === "halted")
			.map(toSnapshot);

	const serialize = (): TimerSystemSnapshot => ({
		version: 1,
		timers: [...timers.values()].map(toSnapshot),
	});

	const deserialize = (snapshot?: TimerSystemSnapshot): void => {
		timers.clear();
		if (!snapshot) return;
		for (const timer of snapshot.timers) {
			timers.set(timer.id, restoreRuntime(timer));
		}
	};

	const clear = (): void => {
		timers.clear();
	};

	return {
		createTimer,
		tick,
		haltTimer,
		resumeTimer,
		cancelTimer,
		getTimer,
		getActiveTimers,
		serialize,
		deserialize,
		clear,
	};
};
