/**
 * Third-person follow camera.
 *
 * Trails the player at a configurable distance with exponential smoothing
 * toward the target position computed from `eye` and `viewDir`. The eye height
 * offset and follow distance are derived from the standing height each time
 * `setStandingHeight()` is called (e.g. on crouch/stand transitions).
 */
import { PerspectiveCamera, Vector3 } from "three";
import type { CameraController, CameraMode } from "./controller";

const SMOOTH = 10;

export class ThirdPersonCameraController implements CameraController {
  readonly mode = "third-person" as const;
  readonly pitchMin = -1.25;
  readonly pitchMax = 0.4;
  readonly showPlayerBody = true;

  private readonly camera: PerspectiveCamera;
  private readonly _desiredPos = new Vector3();
  private followDistance = 3.2;
  private eyeUpOffset = 0;

  constructor(camera: PerspectiveCamera) {
    this.camera = camera;
  }

  setStandingHeight(height: number): void {
    this.followDistance = Math.max(3.2, height * 2.7);
    this.eyeUpOffset = height * 0.24;
  }

  update(eye: Readonly<Vector3>, viewDir: Readonly<Vector3>, deltaSeconds: number): void {
    this._desiredPos
      .copy(eye as Vector3)
      .addScaledVector(viewDir as Vector3, -this.followDistance);
    this._desiredPos.y += this.eyeUpOffset;
    this.camera.position.lerp(this._desiredPos, 1 - Math.exp(-deltaSeconds * SMOOTH));
    this.camera.lookAt(eye as Vector3);
  }
}
