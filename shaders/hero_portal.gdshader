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

// TEXTURE-SAMPLED churn (skill hint: pure fBm read as a single comma arm across 44
// iterations). A tileable greyscale noise texture sampled TWICE in polar coords
// (radius + scrolled angle) at different scales gives dense filamentary turbulence
// that FILLS the disc — far closer to the reference plasma than fBm alone.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float tex_scale     : hint_range(0.5, 8.0)  = 2.4;    // angular tiling of the texture

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

	// POLAR texture sampling. The vortex is mapped into a (angle, radius) rectangle and
	// the tileable noise texture is read there, so the churn wraps seamlessly around the
	// disc instead of streaking across the middle. Angle scrolls with spin (the vortex
	// turns), radius scrolls INWARD with flow (energy drains toward the eye), and a swirl
	// term shears angle by radius so the filaments spiral gently into the throat. Two
	// octaves at different scales give dense, broad-to-fine filamentary turbulence that
	// FILLS the disc — the reference's churning plasma, not a single fBm comma.
	float swirl_a = ang / TAU + swirl * (1.0 - r) * 0.012 + t * spin_speed * 0.06;
	float drain_r = r - t * flow_speed * 0.30;

	// Octave 1 — broad churn (wraps in angle: x * tex_scale keeps tiling integer-friendly).
	vec2 puv1 = vec2(swirl_a * tex_scale, drain_r * 4.0);
	float s1 = texture(noise_tex, puv1).r;
	// Octave 2 — finer filaments, counter-scrolled so the two layers shear past each other.
	vec2 puv2 = vec2(swirl_a * tex_scale * 2.7 - t * 0.05, drain_r * 8.0 + t * flow_speed * 0.18);
	float s2 = texture(noise_tex, puv2).r;
	// Octave 3 — fine sparkle, fast, breaks the body into turbulent beads.
	vec2 puv3 = vec2(swirl_a * tex_scale * 5.9 + t * 0.09, drain_r * 14.0 - t * flow_speed * 0.10);
	float s3 = texture(noise_tex, puv3).r;

	// Combined turbulent value, contrast-stretched so filaments separate from dark gaps.
	// Multiply the octaves (not just sum) so a strand only lights where layers AGREE —
	// this carves sharp dark channels between bright filaments instead of a milky average.
	// The source texture is SOFT (luminance ~0.40-0.79), so a plain sum stays a flat grey.
	// Subtract a per-octave mid and SUM the signed deviations, then stretch hard — this
	// turns the gentle noise into high-contrast filaments with crushed dark channels.
	float d1 = s1 - 0.60;
	float d2 = s2 - 0.60;
	float d3 = s3 - 0.60;
	float n = 0.5 + (d1 * 1.4 + d2 * 1.1 + d3 * 0.7);
	n = clamp((n - 0.5) * 3.4 + 0.5, 0.0, 1.0);
	// Sharpen into filaments — high contrast churn with crushed gaps between strands.
	float fil = pow(n, 1.7);

	// Radial mask: a LARGE crushed-black EYE at the centre, energy filling the rest of
	// the aperture out to a soft rim. Unlike the old gaussian SHELL (which hollowed the
	// disc into a thin donut → the comma look), this is a broad PLATEAU so the plasma
	// fills the whole annulus from just outside the eye to the rim, matching the target.
	float inner = smoothstep(hole_radius, hole_radius + 0.12, r);  // 0 in eye, ramps up outside
	float outer = 1.0 - smoothstep(rim_fade - 0.26, rim_fade, r);  // soft fall toward rim
	float band  = clamp(inner * outer, 0.0, 1.0);

	// Energy field: texture-driven filaments DOMINATE, with a modest fill base so the
	// gaps between strands still glow faintly blue (a continuous plasma sheet, not bare
	// black between threads). A faint radial brightening toward ring_peak gives the
	// reference's slightly hotter mid-band without hollowing the disc.
	float midboost = 1.0 + 0.5 * exp(-pow((r - ring_peak) / 0.45, 2.0));
	float raw = (0.06 + fil * 1.15) * band * midboost;
	float energy_field = pow(clamp(raw, 0.0, 1.0), 1.2);
	float rings = fil;                                 // reused below for hot-arm flashes

	// Colour ramp: deep rim → saturated blue body → hot white-blue highlights. The
	// hot term keys off both the field and the ring shells so the spiral arms flash
	// near-white, blooming into the soft halo the target shows around the portal.
	vec3 col = mix(rim_color, body_color, clamp(energy_field * 2.0, 0.0, 1.0));
	float hot = clamp((energy_field - 0.42) * 2.4 + rings * band * 0.7, 0.0, 1.0);
	col = mix(col, core_color, hot);

	// Dark unstable hole — a LARGE near-black eye in the dead centre (the target's
	// defining "black hole inside the storm"). Wide + deep so the ring + chevrons read
	// as a lit silhouette around it, not erased by a solid bright disc. The eye boundary
	// is warped by the noise so the dark centre churns rather than being a perfect disc,
	// and it ramps across a wide span so there's a soft transition from black eye to the
	// surrounding storm — exactly the reference's unstable hole.
	float hole_edge = hole_radius + (n - 0.5) * 0.10;
	float hole = 1.0 - smoothstep(hole_edge * 0.70, hole_edge * 1.10, r);
	col = mix(col, hole_color, hole);

	// Luminance: low floor (deep rim stays dim) with a strong multiplier on the energy
	// so the bright churn blooms past the glow threshold, plus an extra punch on the
	// hot spiral arms. The gain is tempered so the churning RING blooms while the dark
	// eye stays crushed — no solid white core. The hole mask hard-darkens the centre.
	float lum = energy * (0.08 + energy_field * energy_field * 1.7 + hot * 1.2);
	lum *= (1.0 - hole);
	ALBEDO = col * lum;
	ALPHA = 1.0;
}
