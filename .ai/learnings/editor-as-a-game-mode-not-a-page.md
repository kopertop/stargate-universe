# The level editor is a game mode, not a page

**Context:** A standalone `editor.html` duplicated the game's scene setup. The user wanted it reachable from inside the
running game (hidden console → `leveledit`) using the exact same runtime.

**What it took:**
- A tiny dev console (backquote toggles an <input>; commands are a `{name: fn}` map). input.js ignores keydown/keyup
  whose target is an INPUT/SELECT/TEXTAREA, so typing never leaks into movement.
- The editor takes over the frame: main loop early-returns to `edit.update(dt)` → render. Everything else (player,
  quests, interactables, HUD, music mood) simply isn't ticked. No flags sprinkled through gameplay code.
- Rebuild-in-place needs the world to remember its base state: colliders count before the ship was added
  (`colliders.length = baseColliders`), non-ship occludables, the layout data, and the door audio hook to re-attach.
  Anchors are replaced by mutating the shared object (delete keys + assign) so `const A = destiny.anchors` stays valid.
- Interactables captured anchor Vector3s at registration and go stale after a rebuild — so leaving the editor reloads
  the page on the edited layout (`?layout=live`) instead of trying to re-register everything. Cheap and correct.
- Check the game's global CSS before naming classes in an injected panel: `.bar` was the HUD health bar and turned the
  editor's button rows into 14 px black boxes.
