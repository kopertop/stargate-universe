# Audio System

Lightweight Three.js audio — global (2D) and positional (3D) sound playback for the game.

## Files

```
audio-manager.ts         — AudioManager singleton; play/stop/attachListener
sound-catalog.ts        — Registry of all game sounds with metadata
index.ts                — Public exports
```

## Architecture

`AudioManager` uses Three.js `AudioListener` + `Audio`/`PositionalAudio`. Sounds are loaded from R2 via the asset resolver on first play and cached in memory.

**Singleton pattern** — always use `AudioManager.getInstance()`.

## Usage

```typescript
import { AudioManager } from '@/systems/audio';

// Attach listener to camera (once per scene)
const audio = AudioManager.getInstance();
audio.attachListener(camera);

// Global 2D sound
await audio.play("repair-sparks");

// Positional 3D sound (parent = Object3D in the scene)
await audio.play("repair-sparks", someObject3d);

// Stop
audio.stop("repair-sparks");

// Check if playing
audio.isPlaying("repair-sparks"); // boolean
```

## Adding Sounds

Edit `sound-catalog.ts` and add an entry to `SOUND_CATALOG`:

```typescript
"my-sound": {
  path: "/audio/sfx/my-sound.mp3",  // R2 path
  volume: 0.7,                        // 0-1
  category: "sfx",                    // sfx | ambient | music | ui | voice
  loop: false,                       // loop flag
  positional: true,                  // true = 3D positional
},
```

Sound IDs use kebab-case matching the filename on R2.

## Dependencies

- `three` (0.181) — `AudioListener`, `Audio`, `PositionalAudio`, `AudioLoader`
- `@/systems/asset-resolver` — R2 URL resolution
