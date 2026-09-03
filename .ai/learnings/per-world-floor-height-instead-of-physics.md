# For flat levels with daises, a `floorAt(x, z)` function beats a physics engine

**Symptom.** After arriving on the planet the character's feet were inside the stone dais.

**Fix.** Each world exposes `floorAt(x, z)` (radial rings for the round dais, an AABB for the
Destiny dais). The controller takes `floorY`: when grounded it lerps `y` toward it (step up/down),
when airborne it lands on it. Spawn/arrival positions call `floorAt` too.

Cost: a couple of lines per world. It covers every step edge in the scene without introducing
Rapier/Crashcat for a scene that is otherwise XZ-only AABB sliding.
