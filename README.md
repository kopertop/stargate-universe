# Stargate Universe

A Godot 4.6 sci-fi RPG set in the Stargate Universe TV series.

## Status

This branch (`reset-stack`) is a complete engine pivot from the previous browser-based stack
(Three.js / WebGPU / ggez / Crashcat / VRM). The previous stack is preserved on `main`.

Bootstrapped from [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)
(CC0).

## Running

1. Install [Godot 4.6](https://godotengine.org/) (Forward+ renderer).
2. Open `project.godot` in Godot.
3. Press **F5** to run the main scene.

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
