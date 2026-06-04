shader_type spatial;

// Event horizon — the active Stargate "puddle".
//
// The iconic Stargate surface: a vertical pool of luminous blue water with
// concentric ripples shimmering outward from the centre. Self-lit (unshaded) so
// it glows regardless of room lighting; the OmniLight3D spill is driven from
// stargate.gd.
//
// OPAQUE (not additive): the puddle must COVER the lit wall behind the gate, or
// additive blending over a bright background washes it out to a flat white disc.
// Brightness is driven through ALBEDO because `unshaded` outputs ALBEDO and
// ignores EMISSION (see skill: godot-unshaded-ignores-emission).
//
// Reference: design/concept-art/materials/ancient-metal-pbr-sheet.png (cyan puddle).

render_mode unshaded, cull_disabled;

uniform vec4 core_color : source_color = vec4(0.05, 0.22, 0.55, 1.0);   // deep blue body
uniform vec4 rim_color : source_color = vec4(0.55, 0.88, 1.0, 1.0);     // bright cyan crests
uniform float energy : hint_range(0.0, 6.0) = 1.7;
uniform float ripple_freq = 26.0;     // concentric ring count across the radius
uniform float ripple_speed = 3.0;     // outward ripple travel speed
uniform float swirl_speed = 0.25;     // domain-warp drift (organic, non-circular)
uniform float noise_scale = 3.0;

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Disc is a flat cylinder rotated onto the gate's Z axis; xz is the face.
	vec2 uv = v_local.xz;
	float r = clamp(length(uv) / 2.32, 0.0, 1.0);
	float t = TIME;

	// Domain-warp the radius with drifting noise so the rings ripple organically
	// instead of as perfect circles.
	float warp = value_noise(uv * noise_scale + vec2(t * swirl_speed, -t * swirl_speed * 0.7)) - 0.5;
	float rr = r + warp * 0.07;

	// Concentric ripples travelling outward + a finer surface shimmer. Damped
	// amplitude + a healthy shimmer mix keep it a watery surface, not a bullseye.
	float ripple = 0.5 + 0.36 * sin(rr * ripple_freq - t * ripple_speed);
	float shimmer = value_noise(uv * noise_scale * 2.6 + vec2(-t * 0.6, t * 0.45));
	float surf = mix(ripple, shimmer, 0.46);

	// Deep blue body, brightening toward cyan-white on the ripple crests and
	// slightly toward the centre.
	vec3 col = mix(core_color.rgb, rim_color.rgb, clamp(surf * 0.85 + (1.0 - r) * 0.12, 0.0, 1.0));
	// Luminance: a clear blue base everywhere, crests punch into bloom; a soft
	// fade at the very rim so the puddle seats inside the ring.
	float lum = energy * (0.42 + surf * 0.7) * (1.0 - 0.3 * smoothstep(0.9, 1.0, r));
	ALBEDO = col * lum;
	EMISSION = col * lum;
}
