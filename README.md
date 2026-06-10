# Stargate Universe

A Godot 4.6 sci-fi RPG set in the Stargate Universe TV series.

## Status

This branch (`reset-stack`) is a complete engine pivot from the previous browser-based stack
(Three.js / WebGPU / ggez / Crashcat / VRM). The previous stack is preserved on `main`.

Bootstrapped from [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)
(CC0).

## Install

macOS (Homebrew):

```sh
brew install --cask godot
```

Otherwise download Godot 4.6+ (Forward+) from [godotengine.org](https://godotengine.org/).

## Running

Play directly (no editor):

```sh
godot --path .
```

Or open the editor: `godot -e --path .` and press **F5**.

## Controls

- **WASD** — move
- **Space** — jump (double-jump enabled)
- **Right mouse (hold)** — mouselook (WoW-style)
- **Mouse wheel** — zoom in/out
- **Arrow keys** — camera orbit (fallback)
- **Esc** — release mouse / quit

## Character Builder (Quaternius modular — PRIMARY pipeline)

The hero character direction: **Quaternius Universal Base Characters + Modular
Character Outfits** (CC0, glTF) — true WoW-style slot equipment, assembled and
hot-swapped entirely in code. Launch the builder:

```sh
godot --path . scenes/quaternius_lab.tscn
```

Male/Female base picker; per-slot dropdowns (Body / Arms / Legs / Feet / Head /
Acc / Hair); rifle with aimed-in-hand vs slung-on-back; the shared Mixamo crew
animation library; turntable.

### How it works (`scripts/modular_character.gd`)

- Packs import with a **UE-mannequin→Humanoid BoneMap**
  (`tools/gen_mixamo_imports.py --profile ue --skelpath Armature/Skeleton3D`),
  so every body, outfit part, and hairstyle lands on `%GeneralSkeleton` with
  humanoid bone names — the same ecosystem as the Mixamo animation library
  and the VRM cast.
- **Outfit parts REPLACE body regions** (per the pack README, the full body
  clips through clothing). The pack ships no split body, so ModularCharacter
  splits the FullBody mesh **at load by bone weights** into five region
  meshes (head/torso/arms/legs/feet) and hides regions covered by equipped
  slots — bare base, full outfits, and mixed outfits all render without
  clip-through.
- API: `ModularCharacter.create("Male")`, `set_slot("Body",
  "Male_Ranger_Body")`, `set_slot("Legs", "")` (restores base region),
  `set_rifle(true, aimed)`, `play_clip("walk")`,
  `ModularCharacter.parts_for_slot(slot, gender)`.
- **Adding outfits**: drop part GLTFs in `models/quaternius/parts/`
  (`<Gender>_<Outfit>_<Slot>[_Variant]` naming), run the BoneMap tool +
  `--import`. The free tier has Peasant + Ranger; the other 10 outfits are
  Quaternius Patreon rewards. Sci-fi/military outfits: commission, Patreon
  packs, or author parts on the same rig in Blender.
- Tests: `tests/run.sh modular` (25 asserts); visual proof
  `tests/capture/quaternius_assembly.gd`.

## VRM Lab (VRoid characters — secondary)

The crew's hero pipeline is **VRoid/VRM**: full anime-grade characters authored in VRoid
Studio with facial expressions, finger bones, spring-bone hair physics, and retargeted
humanoid animations. Launch the studio:

```sh
godot --path . scenes/vrm_lab.tscn
```

Live controls: character picker, body animation dropdown (retargeted Mixamo clips),
emotion buttons + weight (happy/angry/sad/relaxed/surprised), visemes for lip-sync
preview (aa/ih/ou/ee/oh), auto/manual blink, gaze sliders, **WoW-style equipment slot
dropdowns (chest/legs/feet — swap shirts/pants/shoes between characters in code)**,
gear toggles with Aim routing (rifle: back ↔ right hand; sidearm: hip ↔ hand), turntable.

### WoW-style equipment (hot-swap gear in code)

Every VRoid export shares the same standard base body, so **any garment authored on any
character fits every other one** — VRoid Studio is the gear-authoring tool. The system
(`scripts/vrm_gear_library.gd` + `VrmCharacter.equip/unequip`):

- **Items are harvested from donor VRMs at runtime** by surface material name — VRoid
  names every material by garment class (`*_Tops_*`, `*_Bottoms_*`, `*_Shoes_*`,
  `*_Onepiece_*`), so a gear item = a donor VRM + a keyword list. Extracted pieces keep
  their `Skin` (name-based humanoid bone binds) and snap onto any crew skeleton,
  following animation automatically.
- **Equipping strips the wearer's own garment surfaces** for occupied slots (no
  z-fighting) and restores them on unequip.
- **Rigid items** (helmet, rifle, sidearm) ride `BoneAttachment3D` snap points with
  aim routing.
- Code: `character.equip("tactical_top")`, `character.unequip("chest")`,
  `character.equipped("legs")`.
- **To add gear**: dress a throwaway character in VRoid Studio → export
  `models/vrm/outfits/<name>.vrm` → add one `ITEMS` entry in `vrm_gear_library.gd`.
- Proof captures: `tests/capture/vrm_wardrobe.gd` (one character, three outfits),
  `vrm_slot_swap_probe.gd`, `vrm_outfit_swap_probe.gd`, `equip_probe.gd` (cross-pack
  binding experiment — also documents the constraint: garments must come from
  same-proportioned rigs, which the shared VRoid base body guarantees).

### How the VRM pipeline works

- **Import**: `addons/vrm` (godot-vrm) + `addons/Godot-MToon-Shader`. A `.vrm` dropped in
  `models/vrm/` imports as: `%GeneralSkeleton` (humanoid-profile bone names incl. full
  finger chains), an AnimationPlayer of VRM expression clips, MToon materials, and a
  spring-bone `secondary` (hair/cloth sway runs automatically).
- **Animations**: Mixamo FBX clips in `models/vrm/anim_src/` import with a
  Mixamo→Humanoid `BoneMap` (`tools/gen_mixamo_imports.py` splices it into each
  `.import`), which rewrites every track to `%GeneralSkeleton:<HumanoidBone>` — the same
  addressing as the VRM skeletons. `tools/extract_anim_library.gd` collects them into the
  shared `models/vrm/anim/crew_body.res` (15 clips: idle/walk/run, emotional idles,
  gestures, the full rifle set, death). One library animates every VRM character.
  To add a clip: download FBX (without skin is fine) from Mixamo → drop in `anim_src/` →
  run the two tools → add to the manifest in `extract_anim_library.gd`.
- **Runtime**: `scripts/vrm_character.gd` (`VrmCharacter.create(path)`) — body animation
  API (`play_clip("walk")`), simultaneous expression channels (emotion + viseme + blink +
  gaze mixed per frame from the imported expression clips), auto-blink, and bone-snapped
  gear (helmet→Head, rifle→Chest back-sling or RightHand when aimed, sidearm→Hips).
- **Models**: `models/vrm/eli.vrm`, `models/vrm/scott.vrm` (authored in VRoid Studio —
  sources in `~/Documents/VRM/*.vroid`). Export more crew from VRoid Studio and drop the
  `.vrm` here; everything (expressions, animations, gear) works automatically because the
  pipeline only depends on the standard VRM humanoid rig.
- **Tests**: `tests/run.sh vrm` (38 asserts) and captures `vrm_lineup.gd`,
  `vrm_motion.gd`, `vrm_showcase.gd`, `vrm_gear_debug.gd` (mount tuning).

Known gaps: `.vrma` (VRM Animation) import is a stub in godot-vrm — use the Mixamo
pipeline instead; `Rush.vroid` exists but needs a `.vrm` export from VRoid Studio.

## Character Lab (Kenney minis — secondary/legacy)

A standalone VRoid-style character editor / test bench for the crew generation system.
Launch it without touching game state:

```sh
godot --path . scenes/character_lab.tscn
```

(or open `scenes/character_lab.tscn` in the editor and press **F6**.)

What you can do there:

- **Pick any crew member** and flip between **Ship** / **Mission** contexts — outfits, gear,
  and identity (e.g. Greer's skin tone) come from the central registry.
- **Toggle gear** (sidearm / rifle / helmet) on the live model — each snaps to a skeleton
  bone, so it bobs and turns with the rig (the helmet rides the head, not the body).
- **Aim** toggle moves the primary weapon (rifle > sidearm) from its stowed mount to the
  hand and plays the holding pose.
- **Override garment colors** per role (top / bottom / shoes / limbs / accent) with live
  rebake, then hit **Print snippet** to dump a paste-ready recolor dict to the console for
  promoting into `CharacterFactory.OUTFITS`. The lab never writes files itself.
- **Cycle animations** and orbit/zoom with the mouse.

### How character generation works

`scripts/character_factory.gd` is the single source of truth, in four layers:

1. **PROFILES** — who: base model, outfit per context, military flag, optional skin/hair
   identity overrides.
2. **OUTFITS** — what they wear: per-garment recolors + carried gear
   (`civvies`, `fatigues`, `duty_black`, `combat`).
3. **SWATCH_GROUPS** — how recolors land: Kenney mini-chars UV-map each garment onto flat
   swatch cells in the shared `colormap.png` atlas, so changing a shirt = recoloring that
   model's shirt cells in a per-instance baked texture. Faces/hair/skin cells are excluded,
   so identity survives every outfit.
4. **MOUNTS** — snap points: gear attaches to the skeleton via `BoneAttachment3D`, never to
   the body in body-space, so it tracks animation. The Kenney mini rig (7 bones) gives us
   `head` (helmet), `torso` (rifle slung on the back, sidearm holstered on the hip), and
   `arm-right` (weapon in hand when aiming). Mount offsets are tuned visually in the Lab via
   `tests/capture/gear_snap_debug.gd` (3-angle view + world-position dump).

Dress rules shipped: military crew wear **black duty uniforms + sidearm on the ship** and
**olive fatigues + rifle + sidearm on missions**; civilians wear their own clothes aboard
and unarmed fatigues off-ship (Eli: t-shirt on Destiny, fatigues on a planet).

### Editing / contributing characters

- **Recast a base model**: copy a GLB from the Kenney library into `models/characters/`,
  point the character's `PROFILES` entry at the new stem, then run the calibration below —
  garment cells differ per model.
- **Calibrate garment cells** (after any recast):
  `CHAR_MODEL=<stem> CELLS="9:8,9:11,..." godot --quit-after 8000 -s res://tests/capture/swatch_calibrate.gd`
  renders the model once per atlas cell with that cell flashed magenta, diffs front+back
  views, and prints which body region each cell paints. Get the candidate cell list from
  `python3 tools/probe_character_swatches.py models/characters/<stem>.glb`.
  Beware: meshes sometimes park large quads on cells with very few vertices — if a garment
  partially survives a recolor, the missing piece is usually an adjacent row in the same
  atlas column.
- **Visual regression**: `godot --quit-after 600 -s res://tests/capture/character_grid.gd`
  renders the whole roster in both contexts;
  `CHAR_ONE="Sgt Greer" godot ... -s res://tests/capture/character_one.gd` renders one
  character as base/ship/mission. Captures land in the Godot `user://` dir (path printed).
- **Logic tests**: `tests/run.sh char-gen` (47 assertions: registry integrity, bake
  correctness, skin-cell immutability, gear sync per context).

## Layout

```
project.godot       Godot project config
scenes/             .tscn scenes (entry: scenes/main.tscn; character_lab.tscn test bench)
scripts/            GDScript (character_factory.gd = crew appearance registry)
models/             Kenney CC0 .glb models (characters/, gear/, sci-fi/)
objects/            Reusable .tscn prefabs
sounds/             SFX
sprites/            UI sprites
fonts/              Fonts
design/gdd/         Game Design Documents (carried from browser branch)
production/         Sprint plans, milestones
docs/               Narrative reference, audio inventory
tests/smoke/        Headless assertion suites (tests/run.sh)
tests/capture/      Visual validation harnesses (render → PNG → eyeball)
tools/              Offline helpers (probe_character_swatches.py, make_trailer.sh)
```

## Testing

```sh
tests/run.sh             # everything (lints + all smoke suites)
tests/run.sh char-gen    # character generation only
tests/run.sh e1-opening  # E1 cold-open (incl. the armed standoff staging)
```

Smoke suites are plain `SceneTree` scripts (no GDUnit4). Two policy lints run in the
pre-commit hook (`git config core.hooksPath .githooks`): save-registration and
collection-fork — see `CLAUDE.md` for the rules they enforce. When adding a suite, wire it
into `tests/run.sh` (mode flag + summary row + exit-code aggregation) so `all` catches it.

Note for visual work: capture scripts must run **without** `--headless` (they read the
viewport), and verify a suite's assertion *count*, not just its exit code — a script that
fails to load exits 0.

## Credits

- Engine: [Godot 4.6](https://godotengine.org/)
- Starter kit: [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) — CC0 by Kenney
- Stargate Universe is a TV series by MGM; this is a non-commercial fan project.

## License

See `LICENSE-kenney.md` for the starter kit's CC0 license. Project code is private/unlicensed.
