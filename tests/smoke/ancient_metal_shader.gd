extends SceneTree

# Smoke test for the Ancient-metal triplanar shader + the event-horizon shader
# (issue #30). Headless cannot compile GLSL (the dummy renderer is used), but it
# CAN verify every resource loads, the shaders parse without error, the
# ShaderMaterial variants bind the shader + detail textures + expected uniforms,
# and that objects/stargate.gd actually applies the new ShaderMaterials to the
# ring / band / chevron meshes (instead of the old StandardMaterial3D).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/ancient_metal_shader.gd

const SHADER_PATH: String = "res://shaders/ancient_metal.gdshader"
const HORIZON_SHADER_PATH: String = "res://shaders/event_horizon.gdshader"
const DETAIL_NORMAL: String = "res://textures/ancient-metal/detail_normal.tres"
const DETAIL_ROUGH: String = "res://textures/ancient-metal/detail_rough.tres"
const RING_MAT: String = "res://shaders/ancient_metal_ring.tres"
const BAND_MAT: String = "res://shaders/ancient_metal_band.tres"
const CHEVRON_MAT: String = "res://shaders/ancient_metal_chevron.tres"
const HORIZON_MAT: String = "res://shaders/event_horizon.tres"
const REFERENCE_IMAGE: String = "res://design/concept-art/materials/ancient-metal-pbr-sheet.png"

# Uniforms the ancient_metal shader must expose for the .tres variants to tune.
const EXPECTED_UNIFORMS: Array[String] = [
	"albedo_tint", "metallic", "roughness_base", "panel_scale", "seam_width",
	"seam_depth", "wear_amount", "detail_scale", "triplanar_sharpness",
	"emission_color", "emission_energy", "seam_emission",
	"detail_normal", "detail_rough",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== ancient_metal_shader smoke test ===")

	_test_reference_image_committed()
	_test_detail_textures_seamless()
	_test_shader_parses()
	_test_horizon_shader_parses()
	_test_material_variants()
	# SceneTree-script _initialize runs BEFORE the first frame, so a node's
	# _ready() is queued, not synchronous. Defer the Stargate check until frames
	# flow (matches scene_boot.gd). await process_frame deadlocks here.
	call_deferred("_run_node_checks")


func _run_node_checks() -> void:
	await _test_stargate_applies_shader_materials()
	_report()


# --- The concept reference must be tracked + importable. -------------------
func _test_reference_image_committed() -> void:
	_expect(ResourceLoader.exists(REFERENCE_IMAGE),
		"reference image committed + imported (%s)" % REFERENCE_IMAGE)


# --- Detail set: seamless NoiseTexture2D resources, normal flagged. --------
func _test_detail_textures_seamless() -> void:
	var dn: Resource = load(DETAIL_NORMAL)
	var dr: Resource = load(DETAIL_ROUGH)
	_expect(dn is NoiseTexture2D, "detail_normal is a NoiseTexture2D")
	_expect(dr is NoiseTexture2D, "detail_rough is a NoiseTexture2D")
	if dn is NoiseTexture2D:
		_expect((dn as NoiseTexture2D).seamless, "detail_normal is seamless")
		_expect((dn as NoiseTexture2D).as_normal_map, "detail_normal is flagged as_normal_map")
	if dr is NoiseTexture2D:
		_expect((dr as NoiseTexture2D).seamless, "detail_rough is seamless")


# --- The shader resource loads + parses (non-empty code, valid mode). ------
func _test_shader_parses() -> void:
	var sh: Resource = load(SHADER_PATH)
	_expect(sh is Shader, "ancient_metal.gdshader loads as a Shader")
	if not (sh is Shader):
		return
	var shader: Shader = sh as Shader
	_expect(shader.code.length() > 0, "shader has source code")
	_expect(shader.get_mode() == Shader.MODE_SPATIAL, "shader is a spatial shader")
	# get_shader_uniform_list exposes every parsed uniform; a parse error yields
	# an empty list. Verify the full uniform surface the .tres variants drive.
	var names: Dictionary = {}
	for u in shader.get_shader_uniform_list():
		names[String(u.get("name", ""))] = true
	for want in EXPECTED_UNIFORMS:
		_expect(names.has(want), "shader exposes uniform '%s'" % want)


func _test_horizon_shader_parses() -> void:
	var sh: Resource = load(HORIZON_SHADER_PATH)
	_expect(sh is Shader, "event_horizon.gdshader loads as a Shader")
	if not (sh is Shader):
		return
	var shader: Shader = sh as Shader
	_expect(shader.code.length() > 0, "event_horizon shader has source code")
	_expect(shader.get_mode() == Shader.MODE_SPATIAL, "event_horizon is a spatial shader")
	var names: Dictionary = {}
	for u in shader.get_shader_uniform_list():
		names[String(u.get("name", ""))] = true
	# Vortex rewrite (#30) renamed the controls: rim_color→edge_color,
	# swirl_speed→swirl, fresnel_power→warp_amount/detail/spin_speed.
	for want in ["core_color", "edge_color", "energy", "swirl", "spin_speed"]:
		_expect(names.has(want), "event_horizon exposes uniform '%s'" % want)


# --- The four ShaderMaterial .tres variants reference the shader + bind the
#     detail textures + the per-part uniforms. -------------------------------
func _test_material_variants() -> void:
	var ametal_shader: Resource = load(SHADER_PATH)
	for path in [RING_MAT, BAND_MAT, CHEVRON_MAT]:
		var res: Resource = load(path)
		_expect(res is ShaderMaterial, "%s loads as a ShaderMaterial" % path)
		if not (res is ShaderMaterial):
			continue
		var mat: ShaderMaterial = res as ShaderMaterial
		_expect(mat.shader == ametal_shader, "%s points at ancient_metal.gdshader" % path)
		_expect(mat.get_shader_parameter("detail_normal") is Texture2D,
			"%s binds a detail_normal texture" % path)
		_expect(mat.get_shader_parameter("detail_rough") is Texture2D,
			"%s binds a detail_rough texture" % path)
		# panel_scale is in world units — must be a positive value.
		_expect(float(mat.get_shader_parameter("panel_scale")) > 0.0,
			"%s has a positive panel_scale" % path)

	var horizon_res: Resource = load(HORIZON_MAT)
	_expect(horizon_res is ShaderMaterial, "event_horizon.tres loads as a ShaderMaterial")
	if horizon_res is ShaderMaterial:
		_expect((horizon_res as ShaderMaterial).shader == load(HORIZON_SHADER_PATH),
			"event_horizon.tres points at event_horizon.gdshader")


# --- Stargate must apply the ShaderMaterials, not StandardMaterial3D. -------
func _test_stargate_applies_shader_materials() -> void:
	var packed: Resource = load("res://objects/stargate.tscn") if ResourceLoader.exists("res://objects/stargate.tscn") else null
	var gate: Node3D
	if packed is PackedScene:
		gate = (packed as PackedScene).instantiate() as Node3D
	else:
		# Stargate is built in code from a script; instance directly.
		var script: Resource = load("res://objects/stargate.gd")
		_expect(script != null, "objects/stargate.gd loads")
		if script == null:
			return
		gate = Node3D.new()
		gate.set_script(script)
	root.add_child(gate)
	# Now a frame has ticked, _ready fired and built the meshes; settle one more.
	await process_frame
	var ring: MeshInstance3D = gate.get_node_or_null("OuterRing") as MeshInstance3D
	var band: MeshInstance3D = gate.get_node_or_null("GlyphBand") as MeshInstance3D
	_expect(ring != null and ring.material_override is ShaderMaterial,
		"OuterRing uses a ShaderMaterial override")
	_expect(band != null and band.material_override is ShaderMaterial,
		"GlyphBand uses a ShaderMaterial override")
	# Chevron bracket sits under a Chevron0 pivot.
	var bracket: MeshInstance3D = gate.get_node_or_null("Chevron0/Bracket") as MeshInstance3D
	_expect(bracket != null and bracket.material_override is ShaderMaterial,
		"Chevron bracket uses a ShaderMaterial override")
	# Event horizon swapped to the energy-surface shader.
	var horizon: MeshInstance3D = gate.get_node_or_null("EventHorizon") as MeshInstance3D
	_expect(horizon != null and horizon.material_override is ShaderMaterial,
		"EventHorizon uses a ShaderMaterial override")
	root.remove_child(gate)
	gate.free()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
