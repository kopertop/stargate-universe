# Packaging the Three.js prototype for itch.io (HTML5 zip)

**Shape.** `web/gate-room/build.sh` → `dist/sgu-destiny-html5.zip` with `index.html` at the zip root, sources,
`data/`, `vendor/three/`, and `assets/` (Quaternius rig + clips, gate sounds, items.json). itch runs HTML
games in an iframe from its own CDN, so everything must be relative and bundled — no jsdelivr import map.

**Gotchas.**
- `three@0.180` split its module build: `build/three.module.js` re-exports `./three.core.js`. Vendoring only
  the module file gives a 404 on `three.core.js` and nothing renders. Fetch both.
- Addons import each other relatively (`GLTFLoader` → `../utils/BufferGeometryUtils.js`). Walk the import
  graph from the `three/addons/…` specifiers in `src/` instead of hand-listing files.
- Asset URLs in code go through one indirection (`assets.js`: `window.__ASSET_ROOT ?? '../../'`); the built
  `index.html` sets `./assets/`. Dev keeps loading from the repo, the package from its own folder.
- Verify the package the same way as dev: serve `dist/` on its own port (`gate-room-dist` in launch.json),
  read the network log for any `jsdelivr`/404, then run `?autoplay` end to end.

**Save/load trap.** `startChapter()` fires the step hook, which persisted a fresh state over the real save
during boot. Gate saves on a `gameStarted` flag that only New Game / Continue set.
