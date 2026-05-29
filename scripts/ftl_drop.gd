class_name FtlDrop
extends CanvasLayer

# One-shot "dropped out of FTL" (or "jumped to FTL") screen effect: a
# full-screen box-blur of the world PLUS a per-frame UV-shake offset that
# reads as a camera jolt. Ramps fast then eases back to clear over ~2 s, and
# fires a directional whoosh. Self-animates and self-frees.
#
# Sits on layer 5 — below HUDLayer (10) — so it shakes / blurs the 3D world
# but leaves the HUD + dialog window (where Brody's line shows) crisp and
# readable. PROCESS_MODE_ALWAYS so it animates even while a dialog has the
# tree paused.
#
# Two directional modes — DROP fires Kenney's gameover3.ogg, JUMP fires the
# sox-reversed version (sounds.ftl-jump.ogg). Drop is the default for the
# scrubber_rush "out of FTL" beat. Set `sound_path` BEFORE `add_child(fx)`
# to use the jump variant, or override entirely.

const DURATION: float = 2.0
const RAMP_FRAC: float = 0.18         # fraction of DURATION ramping the effect in
const MAX_BLUR_PX: float = 10.0       # peak box-blur radius in pixels
const MAX_SHAKE_PX: float = 16.0      # peak UV-shake radius in pixels
const SHAKE_FREQUENCY: float = 38.0   # roughly how many jolts per second at peak

const FTL_DROP_SOUND: String = "res://sounds/ftl-dropout.ogg"
const FTL_JUMP_SOUND: String = "res://sounds/ftl-jump.ogg"

# Override before `add_child` to swap the cue (e.g. jump-in instead of drop-out).
@export var sound_path: String = FTL_DROP_SOUND

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
	Audio.play(sound_path)

func _process(delta: float) -> void:
	_t += delta
	if _rect != null and _rect.material is ShaderMaterial:
		var mat: ShaderMaterial = _rect.material
		var intensity: float = _envelope(_t / DURATION)
		mat.set_shader_parameter("intensity", intensity)
		# Update the UV-shake offset per frame so the world reads as jolting.
		# Two coupled high-frequency sines on the X/Y axes give a non-linear
		# "swirl" that feels more violent than pure random.
		var shake: Vector2 = Vector2(
			sin(_t * SHAKE_FREQUENCY * 1.7),
			cos(_t * SHAKE_FREQUENCY * 2.3)
		) * intensity
		mat.set_shader_parameter("shake", shake)
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
uniform float max_blur_px = 10.0;
uniform float max_shake_px = 16.0;
uniform vec2  shake = vec2(0.0);
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// UV-shake: offset the WHOLE sample point by a screen-relative amount,
	// scaled by max_shake_px. The world appears to jolt; the HUD on a higher
	// CanvasLayer stays still since it doesn't sample through this shader.
	vec2 shake_uv = shake * SCREEN_PIXEL_SIZE * max_shake_px;
	vec2 uv = SCREEN_UV + shake_uv;
	vec4 base = texture(screen_tex, uv);
	// Box blur — nine-tap, radius scaled by max_blur_px * intensity.
	vec2 ps = SCREEN_PIXEL_SIZE * max_blur_px * intensity;
	vec4 acc = base;
	acc += texture(screen_tex, uv + vec2(-ps.x, -ps.y));
	acc += texture(screen_tex, uv + vec2( ps.x, -ps.y));
	acc += texture(screen_tex, uv + vec2(-ps.x,  ps.y));
	acc += texture(screen_tex, uv + vec2( ps.x,  ps.y));
	acc += texture(screen_tex, uv + vec2(-ps.x, 0.0));
	acc += texture(screen_tex, uv + vec2( ps.x, 0.0));
	acc += texture(screen_tex, uv + vec2(0.0, -ps.y));
	acc += texture(screen_tex, uv + vec2(0.0,  ps.y));
	acc /= 9.0;
	COLOR = mix(base, acc, intensity);
}
"""
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("intensity", 0.0)
	m.set_shader_parameter("max_blur_px", MAX_BLUR_PX)
	m.set_shader_parameter("max_shake_px", MAX_SHAKE_PX)
	m.set_shader_parameter("shake", Vector2.ZERO)
	return m
