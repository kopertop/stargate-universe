# Generate ship geometry from the canonical layout JSON, not hand-placed rects

**Context:** The web build had 5 hand-placed rooms; the Godot build in the reference video used the full deck from
`data/ship_layout.json` (29 rooms) + `data/room_connections.json`. Rebuilding the web deck by reading the same files
gave the same floor plan in one pass, and the Kino Remote deck map fell out for free (rects → SVG).

**What mattered:**
- JSON units are 5 cm (gate room 800×400 → 40×20 m). Map JSON X → world −Z so the gate sits at the far end of its
  room and exits leave toward +Z; JSON Y → world X. Derive every anchor from the room rect (`at(u,v)`), never absolutes.
- Compute doors from *shared edges* between rects, not from the `dir` field — one declared connection was geometrically
  on a different wall than its `dir` said. Rooms with no declared connections (the ring corridors) get a door on every
  shared edge, which is exactly what the drawn map showed.
- Let the same generator build the gate room's walls/ceiling so its doors come from data; the hand-authored module
  only dresses the interior. Keep interior props off the wall surfaces (walls are inset WALL_T into each room).
- Lights: 25 rooms × (powered + emergency) point lights = 156. Visible light count drives shader cost — keep only the
  nearest ~6 live (sorted by distance) or fps halves.
- Wall-mounted props must sit at `WALL_T + ε` from the room boundary; `WALL_T/2` is inside the wall.
- Make the demo driver route over the door graph (BFS on doors) instead of hardcoded coordinates; it survived the
  layout swap unchanged apart from anchor names.
- `THREE.Path.absarc(..., aClockwise)`: `true` sweeps *decreasing* angle. A quarter arc from 0→π/2 with `true` loops the
  long way round and produces a huge blob leaf — check the direction per side when mirroring a shape.
