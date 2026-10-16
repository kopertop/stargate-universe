# Directory Structure

```text
/
├── AGENTS.md                   # Master configuration
├── .claude/                     # Agent definitions, skills, hooks, rules, docs
├── src/                         # Game source code (25 ES modules loaded via import maps)
├── tests/                       # Unit tests (27 files, Node 18+ test runner, 943 tests)
├── data/                        # Game data (chapters.json, ship_layout.json, room_connections.json, etc.)
├── docs/                        # Technical documentation (tech-debt register, deployment targets, learnings)
├── tools/                       # Build and pipeline tools (vendor.py, tts-bake/, zip.py)
├── sounds/                      # Audio assets (SFX, music loops, dialogue)
├── design/                      # Game design documents
├── assets/                      # Game art assets (3D models, textures)
├── production/                  # Production management (sprints, milestones, releases)
│   ├── session-state/           # Ephemeral session state (active.md — gitignored)
│   └── session-logs/            # Session audit trail (gitignored)
└── build.sh                     # Build script (vendors Three.js, produces dist/ + itch.io zip)
```
