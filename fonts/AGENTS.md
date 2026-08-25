# fonts/

Bundled fonts. Currently a single TTF — Godot's default fonts cover most UI;
custom font is reserved for hero headings.

## Contents

- `lilita_one_regular.ttf` — Display font, used for "STARGATE UNIVERSE"
  title and other hero typography.
- `license.txt` — Open Font License attribution. Keep with the .ttf.
- `ancient_anquietas.ttf` — "Ancient"/Lantean glyph font (Anquietas, by
  Joseph Spicer). Maps Latin A-Z/a-z/0-9 1:1 onto Stargate Ancient glyphs,
  so plain English rendered in it reads as a consistent substitution cipher.
  Used for the "decipher-on-entry" room feature (encrypted room names,
  door plaques, Kino-map labels, diegetic console text) until the player
  physically enters a room. Applied via `scripts/ancient_text.gd`.
- `ancient_anquietas_LICENSE.txt` — provenance + license caveat. Fan font,
  personal/non-commercial use only — NOT cleared for a commercial release.

## Conventions

- New fonts ship as TTF or OTF with their license file alongside.
- Prefer referencing fonts through Godot theme resources / `LabelSettings`
  so the editor preview stays accurate. Exception: `ancient_anquietas.ttf`
  is applied procedurally at runtime (to code-built `Label3D`/`TextMesh`
  nodes and `canvas.draw_string` on the Kino map — none of them editor
  scenes), so `ancient_text.gd` `load()`s it once and falls back to the
  scramble effect if the file is missing.
- Heading copy uses lilita_one_regular; body copy uses Godot's default
  (Open Sans) at 14-22 px depending on context.

## Cross-references

- Project rules: `../CLAUDE.md`
- UI consumers: `../objects/hud.tscn` (`LabelSettings_*` sub-resources),
  `../scenes/title.tscn`
