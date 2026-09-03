# Verifying a Three.js page in the Claude desktop in-app browser pane

Field notes from driving `web/gate-room/` through the pane:

- `canvas.requestPointerLock()` rejects with `SecurityError` inside the pane. Harmless in a real
  tab; wrap in `?.catch?.(() => {})` and drive camera yaw through a `window.__dbg` handle instead.
- `read_console_messages` is cumulative across `navigate` reloads in the same tab. Compare counts,
  not presence, or an old error looks like a regression.
- `computer.zoom` with a `region` is not supported; you get a full screenshot.
- Consecutive `screenshot` actions in one `browser_batch` land ~0.3 s apart. Time the preceding
  `wait` to the effect start to catch a ~1 s VFX.
- Timing a walk by `wait` seconds is fragile. Poll inside `javascript_tool` instead:
  `while (!dbg.travel()) await new Promise(r => setTimeout(r, 30));` then clear keys.
- Simulate held keys by mutating the exposed input `keys` Set; simulate edge-triggered keys with
  `window.dispatchEvent(new KeyboardEvent('keydown', { code }))`.
- Expose a `window.__dbg` object (input, player, camera, world, setView) from the entry module. It
  is the difference between verifying and guessing.
