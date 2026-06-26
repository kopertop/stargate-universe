# Stargate Universe — Accessibility Requirements

- Version: 1.0 · Last Updated: 2026-06-26 · Engine: Godot 4.6
- Owner: accessibility review (see `accessibility-specialist` agent)
- Scope: baseline requirements the game must meet, marked against what already ships.

Status key: ✅ implemented · 🟡 partial · ⬜ required (not yet built). Priority:
**P1** (must-have for the vertical slice / ship) · **P2** (should-have) · **P3** (nice-to-have).

## 1. Input & Controls

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-IN-01 | Full gamepad support with face-button remapping | P1 | ✅ | `Gamepad` autoload; SDL/Xbox remap, layout GUID round-trip to `user://settings.cfg`; `GamepadConfigDialog`. |
| A11Y-IN-02 | Full keyboard rebinding for every action | P1 | 🟡 | InputMap defines 19 actions; expose a rebinding UI for keyboard parity with the gamepad dialog. |
| A11Y-IN-03 | No essential action requires a hold/chord without a toggle alternative | P2 | 🟡 | Hold-to-skip cold open (~1 s) exists; audit other holds and offer toggles. |
| A11Y-IN-04 | No time-critical input the player can't extend/disable | P1 | 🟡 | Air-crisis/gate-window timer is a near-miss recall (not death); confirm a difficulty/assist toggle slows or disables it. |

## 2. Visual — text, scale, colour

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-VIS-01 | HUD/UI scales without clipping or overlap | P1 | ✅ | Uniform anchored HUD scale (`hud-scale` test mode). Keep the unit-frame + action-bar model intact across scales. |
| A11Y-VIS-02 | Adjustable subtitle/dialog text size | P1 | ⬜ | Add a text-scale setting feeding DialogScreen + captions; verify against the Fable dialog layout. |
| A11Y-VIS-03 | Subtitles on by default; speaker-named; sufficient contrast | P1 | 🟡 | Bottom subtitle exists in dialog cinema; add a background scrim/contrast option and a subtitles toggle. |
| A11Y-VIS-04 | Do not rely on colour alone to convey state | P2 | ⬜ | Pair colour cues (alert red, objective gold, Ancient-glyph signage) with icon/shape/text. |
| A11Y-VIS-05 | Colourblind-safe palette option (deuter/prot/trit) | P2 | ⬜ | Offer a palette swap or post-process; validate the amber/gold accent + alert states. |
| A11Y-VIS-06 | Readable signage fallback | P2 | 🟡 | Rooms render Ancient glyphs until deciphered, then decode to readable text on player entry — ensure the deciphered text meets contrast/size rules. |

## 3. Audio

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-AUD-01 | Independent volume sliders (master/SFX/music/voice) | P1 | 🟡 | `Settings` persists bus volume; ensure separate SFX/Music/Voice buses are all exposed. |
| A11Y-AUD-02 | No information conveyed by audio alone | P1 | 🟡 | Air/alert cues must have a visual equivalent (HUD/console), not just klaxon SFX. |
| A11Y-AUD-03 | Voiced dialogue mirrored by subtitles | P1 | 🟡 | Baked LuxTTS/IndexTTS voice lines must always carry the matching caption (VO gates cutscene advance). |

## 4. Motion, cinematics & comfort

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-MOT-01 | Skippable cinematics | P1 | ✅ | Hold-to-skip the cold open; `instant_mode` snaps end-state. Extend skip to other cutscenes. |
| A11Y-MOT-02 | Reduce camera shake / flash option | P2 | ⬜ | Cold open uses dark-open + light flicker + gate flush; add a reduced-motion/flash toggle. |
| A11Y-MOT-03 | No unavoidable rapid flashing (photosensitivity) | P1 | 🟡 | Audit the flicker-up and kawoosh sequences against flash thresholds; gate behind A11Y-MOT-02. |

## 5. Difficulty & assists

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-DIF-01 | Selectable difficulty | P2 | ✅ | `Settings` difficulty config. |
| A11Y-DIF-02 | Assist options decouple challenge from progression | P2 | 🟡 | E1 has NO death / NO stranding by design; ensure timer pressure is assist-adjustable without blocking the story. |

## 6. Screen reader & navigation

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| A11Y-SR-01 | Menus/HUD expose names to Godot's accessibility/TTS layer | P3 | ⬜ | Godot 4.6 accessibility (AccessKit) — label menu Controls; lower priority for a 3D slice. |
| A11Y-SR-02 | Keyboard/controller focus order is logical and visible | P2 | 🟡 | Menu focus drives the UI-hover SFX (`attach_ui_hover`); verify focus rings + order in every menu. |

## Verification

- Each requirement should map to a check in the smoke suite or a manual QA pass
  (`/qa-plan`, `/playtest-report`). Input remap + HUD scale already have headless
  coverage (`tests/run.sh gamepad`, `hud-scale`).
- Re-run an accessibility audit (`accessibility-specialist`) when UI or cinematics
  change materially. This doc is the checklist; `/ux-design` owns interaction patterns.
