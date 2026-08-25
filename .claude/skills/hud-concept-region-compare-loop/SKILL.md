---
name: hud-concept-region-compare-loop
description: |
  Drive a Karpathy "commit-if-closer / revert-if-not" loop that matches a Godot
  game HUD to a concept SCREENSHOT FROM A DIFFERENT GAME, using a deterministic,
  non-subjective metric. Use when: (1) re-skinning/restyling a HUD toward a
  reference image whose 3D world differs from yours (so a whole-frame pixel diff
  is meaningless), (2) you need an objective per-iteration score to decide
  commit vs rollback, (3) a palette/color change "doesn't move the score" and you
  suspect why, (4) filling an empty HUD region with a panel makes the score WORSE
  not better. Covers the region-palette-signature comparison technique
  (tools/hud_compare.py + tools/hud_loop.sh), the headless-safe capture via the
  TestCapture autoload, and the two calibration gotchas that bite this loop:
  the layout-gated metric and the HSV "dark bucket" trap.
author: Claude Code
version: 1.0.0
date: 2026-06-17
---

# HUD-vs-Concept Region-Signature Comparison Loop

## Problem
You want to iterate a HUD toward a reference screenshot, committing only changes
that are measurably "closer." But the reference is a screenshot of a *different
game* — different 3D world, lighting, characters. A whole-frame pixel diff is
pure noise (most pixels never match) — the classic render-diff baseline poisoning
trap (`godot-render-diff-baseline-poisoning`). You need an objective signal that
isolates the HUD, not the world.

## Context / Trigger Conditions
- Matching a Godot HUD to a concept image (e.g. a WoW-style layout) for issue #141.
- "I changed the palette but the comparison score didn't move."
- "I added a minimap/panel to an empty region and the score went DOWN."
- You need a per-iteration number to gate `git commit` vs `git checkout`.

## Solution
Compare **per-region HUD palette signatures**, not whole frames.

1. **Capture** the live HUD over a gameplay scene HEADED (never `--headless` —
   that renders blank). This repo's `TestCapture` autoload arms on a `capture`
   user arg and saves `user://capture.png`:
   `Godot --quit-after 200 res://scenes/room.tscn ++ capture room_id=<id>`.
   `tools/hud_loop.sh <label> [room_id]` wraps this: capture → score → log →
   print a `CLOSER ✓ / NOT ✗` verdict vs the recorded baseline.
2. **Score** with `tools/hud_compare.py`: for each named normalized region
   (player frame TL, target frame, minimap TR, quest tracker, chat BL, action
   bar BC, menu column) compute the *fraction* of pixels in palette buckets
   (gold / HP-green / cyan / bright / dark) in BOTH the concept and the candidate.
   Region score = `100 * (1 - mean|Δfraction|)`. **Exclude the world center.**
3. The ABSOLUTE total is not meaningful (your content differs); the **delta**
   between two candidate captures is — that is the commit-if-closer signal.
4. To compare against the LAST commit (not the original baseline), read the
   printed `SCORE=` and compare to the previous phase's number in
   `docs/hud-redesign/captures/_scores.log`.

### Gotcha 1 — the metric is LAYOUT-GATED
A palette-only change (e.g. flip a border color) scores ~0 if the element sits
OUTSIDE the concept-anchored region. The fix is NOT to widen the region to where
your element already is — it is to MOVE your element into the concept's region.
Until then, gate foundation/palette work on **visual review + smoke tests**, not
the metric. The metric becomes the primary driver only after repositioning.
(Observed: gold palette flip = +0.001; same gold once the unit frame moved into
the top-left region = +1.24.)

### Gotcha 2 — the HSV "dark bucket" trap
The `dark` bucket is `value <= ~0.22`. A "mid-tone" fill below that threshold
STILL counts as dark, so filling an empty region with a too-dark panel makes the
region score WORSE. To match a bright concept region you need value ABOVE the
threshold AND a hue that matches the concept's region signature. Pick a
**thematically-honest** color, not a metric hack: the concept minimap is green
terrain, so a sci-fi **radar-green** disc (`v≈0.34`, saturated green) both reads
correctly AND matches the region — that jumped the minimap region 81→92.
(Observed: a `v=0.10` disc made the region WORSE, 81.4→81.4; greenifying to
`v=0.34` took it to 91.8.)

## Verification
- `tools/hud_loop.sh <label>` prints `SCORE=` and a per-region table; a `--composite`
  side-by-side (concept | candidate, region boxes drawn) lets you eyeball it too.
- A genuine improvement shows BOTH a positive delta in the targeted region AND a
  visually-correct composite. If the delta is positive but the composite looks
  wrong, you are gaming the metric — stop.
- Always run the structural smoke test (`tests/run.sh hud-wow` etc.) after each
  step; the metric does not catch broken anchors / overlaps / parse errors.

## Example
```
tools/hud_loop.sh baseline            # capture current HUD, record baseline score
# ...edit hud.gd (reposition unit frame into the top-left region)...
tools/hud_loop.sh phase1              # -> phase1=89.05 baseline=87.81 delta=+1.24 CLOSER ✓
"$GODOT" --headless --quit-after 600 -s res://tests/smoke/hud_wow.gd   # PASS
git commit ...                        # commit only because closer AND tests pass
```

## Notes
- Keep per-iteration capture PNGs out of git (`docs/hud-redesign/captures/` is
  gitignored); commit only a curated `result.png`.
- macOS ships bash 3.2: expanding an empty array under `set -u` errors — guard with
  `${ARR[@]+"${ARR[@]}"}` (bit `tools/hud_loop.sh` once).
- Conditional widgets (target frame shown only when an NPC is selected) are
  invisible in a plain room capture — they need a demo-state capture hook to be
  measurable. Always-on widgets (unit frame, action bar, minimap) are measurable
  immediately.
- Related: `godot-render-diff-baseline-poisoning` (why whole-frame diffs fail),
  `feedback_chris_working_style` (commit whenever closer).

## References
- This repo: `tools/hud_compare.py`, `tools/hud_loop.sh`, `scripts/test_capture.gd`,
  `docs/hud-redesign/HANDOFF.md`, GitHub issue #141.
