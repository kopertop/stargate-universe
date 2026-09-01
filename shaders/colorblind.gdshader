shader_type canvas_item;

// Colorblind correction shader for Stargate Universe.
// Applies a color-transform matrix to simulate/correct for the three
// most common forms of color vision deficiency:
//   1 = Protanopia (red-blind)
//   2 = Deuteranopia (green-blind)
//   3 = Tritanopia (blue-blind)
// Mode 0 = pass-through (no correction).
//
// The matrices are the standard Viénot/Alpern correction matrices,
// adapted from https://www.color-blindness.com/ and academic sources.
// Each is a 3x3 row-major transform applied in linear RGB.

uniform int mode = 0; // 0=off, 1=protanopia, 2=deuteranopia, 3=tritanopia
uniform float intensity = 1.0; // 0.0 = no effect, 1.0 = full correction

// Godot 4.6+ uses hint_screen_texture instead of the built-in SCREEN_TEXTURE.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Viénot correction matrices (column-major for Godot's mat3)
const mat3 PROTANOPIA = mat3(
	vec3(0.567, 0.558, 0.433),
	vec3(0.433, 0.442, 0.567),
	vec3(0.0,   0.0,   1.0)
);

const mat3 DEUTERANOPIA = mat3(
	vec3(0.625, 0.375, 0.7),
	vec3(0.375, 0.625, 0.3),
	vec3(0.0,   0.0,   1.0)
);

const mat3 TRITANOPIA = mat3(
	vec3(0.95, 0.433, 0.0),
	vec3(0.05, 0.567, 0.475),
	vec3(0.0,  0.0,   0.525)
);

const mat3 IDENTITY = mat3(1.0);

void fragment() {
	vec4 col = texture(screen_texture, SCREEN_UV);
	mat3 m = IDENTITY;
	if (mode == 1) {
		m = PROTANOPIA;
	} else if (mode == 2) {
		m = DEUTERANOPIA;
	} else if (mode == 3) {
		m = TRITANOPIA;
	}
	vec3 corrected = m * col.rgb;
	col.rgb = mix(col.rgb, corrected, intensity);
	COLOR = col;
}