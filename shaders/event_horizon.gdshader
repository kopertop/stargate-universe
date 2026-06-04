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

	// Two counter-rotating noise layers give a churning energy look.
	float n1 = value_noise(uv * noise_scale + vec2(t, -t * 0.6));
	float n2 = value_noise(uv * (noise_scale * 1.8) - vec2(t * 0.7, t));
	float churn = mix(n1, n2, 0.5);

	// Radial pulse outward from the centre.
	float r = length(uv);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.4 - r * 6.0);

	// Fresnel rim — brighter where the surface faces away from the camera.
	float fres = pow(1.0 - clamp(dot(normalize(v_view_normal), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), fresnel_power);

	vec3 col = mix(core_color.rgb, rim_color.rgb, clamp(churn * 0.7 + fres, 0.0, 1.0));
	float intensity = (0.55 + churn * 0.45) * (0.7 + pulse * 0.3) + fres * 0.6;
	EMISSION = col * energy * intensity;
	ALBEDO = col;
	ALPHA = clamp(0.55 + churn * 0.35 + fres * 0.3, 0.0, 1.0);
}
