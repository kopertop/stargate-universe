# A skinned glTF stuck in T-pose means the AnimationMixer is not being updated

**Symptom.** Character stood in bind pose during the gate-dialing intro even though idle actions were
playing with weight 1.

**Cause.** Player control was gated off during the intro, and the mixer update lived inside the
player's control update. No `mixer.update(dt)` → skeleton stays at bind pose.

**Fix.** Always tick the mixer. Feed the controller a zero-input frame (`{ move: {x:0,y:0}, run:false }`)
when control is disabled instead of skipping its update. Bonus: the idle/fidget blend then runs too.
