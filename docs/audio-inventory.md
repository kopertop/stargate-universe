# Audio Inventory — What's on R2 vs What the Catalog Promises

Generated 2026-04-13 after playtesting the opening cinematic. The sound
catalog at `src/systems/audio/sound-catalog.ts` declares many voice
lines that don't exist on R2 yet — playing them fails silently (404 →
`EncodingError: Unable to decode audio data`) and can poison the
AudioContext for subsequent plays.

## ✅ Verified on R2 (bucket `sgu-assets`, `pub-c642ba55d4f641de916d72786545c520.r2.dev`)

### SFX — `/audio/sfx/`
- `chevron-lock.mp3` ✅
- `stargate-kawoosh.mp3` ✅
- `wormhole-transit.mp3` (used in cinematic) — status unverified but plays
- `energy-burst.mp3` (used) — status unverified but plays
- `debris-impact.mp3` (used) — status unverified but plays
- `low-rumble.mp3` (used) — status unverified but plays
- `power-down.mp3` (used) — status unverified but plays

### Music — `/audio/music/`
- `sgu-theme-song.mp3` ✅ — **~45 seconds** (920 KB). Too short for the
  full 60-second opening on its own; we force `loop: true` on playback.
- `sgu-soundtrack.mp3` ✅ (main-menu bed)

### Voice — `/audio/voice/`
- `eli-discovery-01.mp3` ✅
- `eli-danger-01.mp3` ✅
- `rush-discovery-01.mp3` ✅
- `rush-warning-01.mp3` ✅
- `rush-timer-01.mp3` ✅

## ❌ Declared in catalog, MISSING on R2

These all return `404 Not Found` when fetched. Catalog entries exist so
the string IDs don't break the typecheck, but no audio plays. Removing
them entirely would break the types since game code already references
them — **recommended fix: upload the files**, or strip the catalog
entries and fix call sites.

### Scott voice — ALL MISSING
- `scott-move-out.mp3`
- `scott-point.mp3`
- `scott-scout.mp3`
- `scott-clear.mp3`           ← needed for cinematic "It's clear!" beat
- `scott-contact.mp3`
- `scott-cover.mp3`
- `scott-gate-time.mp3`
- `scott-regroup.mp3`
- `scott-fallen.mp3`
- `scott-retreat.mp3`
- `scott-bark-duty.mp3`
- `scott-bark-eli.mp3`        ← needed for cinematic "Eli… Eli…" beat
- `scott-bark-planet-nice.mp3`
- `scott-bark-ready.mp3`
- `bark-scott-casual.mp3`

**Impact:** Scott's cinematic voice lines fall back to subtitle-only.
Upload all 15 Scott `.mp3` files to `/audio/voice/` on R2 to enable them.

### Other voice — status unknown
- All Young, TJ, Greer, Chloe lines — not probed yet. Likely missing
  too since Scott is uniformly absent.

## 🎯 Priority uploads for the opening cinematic

If you can only upload a few files, these two unlock the biggest UX win:
1. `scott-clear.mp3` — plays at ~t=15s when Scott emerges, "It's clear — start the evacuation!"
2. `scott-bark-eli.mp3` — plays at ~t=35s when Scott crouches, "Eli… Eli, can you hear me?"

## Dialog lines (for the Scott opening quest)

The player dialogue tree `src/dialogues/scott-opening.ts` has 5 nodes.
Once we have TTS voice files, they should map to:
- `intro.text` → "Eli… Eli, can you hear me? Come on, man — look at me."
- `scott-explains.text` → long explanatory line ("We don't know…")
- `scott-crew.text` → "Most of us made it…"
- `scott-ancient.text` → "I don't know. I don't know anything yet…"
- `scott-sends-player.text` → "Good. I'll check on the others. Find Rush…"

Generate via ElevenLabs with the "Brian" voice (catalog says that's
Young but Scott should be a younger, energetic military voice — try
"Drew" or "Paul" per the ElevenLabs library).
