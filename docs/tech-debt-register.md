# Technical Debt Register

## Web-era register — rebuilt 2026-10-06 from a full `src/*.js` scan

Previous Godot-era entries (TD-001 through TD-008) are archived at the bottom.
The codebase was re-pivoted to web/Three.js on 2026-09-08; this register reflects
the current `src/*.js` (24 modules, 3,308 LOC) loaded via ES import maps.

Scoring: `priority = (impact × frequency) / effort`. Effort is T-shirt (S/M/L/XL).

| ID | Category | Description | Files | Effort | Impact | Priority | Added |
|----|----------|-------------|-------|--------|--------|----------|-------|
| TD-101 | ✅ Architecture | RESOLVED 2026-10-14 — Save/load extracted to `src/save.js` (178 lines). FTL+countdown extracted to `src/ftl.js` (168 lines, `createFtlSystem(ctx)` DI pattern) with 64 unit tests (`tests/ftl.test.js`). FTl.js now WIRED into main.js — inline FTL/countdown code (lines 195-256) replaced with `createFtlSystem()` call, destructured return, and getter-based ctx injection for world/destiny/planet/travel/kino/knockedOut. Save system ctx updated to use `__ftl.countdown` getter/setter. All 1007 tests pass, ESLint 0/0. | `src/main.js`, `src/save.js`, `src/ftl.js` | M | Med | Med | 2026-10-06 |
| TD-102 | ✅ Build/Type | RESOLVED 2026-10-12 — Added `package.json` (devDependencies: `three@0.180.0`, `typescript@^5.6.0`, `eslint@^9.0.0`; scripts: `test`, `typecheck`, `lint`, `build`) and `jsconfig.json` (TypeScript `--checkJs` config with import-map path aliases for `three` and `three/addons/*`). Added `eslint.config.js` flat config with ES module support, browser globals, and minimal rules (no-debugger, no-unused-vars warn, prefer-const warn, no-console warn). Lint runs clean: 0 errors, 18 warnings (all pre-existing minor unused vars in gate-room.js textures and test fixtures). CI typecheck step committed 2026-10-09 (cfafa32). ESLint config committed 2026-10-12 (bfbcd3c) on PR #197 branch. | `package.json`, `jsconfig.json`, `eslint.config.js`, `index.html`, `build.sh` | L | Med | Med | 2026-10-06 |
| TD-103 | ✅ Test | RESOLVED 2026-10-14 — 27 test files now cover ALL 25 src/ modules: rpg, settings, quest, hotwire, input, console, components, interact, save, kino, assets, music, ship, flow, ancient, recorder, ui, destination, wormhole, leveledit, player, autoplay, gate-room, main, ftl. 1007 tests pass with `node --test` (Node 18+ built-in runner, zero framework deps). main.js covered with 169 tests using regex-based source-text extraction (constants, mmss formatter, FTL system, gate travel, audio, particles, main loop, quest wiring, RPG, debug interface). ftl.js covered with 64 tests testing createFtlSystem() directly (window, cooldown, countdown, knockOut, warnings, clockScale). | `src/*.js` | L | High | High | 2026-10-06 |
| TD-104 | ✅ Error Handling | RESOLVED 2026-10-06 — 6 silent `catch {}` blocks replaced with `catch (e) { console.warn(...) }` in rpg.js, settings.js, leveledit.js, main.js. quest.js fetch wrapped with HTTP status check. Commit on `heartbeat/pr195-replacement`. Updated 2026-10-06 17:30 UTC: `knockout_lines.json` fetch (`.catch(() => {})`) also upgraded to HTTP status check + `console.warn` — last silent catch in main.js. | — | S | Med | High | 2026-10-06 |
| TD-105 | ✅ Asset Loading | RESOLVED 2026-10-06 — GLTFLoader.loadAsync in player.js wrapped with .catch() (logs + rethrows). Music layer loadAsync in music.js wrapped with .catch() (skips missing layer). SFX loadAsync in main.js wrapped with try/catch per file (warns + continues). Ship layout/connections fetch in main.js wrapped with try/catch + HTTP status check (falls back to empty objects so scene still renders). Commit 4ac16c4 on `heartbeat/pr195-replacement`. | — | S | High | High | 2026-10-06 |
| TD-106 | ✅ Save System | RESOLVED 2026-10-06 — Added `SAVE_VERSION = 1` constant and `migrateSave()` function to `main.js`. `saveGame()` now writes `version: 1` into the localStorage blob. `loadGame()` calls `migrateSave()` before restoring state, treating version-less saves as v0. Future schema changes add migration steps in `migrateSave()`. Commit 3dac598 on `heartbeat/pr195-replacement`. | — | S | Med | High | 2026-10-06 |
| TD-107 | ✅ Code Quality | RESOLVED 2026-10-06 — Added JSDoc `@typedef` blocks for `ComponentSpec`, `BuildContext`, and `ComponentDef` at the top of `components.js`. Documents the implicit component schema (type, u/v position, ry rotation, anchor, loot, style) and the build() contract so IDEs provide autocomplete and contributors don't need to read the object literal. Commit 20becfe on `heartbeat/pr195-replacement`. | — | M | Low | Low | 2026-10-06 |
| TD-108 | ✅ Build | RESOLVED 2026-10-07 — Extracted inline Python heredocs from `build.sh` into `tools/vendor.py` (standalone module: `vendor_addons()`, `rewrite_index()`, `main()`). `build.sh` now calls `python3 tools/vendor.py` instead of using `<<'PY'` heredocs. Vendor logic is now testable and data-driven. Asset manifest extraction deferred (the `cp` chain is stable and documented). | `build.sh`, `tools/vendor.py` | M | Low | Low | 2026-10-07 |

## Resolved / closed

| ID | Category | Description | Resolution | Closed |
|----|----------|-------------|------------|--------|
| TD-104 | Error Handling | Silent `catch {}` blocks | ✅ Resolved 2026-10-06 | 2026-10-06 |
| TD-105 | Asset Loading | Missing error handling on GLTFLoader/fetch | ✅ Resolved 2026-10-06 | 2026-10-06 |
| TD-106 | Save System | No save versioning or migration | ✅ Resolved 2026-10-06 | 2026-10-06 |
| TD-107 | Code Quality | Missing JSDoc typedefs for component schema | ✅ Resolved 2026-10-06 | 2026-10-06 |
| TD-103 | Test | Zero test files — no automated verification | ✅ RESOLVED 2026-10-14 — 1007 tests across 27 files (ALL 25 modules covered, including main.js with 169 tests and ftl.js with 64 tests) | 2026-10-14 |
| TD-101 | Architecture | main.js god object — FTL/countdown inline | ✅ RESOLVED 2026-10-14 — ftl.js wired into main.js via createFtlSystem() DI, inline code replaced | 2026-10-14 |

---

## Archived: Godot-era register (2026-06-26)

These items reference files that no longer exist (`scripts/*.gd`, `addons/vrm/`,
`tests/smoke/`). Kept for historical context only.

| ID | Category | Description | Status |
|----|----------|-------------|--------|
| TD-001 | Architecture | `gate_room.gd` 4,603-line god object | **Deleted** — file removed in re-pivot |
| TD-002 | Architecture | `room.gd` 2,657-line god object | **Deleted** — file removed in re-pivot |
| TD-003 | Documentation | Missing architecture docs | **Moot** — `docs/architecture/` never created |
| TD-004 | Code Quality | Untyped GDScript signatures (false positive) | **Deleted** — no GDScript left |
| TD-005 | Dependency | VRM addon FIXMEs/TODOs | **Deleted** — addon removed in re-pivot |
| TD-006 | Documentation | `/sound-fetch` skill described browser stack | **Moot** — skill context changed |
| TD-007 | Test | SceneTree-based smoke suite | **Deleted** — `tests/smoke/` removed |
| TD-008 | Code Quality | Orphaned `.uid` sidecar | **Deleted** — no Godot imports left |

## Notes

- Tech debt is a tool, not a failure. Every open entry records WHY it's accepted
  and what would trigger a re-evaluation.
- The web-era codebase is remarkably clean: zero `TODO`/`FIXME`/`HACK` comments,
  zero `console.log` debug statements, zero `debugger` statements, no dead code
  found. The debt is structural (no tests, no build tooling, no type checking)
  rather than code-level neglect.
- Highest-value quick wins: TD-104 (error handling, effort S) and TD-105 (asset
  load error handling, effort S) — both are small changes with high impact on
  user experience when things go wrong.