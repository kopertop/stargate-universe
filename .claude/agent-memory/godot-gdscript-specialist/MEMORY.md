# Godot GDScript Specialist — Agent Memory

Persistent project-specific knowledge for the godot-gdscript-specialist agent. Append new
entries with a date and a one-line headline + body that captures *why* the lesson exists,
not just *what* to do. Reference these in any review of player/character/scene code.

---

## Floor / collider y-conventions across scenes

**`scripts/gate_room.gd`** uses a single `BoxMesh` floor at `y=-0.1` size `0.2` → **visible
top at y=0**, collider top at y=0. Player rest height: `player.y ≈ -0.05`.

**`scripts/kenney_room.gd`** uses Kenney `models/sci-fi/space-station/floor.glb` tiles.
Each tile's mesh AABB is `pos=(-0.5, 0.0, -0.5) size=(1.0, 0.3, 1.0)` — origin at the
**bottom** of the mesh, so placing a tile at y=0 puts its **visible top at y=0.3**. The
floor collider in `_build_floor()` must therefore set `cs.position = Vector3(0.0, 0.2, 0.0)`
(top at y=0.3) to match. Player rest height: `player.y ≈ 0.25`.

**Both conventions coexist on purpose** (gate room uses BoxMesh for the perf win of one
draw call vs. 256 tile instances), but mixing y-anchoring math across rooms is a footgun:
a prop placed at `y=0.55` is "knee-height" in a Kenney room (floor top 0.3) but
"thigh-height" in the gate room (floor top 0). Any cross-scene utility (props, NPC spawns,
collider math) must branch on which room is hosting it.

**Spawn-marker y must match collider top:** when adjusting the collider top by Δy, also
shift every `Marker3D` and `Player` y by Δy across the affected scenes — otherwise the
player teleports inside the collider on entry and gets push-out-popped to the surface,
which reads as a half-frame "snap up." Captured 2026-05-21 raising the Kenney collider
top from 0 → 0.3 and bumping spawn-marker y from 0.05 → 0.35 in 9 scenes.

---

## glTF kit pieces have their origin at the BOTTOM of the mesh

Kenney sci-fi space-station kit convention:

| File | AABB pos | AABB size | Top y |
|---|---|---|---|
| `floor.glb` | (-0.5, 0, -0.5) | (1, 0.3, 1) | 0.3 |
| `wall.glb` | (-0.5, 0, -0.15) | (1, 1, 0.3) | 1.0 (then × `wall_y_scale`) |
| `wall-door.glb` | (-0.5, 0, -0.15) | (1, 1, 0.3) | 1.0 |

A wall placed at y=0 has its bottom 0.3m hidden inside the floor tile sitting beside it.
This is the kit's intended visual stack-up. Don't "fix" the bottom 0.3m clipping — it's
how the tiles were modeled.

---

## glTF skinned-mesh AABB lift is per-scene, not universal

Godot reports `accessor.min/max` as **pre-skinning** bounds, so a Model node placed at
y=0 in `objects/character.tscn` may render with the visual feet below the model's
nominal origin. The compensating lift in `character.tscn` (`Model.transform.origin.y`)
is **scene-floor-dependent**:

- With `gate_room.gd`'s BoxMesh floor (top y=0): lift = **0** reads correctly.
- With `kenney_room.gd`'s tile floor (top y=0.3): would need lift ≈ 0.3 / 1.6 = 0.1875
  to plant feet visually — but instead we standardize on lift=0 and align the floor
  colliders so the player visually sits 0.05m below the floor top in **every** scene
  (the 0.05m capsule offset reads as "feet planted" given the AABB error).

**Tuning history (2026-05-20 → 2026-05-21):** 0.3125 → 0.25 → 0.225 → 0. Each step was
the user reporting the character still reading as hovering after a scene-floor change.
Don't anchor on a single "settled" value as universally correct — re-measure when scene
floor conventions change.

Related external memory: `~/.claude/projects/-Users-cmoyer-Projects-personal-stargate-universe/memory/feedback_gltf_skinned_mesh_aabb.md`.

---

## AABB probe — the canonical "visual vs collider misalignment" debugging tool

When the player appears sunken, hovering, or clipping into geometry, the bug almost
always reduces to "the visual mesh top is at y=A, but the collider top is at y=B,
A≠B." Don't guess the offset — measure it with a one-shot SceneTree probe:

```gdscript
extends SceneTree

func _measure(path: String) -> void:
    var scn: PackedScene = load(path)
    var inst: Node3D = scn.instantiate()
    root.add_child(inst)
    var aabb: AABB = AABB()
    var first: bool = true
    for child in inst.find_children("*", "MeshInstance3D", true, false):
        var mi: MeshInstance3D = child
        var t: Transform3D = mi.global_transform
        var world_aabb: AABB = t * mi.get_aabb()
        if first: aabb = world_aabb; first = false
        else: aabb = aabb.merge(world_aabb)
    print(path, " AABB: pos=", aabb.position, " size=", aabb.size,
        " top_y=", aabb.position.y + aabb.size.y)
    root.remove_child(inst)
    inst.queue_free()

func _init() -> void:
    _measure("res://path/to/asset.glb")
    quit()
```

Run with:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/probe/<name>.gd 2>&1 | grep AABB
```

The expected error `Condition "!is_inside_tree()" is true. Returning: Transform3D()` is
benign at the top of `_measure` (fires once before the first add_child completes).
**Delete the probe script after use** — keep `tests/` clean.

---

## Recent fixes index (chronological)

- **2026-05-21** Zeroed `Model.transform.origin.y` in `objects/character.tscn` after the
  gate room got a new floor convention. See "glTF skinned-mesh AABB lift" above.
- **2026-05-21** Raised `kenney_room.gd` floor collider top from y=0 → y=0.3 to match
  the kit's visible tile top. Bumped spawn markers y=0.05 → 0.35 in 9 scenes. See
  "Floor / collider y-conventions across scenes" above.
- **2026-05-21** Gate room walls consolidated to solid panels — doors are decorative
  interactables on solid walls, transitions are E-interact only (no archway portals).
- **2026-05-20** `Interactable._ready()` overwrites `collision_layer = 4`; subclasses
  needing extra bits (walk-blocker, occluder) must set after `super()._ready()`. See
  global memory `feedback_interactable_overwrites_collision_layer.md`.
