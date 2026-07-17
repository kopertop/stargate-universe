# models/mint/

Mint-native character + asset pipeline. **All new characters and (going
forward) game assets are generated via Mint MCP**, downloaded here, and
registered in `../../data/mint/characters.json`.

## Layout

```
models/mint/<slug>/
  <slug>.glb              # original Mint mesh (often unrigged)
  <slug>_animated.glb     # rigged body (may have one placeholder clip)
  <slug>_preview.webp     # Mint preview image
  mint.json               # provenance (model id, chat url, batch id)
  clips/
    Idle.glb              # each file = full rig + ONE animation
    Casual_Walk_inplace.glb
    …
```

## Runtime

- `scripts/mint_character.gd` — loads registry entry, merges clip GLBs into one
  `AnimationPlayer`, exposes `play("Idle")`.
- `scenes/mint_character_lab.tscn` — turntable + clip picker for validation
  (future character editor/menu surface).
- Skill: `.claude/skills/add-character/` — Mint generate → download → register → lab.

## Do not

- Add new Quaternius / Kenney mini-character profiles for crew.
- Runtime-load Mint CDN URLs — always download into this tree.

## Cross-references

- Mint MCP: https://mcp.mint.gg/
- Docs: https://docs.mint.gg/integrations/mcp
- Project rules: `../../CLAUDE.md`
