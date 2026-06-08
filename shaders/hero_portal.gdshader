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

uniform float energy        : hint_range(0.0, 8.0) = 3.4;
uniform float swirl         : hint_range(0.0, 16.0) = 7.0;    // angular twist per radius
uniform float spin_speed                            = 0.35;   // whole-vortex rotation
uniform float flow_speed                            = 0.55;   // churn / drift rate
uniform float warp_amount   : hint_range(0.0, 2.0)  = 0.85;
uniform float detail                                = 3.0;    // base fBm frequency

// Radial annulus profile (in 0..1 disc radius). The bright churning band now
// spans most of the disc (peak pushed outward) with a clear dark centre, so the
// vortex reads as a LARGE energy mass filling the ring, not a small hot dot.
uniform float hole_radius   : hint_range(0.0, 0.7)  = 0.30;   // dark centre extent
uniform float ring_peak     : hint_range(0.1, 0.95) = 0.66;   // brightest band radius
uniform float rim_fade      : hint_range(0.6, 1.15) = 1.02;   // outer fade edge
uniform float ring_sharp    : hint_range(0.3, 4.0)  = 0.7;    // band tightness (low = broad)

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

	// Concentric churning rings — bright blue-white shells spiralling OUTWARD from the
	// hole. Two interfering frequencies + the warp noise give dense overlapping shells
	// that read as turbulent energy arms, not a single static circle. Higher frequency
	// near the rim so the spiral tightens toward the dark eye.
	float ring_phase = (r * 17.0 - t * 2.2) + n * 6.5 + ang * 0.8;
	float rings = sin(ring_phase) * 0.6 + sin(ring_phase * 1.9 + n * 3.0) * 0.4;
	rings = pow(clamp(rings * 0.5 + 0.5, 0.0, 1.0), 1.3);

	// Energy field: the band fills MOST of the aperture (broad ring_sharp), and the
	// noise+rings drive a high, churning value across it so the disc reads as a large
	// bright energy mass — not a thin outline. Bias the base up so the whole disc
	// inside the rim is lit, then let the turbulence carve bright/dark spiral detail.
	float raw = (0.32 + n * 0.55 + rings * 0.7) * band;
	float energy_field = pow(clamp(raw, 0.0, 1.0), 1.05);

	// Colour ramp: deep rim → saturated blue body → hot white-blue highlights. The
	// hot term keys off both the field and the ring shells so the spiral arms flash
	// near-white, blooming into the soft halo the target shows around the portal.
	vec3 col = mix(rim_color, body_color, clamp(energy_field * 2.0, 0.0, 1.0));
	float hot = clamp((energy_field - 0.42) * 2.4 + rings * band * 0.7, 0.0, 1.0);
	col = mix(col, core_color, hot);

	// Dark unstable hole — a LARGE near-black eye in the dead centre (the target's
	// defining "black hole inside the storm"). Wide + deep so the ring + chevrons read
	// as a lit silhouette around it, not erased by a solid bright disc.
	// Soft, slightly turbulent eye edge: warp the hole boundary by the noise so the
	// dark centre churns rather than being a perfect disc.
	float hole_edge = hole_radius + (n - 0.5) * 0.06;
	float hole = 1.0 - smoothstep(hole_edge * 0.78, hole_edge * 1.1, r);
	col = mix(col, hole_color, hole);

	// Soft bloom halo just outside the bright band: a low, broad blue wash that decays
	// past the rim so the portal casts a glowing aura into the surrounding dark — the
	// target's bloom-ringed event horizon.
	float halo = (1.0 - smoothstep(ring_peak, rim_fade + 0.25, r)) * smoothstep(hole_radius, ring_peak, r);
	col += body_color * halo * 0.45;

	// Luminance: low floor (deep rim stays dim) with a strong multiplier on the energy
	// so the bright churn blooms past the glow threshold, plus an extra punch on the
	// hot spiral arms. Higher overall gain so the disc fills the ring with light.
	float lum = energy * (0.12 + energy_field * energy_field * 2.1 + hot * 1.5);
	lum *= (1.0 - hole * 0.98);
	ALBEDO = col * lum;
	ALPHA = 1.0;
}
