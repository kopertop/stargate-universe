# Merge static wall pieces per room — and mind indexed vs non-indexed geometry

**Why:** 25 rooms × (4 walls split around doors + arch lintels) produced ~1,200 meshes and 280–560 draw calls per frame.
Merging each room's wall pieces into one mesh per material cut the corridor view to 77 draw calls (3.5×) with no visual change.
Colliders stay per piece (computed before the merge), so gameplay is untouched; occlusion fading now fades a room's walls
as a unit, which is fine since the follow camera only ever clips its own room's walls.

**Gotcha:** `BufferGeometryUtils.mergeGeometries` refuses to mix indexed (BoxGeometry) and non-indexed (ExtrudeGeometry)
inputs — "All geometries must have compatible attributes; make sure index attribute exists among all geometries, or in none
of them" — and the failure surfaces later as `Cannot read properties of null (reading 'morphAttributes')`. Call
`toNonIndexed()` on the indexed ones first (and bake `matrixWorld` into each clone before merging).

**Also:** the in-app Browser pane keeps console messages across reloads, so an error you just fixed still shows up after
the reload. Check `window.__dbg` exists (the module ran to completion) rather than trusting the console list.
