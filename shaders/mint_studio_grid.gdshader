shader_type spatial;

// World-space grid so travel reads as real progress (no UV treadmill snap).
uniform vec3 bg_color: source_color = vec3(0.10, 0.11, 0.14);
uniform vec3 line_color: source_color = vec3(0.32, 0.52, 0.72);
uniform vec3 major_color: source_color = vec3(0.55, 0.78, 0.95);
uniform float cell_size = 1.0;
uniform float major_every = 5.0;
uniform float line_width = 1.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / max(cell_size, 0.001);
	vec2 deriv = fwidth(p);
	vec2 grid = abs(fract(p - 0.5) - 0.5) / max(deriv, vec2(1e-5));
	float line = 1.0 - clamp(min(grid.x, grid.y) / line_width, 0.0, 1.0);

	vec2 p_maj = world_pos.xz / max(cell_size * major_every, 0.001);
	vec2 d_maj = fwidth(p_maj);
	vec2 g_maj = abs(fract(p_maj - 0.5) - 0.5) / max(d_maj, vec2(1e-5));
	float major = 1.0 - clamp(min(g_maj.x, g_maj.y) / line_width, 0.0, 1.0);

	vec3 col = bg_color;
	col = mix(col, line_color, line * 0.85);
	col = mix(col, major_color, major * 0.95);
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
