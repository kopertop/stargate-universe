# A synthetic input driver must re-assert held keys every tick

**Context:** `web/gate-room` autoplay stalled mid-walk during a recorded run: the player stood still with `input.keys`
empty while the driver believed `KeyW` was held. `input.js` clears every key on window `blur` (so a real player never
runs into a wall after alt-tabbing), and taking a screenshot of the in-app pane blurs the page.

**Lesson:** Anything that simulates held input (autoplay, soak tests, replay) must add its keys on every poll of its
loop, not once at the start — the real input layer is entitled to drop them. Same for hold-to-interact: loop
`add(key); await frame` until the condition holds.

**Applies to:** `src/autoplay.js` walkTo/holdE; any future gamepad-emulation or replay harness.
