---
name: make-trailer
description: "Generate a branded gameplay-trailer MP4 from ACTUAL scripted gameplay. Records a reel (Godot Movie Maker) with in-engine captions + title/end cards, mixes an optional music bed via ffmpeg, and writes a draft social post. Use when asked to make a trailer, gameplay video, or social clip for the game."
argument-hint: "[e1_highlight | e1_full] — reel to record (default: config)"
user-invocable: true
allowed-tools: Read, Edit, Bash
---

# Make Gameplay Trailer

Produces a shareable 16:9 gameplay trailer from real, scripted gameplay — no
mockups. The whole pipeline is the single script `tools/make_trailer.sh`:

1. **Record** — `res://tools/trailer/trailer.tscn` drives a curated reel through
   the real SceneRouter/Interactable pipeline while Godot's built-in Movie Maker
   (`--write-movie`) captures it deterministically. All trailer text (captions,
   title card, end card) is rendered IN-ENGINE and baked into the footage, plus a
   caption beat sidecar JSON for the post text.
2. **Post-process** — ffmpeg normalizes the capture and mixes an optional music
   bed under the game audio. (No ffmpeg text filters — `drawtext` is missing from
   many builds, so captions/cards are in-engine.)
3. **Emit** — `out/trailer_<reel>_16x9.mp4` + `out/post_text.txt` (draft caption).

## Reels
- `e1_highlight` (default) — curated ~40s: dialed Stargate → step-through →
  alien world → mining → return home.
- `e1_full` — the whole E1 spine, filmed end to end.

## How to run

Requires `ffmpeg`, `ffprobe`, `jq`, and Godot (`GODOT_BIN` or on PATH). Movie
Maker needs a GPU context, so this is **local-only** — never in CI.

```bash
tools/make_trailer.sh                       # uses tools/trailer/trailer.config.json
```

To switch reel or branding, edit `tools/trailer/trailer.config.json`
(`reel`, `music`, `game_name`, `tagline`, `end_card_cta`, `hashtags`). To record
a different reel without editing the file, the user can set `TRAILER_REEL` — but
prefer updating the config so output is reproducible.

When invoked: read the config, run `tools/make_trailer.sh`, then report the
output video path, the draft post text, and the recorded duration. A game window
opens during recording and closes itself — tell the user not to close it.
