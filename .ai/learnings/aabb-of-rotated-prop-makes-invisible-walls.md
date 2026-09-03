# Box3 of a rotated prop is an invisible wall; use a circle/sphere collider

**Symptom.** Invisible barriers between rocks on the planet.

**Cause.** `new Box3().setFromObject(rock)` on a randomly rotated dodecahedron is an axis-aligned
bounding box up to ~1.7× the rock's visible radius, and the AABB slide code stops the player at it.

**Fix.** For roundish props push out along the contact normal from a circle: `{ circle: true, x, z, r }`
with `r ≈ 0.85 × scale`. Keep AABBs for actual boxes (walls, obelisks, consoles). A collider list can
mix both shapes; the slide loop skips circles and a second loop resolves them.
