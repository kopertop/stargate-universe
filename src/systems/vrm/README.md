# VRM Character System

Manages VRM (Virtual YouTuber) character models throughout the game — loading, animation, expression, look-at, customization, and persistence.

## Architecture

```
vrm-loader.ts        — Fetches and parses .vrm files into THREE.Object3D
vrm-character-instance.ts — Orchestrates a VRM instance's full lifecycle
vrm-animation-retarget.ts — Maps game animations → VRM blendshapes/muscles
vrm-expression-controller.ts — Blendshape/VRM expression state machine
vrm-lookat-controller.ts   — Smooth look-at target tracking
vrm-customizer.ts    — Runtime character customization UI
vrm-customization-types.ts — Type definitions for customization options
vrm-customization-persistence.ts — Save/load customization to disk
vrm-config.ts        — VRM system configuration
vrm-crew-manifest.ts — Roster of available crew characters
vrm-bone-map.ts      — Bone hierarchy mapping
vrm-mtoon-converter.ts — Three.js MToon material setup
vrm-repair-vfx.ts    — Visual effects for repair/regen moments
```

## Entry Point

`vrm-character-instance.ts` — instantiate one per VRM character. Coordinates all other subsystems.

## Usage

```typescript
import { VrmCharacterManager } from './systems/vrm';

// Create manager for a crew member
const manager = new VrmCharacterManager('destiny-crew-01', {
  vrmUrl: '/assets/vrm/destiny-crew-01.vrm',
  lookatEnabled: true,
  expressionDefault: 'neutral',
});
await manager.load();
```

## Dependencies

- `three` (0.181) — WebGPU/WebGL rendering
- `@pixiv/three-vrm` — VRM import and runtime control
- `@ggez/anim-*` — Animation bundle loading

## See Also

- `src/game/starter-player-controller.ts` — Player avatar VRM integration
- `src/ui/editor/vrm-editor.ts` — Editor tooling for VRM assets
