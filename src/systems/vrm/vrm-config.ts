/**
 * VRM Character Model Configuration — runtime-loaded tuning knobs.
 *
 * All values are externalized in `assets/config/vrm-config.json` and can
 * be hot-reloaded during development. No gameplay values are hardcoded.
 *
 * @see design/gdd/vrm-model-integration.md §Tuning Knobs
 */

// ─── Config Shape ───────────────────────────────────────────────────────────

export type VrmSpringBoneConfig = {
	readonly enabled: boolean;
	readonly stiffnessMultiplier: number;
	readonly dampingMultiplier: number;
	readonly budgetMs: number;
	readonly maxDeltaSeconds: number;
};

export type VrmExpressionConfig = {
	readonly blendSpeed: number;
	readonly visemeBlendSpeed: number;
	readonly blinkBaseInterval: number;
	readonly blinkVariance: number;
	readonly blinkDuration: number;
};

export type VrmLodConfig = {
	readonly nearDistance: number;
	readonly midDistance: number;
	readonly transitionDuration: number;
};

export type VrmLoadingConfig = {
	readonly maxConcurrentLoads: number;
	readonly retryDelayMs: number;
	readonly maxRetries: number;
};

export type VrmFirstPersonConfig = {
	readonly headFadeTransition: number;
};

export type VrmQualityConfig = {
	readonly adaptiveThresholdFps: number;
	readonly meshTriangleBudget: number;
};

export type VrmConfig = {
	readonly maxVisibleCrew: number;
	readonly springBone: VrmSpringBoneConfig;
	readonly expression: VrmExpressionConfig;
	readonly lod: VrmLodConfig;
	readonly loading: VrmLoadingConfig;
	readonly firstPerson: VrmFirstPersonConfig;
	readonly quality: VrmQualityConfig;
};

// ─── Defaults ───────────────────────────────────────────────────────────────

const DEFAULT_CONFIG: VrmConfig = {
	maxVisibleCrew: 4,
	springBone: {
		enabled: true,
		stiffnessMultiplier: 1.0,
		dampingMultiplier: 0.4,
		budgetMs: 1.0,
		maxDeltaSeconds: 0.033,
	},
	expression: {
		blendSpeed: 0.3,
		visemeBlendSpeed: 0.08,
		blinkBaseInterval: 4.0,
		blinkVariance: 2.0,
		blinkDuration: 0.15,
	},
	lod: {
		nearDistance: 5.0,
		midDistance: 15.0,
		transitionDuration: 0.5,
	},
	loading: {
		maxConcurrentLoads: 2,
		retryDelayMs: 2000,
		maxRetries: 1,
	},
	firstPerson: {
		headFadeTransition: 0.15,
	},
	quality: {
		adaptiveThresholdFps: 30.0,
		meshTriangleBudget: 15000,
	},
};

// ─── Singleton ──────────────────────────────────────────────────────────────

let activeConfig: VrmConfig = DEFAULT_CONFIG;

/**
 * Load VRM config from the JSON file. Falls back to defaults on failure.
 */
export async function loadVrmConfig(url = "/assets/config/vrm-config.json"): Promise<VrmConfig> {
	try {
		const response = await fetch(url);

		if (!response.ok) {
			console.info(`[VrmConfig] Failed to load config from ${url} (${response.status}). Using defaults.`);
			return activeConfig;
		}

		const raw: unknown = await response.json();
		activeConfig = mergeWithDefaults(raw);
		return activeConfig;
	} catch (error) {
		console.warn("[VrmConfig] Error loading config. Using defaults.", error);
		return activeConfig;
	}
}

/** Get the current config (synchronous, returns cached value). */
export function getVrmConfig(): VrmConfig {
	return activeConfig;
}

// ─── Merge Helper ───────────────────────────────────────────────────────────

function mergeWithDefaults(raw: unknown): VrmConfig {
	if (typeof raw !== "object" || raw === null) {
		return DEFAULT_CONFIG;
	}

	const obj = raw as Record<string, unknown>;

	return {
		maxVisibleCrew: asNumber(obj["maxVisibleCrew"], DEFAULT_CONFIG.maxVisibleCrew),
		springBone: mergeSection(obj["springBone"], DEFAULT_CONFIG.springBone),
		expression: mergeSection(obj["expression"], DEFAULT_CONFIG.expression),
		lod: mergeSection(obj["lod"], DEFAULT_CONFIG.lod),
		loading: mergeSection(obj["loading"], DEFAULT_CONFIG.loading),
		firstPerson: mergeSection(obj["firstPerson"], DEFAULT_CONFIG.firstPerson),
		quality: mergeSection(obj["quality"], DEFAULT_CONFIG.quality),
	};
}

function mergeSection<T extends Record<string, unknown>>(raw: unknown, defaults: T): T {
	if (typeof raw !== "object" || raw === null) {
		return defaults;
	}

	const obj = raw as Record<string, unknown>;
	const result = { ...defaults };

	for (const key of Object.keys(defaults)) {
		const defaultVal = defaults[key];

		if (typeof defaultVal === "number") {
			(result as Record<string, unknown>)[key] = asNumber(obj[key], defaultVal);
		} else if (typeof defaultVal === "boolean") {
			(result as Record<string, unknown>)[key] = asBoolean(obj[key], defaultVal);
		}
	}

	return result;
}

function asNumber(value: unknown, fallback: number): number {
	return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asBoolean(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}
