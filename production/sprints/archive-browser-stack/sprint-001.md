# Sprint 1 — 2026-04-01 to 2026-04-14

## Sprint Goal

Build a playable exploration loop: walk through a small section of Destiny with
doors that respond to ship state, lights that reflect power levels, and a basic
interaction system. First taste of the game's core feel.

## Capacity

- Total days: 14 calendar days
- Available hours: ~6-8 hrs (a few hours per week)
- Buffer (25%): ~1.5 hrs reserved for debugging/unplanned work
- Productive hours: ~5-6 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S1-01 | **Implement Event Bus** — mitt-based typed GameEventBus with scopedBus helper, error isolation, re-entry protection | 1 | None | Typed events compile. Subscribe/publish works. Scoped cleanup on scene unload. Re-entry depth limit logged. | event-bus.md |
| S1-02 | **Implement Ship State data model** — Three-tier structure (systems, sections, subsystems) with condition values and power distribution | 2 | S1-01 | Ship-wide systems track condition. Sections track power/atmosphere. Subsystems track condition. Power distributes by priority. `ship:*` events fire on changes. | ship-state-system.md |
| S1-03 | **Destiny corridor scene** — Build a 2-3 room ship section in ggez World Editor (or programmatically). Gate room + corridor + one explorable room with a door, a power conduit, and a lighting panel. | 1.5 | S1-02 | Player can walk through 3 connected spaces. Door opens when section is powered. Lights respond to power level. At least one repairable subsystem. | ship-exploration.md |
| S1-04 | **Ship atmosphere visuals** — Dynamic lighting per section driven by Ship State. Emergency strips at low power, Ancient glow at high power. | 1 | S1-02, S1-03 | Lights dim/brighten with power level. Emergency red below threshold. Ancient glow above threshold. Smooth transitions. | ship-atmosphere-lighting.md |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S1-05 | **Basic interaction system** — Radial menu on interactables (subsystems). "Repair" action that improves condition. | 1 | S1-02, S1-03 | Walk up to a broken conduit, hold E, see "Repair" option, select it, condition improves, lights brighten. | player-controller.md |
| S1-06 | **Debug Ship State UI** — Temporary overlay showing section power, system conditions (for development/testing, not the Kino Remote) | 0.5 | S1-02 | Toggle with double-backtick (existing debug mode). Shows power level, atmosphere, subsystem conditions for current section. | — |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S1-07 | **Basic Resource pickup** — Supply cache in the explorable room. Interact to collect Ship Parts. | 0.5 | S1-05 | Cache visible in room. Interact → "Collect" → resource added to pool. Cache shows depleted. | resource-inventory.md |
| S1-08 | **Repair costs resources** — Repair action consumes Ship Parts instead of being free | 0.5 | S1-05, S1-07 | Repair requires Ship Parts. Insufficient parts shows "Need X Ship Parts". | ship-state-system.md, resource-inventory.md |

## Carryover from Previous Sprint

N/A — first sprint.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| ggez scene authoring takes longer than expected (no World Editor access) | Medium | High | Use programmatic scene construction (proven in gate room prototype). Fall back to Three.js + runtime JSON. |
| Ship State data model complexity (three tiers, power routing DAG) | Medium | Medium | Start with simplified flat model (sections with power levels, no DAG routing). Add conduit routing in Sprint 2. |
| Limited hours — scope may not fit | Medium | Low | Must Haves are ~5.5 hrs, within budget. Should/Nice are stretch goals. |

## Dependencies on External Factors

- None — all work is self-contained using existing ggez stack.

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] Player can walk through a multi-room Destiny section
- [ ] Lights visibly respond to ship power state
- [ ] At least one interactable subsystem (repair action)
- [ ] Event Bus is implemented and tested
- [ ] Ship State data model is functional
- [ ] Code compiles with zero TypeScript errors
- [ ] Committed to feature branch, pushed to remote

## Notes

This is the first sprint and establishes velocity. Expect the estimate to be
wrong — the primary goal is learning how fast we actually move, not hitting a
specific feature count. If Must Haves take all available time, that's a
successful sprint that tells us our real capacity.
