/**
 * Episode 1 CO₂ crisis timer — shared duration and timer id.
 *
 * 20 minutes is long enough to collect deposits and return; 8 in-game hours
 * was cosmetic-only and never fired a fail state in playtests.
 */
export const AIR_CRISIS_CO2_TIMER_ID = "air-crisis:co2";

/** Wall-clock seconds for the planet-side CO₂ countdown. */
export const AIR_CRISIS_CO2_DURATION_SECONDS = 20 * 60;

import type { TimerSystem } from "../../systems/timer-system";

export const ensureAirCrisisCo2Timer = (timers: TimerSystem): void => {
	if (timers.getTimer(AIR_CRISIS_CO2_TIMER_ID)) return;

	timers.createTimer({
		id: AIR_CRISIS_CO2_TIMER_ID,
		durationSeconds: AIR_CRISIS_CO2_DURATION_SECONDS,
		tags: ["air-crisis", "life-support"],
		visible: true,
		completionEvent: "timer:planet:expired",
		warnings: [
			{ thresholdSeconds: 10 * 60, event: "timer:planet:warning" },
			{ thresholdSeconds: 2 * 60, event: "timer:planet:warning" },
		],
	});
};
