---
name: add-room
description: "Create a new Godot room scene using the kenney_room.gd procedural builder, and auto-wire its doors and spawn markers into an existing connected room. Use this when the user says 'add a room', 'create a new room', '/add-room <name>', or describes wanting a new playable area linked to an existing one. Handles the full pattern: new .tscn + reciprocal Door + From* Marker3D in both rooms + smoke-test entry + objective text + capture script registration."
argument-hint: "[room_name] (snake_case; ask if omitted)"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
model: sonnet
---

# Add Room

Codifies the repeatable pattern for adding a new playable area on the `godot`
branch. Every Kenney-style room in this project follows the same shape — a
`kenney_room.gd`-driven `.tscn` with floor/wall/ceiling parameters, door cutout
indices, a `World` child, a `Player` + `View` + `SpringArm`/`Camera` rig, a
HUD layer, an `AmbientHum`, plus `Door` instances and `From*` `Marker3D` spawn
points reciprocally connected to the rooms it links to.

This skill drives that template end-to-end. It asks the user for whatever it
needs that wasn't already supplied, writes the new scene, edits the connecting
scene to add the inverse Door + Marker, and registers the room in the smoke
test list and baseline-capture script so the next `tests/run.sh` covers it.

**Inputs the skill needs:**
- Room name (snake_case, e.g. `infirmary`)
- Display name for HUD discovery banner (`Infirmary`)
- Objective text shown on entry (`Find the medkit`)
- Connection target — which existing scene this room attaches to, and which
  side of the connecting room the new door punches through
- Room dimensions (`floor_size`, `wall_y_scale`, `ceiling_height`)
- Wall colour (albedo for the `StandardMaterial3D_metallic` sub-resource)
- Door status indicator colour (passed to `corridor_decor`-style accent if the
  room is a corridor variant — optional)

For anything not provided in the original prompt, ASK with `AskUserQuestion`.
Make every required field a question; never invent values silently.

---

## Phase 1: Parse arguments and inspect repo state

1. Take `$ARGUMENTS` as the proposed room name. If empty, ask:
   ```
   AskUserQuestion:
     question: "What is the new room's snake_case name? (e.g. infirmary, cargo_bay)"
     header: "Room name"
   ```
2. Run `ls scenes/` to enumerate existing scenes. If `scenes/<name>.tscn`
   already exists, abort and tell the user. Don't overwrite.
3. Read `scripts/kenney_room.gd` to confirm the `@export` surface is still
   `floor_size / wall_y_scale / ceiling_height / floor_scene / wall_scene /
   wall_door_scene / south_door_index / north_door_index / east_door_index /
   west_door_index / metallic_material / ceiling_material / objective_on_enter`.
   If that surface has drifted, halt and report — the template is stale.
4. Read `tests/smoke/scene_boot.gd` and `tests/capture_baselines.sh` so you
   know exactly where to splice the new entries.

---

## Phase 2: Gather room metadata (AskUserQuestion)

Ask only for fields the user hasn't already specified. Batch into at most
3 calls. Always include the room-name confirmation as the first question
unless it came in via `$ARGUMENTS`.

**Batch A — identity & narrative:**
```
question: "Display name for the room — shown in the discovery banner ('Discovered: X')?"
header: "Display name"
```
```
question: "Objective text shown on entry (HUD top-left, e.g. 'Find the medkit')?"
header: "Objective"
```

**Batch B — shape:**
```
question: "Room footprint? Pick a preset or choose Other for a custom size."
header: "Footprint"
options:
  - { label: "Small (6×8)", description: "Quarters/utility room scale" }
  - { label: "Medium (8×12)", description: "Standard explorable room" }
  - { label: "Large (10×16)", description: "Mess hall / hub scale" }
  - { label: "Corridor (6×12)", description: "Long & narrow, matches existing corridor rooms" }
```
```
question: "Ceiling height?"
header: "Height"
options:
  - { label: "Standard (5.0m)", description: "Matches corridors and quarters" }
  - { label: "Tall (6.0m)", description: "Matches the gate room and control room" }
```

**Batch C — palette:**
```
question: "Wall accent palette?"
header: "Palette"
options:
  - { label: "Neutral grey", description: "Default Destiny corridor look" }
  - { label: "Warm tan", description: "Living quarters / mess hall" }
  - { label: "Cool blue", description: "Bridge / control areas" }
  - { label: "Hazard amber", description: "Hull breach / emergency" }
```

Map palette → albedo Color tuple before writing:
- Neutral grey → `Color(0.48, 0.50, 0.55, 1)`
- Warm tan → `Color(0.55, 0.50, 0.42, 1)`
- Cool blue → `Color(0.42, 0.48, 0.58, 1)`
- Hazard amber → `Color(0.58, 0.42, 0.30, 1)`

---

## Phase 3: Connection (this is the critical part)

A room with no door to anywhere else is unreachable. Always wire at least one
connection. Ask which existing scene to connect to, and on which side of THAT
connecting scene the new door punches through.

**Pick connecting scene:**
```
question: "Which existing scene should this room connect to?"
header: "Connects to"
options:  # build dynamically from the scenes/ listing minus title/main
  - { label: "destiny_corridor.tscn", description: "Main hub junction (recommended for new rooms)" }
  - { label: "<other candidate>", description: "..." }
  - ...
```

**Pick the side of the connecting scene where the new door appears:**
```
question: "Which wall of <connecting_scene> should the door be punched through?"
header: "Side"
options:
  - { label: "North (+Z)", description: "Top of the room when viewed top-down" }
  - { label: "South (-Z)", description: "Bottom of the room" }
  - { label: "East (+X)", description: "Right side" }
  - { label: "West (-X)", description: "Left side" }
```

**Sanity check:** open the connecting scene's `.tscn`, find its `Room` node
parameters, and confirm the chosen side currently has `<side>_door_index = -1`
(i.e. no door yet). If it already has a door on that side, ask the user
whether to pick a different side or replace the existing door.

---

## Phase 4: Write the new scene

Build `scenes/<room>.tscn` from the template below. Reuse the existing UIDs
for shared resources (env, player, view, floor, wall, wall-door, door, hud,
ambient, decor) — they are listed in `corridor_crew.tscn` for reference.

Use a fresh `uid://` for the scene itself: `uid://cgr0<room>0` (replace
`<room>` with the room slug, no underscores). It must be unique — grep `scenes/`
to be sure.

Door indices on the new room:
- The wall facing the connecting scene gets a door at the centre tile index
  (e.g. for `floor_size = Vector2i(8, 12)` and connecting on south, set
  `south_door_index = 4`).
- All other sides stay `-1` unless the user asks for additional connections.

Spawn marker name in the new room is `From<ConnectingSceneCamelCase>`
(e.g. corridor → `FromCorridor`). The marker sits ~3.5m inside the wall from
the door (matches the spawn-distance convention so `playthrough_runner.gd`'s
4.5m entry-door threshold passes — see `[[feedback_door_decorative_recess]]`
and the `_expect_player_faces_away_from_entry_door` helper in
`scripts/playthrough_runner.gd`).

The Player's transform must match the spawn marker exactly so headless boots
land the player where they will arrive from the connecting scene.

**Template (parameterised — fill the {{...}} placeholders):**

```
[gd_scene load_steps=12 format=3 uid="uid://cgr0{{room_slug_nounderscore}}0"]

[ext_resource type="Environment" uid="uid://cgrenvinterior00" path="res://scenes/destiny-interior-environment.tres" id="1_env"]
[ext_resource type="Script" path="res://scripts/kenney_room.gd" id="2_room"]
[ext_resource type="PackedScene" uid="uid://dl2ed4gkybggf" path="res://objects/player.tscn" id="3_player"]
[ext_resource type="Script" uid="uid://bcg2kkbsnttec" path="res://scripts/view.gd" id="4_view"]
[ext_resource type="PackedScene" uid="uid://dynqkgbn3lu4u" path="res://models/sci-fi/space-station/floor.glb" id="5_floor"]
[ext_resource type="PackedScene" uid="uid://bf2a38eob8tr5" path="res://models/sci-fi/space-station/wall.glb" id="6_wall"]
[ext_resource type="PackedScene" uid="uid://ycqgyfiu8ry6" path="res://models/sci-fi/space-station/wall-door.glb" id="7_walldoor"]
[ext_resource type="PackedScene" uid="uid://b0doorinteractable" path="res://objects/door.tscn" id="8_door"]
[ext_resource type="PackedScene" uid="uid://b1hudsgu000" path="res://objects/hud.tscn" id="9_hud"]
[ext_resource type="Script" path="res://scripts/ambient_hum.gd" id="10_ambient"]

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_metallic"]
albedo_color = {{wall_color}}
metallic = 0.25
metallic_specular = 0.45
roughness = 0.6

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_ceiling"]
albedo_color = Color(0.18, 0.18, 0.22, 1)
metallic = 0.25
roughness = 0.65

[node name="{{RoomPascalCase}}" type="Node3D"]

[node name="Room" type="Node3D" parent="."]
script = ExtResource("2_room")
floor_size = Vector2i({{size_x}}, {{size_z}})
wall_y_scale = {{ceiling_height}}
ceiling_height = {{ceiling_height}}
floor_scene = ExtResource("5_floor")
wall_scene = ExtResource("6_wall")
wall_door_scene = ExtResource("7_walldoor")
south_door_index = {{south_idx}}
north_door_index = {{north_idx}}
east_door_index = {{east_idx}}
west_door_index = {{west_idx}}
metallic_material = SubResource("StandardMaterial3D_metallic")
ceiling_material = SubResource("StandardMaterial3D_ceiling")
objective_on_enter = "{{objective_text}}"

[node name="World" type="Node3D" parent="Room"]

[node name="Environment" type="WorldEnvironment" parent="."]
environment = ExtResource("1_env")

[node name="KeyLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(-0.422618, -0.694272, 0.582563, 0, 0.642788, 0.766044, -0.906308, 0.323744, -0.271654, 0, 8, 0)
light_color = Color(0.86, 0.82, 0.72, 1)
light_energy = 1.2
shadow_enabled = true
shadow_opacity = 0.4

# Three OmniLights down the room's long axis — copy CorridorLightS/C/N from
# corridor_crew.tscn and reposition so they sit at -half_z+2, 0, half_z-2.

[node name="CorridorDoor" parent="." groups=["interactable"] instance=ExtResource("8_door")]
transform = {{door_transform}}
target_scene = "res://scenes/{{connecting_scene}}.tscn"
target_spawn = "From{{ThisRoomPascalCase}}"
transition_prompt = "Back to the {{connecting_human}}"
open_prompt = "Back to the {{connecting_human}}"

[node name="From{{ConnectingRoomPascalCase}}" type="Marker3D" parent="."]
transform = {{spawn_marker_transform}}

[node name="Player" parent="." node_paths=PackedStringArray("view") groups=["player"] instance=ExtResource("3_player")]
transform = {{spawn_marker_transform}}
view = NodePath("../View")

[node name="View" type="Node3D" parent="." node_paths=PackedStringArray("target")]
transform = Transform3D(0.866025, -0.25, 0.433013, 0, 0.866025, 0.5, -0.5, -0.433013, 0.75, 0, 0, 0)
script = ExtResource("4_view")
target = NodePath("../Player")

[node name="SpringArm" type="SpringArm3D" parent="View"]
collision_mask = 2
spring_length = 4.5
margin = 0.2

[node name="Camera" type="Camera3D" parent="View/SpringArm"]
current = true
fov = 60.0

[node name="HUDLayer" type="CanvasLayer" parent="."]
layer = 10

[node name="HUD" parent="HUDLayer" instance=ExtResource("9_hud")]

[node name="AmbientHum" type="AudioStreamPlayer" parent="."]
volume_db = -20.0
script = ExtResource("10_ambient")
base_freq = 52.0
```

**Door + spawn transform math:**

Half-extents: `hx = size_x * 0.5`, `hz = size_z * 0.5`. The connecting wall
sits at `±hx` or `±hz` depending on side.

For a SOUTH-connecting room (door on -Z):
- Door transform: `Transform3D(-1, 0, 0,  0, 1, 0,  0, 0, -1,  0, 0, -hz)` — yaw 180°, sitting on the -Z wall plane.
- Spawn marker `FromCorridor` (or whichever room you came from) faces +Z (away from the door): `Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1,  0, 0.35, -hz + 3.5)` — 3.5m inside the room, lifted 0.35m so they're standing on the floor visually.

For the OTHER sides, rotate accordingly. Reference `corridor_crew.tscn` for
the exact basis matrices that the existing scenes use (the rotations are
non-obvious; copy them rather than re-deriving).

---

## Phase 5: Wire the inverse connection (mutate the connecting scene)

Open `scenes/<connecting>.tscn` and add:

1. A door at the centre tile of the side you picked, pointing to the new room.
   - Set the connecting room's matching `<side>_door_index` on its `Room` node
     to the tile index where the door appears.
   - Instance an additional `Door` node with:
     ```
     target_scene = "res://scenes/<new_room>.tscn"
     target_spawn = "From<ConnectingPascalCase>"
     transition_prompt = "Enter the <new room human name>"
     open_prompt = "Enter the <new room human name>"
     ```
   - Position the door at the same wall plane as the existing doors in that
     scene.

2. A `Marker3D` named `From<NewRoomPascalCase>` placed ~3.5m inside the
   connecting room from the new door, facing AWAY from the door. This is
   where the player lands when they come back FROM the new room.

If the connecting scene's `kenney_room.gd`-driven `Room` node already has a
door on the chosen side, halt with an explanation — never silently overwrite.

---

## Phase 6: Register in tests + capture

1. Edit `tests/smoke/scene_boot.gd`. Add a new SCENES entry:
   ```gdscript
   {
       "path": "res://scenes/<new_room>.tscn",
       "requires": [
           "Player",
           "View/SpringArm/Camera",
           "HUDLayer/HUD",
           "CorridorDoor",  # or whatever the door name is
           "From<ConnectingPascalCase>",
       ],
   },
   ```
2. Edit `tests/capture_baselines.sh`. Add the new room slug to `ROOMS_DEFAULT`
   in alphabetical order with its siblings.
3. If the new room has any specific camera concerns (very close walls, dense
   decor behind player), add a `get_extra_args` case mirroring `eli_quarters`
   or `hull_breach` patterns.

---

## Phase 7: Verify

1. Run `tests/run.sh scene` — the smoke test must pass with the new entry.
2. Run `tests/capture_baselines.sh <new_room>` — confirm the screenshot
   produces and shows the player + doorway without clipping or void.
3. Show the captured screenshot to the user.
4. If everything looks good, summarise what was added (one line per file
   touched) and ask if the user wants you to commit. Never commit without
   approval.

---

## Phase 8: Memory + retrospective

If this run produced any non-obvious knowledge (a transform that needed
inverting, a UID collision, a smoke-test assertion that surprised you),
invoke the continuous-learning skill to save it before exiting.

---

## Collaborative Protocol

- **Never overwrite an existing scene** — abort if `scenes/<name>.tscn` exists.
- **Both ends of the connection must be wired** — a one-way door is a bug.
- **Reuse UIDs** for shared resources; only the scene root needs a fresh UID.
- **Spawn markers sit 3.5m inside the wall**, not at the door. This is the
  contract with `playthrough_runner.gd`'s entry-door distance check.
- **Player transform == spawn marker transform** so the headless capture
  lands in the right place on cold boot.
- **Never commit** — show the diff and ask.
- **AskUserQuestion every missing input** — do not invent room sizes, palettes,
  or objectives.
