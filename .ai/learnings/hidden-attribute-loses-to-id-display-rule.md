# `el.hidden = true` does nothing when your own CSS sets `display` on that element

**Context:** The hotwire mini-game overlay (`web/gate-room/src/hotwire.js`) styled itself with
`#hotwire{display:grid;…}` and closed itself with `el.hidden = true`. The panel stayed on screen after "PROTOCOL
MATCHED" while `isOpen()` (which reads `el.hidden`) said it was closed — the game unpaused underneath a stuck overlay.

**Lesson:** The user-agent rule `[hidden]{display:none}` has attribute-selector specificity (0,1,0) and loses to any
author rule with an id or class selector that sets `display`. Whenever a component sets `display` on its root, add an
explicit `#root[hidden]{display:none}` (or toggle a class instead of the attribute). The artifact/HTML harness reset does
this with `[hidden]{display:none!important}`; plain pages do not.

**Applies to:** every overlay/panel toggled with `.hidden` in this codebase (ui.js uses a `.hidden` class + `!important`,
which is why the Kino Remote never had this problem).
