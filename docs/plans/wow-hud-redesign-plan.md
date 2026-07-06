# WoW-style HUD Redesign — Implementation Plan

> **Status:** Planning (2026-07-06)
> **Author:** Planner agent
> **Relates to:** Issue #141 (epic), `docs/hud-redesign/HANDOFF.md` (deep spec),
> `docs/hud-redesign/wow-hud-reference.png` (visual target)
> **Branch:** `feature/wow-hud-redesign` (to be created from `develop`)

## Overview

Re-skin and extend the in-game HUD (`scripts/hud.gd` + `objects/hud.tscn`) to match
the WoW reference layout, anatomy, and gold-on-dark palette while keeping Stargate
Universe content (Eli/crew, Health + Oxygen, Destiny rooms). We adopt the WoW
*structure*, not the fantasy *content*.

## Current State Assessment

Significant work is **already landed** on the current branch. This plan accounts
for that and focuses each phase on the **remaining** work. A summary of what
exists today (verified by reading the code):

| Element | Status | Evidence |
|---------|--------|----------|
| `scripts/ui/hud_theme.gd` | ✅ EXISTS | `HudTheme` class with gold palette + `panel_stylebox` / `bar_fill_stylebox` / `style_label` factories (66 lines) |
| `scripts/ui/minimap.gd` | ✅ EXISTS | Control-based `_draw` radar disc, markers, heading arrow (56 lines) — integrated in `hud.gd::_build_minimap` / `_update_minimap` |
| Gold palette in `hud.gd` | ✅ DONE | `SKIN_ACCENT` = gold `Color(0.83,0.66,0.32)`; all widgets repointed |
| Player unit frame | ✅ MOSTLY | Portrait + name + HP/O2 bars + level badge + numeric `cur/max` overlays + critical pulse. **PENDING:** circular portrait mask, role icon badge |
| Action bar (4-slot) | ✅ MOSTLY | Bottom-center CenterContainer, 4 fixed slots, kbd + gamepad glyphs, click-to-fire. **PENDING:** menu-button column |
| Chat / Combat log | ✅ PARTIAL | Tabbed Chat/Combat panel, narrative-fed (dialogue_shown + narrative_added), transient feed retired. **PENDING:** reposition bottom-left, `log_entries` seeding decision |
| Quest tracker | ⚠️ SINGLE | One quest title + one objective. **PENDING:** `active_quests()` multi-quest enumeration |
| `hud_wow.gd` palette mirror | ✅ UPDATED | Mirrors gold `SKIN_ACCENT` / `SKIN_ACCENT_GOLD` |
| `hud_chat.gd` smoke test | ✅ EXISTS | Asserts narrative-only transcript, no system-journal seed |
| Input actions (`quest_log`/`toggle_map`/`inventory`/`cancel_target`) | ❌ MISSING | Not in `project.godot [input]` |
| Player `current_target` / `target_changed` | ❌ MISSING | `player.gd` has `_clicked_target` + `interact_target_changed` only |
| Target frame | ❌ MISSING | No target unit frame in `hud.gd` |
| Selection ring | ❌ MISSING | No decal/ring under target |
| `nameplate.gd` / `objects/nameplate.tscn` | ❌ MISSING | No world-space nameplates |
| `QuestLog.marker_for()` / `active_quests()` | ❌ MISSING | Not in `quest_log.gd` |
| NPC target interface | ❌ MISSING | `npc.gd` has no `get_display_name`/`get_level`/`get_health`/`get_portrait_key`/`get_disposition` |
| `objects/minimap.tscn` | N/A | Minimap is code-built Control (no .tscn); acceptable per HANDOFF approach B |
| Linear compass replacement | ❌ PENDING | `planet_compass.gd` still spawns in all gameplay scenes; minimap does not replace it yet |

## Global Acceptance Criteria (apply to every phase)

- [ ] `tests/run.sh` passes (lint + scene + flow + quest + playthrough) on the
      **merged** integration branch, not just the feature branch.
- [ ] Every display-only widget is `MOUSE_FILTER_IGNORE`; only action-bar slots,
      menu chips, minimap, and chat scrollbar accept input — no widget swallows
      world clicks.
- [ ] No widget overlaps another at **1920×1080** and **3440×1440** (extend
      `hud_wow.gd::_assert_no_overlap` to include minimap + target frame + chat +
      tracker + menu column).
- [ ] Every new widget early-returns / is inert under `SceneRouter.instant_mode`
      and headless.
- [ ] Typed GDScript, tabs, `snake_case` files/vars, `PascalCase` nodes
      (CLAUDE.md conventions).
- [ ] Save policy: any new autoload with state must `SaveManager.register_system`
      or carry `# @no-save:`. Target selection is runtime-only.
- [ ] Collection-fork policy: model sets (quests, markers, nameplates) as ONE
      registry + add/enumerate API, not per-instance bools.

## Test Conventions (apply to every new smoke test)

- Assert the PASS/assertion **count**, not just exit code — a smoke script that
  fails to load exits 0 (false green).
- Don't let `instant_mode` null-bypass the branch under test.
- Reach autoloads via `root.get_node_or_null("/root/X")` under `-s`; no
  `await process_frame` in `_initialize`.
- Fresh worktree: run `godot --headless --import` once before tests.
- Duck-type new `class_name`s in test runners via `get_script().resource_path`.
- Visual capture: run **without** `--headless`, set `current_scene` so the HUD
  spawns, save `get_viewport().get_texture().get_image()`.

---

## Phase 0 — Theme Foundation

**Goal:** Single source of truth for the gold-on-dark skin; input actions for the
menu column + selection clear. Most of this phase is **already done** — the
remaining work is the input actions.

### Remaining Tasks

1. Add input actions to `project.godot [input]` (keyboard + gamepad button each):
   - `quest_log` — **Q** (`physical_keycode: 81`) + face button (e.g. `JOY_BUTTON_BACK` or a Y/triangle mapping)
   - `toggle_map` — **M** (`physical_keycode: 77`)
   - `inventory` — **B** (`physical_keycode: 66`)
   - `cancel_target` — **Esc** (`physical_keycode: 4194305`) — gate carefully against `pause` (memory `godot-autoload-input-order`); the OPEN path only
2. Verify `hud_theme.gd` palette constants match `hud.gd` `SKIN_*` inline literals (already mirrored; add a cohesion assertion if not present).

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `project.godot` | Add 4 input actions under `[input]` with kbd + joypad events | **NEW** |
| `scripts/ui/hud_theme.gd` | No change (already exists, palette complete) | ✅ done |
| `scripts/hud.gd` | No change (already repointed to gold palette) | ✅ done |
| `tests/smoke/hud_wow.gd` | Verify palette mirror (`:33-35`) matches gold values; the assertion text at `:89` still says "cool-blue" — update label to "gold" | **PATCH** (label fix) |

### Test Plan

- **Extend `hud_wow.gd`:** assert `HudTheme.ACCENT_GOLD` matches `hud.gd::SKIN_ACCENT` (cross-reference, not just a hardcoded mirror).
- **New `tests/smoke/hud_input_actions.gd`:** assert `InputMap.has_action("quest_log")`, `"toggle_map"`, `"inventory"`, `"cancel_target"`; assert each has ≥1 keyboard + ≥1 joypad event. Assert `cancel_target` keyboard event does not collide with `pause` handling (both use Esc — document the gate).
- Register in `tests/run.sh`.
- Run: `tests/run.sh hud-wow` + `tests/run.sh hud-input-actions` (new).

### Acceptance Criteria

- [ ] `InputMap.has_action()` returns true for all 4 new actions.
- [ ] Each action has a keyboard + a gamepad event.
- [ ] `hud_wow.gd` passes with gold palette assertions (no "cool-blue" label remnants).
- [ ] No existing input action broke (regression: `character_pane`, `pause`, `kino_remote` still fire).

---

## Phase 1 — Player Unit Frame Upgrade

**Goal:** Circular portrait, role/class icon badge, numeric overlays. The frame,
level badge, and numeric overlays already exist — the remaining work is the
circular portrait mask and role icon.

### Remaining Tasks

1. Mask the existing `TextureRect` portrait into a circle (use a `clip_children` 
   clip or a circular shader / `StyleBoxTexture` mask, or reparent the portrait
   under a `TextureRect` with a circular mask texture).
2. Add a role/class icon badge (small icon top-right or bottom-right of the
   portrait) — a placeholder sci-fi role icon for Eli (e.g. "engineer" glyph).
   Wire to a constant or `GameState` if a role system emerges later.

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/hud.gd` | `_build_unit_frame()`: add circular mask to `PortraitFrame`/`Portrait`; add `RoleIcon` badge `TextureRect` | **PATCH** (`:375-458`) |
| `scripts/ui/hud_theme.gd` | Add `ROLE_ICON_COLOR` constant if needed | **PATCH** (minor) |
| `tests/smoke/hud_wow.gd` | Assert `PortraitFrame` has a child named `RoleIcon`; assert portrait render mode supports circular clipping | **PATCH** |

### Test Plan

- **Extend `hud_wow.gd`:** assert `UnitFrame/PortraitFrame/RoleIcon` exists as a `TextureRect`.
- **Extend `tests/smoke/hud_scale.gd`:** assert unit frame still anchors top-left at 1080p + ultrawide after portrait changes.
- Visual: capture a frame, confirm portrait reads circular (Karpathy loop against `wow-hud-reference.png`).

### Acceptance Criteria

- [ ] Portrait renders circular (not square) in visual capture.
- [ ] `RoleIcon` node exists under `PortraitFrame`.
- [ ] Level badge + numeric overlays still work (no regression).
- [ ] Health bar turns red + pulses ≤30% HP (no regression).

---

## Phase 2 — Target Frame + Selection

**Goal:** First-class selection on the player, a target unit frame, and a
disposition-tinted selection ring under the target.

### Tasks

1. `player.gd`: add `var current_target: Node = null` and `signal target_changed(target: Node)`. Set on click-to-select (reuse `_clicked_target` flow at `:449-452`); emit `target_changed`. Clear on Esc (`cancel_target` action), click-empty, or out-of-range. Keep the existing `interact_target_changed` for the prompt; `target_changed` is the selection signal.
2. `npc.gd`: implement the target interface (duck-typed):
   - `get_display_name() -> String` → return `character_name`
   - `get_level() -> int` → return 0 (hide badge, most NPCs have no level)
   - `get_health() -> float` → return 0.0
   - `get_max_health() -> float` → return 0.0 (hide HP bar)
   - `get_portrait_key() -> String` → return `character_name` (feeds `portrait_loader.gd`)
   - `get_disposition() -> String` → return `"neutral"` (override per NPC later)
3. `hud.gd`: build the target unit frame (top-left, right of player frame):
   - Portrait (circular, reuse Phase 1 mask), name label, level badge (hide if `get_level() ≤ 0`), HP bar (hide if `get_max_health() ≤ 0`).
   - Connect to `player.target_changed`; hidden when `current_target == null`.
4. Selection ring: spawn a flat ground ring (Decal or unshaded mesh) under `current_target` feet. Color by disposition (yellow = neutral/selected, red = hostile, green = friendly). Hidden when no target. Skip under `SceneRouter.instant_mode`.
   - **Implementation choice:** Decal node parented to the target's scene, or a shared `MeshInstance3D` (torus/quad with shader) repositioned each frame. Decal is simpler in Godot 4.
   - **Cull layer:** put the ring on its own cull layer so it doesn't conflict with camera-curtain colliders (memory `godot-springarm-doorway-curtain`).

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/player.gd` | Add `current_target` + `target_changed` signal; wire click-select → emit; Esc/click-empty → clear + emit null | **PATCH** (`:7,37,413-452`) |
| `scripts/npc.gd` | Add 6 target-interface methods | **PATCH** (new methods) |
| `scripts/hud.gd` | Add `_build_target_frame()`, `_on_target_changed()`, `_refresh_target_frame()`; connect to `player.target_changed` in `_bind_player` | **PATCH** |
| `scripts/hud.gd` | Add `_build_selection_ring()` / `_update_selection_ring()` (Decal or mesh); update in `_process` | **PATCH** |
| `objects/hud.tscn` | No change (target frame is code-built) | — |
| `tests/smoke/hud_target_frame.gd` | **NEW** — selection set/clear drives target frame; HP graceful-hide | **NEW** |

### Test Plan

- **`tests/smoke/hud_target_frame.gd` (NEW):**
  - Instantiate HUD + a mock NPC with the target interface.
  - Set `player.current_target = npc` → assert `TargetFrame` visible, name == `npc.get_display_name()`.
  - Set `current_target = null` → assert `TargetFrame` hidden.
  - Mock NPC with `get_max_health() = 0` → assert HP bar hidden, name still shown.
  - Mock NPC with `get_level() = 5` → assert level badge shows "5".
  - Mock NPC with `get_level() = 0` → assert level badge hidden.
  - Assert selection ring node exists under HUD or target when target set; hidden when null.
  - Assert count of PASS assertions printed.
- Register in `tests/run.sh`.
- Visual: capture a frame with a selected NPC, confirm ring + target frame.

### Acceptance Criteria

- [ ] `player.current_target` is null by default; set on click-select; cleared on Esc/click-empty/out-of-range.
- [ ] `target_changed` signal fires on set and clear (null).
- [ ] Target frame hidden when `current_target == null`; visible on select.
- [ ] Target frame shows name + level; HP bar hidden when target exposes no HP.
- [ ] Selection ring appears under `current_target`, hidden otherwise, color matches disposition.
- [ ] Both inert under `instant_mode` / headless.

---

## Phase 3 — Nameplates + Quest Markers

**Goal:** World-space `Label3D` nameplates on NPCs/enemies with quest-marker glyphs
(`?` available / `!` turn-in / `✓` complete) and an optional HP sub-bar.

### Tasks

1. `quest_log.gd`: add `marker_for(npc_name: String) -> String` — returns `""` / `"?"` / `"!"` / `"✓"` by querying active steps for whether this NPC is a quest giver/turn-in. Use the ONE-registry pattern (collection-fork lint): iterate `_quests` + `_active_step` targets, not per-NPC bools.
2. Create `scripts/nameplate.gd` + `objects/nameplate.tscn`:
   - `Label3D` (billboard ON) rendering `[Lv] Name` (level bracket hidden when level ≤ 0).
   - Optional quest-marker glyph `Label3D` above the name, driven by `QuestLog.marker_for(name)`.
   - Optional thin HP sub-bar (`Sprite3D` or small `SubViewport` ProgressBar) for nodes that expose HP.
   - Repositions to sit above the NPC's head (reuse `npc.gd`'s ambient bubble anchor y≈2.0–2.42; keep clear of the ambient speech bubble).
3. `npc.gd`: spawn/attach the nameplate in `_ready`; refresh the quest marker on `QuestLog.quest_step_changed`.
   - **Gotcha:** nameplate visibility must key off the on-foot player camera, not assume the player group owns the camera (Kino drone is NOT in group "player" — memory `kino-not-in-player-group`).

### New Files

| File | Purpose |
|------|---------|
| `scripts/nameplate.gd` | Billboard nameplate widget (Label3D name + level + quest marker + optional HP bar) |
| `objects/nameplate.tscn` | Scene wrapper for the nameplate (if used as an instance; alternatively code-built in `npc.gd`) |

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/nameplate.gd` | **NEW** — nameplate widget | **NEW** |
| `objects/nameplate.tscn` | **NEW** — nameplate scene (optional if code-built) | **NEW** |
| `scripts/quest_log.gd` | Add `marker_for(npc_name)` method | **PATCH** |
| `scripts/npc.gd` | Spawn nameplate in `_ready`; refresh marker on quest step change; expose level/name to nameplate | **PATCH** |
| `tests/smoke/hud_nameplate.gd` | **NEW** — nameplate text + quest-marker state | **NEW** |

### Test Plan

- **`tests/smoke/hud_nameplate.gd` (NEW):**
  - Instantiate an NPC, assert a `Nameplate` child exists.
  - Assert nameplate text contains the NPC's `character_name`.
  - Mock `QuestLog.marker_for(name)` → `"?"` → assert marker glyph visible + text == "?".
  - Mock `marker_for` → `""` → assert marker hidden.
  - NPC with `get_level() = 0` → assert level bracket hidden.
  - NPC with `get_level() = 7` → assert `[7]` in nameplate text.
  - Assert PASS count.
- Register in `tests/run.sh`.
- Visual: capture a scene with NPCs, confirm nameplates render above heads.

### Acceptance Criteria

- [ ] NPC shows `[Lv] Name` (level bracket hidden when level ≤ 0).
- [ ] Quest giver shows `?`; marker updates when the quest step changes.
- [ ] Nameplate doesn't overlap the ambient speech bubble.
- [ ] Nameplate inert under `instant_mode` / headless (no Label3D spawned or hidden).
- [ ] `QuestLog.marker_for()` follows the one-registry pattern (no per-NPC bool flags).

---

## Phase 4 — Circular Minimap (Completion)

**Goal:** The minimap Control already exists and is integrated. The remaining work
is to (a) feed it POI/room dots from `discovered_pois`/`rooms_discovered` (not just
quest waypoint + interactables), and (b) replace the linear compass in gameplay
(keep `planet_compass.gd` behind a Settings flag / Kino).

### Remaining Tasks

1. `hud.gd::_update_minimap()`: add POI/room dots from `GameState.discovered_pois` (Dict) and `GameState.rooms_discovered` — project their world positions into the disc (reuse `_append_marker`). Use a distinct color (e.g. dim cyan) from quest/interact markers.
2. Compass replacement: gate `spawn_compass()` behind a `Settings` flag (e.g. `linear_compass_enabled`, default false in gameplay) OR suppress it when the minimap is active. Keep `planet_compass.gd` usable for the Kino overlay.
   - Add a `Settings` property if one doesn't exist (check `scripts/settings.gd`).
3. Zone/room name label already exists (`_minimap_name`); verify it reads `GameState.current_room_id` → `ShipLayout.room(id).name` (already wired at `:682-685`).

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/hud.gd` | Extend `_update_minimap()` to add POI/room dots; gate `spawn_compass()` behind Settings | **PATCH** (`:637-708, 320-351`) |
| `scripts/settings.gd` | Add `linear_compass_enabled: bool = false` (or reuse if present) | **PATCH** |
| `scripts/ui/minimap.gd` | No change (drawing complete) | ✅ done |
| `tests/smoke/hud_minimap.gd` | **NEW** — minimap builds, heading arrow exists, dot count tracks `discovered_pois` | **NEW** |

### Test Plan

- **`tests/smoke/hud_minimap.gd` (NEW):**
  - Instantiate HUD, assert `Minimap` Control exists top-right.
  - Assert `_minimap_name` label exists.
  - Mock `GameState.discovered_pois` non-empty → assert `set_markers` called with ≥1 POI marker (spy on the minimap's marker array via `_markers`).
  - Assert heading arrow renders (check the widget is not errored; visual via capture).
  - Set `GameState.current_room_id` → assert label text == room name.
  - Assert PASS count.
- Register in `tests/run.sh`.
- Visual: capture, confirm minimap disc + markers + zone name.

### Acceptance Criteria

- [ ] Minimap present top-right; heading arrow rotates with player yaw.
- [ ] ≥1 POI/room dot renders when `discovered_pois`/`rooms_discovered` non-empty.
- [ ] Zone label == current room name.
- [ ] Linear compass does NOT spawn in gameplay when minimap is active (unless Settings flag overrides).
- [ ] `planet_compass.gd` still works for Kino overlay (no deletion).
- [ ] Minimap inert under `instant_mode` / headless.

---

## Phase 5 — Action Bar (4-slot) + Menu Column

**Goal:** The 4-slot action bar is done. The remaining work is the bottom-right
menu-button column (C/Q/M/B) opening existing panels.

### Remaining Tasks

1. `hud.gd`: build a vertical `VBoxContainer` bottom-right named `MenuColumn` with 4 chips:
   - **Character (C)** → opens `CharacterPanel` (autoload, action `character_pane` already exists)
   - **Quest (Q)** → opens quest panel / log (action `quest_log` from Phase 0)
   - **Map (M)** → opens Kino map / `kino_remote` (action `toggle_map`)
   - **Bags (B)** → opens inventory (action `inventory`)
   - Each chip: small Panel + Label with key glyph + label; `gui_input` fires the action; key press also fires it (handled via `_unhandled_input` or `InputMap` action).
2. Wire key presses: in `hud.gd::_unhandled_input` (or a dedicated handler), on `quest_log`/`toggle_map`/`inventory` action press → open the matching panel. Gate the OPEN path only (memory `godot-autoload-input-order`).
3. Render glyphs from `InputMap` so the chips reflect actual binds.

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/hud.gd` | Add `_build_menu_column()`, `_make_menu_chip()`, `_on_menu_chip_input()`, `_on_menu_action()` | **PATCH** |
| `tests/smoke/hud_action_bar.gd` | **NEW** — 4 slots + glyph reflects InputMap + 4 menu chips + click/key fires action | **NEW** |

### Test Plan

- **`tests/smoke/hud_action_bar.gd` (NEW):**
  - Assert `ActionBar` has exactly 4 slots.
  - Rebind a key in `InputMap` → assert glyph updates after `_refresh_action_bar`.
  - Assert `MenuColumn` exists bottom-right with 4 chips (Character/Quest/Map/Bags).
  - Simulate chip click → assert the action fires (mock the panel open or check a signal).
  - Assert PASS count.
- Register in `tests/run.sh`.
- Visual: capture, confirm menu column bottom-right.

### Acceptance Criteria

- [ ] Action bar has exactly 4 slots; glyph reflects current `InputMap` binding.
- [ ] Menu column has 4 chips (C/Q/M/B); click or key opens the matching panel.
- [ ] Menu column bottom-right, action bar bottom-center — no overlap at 1080p/ultrawide.
- [ ] Chips + slots accept input; surrounding containers are `MOUSE_FILTER_IGNORE`.

---

## Phase 6 — Persistent Tabbed Chat/Combat Log (Completion)

**Goal:** The chat panel exists (tabbed Chat/Combat, narrative-fed). The remaining
work is repositioning it bottom-left (HANDOFF spec) and reconciling the
`log_entries` seeding decision.

### Remaining Tasks

1. **Position:** Move `_chat_panel` from bottom-right (`anchor_right=1.0`) to bottom-left (`anchor_left=0.0`). This frees the bottom-right for the menu column (Phase 5). Update offsets.
2. **Seeding decision:** The current implementation is narrative-only (dialogue_shown + narrative_added), intentionally NOT seeded from `GameState.log_entries` (documented at `hud.gd:1239-1242`). The HANDOFF §5.5 says "back it with `GameState.log_entries`". **Resolve with owner:** keep narrative-only (current, tested) OR add a `log_entries`-backed "System" tab. Recommend: keep narrative-only for Chat, add an optional "System" tab backed by `log_entries` if the owner wants it. Flag in the PR.
3. **Overlap audit:** chat panel (bottom-left) vs unit frame (top-left) vs action bar (bottom-center) vs menu column (bottom-right) — no overlap at 1080p + ultrawide.

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/hud.gd` | Reposition `_chat_panel` to bottom-left (`:1205-1214`); update `_build_chat_panel` anchors | **PATCH** |
| `tests/smoke/hud_chat.gd` | Update position assertions; assert bottom-left anchoring | **PATCH** |
| `tests/smoke/hud_wow.gd` | Add chat panel to the overlap audit | **PATCH** |

### Test Plan

- **Extend `hud_chat.gd`:** assert `_chat_panel.anchor_left == 0.0` (bottom-left).
- **Extend `hud_wow.gd::_assert_no_overlap`:** include chat panel rect vs action bar + menu column.
- Visual: capture, confirm chat bottom-left.

### Acceptance Criteria

- [ ] Chat panel bottom-left (not bottom-right).
- [ ] Chat/Combat tabs switch correctly.
- [ ] `dialogue_shown` + `narrative_added` append + auto-scroll; system-journal noise excluded.
- [ ] Chat survives a save/load round-trip (narrative transcript persists via `GameState` if backed, or is session-only — document the decision).
- [ ] No overlap with action bar / menu column / unit frame at 1080p + ultrawide.

---

## Phase 7 — Multi-Quest Tracker

**Goal:** Enumerate all active quests (not just one) with title + objective lines
+ counters, positioned under the minimap.

### Tasks

1. `quest_log.gd`: add `active_quests() -> Array[String]` — all started, non-complete quests (iterate `_progress`, filter `started == true` and `not is_complete(id)`). Use the one-registry pattern.
2. `hud.gd`: rewrite `_refresh_quest_tracker()` to render N quests:
   - For each quest in `active_quests()`: gold title + objective line(s) (prefix `☐` or `-`).
   - Counters (`0/5`) come from the objective text (already dynamic via `objective_fn`).
   - Stack quests vertically under the minimap (top-right, below `MINIMAP_POS_TOP + MINIMAP_SIZE`).
3. Reposition: tracker sits **under the minimap** (minimap owns the very top-right corner). `TRACKER_POS_TOP` already moved to `196.0` (`:151`) — verify it clears the minimap.

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/quest_log.gd` | Add `active_quests()` method | **PATCH** |
| `scripts/hud.gd` | Rewrite `_build_quest_tracker()` / `_refresh_quest_tracker()` for N quests | **PATCH** (`:999-1074`) |
| `tests/smoke/quest_log.gd` | Add assertions for `active_quests()` | **PATCH** |
| `tests/smoke/hud_wow.gd` | Update tracker assertions for multi-quest | **PATCH** |

### Test Plan

- **Extend `tests/smoke/quest_log.gd`:** assert `active_quests()` returns `["e1_air"]` by default; mock a second started quest → assert 2 entries; complete one → assert it drops out.
- **Extend `hud_wow.gd`:** assert tracker renders N titles when N quests active; assert hidden when none.
- Visual: capture with 2 quests, confirm both render under minimap.

### Acceptance Criteria

- [ ] `QuestLog.active_quests()` returns all started, non-complete quest IDs.
- [ ] Tracker renders N quests, each with title + objective line.
- [ ] Tracker hidden when no active quests.
- [ ] Tracker positioned under the minimap (no overlap at 1080p/ultrawide).
- [ ] `active_quests()` follows the one-registry pattern.

---

## Phase 8 — Integration & Polish

**Goal:** Cohesion pass across every widget, full test suite green, verification
capture.

### Tasks

1. **Cohesion pass:** every framed widget draws its border from `HudTheme` gold (or `hud.gd::SKIN_ACCENT`). Audit `_make_wow_stylebox` usage — no widget should redefine its own palette.
2. **Overlap audit:** extend `hud_wow.gd::_assert_no_overlap` to check all widget pairs: unit frame (UL), minimap (UR), tracker (UR under minimap), target frame (UL right of player), chat (BL), action bar (BC), menu column (BR), discovery toast (center). Test at 1920×1080 and 3440×1440.
3. **Mouse filter audit:** every display-only widget is `MOUSE_FILTER_IGNORE`; only action slots, menu chips, minimap, chat scrollbar accept input.
4. **Full `tests/run.sh`:** all smoke groups green on the integration branch.
5. **Verification capture:** boot a gameplay scene non-headless, capture 1080p → `docs/hud-redesign/result.png`. Compare to `wow-hud-reference.png`; calibrate (Karpathy loop).
6. **Docs:** update `scripts/AGENTS.md` + `objects/AGENTS.md` with the new widgets (target frame, nameplate, minimap, menu column, chat panel, multi-quest tracker).
7. **Lint:** `tests/lint/check_save_registration.sh` + `tests/lint/check_collection_forks.sh` pass (target selection runtime-only; quests/markers/nameplates as registries).

### File-by-File Changes

| File | Change | Status |
|------|--------|--------|
| `scripts/hud.gd` | Final palette cohesion fixes if any drift found | **PATCH** |
| `scripts/ui/hud_theme.gd` | Add any missing constants discovered in audit | **PATCH** |
| `tests/smoke/hud_wow.gd` | Full overlap + mouse-filter + palette audit | **PATCH** |
| `docs/hud-redesign/result.png` | **NEW** — verification capture | **NEW** |
| `scripts/AGENTS.md` | Document new HUD widgets | **PATCH** |
| `objects/AGENTS.md` | Document new scenes (nameplate, minimap if .tscn) | **PATCH** |

### Test Plan

- Run `tests/run.sh all` — expect all green.
- Run lint subset: `tests/run.sh lint`.
- Visual: capture + compare to reference; commit if closer.
- Confirm `result.png` saved.

### Acceptance Criteria

- [ ] `tests/run.sh all` green on the integration branch.
- [ ] All new smoke tests green (asserting counts, not just exit codes).
- [ ] `docs/hud-redesign/result.png` exists and the owner agrees it reads like the reference.
- [ ] `AGENTS.md` cheatsheets updated.
- [ ] No widget overlaps at 1080p + ultrawide.
- [ ] Lint passes (save registration + collection forks).

---

## New Files Summary

| File | Phase | Purpose |
|------|-------|---------|
| `scripts/nameplate.gd` | 3 | Billboard Label3D nameplate (name + level + quest marker + optional HP bar) |
| `objects/nameplate.tscn` | 3 | Nameplate scene wrapper (optional if code-built in `npc.gd`) |
| `tests/smoke/hud_target_frame.gd` | 2 | Target frame set/clear + HP graceful-hide + selection ring |
| `tests/smoke/hud_minimap.gd` | 4 | Minimap builds + markers + zone label |
| `tests/smoke/hud_nameplate.gd` | 3 | Nameplate text + quest-marker state |
| `tests/smoke/hud_action_bar.gd` | 5 | 4 slots + glyph reflects InputMap + menu chips |
| `tests/smoke/hud_input_actions.gd` | 0 | InputMap has the 4 new actions with kbd + joypad events |
| `docs/hud-redesign/result.png` | 8 | Verification capture |

> **Note on `hud_theme.gd`, `nameplate.gd`, `minimap.gd`:** `hud_theme.gd` and
> `minimap.gd` already exist and are integrated. `nameplate.gd` is the primary
> net-new script to create (Phase 3). The plan honors the task's requirement to
> identify these three files; two are done, one is pending.

## Dependencies

- Phase 0 (input actions) is a dependency for Phase 5 (menu column keybinds) and
  Phase 2 (`cancel_target` for Esc-clear).
- Phase 1 (circular portrait mask) is a dependency for Phase 2 (target frame
  reuses the mask).
- Phase 2 (player.current_target + target interface on NPCs) is a dependency for
  Phase 3 (nameplates query the same interface for level/name).
- Phase 4 (minimap owns top-right) is a dependency for Phase 7 (tracker under
  minimap) and Phase 6 (chat moves bottom-left to avoid the minimap corner).
- Phase 5 (menu column bottom-right) is a dependency for Phase 6 (chat moves
  bottom-left; menu column claims bottom-right).

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Esc overloads `pause` + `cancel_target` (memory `godot-autoload-input-order`) | Gate the OPEN path only; `cancel_target` clears selection before `pause` fires; document the ordering |
| Circular portrait mask rendering gotchas in Godot 4 | Use `clip_children = CLIP_CHILDREN_AND_DRAW` or a circular mask texture; fallback to a circular `StyleBoxTexture` |
| Nameplate Label3D on procedural meshes (memory `godot-label3d-on-procedural-mesh`) | Use `billboard = BILLBOARD_ENABLED` + fixed pixel size; test on the gate_room scene |
| Minimap SubViewport sees curtain colliders (memory `godot-springarm-doorway-curtain`) | Current approach is Control-based `_draw` (no camera) — already avoids this; if switching to SubViewport, use a dedicated cull layer |
| Chat panel eats world clicks (memory `godot-control-eats-mouse-input`) | Set backing layer `MOUSE_FILTER_IGNORE` outside the panel rect; only the scrollbar + tabs accept input |
| Class_name headless race (memory `godot-class-name-headless`) | Duck-type new `class_name`s in test runners via `preload` path |
| Render-diff baseline poisoning (memory `godot-render-diff-baseline-poisoning`) | Clear baselines before capturing; use fresh worktree |

## Definition of Done

- All 8 phases merged; `tests/run.sh all` green on the integration branch.
- New smoke tests green (asserting counts, not just exit codes).
- `docs/hud-redesign/result.png` exists and the owner agrees it reads like the
  reference (WoW layout, SGU content, gold palette).
- `AGENTS.md` cheatsheets updated; `HANDOFF.md` kept in sync if the design shifts.