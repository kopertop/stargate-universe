# Sprint 1 Retrospective — 2026-04-01

## Result: ALL TASKS COMPLETE (8/8)

### Completed
| ID | Task | Notes |
|----|------|-------|
| S1-01 | Event Bus | mitt-based, typed, error isolation, scoped cleanup |
| S1-02 | Ship State data model | 3-tier, power distribution, repairs, serialization |
| S1-03 | Destiny corridor scene | Gate room + corridor + storage bay |
| S1-04 | Ship atmosphere visuals | Dynamic lighting from Ship State power levels |
| S1-05 | Basic interaction (repair) | E key, condition feedback, subsystem indicators |
| S1-06 | Debug Ship State UI | Double-backtick overlay with systems/sections/subsystems/resources |
| S1-07 | Basic resource pickup | 3 supply crates in storage room, loot with E |
| S1-08 | Repair costs resources | 1 Ship Part per repair, insufficient feedback |

### Velocity
- Estimated: 6-8 hrs for Must Haves only
- Actual: All 8 tasks (Must + Should + Nice) completed in one session
- Conclusion: estimates were conservative. Sprint 2 can be more ambitious.

### What Went Well
- Event Bus and Ship State systems are clean, production-quality code
- Camera arm pull-in technique works great (professional standard)
- Ship State driving lighting creates satisfying repair feedback loop
- Resource economy creates meaningful decisions (loot → repair → lights)

### What Needs Improvement
- **Visibility in dark rooms** — recurring issue. Objects too dark without player light.
  Emissive materials on surfaces help but aren't enough alone. Player-attached
  light (intensity 2.5, range 15m) is the current solution.
- **Performance with lights** — every point light is expensive. Spotlights especially.
  Must stay under ~10 real lights. Use emissive materials for accent/glow.
- **Wall transparency approach was wrong** — raycasting + material opacity changes
  caused massive lag. Camera arm pull-in is the correct solution.
- **ggez runtime materials can't be modified via scene.traverse** — material
  overrides don't work reliably. Add visual overlays instead of modifying runtime meshes.

### Key Learnings (applied to memory)
- Camera arm pull-in > wall transparency (professional standard)
- Point lights < 10 total, use emissive for accents
- Player-attached light solves dark room visibility
- Ship State powerGrid.powered must be set explicitly
- ggez runtime materials need overlay approach, not modification

### Sprint 2 Recommendations
- Add wall physics colliders (currently walk-through)
- Improve corridor/door framing (visual door frames, lighting near openings)
- Start implementing the Kino Remote basic UI
- Add more rooms to explore with discoverable sections
