# Record gameplay as fixed-step frames piped to ffmpeg, not MediaRecorder

**Context:** `web/gate-room` proof videos via `canvas.captureStream()` + `MediaRecorder` were choppy whenever the
window was occluded or the machine was busy: MediaRecorder timestamps frames by wall clock, so a starved render loop
produces a video with real gaps and a slowed, stuttering picture — even though the simulation itself was fine.

**Lesson:** Decouple the video clock from the wall clock. While recording, the game loop advances exactly `1/fps` of
simulation per rendered frame (never faster than real time, as slow as it needs to be), composes the frame, encodes a
JPEG, and POSTs it to the dev server, which pipes frames in order into `ffmpeg -f image2pipe -framerate fps`. The mp4
is perfectly smooth because ffmpeg assigns timestamps by frame count. Anything that waits on time during a recording
(the autoplay driver) must use the simulated clock (`__dbg.simTime()`), not `performance.now()`, or its timeouts fire
early when the sim lags.

**Applies to:** any browser game proof/trailer recording; headless CI capture; recording in a background tab.
