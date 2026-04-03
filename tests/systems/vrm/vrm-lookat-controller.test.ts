import { describe, expect, it, vi, beforeEach } from "vitest";
import { Object3D, Vector3 } from "three";
import { VrmLookAtController } from "../../../src/systems/vrm/vrm-lookat-controller";

function createMockVrm() {
	return {
		lookAt: {
			autoUpdate: true,
			yaw: 0,
			pitch: 0,
			lookAt: vi.fn(),
			reset: vi.fn(),
			update: vi.fn(),
			target: null,
		},
		scene: new Object3D(),
		humanoid: {},
		meta: {},
		update: vi.fn(),
	} as unknown;
}

describe("VrmLookAtController", () => {
	let mockVrm: ReturnType<typeof createMockVrm>;
	let controller: VrmLookAtController;

	beforeEach(() => {
		mockVrm = createMockVrm();
		controller = new VrmLookAtController(mockVrm as never);
	});

	it("disables VRM autoUpdate on construction", () => {
		const lookAt = (mockVrm as { lookAt: { autoUpdate: boolean } }).lookAt;
		expect(lookAt.autoUpdate).toBe(false);
	});

	it("lookAtCamera calls vrm.lookAt.lookAt with camera position", () => {
		const camera = new Object3D();
		camera.position.set(5, 2, 3);

		controller.lookAtCamera(camera);
		controller.update(0.016, camera);

		const lookAt = (mockVrm as { lookAt: { lookAt: ReturnType<typeof vi.fn> } }).lookAt;
		expect(lookAt.lookAt).toHaveBeenCalled();
	});

	it("lookAtPosition tracks a world position", () => {
		const target = new Vector3(10, 0, -5);
		controller.lookAtPosition(target);
		controller.update(0.016);

		const lookAt = (mockVrm as { lookAt: { lookAt: ReturnType<typeof vi.fn> } }).lookAt;
		expect(lookAt.lookAt).toHaveBeenCalledWith(target);
	});

	it("lookAtDirection sets manual yaw/pitch", () => {
		controller.lookAtDirection(30, -10);
		controller.update(0.016);

		const lookAt = (mockVrm as { lookAt: { yaw: number; pitch: number } }).lookAt;
		expect(lookAt.yaw).toBe(30);
		expect(lookAt.pitch).toBe(-10);
	});

	it("clearLookAt blends gaze back to forward", () => {
		const lookAt = (mockVrm as { lookAt: { yaw: number; pitch: number } }).lookAt;
		lookAt.yaw = 20;
		lookAt.pitch = -15;

		controller.clearLookAt();

		// After several frames, yaw and pitch should approach 0
		for (let i = 0; i < 120; i++) {
			controller.update(0.016);
		}

		expect(Math.abs(lookAt.yaw)).toBeLessThan(0.1);
		expect(Math.abs(lookAt.pitch)).toBeLessThan(0.1);
	});

	it("does nothing when disabled", () => {
		controller.setEnabled(false);
		controller.lookAtPosition(new Vector3(10, 0, 0));
		controller.update(0.016);

		const lookAt = (mockVrm as { lookAt: { lookAt: ReturnType<typeof vi.fn>; reset: ReturnType<typeof vi.fn> } }).lookAt;
		expect(lookAt.lookAt).not.toHaveBeenCalled();
		expect(lookAt.reset).toHaveBeenCalled();
	});

	it("calls vrm.lookAt.update each frame", () => {
		controller.update(0.016);
		const lookAt = (mockVrm as { lookAt: { update: ReturnType<typeof vi.fn> } }).lookAt;
		expect(lookAt.update).toHaveBeenCalledWith(0.016);
	});
});
