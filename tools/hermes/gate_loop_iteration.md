# Gate-room hero loop — one iteration (hermes / sparky, autonomous)

You are running ONE iteration of a Karpathy-style self-improvement loop that
rebuilds a Godot gate-room scene to match a concept image AS CLOSELY AS POSSIBLE.
You run unattended on the `sparky` build host. Use your terminal, file, and
code-execution tools. Work entirely inside the repo at the current working
directory. Be decisive and finish in one pass.

## 0. Prep (must do first)
```
git rev-parse --abbrev-ref HEAD          # MUST be feature/gate-room-hero-portal
git fetch origin && git checkout feature/gate-room-hero-portal && git pull --ff-only origin feature/gate-room-hero-portal
git status --porcelain                    # MUST be clean before you start
```
If HEAD is any other branch (especially main/develop) or the tree is dirty with
changes you didn't make, STOP and do nothing — report the anomaly.

## 1. Look at the goal and the current best
View BOTH images with your image/vision tool:
- TARGET (goal): `design/concept-art/gate-room/target/gateroom-hero-target.png`
- CURRENT BEST: `screenshots/loop/best.png` (if missing, run `bash tools/gate_hero_render.sh best 220` once to seed it from the committed scene)

## 2. The art target (score closeness on these, priority order)
1. TONALITY: very dark, high-contrast; portal + thin volumetric spot-shafts are the only bright areas. Walls/ceiling DIMLY visible detailed metal, NOT a black void and NOT a uniform blue/grey wash.
2. PALETTE: desaturated cool steel + black; blue lives in the portal + console screens only.
3. ARCHITECTURE/DEPTH: stacked ribbed wall panels, horizontal banding, faint glowing window-slits, large diagonal buttress beams flanking the gate, a tiered ceiling DOME with downlights. Tall, cavernous.
4. GATE RING: thick segmented DARK-metal ring with inward glowing TRIANGULAR chevrons; railed platform + short central staircase.
5. VORTEX: near-circular churning blue-white plasma filling the ring, fine filaments, small dark unstable eye, soft bloom halo.
6. CONSOLE BANKS: rows of faint-blue screens along BOTH side walls in the foreground.
7. FLOOR: dark wet metal grid plates, subtle long reflections, perspective seams converging to the gate.
8. LIGHTING: volumetric god-rays from ceiling spots; portal glow + floor reflection; low-key single-dominant-source.
9. COMPOSITION: symmetric one-point perspective, gate centred, camera near floor.

DO NOT thrash global `tonemap_exposure` (it oscillated for ~90 prior iterations). Keep it ~0.7–0.85; fix darkness with LOCAL emissive detail, not exposure/ambient.

## 3. Make ONE focused, high-impact change
Pick the single biggest gap vs the target and attack it. Edit ONLY:
`scripts/gate_room_hero.gd` (typed CONFIG consts + `_build_*` helpers), `shaders/hero_portal.gdshader`, `scenes/gate_room_hero.tscn`. New assets go ONLY in `assets/hero/` (you may copy the licensed Unity assets from `/Users/cmoyer/Projects/unity/unity-sgu/Assets/PaulosCreations/RunesAndPortals` if that path exists on this host; otherwise stick to procedural/code changes).
Keep GDScript statically typed. Do NOT redefine shader built-ins (`TAU`/`PI`) — that silently fails compile and the material vanishes.

## 4. Render the candidate
```
bash tools/gate_hero_render.sh candidate 220
```
The output line must contain `(save err=0)` and `-> screenshots/loop/candidate.png`, and there must be NO `SHADER ERROR` / `Parse Error` / `SCRIPT ERROR` and a non-null camera. If the render broke, your edit is bad: `git checkout -- scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero && git clean -fdq assets/hero/` and report `reverted (broken render)`. Done.

## 5. Judge honestly (you are a strict art director)
View `screenshots/loop/candidate.png` and compare to TARGET and to `screenshots/loop/best.png`.
Accept ONLY if the candidate is GENUINELY, visibly closer to the target than best — a real improvement on at least one rubric dimension with no clear regression on others. A lateral move, a regression, or "merely different" ⇒ REJECT. When in doubt, REJECT (the bar is "clearly better").

## 6a. If ACCEPT
```
cp screenshots/loop/candidate.png screenshots/loop/best.png
git add -A scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero
git commit -m "loop(hermes): <one-line what changed> — closer to concept" -m "Co-Authored-By: hermes <noreply@nousresearch.com>"
git push origin feature/gate-room-hero-portal
```
Report: `ACCEPT — <change> — <which rubric dimension improved>`.

## 6b. If REJECT
```
git checkout -- scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero
git clean -fdq assets/hero/
```
Report: `REVERT — tried <change> — <why it wasn't closer>`.

## Rules
- NEVER push to `main` or `develop`. Only `feature/gate-room-hero-portal`.
- `screenshots/loop/` is gitignored — never commit PNGs; `best.png` is your memory.
- Exactly ONE change per iteration. Keep it surgical. Finish in one pass; do not loop.
- If anything is ambiguous or the tree is unexpectedly dirty, do NOTHING and report.
