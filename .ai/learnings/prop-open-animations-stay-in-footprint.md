# A prop's open/deploy animation must stay inside its own footprint (or above its neighbours)

**Context:** Redesigning Destiny's salvage crates (`src/components.js`) so the lid visibly comes off. The first Ancient
lid slid 1.6 m sideways and dropped to the floor — straight into the Pelican case placed next to it in the gate room.
Crates are authored in room fractions (`u, v`) with no knowledge of each other, and level editors will keep packing them.

**Lesson:** Give every moving part a resting pose that never leaves the prop's own footprint, or that only overhangs above
the tallest neighbour it could sit beside. Lift-then-split (the halves slide out at rim height + 0.34 m) clears a 0.74 m
Pelican case and another crate's rim; a hinged lid stays inside the depth of the box; anything that translates along the
floor will eventually intersect the next prop or a wall. Drive the pose through a single `setOpen(k)` (0→1) so the same
function serves the 0.9 s animation on interaction and the instant `k = 1` restore on save/load.

**Applies to:** crate lids, relay covers, elevator leaves, any deployable furniture the editor can place adjacent to walls
or other props.
