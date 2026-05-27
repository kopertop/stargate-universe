class_name FtlDrop
extends CanvasLayer

# One-shot "dropped out of FTL" screen effect: a full-screen box-blur of the
# world that ramps up fast then eases back to clear over ~1.6 s, plus an
# FTL-cut sound. Self-animates and self-frees.
#
# Sits on layer 5 — below HUDLayer (10) — so it blurs the 3D world but leaves
# the HUD / dialog window (where Brody's line shows) crisp and readable.
# PROCESS_MODE_ALWAYS so it animates even while a dialog has the tree paused.

const DURATION: float = 1.6
const RAMP_FRAC: float = 0.18  # fraction of DURATION spent ramping blur in
const MAX_BLUR_PX: float = 3.0
# Placeholder FTL-drop cue (glitchy cut). Swap for a dedicated whoom later.
const FTL_SOUND: String = "res://sounds/flicker.ogg"

var _t: float = 0.0
var _rect: ColorRect = null

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _make_material()
	add_child(_rect)
	Audio.play(FTL_SOUND)

func _process(delta: float) -> void:
	_t += delta
	if _rect != null and _rect.material is ShaderMaterial:
		(_rect.material as ShaderMaterial).set_shader_parameter("intensity", _envelope(_t / DURATION))
	if _t >= DURATION:
		queue_free()

# 0 → 1 over the first RAMP_FRAC, then ease back to 0 across the remainder.
func _envelope(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x < RAMP_FRAC:
		return x / RAMP_FRAC
	return clampf(1.0 - (x - RAMP_FRAC) / (1.0 - RAMP_FRAC), 0.0, 1.0)

func _make_material() -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_blur_px = 3.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 base = texture(screen_tex, SCREEN_UV);
	vec2 ps = SCREEN_PIXEL_SIZE * max_blur_px * intensity;
	vec4 acc = base;
	acc += texture(screen_tex, SCREEN_UV + vec2(-ps.x, -ps.y));
	acc += texture(screen_tex, SCREEN_UV + vec2( ps.x, -ps.y));
	acc += texture(screen_tex, SCREEN_UV + vec2(-ps.x,  ps.y));
	acc += texture(screen_tex, SCREEN_UV + vec2( ps.x,  ps.y));
	acc += texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0));
	acc += texture(screen_tex, SCREEN_UV + vec2( ps.x, 0.0));
	acc += texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y));
	acc += texture(screen_tex, SCREEN_UV + vec2(0.0,  ps.y));
	acc /= 9.0;
	COLOR = mix(base, acc, intensity);
}
"""
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("intensity", 0.0)
	m.set_shader_parameter("max_blur_px", MAX_BLUR_PX)
	return m
