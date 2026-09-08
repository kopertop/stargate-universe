# Footsteps and stride come from the animation's foot plants, not from distance counters

**Symptom:** "footsteps don't line up with the feet" — sounds fired every N metres while the walk clip ran at a speed-scaled
timeScale, so feet slid and sounds drifted.

**What the clips actually are:** the Quaternius UAL loops are in-place (root.position track is flat). Each loop is authored
for one ground speed: during stance the planted foot moves backward relative to the root at exactly that speed. Measured
by sampling foot bone world positions over the loop and taking the median foot velocity while the foot is at its lowest:
Walk_Loop ≈ 0.9 m/s, Walk_Carry_Loop ≈ 0.6, Jog_Fwd_Loop ≈ 5.0, Sprint_Loop unmeasurable at 60 Hz (stance < 1 frame).

**Fix (player.js):**
- `timeScale = speed / CLIP_SPEED[gait]` so the planted foot stays put; pick the gait by speed (walk < ~2 m/s, jog to ~7,
  sprint above). The game's 4.2 m/s "walk" is physically a jog and now uses the jog loop at ~0.85× — feet no longer slide.
- Fire `onStep(side)` when a foot bone that swung above 0.2 m drops below 0.14 m above the root. main.js hangs sound and
  sand dust on it. No distance counter.

**Proof method (reusable):** walk straight for ~3 s, sample `foot.getWorldPosition` each frame, find local minima of foot
height, and read the foot's world velocity there: ≈0 means no slide; ratio foot/root velocity gives the correction factor
`authored = assumed × (1 − ratio)`. Jog went from tens of centimetres of slide per stance to ~1.4 cm.

**Caveat:** a stance shorter than one frame (fast sprints) can't be measured this way; estimate from stride instead or
sample the clip offline at a higher rate.
