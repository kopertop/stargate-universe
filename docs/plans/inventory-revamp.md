# Inventory System Revamp — Implementation Plan

> **Status:** Partially implemented (2026-05-30)
> **Author:** User + Claude
> **Created:** 2026-05-30
> **Branch:** `feature/inventory-revamp-plan`
> **Relates to:** `design/gdd/resource-inventory.md` (design intent),
> `design/gdd/kino-remote.md` (host UI), issue #41 (this work), #36 (data-driven pattern this follows)

> ## Implementation status
>
> **Shipped:** `data/items.json` catalog, an `Inventory` autoload, and the
> **slot-grid UI** on the Kino Remote (icon glyphs, stack-count badges, hover
> tooltips, click-to-inspect detail panel). The looted-fuse bug is fixed —
> every carried item now renders from one enumerable surface
> (`Inventory.entries()`). Covered by `tests/smoke/inventory.gd` (34 assertions).
>
> **Deviation from the plan below — `Inventory` is a stateless *projection*, not
> a separate store.** Each item's count is read live from its canonical
> GameState source (`kino_acquired` / `*_fuse_found` / `resources` dict /
> `kino_orbs`). This fixes the user-visible bug and delivers the real catalog +
> UI **without** churning the deeply-used + heavily-tested GameState fields, and
> needs **no serialization or save migration** (counts come from whatever
> GameState already restores). The renderer is fully generic — a new item is a
> catalog row + one `count()` arm.
>
> **Still deferred (the §4.2 "unified store" + §5 full migration):** collapsing
> the fuse bools / `resources` dict / `kino_acquired` into `Inventory` as the
> single source of truth, and real icon art (the catalog `icon` field is wired;
> currently falls back to a procedural letter glyph).

This is an **engineering plan**, not a new GDD. The design intent already lives in
`design/gdd/resource-inventory.md` ("two item categories: stackable resources +
story items"). The current code is a divergent, partial implementation of that
GDD. This plan realigns the implementation with the GDD **and** adds the
icon/slot/tooltip UI the design always called for ("Kino Remote inventory panel").

---

## 1. The bug that triggered this

The player loots three crates in the Shuttle Dock — **Rations**, a **Small Fuse**,
and a **Large Fuse** — yet the Kino Remote inventory page only shows
`Kino Remote` and `Rations × 1`. Both fuses are invisible.

### Root cause — three disjoint storage mechanisms

The "inventory" is not one system. It is three unrelated stores that
`kino_remote.gd::_refresh_inventory()` (`scripts/kino_remote.gd:2092`) reads from,
each with different rendering rules:

| Item | Stored as | Location | Rendered? |
|---|---|---|---|
| Kino Remote | `kino_acquired: bool` (special-case) | `game_state.gd:152` | ✅ hard-coded line |
| Rations / Lime | `resources: Dictionary` (key → count) | `game_state.gd:244` | ✅ with count |
| Small Fuse | `small_fuse_found: bool` | `game_state.gd:208` | ❌ never rendered |
| Large Fuse | `large_fuse_found: bool` | `game_state.gd:209` | ❌ never rendered |
| Kino orbs | `kino_orbs: int` | `game_state.gd` | ❌ shown only on Kino-control page |

The small fuse is *defensible* as hidden — it is consumed when slotted into the
door panel (`shuttle_door_panel.gd`). But the **large fuse is a genuine dead
pickup**: its own loot text says *"Too big for the door panel — pocket it
anyway."* (`game_state.gd:760`), implying the player keeps it, yet it appears
nowhere. Picking up three items and seeing one reads as a broken inventory.

### Why it happened

There is **no item model**. Items are whatever ad-hoc field a feature author
reached for: a bool flag, a dict counter, or a special-cased render line. There
is no catalog, no display name (names are just `resource_type.capitalize()`,
`kino_remote.gd:2111`), no icon, no notion of "this is a thing the player is
holding." Each new item invents its own storage, and the renderer has to know
about each one individually — so new items silently fail to show up.

---

## 2. Goals

1. **Fix the bug by construction** — every looted item lands in one store the UI
   iterates generically, so "picked it up but don't see it" becomes impossible.
2. **One unified item model** backed by a **data-driven catalog** (`data/items.json`),
   consistent with `quests.json` / `planets.json` / `ship_layout.json`.
3. **A real inventory UI** on the Kino Remote inventory page: **slot grid** with
   icons, stack-count badges, click-to-select detail, and hover tooltips.
4. **No regressions** — lime gating (`has_resource(lime, 3)`), the door-panel
   fuse check, kino-orb count, and all save/load round-trips keep working.

### Non-goals (this pass)

- Weight / carry limits / inventory-tetris — the GDD explicitly forbids these
  ("no carry limits, no weight, no inventory tetris", `resource-inventory.md:14`).
- Drag-and-drop reordering, equip slots, crafting.
- Moving inventory off the Kino Remote into a standalone screen (decision: stays
  in the Kino Remote, the diegetic device).
- Authoring the full S1+ resource list (Water/Food/Naquadah/etc. from the GDD) —
  the catalog makes them trivial to add later; this pass seeds only what E1 uses.

---

## 3. Decisions (locked with user)

| Question | Decision |
|---|---|
| UI home | **Stay in the Kino Remote** — upgrade the existing inventory page in place |
| Item model | **Data-driven catalog** — `data/items.json` + unified inventory dict |
| Visual layout | **Slot grid** — icon tiles, stack-count badge, click-to-select, hover tooltip |
| Plan doc home | **Repo file** (`docs/plans/inventory-revamp.md`) + linked from the issue |

---

## 4. Target architecture

Three layers, mirroring the QuestLog refactor (#36):

### 4.1 Data — `data/items.json`

A catalog keyed by stable item id. Ids reuse today's strings where they exist
(`lime`, `rations`) so saves and `has_resource()` calls migrate for free.

```json
[
  {
    "id": "kino_remote",
    "name": "Kino Remote",
    "category": "tool",
    "icon": "res://sprites/ui/items/kino_remote.png",
    "description": "Handheld controller for the Kino reconnaissance orbs.",
    "stackable": false,
    "consumable": false,
    "show_in_inventory": true
  },
  {
    "id": "kino_orb",
    "name": "Kino",
    "category": "tool",
    "icon": "res://sprites/ui/items/kino_orb.png",
    "description": "A floating Ancient camera drone. Deploy it to scout ahead.",
    "stackable": true,
    "consumable": false,
    "show_in_inventory": true
  },
  {
    "id": "rations",
    "name": "Rations",
    "category": "resource",
    "icon": "res://sprites/ui/items/rations.png",
    "description": "Vacuum-sealed crew meals salvaged from a supply crate.",
    "stackable": true,
    "consumable": true,
    "show_in_inventory": true
  },
  {
    "id": "lime",
    "name": "Lime",
    "category": "resource",
    "icon": "res://sprites/ui/items/lime.png",
    "description": "Calcium compound for the CO2 scrubber cartridge bed.",
    "stackable": true,
    "consumable": true,
    "show_in_inventory": true
  },
  {
    "id": "small_fuse",
    "name": "Small Fuse",
    "category": "story_item",
    "icon": "res://sprites/ui/items/fuse_small.png",
    "description": "A small replacement fuse. Looks like it would fit a door panel.",
    "stackable": false,
    "consumable": true,
    "show_in_inventory": true
  },
  {
    "id": "large_fuse",
    "name": "Large Fuse",
    "category": "story_item",
    "icon": "res://sprites/ui/items/fuse_large.png",
    "description": "Too big for the jammed door panel — pocketed for later.",
    "stackable": false,
    "consumable": false,
    "show_in_inventory": true
  }
]
```

**Field reference**

| Field | Type | Meaning |
|---|---|---|
| `id` | string (req) | Stable key; equals existing resource strings where one exists. |
| `name` | string | Display name (replaces `capitalize()` guessing). |
| `category` | enum | `tool` \| `resource` \| `story_item` — drives grouping + sort order. |
| `icon` | string | `res://` path to the slot icon (64×64 PNG). |
| `description` | string | Tooltip + detail-panel body. |
| `stackable` | bool | Multiple held → one slot with a count badge. |
| `consumable` | bool | Can be spent (rations, lime, small fuse). |
| `show_in_inventory` | bool | False for purely-internal flags we don't want surfaced. |

### 4.2 Runtime — `Inventory` (autoload) or a section of `GameState`

A single unified store, replacing the three ad-hoc mechanisms:

```gdscript
# item id -> count. Non-stackable items are 0 or 1.
var _items: Dictionary = {}

func add_item(id: String, amount: int = 1, source: String = "") -> void
func remove_item(id: String, amount: int = 1, reason: String = "") -> bool
func count(id: String) -> int
func has(id: String, amount: int = 1) -> bool
func entries() -> Array          # [{id, def, count}] for display, filtered + sorted
signal item_changed(id: String, count: int)
```

**Decision point (resolve during build):** new `Inventory` autoload vs. fold into
`GameState`. Recommendation: **new `Inventory` autoload** — keeps `game_state.gd`
(already 1100+ lines) from growing, registers cleanly with `SaveManager`
(`register_system("inventory", self)`, satisfies the save-registration lint), and
matches the QuestLog precedent. `GameState` keeps thin back-compat shims (below).

### 4.3 UI — Kino Remote inventory page (slot grid)

Replace the `VBoxContainer` of text `_label`s
(`kino_remote.gd::_build_inventory_page:435`, `_refresh_inventory:2092`) with a
`GridContainer` of slot controls:

- **Slot** = `Panel` + `TextureRect` (icon) + count `Label` badge (bottom-right,
  hidden when count ≤ 1 or non-stackable).
- **Hover** → Godot `tooltip_text` (or a custom tooltip Control) with name +
  description, via `mouse_entered` / `mouse_exited` or `_make_custom_tooltip`.
- **Click** → `gui_input` selects the slot, populating a detail sub-panel (larger
  icon + name + full description) beside/below the grid. Reuses the existing
  `gui_input` plumbing the map page already uses (`kino_remote.gd:816, 1685`).
- Empty grid → `(empty)` placeholder, as today.

---

## 5. Migration map (old → new)

| Old | New |
|---|---|
| `kino_acquired` (bool) | `add_item("kino_remote")` on acquire; bool kept as derived shim |
| `resources["rations"]`, `resources["lime"]` | `_items["rations"]`, `_items["lime"]` |
| `small_fuse_found` (bool) | `add_item("small_fuse")`; `small_fuse_found` → `Inventory.has("small_fuse")` shim |
| `large_fuse_found` (bool) | `add_item("large_fuse")`; shim likewise |
| `kino_orbs` (int) | `_items["kino_orb"]` (display); count logic can stay or delegate |
| `add_resource(t, n)` | `Inventory.add_item(t, n)` (keep `add_resource` as shim → emits `resource_changed`) |
| `has_resource(t, n)` | `Inventory.has(t, n)` shim |
| `resource_count(t)` | `Inventory.count(t)` shim |

**Back-compat is the safety net.** Every reader keeps its current call —
`has_resource(AIR_LIME_RESOURCE, AIR_LIME_REQUIRED)` (the lime gate),
`small_fuse_found` (the door panel), `resource_changed` (planet.gd) — and those
delegate to `Inventory`. Readers migrate to the new API opportunistically, not in
a big bang. This is the same shim strategy that made #36 cheap.

---

## 6. Save / migration

- `Inventory.serialize()` → `{ "items": { "lime": 3, "rations": 1, ... } }`,
  registered via `SaveManager.register_system("inventory", self)`.
- **Old saves** carry `resources` (dict), `small_fuse_found`, `large_fuse_found`,
  `kino_acquired`, `kino_orbs` as separate fields. `deserialize()` folds all of
  them into `_items`: copy the resources dict verbatim, and for each legacy bool
  that is `true`, `add_item(<id>, 1)`. → migration is mechanical and lossless.
- `GameState` may keep reading/writing the legacy fields for one version (derived
  from `Inventory`) as a belt-and-suspenders guard, then drop them.

---

## 7. Icons

Need 6 icons for E1 (`kino_remote`, `kino_orb`, `rations`, `lime`, `small_fuse`,
`large_fuse`). Sourcing options (in priority order):

1. **Kenney "Game Icons" / "UI assets" packs** (already on disk —
   `~/Downloads/Kenney Game Assets All-in-1 3.4.0/Icons`, `/UI assets`; CC0).
   Likely have generic crate/canister/orb/tool glyphs. Re-tint to the Kino UI
   blue palette (`Color(0.55, 0.85, 1.0)`).
2. **Existing project sprites** — `sprites/coin.png` already exists; `sprites/ui/`
   holds the dialog panel art for palette reference.
3. **Procedural/placeholder** — a flat colored tile + first letter, if no Kenney
   glyph fits, so the system ships without art-blocking.

> ⚠️ **Import gotcha (from project memory):** copying a PNG into `sprites/` is not
> enough — run `godot --headless --import` to generate the `.import` sidecar, or
> the `TextureRect` loads nothing. Same trap as the audio `.import` sidecars.

Store under `sprites/ui/items/`. Add an `AGENTS.md` note there.

---

## 8. Implementation steps (ordered)

1. **`data/items.json`** — author the 6 E1 items above. Update `data/AGENTS.md`.
2. **Icons** — source/place 6 PNGs in `sprites/ui/items/`, run `--import`.
3. **`scripts/inventory.gd`** (new autoload) — catalog loader (FileAccess + JSON,
   the `ship_layout.gd` pattern), unified `_items` store, `add/remove/count/has/
   entries`, `item_changed` signal, `serialize`/`deserialize`,
   `SaveManager.register_system("inventory", self)`.
4. **Register autoload** in `project.godot` (after `GameState`, before UI).
5. **Wire `GameState` shims** — `add_resource`/`has_resource`/`resource_count`
   delegate; `find_small_fuse`/`find_large_fuse`/`find_rations`/`acquire_kino`/
   `acquire_kino_orb` call `Inventory.add_item`; legacy bools become derived
   getters; re-emit `resource_changed` from `item_changed` for existing listeners.
6. **Kino Remote UI** — rebuild `_build_inventory_page` + `_refresh_inventory` as
   the slot grid with tooltips + click-to-detail; listen to `Inventory.item_changed`.
7. **Save migration** — fold legacy fields in `deserialize`; verify a pre-revamp
   save loads with all items intact.
8. **Tests** — see §9.
9. **Capture sanity** — `tests/shots/capture.sh` on the inventory page (if the
   harness supports it) shows the grid with fuses present.

---

## 9. Testing plan

New `tests/smoke/inventory.gd` (SceneTree script, project convention):

- `data/items.json` loads; all 6 ids present with required fields.
- `add_item` then `count`/`has`/`entries` reflect the add; stackables accumulate.
- Non-stackable item caps at 1; second add is a no-op (or logged).
- `remove_item` decrements, clamps at 0, returns false when insufficient.
- **Bug regression:** after `find_small_fuse()` + `find_large_fuse()` +
  `find_rations()`, `entries()` contains small_fuse, large_fuse, AND rations
  (this is the assertion that would have caught the original bug).
- Lime gate intact: `has("lime", 3)` matches old `has_resource` behavior.
- Save round-trip: serialize → reset → deserialize restores `_items`.
- **Old-format migration:** a save dict with `resources` + `small_fuse_found:true`
  + `kino_acquired:true` (no `items` block) deserializes to the right `_items`.

Keep green: `e1_flow`, `quest_waypoint`, `scene_boot`, `e1_playthrough`,
`kino_autopilot`, `quest_log`, `save_registration` lint. Run `tests/run.sh`.

---

## 10. Acceptance criteria

- [ ] `data/items.json` defines the 6 E1 items; loaded by an `Inventory` autoload.
- [ ] All looted items (rations, small fuse, large fuse, kino orbs, kino remote)
      appear on the Kino Remote inventory page. **The original bug is gone.**
- [ ] Inventory page renders a **slot grid**: icons, stack-count badges on
      stackables, hover tooltips (name + description), click-to-select detail.
- [ ] One unified store; the three old mechanisms (`small_fuse_found` /
      `large_fuse_found` bools, ad-hoc `resources` dict reads in the UI, special-
      cased kino line) are replaced or shimmed — no item renders via a bespoke line.
- [ ] Back-compat shims keep `has_resource` (lime gate), the door-panel fuse
      check, and `resource_changed` listeners working unchanged.
- [ ] `Inventory` registered with `SaveManager`; save round-trip + old-format
      migration both pass.
- [ ] New `tests/smoke/inventory.gd` passes; all existing suites stay green.

## 11. Risks & mitigations

- **Reader churn / lime-gate regression** → back-compat shims on `GameState`;
  the lime gate is covered by `e1_playthrough` + a dedicated `has("lime",3)` test.
- **Missing/placeholder icons block the build** → procedural letter-tile fallback
  so the grid ships even before final art.
- **PNG `.import` sidecar trap** → explicit `--import` step (§7) + AGENTS note.
- **Kino-orb double-accounting** (count lives in both `kino_orbs` and `_items`) →
  pick one source of truth (recommend `_items["kino_orb"]`); shim `kino_orbs`.
- **Save migration data loss** → old-format-migration test is a hard gate.

## 12. Out of scope (future)

- Full S1 resource roster (Water, Food, Naquadah, Ancient Components) — add as
  catalog rows when those systems land.
- Standalone inventory screen / pause-menu tab.
- Item interactions from the grid (use/drop/combine).
- Story-item capability unlocks (Ancient crystal → new system) per the GDD.
