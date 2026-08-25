# Practical Application Guide: Camera Occlusion Transparency

## Quick Setup (30 seconds)

### Step 1: Create the Shader
The shader is already created at `shaders/transparency_material.gdshader`

### Step 2: Apply to Your Scene
1. Open your scene in Godot editor
2. Select objects that block the player's view (platforms, walls)
3. Click **Add Child Node** → select `apply_transparency.gd`
4. Configure in Inspector:
   - **Fade Distance**: 1.0 (how far from camera to start fading)
   - **Opacity**: 0.7 (how visible before fading)
   - **Enabled**: ✓ (check this box)

### Step 3: Test It
Press **Play** and walk towards the object - it should fade smoothly!

## Recommended Objects to Apply To

Based on the project structure, apply transparency to:

### Gate Room Scene
- Wall pillars
- Platform edges
- Decorative objects near the corridor

### Corridor Areas
- Doorframes
- Junction walls
- Room divider objects

### Character Lab
- Lab equipment surfaces
- Wall-mounted displays
- Test bench obstacles

## Common Scenarios

### Scenario 1: Platform Near Player
```gdscript
Fade Distance: 1.5
Opacity: 0.8
```
Use when player can stand close to object but shouldn't see through it

### Scenario 2: Wall Obstructions
```gdscript
Fade Distance: 1.0
Opacity: 0.6
```
Use for walls that occasionally block view during gameplay

### Scenario 3: Decorative Objects
```gdscript
Fade Distance: 3.0
Opacity: 0.4
```
Use for background objects that shouldn't be distracting

## Editor Tips

### Batch Application
1. Select multiple objects
2. Add `apply_transparency.gd` to all
3. Set common fade distance/opacity
4. Use `apply_transparency()` to all

### Debug Mode
```gdscript
# Quick debug to see distances
func _physics_process(delta):
    var camera = get_viewport().camera_3d
    if camera:
        print("Camera dist to ", name, ": ",               camera.global_position.distance_to(global_position))
```

## Troubleshooting

### Not Fading?
1. Check camera is World-Space
2. Verify material_override is applied
3. Check console for shader errors

### Too Faint?
Increase Opacity
Decrease Fade Distance

### Too Opaque?
Decrease Opacity
Increase Fade Distance

## Performance Optimization

Apply to **only** objects that:
- Are close to player (fade_distance > 1)
- Have interesting geometry worth seeing
- Occasionally block gameplay

Avoid applying to:
- Background objects (camera never gets close)
- Simple planes (low visual impact)
- Distant objects (constant rendering)

## Integration with Game Flow

### Dialogue Mode
The transparency shader works well with dialogs - NPCs appear slightly through objects, creating atmospheric depth without blocking readability.

### Cinematic Mode
For cutscenes, consider disabling transparency by setting **Enabled = false** in the inspector during playback.

### HUD Overlay
If using HUD, ensure transparency doesn't interfere with UI elements by adjusting z-index or using occlusion culling.

## Version Control

These files should be committed:
```
shaders/transparency_material.gdshader
scripts/apply_transparency.gd
tests/TEST_OCCLUSION_TRANSPARENCY.md
```

Optional (only if customized for specific scenes):
- Scene modifications with materials applied
- Custom configurations for unique objects

