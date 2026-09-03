# OpenBot (Mixamo-style) loop clips carry hips translation; strip it

**Symptom.** Walk/run loops drift the mesh away from its root when the controller also moves the root.

**Fix.** After `GLTFLoader`, filter out tracks whose name ends with `hips.position` from every clip
before creating actions. The controller owns world position; clips only rotate bones.

```js
for (const a of gltf.animations) a.tracks = a.tracks.filter((t) => !t.name.endsWith('hips.position'));
```

Same idea as the Godot rifle-combat showcase ("strip hip location on shoot/loco") in
`models/mixamo_openbot/AGENTS.md`.
