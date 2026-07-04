
# Test Harness for Camera Occlusion Transparency

This is a simplified test to verify the transparency shader works correctly.

## Quick Test (5 minutes)

1. Copy `transparency_material.gdshader` to your project
2. Create a test scene with:
   - A player/camera
   - A platform that should fade
3. Apply material to platform
4. In editor Play mode, observe:
   - Platform should fade when camera gets close
   - Alpha should change smoothly based on distance

## Verification Checklist

- [ ] Shader compiles without errors
- [ ] Material applies to mesh
- [ ] Distance calculation works
- [ ] Alpha varies with camera distance
- [ ] Visual fade is smooth (no hard edges)
- [ ] Performance is acceptable (<5ms on test hardware)

## Common Issues

### Shader Won't Compile
- Check Godot version (requires 4.0+)
- Ensure file extension is `.gdshader`

### No Transparency
- Verify mesh instance has material_override
- Check camera_pos shader input (must match Camera3D world position)
- Debug: print distances in fragment shader

### Performance Issues
- Reduce fade_distance range
- Optimize mesh geometry
- Disable transparency for distant objects
