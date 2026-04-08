---
name: sound-fetch
description: "Search CC0 sound sources (soundcn.xyz primary), download game sounds, upload to R2, and wire audio triggers into the game."
argument-hint: "[sound description or soundcn package name, e.g. 'repair sparks', '@soundcn/impact-metal-000']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion, WebFetch, Agent
---

# Sound Fetch Skill

Search CC0 sound sources for game audio, download, upload to R2, and wire into the game.

## Primary Source: soundcn.xyz

**soundcn** is a CC0 sound library with an npx CLI (similar to shadcn for UI components).

### Direct Install (preferred when you know the package name)

```bash
npx shadcn@latest add @soundcn/<package-name>
```

Examples:
```bash
npx shadcn@latest add @soundcn/impact-metal-000
npx shadcn@latest add @soundcn/ambient-hum-001
npx shadcn@latest add @soundcn/ui-click-003
```

### Browsing soundcn.xyz

Use browser automation (claude-in-chrome) to:
1. Navigate to `https://www.soundcn.xyz/`
2. Browse categories or search for the described sound
3. Identify the package name (e.g. `@soundcn/impact-metal-000`)
4. Present candidates to the user via `AskUserQuestion`
5. Install the selected sound via `npx shadcn@latest add @soundcn/<name>`

### After soundcn download

The CLI downloads sound files locally. After download:
1. Locate the downloaded file(s)
2. Convert to mp3 if needed (see Format Guidelines)
3. Upload to R2 (see Step 5)
4. Remove the local file from the repo (sounds live on R2, not in git)

## Other CC0 Sources

When soundcn doesn't have what's needed:
- **Freesound.org** — `https://freesound.org/`
- **OpenGameArt.org** — `https://opengameart.org/`
- User may provide a direct URL to any CC0/public domain sound file

## Workflow

### Step 1: Understand the Request

Parse the argument to determine:
- **Sound category**: SFX, ambient, music, UI, voice
- **Context**: What game system/feature needs this sound
- **Desired format**: Default to `.mp3` for web (small + universal)

If the argument looks like a soundcn package name (e.g. `@soundcn/...`), skip search and go directly to install.

### Step 2: Search for Sounds

**soundcn (preferred):**
1. Browse `https://www.soundcn.xyz/` using browser tools
2. Search or browse categories for matching sounds
3. Note the `@soundcn/<package>` names

**Other sources:**
Use browser automation or ask the user for a direct URL.

Present the top 3-5 candidates to the user via `AskUserQuestion`:
- Include: name, duration, source, preview info

### Step 3: Download the Sound

**From soundcn:**
```bash
npx shadcn@latest add @soundcn/<package-name>
```

**From URL:**
Download to temp location:
```bash
curl -L -o /tmp/sgu-sounds/<filename> <url>
```

### Step 4: Convert and Normalize

If the file is not `.mp3`, convert using ffmpeg:
```bash
ffmpeg -i input.wav -codec:a libmp3lame -qscale:a 4 output.mp3
```

Normalize audio levels:
```bash
ffmpeg -i input.mp3 -af loudnorm output-normalized.mp3
```

### Step 5: Name and Categorize

Apply the project naming convention:
- **Path**: `audio/<category>/<name>.mp3`
- **Categories**: `sfx`, `ambient`, `music`, `ui`, `voice`
- **Names**: kebab-case, descriptive (e.g. `repair-sparks.mp3`, `door-hiss.mp3`)

Ask the user to confirm the name and category if ambiguous.

### Step 6: Upload to R2

Upload to the **remote** sgu-assets R2 bucket. **NEVER store audio files in the code repo.**

```bash
wrangler r2 object put sgu-assets/audio/<category>/<name>.mp3 --file /tmp/sgu-sounds/<file> --remote
```

Remove any locally downloaded files from the repo after upload:
```bash
rm /tmp/sgu-sounds/<file>
# Also remove any files soundcn may have placed in the project directory
```

Verify the upload succeeded. Report the full R2 path to the user.

### Step 7: Wire into Game

1. **Check for audio manager**: Look for an existing audio system in `src/systems/audio/`.

2. **If no audio system exists**, create one:
   - `src/systems/audio/audio-manager.ts` — Singleton manager using Three.js `AudioListener` + `Audio`/`PositionalAudio`
   - `src/systems/audio/sound-catalog.ts` — Registry mapping sound IDs to R2 asset paths
   - Export from `src/systems/audio/index.ts`

3. **Register the new sound** in the sound catalog with:
   - Sound ID (kebab-case, matches filename)
   - R2 asset path (resolved via `resolveAssetUrl()` from `src/systems/asset-resolver.ts`)
   - Default volume (0-1)
   - Category (sfx/ambient/music/ui/voice)
   - Whether it's positional (3D) or global (2D)
   - Loop setting

4. **Add the trigger** in the relevant game system:
   - Identify which scene or system should play this sound
   - Add the `playSound()` call at the appropriate trigger point
   - For positional audio, attach to the relevant `Object3D`

5. **Present the integration** to the user for approval before writing.

### Step 8: Verify

- Run `bun run typecheck` to ensure no TS errors
- Report: sound name, R2 path, trigger location, and playback settings

## Audio Format Guidelines

| Category | Format | Sample Rate | Channels | Notes |
|----------|--------|-------------|----------|-------|
| SFX      | mp3    | 44.1kHz     | Mono     | Short, one-shot |
| Ambient  | mp3    | 44.1kHz     | Stereo   | Looping, crossfade |
| Music    | mp3    | 44.1kHz     | Stereo   | Looping or one-shot |
| UI       | mp3    | 44.1kHz     | Mono     | Very short, responsive |
| Voice    | mp3    | 44.1kHz     | Mono     | Dialogue, announcements, radio chatter |

## R2 Asset Path Convention

All sounds go to `sgu-assets` R2 bucket under:
```
audio/
  sfx/           # Short sound effects (repair, hit, interact)
  ambient/       # Background loops (ship hum, corridor atmosphere)
  music/         # Music tracks
  ui/            # Interface sounds (click, hover, notification)
  voice/         # Dialogue, ship announcements, radio comms
```

## Example Usage

```
/sound-fetch @soundcn/impact-metal-000
/sound-fetch repair sparks — metallic welding sparks for conduit repair
/sound-fetch door hiss — pneumatic door opening/closing sound
/sound-fetch ambient ship hum — low frequency Destiny background hum
/sound-fetch voice ship announcement — Destiny automated warning klaxon
```
