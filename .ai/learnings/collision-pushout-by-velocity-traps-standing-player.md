# Per-axis box push-out chosen by velocity sign traps a player who is already inside

**Context:** Hands-free runs stalled in the South Corridor with `KeyW` held and the player frozen at (24.1, −18.4) — inside
the CO2 scrubber's 0.4 m collider, flush against the corridor wall. It only happened in a throttled tab (sub-stepped, large
`dt`) or the visible pane at 23 fps; the hidden smoke tab passed five times in a row.

**Lesson:** `player.js` resolved each axis with `p[axis] = vel[axis] > 0 ? b.min − r : b.max + r`. With `vel.x === 0` the
ternary always picked `b.max.x + r`, i.e. *through* the prop into the wall; the wall then pushed the player back into the
prop, and the two boxes traded him every frame with zero net motion. When the player is not moving along an axis, exit by the
**nearest face** (`p < centre ? min − r : max + r`); keep the velocity rule only for real hits. Large steps (hidden-tab
sub-stepping, teleports, corner squeezes between a door frame and a wall-mounted prop) will put a capsule inside a box
eventually — the resolver must be able to get out of any box, not just stop at one.

**Applies to:** any hand-rolled AABB slide (player, NPC walkers, Kino), and any autoplay stall where `keys` shows a held
direction but the position does not change.
