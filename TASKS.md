# TASKS — Stargate Universe

> **Branch**: `feature/vrm-cleanup-level-editor`
> **Last updated**: 2026-05-02
> **Phase 0 reviewed for PR.** Game changes live on
> `feature/vrm-cleanup-level-editor`; engine support lives in
> `../vibe-game-engine/` on `add-managers`.

---

## How to use this file

- Check off tasks by changing `[ ]` to `[x]`.
- Each task has **Verify** steps — run them before checking off.
- Tasks are grouped by phase. Complete Phase N before starting Phase N+1
  unless explicitly marked "independent."
- GDD design docs are at `design/gdd/*.md` — read them before implementing.

---

## Phase 0 — Cinematic & Gameplay Fixes (this branch)

### Completed

- [x] **Gate halved + flush** — `GATE_RADIUS` 6→3, proportional chevrons,
      portal bottom sunk 0.2m below floor.
      _Files_: `src/scenes/gate-room/index.ts` (constants + chevron geometry)
      _Verify_: `/?scene=gate-room` — gate visually smaller, no step at portal base.

- [x] **VRM-only characters** — deleted `createChaosActor` capsule code +
      `createFallbackCapsule` in `vrm-character-manager.ts` + capsule-fallback
      visual in `starter-player-controller.ts`.
      _Files_: `cinematic-controller.ts`, `vrm-character-manager.ts`,
      `starter-player-controller.ts`
      _Verify_: no blue pill under player; no capsule shapes anywhere in scene.

- [x] **Ragdoll system rewrite** — `src/systems/ragdoll.ts` mirrors the
      official crashcat example: full stabilization, skeleton hierarchy,
      named joints, imperative lifecycle API.
      _Verify_: `/?scene=character-viewer&ragdoll=1` — click to relaunch,
      ragdoll stays together (note: uses old Crashcat backend which may
      still self-collide; Rapier backend now available for this).

- [x] **Character viewer scene** — `src/scenes/character-viewer/` with URL
      params `?character=<id>&animation=<path>&ragdoll=1&autorotate=0`.
      _Verify_: `/?scene=character-viewer&character=rush` loads Rush VRM on turntable.

- [x] **Level editor GDD** — skeleton at `design/gdd/level-editor.md`.
      Sections are `_TBD_` — fill incrementally per design-docs rule.

- [x] **Level editor prototype** — `src/scenes/editor/` + `src/editor/`
      with click-to-place crate/stargate, grid snap, localStorage persist.
      _Verify_: `/?scene=editor` — click to place crate, press 2 for stargate,
      G toggles snap, right-click removes, Delete clears all, refresh restores.

- [x] **Controller profiles (engine)** — `../vibe-game-engine/src/input/`
      `controller-profiles.ts` + `calibration.ts`. Built-in profiles for
      Xbox/Nintendo/PlayStation/8BitDo, localStorage persistence,
      `beginCalibration()` API.
      _Verify_: engine `bun run typecheck` clean.

- [x] **Controller calibration UI (game)** —
      `src/systems/controller-calibration.ts` + wired in `main.ts`.
      _Verify_: connect an unrecognized gamepad → modal prompts A/B/X/Y presses.

- [x] **Natural stand-up sequence** —
      `src/systems/vrm/vrm-standup-sequence.ts` with 6-phase procedural
      bone animation (prone → pushup → kneel → hands-on-head → shake → stand).
      Wired into cinematic `updateThrown` for all non-Young thrown actors.
      _Verify_: `/?scene=gate-room&cinstep=20` — after Scott lands, watch the
      phased recovery instead of the old simple tilt-up.

- [x] **Dialogue arrow-key nav** — engine `dialogue-panel.ts` gained
      `selectPrev()`/`selectNext()`/`confirmSelection()`/`isOpen()`.
      Gate-room wired: D-pad + ArrowUp/Down navigate, A/Enter confirm.
      Digit1-4 and A/B/X/Y per-option direct-mapping removed.
      _Files_: `../vibe-game-engine/src/ui/dialogue-panel.ts`,
      `src/scenes/gate-room/index.ts`, `src/systems/input.ts`
      _Verify_: talk to NPC, use ↑/↓ to move highlight, Enter/A to pick.

- [x] **"Press A" interact prompts** — `src/ui/interact-prompt-text.ts`
      `formatInteractPrompt()` returns `[A]` or `[E]` based on gamepad state.
      All 4 scene files updated.
      _Verify_: with gamepad connected, prompts show `[A] Talk to ...`.

- [x] **A button = Interact** — `GamepadButton.A` now fires
      `[Jump, MenuConfirm, Interact]` in `src/systems/input.ts`.
      _Verify_: press A near Rush → dialogue opens.

- [x] **Manifest → R2 URLs** — `public/assets/characters/manifest.json`
      now points every crew VRM at the R2 public bucket
      (`pub-c642ba55…r2.dev/characters/<id>.vrm`).
      _Verify_: `/?scene=gate-room` — Scott renders as a real VRM, not a
      block/Rush-fallback. (Requires VRMs uploaded to R2 under those names.)

- [x] **Blue capsule fix** — deleted `createFallbackCapsule()` + all
      `fallbackMesh` refs from `vrm-character-manager.ts`. Cinematic's
      `restorePlayerVisual` no longer filters by stale name.
      _Verify_: no blue pill anywhere under the player character.

- [x] **More NPCs through gate** — added Greer, Chloe, and one VRoid
      anonymous extra to the cinematic throw sequence (Beat-4 chaos).
      _Verify_: `/?scene=gate-room` — 8 crew flung through gate (5 named + 3 extras).

- [x] **TJ kneels next to Young** — after `T_GATE_SHUTDOWN` (32s), TJ
      teleports next to Young, faces him, applies `applyKneelingPose()`.
      _Verify_: `/?scene=gate-room&cinstep=33` — TJ kneeling beside prone Young.

- [x] **Physics backend abstraction (engine)** —
      `../vibe-game-engine/src/physics/backend-interface.ts` defines
      `PhysicsBackend` interface. Two implementations:
      `backends/rapier-backend.ts` (Rapier, `contactsEnabled:false` on joints)
      `backends/crashcat-backend.ts` (Crashcat/Jolt wrapper).
      Factory: `createPhysicsBackend("rapier" | "crashcat")`.
      _Verify_: engine `bun run typecheck` clean. Rapier ragdoll test passes
      (`bun test src/physics/backends/rapier-backend.test.ts`).

- [x] **Editor core Phase 1a (engine)** —
      `../vibe-game-engine/src/editor/{types,component-registry,scene-api,index}.ts`
      Prefab/GameObject/ComponentData types, imperative ComponentView lifecycle,
      Scene/Entity/EntityComponent handles with change-listener API.
      _Verify_: engine `bun run typecheck` clean.

### Pending — not yet started

- [x] **Commit all Phase 0 changes**
      _Branch_: `feature/vrm-cleanup-level-editor`
      _Instruction_: review `git diff --stat` across both repos, stage
      relevant files, write conventional commit message. Do NOT force-push.
      Engine changes need a separate commit in `../vibe-game-engine/`.
      _Verify_: `git status` clean in both repos after commit.
      _Done_: reviewed, fixed smoke-test blockers, and prepared separate
      game/engine commits for PR on 2026-05-02.

---

## Phase 1 — Editor Core (engine-side)

> **Decisions (locked 2026-04-15):**
> - UI: Preact + shadow DOM (editor package only)
> - Format: Prefab JSON canonical; `scene.runtime.json` derived
> - ECS: unified — editor entities ARE bitECS entities
> - View lifecycle: imperative `{ create, update, dispose }`
> - Design doc: `design/gdd/editor-port-design.md`

- [x] **#12 Study r3game architecture** — design doc written.

- [ ] **#13 Editor core Phase 1b — bitECS bridge + renderer**
      _What_: implement `SceneAdapter` in `prefab-renderer.ts` that
      materializes GameObjects → bitECS entities and calls Component Views.
      _Where_: `../vibe-game-engine/src/editor/prefab-renderer.ts`
      _Instruction_:
      1. Read `scene-api.ts` SceneAdapter interface
      2. For each GameObject in the prefab tree, `addEntity()` to bitECS world
      3. For each component on the GameObject, look up its `ComponentView`
         via `getComponent(type)` and call `view.create(ctx)`
      4. Store the bitECS eid ↔ GameObject id mapping
      5. On property change (via Scene API change listener), call `view.update()`
      6. On node removal, call `view.dispose()` + `removeEntity()`
      _Verify_: write a unit test that creates a Prefab with a Transform +
      Geometry component, materializes it, and confirms an `Object3D` exists
      in the scene root.

- [ ] **Register built-in components: Transform, Geometry, Material**
      _What_: three `ComponentDefinition` entries with full `create`/`update`/
      `dispose` Views that produce real Three.js objects.
      _Where_: `../vibe-game-engine/src/editor/components/` (new dir)
      _Instruction_:
      - **Transform**: `create` → new `Group()` with position/rotation/scale
        from properties. `update` → copy props to Object3D.
      - **Geometry**: `create` → `new Mesh(geo, defaultMat)` where geo is
        `BoxGeometry`/`SphereGeometry`/etc per `geometryType` prop.
      - **Material**: `create` → noop (attaches to sibling Geometry's mesh).
        `update` → set color/roughness/metalness on the mesh's material.
      _Verify_: `registerComponent(transformComponent)` + create a scene with
      a box at `[0,2,0]` → visible in Three.js scene.

- [ ] **#14 Build vibe editor UI (hierarchy, inspector, gizmos)**
      _What_: Preact-in-shadow-DOM panels. Left = hierarchy tree, right =
      inspector with per-component property editors, top = toolbar.
      _Where_: new `@kopertop/vibe-game-engine-editor` package (or
      `../vibe-game-engine/src/editor/ui/` temporarily).
      _Instruction_:
      1. Add `preact` as devDep to the editor package
      2. Create shadow-DOM host element that attaches to the game's
         `document.body` (or a user-specified container)
      3. Hierarchy panel: subscribe to Scene change events, render tree
      4. Inspector: on selection change, iterate selected entity's components,
         render each component's form fields
      5. Toolbar: Play/Pause, transform-mode toggle (W/E/R), save/load buttons
      _Verify_: `/?scene=editor&editor=1` shows panels overlaying the 3D view.

---

## Phase 2 — Editor Polish

- [ ] **#17 Gizmo UX** — Three.js `TransformControls` wired to selected
      entity's Object3D. W/E/R mode toggle, axis constraints, snap.
      _Prerequisite_: #14 (needs selection state from inspector).

- [ ] **#23 Play-mode boundary** — serialize prefab state on Play, restore
      on Stop. Flash indicator bar.
      _Prerequisite_: #13 Phase 1b (needs materializer to rebuild scene from
      snapshot).

- [ ] **#22 scene.runtime.json exporter** — one-way `Prefab → RuntimeScene`
      converter that emits the `@ggez/runtime-format` schema.
      _Prerequisite_: #13 Phase 1b + built-in components.

---

## Phase 3 — VRM + Animation Pipeline (editor-driven)

- [ ] **#15 VRMCharacter component** — editor component with properties
      `{ vrmUrl, idleAnimationUrl, gettingUpUrl, extraClipsUrls[] }`.
      Hot-reloads VRM in editor. Integrates with `loadVRMCharacter` +
      `loadAnimation` retargeting.
      _Prerequisite_: #13 Phase 1b (component Views must work).

- [ ] **#16 Animation graph editor** — in-editor panel to drop Mixamo/GLB/VRMA
      clips, define state transitions (idle↔walk↔run↔jump↔getting-up),
      set crossfade durations, export `AnimationGraph` JSON.
      _Prerequisite_: #15 (needs VRM loaded to preview animations).

- [ ] **#20 "Prefab from VRoid" workflow** — right-click VRM in asset browser
      → auto-generate GameObject with VRMCharacter + Transform + Dialogue +
      PathfindTarget components.
      _Prerequisite_: #15 + #14 (asset browser + VRM component).

- [ ] **#21 Prefab library dock** — bottom panel with thumbnails, tag search,
      drag-into-viewport placement.
      _Prerequisite_: #14 (editor UI framework).

---

## Phase 4 — SGU Migration

- [ ] **#19 Migrate SGU editor to engine editor** — convert `src/editor/`
      prop-catalog + `src/scenes/editor/` scene → engine's Prefab/GameObject/
      Component model. Delete duplicate scaffolding.
      _Prerequisite_: #14 + built-in components.

---

## Independent Tasks (no phase dependency)

- [ ] **#8 Observation room — execute design**
      _Design doc_: `design/gdd/observation-room-rush-intro.md` (complete)
      _What_: 10 ordered file changes:
      1. `src/scenes/observation-room/scene.runtime.json` — new
      2. `src/scenes/observation-room/index.ts` — new (~200 LOC)
      3. `src/npcs/dr-rush-observation.ts` — new NPC def
      4. `src/npcs/chloe-gateroom.ts` — new NPC def
      5. `src/npcs/greer-gateroom.ts` — new NPC def
      6. `src/dialogues/scientists-gateroom.ts` — new dialogue tree
      7. `src/dialogues/dr-rush-observation.ts` — new/modified
      8. `src/quests/find-rush/` — new quest definition
      9. `src/scenes/gate-room/index.ts` — remove Rush NPC, add Chloe+Greer,
         add observation-room doorway trigger, wire quest
      10. `src/dialogues/scott-opening.ts` — update "observation room" text
      _Risk_: cinematic-spawned Rush body may persist after cinematic ends.
      Verify cleanup in cinematic completion callback.
      _Verify_: `/?scene=gate-room` — no Rush; Chloe+Greer present; doorway
      to observation room; Rush at window inside.

- [ ] **Re-enable ragdoll in cinematic (Rapier backend)**
      _Prerequisite_: #18 ✅ (physics abstraction done)
      _What_: swap the cinematic's thrown-crew physics from parabolic math to
      Rapier-backend ragdoll. The Rapier backend's `contactsEnabled: false`
      on joints prevents the self-collision explosion that broke the Crashcat
      ragdoll.
      _Instruction_:
      1. In `cinematic-controller.ts`, import `createPhysicsBackend` from engine
      2. Create a Rapier backend instance at cinematic start
      3. In `updateThrown`, re-enable ragdoll creation via Rapier backend
      4. Replace `CRASHCAT_OBJECT_LAYER_MOVING` with Rapier body descriptors
      5. Ragdoll `launch()` + pelvis-to-VRM sync (code already written,
         currently commented out behind parabolic fallback)
      6. At `flightTime`, dispose ragdoll, snap to landPos, start standup
      _Verify_: `/?scene=gate-room` — crew tumble via real physics, no explosion,
      land at intended positions, standup sequence plays.

- [ ] **Mixamo stand-up animations**
      _What_: download "Standing Up" / "Zombie Stand Up" + "Dizzy Idle" from
      Mixamo, convert to GLB, drop in `public/assets/animations/` or per-
      character dirs.
      _Instruction_: see `public/assets/animations/README.md` for exact clip
      names, filenames, and conversion recipe.
      _Verify_: `/?scene=gate-room` — crew recovery uses mocap motion instead
      of procedural bone keyframes.

- [ ] **Upload remaining VRMs to R2**
      _What_: the manifest now points at R2 URLs. If `scott.vrm`, `young.vrm`,
      `tj.vrm`, `chloe.vrm`, `greer.vrm` aren't uploaded yet, they'll 404
      and fall back to Rush's VRoid.
      _Instruction_:
      1. Generate VRMs for each character (VRoid Studio or existing pipeline)
      2. Upload to `sgu-assets` R2 bucket under `characters/<id>.vrm`
      3. Test each: `/?scene=character-viewer&character=<id>`
      _Verify_: each crew member renders with their own distinct model.

- [ ] **Fill in level-editor GDD sections**
      _What_: `design/gdd/level-editor.md` has 8 required sections, most are
      `_TBD_`. Per design-docs rule, fill incrementally with user approval.
      _Instruction_: write Overview first, get approval, then Detailed Rules,
      then Formulas, etc.

---

## Reference — design docs produced this session

| Doc | Path | Status |
|---|---|---|
| Editor port design | `design/gdd/editor-port-design.md` | Complete with decisions |
| Observation room | `design/gdd/observation-room-rush-intro.md` | Complete, ready to execute |
| Level editor | `design/gdd/level-editor.md` | Skeleton — sections TBD |
| Animation README | `public/assets/animations/README.md` | Complete |

## Reference — engine files created/modified this session

| File | Repo | Status |
|---|---|---|
| `src/editor/types.ts` | vibe-game-engine | New — Prefab/GameObject/ComponentData |
| `src/editor/component-registry.ts` | vibe-game-engine | New — ComponentView lifecycle |
| `src/editor/scene-api.ts` | vibe-game-engine | New — Scene/Entity/EntityComponent |
| `src/editor/index.ts` | vibe-game-engine | New — barrel exports |
| `src/physics/backend-interface.ts` | vibe-game-engine | New — PhysicsBackend interface |
| `src/physics/backends/rapier-backend.ts` | vibe-game-engine | New — Rapier impl |
| `src/physics/backends/crashcat-backend.ts` | vibe-game-engine | New — Crashcat impl |
| `src/physics/backends/crashcat-types.d.ts` | vibe-game-engine | New — type stubs |
| `src/physics/backends/rapier-backend.test.ts` | vibe-game-engine | New — 12 tests |
| `src/physics/index.ts` | vibe-game-engine | Modified — factory export |
| `src/index.ts` | vibe-game-engine | Modified — editor + physics exports |
| `src/input/controller-profiles.ts` | vibe-game-engine | New — profile registry |
| `src/input/calibration.ts` | vibe-game-engine | New — calibration session |
| `src/input/input-manager.ts` | vibe-game-engine | Modified — gamepad profile integration |
| `src/ui/dialogue-panel.ts` | vibe-game-engine | Modified — selection nav API |
| `docs/controller-profiles.md` | vibe-game-engine | New — API docs |
