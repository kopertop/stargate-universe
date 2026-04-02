# Sprint 2 — 2026-04-01 to 2026-04-14

## Sprint Goal

Expand the exploration experience: add wall physics so rooms feel solid, create
visual door frames between areas, implement basic Kino Remote UI (quick-check
mode), and add more explorable sections with discoverable content.

## Capacity

- Total days: 14 calendar days
- Available hours: ~8-10 hrs (Sprint 1 showed we move faster than estimated)
- Buffer (20%): ~2 hrs
- Productive hours: ~6-8 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-01 | **Wall physics colliders** — Add Crashcat colliders to corridor/storage walls so player can't walk through them | 1.5 | S1-02 | Player bounces off all walls. No walk-through. | player-controller.md |
| S2-02 | **Door frame geometry** — Visual door frames at room transitions (gate room→corridor, corridor→storage). Archway meshes with emissive edge lighting. | 1 | S1-03 | Doorways are visually obvious. Player can see the transition between rooms. | ship-exploration.md |
| S2-03 | **Kino Remote quick-check** — Tab key shows small overlay: current Ship Parts count, active section name, subsystem conditions for current room. Game continues while displayed. | 2 | S1-01, S1-02 | Tab shows overlay. Gameplay continues. Shows resources + section info. Release to dismiss. | kino-remote.md |
| S2-04 | **Section discovery** — Entering a new section triggers discovery event, Kino Remote logs it, debug overlay shows explored/unexplored status | 1 | S1-02, S2-03 | Walking into corridor/storage for first time fires event. Section marked explored permanently. | ship-exploration.md |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-05 | **Additional rooms** — Add 2 more explorable rooms branching from the gate room (e.g., observation deck, crew quarters) with unique subsystems and crates | 2 | S2-01, S2-02 | 5 total rooms. Each has unique subsystems and at least 1 crate. | ship-exploration.md |
| S2-06 | **Ambient audio** — Basic ambient ship hum that scales with power level. Gate activation sounds. Repair feedback sound. | 1 | S1-04 | Ship hum plays. Volume scales with section power. Gate dial has audio. | ship-atmosphere-lighting.md |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-07 | **Degradation tick** — Subsystems slowly degrade over time, requiring ongoing maintenance | 0.5 | S1-02 | Subsystem conditions decrease slowly. Player must re-repair periodically. | ship-state-system.md |
| S2-08 | **Power priority via debug UI** — Temporary UI to reorder ship system priorities and see power redistribution | 1 | S1-02 | Can change priority order. Power redistribution updates visually. | ship-state-system.md |

## Carryover from Sprint 1

None — all tasks completed.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Crashcat programmatic collider API unknown | Medium | High | Research ggez physics docs. Fallback: add walls to runtime JSON as physics brushes. |
| Audio integration with ggez unknown | Medium | Medium | Use basic Web Audio API / Howler.js if ggez audio isn't straightforward. |
| Kino Remote UI complexity creep | Low | Medium | Keep it to quick-check only (no full mode this sprint). |

## Dependencies on External Factors

- May need to research Crashcat collider API for programmatic wall physics.

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] Player cannot walk through any walls
- [ ] Doorways are visually framed and obvious
- [ ] Kino Remote quick-check shows relevant game state
- [ ] Section discovery works and persists
- [ ] Code compiles with zero TypeScript errors
- [ ] Committed to feature branch, pushed to remote
