# Never freeze the player at a transition boundary; overlap the effect with the last action

**Symptom.** Walking into the event horizon produced a brief "stuck" frame: the controller stopped
at the gate plane, then the dive/whiteout started.

**Fix.** Trigger travel ~1.1 m before the plane and let the character keep auto-walking forward
while a disintegration takes over: sample world-space points on the posed skin with
`SkinnedMesh.getVertexPosition(i, v).applyMatrix4(mesh.matrixWorld)`, emit ~2600 particles/s toward
the gate, and ramp material opacity 1 → 0 (set `transparent` only while fading). The ripple fires
when the root actually crosses the plane. The camera follows normally for the first 0.45 s, then
dives.

General rule: whatever the player was doing must visibly continue into the transition.
