# Level Editor

> **Status**: Skeleton — sections pending fill-in
> **Author**: User + Claude
> **Last Updated**: 2026-04-15
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 3 (Earned Discovery)

## Overview

_TBD_ — What the Level Editor is, what problem it solves, and how it fits into the
Stargate Universe development pipeline and (optionally) into player-facing
creative features down the line.

Working premise: the editor is an in-game mode (toggled via `?editor=1` URL
param at the prototype stage, and a debug key-combo at production stage) that
lets a human place catalog-registered props into a scene with a
Minecraft/WoW-housing placement feel. Edits persist to localStorage during
prototyping and eventually serialize into `scene.runtime.json` alongside
hand-authored geometry.

## Player Fantasy

_TBD_ — Internal-tooling version: "I can build a room in five minutes instead of
five hours." Player-facing version (future): "Destiny is mine to arrange."

## Detailed Rules

_TBD_

### Scope of the prototype (this pass)

- Single scene id: `editor`, reachable via `?scene=editor&editor=1`
- Single editable prop type (`crate` — simple box) + stub registry entry for
  `simple-stargate`
- Left click floor → place prop at raycast hit
- Right click prop → remove
- `G` → toggle 1m grid snap
- State persisted to `localStorage["sgu:editor:<sceneId>"]` as JSON
- Reload restores placed props

### Data model

```ts
type PropId = string; // e.g. "crate", "simple-stargate"

interface PropCatalogEntry {
    id: PropId;
    name: string;
    /** Create Three.js + optional physics bodies at the given world position. */
    create(ctx: PropBuildContext, position: THREE.Vector3, rotation: THREE.Euler): PropInstance;
}

interface PropInstance {
    id: PropId;
    root: THREE.Object3D;
    dispose(): void;
}

interface PlacedProp {
    id: PropId;
    position: [number, number, number];
    rotation: [number, number, number];
    /** Per-instance overrides (e.g. color, variant) — optional, prop-defined. */
    props?: Record<string, unknown>;
}

interface EditorScene {
    sceneId: string;
    version: 1;
    placed: PlacedProp[];
}
```

### Prop catalog (initial)

| id | name | geometry | physics | notes |
|---|---|---|---|---|
| `crate` | Crate | 1m box, weathered metal | static box | proves the pipeline |
| `simple-stargate` | Stargate (simple) | flat ring, 6m Ø | static frame box (no portal) | stub for V2 |

_Later additions expected: `dhd`, `ancient-console`, `crew-bunk`, `kino`, `resource-container`._

### Placement UX

_TBD_ — Full pointer interaction table:
- hover floor → show ghost preview of currently-selected prop
- click floor → place prop
- click existing prop → select for rotation/delete
- `[` / `]` → rotate selected 15° left/right
- `R` → reset rotation
- `Delete` / `Backspace` → remove selected
- `G` → toggle grid snap
- `Ctrl+Z` / `Ctrl+Y` → undo/redo (future)
- `S` → save to localStorage (also auto-save on every mutation)

### Save format & integration with `scene.runtime.json`

_TBD_ — Prototype saves to `localStorage`. Production flow: export button emits a
`scene.runtime.json` patch that can be committed to the repo. `PlacedProp` → scene
node mapping spec lives here.

## Formulas

_TBD_ — grid snap quantization, placement-preview collision offset, raycast ray
distance clamping.

## Edge Cases

_TBD_ — Covering: place-on-place, overlapping props, placement on non-floor
surfaces (walls, ceilings), prop catalog mismatch after schema bump, corrupt
localStorage, out-of-bounds placement, extreme prop count (>500 crates).

## Dependencies

- **Upstream:**
  - Scene system (`src/game/scene-types.ts`) — editor mounts as a scene
  - Character loader (`src/characters/character-loader.ts`) — later, for
    placing NPC spawns
  - Physics world (`@ggez/runtime-physics-crashcat`) — static bodies for collidable props
- **Downstream:** _TBD_ — Any scene that wants to be editable ("editable" flag
  in scene config) must participate.
- **Related:** scene authoring in ggez World Editor (external tool) — editor
  should eventually import/export compatible formats.

## Tuning Knobs

_TBD_
- `GRID_STEP` — snap quantization (default: 1.0 m; range: 0.1–4.0)
- `PLACEMENT_RAY_LENGTH` — max floor-pick distance (default: 64 m)
- `GHOST_OPACITY` — preview transparency (default: 0.5; range: 0.2–0.9)

## Acceptance Criteria

_TBD — must be testable by QA._

Prototype pass acceptance checklist:
1. Navigating to `/?scene=editor&editor=1` loads the editor scene without errors.
2. Left-click on the floor places a crate at the clicked location.
3. The placed crate persists across page refresh (localStorage).
4. Right-click on a placed crate removes it; refresh confirms deletion.
5. No production scenes are affected when `?editor=1` is absent.
6. Clearing `localStorage["sgu:editor:editor"]` returns the scene to empty.

Later-pass acceptance criteria (full editor):
7. All catalog props can be placed.
8. Rotation hotkeys operate on the selected prop.
9. Saving a scene produces a valid `scene.runtime.json` diff that the runtime
   can load identically offline.
