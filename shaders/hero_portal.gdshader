shader_type spatial;

// Hero portal — the cinematic event-horizon vortex for the gate-room beauty shot.
// Target reference: design/concept-art/gate-room/target/gateroom-hero-target.png
//
// Distinct from event_horizon.gdshader (issue #30): this one is UV-driven so it
// rides on a plain QuadMesh, and its radial profile draws a DARK unstable hole at
// the centre ringed by a bright band of churning blue energy that fades out at the
// rim — matching the concept's "black eye inside a storm" look, NOT a hot core.
//
// Recipe (native Godot, no ported code):
//   • fBm (octave value noise) for organic energy
//   • domain warp — sample fBm offset by more fBm → churning liquid
//   • polar swirl — twist sample angle by radius + time → spiral arms
//   • annular radial mask — peak at mid radius, dark hole, soft rim fade
//
// unshaded ⇒ EMISSION is ignored; brightness rides on ALBEDO (skill:
// godot-unshaded-ignores-emission). OPAQUE so it covers the wall behind the gate.

render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3  core_color  : source_color = vec3(0.62, 0.82, 1.0);   // hot white-blue highlights
uniform vec3  body_color  : source_color = vec3(0.20, 0.52, 0.95);  // main blue energy
uniform vec3  rim_color   : source_color = vec3(0.03, 0.10, 0.30);  // deep blue rim
uniform vec3  hole_color  : source_color = vec3(0.0, 0.01, 0.04);   // dark unstable centre

uniform float energy        : hint_range(0.0, 8.0) = 2.0;
uniform float swirl         : hint_range(0.0, 16.0) = 7.0;    // angular twist per radius
uniform float spin_speed                            = 0.35;   // whole-vortex rotation
uniform float flow_speed                            = 0.55;   // churn / drift rate
uniform float warp_amount   : hint_range(0.0, 2.0)  = 0.85;
uniform float detail                                = 3.0;    // base fBm frequency

// Radial annulus profile (in 0..1 disc radius). The bright churning band now
// spans most of the disc (peak pushed outward) with a clear dark centre, so the
// vortex reads as a LARGE energy mass filling the ring, not a small hot dot.
uniform float hole_radius   : hint_range(0.0, 0.6)  = 0.22;   // dark centre extent
uniform float ring_peak     : hint_range(0.1, 0.9)  = 0.62;   // brightest band radius
uniform float rim_fade      : hint_range(0.6, 1.15) = 1.05;   // outer fade edge
uniform float ring_sharp    : hint_range(0.3, 4.0)  = 0.85;   // band tightness (low = broad)

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

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p = rot * p * 2.0;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;            // -1..1
	float r = clamp(length(uv), 0.0, 1.0);
	float ang = atan(uv.y, uv.x);
	float t = TIME;

	// Polar swirl + global spin, rebuilt from (cos,sin) to avoid the atan seam.
	float a = ang + swirl * (1.0 - r) + t * spin_speed;
	vec2 swuv = vec2(cos(a), sin(a)) * (r * detail);

	// Domain warp: churning liquid.
	vec2 q = vec2(
		fbm(swuv + t * flow_speed),
		fbm(swuv + vec2(5.2, 1.3) - t * flow_speed)
	);
	float n = fbm(swuv + warp_amount * q + vec2(t * flow_speed * 0.6, -t * flow_speed * 0.4));

	// Annular radial mask: dark hole → bright band at ring_peak → soft rim fade.
	float inner = smoothstep(hole_radius, ring_peak, r);          // 0 in hole, 1 at peak
	float outer = 1.0 - smoothstep(ring_peak, rim_fade, r);       // 1 at peak, 0 at rim
	float band  = pow(clamp(inner * outer, 0.0, 1.0), ring_sharp);

	float energy_field = (n * 0.75 + 0.25) * band;

	// Colour ramp: deep rim → blue body → hot white highlights on noise peaks.
	vec3 col = mix(rim_color, body_color, clamp(energy_field * 1.4, 0.0, 1.0));
	col = mix(col, core_color, clamp((n - 0.55) * 2.2 * band, 0.0, 1.0));

	// Dark unstable hole bleeds in toward the centre.
	float hole = 1.0 - smoothstep(hole_radius * 0.4, hole_radius * 1.3, r);
	col = mix(col, hole_color, hole);

	float lum = energy * (0.18 + energy_field * 1.15);
	ALBEDO = col * lum;
	ALPHA = 1.0;
}
