---
name: Always use Crashcat physics
description: Never use or suggest Rapier physics — always use ggez's built-in Crashcat physics engine
type: feedback
---

Always use Crashcat physics (`@ggez/runtime-physics-crashcat`), never Rapier.

**Why:** User explicitly stated DO NOT use Rapier. Crashcat is ggez's built-in physics and the preferred choice for all ggez projects.

**How to apply:** When writing physics code, scene setup, or ADRs, always reference Crashcat. Do not suggest "upgrade to Rapier" as a future option. Remove any existing mentions of Rapier as an upgrade path.
