# A hidden or occluded window stops requestAnimationFrame — sub-step on a timer

**Symptom:** the hands-free playthrough stalled on "arrive" and the arrival timer advanced 0.06 s per real second. The in-app
Browser pane reported "displayed", but `document.hidden` was true: the desktop window was occluded/minimised, and Chrome
stops rAF for occluded windows (macOS occlusion tracking), then throttles timers to a few Hz.

**Fix (main.js):** drive the loop with rAF when visible and `setTimeout(33)` when hidden; on `visibilitychange` cancel a
pending rAF (it would never fire) and reschedule. When the measured real delta exceeds 80 ms, run up to 8 sub-steps of
≤50 ms so quests, doors and the autoplay driver keep wall-clock time even at 3 timer ticks per second.

**Also:** `dt` clamped at 50 ms hides frame starvation from the fps counter (frames/Σdt stays ~20). Check
`renderer.info.render.frame` over real time, or `document.visibilityState`, before blaming the code for "slow".

**Consequence for proof recordings:** MediaRecorder on a canvas in an occluded window captures whatever frames get painted;
the run completes and the log/report is valid, but video smoothness depends on the window being visible.
