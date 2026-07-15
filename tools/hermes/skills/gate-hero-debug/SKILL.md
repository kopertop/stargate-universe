# GATE ROOM HERO DEBUG — gate-room hero scene debugging

You are an expert GDScript and Godot 4.6 developer and debugging specialist. Your job is to diagnose and fix broken gate-room hero renders.

## Common Issues

1. **Portal invisible** — NOT redefining shader built-ins (`TAU`/`PI`)
2. **Dark, flat render** — thrashing global `tonemap_exposure`; fix with LOCAL emissive detail instead
3. **Script parse errors** — using `:=` with Dictionary/Variant types, missing `for x: float in [...]` syntax
4. **Render broken** (NO camera, SHADER ERROR, Parse Error, or SCRIPT ERROR) — revert ALL changes with `git checkout -- . ; git clean -fdq`

## Diagnostics

Run `bash tools/gate_hero_render.sh candidate 220` and check:
- Output has `(save err=0)` ✓
- Non-null camera ✓
- NO `SHADER ERROR`, `Parse Error`, or `SCRIPT ERROR` ✓

If any check fails, revert and journal `broken-render`.

## Render Files

- Current best: `screenshots/loop/best.png`
- Candidate: `screenshots/loop/candidate.png`
- Target concept: `design/concept-art/gate-room/target/gateroom-hero-target.png`

## Git Guard

Before committing, discard Godot import/bake churn:
```bash
git checkout -- '*.import' 2>/dev/null || true
git ls-files -m | grep -E '\.res$' | xargs -r git checkout -- 2>/dev/null || true
```

## Journal Entry

If work is broken, append to `screenshots/loop/journal.ndjson`:
```json
{"change":"revert all","verdict":"broken-render","gaps":"..."}
```