# Sprint 2 — 2026-04-15 to 2026-04-28

## Sprint Goal

Harden the exploration loop: add wall colliders so Destiny feels solid, expand the
ship with more explorable sections, and start the Kino Remote (diegetic menu) so the
player can check ship status without the debug overlay.

## Capacity

- Total days: 14 calendar days
- Available hours: ~6-8 hrs (a few hours per week)
- Buffer (25%): ~1.5 hrs reserved for debugging/unplanned work
- Productive hours: ~5-6 hrs

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-01 | **Wall physics colliders** — Add Crashcat rigid bodies to corridor walls, floors, and ceilings so the player can't walk through walls. | 1.5 | S1-03 | Player collides with walls in all rooms. No clipping through geometry. Collider mesh matches visual mesh within tolerance. | ship-exploration.md |
| S2-02 | **Corridor/door framing** — Visual door frames with accent lighting near openings. Doors that visually close/open based on ship state (even if no animation yet). | 1 | S2-01 | Doorways have visible frames. Frames have accent lighting (emissive strips). Closed doors block player movement when section is unpowered. | ship-exploration.md, ship-atmosphere-lighting.md |
| S2-03 | **Expand ship: Engineering section** — Add 2-3 more rooms (engineering bay, corridor junction, auxiliary power room) with power conduits and subsystems to repair. | 1.5 | S2-01 | Player can navigate from gate room through corridors to engineering. At least 2 new repairable subsystems. Resource crates in engineering. | ship-exploration.md |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-04 | **Kino Remote: Ship Status tab** — Diegetic handheld device showing section power levels and subsystem conditions. Replaces debug overlay for ship info. | 2 | S1-02 | Press Tab (or dedicated key) to raise Kino Remote. Shows current section power, atmosphere, subsystem conditions. Smooth raise/lower animation. | kino-remote.md |
| S2-05 | **Minimap in Kino Remote** — Rudimentary top-down map showing discovered rooms and player position. | 1 | S2-04 | Kino Remote shows a map tab. Visited rooms appear on map. Player blip shows current position. Undiscovered rooms are dark/hidden. | kino-remote.md |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Design Doc |
|----|------|----------|-------------|---------------------|------------|
| S2-06 | **Door open/close animation** — Ancient-style sliding door animation when power state changes. | 0.5 | S2-02 | Doors animate open/close over ~0.5s. Sound effect on open/close. | — |
| S2-07 | **Footstep audio** — Different footstep sounds per floor material (metal grate vs smooth floor). | 0.5 | S2-01 | Walking plays footstep sounds. Different sounds on different surfaces. | — |

## Carryover from Previous Sprint

- Unpushed commit on main: `chore: add package-lock.json to .gitignore` — needs kopertop push access

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Crashcat collider authoring is tedious for complex geometry | Medium | Medium | Use simplified box/capsule colliders instead of mesh colliders. Programmatic placement from scene metadata. |
| Kino Remote UI complexity (diegetic device, not flat HUD) | Medium | High | Start with flat overlay inside a textured frame. Add 3D device model later. Focus on data display, not form factor. |
| Engineering section content pipeline (new rooms, assets) | Low | Medium | Reuse existing corridor geometry. Variation through lighting and props, not new models. |

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] Player cannot walk through walls anywhere
- [ ] At least 5 explorable rooms (gate room + existing 2 + engineering 2-3)
- [ ] Doors respond to ship power state
- [ ] Kino Remote shows ship status (if Should Have completed)
- [ ] Code compiles with zero TypeScript errors
- [ ] Committed to feature branch, pushed to remote

## Notes

Sprint 1 retro showed velocity exceeded estimates — all 8 tasks in one session.
Sprint 2 raises scope with wall colliders (a known pain point) and the first
diegetic UI. If wall colliders prove harder than expected, the Kino Remote
slides to Sprint 3.