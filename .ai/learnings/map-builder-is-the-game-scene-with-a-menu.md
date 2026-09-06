# The map builder is the game scene with a build menu, not a separate editor

**Context:** Asked for a hand-authoring tool for ship decks/rooms/planets. A 2D plan editor was built first; the user
wanted a first-person 3D fly-through instead. The rewrite was cheap because everything was already a factory.

**What made it cheap:**
- Rooms, doors and props were already built from data by pure factories (`createShip`, `COMPONENTS`, `createDestination`).
  The editor imports the same modules, so what you place is exactly what the game renders — no editor-only renderer to
  keep in sync. Any edit just disposes the ship group and calls `createShip` again (25 rooms rebuild in well under a frame's
  worth of noticeable time).
- Props are a registry (`components.js`) with `size`, `defaultAnchor` and `build(ctx, worldPos, spec)`; specs are
  room-relative fractions `{type,u,v,ry,anchor}`. Per-type defaults live in the same file, so rooms without a `props`
  array still furnish themselves, and editing one materialises the defaults into the layout row.
- Picking: tag prop meshes (`userData.prop = {roomId, spec}`) and room floors (`userData.roomId`) at build time; the
  editor raycasts those. The gate hall has no ship floor, so an invisible pick target is added — three's Raycaster does
  not skip invisible meshes.
- Pick where the mouse is, not where the crosshair is (only use the crosshair under pointer lock). The first version
  raycast from screen centre and "click on the floor" silently selected whatever the camera looked at.

**Round-tripping repo data:** a save must not reformat. Sniff the existing file's indentation and keep `ensure_ascii`
matching what's on disk (these files escape `—` as `—`), otherwise every save produces a whole-file diff.

**Dev write endpoint:** an unauthenticated PUT is fine for a local tool only if it binds `127.0.0.1` and whitelists
paths with a regex; the security reviewer flagged the first version that bound all interfaces.
