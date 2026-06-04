shader_type spatial;

// Event horizon — the active Stargate "puddle" / portal vortex.
//
// Technique (the same recipe behind good real-time portal shaders, written
// natively for Godot — no ported/proprietary code):
//   • fBm  — fractal Brownian motion (octaves of value noise) for organic energy
//   • domain warp — sample fBm at coords offset by more fBm → churning liquid
//   • polar swirl — twist the sample angle by radius + time → a spiralling vortex
//   • hot core + rim falloff — bright unstable centre fading into the ring
//
// OPAQUE (not additive): the puddle must COVER the lit wall behind the gate, or
// blending over a bright background washes it out to white. Brightness rides on
// ALBEDO because `unshaded` ignores EMISSION (skill: godot-unshaded-ignores-emission).

render_mode unshaded, cull_disabled;

uniform vec4 core_color : source_color = vec4(0.78, 0.95, 1.0, 1.0);   // hot centre
uniform vec4 mid_color : source_color = vec4(0.18, 0.55, 0.95, 1.0);   // body
uniform vec4 edge_color : source_color = vec4(0.02, 0.10, 0.34, 1.0);  // deep rim
uniform float energy : hint_range(0.0, 6.0) = 1.9;
uniform float swirl : hint_range(0.0, 12.0) = 4.5;     // angular twist per radius (vortex)
uniform float flow_speed = 0.5;                        // noise drift / churn rate
uniform float warp_amount : hint_range(0.0, 2.0) = 0.55;
uniform float detail = 3.2;                            // base fBm frequency
uniform float spin_speed = 0.4;                        // whole-vortex rotation

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian motion — 5 octaves, lacunarity 2, gain 0.5.
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));   // de-correlate octaves
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p = rot * p * 2.0;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Normalised disc coords (-1..1), disc local half-extent ~2.32.
	vec2 uv = v_local.xz / 2.32;
	float r = clamp(length(uv), 0.0, 1.0);
	float ang = atan(uv.y, uv.x);
	float t = TIME;

	// Polar swirl: twist the angle harder toward the centre + a slow global spin,
	// then rebuild a seamless sample coordinate from (cos,sin) so there's no atan
	// wrap seam. Features stretch into spiral arms.
	float a = ang + swirl * (1.0 - r) + t * spin_speed;
	vec2 swuv = vec2(cos(a), sin(a)) * (r * detail);

	// Domain warp: offset the fBm lookup by another fBm pair → churning liquid.
	vec2 q = vec2(
		fbm(swuv + vec2(0.0, 0.0) + t * flow_speed),
		fbm(swuv + vec2(5.2, 1.3) - t * flow_speed)
	);
	float n = fbm(swuv + warp_amount * q + vec2(t * flow_speed * 0.6, -t * flow_speed * 0.4));

	// Radial shape: hot unstable core, energetic body, fade into the ring.
	float core = smoothstep(0.5, 0.0, r);
	float body = 1.0 - smoothstep(0.86, 1.02, r);
	float energy_field = (n * 0.75 + 0.25) * body;

	// Colour ramp: deep rim → cyan body → hot white core, pushed by the noise.
	vec3 col = mix(edge_color.rgb, mid_color.rgb, clamp(energy_field * 1.3, 0.0, 1.0));
	col = mix(col, core_color.rgb, clamp(core * (0.6 + n * 0.6), 0.0, 1.0));

	float lum = energy * (0.35 + energy_field * 1.0 + core * 0.7);
	ALBEDO = col * lum;
	EMISSION = col * lum;
}
