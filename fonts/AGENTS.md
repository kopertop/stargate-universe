# fonts/

Bundled fonts. Currently a single TTF — Godot's default fonts cover most UI;
custom font is reserved for hero headings.

## Contents

- `lilita_one_regular.ttf` — Display font, used for "STARGATE UNIVERSE"
  title and other hero typography.
- `license.txt` — Open Font License attribution. Keep with the .ttf.

## Conventions

- New fonts ship as TTF or OTF with their license file alongside.
- Don't load fonts via `load()` in scripts; reference them through Godot
  theme resources / `LabelSettings` so the editor preview stays accurate.
- Heading copy uses lilita_one_regular; body copy uses Godot's default
  (Open Sans) at 14-22 px depending on context.

## Cross-references

- Project rules: `../CLAUDE.md`
- UI consumers: `../objects/hud.tscn` (`LabelSettings_*` sub-resources),
  `../scenes/title.tscn`
