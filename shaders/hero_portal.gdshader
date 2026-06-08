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

	// CARTESIAN swirled texture sampling. Polar (angle,radius) sampling — used for 44
	// prior iterations — inherently stretches the noise into concentric bands (cells tiny
	// at the centre, huge at the rim) which the eye reads as rings / a spiral comma. The
	// target plasma is ISOTROPIC churning cells of roughly equal size everywhere, slowly
	// rotating about a small dark eye. So sample the texture in the FLAT plane instead,
	// with a gentle radius-dependent angular SWIRL applied to the sample coordinates and
	// the whole field rotating with spin. Domain-warp by a low-frequency texture read so
	// the cells boil/churn rather than rigidly rotate. Three octaves of progressively
	// finer cells give the dense filamentary turbulence that FILLS the disc as a sheet.
	float spin = t * spin_speed * 0.25;
	float tw = swirl * (1.0 - r) * 0.10 + spin;            // swirl shear: inner turns faster
	float cs = cos(tw);
	float sn = sin(tw);
	mat2 swrot = mat2(vec2(cs, sn), vec2(-sn, cs));
	vec2 suv = swrot * uv;                                 // swirled disc coords (-1..1)

	// Domain warp — read a coarse noise field and use it to nudge the sample point so the
	// cells slosh and reconnect over time (liquid churn, not rigid spin).
	float drift = t * flow_speed;
	vec2 w = vec2(
		texture(noise_tex, suv * (tex_scale * 0.5) + vec2(drift * 0.07, -drift * 0.05)).r,
		texture(noise_tex, suv * (tex_scale * 0.5) + vec2(-drift * 0.05, drift * 0.06) + 7.3).r) - 0.5;
	vec2 wuv = suv + w * warp_amount * 0.55;

	// Octave 1 — broad churn cells.
	vec2 puv1 = wuv * tex_scale + vec2(drift * 0.04, -drift * 0.03);
	float s1 = texture(noise_tex, puv1).r;
	// Octave 2 — mid filaments, counter-drifting so layers shear past each other.
	vec2 puv2 = wuv * (tex_scale * 2.3) + vec2(-drift * 0.06, drift * 0.05) + 3.1;
	float s2 = texture(noise_tex, puv2).r;
	// Octave 3 — fine sparkle breaking the body into turbulent beads.
	vec2 puv3 = wuv * (tex_scale * 5.1) + vec2(drift * 0.09, drift * 0.07) + 11.7;
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

	// Radial mask: a SMALL crushed-black EYE at the centre, energy FILLING the entire
	// aperture out to a soft rim. The target plasma is a near-solid luminous disc that is
	// HOTTEST just around the small dark eye and fades gently to the rim — NOT a donut
	// with a fat mid-band ring. So drop the outward midboost donut entirely: brightness
	// is highest near the eye (a CENTRE-WEIGHTED falloff) and the filaments ride on top
	// of a continuous fill base so the gaps glow blue instead of reading as black spokes.
	float inner = smoothstep(hole_radius * 0.5, hole_radius + 0.06, r);  // tight ramp out of the eye
	float outer = 1.0 - smoothstep(rim_fade - 0.30, rim_fade, r);        // soft fall toward rim
	float band  = clamp(inner * outer, 0.0, 1.0);

	// Centre-weighted brightness: hottest just outside the eye, decaying to the rim. This
	// is the target's "bright storm packed around a small dark eye, dimming outward" — the
	// opposite of the prior mid-radius donut that read as a glowing ring with a black hole.
	float coreglow = exp(-pow((r - (hole_radius + 0.04)) / 0.42, 2.0));
	// Energy field: a STRONG continuous fill (so the whole disc is a luminous plasma sheet,
	// no black gaps reading as radial spokes) with the texture filaments adding churn on
	// top. Centre-weighting concentrates the heat around the eye.
	float raw = (0.42 + fil * 0.85) * band * (0.55 + coreglow * 1.0);
	float energy_field = pow(clamp(raw, 0.0, 1.0), 1.1);
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
	float hole_edge = hole_radius + (n - 0.5) * 0.06;
	float hole = 1.0 - smoothstep(hole_edge * 0.55, hole_edge * 1.0, r);
	col = mix(col, hole_color, hole);

	// Luminance: low floor (deep rim stays dim) with a strong multiplier on the energy
	// so the bright churn blooms past the glow threshold, plus an extra punch on the
	// hot spiral arms. The gain is tempered so the churning RING blooms while the dark
	// eye stays crushed — no solid white core. The hole mask hard-darkens the centre.
	float lum = energy * (0.18 + energy_field * energy_field * 1.5 + hot * 1.1);
	lum *= (1.0 - hole);
	ALBEDO = col * lum;
	ALPHA = 1.0;
}
