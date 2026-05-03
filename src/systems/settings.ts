import { AudioManager } from "./audio";
import { setFullscreenBehaviorEnabled } from "./fullscreen";

const SETTINGS_KEY = "sgu:settings";

export type GameSettings = {
	readonly effectsVolume: number;
	readonly fullscreen: boolean;
	readonly masterVolume: number;
	readonly musicVolume: number;
};

export const DEFAULT_GAME_SETTINGS: GameSettings = {
	effectsVolume: 0.85,
	fullscreen: true,
	masterVolume: 1,
	musicVolume: 0.8,
};

export function readGameSettings(): GameSettings {
	try {
		const raw = localStorage.getItem(SETTINGS_KEY);
		if (!raw) return DEFAULT_GAME_SETTINGS;
		return normalizeSettings(JSON.parse(raw) as Partial<GameSettings>);
	} catch {
		return DEFAULT_GAME_SETTINGS;
	}
}

export function writeGameSettings(settings: GameSettings): void {
	const normalized = normalizeSettings(settings);
	try {
		localStorage.setItem(SETTINGS_KEY, JSON.stringify(normalized));
	} catch {
		// Settings are optional; failures should not block the menu.
	}
	applyGameSettings(normalized);
}

export function applyGameSettings(settings: GameSettings): void {
	const audio = AudioManager.getInstance();
	audio.setMasterVolume(settings.masterVolume);
	audio.setCategoryVolume("ambient", settings.musicVolume);
	audio.setCategoryVolume("music", settings.musicVolume);
	audio.setCategoryVolume("sfx", settings.effectsVolume);
	audio.setCategoryVolume("ui", settings.effectsVolume);
	setFullscreenBehaviorEnabled(settings.fullscreen);
}

function normalizeSettings(settings: Partial<GameSettings>): GameSettings {
	return {
		effectsVolume: clampSetting(settings.effectsVolume, DEFAULT_GAME_SETTINGS.effectsVolume),
		fullscreen: settings.fullscreen ?? DEFAULT_GAME_SETTINGS.fullscreen,
		masterVolume: clampSetting(settings.masterVolume, DEFAULT_GAME_SETTINGS.masterVolume),
		musicVolume: clampSetting(settings.musicVolume, DEFAULT_GAME_SETTINGS.musicVolume),
	};
}

function clampSetting(value: unknown, fallback: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.max(0, Math.min(1, value));
}
