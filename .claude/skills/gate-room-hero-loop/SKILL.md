---
name: gate-room-hero-loop
description: "Resume or re-run the Karpathy-style self-improvement loop that rebuilds the cinematic hero gate-room (scenes/gate_room_hero.tscn) toward the concept image design/concept-art/gate-room/target/gateroom-hero-target.png. Use when continuing visual refinement of the hero gate room, re-running the mutate→render→judge→commit-or-revert loop, or adapting the loop pattern to another scene."
argument-hint: "[iterations | resume]"
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Workflow, Glob, Grep
model: opus
---

# Gate-room hero self-improvement loop

A **Karpathy-style "commit if closer, revert if not" loop** that rebuilds the gate
room as close as possible to a concept image, run on `feature/gate-room-hero-portal`
(branched from `godot`). An LLM mutates the scene, Godot renders a frame, an
independent 3-judge panel compares it to the target, and git is the memory:
accepted → commit (new best), rejected → `git checkout --`.

## Goal image
`design/concept-art/gate-room/target/gateroom-hero-target.png` — a dark cinematic
cathedral: symmetric hall converging on an active Stargate whose blue churning
vortex is the only real light source; ribbed dark-metal walls with glowing
window-slits; tiered ceiling dome with downlights; console banks flanking the
foreground; wet reflective grid floor.

## The pieces (all on this branch)

| File | Role |
|---|---|
| `scenes/gate_room_hero.tscn` | Root scene (just runs the script). |
| `scripts/gate_room_hero.gd` | **The iteration surface.** Procedural builder. Typed CONFIG consts at top (HALL_*, GATE_*, CAM_*, *_ENERGY, *_COLOR, *_ROUGHNESS, FOG_DENSITY) + `_build_*` helpers. One value per line so mutations stay surgical. |
| `shaders/hero_portal.gdshader` | The vortex. UV-driven; samples `assets/hero/noise_1024.png` (the licensed Unity `RunesAndPortals/Shaders/Noise_0_1024.png`) in polar coords for filamentary churn. Distinct from `event_horizon.gdshader` (#30 tests). |
| `tests/shots/hero_shot.gd` | Minimal Forward+ render harness (no HUD/NPCs), 1280×720. |
| `tools/gate_hero_render.sh` | Wrapper: `--import` then render → `screenshots/loop/<name>.png`. |
| `assets/hero/` | Sandbox for loop-generated assets (so rejects `git clean` safely). |
| `screenshots/loop/{best,candidate}.png` | best = last accepted render; candidate = newest. **gitignored.** |
| `tools/gate_room_hero_loop.workflow.js` | The committed Workflow script (v3). |

## Render one frame by hand
```bash
tools/gate_hero_render.sh candidate 220   # → screenshots/loop/candidate.png
```
Run WITHOUT `--headless` (that blanks the frame) and with Forward+ (default). The
harness sets the window to 1280×720 to match the concept's 16:9.

## Re-run / resume the loop (the Workflow)
The loop is the `Workflow` tool driving `tools/gate_room_hero_loop.workflow.js`.
Per iteration it runs, **sequentially** (shared git tree + best.png):
1. **Mutate** — a `general-purpose` agent studies target + current best, makes ONE
   focused change to the scene/shader/assets, renders a candidate, self-reverts if
   the scene fails to parse. (Does NOT commit.)
2. **Judge** — 3 independent strict art-director agents (different lenses: tonality,
   ring/vortex, architecture) score candidate vs best vs target and vote `closer?`.
3. **Referee** — **accept gate = majority `closer` AND same-panel `avgCand > avgBest`**
   → `cp candidate best` + `git commit "loop(#N): … (~score/100)"`; else
   `git checkout -- <3 files> assets/hero && git clean -fdq assets/hero/`.

To launch a fresh batch (continues from current HEAD/best — best.png must reflect
HEAD; re-render it first if unsure):
```bash
tools/gate_hero_render.sh best 220        # sync best.png to current source
```
Then call the Workflow tool with `{ scriptPath: "tools/gate_room_hero_loop.workflow.js" }`.
To **resume** an interrupted run with cached agent results, pass
`{ scriptPath, resumeFromRunId: "<wf_…>" }`.

Tunables inside the script: `MAX` (iterations, default 60), the `RUBRIC`,
`ANTI_OSC` directive, the accept gate, and the `highStreak`/`consecutiveReverts`
stop conditions.

## Status & score trajectory (2026-06-08)
~125 accepted commits across 3 runs (each ~2–2.5h, ~230 agents, ~9M tokens).
Judge similarity-to-target: baseline → **~32 (runs 1–2 plateau)** → **~50 (run 3)**.
- **Run 1** got the gestalt: dark high-contrast hall, thick segmented ring +
  chevrons, blue vortex, flanking consoles, reflective floor.
- **Run 2** fixed the vortex (texture-sampled plasma + dark eye, replacing the
  "comma spiral" fBm) but **plateaued ~32 from OSCILLATION** — a relative-only
  accept gate kept committing lateral swaps (tonemap_exposure ping-ponging
  0.62↔0.95 between two judges' tastes).
- **Run 3 (v3) broke the plateau → ~50** by (a) tightening the gate to require a
  numeric same-panel gain, and (b) an `ANTI_OSC` rule forbidding global-exposure
  chasing — the over-crushed black side walls/dome were restored with LOCAL dim
  detail (emissive banding, window-slits, dome downlights), not exposure.

### Remaining gaps to attack next
- Side-wall + buttress material variety (still reads a bit uniform/banded).
- Ceiling dome grandeur (concentric rings read but are modest).
- Gate ring should be darker metal with brighter discrete chevrons.
- Vortex polish: more blue, smaller/darker eye, finer filaments.

## Hard-won gotchas (also in agent memory)
- **`const float TAU` / `PI` in a `.gdshader` redefines a built-in** → silent
  compile failure → material renders **invisible**; edits then "do nothing".
  Grep render stderr for `SHADER ERROR` / `Redefinition`.
- **Workflow `agent({schema})` that doesn't call `StructuredOutput` THROWS and
  kills the whole run** — even inside `parallel()` (contrary to docs). Every agent
  call is wrapped in a `safeAgent` try/catch → `null`; a thin/empty judge panel
  degrades to a revert instead of crashing a multi-hour run. (This ended run 1.)
- **Typed GDScript:** no `:=` on Dictionary/Variant values (a `CFG` dict broke
  inference everywhere — hence the typed top-level consts); loop vars over literal
  arrays need `for x: float in [...]`.
- **Relative accept gates oscillate.** "Closer than previous" alone commits lateral
  moves forever. Require a numeric improvement from the *same* panel to climb.

## Running continually on `sparky` via hermes (free, zero Claude-Code credits)

The loop can run unattended on the `sparky` build host driven by the **hermes
agent** (Nous Research), which uses its own Nous Portal inference — so it slowly
improves the scene around the clock without spending Claude Code credits.

Pieces (all under `tools/hermes/`):
- `gate_loop_iteration.md` — the per-tick instructions hermes follows: prep/branch
  guard → view target + best → 9-point rubric → ONE change → render → judge → commit
  if closer / revert if not → push `feature/gate-room-hero-portal`. One iteration per run.
- `skills/gate-hero-loop/SKILL.md` — the hermes-format skill (installed to
  `~/.hermes/skills/` on the host so hermes "knows" the loop; attached via `--skill`).
- `install_on_sparky.sh` — idempotent installer (run ON the host).

`tools/gate_hero_render.sh` is OS-aware: on headless Linux it wraps Godot in
`xvfb-run` (a Vulkan GPU still rasterises) and locates the PNG in the Linux
userdata dir.

### Install (when sparky is reachable over Tailscale)
```bash
ssh sparky 'REPO=~/stargate-universe SCHEDULE=30m bash -s' < tools/hermes/install_on_sparky.sh
```
Prereqs on the host: Godot 4.6 on PATH (`godot`/`godot4` or `GODOT_BIN`), a GPU
(`nvidia-smi`) or `xvfb`, and hermes installed + `hermes login` (Nous Portal).
The installer refreshes the repo on the branch, smoke-renders `best.png`, sets
`approvals.cron_mode=allow` (else cron auto-denies the agent's git/terminal calls
— the key gotcha), installs the skill, registers a `hermes cron` job (`--workdir`
the repo), and adds a system-crontab line driving `hermes cron tick` every few
minutes so jobs fire without a long-lived hermes daemon.

### Operate
```bash
ssh sparky 'hermes cron list'                              # see the job
ssh sparky 'cd ~/stargate-universe && hermes cron tick'    # force one iteration now
ssh sparky 'git -C ~/stargate-universe log --oneline origin/feature/gate-room-hero-portal | head'
ssh sparky 'hermes cron pause gate-hero-loop'              # pause / resume / remove
```
The hermes loop self-judges (single agent, no separate panel) — cheaper but more
lenient than the Claude `Workflow` panel; the iteration prompt biases it to revert
when unsure. Pull its commits back with `git fetch && git log origin/<branch>`.

## Adapting the pattern to another scene
Copy the four pieces (procedural scene + parametric consts, a fixed-camera render
harness, a render wrapper writing best/candidate PNGs, the Workflow script), point
`TARGET` at the new reference, rewrite the `RUBRIC` for that subject, and keep the
tightened accept gate + `safeAgent` wrappers. To run it free/continually instead
of via the Claude Workflow tool, swap the orchestrator for the `tools/hermes/`
package above (hermes cron + per-tick markdown).
