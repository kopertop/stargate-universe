# Sprint 5 — 2026-05-21 to 2026-06-03

## Sprint Goal

**Make E1 Mission 1 actually playable in Godot.** Today the gate room exists in
isolation — the player spawns, reads consoles, and that's the slice. Mission 1 of
the game's intended story arc (find quarters → discover Kino Remote → discover
hull breach → seal it) cannot currently be completed.

This sprint connects the rooms that already exist as scene stubs
(`destiny_corridor.tscn`, `eli_quarters.tscn`, `hull_breach.tscn`) into a
walkable, objective-driven slice, and adds the missing interactables (Kino
pickup, crate, seal-the-breach panel) so the mission's beats fire end-to-end.

**Success criteria:** A new player can boot the game, complete Mission 1 without
hints, and see the EpisodeWrap card. The headless `e1_flow.gd` test gains four
new assertions covering Kino discovery, breach discovery, breach sealing, and
mission completion.

Mission 2 (stargate dial-out → lime planet → CO2 scrubber repair) is **out of
scope** and queued for Sprint 6.

## Capacity

- Total days: 14 calendar days
- Available hours: ~6–8 hrs (holding pattern, a few hours per week)
- Buffer (25%): ~1.5 hrs reserved for debugging & PR review
- Productive hours: ~5–6 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|--------------|---------------------|------------|
| S5-01 | **Wire rooms together via doors + SceneRouter** — Connect `gate_room` ↔ `destiny_corridor` ↔ `eli_quarters` ↔ `hull_breach` using `door.tscn` as area-trigger transitions. Each door records discovery in `GameState.rooms_discovered`. | 1.5 | — | Player can walk from gate room through corridor to quarters and to hull breach. All four rooms appear in `rooms_discovered` after a full circuit. | ship-exploration.md |
| S5-02 | **Kino Remote pickup** — Author a `kino_remote.tscn` interactable (placed in `eli_quarters`). Hold E → KinoRemote autoload flips to `acquired = true`, GameState logs entry, audio cue fires. | 1 | S5-01 | Kino sits on a desk in quarters. Walking up shows interact prompt. Pickup is one-time, persists across save/load. | kino-remote.md |
| S5-03 | **Kino Remote UI (Godot port)** — Tab key raises diegetic overlay only after pickup. Shows current objective + discovered rooms list. Lower on Tab. | 1.5 | S5-02 | Tab does nothing before pickup. After pickup: Tab raises overlay, shows live objective text + room list, Tab lowers it. Pause game while raised. | kino-remote.md |
| S5-04 | **Hull breach scene fleshed out** — Wind/vacuum SFX loop, visible breach geometry (broken bulkhead + starfield poking through), accelerated `GameState.consume_oxygen` while player is in this scene. | 1.5 | S5-01 | Entering hull_breach triggers vacuum audio. Oxygen drains ~3× faster than baseline. Visible breach is unmistakable on entry. | ship-state-system.md, ship-atmosphere-lighting.md |
| S5-05 | **Seal-the-breach interaction** — Panel near the breach. Hold E for ~2s → breach closes (visual change), vacuum audio fades, oxygen drain returns to baseline, GameState marks `breach_sealed = true`. | 1.5 | S5-04 | Hold E triggers progress indicator. On completion: visual + audio + state all flip. Re-entering scene does not re-open breach. | timer-pressure-system.md |
| S5-06 | **Crate prefab (interactable)** — Reusable `crate.tscn` with a one-shot interaction that fires a log entry. Place 2–3 across corridor/quarters with lore snippets. | 1 | S5-01 | Walking up shows prompt. E key opens crate (visual: lid lifts), log entry added to GameState. Looted crates persist their state across save/load. | resource-inventory.md |
| S5-07 | **Mission 1 completion trigger** — When `breach_sealed = true` AND `kino_remote.acquired = true` AND key rooms discovered, fire `EpisodeWrap` with Mission 1 card. | 0.5 | S5-02, S5-05 | Sealing breach as the last beat triggers wrap card. Wrap card text references all three accomplishments. | save-load-interface.md |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|--------------|---------------------|------------|
| S5-08 | **Objective HUD pin** — Current objective text shown bottom-left of HUD at all times (independent of Kino raise state). Updates as GameState.objective changes. | 0.5 | — | Objective is always visible during gameplay. Hidden in title screen and during EpisodeWrap. | kino-remote.md |
| S5-09 | **Extend `e1_flow.gd` smoke test** — Add assertions for Kino pickup → discovery → seal → mission complete (state mutations only, no scene rendering). | 1 | S5-02, S5-05, S5-07 | New `assert`s cover the four mission beats. Test still runs under 80 frames headless. | — |
| S5-10 | **Sprint-003/004 retro** — Single retro doc capturing what shipped on `main` (browser branch), why we pivoted, and what carries over conceptually. Replaces missing sprint-002-retro. | 0.5 | — | `production/sprints/archive-browser-stack/pivot-retro.md` exists, captures shipped vs dropped vs carryover-concept. | — |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|--------------|---------------------|------------|
| S5-11 | **Idle ↔ walk anim blend on Eli** — Wire AnimationTree blend space driven by horizontal speed. (Godot equivalent of dropped S4-04.) | 2 | — | Eli transitions smoothly between idle and walk. No T-pose at any speed. | vrm-model-integration.md |
| S5-12 | **Ambient ship sounds per room** — Loop low engine hum in corridor, quieter ambience in quarters, vacuum wind in breach. | 1 | S5-04 | Each room has distinct ambient bed. Crossfades on scene transition. | — |
| S5-13 | **Door open/close animation** — Sliding-door animation on `door.tscn` instead of instant teleport. | 1 | S5-01 | Doors slide open ~0.5s before scene change. Sound effect on open. | — |

## Carryover / superseded

| Prior Task | Disposition |
|------------|-------------|
| Sprint 1–3 retros (browser stack) | Archived to `archive-browser-stack/`. Conceptual learnings retained in memory entries. |
| Sprint 4 entire scope | Browser-stack-only (DRACO/Meshopt/KTX2/EffectComposer/leva). Not applicable to Godot — Godot has its own asset pipeline + post processing. |
| S4-04 character locomotion | Re-scoped as S5-11 (Nice-to-Have) using Godot AnimationTree. |
| S2-04 / S3-05 Kino Remote | Replaced by S5-02 + S5-03 (Godot port). |
| S2-01 wall colliders | Already covered by `KinematicBody3D` + `StaticBody3D` defaults in Godot scenes — no separate task needed. |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| `door.tscn` doesn't support area-trigger scene transitions out of the box | Medium | Medium | Wrap with `Area3D` + `SceneRouter.go_to(scene)` — pattern already used in gate_room consoles. |
| Hold-E progress indicator UX is harder than it looks (interruptible? cancellable?) | Medium | Low | Start with simple linear progress, no interrupt. Polish in Sprint 6. |
| Kino UI overlay conflicts with existing console UIs in gate_room | Low | Medium | Use a dedicated `CanvasLayer` for Kino, higher z than consoles. |
| Oxygen drain rate feels punishing on first playtest | Medium | Low | Tune via `GameState.OXYGEN_DRAIN_BREACH_MULT` constant. Easy to adjust post-playtest. |
| Save/load doesn't capture `breach_sealed` / `kino.acquired` state | Medium | High | Extend `game_state.gd` save payload first (one-line additions), cover with S5-09 test assertions. |

## Out of Scope (explicitly deferred)

- **Mission 2 (stargate dial-out → lime planet → CO2 scrubbers)** — Sprint 6
- Lt. Scott NPC re-author in Godot — Sprint 6 alongside dialogue
- VRM character pipeline — replaced by Kenney Eli model (already wired)
- Browser-era perf tooling (DRACO/Meshopt/KTX2/Vite chunks) — N/A on Godot
- Lime resource model + harvesting UI — Sprint 6

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] A fresh player can complete Mission 1 end-to-end without hints
- [ ] EpisodeWrap card fires on mission completion
- [ ] `e1_flow.gd` smoke test extended and passing
- [ ] Save/load round-trips Kino acquisition + breach sealed state
- [ ] GDScript compiles with zero parse errors in editor
- [ ] Committed to feature branches, merged to `godot`

## Notes

This is the **first Godot-era sprint**. Sprints 1–4 are archived as browser-stack
history. Velocity from those sprints is not predictive of Godot velocity — expect
the first ~2 tasks to take longer than estimated while Godot conventions
solidify (signals, scene composition, AnimationTree, autoloads).

If S5-01 (room wiring) blows past 1.5 hrs, cut S5-06 (crates) to a single crate
and defer the rest. The mission must complete; lore crates are flavor.
