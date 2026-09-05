# If locomotion weights are scaled by (1 − actionWeight), re-normalise when the action ends

**Symptom.** A one-frame T-pose the instant a dig or interact animation finished.

**Cause.** Locomotion weights were multiplied by `(1 − actW)` while an action layer played. When the
action stopped, `actW` dropped to 0 instantly but the locomotion weights lerped back from ~0 over
several frames. With every action weight near zero the mixer shows the bind pose.

**Fix.** On `stopAction()` set `idle = 1` immediately, and every frame with no action active, if the
weights sum to less than 1, add the remainder to idle. Total body weight never dips below 1.
