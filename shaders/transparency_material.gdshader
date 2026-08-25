
[gd_shader type=unmultiplied version=3.4]

[render_settings]
blend_mode=BLEND_MODE_MIX
transparency=TRANSPARENCY_ALPHA

uniform vec3 camera_pos : source_position;
uniform float fade_distance : hint_range(0.1, 10.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void fragment() {
    // Calculate distance from camera to fragment
    float dist = distance(camera_pos, world_pos);
    
    // Fade out based on distance (linear falloff)
    float alpha = clamp(1.0 - (dist / fade_distance), 0.0, 1.0);
    
    // Apply global opacity
    alpha *= opacity;
    
    // Basic lighting (optional - can be removed for pure transparency)
    vec3 albedo = texture(texture_albedo, UV).rgb;
    
    // Calculate simple directional light
    vec3 light_dir = normalize(vec3(0.5, 1.0, -0.5));
    float light = max(dot(NORMAL, light_dir), 0.2);
    
    // Apply transparency to final color
    vec3 final_color = albedo * light;
    
    // Alpha varies based on distance
    ALBEDO = final_color;
    ALPHA = alpha;
}

void vertex() {
    // Pass world position to fragment shader
    world_pos = (TRANSFORM * vec4(VERTEX, 1.0)).xyz;
    
    // Standard vertex processing
    VERTEX = (MATRIX * vec4(VERTEX, 1.0)).xyz;
}
