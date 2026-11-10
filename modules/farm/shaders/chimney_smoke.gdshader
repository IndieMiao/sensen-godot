shader_type spatial;
render_mode unshaded, shadows_disabled;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
varying float opacity;

void vertex() {
	float age = fract(TIME * 0.27 + INSTANCE_CUSTOM.r);
	VERTEX *= (0.55 + age * 1.35);
	VERTEX += vec3(age * 0.20 + sin(age * 7.0) * 0.025, age * 0.70, 0.0);
	opacity = smoothstep(0.0, 0.14, age) * (1.0 - smoothstep(0.60, 1.0, age));
}

void fragment() {
	ALBEDO = vec3(0.98, 0.98, 0.94);
	ALPHA = opacity * 0.72;
	ALBEDO = albedo_out(ALBEDO);
}
