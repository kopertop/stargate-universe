# Next Development Plan

Last updated: 2026-05-24

## Recommendation

Finish a full executable Episode 1 proof before starting Mission 2.

The static graph and `tests/run.sh` show that core systems are healthy: state, procedural room boot, mission interactables, and the first real door transition all pass. The main gap is proof depth. The playthrough runner currently validates gate room -> first corridor -> gate room, but it does not yet walk the complete Episode 1 route, interact with Rush, pick up the Kino, rest in quarters, seal the hull breach, and trigger EpisodeWrap through real scene transitions.

## Next Slice: E1 Full Playthrough Proof

Goal: A headless integration run completes Episode 1 through production codepaths.

Acceptance criteria:

- `scripts/playthrough_runner.gd` reaches `control_interface_room`, interacts with Dr Rush, and verifies `GameState.met_rush`.
- The runner reaches `kino_room`, interacts with `KinoPickup`, and verifies `GameState.kino_acquired`.
- The runner reaches `quarters_room_1`, interacts with `Bed`, and verifies `GameState.quarters_found`.
- The runner reaches `east_corridor`, interacts with `HullSealSwitch`, and verifies one sealed breach.
- The runner verifies `GameState.episode_complete` and EpisodeWrap behavior from the real mission sequence.
- `tests/run.sh` passes with the expanded playthrough.

Suggested implementation order:

1. Add a route helper to `scripts/playthrough_runner.gd` that follows `target_room_id` doors through a list of room ids.
2. Expand the current route to cover the mission path:
	- `gate_room`
	- `stargate_corridor_east_connector`
	- `east_corridor`
	- `north_corridor`
	- `control_approach_north`
	- `control_interface_room`
	- `cr_corridor_2`
	- `kino_room`
	- back through the control/north/elevator route
	- `elevator_room_floor_1`
	- `room_1753576770763`
	- `quarters_room_1`
	- return to `east_corridor`
3. Add duck-typed interactable finders for NPC, bed, Kino pickup, and seal switch using script resource paths rather than class lookup.
4. Keep `SceneRouter.instant_mode = true` for headless speed, but keep the production `Door.interact()` path.
5. Only after the route passes, add optional demo screenshot capture for the full mission path.

## Product Work After Proof

1. Mission readability pass:
	- Objective text should always point to the next reachable destination.
	- Door plaque labels should clarify the route to Rush, Kino storage, quarters, and the breach.
	- Kino map should distinguish discovered, known-but-undiscovered, and objective-critical rooms.

2. Content pass:
	- Add a short Rush conversation branch that explicitly assigns the survival tasks.
	- Add corridor/quarters flavor interactions only after the full proof route is stable.
	- Give hull breach sealing a visible before/after state that is hard to miss in screenshots.

3. Architecture cleanup:
	- Extract `room.gd` mission spawn helpers into small data-driven builders once the full route is covered.
	- Keep `GameState` as the canonical state source, but move mission constants and route ids into a small data file if they keep growing.
	- Add a generated dependency index once the manual graph has proven useful.

4. Mission 2 kickoff:
	- Start only after E1 full playthrough proof passes.
	- Scope should be: gate dial-out -> lime planet arrival -> CO2 scrubber repair setup.
	- Reuse the same pattern: data route, scene boot coverage, state smoke coverage, then real playthrough coverage.

## Director Decision Point

Default path: prioritize E1 full playthrough proof.

Alternative A: prioritize visible polish first. This makes the game feel better sooner, but leaves the main mission path under-tested.

Alternative B: start Mission 2 immediately. This moves content forward, but compounds route and state risk before the Episode 1 foundation is fully proven.

The recommended default is E1 proof because it turns the current codebase from "systems pass in isolation" into "the first mission is demonstrably playable end to end."
