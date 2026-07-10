shader_type sky;

// Alien planet sky — fully parametric so PlanetSky (scripts/planet_sky.gd) can
// roll a unique sky per planet from the spec seed, tuned per biome via
// data/skies.json:
//   * three-stop gradient (top / horizon / below-horizon ground haze)
//   * hash starfield (no texture; density + seed uniforms)
//   * up to 3 suns (disc + halo) — desert worlds love a binary pair
//   * up to 4 moons with crescent phase shading; a very large "moon" with
//     banding reads as a parent gas giant looming over the horizon
//   * planetary ring arc (great-circle band, banded alpha)
//   * aurora curtains (scrolling fbm, additive)

uniform vec3 top_color : source_color = vec3(0.18, 0.32, 0.58);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.74, 0.86);
uniform vec3 ground_color : source_color = vec3(0.35, 0.32, 0.28);

uniform float star_density : hint_range(0.0, 1.0) = 0.35;
uniform float star_seed = 7.0;

uniform int sun_count = 1;
uniform vec3 sun_dirs[3];
uniform vec3 sun_colors[3];
uniform float sun_sizes[3];

uniform int moon_count = 0;
uniform vec3 moon_dirs[4];
uniform vec3 moon_colors[4];
uniform float moon_sizes[4];
// xy = phase direction in disc space, z = banding strength (gas giant look)
uniform vec3 moon_phase_band[4];

uniform float ring_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ring_normal = vec3(0.25, 0.9, 0.0);
uniform vec3 ring_color : source_color = vec3(0.8, 0.75, 0.65);

uniform float aurora_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 aurora_color : source_color = vec3(0.2, 0.95, 0.55);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		v += amp * noise2(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// --- base gradient --------------------------------------------------
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.45));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	}

	// --- stars ------------------------------------------------------------
	if (up > 0.02 && star_density > 0.001) {
		vec3 cell = floor(dir * 220.0 + star_seed);
		float h = hash13(cell);
		float threshold = 1.0 - star_density * 0.035;
		if (h > threshold) {
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + hash13(cell + 3.0) * 3.0) + hash13(cell + 7.0) * 6.28);
			float star = smoothstep(threshold, 1.0, h) * tw;
			col += vec3(star) * clamp(up * 4.0, 0.0, 1.0);
		}
	}

	// --- planetary ring (great-circle band) --------------------------------
	if (ring_amount > 0.001) {
		float t = dot(dir, normalize(ring_normal));
		float band = 1.0 - smoothstep(0.0, 0.06, abs(t));
		if (band > 0.0 && up > -0.05) {
			// banded alpha across the ring's width + subtle grain along it
			float stripes = 0.6 + 0.4 * sin(t * 640.0);
			float horizon_fade = clamp((up + 0.05) * 8.0, 0.0, 1.0);
			col = mix(col, ring_color, band * stripes * ring_amount * 0.55 * horizon_fade);
		}
	}

	// --- moons (and gas-giant parents) --------------------------------------
	for (int i = 0; i < moon_count; i++) {
		vec3 md = normalize(moon_dirs[i]);
		float cosang = dot(dir, md);
		float ang = acos(clamp(cosang, -1.0, 1.0));
		float r = moon_sizes[i];
		if (ang < r) {
			// disc-space offset for phase + banding
			vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), md));
			vec3 north = normalize(cross(md, east));
			vec2 duv = vec2(dot(dir - md * cosang, east), dot(dir - md * cosang, north)) / r;
			float rim = 1.0 - smoothstep(0.82, 1.0, ang / r);
			// crescent: darken the half opposite the phase direction
			vec2 phase_dir = moon_phase_band[i].xy;
			float lit = clamp(0.55 + 0.6 * dot(normalize(duv + vec2(1e-4)), phase_dir), 0.08, 1.0);
			// gas-giant banding across the disc's north axis
			float banding = moon_phase_band[i].z;
			float bands = 1.0 - banding * (0.30 + 0.30 * sin(duv.y * 9.0 + star_seed));
			// faint surface mottling
			float mottle = 0.9 + 0.2 * noise2(duv * 5.0 + star_seed);
			vec3 mc = moon_colors[i] * lit * bands * mottle;
			col = mix(col, mc, rim);
		}
	}

	// --- suns ---------------------------------------------------------------
	for (int i = 0; i < sun_count; i++) {
		vec3 sd = normalize(sun_dirs[i]);
		float d = dot(dir, sd);
		float ang = acos(clamp(d, -1.0, 1.0));
		float r = sun_sizes[i];
		float disc = 1.0 - smoothstep(r * 0.82, r, ang);
		float halo = pow(clamp(d, 0.0, 1.0), 90.0) * 0.5;
		col += sun_colors[i] * (disc * 1.8 + halo);
	}

	// --- aurora curtains ------------------------------------------------------
	if (aurora_amount > 0.001 && up > 0.03) {
		vec2 p = dir.xz / max(up + 0.25, 0.12);
		float curtain = fbm2(p * 2.4 + vec2(TIME * 0.03, TIME * 0.011));
		curtain = smoothstep(0.52, 0.85, curtain);
		float height_band = smoothstep(0.03, 0.18, up) * (1.0 - smoothstep(0.45, 0.85, up));
		float flicker = 0.85 + 0.15 * sin(TIME * 0.7 + p.x * 3.0);
		col += aurora_color * curtain * height_band * aurora_amount * flicker * 0.8;
	}

	COLOR = col;
}
