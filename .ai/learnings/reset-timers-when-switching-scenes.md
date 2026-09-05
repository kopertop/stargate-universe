# Timers that outlive a scene switch cause "it worked once" bugs

**Symptom.** The destination gate shut down the instant control resumed after arrival, so walking
back into it did nothing.

**Cause.** A "far gate auto-shutdown after 12 s" timer started counting while still on Destiny (the
gate there was active too). Arriving on the planet inherited an already-expired timer.

**Fix.** Reset per-world timers inside the single `enterWorld()` function, and scope the condition to
the world it applies to (`world !== destiny && world.gate.active`). Any state keyed to "current
location" must be zeroed in the one place location changes.
