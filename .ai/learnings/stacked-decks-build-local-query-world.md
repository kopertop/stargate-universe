# Stacked decks: build in deck-local space, query in world space, and never let collision ignore height

**Context:** Adding Floor 1 to Destiny (`src/ship.js`) on top of a generator that assumed y = 0 everywhere. The first
run built fine, but on the upper deck the player froze in the middle of Hydroponics: `player.js` tested colliders in
x/z only (`b.min.y < 1.2`), so the gate room's walls twelve metres below were solid on the deck above.

**Lesson:** Give every deck its own `THREE.Group` at `y = floor × DECK_H`, call `updateMatrixWorld(true)` on it once,
then build rooms, doors and props in deck-local coordinates exactly as before. Everything that is *queried* against the
player must be world-space: colliders (from `matrixWorld`, free), anchors (`+ y0`), door/light positions (`wp`),
`roomAt(p)` (match the deck by `|p.y − y0| < DECK_H/2`). And any spatial test that was written for a flat world —
collision, "near a door", light culling — must include the y band, or the decks bleed into each other invisibly.
Elevators are routing edges, not doors: `route()` walks them and the driver rides instead of walking.

**Applies to:** any multi-level map added to a generator written for one level; teleport-style level transitions.
