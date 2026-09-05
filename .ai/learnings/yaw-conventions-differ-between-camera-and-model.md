# Two yaw conventions live in this codebase; label which one a function takes

**Symptom.** The Kino drone launched "toward the gate" flew the opposite way for nine seconds.

**Cause.** The follow camera and the drone use `forward = (-sin yaw, 0, -cos yaw)` (yaw 0 → −Z). The
character model uses `rotation.y` with +Z as forward (yaw π → faces −Z). Passing the player's
`Math.PI` into the drone's camera-convention yaw pointed it at +Z.

**Rule.** Name parameters `camYaw` vs `modelYaw`, and when spawning something that must "face the
gate", derive the heading from the gate position, not from a constant copied from the other system.
