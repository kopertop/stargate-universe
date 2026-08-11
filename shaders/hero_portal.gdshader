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

uniform float energy        : hint_range(0.0, 8.0) = 4.8;
uniform float swirl         : hint_range(0.0, 16.0) = 3.5;    // angular twist per radius (halved from 7.0: strong shear wrapped noise into tight concentric arcs/bullseye; gentler shear keeps one coherent rotating mass with soft spiral arms — nebula churn)
uniform float spin_speed                            = 0.35;   // whole-vortex rotation
uniform float flow_speed                            = 0.55;   // churn / drift rate
uniform float warp_amount   : hint_range(0.0, 2.0)  = 0.85;
uniform float detail                                = 4.0;    // base fBm frequency

// Radial annulus profile (in 0..1 disc radius). The bright churning band now
// spans most of the disc (peak pushed outward) with a clear dark centre, so the
// vortex reads as a LARGE energy mass filling the ring, not a small hot dot.
uniform float hole_radius   : hint_range(0.0, 0.7)  = 0.52;   // dark centre extent
uniform float ring_peak     : hint_range(0.1, 0.95) = 0.66;   // brightest band radius
uniform float rim_fade      : hint_range(0.6, 1.15) = 1.08;   // outer fade edge
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
	// CRITICAL FIX: do NOT clamp r to 1.0. The mesh is a SQUARE QuadMesh, so the corners
	// reach r≈1.41. Clamping r to 1.0 pinned the outer radial mask at full brightness all
	// the way into the corners, so the plasma filled the square and read as a flat frosted
	// rounded-SQUARE with a tiny dot (the persistent gap) — never a disc. Leaving r
	// unclamped lets the firm circular rim falloff below actually cut a round edge, so the
	// churning plasma is a true CIRCLE that fills the ring aperture with a soft bloom halo.
	float r = length(uv);
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
	// STRONG radial swirl shear so the cells streak into visible spiral filaments curving
	// around the eye (the target's churning vortex), not a static isotropic sparkle-ball.
	// Inner radii twist far more than the rim, sweeping the texture into flowing arcs.
	float tw = swirl * (1.0 - r) * 0.42 + spin;            // swirl shear: inner turns faster
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

	// Combined turbulent value. Bias toward FLOWING strands rather than sparkly beads:
	// the broad+mid octaves carry most of the weight (they read as sweeping plasma
	// filaments curved by the swirl shear), and the fine octave only lightly breaks up
	// the body so it shimmers without dissolving into snow. The source texture is SOFT
	// (luminance ~0.40-0.79); subtract a per-octave mid and stretch so strands separate
	// from the dark gaps, but with a GENTLER stretch + lower gamma than prior iterations
	// so the disc reads as continuous churning plasma, not isolated white grains.
	float d1 = s1 - 0.55;
	float d2 = s2 - 0.57;
	float d3 = s3 - 0.60;
	float n = 0.5 + (d1 * 1.9 + d2 * 1.15 + d3 * 0.5);
	// HIGHER contrast stretch so the turbulent field separates into bright flowing strands
	// with genuinely DARK channels between them — the persistent gap was a uniform pale disc
	// with no visible churn (the noise averaged out to flat grey). A steeper stretch + gamma
	// carves the filaments so the eye reads moving plasma, not frosted glass.
	n = clamp((n - 0.5) * 3.2 + 0.5, 0.0, 1.0);
	// Filament shaping — gamma > 1 darkens the mid-grey gaps so only the strand crests stay
	// bright, giving the dense filamentary churn that fills the disc.
	float fil = pow(n, 1.7);

	// Radial mask. The target event horizon is a CHURNING BLUE plasma disc with a
	// clearly DARK unstable eye and a defined circular outer edge that blooms into a
	// soft halo — NOT a diffuse white sparkle-ball that fills the frame edge-to-edge.
	// Two changes vs. prior iterations that made it read as a "snowball":
	//   1. A FIRM circular rim falloff (steep outer smoothstep) so the disc has a real
	//      edge — the bloom halo comes from the edge being bright, not from a fuzzy fade.
	//   2. The eye is wider + the transition out of it is gentle, so a big near-black
	//      centre dominates the middle of the ring (the reference's defining feature).
	// SMALL noise-warped eye — the target's defining dark unstable centre is a compact
	// churning throat, not a wide hole. A gentle ramp out of it keeps the surrounding
	// plasma reaching almost to the centre.
	float eye_r = hole_radius * (0.85 + (n - 0.5) * 0.25);
	float inner = smoothstep(eye_r * 0.4, eye_r, r);
	// Outer fade — plasma stays at FULL brightness across the disc then drops at a defined
	// circular edge near the rim, so the churning blue sheet fills the aperture right up to
	// the ring's inner lip (the target) and the bloom comes from that bright edge — NOT a
	// soft early fade that hollows the disc into a dim halo well inside the ring.
	float outer = 1.0 - smoothstep(rim_fade - 0.12, rim_fade + 0.04, r);
	float band  = clamp(inner * outer, 0.0, 1.0);

	// Brightness FILLS the whole aperture evenly — a near-flat radial weight so the plasma
	// is a continuous churning sheet from just outside the eye to the rim, NOT a hot annulus.
	// Lifted to a true flat fill (no mid-radius hump) and biased UP toward the rim so the
	// blue plasma reaches all the way to the ring's inner edge — the prior weight let the
	// disc fall off well inside the aperture, leaving a hollow grey gap between the bright
	// core and the ring (the render's persistent "small ball in a big grey hole" read).
	float fill_weight = 1.0 + 0.18 * smoothstep(0.2, 0.95, r);
	// Energy field: a strong base fill so the ENTIRE disc glows blue out to the rim, with the
	// flowing filaments modulating brightness on top. The small eye stays dark; everything
	// outside it is lit plasma reaching the rim — the target's full-aperture churning horizon.
	// LOW base floor + strong filament term: the dark channels between strands actually go
	// dark (no more uniform pale fill), and the bright flowing filaments carry the energy.
	// This is what turns the flat frosted disc into churning plasma.
	float raw = (0.55 + fil * 0.7) * band * fill_weight;
	float energy_field = pow(clamp(raw, 0.0, 1.0), 1.0);
	float rings = fil;                                 // reused below for hot-arm flashes

	// Colour ramp: deep blue rim → saturated blue body → cool white-blue highlights. The
	// hot (white) term is held BACK HARD so the disc stays predominantly BLUE (the reference
	// is blue plasma, not a white snowball) — only the very brightest, sparsest churn
	// filaments flash near white. The body fills out as saturated blue first; white is
	// reserved for the thin crests of the turbulent strands.
	vec3 col = mix(rim_color, body_color, clamp(energy_field * 2.4, 0.0, 1.0));
	// Hot crests: gated to ONLY the top fraction of filament brightness AND high energy, then
	// cubed, so white appears as sparse sparkle on strand peaks rather than washing the body.
	float crest = smoothstep(0.78, 0.98, fil);
	float hot = clamp((energy_field - 0.74) * 1.6, 0.0, 1.0) * crest;
	hot = hot * hot * hot;                             // sharply bias toward the very brightest only
	col = mix(col, core_color, hot * 0.85);

	// Dark unstable hole — a SMALL near-black eye in the dead centre (the target's
	// defining "black hole inside the storm"). Compact so the plasma dominates the disc,
	// with a noise-warped edge so the throat churns rather than reading as a perfect disc.
	float hole = 1.0 - smoothstep(eye_r * 0.5, eye_r * 1.1, r);
	col = mix(col, hole_color, hole);

	// Luminance: a moderate body brightness so the blue plasma reads as a luminous churning
	// sheet WITHOUT the whole disc clipping to white past the bloom threshold (the persistent
	// "blown-out snowball" gap). The energy_field term is now LINEAR-ish (gentle square) and
	// scaled down, so the disc holds its saturated blue; only the sparse hot crests punch
	// bright enough to bloom into the soft halo. The crushed eye stays black.
	// FILAMENT-DRIVEN luminance: brightness rides mostly on the carved filament term so the
	// strands clip bright (and bloom into the halo) while the channels between them stay dim
	// blue — the difference that turns a uniform pale disc into churning plasma. The flat
	// body floor is small; fil drives the structure.
	float body_lum = 0.30 + energy_field * 0.8 + fil * fil * 0.9;
	float lum = energy * (body_lum + hot * 1.4);
	lum *= (1.0 - hole);
	// Hard circular cut: zero everything past the disc edge so the square QuadMesh corners
	// carry NO energy (step replaces the disallowed early-return — `return` is illegal in the
	// fragment processor in Godot's shading language and silently fails the whole shader).
	lum *= step(r, 1.05);
	ALBEDO = col * lum;
	ALPHA = 1.0;
}
