import { describe, expect, it } from "vitest";
import {
	MIXAMO_TO_VRM_BONE_MAP,
	VRM_REQUIRED_BONES,
	VRM_TO_GGEZ_BONE_MAP,
	validateRequiredBones,
} from "../../../src/systems/vrm/vrm-bone-map";

describe("VRM Bone Map", () => {
	it("defines all required VRM bones", () => {
		expect(VRM_REQUIRED_BONES).toContain("hips");
		expect(VRM_REQUIRED_BONES).toContain("spine");
		expect(VRM_REQUIRED_BONES).toContain("head");
		expect(VRM_REQUIRED_BONES).toContain("leftUpperArm");
		expect(VRM_REQUIRED_BONES).toContain("rightUpperArm");
		expect(VRM_REQUIRED_BONES).toContain("leftUpperLeg");
		expect(VRM_REQUIRED_BONES).toContain("rightUpperLeg");
		expect(VRM_REQUIRED_BONES.length).toBe(17);
	});

	it("maps every required bone in VRM_TO_GGEZ_BONE_MAP", () => {
		for (const bone of VRM_REQUIRED_BONES) {
			expect(VRM_TO_GGEZ_BONE_MAP.has(bone)).toBe(true);
		}
	});

	it("validates required bones — all present", () => {
		const available = new Set(VRM_REQUIRED_BONES);
		const missing = validateRequiredBones(available);
		expect(missing).toHaveLength(0);
	});

	it("validates required bones — some missing", () => {
		const available = new Set(["hips", "spine", "chest"]);
		const missing = validateRequiredBones(available);
		expect(missing.length).toBeGreaterThan(0);
		expect(missing).toContain("neck");
		expect(missing).toContain("head");
		expect(missing).not.toContain("hips");
	});

	it("validates required bones — empty set", () => {
		const missing = validateRequiredBones(new Set());
		expect(missing).toHaveLength(VRM_REQUIRED_BONES.length);
	});

	it("maps core Mixamo bones to VRM equivalents", () => {
		expect(MIXAMO_TO_VRM_BONE_MAP.get("mixamorigHips")).toBe("hips");
		expect(MIXAMO_TO_VRM_BONE_MAP.get("mixamorigSpine")).toBe("spine");
		expect(MIXAMO_TO_VRM_BONE_MAP.get("mixamorigHead")).toBe("head");
		expect(MIXAMO_TO_VRM_BONE_MAP.get("mixamorigLeftArm")).toBe("leftUpperArm");
		expect(MIXAMO_TO_VRM_BONE_MAP.get("mixamorigRightArm")).toBe("rightUpperArm");
	});

	it("Mixamo map covers all major body parts", () => {
		const mappedBones = new Set(MIXAMO_TO_VRM_BONE_MAP.values());
		expect(mappedBones.has("hips")).toBe(true);
		expect(mappedBones.has("head")).toBe(true);
		expect(mappedBones.has("leftHand")).toBe(true);
		expect(mappedBones.has("rightHand")).toBe(true);
		expect(mappedBones.has("leftFoot")).toBe(true);
		expect(mappedBones.has("rightFoot")).toBe(true);
	});
});
