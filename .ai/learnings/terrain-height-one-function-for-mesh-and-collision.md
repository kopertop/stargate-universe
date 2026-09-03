# Terrain: one height function must drive both the mesh and the collision

**Symptom.** On the planet the character floated at y = 0 while walking over dunes; the ground mesh
rose and fell but the feet did not.

**Cause.** The dune displacement was computed inline while building the `PlaneGeometry` vertices,
and `floorAt(x, z)` only knew about the dais rings, returning 0 everywhere else. Two sources of truth.

**Fix.** `terrainHeight(x, z)` is the single definition. The geometry loop calls it per vertex, and
`floorAt`, the camera clamp, and rock/obelisk placement all call the same function.

**Gotcha.** A `PlaneGeometry` rotated -90° about X maps local `(x, y)` to world `(x, -y)`. Pass
`-pos.getY(i)` as `z` when sampling, or pick an even function in z as this one is.

**Test.** Walk perpendicular to a dune ridge and log `[x, z, y, floorAt(x, z)]` every 0.5 s. Walking
along `x = 0` is a valley of `sin(x·0.08)` and proves nothing.
