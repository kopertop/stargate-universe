---
name: add-character
description: >-
  Create a new game character via Mint MCP (mint-native pipeline). Generates a
  riggable humanoid, applies animation sets, downloads GLB into models/mint/,
  registers it in data/mint/characters.json, and validates in Mint Character Lab.
  Use when adding crew/NPCs, minting a new character, or when the user mentions
  Mint characters / add-character. Do NOT use Quaternius or ModularCharacter.
---

# Add Character (Mint-native)

All new characters go through **Mint MCP** (`user-mint`). Quaternius /
`ModularCharacter` / Kenney mini-chars are legacy — do not extend them.

## Prerequisites

1. Mint MCP connected: `.cursor/mcp.json` (or `~/.cursor/mcp.json`) has
   `"mint": { "url": "https://mcp.mint.gg/mcp" }`.
2. Authenticated (`mcp_auth` on `user-mint` if `needsAuth`).
3. Credits available (`get_credits_balance` / `get_mint_context`).

## Workflow

### 1. Slug + brief

Ask for (or infer):
- **slug** — `snake_case` id (`eli`, `scott`, `wray`)
- **display_name** — `"Eli Wallace"`
- **look** — hair, build, outfit, era/show likeness notes
- **animation_sets** — start with `basic_locomotion`; add combat/social later

### 2. Generate riggable model

```
CallMcpTool user-mint / start_model_generation
  prompt: game-ready stylized humanoid … empty hands …
  display_name_hint: <Display Name>
  mode: auto
  riggable_character: { pose: t_pose, hands: empty }
```

Show the user the returned **chatUrl** (Open in Mint). Keep `assetId`.

### 3. Wait + download mesh

```
wait_for_status { asset_type: model, asset_id, until_stage: final }
get_asset_artifact_manifest { asset_type: model, asset_id }
```

Download the `canonical_model` / `original_glb` into:

```
models/mint/<slug>/<slug>.glb
models/mint/<slug>/<slug>_preview.webp   # optional
models/mint/<slug>/mint.json             # provenance (ids + chat url)
```

### 4. Animate

```
list_model_animation_sets   # confirm set ids
animate_generated_model {
  model_id,
  animation_set_id: "basic_locomotion",
  height_meters: ~1.7
}
wait_for_model_animation { target_type: model_animation_batch, target_id: batchId }
get_model_animation_artifact_manifest { target_type: model_animation_batch, target_id }
```

Download the **rigged_character** (or combined animated GLB) to:

```
models/mint/<slug>/<slug>_animated.glb
```

Prefer the animated GLB that includes clips for the lab. If Mint returns
per-clip GLBs, keep them under `models/mint/<slug>/clips/` and point the
registry at the rigged body + note clip paths in `mint.json`.

### 5. Register

Update `data/mint/characters.json`:

```json
"<slug>": {
  "display_name": "<Display Name>",
  "mint_model_id": "<assetId>",
  "mint_chat_url": "https://mint.gg/chat/...",
  "glb": "res://models/mint/<slug>/<slug>.glb",
  "animated_glb": "res://models/mint/<slug>/<slug>_animated.glb",
  "scale": 1.0,
  "animation_sets": ["basic_locomotion"],
  "status": "ready"
}
```

### 6. Validate in lab

1. Open `scenes/mint_character_lab.tscn` (F6) — or:
   `Godot --path . res://scenes/mint_character_lab.tscn`
2. Confirm the character appears, clips populate, Idle/Walk/Run play.
3. Godot may need one editor import pass for new `.glb` files before headless
   loads succeed (`.import` sidecars).

### 7. Runtime API

```gdscript
const MintCharacterRef = preload("res://scripts/mint_character.gd")
var eli := MintCharacterRef.load_profile("eli")
add_child(eli)
eli.play("Idle")
```

## Prompt tips (SGU)

- Empty hands (`hands: empty`) — required for Mint rigging.
- T-pose default for animation-ready humans.
- Name likeness + wardrobe (e.g. “Eli Wallace… red t-shirt, jeans”).
- Avoid held props; add gear later as separate Mint models / BoneAttachments.

## Do not

- Add Quaternius parts / `CharacterFactory.PROFILES` for new characters.
- Commit Mint CDN URLs as runtime loaders — always download into `models/mint/`.
- Skip the lab validation step.

## Related

- Lab: `scenes/mint_character_lab.tscn` · `scripts/mint_character_lab.gd`
- Runtime: `scripts/mint_character.gd`
- Registry: `data/mint/characters.json`
- Mint docs: https://mcp.mint.gg/ · https://docs.mint.gg/integrations/mcp
