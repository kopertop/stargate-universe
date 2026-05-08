# Animation Assets

Mixamo and VRMA animation clips used by the VRM characters.

## How these get used

- **Player (Eli)**: loaded by `src/systems/vrm/vrm-player-animation-controller.ts`
  from `<characterBasePath>/<name>.<ext>`. Clip names the controller probes:
  `idle`, `walk`, `run`, `jump`, `strafe-left`, `strafe-right`, `repair`,
  `getting-up`. First matching extension (`fbx`, `glb`, `vrma`) wins.
- **Cinematic crew**: by default use the procedural stand-up sequence in
  `src/systems/vrm/vrm-standup-sequence.ts`. If you want higher-fidelity
  mocap motion, download Mixamo clips and drop them here — the cinematic
  will prefer them once the loader wiring lands (currently procedural only).
- **Character viewer**: accepts any animation by full URL via
  `?scene=character-viewer&animation=/assets/animations/<file>.glb`.

## Mixamo download recipe for the "arrival" stand-up sequence

The opening cinematic throws crew through the gate. The user-facing motion
brief is: _face-down → push up onto hands and knees → kneel with hands on
head → shake head (disoriented) → stand up_.

Recommended Mixamo clips (visit <https://www.mixamo.com>, search the animation
library by name, download as **FBX for Unity (.fbx)** — yes, for this
project too; the retargeter in `src/systems/vrm/vrm-animation-retarget.ts`
handles it):

| Purpose | Mixamo name | Save as | Notes |
|---|---|---|---|
| Primary prone-to-stand | `Standing Up` or `Getting Up` | `getting-up.fbx` | Check that it starts lying down, not mid-animation |
| Alternative (zombie style, slow, disoriented — fits the "thrown through wormhole" vibe) | `Zombie Stand Up` | `getting-up.fbx` | Slower, more natural for our use case |
| Disoriented idle (for the "hands on head" moment) | `Dizzy Idle` or `Confused` | `dizzy-idle.fbx` | Optional — used after stand-up completes |
| Head shake | `Shake Head No` | `shake-head.fbx` | Optional — procedural fallback is fine here |

### Conversion step (optional but recommended)

FBX loads slower than GLB. Convert with Blender or the
`mixamo-fbx-to-glb-threejs-expo` skill in `~/.claude/skills/`:

```
# Blender headless
blender --background --python convert-mixamo.py -- input.fbx output.glb
```

Then place the `.glb` in this directory with the filename shown in the table.

### What each character uses

| Character | base path | getting-up source | idle source |
|---|---|---|---|
| Eli (player) | `assets/characters/eli-wallace/` | `eli-wallace/getting-up.glb` | `eli-wallace/idle.glb` |
| Rush NPC    | (loaded via VRM character manager) | — | uses shared idle |
| Cinematic crew (Scott/Rush/TJ/Young) | — | procedural (vrm-standup-sequence.ts) | — |

You can share one `getting-up.glb` across crew by symlinking, or drop per-character
variants to give each crew member a slightly different recovery cadence.

## Existing clips in this directory

- `standing-short-idle.glb` — short idle loop, currently used as fallback idle
- `unarmed-idle-01.glb` — longer idle with subtle animation
- `walking-forward.glb` — basic forward walk cycle

## VRMA alternative

If you'd rather use VRM's native animation format instead of Mixamo:

1. Visit <https://vrm.dev/en/vrma/> for the spec
2. Create or download `.vrma` files — they carry humanoid bone mappings
   natively so **no retargeting is needed**
3. Drop next to the `.glb` clips. `loadAnimation()` auto-detects the extension
   and dispatches to `loadVrmaAnimation()` for `.vrma`
