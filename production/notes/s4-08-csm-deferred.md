# S4-08 — CSM (Cascaded Shadow Maps): deferred

**Status:** deferred to a later sprint.
**Decision date:** 2026-05-21 (Sprint 4 in-flight)

## Why not this sprint

CSM is an exterior-scene technique. It cascades the shadow map into 2–4
view-dependent slices so a single directional light can cast crisp shadows
both at the player's feet and on the distant terrain horizon — without
either blowing the shadow texture budget or smearing far shadows into a
single low-res blur.

This sprint's traffic is interior-heavy:
- gate-room (interior)
- destiny-corridor (interior)
- opening-cinematic (no terrain — space)
- scrubber-room (interior)

The only exterior scene in the project, `desert-planet`, is currently a
stub. Implementing CSM now would mean tuning cascade splits, frustum
fits, and PSM bias against a placeholder — work that would have to be
re-tuned the moment the planet's real terrain, hero foliage, and
sun-angle direction land.

## What landed instead this sprint

The S4-08 budget rolled into S4-05 (instancing in destiny-corridor —
~32 → 2 draw calls for repeating fixtures) and S4-06 (post profiles —
centralised tone mapping/exposure per scene profile). Both of these
deliver visible-on-shipping-scenes wins that CSM would not.

## When to revisit

Re-open S4-08 once any of the following is true:

1. `desert-planet` (or any exterior scene) has real terrain geometry,
   a hero directional sun, and a reference shot to tune against.
2. A scene introduces **outdoor → indoor transitions** that need shadow
   continuity (e.g. stepping off Destiny onto a planet through an open
   gate). CSM bias mismatch becomes visible at the boundary.
3. Daylight-cycle work begins — moving sun angles change cascade splits
   per minute, so cascade tuning becomes part of the day-night loop.

## Implementation pointers (for the future)

- three.js ships `CSM` and `CSMHelper` under `three/examples/jsm/csm/`.
  No external dep needed.
- Default cascade count: 4 splits is typical; mobile/lower-end GPU paths
  often drop to 2.
- The split scheme that holds up best for player-centric outdoor games is
  practical (PSSM) — `mode: "practical", lambda: 0.5` is a reasonable
  starting point.
- WebGPU support: CSM in three.js uses WebGLRenderer shadow paths; verify
  WebGPU node-material parity before wiring (the project's renderer is
  WebGPU-first with WebGL fallback).

## Tracking

Captured in `production/perf-baseline-2026-05-21.md` § "Caveats" — keep
this note linked from the next exterior-scene GDD when one is authored.
