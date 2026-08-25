shader_type spatial;

// Stargate Portal — procedural, texture-free vortex for a free-standing portal plane.
// Based on: "Portal shader inspired by Portal 1" (stryck33, godotshaders.com)
// Adapted for SGU: amber/orange palette, stronger central vortex, and swirl rotation.
//
// Usage:
//   - Create a MeshInstance3D with a QuadMesh
//   - Assign a ShaderMaterial using this shader
//   - Place it inside your stargate frame mesh
//   - Tweak uniforms to taste; key ones are speed, swirl_strength, core_color, ring_color

render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled, specular_disabled;

// ---- Palette (Ancient / event-horizon amber-orange) ----
uniform vec3  core_color        : source_color = vec3(1.0, 0.85, 0.55);   // hot white-yellow centre
uniform vec3  mid_color         : source_color = vec3(0.95, 0.45, 0.10);   // orange body
uniform vec3  edge_color        : source_color = vec3(0.35, 0.08, 0.01);   // deep red-brown rim
uniform vec3  ring_color_bottom : source_color = vec3(1.0, 0.9, 0.7);     // warm white ring
uniform vec3  ring_color_top    : source_color = vec3(0.95, 0.45, 0.10);   // orange ring top

// ---- Brightness / bloom balance ----
uniform float brightness         : hint_range(0.5, 10.0) = 3.0;
uniform float ring_brightness    : hint_range(0.5, 10.0) = 3.0;
uniform float halo_brightness    : hint_range(0.0, 5.0)  = 0.8;

// ---- Shape ----
uniform float oval_ratio         : hint_range(0.1, 1.0)  = 0.55;   // squish to match SGU chevron-frame oval
uniform float body_edge_inner    : hint_range(0.5, 1.0)  = 0.88;
uniform float body_edge_outer    : hint_range(0.5, 1.0)  = 1.0;

// ---- Rings ----
uniform float ring_inner_start   : hint_range(0.5, 1.0)  = 0.82;
uniform float ring_inner_end     : hint_range(0.5, 1.0)  = 0.93;
uniform float ring_outer_start   : hint_range(0.8, 1.2)  = 0.96;
uniform float ring_outer_end     : hint_range(0.8, 1.5)  = 1.04;
uniform float ring_top_brightness: hint_range(0.0, 5.0)  = 1.4;

// ---- Vertical split (top/bottom ring colour split) ----
uniform float vertical_split_top : hint_range(-0.5, 0.5) =  0.15;
uniform float vertical_split_bot : hint_range(-0.5, 0.5) = -0.15;

// ---- Halo ----
uniform float halo_outer         : hint_range(1.0, 2.0)  = 1.18;
uniform float halo_inner         : hint_range(0.5, 1.2)  = 0.94;
uniform float halo_alpha_mult    : hint_range(0.0, 1.0)  = 0.75;

// ---- Animation / swirl ----
uniform float speed              : hint_range(0.0, 3.0)  = 1.0;
uniform float turbulence         : hint_range(0.5, 3.0)  = 1.5;

// Layered noise: wide slow clouds + finer churn
uniform float noise1_scale       : hint_range(1.0, 20.0) =  5.0;
uniform float noise1_speed_x     : hint_range(-1.0, 1.0) =  0.05;
uniform float noise1_speed_y     : hint_range(-1.0, 1.0) =  0.10;
uniform float noise1_weight      : hint_range(0.0, 1.0)  =  0.55;

uniform float noise2_scale       : hint_range(1.0, 20.0) = 11.0;
uniform float noise2_speed_x     : hint_range(-1.0, 1.0) = -0.09;
uniform float noise2_speed_y     : hint_range(-1.0, 1.0) =  0.07;
uniform float noise2_weight      : hint_range(0.0, 1.0)  =  0.45;

// Extra twist that makes the surface feel like it's spiralling toward the centre
uniform float swirl_strength     : hint_range(0.0, 2.0)  = 0.6;

// ---- Cloud thresholding ----
uniform float cloud_threshold_low  : hint_range(0.0, 0.5) = 0.12;
uniform float cloud_threshold_high : hint_range(0.5, 1.0) = 0.88;
uniform float cloud_dark_level     : hint_range(0.0, 1.0) = 0.05;

// ---- FBM octaves (quality vs cost) ----
uniform int   fbm_octaves        : hint_range(1, 8)      = 5;

// ---- Noise helpers ----
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),             hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 8; i++) {
        if (i >= fbm_octaves) {
            break;
        }
        v += a * vnoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

void fragment() {
    // Centre the UV plane and squish to an oval
    vec2 uv = UV - 0.5;
    float safe_oval = max(oval_ratio, 0.001);
    vec2 e = uv * vec2(1.0 / safe_oval, 1.0);
    float r = length(e) * 2.0;

    // Convert to polar so we can twist toward the centre
    float ang = atan(e.y, e.x);
    float rad = length(e) * 2.0;

    // Swirl: more twist near the centre, driven by noise so it isn't uniform
    vec2 t1 = vec2(TIME * noise1_speed_x, TIME * noise1_speed_y) * speed;
    vec2 t2 = vec2(TIME * noise2_speed_x, TIME * noise2_speed_y) * speed;
    float n = fbm(uv * noise1_scale * turbulence + t1) * noise1_weight
            + fbm(uv * noise2_scale * turbulence + t2) * noise2_weight;

    float swirl = swirl_strength * (1.0 - smoothstep(0.0, 1.0, rad)) * (n - 0.5);
    ang += swirl;

    // Rebuild a slightly warped sample space from the polar angle
    vec2 warped = vec2(cos(ang), sin(ang)) * rad * 0.5;

    // Sample noise again in warped space for the body texture
    float n_body = fbm(warped * noise1_scale * turbulence + t1) * noise1_weight
                 + fbm(warped * noise2_scale * turbulence + t2) * noise2_weight;

    // Distort radius with noise for organic edge motion
    float dr = r + (n - 0.5) * 0.12;

    // Masks
    float body = 1.0 - smoothstep(body_edge_inner, body_edge_outer, dr);

    float ring = smoothstep(ring_inner_start, ring_inner_end, dr)
               - smoothstep(ring_outer_start, ring_outer_end, dr);

    float clouds = smoothstep(cloud_threshold_low, cloud_threshold_high, n_body);

    float bottom_mask = 1.0 - smoothstep(vertical_split_bot, vertical_split_top, uv.y);

    // Colour mix: top/bottom ring gradient
    vec3 r_bottom = ring_color_bottom * brightness * ring_brightness;
    vec3 r_top    = ring_color_top    * brightness * ring_top_brightness;
    vec3 ring_col = mix(r_top, r_bottom, bottom_mask);

    // Inner portal colour ramp: dark edge -> hot core driven by noise + radius
    float body_energy = (1.0 - smoothstep(0.0, 1.0, rad)) * 0.6 + clouds * 0.4;
    vec3 inside_col = mix(
        edge_color * brightness,
        mix(mid_color * brightness, core_color * brightness, body_energy),
        clouds
    );

    vec3 col = inside_col * body + ring_col * ring;

    // Halo / outer bloom ring
    float halo = smoothstep(halo_outer, halo_inner, r) * (1.0 - body) * clouds;
    col += ring_color_top * halo * brightness * halo_brightness;

    ALBEDO = col;
    ALPHA  = clamp(body + ring + halo * halo_alpha_mult, 0.0, 1.0);
}
