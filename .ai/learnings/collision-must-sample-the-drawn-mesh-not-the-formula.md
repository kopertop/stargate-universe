# Terrain collision must sample the drawn mesh, not the analytic formula

**Symptom.** After unifying the height function, the character still floated a few cm on dune crests
and sank a few cm in troughs.

**Cause.** The GPU draws a piecewise-linear surface between vertices. A smooth `sin·cos` formula is
above that surface on crests (concave down) and below it in troughs (concave up). With 4 m cells the
gap measured up to 3.3 cm.

**Fix.** Keep the per-vertex heights in a `Float32Array` when building the `PlaneGeometry` and
interpolate them with the SAME triangle split the geometry uses. PlaneGeometry splits each quad into
`(a,b,d)` and `(b,c,d)` where `a=(ix,iy)`, `b=(ix,iy+1)`, `c=(ix+1,iy+1)`, `d=(ix+1,iy)`; the diagonal
is `u + v = 1` in cell-local coordinates.

**Proof.** Debug overlay (`B`): raycast straight down onto the ground mesh and print
`feet − mesh`. At crest, trough, slope and mid-dune test points it reads exactly 0. Also snap the
grounded `y` to the floor query instead of lerping, or a running character shows a 1 cm lag.
