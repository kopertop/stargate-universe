shader_type spatial;

// Issue #30 — Ancient-metal PBR shader for hero props (Stargate slice first).
//
// This is the player-facing PBR shader for the Stargate hero slice: a metallic
// surface with weathering (edge wear, scratches, panel seams, and optional
// glowing seam emission). It is the simplified, drop-in PBR companion to
// shaders/ancient_metal.gdshader — same look language (dark weathered steel,
// beveled rectangular panels, inset seam traces, fine scratches, glowing
// seams) but a leaner uniform surface tuned for the Stargate ring/chevron
// slice so it drops onto the hero prop in one shot.
//
// Why triplanar: the hero meshes are procedural primitives with
// engine-generated UVs that can't cleanly tile a panel texture. We sample in
// WORLD space and blend by the world-normal weights, so one material drops
// onto any prop and panel_scale stays consistent regardless of mesh scale.
//
// Headless note: Godot's dummy renderer cannot compile GLSL — the smoke test
// verifies the shader parses (non-empty code, spatial mode, expected uniforms
// present via get_shader_uniform_list). Real-renderer validation is the
// capture in tests/shots/capture.sh gate-room.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ── Look uniforms ───────────────────────────────────────────────────────────
// Base albedo tint — dark weathered steel.
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

// Rivets (studs at panel corners) + per-panel tone variation — the signature
// Ancient-metal "riveted plates" read.
uniform float rivet_amount : hint_range(0.0, 1.0) = 0.7;
uniform float rivet_radius : hint_range(0.02, 0.25) = 0.13;
uniform float panel_variation : hint_range(0.0, 0.5) = 0.16;

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
	nx = mix(vec3(0.0, 0.0, 1.0), nx, strength);
	ny = mix(vec3(0.0, 0.0, 1.0), ny, strength);
	nz = mix(vec3(0.0, 0.0, 1.0), nz, strength);
	// Reorient each tangent-space normal to its plane.
	nx = vec3(nx.x * wn.y, nx.y * wn.z, nx.z * -wn.x);
	ny = vec3(ny.x * -wn.z, ny.y * wn.x, ny.z * -wn.y);
	nz = vec3(nz.x * wn.x, nz.y * wn.y, nz.z * wn.z);
	vec3 blended = nx * w.x + ny * w.y + nz * w.z;
	return normalize(blended);
}

// Panel seam mask: 1.0 at panel borders, 0.0 in the panel interior. Drives the
// recessed seam read + the glowing seam emission.
float panel_seam_mask(vec3 pos, float scale, float width) {
	vec3 p = pos * (1.0 / scale);
	vec3 f = abs(fract(p) - 0.5);
	float d = min(min(f.x, f.y), f.z);
	// d in [0, 0.5]; 0 at panel centre, 0.5 at the border. Seam = near border.
	return 1.0 - smoothstep(width, width * 2.0, d);
}

// Rivet mask: small round studs at the panel corners (every panel_scale).
float rivet_mask(vec3 pos, float scale, float radius) {
	vec3 p = pos * (1.0 / scale);
	vec3 f = fract(p) - 0.5;
	// Corner offset so studs sit near the panel corners.
	vec3 c = sign(f) * 0.5;
	float d = length(f - c * 0.5);
	return 1.0 - smoothstep(radius, radius * 1.5, d);
}

// Hash + value noise for per-panel tone variation and edge wear.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void fragment() {
	vec3 wn = normalize(v_world_normal);
	vec3 w = triplanar_weights(wn);
	vec3 pos = v_world_pos;

	// Panel seam + rivet masks (triplanar-blended across the 3 planes).
	float seam = panel_seam_mask(pos, panel_scale, seam_width);
	float rivet = rivet_mask(pos, panel_scale, rivet_radius) * rivet_amount;

	// Per-panel tone variation — the "riveted plates" read.
	float panel_id = floor(pos.x / panel_scale) + floor(pos.y / panel_scale) * 17.0 + floor(pos.z / panel_scale) * 31.0;
	float variation = (hash13(vec3(panel_id)) - 0.5) * 2.0 * panel_variation;

	// Detail normal + roughness (triplanar).
	vec3 dn = triplanar_normal(detail_normal, pos, wn, w, detail_scale, detail_normal_strength);
	float dr = triplanar_scalar(detail_rough, pos, w, detail_scale);

	// Edge wear: lighten + roughen near raised panel borders and rivets.
	float wear = clamp(seam * wear_amount + rivet * wear_amount * 0.5, 0.0, 1.0);

	// Compose albedo: tint + per-panel variation, darkened at seams (recessed).
	vec3 albedo = albedo_tint.rgb * (1.0 + variation);
	albedo *= 1.0 - seam * seam_depth * 0.3;
	albedo = mix(albedo, albedo * 1.3, wear);  // edges lighten with wear

	// Roughness: base + detail, raised at seams (recessed = rougher) and by wear.
	float rough = clamp(roughness_base + dr * 0.3 + seam * seam_depth * 0.2 + wear * 0.25, 0.0, 1.0);

	// Metallic: base, slightly reduced at heavy wear (exposed base metal reads
	// less metallic than the weathered surface).
	float metal = clamp(metallic - wear * 0.15, 0.0, 1.0);

	// Emission: glowing seams (the gate's amber rim light).
	float seam_glow = seam * seam_emission;
	vec3 emission = emission_color.rgb * (seam_glow + rivet * seam_emission * 0.3) * emission_energy;

	// Output PBR.
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = dn;
	NORMAL_MAP_BLEND = 0.0;  // full replace (triplanar already reoriented)
	EMISSION = emission;
}