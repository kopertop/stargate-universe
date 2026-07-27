# models/mint/

Weapon / tool **prop** meshes from Mint (Destiny Character Props pack).
Character hosts live under `models/mixamo_openbot/` via Mixamo — do not
reintroduce `models/mint/<slug>/` character trees without updating
`data/mint/characters.json` and the Mixamo-first player path.

## Layout

```
models/mint/props/
  sidearm.glb / rifle.glb / repair_tool.glb / stun_baton.glb / kino.glb
  mint.json               # pack provenance
```

## Runtime

- `data/mint/weapons.json` — weapon/tool defs (mesh paths, grip, clips).
- `scripts/mint_held_weapon.gd` — holster↔hand mount helper (still usable
  for Mixamo bone attachments once the wield layer wires it).
- Play path: `scripts/mixamo_combat_avatar.gd` + `scripts/mixamo_host_catalog.gd`.

## Do not

- Commit Mixamo ToS character packs (`models/mixamo_openbot/*` gitignored hosts).
- Point `player.use_mint_avatar` at missing character GLBs — default is `false`.
