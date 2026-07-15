# Stargate Universe — Repo Review Learnings

Compiled 2026-07-03 from a full-repo review (code, tests, tooling, design docs, production
history, GitHub tracker). Written as atomic, self-contained memory entries so each one can be
imported into an external memory store (e.g. Supermemory) independently. Tags in brackets.

---

## 1. Project identity [concept, status]

*Stargate Universe — The Destiny Mission*: a Godot 4.6 (Forward+, Jolt physics) third-person
exploration-survival RPG. You play Eli Wallace aboard the Ancient ship Destiny. Single-player,
30–90 min "one episode per session" structure; content vision 40–60 episodes. Four design
pillars: (1) The Ship IS the World, (2) Survival with Purpose (no crafting grind),
(3) Earned Discovery (no waypoints/tutorials), (4) Your Choices, Your Destiny. Anti-pillars:
not combat-focused, not aimless, not passive. Non-commercial fan project; bootstrapped from
KenneyNL Starter-Kit-3D-Platformer (CC0). Sole committer: Chris Moyer.

## 2. Engine pivot history [history, architecture]

The project pivoted completely from a browser stack (Three.js + WebGPU + ggez + Crashcat +
VRM + TypeScript/Vite/Bun/Cloudflare) to Godot 4.6 because character animation/display never
worked on the browser stack. ~3,600 LOC of VRM code was dropped. What carried over:
`design/gdd/` (engine-agnostic GDDs), `production/`, `docs/`, `.claude/` agents+skills.
Consequences that still bite: **all 4 ADRs in `docs/architecture/` describe the DEAD browser
stack** (ggez, Crashcat, WebGPU, three-vrm), as do `technical-preferences.md`,
`deployment-targets.md`, `audio-inventory.md`, and `design/data/entities.json`. Never treat
them as current guidance. Pre-pivot sprints 1–4 are archived in
`production/sprints/archive-browser-stack/` — do not resume them.

## 3. Development history since the pivot [history, status]

The CLAUDE.md "Current Status" snapshot (2026-05-21) is far behind reality. Sprint-005
(first Godot sprint) finished SCOPE COMPLETE plus seven phases of expansion
(`production/sprints/sprint-005-retro.md`): full Episode 1 "Air" crisis arc — consoles,
red-alert cinematic, fuse mini-quest, Rush/CO₂-scrubber reveal, FTL drop + gate dial +
pilotable Kino drone, off-world lime mining under a 10-minute gate window, scrubber decay
loop. Post-sprint commit history (through June 2026) adds: profile+checkpoint save system
(#77–#83), equipment/paper-doll (#72–#75), procedural planets with 6 biomes (#85–#94),
WoW-style UI suite (#61–#66), NPC ambient chat, native controller support, per-environment
footfalls, trailer generator, and the #30 gate-room art pass (event-horizon vortex +
ancient-metal shaders). Open epics: E1 cold-open narrative (#142), WoW HUD redesign (#141),
camera-occlusion transparency (#139), infinite-terrain Kino bug (#125).

## 4. Autoload architecture [architecture, code]

~20 autoloads declared in `project.godot`; **declaration order defines save deserialize
order and is load-bearing** (GameClock → GameState → QuestLog → Inventory → NPCState —
GameState seeds Inventory from legacy keys before Inventory deserializes).
`scripts/game_state.gd` (94 KB) is the signal hub and world-state spine: `objective_changed`,
`current_room_changed`, `room_discovered`, `resource_changed`, `episode_completed`, etc.
`scripts/kino_remote.gd` (92 KB) is the diegetic pause-menu UI. Autoloads reach siblings via
`_autoload_node("Name")` → `root.get_node_or_null(...)` (never the bare global) and use
idempotent `_load()` guards — both required for headless `-s` test compatibility.
Cross-script references use `preload()`, not bare `class_name`, because class_name globals
aren't reliably registered in headless `-s` mode.

## 5. Save system [architecture, save]

Two layers: `save_manager.gd` (autoload, orchestration, owns `register_system(id, system)`)
and `save_store.gd` (RefCounted, all file I/O, reused by CLI tools). Model: profiles →
checkpoint timelines (`autosave_<ts>` rolling ring of 3, `quicksave`, `manual_<ts>` and
`episode_<id>` permanent). SAVE_VERSION=2 with idempotent legacy migration. Systems implement
`serialize() -> Dictionary` / `deserialize(data, version)`; collections are `.duplicate()`d
on serialize (a real save-corruption bug motivated this). Autosave triggers on
`objective_changed`/`current_room_changed`; guards refuse to save mid-transition, roomless,
or during hydration. Save-root precedence: `--save-root=` > `SGU_SAVE_ROOT` env > headless
sandbox (`user://saves_sandbox/`) > player root. CLI: `tests/tools/save.sh`
(list/dump/validate/set/clone/scenario) — it targets the LIVE save root by default.

## 6. Policy lints — the two pre-commit gates [policy, tooling]

Install once per clone: `git config core.hooksPath .githooks`. Both lints run `--staged`:

- **Save-registration policy** (`tests/lint/check_save_registration.sh`): every autoload in
  `project.godot` must call `SaveManager.register_system(...)` or carry `# @no-save: <reason>`.
  Prevents stateful autoloads silently dropping state across save/load.
- **Collection-fork policy** (`tests/lint/check_collection_forks.sh`): no top-level bool var
  in `scripts/*.gd` may use acquisition vocabulary (`*_found`, `*_acquired`, `has_*`, `got_*`,
  …; world-state verbs like `has_seen`/`*_visited` are stoplisted). Sets of like things must
  live in ONE registry behind one add/enumerate API. Opt out with `# @collection-ok: <reason>`.
  Origin bugs: looted-fuse inventory bug #41 (fuses stored as per-instance bools never
  rendered) and quest fork #36. Adding a `kino_found`-style bool fails the commit.

## 7. Two room pipelines — diverged, know which is live [architecture, rooms, gotcha]

- **LIVE**: `scenes/room.tscn` + `scripts/room.gd` (63 KB) + `room_builder.gd`, driven by
  `data/ship_layout.json` (19 rooms, `SCALE = 0.05 m/unit`, JSON Y → world Z) and
  `data/room_connections.json` (one-directional edges, auto-mirrored). Adding a playable room
  = edit those two JSON files; `scene_boot.gd` smoke coverage picks it up automatically.
- **ORPHANED**: `scripts/kenney_room.gd` standalone-scene template — no scene instances it.
  The `/add-room` skill and `tests/capture_baselines.sh` reference per-room `.tscn` files
  (`corridor_crew.tscn`, `hull_breach.tscn`, …) that DO NOT exist. Don't follow them for
  shipping rooms.
- Spawn-marker contract: arrival marker is named `"From" + camel(source_room)`; break the
  naming and SceneRouter silently fails to place the player. The gate room
  (`scenes/gate_room.tscn`, 74 KB script) is the hand-authored exception.

## 8. Floor y-conventions and glTF origins [gotcha, 3d]

Two floor conventions coexist deliberately: `gate_room.gd` BoxMesh floor (visible top y=0,
one draw call) vs `kenney_room.gd` Kenney tiles (origin at mesh BOTTOM, visible top y=0.3;
collider must be set to match). Any cross-scene prop/NPC/spawn helper must branch on
floor-top-y. Kenney glTF kit pieces all have origin at mesh bottom; walls sink 0.3 m into
floor tiles by design — don't "fix" it. When adjusting a collider top by Δy, shift all
spawn markers and Player y by Δy too, or entry teleports pop the player out of the collider.
Skinned-mesh AABBs are pre-skinning (feet can render below origin) — measure with a one-shot
SceneTree AABB probe, never guess. `Interactable._ready()` unconditionally overwrites
`collision_layer = 4`; subclasses needing extra bits must reassign AFTER `super()._ready()`.
Collision layers: 1 = walk-blocker, 2 = camera-occluder (SpringArm masks only 2),
4 = interactable.

## 9. Test harness [testing]

Addon-free (no GDUnit4): `SceneTree`-extending GDScript run headless via `tests/run.sh
[mode]` (~40 smoke suites + lint/scene/flow/quest/playthrough/save/resume; ~160 assertions
for E1). Conventions (`tests/smoke/AGENTS.md`): `extends SceneTree`, banner + `PASS`/`FAIL`
lines + summary, explicit `quit(0|1)`, filenames `<scope>.gd` with no `test_` prefix.
Adding a suite requires wiring run.sh in four places (RAN_/RC_ vars, mode block, final
report, exit boolean). Script tests (`-s`) vs scene tests (`.tscn`): code referencing an
autoload by bare global name won't compile under `-s` — use a scene test. Runners that
survive `SceneRouter` transitions must attach to `/root` via a `call_deferred` bootstrap
(pattern: `tests/playthrough/bootstrap.gd`).

## 10. Headless testing gotchas [testing, gotcha]

- `--quit-after` is a frame-count CEILING, not a target — a truncated run exits 0 and
  **masquerades as PASS**. Tests must call `quit()` explicitly; keep ceilings generous.
- **Save isolation is mandatory in EVERY test**: autoloads run under `-s`, so any GameState
  mutation autosaves over the player's real save (bug #44) unless
  `SaveManager.configure_test_paths("<stem>")` is called first (headless runs also
  auto-sandbox).
- `-s` quirks: autoload `_ready()` deferred one frame; `await process_frame` deadlocks
  inside `_initialize()` (defer with `call_deferred("_run")`); reach autoloads via
  `root.get_node_or_null("Name")`.
- `change_scene_to_file` is async in Godot 4 — SceneRouter loops waiting for
  `current_scene`; never assume the new scene exists next frame.
- Headless can't compile GLSL — shader "validation" only parses; real proof needs
  `tests/shots/capture.sh` with a real renderer. Screenshot/movie tooling must NOT use
  `--headless` (blank PNGs).
- `Object.get("CONST")` silently returns null for consts/enums/static funcs.

## 11. CI is a stale template — tests do not run in CI [ci, gotcha, tech-debt]

`.github/workflows/ci.yml` is an unmodified TypeScript/bun template (`bun run typecheck`,
`bun run test`) with no `package.json` in the repo and no Godot install. **The Godot suite
and policy lints are enforced only by the local pre-commit hook.** Real CI needs a
Godot-headless setup invoking `tests/run.sh` + `tests/lint/*.sh`. Similarly, several
`.claude/hooks/` validators target template paths (`src/`, `assets/data/`) that don't exist
here and are inert.

## 12. Capture and trailer tooling [tooling]

`tests/shots/capture.sh <preset>` renders repeatable screenshots (real renderer, presets:
gate-room, planet biomes, ship-compass, kino views) into `screenshots/result/`;
`tests/shots/cine.sh` does gate-room cinematics with CAM_POS/CAM_LOOK/FOV env overrides.
`tools/make_trailer.sh` records scripted gameplay via Godot Movie Maker (`--write-movie`,
needs GPU) then ffmpeg-assembles an MP4 + draft social post; `tools/trailer/record.sh`
captures human playthroughs for replay. Blender/Python generators in `tools/` build
placeholder equipment GLBs and inventory icons. macOS paths are hardcoded in places
(`GODOT_BIN` default, Godot user-data dir).

## 13. Content is data-driven [architecture, content]

`data/` is the source of truth: `ship_layout.json`, `room_connections.json`, `quests.json`
(QuestLog steps complete via event `complete_step()` OR `complete_when` predicate — one
match arm in `quest_log.gd` + a JSON reference; `active` is re-derived on load, never
serialized), `items.json`, `characters.json`, `planets.json`, `biomes.json` (toxic biome
gated by `pressure_suits_found`), `knockout_lines.json`. Dialogue trees are
`Array[Dictionary]{speaker,text,choices}` routed to a WoW-style dialog screen; `dialog_action`
signals fire side effects mid-conversation.

## 14. Shaders [shaders, art]

- `shaders/event_horizon.gdshader` — gate puddle: unshaded, deliberately OPAQUE (additive
  washed out to white over lit walls), 5-octave value-noise fBm + domain warp + seam-free
  polar swirl; brightness on both ALBEDO and EMISSION.
- `shaders/ancient_metal.gdshader` — shared hero-prop PBR, world-space triplanar (procedural
  meshes lack UVs) so `panel_scale` in metres tunes once and reuses everywhere; panel grid,
  rivets, edge wear, `seam_emission` for chevron glow. Per-part tints via `.tres` variants,
  never `duplicate()` in code.
- `shaders/stargate_portal.gdshader` — free-standing amber swirling portal + HTML preview.

## 15. GDScript conventions [conventions]

Tabs; static typing everywhere (`func f(x: int) -> void:`); `snake_case` files/vars/funcs,
`PascalCase` class_name/nodes; leading `_` for private; signals over polling; composition of
small `.tscn` scenes; `Resource`/JSON for content. Kenney mini-characters share one skin
texture column — duplicate the material and multiply `albedo_color` per instance for
skin-tone variation. Cinematic-dash actors that disable collision must not restore it
mid-cutscene (trips destination Area3D).

## 16. Studio process [process]

Collaboration protocol (CLAUDE.md): user-driven, never autonomous — Question → Options →
Decision → Draft → Approval; ask before writing files; no commits without instruction.
~55 role agents (directors → leads → specialists, vertical delegation only) and ~90 skills;
director gates (`.claude/docs/director-gates.md`) are advisory with review mode in
`production/review-mode.txt` (default `lean`). Persistent agent memory lives in
`.claude/agent-memory/<agent>/MEMORY.md` (lead-programmer and godot-gdscript-specialist have
entries — read them before player/scene/floor work). Per-directory `AGENTS.md` cheatsheets
exist everywhere but are **partially stale** (they predate SaveManager, Inventory, QuestLog,
planets) — trust code over cheatsheets. GitHub workflow: epic parent issue decomposed into
numbered, dependency-ordered sub-issues; commits reference issue numbers; many implemented
issues remain open pending closure.

## 17. Known stale artifacts and inconsistencies [tech-debt]

- CLAUDE.md status snapshot (2026-05-21) far behind commit history; says branch `godot`,
  README says `reset-stack`, actual default branch is now `main` (Godot content).
- `production/stage.txt` says "Pre-Production"; CLAUDE.md says "Production".
- All 4 ADRs + technical-preferences + entities.json are browser-era.
- `/add-scene`, `/add-npc`, `/add-dialogue`, `/add-room` skills describe non-shipping
  pipelines; CCGS testing skills are Godot-aware.
- `capture_baselines.sh` references room scenes that don't exist.
- Missing: `docs/architecture/architecture.md`, `control-manifest.md`,
  `design/accessibility-requirements.md`, `sprint-002-retro.md`, `production/qa/bugs/`,
  `tests/regression-suite.md`.
- CI workflow doesn't test the game at all (see §11).
