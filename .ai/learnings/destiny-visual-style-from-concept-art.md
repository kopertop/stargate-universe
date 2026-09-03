# Destiny visual style — derived from design/concept-art (use `web/gate-room/src/ancient.js`)

**Sources.** `concept-art/gate-room/gate-room-active.png`, `gate-room-dormant.png`, `gateroom-views-sheet.png`,
`materials/ancient-metal-pbr-sheet.png`, `destiny-ship/*`, `ui/destiny-restored-hud-layout.png`.

**Palette / rules (what "Ancient starship" means here):**
- Surfaces: near-black blue-grey gunmetal plates (`#0a0d11`–`#1b2028`), recessed dark seams, small rivets,
  faint bevel highlights, brushed grime. Never wood, olive/khaki, or beige lattice.
- Light: cold blue-white key + slits (`#cfe6ff`), very low ambient, a few spot downlights on the gate
  approach; **sparse amber runway lamps** along walkway edges are the only warm accent (plus emergency red).
- Gate: dark gunmetal ring with steel trim, **white-blue chevrons**, deep-blue horizon with white core;
  railed dais with steps in front; consoles flank the approach with **blue** screens.
- Doors: **octagonal frames** (chamfered corners), sliding halves.
- Exposure matters more than material: the same plates read cream/white when a room light is too strong.
  Keep `toneMappingExposure ≈ 0.95`, env intensity ≈ 0.15, metalness ≈ 0.35–0.5 (high metalness + env map
  turns dark floors silver).

**Performance rule.** One emissive slab per lamp is fine; one `PointLight` per lamp is not (40+ lights halved
the frame rate). Use emissive lamps + one warm point light per room.

**Gotcha.** A `python str.replace` that silently misses leaves the old olive windows in the scene; grep the
file for the removed identifier (`latticeTexture(`) after a restyle, and re-check in the browser.
