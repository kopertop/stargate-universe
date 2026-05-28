# Sprint 5 Retrospective — 2026-05-21 → 2026-05-28

## Result: SCOPE COMPLETE — ORIGINAL PLAN + 7 PHASES OF EXPANSION

The original sprint-005 plan targeted **Mission 1 only**: connect rooms via
doors, ship a Kino pickup + UI, flesh out the hull breach + seal, fire a
mission-complete trigger. Acceptance criteria were "a fresh player can boot
the game and complete Mission 1 without hints."

That scope shipped in the first half of the sprint. The remaining sprint
window absorbed what `sprint-005.md` originally labelled "Out of Scope —
Sprint 6": the full **Episode 1 air-crisis arc** (Mission 1 → Mission 2 →
ongoing scrubber loop), end-to-end and headless-tested.

What follows is the actual ship list, grouped by the Phase letters we used
in the day-to-day commits, with the original task IDs cross-referenced where
they apply.

---

## What Shipped

### Original sprint-005 scope (Mission 1 — gate room + breach)

| ID | Task | Status | Notes |
|----|------|--------|-------|
| S5-01 | Wire rooms via doors + SceneRouter | ✅ | `room.gd` door system; rooms_discovered persists. |
| S5-02 | Kino Remote pickup | ✅ | Acquired in Eli's quarters; KinoRemote autoload flips. |
| S5-03 | Kino Remote UI (Godot port) | ✅ | Tab raises map/scout/objective; pause-while-raised. |
| S5-04 | Hull breach scene | ✅ | Vacuum SFX + accelerated O₂ drain + visible breach. |
| S5-05 | Seal-the-breach interaction | ✅ | Hold-E panel, vacuum fade, `breaches_sealed` flag. |
| S5-06 | Crate prefab | ✅ | Reusable interactable; one-shot log entries. |
| S5-07 | Mission-1 completion trigger | ✅ | Subsumed into the larger `complete_episode_air()` win-condition. |
| S5-08 | Objective HUD pin | ✅ | Always-visible bottom-left, drives off `GameState.objective`. |
| S5-09 | Extend `e1_flow.gd` | ✅ | Headless suite now sits at ~160 assertions covering every beat. |
| S5-10 | Browser-stack pivot retro | ✅ | Archived under `archive-browser-stack/`. |
| S5-11 | Idle ↔ walk anim blend | ✅ | Eli + crew running off Kenney mini-char AnimationPlayer + the project's idle/walk/sprint helpers. |
| S5-12 | Per-room ambient sounds | ✅ | Engine hum / vacuum wind / corridor bed. |
| S5-13 | Door open/close animation | ✅ | Door slide + auto-walk-through transition (`SceneRouter` fade). |

### Beyond the plan — Episode 1 expansion (Phases A → G)

| Phase | Beat | Key files | Headless cover |
|-------|------|-----------|----------------|
| A | Control-room consoles + interactability polish | `control_console.gd`, `room.gd` | `e1_flow.gd`, `quest_waypoint.gd` |
| B | Sleep cinematic + post-sleep red-alert hand-off | `bed.gd`, `cinematic.gd` (early), `ship_alert.gd` | `e1_flow.gd` |
| C | Broken-door mini-quest (fuse find/place) | `door.gd`, `fuse_pickup.gd`, `door_panel.gd` | `e1_flow.gd` |
| D | Dr Rush corridor → CO₂ scrubber reveal scene | `scrubber_rush.gd`, `co2_scrubber.gd`, `room.gd` | `e1_flow.gd`, `quest_waypoint.gd` |
| E | FTL drop + gate dial + Kino-first scout, then pilotable Kino drone, fleet control, deploy tracking | `gate_room.gd`, `kino_drone.gd`, `kino_remote.gd` (Kino Control page), `game_state.gd` deploy state | `e1_flow.gd`, `scene_boot.gd`, `e1_playthrough.gd` |
| F | Off-world lime mining: 10-min planet timer + reusable letterbox cutscene + away-team companions + discovered-lime tracking + compass HUD + team-assembled-at-gate walk-through | `planet_timer.gd`, `cinematic.gd`, `companion.gd`, `planet_compass.gd`, `resource_node.gd`, `planet.gd`, `gate_room.gd` | `e1_flow.gd`, `cutscene_shot.gd`, `gate_team_shot.gd` |
| G | Ongoing scrubber resource loop (decay → warn → critical, top-up with lime, live HUD) | `game_state.gd`, `co2_scrubber.gd`, `kino_remote.gd` System Status page | `e1_flow.gd` (9 dedicated assertions) |

### Cross-cutting infrastructure that fell out of the expansion

- **Reusable `Cinematic` autoload** — letterbox bars, subtitle caption, overhead
  cinematic camera, full-screen flash, automatic gameplay-HUD hide, armable
  "lift bars on the next scene change" for cuts that end via `change_to`.
- **Collision-free cinematic dash on `player.gd`** — actors can sprint to a
  target through terrain/triggers during a cutscene without snagging or
  tripping gate Area3Ds.
- **`Companion` actor** — Kenney mini-char-driven follower used by both the
  planet-side away team (follow + help-mine) and the gate-room assembled-team
  (stationary until the walk-through trigger fires). Brown per-instance tint
  pipeline so Greer reads as a distinct soldier without forking the colormap.
- **Save/load coverage expansion** — `lime_discovered`, `doors_traversed`,
  `deployed_kinos`, `scrubber_*` and all related signals round-trip; the
  `resume_probe` suite verifies a Phase-D restore lands the player in the
  breach corridor at the right quest step.
- **Screenshot harnesses** — `tests/shots/scene_shot.gd`, `cutscene_shot.gd`,
  and `gate_team_shot.gd` capture Forward+ stills of specific beats so visual
  regressions can be eyeballed without manually walking the game.

---

## Definition of Done

Original checklist + the de-facto expanded scope:

- [x] All original Must-Have tasks completed
- [x] A fresh player can play Mission 1 end-to-end without hints
- [x] EpisodeWrap card fires on mission completion (now from
      `complete_episode_air()` via `repair_scrubber_with_lime`)
- [x] `e1_flow.gd` smoke test extended and passing (~160 assertions)
- [x] Save/load round-trips Kino acquisition + breach + Phase-F/G state
- [x] All 6 headless suites green (save_registration, scene_boot, e1_flow,
      quest_waypoint, e1_playthrough, resume_probe)
- [ ] **Manual real-play end-to-end (pre-PR)** — see "What's Left" below

---

## Velocity

| | Estimate | Actual |
|---|---|---|
| Original sprint scope (S5-01 → S5-13) | ~13–17 hrs | First ~half of the sprint window |
| Phase A → G expansion | — (out of scope per the original doc) | Remainder of the sprint window |
| Headless test growth | "Add ~4 assertions to e1_flow" | e1_flow went from ~60 → ~160 assertions; added `quest_waypoint.gd`, `resume_probe`, three screenshot harnesses |

The original estimates were correct — they just didn't account for the
project deciding to absorb Sprint 6 into the same window once Mission 1
shipped quickly.

---

## What Went Well

- **The `Phase A → G` letter scheme** worked as a lightweight feature-flagging
  / commit-message convention. Each commit message says exactly which slice
  it advanced, which made the 25-commit branch easy to read at the end.
- **RCP (review → commit → push) cadence between phases** caught two
  legitimate quality issues mid-sprint (companion auto-mining trivialising
  the objective; compass `_draw` missing an `is_instance_valid` guard) that
  would otherwise have shipped.
- **Per-feature screenshot harness pattern** (`tests/shots/<name>.gd`) — far
  faster than walking the game to verify cutscenes / HUDs / cinematic camera
  framing. The same harness was reused for cross-scene cutscene capture, the
  landing-zone overhead, and the gate-room assembled-team beat.
- **Reusable Cinematic autoload + cross-scene "close on next transition"** —
  built once for the planet-departure beat, immediately payable for future
  cutscenes that end with a `change_to`.

---

## What Needs Improvement

- **Real-play coverage of real-time loops** — anything driven by `delta`
  (scrubber decay, cinematic dash) is hard to validate in `-s` SceneTree
  scripts because physics steps many times per render frame. Two of the
  late bugs (`cutscene_shot` over-stepping the player past every distance
  threshold in one frame; `gate_team_shot` reading a const via `Object.get`)
  surfaced only when comparing the captured PNG to expectations. The
  takeaway: trust unit tests for state, but always capture a still + watch
  a live frame for time-driven beats.
- **`Object.get("CONST_NAME")` silently returns null** — burned one test
  cycle on this. Extracted as
  `~/.claude/skills/gdscript-object-get-skips-consts/` so it doesn't bite
  the next harness.
- **The sprint doc was stale by the second half of the sprint.** This retro
  is the correction; future sprints should re-scope mid-flight (or open a
  follow-on sprint doc) when the actual ship list outgrows the plan instead
  of accumulating a single 25-commit branch.

---

## Key Learnings (committed to memory or extracted as skills)

- **`Object.get` does NOT read consts / enums / static funcs** —
  `gdscript-object-get-skips-consts` skill.
- **Kenney Mini-Characters all share one peach skin column** — to vary skin
  tone without a custom colormap, duplicate the material reference and
  multiply `albedo_color` per-instance. Extracted as
  `godot-kenney-mini-char-skin-tone-tint`.
- **Cinematic-dash actors that disable `collision_layer` must NOT have their
  collision restored mid-cutscene** — they'd trip the destination gate's
  Area3D. The cinematic ends with a `change_to` that frees the actor anyway.
  Extracted as `godot-cinematic-collision-free-dash`.
- **Headless `-s` SceneTree scripts defer node lifecycle callbacks**
  (`_ready`, `_enter_tree`) until a frame ticks. Group membership / signal
  connections that the synchronous test needs immediately should happen in
  an explicit `setup()` method the caller invokes after `add_child`, not
  inside `_ready`.

---

## What's Left Before the PR

1. **Manual end-to-end real-play of the expanded E1 arc** — the bits with
   only headless coverage that should be eyeballed live:
   - Team-walk-through coroutine at the ship gate (only the assembled trio
     was captured statically; the staggered walk + `visible=false` arrival
     + gate re-open hand-off hasn't been watched).
   - Kino remote prop +45° tilt: confirm Eli sees the screen, camera sees
     the back.
   - Scrubber decay running on real wall-clock for a few minutes; top-up
     interaction; warn / critical thresholds firing.
   - `EpisodeWrap` card actually fires on `scrubber_repaired`.
2. **Open the Godot editor once** to confirm zero parse errors (definition-
   of-done line 95). All work was validated headless; the editor's static
   analyzer is stricter.
3. **Open the PR** — `gh pr create --base godot --head feature/e1-act2-broken-air`
   with a phase-grouped summary linking back to this retro.

---

## Sprint 6 Recommendations

- **Episode 2 arc design** — original sprint-005 deferred "stargate dial-out
  → lime planet → CO₂ scrubbers" to Sprint 6. The mechanics are now built
  (Phases E, F, G), so Sprint 6's narrative work is the next planet, the
  next crisis, and the long-arc resource pressure that the ongoing scrubber
  loop now creates.
- **Quest system rewrite (#36)** — explicitly deferred per project memory
  ("don't half-migrate; data-driven numeric-step refactor planned post-E1").
  Sprint 6 is the right moment if E1 ships cleanly here.
- **WoW-style UI direction (#31)** — currently the dialog window is already
  WoW-style; the next pass is the broader HUD/menu pass.
- **Manual playtesting cadence** — formalise a "watch every beat once per
  sprint" gate before merging back to `godot`.
