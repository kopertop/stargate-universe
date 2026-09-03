# A positional sound fired while the listener is in another scene is silent; fire it on arrival

**Symptom.** Arriving on the planet you heard only the wormhole drone, not the gate kawoosh.

**Cause.** The far gate's incoming kawoosh (and its `PositionalAudio`) fired while the camera, which
carries the `AudioListener`, was ~300 m down the wormhole tube in a different scene. Three.js
positional audio uses world matrices regardless of scene membership, so the panner attenuated it to
nothing (`maxDistance` 60).

**Fix.** Keep the *visual* incoming kawoosh in transit, but `playOnce()` the far gate's kawoosh
sample at the frame the camera is placed at the destination. Keep hum + drone running during the
step-out, then fade the hum and play the shutdown sound when the gate closes.

**Test.** Expose `isPlaying` getters via `window.__dbg` and assert the sequence at three checkpoints:
at arrive (kawoosh, hum, drone on), after step-out (shutdown on, hum fading, gate inactive), ~2 s
later (everything off).
