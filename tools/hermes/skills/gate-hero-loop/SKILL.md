---
name: gate-hero-loop
description: "Run one cycle of the Stargate gate-room hero self-improvement studio on the sparky host: a hermes PM delegates a Godot-developer change, renders it, then an INDEPENDENT Ollama-Cloud vision reviewer panel (qwen3-vl ×3) votes closer/not — commit if closer, revert if not. For the autonomous hermes cron loop."
version: 2.0.0
platforms: [linux, macos]
metadata:
  hermes:
    tags: [godot, stargate, gate-room, render, self-improvement, karpathy, loop, vortex, shader, beauty-shot, cron, sparky, ollama, qwen3-vl, reviewer, project-manager]
    related_skills: [godot-game-development]
---

# Gate-room hero studio — one cycle (PM ▸ Godot dev ▸ Ollama reviewer panel)

A Karpathy "commit if closer, revert if not" loop, run as a tiny autonomous studio
on the `sparky` build host. You are invoked once per cycle by the scheduler.
Inference for the PM + developer is hermes/Nous (free); the reviewer is Ollama
Cloud vision (qwen3-vl) — an INDEPENDENT judge so the developer never grades its
own homework.

## Roles (briefs live in the repo under `tools/hermes/`)
- **PM** — `roles/project_manager.md`. THIS is your playbook. Run its one-cycle
  sequence: prep/guard → developer makes ONE change → render → reviewer panel →
  obey the verdict (commit+push / revert) → journal. You do not judge.
- **Godot developer** — `roles/godot_developer.md`. Makes exactly one focused change
  toward `design/concept-art/gate-room/target/gateroom-hero-target.png`. Delegate it
  or perform it inline following that brief.
- **Reviewer panel** — `hermes_review.sh <target> <best> <candidate>`. THREE hermes
  agents under profiles gd-qa-1/2/3, each on a DIFFERENT model + lens. Emits
  `VERDICT=ACCEPT|REJECT` (exit 0/10). AUTHORITATIVE — never overrule it.

## Where
The `--workdir` you were given: a checkout of `kopertop/stargate-universe` on branch
**feature/gate-room-hero-portal**. Everything is relative to it.

## Do exactly this
Follow `tools/hermes/roles/project_manager.md` top to bottom, once, then stop.

## Non-negotiables
- NEVER touch `main`/`develop`; only `feature/gate-room-hero-portal`.
- Exactly ONE change per cycle; finish in one pass (don't loop).
- `screenshots/loop/` is gitignored — never commit PNGs/journal; `best.png` is the memory.
- The Ollama reviewer panel is ground truth for "closer or not" — never overrule it.

## Render / env notes (sparky)
- `tools/gate_hero_render.sh` wraps Godot in `xvfb-run` headless (GB10 Vulkan does the
  rasterising) and writes `screenshots/loop/{candidate,best}.png`.
- The reviewer profiles (gd-qa-1/2/3) carry the ollama.com provider + key in their own
  hermes config (cloned from default) — no extra env needed. `jq` must be installed.
  Recreate them with `tools/hermes/setup_reviewer_profiles.sh`.

## Known traps
- Don't redefine shader built-ins (`TAU`/`PI`) — silent compile fail → invisible portal.
- Don't thrash global `tonemap_exposure`; fix darkness with LOCAL emissive detail.
- Keep GDScript statically typed (no `:=` on Dictionary/Variant values).
