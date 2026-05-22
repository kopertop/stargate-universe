import { describe, expect, it } from "vitest";

import {
	CREW_IDLE_ANIMATION_ID,
	FEMALE_IDLE_ANIMATION_ID,
	getDefaultViewerAnimationId,
} from "../../src/animations/vrma-catalog";

describe("vrma-catalog crew idle resolution", () => {
	it("maps crew by gender", () => {
		expect(getDefaultViewerAnimationId("male")).toBe(CREW_IDLE_ANIMATION_ID);
		expect(getDefaultViewerAnimationId("female")).toBe(FEMALE_IDLE_ANIMATION_ID);
		expect(getDefaultViewerAnimationId(undefined)).toBeUndefined();
	});

	it("uses the same male idle for Scott and Greer as other male crew", () => {
		expect(getDefaultViewerAnimationId("male")).toBe(CREW_IDLE_ANIMATION_ID);
	});
});
