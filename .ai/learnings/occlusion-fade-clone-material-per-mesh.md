# Camera-occlusion fade must clone materials per mesh

**Goal.** Anything between the follow camera and the character becomes ~90% transparent.

**Trap.** Level meshes share a handful of materials (walls, pillars, columns). Setting `opacity` on a
hit mesh's material fades every sibling that shares it.

**Pattern.** Raycast camera → character chest each frame with `far = distance - 0.3`. On first hit,
stash the original material in a `Map`, assign `material.clone()` with
`transparent = true, opacity = 0.1, depthWrite = false`. When a mesh leaves the hit set, dispose the
clone and restore the original. Keep an explicit `occludable` list (exclude floor, reflector,
event horizon) so the ray is cheap.
