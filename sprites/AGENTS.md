# sprites/

2D images: UI panels, portraits, particles, skybox panorama.

## Contents

- `portraits/` — Character portrait PNGs used by the dialog UI.
- `ui/` — HUD + menu artwork (dialog panel ninepatch, nameplate, etc.).
- `blob_shadow.png` — Soft circular shadow blob used under dynamic actors.
- `coin.png`, `particle.png` — Kenney starter-kit (largely unused on this
  branch).
- `skybox.png` — Equirectangular skybox source for the gate room and
  planet scenes.

## Conventions

- PNGs need a `.import` sidecar. If you drop a PNG into `sprites/` while
  the editor is closed, generate the sidecar before headless code tries to
  `load()` it. See memory `[[godot-png-no-import-sidecar]]`.
- NinePatch UI panels: keep their `patch_margin_*` settings in the `.tscn`
  that uses them so multiple consumers don't drift.
- Avoid putting concept art in here — that lives in
  `../design/concept-art/`. Runtime art only.

## Cross-references

- Project rules: `../CLAUDE.md`
- Dialog UI: `../objects/dialog_screen.tscn`, `../objects/hud.tscn`
- Concept art (reference, not runtime): `../design/concept-art/AGENTS.md`
