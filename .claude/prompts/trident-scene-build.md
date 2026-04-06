# Trident Scene Building — Claude Code Prompt

Use this prompt when launching Claude Code to build scenes in Trident.

---

## Context

You are working with **Trident**, the browser-based world editor for the **ggez** game framework. Trident is running at `http://localhost:5174/` and is connected via editor sync to the game dev server at `http://localhost:5173/`.

### Project Setup
- **Project**: stargate-universe (Stargate Universe 3D exploration game)
- **Engine**: ggez (Three.js game framework) + Crashcat physics
- **Scaffold**: `bunx create-ggez` with `@ggez/game-dev@0.1.11`
- **Trident location**: `~/Projects/personal/trident/` (cloned from `github.com/vibe-stack/trident`)
- **Game location**: `~/Projects/personal/stargate-universe/`
- **Scene files**: `src/scenes/<scene-id>/scene.runtime.json`

### How ggez Editor Sync Works
1. The game's Vite plugin (`@ggez/game-dev`) exposes `/api/editor-sync/status`
2. Trident connects to this endpoint and can read/write scene data
3. Scene changes in Trident save to `scene.runtime.json` → game hot-reloads
4. Each scene folder (`src/scenes/<id>/`) contains `index.ts`, `scene.runtime.json`, and `assets/`

### scene.runtime.json Format
Scenes contain:
- **nodes**: Geometry brushes with `kind: "primitive"`, `data.role: "brush"`, `data.shape: "cube"`, `data.size`, `data.physics.enabled: true`, `data.bodyType: "fixed"`, `data.colliderShape: "trimesh"`
- **entities**: Player spawns (`type: "player-spawn"`), triggers, etc.
- **materials**: Color, metalness, roughness, emissive properties
- **settings**: Player config (cameraMode, speed, jump), world config (gravity, fog, ambient, physics)

### What Needs Validation
Before building real scenes, validate the full pipeline works:
1. Trident can see the game project via editor sync
2. Adding a brush in Trident saves to `scene.runtime.json`
3. The game loads the brush with correct materials and position
4. Physics colliders are created automatically from `physics.enabled` brushes
5. Player cannot walk through physics-enabled walls

## Task: Build the Gate Room

Once pipeline is validated, build the gate room from Stargate Universe aboard the Starship Destiny:

- **Dimensions**: 26 wide × 40 deep × 8 tall
- **Aesthetic**: Dark ancient metal (#1a1a2e to #2a2a3a), blue emissive accents (#4488ff)
- **Layout**:
  - Floor, ceiling, four walls — all physics enabled
  - Raised platform at the back wall center (for the Stargate)
  - Two doorway openings in the side walls near the front (for corridor connections)
  - Player spawn at room center, facing the gate platform
- **Settings**: Third-person camera, physicsEnabled: true, dark fog
