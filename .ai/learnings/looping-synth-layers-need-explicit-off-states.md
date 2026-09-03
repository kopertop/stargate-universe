# Looping synthesized audio layers need an explicit target-volume state machine

**Symptom.** A low hum persisted on the desert planet with the gate off. Later, restoring the earlier
sound the user liked turned out to mean the "bug" layer was part of the gate-active texture.

**Cause.** The ring-spin rumble was a looping noise buffer whose volume was ramped up during dialing
and set to 0 at the last chevron, but the ramp kept running through the kawoosh and nothing ever
stopped it.

**Fix.** Drive each looping layer from a per-frame *target volume* derived from state
(`active → 0.7`, `dialing → ramp`, otherwise `0`), lerp toward it, and `play()`/`stop()` when it
crosses ~0.01. Expose `isPlaying` getters on `window.__dbg` and assert them at each state in the
browser test (dialing / active / off-world).
