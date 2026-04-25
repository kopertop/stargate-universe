/**
 * Sound Catalog — registry of all game sounds with metadata.
 *
 * Sound files are stored on R2 and resolved via the asset resolver.
 * This catalog maps sound IDs to their R2 paths and playback settings.
 *
 * Sources:
 * - SFX/UI: soundcn CC0 library + ElevenLabs Sound Effects API
 * - Ambient: ElevenLabs Music API (planet beds) + soundcn (ship sounds)
 * - Music: ported from sibling repo `stargate-evolution/apps/game/public/sounds/`
 *          (sgu-theme-song, sgu-soundtrack) — uploaded to R2 bucket `sgu-assets`
 *          under `/audio/music/`.
 * - Voice: ElevenLabs TTS (multilingual v2 model)
 *
 * R2 layout (bucket: sgu-assets):
 *   /audio/sfx/         one-shot SFX (chevron-lock, stargate-kawoosh, etc.)
 *   /audio/ambient/     looping ambient beds (ship hums, planet beds)
 *   /audio/music/       score cues & theme
 *   /audio/ui/          interface clicks/hovers/navigation
 *   /audio/voice/       TTS-generated character VO
 *
 * Voice cast:
 * - Eli Wallace: "Will" voice (young, american, chill)
 * - Ship AI (Destiny): "Alice" voice (clear, british, professional)
 * - Colonel Young: "Brian" voice (deep, resonant, american)
 * - Dr. Rush: "George" voice (warm, british, mature)
 * - Chloe Armstrong: "Jessica" voice (playful, bright, young)
 * - TJ Johansen: "Lily" voice (confident, british)
 * - Sgt. Greer: "Harry" voice (fierce, rough)
 */

export type SoundCategory = "sfx" | "ambient" | "music" | "ui" | "voice";

export interface SoundEntry {
	/** R2 asset path (resolved via resolveAssetUrl). */
	readonly path: string;
	/** Default volume (0-1). */
	readonly volume: number;
	/** Sound category. */
	readonly category: SoundCategory;
	/** Whether this sound should loop. */
	readonly loop: boolean;
	/** Whether this is positional (3D) or global (2D). */
	readonly positional: boolean;
}

/**
 * All registered game sounds. Add new entries here when integrating sounds.
 *
 * Sound IDs use kebab-case matching the filename on R2.
 */
export const SOUND_CATALOG = {
	// ─── SFX — Ship Interaction ──────────────────────────────────────────────
	"console-activate": { path: "/audio/sfx/console-activate.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"console-beep": { path: "/audio/sfx/console-beep.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"console-hum": { path: "/audio/sfx/console-hum.mp3", volume: 0.3, category: "sfx", loop: true, positional: true },
	"data-processing": { path: "/audio/sfx/data-processing.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"data-node-open": { path: "/audio/sfx/data-node-open.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"ancient-text-reveal": { path: "/audio/sfx/ancient-text-reveal.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },

	// ─── SFX — Doors ─────────────────────────────────────────────────────────
	"door-open": { path: "/audio/sfx/door-open.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"door-close": { path: "/audio/sfx/door-close.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"heavy-door-open": { path: "/audio/sfx/heavy-door-open.mp3", volume: 0.7, category: "sfx", loop: false, positional: true },
	"stone-door-close": { path: "/audio/sfx/stone-door-close.mp3", volume: 0.7, category: "sfx", loop: false, positional: true },

	// ─── SFX — Stargate ──────────────────────────────────────────────────────
	"chevron-lock": { path: "/audio/sfx/chevron-lock.mp3", volume: 0.8, category: "sfx", loop: false, positional: true },
	"stargate-kawoosh": { path: "/audio/sfx/stargate-kawoosh.mp3", volume: 0.9, category: "sfx", loop: false, positional: true },
	"energy-burst": { path: "/audio/sfx/energy-burst.mp3", volume: 0.9, category: "sfx", loop: false, positional: true },
	"energy-charge": { path: "/audio/sfx/energy-charge.mp3", volume: 0.7, category: "sfx", loop: false, positional: true },
	"energy-zap": { path: "/audio/sfx/energy-zap.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"energy-up": { path: "/audio/sfx/energy-up.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"force-field-000": { path: "/audio/sfx/force-field-000.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"force-field-001": { path: "/audio/sfx/force-field-001.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"force-field-002": { path: "/audio/sfx/force-field-002.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"wormhole-transit": { path: "/audio/sfx/wormhole-transit.mp3", volume: 0.8, category: "sfx", loop: false, positional: false },
	"flt-jump": { path: "/audio/sfx/flt-jump.mp3", volume: 0.7, category: "sfx", loop: false, positional: false },
	"flt-exit": { path: "/audio/sfx/flt-exit.mp3", volume: 0.7, category: "sfx", loop: false, positional: false },

	// ─── SFX — Ship Systems ──────────────────────────────────────────────────
	"power-up": { path: "/audio/sfx/power-up.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"power-up-alt": { path: "/audio/sfx/power-up-alt.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"power-down": { path: "/audio/sfx/power-down.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"system-glitch": { path: "/audio/sfx/system-glitch.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"system-glitch-alt": { path: "/audio/sfx/system-glitch-alt.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"error-beep": { path: "/audio/sfx/error-beep.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"error-buzz": { path: "/audio/sfx/error-buzz.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"warning-tone": { path: "/audio/sfx/warning-tone.mp3", volume: 0.7, category: "sfx", loop: false, positional: false },
	"thruster": { path: "/audio/sfx/thruster.mp3", volume: 0.5, category: "sfx", loop: true, positional: true },
	"thruster-alt": { path: "/audio/sfx/thruster-alt.mp3", volume: 0.5, category: "sfx", loop: true, positional: true },

	// ─── SFX — Damage & Hazards ──────────────────────────────────────────────
	"explosion": { path: "/audio/sfx/explosion.mp3", volume: 0.8, category: "sfx", loop: false, positional: true },
	"low-rumble": { path: "/audio/sfx/low-rumble.mp3", volume: 0.6, category: "sfx", loop: false, positional: false },
	"low-rumble-alt": { path: "/audio/sfx/low-rumble-alt.mp3", volume: 0.6, category: "sfx", loop: false, positional: false },
	"debris-impact": { path: "/audio/sfx/debris-impact.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"hull-stress": { path: "/audio/sfx/hull-stress.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"glass-crack": { path: "/audio/sfx/glass-crack.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"glass-shatter": { path: "/audio/sfx/glass-shatter.mp3", volume: 0.7, category: "sfx", loop: false, positional: true },

	// ─── SFX — Metal Impacts ─────────────────────────────────────────────────
	"impact-metal": { path: "/audio/sfx/impact-metal.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"impact-metal-heavy": { path: "/audio/sfx/impact-metal-heavy.mp3", volume: 0.6, category: "sfx", loop: false, positional: true },
	"impact-metal-light": { path: "/audio/sfx/impact-metal-light.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"metal-click": { path: "/audio/sfx/metal-click.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },
	"metal-latch": { path: "/audio/sfx/metal-latch.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"radio-click": { path: "/audio/sfx/radio-click.mp3", volume: 0.6, category: "sfx", loop: false, positional: false },
	"repair-sparks": { path: "/audio/sfx/repair-sparks.mp3", volume: 0.6, category: "sfx", loop: true, positional: true },

	// ─── SFX — Footsteps (Metal/Ship) ────────────────────────────────────────
	"footstep-metal-000": { path: "/audio/sfx/footstep-metal-000.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-metal-001": { path: "/audio/sfx/footstep-metal-001.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-metal-002": { path: "/audio/sfx/footstep-metal-002.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-metal-003": { path: "/audio/sfx/footstep-metal-003.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-metal-004": { path: "/audio/sfx/footstep-metal-004.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },

	// ─── SFX — Footsteps (Grass/Temperate) ───────────────────────────────────
	"footstep-grass-000": { path: "/audio/sfx/footstep-grass-000.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-grass-001": { path: "/audio/sfx/footstep-grass-001.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-grass-002": { path: "/audio/sfx/footstep-grass-002.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-grass-003": { path: "/audio/sfx/footstep-grass-003.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-grass-004": { path: "/audio/sfx/footstep-grass-004.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },

	// ─── SFX — Footsteps (Snow/Ice) ──────────────────────────────────────────
	"footstep-snow-000": { path: "/audio/sfx/footstep-snow-000.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-snow-001": { path: "/audio/sfx/footstep-snow-001.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-snow-002": { path: "/audio/sfx/footstep-snow-002.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-snow-003": { path: "/audio/sfx/footstep-snow-003.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-snow-004": { path: "/audio/sfx/footstep-snow-004.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },

	// ─── SFX — Footsteps (Wood/Ruins) ────────────────────────────────────────
	"footstep-wood-000": { path: "/audio/sfx/footstep-wood-000.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-wood-001": { path: "/audio/sfx/footstep-wood-001.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-wood-002": { path: "/audio/sfx/footstep-wood-002.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-wood-003": { path: "/audio/sfx/footstep-wood-003.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },
	"footstep-wood-004": { path: "/audio/sfx/footstep-wood-004.mp3", volume: 0.3, category: "sfx", loop: false, positional: true },

	// ─── SFX — Resource Collection ───────────────────────────────────────────
	"resource-pickup": { path: "/audio/sfx/resource-pickup.mp3", volume: 0.5, category: "sfx", loop: false, positional: true },
	"resource-pickup-small": { path: "/audio/sfx/resource-pickup-small.mp3", volume: 0.4, category: "sfx", loop: false, positional: true },

	// ─── Ambient — Ship Interior ─────────────────────────────────────────────
	"ship-hum-full": { path: "/audio/ambient/ship-hum-full.mp3", volume: 0.2, category: "ambient", loop: true, positional: false },
	"ship-hum-full-alt": { path: "/audio/ambient/ship-hum-full-alt.mp3", volume: 0.2, category: "ambient", loop: true, positional: false },
	"ship-hum-low": { path: "/audio/ambient/ship-hum-low.mp3", volume: 0.15, category: "ambient", loop: true, positional: false },
	"ship-hum-low-alt": { path: "/audio/ambient/ship-hum-low-alt.mp3", volume: 0.15, category: "ambient", loop: true, positional: false },
	"ship-engine": { path: "/audio/ambient/ship-engine.mp3", volume: 0.2, category: "ambient", loop: true, positional: false },
	"ventilation-loop": { path: "/audio/ambient/ventilation-loop.mp3", volume: 0.1, category: "ambient", loop: true, positional: false },

	// ─── Ambient — Planet Environments ───────────────────────────────────────
	"planet-desert": { path: "/audio/ambient/planet-desert.mp3", volume: 0.25, category: "ambient", loop: true, positional: false },
	"planet-ice": { path: "/audio/ambient/planet-ice.mp3", volume: 0.25, category: "ambient", loop: true, positional: false },
	"planet-jungle": { path: "/audio/ambient/planet-jungle.mp3", volume: 0.25, category: "ambient", loop: true, positional: false },
	"planet-temperate": { path: "/audio/ambient/planet-temperate.mp3", volume: 0.25, category: "ambient", loop: true, positional: false },
	"planet-volcanic": { path: "/audio/ambient/planet-volcanic.mp3", volume: 0.25, category: "ambient", loop: true, positional: false },

	// ─── Music — Theme & Score ───────────────────────────────────────────────
	// Sourced from stargate-evolution project (sibling repo). Ported 2026-04-13.
	// "sgu-theme-song": DRAMATIC one-shot reserved for cinematics only —
	//                   opening cinematic + other cinematic beats.
	//                   Do NOT use on menus (too dramatic for background).
	// "sgu-soundtrack": looping background score — use for main menu,
	//                   exploration, ship-interior idle, and quiet story beats.
	"sgu-theme-song": { path: "/audio/music/sgu-theme-song.mp3", volume: 0.8, category: "music", loop: false, positional: false },
	"sgu-soundtrack": { path: "/audio/music/sgu-soundtrack.mp3", volume: 0.4, category: "music", loop: true, positional: false },

	// ─── UI — Clicks & Selection ─────────────────────────────────────────────
	"click-001": { path: "/audio/ui/click-001.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"click-002": { path: "/audio/ui/click-002.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"click-soft": { path: "/audio/ui/click-soft.mp3", volume: 0.25, category: "ui", loop: false, positional: false },
	"select": { path: "/audio/ui/select.mp3", volume: 0.35, category: "ui", loop: false, positional: false },
	"select-alt": { path: "/audio/ui/select-alt.mp3", volume: 0.35, category: "ui", loop: false, positional: false },
	"hover": { path: "/audio/ui/hover.mp3", volume: 0.2, category: "ui", loop: false, positional: false },

	// ─── UI — Navigation ─────────────────────────────────────────────────────
	"tab-switch": { path: "/audio/ui/tab-switch.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"toggle": { path: "/audio/ui/toggle.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"scroll": { path: "/audio/ui/scroll.mp3", volume: 0.2, category: "ui", loop: false, positional: false },

	// ─── UI — Kino Remote ────────────────────────────────────────────────────
	"kino-open": { path: "/audio/ui/kino-open.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"kino-close": { path: "/audio/ui/kino-close.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"menu-open": { path: "/audio/ui/menu-open.mp3", volume: 0.35, category: "ui", loop: false, positional: false },
	"menu-close": { path: "/audio/ui/menu-close.mp3", volume: 0.35, category: "ui", loop: false, positional: false },

	// ─── UI — Notifications & Feedback ───────────────────────────────────────
	"notification": { path: "/audio/ui/notification.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"confirm": { path: "/audio/ui/confirm.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"confirm-alt": { path: "/audio/ui/confirm-alt.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"discovery-chime": { path: "/audio/ui/discovery-chime.mp3", volume: 0.5, category: "ui", loop: false, positional: false },
	"discovery-jingle": { path: "/audio/ui/discovery-jingle.mp3", volume: 0.5, category: "ui", loop: false, positional: false },
	"achievement-jingle": { path: "/audio/ui/achievement-jingle.mp3", volume: 0.5, category: "ui", loop: false, positional: false },
	"ready-chime": { path: "/audio/ui/ready-chime.mp3", volume: 0.4, category: "ui", loop: false, positional: false },

	// ─── UI — Quest System ───────────────────────────────────────────────────
	"quest-activate": { path: "/audio/ui/quest-activate.mp3", volume: 0.4, category: "ui", loop: false, positional: false },
	"quest-complete": { path: "/audio/ui/quest-complete.mp3", volume: 0.5, category: "ui", loop: false, positional: false },
	"quest-update": { path: "/audio/ui/quest-update.mp3", volume: 0.35, category: "ui", loop: false, positional: false },

	// ─── UI — Relationship ───────────────────────────────────────────────────
	"relationship-positive": { path: "/audio/ui/relationship-positive.mp3", volume: 0.35, category: "ui", loop: false, positional: false },
	"relationship-negative": { path: "/audio/ui/relationship-negative.mp3", volume: 0.35, category: "ui", loop: false, positional: false },

	// ─── UI — Tonal ──────────────────────────────────────────────────────────
	"tick": { path: "/audio/ui/tick.mp3", volume: 0.2, category: "ui", loop: false, positional: false },
	"tick-alt": { path: "/audio/ui/tick-alt.mp3", volume: 0.2, category: "ui", loop: false, positional: false },
	"pluck": { path: "/audio/ui/pluck.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"pluck-alt": { path: "/audio/ui/pluck-alt.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"tone": { path: "/audio/ui/tone.mp3", volume: 0.3, category: "ui", loop: false, positional: false },
	"bong": { path: "/audio/ui/bong.mp3", volume: 0.3, category: "ui", loop: false, positional: false },

	// ─── Voice — Eli Wallace ─────────────────────────────────────────────────
	"eli-discovery-01": { path: "/audio/voice/eli-discovery-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-discovery-02": { path: "/audio/voice/eli-discovery-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-discovery-03": { path: "/audio/voice/eli-discovery-03.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-01": { path: "/audio/voice/eli-danger-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-02": { path: "/audio/voice/eli-danger-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-03": { path: "/audio/voice/eli-danger-03.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-04": { path: "/audio/voice/eli-danger-04.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-idle-01": { path: "/audio/voice/eli-idle-01.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-02": { path: "/audio/voice/eli-idle-02.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-03": { path: "/audio/voice/eli-idle-03.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-repair-01": { path: "/audio/voice/eli-repair-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-repair-02": { path: "/audio/voice/eli-repair-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-repair-03": { path: "/audio/voice/eli-repair-03.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-gate-01": { path: "/audio/voice/eli-gate-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-gate-02": { path: "/audio/voice/eli-gate-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-gate-03": { path: "/audio/voice/eli-gate-03.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-01": { path: "/audio/voice/eli-planet-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-02": { path: "/audio/voice/eli-planet-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-timer-01": { path: "/audio/voice/eli-timer-01.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-timer-02": { path: "/audio/voice/eli-timer-02.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-kino-01": { path: "/audio/voice/eli-kino-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-kino-02": { path: "/audio/voice/eli-kino-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-kino-low": { path: "/audio/voice/eli-kino-low.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-water": { path: "/audio/voice/eli-resource-water.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-minerals": { path: "/audio/voice/eli-resource-minerals.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-food": { path: "/audio/voice/eli-resource-food.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-flicker": { path: "/audio/voice/eli-ship-flicker.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-sound": { path: "/audio/voice/eli-ship-sound.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-air": { path: "/audio/voice/eli-ship-air.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-shake": { path: "/audio/voice/eli-ship-shake.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-creature-01": { path: "/audio/voice/eli-creature-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-flee-01": { path: "/audio/voice/eli-flee-01.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-safe-01": { path: "/audio/voice/eli-safe-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-puzzle-01": { path: "/audio/voice/eli-puzzle-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-puzzle-solved": { path: "/audio/voice/eli-puzzle-solved.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ftl-drop": { path: "/audio/voice/eli-ftl-drop.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-sealed-section": { path: "/audio/voice/eli-sealed-section.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-translate": { path: "/audio/voice/eli-translate.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-retreat": { path: "/audio/voice/eli-retreat.mp3", volume: 0.9, category: "voice", loop: false, positional: true },

	// ─── Voice — Ship AI (Destiny) ───────────────────────────────────────────
	"ship-warning-hull-breach": { path: "/audio/voice/ship-warning-hull-breach.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-warning-power-critical": { path: "/audio/voice/ship-warning-power-critical.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-warning-life-support": { path: "/audio/voice/ship-warning-life-support.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-ftl-countdown": { path: "/audio/voice/ship-ftl-countdown.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-ftl-exit": { path: "/audio/voice/ship-ftl-exit.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-gate-incoming": { path: "/audio/voice/ship-gate-incoming.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-gate-ready": { path: "/audio/voice/ship-gate-ready.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-gate-timer": { path: "/audio/voice/ship-gate-timer.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-gate-unstable": { path: "/audio/voice/ship-gate-unstable.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-planet-safe": { path: "/audio/voice/ship-planet-safe.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-planet-hostile": { path: "/audio/voice/ship-planet-hostile.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-power-restored": { path: "/audio/voice/ship-power-restored.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-emergency-recall": { path: "/audio/voice/ship-emergency-recall.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"ship-repair-complete": { path: "/audio/voice/ship-repair-complete.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-resource-low": { path: "/audio/voice/ship-resource-low.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-life-signs": { path: "/audio/voice/ship-life-signs.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-hostile-env": { path: "/audio/voice/ship-hostile-env.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-scan-clear": { path: "/audio/voice/ship-scan-clear.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-air-ok": { path: "/audio/voice/ship-air-ok.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-nav-update": { path: "/audio/voice/ship-nav-update.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-lockdown": { path: "/audio/voice/ship-lockdown.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-shield-damage": { path: "/audio/voice/ship-shield-damage.mp3", volume: 0.9, category: "voice", loop: false, positional: false },

	// ─── Voice — Colonel Young ───────────────────────────────────────────────
	"young-mission-brief": { path: "/audio/voice/young-mission-brief.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-order-retreat": { path: "/audio/voice/young-order-retreat.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"young-encourage": { path: "/audio/voice/young-encourage.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-hurry": { path: "/audio/voice/young-hurry.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-status-request": { path: "/audio/voice/young-status-request.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-gate-safety": { path: "/audio/voice/young-gate-safety.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-priorities": { path: "/audio/voice/young-priorities.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-suspicious": { path: "/audio/voice/young-suspicious.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-caution": { path: "/audio/voice/young-caution.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-order-secure": { path: "/audio/voice/young-order-secure.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-time-check": { path: "/audio/voice/young-time-check.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Dr. Rush ────────────────────────────────────────────────────
	"rush-discovery-01": { path: "/audio/voice/rush-discovery-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-warning-01": { path: "/audio/voice/rush-warning-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-timer-01": { path: "/audio/voice/rush-timer-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-ship-trust": { path: "/audio/voice/rush-ship-trust.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-console-01": { path: "/audio/voice/rush-console-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-power-01": { path: "/audio/voice/rush-power-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-database-01": { path: "/audio/voice/rush-database-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-ship-knows": { path: "/audio/voice/rush-ship-knows.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-busy": { path: "/audio/voice/rush-busy.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-power-readings": { path: "/audio/voice/rush-power-readings.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-passionate": { path: "/audio/voice/rush-passionate.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Chloe Armstrong ─────────────────────────────────────────────
	"chloe-caution-01": { path: "/audio/voice/chloe-caution-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-concern-01": { path: "/audio/voice/chloe-concern-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-uneasy-01": { path: "/audio/voice/chloe-uneasy-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-kino-request": { path: "/audio/voice/chloe-kino-request.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-water-clean": { path: "/audio/voice/chloe-water-clean.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-air-concern": { path: "/audio/voice/chloe-air-concern.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — TJ Johansen (Medic) ─────────────────────────────────────────
	"tj-medical-01": { path: "/audio/voice/tj-medical-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-medical-02": { path: "/audio/voice/tj-medical-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-medical-03": { path: "/audio/voice/tj-medical-03.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-concussion": { path: "/audio/voice/tj-concussion.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-status-ok": { path: "/audio/voice/tj-status-ok.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Sgt. Greer ──────────────────────────────────────────────────
	"greer-combat-01": { path: "/audio/voice/greer-combat-01.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"greer-protect-01": { path: "/audio/voice/greer-protect-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-clear-01": { path: "/audio/voice/greer-clear-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-weapons-hot": { path: "/audio/voice/greer-weapons-hot.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"greer-cover": { path: "/audio/voice/greer-cover.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-surprise": { path: "/audio/voice/greer-surprise.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-perimeter-clear": { path: "/audio/voice/greer-perimeter-clear.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Crew Generic ────────────────────────────────────────────────
	"crew-acknowledge-01": { path: "/audio/voice/crew-acknowledge-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-acknowledge-02": { path: "/audio/voice/crew-acknowledge-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-roger": { path: "/audio/voice/crew-roger.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-yes-sir": { path: "/audio/voice/crew-yes-sir.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-on-it": { path: "/audio/voice/crew-on-it.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-negative": { path: "/audio/voice/crew-negative.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"crew-help": { path: "/audio/voice/crew-help.mp3", volume: 0.9, category: "voice", loop: false, positional: true },

	// ─── Voice — Eli Wallace (Extended) ──────────────────────────────────────
	"eli-explore-dark-01": { path: "/audio/voice/eli-explore-dark-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-dark-02": { path: "/audio/voice/eli-explore-dark-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-new-room": { path: "/audio/voice/eli-explore-new-room.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-bridge": { path: "/audio/voice/eli-explore-bridge.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-observation": { path: "/audio/voice/eli-explore-observation.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-lab": { path: "/audio/voice/eli-explore-lab.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-damage": { path: "/audio/voice/eli-explore-damage.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-explore-ancient-01": { path: "/audio/voice/eli-explore-ancient-01.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-explore-ancient-02": { path: "/audio/voice/eli-explore-ancient-02.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-knowledge-01": { path: "/audio/voice/eli-knowledge-01.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-knowledge-02": { path: "/audio/voice/eli-knowledge-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-map-update": { path: "/audio/voice/eli-map-update.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-hint-interact": { path: "/audio/voice/eli-hint-interact.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-repair": { path: "/audio/voice/eli-hint-repair.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-kino": { path: "/audio/voice/eli-hint-kino.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-gate": { path: "/audio/voice/eli-hint-gate.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-timer": { path: "/audio/voice/eli-hint-timer.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-hint-resource": { path: "/audio/voice/eli-hint-resource.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-door-power": { path: "/audio/voice/eli-hint-door-power.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-door-sealed": { path: "/audio/voice/eli-hint-door-sealed.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-talk": { path: "/audio/voice/eli-hint-talk.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-talk-young": { path: "/audio/voice/eli-hint-talk-young.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-health": { path: "/audio/voice/eli-hint-health.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-oxygen": { path: "/audio/voice/eli-hint-oxygen.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-hint-kino-remote": { path: "/audio/voice/eli-hint-kino-remote.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-save-supplies": { path: "/audio/voice/eli-hint-save-supplies.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-hint-gate-return": { path: "/audio/voice/eli-hint-gate-return.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-hull": { path: "/audio/voice/eli-danger-hull.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-danger-atmosphere": { path: "/audio/voice/eli-danger-atmosphere.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-danger-toxic": { path: "/audio/voice/eli-danger-toxic.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-radiation": { path: "/audio/voice/eli-danger-radiation.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-creature-02": { path: "/audio/voice/eli-danger-creature-02.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-danger-creature-flee": { path: "/audio/voice/eli-danger-creature-flee.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-planet-hostile": { path: "/audio/voice/eli-planet-hostile.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-desert": { path: "/audio/voice/eli-planet-desert.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-ice": { path: "/audio/voice/eli-planet-ice.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-jungle": { path: "/audio/voice/eli-planet-jungle.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-volcanic": { path: "/audio/voice/eli-planet-volcanic.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-ruins": { path: "/audio/voice/eli-planet-ruins.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-gate-closing": { path: "/audio/voice/eli-gate-closing.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-gate-noreturn": { path: "/audio/voice/eli-gate-noreturn.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"eli-planet-scan": { path: "/audio/voice/eli-planet-scan.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-planet-alien-tech": { path: "/audio/voice/eli-planet-alien-tech.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-return-relief": { path: "/audio/voice/eli-return-relief.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-hum-change": { path: "/audio/voice/eli-ship-hum-change.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-ship-power-low": { path: "/audio/voice/eli-ship-power-low.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-power-restored": { path: "/audio/voice/eli-ship-power-restored.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-ship-systems-online": { path: "/audio/voice/eli-ship-systems-online.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-kino-lost": { path: "/audio/voice/eli-kino-lost.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-kino-deploy": { path: "/audio/voice/eli-kino-deploy.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-parts": { path: "/audio/voice/eli-resource-parts.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-ancient-data": { path: "/audio/voice/eli-resource-ancient-data.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-medicine": { path: "/audio/voice/eli-resource-medicine.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-lime": { path: "/audio/voice/eli-resource-lime.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-resource-full": { path: "/audio/voice/eli-resource-full.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-miss-home": { path: "/audio/voice/eli-idle-miss-home.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-games": { path: "/audio/voice/eli-idle-games.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-math": { path: "/audio/voice/eli-idle-math.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-food": { path: "/audio/voice/eli-idle-food.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-destiny": { path: "/audio/voice/eli-idle-destiny.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-ancients": { path: "/audio/voice/eli-idle-ancients.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-idle-video-log": { path: "/audio/voice/eli-idle-video-log.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-find-rush": { path: "/audio/voice/eli-find-rush.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-find-young": { path: "/audio/voice/eli-find-young.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-find-tj": { path: "/audio/voice/eli-find-tj.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-find-brody": { path: "/audio/voice/eli-find-brody.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-find-chloe": { path: "/audio/voice/eli-find-chloe.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-where-am-i": { path: "/audio/voice/eli-where-am-i.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-where-gate": { path: "/audio/voice/eli-where-gate.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-need-help": { path: "/audio/voice/eli-need-help.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-check-in": { path: "/audio/voice/eli-check-in.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-grunt-effort": { path: "/audio/voice/eli-grunt-effort.mp3", volume: 0.6, category: "voice", loop: false, positional: true },
	"eli-grunt-impact": { path: "/audio/voice/eli-grunt-impact.mp3", volume: 0.6, category: "voice", loop: false, positional: true },
	"eli-pain": { path: "/audio/voice/eli-pain.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"eli-sigh-relief": { path: "/audio/voice/eli-sigh-relief.mp3", volume: 0.5, category: "voice", loop: false, positional: true },
	"eli-shiver": { path: "/audio/voice/eli-shiver.mp3", volume: 0.5, category: "voice", loop: false, positional: true },
	"eli-muttering": { path: "/audio/voice/eli-muttering.mp3", volume: 0.6, category: "voice", loop: false, positional: true },
	"eli-thinking": { path: "/audio/voice/eli-thinking.mp3", volume: 0.5, category: "voice", loop: false, positional: true },
	"eli-center-universe": { path: "/audio/voice/eli-center-universe.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-first-contact": { path: "/audio/voice/eli-first-contact.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-alien-peaceful": { path: "/audio/voice/eli-alien-peaceful.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"eli-eloi-faith": { path: "/audio/voice/eli-eloi-faith.mp3", volume: 0.7, category: "voice", loop: false, positional: true },

	// ─── Voice — Ship AI (Extended) ──────────────────────────────────────────
	"ship-warning-radiation": { path: "/audio/voice/ship-warning-radiation.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-warning-fire": { path: "/audio/voice/ship-warning-fire.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-warning-intruder": { path: "/audio/voice/ship-warning-intruder.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-ftl-imminent": { path: "/audio/voice/ship-ftl-imminent.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"ship-ftl-five-min": { path: "/audio/voice/ship-ftl-five-min.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-ftl-one-min": { path: "/audio/voice/ship-ftl-one-min.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-gate-two-min": { path: "/audio/voice/ship-gate-two-min.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-gate-one-min": { path: "/audio/voice/ship-gate-one-min.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-gate-thirty-sec": { path: "/audio/voice/ship-gate-thirty-sec.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"ship-gate-closed": { path: "/audio/voice/ship-gate-closed.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-planet-resources": { path: "/audio/voice/ship-planet-resources.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-systems-nominal": { path: "/audio/voice/ship-systems-nominal.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-alert-incoming": { path: "/audio/voice/ship-alert-incoming.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"ship-welcome": { path: "/audio/voice/ship-welcome.mp3", volume: 0.7, category: "voice", loop: false, positional: false },
	"ship-water-low": { path: "/audio/voice/ship-water-low.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-food-low": { path: "/audio/voice/ship-food-low.mp3", volume: 0.8, category: "voice", loop: false, positional: false },
	"ship-power-restored-section": { path: "/audio/voice/ship-power-restored-section.mp3", volume: 0.7, category: "voice", loop: false, positional: false },

	// ─── Voice — Colonel Young (Extended) ────────────────────────────────────
	"young-order-hold": { path: "/audio/voice/young-order-hold.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-order-recon": { path: "/audio/voice/young-order-recon.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-order-evac": { path: "/audio/voice/young-order-evac.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"young-order-eli": { path: "/audio/voice/young-order-eli.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-assess-damage": { path: "/audio/voice/young-assess-damage.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-assess-supplies": { path: "/audio/voice/young-assess-supplies.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-bark-tired": { path: "/audio/voice/young-bark-tired.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"young-bark-concern": { path: "/audio/voice/young-bark-concern.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"young-bark-decision": { path: "/audio/voice/young-bark-decision.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"young-bark-responsibility": { path: "/audio/voice/young-bark-responsibility.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"young-bark-rush-frustration": { path: "/audio/voice/young-bark-rush-frustration.mp3", volume: 0.7, category: "voice", loop: false, positional: true },

	// ─── Voice — Dr. Rush (Extended) ─────────────────────────────────────────
	"rush-analyze": { path: "/audio/voice/rush-analyze.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-eureka": { path: "/audio/voice/rush-eureka.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-disappointed": { path: "/audio/voice/rush-disappointed.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-ancient-respect": { path: "/audio/voice/rush-ancient-respect.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-condescend": { path: "/audio/voice/rush-condescend.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"rush-urgent": { path: "/audio/voice/rush-urgent.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"rush-secret": { path: "/audio/voice/rush-secret.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-young-conflict": { path: "/audio/voice/rush-young-conflict.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-bark-muttering": { path: "/audio/voice/rush-bark-muttering.mp3", volume: 0.5, category: "voice", loop: false, positional: true },
	"rush-bark-eli": { path: "/audio/voice/rush-bark-eli.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-bark-sleep": { path: "/audio/voice/rush-bark-sleep.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-bark-mission": { path: "/audio/voice/rush-bark-mission.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"rush-ancient-language": { path: "/audio/voice/rush-ancient-language.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Lt. Scott ───────────────────────────────────────────────────
	"scott-move-out": { path: "/audio/voice/scott-move-out.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"scott-point": { path: "/audio/voice/scott-point.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"scott-scout": { path: "/audio/voice/scott-scout.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"scott-clear": { path: "/audio/voice/scott-clear-evacuation.mp3", volume: 0.85, category: "voice", loop: false, positional: false },
	"scott-contact": { path: "/audio/voice/scott-contact.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"scott-cover": { path: "/audio/voice/scott-cover.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"scott-gate-time": { path: "/audio/voice/scott-gate-time.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"scott-regroup": { path: "/audio/voice/scott-regroup.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"scott-fallen": { path: "/audio/voice/scott-fallen.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"scott-retreat": { path: "/audio/voice/scott-retreat.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"scott-bark-duty": { path: "/audio/voice/scott-bark-duty.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"scott-bark-eli": { path: "/audio/voice/scott-bark-eli.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"scott-bark-planet-nice": { path: "/audio/voice/scott-bark-planet-nice.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"scott-bark-ready": { path: "/audio/voice/scott-bark-ready.mp3", volume: 0.7, category: "voice", loop: false, positional: true },

	// ─── Voice — Chloe Armstrong (Extended) ──────────────────────────────────
	"chloe-encourage-eli": { path: "/audio/voice/chloe-encourage-eli.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-scared": { path: "/audio/voice/chloe-scared.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-thanks": { path: "/audio/voice/chloe-thanks.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"chloe-capable": { path: "/audio/voice/chloe-capable.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-translate": { path: "/audio/voice/chloe-translate.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-fight-back": { path: "/audio/voice/chloe-fight-back.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-strategy": { path: "/audio/voice/chloe-strategy.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"chloe-trance": { path: "/audio/voice/chloe-trance.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — TJ Johansen (Extended) ──────────────────────────────────────
	"tj-triage": { path: "/audio/voice/tj-triage.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-medicine-planet": { path: "/audio/voice/tj-medicine-planet.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-stabilize": { path: "/audio/voice/tj-stabilize.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"tj-cant-help": { path: "/audio/voice/tj-cant-help.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"resource-tj-medicine": { path: "/audio/voice/resource-tj-medicine.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Sgt. Greer (Extended) ───────────────────────────────────────
	"greer-threat": { path: "/audio/voice/greer-threat.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-defend": { path: "/audio/voice/greer-defend.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"greer-ready": { path: "/audio/voice/greer-ready.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-hunt": { path: "/audio/voice/greer-hunt.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"greer-bark-trust": { path: "/audio/voice/greer-bark-trust.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"greer-bark-loyalty": { path: "/audio/voice/greer-bark-loyalty.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"greer-bark-planet": { path: "/audio/voice/greer-bark-planet.mp3", volume: 0.7, category: "voice", loop: false, positional: true },

	// ─── Voice — Camile Wray ─────────────────────────────────────────────────
	"wray-civilian-concern": { path: "/audio/voice/wray-civilian-concern.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-negotiate": { path: "/audio/voice/wray-negotiate.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-resource-fair": { path: "/audio/voice/wray-resource-fair.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-support-eli": { path: "/audio/voice/wray-support-eli.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-compromise": { path: "/audio/voice/wray-compromise.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-rights": { path: "/audio/voice/wray-rights.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-report": { path: "/audio/voice/wray-report.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"wray-angry": { path: "/audio/voice/wray-angry.mp3", volume: 0.9, category: "voice", loop: false, positional: true },

	// ─── Voice — Adam Brody ──────────────────────────────────────────────────
	"brody-repair-assess": { path: "/audio/voice/brody-repair-assess.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-repair-bad": { path: "/audio/voice/brody-repair-bad.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-repair-doable": { path: "/audio/voice/brody-repair-doable.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-repair-done": { path: "/audio/voice/brody-repair-done.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-sarcasm-01": { path: "/audio/voice/brody-sarcasm-01.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"brody-sarcasm-02": { path: "/audio/voice/brody-sarcasm-02.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"brody-parts-request": { path: "/audio/voice/brody-parts-request.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-warning": { path: "/audio/voice/brody-warning.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"brody-volker-banter": { path: "/audio/voice/brody-volker-banter.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"resource-brody-parts": { path: "/audio/voice/resource-brody-parts.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Dale Volker ─────────────────────────────────────────────────
	"volker-star-analysis": { path: "/audio/voice/volker-star-analysis.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"volker-planet-data": { path: "/audio/voice/volker-planet-data.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"volker-nervous": { path: "/audio/voice/volker-nervous.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"volker-complain": { path: "/audio/voice/volker-complain.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"volker-scared": { path: "/audio/voice/volker-scared.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"volker-eureka": { path: "/audio/voice/volker-eureka.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"volker-brody-banter": { path: "/audio/voice/volker-brody-banter.mp3", volume: 0.7, category: "voice", loop: false, positional: true },

	// ─── Voice — Lisa Park ───────────────────────────────────────────────────
	"park-analysis": { path: "/audio/voice/park-analysis.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-discovery": { path: "/audio/voice/park-discovery.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-planet-flora": { path: "/audio/voice/park-planet-flora.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-enthusiastic": { path: "/audio/voice/park-enthusiastic.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-caution": { path: "/audio/voice/park-caution.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-data": { path: "/audio/voice/park-data.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"park-optimist": { path: "/audio/voice/park-optimist.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"park-computer": { path: "/audio/voice/park-computer.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Vanessa James ───────────────────────────────────────────────
	"james-ready": { path: "/audio/voice/james-ready.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"james-position": { path: "/audio/voice/james-position.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"james-report": { path: "/audio/voice/james-report.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"james-hostile": { path: "/audio/voice/james-hostile.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"james-covering": { path: "/audio/voice/james-covering.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"james-wounded": { path: "/audio/voice/james-wounded.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Varro ───────────────────────────────────────────────────────
	"varro-help": { path: "/audio/voice/varro-help.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"varro-honor": { path: "/audio/voice/varro-honor.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"varro-recon": { path: "/audio/voice/varro-recon.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"varro-trust": { path: "/audio/voice/varro-trust.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — System Triggers ─────────────────────────────────────────────
	"timer-eli-2min": { path: "/audio/voice/timer-eli-2min.mp3", volume: 0.9, category: "voice", loop: false, positional: false },
	"timer-eli-1min": { path: "/audio/voice/timer-eli-1min.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"timer-eli-30sec": { path: "/audio/voice/timer-eli-30sec.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"timer-rush-crisis": { path: "/audio/voice/timer-rush-crisis.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"timer-young-evac": { path: "/audio/voice/timer-young-evac.mp3", volume: 1.0, category: "voice", loop: false, positional: false },
	"resource-crew-thirsty": { path: "/audio/voice/resource-crew-thirsty.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"resource-crew-hungry": { path: "/audio/voice/resource-crew-hungry.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"resource-eli-lime": { path: "/audio/voice/resource-eli-lime.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"state-rush-demand": { path: "/audio/voice/state-rush-demand.mp3", volume: 0.9, category: "voice", loop: false, positional: true },
	"state-young-damage": { path: "/audio/voice/state-young-damage.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"state-brody-assess": { path: "/audio/voice/state-brody-assess.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"state-volker-readings": { path: "/audio/voice/state-volker-readings.mp3", volume: 0.8, category: "voice", loop: false, positional: true },
	"state-park-analysis": { path: "/audio/voice/state-park-analysis.mp3", volume: 0.8, category: "voice", loop: false, positional: true },

	// ─── Voice — Proximity Barks ─────────────────────────────────────────────
	"bark-rush-respect": { path: "/audio/voice/bark-rush-respect.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-rush-dismiss": { path: "/audio/voice/bark-rush-dismiss.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-young-checkin": { path: "/audio/voice/bark-young-checkin.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-chloe-friendly": { path: "/audio/voice/bark-chloe-friendly.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-greer-respect": { path: "/audio/voice/bark-greer-respect.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-scott-casual": { path: "/audio/voice/bark-scott-casual.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-tj-concern": { path: "/audio/voice/bark-tj-concern.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-brody-sarcasm": { path: "/audio/voice/bark-brody-sarcasm.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-volker-nervous": { path: "/audio/voice/bark-volker-nervous.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-park-excited": { path: "/audio/voice/bark-park-excited.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
	"bark-wray-diplomatic": { path: "/audio/voice/bark-wray-diplomatic.mp3", volume: 0.7, category: "voice", loop: false, positional: true },
} as const satisfies Record<string, SoundEntry>;

export type SoundId = keyof typeof SOUND_CATALOG;
