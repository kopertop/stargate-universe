# Validate a volumetric VFX from an orthogonal camera, not just the hero angle

**Symptom.** The kawoosh looked fine head-on but, viewed from above, read as a widening funnel
("toilet bowl") because it was a straight cone with the wide mouth toward the camera.

**Lesson.** Any effect that has depth (plumes, beams, shockwaves) must be checked from a side or
top view. A debug view cycle (`V`: follow → top-down → orbit) plus a replay key (`R` redial) made
this a 10-second loop instead of guesswork.

**Fix shape.** A lathed bulb: widest at the gate plane, tapering to a rounded tip ~4.5 m out, with
helical streak shader and a scale-Z erupt/hang/retract envelope.

**Gotcha.** A top-down camera above the ceiling sees the ceiling. Hide the ceiling mesh in that
view and sit the camera just under it.
