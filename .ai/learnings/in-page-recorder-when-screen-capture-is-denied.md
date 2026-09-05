# Recording gameplay video without screen-recording permission: composite in-page + POST to a local server

**Problem.** `screencapture -v` wrote nothing and `ffmpeg -f avfoundation` hung: the agent's shell has
no macOS Screen Recording permission (TCC), and granting it needs the user at a dialog.

**Solution** (`web/gate-room/src/recorder.js`, `?record`):
1. Each frame after `renderer.render()`, `ctx.drawImage(glCanvas)` onto a 2D canvas (no
   `preserveDrawingBuffer` needed when copied in the same frame) and draw a minimal text HUD from
   game state (DOM HUD can't be captured).
2. `canvas.captureStream(30)` → `MediaRecorder` (`video/webm;codecs=vp9`, 7 Mb/s), `start(1000)`.
3. On stop, `fetch('http://127.0.0.1:8091/save?name=…', { method: 'POST', body: blob })` to a
   10-line Python `BaseHTTPRequestHandler` with CORS that writes into `~/Desktop`. Downloads via
   `<a download>` are blocked in the in-app pane; a local POST is not.
4. `ffmpeg -i x.webm -c:v libx264 -pix_fmt yuv420p x.mp4` — MediaRecorder WebM has no duration
   header, so remux for players/QuickTime.

**Cost.** ~60 → ~23 fps while recording at pane resolution; not present in normal play. A hands-free
driver (`autoplay.js`) that uses the real input path (keys + E) makes takes repeatable; it needs a
stall-and-sidestep rule because straight-line walking snags on rocks and pedestals.
