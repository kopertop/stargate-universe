# Agent Roster

The following agents are available. Each has a dedicated definition file in
`.claude/agents/`. Use the agent best suited to the task at hand. When a task
spans multiple domains, the coordinating agent (usually `producer` or the
domain lead) should delegate to specialists.

## Tier 1 -- Leadership Agents (Opus)
| Agent | Domain | When to Use |
|-------|--------|-------------|
| `creative-director` | High-level vision | Major creative decisions, pillar conflicts, tone/direction |
| `technical-director` | Technical vision | Architecture decisions, tech stack choices, performance strategy |
| `producer` | Production management | Sprint planning, milestone tracking, risk management, coordination |

## Tier 2 -- Department Lead Agents (Sonnet)
| Agent | Domain | When to Use |
|-------|--------|-------------|
| `game-designer` | Game design | Mechanics, systems, progression, economy, balancing |
| `lead-programmer` | Code architecture | System design, code review, API design, refactoring |
| `art-director` | Visual direction | Style guides, art bible, asset standards, UI/UX direction |
| `audio-director` | Audio direction | Music direction, sound palette, audio implementation strategy |
| `narrative-director` | Story and writing | Story arcs, world-building, character design, dialogue strategy |
| `qa-lead` | Quality assurance | Test strategy, bug triage, release readiness, regression planning |
| `release-manager` | Release pipeline | Build management, versioning, changelogs, deployment, rollbacks |
| `localization-lead` | Internationalization | String externalization, translation pipeline, locale testing |

## Tier 3 -- Specialist Agents (Sonnet or Haiku)
| Agent | Domain | Model | When to Use |
|-------|--------|-------|-------------|
| `systems-designer` | Systems design | Sonnet | Specific mechanic implementation, formula design, loops |
| `level-designer` | Level design | Sonnet | Level layouts, pacing, encounter design, flow |
| `economy-designer` | Economy/balance | Sonnet | Resource economies, loot tables, progression curves |
| `gameplay-programmer` | Gameplay code | Sonnet | Feature implementation, gameplay systems code |
| `engine-programmer` | Engine systems | Sonnet | Core engine, rendering, physics, memory management |
| `ai-programmer` | AI systems | Sonnet | Behavior trees, pathfinding, NPC logic, state machines |
| `network-programmer` | Networking | Sonnet | Netcode, replication, lag compensation, matchmaking |
| `tools-programmer` | Dev tools | Sonnet | Editor extensions, pipeline tools, debug utilities |
| `ui-programmer` | UI implementation | Sonnet | UI framework, screens, widgets, data binding |
| `technical-artist` | Tech art | Sonnet | Shaders, VFX, optimization, art pipeline tools |
| `sound-designer` | Sound design | Haiku | SFX design docs, audio event lists, mixing notes |
| `writer` | Dialogue/lore | Sonnet | Dialogue writing, lore entries, item descriptions |
| `world-builder` | World/lore design | Sonnet | World rules, faction design, history, geography |
| `qa-tester` | Test execution | Haiku | Writing test cases, bug reports, test checklists |
| `performance-analyst` | Performance | Sonnet | Profiling, optimization recs, memory analysis |
| `devops-engineer` | Build/deploy | Haiku | CI/CD, build scripts, version control workflow |
| `analytics-engineer` | Telemetry | Sonnet | Event tracking, dashboards, A/B test design |
| `ux-designer` | UX flows | Sonnet | User flows, wireframes, accessibility, input handling |
| `prototyper` | Rapid prototyping | Sonnet | Throwaway prototypes, mechanic testing, feasibility validation |
| `security-engineer` | Security | Sonnet | Anti-cheat, exploit prevention, save encryption, network security |
| `accessibility-specialist` | Accessibility | Haiku | WCAG compliance, colorblind modes, remapping, text scaling |
| `live-ops-designer` | Live operations | Sonnet | Seasons, events, battle passes, retention, live economy |
| `community-manager` | Community | Haiku | Patch notes, player feedback, crisis comms, community health |

## Engine Specialists

⚠️ This repo is web-era only: the 2026-09-08 re-pivot replaced the Godot stack
with vanilla Three.js (see `.claude/docs/technical-preferences.md`). No
Unity/Unreal specialist agents exist in `.claude/agents/` — those were
removed with the engine. For engine questions, use the general specialist
above (`engine-programmer`, `technical-artist`, `performance-analyst`) backed by
the technical-preferences doc.
