/**
 * Crew Character Manifest — defines the character roster, their VRM assets,
 * and spawning configuration.
 *
 * Each character in the SGU crew has a manifest entry that maps their ID
 * to a VRM model, default animation bundle, expression profile, and
 * spring bone LOD overrides. The manifest is loaded from a JSON config
 * and drives the `addCharacter()` calls in the VRM Character Manager.
 *
 * @see design/gdd/vrm-model-integration.md §Detailed Rules > Crew NPC Models
 */

// ─── Types ──────────────────────────────────────────────────────────────────

export type CrewCharacterManifest = {
	readonly id: string;
	readonly displayName: string;
	readonly vrmAsset: string;
	readonly isPlayer?: boolean;
	readonly animationBundleId?: string;
	readonly expressionProfile?: CrewExpressionProfile;
	readonly springBoneProfile?: SpringBoneProfile;
};

export type CrewExpressionProfile = {
	/** Default idle expression (e.g., "neutral", "relaxed", "angry" for Rush). */
	readonly defaultExpression?: string;
	/** Expression intensity multiplier (0-1). Stoic characters use lower values. */
	readonly expressionIntensity?: number;
	/** Custom expression map overrides for dialogue. */
	readonly customExpressions?: Record<string, string>;
};

export type SpringBoneProfile = {
	/** Override stiffness for this character's spring bones. */
	readonly stiffnessOverride?: number;
	/** Override damping for this character's spring bones. */
	readonly dampingOverride?: number;
};

// ─── Default Crew Roster ────────────────────────────────────────────────────

/**
 * The default SGU crew roster.
 * Asset paths are relative to the assets directory.
 * VRM files must be placed in `assets/characters/<id>/`.
 */
export const DEFAULT_CREW_ROSTER: readonly CrewCharacterManifest[] = [
	{
		id: "eli-wallace",
		displayName: "Eli Wallace",
		vrmAsset: "/assets/characters/eli-wallace/eli-wallace.vrm",
		isPlayer: true,
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.9,
		},
	},
	{
		id: "nicholas-rush",
		displayName: "Dr. Nicholas Rush",
		vrmAsset: "/assets/characters/nicholas-rush/nicholas-rush.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.6, // Guarded, intense
		},
	},
	{
		id: "everett-young",
		displayName: "Colonel Everett Young",
		vrmAsset: "/assets/characters/everett-young/everett-young.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.5, // Military bearing, controlled
		},
	},
	{
		id: "chloe-armstrong",
		displayName: "Chloe Armstrong",
		vrmAsset: "/assets/characters/chloe-armstrong/chloe-armstrong.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.85, // Expressive, emotional
		},
	},
	{
		id: "matthew-scott",
		displayName: "Lt. Matthew Scott",
		vrmAsset: "/assets/characters/matthew-scott/matthew-scott.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.7,
		},
	},
	{
		id: "ronald-greer",
		displayName: "MSgt. Ronald Greer",
		vrmAsset: "/assets/characters/ronald-greer/ronald-greer.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.5, // Tough exterior
		},
	},
	{
		id: "tamara-johansen",
		displayName: "TJ (Tamara Johansen)",
		vrmAsset: "/assets/characters/tamara-johansen/tamara-johansen.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.75, // Warm but professional
		},
	},
	{
		id: "camile-wray",
		displayName: "Camile Wray",
		vrmAsset: "/assets/characters/camile-wray/camile-wray.vrm",
		expressionProfile: {
			defaultExpression: "neutral",
			expressionIntensity: 0.7,
		},
	},
];

// ─── Manifest Registry ──────────────────────────────────────────────────────

let roster: CrewCharacterManifest[] = [...DEFAULT_CREW_ROSTER];

/**
 * Load a custom crew roster from a JSON file. Falls back to defaults on failure.
 */
export async function loadCrewRoster(
	url = "/assets/config/crew-roster.json"
): Promise<readonly CrewCharacterManifest[]> {
	try {
		const response = await fetch(url);

		if (!response.ok) {
				console.info(`[CrewManifest] Failed to load roster from ${url} (${response.status}). Using defaults.`);
			return roster;
		}

		const raw: unknown = await response.json();

		if (!Array.isArray(raw)) {
				console.info("[CrewManifest] Roster JSON is not an array. Using defaults.");
			return roster;
		}

		roster = raw.map(parseManifestEntry).filter(
			(entry): entry is CrewCharacterManifest => entry !== null
		);

		console.info(`[CrewManifest] Loaded ${roster.length} crew members from ${url}`);
		return roster;
	} catch (error) {
		console.error("[CrewManifest] Error loading roster. Using defaults.", error);
		return roster;
	}
}

/**
 * Get the current crew roster.
 */
export function getCrewRoster(): readonly CrewCharacterManifest[] {
	return roster;
}

/**
 * Get a specific crew member's manifest by ID.
 */
export function getCrewManifest(id: string): CrewCharacterManifest | undefined {
	return roster.find((entry) => entry.id === id);
}

/**
 * Get the player character manifest.
 */
export function getPlayerManifest(): CrewCharacterManifest | undefined {
	return roster.find((entry) => entry.isPlayer);
}

/**
 * Get all non-player crew manifests.
 */
export function getNpcManifests(): readonly CrewCharacterManifest[] {
	return roster.filter((entry) => !entry.isPlayer);
}

// ─── Parsing ────────────────────────────────────────────────────────────────

function parseManifestEntry(raw: unknown): CrewCharacterManifest | null {
	if (typeof raw !== "object" || raw === null) return null;

	const obj = raw as Record<string, unknown>;

	if (typeof obj["id"] !== "string" || typeof obj["vrmAsset"] !== "string") {
		return null;
	}

	return {
		id: obj["id"],
		displayName: typeof obj["displayName"] === "string" ? obj["displayName"] : obj["id"],
		vrmAsset: obj["vrmAsset"],
		isPlayer: obj["isPlayer"] === true,
		animationBundleId: typeof obj["animationBundleId"] === "string"
			? obj["animationBundleId"]
			: undefined,
		expressionProfile: parseExpressionProfile(obj["expressionProfile"]),
		springBoneProfile: parseSpringBoneProfile(obj["springBoneProfile"]),
	};
}

function parseExpressionProfile(raw: unknown): CrewExpressionProfile | undefined {
	if (typeof raw !== "object" || raw === null) return undefined;

	const obj = raw as Record<string, unknown>;

	return {
		defaultExpression: typeof obj["defaultExpression"] === "string"
			? obj["defaultExpression"]
			: undefined,
		expressionIntensity: typeof obj["expressionIntensity"] === "number"
			? obj["expressionIntensity"]
			: undefined,
		customExpressions: typeof obj["customExpressions"] === "object" && obj["customExpressions"] !== null
			? obj["customExpressions"] as Record<string, string>
			: undefined,
	};
}

function parseSpringBoneProfile(raw: unknown): SpringBoneProfile | undefined {
	if (typeof raw !== "object" || raw === null) return undefined;

	const obj = raw as Record<string, unknown>;

	return {
		stiffnessOverride: typeof obj["stiffnessOverride"] === "number"
			? obj["stiffnessOverride"]
			: undefined,
		dampingOverride: typeof obj["dampingOverride"] === "number"
			? obj["dampingOverride"]
			: undefined,
	};
}
