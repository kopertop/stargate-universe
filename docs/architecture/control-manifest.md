# Stargate Universe — Control Manifest

A flat, actionable rules sheet for programmers. Where ADRs and `architecture.md`
explain *why*, this tells you *what to do* and *what to never do*, per layer.

- Version: 1.0 · Last Updated: 2026-06-26 · Engine: Godot 4.6
- Sources: ADR-001..004, `CLAUDE.md` dev conventions, the two pre-commit lints, and
  the project's documented runtime gotchas.
- Re-run/refresh whenever a new ADR is accepted or a recurring gotcha is found.

## Global Rules (all layers)

**MUST**
- Use **typed GDScript** everywhere: `func f(x: int) -> void:`. Type params, returns, and members.
- Indent with **tabs**. `snake_case` files & funcs, `PascalCase` nodes/classes, `UPPER_SNAKE_CASE` consts.
- Prefer **Godot signals** over polling for cross-node communication.
- Prefer **composition**: small `.tscn` files instanced together; small scripts over god objects.
- `preload(...)` as a `const Script` and call statics — do **not** rely on `class_name` for type
  lookup. Registration lags in headless `-s` runs and silently fails to resolve.
- Make every system exercisable from a `SceneTree` smoke test; verify the **assertion count**,
  not just exit code (a script that fails to LOAD exits 0 with 0 assertions = false green).
- After adding any asset (`.ogg`, `.png`, `.glb`), run `godot --headless --import` to generate
  the `.import` sidecar — without it `load()`/`Audio.play()` silently fails.

**MUST NEVER**
- Use `bool()` on a String/null/Array/Dict — it crashes in GDScript 4.6. Use truthiness or `== true`.
- Add a per-instance acquisition bool (`*_found`, `has_*`, `got_*`) for a set of like things — route
  through the ONE collection (lint `check_collection_forks.sh`). Opt out only with `# @collection-ok:`.
- Reason about facing from rotation magnitude — use `look_at()` or the forward lookup
  (`forward = -basis.z`; `rot=+π/2 → -X`). Gimbal-lock corrupts `rotation.z` reads.

## Foundation Layer — state, save, routing

**MUST**
- Change story state ONLY through `GameState` mutators; emit/listen via its signals.
- Register every stateful autoload: `SaveManager.register_system("<id>", self)`, OR mark it
  `# @no-save: <reason>` (lint `check_save_registration.sh` blocks the commit otherwise).
- Keep `serialize()` → plain-value `Dictionary`; make `deserialize()` tolerant of missing keys.
- Give NPCs **unique node names** — `NPCState` persists transforms keyed by node name globally;
  the same character in two scenes will cross-restore if names collide.
- Route all scene changes through `SceneRouter.change_to(scene, spawn)`. After
  `change_scene_to_file`, `current_scene` is briefly null — loop-wait with a ceiling in headless.
- Isolate the save root for any non-player session (screenshots, tests, captures) — default-on,
  not opt-in — or it clobbers `user://save.json`.

**MUST NEVER**
- Set `current_scene` directly or place spawns outside `SceneRouter`.
- Emit a tree-pausing dialog while `SceneRouter.is_transitioning` (stalls the fade tween →
  permanent black screen). Defer the emit past the fade.
- Assume autoload `_unhandled_input` order — it fires in **reverse** registration order; gate only
  the OPEN path of a toggle and defer explicitly.

## Core Layer — player, doors, interactables

**MUST**
- Size interact boxes ~1.6 m tall: the player interact ray casts horizontally from 1.1 m
  (chest height); low props never get hit.
- In an `Interactable` subclass, set extra collision layers AFTER `super()` — `Interactable._ready()`
  hard-sets `collision_layer = 4`.
- Land door auto-walk targets on the **player side** of `door.global_position` — the door is a
  decorative recess in front of a solid -Z wall, not a hole through it.
- Keep ≥1–2 m clearance around every doorway (props at wall midpoints collide with door stamps).
- After restoring an idle body's `rotation.y`, also `view.snap_to_target()` — an idle body
  re-faces `view.rotation.y` each frame, so position survives a load but facing doesn't.
- `add_child()` BEFORE `look_at()` — `look_at` silently errors outside the tree.

**MUST NEVER**
- Rely on `enabled = false` to stop an interact prompt — it doesn't change `collision_layer`, so the
  ray still hits. (Handled centrally in `player.gd::_find_interact_target`.)
- Read post-interact state in an `interacted` listener — `interact()` emits `interacted` BEFORE
  running `_on_interact`; defer.
- Put the Kino drone in group `"player"` — it deliberately isn't; player-keyed systems must skip it.

## Feature Layer — quests, inventory, cinematics, NPCs

**MUST**
- Early-return on `SceneRouter.instant_mode` in any async tween/timer cinematic in `_on_interact`,
  snapping the end-state, so the headless playthrough never pumps frames. Tween the Character child,
  not the body.
- Stage NPCs during a (tree-pausing) dialog via per-node `"action"` cues
  (`GameState.dialog_action`) on `PROCESS_MODE_ALWAYS` actors with unique node names.
- Disable an NPC's `auto_greet` during a custom cinematic (it spawns the dialog's StandoffCamera and
  steals your cutscene cam). Re-enabling `auto_greet` must also `set_process(true)` + reset its flags.
- Gate run-scoped `_ready` setup (timers, away-team) on the SPAN of quest steps the scene is valid
  in, not a single step — steps auto-advance mid-scene and a save can reload on a later one.

**MUST NEVER**
- Throw a `PhysicalBone3D` ragdoll across a room (joint solver bleeds the launch). Use a kinematic
  projectile arc, then settle to ragdoll.
- Add a sibling boolean for a newly-acquired thing — extend the collection (see Global rule).

## Presentation Layer — HUD, dialog, audio

**MUST**
- Keep the HUD to the WoW model: unit frame + action bar of tools/actions. Ship stats and general
  items belong in the Kino Remote / consoles / inventory, never a persistent HUD strip.
- Route one-shot SFX through the `Audio` autoload (`Audio.play("res://sounds/x.ogg")`); ambient/music
  through `MusicDirector`.
- For dialog, frame the speaker (OTS shifts to the speaker; gold floating choice list, bottom
  subtitle) — the Fable dialog direction. The flow engine + node paths underneath are load-bearing
  for tests; don't break them when restyling.

**MUST NEVER**
- Define `const float TAU/PI` (or any built-in) in a `.gdshader` — it fails compile silently and the
  mesh vanishes. Grep stderr for `Redefinition`.
- Trust whole-frame render diffs without verifying raw frame size and stopping GLB autoplay anims
  (async resize/retina + cold materials poison the baseline).

## Control Bindings (InputMap, `project.godot`)

| Action | Purpose |
|---|---|
| `move_forward` / `move_back` / `move_left` / `move_right` | player movement (camera-relative) |
| `jump` | jump; **hold ~1 s to skip the cold open** |
| `interact` | interact with the targeted `Interactable` |
| `kino_remote` | open/close the Kino overlay (map/status/objectives/inventory) |
| `kino_autopilot` / `kino_descend` | Kino drone piloting |
| `pause` | pause menu |

Plus `[V]` opens the in-game Crew Viewer (dev/preview). 19 actions total — see `project.godot`
`[input]` for the authoritative bindings and gamepad mappings (persisted via `Gamepad`/`Settings`).
