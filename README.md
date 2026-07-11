# Stargate Universe

A Godot 4.6 sci-fi RPG set in the Stargate Universe TV series.

## Status

Bootstrapped from [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)
(CC0).

## Install

macOS (Homebrew):

```sh
brew install --cask godot
```

Otherwise download Godot 4.6+ (Forward+) from [godotengine.org](https://godotengine.org/).

## Running

Play directly (no editor):

```sh
godot --path .
```

Or open the editor: `godot -e --path .` and press **F5**.

## Controls

- **WASD** — move
- **Space** — jump (double-jump enabled)
- **Right mouse (hold)** — mouselook (WoW-style)
- **Mouse wheel** — zoom in/out
- **Arrow keys** — camera orbit (fallback)
- **Esc** — release mouse / quit

## Layout

```
project.godot       Godot project config
scenes/             .tscn scenes (entry: scenes/main.tscn)
scripts/            GDScript (audio, hud, main, player, view)
models/             Kenney CC0 .glb models
objects/            Reusable .tscn prefabs
sounds/             SFX
sprites/            UI sprites
fonts/              Fonts
design/gdd/         Game Design Documents (carried from browser branch)
production/         Sprint plans, milestones
docs/               Narrative reference, audio inventory
```

## Credits

- Engine: [Godot 4.6](https://godotengine.org/)
- Starter kit: [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) — CC0 by Kenney
- Stargate Universe is a TV series by MGM; this is a non-commercial fan project.

## License

See `LICENSE-kenney.md` for the starter kit's CC0 license. Project code is private/unlicensed.
