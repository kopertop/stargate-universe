# Implementation Plan for #142 — E1 Cold-Open Atmosphere & Dialog System

> **Issue:** [#142 — E1 cold-open: replicate the SGU opening atmosphere + dialog → Find Rush](https://github.com/kopertop/stargate-universe/issues/142)
> **Reference doc:** `design/sgu-opening-reference.md`
> **Authoritative shot list:** `docs/OPENING_SCENE_SCRIPT.md` (referenced in code comments; not yet on disk — see Task 0)
> **Status:** Planning
> **Created:** 2026-07-06
> **Relates to:** #136 (cold-open standoff cutscene), #137 (E1 away-team split)

---

## Overview

Layer the missing **sound design, crowd dialog, and atmosphere polish** onto the already-substantial cold-open cinematic in `scripts/gate_room.gd::_play_prologue_cinematic()`, so the sequence reads as a **chaotic disaster evacuation** (panic under discipline, overlapping voices, impact percussion, no answers → wonder → discovery) and lands on the diegetic **"Help me find him." → Find Rush** quest hand-off.

---

## What Already Exists (DO NOT duplicate)

The cold open is **substantially implemented**. This plan layers *on top* of these systems — it does not rebuild them.

### Choreography & sequencing (`scripts/gate_room.gd`)
- **`_play_prologue_cinematic()` (L620–927)** — full ~165s cold open, playhead-synced to `cold_open_bed.mp3` via `_await_audio()` / `_cap()` / `_cap_now()`.
- **Wave arrivals** — `_co_arrival()`, `_co_crowd_flood()`, `_throw_persistent_crew()`, `_settle_persistent_crew()` (Waves 1–8 + Eli).
- **Impact SFX** — `_thud()` (round-robin land/fall/break pool + metallic deck-ring), `_splash()` (puddle punch-through), `_grunt()` (3 grunt clips, round-robin, pitch-varied).
- **Gate sequence** — `dial_and_open()` (ring spin → chevron lock → kawoosh), `_collapse_gate()`, `_vent_gate_sides()`, `_collapse_blackout()`, `_flashlights_during_dark()`.
- **Camera cuts** — `_begin_cuts()`, `_cut_to()`, `_cut_wide()`, `_cut_follow()`, `_cut_to_spot()`, `_end_cuts()` (via `StandoffCamera`).
- **Lighting** — `_open_dark()`, `_flicker_lights_up()`, `_wake_consoles()`, `_set_consoles_offline()`.
- **FTL jump** — `_ftl_jump()` + `Cinematic.flash()` for the wonder beat.
- **Command hand-off** — `_co_command_handoff()` (Scott → Young → TJ).
- **Quest hand-off** — `_finalize_cold_open()` (gate shut, player visible, `GameState.met_scott = true`, `GameState.advance_air_quest()`, `_set_scott_autogreet(false)`, Scott walks off, player control restored).
- **Skip support** — `_co_skip`, `_trigger_cold_open_skip()`, `_cwait()`, hold-Jump detection, `_autoskip_after`.
- **Nametag suppression** — `_set_crew_nametags_visible()`, `_is_anonymous_extra()`, `_cold_open_active` flag.

### Cinematic framework
- **`scripts/cinematic.gd`** — `letterbox_in/out()`, `set_caption()`, `flash()`, `begin_camera()`, `end_camera()`, gameplay-UI hide/restore.
- **`scripts/standoff_camera.gd`** — `frame()`, `follow()`, `shake()`, `configure()`, wall-collision avoidance (`_pull_clear`).
- **`scripts/standoff_cinematic.gd`** — multi-line caption sequencer (used by the standoff cutscene, not currently by the cold open).

### Quest system
- **`scripts/quest_log.gd`** + **`data/quests.json`** — `e1_air` quest, `find_rush` step (target: `control_interface_room` / `DrRush`, `complete_when: "met_rush"`).
- **`scripts/quest_waypoint.gd`** — in-world objective diamond.

### Voice lines already baked and wired
All 38 `_cap()` / `_cap_now()` calls in `_play_prologue_cinematic()` reference VO files that **exist on disk** under `sounds/dialog/prologue/`. The dialog from the reference doc is **already present as captions and VO**:
- Scott's marshalling barks, Wray's "Where are we?", TJ's medic pocket, the Senator/Chloe beat, Greer's "Move, move, move!", Young's "Where are we?" / "You're in charge", the Rush hand-off ("Rush! Eli, help me find him."), "What in the hell was that?!", and "Eli! Now!".

### Voice lines baked but NOT yet wired into the cinematic
The following VO files exist on disk but are **not referenced** in `_play_prologue_cinematic()`:

| File | Line (from reference) | Where it should go |
|------|----------------------|--------------------|
| `open-crowd-where.wav` | Crowd: "Where are we?" | Layered under waves 2–8 (overlapping crowd confusion) |
| `open-crowd-what.wav` | Crowd: "What's going on?" | Layered under waves 2–8 |
| `open-eli-whatisthis.wav` | Eli: "What is this place?" | The wonder beat (§1.9) or the Rush hand-off (§1.8b) |
| `open-crew-whatwasthat.wav` | Crew: "What the hell was that?" | The wonder beat (§1.9) — currently only Greer's version is wired |
| `open-eli-coming.wav` | Eli: "Okay! I'm coming!" | The button (§1.10) — the Eli response to Scott's "Eli! NOW!" |
| `open-greer-clear.wav` | Greer: "Clear!" | Marshalling bark during waves 2–8 |
| `open-greer-side.wav` | Greer: "Off to the side!" | Marshalling bark during waves 2–8 |
| `open-marine-clear.wav` | Marine: "Clear!" | During the flood |
| `open-marine-clearway.wav` | Marine: "Clear the way!" | During the flood |
| `open-marine-leaveit.wav` | Marine: "Leave it — there'll be more coming through." | After the flood tapers (~38s) |
| `open-officer-idontknow.wav` | Officer: "I don't know, sir." | The command hand-off — currently Scott says "I don't know, sir." (open-scott-idontknow); the officer version is an alternative |
| `open-tj-areyouokay.wav` | TJ: "Are you okay?" | The medic pocket or the Senator/Chloe beat |
| `open-scott-norush.wav` | Scott: "I haven't seen Rush — I don't know if he made it through." | The Rush hand-off (§1.8b) — a longer alternative to the current "Rush! Eli, help me find him." |
| `open-scott-eli-now.wav` | Scott: "Eli! Now!" | Duplicate of `open-scott-elinow.wav` (already wired) — verify which take to use |
| `young-myship.wav` | Young: "My ship..." | Post-collapse or command hand-off |
| `rush-discovery.wav` | Rush: (discovery line) | Post-cold-open — not part of the cold open itself |

### Sound assets already on disk
- `sounds/land.ogg`, `sounds/fall.ogg`, `sounds/break.ogg` — impact pool (used by `_thud()`).
- `sounds/bong_001.ogg` — metallic deck-ring (used by `_thud()`).
- `sounds/grunt_01.wav`, `sounds/grunt_02.wav`, `sounds/grunt_03.wav` — effort grunts (used by `_grunt()`).
- `sounds/gate_kawoosh.wav`, `sounds/gate_active_hum.wav` — gate SFX (wired).
- `sounds/klaxon.ogg` — alarm klaxon (exists, **not wired** into the cold open).
- `sounds/stargate_chevron_incom.mp3` — per-chevron lock (wired).
- `sounds/ftl-dropout.ogg`, `sounds/ftl_jump_destiny.ogg` — FTL SFX (wired via `_ftl_jump()`).
- `sounds/dialog/prologue/cold_open_bed.mp3` — master ambience bed (wired).
- `sounds/dialog/prologue/cold_open_master.mp3` — original reference recording (exists, used as timing reference).
- `sounds/dialog/prologue/scott_clear.wav` — Scott's radio line (exists; referenced in code comments but the actual cold open uses `open-scott-clearway.wav` etc.).
- `sounds/radio_click.ogg`, `sounds/radio_off.ogg` — radio SFX (exist, not used in cold open).

### Tests already in place
- **`tests/smoke/cold_open_lines.gd`** — drift guard: asserts master track referenced + present, required hand-off captions present, quest advances without Scott walk-up, mechanics wired, nametags suppressed, skip wired.
- **`tests/smoke/e1_flow.gd`** — flow test: GameState mutators, quest advancement (`met_scott` → `QUEST_FIND_RUSH`).
- **`tests/run.sh`** — `cold-open` and `e1-opening` modes wire both tests.

---

## Acceptance Criteria

- [ ] **AC1:** The cold open reads as a **chaotic disaster evacuation** — crowd-panic ambient bed loops under waves 2–8, ducking under voiced lines; Icarus rumble/klaxon bleeds through the open wormhole and cuts on `_collapse_gate()`.
- [ ] **AC2:** **All dialog beats** from `design/sgu-opening-reference.md` are present and voiced — including the unreferenced VO clips (crowd confusion, Eli's "What is this place?", crew "What the hell was that?", Eli's "Okay! I'm coming!", marshalling barks, "Leave it — there'll be more").
- [ ] **AC3:** The sequence lands on Scott's shouted **"Eli! NOW!"** → Eli's **"Okay! I'm coming!"**, hands control to the player, and activates the **Find Rush** quest (`find_rush` step active, waypoint points to Control Interface Room).
- [ ] **AC4:** The gate **energize ramp** cross-fades `gate_active_hum` → `gate_kawoosh` during the dial (tension before kawoosh).
- [ ] **AC5:** A **ship-shudder/groan** one-shot fires on the wonder beat (pairs with `Cinematic.flash()` + camera shake at the FTL jump).
- [ ] **AC6:** Radio static/crackle EQ sits over Scott's radio lines for comms authenticity.
- [ ] **AC7:** `tests/run.sh cold-open` (cold_open_lines) still **passes** — existing drift guards are not broken.
- [ ] **AC8:** `tests/run.sh flow` (e1_flow) still **passes** — quest hand-off from `talk_scott` → `find_rush` is intact.
- [ ] **AC9:** New assertions in `cold_open_lines.gd` cover the newly-wired beats (crowd VO, Icarus rumble, energize ramp, Eli's "I'm coming!" response).
- [ ] **AC10:** Hold-to-skip still works — `_co_skip` funnels to `_finalize_cold_open()` and the end state is deterministic regardless of when the skip fires.
- [ ] **AC11:** Headless `instant_mode` path is unchanged — no new audio/tween calls block or error in headless runs.

---

## Architecture

### High-Level Design

The cold open is a **single coroutine** (`_play_prologue_cinematic`) driven by one master audio bed (`cold_open_bed.mp3`). Visual beats and captions are paced by `_await_audio(player, t)` (playhead-locked) or `_cwait(t)` / `_cap_now()` (timer-paced for the dial sequence). This plan **does not change that architecture** — it adds:

1. **Sound bed layers** — new `AudioStreamPlayer` nodes started/stopped alongside the existing master bed, gated by `_co_skip` and cleaned up in `_finalize_cold_open()`.
2. **Overlapping crowd VO** — fire-and-forget `_cap_crowd()` calls that play a VO clip **without** a caption (or with a brief one), layered over the existing captioned lines. These are **not** playhead-locked — they fire on timers during the flood windows.
3. **Energize ramp** — a short cross-fade tween on `_gate_hum_sfx` volume before `dial_and_open()` fires the kawoosh.
4. **Icarus rumble** — a looping `AudioStreamPlayer` started after `dial_and_open()`, stopped in `_collapse_gate()`.
5. **Ship shudder SFX** — a one-shot played at the FTL jump beat alongside `Cinematic.flash()`.

### Key Components

1. **`scripts/gate_room.gd`** — all new logic lives here (sound bed players, crowd VO, energize ramp, Icarus rumble, shudder SFX). No new files.
2. **`sounds/`** — new audio assets sourced/authoried (see Sound Design Asset List).
3. **`design/voice-line-manifest.md`** — to be created (referenced in the reference doc but does not exist yet; documents cast + ElevenLabs voice IDs).
4. **`docs/OPENING_SCENE_SCRIPT.md`** — to be created (referenced in code comments at L126–128 but not on disk; the authoritative playhead-keyed shot list).
5. **`tests/smoke/cold_open_lines.gd`** — extended with new assertions.

---

## Task Breakdown

### Task 0 — Author the missing reference docs [Effort: S]
**Files:** `docs/OPENING_SCENE_SCRIPT.md` (new), `design/voice-line-manifest.md` (new)

The code comments (L126–128) and the reference doc both point to `docs/OPENING_SCENE_SCRIPT.md` as "the authoritative playhead-keyed script" — it does not exist. The reference doc also says voice lines "extend `design/voice-line-manifest.md`" — that file does not exist either.

- [ ] Create `docs/OPENING_SCENE_SCRIPT.md` — transcribe the beat-by-beat shot list with playhead timestamps from the existing `_play_prologue_cinematic()` code (§1.1 through §1.10, L683–927). This is the single source of truth for "what happens at what second."
- [ ] Create `design/voice-line-manifest.md` — document cast (Scott, Greer, Young, TJ, Wray, Chloe, Senator, Eli, Marine, Officer, Crew), ElevenLabs voice IDs, and map each `open-*.wav` file to its speaker + line. Mark which clips are wired vs. unwired.

### Task 1 — Sound design: crowd-panic ambient bed [Effort: M]
**Files:** `sounds/dialog/prologue/crowd_panic_bed.ogg` (new asset), `scripts/gate_room.gd`

The "many terrified people" layer that loops under waves 2–8 and ducks under voiced lines. Currently the only crowd layer is the master `cold_open_bed.mp3` (which has the original recording's stripped ambience).

- [ ] Source/author `sounds/dialog/prologue/crowd_panic_bed.ogg` — a loopable ~30s bed of overlapping panicked crowd voices (not intelligible words — just the texture). Should be mono (non-positional) and sit below the VO in the mix.
- [ ] In `_play_prologue_cinematic()`, after `_co_crowd_flood()` starts (~9s playhead), start a new `AudioStreamPlayer` with this bed, `loop = true`.
- [ ] Duck the bed volume (`volume_db`) down by ~6dB whenever a `_cap()` / `_cap_now()` VO fires, and restore it after. Implement as a simple tween on the bed player's `volume_db` — or a simpler approach: just set a lower `volume_db` from the start (the VO clips play on separate players and are loud enough to cut through).
- [ ] Stop the bed in `_collapse_gate()` (the gate shutting = the evac is over) or at the ~38s flood taper, whichever is later. Also stop it in `_finalize_cold_open()` (skip safety).
- [ ] Guard with `_co_skip` — don't start it if skipping.

### Task 2 — Sound design: Icarus rumble / klaxon [Effort: S]
**Files:** `sounds/klaxon.ogg` (exists), `sounds/dialog/prologue/icarus_rumble.ogg` (new asset), `scripts/gate_room.gd`

"The base behind them is dying" — distant rumble + klaxon bleeding through the open wormhole. `sounds/klaxon.ogg` already exists but is not wired into the cold open.

- [ ] Source/author `sounds/dialog/prologue/icarus_rumble.ogg` — a low, distant, muffled explosion/rumble loop (~10s loopable).
- [ ] In `_play_prologue_cinematic()`, after `dial_and_open()` completes (the gate is open), start two looping `AudioStreamPlayer`s: one with `klaxon.ogg` (low volume, muffled EQ if possible), one with `icarus_rumble.ogg`.
- [ ] Stop both in `_collapse_gate()` (the gate shuts = the connection to Icarus is severed). Also stop in `_finalize_cold_open()`.
- [ ] Guard with `_co_skip`.

### Task 3 — Sound design: gate energize ramp [Effort: S]
**Files:** `scripts/gate_room.gd` (the `dial_and_open()` function, L437–478)

The reference doc calls for a "gate energize ramp" cross-fading `gate_active_hum.wav` → `gate_kawoosh.wav`. Currently the dial plays per-chevron lock sounds, then the kawoosh fires on open — but there's no rising tension ramp before the kawoosh.

- [ ] In `dial_and_open()`, during the `DIAL_TIME` wait (L453), add a volume ramp on `_gate_hum_sfx`: start at a low volume and tween up to full over ~2.5s (the dial spinning = energy building). This creates the "energize" rise.
- [ ] The kawoosh already fires at L472–473 (`_gate_kawoosh_sfx.play()`) — ensure the hum cross-fades or cuts when the kawoosh fires (currently it starts the hum AFTER the kawoosh at L474; adjust so the ramping hum stops/ducks as the kawoosh hits).
- [ ] Guard with `with_sfx` (already the parameter) — skip in headless.

### Task 4 — Sound design: radio static/crackle over Scott's lines [Effort: S]
**Files:** `sounds/radio_click.ogg` (exists), `sounds/radio_off.ogg` (exists), `scripts/gate_room.gd`

Scott's marshalling barks are radio comms. A light radio crackle/static layer sells that.

- [ ] Play `radio_click.ogg` as a short one-shot immediately before each of Scott's `_cap()` / `_cap_now()` radio lines (the "Slow down the evac", "Come in", "Clear this area" beats).
- [ ] Optionally layer a low-volume radio static loop under Scott's lines (if a `radio_static.ogg` asset is sourced; otherwise the click-on/click-off is sufficient).
- [ ] Guard with `_co_skip`.

### Task 5 — Sound design: ship-shudder / groan one-shot [Effort: S]
**Files:** `sounds/dialog/prologue/ship_shudder.ogg` (new asset), `scripts/gate_room.gd`

The wonder beat (§1.9, L900–904) currently fires `_ftl_jump()` + `Cinematic.flash()` + a camera shake. The reference doc calls for a dedicated "ship-shudder / groan one-shot" paired with the flash.

- [ ] Source/author `sounds/dialog/prologue/ship_shudder.ogg` — a deep, metallic, structural-groan one-shot (~2s).
- [ ] Play it at L900 (the `await _await_audio(audio, 118.0)` / `_ftl_jump()` beat), alongside `Cinematic.flash()`.
- [ ] Also play a lighter version at the gate-collapse beat (L849, `_collapse_gate()`) — currently only a camera shake fires there; a groan sells the room shuddering.
- [ ] Guard with `_co_skip`.

### Task 6 — Dialog: wire unreferenced crowd confusion VO [Effort: M]
**Files:** `scripts/gate_room.gd`

The crowd confusion lines ("Where are we?", "What's going on?") exist as `open-crowd-where.wav` and `open-crowd-what.wav` but are not played during the flood. The reference doc says the atmosphere is "overlapping, layered voices — not clean one-at-a-time lines."

- [ ] Add a new helper `_cap_crowd(vo_id: String, at_t: float = -1.0)` that plays a VO clip **without** a caption (or with a brief, non-blocking caption that doesn't wait for advance). This is fire-and-forget, layered over the existing captioned lines.
- [ ] During `_co_crowd_flood()` (L718–719, the ~9s–38s window), fire `_cap_crowd("open-crowd-where")` and `_cap_crowd("open-crowd-what")` at semi-random intervals (deterministic via the flood index `i`) — e.g. every 3rd flood spawn, alternate between the two clips.
- [ ] Add `_cap_crowd("open-eli-whatisthis")` at the wonder beat (§1.9, ~99s) — Eli's "What is this place?" layered before/after Greer's "What in the hell was that?!"
- [ ] Add `_cap_crowd("open-crew-whatwasthat")` alongside the existing Greer "What in the hell was that?!" at L906 — the crew echo.
- [ ] Guard all with `_co_skip`.

### Task 7 — Dialog: wire Eli's "Okay! I'm coming!" button response [Effort: S]
**Files:** `scripts/gate_room.gd`

The "button" is Scott yelling "Eli! NOW!" (L914, `open-scott-elinow`) → Eli's "Okay! I'm coming!" (`open-eli-coming.wav` exists but is **not played**). This is the hand-off into gameplay.

- [ ] At L914, after `_cap("LT. SCOTT", "Eli! Now!", 139.0, "open-scott-elinow")`, add `_cap("ELI", "Okay! I'm coming!", 140.5, "open-eli-coming")` — Eli's response, ~1.5s after Scott's shout (or at the next playhead beat, ~140.5s).
- [ ] Verify the VO file `open-eli-coming.wav` is the correct take (there's also `open-scott-eli-now.wav` which may be a duplicate of `open-scott-elinow.wav` — confirm which to use and delete the stale one if so).
- [ ] Ensure this plays **before** `_finalize_cold_open()` so it lands during the cinematic, not after control is restored.

### Task 8 — Dialog: wire remaining marshalling barks [Effort: S]
**Files:** `scripts/gate_room.gd`

`open-greer-clear.wav` ("Clear!"), `open-greer-side.wav` ("Off to the side!"), `open-marine-clear.wav`, `open-marine-clearway.wav` ("Clear the way!"), and `open-marine-leaveit.wav` ("Leave it — there'll be more coming through.") exist but are not wired.

- [ ] Fire `_cap_crowd("open-greer-clear")` and `_cap_crowd("open-marine-clear")` during the flood at ~20s and ~30s (overlapping with the existing Scott captions).
- [ ] Fire `_cap_crowd("open-greer-side")` alongside or just after Scott's "Off to the side!" (L741, `open-scott-side`).
- [ ] Fire `_cap("MARINE", "Leave it — there'll be more coming through.", <t>, "open-marine-leaveit")` at ~38s (the flood tapers — a marine waves off scavenging). Use `_cap()` with a playhead time around 38s.
- [ ] Guard with `_co_skip`.

### Task 9 — Dialog: wire TJ "Are you okay?" and the officer "I don't know, sir." [Effort: S]
**Files:** `scripts/gate_room.gd`

- [ ] `open-tj-areyouokay.wav` — fire during the Senator/Chloe beat (§1.5, ~44s–49s) or the medic pocket. TJ asking "Are you okay?" fits the Chloe/Senator moment (Chloe is already asking "Are you okay?" at L806 — verify if this is the same line or a TJ variant; if Chloe's line is already `open-chloe-areyouok`, then `open-tj-areyouokay` is TJ's version for a different beat — e.g. TJ checking on Young at the command hand-off).
- [ ] `open-officer-idontknow.wav` — the reference doc has Young asking "Where are we?" → officer: "I don't know, sir." Currently Scott says "I don't know, sir." (L871, `open-scott-idontknow`). The officer version is an alternative — decide whether to keep Scott's (he's the one Young is talking to) or layer the officer version as a background bark. **Recommendation:** keep Scott's version as the primary caption; fire `open-officer-idontknow` as a `_cap_crowd` background bark at ~78s for layered depth.
- [ ] `open-scott-norush.wav` — Scott's longer "I haven't seen Rush — I don't know if he made it through." This is an alternative to the current Rush hand-off beat (L895–896). **Recommendation:** use it as a lead-in: fire `_cap_now("LT. SCOTT", "I haven't seen Rush — I don't know if he made it through.", "open-scott-norush")` at ~96s (the §1.8b beat), then the existing "Rush!" and "Rush! Eli, help me find him." follow.

### Task 10 — Verify and clean up duplicate/unused VO files [Effort: S]
**Files:** `sounds/dialog/prologue/`

- [ ] `open-scott-eli-now.wav` vs `open-scott-elinow.wav` — both are "Eli! Now!" Determine which take is in use (code references `open-scott-elinow` at L914) and whether the other is a stale duplicate. Delete the stale one or document it as an alternate take.
- [ ] `open-man-broken.wav` vs `open-wounded-broken.wav` — both are "I think my arm is broken." Code references `open-man-broken` (L771). Verify and clean up.
- [ ] `open-marine-clear.wav` vs `open-marine-clearway.wav` — determine if these are distinct lines ("Clear!" vs "Clear the way!") or duplicates. Wire accordingly.
- [ ] `scott_clear.wav` vs `open-scott-clearway.wav` — the reference doc mentions `scott_clear.wav` as the "existing radio line" but the cold open uses the `open-*` clips. Verify `scott_clear.wav` is still needed or is legacy.
- [ ] `young-myship.wav` — determine if this belongs in the cold open (Young is unconscious) or a later scene. If not cold-open, move or document.

### Task 11 — Extend the cold_open_lines drift guard [Effort: S]
**Files:** `tests/smoke/cold_open_lines.gd`

Add assertions for the newly-wired beats so a future refactor can't silently drop them.

- [ ] Add to `REQUIRED_CAPTIONS`: `"Okay! I'm coming!"` (Eli's button response), `"I haven't seen Rush"` (if Task 9 is done), `"Leave it"` (marine, if Task 8 is done).
- [ ] Add a new test function `test_cold_open_sound_bed_wired(code)` that asserts the crowd-panic bed, Icarus rumble, and ship-shudder SFX are referenced in `gate_room.gd` (string search for the asset paths).
- [ ] Add a new test function `test_cold_open_energize_ramp_wired(code)` that asserts a volume tween on `_gate_hum_sfx` exists in `dial_and_open()`.
- [ ] Add a new test function `test_cold_open_crowd_vo_wired(code)` that asserts `_cap_crowd(` is defined and called with the crowd confusion VO IDs.
- [ ] Ensure all new assertions follow the existing pattern (string search in the gate_room.gd source; `_pass` on found, `_fail` on missing).

### Task 12 — Manual verification pass [Effort: S]
**Files:** none (visual/audio QA)

- [ ] Run the cold open in a **headed** Godot instance with audio on. Verify:
  - The crowd panic bed is audible under the flood and ducks under VO.
  - The Icarus klaxon/rumble is audible while the gate is open and cuts on collapse.
  - The energize ramp builds tension before the kawoosh.
  - Scott's radio lines have crackle.
  - The ship shudder is audible at the FTL jump.
  - Eli's "Okay! I'm coming!" plays after "Eli! NOW!"
  - The crowd confusion lines ("Where are we?", "What's going on?") are audibly layered.
  - The "Leave it" marine line plays at ~38s.
  - Hold-to-skip still works and lands on the correct end state.
  - The quest waypoint points to the Control Interface Room after hand-off.

---

## Dialog Line List (with speaker tags)

This is the **complete** dialog list for the cold open, combining what's already wired with what this plan adds. Times are playhead seconds on `cold_open_bed.mp3`.

### Already wired (existing `_cap` / `_cap_now` calls)

| ~Time | Speaker | Line | VO file | Status |
|-------|---------|------|---------|--------|
| ~6s | LT. SCOTT | "All right, get out of here. Get out of the way!" | `open-scott-clearway` | ✅ wired |
| ~9s | LT. SCOTT | "This is Scott! Slow down the evac — we are comin' in too hot!" | `open-scott-evac` | ✅ wired |
| ~14s | CAMILE WRAY | "Where are we? Why didn't we come through to Earth?" | `open-wray-whereare` | ✅ wired |
| ~16s | LT. SCOTT | "There's no time to explain. Off to the side!" | `open-scott-side` | ✅ wired |
| ~18.5s | LT. SCOTT | "This is Scott — come in!" | `open-scott-comein` | ✅ wired |
| ~20s | MARINE | "I need a medic!" | `open-marine-medic` | ✅ wired |
| ~24s | TJ | "Over here! Can you move your fingers?" | `open-tj-fingers` | ✅ wired |
| ~29s | MARINE | "No. I think my arm is broken." | `open-man-broken` | ✅ wired |
| ~32s | TJ | "Okay, just hold your arm there and we'll put it in a sling, okay?" | `open-tj-sling` | ✅ wired |
| ~38s | LT. SCOTT | "Clear this area! There could still be more incoming!" | `open-scott-cleararea` | ✅ wired |
| ~44s | CHLOE | "Are you okay?" | `open-chloe-areyouok` | ✅ wired |
| ~47s | SENATOR | "Yeah." | `open-senator-yeah` | ✅ wired |
| ~49s | SENATOR | "Where the hell are we?" | `open-senator-whereare` | ✅ wired |
| ~55s | LT. SCOTT | "Greer? Where's Colonel Young?" | `open-scott-greerwhere` | ✅ wired |
| ~58s | SGT. GREER | "He was right behind me." | `open-greer-behindme` | ✅ wired |
| ~66s | SGT. GREER | "Move, move, move. Stay calm! Keep it down! Move, move, move, move, move." | `open-greer-move` | ✅ wired |
| ~72s | LT. SCOTT | "Colonel? Colonel?" | `open-scott-colonel` | ✅ wired |
| ~74s | SGT. GREER | "Don't move!" | `open-greer-dontmove` | ✅ wired |
| ~76s | COL. YOUNG | "Where are we? Where are we?" | `open-young-whereare` | ✅ wired |
| ~78s | LT. SCOTT | "I don't know, sir." | `open-scott-idontknow` | ✅ wired |
| ~80s | COL. YOUNG | "You're in charge, okay? You're..." | `open-young-incharge` | ✅ wired |
| ~83.5s | LT. SCOTT | "Yes, sir." | `open-scott-yessir` | ✅ wired |
| ~86s | LT. SCOTT | "TJ!" | `open-scott-tj` | ✅ wired |
| ~88s | TJ | "I'm coming!" | `open-tj-coming` | ✅ wired |
| ~91s | SGT. GREER | "Is he okay?" | `open-greer-isheok` | ✅ wired |
| ~93s | TJ | "Uh, I dunno." | `open-tj-dunno` | ✅ wired |
| ~96s | LT. SCOTT | "Wallace!" | `open-scott-wallace` | ✅ wired |
| ~99s | LT. SCOTT | "What is this place?" | `open-scott-whatisplace` | ✅ wired |
| ~101s | ELI | "Look, I just did what Rush told me." | `open-eli-didwhat` | ✅ wired |
| ~104s | LT. SCOTT | "Where is he?" | `open-scott-whereishe` | ✅ wired |
| ~106s | ELI | "I don't know if he went ahead of me." | `open-eli-wentahead` | ✅ wired |
| ~109s | LT. SCOTT | "Rush!" | `open-scott-rush` | ✅ wired |
| ~112s | LT. SCOTT | "Rush! Eli, help me find him." | `open-scott-findhim` | ✅ wired |
| ~114.5s | ELI | "Well, I..." | `open-eli-welli` | ✅ wired |
| ~120s | SGT. GREER | "What in the hell was that?!" | `open-greer-whatwasthat` | ✅ wired |
| ~123s | LT. SCOTT | "I don't know. Sergeant, I need you to get these people settled here..." | `open-scott-settle` | ✅ wired |
| ~133s | SGT. GREER | "Yes, sir." | `open-greer-yessir` | ✅ wired |
| ~139s | LT. SCOTT | "Eli! Now!" | `open-scott-elinow` | ✅ wired |

### New lines to wire (this plan)

| ~Time | Speaker | Line | VO file | Task |
|-------|---------|------|---------|------|
| ~12s (layered) | CROWD | "Where are we?" | `open-crowd-where` | Task 6 |
| ~15s (layered) | CROWD | "What's going on?" | `open-crowd-what` | Task 6 |
| ~20s (layered) | SGT. GREER | "Clear!" | `open-greer-clear` | Task 8 |
| ~22s (layered) | MARINE | "Clear the way!" | `open-marine-clearway` | Task 8 |
| ~30s (layered) | MARINE | "Clear!" | `open-marine-clear` | Task 8 |
| ~16s (layered) | SGT. GREER | "Off to the side!" | `open-greer-side` | Task 8 |
| ~38s | MARINE | "Leave it — there'll be more coming through." | `open-marine-leaveit` | Task 8 |
| ~78s (layered) | OFFICER | "I don't know, sir." | `open-officer-idontknow` | Task 9 |
| ~92s | TJ | "Are you okay?" | `open-tj-areyouokay` | Task 9 |
| ~96s | LT. SCOTT | "I haven't seen Rush — I don't know if he made it through." | `open-scott-norush` | Task 9 |
| ~99s (layered) | ELI | "What is this place?" | `open-eli-whatisthis` | Task 6 |
| ~120s (layered) | CREW | "What the hell was that?" | `open-crew-whatwasthat` | Task 6 |
| ~140.5s | ELI | "Okay! I'm coming!" | `open-eli-coming` | Task 7 |

---

## Sound Design Asset List

### Already present (wired)

| Asset | Purpose | Status |
|-------|---------|--------|
| `sounds/land.ogg`, `sounds/fall.ogg`, `sounds/break.ogg` | Impact pool (`_thud()`) | ✅ wired |
| `sounds/bong_001.ogg` | Metallic deck-ring (`_thud()`) | ✅ wired |
| `sounds/grunt_01.wav`–`grunt_03.wav` | Effort grunts (`_grunt()`) | ✅ wired (3 clips; issue asks for 4–6) |
| `sounds/gate_kawoosh.wav` | Gate kawoosh | ✅ wired |
| `sounds/gate_active_hum.wav` | Gate steady hum | ✅ wired |
| `sounds/stargate_chevron_incom.mp3` | Per-chevron lock | ✅ wired |
| `sounds/ftl_jump_destiny.ogg` | FTL jump whoosh | ✅ wired |
| `sounds/dialog/prologue/cold_open_bed.mp3` | Master ambience bed | ✅ wired |
| `sounds/footstep_water_00–03.ogg` | Puddle splash (`_splash()`) | ✅ wired |

### Already present (NOT wired — to wire in this plan)

| Asset | Purpose | Task |
|-------|---------|------|
| `sounds/klaxon.ogg` | Icarus alarm bleeding through wormhole | Task 2 |

### New assets to source/author

| Asset | Purpose | Task | Notes |
|-------|---------|------|-------|
| `sounds/dialog/prologue/crowd_panic_bed.ogg` | Crowd-panic ambient loop under waves 2–8 | Task 1 | ~30s loop, mono, sits below VO. Duck under voiced lines. |
| `sounds/dialog/prologue/icarus_rumble.ogg` | Distant base-dying rumble through wormhole | Task 2 | ~10s loop, low muffled explosions. |
| `sounds/dialog/prologue/ship_shudder.ogg` | Ship structural groan (wonder beat) | Task 5 | ~2s deep metallic groan. |
| `sounds/grunt_04.wav`–`grunt_06.wav` | Additional effort grunts (issue asks for 4–6; only 3 exist) | Task 1/6 | Optional — 3 is functional but 4–6 adds variety. |

### Existing SFX to repurpose

| Asset | Purpose | Task |
|-------|---------|------|
| `sounds/radio_click.ogg` | Radio crackle before Scott's comms lines | Task 4 |
| `sounds/radio_off.ogg` | Radio click-off after Scott's comms lines | Task 4 (optional) |

---

## Cinematic Integration Steps

All integration is in `scripts/gate_room.gd::_play_prologue_cinematic()` (L620–927) and its helpers. The steps are ordered by where they land in the cinematic timeline.

### Step 1: Gate dial (≈0.5–3.5s playhead)
- **Energize ramp** (Task 3): In `dial_and_open()`, add a volume tween on `_gate_hum_sfx` ramping from low to full over `DIAL_TIME`. The hum builds as the ring spins. On kawoosh, duck/stop the hum and let the kawoosh play.

### Step 2: Gate open → first through (≈3.5–9s)
- **Icarus rumble + klaxon** (Task 2): After `dial_and_open()` returns (L677), start the `klaxon.ogg` and `icarus_rumble.ogg` loop players. They bleed through the open wormhole.
- **Radio crackle** (Task 4): Play `radio_click.ogg` before Scott's first `_cap_now("LT. SCOTT", "All right, get out of here...")` at L711.

### Step 3: The flood (≈9–38s)
- **Crowd panic bed** (Task 1): Start `crowd_panic_bed.ogg` looping at the `_co_crowd_flood()` call (L718–719).
- **Crowd confusion VO** (Task 6): Fire `_cap_crowd("open-crowd-where")` and `_cap_crowd("open-crowd-what")` at deterministic intervals during the flood (every 3rd spawn, alternating).
- **Marshalling barks** (Task 8): Fire `_cap_crowd("open-greer-clear")` at ~20s, `_cap_crowd("open-marine-clearway")` at ~22s, `_cap_crowd("open-marine-clear")` at ~30s, `_cap_crowd("open-greer-side")` right after L741.
- **Marine "Leave it"** (Task 8): `_cap("MARINE", "Leave it — there'll be more coming through.", 38.0, "open-marine-leaveit")` at the flood taper.

### Step 4: Medic pocket (≈20–33s)
- Already fully staged (TJ + wounded marine, crate impact, captions + VO). No changes needed.

### Step 5: Senator/Chloe (≈39–49s)
- Already staged. Optionally add `_cap_crowd("open-tj-areyouokay")` if TJ's "Are you okay?" fits here (Task 9 — verify against the Chloe line at L806).

### Step 6: Greer + Eli arrival (≈51–58s)
- Already staged. No changes.

### Step 7: Young arrival + gate collapse (≈60–66s)
- **Ship shudder** (Task 5): Play a light `ship_shudder.ogg` at `_collapse_gate()` (L849) alongside the camera shake.
- **Icarus rumble/klaxon stop** (Task 2): Stop the loop players in `_collapse_gate()`.
- **Crowd panic bed stop** (Task 1): Stop the bed here (the evac is over) or at the 38s taper if later. Since the collapse is at ~64s, stop it here.

### Step 8: Command hand-off (≈66–93s)
- Already staged (`_co_command_handoff`, captions, VO).
- **Officer "I don't know, sir."** (Task 9): `_cap_crowd("open-officer-idontknow")` at ~78s (layered behind Scott's "I don't know, sir.").
- **TJ "Are you okay?"** (Task 9): `_cap_now("TJ", "Are you okay?", "open-tj-areyouokay")` at ~92s (TJ checking on Young).

### Step 9: Rush hand-off (≈96–115s)
- **Scott "I haven't seen Rush"** (Task 9): `_cap_now("LT. SCOTT", "I haven't seen Rush — I don't know if he made it through.", "open-scott-norush")` at ~96s, before the existing "Rush!" / "Rush! Eli, help me find him." beats.
- Existing beats at L884–897 remain.

### Step 10: The wonder / FTL jump (≈118–133s)
- **Ship shudder SFX** (Task 5): Play `ship_shudder.ogg` at L900 (`_ftl_jump()` + `Cinematic.flash()`).
- **Eli "What is this place?"** (Task 6): `_cap_crowd("open-eli-whatisthis")` at ~99s or ~120s.
- **Crew "What the hell was that?"** (Task 6): `_cap_crowd("open-crew-whatwasthat")` alongside L906 (Greer's version).
- Existing Greer/Scott/Greer captions remain.

### Step 11: The button + hand-off (≈139–142s)
- **Eli "Okay! I'm coming!"** (Task 7): `_cap("ELI", "Okay! I'm coming!", 140.5, "open-eli-coming")` after L914 (Scott's "Eli! Now!").
- Existing `_finalize_cold_open()` (L976–1040) handles the rest: letterbox out, camera restore, consoles wake, quest advance, Scott walks off, player control restored.

### Step 12: Cleanup safety
- Ensure **all** new audio players (crowd bed, Icarus rumble, klaxon, shudder) are stopped/freed in `_finalize_cold_open()` (L976) — add them to the cleanup block alongside `_co_audio.queue_free()`. This is the skip-safety net.

---

## Test Strategy

### Unit / drift-guard tests (`tests/smoke/cold_open_lines.gd`)

The existing test is a **string-search drift guard** — it reads `gate_room.gd` source and asserts that load-bearing code patterns are present. This plan extends it:

- [ ] **Extend `REQUIRED_CAPTIONS`** with the new wired lines (Task 11).
- [ ] **`test_cold_open_sound_bed_wired(code)`** — assert `crowd_panic_bed`, `icarus_rumble`, `ship_shudder` asset paths are referenced in `gate_room.gd`.
- [ ] **`test_cold_open_energize_ramp_wired(code)`** — assert a volume tween on `_gate_hum_sfx` exists in `dial_and_open`.
- [ ] **`test_cold_open_crowd_vo_wired(code)`** — assert `_cap_crowd(` is defined and called with the crowd VO IDs (`open-crowd-where`, `open-crowd-what`, `open-eli-whatisthis`, `open-crew-whatwasthat`).
- [ ] **`test_cold_open_elicoming_wired(code)`** — assert `"open-eli-coming"` is referenced (the button response).
- [ ] **`test_cold_open_icarus_rumble_cuts_on_collapse(code)`** — assert the Icarus rumble player is stopped in `_collapse_gate()` or that `_collapse_gate` references the rumble player variable.
- [ ] **`test_cold_open_finalize_cleans_new_audio(code)`** — assert `_finalize_cold_open` references the new audio player variables (crowd bed, rumble, klaxon) so a skip can't orphan them.

### Flow test (`tests/smoke/e1_flow.gd`)
- [ ] **No changes needed** — the quest hand-off (`met_scott` → `QUEST_FIND_RUSH`) is already asserted and unchanged by this plan.

### Integration / manual verification
- [ ] **Headed playthrough** (Task 12) — run the cold open in a headed Godot with audio. Verify the soundbed layers, VO overlaps, and the button response. This is the only way to verify the *atmosphere* (headless tests can't hear).
- [ ] **Skip test** — hold Jump to skip at various points (during dial, during flood, during hand-off). Verify the end state is always: gate shut, player standing, Find Rush active, Scott auto-greet off, no orphaned audio.
- [ ] **Headless regression** — `tests/run.sh cold-open` and `tests/run.sh flow` both pass.

### Test execution
```bash
# Headless drift guards (no Godot assets needed):
tests/run.sh cold-open    # cold_open_lines.gd
tests/run.sh flow         # e1_flow.gd
tests/run.sh e1-opening   # e1_opening.gd (if it exists)

# Full suite:
tests/run.sh all

# Headed manual QA (requires Godot with audio):
# Launch the game, skip the title, observe the cold open.
```

---

## Dependencies

- **Blocker:** None — all work is additive to existing code. No upstream issue blocks this.
- **Related:** #136 (cold-open standoff cutscene — shares `standoff_camera.gd` / `standoff_cinematic.gd`), #137 (E1 away-team split — shares the gate room scene).
- **Asset dependency:** Tasks 1, 2, 5 require new audio assets to be sourced/authoried. The code can be wired with placeholder paths (the existing pattern: `_grunt()` no-ops cleanly if assets are absent) so implementation is not blocked by audio production.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Audio clipping / mud** — too many layers (master bed + crowd bed + Icarus rumble + klaxon + VO + grunts + thuds) could muddy the mix. | Set conservative `volume_db` on each layer (crowd bed at -12dB, rumble at -15dB, klaxon at -18dB). Duck the crowd bed under VO. Manual QA (Task 12) is the real gate. |
| **Playhead desync** — new `_cap_crowd()` calls fire on timers, not playhead, so they could drift from the master bed. | Keep crowd VO on short, fire-and-forget timers (not playhead-locked) — they're background texture, not lip-synced. The existing `_cap()` calls stay playhead-locked for the primary dialog. |
| **Skip orphaning audio** — a skip mid-flood could leave the crowd bed or Icarus rumble looping. | All new audio players are stopped/freed in `_finalize_cold_open()` (Step 12). Guard all start calls with `_co_skip`. |
| **Headless test breakage** — new audio players could error in `instant_mode` (no stream). | Follow the existing pattern: `_grunt()` / `_thud()` both no-op cleanly if streams are null. All new audio loads are guarded with `load() as AudioStream` null checks. The `instant_mode` early-return in `_run_arrival()` (L586) skips the entire cinematic, so none of this runs headless. |
| **VO file duplication confusion** — `open-scott-eli-now.wav` vs `open-scott-elinow.wav`, `open-man-broken.wav` vs `open-wounded-broken.wav`. | Task 10 audits and cleans these up before wiring. |
| **Reference docs don't exist** — `docs/OPENING_SCENE_SCRIPT.md` and `design/voice-line-manifest.md` are referenced but absent. | Task 0 creates them first so downstream tasks have a single source of truth. |

---

## Phasing

**Phase 1 — Foundation (Tasks 0, 10):** Author the reference docs, audit/clean VO files. No code changes. [Timebox: 1 session]

**Phase 2 — Sound design (Tasks 1–5):** Source/author audio assets, wire the soundbed layers (crowd panic, Icarus rumble, energize ramp, radio crackle, ship shudder). All guarded by `_co_skip` and cleaned up in `_finalize_cold_open()`. [Timebox: 2 sessions]

**Phase 3 — Dialog wiring (Tasks 6–9):** Wire the unreferenced VO clips (crowd confusion, Eli's "I'm coming!", marshalling barks, "Leave it", officer "I don't know, sir.", TJ "Are you okay?", Scott "I haven't seen Rush"). [Timebox: 1 session]

**Phase 4 — Tests & verification (Tasks 11–12):** Extend the drift guard, run headless regression, headed manual QA. [Timebox: 1 session]

---

## Notes for the Implementer

1. **Read `design/sgu-opening-reference.md` first** — it is the authoring target. The "essence" section (panic under discipline, overlapping voices, velocity & impact, darkness & cold, no answers → wonder) is the vibe spec.

2. **The code is already very complete.** Do not rewrite `_play_prologue_cinematic()`. All changes are **additive** — new `_cap_crowd()` calls, new `AudioStreamPlayer` starts, new cleanup in `_finalize_cold_open()`.

3. **Follow the existing `_co_skip` pattern religiously.** Every new audio start, every new `_cap_crowd()`, every new tween must be guarded by `if _co_skip: return` or `if not _co_skip:`. The skip funnels through `_finalize_cold_open()`, which must clean up all new players.

4. **The `_cap_crowd()` helper is the key new abstraction.** It's like `_cap()` / `_cap_now()` but:
   - Fire-and-forget (no playhead wait, no advance wait).
   - Optionally no caption (or a brief, non-blocking one).
   - Layered over existing captions (not replacing them).
   - Used for the overlapping crowd confusion / marshalling barks that make the evac feel chaotic.

5. **Audio assets can be placeholder-empty.** The existing pattern (`_grunt()`, `_thud()`) loads assets at runtime and no-ops if they're missing. Wire the code with the intended paths even if the assets aren't sourced yet — the cinematic runs silently for missing layers and never errors.

6. **The `instant_mode` path is sacred.** `_run_arrival()` (L586) returns early in `instant_mode` before `_play_prologue_cinematic()` is ever called. None of this plan's changes run headless. Do not break that guard.