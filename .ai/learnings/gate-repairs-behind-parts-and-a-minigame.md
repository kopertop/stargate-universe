# A repair beat is parts + a hands-on puzzle, not a button press

**Context:** The web build restored Destiny's power with one `E` press on the relay. Playtest note: "repairing power is
too simple, it should be more like the original minigame, or require parts to fix." The Godot build already had the
answer: search three crates (large fuse = wrong size, small fuse = right, rations = consolation), seat the fuse, then a
wire-matching hotwire panel with a VOID decoy.

**Lesson:** Turn a single interaction into a three-stage arc that touches every system once — *diagnose* (read the
problem in dialogue), *fetch* (a small search with a red herring, rewarded even when wrong), *fix* (a 10–20 s mini-game
with a fail state that resets rather than punishes). Implement the arc as quest flags so save/load and the autoplay
harness see ordinary steps: `relay_inspected → has_small_fuse → fuse_installed → power_restored`. Loot lives on the
component spec (`{ type: 'crate', loot: [...] }`) so the level editor can author more of them without code; looted
state is a flag per crate key so it round-trips through the save.

**Applies to:** the elevator (bus fuses), scrubber/water tanks, sealed doors — any "repair X" objective in
`web/gate-room/data/chapters.json` and the Godot `procedural_ship.gd` repair paths.
