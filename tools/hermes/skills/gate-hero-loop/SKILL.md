---
name: gate-hero-loop
description: "Run one iteration of the Stargate gate-room hero visual self-improvement loop: mutate the Godot scene, render, judge vs the concept image, commit if closer / revert if not. For the autonomous hermes cron loop on the sparky build host."
version: 1.0.0
platforms: [linux, macos]
metadata:
  hermes:
    tags: [godot, stargate, gate-room, render, self-improvement, karpathy, loop, vortex, shader, beauty-shot, cron, sparky]
    related_skills: [godot-game-development]
---

# Gate-room hero self-improvement loop

A Karpathy-style "commit if closer, revert if not" loop that rebuilds a Godot
gate-room scene to match a concept image. You run ONE iteration per invocation
(a scheduler calls you repeatedly). Inference is your own (Nous Portal) — this
loop is designed to run unattended and cost nothing on the user's coding-tool
budget.

## Where
Repo: the `--workdir` you were given (a checkout of `kopertop/stargate-universe`
on branch **feature/gate-room-hero-portal**). Everything is relative to it.

## The single source of truth
Read and follow **`tools/hermes/gate_loop_iteration.md`** in the repo EXACTLY,
top to bottom. It defines: prep/branch guard → view target + best images →
the 9-point art rubric → make ONE focused change → `bash tools/gate_hero_render.sh
candidate 220` → judge honestly → `cp candidate best` + commit + push (accept)
OR `git checkout --`/`git clean` (reject). Do exactly one iteration, then stop.

## Non-negotiables
- Branch must be `feature/gate-room-hero-portal`. NEVER touch `main`/`develop`.
- Exactly ONE change per run; keep it surgical; finish in one pass (don't loop).
- `screenshots/loop/` is gitignored — never commit PNGs; `best.png` is the memory.
- Accept ONLY a clearly-better render; when in doubt, REVERT.

## Render notes (sparky / headless Linux)
- `tools/gate_hero_render.sh` auto-wraps Godot in `xvfb-run` when there's no
  `$DISPLAY`; a Vulkan GPU still does the rasterising. It writes
  `screenshots/loop/candidate.png` (or `best.png`).
- A render is only valid if the output has `(save err=0)`, a non-null camera, and
  NO `SHADER ERROR` / `Parse Error` / `SCRIPT ERROR`. Otherwise the edit is broken
  → revert and report.

## Known traps (don't repeat them)
- Don't redefine shader built-ins (`TAU`/`PI`) in `hero_portal.gdshader` — it
  silently fails compile and the portal renders INVISIBLE.
- Don't thrash global `tonemap_exposure` (it oscillated ~90 prior iterations).
  Fix darkness with LOCAL emissive detail (ribbing, window-slits, dome downlights).
- Keep GDScript statically typed (no `:=` on Dictionary/Variant values).
