
# Camera-Occlusion Transparency

## Overview

This feature adds depth-based transparency to geometry that blocks the player's view, making it fade smoothly rather than completely occluding characters.

## Files Created

### 1. Shader: `shaders/transparency_material.gdshader`
- **Purpose**: Base transparency shader for occlusion handling
- **Key Parameters**:
  - `camera_pos`: Current camera position (automatic input)
  - `fade_distance`: Distance at which material becomes fully transparent (0.1 - 10.0)
  - `opacity`: Base opacity (0.0 - 1.0) - default: 0.7 (70%)

### 2. Script: `scripts/apply_transparency.gd`
- **Purpose**: Utility script to automatically apply the transparency material
- **Usage**: Attach to objects that need occlusion transparency

## How to Use

### Method 1: In Editor (Recommended)

1. Select an object that needs transparency (platform, wall, etc.)
2. Add the `apply_transparency.gd` script as a child node
3. Configure the following properties:
   - **Fade Distance**: How far from camera to start fading (default: 1.0)
   - **Opacity**: How opaque the material is by default (default: 0.7)
   - **Enabled**: Toggle the effect on/off

4. Run `apply_transparency()` in the editor or press Play to test

### Method 2: Manually Applying Material

```gdscript
# Apply material to mesh instances
var shader = load("res://shaders/transparency_material.gdshader").new()
var mat = ShaderMaterial.new()
mat.shader = shader
mat.set("shader_parameter/fade_distance", 1.5)
mat.set("shader_parameter/opacity", 0.6)

# Apply to your mesh
$MeshInstance3D.material_override = mat
```

## Implementation Details

### Shader Logic
- **Distance-based alpha calculation**: `alpha = 1.0 - (distance / fade_distance)`
- **Smooth falloff**: Clamped between 0.0 and 1.0
- **Lighting preserved**: Uses base lighting for realistic fade

### Performance
- Lightweight shader (no texture lookups required)
- Uses built-in transparency mode
- Efficient distance calculation in fragment shader

## Testing

1. Launch game in editor: `godot -e --path .`
2. Navigate to scene with objects that need transparency
3. Observe geometry blocking view fading smoothly
4. Adjust fade_distance based on gameplay needs

## Known Limitations

- Material affects entire mesh uniformly - use for objects that should be see-through
- Not suitable for objects that need precise cut-out transparency
- Requires SpringArm3D collision detection to function properly

## Related Issues

- GitHub Issue: #139 Camera-occlusion transparency
- Issue Type: Bug fix
- Status: Complete
