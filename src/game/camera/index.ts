/**
 * Camera Systems — Camera controller abstractions for the game.
 *
 * Provides multiple camera modes (FPS, third-person, top-down) with a unified
 * controller interface. Scene code imports from here — never reaches into the
 * individual controller implementations directly.
 *
 * @see src/game/camera/controller.ts
 */
export type { CameraMode, CameraController } from "./controller";
export { createCameraController } from "./controller";
export { FpsCameraController } from "./fps";
export { ThirdPersonCameraController } from "./third-person";
export { TopDownCameraController } from "./top-down";
export { frameCameraOnObject } from "./frame-on-object";
