# Rough-metal MeshStandardMaterial renders black without an environment map

**Symptom.** The stargate ring (metalness 0.8) looked fine in the dim gate room but pure black in the
sunlit desert scene.

**Cause.** Metals get almost all their colour from reflections. With no `scene.environment` there is
nothing to reflect, so direct lights alone leave them dark.

**Fix.** One neutral env map for every scene:

```js
const env = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
scene.environment = env; scene.environmentIntensity = 0.35; // tune per scene
```
