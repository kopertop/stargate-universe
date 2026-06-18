# HANDOFF — WoW-style HUD Redesign (Epic)

> **Purpose:** A complete, self-contained brief for the code agent who implements the
> WoW-style HUD. Read this top-to-bottom before touching code. Every phase lists
> concrete tasks, the exact files to touch (with current line refs), and **testable
> acceptance criteria**. This is the source of truth; the GitHub issue mirrors it.

![WoW-style HUD reference — "World of Claudecraft"](./wow-hud-reference.png)

---

## 1. Goal & Non-Goals

**Goal:** Re-skin and extend the in-game HUD (`scripts/hud.gd` + `objects/hud.tscn`)
to match the **layout, anatomy, and gold-on-dark palette** of the reference
screenshot, while keeping **Stargate Universe content** (Eli/crew, Health + Oxygen,
Destiny rooms, sci-fi iconography). We adopt the WoW *structure*, not the fantasy
*content*.

**In scope (decided with project owner):**
- Gold-primary palette re-skin of all existing widgets.
- Player unit frame upgrade: circular portrait, role/class icon, level badge, numeric bar overlays.
- **Target / companion unit frame** (net-new) + lightweight **selection system**.
- **Selection ring** decal under the selected unit (net-new).
- **World-space nameplates + quest markers** on NPCs/enemies (net-new).
- **Circular minimap** top-right (net-new; replaces the top-banner linear compass in gameplay).
- **4-slot, controller-first action bar**, repositioned bottom-center, + a bottom-right **menu-button column** (C/Q/M/B).
- **Persistent tabbed Chat / Combat Log** bottom-left (net-new; retires the transient top-right feed).
- **Multi-quest tracker** (top-right under the minimap) with counter objectives.

**Non-goals:**
- No combat/ability system (action-bar slots wire to *tools/actions* that exist; combat is future work).
- No fantasy art. Borrow layout + palette only.
- **Do NOT add a ship-stats/items resource strip to the HUD** — see memory `wow-hud-no-stats-strip`. Ship stats live in the Kino Remote / consoles, not the persistent HUD.
- Discord/GitHub social buttons from the screenshot are **out of scope** (not relevant to a shipped game build).

---

## 2. Reference Element Breakdown (what's in the screenshot)

| # | Element | Screenshot detail | SGU adaptation |
|---|---------|-------------------|----------------|
| A | Player unit frame (top-left) | Circular portrait, class icon (crossed swords), level badge "1", name "Chris", green HP `90/90`, gold bar `0/100` | Eli portrait (circular), role icon, level badge, **Health** (green) + **Oxygen** (cyan/amber) with numeric overlays |
| B | Target/companion frame (right of A) | "Marshal Redbrook" Lv10, HP `500/500`, buff/overflow dot `...` | Selected NPC/target: portrait, name, level, HP bar (hidden when target has no HP) |
| C | Circular minimap (top-right) | Radial paths, POI dots, heading arrow, zone name "Eastbrook Vale" | Top-down ship/planet minimap, room/POI/quest dots, heading arrow, current-room/zone name |
| D | Quest tracker (right) | Multiple quests, each w/ counter objectives `0/5`, `0/8` | Enumerate all tracked quests; each title + objective line(s), counters from objective text |
| E | Chat / Combat Log (bottom-left) | Tabbed, persistent, scrollable, color-coded gold text | Persistent tabbed panel backed by `GameState.log_entries`; tabs "Log" / "Combat" |
| F | Action bar (bottom-center) | 12 numbered slots | **4 slots, controller-first** (icon + kbd glyph + gamepad glyph) |
| G | Menu button column (bottom-right) | Vertical C/S/Q/M/B keybind chips | Character (C), Quest (Q), Map/Kino (M), Bags/Inventory (B) — open existing panels |
| H | NPC nameplates + quest markers | Floating names, `?` quest markers, enemy plates w/ level + green HP | Label3D billboards: name, level, quest marker `?`/`!`/`✓`, optional HP bar |
| I | Selection ring | Yellow ground ring under targeted unit | Ground decal/ring under `player.current_target` |
| J | Palette | Gold/amber text on near-black translucent panels, thin gold borders | Gold-primary skin (shift from current cool-blue) |

---

## 3. Current State Inventory (what already exists)

All HUD widgets today are **built in code** in `scripts/hud.gd` (858 lines). `objects/hud.tscn`
only declares a handful of legacy `Label`/`NinePatchRect` nodes.

| Widget | Status | Code ref |
|--------|--------|----------|
| Shared skin factory `_make_wow_stylebox()` | ✅ exists, **cool-blue** primary accent | `hud.gd:258` |
| Palette constants `SKIN_ACCENT` (blue), `SKIN_ACCENT_GOLD`, `SKIN_PANEL_BG` … | ✅ | `hud.gd:34-40` |
| Player unit frame (square portrait + name + HP/Oxygen bars) | ✅ | `hud.gd:274-349` (`_build_unit_frame`, `_make_vital_bar`) |
| Health critical pulse | ✅ | `hud.gd:563-577` |
| Quest tracker (single quest, single objective, top-right) | ✅ | `hud.gd:708-799` |
| Action bar (bottom-right, tool-only, grows left) | ✅ | `hud.gd:595-703` |
| Transient log feed (last 3, 6s fade, top-right) | ✅ | `hud.gd:842-858` |
| Discovery toast (center, glyph decode) | ✅ | `hud.gd:368-481` |
| Quest edge arrow (offscreen waypoint pointer) | ✅ | `hud.gd:352-537` |
| Top-banner **linear** compass (ship/planet) | ✅ | `hud.gd:219-251` + `scripts/planet_compass.gd` |
| Dialog subtitle panel + choice-tree DialogScreen | ✅ | `hud.gd:802-839` |
| Interact prompt `[E] …` | ✅ | `hud.gd:544-554` |

**Backing data already present (no new gameplay state needed for most of this):**
- `GameState.health` / `oxygen` (0–100), `MAX_HEALTH`/`MAX_OXYGEN` (`game_state.gd:78-79,270-271`), signals `health_changed(float)`, `oxygen_changed(float)`.
- `GameState.log_added(String)` + persisted `GameState.log_entries: Array[String]` (`game_state.gd:323`). **Use `log_entries` to back the persistent chat panel.**
- `GameState.quest_step_changed(String)`, `current_room_changed(String)`, `room_deciphered(String)`.
- `QuestLog.title()`, `objective()`, `active_step_id()`, `target()` (`quest_log.gd:172-214`). **Single-quest today** — Phase 7 adds enumeration.
- Player targeting primitives: `player.gd` already tracks `_current_interactable` (`player.gd:33`) and a **sticky** `_clicked_target` (`player.gd:37`) and emits `interact_target_changed(Node)` (`player.gd:8`). **Phase 2 promotes this into a real selection.**
- Compass bearing/marker math reusable for the minimap: `planet_compass.gd`.
- POI/room data for the minimap: `GameState.discovered_pois` (Dict), `GameState.rooms_discovered`, `GameState.current_room_id`, `ShipLayout.room(id)`, `ProceduralShip`.
- `CharacterPanel` autoload already exists (`character_pane` action on **C**, `project.godot:171`).

---

## 4. Theme / Palette Spec (Phase 0 foundation)

Create a single source of truth for the skin so every widget shares it (the current
`_make_wow_stylebox` is close but per-widget constants drift). **Recommended:** extract a
small static helper `res://scripts/ui/hud_theme.gd` (`class_name HudTheme`) holding the
palette + stylebox factories; `hud.gd` and all new widgets read from it. (Duck-type via
`preload` path in tests to dodge the `class_name` headless race — see §11.)

```
# Target palette (calibrate against the reference; these are starting values)
PANEL_BG        = Color(0.035, 0.035, 0.045, 0.82)   # near-black, more opaque than today's 0.6
BORDER_DARK     = Color(0.0,   0.0,   0.0,   0.90)    # outer hairline
ACCENT_GOLD     = Color(0.83,  0.66,  0.32, 1.0)      # PRIMARY: borders, headers, quest text
ACCENT_GOLD_DIM = Color(0.55,  0.44,  0.22, 1.0)      # inactive border
HEALTH_FILL     = Color(0.34,  0.74,  0.26, 0.97)     # WoW green
HEALTH_CRIT     = Color(0.90,  0.25,  0.22, 0.98)
OXYGEN_FILL     = Color(0.35,  0.72,  0.92, 0.97)     # cyan (SGU oxygen); OR amber to mirror screenshot — calibrate
TEXT_PRIMARY    = Color(0.96,  0.92,  0.80, 1.0)      # warm off-white
TEXT_GOLD       = ACCENT_GOLD
TEXT_OUTLINE    = Color(0, 0, 0, 0.9)
CORNER_RADIUS   = 4
```

- **Double border** look (black outer + thin gold inner) reads closest to the screenshot. Implement as a `StyleBoxFlat` with `border_color = BORDER_DARK`, `border_width = 3`, plus a child overlay or `expand_margin` gold inner — or simpler: single gold border on black bg. Calibrate by capture (§10).
- **Migration:** keep existing widget structure; only swap the color sources to the new palette. The existing `hud_wow.gd` test mirrors palette constants (`hud_wow.gd:33-35`) — **update that mirror** or the cohesion test fails by design.

---

## 5. New Systems & Data Contracts

### 5.1 Selection / targeting (Phase 2)
Promote the existing sticky click-target into a first-class **selection**:
- `player.gd`: add `var current_target: Node = null` and `signal target_changed(target: Node)`. Set it on click-to-select (reuse `_clicked_target` flow, `player.gd:37,449-452`); clear on Esc/click-empty/out-of-range.
- **Target interface (duck-typed; no hard dependency):** a selectable node MAY implement:
  - `get_display_name() -> String`
  - `get_level() -> int` (≤0 ⇒ hide level badge)
  - `get_health() -> float` / `get_max_health() -> float` (≤0 max ⇒ hide HP bar; most SGU NPCs are non-combat → no HP)
  - `get_portrait_key() -> String` (feeds `portrait_loader.gd`)
  - `get_disposition() -> String` ("friendly" | "neutral" | "hostile" → border tint)
- `npc.gd` implements the above (most return name/level only, no HP).

### 5.2 Selection ring (Phase 2)
- A flat ground ring (Decal or unshaded torus/quad-with-shader) parented under the HUD's owner scene or spawned at `current_target` feet, billboard OFF, y just above floor. Color by disposition (yellow = neutral/selected, red = hostile, green = friendly). Hidden when no target. Skip under `SceneRouter.instant_mode`.

### 5.3 Nameplates + quest markers (Phase 3)
- `objects/nameplate.tscn` + `scripts/nameplate.gd` (or built in `npc.gd`). A `Label3D` (billboard ON) for the name + level bracket `[Lv] Name`, an optional thin HP sub-bar (`Sprite3D`/`MeshInstance3D` or a small SubViewport), and a quest-marker glyph (`?` available / `!` turn-in / `✓` complete) driven by `QuestLog`.
- Reuse `npc.gd`'s existing over-head anchor (`npc.gd:241` references y≈2.0 nametag pos; ambient bubble at y≈2.42, `npc.gd:262-277`). Keep clear of the ambient speech bubble.
- Quest-marker state: query `QuestLog` for whether this NPC is a quest giver/turn-in for any active step (add a helper `QuestLog.marker_for(npc_name) -> String`).
- **Gotcha:** the Kino drone is NOT in group "player" (memory `kino-not-in-player-group`); nameplate visibility logic must key off the on-foot player camera, not assume the player group is the camera owner.

### 5.4 Circular minimap (Phase 4)
Two viable approaches — **recommended: live SubViewport ortho camera**:
- **A (recommended):** `objects/minimap.tscn` = `SubViewport` (square, e.g. 256²) containing a top-down `Camera3D` (orthogonal, `projection = ORTHOGONAL`) that follows the player from above; render into a `TextureRect` masked to a circle (`Control` with a circular `clip` shader or a ring frame PNG). Overlay POI/quest/heading markers as `Control` children drawn from projected world positions. Heading arrow from the player's yaw.
- **B (fallback):** pure `Control._draw` radial map: plot `discovered_pois` / rooms relative to player using `planet_compass.gd` bearing+distance math, no second camera. Cheaper, less "live".
- **Decision:** the circular minimap **replaces the top-banner linear compass during gameplay**. Keep `planet_compass.gd` for the Kino overlay / behind a `Settings` toggle so we don't delete a working system. Flag this in the PR for owner review (calibration item).
- Zone/room name label under/over the minimap from `GameState.current_room_id` → `ShipLayout.room(id).name`.

### 5.5 Persistent tabbed Chat / Combat Log (Phase 6)
- Bottom-left `PanelContainer` with a tab strip ("Log" / "Combat") over a scrollable `RichTextLabel` (`scroll_following = true`, `bbcode_enabled = true`). Back it with `GameState.log_entries` (already persisted) + live `log_added`.
- Color-code by line type (system / dialogue / discovery / resource) — gold default, matching the screenshot.
- **Retire** the transient top-right 3-line feed (`hud.gd:842-858`) — its content now lives here. (Discovery *toast* stays — it's a different, center-screen affordance.)
- `mouse_filter`: the panel scrollbar needs input, but it must not swallow world clicks elsewhere — see memory `godot-control-eats-mouse-input`. Size it tightly and set the backing layer `MOUSE_FILTER_IGNORE` outside the panel rect.

### 5.6 Action bar (4 slots, controller-first) + menu column (Phase 5)
- **4 fixed slots**, bottom-center, `HBoxContainer` centered (anchor 0.5/1.0). Each slot: icon + small **keyboard glyph** + **gamepad glyph** (read current binding from `InputMap` for the slot's action so it reflects rebinds; `Gamepad`/`Settings` autoloads exist for glyph style).
- Slot contents are *contextual actions/tools*, not abilities: e.g. `interact`, `kino_remote`, sprint/`jump`, + 1 reserved/contextual. Keep the existing click-to-fire (`hud.gd:693-703`) and attention-pulse (`hud.gd:629-637`).
- **Menu-button column** bottom-right (vertical `VBoxContainer`): Character (C), Quest (Q), Map (M), Bags (B). Each a small chip with label + keybind; click or key opens the matching panel (`CharacterPanel`, quest panel, Kino map, inventory). Add the missing input actions (§6).

### 5.7 Multi-quest tracker (Phase 7)
- `QuestLog.active_quests() -> Array[String]` (new): all started, non-complete, tracked quests. E1 has one today; design for N.
- Tracker renders, per quest: gold title + one or more objective lines (prefix `-` or `☐`); counters (`0/5`) come from the objective text (already dynamic, e.g. `GameState.lime_objective_text`).
- Position top-right **under the minimap** (minimap now owns the very top-right corner).

---

## 6. Input / Keybind Additions (`project.godot [input]`)

Existing: `move_*`, `jump`, `sprint`, `interact` (E), `camera_*`, `zoom_*`, `kino_remote` (Tab), `pause` (Esc), `character_pane` (C), `kino_autopilot` (F), `kino_descend`.

**Add** (keyboard + a gamepad button each, to stay controller-first):
- `quest_log` — **Q**
- `toggle_map` — **M**
- `inventory` — **B**
- `cancel_target` — **Esc** (or a face button) to clear selection (may overload `pause`; gate carefully — see memory `godot-autoload-input-order`).

Keep a single owner for each binding; do not rely on autoload `_unhandled_input` order (memory `godot-autoload-input-order`). Render glyphs from `InputMap` so the menu column + action bar reflect actual binds.

---

## 7. Phased Implementation Plan (checklist)

> Land each phase as its own commit on a `feature/wow-hud-redesign` branch. Run the
> relevant smoke group after every phase. Karpathy-loop the visual phases: capture →
> compare to reference → commit-if-closer (memory `chris-working-style`).

### Phase 0 — Theme foundation
- [ ] Extract `scripts/ui/hud_theme.gd` (palette + `make_panel_stylebox`, `make_bar_styleboxes`).
- [ ] Repoint `hud.gd` widgets to the gold palette; keep layout unchanged.
- [ ] Add input actions `quest_log`/`toggle_map`/`inventory`/`cancel_target`.
- [ ] Update `tests/smoke/hud_wow.gd` palette mirror (`:33-35`) to the new gold values.

### Phase 1 — Player unit frame upgrade
- [ ] Circular portrait (mask the existing `TextureRect`), role/class icon badge, level badge.
- [ ] Numeric overlays on Health + Oxygen bars (`90/90` style), value text centered.
- [ ] Gold skin, keep critical-pulse behavior.

### Phase 2 — Target frame + selection
- [ ] `player.current_target` + `target_changed`; click-to-select / Esc-clear.
- [ ] HUD target frame (top-left, right of player frame): portrait, name, level, HP bar (graceful-hide when no HP).
- [ ] Selection ring decal under target; disposition-tinted; instant_mode-skip.

### Phase 3 — Nameplates + quest markers
- [ ] `nameplate.gd` Label3D (billboard) name + `[Lv]` bracket on NPCs/enemies.
- [ ] Quest marker glyph driven by `QuestLog.marker_for(name)`.
- [ ] Optional thin HP sub-bar for nodes that expose HP.

### Phase 4 — Circular minimap
- [ ] `objects/minimap.tscn` SubViewport ortho top-down cam following the player; circular mask + frame.
- [ ] POI/room/quest dot overlay + heading arrow; zone/room name label.
- [ ] Replace top-banner linear compass in gameplay (keep `planet_compass.gd` behind a Settings flag / Kino).

### Phase 5 — Action bar (4-slot) + menu column
- [ ] Reposition action bar bottom-center; 4 fixed slots; kbd + gamepad glyphs from `InputMap`.
- [ ] Menu-button column bottom-right (C/Q/M/B) opening existing panels; add bindings.

### Phase 6 — Persistent tabbed Chat/Combat log
- [ ] Bottom-left tabbed panel backed by `GameState.log_entries`; auto-scroll; color-coded.
- [ ] Retire transient top-right feed; keep discovery toast.

### Phase 7 — Multi-quest tracker
- [ ] `QuestLog.active_quests()` enumeration.
- [ ] Tracker renders all active quests + objective lines/counters; reposition under minimap.

### Phase 8 — Integration & polish
- [ ] Cohesion pass: one palette across every widget; no overlaps at 1080p + ultrawide.
- [ ] Full `tests/run.sh`; new smoke tests green; capture a verification screenshot into `docs/hud-redesign/result.png`.
- [ ] Update `scripts/AGENTS.md` + `objects/AGENTS.md`.

---

## 8. Acceptance Criteria (testable)

**Global**
- `tests/run.sh` passes (lint + scene + flow + quest + playthrough) on merged `godot`/`develop` HEAD, not just the feature branch (memory `concurrent-session-pr-bundling`).
- Every display-only widget is `MOUSE_FILTER_IGNORE`; only the action bar slots, menu chips, minimap, and chat scrollbar accept input. No widget swallows world clicks (memory `godot-control-eats-mouse-input`).
- No widget overlaps another at **1920×1080** and **3440×1440** (extend `hud_wow.gd`'s `_assert_no_overlap`).
- Every new widget early-returns / is inert under `SceneRouter.instant_mode` and headless (memory `sgu-cinematics-respect-instant-mode`).

**Per element**
- **A Player frame:** portrait renders circular; level badge shows `GameState` level (or "1" placeholder if no level system); HP bar value == `GameState.health`, text reads `health/MAX_HEALTH`; bar turns red + pulses ≤30% HP.
- **B Target frame:** hidden when `player.current_target == null`; on select, shows target name/level; HP bar hidden when target exposes no HP; clears on Esc/deselect.
- **C Minimap:** present top-right; heading arrow rotates with player yaw; ≥1 POI/room dot renders when `discovered_pois`/`rooms_discovered` non-empty; zone label == current room name. (Headless: assert node tree + data wiring; visual via capture.)
- **D Tracker:** renders N active quests from `QuestLog.active_quests()`; each shows title + objective; hidden when none active.
- **E Chat log:** shows last K of `GameState.log_entries`; new `log_added` appends + auto-scrolls; tab switch works; survives a save/load round-trip (entries persisted).
- **F Action bar:** exactly 4 slots; each shows the *current* binding glyph (rebind a key in test → glyph updates); click fires the slot action.
- **G Menu column:** 4 chips; pressing C/Q/M/B (or clicking) opens the matching panel.
- **H Nameplates:** NPC shows `[Lv] Name`; quest giver shows `?`; marker updates when the quest step changes.
- **I Selection ring:** appears under `current_target`, hidden otherwise, color matches disposition.
- **J Palette:** all framed widgets draw their border from `HudTheme` gold; `hud_wow.gd` cohesion assertions pass against the new palette.

---

## 9. Test Plan

Add headless `SceneTree` smoke scripts under `tests/smoke/` (no GDUnit4), register in `tests/run.sh`:
- `hud_target_frame.gd` — selection set/clear drives the target frame; HP graceful-hide.
- `hud_minimap.gd` — minimap builds; heading arrow exists; dot count tracks `discovered_pois`.
- `hud_chat_log.gd` — `log_added` appends; reads `log_entries`; tab switch; persistence round-trip.
- `hud_nameplate.gd` — nameplate text + quest-marker state from `QuestLog`.
- `hud_action_bar.gd` — 4 slots; glyph reflects `InputMap`; click fires action.
- Extend `hud_wow.gd` — new palette mirror; overlap audit includes minimap + target frame + chat + tracker.

**Test conventions (do not skip — these have bitten this project):**
- Assert the **PASS/assertion COUNT**, not just exit code — a smoke script that fails to *load* exits 0 and reports a false green (memory `godot-smoke-suite-load-failure-false-green`).
- Don't let `instant_mode` skip the real branch you're testing into a null bypass (memory/skill `smoke-test-null-bypass-real-play-branch`).
- Reach autoloads via `root.get_node_or_null("/root/X")` under `-s`; don't use bare global identifiers; no `await process_frame` in `_initialize` (memory `godot-scenetree-script-gotchas`).
- Fresh worktree: run `godot --headless --import` once before tests (memory `godot-worktree-cold-import-cache`).
- Duck-type new `class_name`s in test runners via `get_script().resource_path` (memory `godot-class-name-headless`).
- Visual verification: capture WITHOUT `--headless` (headless = blank PNG), set `current_scene` so the per-scene HUD spawns, then save `get_viewport().get_texture().get_image()` (skill `gh-issue-embed-screenshots`). Beware render-diff baseline poisoning (memory `godot-render-diff-baseline-poisoning`).

---

## 10. Visual Verification Loop
1. Boot a gameplay scene (e.g. `scenes/gate_room.tscn` or `scenes/room.tscn`) non-headless.
2. Capture a 1080p frame → `docs/hud-redesign/result.png`.
3. Compare side-by-side to `wow-hud-reference.png`; calibrate palette/positions.
4. Commit whenever the result is **closer** to the reference; revert if not (Karpathy loop, memory `chris-working-style`). Frequent commits on the feature branch are fine.

---

## 11. Risks, Gotchas & Required Reading

**Memory notes (read before the matching phase):**
- `wow-hud-no-stats-strip` — do NOT add a ship-stats/items strip to the HUD.
- `feedback_godot_wow_style_dialog_window` / `project_fable_dialog_direction` — dialog presentation already exists; the chat log is separate from dialogue subtitles.
- `kino-not-in-player-group` — minimap/nameplate visibility must not assume the player group owns the camera.
- `godot-control-eats-mouse-input` — interactive panels (minimap, chat, action bar, menu chips) must not swallow world clicks.
- `godot-springarm-doorway-curtain` / `kenney_room camera curtain` — the minimap top-down camera will see curtain colliders; put it on its own cull layer.
- `godot-autoload-input-order` — new toggles via `_unhandled_input` fire in reverse autoload order; gate the OPEN path only.
- `godot-png-no-import-sidecar` / `sgu-import-sidecar-after-asset-copy` — any new icon/frame PNG needs `--import` to generate its `.import` sidecar.
- `godot-label3d-on-procedural-mesh` / `godot-subviewport-text-on-procedural-mesh` — nameplate text rendering gotchas.
- `godot-third-person-camera` (skill) — for the minimap follow camera.

**Hard constraints:**
- **Save policy:** any new autoload holding gameplay state must `SaveManager.register_system(...)` or carry `# @no-save:` (pre-commit lint, `tests/lint/check_save_registration.sh`). Target selection is runtime-only → if you add a manager, mark it `# @no-save: transient UI selection`.
- **Collection-fork policy:** model sets of like things (quests, minimap markers, nameplates) as ONE registry + add/enumerate API, not per-instance bools (pre-commit lint, `tests/lint/check_collection_forks.sh`; memory `scattered-collection-antipattern`).
- **Typed GDScript**, tabs, `snake_case` files/vars, `PascalCase` nodes (CLAUDE.md Dev Conventions).

---

## 12. File-by-File Change Map

| File | Change |
|------|--------|
| `scripts/ui/hud_theme.gd` | **NEW** — palette + stylebox factories (single source of truth). |
| `scripts/hud.gd` | Repoint to `HudTheme`; upgrade unit frame; add target frame; host minimap; reposition action bar; add menu column; add chat panel; multi-quest tracker; retire transient feed. |
| `objects/hud.tscn` | Add container anchors if needed (most stays code-built). |
| `scripts/player.gd` | `current_target` + `target_changed`; selection-ring spawn/clear. |
| `scripts/npc.gd` | Target interface (`get_display_name/level/health/portrait_key/disposition`); nameplate + quest marker. |
| `objects/nameplate.tscn` + `scripts/nameplate.gd` | **NEW** — billboard nameplate widget. |
| `objects/minimap.tscn` (+ `scripts/minimap.gd`) | **NEW** — SubViewport ortho minimap + marker overlay. |
| `scripts/quest_log.gd` | `active_quests()` enumeration; `marker_for(npc_name)`. |
| `scripts/planet_compass.gd` | Keep; gate behind Settings/Kino once minimap replaces it in gameplay. |
| `project.godot` | New input actions `quest_log`/`toggle_map`/`inventory`/`cancel_target`. |
| `tests/smoke/hud_*.gd` | New + extended smoke tests (§9). |
| `tests/run.sh` | Register new smoke groups. |
| `scripts/AGENTS.md`, `objects/AGENTS.md` | Document the new widgets. |

---

## 13. Definition of Done
- All 8 phases merged; `tests/run.sh` green on the integration branch.
- New smoke tests green (asserting counts, not just exit codes).
- A verification capture in `docs/hud-redesign/result.png` that the owner agrees reads like the reference (WoW layout, SGU content, gold palette).
- `AGENTS.md` cheatsheets updated; this HANDOFF kept in sync if the design shifts.
