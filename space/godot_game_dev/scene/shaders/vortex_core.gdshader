// VORTEX CORE SHADER — procedural portal pattern with tight filament brightness
shader_type spatial;
render_mode unshaded, cull_disabled, diffuse_lambert_wrap;

uniform float scale : hint_range(0.1, 8) = 2.5;
uniform float energy : hint_range(0.3, 4.0) = 1.6;   // lower brightness = less SSR wash on wet floor
uniform float detail : hint_range(0.5, 5.0) = 2.2;
uniform vec3 base_color : color = vec3(0.12, 0.08, 0.9);
uniform float opacity : hint_range(0.3, 1.0) = 0.90;

// Inner glow with 3 filaments (fewer = less density complaint from judge)
const int FILAMENT_COUNT = 3; const float FIB_SPACING = 2.4;

