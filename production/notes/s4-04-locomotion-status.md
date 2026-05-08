# S4-04 — Locomotion blend tree: status

**Status:** player half complete (pre-existing); NPC half N/A this sprint.
**Decision date:** 2026-05-21

## Sprint scope (verbatim)

> Author/import idle, walk, run clips into the existing `@ggez/anim-runtime`
> graph. Drive blend by horizontal speed. Apply to S3-03 NPC and to the local
> player VRM.
> *(production/sprints/sprint-004.md line 45)*

## Player half — already shipped

`src/systems/vrm/vrm-player-animation-controller.ts` (≈580 LOC) implements
the spec and then some:

- AnimationMixer with weight-blended idle / walk / run actions
- Speed-driven blend via `walkSpeed` / `runSpeed` thresholds in
  `updateLocomotionWeights(delta, params, scale)`
- Strafe-left / strafe-right blends via `strafeInput`
- Jump (LoopOnce) layered over locomotion via `JUMP_LOCOMOTION_BLEND = 0.5`
- 12-variant idle cycling (8–20 s intervals)
- Repair / interaction states
- Exponential weight smoothing: `1 - Math.exp(-WEIGHT_SMOOTHING * delta)`
  with `WEIGHT_SMOOTHING = 8.0`

Acceptance criteria already met: visible idle ↔ walk ↔ run transitions, no
T-pose, foot-slide acceptable.

## NPC half — not applicable to S3-03 NPC

S3-03's only shipped NPC is **Lt. Matthew Scott** (`src/npcs/scott-opening.ts`).
He is a *stationary kneeling* opening-cinematic NPC:

- `position` is set at spawn time relative to the player and never moves
- `patrolDwellTime: 0`, no `patrol` waypoints
- `npc-manager` does not move him post-registration

There is no NPC currently traversing space, so a locomotion blend tree on
the NPC side has nothing to drive. Adding a controller now would mean
authoring against a stationary character whose *intended* state is the
kneeling pose — the moment we have a walking NPC the controller would
need re-tuning anyway.

NPC AnimationMixer plumbing is also not yet present in
`vrm-character-instance.ts` / `vrm-character-manager.ts` — NPCs are
A-pose / authored static pose. Wiring a mixer per-NPC is a separate
work item, not a tweak to the existing controller.

## When to revisit

Re-open S4-04's NPC half once any of the following is true:

1. A patrolling NPC ships (any NPC with non-empty `behavior.patrol`).
2. Lt. Scott gets a "stand up and walk" beat in the post-cinematic flow
   (currently he stays kneeling — see
   `~/.claude/projects/.../memory/project_cinematic_remaining_work.md`).
3. The crew-quarters / mess-hall scenes ship with ambient walking crew.

## Implementation pointers (for the future)

- The existing `VrmPlayerAnimationController` is *almost* generic — its
  only player-specific bits are the idle-variant cycle and the input
  param shape. A near-copy with `PlayerAnimationParams` swapped for an
  NPC-driven `{ speed, walkSpeed, runSpeed, isGrounded }` subset is the
  shortest path.
- NPCs need an AnimationMixer per `VrmCharacterInstance`; thread it
  through `vrm-character-manager.ts` alongside the existing pose setup.
- Animation clips: re-use `src/animations/player-locomotion/` bundle —
  already retargeted for VRM via `vrm-animation-retarget.ts`.

## Tracking

Captured in `production/perf-baseline-2026-05-21.md` § "Caveats" — keep
this note linked from the next sprint that introduces a walking NPC.
