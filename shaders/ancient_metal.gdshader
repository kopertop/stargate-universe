shader_type spatial;

// Ancient-metal — procedural triplanar PBR for the game's hero props.
//
// Reference: design/concept-art/materials/ancient-metal-pbr-sheet.png
// (dark weathered steel, beveled rectangular panels, inset seam traces,
// fine scratches, optional glowing seams that drive the gate's amber/orange
// chevron light).
//
// Why triplanar: the hero meshes (Stargate ring/chevrons, control pillar,
// console body) are procedural primitives with engine-generated UVs that
// can't cleanly tile a panel texture. We sample everything in WORLD space and
// blend by the world-normal weights, so one material drops onto any prop and
// panel_scale stays consistent regardless of mesh scale. See shaders/AGENTS.md.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// --- Look uniforms ---------------------------------------------------------
uniform vec4 albedo_tint : source_color = vec4(0.18, 0.17, 0.20, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.38;

// Panel grid, in WORLD units (a panel is panel_scale metres on a side).
uniform float panel_scale = 0.85;
uniform float seam_width : hint_range(0.0, 0.5) = 0.06;
uniform float seam_depth : hint_range(0.0, 1.0) = 0.65;

// Edge wear: noise-thresholded lightening + roughening along raised panel edges.
uniform float wear_amount : hint_range(0.0, 1.0) = 0.35;

// Fine detail set (one shared normal+roughness texture, triplanar-sampled).
uniform float detail_scale = 1.7;
uniform sampler2D detail_normal : hint_normal;
uniform sampler2D detail_rough : hint_default_white;
uniform float detail_normal_strength : hint_range(0.0, 2.0) = 0.6;

// Triplanar projection blend sharpness (higher = harder seams between axes).
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;

// Emission — the glowing seams give the gate its amber/orange rim light.
uniform vec4 emission_color : source_color = vec4(0.32, 0.20, 0.10, 1.0);
uniform float emission_energy = 0.0;
uniform float seam_emission = 0.0;

// World-space position + normal handed to fragment for triplanar sampling.
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Per-axis blend weights from the world normal.
vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	return w / max(w.x + w.y + w.z, 1e-4);
}

// Triplanar sample of a plain (non-normal) texture: project onto the 3 planes
// and blend by weights. Returns the .x channel (roughness/scratch grain).
float triplanar_scalar(sampler2D tex, vec3 pos, vec3 w, float scale) {
	float x = texture(tex, pos.yz * scale).x;
	float y = texture(tex, pos.zx * scale).x;
	float z = texture(tex, pos.xy * scale).x;
	return x * w.x + y * w.y + z * w.z;
}

// Triplanar tangent-space normal blend (whiteout technique). Each plane's
// tangent-space normal is reoriented to point along the surface normal, then
// the three are blended by the triplanar weights.
vec3 triplanar_normal(sampler2D tex, vec3 pos, vec3 wn, vec3 w, float scale, float strength) {
	vec3 nx = texture(tex, pos.yz * scale).xyz * 2.0 - 1.0;
	vec3 ny = texture(tex, pos.zx * scale).xyz * 2.0 - 1.0;
	vec3 nz = texture(tex, pos.xy * scale).xyz * 2.0 - 1.0;
	nx.xy *= strength;
	ny.xy *= strength;
	nz.xy *= strength;
	// Whiteout blend: push the detail's xy into the geometric normal's plane.
	vec3 wsign = sign(wn);
	vec3 axis_x = vec3(wn.x, nx.z * wsign.x + wn.x, nx.y);
	vec3 nrm_x = vec3(nx.xy + wn.zy, abs(nx.z) * wn.x);
	vec3 nrm_y = vec3(ny.xy + wn.xz, abs(ny.z) * wn.y);
	vec3 nrm_z = vec3(nz.xy + wn.xy, abs(nz.z) * wn.z);
	vec3 blended =
		nrm_x.zyx * w.x +
		nrm_y.xzy * w.y +
		nrm_z.xyz * w.z;
	return normalize(blended);
}

// Cheap value noise on a world-space coordinate (for wear thresholding).
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

// Distance to the nearest panel seam, in [0,1] panel-cell space. Returns a
// 0..1 mask that is 1 deep in the seam and 0 on the panel face.
float seam_mask(vec2 cell) {
	vec2 g = abs(fract(cell) - 0.5);     // 0 at centre, 0.5 at the seam edge
	vec2 edge = vec2(0.5 - seam_width);
	vec2 m = smoothstep(edge, vec2(0.5), g);
	return max(m.x, m.y);
}

void fragment() {
	vec3 w = triplanar_weights(v_world_normal);
	vec3 wpos = v_world_pos;

	// --- Panel grid: pick the dominant projection plane for the cell coords so
	// the rectangular panels stay axis-aligned on each face. ---
	vec2 cell_x = wpos.yz / panel_scale;
	vec2 cell_y = wpos.zx / panel_scale;
	vec2 cell_z = wpos.xy / panel_scale;
	float seam = seam_mask(cell_x) * w.x + seam_mask(cell_y) * w.y + seam_mask(cell_z) * w.z;

	// --- Edge wear: noise gates where bare metal shows on raised panel edges. ---
	float wear_n = value_noise(wpos.xz * (1.0 / panel_scale) * 2.0 + wpos.y);
	float panel_edge = smoothstep(0.5 - seam_width * 2.0, 0.5 - seam_width, seam);
	float wear = wear_amount * panel_edge * smoothstep(0.4, 0.8, wear_n);

	// --- Fine detail (scratch grain) ---
	float grain = triplanar_scalar(detail_rough, wpos, w, detail_scale);

	// --- Albedo: tint, darken in seams, lighten on worn edges. ---
	vec3 base = albedo_tint.rgb;
	base *= mix(1.0, 0.45, seam * seam_depth);          // recessed seams read dark
	base = mix(base, base * 1.6, wear);                  // worn edges show brighter metal
	ALBEDO = base;

	// --- Metallic / roughness ---
	METALLIC = metallic * (1.0 - seam * 0.25);
	float rough = roughness_base;
	rough = mix(rough, clamp(rough + 0.25, 0.0, 1.0), seam * seam_depth);  // seams rougher
	rough = mix(rough, clamp(rough + 0.35, 0.0, 1.0), wear);                // wear rougher
	rough = mix(rough, grain, 0.25);                                        // scratch grain
	ROUGHNESS = clamp(rough, 0.04, 1.0);

	// --- Normal: triplanar detail normal + a beveled push out of the seams. ---
	NORMAL_MAP = triplanar_normal(
		detail_normal, wpos, v_world_normal, w, detail_scale, detail_normal_strength
	) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0 + seam * seam_depth * 1.5;

	// --- Emission: constant tint plus glowing seams (gate chevron light). ---
	vec3 emit = emission_color.rgb * emission_energy;
	emit += emission_color.rgb * seam * seam_emission;
	EMISSION = emit;
}
