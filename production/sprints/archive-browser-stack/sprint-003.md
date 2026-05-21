# Sprint 3 — 2026-05-07 to 2026-05-20

## Sprint Goal

Land the visual fidelity & cinematic pass: ship the destiny-cinematic-glb branch
(opening cinematic + concept-art parity across scenes), then unlock content authoring
by adding the first NPC and a save/load round-trip so playtesting can begin.

## Capacity

- Total days: 14 calendar days
- Available hours: ~6–8 hrs (a few hours per week, holding pattern)
- Buffer (25%): ~1.5 hrs reserved for visual-polish iteration & PR review
- Productive hours: ~5–6 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|--------------------|------------|
| S3-01 | **Land `feature/destiny-cinematic-glb`** — Resolve outstanding scene-by-scene visual deltas (~50 converged-loop ticks already match concept art within procedural-geometry constraints). Open PR, review, merge. | 1.5 | — | All 6 scenes pass concept-art comparison via `scripts/capture-screenshots.ts` (15/15). PR merged to main. Sprint-002 retro written. | ship-atmosphere-lighting.md |
| S3-02 | **Save/load round-trip** — Persist ship state, player position, scene id, inventory to localStorage. Load slot restores into a running game without crash. | 1.5 | S3-01 | Press F5 → save; restart → load slot → world matches saved state. Two-slot UI in start menu. | save-load-interface.md |
| S3-03 | **First NPC: Lt. Scott in gate room** — VRM character placed in destiny-gate-room with idle animation and one-line proximity dialogue trigger ("This is the gate room…"). Uses existing dialogue stub. | 1.5 | S3-01 | NPC visible & animated in gate room. Walking within 3 m fires dialogue overlay. NPC does not block player movement. | crew-dialogue-choice.md, vrm-model-integration.md |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|--------------------|------------|
| S3-04 | **Sprint-002 retro** — Write `sprint-002-retro.md` capturing the actual scope (cinematic, VRM pipeline, audio catalog, start menu) vs the original plan (wall colliders, Kino Remote). Note carryover. | 0.5 | — | File exists in `production/sprints/`. Lists shipped tasks, deferred tasks, key learnings. |
| S3-05 | **Kino Remote: Ship Status tab (carryover from S2-04)** — Diegetic status overlay raised by Tab key, replaces double-backtick debug overlay for player-facing info. | 2 | S3-01 | Tab raises overlay. Shows section power, atmosphere, subsystems. Lower on Tab again. | kino-remote.md |
| S3-06 | **Wall colliders sweep (carryover from S2-01)** — Confirm Crashcat colliders cover all current rooms (gate room, corridor, scrubber, engineering if landed, desert planet). | 1 | S3-01 | Player cannot walk through walls in any scene. Verified by manual walk-through in each scene. | ship-exploration.md |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|--------------------|------------|
| S3-07 | **Concept-art capture diff harness** — Extend `scripts/capture-screenshots.ts` to diff against a stored baseline; flag scenes whose pixel-difference exceeds a threshold. | 1 | S3-01 | CI/local script reports per-scene diff %. Baseline committed. | — |
| S3-08 | **Reflector-based wet-floor pass for gate room** — Replace runtime.json grid with planar Reflector (deferred from prior loop ticks). | 1 | S3-01 | Floor reflects ring pillar without revealing the runtime.json grid issue. | ship-atmosphere-lighting.md |

## Carryover from Previous Sprint

| Task | Reason | New Estimate |
|------|--------|-------------|
| Kino Remote (S2-04) | Cinematic & VRM work consumed Sprint 2 capacity | 2 hrs (S3-05) |
| Wall colliders sweep (S2-01) | Partially landed during physics fixes; needs verification | 1 hr (S3-06) |
| Minimap in Kino Remote (S2-05) | Depends on Kino Remote — defers to Sprint 4 | — |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Cinematic branch has unresolved visual deltas that block PR | Low | Medium | 50+ converged-loop ticks confirm parity; pixel-diff harness (S3-07) catches regressions |
| Save/load surfaces ship-state serialization gaps not exposed by current Zod schemas | Medium | Medium | Validate roundtrip with Zod parse; treat unknown fields as fatal in dev, soft-warn in prod |
| First NPC reveals VRM-pipeline edge cases (animation retargeting, LOD) at runtime | Medium | Medium | Reuse `crew-character-manager` paths already exercised by opening cinematic |
| Loop continues to consume cycles with no visual deltas | High | Low | Sprint 3 supersedes the loop; cancel `/loop` when S3-01 PR is opened |

## Dependencies on External Factors

- None. All work is local-codebase + local-asset.

## Definition of Done for this Sprint

- [ ] `feature/destiny-cinematic-glb` merged to main
- [ ] Sprint-002 retro written
- [ ] Save/load round-trip works for at least one slot
- [ ] One named NPC visible & interactable in gate room
- [ ] Code compiles with zero TypeScript errors
- [ ] All scenes pass concept-art comparison
- [ ] No S1/S2 bugs in delivered features

## Notes

The /loop visual-polish exercise has converged — Sprint 3 takes the work to merge
and pivots toward gameplay-content unlocks (NPC, save/load) so Sprint 4 can begin
the dialogue / quest authoring loop. Pre-production stage continues; no playtest
target this sprint.
