shader_type spatial;

// Event horizon — the active Stargate "puddle".
//
// Replaces the flat additive disc with an animated energy surface: two layers
// of scrolling/swirling noise, a Fresnel rim that brightens at grazing angles,
// and a slow radial pulse. Additive + unshaded so it glows regardless of scene
// lighting; the OmniLight3D spill is still driven from stargate.gd.
//
// Reference: design/concept-art/materials/ancient-metal-pbr-sheet.png (the cyan
// puddle in the stargate segment).

render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 core_color : source_color = vec4(0.32, 0.84, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.62, 0.95, 1.0, 1.0);
uniform float energy : hint_range(0.0, 6.0) = 2.6;
uniform float swirl_speed = 0.35;
uniform float noise_scale = 3.5;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;

varying vec3 v_local;
varying vec3 v_view_normal;

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
	v_view_normal = NORMAL;
}

void fragment() {
	// The disc is a flat cylinder rotated onto the gate's Z axis: its xz plane
	// is the puddle face. Use local xz as the surface coordinate.
	vec2 uv = v_local.xz;
	float t = TIME * swirl_speed;
	// Normalised radius (0 centre, 1 rim) — disc local half-extent ~2.32.
	float r = clamp(length(uv) / 2.32, 0.0, 1.0);

	// Twist the sample coords by radius+time so the churn spirals into a VORTEX
	// (the reference puddle swirls toward the centre) instead of flat plasma.
	float a = t + r * 5.0;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	vec2 suv = rot * uv;
	float n1 = value_noise(suv * noise_scale + vec2(t, -t * 0.6));
	float n2 = value_noise(suv * (noise_scale * 1.9) - vec2(t * 0.7, t));
	float churn = mix(n1, n2, 0.5);

	// Radial profile: a dim hole at the centre, a bright churning body, and a
	// hot rim that lights the inside of the ring (matches the reference).
	float body = smoothstep(0.04, 0.36, r);
	float rim = smoothstep(0.74, 1.0, r);
	float radial = body * (1.0 - 0.45 * smoothstep(0.88, 1.0, r)) + rim * 0.9;
	float pulse = 0.5 + 0.5 * sin(TIME * 1.2 - r * 7.0);

	// NOTE: a real view-fresnel is useless on this flat disc (the cap normal is
	// perpendicular to the view dir in local space, so it's constant) — it just
	// flat-lifts the whole puddle and erases the dark vortex hole. Structure comes
	// from the radial profile + churn instead.
	vec3 col = mix(core_color.rgb, rim_color.rgb, clamp(churn * 0.55 + r * 0.5 + rim, 0.0, 1.0));
	float intensity = (0.22 + churn * 0.62) * radial * (0.82 + pulse * 0.18);
	// render_mode is `unshaded`, so the final colour is ALBEDO — EMISSION is
	// ignored. Drive the full HDR brightness through ALBEDO so `energy` actually
	// scales the glow (and the env glow buffer blooms it).
	ALBEDO = col * energy * intensity;
	EMISSION = col * energy * intensity;
	ALPHA = clamp(0.40 + churn * 0.4 + radial * 0.3, 0.0, 1.0);
}
