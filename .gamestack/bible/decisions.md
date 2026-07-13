# SGU Development Decisions Log

Autonomous development progress log for the Stargate Universe Godot 4.6 project.

---

## 2026-07-12 — Session: Boot-Blocking Autoload Fix (P0)

### Context
- Ran `sgu_judge.sh` and headless test suite (`tests/run.sh scene`)
- Discovered the game **cannot boot** — critical P0 architecture failure
- 10+ missing autoload scripts, parse errors in `audio.gd`, missing `GameClock` autoload, missing translation files

### Scores (pre-fix)
| Dimension | Score | Notes |
|---|---|---|
| Architecture | 0/10 | 10 missing autoloads, parse errors, game can't boot |
| Code Quality | 3/10 | Tests can't run due to boot failure |
| Gameplay Depth | 5/10 | Episode 1 quest chain defined in data (22 steps) but unreachable |
| Story | 6/10 | E1 "Air" quest chain well-defined in `data/quests.json` |
| Content Volume | 5/10 | 119 scripts, 40 scenes, 11 data files — but many broken refs |
| Polish | 3/10 | Missing translations, broken audio |
| Performance | N/A | Can't evaluate if it can't boot |

### Work Done
- Created Kanban task `t_d8bbcc6d`: "P0: Fix boot-blocking autoload errors"
- Dispatched sub-agent to fix:
  1. `audio.gd` line 46: `PROCESS_MODE = Node.PROCESS_MODE.ALWAYS` → `process_mode = Node.PROCESS_MODE_ALWAYS`
  2. `save_manager.gd` line 743: Register `GameClock` autoload (file exists at `scripts/game_clock.gd`)
  3. Remove 10 broken autoload entries for non-existent scripts (scrubber_system, planet_system, ui_manager, i18n, achievements, colorblind_filter, input_remap, aim_assist, puzzle_hint_system, auto_retry)
  4. Create `translations/` directory with 3 minimal CSV files (ui.csv, dialogue.csv, quests.csv)

### Dimension Improved
- **Architecture**: 0 → target 5/10 (game boots, autoloads load cleanly)

### Next Steps
- Verify tests pass after boot fix
- Address largest files (gate_room.gd at 4786 lines — architecture score still low)
- Create follow-up tasks for accessibility systems that were removed as broken autoloads
---

## 2026-07-12 (Session 2) — Fix broken tests: EpisodeWrap autoload + refresh_gate_state crash

### Context
- Ran `tests/run.sh scene` and `tests/run.sh flow` — both FAIL
- Ran `tests/run.sh quest` and `tests/run.sh questlog` — both PASS
- Identified two surgical bugs causing the failures

### Work Done
1. **Bug 1 — EpisodeWrap autoload missing**: The test `e1_flow.gd` expects `EpisodeWrap` to be a registered autoload. The script `episode_wrap.gd` exists and is designed as an autoload (its header says "Autoload. Listens for GameState.episode_completed..."), but it was missing from the `[autoload]` section of `project.godot`. Added `EpisodeWrap="*res://scripts/episode_wrap.gd"` to the autoload section.

2. **Bug 2 — refresh_gate_state called on wrong object**: `gate_room_npcs.gd` line 115 called `host.refresh_gate_state()` where `host` is `gate_room.gd` (a Node3D that doesn't have that function). The function lives on `gate_room_interactables.gd` line 335, accessible via `host.interactables`. The runtime SCRIPT ERROR aborted the rest of `assemble_away_team_at_gate()` — specifically the NPC-hiding code (lines 121-126) — causing the "double-Park" and "double-Scott" test failures. Fixed by changing to `host.interactables.refresh_gate_state()`.

### Scores (post-fix)
| Dimension | Score | Notes |
|---|---|---|
| Architecture | 5/10 | 23 autoloads, largest file 2670 lines (room.gd) |
| Code Quality | 8/10 | Tests now PASS (scene_boot, e1_flow, quest_waypoint, questlog) |
| Gameplay Depth | 5/10 | E1 quest chain playable, E2+ mostly todo |
| Story | 4/10 | E1 Air complete, E2-E3 partial, E4+ todo |
| Content Volume | 6/10 | 50+ scripts, multiple scenes, NPCs, data files |
| Polish | 5/10 | Cinematics, HUD, audio, shaders present |
| Performance | 6/10 | Optimization tasks done, Area3D scanning optimized |

### Dimension Improved
- **Code Quality**: 3 → 8 (all test suites now pass)

### Kanban
- Completed: t_3ba0e2a5 (P0: Fix broken autoloads)
- Created: t_15ba81a2 (P1: Add CO2 scrubber crisis multi-stage mechanical depth)

### Next Steps
- Add multi-stage CO2 scrubber crisis (gameplay depth)
- Continue E1 Icarus Base evacuation tutorial (story completeness)
- Refactor room.gd (2670 lines) into modules (architecture)
