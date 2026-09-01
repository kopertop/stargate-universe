|# Sprint 6 — 2026-07-13 to 2026-07-27

## Sprint Goal

**Complete Episode 1 end-to-end playthrough proof in headless mode.**

The goal is to verify that the expanded Episode 1 route (`gate_room` → `control_interface_room` → `kino_room` → `quarters_room_1` → `east_corridor` with `HullSealSwitch`) completes via production codepaths and produces EpisodeWrap. This turns the base system health (state boot, mission interactables, door transitions) into a demonstrably playable mission sequence.

**Success criteria:**
- `playthrough_runner.gd` reaches `control_interface_room`, interacts with Dr Rush, and `GameState.met_rush` is set.
- Runner reaches `kino_room`, interacts with `KinoPickup`, and `GameState.kino_acquired` is set.
- Runner reaches `quarters_room_1`, interacts with `Bed`, and `GameState.quarters_found` is set.
- Runner reaches `east_corridor` with `HullSealSwitch`, interacts, and one breach is sealed (`GameState.breaches_sealed >= 1`).
- Runner verifies `GameState.episode_complete` and EpisodeWrap behavior from the real mission sequence.
- `tests/run.sh` passes with the expanded playthrough test.

**Out of scope:**
- Visual polish, screenshots, mission readability pass.
- Mission 2 scope (gate dial-out → lime planet → CO2 scrubber repair).

## Capacity

- Total days: 14 calendar days
- Available hours: ~6–8 hrs (holding pattern, intermittent focus)
- Buffer (25%): ~1.5 hrs reserved for debugging and route stabilization
- Productive hours: ~5–6 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|--------------|---------------------|------------|
| S6-01 | Add `playthrough_runner.gd` route helper — Follow `target_room_id` via `room.gd` doors through a list of room IDs. Use `SceneRouter.instant_mode = true` for headless speed. | 1.5 | — | Helper `follow_route(target_list: Array[String])` moves the player through doors and returns final room ID. | ship-exploration.md |
| S6-02 | Expand playthrough route to E1 full path — Add sequence: `gate_room` → `stargate_corridor_east_connector` → `east_corridor` → `north_corridor` → `control_approach_north` → `control_interface_room` → `cr_corridor_2` → `kino_room` → elevator/north route → `elevator_room_floor_1` → `room_1753576770763` → `quarters_room_1` → back to `east_corridor`. | 2 | S6-01 | Route list is in `playthrough_runner.gd`, all transitions succeed, no assertion failures. | ship-exploration.md |
| S6-03 | Add duck-typed interactable finders — Create helpers to find NPC (`DrRush`), bed (`Bed`), Kino pickup (`KinoPickup`), and hull seal switch (`HullSealSwitch`) via script resource paths instead of class lookup. | 1 | S6-02 | Finders accept (node) → node or `null`, work in `instant_mode`, fire required interactions. | — |
| S6-04 | Verify Rush interaction — Add assertion after visiting `control_interface_room`: `assert GameState.met_rush == true`. | 0.5 | S6-02, S6-03 | Assertion passes; `met_rush` flag is set during scene arrival. | — |
| S6-05 | Verify Kino acquisition — Add assertion after visiting `kino_room`: `assert GameState.kino_acquired == true`. | 0.5 | S6-02, S6-03 | Assertion passes; KinoPickup node is found and interacted with. | kino-remote.md |
| S6-06 | Verify quarters discovery — Add assertion after visiting `quarters_room_1`: `assert GameState.quarters_found == true`. | 0.5 | S6-02, S6-03 | Assertion passes; `Bed` node is interacted with on arrival. | ship-exploration.md |
| S6-07 | Verify hull breach sealing — Add assertion after visiting `east_corridor` and interacting with `HullSealSwitch`: `assert GameState.breaches_sealed >= 1`. | 1 | S6-02, S6-03 | Assertion passes; seal switch node is found, interacted, and `GameState.breaches_sealed` is incremented. | timer-pressure-system.md |
| S6-08 | Verify EpisodeWrap from real mission sequence — Add final assertion after all beats: `assert GameState.episode_complete == true`. Verify EpisodeWrap behavior (card appears, state frozen) is triggered by the production mission flow, not a synthetic test-only path. | 1 | S6-07 | Assertion passes; EpisodeWrap fires via real `complete_episode_air()` call. | save-load-interface.md |
| S6-09 | Pass `tests/run.sh` with expanded playthrough — Ensure the new route is part of the main smoke test suite and the runner completes under 80 frames headless. | 0.5 | S6-01–S6-08 | All tests pass; output shows no assertion failures or crashes. | — |

## Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|--------------|---------------------|------------|
| S6-10 | Optional demo screenshot capture for full mission path — After playthrough proof passes, add one-shot screenshots at critical beats (Rush scene, Kino pickup, quarters bed, breach seal). Keep `instant_mode = true` for speed. | 1 | S6-09 | Screenshots capture Forward+ render at specified rooms; no visual regressions introduced. | — |

## Carryover / notes

- This sprint is purely headless validation, not visual polish.
- Production `Door.interact()` path remains active; we're not using a debug bypass.
- Route IDs are manually defined; no automated graph generation yet.

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] `playthrough_runner.gd` route reaches all E1 beats without crashes
- [ ] All eight assertions pass under `tests/run.sh`
- [ ] `GameState.episode_complete` is triggered from real mission code, not synthetic path
- [ ] GDScript compiles with zero parse errors in editor
- [ ] Committed to feature branch, merged to `godot`

## Notes

- Episode 1 content pass (objectives, plaque labels, Kino map) moves to post-proof backlog.
- This is the last system/proof sprint before Mission 2 kickoff.
- Current `e1_flow.gd` has ~160 assertions from sprint-005 retro; the new playthrough runner should align with those state mutations.